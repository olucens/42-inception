# ---------------------------------------------------------------------------
# BONUS 3/5 — a static website.
#
# Subject: "Create a simple static website in the language of your choice except
# PHP (yes, PHP is excluded). For example, a showcase site or a site for
# presenting your resume."
#
# The site is plain HTML + CSS + a few lines of vanilla JS — no PHP anywhere,
# no build step, no framework, no runtime dependency to install.
#
# WHY NGINX SERVES IT. "Language of your choice" constrains the SITE, not the
# server. A static file server is exactly what NGINX is best at: sendfile()
# straight from page cache to socket, correct MIME types, conditional requests.
# The alternative — `python3 -m http.server` or a small Node server — would add
# an interpreter and a slower, single-threaded server to do strictly less.
#
# This is a SEPARATE nginx container from the mandatory one, with its own image,
# its own config and its own port. It is not a second service crammed into the
# existing container.
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends nginx \
    && rm -rf /var/lib/apt/lists/*

RUN rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default

COPY conf/nginx.conf /etc/nginx/nginx.conf

# The site itself. Baked into the image on purpose: it is immutable content that
# belongs to a version of the image, so it needs no volume. Contrast with
# WordPress, whose content is user data and therefore lives on a volume.
COPY site/ /var/www/static/

COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
