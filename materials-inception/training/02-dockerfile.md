# Lab 02 — Write Your Own Dockerfiles

> **Goal:** Understand every Dockerfile instruction and write one from scratch.
> You should be able to write the project's Dockerfiles yourself after this.
> Time: ~45 minutes

---

## What is a Dockerfile?

A Dockerfile is a recipe that tells Docker how to build an image.
An **image** is a frozen snapshot of a filesystem — like a template.
A **container** is a running instance of an image — like a process.

```
Dockerfile → (docker build) → Image → (docker run) → Container
```

---

## Image = Stack of Layers

Every instruction that modifies the filesystem creates a new layer:

```
FROM debian:bookworm-slim        ← Layer 1 (base OS, ~75MB)
RUN apt-get install -y nginx     ← Layer 2 (+nginx, ~5MB)
COPY nginx.conf /etc/nginx/      ← Layer 3 (+config, tiny)
CMD ["nginx", "-g", "daemon off;"] ← no layer, just metadata
```

Docker **caches** each layer. If you change Layer 3, it rebuilds 3 and everything after.
Layer 1 and 2 stay cached. This is why order matters.

**See layers yourself:**
```bash
docker pull nginx:1.25   # just to have something to inspect
docker history nginx:1.25
```

---

## Every Instruction Explained

### FROM — Choose your base

```dockerfile
FROM debian:bookworm-slim
```

**What it does:** Sets the starting filesystem for your image.
**Rules:**
- Must be first instruction
- Use a specific tag — NEVER `latest` (not reproducible, forbidden in Inception)
- `slim` variants have less bloat (no man pages, locale data)
- For Inception: `debian:bookworm-slim` (Debian 12, penultimate stable)

### RUN — Execute during build

```dockerfile
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        mariadb-server \
    && rm -rf /var/lib/apt/lists/*
```

