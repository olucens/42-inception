# ---------------------------------------------------------------------------
# BONUS 2/5 — FTP server (vsftpd) onto the WordPress volume.
#
# Subject: "Setup a FTP server container pointing to the volume of your
# WordPress website."
#
# WHAT IT IS FOR. It gives file-level access to the site: uploading a theme,
# pulling a copy of wp-content, fixing a file WordPress cannot edit itself.
# It mounts the SAME named volume as WordPress and NGINX, so a file dropped
# here is served immediately.
#
# vsftpd = "very secure FTP daemon": privilege separation, chroot per user, and
# a small codebase. Debian ships it, so no third-party download is needed.
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends vsftpd \
    && rm -rf /var/lib/apt/lists/*

COPY conf/vsftpd.conf /etc/vsftpd.conf
COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 21 is the control channel. 21100-21110 is the passive DATA range configured in
# vsftpd.conf — see the entrypoint for why passive mode is mandatory here.
EXPOSE 21 21100-21110

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
