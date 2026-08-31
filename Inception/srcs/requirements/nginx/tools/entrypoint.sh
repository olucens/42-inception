#!/bin/bash
# ---------------------------------------------------------------------------
# NGINX entrypoint.
#
# 1. renders nginx.conf from the template
# 2. generates a self-signed TLS certificate if there isn't one
# 3. execs nginx in the foreground as PID 1
# ---------------------------------------------------------------------------
set -euo pipefail

log() { echo "[nginx-init] $*"; }

: "${DOMAIN_NAME:?DOMAIN_NAME is not set (check srcs/.env)}"

CERT_DIR="/etc/nginx/ssl"
CERT="${CERT_DIR}/inception.crt"
KEY="${CERT_DIR}/inception.key"

# --- Render the configuration ----------------------------------------------
# WHY envsubst is given '${DOMAIN_NAME}' as an argument:
# with no argument, envsubst replaces EVERY $NAME it finds. The nginx config is
# full of nginx's own runtime variables — $uri, $args, $document_root,
# $fastcgi_script_name — which are meaningless to the shell and would all be
# replaced with empty strings, silently producing a broken config
# (`try_files  / /index.php?;`). Passing an explicit shell-format string
# restricts substitution to that one variable and leaves nginx's alone.
log "rendering nginx.conf for domain '${DOMAIN_NAME}'"
envsubst '${DOMAIN_NAME}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

# --- TLS certificate --------------------------------------------------------
# WHY self-signed: akuzmin.42.fr is a name in /etc/hosts, not a public domain,
# so no public CA can ever issue for it. The browser will show a warning — that
# is expected and correct. What matters for the subject is that the connection
# is genuinely TLS 1.2/1.3, which a self-signed certificate provides in full.
#
# WHY generated at RUNTIME and not baked into the image with a COPY:
# a private key committed to git — or baked into a layer that `docker history`
# can dump — is a leaked credential. Generating it on start-up means the key
# never exists outside the running container's filesystem.
if [ -f "${CERT}" ] && [ -f "${KEY}" ]; then
    log "certificate already present — reusing it"
else
    log "generating a self-signed TLS certificate for CN=${DOMAIN_NAME}"
    mkdir -p "${CERT_DIR}"

    # -x509      : output a self-signed certificate, not a CSR
    # -nodes     : do not encrypt the private key — nginx starts unattended and
    #              nobody is there to type a passphrase
    # -newkey rsa:2048 : generate a fresh key alongside the certificate
    # -addext subjectAltName : modern browsers ignore CN entirely and validate
    #              the name against the SAN extension; without it Chrome/Firefox
    #              report ERR_CERT_COMMON_NAME_INVALID rather than a plain
    #              "self-signed" warning
    openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout "${KEY}" \
        -out "${CERT}" \
        -subj "/C=FR/ST=Ile-de-France/L=Paris/O=42/OU=42-Inception/CN=${DOMAIN_NAME}" \
        -addext "subjectAltName=DNS:${DOMAIN_NAME},DNS:www.${DOMAIN_NAME}" \
        2>/dev/null

    # The private key must not be world-readable, even inside a container.
    chmod 600 "${KEY}"
    chmod 644 "${CERT}"
fi

# /run is a tmpfs, empty on every container start — nginx needs its pid dir.
mkdir -p /run/nginx

# Fail fast on a bad config: `nginx -t` parses and validates without binding
# any port. Better a clear syntax error in the logs than a crash-loop.
log "validating configuration"
nginx -t

# --- Hand over to the daemon -----------------------------------------------
# `daemon off;` keeps the master process in the foreground so it stays PID 1
# and receives SIGTERM/SIGQUIT from `docker stop` for a graceful shutdown.
# Without it nginx would fork, detach, and PID 1 would exit — killing the
# container. This is the legitimate alternative to a `tail -f` hack.
log "starting nginx as PID 1"
exec nginx -g "daemon off;"
