# Docker Internals: How Docker Works Under the Hood

> Goal: understand Docker deeply enough that you could implement a basic container runtime yourself.
> References to Linux kernel features you can verify on your own system.

---

## The Big Picture

Docker is NOT magic. It is a user-friendly API over three Linux kernel primitives:

```
┌─────────────────────────────────────────────────────────┐
│                    docker CLI                           │
│                    docker compose                       │
└──────────────────────┬──────────────────────────────────┘
                       │ REST API (unix:///var/run/docker.sock)
┌──────────────────────▼──────────────────────────────────┐
│                  dockerd (Docker daemon)                 │
│              - image management                         │
│              - container lifecycle                      │
│              - networking, volumes                      │
└──────────────────────┬──────────────────────────────────┘
                       │ gRPC
┌──────────────────────▼──────────────────────────────────┐
│                   containerd                            │
│       (OCI-compliant container runtime manager)         │
└──────────────────────┬──────────────────────────────────┘
                       │ executes via
┌──────────────────────▼──────────────────────────────────┐
│                      runc                               │
│      (OCI runtime — actually calls kernel syscalls)     │
│                                                         │
│  ┌────────────────────────────────────────────────────┐ │
│  │             Linux Kernel                           │ │
│  │  Namespaces │ cgroups │ OverlayFS │ netfilter      │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

---

## 1. Linux Namespaces — Isolation

Namespaces make a process think it's alone in the system. Each namespace type isolates a different resource.

### 1.1 PID Namespace

**What it does:** Processes in a container have their own PID numbering starting from 1.

```bash
# On the host, your NGINX might be PID 4721
# Inside the NGINX container, the same process is PID 1

# Verify: inside the container
ps aux
# PID 1 = nginx master process

# On the host, find the real PID
docker inspect nginx | grep Pid
# "Pid": 4721
```

**Why it matters:** PID 1 is special — it receives signals (SIGTERM, SIGKILL) that stop the container. It must handle them correctly. If PID 1 dies, the container dies. This is why `tail -f` is banned — it becomes PID 1 but doesn't actually run your service.

**How to create one yourself:**
```bash
# unshare creates a new namespace
sudo unshare --pid --fork --mount-proc /bin/bash
# Now you're in a new PID namespace — bash is PID 1
echo $$   # outputs: 1
```

### 1.2 Network Namespace

**What it does:** Each container gets its own network stack: its own interfaces, routing tables, iptables rules, ports.

```
Host network namespace:
  eth0: 192.168.1.100
  lo: 127.0.0.1
  docker0: 172.17.0.1      ← Docker bridge

Container nginx network namespace:
  eth0: 172.17.0.2         ← veth pair endpoint
  lo: 127.0.0.1
  (no access to host eth0)
```

**veth pairs:** Docker creates a virtual ethernet pair — like a virtual cable. One end goes into the container's network namespace, the other attaches to the docker0 bridge on the host.

```bash
# See veth interfaces on the host
ip link show | grep veth

# See the bridge
ip addr show docker0

# See routing
ip route
```

**Port publishing:** When you do `-p 443:443`, Docker adds an iptables NAT rule that redirects traffic from host port 443 to the container's IP:443.

```bash
# See these rules
sudo iptables -t nat -L -n
# You'll see DOCKER chain with DNAT rules
```

### 1.3 Mount Namespace

**What it does:** Each container has its own filesystem view. The container sees only its image layers + any mounted volumes.

```
Container's view:             Host's view:
/                             /var/lib/docker/overlay2/abc123/merged/
├── bin/                      ← combined view of all image layers
├── etc/
├── var/
│   └── lib/mysql/            ← mounted from named volume
└── run/
    └── secrets/              ← Docker secrets mounted here
```

### 1.4 UTS Namespace

**What it does:** Containers have their own hostname and domain name.

```bash
# Inside container
hostname   # outputs: container_name

