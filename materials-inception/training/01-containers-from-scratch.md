# Lab 01 — What IS a Container? Build One Without Docker

> **Goal:** Understand containers at the kernel level before touching Docker.
> After this lab you can explain WHY Docker does what it does, not just HOW to use it.
> Time: ~30 minutes

---

## The Problem Docker Solves

Imagine you have two applications:
- App A needs Python 3.8
- App B needs Python 3.11
- Your host has Python 3.10

Without isolation you can't run both cleanly. You need each app to see its own "world":
- Its own filesystem
- Its own process list
- Its own network stack
- Its own resource limits

Containers give each process a private view of the system using **Linux kernel features**. There is no separate OS, no hypervisor — just the same kernel with extra isolation.

---

## The 3 Kernel Features That Make Containers

### Feature 1: Namespaces (isolation)

A namespace makes a process think it's alone. Linux has 7 types:

```
PID namespace     → process sees PID 1 as itself (not the host's PID 1)
Network namespace → process gets its own network interfaces
Mount namespace   → process sees its own filesystem tree
UTS namespace     → process has its own hostname
IPC namespace     → isolated inter-process communication
User namespace    → process can be "root" inside without being root outside
Cgroup namespace  → process sees its own resource limits
```

### Feature 2: cgroups (resource limits)

cgroups (control groups) limit how much CPU, RAM, and disk I/O a process can use:
```
/sys/fs/cgroup/memory/docker/<container_id>/memory.limit_in_bytes
/sys/fs/cgroup/cpu/docker/<container_id>/cpu.shares
```

Without cgroups, one container could eat all your RAM and crash the host.

### Feature 3: Union Filesystem (image layers)

Containers get their filesystem from stacked read-only layers + one writable layer on top.
Docker uses **OverlayFS** for this. Each `RUN` instruction in a Dockerfile creates a layer.

---

## Exercise 1 — See namespaces in action

**Step 1:** Check your current process's namespaces:
```bash
ls -la /proc/$$/ns/
```

You'll see symlinks like `net -> net:[4026531992]`. That number is the namespace ID.

**Step 2:** Run a Docker container and look at its namespaces:
```bash
docker run -d --name test alpine:3.19 sleep 300
docker inspect test | grep '"Pid"'
# note the PID number
sudo ls -la /proc/<PID>/ns/
```

Compare the namespace IDs. The container has DIFFERENT IDs — it's in different namespaces.

**Step 3:** What cleanup:
```bash
docker rm -f test
```

---

## Exercise 2 — Build a container manually (no Docker)

This is the most important exercise. We'll do what Docker does under the hood.

**Step 1:** Get a minimal root filesystem. We'll extract Alpine Linux:
```bash
mkdir -p /tmp/mycontainer

# Download Alpine mini rootfs
curl -O https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-minirootfs-3.19.0-x86_64.tar.gz

# Extract into our container directory
tar xzf alpine-minirootfs-3.19.0-x86_64.tar.gz -C /tmp/mycontainer
ls /tmp/mycontainer
# you should see: bin  dev  etc  home  lib  ...
```

**Step 2:** Use `chroot` to change the root filesystem:
```bash
sudo chroot /tmp/mycontainer /bin/sh
# now you're "inside" — type:
ls /         # you see Alpine's filesystem, not the host's
cat /etc/os-release  # Alpine Linux!
ps aux       # BUT: you still see host processes — no PID isolation yet
exit
```

`chroot` is filesystem isolation only. It's NOT a container — you can still escape it and you share the host's PID/network namespaces.

**Step 3:** Add namespace isolation with `unshare`:
```bash
sudo unshare \
  --pid \
  --fork \
  --mount-proc \
  chroot /tmp/mycontainer /bin/sh

# Now inside:
ps aux       # ONLY shows processes in this PID namespace
echo $$      # PID is 1! This shell is PID 1 in its own namespace
hostname     # still shows host hostname (no UTS namespace yet)
exit
```

**Step 4:** Add ALL namespace isolation:
```bash
sudo unshare \
  --pid \
  --fork \
  --mount-proc \
  --net \
  --uts \
  --ipc \
  chroot /tmp/mycontainer /bin/sh

# Inside:
hostname mycontainer     # set our own hostname
hostname                 # mycontainer — isolated!
ip addr                  # only loopback — no network (net namespace is empty)
ps aux                   # only this shell
echo $$                  # PID 1
exit
```

**You just created a container manually.** Docker does exactly this, plus:
- Sets up a network (creates veth pair, attaches to bridge)
- Applies cgroup limits
- Manages the lifecycle
- Handles images (the tarball we extracted)

---

## Exercise 3 — Understand PID 1

**Why PID 1 is special:**

PID 1 is the init process. In a real Linux system it's `systemd` or `init`. It has responsibilities:
1. It receives signals when the system (or Docker) wants to stop it
2. It must reap zombie processes (children that exited but aren't cleaned up)
3. If PID 1 dies, everything dies

**The problem with bad entrypoints:**

```bash
# BAD: shell script as PID 1, nginx as child
CMD ["./start.sh"]  # → shell is PID 1, nginx is child PID 2
                    # Docker sends SIGTERM to PID 1 (the shell)
                    # Shell exits immediately
                    # Nginx is killed ungracefully (SIGKILL)
                    # Dirty shutdown, possible data corruption

# GOOD: nginx IS PID 1
CMD ["nginx", "-g", "daemon off;"]  # nginx is PID 1, receives SIGTERM directly
```

**Prove it yourself:**
```bash
# Start a container with a shell script as entrypoint
docker run -d --name pid_test alpine:3.19 sh -c 'sleep 999'
docker exec pid_test ps aux
# PID 1 = sh, PID 2 = sleep

docker stop pid_test  # sends SIGTERM to PID 1 (sh), sh exits, sleep gets SIGKILL
docker rm pid_test

# Start with the actual process as PID 1
docker run -d --name pid_test2 alpine:3.19 sleep 999
docker exec pid_test2 ps aux
# PID 1 = sleep (receives SIGTERM directly, can clean up)

docker rm -f pid_test2
```

**The `exec` trick in shell scripts:**
```bash
#!/bin/sh
# Do setup here...
setup_stuff()

# exec REPLACES the shell process with mysqld
# Shell PID becomes mysqld — mysqld IS PID 1
exec mysqld --user=mysql

# Without exec:
mysqld --user=mysql
# Shell stays as PID 1, mysqld is a child
# Docker can't reach mysqld with SIGTERM
```

---

## Knowledge Check

Before moving to Lab 02, make sure you can answer these from memory:

1. What 3 kernel features make containers possible?
2. What is a namespace? Name 3 types and what each isolates.
3. What is cgroup and why do we need it?
4. What is the difference between a container and a VM?
5. Why is PID 1 special in a container?
6. What does `exec` do in a shell script and why does it matter?
7. Why is `chroot` alone not enough to make a secure container?

---

## Summary

```
Container = chroot (filesystem) + namespaces (isolation) + cgroups (limits)
Docker = user-friendly API that automates all of the above + image management
```

A container is NOT a mini VM. It's a regular process with extra kernel-enforced isolation.
The same Linux kernel runs both your host processes and all your containers.
