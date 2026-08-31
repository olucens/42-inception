# DEV_DOC — Inception, developer documentation

How to set this project up from nothing, how it is built, and how to work on it.
Operating an already-running stack is covered in [USER_DOC.md](USER_DOC.md).

---

## 1. Setting up from scratch

### Prerequisites

| Requirement | Why |
|---|---|
| A Linux host or VM | containers share the host kernel; `/home/<login>/data` and privileged port 443 are assumed |
| Docker Engine 20.10+ | the runtime |
| Docker Compose **v2** (`docker compose`, not `docker-compose`) | the compose file uses v2 syntax and no `version:` key |
| `make`, `git`, `openssl` | build driver, clone, secret generation |
| Your user in the `docker` group | otherwise every command needs `sudo` |

```bash
docker --version && docker compose version && make --version
```

### Layout

```
.
├── Makefile                 drives compose; the only entry point
├── README.md  USER_DOC.md  DEV_DOC.md
├── secrets/                 GIT-IGNORED — passwords, one per file
│   ├── db_root_password.txt
│   ├── db_password.txt
│   └── credentials.txt
└── srcs/
    ├── .env                 GIT-IGNORED — non-secret configuration
    ├── .env.example         committed template
    ├── docker-compose.yml
    └── requirements/
        ├── mariadb/   Dockerfile · conf/mariadb.cnf        · tools/init.sh
        ├── wordpress/ Dockerfile · conf/www.conf           · tools/setup.sh
        └── nginx/     Dockerfile · conf/nginx.conf.template · tools/entrypoint.sh
```

Every service follows the same three-part shape — `Dockerfile`, `conf/`,
`tools/` — so a new service is always added the same way.

### Configuration files

```bash
cp srcs/.env.example srcs/.env
```

`srcs/.env` holds **only non-confidential** values, and is read by all three
services through `env_file:`.

| Variable | Meaning |
|---|---|
| `DOMAIN_NAME` | must be `<login>.42.fr`; used for `server_name` and the certificate CN |
| `MYSQL_HOST` | the compose **service name** `mariadb`, resolved by Docker's DNS |
| `MYSQL_DATABASE`, `MYSQL_USER` | database and application user created on first run |
| `WP_TITLE`, `WP_URL` | site title, and the canonical `https://` URL pinned into `wp-config.php` |
| `WP_ADMIN_USER`, `WP_ADMIN_EMAIL` | the administrator. **The name must not contain `admin`/`administrator`** — `tools/setup.sh` refuses to start otherwise |
| `WP_USER`, `WP_USER_EMAIL`, `WP_USER_ROLE` | the second, non-administrator account the subject requires |

### Secrets

Three files, never committed, created once per machine:

```bash
mkdir -p secrets
openssl rand -base64 24 > secrets/db_root_password.txt
openssl rand -base64 24 > secrets/db_password.txt
printf 'WP_ADMIN_PASSWORD=%s\nWP_USER_PASSWORD=%s\n' \
    "$(openssl rand -base64 18)" "$(openssl rand -base64 18)" > secrets/credentials.txt
chmod 600 secrets/*.txt
```

`credentials.txt` is parsed as `KEY=value` lines — the format matters:

```
WP_ADMIN_PASSWORD=...
WP_USER_PASSWORD=...
```

