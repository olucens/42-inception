*This project has been created as part of the 42 curriculum by akuzmin.*

# Inception

A small, self-contained web infrastructure — NGINX, WordPress + PHP-FPM and
MariaDB — each in its own container, built from scratch and orchestrated with
Docker Compose. No ready-made application image is used anywhere.

## Description

The goal is to run a working WordPress site behind TLS, where every layer is
built by hand from a bare Debian base, so that nothing about the stack is
opaque.

Eight services on this branch: the three mandatory tiers, plus the five bonus
services. The mandatory part is unchanged and still stands on its own — the
subject only assesses bonuses once the mandatory part is perfect.

```
                    host :443
                        |
             (only published port)
                        |
        ┌───────────────▼───────────────┐
        │  nginx           TLS 1.2/1.3  │   serves static files itself,
        │  debian bookworm + nginx      │   forwards *.php over FastCGI
        └───────────────┬───────────────┘
                        │  fastcgi  wordpress:9000
        ┌───────────────▼───────────────┐
        │  wordpress                    │   PHP-FPM only. No web server.
        │  debian bookworm + php8.2-fpm │   Installed by WP-CLI on first run.
        └───────────────┬───────────────┘
                        │  mysql  mariadb:3306
        ┌───────────────▼───────────────┐
        │  mariadb                      │   No published port. Reachable
        │  debian bookworm + mariadb    │   only from inside the network.
        └───────────────────────────────┘

  volumes (named, backed by /home/akuzmin/data):
    mariadb-data    -> mariadb:/var/lib/mysql
    wordpress-data  -> wordpress:/var/www/html   (rw)
                       nginx:/var/www/html       (ro)
                       ftp:/var/www/html         (rw)   [bonus]
    backup-data     -> backup:/backups                  [bonus]
```

### Bonus services

| Service | Port | What it does | Volume |
|---|---|---|---|
| **redis** | — | Persistent object cache for WordPress. `allkeys-lru` eviction, no persistence. | none — every value is derivable from MariaDB |
| **ftp** | 21 + 21100-21110 | vsftpd onto the WordPress volume, chrooted to the site root. | shares `wordpress-data` |
| **static** | 8080 | A static showcase site — plain HTML/CSS/JS, no PHP. Its own NGINX. | none — immutable content, baked into the image |
| **adminer** | 8081 | Web UI for inspecting the database. | none — holds no state |
| **backup** | — | Scheduled `mariadb-dump`, gzipped and rotated. The "service of your choice". | `backup-data`, deliberately separate from `mariadb-data` |

Three of the five have no volume, and that is the point of the subject's phrase
"if necessary": a cache, an immutable site and a stateless UI do not need one.
Only `backup` does — and it must be a *different* volume from the database it
protects, or it is not a backup.

**Why a backup service was chosen as the free slot.** The mandatory stack
protects against exactly one failure — losing a container. Volumes survive
`docker rm`, rebuilds and restarts, and nothing else. They do not protect against
`make fclean`, an `UPDATE` without a `WHERE`, a bad plugin corrupting tables, or
the disk failing. A volume is redundancy; a backup is a copy at a point in time,
which is the only thing that survives a mistake.

Ports 3306 and 9000 are `expose`d, never published: they exist only on
`inception-network`. NGINX on 443 is the single way in.

## Instructions

Requires a Linux host (or VM) with Docker Engine and the Compose v2 plugin.

```bash
# 1. configuration
cp srcs/.env.example srcs/.env      # edit DOMAIN_NAME and the WordPress names

# 2. secrets (never committed — see DEV_DOC.md)
mkdir -p secrets
openssl rand -base64 24 > secrets/db_root_password.txt
openssl rand -base64 24 > secrets/db_password.txt
printf 'WP_ADMIN_PASSWORD=%s\nWP_USER_PASSWORD=%s\n' \
    "$(openssl rand -base64 18)" "$(openssl rand -base64 18)" > secrets/credentials.txt
chmod 600 secrets/*.txt

# 3. domain resolution
echo "127.0.0.1 akuzmin.42.fr" | sudo tee -a /etc/hosts

# 4. build and start everything
make
```

Then open <https://akuzmin.42.fr>. The certificate is self-signed, so the
browser shows a warning — that is expected (see "Technical choices").

The bonus services are at <http://localhost:8080> (static site) and
<http://localhost:8081> (Adminer, log in with `MYSQL_USER` against server
`mariadb`). FTP is on port 21 as `FTP_USER`.

Note the bonus adds a fourth secret:

```bash
openssl rand -base64 18 > secrets/ftp_password.txt && chmod 600 secrets/ftp_password.txt
```

