# Dockerfile Best Practices & Image Building

---

## 1. Dockerfile Instruction Reference

### FROM — Choose the right base

```dockerfile
# CORRECT: pin to specific penultimate stable version
FROM debian:bookworm-slim    # Debian 12, slim variant (no extras)
FROM alpine:3.19             # Alpine (smaller, musl libc)

# WRONG: latest tag is forbidden in Inception
FROM debian:latest           # ❌ FORBIDDEN
FROM nginx:latest            # ❌ FORBIDDEN (also ready-made app image)
```

**Alpine vs Debian trade-offs:**
- Alpine: ~5MB base, uses `apk`, uses musl libc (some software incompatible)
- Debian: ~25MB slim, uses `apt`, uses glibc (universal compatibility)
- For Inception: either works, pick one and be consistent per service

### RUN — Execute commands during build

```dockerfile
# CORRECT: chain commands, clean up in same layer
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        nginx \
        openssl && \
    rm -rf /var/lib/apt/lists/*

# WRONG: separate RUN = separate layer, cache not shared
RUN apt-get update
RUN apt-get install -y nginx    # ❌ apt-get update cache already stale
```

**Alpine equivalent:**
```dockerfile
RUN apk add --no-cache nginx openssl
# --no-cache: don't cache the index locally (smaller image)
```

### COPY vs ADD

```dockerfile
# COPY: simple, predictable — use this
COPY conf/nginx.conf /etc/nginx/nginx.conf
COPY tools/entrypoint.sh /entrypoint.sh

# ADD: has extra powers (auto-extract archives, URLs) — avoid unless needed
ADD https://example.com/file.tar.gz /tmp/   # downloads from URL
ADD archive.tar.gz /opt/                    # auto-extracts
```

### ENV vs ARG

```dockerfile
# ARG: only available during BUILD
ARG PHP_VERSION=8.2
RUN apt-get install -y php${PHP_VERSION}-fpm

# ENV: available during BUILD and at RUNTIME (in the container)
ENV PHP_VERSION=8.2
ENV WP_HOME=/var/www/html

# NEVER put secrets in ENV or ARG — they're visible in docker inspect and docker history
```

### WORKDIR — Set working directory

```dockerfile
WORKDIR /var/www/html
# Equivalent to: mkdir -p /var/www/html && cd /var/www/html
# All subsequent COPY, RUN, CMD use this as cwd
```

### USER — Run as non-root

```dockerfile
# Create a user for the service
RUN adduser --disabled-password --no-create-home www-data

# Switch to it
USER www-data

# The process runs as this user, not root
CMD ["nginx", "-g", "daemon off;"]
```

### EXPOSE — Document ports (metadata only)

```dockerfile
EXPOSE 443     # nginx
EXPOSE 9000    # php-fpm
EXPOSE 3306    # mariadb

# EXPOSE does NOT publish ports — it's documentation
# Ports are published via docker-compose.yml `ports:`
```

### CMD vs ENTRYPOINT

```dockerfile
# Pattern 1: ENTRYPOINT as fixed command, CMD as default args
ENTRYPOINT ["nginx"]
CMD ["-g", "daemon off;"]
# docker run myimage           → nginx -g "daemon off;"
# docker run myimage -t        → nginx -t

# Pattern 2: ENTRYPOINT as init script, CMD as the main process
ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
# entrypoint.sh receives "nginx" "-g" "daemon off;" as "$@"
# Script should end with: exec "$@"

# Pattern 3: Just CMD (most common for simple cases)
CMD ["nginx", "-g", "daemon off;"]
```

---

## 2. The Init Script Pattern

For MariaDB and WordPress, you need an init script that sets up the service before starting it.

```bash
#!/bin/sh
# tools/init.sh — template for any service init script

set -e   # exit on error

# Step 1: do setup (runs once)
if [ ! -f /var/lib/mysql/ibdata1 ]; then
    echo "Initializing MariaDB..."
    mysql_install_db --user=mysql --datadir=/var/lib/mysql > /dev/null

    # Start temporarily for setup
    mysqld --user=mysql &
    MYSQL_PID=$!

    # Wait for MySQL to be ready
    until mysqladmin ping --silent; do
        echo "Waiting for MariaDB..."
        sleep 1
    done

    # Run initialization SQL
    mysql -u root << EOF
CREATE DATABASE IF NOT EXISTS ${MYSQL_DATABASE};
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO '${MYSQL_USER}'@'%';
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
EOF

    # Stop temporary instance
    mysqladmin -u root -p${MYSQL_ROOT_PASSWORD} shutdown
    wait $MYSQL_PID
fi

# Step 2: start the actual service as PID 1
exec mysqld --user=mysql
```

