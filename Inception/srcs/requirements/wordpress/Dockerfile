# ---------------------------------------------------------------------------
# WordPress + PHP-FPM — the application tier.
#
# Subject: this container holds WordPress + php-fpm only.
# So there is NO web server in this image. It speaks FastCGI on port 9000 and
# nothing else. The web server is a separate container and a separate concern.
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive

# php8.2-fpm       — the FastCGI process manager (Debian 12 ships PHP 8.2)
# php8.2-mysql     — the mysqli/pdo_mysql driver WordPress needs to reach MariaDB
# gd/curl/xml/mbstring/zip — extensions WordPress core and most plugins require;
#                    without them the admin panel shows "missing extension" notices
# mariadb-client   — used ONLY by setup.sh to wait until the DB accepts queries;
#                    WP-CLI's `db` commands also need it
# curl, ca-certificates — to fetch WP-CLI over HTTPS at build time
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        php8.2-fpm \
        php8.2-mysql \
        php8.2-gd \
        php8.2-curl \
        php8.2-xml \
        php8.2-mbstring \
        php8.2-zip \
        mariadb-client \
        curl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# WP-CLI: the official WordPress command-line tool.
# WHY WP-CLI instead of clicking through the browser installer:
#   * the subject requires two users (one admin) to already exist in the
#     database — that has to happen unattended, without a human;
#   * the install must be idempotent and reproducible on a fresh volume;
#   * `wp core install` writes the same tables the web installer would.
# The version is pinned for the same reason image tags are pinned: a moving
# target breaks reproducibility.
ARG WP_CLI_VERSION=2.10.0
RUN curl -fsSL -o /usr/local/bin/wp \
      "https://github.com/wp-cli/wp-cli/releases/download/v${WP_CLI_VERSION}/wp-cli-${WP_CLI_VERSION}.phar" \
    && chmod +x /usr/local/bin/wp

# Our PHP-FPM pool config, replacing Debian's default www pool.
COPY conf/www.conf /etc/php/8.2/fpm/pool.d/www.conf

COPY tools/setup.sh /usr/local/bin/setup.sh
RUN chmod +x /usr/local/bin/setup.sh

# php-fpm writes its pid file to /run/php, and the directory must already exist.
RUN mkdir -p /run/php /var/www/html && chown -R www-data:www-data /var/www/html

WORKDIR /var/www/html

# Documentation only — 9000 is reachable from the web server over the bridge network and
# is never published to the host.
EXPOSE 9000

ENTRYPOINT ["/usr/local/bin/setup.sh"]
