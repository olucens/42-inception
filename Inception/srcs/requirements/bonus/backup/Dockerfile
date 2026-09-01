# ---------------------------------------------------------------------------
# BONUS 5/5 — automated database backups. "A service of your choice."
#
# Subject: "Setup a service of your choice that you think is useful. During the
# defense, you will have to justify your choice."
#
# THE JUSTIFICATION (this is the part that gets asked):
#
# The mandatory stack protects against exactly one failure: losing a container.
# Named volumes survive `docker rm`, image rebuilds and restarts. They protect
# against nothing else.
#
#   * `make fclean` deletes the volumes. One keystroke, no confirmation.
#   * A bad UPDATE without a WHERE clause is faithfully persisted.
#   * A plugin or a botched WordPress upgrade corrupts tables — and the volume
#     dutifully keeps the corruption.
#   * The disk backing /home/akuzmin/data fails.
#
# A volume is redundancy against container loss. A backup is a copy at a POINT
# IN TIME, which is the only thing that survives a mistake. That is a different
# guarantee, and the stack did not have it.
#
# Rejected alternatives and why:
#   * Grafana/Prometheus — impressive, but this stack has one user and no
#     alerting story; it would be a dashboard nobody reads.
#   * Portainer — a ready-made image, forbidden here.
#   * A mail server — nothing in the stack sends mail.
# Backups win because the risk they remove is real, present, and one command away.
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive

# mariadb-client : provides mariadb-dump
# cron           : the scheduler; runs in the foreground with -f
# gzip           : SQL dumps compress ~10x
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        mariadb-client \
        cron \
        gzip \
    && rm -rf /var/lib/apt/lists/*

COPY tools/backup.sh /usr/local/bin/backup.sh
COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/backup.sh /usr/local/bin/entrypoint.sh

# Mount point of the dedicated backup-data volume. The subject says each bonus
# service gets its own volume "if necessary" — here it is necessary, and it must
# be a DIFFERENT volume from mariadb-data: a backup stored on the same volume as
# the data it protects is not a backup.
VOLUME ["/backups"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
