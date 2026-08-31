# ---------------------------------------------------------------------------
# NGINX — the TLS termination point and the ONLY entry point.
#
# Subject: "Your NGINX container must be the only entry point into your
# infrastructure via the port 443 only, using the TLSv1.2 or TLSv1.3 protocol."
# It is therefore the only service in docker-compose.yml with a `ports:` key.
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive

# nginx        — the reverse proxy / FastCGI client / static file server
# openssl      — to generate the self-signed certificate at runtime
# gettext-base — provides envsubst, used to inject DOMAIN_NAME into the config
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        nginx \
        openssl \
        gettext-base \
    && rm -rf /var/lib/apt/lists/*

# WHY a .template and not a finished nginx.conf:
# server_name and the certificate CN must both be the domain from srcs/.env.
# nginx.conf has no variable expansion of its own, so the entrypoint renders the
# template with envsubst at start-up. Hardcoding "akuzmin.42.fr" would mean the
# image only works for one login — a config file, not a configurable image.
COPY conf/nginx.conf.template /etc/nginx/nginx.conf.template

COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Debian's package leaves a default vhost that would answer on port 80 and
# shadow ours. Port 80 must not serve anything — 443 only.
RUN rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default

# 443 only. Port 80 is deliberately absent: the subject allows exactly one way in.
EXPOSE 443

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
