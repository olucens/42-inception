# Lab 03 — Networking and Volumes

> **Goal:** Connect containers together and persist data across restarts.
> After this you can explain how NGINX talks to WordPress, and how data survives container deletion.
> Time: ~40 minutes

---

## Part A — Networking

### Why containers need networking

In Inception, 3 containers must communicate:
```
Browser → NGINX:443 → WordPress:9000 → MariaDB:3306
```

NGINX needs to reach WordPress by name. WordPress needs to reach MariaDB by name.
They need to be on the same network and resolve each other's names automatically.

### The Default Bridge (docker0) — what NOT to use

When you run `docker run` without specifying a network, Docker uses its default bridge:
```bash
ip addr show docker0    # 172.17.0.1
```

Problem: containers on the default bridge **cannot reach each other by name**. Only by IP, which changes every restart.

### Custom Bridge Networks — what to use

```bash
# Create a custom network
docker network create --driver bridge mynet

# Run two containers on it
docker run -d --name db     --network mynet alpine:3.19 sleep 999
docker run -d --name webapp --network mynet alpine:3.19 sleep 999

# From webapp, reach db by NAME (automatic DNS)
docker exec webapp ping db         # works!
docker exec webapp ping 172.x.x.x  # works too, but name is better

# Cleanup
docker rm -f db webapp
docker network rm mynet
```

**Why does name resolution work?**
Docker runs an embedded DNS server at `127.0.0.11` inside each container. It resolves container names and service names automatically.

```bash
# Verify inside a container
docker exec webapp cat /etc/resolv.conf
# nameserver 127.0.0.11
```

---

## Exercise 1 — Connect two containers manually

**Task:** Start a MariaDB container and connect to it from a second container.

```bash
# Step 1: Create a network
docker network create --driver bridge test-net

# Step 2: Start MariaDB (using environment variables for quick setup)
docker run -d \
  --name test-db \
  --network test-net \
  -e MYSQL_ROOT_PASSWORD=rootpass \
  -e MYSQL_DATABASE=testdb \
  -e MYSQL_USER=testuser \
  -e MYSQL_PASSWORD=testpass \
  mariadb:10.11

# Wait ~15 seconds for MariaDB to initialize

# Step 3: Start a client container on the same network
docker run -it \
  --name test-client \
  --network test-net \
  --rm \
  mariadb:10.11 \
  mariadb -h test-db -u testuser -ptestpass testdb

# 'test-db' resolves by name because both are on test-net
# You get a MariaDB prompt — type: SHOW DATABASES; then \q

# Cleanup
docker rm -f test-db
docker network rm test-net
```

**Note:** We used the ready-made `mariadb:` image here only for testing. In your project, you must build it yourself. This exercise is just to see networking work.

---

## Exercise 2 — Port publishing

Ports work at two levels:
- `EXPOSE` in Dockerfile = documentation only, does nothing
- `ports:` in compose / `-p` in docker run = actually forwards traffic

```bash
# Run nginx and publish port 80 to host port 8080
docker run -d --name nginx-test -p 8080:80 nginx:1.25
curl http://localhost:8080    # reaches the nginx inside the container

# Without port publishing:
docker run -d --name nginx-test2 nginx:1.25
curl http://localhost:80      # fails — port not published to host
# BUT another container on the same network can still reach it:
docker run --rm --network container:nginx-test2 alpine curl http://localhost:80

docker rm -f nginx-test nginx-test2
```

**Inception rule:** Only NGINX publishes port 443 to the host. WordPress and MariaDB only `expose` (internal only).

---

## Part B — Volumes

### Why volumes exist

Containers are ephemeral — their filesystem is lost when removed:

```bash
docker run --name test alpine sh -c "echo hello > /data/myfile.txt"
docker rm test
docker run --name test alpine sh -c "cat /data/myfile.txt"
# cat: /data/myfile.txt: No such file or directory
```

The file is gone. For a database, this means ALL your data is lost every restart. Unacceptable.

Volumes solve this by storing data OUTSIDE the container's ephemeral layer.

### 3 types of storage

```
1. Container layer (default)
   - Lives inside the container's OverlayFS
   - Fast access
   - DESTROYED when container is removed
   - Use for: temporary files, logs you don't need

2. Named volumes (Docker manages)
   - docker volume create myvolume
   - Lives at /var/lib/docker/volumes/myvolume/_data
   - Persists when container is removed
   - Use for: databases, persistent app data

3. Bind mounts (you specify the host path)
   - docker run -v /host/path:/container/path
   - Host path IS the container path (same files, same inodes)
   - Persists, but tied to host path
   - FORBIDDEN for main volumes in Inception (but named volumes CAN use a host path internally)
```