| Command | Effect |
|---|---|
| `make` | build images and start the stack |
| `make down` | stop and remove containers; **data survives** |
| `make clean` | the above, plus remove the locally built images |
| `make fclean` | the above, plus delete the volumes and `/home/akuzmin/data` |
| `make re` | `fclean` then `make` — a true from-scratch rebuild |
| `make logs` / `make ps` | follow logs / show container state |
| `make tls-test` | prove TLS 1.0/1.1 are refused and 1.2/1.3 accepted |
| `make redis-status` | show the object cache is connected, with hit/miss counters |
| `make backups` | list the dumps taken so far |
| `make backup-now` | take a dump immediately instead of waiting for the schedule |

User-facing details are in [USER_DOC.md](USER_DOC.md); setup and internals in
[DEV_DOC.md](DEV_DOC.md).

## Project description

### Use of Docker and the sources in this project

Each service is a directory under `srcs/requirements/` holding a `Dockerfile`,
a `conf/` directory with that service's configuration, and a `tools/` directory
with its entrypoint script. `srcs/docker-compose.yml` wires them together;
`Makefile` at the root drives Compose.

Every entrypoint follows the same shape, and it is the shape that matters:

1. read secrets from `/run/secrets/`,
2. do first-run setup, guarded so a restart is a no-op,
3. `exec` the real daemon, so the daemon — not the shell — becomes PID 1.

PID 1 is the process the kernel delivers `SIGTERM` to when Docker stops the
container. A shell left in that slot does not forward signals, so the daemon
gets `SIGKILL`ed after the grace period and a database can be killed mid-write.
`exec` replaces the shell image with the daemon's, keeping the same PID. This is
also why none of these containers needs `tail -f`, `sleep infinity` or
`while true`: a real foreground daemon already keeps the container alive.

### Main design choices

- **Debian bookworm (12), pinned.** Debian 13 (trixie) is current stable, so 12
  is the penultimate stable the subject asks for. `latest` is forbidden and, more
  practically, would make the build non-reproducible.
- **NGINX serves static files directly, PHP-FPM only sees `.php`.** Handing an
  image to PHP would be pure overhead.
- **The WordPress volume is mounted read-only in NGINX.** NGINX never needs to
  write, and a compromised NGINX then cannot drop a `.php` file for FPM to run.
- **WordPress is installed at runtime by WP-CLI, not baked into the image.**
  `/var/www/html` is a volume mount point: anything the image put there is
  hidden the moment the volume is mounted over it.
- **The certificate is generated on start-up, not committed.** `akuzmin.42.fr`
  resolves through `/etc/hosts`, so no public CA could ever sign it, and a
  private key in git is a leaked credential.
- **`restart: on-failure`, not `always`.** It restarts a crash but respects a
  deliberate `docker compose stop`.
- **The bonus never weakens the mandatory part.** The extra published ports are
  explicitly permitted ("you may open more ports to suit your needs"), and none
  of them is a second route to the WordPress site — NGINX on 443 is still the
  only way in. Redis and the backup service publish nothing at all.
- **A failing bonus must not take the stack down.** WordPress treats a missing
  Redis as non-fatal and serves uncached; the backup service logs and lets cron
  retry. A cache that can break the site is worse than no cache.

### Virtual Machines vs Docker

A VM virtualises *hardware*: the hypervisor presents virtual CPUs, disks and
NICs, and a complete guest OS with its own kernel boots on top. A container
virtualises the *process view of one kernel*: `namespaces` give a process its own
PID/network/mount/UTS/IPC/user view, `cgroups` cap what it may consume, and an
overlay filesystem gives it its own root filesystem. Containers share the host
kernel.

The consequences follow directly. A container starts in milliseconds and costs a
few MB, because nothing boots — it is one process in a different view of the same
running kernel. A VM takes tens of seconds and hundreds of MB. But the isolation
boundary of a VM is the hypervisor, and of a container the *kernel's syscall
interface* — which is a far larger attack surface, so a kernel escape breaks out
of a container. And a container cannot run a different kernel: Linux containers
on macOS or Windows are really running inside a hidden Linux VM.

For this project, containers are the right tool: three services that must start
fast, be rebuilt constantly, and be described entirely by files in git.

### Secrets vs Environment variables

Environment variables are the standard way to configure a container, but they
leak by design. `docker inspect <container>` prints them, `docker compose config`
prints them, every child process inherits them and exposes them in
`/proc/<pid>/environ`, and if set with `ENV` in a Dockerfile they are baked into
an image layer that `docker history` can recover.

A Docker secret is a file mounted read-only under `/run/secrets/<name>` — in
Swarm on an in-memory tmpfs, in Compose as a read-only bind mount of a host file.
It appears in none of those places. The file itself lives in `secrets/`, which is
git-ignored; only a `.example` template is committed.

This project splits on exactly that line: `srcs/.env` holds non-confidential
configuration (domain, database name, usernames), and every password lives in
`secrets/`. The subject is blunt about the stakes — credentials found in the git
repository "will result in project failure".

### Docker Network vs Host Network