# On host
hostname   # outputs: your-vm
```

### 1.5 IPC Namespace

**What it does:** Isolates System V IPC (shared memory, semaphores, message queues) between containers. Prevents inter-container shared memory by default.

### 1.6 User Namespace

**What it does:** Maps container UIDs to host UIDs. Can run container "as root" (UID 0) inside while mapping to a non-privileged UID on the host.

```bash
# Enable rootless Docker using user namespaces
# UID 0 inside container → UID 100000 on host
```

**Why it matters for security:** Without user namespaces, root in the container is root on the host (if they escape). With user namespaces, escaping still only gives you an unprivileged UID.

### Summary Table

| Namespace | Isolates | Created with |
|-----------|----------|--------------|
| PID | Process IDs | `CLONE_NEWPID` |
| Net | Network stack | `CLONE_NEWNET` |
| Mount | Filesystem mounts | `CLONE_NEWNS` |
| UTS | Hostname | `CLONE_NEWUTS` |
| IPC | SysV IPC | `CLONE_NEWIPC` |
| User | UID/GID mapping | `CLONE_NEWUSER` |
| Cgroup | cgroup root | `CLONE_NEWCGROUP` |

**Verify a running container's namespaces:**
```bash
# Get container PID on host
docker inspect --format '{{.State.Pid}}' nginx

# See its namespaces
ls -la /proc/<PID>/ns/
# lrwxrwxrwx 1 root root ... net -> net:[4026531992]
# lrwxrwxrwx 1 root root ... pid -> pid:[4026532099]
# etc.
```

---

## 2. Control Groups (cgroups) — Resource Limiting

cgroups limit, account for, and isolate resource usage. Without them, one container could consume all host RAM and kill the system.

### 2.1 What cgroups control

- **CPU**: limit to N% of a core, or N CPU shares
- **Memory**: hard limit on RAM + swap usage
- **Block I/O**: limit disk read/write throughput
- **Network**: (via tc/netfilter, not pure cgroups)
- **PIDs**: maximum number of processes

### 2.2 Where cgroups live on disk

```
# cgroups v1 (older)
/sys/fs/cgroup/memory/docker/<container_id>/
/sys/fs/cgroup/cpu/docker/<container_id>/

# cgroups v2 (unified, modern Linux)
/sys/fs/cgroup/system.slice/docker-<container_id>.scope/
```

```bash
# See cgroup for a container
docker inspect --format '{{.HostConfig.CgroupParent}}' nginx

# See memory limit
cat /sys/fs/cgroup/memory/docker/<container_id>/memory.limit_in_bytes

# See CPU shares
cat /sys/fs/cgroup/cpu/docker/<container_id>/cpu.shares
```

### 2.3 Docker Compose resource limits

```yaml
services:
  wordpress:
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
```

### 2.4 How runc applies cgroups

When `runc` creates a container, it:
1. Creates a new cgroup directory
2. Writes limits to the cgroup files
3. Writes the container PID into `cgroup.procs`
4. All child processes of that PID inherit the same cgroup

---

## 3. OverlayFS — The Layered Filesystem

This is how Docker images become efficient. Without layers, every image would be a full copy of the OS.

### 3.1 Layer concept

A Docker image is a stack of read-only layers. When you pull `debian:bookworm`:

```
Layer 4: ca-certificates update       ← top (most recent)
Layer 3: apt-get upgrade
Layer 2: /etc/debian_version
Layer 1: base debian rootfs           ← bottom
```

Each layer only stores the DIFF from the layer below it. This means:
- `debian:bookworm` and `debian:bullseye` can share base layers
- Pulling a new image that shares layers with existing ones is fast
- Stored efficiently on disk

### 3.2 OverlayFS mechanics

OverlayFS merges multiple directories into a single view:

```
lower (read-only image layers)
upper (read-write container layer)
work  (OverlayFS internal)
─────────────────────────────────
merged (what the container sees)
```

```bash
# See overlay mounts for a running container
docker inspect --format '{{.GraphDriver}}' <container>
# {"Data": {"LowerDir": "/var/lib/docker/overlay2/.../diff",
#            "MergedDir": "/var/lib/docker/overlay2/.../merged",
#            "UpperDir": "/var/lib/docker/overlay2/.../diff",
#            "WorkDir": "/var/lib/docker/overlay2/.../work"}}

