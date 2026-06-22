# Inception — Learning Plan & Roadmap

> This is your road. Each step has a clear goal, concrete deliverable, and list of concepts to internalize.
> The project is split into Core (mandatory) and Bonus. Master Core 100% before touching Bonus.

---

## What the project builds

A production-like mini-infrastructure running entirely in Docker Compose inside a VM:

```
Browser (HTTPS :443)
       |
  [NGINX container]  ← only public entry point, TLS 1.2/1.3
       |
  [WordPress+PHP-FPM container]  ← FastCGI on port 9000
       |
  [MariaDB container]  ← MySQL protocol on port 3306
       |
  [Named volumes on host: /home/login/data/]
```

All containers share one custom Docker network. No ready-made app images allowed — you build every image from Alpine or Debian base yourself.

---

## CORE (Mandatory) Road Map

### Step 0 — Linux & VM Prerequisites
**Goal:** Have a working VM with Docker + Docker Compose installed, understand why we need a VM.

**What to learn:**
- What a hypervisor is (Type 1 vs Type 2)
- VM vs Container — key differences (isolation level, performance, kernel sharing)
- How to install Docker Engine on Debian/Ubuntu (NOT Docker Desktop)
- How to install Docker Compose plugin (`docker compose` v2 syntax)
- Basic Linux: systemd, journalctl, ip addr, ss -tlnp, /etc/hosts

**Deliverable:**
- VM running with Docker daemon active
- `docker info`, `docker compose version` work

**Key commands to know:**
```bash
systemctl status docker
docker info
docker ps
docker images
docker network ls
docker volume ls
```

---

### Step 1 — Dockerfile Fundamentals & Image Anatomy
**Goal:** Understand what a Docker image IS and write correct Dockerfiles.

**What to learn:**
- OCI image spec: images = ordered stack of read-only layers
- Union filesystem (OverlayFS): how layers compose into a container rootfs
- Every `RUN`, `COPY`, `ADD` creates a new layer — minimize layers
- PID 1 problem: why daemons must run as PID 1, what signal handling means
- The difference between CMD vs ENTRYPOINT
- Why `latest` tag is forbidden (reproducibility)
- ENV vs ARG in Dockerfiles
- Multi-stage builds (concept — useful for bonus)
- `.dockerignore` purpose

**Critical rules from subject:**
- No passwords in Dockerfiles
- No `tail -f`, `bash`, `sleep infinity`, `while true` as entrypoint/CMD
- Containers must restart on crash (`restart: on-failure` or `always`)
- Use penultimate stable Alpine or Debian as base (`alpine:3.19`, `debian:bookworm`)

**Deliverable:**
- Can write a minimal Dockerfile that starts a real daemon as PID 1
- Understand `docker build`, `docker run`, `docker exec`, `docker logs`

**Read:**
- `docker/01-internals.md` (this repo) — full internals explanation
- Docker official Dockerfile best practices

---

### Step 2 — MariaDB Container
**Goal:** Build a MariaDB container from scratch that initializes a WordPress database.

**What to learn:**
- How relational databases work at a glance (users, databases, privileges)
- MariaDB installation on Alpine/Debian (package manager differs: `apk` vs `apt`)
- How MariaDB initialization works: `mysql_install_db`, the data directory
- MySQL/MariaDB config file structure (`/etc/mysql/mariadb.conf.d/`)
- How to set root password, create a database, create a user programmatically
- Why MariaDB must NOT run as root inside the container
- How to make MariaDB listen on all interfaces (bind-address = 0.0.0.0) for inter-container access
- Docker volumes: where does /var/lib/mysql live and why it must be on a named volume

**Concepts to internalize:**
- Named volume vs bind mount (named volume = Docker manages the path)
- Data persistence: container can die and restart, data survives on the volume
- The volume maps to `/home/akuzmin/data/mariadb` on host (using custom driver-opts)

