#!/bin/bash
# ---------------------------------------------------------------------------
# Adminer entrypoint.
# ---------------------------------------------------------------------------
set -euo pipefail

log() { echo "[adminer-init] $*"; }

: "${MYSQL_HOST:=mariadb}"

log "adminer ready — server field should be '${MYSQL_HOST}'"
log "log in with MYSQL_USER from srcs/.env and the password in secrets/db_password.txt"

# --- Hand over to the daemon -----------------------------------------------
# php -S runs in the foreground as a single process, so `exec` makes it PID 1
# and it receives SIGTERM from `docker stop`.
#
# -S 0.0.0.0:8080 : bind every interface of this container. 127.0.0.1 would only
#                   accept connections from inside the container itself.
# -t              : document root.
#
# No credentials are baked in anywhere: Adminer asks for them in its login form,
# and the operator reads them from secrets/. Pre-filling them would put a
# password in an image layer.
log "starting php built-in server as PID 1 on :8080"
exec php -S 0.0.0.0:8080 -t /var/www/adminer
