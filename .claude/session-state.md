# Session State

Last updated: 2026-06-22

## Current Status

**Phase 0 — COMPLETE**
**Phase 1 — NOT STARTED (next action)**

---

## What Was Done This Session

1. Read the full Inception subject PDF (17 pages, v5.3)
2. Created `materials-inception/learning-plan.md` — full 8-step core + 5-step bonus roadmap
3. Created `materials-inception/docker/01-internals.md` — Linux namespaces, cgroups, OverlayFS, runc/containerd/dockerd stack, how to implement containers from scratch
4. Created `materials-inception/docker/02-networking.md` — veth pairs, bridge networks, DNS, iptables port publishing, why host/link are forbidden
5. Created `materials-inception/docker/03-storage.md` — named volumes vs bind mounts, the Inception-specific volume pattern, OverlayFS CoW
6. Created `materials-inception/docker/04-building-images.md` — all Dockerfile instructions, init script pattern with `exec`, layer caching, security rules
7. Created `CLAUDE.md` (this repo) — full project context for any machine
8. Created `.claude/session-state.md` — this file

---

## Next Session: Start Phase 1

Tell Claude: **"Start Phase 1"** or **"Let's build the MariaDB container"**

Claude will:
1. Create the project directory structure and Makefile skeleton
2. Guide through MariaDB Dockerfile + init script with full explanation
3. Then WordPress + PHP-FPM
4. Then NGINX with TLS
5. Then Docker Compose wiring

---

## Key Decisions Made (or to make in Phase 1)

- [ ] Alpine or Debian? (choose one per service, be consistent)
- [ ] Specific version to pin (Alpine 3.19 or 3.20, Debian bookworm)
- [ ] Username for `akuzmin.42.fr` domain (login = akuzmin)
- [ ] WordPress admin username (cannot contain admin/administrator)

---

## Files to Create Manually on Each Machine (NOT in git)

```
secrets/credentials.txt        # WP admin user:password
secrets/db_password.txt        # MariaDB wp user password
secrets/db_root_password.txt   # MariaDB root password
srcs/.env                      # DOMAIN_NAME, MYSQL_DATABASE, MYSQL_USER
```

Also create data directories:
```bash
mkdir -p /home/akuzmin/data/mariadb
mkdir -p /home/akuzmin/data/wordpress
```

---

## Existing File Inventory

```
/home/akuzmin/Documents/42-inception/
├── CLAUDE.md                           ← project context (commit this)
├── claude-instructions.md              ← user's original phase instructions
├── .claude/
│   └── session-state.md               ← this file (commit this)
├── materials-inception/
│   ├── inception-subject.pdf           ← original subject PDF
│   ├── learning-plan.md               ← Phase 0 output (commit this)
│   ├── docker/
│   │   ├── 01-internals.md            ← commit
│   │   ├── 02-networking.md           ← commit
│   │   ├── 03-storage.md             ← commit
│   │   └── 04-building-images.md     ← commit
│   └── eval/
│       └── core/                      ← empty, Phase 2 will fill this
└── Inception/                         ← unknown (existing before this session)
```
