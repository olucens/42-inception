# ---------------------------------------------------------------------------
# BONUS 4/5 — Adminer, a web UI for the database.
#
# Subject: "Setup Adminer."
#
# WHAT IT IS. Adminer is phpMyAdmin's single-file replacement: one ~500 KB PHP
# script that gives you schema browsing, arbitrary SQL, and export/import.
# During a defence it is the fastest way to *show* that the WordPress tables
# exist and hold real data.
#
# NOTE ON "except PHP": that constraint belongs to the static-website bonus.
# Adminer is a PHP application by definition — the subject asks for Adminer by
# name, so PHP here is required, not a violation.
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive

# php-cli, not php-fpm. WHY: FPM speaks FastCGI, which needs a web server in
# front of it — that would mean either a second process in this container (and
# then a supervisor, and then PID 1 is no longer the service) or a whole extra
# NGINX container to front a single admin script. php-cli ships a built-in HTTP
# server that is one process and speaks HTTP directly.
#
# The honest trade-off: PHP's built-in server is single-threaded and documented
# as unsuitable for production. That is acceptable precisely here — a
# single-operator admin tool, on an unpublished-by-default internal port, used
# interactively for a few minutes. It would not be acceptable for the WordPress
# site itself, which is exactly why that one uses PHP-FPM behind NGINX.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        php8.2-cli \
        php8.2-mysql \
        curl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Pinned, like every other download in this project: an unpinned URL would make
# the image non-reproducible.
ARG ADMINER_VERSION=4.8.1
RUN mkdir -p /var/www/adminer && \
    curl -fsSL -o /var/www/adminer/index.php \
      "https://github.com/vrana/adminer/releases/download/v${ADMINER_VERSION}/adminer-${ADMINER_VERSION}.php"

COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /var/www/adminer

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
