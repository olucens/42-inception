*This project has been created as part of the 42 curriculum by akuzmin.*

# Inception

A small, self-contained web infrastructure — NGINX, WordPress + PHP-FPM and
MariaDB — each in its own container, built from scratch and orchestrated with
Docker Compose. No ready-made application image is used anywhere.

## Description

The goal is to run a working WordPress site behind TLS, where every layer is
built by hand from a bare Debian base, so that nothing about the stack is
opaque.

Three services, three containers, one private bridge network:

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
```

Ports 3306 and 9000 are `expose`d, never published: they exist only on
`inception-network`. NGINX on 443 is the single way in.

## Instructions

Requires a Linux host (or VM) with Docker Engine and the Compose v2 plugin.

```bash
# 1. create srcs/.env and random secrets (never committed - see DEV_DOC.md)
make init

# 2. domain resolution
echo "127.0.0.1 akuzmin.42.fr" | sudo tee -a /etc/hosts

# 3. build and start everything; returns when the site is ready
make
```

Then open <https://akuzmin.42.fr>. The certificate is self-signed, so the
browser shows a warning — that is expected (see "Technical choices").

| Command | Effect |
|---|---|
| `make init` | create `srcs/.env` and any missing secret; never overwrites |
| `make` | build images and start the stack, wait until it is healthy |
| `make down` | stop and remove containers; **data survives** |
| `make clean` | the above, plus remove the locally built images |
| `make fclean` | the above, plus delete the volumes and their data (asks for `sudo`) |
| `make re` | `fclean` then `make` — a true from-scratch rebuild |
| `make logs` / `make ps` | follow logs / show container state |
| `make tls-test` | prove TLS 1.0/1.1 are refused and 1.2/1.3 accepted |

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
  Docker seeds an empty volume from the image only once, so a rebuilt image could
  never update a volume that already has files. Each install step checks its own
  result, so a run interrupted halfway simply continues on restart.
- **MariaDB is initialised with `mysqld --bootstrap`.** It runs the SQL in the
  foreground and exits, with no background process and no open port while root
  still has no password.
- **The certificate is generated on start-up, not committed.** `akuzmin.42.fr`
  resolves through `/etc/hosts`, so no public CA could ever sign it, and a
  private key in git is a leaked credential.
- **`restart: unless-stopped`.** It restarts after any unexpected exit but respects
  a deliberate `docker stop`. `on-failure` would miss a daemon that ended with
  exit code 0, and for a long-running service that is an outage as well.
- **Healthchecks with `condition: service_healthy`.** A bare `depends_on` only
  orders container start. With healthchecks, `make` returns when the site answers.

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
   `WP_DB_HOST=mariadb` work without knowing an IP and without the obsolete,
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
directory, `make` creates it before `up`.

## Resources

Documentation and references used:

- Inception subject v5.3 (42 intranet)
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

- **Writing and reviewing** Dockerfiles, configuration and entrypoint scripts,
  and drafting this documentation.
- **Auditing** the project against the subject and the evaluation scale, on a
  throwaway test environment. This found, for example, the background `mysqld`
  in the MariaDB entrypoint (now `--bootstrap`) and a redirect loop on non-default
  ports caused by `HTTP_HOST` losing its port.
- **Debugging**, by reading logs and forming hypotheses: the `mariadb-server`
  package pre-seeding `/var/lib/mysql` in the image, and `http2 on;` being invalid
  on the nginx 1.22 that bookworm ships.
- **Study material**: explanations and self-assessment questions used to learn the
  topics in this project.

AI output was tested on a running stack and reviewed before being kept: TLS with
`openssl s_client`, PID 1 with `/proc/1/comm`, persistence across a restart, and
port isolation from the host.
