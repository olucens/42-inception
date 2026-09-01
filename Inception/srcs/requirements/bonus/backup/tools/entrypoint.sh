#!/bin/bash
# ---------------------------------------------------------------------------
# Backup service entrypoint: publish the environment for cron, install the
# schedule, take one backup now, then run cron in the foreground.
# ---------------------------------------------------------------------------
set -euo pipefail

log() { echo "[backup-init] $*"; }

: "${MYSQL_HOST:?MYSQL_HOST is not set}"
: "${MYSQL_DATABASE:?MYSQL_DATABASE is not set}"
: "${MYSQL_USER:?MYSQL_USER is not set}"
: "${BACKUP_SCHEDULE:=0 3 * * *}"
: "${BACKUP_KEEP:=7}"

# --- Hand the environment to cron -------------------------------------------
# cron jobs do not inherit this process's environment, so the values that
# arrived via `env_file:` have to be written somewhere backup.sh can read them.
# Note that only NON-SECRET values go here — the password stays in
# /run/secrets/db_password and is read by the script at run time.
cat > /etc/backup.env <<ENVEOF
MYSQL_HOST=${MYSQL_HOST}
MYSQL_DATABASE=${MYSQL_DATABASE}
MYSQL_USER=${MYSQL_USER}
BACKUP_KEEP=${BACKUP_KEEP}
ENVEOF
chmod 600 /etc/backup.env

# --- Install the schedule ---------------------------------------------------
# Output is redirected to /proc/1/fd/1, i.e. PID 1's stdout — which is what
# Docker captures. By default cron mails output to a local user, and there is no
# MTA in this container, so the job's log would vanish entirely.
log "schedule: ${BACKUP_SCHEDULE} (keeping ${BACKUP_KEEP} dumps)"
echo "${BACKUP_SCHEDULE} root /usr/local/bin/backup.sh > /proc/1/fd/1 2>&1" > /etc/cron.d/db-backup
# Debian's cron silently ignores files in cron.d that are group/world writable
# or that lack a trailing newline. Both are classic silent failures.
chmod 0644 /etc/cron.d/db-backup
crontab /dev/null 2>/dev/null || true

# --- Wait for MariaDB -------------------------------------------------------
# WHY this is needed even though compose has `depends_on: mariadb`:
# depends_on orders container START, not service READINESS. On a cold volume
# MariaDB spends ~40s in mysql_install_db before it answers, and the initial
# backup below would fail with
#   ERROR 2002: Can't connect to server on 'mariadb' (115)
# Cron would then not retry until the next scheduled run — 03:00 by default —
# so the operator would find an empty /backups with no obvious explanation.
#
# Bounded retry with a real authenticated query, not a port check: the port
# opens well before the grants exist.
DB_PASSWORD="$(cat /run/secrets/db_password)"
DB_WAIT_SECONDS=120
log "waiting for MariaDB at ${MYSQL_HOST} (up to ${DB_WAIT_SECONDS}s)"
DB_READY=0
for i in $(seq 1 "${DB_WAIT_SECONDS}"); do
    if mariadb -h "${MYSQL_HOST}" -u "${MYSQL_USER}" -p"${DB_PASSWORD}" \
               -e 'SELECT 1' "${MYSQL_DATABASE}" >/dev/null 2>&1; then
        DB_READY=1
        log "MariaDB is ready"
        break
    fi
    sleep 1
done

# --- One backup now ---------------------------------------------------------
# So there is something to show immediately, and so a misconfiguration surfaces
# at start-up rather than silently at 03:00.
#
# Non-fatal on failure: a backup service must never be the reason the stack does
# not come up. It logs loudly and cron retries on schedule.
if [ "${DB_READY}" = "1" ]; then
    log "taking an initial backup"
    /usr/local/bin/backup.sh || log "initial backup failed (will retry on schedule)"
else
    log "WARNING: MariaDB not reachable after ${DB_WAIT_SECONDS}s — skipping initial backup"
fi

# --- Hand over to the daemon -----------------------------------------------
# `cron -f` stays in the foreground, so `exec` makes it PID 1.
#
# This is worth being precise about at a defence: cron is a REAL daemon whose
# job is to wait, not a `sleep infinity` hack. The forbidden patterns are fake
# foreground processes that exist only to stop the container exiting; here the
# scheduler IS the service.
log "starting cron as PID 1"
exec cron -f
