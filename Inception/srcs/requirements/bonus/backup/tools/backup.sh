#!/bin/bash
# ---------------------------------------------------------------------------
# Takes one compressed dump of the WordPress database and rotates old ones.
# Run by cron, and once at container start.
# ---------------------------------------------------------------------------
set -euo pipefail

# WHY the environment is read from a file instead of inherited:
# cron does NOT inherit the environment of the process that started it. Jobs run
# with a nearly empty environment (basically HOME, PATH, LOGNAME), so MYSQL_HOST
# and friends — which reached PID 1 through `env_file:` — are simply absent
# here. The entrypoint writes them to this file at start-up. Forgetting this is
# the single most common reason a containerised cron job "does nothing".
# shellcheck source=/dev/null
[ -f /etc/backup.env ] && . /etc/backup.env

: "${MYSQL_HOST:?}" "${MYSQL_DATABASE:?}" "${MYSQL_USER:?}"
: "${BACKUP_KEEP:=7}"

BACKUP_DIR="/backups"
STAMP="$(date +%Y%m%d-%H%M%S)"
TARGET="${BACKUP_DIR}/${MYSQL_DATABASE}-${STAMP}.sql.gz"

log() { echo "[backup $(date '+%Y-%m-%d %H:%M:%S')] $*"; }

DB_PASSWORD="$(cat /run/secrets/db_password)"

mkdir -p "${BACKUP_DIR}"

log "dumping '${MYSQL_DATABASE}' from ${MYSQL_HOST}"

# --single-transaction : take the dump inside one consistent snapshot instead of
#                        locking the tables. WordPress keeps serving during the
#                        backup — for InnoDB this is the correct choice.
# --quick              : stream rows instead of buffering a whole table in RAM.
# Write to .part first and rename only on success: a rename is atomic, so a
# crash mid-dump can never leave a truncated file that looks like a good backup.
if mariadb-dump \
        --host="${MYSQL_HOST}" \
        --user="${MYSQL_USER}" \
        --password="${DB_PASSWORD}" \
        --single-transaction \
        --quick \
        --databases "${MYSQL_DATABASE}" 2>/tmp/dump.err | gzip -c > "${TARGET}.part"; then
    mv "${TARGET}.part" "${TARGET}"
    log "wrote $(du -h "${TARGET}" | cut -f1) -> $(basename "${TARGET}")"
else
    rm -f "${TARGET}.part"
    log "FAILED: $(tr '\n' ' ' < /tmp/dump.err)"
    exit 1
fi

# --- Rotation ---------------------------------------------------------------
# Without this the volume grows until the disk is full — and a full disk takes
# down MariaDB too, so an unrotated backup job eventually causes the outage it
# was meant to protect against.
COUNT=$(find "${BACKUP_DIR}" -maxdepth 1 -name '*.sql.gz' | wc -l)
if [ "${COUNT}" -gt "${BACKUP_KEEP}" ]; then
    # Sorted by name; the timestamp format is lexicographically ordered, so the
    # oldest sort first.
    find "${BACKUP_DIR}" -maxdepth 1 -name '*.sql.gz' | sort | \
        head -n "$(( COUNT - BACKUP_KEEP ))" | \
        while read -r old; do
            log "rotating out $(basename "${old}")"
            rm -f "${old}"
        done
fi

log "done — ${BACKUP_KEEP} most recent kept"
