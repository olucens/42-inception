# ---------------------------------------------------------------------------
# BONUS 1/5 — Redis, object cache for WordPress.
#
# Subject: "Setup redis cache for your WordPress website in order to properly
# manage the cache."
#
# WHAT PROBLEM THIS SOLVES. Every WordPress page view runs dozens of SQL
# queries — options, post meta, terms, user meta. WordPress already has an
# object cache, but by default it is *non-persistent*: it lives in PHP's memory
# and is thrown away when the request ends, so the next request repeats the same
# queries. A persistent object cache backend keeps those results between
# requests, in a store both PHP-FPM workers share.
#
# "Properly manage the cache" is the operative phrase, and it is about eviction,
# not about installing a plugin — see conf/redis.conf.
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends redis-server \
    && rm -rf /var/lib/apt/lists/*

COPY conf/redis.conf /etc/redis/redis.conf
COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Reachable only from inside inception-network; never published to the host.
EXPOSE 6379

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
