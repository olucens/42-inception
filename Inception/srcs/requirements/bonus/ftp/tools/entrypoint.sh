#!/bin/bash
# ---------------------------------------------------------------------------
# FTP entrypoint: create the FTP user from a secret, point it at the WordPress
# volume, then exec vsftpd.
# ---------------------------------------------------------------------------
set -euo pipefail

log() { echo "[ftp-init] $*"; }

: "${FTP_USER:?FTP_USER is not set (check srcs/.env)}"
: "${FTP_PASV_ADDRESS:=127.0.0.1}"

WP_PATH="/var/www/html"

# The password is a secret, never an environment variable — an env var would be
# printed by `docker inspect`.
FTP_PASSWORD="$(cat /run/secrets/ftp_password)"

# --- Create the user --------------------------------------------------------
# Idempotent: the container is recreated on every `up`, and /etc/passwd lives in
# the container's writable layer, not on a volume, so the user must be created
# on each start — but a restart must not fail because it already exists.
if id "${FTP_USER}" >/dev/null 2>&1; then
    log "user '${FTP_USER}' already exists"
else
    log "creating ftp user '${FTP_USER}'"
    # --home the WordPress volume, so the user lands directly in the site root.
    # --shell /usr/sbin/nologin: FTP does not need a shell, and denying one
    # means a stolen password cannot become an interactive session.
    useradd --home-dir "${WP_PATH}" --no-create-home \
            --shell /usr/sbin/nologin "${FTP_USER}"
fi

# WHY /usr/sbin/nologin must be listed in /etc/shells:
# Debian's /etc/pam.d/vsftpd ends with `auth required pam_shells.so`, which
# rejects any user whose login shell is not in /etc/shells. Since we
# deliberately gave the FTP user a nologin shell, PAM refuses the login with a
# bare "530 Login incorrect" — no hint that the password was in fact correct.
#
# Whitelisting nologin here keeps the security property we wanted: the account
# still cannot open an interactive shell via ssh or su; it is only allowed to
# authenticate for FTP.
grep -qxF '/usr/sbin/nologin' /etc/shells || echo '/usr/sbin/nologin' >> /etc/shells

# chpasswd reads from stdin, so the password never appears in the process table
# the way `useradd -p` or `echo ... | ps` would expose it.
echo "${FTP_USER}:${FTP_PASSWORD}" | chpasswd

# The login whitelist referenced by userlist_file in vsftpd.conf.
echo "${FTP_USER}" > /etc/vsftpd.userlist

# --- Ownership --------------------------------------------------------------
# The WordPress volume is owned by www-data (uid 33) because PHP-FPM writes to
# it. Adding the FTP user to that group, plus g+w, lets both write the same
# files. Giving the FTP user ownership instead would break WordPress uploads.
usermod -aG www-data "${FTP_USER}"
chmod -R g+w "${WP_PATH}" 2>/dev/null || true

# --- Passive address --------------------------------------------------------
# Injected at runtime: the container has no way to learn the host's address, and
# a wrong value here makes every transfer hang while login still succeeds.
log "advertising passive address ${FTP_PASV_ADDRESS}"
sed -i "/^pasv_address=/d" /etc/vsftpd.conf
echo "pasv_address=${FTP_PASV_ADDRESS}" >> /etc/vsftpd.conf

# vsftpd needs this directory for its privilege-separation process.
mkdir -p /var/run/vsftpd/empty

# --- Route the log to the container's stdout --------------------------------
# /proc/1/fd/1 is PID 1's stdout — the stream Docker captures for
# `docker compose logs ftp`. Unlike /dev/stdout it does not depend on which
# process does the opening, so vsftpd's privilege-separated writer can use it.
# If the symlink cannot be created, fall back to a real file rather than
# leaving vsftpd unable to start.
if ln -sf /proc/1/fd/1 /var/log/vsftpd.log 2>/dev/null; then
    log "logging to container stdout"
else
    : > /var/log/vsftpd.log
    log "logging to /var/log/vsftpd.log (read with: docker exec ftp cat /var/log/vsftpd.log)"
fi

# --- Hand over to the daemon -----------------------------------------------
# With `listen=YES` and no `background=YES`, vsftpd stays in the foreground, so
# `exec` makes it PID 1.
log "starting vsftpd as PID 1"
exec /usr/sbin/vsftpd /etc/vsftpd.conf
