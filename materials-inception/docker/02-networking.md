# Docker Networking — Deep Dive

---

## 1. Network Drivers

| Driver | Use Case | Inception |
|--------|----------|-----------|
| `bridge` | Default, container-to-container on same host | ✅ Use this |
| `host` | Share host network namespace | ❌ FORBIDDEN |
| `none` | No networking | For one-off tasks |
| `overlay` | Multi-host (Swarm/Kubernetes) | Not needed here |
| `macvlan` | Assign MAC address, appear as physical device | Not needed |

---

## 2. Custom Bridge vs Default Bridge

**Default bridge (docker0):**
- Containers CAN'T resolve each other by name (no DNS)
- Must use `--link` (deprecated) for name resolution
- All containers on it share the same broadcast domain

**Custom bridge (what Inception requires):**
```yaml
networks:
  inception-network:
    driver: bridge
```

- Automatic DNS: `mariadb`, `wordpress`, `nginx` are resolvable by name
- Better isolation: containers on different custom networks are isolated
- Can be connected to multiple networks simultaneously
- `docker network connect` adds a container to a network at runtime

---

## 3. DNS Resolution Inside Containers

Docker runs an embedded DNS server at `127.0.0.11:53` inside each container on a custom network.

```bash
# Inside any container on inception-network:
cat /etc/resolv.conf
# nameserver 127.0.0.11
# options ndots:0

# Resolving mariadb:
dig mariadb @127.0.0.11
# Returns the container's IP on inception-network
```

The DNS server is part of dockerd — it answers queries based on container_name and service name (from Compose).

---

## 4. Inter-Container Communication Flow

```
NGINX (172.20.0.2) → WordPress (172.20.0.3):9000

1. NGINX process calls connect(172.20.0.3, 9000)
2. Kernel routes: 172.20.0.0/24 via br-inception (bridge)
3. Packet enters bridge interface
4. Bridge sees destination 172.20.0.3 in its ARP table
5. Forwards to veth pair connected to WordPress container
6. WordPress's kernel receives on eth0 (172.20.0.3)
7. PHP-FPM accepts the connection on port 9000
```

---

## 5. Port Publishing Deep Dive

```yaml
ports:
  - "443:443"
```

Docker adds these iptables rules (check with `sudo iptables -t nat -L -n -v`):

```
Chain DOCKER (nat table):
DNAT  tcp  --  !docker0  *  0.0.0.0/0  0.0.0.0/0  tcp dpt:443  to:172.20.0.2:443

Chain FORWARD (filter table):
ACCEPT  tcp  --  *  br-inception  0.0.0.0/0  172.20.0.2  tcp dpt:443
```

**Traffic flow for external HTTPS request:**
```
Client → host:443
  → iptables PREROUTING: DNAT to 172.20.0.2:443
  → routing: forward to br-inception bridge
  → iptables FORWARD: ACCEPT
  → veth to nginx container
  → nginx process on port 443
```

---

## 6. Forbidden Networking Patterns

### `network: host`
```yaml
# FORBIDDEN in Inception
services:
  nginx:
    network_mode: host   # container shares host network stack entirely
```
Problem: No isolation. Container can bind any host port, intercept host traffic.

### `--link` / `links:`
```yaml
# FORBIDDEN
services:
  wordpress:
    links:
      - mariadb   # deprecated, insecure, creates one-directional connection
```
Use custom networks instead — they're bidirectional and DNS-based.

---

## 7. Inspecting Networks

```bash
# List networks
docker network ls

# Inspect your network
docker network inspect inception-network
# Shows: containers, IPs, gateway, subnet

# See what network a container is on
docker inspect <container> | grep -A 20 '"Networks"'

# Watch network traffic between containers (install tcpdump in container)
docker exec nginx tcpdump -i eth0 -n
```

---

## 8. Security Model

In Inception, the network architecture enforces security:

```
Internet
   │
   │ port 443 only
   ▼
[NGINX] ←─── only container exposed to outside
   │ FastCGI (9000) — internal only
   ▼
[WordPress+PHP-FPM] — not exposed to internet
   │ MySQL (3306) — internal only
   ▼
[MariaDB] — not exposed to internet
```

MariaDB and WordPress are NEVER directly accessible from outside the host. Only NGINX is published. This is defense in depth.
