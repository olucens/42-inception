# Lab 04 — Docker Compose and Init Scripts

> **Goal:** Orchestrate multiple containers together; write init scripts correctly.
> After this you can write docker-compose.yml and init.sh for all 3 project services.
> Time: ~45 minutes

---

## Part A — Docker Compose

### What Compose does

Manually running 3 `docker run` commands with the right networks, volumes, and env vars is error-prone. Docker Compose does it all from one YAML file:

```bash
# Without compose (3 commands, easy to make mistakes):
docker network create inception-network
docker volume create mariadb-data
docker run -d --name mariadb \
  --network inception-network \
  -v mariadb-data:/var/lib/mysql \
  -e MYSQL_DATABASE=wordpress \
  ...

# With compose (one command):
docker compose up -d
```

### docker-compose.yml Structure

```yaml
services:               # ← each service is one container
  servicename:
    build:              # ← how to build the image
      context: path/    # directory with the Dockerfile
      dockerfile: Dockerfile
    image: myimage      # ← name to give the built image
    container_name: mycontainer  # ← container name (also DNS name!)
    env_file: .env      # ← load variables from .env file
    environment:        # ← set individual env vars
      - VAR=${VAR}      # ← from .env
      - OTHER=value     # ← hardcoded
    secrets:            # ← Docker secrets to mount
      - mysecret
    volumes:            # ← mount volumes
      - myvolume:/path/in/container
    networks:           # ← connect to networks
      - mynetwork
    depends_on:         # ← start this service after others
      - mariadb
    restart: on-failure # ← restart policy
    expose:             # ← document internal ports
      - "3306"
    ports:              # ← publish to host
      - "443:443"

secrets:                # ← define secrets (file paths)
  mysecret:
    file: ../secrets/mysecret.txt

volumes:                # ← define named volumes
  myvolume:
    driver: local

networks:               # ← define networks
  mynetwork:
    driver: bridge
```

### .env file

Compose automatically reads `.env` from the same directory as `docker-compose.yml`:

```bash
# srcs/.env
DOMAIN_NAME=akuzmin.42.fr
MYSQL_DATABASE=wordpress
MYSQL_USER=wp_user
```

These variables are available for `${VARIABLE}` substitution in the compose file.
They're also injected into containers that use `env_file: .env`.

**The .env is gitignored** — you create it manually on each machine.

---

## Exercise 1 — Write a simple compose file from scratch

**Task:** Two services — a `web` (nginx serving static content) and a `database` (mariadb). They should be on the same network and the web should be accessible on port 8080.

```bash
mkdir /tmp/compose-test && cd /tmp/compose-test
mkdir -p web/html
echo "<h1>Hello Compose!</h1>" > web/html/index.html
```

Now write `docker-compose.yml` yourself:
- Service `web`: uses `nginx:1.25`, mounts `./web/html:/usr/share/nginx/html`, publishes 8080:80
- Service `db`: uses `mariadb:10.11`, env vars: MYSQL_ROOT_PASSWORD, MYSQL_DATABASE
- Network: `mynet` (custom bridge)
- Both services on `mynet`

<details>
<summary>Solution (try first!)</summary>

```yaml
services:
  web:
    image: nginx:1.25
    volumes:
      - ./web/html:/usr/share/nginx/html
    ports:
      - "8080:80"
    networks:
      - mynet
    depends_on:
      - db

  db:
    image: mariadb:10.11
    environment:
      - MYSQL_ROOT_PASSWORD=root
      - MYSQL_DATABASE=mydb
    networks:
      - mynet

networks:
  mynet:
    driver: bridge
```
</details>

```bash
# Test it
docker compose up -d
curl http://localhost:8080    # should show: Hello Compose!
docker compose exec web ping db   # should resolve 'db' by name
docker compose down
```

---

## Exercise 2 — depends_on and its limits

`depends_on` tells Compose the ORDER to start services. But it only waits for the container to START — NOT for the service inside to be READY.

```bash
# Common problem: WordPress starts before MariaDB is ready
# depends_on: [mariadb] — MariaDB container started, but mysqld not ready yet
# WordPress tries to connect — FAILS
```

**Solutions:**
1. Health checks in Compose (proper but complex)
2. Retry loop in the init script (simpler, common in 42 projects)

```bash
# Init script retry pattern
until mariadb-admin ping -h mariadb --silent 2>/dev/null; do
    echo "Waiting for database..."
    sleep 2
done
echo "Database ready!"
```

---

## Exercise 3 — Docker secrets

**Why secrets instead of env vars?**
```bash
# Env vars:
docker inspect container | grep PASSWORD
# "MYSQL_ROOT_PASSWORD": "mysecretpass"   ← visible to anyone with docker access!

# Secrets:
# The password is NOT in env — it's a file at /run/secrets/db_root_password
# docker inspect doesn't show the content
```

**How secrets work in Compose:**

```yaml
# 1. Define the secret (where the file lives on the host)
secrets:
  db_root_password:
    file: ../secrets/db_root_password.txt

# 2. Attach to a service
services:
  mariadb:
    secrets:
      - db_root_password
```

**Inside the container**, the secret is available as:
```bash
cat /run/secrets/db_root_password    # contains the password
```

