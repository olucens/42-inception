# ---------------------------------------------------------------------------
# MariaDB — the database tier. NOTHING else runs in this container.
#
# WHY debian:bookworm and not the ready-made "mariadb" image:
#   * Subject: "containers must be built either from the penultimate stable
#     version of Alpine or Debian". Debian stable today is 13 (trixie),
#     so the penultimate stable is 12 (bookworm).
#   * An unpinned tag is prohibited by the subject and makes the build
#     non-reproducible: the same Dockerfile would produce a different image
#     next month.
#   * Subject: "it is forbidden to pull ready-made Docker images" — so we
#     install the mariadb-server package into a bare OS ourselves, instead of
#     using the official `mariadb:` image.
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim

# WHY one single RUN and `rm -rf /var/lib/apt/lists/*` in the SAME layer:
# every RUN creates a new read-only layer. Deleting a file in a later layer
# does not shrink the earlier one — the bytes stay in the image forever. The
# apt index is ~40 MB, so it has to be removed inside the layer that created it.
#
# WHY --no-install-recommends: apt would otherwise pull in dozens of optional
# packages (a mail transfer agent, docs). Smaller image = smaller attack surface.
#
# WHY DEBIAN_FRONTEND=noninteractive as an ARG and not an ENV: `docker build`
# has no TTY, so debconf must not try to prompt. Using ARG keeps the variable
# out of the final image's environment (an ENV would leak into every process).
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        mariadb-server \
        mariadb-client \
    && rm -rf /var/lib/apt/lists/*

# CRITICAL, and the single most common bug in this project.
#
# Debian's mariadb-server postinst runs mysql_install_db at BUILD time, leaving
# ~113 MB of system tables baked into the image at /var/lib/mysql.
#
# When a container starts, Docker seeds an EMPTY named volume with whatever the
# image has at the mount point. The volume would then start with system tables
# created at build time, not by tools/init.sh, with a root account nobody set up.
#
# Emptying the directory here makes a fresh volume genuinely empty, so init.sh
# runs mysql_install_db itself, at RUNTIME, against the real volume.
RUN rm -rf /var/lib/mysql/* && \
    mkdir -p /var/lib/mysql && \
    chown -R mysql:mysql /var/lib/mysql

# Our server config. Debian's package reads every file in mariadb.conf.d/,
# and 50-server.cnf is the one it ships — overwriting it replaces its defaults.
COPY conf/mariadb.cnf /etc/mysql/mariadb.conf.d/50-server.cnf

# WHY the init script instead of just CMD ["mysqld"]: on the very first start
# the named volume at /var/lib/mysql is empty — there are no system tables, no
# database, no users. The script creates them once, then hands over to mysqld.
COPY tools/init.sh /usr/local/bin/init.sh
RUN chmod +x /usr/local/bin/init.sh

# WHY EXPOSE and not `ports:`: EXPOSE is pure metadata (documentation +
# `docker inspect`). It does NOT publish anything to the host. MariaDB must be
# reachable ONLY from the WordPress container over the internal bridge network.
EXPOSE 3306

# WHY ENTRYPOINT in exec form (JSON array) and not shell form:
# shell form would run `/bin/sh -c "init.sh"`, making /bin/sh PID 1. PID 1 is
# the process Docker sends SIGTERM to on `docker stop`, and /bin/sh does not
# forward signals to its children -> mysqld would be SIGKILLed after 10s
# without flushing to disk. Exec form makes our script PID 1, and the script
# ends with `exec mysqld` so mysqld itself inherits PID 1.
ENTRYPOINT ["/usr/local/bin/init.sh"]