`tools/setup.sh` reads it with `grep`/`cut`, deliberately **not** `source`:
sourcing would execute the file as shell code, so a `` ` `` or `$(…)` inside a
password would run as a command.

Compose exposes each file read-only at `/run/secrets/<name>` — verify with
`docker exec wordpress grep secrets /proc/mounts`. Note that Compose implements
secrets as a read-only **bind mount** of the host file; the in-memory tmpfs
behaviour belongs to Swarm. Either way they stay out of `docker inspect`,
`docker compose config`, `/proc/<pid>/environ` and image layers.

`.gitignore` excludes `secrets/` and `srcs/.env`. Confirm before every push:

```bash
git status --ignored --short | grep -E 'secrets|\.env$'
git ls-files | grep -E 'secrets/|srcs/\.env$'   # must print NOTHING
```

### Domain

```bash
echo "127.0.0.1 akuzmin.42.fr" | sudo tee -a /etc/hosts
```

---

## 2. Building and launching

```bash
make
```

`make` runs `check` → `setup` → `docker compose up --build -d`:

- **check** — fails early with a readable message if `.env` or a secret is
  missing, instead of a cryptic Compose error.
- **setup** — `mkdir -p /home/akuzmin/data/{mariadb,wordpress}`. Required: the
  volumes use `type: none, o: bind`, which binds an *existing* directory. Docker
  will not create it, and `up` fails with "no such file or directory" without it.
- **up --build -d** — build images, create network and volumes, start containers.

| Target | Effect |
|---|---|
| `make` / `all` | check, setup, build, start |
| `make build` | build images only |
| `make up` / `down` | start / stop+remove containers **keeping volumes** |
| `make clean` | `down` plus remove the locally built images |
| `make fclean` | `clean` plus `down -v` and `rm -rf /home/akuzmin/data/*` |
| `make re` | `fclean` then `all` — the real from-scratch test |
| `make logs` / `ps` | follow logs / show state |
| `make tls-test` | assert TLS 1.0/1.1 refused, 1.2/1.3 accepted |

### What happens on first start

```
mariadb    volume empty -> mysql_install_db, create DB + user + grants,
                           write .inception-initialised, exec mysqld
wordpress  wait for an authenticated query to succeed (up to 120s),
           wp core download / config create / core install / user create,
           exec php-fpm --nodaemonize
nginx      envsubst the config, generate a self-signed cert,
           nginx -t, exec nginx -g "daemon off;"
```

Each entrypoint ends in `exec`, so the daemon itself is PID 1 — the process
Docker signals on stop. Check it:

```bash
for c in mariadb wordpress nginx; do docker exec $c cat /proc/1/comm; done
# mysqld / php-fpm8.2 / nginx
```

---

## 3. Managing containers and volumes

```bash
docker compose -f srcs/docker-compose.yml ps
docker logs -f wordpress
docker exec -it mariadb bash                    # shell inside a container
docker compose -f srcs/docker-compose.yml restart nginx
docker compose -f srcs/docker-compose.yml up -d --build --no-deps wordpress   # rebuild one service
```

Useful service-specific commands:

```bash
# MariaDB — note --protocol=socket, see §5
docker exec -it mariadb mariadb --protocol=socket -u root \
    -p"$(cat secrets/db_root_password.txt)"

# WordPress
docker exec wordpress wp --path=/var/www/html --allow-root user list
docker exec wordpress wp --path=/var/www/html --allow-root plugin list

# NGINX
docker exec nginx nginx -t                      # validate config
docker exec nginx cat /etc/nginx/nginx.conf     # the RENDERED config
```

Network and volumes:

```bash
docker network inspect inception-network        # members, subnet, IPs
docker exec nginx getent hosts wordpress        # embedded DNS at 127.0.0.11
docker volume ls
docker volume inspect srcs_wordpress-data       # Mountpoint + driver_opts
```

---

## 4. Where the data is, and how it persists

Two named volumes, both backed by a directory under `/home/akuzmin/data`:

| Volume | Mounted at | Host path | Holds |
|---|---|---|---|
| `mariadb-data` | `mariadb:/var/lib/mysql` | `/home/akuzmin/data/mariadb` | tables, users, InnoDB files |
| `wordpress-data` | `wordpress:/var/www/html` (rw)<br>`nginx:/var/www/html` (**ro**) | `/home/akuzmin/data/wordpress` | core files, `wp-config.php`, themes, uploads |

They are *named volumes*, not bind mounts. The subject requires named volumes
**and** requires the data to sit in `/home/<login>/data`; the `local` driver with
`type: none, o: bind, device: …` is what satisfies both. The volume is a real
Docker object (`docker volume ls`, `docker volume rm`, removed by `down -v`)
whose backing store is a chosen directory.

### Persistence rules

| Action | Containers | Images | Volume data |
|---|---|---|---|
| `docker compose restart` | restarted | kept | **kept** |
| `make down` | removed | kept | **kept** |
| `make clean` | removed | removed | **kept** |
| `make fclean` | removed | removed | **DESTROYED** |

The entrypoints are idempotent, which is what makes restarts safe:

- MariaDB writes `/var/lib/mysql/.inception-initialised` only after the *last*
  SQL statement succeeds, so a run that fails halfway is retried rather than
  mistaken for a finished one.
- WordPress checks for `wp-config.php`, which exists only after a successful
  install.

Verify persistence honestly — create data, cycle, confirm:

```bash
docker exec wordpress wp --path=/var/www/html --allow-root \
    post create --post_title="probe" --post_status=publish
make down && make && sleep 30
docker exec wordpress wp --path=/var/www/html --allow-root post list
```

### Backup / restore

```bash
docker exec mariadb mariadb-dump --protocol=socket -u root \
    -p"$(cat secrets/db_root_password.txt)" wordpress > backup.sql
tar czf wp-files.tar.gz -C /home/akuzmin/data/wordpress .
```

---

## 5. Notes for whoever works on this next

Three defects were hit while building this, all silent enough to be worth
writing down.

**MariaDB's Debian package pre-seeds the data directory.** `apt-get install
mariadb-server` runs `mysql_install_db` at *build* time, leaving ~113 MB at
`/var/lib/mysql` inside the image. Docker seeds an empty named volume from the
image, so the "empty" volume came up already containing `mysql/` — first-run
setup was skipped and the WordPress user was never created. The Dockerfile now
empties that directory, so a fresh volume is genuinely empty.

**`MYSQL_HOST` hijacks the local MariaDB client.** `.env` sets
`MYSQL_HOST=mariadb` for WordPress, and `env_file:` hands it to *every* service.
The client libraries read `MYSQL_HOST` as their default host, which forces TCP —
and `--protocol=socket` does **not** override it. Against the `--skip-networking`
temporary instance this fails with `ERROR 2002 … Can't connect to server on
'mariadb' (115)`. `init.sh` therefore `unset MYSQL_HOST` before any local client
call.

**`http2 on;` needs nginx ≥ 1.25.1.** Bookworm ships 1.22, where HTTP/2 is a
`listen` parameter; the standalone directive makes nginx refuse to start with
`unknown directive "http2"`. The config uses `listen 443 ssl http2;`.

### Conventions to keep

- Pin every base image and every downloaded tool to an explicit version.
- One `RUN` per logical step, with cleanup **inside the same layer** — a file
  deleted in a later layer still ships in the earlier one.
- Entrypoints: read secrets, do guarded setup, then `exec` the daemon. Never
  leave a shell as PID 1, and never use `tail -f`, `sleep infinity` or
  `while true` to keep a container alive — a foreground daemon already does.
- Readiness waits must be *bounded* and must test a real authenticated query;
  `depends_on` only orders container start, not service readiness.
- Secrets are files, `.env` is configuration. Nothing confidential in a
  Dockerfile, in `ENV`, or on a command line visible in `ps`.

### Adding a service

1. `srcs/requirements/<name>/` with `Dockerfile`, `conf/`, `tools/`.
2. Add it to `docker-compose.yml`: `image: <name>:inception` (name matches the
   service, tag is never `latest`), `env_file`, `networks: [inception-network]`,
   `restart: on-failure`, and `expose:` rather than `ports:` unless it genuinely
   must be reachable from the host.
3. Give it its own volume if it needs persistence — never share another
   service's data volume read-write.

### Before pushing

```bash
git ls-files | grep -E 'secrets/|srcs/\.env$'   # must be empty
make re                                          # must build and run from zero
make tls-test                                    # 1.0/1.1 refused, 1.2/1.3 accepted
```