**Key files to create:**
```
srcs/requirements/mariadb/
├── Dockerfile
├── conf/
│   └── mariadb.cnf          # custom config
└── tools/
    └── init.sh              # initialization script
```

**Init script must:**
1. Run `mysql_install_db` if data dir is empty
2. Start MariaDB temporarily
3. Create database + user + set passwords (from env vars)
4. Stop MariaDB
5. Then exec mysqld as PID 1

**Environment variables (from .env / secrets):**
- `MYSQL_ROOT_PASSWORD`
- `MYSQL_DATABASE`
- `MYSQL_USER`
- `MYSQL_PASSWORD`

---

### Step 3 — WordPress + PHP-FPM Container
**Goal:** Build a container that runs WordPress via PHP-FPM (FastCGI Process Manager). NO nginx inside.

**What to learn:**
- What PHP-FPM is: a FastCGI server, listens on a socket/port, executes PHP
- FastCGI protocol: nginx talks FastCGI to PHP-FPM, not HTTP
- WordPress: how it uses a database, how wp-config.php works
- WP-CLI: command-line tool to automate WordPress setup (install core, create users, activate themes)
- PHP-FPM pool configuration: `listen = 9000`, `listen.allowed_clients`
- Why PHP-FPM runs as PID 1 (use `php-fpm7.x -F` for foreground mode)
- WordPress user rules: admin username CANNOT be admin/Admin/administrator/Administrator

**WordPress database users required:**
1. Admin user (e.g., `wp_admin`) — administrator role
2. Regular user (e.g., `wp_user`) — subscriber/editor role

**Key files:**
```
srcs/requirements/wordpress/
├── Dockerfile
├── conf/
│   └── www.conf             # PHP-FPM pool config
└── tools/
    └── setup.sh             # WP-CLI setup script
```

**Setup script must:**
1. Wait for MariaDB to be ready (check with mysqladmin ping)
2. Download WordPress core if not already present
3. Generate wp-config.php
4. Run WordPress install (via WP-CLI)
5. Create admin user + regular user
6. Start PHP-FPM as PID 1 (`exec php-fpm -F`)

**The WordPress files must live on a named volume** (shared with NGINX for static files)

---

### Step 4 — NGINX Container with TLS
**Goal:** Build NGINX container that is the sole public entry point, serving HTTPS only.

**What to learn:**
- NGINX as reverse proxy + static file server
- FastCGI proxying: `fastcgi_pass wordpress:9000`
- TLS/SSL fundamentals: certificates, private keys, certificate chains
- TLSv1.2 vs TLSv1.3: how to restrict in NGINX (`ssl_protocols TLSv1.2 TLSv1.3`)
- Self-signed certificate generation with `openssl req -x509`
- NGINX config structure: `http { server { location {} } }`
- How NGINX resolves container names (Docker DNS)
- Port 443 only — no HTTP (port 80) redirect needed (subject says 443 only)

**Key files:**
```
srcs/requirements/nginx/
├── Dockerfile
├── conf/
│   └── nginx.conf           # or default.conf in conf.d/
└── tools/
    └── gen-cert.sh          # generates self-signed cert
```

**NGINX config must:**
- Listen on 443 ssl
- Use ssl_certificate + ssl_certificate_key
- `ssl_protocols TLSv1.2 TLSv1.3`
- Pass PHP requests to `fastcgi_pass wordpress:9000`
- Serve WordPress static files from the shared volume
- Set correct `fastcgi_param` (especially SCRIPT_FILENAME)

**Certificate stored in the image** (generated at build or startup, never committed)

---

### Step 5 — Docker Compose + Network + Volumes
**Goal:** Wire everything together with docker-compose.yml.

