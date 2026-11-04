# Урок 4. Сеть

⏱ 1,5 часа · блок вопросов D (Q31–Q40)

**На защите:** «объясни docker-network простыми словами», `network: host` и `links:` останавливают защиту.

## Прочитай

### Как контейнер подключён

```
контейнер: eth0 172.19.0.3 ──┐ veth (виртуальный кабель)
                             ├── мост br-xxxx 172.19.0.1 (виртуальный коммутатор) ── хост
контейнер: eth0 172.19.0.2 ──┘ veth
```

- **Network namespace** даёт контейнеру свой сетевой стек.
- **Пара veth** работает как кабель: один конец внутри контейнера (`eth0`), другой на хосте.
- **Мост** соединяет все такие концы, как коммутатор.

### Встроенный DNS

В пользовательской сети Docker записывает в `/etc/resolv.conf` контейнера `nameserver 127.0.0.11`. Этот адрес
обслуживает сам Docker и знает имена контейнеров и сервисов сети. Поэтому работает
`fastcgi_pass wordpress:9000`. Указывать IP нельзя: он меняется при пересоздании контейнера.

### Стандартный мост и пользовательская сеть

| | `docker0` (по умолчанию) | своя сеть |
|---|---|---|
| DNS по имени | нет | есть |
| Изоляция | все контейнеры без явной сети вместе | только подключённые к этой сети |

`links:` устарели: они писали записи в `/etc/hosts` и нужны были, пока не было встроенного DNS. Запрет ничего не
отнимает.

### `expose` и `ports`

| | Что делает |
|---|---|
| `expose` | только документация; внутри сети порт и так доступен |
| `ports: "443:443"` | добавляет правило DNAT: трафик на порт хоста перенаправляется в контейнер |

В проекте `ports` есть только у nginx. MariaDB и PHP-FPM защищены тем, что до них просто нет сетевого пути снаружи,
а не только паролем.

### Почему запрещён `network: host`

Контейнер получает сетевой namespace хоста: своей изоляции нет. Каждый открытый порт сразу открыт на хосте. MariaDB
с `bind-address = 0.0.0.0` слушала бы 3306 на всех интерфейсах машины, в обход nginx.

### Прочитай в проекте

В `docker-compose.yml` найди блок `networks:` и подключение каждого сервиса. Найди `fastcgi_pass` в шаблоне nginx и
`WP_DB_HOST` в `.env.example`.

## Сделай руками

**Шаг 1. На стандартном мосту имён нет:**

```bash
docker run -d --name lab-a alpine:3.20 sleep 600
docker run --rm alpine:3.20 ping -c1 -W2 lab-a      # bad address
docker rm -f lab-a
```

**Шаг 2. В своей сети есть DNS и изоляция:**

```bash
docker network create labnet; docker network create othernet
docker run -d --name lab-db  --network labnet   alpine:3.20 sleep 600
docker run -d --name lab-app --network labnet   alpine:3.20 sleep 600
docker run -d --name lab-out --network othernet alpine:3.20 sleep 600

docker exec lab-app ping -c1 -W2 lab-db             # работает
docker exec lab-app cat /etc/resolv.conf            # nameserver 127.0.0.11
docker exec lab-out ping -c1 -W2 lab-db             # bad address: другая сеть
```

**Шаг 3. Посмотри устройство сети:**

```bash
docker exec lab-app ip route                        # шлюз: адрес моста
ip -o link | grep veth                              # концы veth на хосте, "master br-..."
ID=$(docker network inspect labnet -f '{{.Id}}' | cut -c1-12); ip -4 addr show br-$ID
docker network inspect labnet --format '{{range .Containers}}{{.Name}} {{.IPv4Address}}{{"\n"}}{{end}}'
docker rm -f lab-db lab-app lab-out; docker network rm labnet othernet
```

**Шаг 4. Публикация порта:**

```bash
docker run -d --name lab-web -p 8080:80 alpine:3.20 sh -c 'apk add -q busybox-extras && exec httpd -f -p 80 -h /etc'
sleep 5; curl -s localhost:8080/alpine-release      # версия Alpine
docker ps --filter name=lab-web --format '{{.Ports}}'
sudo iptables -t nat -L DOCKER -n | grep 8080       # правило DNAT
docker rm -f lab-web
```

**Шаг 5. Сеть хоста:**

```bash
docker run --rm --network host alpine:3.20 hostname     # имя твоей VM
docker run --rm --network host alpine:3.20 ip -o link | wc -l
docker run --rm alpine:3.20 ip -o link | wc -l
```

**Шаг 6. Проект:**

```bash
docker network ls
docker ps --format '{{.Names}}: {{.Ports}}'          # "->" есть только у nginx
docker exec nginx getent hosts wordpress
docker exec wordpress getent hosts mariadb
nc -zv 127.0.0.1 3306; nc -zv 127.0.0.1 9000         # оба отказ
curl -s -m 4 http://akuzmin.42.fr/; echo "exit=$?"   # exit=7
```

Если нет `nc`: `sudo apt-get install -y netcat-openbsd`.

**Запиши в [`labs.md`](../my-work/labs.md), раздел «Лаба 4»** и скажи «проверь лабу 4».

## Ответь

Блок D в [`answers.md`](../my-work/answers.md). Затем «проверь блок D».

## Глубже, по желанию

[Docker networking](https://docs.docker.com/engine/network/).