With `network_mode: host` a container shares the host's network namespace: no
veth pair, no NAT, no isolation. Every port a service opens is immediately open
on the host, `localhost` means the host's loopback, and two containers cannot
both bind 3306.

A user-defined bridge — `inception-network` here — gives each container its own
network namespace and a veth pair into a virtual switch. Two things follow that
this project depends on:

1. **Embedded DNS.** Docker runs a resolver at `127.0.0.11` that resolves
   *service names*. This is why `fastcgi_pass wordpress:9000` and
   `MYSQL_HOST=mariadb` work without knowing an IP and without the obsolete,
   forbidden `links:`.
2. **A real boundary.** Only what is listed under `ports:` reaches the host. 3306
   and 9000 are `expose`d and therefore unreachable from outside the network.

Host networking would destroy both properties and hand the database a publicly
bound port.

### Docker Volumes vs Bind Mounts

A container's writable layer dies with the container, so persistent data needs
storage that outlives it.

A **bind mount** attaches an arbitrary host path into a container. It is not a
Docker object: `docker volume ls` does not show it, `docker volume rm` cannot
remove it, its ownership and SELinux labels come from the host, and it silently
creates the path if missing. It is ideal for injecting source code during
development, and a poor fit for production data.

A **named volume** is a first-class Docker object with a name, a driver and a
lifecycle. Docker creates it, seeds it from the image on first use, lists it,
prunes it, and can back it with a plugin driver (NFS, cloud block storage).

This project must satisfy two rules at once: named volumes only, *and* the data
must live in `/home/akuzmin/data`. The way to do both is the `local` driver with
`type: none, o: bind, device: …` — a genuine named volume whose backing store is
a chosen host directory:

```yaml
volumes:
  mariadb-data:
    driver: local
    driver_opts: { type: none, o: bind, device: /home/akuzmin/data/mariadb }
```

Written instead as `- /home/akuzmin/data/mariadb:/var/lib/mysql` under a service,
it would be a plain bind mount — no volume object, invisible to `docker volume
ls` — which is what the subject forbids. Because `o: bind` binds an *existing*
directory, `make setup` creates it before `up`.

## Resources

Documentation and references used:

- Inception subject v5.3 — `materials-inception/inception-subject.pdf`
- Docker docs — [Dockerfile reference](https://docs.docker.com/reference/dockerfile/),
  [Compose file reference](https://docs.docker.com/reference/compose-file/),
  [networking](https://docs.docker.com/engine/network/),
  [volumes](https://docs.docker.com/engine/storage/volumes/),
  [secrets in Compose](https://docs.docker.com/compose/how-tos/use-secrets/)
- [MariaDB Knowledge Base — mysql_install_db](https://mariadb.com/kb/en/mysql_install_db/),
  [server system variables](https://mariadb.com/kb/en/server-system-variables/)
- [PHP-FPM configuration](https://www.php.net/manual/en/install.fpm.configuration.php)
- [NGINX docs](https://nginx.org/en/docs/) — `ngx_http_ssl_module`, `ngx_http_fastcgi_module`
- [WP-CLI command reference](https://developer.wordpress.org/cli/commands/)
- [Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org/) — cipher suite selection
- Man pages: `namespaces(7)`, `cgroups(7)`, `pid_namespaces(7)`, `unshare(1)`, `signal(7)`

### Use of AI

AI (Claude) was used on this project for:

- **Reviewing and explaining**, not authoring blind: producing the annotated
  rationale in `materials-inception/solutions/core-explained.md`, and the
  self-assessment material in `materials-inception/eval/`.
- **Debugging**, by reading logs and forming hypotheses. Six defects in this
  code were found this way — three in the mandatory part and three in the bonus —
  and all are documented in the rationale files. In the mandatory part: the
  `mariadb-server` package pre-seeding `/var/lib/mysql` inside the image (which
  made Docker seed the "empty" volume and caused first-run setup to be skipped);
  `MYSQL_HOST` from `.env` hijacking the local MariaDB client's transport so
  `--protocol=socket` was ignored; and `http2 on;` being invalid on the nginx
  1.22 that bookworm ships. In the bonus: vsftpd refusing every connection
  because a privilege-separated process cannot open `/dev/stdout`; PAM's
  `pam_shells.so` rejecting the FTP login because the account's `nologin` shell
  was not in `/etc/shells`; and the backup service racing MariaDB's cold start
  and then not retrying until 03:00.
- **Not** used to generate configuration that was then accepted untested. Every
  claim in these documents was checked against a running stack — TLS version
  enforcement with `openssl s_client`, PID 1 with `/proc/1/comm`, persistence by
  creating a post and cycling `down`/`up`, and port isolation from the host.

The learning material in `materials-inception/` was written with AI assistance as
a study aid; the verification checklists there are designed to be run by hand,
without AI, precisely so understanding can be tested independently.
