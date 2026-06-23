# Inception — Claude Code Project Context

This file is read automatically by Claude Code. It contains full project context
so any conversation on any machine can resume exactly where we left off.

---

## Project Overview

**42 School project: Inception (v5.3)**
Build a multi-container Docker infrastructure inside a VM using Docker Compose.
Full subject: `materials-inception/inception-subject.pdf`

**User goal:** Reach senior Docker developer level through guided phases.
**Current phase: Phase 1 — IN PROGRESS**

---

## 5-Phase Learning Structure

| Phase | Description | Status |
|-------|-------------|--------|
| Phase 0 | Learning plan + Docker internals docs | ✅ COMPLETE |
| Phase 1 | Build core project (guided, with teaching) | 🔄 IN PROGRESS |
| Phase 2 | Q&A evaluation — must score ≥90% to proceed | 🔲 |
| Phase 3 | Bonus part (guided, deeper) | 🔲 |
| Phase 4 | Senior DevOps Q&A — must score ≥90% | 🔲 |

---

## Important Context: Teaching Approach

The user asked to LEARN, not just receive code. Key guidance:
- Always explain WHY before giving code
- Ask user to try writing things themselves before showing solutions
- Point to `materials-inception/training/` for hands-on exercises
- After Phase 1 code is written, user should be able to DELETE it all and rewrite from memory

---

## What Has Been Created

### Learning Materials (`materials-inception/`)
```
learning-plan.md              ← 8-step core + 5-step bonus roadmap
cheatsheet.md                 ← all commands needed in this project
docker/
  01-internals.md             ← namespaces, cgroups, OverlayFS, runc stack
  02-networking.md            ← bridge networks, DNS, iptables
  03-storage.md               ← named volumes, bind mounts
  04-building-images.md       ← Dockerfile best practices
training/                     ← HANDS-ON EXERCISES (read these in order!)
  01-containers-from-scratch.md  ← what containers ARE at kernel level
  02-dockerfile.md               ← write Dockerfiles yourself
  03-networking-volumes.md       ← connect containers, persist data
  04-compose-and-init.md         ← docker-compose.yml, init scripts
  05-services-deep-dive.md       ← MariaDB, WordPress, NGINX in depth
eval/
  core/                       ← empty, Phase 2 will fill this
```

### Project Code (`Inception/`)
```
Makefile                      ← all/clean/fclean/re targets ✅
.gitignore                    ← excludes secrets/ and srcs/.env ✅
srcs/
  .env.example                ← template, copy to .env manually ✅
  docker-compose.yml          ← MariaDB wired, WP and NGINX stubbed ✅
  requirements/
    mariadb/
      Dockerfile              ← debian:bookworm-slim ✅
      conf/mariadb.cnf        ← bind-address=0.0.0.0 ✅
      tools/init.sh           ← first-run setup + exec mysqld ✅
    nginx/
      Dockerfile              ← EMPTY — to be written
      conf/                   ← EMPTY — nginx.conf needed
      tools/                  ← EMPTY — gen-cert.sh needed
    wordpress/
      Dockerfile              ← EMPTY — to be written
      conf/                   ← EMPTY — www.conf needed
      tools/                  ← EMPTY — setup.sh needed
```

---

## Mandatory Project Requirements (from subject)

### Infrastructure
- 3 containers: **NGINX** (TLS 1.2/1.3 only, port 443) → **WordPress+PHP-FPM** (port 9000) → **MariaDB** (port 3306)
- 2 named volumes: WordPress files + MariaDB database
- 1 custom Docker network (bridge)
- All images built from Alpine or Debian (penultimate stable) — NO ready-made app images
- Data stored at `/home/akuzmin/data/` on host

### Hard Rules
- `latest` tag: **FORBIDDEN**
- Ready-made images (wordpress:, nginx:, mariadb:): **FORBIDDEN**
- `network: host`, `--link`, `links:`: **FORBIDDEN**
- `tail -f`, `sleep infinity`, `while true`, `bash` as entrypoint: **FORBIDDEN**
- Passwords in Dockerfiles or committed files: **FORBIDDEN** (project failure)
- Bind mounts for main volumes: **FORBIDDEN** (use named volumes)
- Containers must restart on crash: `restart: on-failure`
- Environment variables + `.env` file: **MANDATORY**
- Docker secrets for passwords: **STRONGLY RECOMMENDED**

### WordPress Database
- 2 users required: one admin + one regular user
- Admin username CANNOT contain: `admin`, `Admin`, `administrator`, `Administrator`

### Domain
- `akuzmin.42.fr` must resolve to VM's local IP (edit `/etc/hosts`)
- NGINX is the ONLY entry point (port 443)

### Required Documentation Files
- `README.md`, `USER_DOC.md`, `DEV_DOC.md` (at repo root)

---

## Files to Create Manually on Each Machine (NOT in git)

```bash
# 1. Copy env template
cp Inception/srcs/.env.example Inception/srcs/.env

# 2. Create secrets (use your own passwords)
echo "your_root_password"  > Inception/secrets/db_root_password.txt
echo "your_wp_password"    > Inception/secrets/db_password.txt
echo "admin:admin_password" > Inception/secrets/credentials.txt

# 3. Create data directories
mkdir -p /home/akuzmin/data/mariadb
mkdir -p /home/akuzmin/data/wordpress
```

---

## Next Steps When Resuming

**The user should:**
1. Read `materials-inception/training/` labs 01-05 (understand concepts)
2. Try exercises in each lab
3. Then attempt to write each service container from scratch

**Order to build:**
1. Test MariaDB: `cd Inception && make` → verify with `docker exec -it mariadb mariadb -u wp_user -pwppassword wordpress`
2. Build WordPress container (Dockerfile + www.conf + setup.sh)
3. Add WordPress to docker-compose.yml
4. Build NGINX container (Dockerfile + nginx.conf + TLS cert)
5. Add NGINX to docker-compose.yml
6. Wire everything, test full stack
7. Add domain to /etc/hosts
8. Documentation (README, USER_DOC, DEV_DOC)

---

## How Claude Should Behave in This Project

- Ask user to write things themselves first, then review
- Explain WHY before giving code
- Point to training labs for background reading
- Phase 2 and 4: create Q&A files, evaluate strictly (0-100% per question), do not proceed until ≥90%
- Phase 3 and bonus: go deeper, provide external learning resources
