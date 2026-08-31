#!/bin/bash
# ---------------------------------------------------------------------------
# WordPress entrypoint.
#
# Runs as PID 1. Installs WordPress into the shared named volume on first run,
# then `exec`s php-fpm so the daemon — not this shell — is PID 1.
# ---------------------------------------------------------------------------
set -euo pipefail

log() { echo "[wordpress-init] $*"; }

WP_PATH="/var/www/html"
WP="wp --path=${WP_PATH} --allow-root"

# --- Configuration ---------------------------------------------------------
: "${MYSQL_HOST:?MYSQL_HOST is not set (check srcs/.env)}"
: "${MYSQL_DATABASE:?MYSQL_DATABASE is not set}"
: "${MYSQL_USER:?MYSQL_USER is not set}"
: "${DOMAIN_NAME:?DOMAIN_NAME is not set}"
: "${WP_TITLE:?WP_TITLE is not set}"
: "${WP_ADMIN_USER:?WP_ADMIN_USER is not set}"
: "${WP_ADMIN_EMAIL:?WP_ADMIN_EMAIL is not set}"
: "${WP_USER:?WP_USER is not set}"
: "${WP_USER_EMAIL:?WP_USER_EMAIL is not set}"
: "${WP_USER_ROLE:=author}"
: "${WP_URL:=https://${DOMAIN_NAME}}"

# --- Secrets ---------------------------------------------------------------
DB_PASSWORD="$(cat /run/secrets/db_password)"

# credentials.txt holds the two WordPress account passwords as KEY=value lines.
# WHY parsed with grep/cut instead of `source`: `source` would execute the file
# as shell code, so a stray backtick or $(...) in a password would run as a
# command. Parsing keeps the file strictly data.
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
# administrator/Administrator". Failing loudly at startup is far better than
# discovering it during the defence.
if printf '%s' "${WP_ADMIN_USER}" | grep -qiE 'admin'; then
    log "FATAL: WP_ADMIN_USER='${WP_ADMIN_USER}' contains 'admin' — forbidden by the subject"
    exit 1
fi

# php-fpm's runtime dir lives on a tmpfs and is empty on every container start.
mkdir -p /run/php

# --- Wait for MariaDB ------------------------------------------------------
# WHY this loop exists even though compose has `depends_on: mariadb`:
# depends_on only orders *container start*, not *service readiness*. The mariadb
# container is "started" the instant its entrypoint runs — but on a fresh volume
# that entrypoint still has ~10s of mysql_install_db ahead of it. Without this
# wait, `wp config create` would fail on connection refused and the container
# would crash-loop.
#
# It is a bounded retry, not a keep-alive loop: 60 tries then a hard failure.
# The ceiling is generous on purpose: on a cold volume MariaDB has to run
# mysql_install_db before it will answer, which takes ~30-40s on a laptop VM.
DB_WAIT_SECONDS=120
log "waiting for MariaDB at ${MYSQL_HOST}:3306 (up to ${DB_WAIT_SECONDS}s)"
for i in $(seq 1 "${DB_WAIT_SECONDS}"); do
    # A real authenticated query, not just a TCP connect: the port opens well
    # before the grants exist, so `nc -z` style checks report ready too early.
    if mariadb -h "${MYSQL_HOST}" -u "${MYSQL_USER}" -p"${DB_PASSWORD}" \
               -e 'SELECT 1' "${MYSQL_DATABASE}" >/dev/null 2>&1; then
        log "MariaDB is accepting authenticated queries"
        break
    fi
    [ $(( i % 15 )) -eq 0 ] && log "still waiting... (${i}s)"
    [ "$i" -eq "${DB_WAIT_SECONDS}" ] && { log "FATAL: MariaDB unreachable after ${DB_WAIT_SECONDS}s"; exit 1; }
    sleep 1
done

# --- First-run installation ------------------------------------------------
# wp-config.php is the marker: it only exists after a successful install, and it
# lives on the named volume, so this whole block runs exactly once per volume.
if [ -f "${WP_PATH}/wp-config.php" ]; then
    log "wp-config.php present — WordPress already installed, skipping setup"
else
    log "installing WordPress into ${WP_PATH}"

    # WHY the core files are downloaded at RUNTIME and not baked into the image:
    # /var/www/html is a mount point for the wordpress-data named volume. Docker
    # mounts the volume OVER that directory, so anything the Dockerfile put there
    # would be hidden the moment the container starts. The files have to be
    # written after the mount exists — i.e. here.
    $WP core download --version=6.4.3

    # Writes wp-config.php with the DB credentials. The password is passed via
    # --dbpass, which never touches the Dockerfile or the .env file.
    $WP config create \
        --dbname="${MYSQL_DATABASE}" \
        --dbuser="${MYSQL_USER}" \
        --dbpass="${DB_PASSWORD}" \
        --dbhost="${MYSQL_HOST}" \
        --skip-check

    # TLS terminates at NGINX, so PHP sees a plain HTTP request. Pinning
    # WP_HOME/WP_SITEURL to the https:// URL stops WordPress from generating
    # http:// links (which browsers block as mixed content on an https page).
    $WP config set WP_HOME    "${WP_URL}"
    $WP config set WP_SITEURL "${WP_URL}"

    # Creates the tables and the administrator account.
    # --skip-email: there is no MTA in this container; without it the install
    # blocks trying to send the welcome mail.
    $WP core install \
        --url="${WP_URL}" \
        --title="${WP_TITLE}" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASSWORD}" \
        --admin_email="${WP_ADMIN_EMAIL}" \
        --skip-email

    # Subject: "there must be two users, one of them being the administrator."
    $WP user create "${WP_USER}" "${WP_USER_EMAIL}" \
        --role="${WP_USER_ROLE}" \
        --user_pass="${WP_USER_PASSWORD}"

    log "WordPress installed — admin='${WP_ADMIN_USER}', second user='${WP_USER}'"
fi

# WP-CLI ran as root (--allow-root), so fresh files are root-owned. The FPM
# workers run as www-data and must be able to write uploads, themes and updates.
chown -R www-data:www-data "${WP_PATH}"

# --- Hand over to the daemon -----------------------------------------------
# --nodaemonize : stay in the foreground. The default is to fork and detach,
#                 which would make PID 1 exit and kill the container instantly.
#                 This is the correct alternative to `tail -f` hacks.
# --force-stderr: send the master's log to stderr so `docker compose logs`
#                 shows it instead of it disappearing into a file.
log "starting php-fpm 8.2 as PID 1"
exec /usr/sbin/php-fpm8.2 --nodaemonize --force-stderr