---

## Exercise 3 — Named volumes survive container deletion

```bash
# Step 1: Create a named volume
docker volume create mydata

# Step 2: Write a file to it
docker run --rm -v mydata:/data alpine sh -c "echo 'persistent!' > /data/test.txt"

# Step 3: Verify it's gone from the container but not the volume
docker run --rm -v mydata:/data alpine cat /data/test.txt
# prints: persistent!

# Step 4: Remove EVERYTHING and check the volume
docker volume ls    # mydata is still there
ls /var/lib/docker/volumes/mydata/_data/   # test.txt is here

# Step 5: Mount to a new container — data is still there
docker run --rm -v mydata:/data alpine cat /data/test.txt
# prints: persistent!

# Only gone when you explicitly delete the volume
docker volume rm mydata
```

---

## Exercise 4 — What happens without a volume for MariaDB

```bash
# Start MariaDB WITHOUT a volume
docker run -d --name no-volume-db \
  -e MYSQL_ROOT_PASSWORD=root \
  -e MYSQL_DATABASE=mydb \
  mariadb:10.11

# Wait for it to initialize, then create a table
sleep 20
docker exec no-volume-db mariadb -uroot -proot mydb \
  -e "CREATE TABLE test (id INT); INSERT INTO test VALUES (42);"

# Verify data exists
docker exec no-volume-db mariadb -uroot -proot mydb -e "SELECT * FROM test;"
# shows: 42

# Remove the container
docker rm -f no-volume-db

# Start a new container (same name, same config, NO volume)
docker run -d --name no-volume-db \
  -e MYSQL_ROOT_PASSWORD=root \
  -e MYSQL_DATABASE=mydb \
  mariadb:10.11

sleep 20
docker exec no-volume-db mariadb -uroot -proot mydb -e "SELECT * FROM test;"
# ERROR: Table 'mydb.test' doesn't exist
# DATA IS GONE

docker rm -f no-volume-db
```

**Now do it WITH a volume:**
```bash
docker volume create db-data

docker run -d --name volume-db \
  -v db-data:/var/lib/mysql \
  -e MYSQL_ROOT_PASSWORD=root \
  -e MYSQL_DATABASE=mydb \
  mariadb:10.11

sleep 20
docker exec volume-db mariadb -uroot -proot mydb \
  -e "CREATE TABLE test (id INT); INSERT INTO test VALUES (42);"

docker rm -f volume-db

# Start again with the SAME volume
docker run -d --name volume-db \
  -v db-data:/var/lib/mysql \
  -e MYSQL_ROOT_PASSWORD=root \
  -e MYSQL_DATABASE=mydb \
  mariadb:10.11

sleep 10
docker exec volume-db mariadb -uroot -proot mydb -e "SELECT * FROM test;"
# shows: 42 — DATA SURVIVED!

docker rm -f volume-db
docker volume rm db-data
```

---

## Exercise 5 — Share a volume between two containers

In Inception, NGINX needs to serve WordPress static files (CSS, JS, images). Both containers must see the same files.

```bash
docker volume create shared-files

# Container 1 writes a file
docker run --rm -v shared-files:/data alpine sh -c \
  "echo '<h1>Hello from WordPress!</h1>' > /data/index.html"

# Container 2 (NGINX) reads it
docker run --rm -v shared-files:/usr/share/nginx/html -p 8080:80 nginx:1.25 &
curl http://localhost:8080
# prints: <h1>Hello from WordPress!</h1>

docker stop $(docker ps -q)
docker volume rm shared-files
```

---

## The Inception Volume Pattern

Named volumes normally store data at `/var/lib/docker/volumes/name/_data`.
The subject requires data at `/home/akuzmin/data/`. 

Solution: named volume + `local` driver with bind options:
```yaml
volumes:
  mariadb-data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/akuzmin/data/mariadb
```

This is still a proper named volume (appears in `docker volume ls`) but data is stored at your specified path.

**The directory MUST exist before docker compose up:**
```bash
mkdir -p /home/akuzmin/data/mariadb
mkdir -p /home/akuzmin/data/wordpress
```

Your Makefile handles this automatically with the `setup` target.

---

## Knowledge Check

1. Why can't containers on the default bridge resolve each other by name?
2. What is Docker's embedded DNS server IP inside a container?
3. What is the difference between `EXPOSE` and `ports:`?
4. What happens to data in a container's filesystem when you `docker rm` the container?
5. What is the difference between a named volume and a bind mount?
6. How can two containers share the same volume?
7. Why does `/home/akuzmin/data/mariadb` need to exist before `docker compose up`?
8. In Inception, which container publishes a port to the host? Which containers only expose internally?