**Key points:**
- `set -e`: script exits immediately on any error
- Check if already initialized (idempotent)
- Start service temporarily → setup → stop → `exec` real service
- `exec` replaces the shell process — mysqld becomes PID 1
- Without `exec`: shell is PID 1, mysqld is a child — signals don't reach mysqld correctly

---

## 3. Layer Optimization

```dockerfile
# OPTIMAL ORDER: least-changed → most-changed

FROM debian:bookworm-slim                    # Layer 1: changes rarely
RUN apt-get update && apt-get install -y ... # Layer 2: changes when deps change
COPY conf/ /etc/nginx/                       # Layer 3: changes when config changes
COPY tools/ /                                # Layer 4: changes when scripts change
RUN chmod +x /entrypoint.sh                  # Layer 5: always same after copy
EXPOSE 443
ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
```

**Why order matters for caching:**
If Layer 3 (your config) changes, Docker rebuilds Layer 3, 4, and 5.
But Layer 1 and 2 (base + packages) stay cached.
If you put `COPY` before `RUN apt-get`, then ANY file change rebuilds the package installation — very slow.

---

## 4. .dockerignore

```
# .dockerignore — like .gitignore but for build context
.git/
.env
secrets/
*.md
node_modules/
__pycache__/
*.log
```

Without `.dockerignore`, `docker build .` sends everything including `.git` (potentially huge) to the daemon.

---

## 5. Security Rules (Inception-specific)

```dockerfile
# ❌ NEVER do this
ENV DB_PASSWORD=mysecretpassword    # visible in docker inspect, docker history

# ❌ NEVER do this
RUN echo "password123" > /etc/mysql/root.passwd

# ✅ Read secrets from environment at runtime
# In your init script:
MYSQL_ROOT_PASSWORD=$(cat /run/secrets/db_root_password)
# or from environment variable passed at runtime
```

```dockerfile
# ❌ FORBIDDEN tags
FROM mariadb:latest    # forbidden: ready-made app image AND latest tag

# ✅ Correct
FROM debian:bookworm-slim
RUN apt-get install -y mariadb-server
```

---

## 6. Complete Dockerfile Examples

### MariaDB Dockerfile (Alpine)

```dockerfile
FROM alpine:3.19

RUN apk add --no-cache \
    mariadb \
    mariadb-client \
    && rm -rf /var/cache/apk/*

# Copy custom config
COPY conf/mariadb.cnf /etc/my.cnf.d/custom.cnf

# Copy init script
COPY tools/init.sh /init.sh
RUN chmod +x /init.sh

# MariaDB data directory (will be a named volume)
VOLUME /var/lib/mysql

EXPOSE 3306

ENTRYPOINT ["/init.sh"]
```

### NGINX Dockerfile (Debian)

```dockerfile
FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        nginx \
        openssl && \
    rm -rf /var/lib/apt/lists/*

# Generate self-signed certificate
RUN mkdir -p /etc/nginx/ssl && \
    openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/nginx.key \
        -out /etc/nginx/ssl/nginx.crt \
        -subj "/C=FR/ST=IDF/L=Paris/O=42/CN=${DOMAIN_NAME:-localhost}"

COPY conf/nginx.conf /etc/nginx/nginx.conf

EXPOSE 443

CMD ["nginx", "-g", "daemon off;"]
```

---

## 7. Debugging Builds

```bash
# Build with verbose output
docker build --progress=plain -t myimage .

# See all layers and their sizes
docker history myimage

# Dive into an image (install: https://github.com/wagoodman/dive)
dive myimage

# Run a failed build up to a specific step
docker build --target <stage> .    # for multi-stage builds

# Enter a container to debug
docker run -it --entrypoint /bin/sh myimage

# See what changed in a container layer
docker diff <container>
```

---

## 8. Multi-Stage Builds (Bonus Concept)

Not required for basic Inception but useful for bonus services:

```dockerfile
# Stage 1: Build
FROM golang:1.21 AS builder
WORKDIR /app
COPY . .
RUN go build -o myapp .

# Stage 2: Runtime (tiny image, no build tools)
FROM alpine:3.19
COPY --from=builder /app/myapp /myapp
CMD ["/myapp"]
```

Result: final image has only the compiled binary, not the Go compiler or source code.
