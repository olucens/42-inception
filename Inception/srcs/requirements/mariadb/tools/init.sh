#!/bin/bash
set -e

# Read passwords from Docker secrets (mounted at /run/secrets/ by Docker)
# The subject strongly recommends secrets over env vars for passwords
DB_ROOT_PASSWORD=$(cat /run/secrets/db_root_password)
DB_PASSWORD=$(cat /run/secrets/db_password)

# The mysqld socket directory must exist and be owned by mysql
# Debian's package doesn't always pre-create it inside a container
mkdir -p /var/run/mysqld
chown mysql:mysql /var/run/mysqld

# Only initialize when the data directory is empty (first container start)
# mysql/ subdirectory = MariaDB's internal system database — created during init
if [ ! -d "/var/lib/mysql/mysql" ]; then
    echo "[MariaDB] First run — initializing data directory..."

    # mysql_install_db creates the system tables (user, grants, etc.)
    # --skip-test-db: don't create the test database
    mysql_install_db \
        --user=mysql \
        --datadir=/var/lib/mysql \
        --skip-test-db > /dev/null 2>&1

    # Start a temporary instance with NO network — socket only
    # We need it running to execute SQL, but we don't want it accepting
    # network connections before it's fully configured
    mysqld --user=mysql --skip-networking &
    MYSQL_PID=$!

    echo "[MariaDB] Waiting for temporary instance to be ready..."
    until mysqladmin ping --socket=/var/run/mysqld/mysqld.sock --silent 2>/dev/null; do
        sleep 1
    done

    echo "[MariaDB] Creating database '${MYSQL_DATABASE}' and user '${MYSQL_USER}'..."

    # Run all setup as a single SQL transaction over the local socket
    # MYSQL_DATABASE and MYSQL_USER come from docker-compose env_file (.env)
    mysql --socket=/var/run/mysqld/mysqld.sock << SQL
-- WordPress database
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;

-- WordPress application user (connects from WordPress container, hence '%')
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%'
    IDENTIFIED BY '${DB_PASSWORD}';

GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.*
    TO '${MYSQL_USER}'@'%';

-- Set root password (root only accessible locally, but password still required)
ALTER USER 'root'@'localhost'
    IDENTIFIED BY '${DB_ROOT_PASSWORD}';

FLUSH PRIVILEGES;
SQL

    echo "[MariaDB] Setup complete. Stopping temporary instance..."
    mysqladmin \
        --socket=/var/run/mysqld/mysqld.sock \
        -u root \
        --password="${DB_ROOT_PASSWORD}" \
        shutdown
    wait $MYSQL_PID
    echo "[MariaDB] Data directory initialized."
fi

# exec replaces this script with mysqld — mysqld becomes PID 1
# This is critical: PID 1 receives SIGTERM from Docker on container stop
# Without exec, the shell would be PID 1 and mysqld would never get SIGTERM
echo "[MariaDB] Starting mysqld as PID 1..."
exec mysqld --user=mysql