# See on filesystem
ls /var/lib/docker/overlay2/
```

### 3.3 Copy-on-Write (CoW)

When a container modifies a file from a lower layer:
1. OverlayFS copies the file from the lower layer to the upper layer
2. The modification is made in the upper layer
3. The lower layer is unchanged
4. The container sees the modified version (upper layer takes precedence)

**Consequence:** A tiny config change to a 100MB file copies 100MB to the upper layer. This is why you should keep file modifications small in containers and put large mutable data on volumes.

### 3.4 Where image data is stored

```bash
/var/lib/docker/
├── image/
│   └── overlay2/
│       ├── imagedb/         # image metadata
│       └── layerdb/         # layer checksums
├── overlay2/                # actual layer data
│   ├── <sha256>/
│   │   ├── diff/            # the layer's files
│   │   ├── link             # short ID symlink
│   │   └── lower            # parent layer references
│   └── ...
└── containers/
    └── <container_id>/
        ├── config.v2.json   # container config
        └── ...
```

---

## 4. Container Runtime Stack

### 4.1 The full call chain for `docker run`

```
docker run nginx
    │
    ▼
docker CLI → REST API → /var/run/docker.sock
    │
    ▼
dockerd (Docker daemon)
  - Checks if image exists locally
  - Pulls if needed (registry API)
  - Creates container config
  - Calls containerd via gRPC
    │
    ▼
containerd
  - Manages container lifecycle
  - Calls containerd-shim
    │
    ▼
containerd-shim
  - Stays alive to collect exit code
  - Calls runc
    │
    ▼
runc
  - Creates namespaces (clone syscall with CLONE_NEW* flags)
  - Sets up cgroups
  - Mounts the container rootfs (OverlayFS)
  - Pivots root (pivot_root syscall)
  - Executes the container's entrypoint as PID 1
    │
    ▼
Your process (nginx, php-fpm, mysqld) as PID 1
```

### 4.2 Why this layered architecture?

- **dockerd**: user-facing features (images, volumes, networking, compose)
- **containerd**: OCI-standard lifecycle management, can be used without Docker
- **runc**: minimal — just creates the container. Nothing else. Can be replaced (e.g., gVisor's `runsc` for extra sandboxing)

### 4.3 OCI Specification

OCI (Open Container Initiative) defines two standards:
1. **Image Spec**: how to package a container image (layers, manifest, config)
2. **Runtime Spec**: what a container runtime must do (filesystem bundle + `config.json`)

This means: any OCI-compliant runtime can run OCI images. Docker images work with Podman, containerd, etc.

---

## 5. Docker Networking Internals

### 5.1 Default bridge (docker0)

```
Host:
  eth0: 192.168.1.100      ← real NIC
  docker0: 172.17.0.1      ← Docker's virtual bridge
    ├── veth0abc → container1 eth0 (172.17.0.2)
    ├── veth1def → container2 eth0 (172.17.0.3)
    └── veth2ghi → container3 eth0 (172.17.0.4)
```

**How packets flow from container1 to container2:**
1. container1 sends to 172.17.0.3
2. Packet goes through veth0abc
3. Exits on docker0 bridge
4. Bridge forwards to veth1def (same subnet)
5. container2 receives on its eth0

### 5.2 Custom bridge (what Inception uses)

A custom bridge network (`docker network create --driver bridge inception-network`) provides:
- **Automatic DNS**: containers can reach each other by container_name or service name
- **Isolation**: containers on different custom networks can't communicate
- **No legacy link feature**: clean, modern approach

```bash
# Inside the NGINX container, this works:
ping mariadb     # resolves to MariaDB container IP
curl wordpress:9000  # reaches WordPress PHP-FPM
```

The DNS resolution is handled by an embedded DNS server in dockerd (127.0.0.11 inside containers).

### 5.3 Port publishing (iptables)

When you publish port 443:

```
# Docker adds iptables rules:
iptables -t nat -A DOCKER -p tcp --dport 443 -j DNAT --to-destination 172.17.0.2:443
iptables -A DOCKER -d 172.17.0.2/32 -p tcp --dport 443 -j ACCEPT

