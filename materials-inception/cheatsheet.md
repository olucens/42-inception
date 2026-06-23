# Command Cheatsheet — Inception Project

---

## Linux / VM Basics

```bash
# Navigation
pwd                         # where am I?
ls -la                      # list files with permissions and hidden files
cd /path/to/dir             # change directory
cd ..                       # go up one level
cd -                        # go back to previous directory

# Files
mkdir -p a/b/c              # create nested directories
cp file dest                # copy file
mv file dest                # move / rename
rm file                     # delete file
rm -rf dir/                 # delete directory recursively (careful!)
cat file                    # print file contents
less file                   # scrollable file viewer (q to quit)

# Edit files
nano file                   # simple editor (Ctrl+S save, Ctrl+X exit)
vim file                    # powerful editor (i = insert, Esc then :wq = save+quit)

# Permissions
chmod +x script.sh          # make script executable
chmod 600 file              # owner read/write only
chown user:group file       # change owner

# Users and groups
whoami                      # current user
id                          # show UID, GID, groups
sudo command                # run as root
su - username               # switch to user (full login)
usermod -aG groupname user  # add user to group (need logout to take effect)
groups username             # show user's groups
grep groupname /etc/group   # verify group membership

# Processes
ps aux                      # all running processes
ps aux | grep nginx         # find specific process
kill -9 PID                 # force-kill a process
top / htop                  # live process monitor

# Networking
ip addr                     # show network interfaces and IPs
ip addr show eth0           # specific interface
ss -tlnp                    # show listening TCP ports with process names
curl -k https://domain      # make HTTPS request (skip cert check)
ping hostname               # test connectivity
/etc/hosts                  # local DNS overrides (add VM IP → domain here)

# System
df -h                       # disk space
du -sh /path                # size of directory
free -h                     # memory usage
journalctl -u service -f    # follow systemd service logs
systemctl status docker     # check docker daemon status

# Useful shortcuts
Ctrl+C                      # interrupt running command
Ctrl+D                      # close shell / EOF
Ctrl+L                      # clear terminal
Ctrl+R                      # search command history
Tab                         # autocomplete
!!                          # repeat last command
sudo !!                     # repeat last command with sudo
```

---

## Docker — Images

```bash
# Build an image from a Dockerfile
docker build -t myimage .                   # build from current directory
docker build -t myimage:v1 .               # with tag
docker build -t myimage -f path/Dockerfile . # specify Dockerfile location
docker build --no-cache -t myimage .       # ignore cache (full rebuild)
docker build --progress=plain -t myimage . # verbose output (see each step)

# List / inspect images
docker images                              # list local images
docker image ls                            # same thing
docker image inspect myimage              # full metadata (JSON)
docker history myimage                     # show layers and sizes
docker image rm myimage                    # delete image
docker image prune                         # delete dangling images
docker image prune -a                      # delete ALL unused images
```

---

## Docker — Containers

```bash
# Run containers
docker run myimage                         # run (interactive, foreground)
docker run -d myimage                      # detached (background)
docker run -it myimage /bin/bash           # interactive with terminal
docker run --name mycontainer myimage      # give it a name
docker run --rm myimage                    # auto-remove when stopped

# Ports and volumes
docker run -p 443:443 myimage              # publish port host:container
docker run -v myvolume:/data myimage       # named volume
docker run -v /host/path:/data myimage     # bind mount
docker run -e VAR=value myimage            # set environment variable
docker run --env-file .env myimage         # load env from file

# Manage running containers
docker ps                                  # list running containers
docker ps -a                               # all containers (including stopped)
docker stop container                      # graceful stop (SIGTERM → wait → SIGKILL)
docker kill container                      # immediate kill (SIGKILL)
docker rm container                        # remove stopped container
docker rm -f container                     # force remove (even running)

# Inspect a running container
docker logs container                      # print logs
docker logs -f container                   # follow logs (live)
docker logs --tail 50 container            # last 50 lines
docker exec -it container /bin/bash        # open shell inside container
docker exec container command              # run command inside container
docker inspect container                   # full metadata (JSON)
docker inspect container | grep IPAddress  # find container IP
docker stats                               # live resource usage (CPU, RAM)
docker top container                       # processes inside container
docker diff container                      # files changed vs image
```

---

## Docker — Volumes

```bash
docker volume create myvolume              # create named volume
docker volume ls                           # list volumes
docker volume inspect myvolume             # details (where data lives on host)
docker volume rm myvolume                  # delete volume
docker volume prune                        # delete all unused volumes

# Where named volumes live on host:
ls /var/lib/docker/volumes/myvolume/_data/
```

---

## Docker — Networks

