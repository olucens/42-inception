# Docker Storage — Volumes, Bind Mounts, and OverlayFS

---

## 1. The Three Storage Types

```
┌──────────────────────────────────────────────────────────────┐
│                     Container Process                        │
├──────────────────────────────────────────────────────────────┤
│   Container Layer (read-write, OverlayFS upper)              │
│   → Lost when container is removed                           │
├─────────────────┬────────────────────────────────────────────┤
│  Named Volumes  │  Bind Mounts  │  tmpfs (memory only)       │
│  (managed by    │  (host path   │  (RAM, no persistence)     │
│  Docker)        │  directly)    │                            │
└─────────────────┴────────────────────────────────────────────┘
```

---

## 2. Named Volumes

```bash
# Create
docker volume create myvolume

# Use
docker run -v myvolume:/var/lib/mysql mariadb

# Where data lives
ls /var/lib/docker/volumes/myvolume/_data/

# Inspect
docker volume inspect myvolume
```

**Properties:**
- Docker manages the lifecycle
- Appears in `docker volume ls`
- Data persists: container removal does NOT delete volume
- Data deleted only with `docker volume rm` or `docker volume prune`
- Can be shared between containers simultaneously

---

## 3. Bind Mounts

```bash
docker run -v /home/user/data:/var/lib/mysql mariadb
# or
docker run --mount type=bind,source=/home/user/data,target=/var/lib/mysql mariadb
```

**Properties:**
- Host path is mounted directly — same files, same inode numbers
- Docker has no knowledge of the mount (not in `docker volume ls`)
- Depends on host filesystem structure (less portable)
- **FORBIDDEN for main volumes in Inception**

---

## 4. Inception Volume Pattern

The subject requires:
1. **Named volumes** (appears in `docker volume ls`)
2. Data stored at `/home/akuzmin/data/` on host

Solution — named volume with local driver and bind options:

```yaml
volumes:
  mariadb-data:
    driver: local
    driver_opts:
      type: none        # no special fs type
      o: bind           # bind mount behavior
      device: /home/akuzmin/data/mariadb   # host path

  wordpress-data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/akuzmin/data/wordpress
```

**The host directories must exist before `docker compose up`:**
```makefile
all:
	mkdir -p /home/akuzmin/data/mariadb
	mkdir -p /home/akuzmin/data/wordpress
	docker compose -f srcs/docker-compose.yml up --build -d
```

---

## 5. Volume Sharing Between Containers

WordPress files must be accessible by BOTH:
- **WordPress container**: to write files, run PHP
- **NGINX container**: to serve static assets (CSS, JS, images) directly

```yaml
services:
  wordpress:
    volumes:
      - wordpress-data:/var/www/html    # WordPress writes here

  nginx:
    volumes:
      - wordpress-data:/var/www/html    # NGINX reads same files
```

Both containers mount the same named volume. The data lives once on disk, visible from both.

---

## 6. OverlayFS Layers in Detail

```
Image: debian:bookworm + nginx installation

Layer chain (bottom to top):
  L1: debian:bookworm base        [sha256:abc...]  read-only
  L2: apt-get update              [sha256:def...]  read-only
  L3: apt-get install nginx       [sha256:ghi...]  read-only
  L4: COPY nginx.conf /etc/nginx  [sha256:jkl...]  read-only
─────────────────────────────────────────────────
  Upper: container write layer                     read-write
  (logs, PID files, runtime state)
─────────────────────────────────────────────────
  Merged: union view (what container sees as /)
```

```bash
# See the actual layers
docker inspect nginx:latest | python3 -m json.tool | grep -A 5 "Layers"

# On disk
ls /var/lib/docker/overlay2/
# Each directory = one layer

# For a running container
docker inspect <container> | grep MergedDir
# ls that path shows the full filesystem the container sees
```

---

## 7. Why Volume Data Bypasses OverlayFS

When Docker starts a container with a volume:
1. Sets up OverlayFS for the container rootfs (image layers + upper layer)
2. THEN bind-mounts the volume at the specified path
3. The bind mount overwrites whatever OverlayFS shows at that path

```
Without volume:  /var/lib/mysql → OverlayFS upper layer (lost on container rm)
With volume:     /var/lib/mysql → bind mount to /var/lib/docker/volumes/.../_data/
                                  (persists)
```

**Volume writes go directly to the host filesystem** — no OverlayFS copy-on-write overhead, which is why volume I/O is faster.

---

## 8. Data Persistence Scenarios

| Action | Container Layer | Named Volume |
|--------|----------------|--------------|
| Container stop | Preserved | Preserved |
| Container start | Preserved | Preserved |
| `docker rm` container | **DELETED** | Preserved |
| `docker volume rm` | N/A | **DELETED** |
| `docker compose down` | **DELETED** | Preserved |
| `docker compose down -v` | **DELETED** | **DELETED** |
| Host reboot | N/A (docker manages) | Preserved |

---

## 9. Inspecting Storage

```bash
# List volumes
docker volume ls

# Inspect volume
docker volume inspect mariadb-data
# Shows: Mountpoint, Driver, Options

# See disk usage
docker system df

# See detailed storage
docker system df -v

# Find dangling volumes (not used by any container)
docker volume ls -f dangling=true

# Clean up dangling volumes
docker volume prune
```

---

## 10. MariaDB Data Directory Structure

After MariaDB initializes in `/var/lib/mysql` (on the named volume):

```
/var/lib/mysql/
├── aria_log.00000001     # Aria storage engine log
├── aria_log_control
├── ib_logfile0           # InnoDB redo log
├── ib_logfile1
├── ibdata1               # InnoDB system tablespace
├── mysql/                # System database (users, grants)
├── performance_schema/   # Performance monitoring
└── wordpress/            # Your WordPress database
    ├── wp_posts.ibd
    ├── wp_users.ibd
    └── ...
```

This entire directory must be on the named volume. If it's in the container layer, the database is lost on container removal.