**In your init script, read it like this:**
```bash
DB_ROOT_PASSWORD=$(cat /run/secrets/db_root_password)
```

**Test it:**
```bash
mkdir /tmp/secret-test && cd /tmp/secret-test
echo "supersecret" > mypassword.txt

cat > docker-compose.yml << 'EOF'
services:
  test:
    image: alpine:3.19
    command: ["sh", "-c", "echo 'Secret is:' && cat /run/secrets/mypassword && sleep 999"]
    secrets:
      - mypassword

secrets:
  mypassword:
    file: ./mypassword.txt
EOF

docker compose up -d
docker compose logs test   # should print: Secret is: supersecret
docker compose down
```

---

## Part B — Init Scripts

### The pattern all 3 Inception services use

Every service (MariaDB, WordPress, NGINX) follows the same pattern:

```bash
#!/bin/bash
set -e   # exit immediately if any command fails

# === PHASE 1: One-time setup (only runs on first start) ===
# Check if already initialized to make this script idempotent
if [ ! -f "/some/marker/that/setup/happened" ]; then
    do_first_time_setup
fi

# === PHASE 2: Start the actual service as PID 1 ===
exec real_daemon --foreground-flag
```

### Why `set -e`?

Without it, errors are silently ignored:
```bash
# Without set -e:
create_database     # fails silently
start_server        # starts without the database — wrong!

# With set -e:
create_database     # fails
# script stops immediately with an error
# better to fail loudly than silently continue
```

### Why `exec` at the end?

```bash
# WITHOUT exec:
mysqld --user=mysql   # bash runs mysqld as a child process
                       # bash is still PID 1
                       # Docker sends SIGTERM to PID 1 (bash)
                       # bash exits
                       # mysqld gets SIGKILL (no clean shutdown!)

# WITH exec:
exec mysqld --user=mysql   # bash BECOMES mysqld
                            # mysqld is now PID 1
                            # Docker sends SIGTERM to PID 1 (mysqld)
                            # mysqld handles it gracefully, flushes data
```

### The idempotency check

Your init script will run EVERY time the container starts (after restarts, crashes, etc.).
The database setup should only run ONCE — on the very first start.

```bash
# MariaDB: check if data directory already initialized
if [ ! -d "/var/lib/mysql/mysql" ]; then
    # "mysql" dir = MariaDB system database = created during mysql_install_db
    # If it doesn't exist, this is a fresh start
    do_full_initialization
fi
# If it exists, skip initialization and go straight to starting the server
```

---

## Exercise 4 — Write the MariaDB init script yourself

Delete the existing init script and write it from scratch:
```bash
rm Inception/srcs/requirements/mariadb/tools/init.sh
touch Inception/srcs/requirements/mariadb/tools/init.sh
chmod +x Inception/srcs/requirements/mariadb/tools/init.sh
```

Your script must:
1. Read `DB_ROOT_PASSWORD` from `/run/secrets/db_root_password`
2. Read `DB_PASSWORD` from `/run/secrets/db_password`
3. Create `/var/run/mysqld` directory and chown it to mysql
4. Check if `/var/lib/mysql/mysql` exists
5. If NOT (first run):
   - Run `mysql_install_db --user=mysql --datadir=/var/lib/mysql --skip-test-db`
   - Start mysqld temporarily with `--skip-networking` in background
   - Wait until `mysqladmin ping --socket=/var/run/mysqld/mysqld.sock --silent` succeeds
   - Run SQL: CREATE DATABASE, CREATE USER, GRANT, ALTER USER root, FLUSH PRIVILEGES
   - Shutdown the temp instance and wait for it
6. `exec mysqld --user=mysql`

Variables available from env: `MYSQL_DATABASE`, `MYSQL_USER`

Write it line by line without looking at the solution. Then compare with the existing file in the repo.

---

## Exercise 5 — Write the WordPress init script (preview)

WordPress's `setup.sh` follows the same pattern but is more complex:

```bash
#!/bin/bash
set -e

# 1. Wait for MariaDB to be ready (it starts before WordPress but needs time)
until mariadb-admin ping -h mariadb -u root --password="$(cat /run/secrets/db_root_password)" --silent; do
    echo "Waiting for MariaDB..."
    sleep 2
done

# 2. Download WordPress core if not already present
if [ ! -f "/var/www/html/wp-config.php" ]; then
    # wp-cli commands to:
    # - download wordpress
    # - create wp-config.php
    # - run the wordpress installer
    # - create admin user
    # - create regular user
fi

# 3. Start PHP-FPM as PID 1
exec php-fpm8.2 -F
```

You'll write this fully in the next lab when we build WordPress.

---

## Knowledge Check

1. What is Docker Compose for? What problem does it solve vs `docker run`?
2. What does `depends_on` actually guarantee? What does it NOT guarantee?
3. Where does a Docker secret get mounted inside a container?
4. Why is a secret more secure than an environment variable for passwords?
5. What does `set -e` do in a bash script?
6. What happens if you forget `exec` before your final daemon command?
7. What makes an init script "idempotent"? Why does it matter?
8. In docker-compose.yml, what is `env_file` vs `environment`?