**What to learn:**
- `docker-compose.yml` v3 syntax (actually Compose Specification now)
- `services`, `build`, `image`, `container_name`, `environment`, `env_file`
- `volumes` top-level definition with `driver_opts` to set host path
- `networks` top-level definition (custom bridge, NOT host network)
- `depends_on` (and its limitations — only waits for container start, not service ready)
- `restart: on-failure` vs `restart: always`
- How Docker DNS works: container_name is resolvable by other containers
- `secrets` in Docker Compose

**Volume driver configuration to set host path:**
```yaml
volumes:
  wordpress-data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/akuzmin/data/wordpress
  mariadb-data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/akuzmin/data/mariadb
```

**Network:**
```yaml
networks:
  inception-network:
    driver: bridge
```

**Makefile targets:**
```makefile
all:      # docker compose up --build -d
clean:    # docker compose down
fclean:   # docker compose down -v --rmi all, remove data dirs
re:       # fclean + all
```

---

### Step 6 — Security: Secrets, Environment Variables, .env
**Goal:** Zero credentials in code, repo, or Dockerfiles.

**What to learn:**
- `.env` file: loaded by Docker Compose automatically, provides variables to compose file
- `env_file` directive in compose: injects variables into container environment
- Docker secrets: files mounted at `/run/secrets/<name>` inside container
- Why env vars alone are insufficient for true security (visible in `docker inspect`)
- `.gitignore` must include: `.env`, `secrets/`
- The secrets directory structure:
  ```
  secrets/
  ├── credentials.txt       # WordPress admin credentials
  ├── db_password.txt       # MariaDB user password
  └── db_root_password.txt  # MariaDB root password
  ```

**What goes in .env (non-secret config):**
```env
DOMAIN_NAME=akuzmin.42.fr
MYSQL_DATABASE=wordpress
MYSQL_USER=wp_user
```

**What goes in secrets (never in .env or Dockerfiles):**
- Passwords
- API keys

---

### Step 7 — Domain Name Setup
**Goal:** `akuzmin.42.fr` resolves to your VM's IP on the host machine.

**What to do:**
- Edit `/etc/hosts` on the host (not in VM): `<VM_IP>  akuzmin.42.fr`
- In the VM itself also add to `/etc/hosts`

---

### Step 8 — Documentation
**Goal:** Meet all mandatory documentation requirements.

**Files to create at repo root:**
1. `README.md` — with specific sections required by subject:
   - Italicized first line: *This project has been created as part of the 42 curriculum by akuzmin.*
   - Description, Instructions, Resources
   - Project description: VM vs Docker, Secrets vs Env Vars, Docker Network vs Host Network, Docker Volumes vs Bind Mounts
2. `USER_DOC.md` — how an end user starts/stops/accesses the stack
3. `DEV_DOC.md` — how a developer sets up from scratch

---

## BONUS Road Map

> Only start this after core is working perfectly.

### Bonus Step 1 — Redis Cache
**Goal:** Redis container connected to WordPress as object cache.

**What to learn:**
- Redis: in-memory key-value store, used for caching
- Redis persistence modes: RDB snapshots, AOF log
- WordPress Redis plugin: `redis-cache` (by Till Krüss)
- PHP Redis extension (`phpredis`)
- Redis configuration: `requirepass`, `bind`, `maxmemory`, `maxmemory-policy`
- Redis container needs its own named volume for persistence

**Setup:**
- Redis listens on port 6379 (internal network only)
- WordPress container needs `WP_REDIS_HOST`, `WP_REDIS_PORT` in wp-config.php
- Activate Redis Cache plugin via WP-CLI

---

### Bonus Step 2 — FTP Server
**Goal:** FTP container that points to the WordPress files volume.

**What to learn:**
- FTP protocol: control port 21, data ports (passive mode range)
- vsftpd or Pure-FTPd as server
- Passive mode and why it's needed behind NAT
- FTP is unencrypted — acceptable here since it's internal
- The FTP server must share the WordPress files volume (read/write access)

**Setup:**
- vsftpd configuration: `pasv_enable`, `pasv_min_port`, `pasv_max_port`
- Create an FTP user that maps to the WordPress volume

