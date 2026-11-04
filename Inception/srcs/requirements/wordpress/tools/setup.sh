#!/bin/bash
# ---------------------------------------------------------------------------
# WordPress entrypoint.
#
# Runs as PID 1. Brings the shared named volume to the desired state, then
# `exec`s php-fpm so the daemon - not this shell - is PID 1.
# ---------------------------------------------------------------------------
set -euo pipefail

log() { echo "[wordpress-init] $*"; }

WP_PATH="/var/www/html"
WP="wp --path=${WP_PATH} --allow-root"

# --- Configuration ---------------------------------------------------------
# WP_DB_HOST is deliberately NOT called MYSQL_HOST. `env_file: .env` hands this
# file to every service, and the MariaDB client treats MYSQL_HOST as its default
# host. Inside the mariadb container that variable would turn a plain
# `mariadb -u root -p` into a TCP connection, which root is not allowed to make.
: "${WP_DB_HOST:?WP_DB_HOST is not set (check srcs/.env)}"
: "${MYSQL_DATABASE:?MYSQL_DATABASE is not set}"
: "${MYSQL_USER:?MYSQL_USER is not set}"
: "${DOMAIN_NAME:?DOMAIN_NAME is not set}"
: "${WP_TITLE:?WP_TITLE is not set}"
: "${WP_ADMIN_USER:?WP_ADMIN_USER is not set}"
: "${WP_ADMIN_EMAIL:?WP_ADMIN_EMAIL is not set}"
: "${WP_USER:?WP_USER is not set}"
: "${WP_USER_EMAIL:?WP_USER_EMAIL is not set}"
: "${MYSQL_PORT:=3306}"
: "${WP_USER_ROLE:=author}"
: "${WP_URL:=https://${DOMAIN_NAME}}"

# --- Secrets ---------------------------------------------------------------
DB_PASSWORD="$(cat /run/secrets/db_password)"

# credentials.txt holds the two WordPress account passwords as KEY=value lines.
# WHY grep/cut instead of `source`: `source` would execute the file as shell code,
# so a stray backtick or $(...) in a password would run as a command.
read_credential() {
    local key="$1" value
    value="$(grep -m1 -E "^${key}=" /run/secrets/credentials | cut -d= -f2-)"
    [ -n "${value}" ] || { log "FATAL: ${key} missing from secrets/credentials.txt"; exit 1; }
    printf '%s' "${value}"
}
WP_ADMIN_PASSWORD="$(read_credential WP_ADMIN_PASSWORD)"
WP_USER_PASSWORD="$(read_credential WP_USER_PASSWORD)"

# --- Guard: the admin username rule ----------------------------------------
# Subject: "The administrator's username can't contain admin/Admin or
# administrator/Administrator". Fail loudly at startup, not during the defence.
if printf '%s' "${WP_ADMIN_USER}" | grep -qi 'admin'; then
    log "FATAL: WP_ADMIN_USER='${WP_ADMIN_USER}' contains 'admin' - forbidden by the subject"
    exit 1
fi

# --- Wait for MariaDB ------------------------------------------------------
# compose already waits for mariadb to be healthy, but only during `up`. When the
# Docker daemon restarts this container after a crash, compose is not involved,
# so the wait has to live here as well.
#
# It is a bounded retry, not a keep-alive loop: it ends with success or a failure.
# It runs a real authenticated query, so it also proves that the user and the
# grants exist. MYSQL_PWD keeps the password out of `ps`, unlike -p<password>.
DB_WAIT_SECONDS=120
log "waiting for MariaDB at ${WP_DB_HOST}:${MYSQL_PORT} (up to ${DB_WAIT_SECONDS}s)"
for i in $(seq 1 "${DB_WAIT_SECONDS}"); do
    if MYSQL_PWD="${DB_PASSWORD}" mariadb -h "${WP_DB_HOST}" -P "${MYSQL_PORT}" \
            -u "${MYSQL_USER}" -e 'SELECT 1' "${MYSQL_DATABASE}" >/dev/null 2>&1; then
        log "MariaDB is accepting authenticated queries"
        break
    fi
    if [ "$i" -eq "${DB_WAIT_SECONDS}" ]; then
        log "FATAL: cannot log in to MariaDB after ${DB_WAIT_SECONDS}s"
        log "If secrets/ was regenerated, the data directory still holds the OLD passwords: run 'make fclean'"
        exit 1
    fi
    sleep 1
done

# --- Installation ----------------------------------------------------------
# Every step checks its own result instead of sharing one marker. A crash between
# two steps is therefore safe: the restart policy runs this script again and it
# continues exactly where it stopped.

# WHY at runtime and not in the Dockerfile: Docker seeds an empty volume from the
# image only once, so a rebuilt image could never update a volume that already
# has files. WP-CLI owns the volume's contents instead.
if [ ! -f "${WP_PATH}/wp-load.php" ]; then
    log "downloading WordPress"
    $WP core download --version=6.4.3 --force
fi

if [ ! -f "${WP_PATH}/wp-config.php" ]; then
    log "creating wp-config.php"
    $WP config create \
        --dbname="${MYSQL_DATABASE}" \
        --dbuser="${MYSQL_USER}" \
        --dbpass="${DB_PASSWORD}" \
        --dbhost="${WP_DB_HOST}:${MYSQL_PORT}" \
        --skip-check
fi

# wp-config.php lives on the volume, so without this a changed port in .env would
# never reach an installed site. Re-applying on every start makes a configuration
# change take effect on the next `make`.
#
# Pinning the https:// URL also stops WordPress from generating http:// URLs:
# TLS terminates at NGINX, so PHP itself only ever sees FastCGI.
$WP config set DB_HOST    "${WP_DB_HOST}:${MYSQL_PORT}" --quiet
$WP config set WP_HOME    "${WP_URL}" --quiet
$WP config set WP_SITEURL "${WP_URL}" --quiet

if ! $WP core is-installed; then
    log "installing WordPress"
    # --skip-email: there is no mail server in this container.
    $WP core install \
        --url="${WP_URL}" \
        --title="${WP_TITLE}" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASSWORD}" \
        --admin_email="${WP_ADMIN_EMAIL}" \
        --skip-email
    # Publish comments of logged-in users immediately instead of holding them
    # for moderation, so a new comment is visible on the site right away.
    $WP option update comment_previously_approved 0 --quiet
fi

# Subject: "there must be two users, one of them being the administrator."
if ! $WP user get "${WP_USER}" --field=ID >/dev/null 2>&1; then
    log "creating user '${WP_USER}'"
    $WP user create "${WP_USER}" "${WP_USER_EMAIL}" \
        --role="${WP_USER_ROLE}" \
        --user_pass="${WP_USER_PASSWORD}" --quiet
fi

# WP-CLI ran as root, so new files are root-owned. The FPM workers run as www-data
# and must be able to write uploads, themes and updates.
chown -R www-data:www-data "${WP_PATH}"

# --- Hand over to the daemon -----------------------------------------------
# --nodaemonize : stay in the foreground. The default is to fork and detach, which
#                 would make PID 1 exit and stop the container immediately.
# --force-stderr: send the master's log to stderr, where `docker logs` sees it.
log "starting php-fpm 8.2 as PID 1"
exec /usr/sbin/php-fpm8.2 --nodaemonize --force-stderr
