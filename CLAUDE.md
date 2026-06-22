# Inception — Claude Code Project Context

This file is read automatically by Claude Code. It contains full project context
so any conversation on any machine can resume exactly where we left off.

---

## Project Overview

**42 School project: Inception (v5.3)**
Build a multi-container Docker infrastructure inside a VM using Docker Compose.
Full subject: `materials-inception/inception-subject.pdf`

**User goal:** Reach senior Docker developer level through guided phases.
**Current phase: Phase 1 — NOT STARTED YET** (ready to begin)

---

## 5-Phase Learning Structure

| Phase | Description | Status |
|-------|-------------|--------|
| Phase 0 | Learning plan + Docker internals docs | ✅ COMPLETE |
| Phase 1 | Build core project (guided, with teaching) | 🔲 NEXT |
| Phase 2 | Q&A evaluation — must score ≥90% to proceed | 🔲 |
| Phase 3 | Bonus part (guided, deeper) | 🔲 |
| Phase 4 | Senior DevOps Q&A — must score ≥90% | 🔲 |

**Evaluation rule:** 0% = not answered at all, 100% = full answer with sufficient explanation.
Questions are in `materials-inception/eval/core/` (Phase 2) — not created yet.

---

## What Phase 0 Produced

```
materials-inception/
├── learning-plan.md          ← 8-step core roadmap + 5-step bonus roadmap
├── inception-subject.pdf     ← original subject
├── docker/
│   ├── 01-internals.md       ← namespaces, cgroups, OverlayFS, runc stack
│   ├── 02-networking.md      ← bridge networks, DNS, iptables, veth pairs
│   ├── 03-storage.md         ← named volumes, bind mounts, OverlayFS layers
│   └── 04-building-images.md ← Dockerfile best practices, init script pattern
└── eval/
    └── core/                 ← empty, will be filled in Phase 2
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

### Required Documentation Files (at repo root)
- `README.md` — with specific sections (see subject p.12)
- `USER_DOC.md` — end-user guide
- `DEV_DOC.md` — developer setup guide

---

## Final Project Structure to Build

```
42-inception/
├── Makefile                          ← builds everything via docker compose
├── README.md                         ← required, specific format
├── USER_DOC.md                       ← required
├── DEV_DOC.md                        ← required
├── .gitignore                        ← must ignore .env and secrets/
├── secrets/                          ← ignored by git, created manually on each machine
│   ├── credentials.txt               ← WP admin credentials
│   ├── db_password.txt               ← MariaDB user password
│   └── db_root_password.txt          ← MariaDB root password
└── srcs/
    ├── .env                          ← ignored by git, created manually
    ├── docker-compose.yml
    └── requirements/
        ├── mariadb/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/mariadb.cnf
        │   └── tools/init.sh
        ├── nginx/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/nginx.conf
        │   └── tools/gen-cert.sh
        ├── wordpress/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/www.conf
        │   └── tools/setup.sh
        └── bonus/
            ├── redis/
            ├── ftp/
            ├── static/
            ├── adminer/
            └── custom/
```

---

## Build Dependency Order

```
MariaDB (must be ready first)
    ↓
WordPress/PHP-FPM (needs DB)
    ↓
NGINX (needs WP files for serving static assets)
    ↓
User via browser (HTTPS :443)
```

---

## Phase 1 — Where to Start

When starting Phase 1, begin with Step 2 from `materials-inception/learning-plan.md`:
**MariaDB container first** (no dependencies, simplest to test independently).

Order of implementation:
1. Set up project directory structure + Makefile skeleton
2. MariaDB container + test it works
3. WordPress + PHP-FPM container + test against MariaDB
4. NGINX container with TLS + test full stack
5. Docker Compose wiring (volumes, network, secrets)
6. Security hardening (.env, secrets, .gitignore)
7. Domain setup (/etc/hosts)
8. Documentation (README, USER_DOC, DEV_DOC)

---

## How Claude Should Behave in This Project

- Guide through implementation step by step, explaining every decision
- Teach concepts at each step — don't just give code, explain WHY
- After each major piece, ask the user to confirm they understand before moving on
- Point to `materials-inception/docker/*.md` for reference material
- Phase 2 and 4: create Q&A files, evaluate strictly (0-100% per question), do not proceed until ≥90%
- Phase 3 and bonus: go deeper, provide external learning resources
