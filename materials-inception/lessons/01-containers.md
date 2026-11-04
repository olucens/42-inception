# Урок 1. Что такое контейнер

⏱ 1,5 часа · блок вопросов A (Q1–Q10)

**На защите:** «как работает Docker», «чем он лучше VM».

## Прочитай

**Контейнер — это обычный процесс Linux, которому ядро показывает ограниченный вид на систему.**
Отдельной ОС внутри нет. Всё держится на трёх механизмах ядра:

| Механизм | На какой вопрос отвечает |
|---|---|
| **namespaces** | что процесс **видит** |
| **cgroups** | сколько ресурсов процесс может **потребить** |
| **OverlayFS** | какая у него **файловая система** |

### Namespaces

| Namespace | Что у процесса своё |
|---|---|
| `pid` | нумерация процессов: сам он PID 1, чужих не видит |
| `net` | интерфейсы, маршруты, порты |
| `mnt` | дерево монтирований |
| `uts` | hostname |
| `ipc` | разделяемая память, семафоры |
| `user` | соответствие UID и GID |
| `cgroup` | вид на иерархию cgroups |

У процесса два PID: внутри он 1, на хосте — обычный большой номер. Ядро одно, нумерации разные.

### Cgroups

Namespaces не ограничивают ресурсы. Без cgroups «изолированный» процесс всё равно съест всю память
хоста. Docker записывает лимит в файл вроде `memory.max`, и при превышении ядро убивает процесс
(OOM killer, код выхода 137).

### OverlayFS

Образ — это стопка неизменяемых слоёв. Поверх них при запуске добавляется один записываемый слой:

```
merged  ← то, что видит контейнер как /
upper   ← записываемый слой контейнера, удаляется вместе с ним
lower   ← слои образа, только чтение
```

- **Copy-on-write:** при изменении файл целиком копируется из lower в upper и меняется там.
- **Удаление:** в upper появляется специальный файл whiteout, а в lower оригинал остаётся.

Отсюда два вывода, которые встретятся дальше: удаление в следующем слое не уменьшает образ (урок 2), а
данные базы нельзя хранить в записываемом слое (урок 5).

### Кто что делает при `docker run`

```
docker (клиент) → REST API через /var/run/docker.sock → dockerd
  → containerd (управляет жизненным циклом)
    → runc: создаёт namespaces и cgroups, собирает корневую ФС, запускает твой процесс как PID 1
```

`docker compose` — такой же клиент: читает YAML и делает те же вызовы API.

### Контейнер и виртуальная машина

| | VM | Контейнер |
|---|---|---|
| Ядро | своё, гостевое | общее с хостом |
| Запуск | BIOS, ядро, init: десятки секунд | один процесс: доли секунды |
| Размер | гигабайты | мегабайты |
| Граница изоляции | гипервизор | системные вызовы общего ядра |

У контейнера граница шире: уязвимость ядра открывает побег на хост. Поэтому недоверенный код чужих
клиентов обычно разделяют виртуальными машинами. Linux-контейнер не может работать на другом ядре:
Docker на macOS запускает их внутри скрытой Linux-VM.

## Сделай руками

Всё выполняется в VM. Сначала соберём контейнер без Docker.

```bash
mkdir -p ~/lab && cd ~/lab
A=$(uname -m)
curl -fsSLO https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/$A/alpine-minirootfs-3.20.3-$A.tar.gz
mkdir rootfs && sudo tar xzf alpine-minirootfs-3.20.3-$A.tar.gz -C rootfs
```

**Шаг 1. Только `chroot`.** Файловая система чужая, но изоляции нет:

```bash
sudo chroot rootfs /bin/sh -c 'mount -t proc proc /proc; head -2 /etc/os-release; ps | wc -l; hostname; umount /proc'
```

Видно Alpine, но и все процессы хоста (десятки строк), и его hostname.

**Шаг 2. Добавляем PID namespace:**

```bash
sudo unshare --pid --fork --mount-proc=$PWD/rootfs/proc chroot rootfs /bin/sh -c 'ps; echo PID=$$'
```

В списке только твои процессы, а shell стал `PID=1`. Без `--fork` не сработает: `unshare` меняет
namespace только для новых процессов.

**Шаг 3. Все namespaces.** Hostname меняется только внутри, а сетевого интерфейса `eth0` нет:

```bash
sudo unshare --pid --fork --mount-proc=$PWD/rootfs/proc --net --uts --ipc chroot rootfs \
  /bin/sh -c 'hostname mybox; hostname; ip addr; echo PID=$$'
hostname     # на хосте имя прежнее
```

**Шаг 4. Настоящий контейнер устроен так же:**

```bash
docker run -d --name lab-t alpine:3.20 sleep 300
P=$(docker inspect -f '{{.State.Pid}}' lab-t)
echo "PID на хосте: $P"
docker exec lab-t cat /proc/1/comm                  # sleep, внутри это PID 1
sudo readlink /proc/$$/ns/pid /proc/$P/ns/pid       # номера разные: разные namespace
uname -r; docker exec lab-t uname -r                # ядро одно и то же
docker rm -f lab-t
```

**Шаг 5. Cgroups:**

```bash
docker run --rm -m 50m alpine:3.20 cat /sys/fs/cgroup/memory.max      # 52428800
docker run --name lab-oom -m 20m alpine:3.20 sh -c 'x=aaaaaaaaaa; while true; do x=$x$x; done'
docker inspect lab-oom -f 'OOMKilled={{.State.OOMKilled}} exit={{.State.ExitCode}}'     # true, 137
docker rm lab-oom
```

**Шаг 6. OverlayFS своими руками:**

```bash
mkdir -p ov/lower ov/upper ov/work ov/merged
echo "from image" > ov/lower/a.txt; echo "delete me" > ov/lower/b.txt
sudo mount -t overlay overlay -o lowerdir=ov/lower,upperdir=ov/upper,workdir=ov/work ov/merged
sudo sh -c 'echo changed > ov/merged/a.txt; rm ov/merged/b.txt'
ls ov/merged            # только a.txt
cat ov/lower/a.txt      # from image: нижний слой не изменился
ls ov/lower             # a.txt b.txt: b.txt никуда не делся
ls -l ov/upper          # a.txt и b.txt с типом "c" и номером 0, 0: это whiteout
sudo umount ov/merged
```

**Уборка:** `cd ~ && sudo rm -rf ~/lab`. Файлы `rootfs` принадлежат root, поэтому нужен `sudo`.

**Запиши в [`labs.md`](../my-work/labs.md), раздел «Лаба 1»** и скажи «проверь лабу 1».

## Ответь

Блок A в [`answers.md`](../my-work/answers.md), не глядя сюда. Затем «проверь блок A».

## Глубже, по желанию

`man 7 namespaces`, `man 7 cgroups`, доклад Liz Rice
[Containers from Scratch](https://www.youtube.com/watch?v=8fi7uSYlOdc).
