# tests/

Not unit tests — a linter for the forbidden-pattern rules in `materials-inception/inception-subject.pdf`. Nothing here runs containers; it only greps Dockerfiles, `docker-compose.yml`, and git-tracked files.

## Run locally

```bash
bash tests/check_inception_rules.sh
```

Exit code `0` = no FAIL (WARN is fine — usually means "not written yet"). Exit code `1` = at least one FAIL.

## What it checks

- Required files exist: `Makefile`, `docker-compose.yml`, one `Dockerfile` per mandatory service
- `FROM` is `alpine:` or `debian:` with an explicit non-`latest` tag
- No `tail -f`, `sleep infinity`, `while true`/`while :`, or bare `bash`/`sh` as CMD/ENTRYPOINT — in Dockerfiles and in `tools/*.sh`
- No hardcoded `PASSWORD=`/`PASSWD=` literal in a Dockerfile
- No `network: host` / `network_mode: host`, no `links:` / `--link`
- Top-level `networks:` present (mandatory), `secrets:` present (recommended, warn-only)
- Each mandatory service (`mariadb`, `wordpress`, `nginx`) is defined in compose
- `image:` name matches the service name and has an explicit non-`latest` tag
- `restart:` policy set per service
- No bind-mount syntax (`- /host/path:...`) in a service's `volumes:`
- `srcs/.env` and `secrets/*.txt` are not tracked by git (the subject: "credentials found in your Git repository → project failure")

## Runs automatically

`.github/workflows/lints.yml` runs this script on every push to `main`. It's a personal safety net, not part of the 42 evaluation — the defense itself is manual, in your VM.
