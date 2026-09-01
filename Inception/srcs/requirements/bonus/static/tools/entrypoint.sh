#!/bin/bash
set -euo pipefail
echo "[static-init] validating configuration"
nginx -t
mkdir -p /run/nginx
echo "[static-init] starting nginx as PID 1 on :8080"
# Same reasoning as the mandatory nginx: `daemon off;` keeps the master in the
# foreground so it stays PID 1 and receives SIGTERM directly.
exec nginx -g "daemon off;"
