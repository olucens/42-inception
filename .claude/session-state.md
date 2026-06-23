# Session State

Last updated: 2026-06-23

## Current Status

**Phase 1 — IN PROGRESS**
MariaDB container built. WordPress and NGINX: empty stubs.
User requested learning materials instead of just receiving code.

---

## What Was Done Across All Sessions

### Session 1 (Phase 0)
- Read inception-subject.pdf
- Created `materials-inception/learning-plan.md`
- Created `materials-inception/docker/01-04` (internals, networking, storage, building images)

### Session 2 (Phase 1 start)
- Fixed .gitignore (added secrets/, srcs/.env)
- Removed empty secrets files from git tracking
- Created Makefile (all/clean/fclean/re)
- Built MariaDB: Dockerfile + conf/mariadb.cnf + tools/init.sh
- Created docker-compose.yml (MariaDB wired, WP/NGINX commented stubs)

### Session 3 (Learning materials)
- Created `materials-inception/cheatsheet.md`
- Created `materials-inception/training/01-05` (full hands-on lab series)
- Updated CLAUDE.md with full context + teaching approach

---

## What Exists Now

### Learning Materials (all committed)
```
materials-inception/
  cheatsheet.md                    ← all commands needed
  learning-plan.md                 ← roadmap
  docker/01-04.md                  ← theory docs
  training/
    01-containers-from-scratch.md  ← kernel level, exercises
    02-dockerfile.md               ← write Dockerfiles, exercises
    03-networking-volumes.md       ← connect containers, exercises
    04-compose-and-init.md         ← compose file + init scripts
    05-services-deep-dive.md       ← MariaDB/WP/NGINX details
```

### Project Code
```
Inception/
  Makefile                 ✅ complete
  .gitignore               ✅ excludes secrets/ and srcs/.env
  srcs/
    .env.example           ✅ template committed
    docker-compose.yml     ✅ MariaDB wired
    requirements/
      mariadb/
        Dockerfile         ✅ debian:bookworm-slim
        conf/mariadb.cnf   ✅ bind-address=0.0.0.0
        tools/init.sh      ✅ first-run init + exec mysqld
      nginx/               ❌ empty — user to write
      wordpress/           ❌ empty — user to write
```

---

## Next Steps

**User should:**
1. Read training/01-05 and do exercises
2. Set up secrets and .env manually (see CLAUDE.md)
3. Test `make` and verify MariaDB works
4. Write WordPress container themselves (guided by training/05)
5. Write NGINX container themselves (guided by training/05)

**When user is ready for each container:**
- Guide them through: ask what they've tried, review their code, explain what's missing
- Don't write it FOR them — pair program

---

## Files to Create Manually (NOT in git)

```bash
cp Inception/srcs/.env.example Inception/srcs/.env
echo "rootpass"   > Inception/secrets/db_root_password.txt
echo "wppass"     > Inception/secrets/db_password.txt
echo "admin:pass" > Inception/secrets/credentials.txt
mkdir -p /home/akuzmin/data/mariadb /home/akuzmin/data/wordpress
```
