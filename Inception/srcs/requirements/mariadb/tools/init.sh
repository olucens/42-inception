#!/bin/bash
# ---------------------------------------------------------------------------
# MariaDB entrypoint.
#
# Runs as PID 1. Its job: make sure /var/lib/mysql is a usable data directory,
# then REPLACE itself with mysqld via `exec`.
#
# No keep-alive tricks and no process in the background: the container stays alive
# because a real daemon runs in the foreground as PID 1.
# ---------------------------------------------------------------------------
set -euo pipefail

log() { echo "[mariadb-init] $*"; }

# --- Secrets ---------------------------------------------------------------
# Read from files, not from the environment: `docker inspect` prints every
# environment variable in clear text, and child processes inherit them. A secret
# is a read-only file under /run/secrets that neither of those reveals.
DB_ROOT_PASSWORD="$(cat /run/secrets/db_root_password)"
DB_PASSWORD="$(cat /run/secrets/db_password)"

# Non-secret configuration comes from srcs/.env via `env_file:` in compose.
: "${MYSQL_DATABASE:?MYSQL_DATABASE is not set (check srcs/.env)}"
: "${MYSQL_USER:?MYSQL_USER is not set (check srcs/.env)}"

# --- Runtime directories ---------------------------------------------------
# mysqld runs as the mysql user, so it must own its socket directory and its
# data directory. A freshly created volume does not belong to mysql yet.
mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld /var/lib/mysql

# --- First-run initialisation ----------------------------------------------
# The marker is written only after the last SQL statement succeeded, so a run
# that fails halfway is retried by the restart policy instead of being mistaken
# for a finished one.
INIT_MARKER="/var/lib/mysql/.inception-initialised"

if [ -f "${INIT_MARKER}" ]; then
    log "data directory already initialised - skipping setup"
else
    log "no init marker - initialising data directory"

    # Creates the system tables (mysql.user, mysql.db, ...).
    # --skip-test-db: do not create the world-writable `test` database.
    if [ ! -d /var/lib/mysql/mysql ]; then
        mysql_install_db --user=mysql --datadir=/var/lib/mysql --skip-test-db >/dev/null
    fi

    # WHY --bootstrap and not a temporary server started in the background:
    # the evaluation forbids that ("ensure it runs no program in background").
    # --bootstrap runs in the FOREGROUND: it executes
    # the SQL from stdin and exits. It opens no socket and no TCP port, so nothing
    # can connect while root has no password, and no readiness loop is needed.
    #
    # FLUSH PRIVILEGES comes first because bootstrap mode starts with the grant
    # tables NOT loaded, and CREATE USER / ALTER USER need them.
    #
    # '%' = from any host: Docker assigns the WordPress container's IP dynamically,
    # so the grant cannot pin an address. The isolation comes from the network
    # (3306 is never published to the host).
    #
    # Root stays local-only, because WordPress never uses it.
    #
    # The passwords are piped over stdin, so they never appear in `ps`.
    log "creating database '${MYSQL_DATABASE}' and user '${MYSQL_USER}'"
    mysqld --user=mysql --bootstrap <<SQL
USE mysql;
FLUSH PRIVILEGES;
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
DROP USER IF EXISTS ''@'localhost';
DROP USER IF EXISTS ''@'%';
FLUSH PRIVILEGES;
SQL

    touch "${INIT_MARKER}"
    log "initialisation complete"
fi

# --- Hand over to the daemon -----------------------------------------------
# `exec` replaces this shell with mysqld, so mysqld keeps PID 1 and receives
# SIGTERM directly from `docker stop`, giving InnoDB time for a clean shutdown.
# Without exec the shell would stay PID 1 and swallow the signal, and the database
# would be SIGKILLed mid-write after the 10s grace period.
log "starting mysqld as PID 1"
exec mysqld --user=mysql