```bash
docker network ls                          # list networks
docker network inspect networkname         # details, which containers are on it
docker network create --driver bridge mynet # create custom bridge
docker network connect mynet container     # attach container to network
docker network disconnect mynet container  # detach

# Check DNS from inside a container
docker exec container cat /etc/resolv.conf  # should show 127.0.0.11
docker exec container ping other-container  # test name resolution
```

---

## Docker — Cleanup

```bash
docker system df                           # disk usage summary
docker system df -v                        # detailed breakdown
docker system prune                        # remove stopped containers + dangling images
docker system prune -a                     # remove ALL unused resources
docker system prune -a --volumes           # also remove unused volumes (DESTRUCTIVE)

# Nuclear option (wipe everything)
docker stop $(docker ps -q)               # stop all running containers
docker rm $(docker ps -aq)               # remove all containers
docker rmi $(docker images -q)           # remove all images
docker volume prune                       # remove unused volumes
```

---

## Docker Compose

```bash
# Run from directory containing docker-compose.yml
docker compose up                          # start all services (foreground)
docker compose up -d                       # detached
docker compose up --build                  # rebuild images first
docker compose up --build -d               # rebuild + detached
docker compose down                        # stop and remove containers
docker compose down -v                     # also remove volumes
docker compose down --rmi all              # also remove images

# Manage services
docker compose ps                          # status of all services
docker compose logs                        # all logs
docker compose logs -f                     # follow all logs
docker compose logs -f mariadb             # follow specific service
docker compose restart mariadb             # restart one service
docker compose exec mariadb bash           # shell into service

# Build without running
docker compose build                       # build all images
docker compose build mariadb              # build specific service
docker compose build --no-cache mariadb   # rebuild without cache

# With non-default file location
docker compose -f srcs/docker-compose.yml up --build -d
```

---

## MariaDB / MySQL Commands

```bash
# Connect to MariaDB
mariadb -u root -p                         # prompt for root password
mariadb -u wp_user -p wordpress            # specific user and database
mariadb -u root -prootpassword             # password directly (no space!)

# From host into container
docker exec -it mariadb mariadb -u root -prootpassword

# Inside MariaDB prompt
SHOW DATABASES;                            # list all databases
USE wordpress;                             # select database
SHOW TABLES;                               # list tables in current db
SELECT User, Host FROM mysql.user;         # list all users
SHOW GRANTS FOR 'wp_user'@'%';            # show user privileges
EXIT;  or  \q                             # quit

# Admin commands
CREATE DATABASE mydb;
CREATE USER 'username'@'%' IDENTIFIED BY 'password';
GRANT ALL PRIVILEGES ON mydb.* TO 'username'@'%';
FLUSH PRIVILEGES;                          # reload grant tables
ALTER USER 'root'@'localhost' IDENTIFIED BY 'newpassword';

# Useful diagnostics
SHOW STATUS LIKE 'Threads%';              # connection stats
SELECT @@bind_address;                     # what address MariaDB listens on
```

---

## NGINX Useful Commands

```bash
# Inside NGINX container
nginx -t                                   # test config syntax
nginx -T                                   # print full config
nginx -s reload                            # reload config without restart
nginx -s stop                              # graceful stop

# Check if NGINX is actually serving
curl -k https://localhost                  # from inside container
curl -vk https://akuzmin.42.fr            # from outside, verbose

# Check certificate
openssl s_client -connect akuzmin.42.fr:443 -tls1_3
echo | openssl s_client -connect host:443 2>/dev/null | openssl x509 -text
```

---

## Debugging Docker Problems

```bash
# Container won't start
docker logs <container>                    # read the error
docker run -it --entrypoint /bin/bash myimage  # override entrypoint to poke around

# Container exits immediately
docker logs <container>                    # what did PID 1 print before dying?
docker run --rm myimage /bin/bash          # try running bash directly

# Can't connect between containers
docker exec container ping other           # DNS resolves?
docker exec container curl http://other:port  # port reachable?
docker network inspect inception-network   # are both containers on it?

# Volume issues
docker volume inspect volumename          # where is data?
docker exec container ls /var/lib/mysql/  # is the volume mounted?

# Permission errors
docker exec container id                  # what user is the process running as?
docker exec container ls -la /path        # what are the file permissions?

# Find where a process is listening
docker exec container ss -tlnp
docker exec container cat /etc/hosts
```

---

## Inception Project Specific

```bash
# From Inception/ directory
make                     # build and start everything
make clean               # stop containers
make fclean              # stop + remove containers + images + data
make re                  # full rebuild from scratch
make logs                # follow all service logs
make ps                  # show container status

# Manual data dir creation (Makefile does this automatically)
mkdir -p /home/akuzmin/data/mariadb
mkdir -p /home/akuzmin/data/wordpress

# Check your domain resolves
cat /etc/hosts           # should have: 127.0.0.1  akuzmin.42.fr
curl -k https://akuzmin.42.fr  # should return WordPress HTML
```
