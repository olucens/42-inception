#!/bin/bash
# ---------------------------------------------------------------------------
# Redis entrypoint.
# ---------------------------------------------------------------------------
set -euo pipefail

echo "[redis-init] starting redis-server as PID 1 (maxmemory-policy=allkeys-lru)"

# `exec` so redis-server itself is PID 1 and receives SIGTERM from `docker stop`.
#
# The config file sets `daemonize no` by default in Debian's packaging; passing
# it explicitly makes the intent unmissable. Daemonising here would detach the
# server, PID 1 would exit, and the container would stop immediately — the same
# trap as nginx and php-fpm.
exec redis-server /etc/redis/redis.conf --daemonize no
