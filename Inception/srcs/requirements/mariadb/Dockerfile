FROM debian:bookworm-slim

# Install MariaDB — no ready-made mariadb: image allowed, so we install into base OS
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        mariadb-server \
        mariadb-client \
    && rm -rf /var/lib/apt/lists/*

# Our custom server config (overrides package defaults)
COPY conf/mariadb.cnf /etc/mysql/mariadb.conf.d/50-server.cnf

# Init script: initializes data dir on first run, then starts mysqld as PID 1
COPY tools/init.sh /usr/local/bin/init.sh
RUN chmod +x /usr/local/bin/init.sh

EXPOSE 3306

ENTRYPOINT ["init.sh"]