---

### Bonus Step 3 — Static Website
**Goal:** A static website container (HTML/CSS/JS, no PHP).

**What to learn:**
- Simple HTTP server options: nginx (basic config), Caddy, Python http.server (dev only)
- Serve static files from a different port (e.g., 8080) or subdomain
- Why PHP is excluded: already handled by WordPress stack

**Ideas:**
- Personal portfolio/resume site
- A showcase of the project
- Written in pure HTML/CSS or with a static site generator (Hugo, etc.)

---

### Bonus Step 4 — Adminer
**Goal:** Adminer container for database GUI management.

**What to learn:**
- Adminer: single PHP file database management tool (like phpMyAdmin but lighter)
- It needs PHP installed or can run via PHP-FPM
- Connects to MariaDB on the internal network
- Served via NGINX or its own web server on a different port

---

### Bonus Step 5 — Custom Service
**Goal:** Add one useful service of your choice (must justify at defense).

**Good ideas (justify well):**
- **Portainer** — Docker container management UI (ironic but useful for demos)
- **cAdvisor** — container resource monitoring
- **Netdata** — real-time system monitoring
- **Fail2ban** — intrusion prevention (shows security awareness)
- **Watchtower** — automatic container updates (controversial — discuss trade-offs)

**What to prepare for defense:**
- What problem does this service solve?
- Why this over alternatives?
- How is it configured?

---

## Concepts Mastery Checklist

### Docker Core
- [ ] Image layers and OverlayFS
- [ ] Dockerfile instructions and layer caching
- [ ] Container lifecycle (created → running → stopped → removed)
- [ ] PID 1 and signal handling
- [ ] Docker networking (bridge, host, none, custom)
- [ ] Named volumes vs bind mounts
- [ ] Docker secrets
- [ ] Multi-container orchestration with Compose
- [ ] Environment variables in containers

### Linux System Administration
- [ ] Process management and systemd
- [ ] Network interfaces and routing
- [ ] File permissions and ownership
- [ ] SSL/TLS certificate structure
- [ ] Package management (apk/apt)
- [ ] Shell scripting for init scripts

### Services
- [ ] NGINX: reverse proxy, FastCGI, SSL termination
- [ ] PHP-FPM: process manager, pools, FastCGI protocol
- [ ] MariaDB: initialization, users, grants
- [ ] WordPress: wp-config.php, WP-CLI, user roles

### Security
- [ ] Never store credentials in images/repo
- [ ] Principle of least privilege (non-root users in containers)
- [ ] TLS: certificates, keys, protocol versions
- [ ] Environment variable security vs Docker secrets
- [ ] .gitignore for sensitive files

---

## File Structure (final project)

```
42-inception/
├── Makefile
├── README.md
├── USER_DOC.md
├── DEV_DOC.md
├── .gitignore
├── secrets/                          # ignored by git
│   ├── credentials.txt
│   ├── db_password.txt
│   └── db_root_password.txt
└── srcs/
    ├── .env                          # ignored by git
    ├── docker-compose.yml
    └── requirements/
        ├── mariadb/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/
        │   │   └── mariadb.cnf
        │   └── tools/
        │       └── init.sh
        ├── nginx/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/
        │   │   └── nginx.conf
        │   └── tools/
        │       └── gen-cert.sh
        ├── wordpress/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/
        │   │   └── www.conf
        │   └── tools/
        │       └── setup.sh
        └── bonus/
            ├── redis/
            ├── ftp/
            ├── static/
            ├── adminer/
            └── custom/
```

---

## Build Order (important — dependencies matter)

1. MariaDB must be READY before WordPress starts
2. WordPress must have its files before NGINX can serve them
3. NGINX is last in the dependency chain

```
MariaDB ← WordPress ← NGINX ← User
```

In Compose, use `depends_on` + health checks or init script retry loops to handle readiness.