# Traffic path:
External → host:443 → iptables DNAT → container_ip:443
```

```bash
# See Docker's iptables rules
sudo iptables -t nat -L DOCKER -n -v
sudo iptables -L DOCKER -n -v
```

### 5.4 What `network: host` does (and why it's FORBIDDEN)

With `network: host`, the container shares the host's network namespace entirely. There is no isolation — the container can bind to any host port, see all host network traffic. This is a security risk and defeats the purpose of containerization.

### 5.5 Why `--link` is deprecated/forbidden

`--link` was an old way to connect containers. It injected environment variables and `/etc/hosts` entries. It's been deprecated since Docker 1.9 in favor of custom networks with automatic DNS. Using `--link` in Inception will fail your evaluation.

---

## 6. Volumes Internals

### 6.1 Named volumes

```bash
docker volume create myvolume
# Creates: /var/lib/docker/volumes/myvolume/_data/

docker run -v myvolume:/data nginx
# Mounts /var/lib/docker/volumes/myvolume/_data/ at /data inside container
```

**The volume data persists when the container is removed.** It only disappears with `docker volume rm`.

### 6.2 Bind mounts

```bash
docker run -v /host/path:/container/path nginx
```

Direct mount of a host directory. No Docker management. What you see in `/host/path` IS the container's `/container/path`.

**Bind mounts are FORBIDDEN in Inception** for the main volumes. Reason: they're less portable and the subject wants you to use proper named volume tooling.

### 6.3 Named volumes with custom host path (Inception pattern)

The subject requires data to be at `/home/akuzmin/data/`. Use local driver with bind options:

```yaml
volumes:
  mariadb-data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/akuzmin/data/mariadb
```

This IS a named volume (Docker knows about it, `docker volume ls` shows it) but it stores data at a specific host path. This satisfies both the "named volume" requirement and the "data in /home/login/data" requirement.

**The directory must exist on the host before you start Compose.** Add it to your Makefile.

### 6.4 How volumes bypass OverlayFS

Volumes are mounted AFTER the container's rootfs is set up. They bypass the OverlayFS entirely — data goes directly to the volume's location. This means:
- Volume data is NOT part of the image layers
- Volume data persists container restarts
- Volume I/O is faster than writing to the container layer

---

## 7. Docker Build Internals

### 7.1 Build context

```bash
docker build -t myimage .
```

The `.` is the **build context** — everything in it gets sent to the Docker daemon as a tar archive. This is why `.dockerignore` matters: exclude large files (node_modules, .git) to keep the context small.

### 7.2 Layer caching

Each Dockerfile instruction that produces a filesystem change creates a layer. Docker caches these layers by instruction hash.

```dockerfile
FROM debian:bookworm-slim        # Layer 1 — cached from last time
RUN apt-get update && \
    apt-get install -y nginx     # Layer 2 — cached if instruction unchanged
COPY conf/nginx.conf /etc/nginx/ # Layer 3 — invalidated if file changed
RUN nginx -t                     # Layer 4 — runs again because Layer 3 changed
```

**Key rule:** Put things that change rarely at the top of the Dockerfile. Put things that change often (your config files, scripts) near the bottom.

### 7.3 PID 1 and signal handling

When Docker stops a container, it sends `SIGTERM` to PID 1. If PID 1 doesn't handle it within 10 seconds, Docker sends `SIGKILL`.

**Problem with shell scripts as PID 1:**
```dockerfile
CMD ["./start.sh"]   # start.sh is PID 1
# Inside start.sh:
exec nginx -g "daemon off;"   # CORRECT: exec replaces shell with nginx
                               # nginx becomes PID 1, receives SIGTERM

