# Шпаргалка команд

Только то, что нужно на защите. Команды выполняются из корня проекта.

## Проект

```bash
make init        # создать srcs/.env и недостающие секреты
make             # собрать, запустить, дождаться healthy
make ps          # состояние контейнеров
make logs        # логи всех сервисов
make down        # удалить контейнеры, данные остаются
make clean       # и образы, данные остаются
make fclean      # всё вместе с данными (нужен sudo)
make re          # fclean, затем make
make tls-test    # TLS 1.0 и 1.1 отклонены, 1.2 и 1.3 приняты
```

## Состояние и логи

```bash
docker compose -f srcs/docker-compose.yml ps    # или: docker compose -p srcs ps
docker ps -a
docker logs --tail 40 wordpress
docker exec wordpress cat /proc/1/comm          # кто PID 1
docker inspect mariadb -f '{{.HostConfig.RestartPolicy.Name}} restarts={{.RestartCount}}'
docker images
docker history --no-trunc mariadb:inception
```

## Сеть

```bash
docker network ls
docker network inspect inception-network --format '{{range .Containers}}{{.Name}} {{.IPv4Address}}{{"\n"}}{{end}}'
docker exec nginx getent hosts wordpress
docker exec nginx cat /etc/resolv.conf
docker ps --format '{{.Names}}: {{.Ports}}'
nc -zv 127.0.0.1 3306
curl -s -m 4 http://akuzmin.42.fr/; echo "exit=$?"
```

## Тома

```bash
docker volume ls
docker volume inspect srcs_mariadb-data | grep device
docker volume inspect srcs_wordpress-data | grep device
sudo ls /home/akuzmin/data/mariadb
```

## TLS

```bash
echo | openssl s_client -connect akuzmin.42.fr:443 2>/dev/null | grep -E 'Protocol|New,'
echo | openssl s_client -connect akuzmin.42.fr:443 2>/dev/null | openssl x509 -noout -subject -ext subjectAltName
curl -kI https://akuzmin.42.fr/
```

## База

```bash
docker exec -it mariadb mariadb -u root -p              # пароль: secrets/db_root_password.txt
docker exec -it mariadb mariadb -u wp_user -p wordpress # пароль: secrets/db_password.txt
```

```sql
SHOW DATABASES;
USE wordpress;
SHOW TABLES;
SELECT user_login FROM wp_users;
SELECT comment_content FROM wp_comments;
SELECT user, host FROM mysql.user;
SHOW GRANTS FOR 'wp_user'@'%';
```

## WordPress

```bash
W="docker exec wordpress wp --path=/var/www/html --allow-root"
$W user list --fields=user_login,roles
$W post list --post_type=page --fields=ID,post_title
$W config get WP_HOME
$W config get DB_HOST
```

## Секреты и git

```bash
docker exec wordpress ls /run/secrets/
docker exec wordpress grep secrets /proc/mounts
docker inspect wordpress --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -i password   # пусто
git ls-files | grep -E 'secrets/|\.env$'                                                           # пусто
```

## Сбой контейнера

```bash
sudo kill -9 $(docker inspect -f '{{.State.Pid}}' mariadb)     # настоящий сбой
docker exec nginx sh -c 'kill 1'                               # выход с кодом 0
```

`docker kill` и `docker stop` считаются ручной остановкой: контейнер не поднимется.
