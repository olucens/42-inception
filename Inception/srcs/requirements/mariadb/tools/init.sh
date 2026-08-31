#!/bin/bash
# ---------------------------------------------------------------------------
# MariaDB entrypoint.
#
# Runs as PID 1. Its job: make sure /var/lib/mysql is a usable data directory,
# then REPLACE itself with mysqld via `exec`.
#
# It deliberately does NOT contain `tail -f`, `sleep infinity` or `while true`.
# The container stays alive because a real daemon (mysqld) is running in the
# foreground as PID 1 — which is the whole point of the subject's warning.
# ---------------------------------------------------------------------------
set -euo pipefail

log() { echo "[mariadb-init] $*"; }

# --- Secrets ---------------------------------------------------------------
# WHY read from /run/secrets and not from the environment:
# `docker inspect <container>` and `docker compose config` print every
# environment variable in clear text, and env vars are inherited by every child
# process (visible in /proc/<pid>/environ). A Docker secret is instead exposed
# as a read-only file under /run/secrets, which none of those commands reveal
# and which is never baked into an image layer. The subject says credentials
# found in the git repository "will result in project failure" — ../secrets/ is
# git-ignored, and only the .example template is committed.
DB_ROOT_PASSWORD="$(cat /run/secrets/db_root_password)"
DB_PASSWORD="$(cat /run/secrets/db_password)"

# Non-secret configuration comes from srcs/.env via `env_file:` in compose.
: "${MYSQL_DATABASE:?MYSQL_DATABASE is not set (check srcs/.env)}"
: "${MYSQL_USER:?MYSQL_USER is not set (check srcs/.env)}"

# --- Runtime directories ---------------------------------------------------
# The Debian package creates /run/mysqld at install time, but /run is a tmpfs
# that is empty on every container start, so it must be recreated here.
mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld

# The named volume is mounted by Docker as root-owned on first creation.
chown -R mysql:mysql /var/lib/mysql

# --- Local client invocations ----------------------------------------------
# WHY MYSQL_HOST is unset here — this one cost a full debugging round.
#
# srcs/.env defines MYSQL_HOST=mariadb because WordPress needs it, and
# `env_file: .env` hands the whole file to EVERY service, including this one.
# The MariaDB client libraries read MYSQL_HOST from the environment as their
# default host, and naming a host switches the transport to TCP.
#
# The trap: --protocol=socket does NOT win against it. Verified empirically —
# `mariadb --protocol=socket --socket=/run/mysqld/mysqld.sock -e 'SELECT 1'`
# with MYSQL_HOST set still fails with
#   ERROR 2002 (HY000): Can't connect to server on 'mariadb' (115)
# because the temporary instance below runs with --skip-networking and has no
# TCP listener at all. Only removing the variable (or passing -h localhost)
# actually restores socket connections.
#
# The failure is nasty because it is silent-ish: the container crash-loops on
# `restart: on-failure`, and the log line that matters scrolls past between
# hundreds of InnoDB notices.
unset MYSQL_HOST

MYSQL_SOCKET="/run/mysqld/mysqld.sock"
# --protocol=socket is kept as belt-and-braces: it documents the intent and
# guards against a stray ~/.my.cnf or a MYSQL_TCP_PORT in the environment.
CLIENT="mariadb --protocol=socket --socket=${MYSQL_SOCKET}"
ADMIN="mariadb-admin --protocol=socket --socket=${MYSQL_SOCKET}"

# --- First-run initialisation ----------------------------------------------
# WHY a sentinel file we write ourselves, instead of testing for
# /var/lib/mysql/mysql:
# that directory exists as soon as mysql_install_db has run — i.e. BEFORE the
# database, the user and the grants are created. If the SQL step then fails, the
# container exits, `restart: on-failure` brings it back, and the old check would
# report "already initialised" and start a permanently broken server. The
# sentinel is written only after the last statement succeeds, so a partially
# initialised volume is correctly retried.
INIT_MARKER="/var/lib/mysql/.inception-initialised"

if [ -f "${INIT_MARKER}" ]; then
    log "data directory already initialised — skipping setup"
else
    log "no init marker — initialising data directory"

    # Creates the system tables (mysql.user, mysql.db, ...).
    # --skip-test-db: do not create the world-writable `test` database.
    # Guarded because a previous partial run may already have done this.
    if [ -d "/var/lib/mysql/mysql" ]; then
        log "system tables already present — skipping mysql_install_db"
    else
        mysql_install_db --user=mysql --datadir=/var/lib/mysql --skip-test-db >/dev/null
    fi

    # WHY a temporary instance with --skip-networking:
    # we need a running server to execute SQL, but during this window root has
    # no password yet. --skip-networking makes it listen on the UNIX socket
    # only, so nothing on the Docker network can connect while it is unlocked.
    log "starting temporary instance (socket only)"
    mysqld --user=mysql --skip-networking --socket="${MYSQL_SOCKET}" &
    MYSQLD_PID=$!

    # Bounded readiness wait. This is NOT a keep-alive loop: it has a hard
    # ceiling and the script fails loudly instead of hanging forever.
    for i in $(seq 1 60); do
        if $ADMIN ping --silent 2>/dev/null; then
            break
        fi
        [ "$i" -eq 60 ] && { log "FATAL: temporary instance never came up"; exit 1; }
        sleep 1
    done

    log "creating database '${MYSQL_DATABASE}' and user '${MYSQL_USER}'"

    # WHY the passwords are interpolated here and not passed on the command
    # line: anything after `mysql -p...` shows up in `ps aux` inside the
    # container. Piping SQL over stdin keeps them out of the process table.
    $CLIENT <<SQL
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;

-- '%' = "from any host". Inside a user-defined bridge network the container's
-- IP is assigned by Docker's IPAM and changes between runs, so pinning the
-- grant to an address is not possible. Isolation is provided by the network
-- (3306 is never published to the host), not by the grant host.
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';

-- Least privilege: root stays local-only. WordPress never uses it.
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
DROP USER IF EXISTS ''@'localhost';
DROP USER IF EXISTS ''@'%';
FLUSH PRIVILEGES;
SQL

    # Written only now: every statement above succeeded.
    touch "${INIT_MARKER}"

    log "shutting down temporary instance"
    $ADMIN -u root --password="${DB_ROOT_PASSWORD}" shutdown
    wait "${MYSQLD_PID}"
    log "initialisation complete"
fi

# --- Hand over to the daemon -----------------------------------------------
# `exec` replaces this shell process with mysqld, so mysqld keeps PID 1 and
# receives SIGTERM directly from `docker stop`, giving InnoDB time for a clean
# shutdown. Without exec, the shell would stay PID 1, swallow the signal, and
# the database would be killed mid-write after the 10s grace period.
log "starting mysqld as PID 1"
exec mysqld --user=mysql