# WITHOUT exec:
nginx -g "daemon off;"        # WRONG: shell is PID 1, nginx is child
                               # SIGTERM hits shell, shell exits
                               # nginx gets killed ungracefully
```

**Always use `exec` in init scripts for the final process.**

### 7.4 CMD vs ENTRYPOINT

```dockerfile
# ENTRYPOINT is the fixed command
# CMD provides default arguments (overridable at runtime)

ENTRYPOINT ["nginx"]
CMD ["-g", "daemon off;"]

# docker run myimage                → nginx -g "daemon off;"
# docker run myimage -t             → nginx -t  (overrides CMD)

# Shell form (avoid — wraps in /bin/sh -c, making sh the PID 1):
CMD nginx -g "daemon off;"     # sh -c "nginx -g..." — sh is PID 1
ENTRYPOINT nginx               # same problem

# Exec form (correct):
CMD ["nginx", "-g", "daemon off;"]
```

---

## 8. Docker Daemon Architecture

```
/var/run/docker.sock       ← Unix socket (API endpoint)
       │
dockerd                    ← main daemon process
  ├── API server           ← handles REST requests
  ├── Builder              ← handles docker build
  ├── Distribution         ← registry pulls/pushes
  ├── NetworkController    ← manages networks, iptables
  ├── VolumeController     ← manages volumes
  └── containerd client    ← delegates to containerd
```

```bash
# Docker daemon config file
cat /etc/docker/daemon.json

# Daemon logs
journalctl -u docker.service -f

# Docker socket permissions
ls -la /var/run/docker.sock
# srw-rw---- 1 root docker ...
# Users in 'docker' group can access it
```

---

## 9. Implement a Container Yourself (Conceptual)

To prove you understand it: here's a minimal container in bash:

```bash
#!/bin/bash
# Minimal container: isolate a process using namespaces

# 1. Create a rootfs (e.g., extract Alpine)
mkdir -p /tmp/mycontainer
tar xf alpine-minirootfs.tar.gz -C /tmp/mycontainer

# 2. Launch with namespaces
unshare \
  --pid \
  --net \
  --mount \
  --uts \
  --ipc \
  --fork \
  chroot /tmp/mycontainer \
  /bin/sh

# What happened:
# - New PID namespace: sh is PID 1
# - New network namespace: no network interfaces (yet)
# - New mount namespace: won't affect host mounts
# - New UTS namespace: can set different hostname
# - chroot: / is now /tmp/mycontainer
```

To add networking, you'd then:
```bash
# Create veth pair on host
ip link add veth0 type veth peer name veth1
# Move one end into container's network namespace
ip link set veth1 netns <container_netns_pid>
# Configure IPs
ip addr add 172.20.0.1/24 dev veth0
nsenter -t <pid> -n ip addr add 172.20.0.2/24 dev veth1
```

This is exactly what runc does, just properly and in C/Go.

---

## Key Sources

- Linux man pages: `man 7 namespaces`, `man 7 cgroups`, `man 8 ip`
- Linux kernel docs: https://www.kernel.org/doc/html/latest/filesystems/overlayfs.html
- OCI Runtime Spec: https://github.com/opencontainers/runtime-spec
- OCI Image Spec: https://github.com/opencontainers/image-spec
- containerd docs: https://containerd.io/docs/
- runc source: https://github.com/opencontainers/runc
- Docker engine internals: https://docs.docker.com/engine/
- Liz Rice "Containers from Scratch" talk: https://www.youtube.com/watch?v=8fi7uSYlOdc
- Jesse Frazelle's blog on container security
- "Container Security" book by Liz Rice (free PDF available)