**What it does:** Runs a command and saves the result as a new layer.
**Best practices:**
- Chain commands with `&&` (one `RUN` = one layer)
- Clean up package caches in the SAME `RUN` (different RUN = different layer, cleanup won't shrink)
- `--no-install-recommends` prevents installing optional packages

**Why clean `/var/lib/apt/lists/*`?**
```bash
# After apt-get update, this cache is ~40MB
# If you don't clean it, every image carries 40MB of stale package lists
# Clean it in the same RUN so the cleanup is in the same layer
```

### COPY — Add files from your machine into the image

```dockerfile
COPY conf/nginx.conf /etc/nginx/nginx.conf
COPY tools/init.sh /usr/local/bin/init.sh
COPY tools/ /usr/local/bin/         # copy whole directory
```

**What it does:** Copies files from the build context (your local dir) into the image.
**Note:** The path is relative to where you run `docker build`.

### ADD — Like COPY but with superpowers (avoid unless needed)

```dockerfile
ADD archive.tar.gz /opt/    # auto-extracts archives
ADD https://url/file /tmp/  # downloads from URL
```

**Rule:** Use `COPY` by default. Use `ADD` only when you need auto-extract.

### ENV — Set environment variables

```dockerfile
ENV WP_VERSION=6.4
ENV DATA_DIR=/var/www/html
```

**What it does:** Sets variables available both during build AND at runtime in the container.
**Never put passwords here** — they're visible in `docker inspect` and `docker history`.

### ARG — Build-time only variables

```dockerfile
ARG PHP_VERSION=8.2
RUN apt-get install -y php${PHP_VERSION}-fpm
```

**What it does:** Variable only available during `docker build`, not at runtime.
**Pass a value:** `docker build --build-arg PHP_VERSION=8.1 .`

### WORKDIR — Set the working directory

```dockerfile
WORKDIR /var/www/html
```

**What it does:** All subsequent `RUN`, `COPY`, `CMD` commands use this as their cwd.
Creates the directory if it doesn't exist.
**Prefer this over `RUN cd /path`** (which only affects that single RUN step).

### EXPOSE — Document which ports the container uses

```dockerfile
EXPOSE 443    # NGINX
EXPOSE 9000   # PHP-FPM
EXPOSE 3306   # MariaDB
```

**What it does:** Documentation only. Does NOT actually open ports.
Ports are actually opened by `-p` in `docker run` or `ports:` in docker-compose.yml.

### USER — Switch to a non-root user

```dockerfile
RUN useradd -r -s /bin/false www-data
USER www-data
CMD ["nginx"]    # nginx runs as www-data, not root
```

**What it does:** All subsequent instructions and the final process run as this user.

### CMD — Default command to run

```dockerfile
CMD ["nginx", "-g", "daemon off;"]
CMD ["mysqld", "--user=mysql"]
```

**What it does:** The command that runs when you `docker run` without specifying a command.
**Always use exec form** (JSON array) — it makes the process PID 1 directly.

```dockerfile
# WRONG (shell form): /bin/sh -c "nginx ..." runs, nginx is child
CMD nginx -g "daemon off;"

# CORRECT (exec form): nginx IS PID 1
CMD ["nginx", "-g", "daemon off;"]
```

### ENTRYPOINT — Non-overridable command

```dockerfile
ENTRYPOINT ["/init.sh"]
CMD ["mysqld", "--user=mysql"]
```

**Relationship:**
- `CMD` arguments are APPENDED to `ENTRYPOINT`
- `docker run myimage` → runs `/init.sh mysqld --user=mysql`
- `docker run myimage bash` → runs `/init.sh bash` (CMD replaced, ENTRYPOINT stays)

**Pattern for init scripts:**
```dockerfile
ENTRYPOINT ["/init.sh"]   # init script runs first
# init.sh does setup, then ends with:
# exec "$@"               # runs CMD as PID 1
```

---

## Exercise 1 — Write a Dockerfile from memory

Create a file called `Dockerfile.test` and write a Dockerfile that:
1. Starts from `debian:bookworm-slim`
2. Installs `curl` and `vim`
3. Creates a directory `/app`
4. Copies a file `hello.txt` from your machine into `/app/hello.txt`
5. Sets working directory to `/app`
6. Runs `cat /app/hello.txt` on start

**Do it yourself first, then check:**
```bash
echo "Hello from inside the container!" > hello.txt
# write your Dockerfile.test here...
docker build -t mytest -f Dockerfile.test .
docker run --rm mytest
# should print: Hello from inside the container!
```

<details>
<summary>Solution (try yourself first!)</summary>

```dockerfile
FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl vim && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /app

COPY hello.txt /app/hello.txt

WORKDIR /app

CMD ["cat", "/app/hello.txt"]
```
</details>

---

## Exercise 2 — See layer caching

```bash
# Build your Dockerfile twice and observe caching
docker build -t mytest -f Dockerfile.test .
# All steps run

docker build -t mytest -f Dockerfile.test .
# All steps say "CACHED" — nothing ran

# Now change hello.txt
echo "Changed!" > hello.txt
docker build -t mytest -f Dockerfile.test .
# Steps 1-4 still CACHED
# Step 5 (COPY) runs again — file changed
# Step 6 (CMD) also "runs" (it's just metadata)
```

**Key insight:** If you put `COPY` before `RUN apt-get install`, then changing ANY file forces a full package reinstall. Always install packages FIRST, then copy your config files.

---

## Exercise 3 — The layer order problem

```dockerfile
# BAD ORDER
FROM debian:bookworm-slim
COPY conf/ /etc/myapp/     # ← changes often
RUN apt-get update && apt-get install -y myapp  # ← slow, but must rerun every time conf changes!

# GOOD ORDER
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y myapp  # ← slow, but cached
COPY conf/ /etc/myapp/     # ← changes often, but only this layer rebuilds
```

**Prove it:**
1. Write a Dockerfile with the bad order
2. Run `docker build` — note total time
3. Change a config file
4. Run `docker build` again — note time (apt reinstall runs again)
5. Fix the order
6. Change the config file
7. Run `docker build` — note time (apt is cached, only COPY reruns)

---

## Exercise 4 — Build the MariaDB Dockerfile yourself

**Delete the existing Dockerfile and write it from scratch.**

Requirements:
- Base: `debian:bookworm-slim`
- Install: `mariadb-server` and `mariadb-client`
- Copy a config file into `/etc/mysql/mariadb.conf.d/`
- Copy an init script into `/usr/local/bin/` and make it executable
- Expose port 3306
- Use the init script as the entrypoint

```bash
# Start fresh
rm Inception/srcs/requirements/mariadb/Dockerfile
touch Inception/srcs/requirements/mariadb/Dockerfile
# Write it yourself
```

Compare your result to what exists in the repo only after you've written your own.

---

## .dockerignore — Keep your build context clean

The `.dockerignore` file works like `.gitignore` but for the Docker build context.

```
# .dockerignore
*.md
.git/
node_modules/
.env
secrets/
```

**Why it matters:**
```bash
# Without .dockerignore, everything in the directory goes to Docker daemon
# Your .git folder alone can be 50MB
# docker build -t myimage .  ← sends .git to daemon = slow
```

---

## Debugging Dockerfile problems

```bash
# See exactly what went wrong during build
docker build --progress=plain -t myimage .

# If a RUN step fails, comment out everything after it
# Then build and exec into it to debug
docker build -t debug .
docker run -it --entrypoint /bin/bash debug
# Now you're inside the partially-built image

# Check what's in each layer
docker history myimage

# Nuclear option: start from scratch
docker build --no-cache -t myimage .
```

---

## Knowledge Check

1. What is the difference between an image and a container?
2. Why should you chain `apt-get update && apt-get install` in one `RUN`?
3. What is the difference between `CMD` and `ENTRYPOINT`?
4. Why use exec form `["nginx"]` instead of shell form `nginx`?
5. What does `EXPOSE` actually do?
6. If you put `COPY` before `RUN apt-get install`, what problem does this cause?
7. How do you enter a shell inside a running container?
8. How do you build an image from a specific Dockerfile file (not named `Dockerfile`)?
