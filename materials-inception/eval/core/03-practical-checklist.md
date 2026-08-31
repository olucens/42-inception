# Core — практический чек-лист

40 проверок на живом стеке. Для каждой: команда, ожидаемый результат и **что она
доказывает**. Последнее важнее: на защите спрашивают не «покажи», а «объясни,
почему это доказывает требование».

Работай сверху вниз. Выполняй из корня проекта (там, где `Makefile`).

Легенда: `[ ]` не проверял · `[x]` зелёная · `[!]` красная, разбираться

---

## 0. Подготовка

```bash
make fclean     # чистый лист — все проверки ниже про сборку с нуля
make            # первый старт: несколько минут
```

Ждать надо не `make ps`, а вот это:

```bash
docker logs wordpress 2>&1 | grep "starting php-fpm"
# [wordpress-init] starting php-fpm 8.2 as PID 1
```

---

## 1. Структура и правила репозитория (1–8)

**[ ] 1. Makefile в корне**
```bash
ls Makefile
```
→ файл есть. *Требование субъекта: Makefile в корне каталога.*

**[ ] 2. Всё конфигурационное — в `srcs/`**
```bash
ls srcs/docker-compose.yml srcs/requirements/*/Dockerfile
```
→ три Dockerfile. *Требование: все файлы конфигурации в `srcs`.*

**[ ] 3. Ни одного `latest`**
```bash
grep -rn "latest" srcs/ Makefile | grep -v "^.*#"
```
→ пусто. *`latest` запрещён; без явного тега `image: mariadb` — это тоже latest.*

**[ ] 4. База — Debian/Alpine предпоследней стабильной**
```bash
grep -h "^FROM" srcs/requirements/*/Dockerfile
```
→ три раза `debian:bookworm-slim`. *Debian 13 — текущая stable, значит 12 —
предпоследняя. Уметь обосновать вслух.*

**[ ] 5. Никаких готовых образов приложений**
```bash
grep -h "^FROM" srcs/requirements/*/Dockerfile | grep -vE "debian|alpine"
```
→ пусто. *`FROM wordpress`, `FROM nginx`, `FROM mariadb` = провал.*

**[ ] 6. Нет запрещённых костылей**
```bash
grep -rnE "tail -f|sleep infinity|while true|while :" srcs/ | grep -v "#"
```
→ пусто вне комментариев. *Запрещены субъектом.*

**[ ] 7. Секреты не в git**
```bash
git ls-files | grep -E "secrets/|srcs/\.env$"
```
→ **пусто**. *Пароли в репозитории = провал проекта. Проверяй по индексу
(`ls-files`), а не по `git status`.*

**[ ] 8. Линтер правил проходит**
```bash
bash ../tests/check_inception_rules.sh | tail -3
```
→ `failed: 0`.

---

## 2. Контейнеры живы и правильно устроены (9–15)

**[ ] 9. Ровно три контейнера, все running**
```bash
make ps
```
→ mariadb, wordpress, nginx — `running`. *`restarting` = crash-loop, смотри логи.*

**[ ] 10. Имя образа = имя сервиса, тег явный**
```bash
docker compose -f srcs/docker-compose.yml config | grep "image:"
```
→ `mariadb:inception`, `wordpress:inception`, `nginx:inception`.
*Требование: «Each Docker image must have the same name as its corresponding service».*

**[ ] 11. PID 1 — настоящий демон** ⭐
```bash
for c in mariadb wordpress nginx; do printf "%-10s " $c; docker exec $c cat /proc/1/comm; done
```
→ `mysqld`, `php-fpm8.2`, `nginx`. *Не `sh`, не `bash`. Доказывает, что демон
получает SIGTERM напрямую и контейнер держится без костылей. Это спрашивают чаще
всего.*

**[ ] 12. Политика перезапуска задана**
```bash
docker inspect mariadb --format '{{.HostConfig.RestartPolicy.Name}}'
```
→ `on-failure`. *«Containers have to restart in case of a crash».*

**[ ] 13. Перезапуск реально работает** ⭐

Здесь три ловушки подряд, и почти все проверяют это неправильно.

- `docker stop` / `docker kill` **отключают** политику перезапуска: Docker считает
  остановку намеренной. `RestartCount` останется 0 — и это не баг.
- `docker exec <c> kill -9 1` не сработает: ядро не доставляет процессу с PID 1
  сигнал, посланный **изнутри его же PID namespace**, если на сигнал не
  установлен обработчик (а на SIGKILL обработчик поставить нельзя).
- `docker exec <c> kill -TERM 1` дойдёт (mysqld обрабатывает SIGTERM), но он
  завершится **штатно, с кодом 0** — и `on-failure` правильно не перезапустит.

Настоящий сбой — это ненулевой код выхода. Убивать надо из PID namespace хоста
(Linux, нужен sudo):

```bash
HOSTPID=$(docker inspect -f '{{.State.Pid}}' mariadb)
sudo kill -9 "$HOSTPID"
sleep 20
docker inspect mariadb --format 'restarts={{.RestartCount}} running={{.State.Running}}'
```
→ `restarts=1 running=true`.

Проверить саму семантику политики можно и одноразовым контейнером:
```bash
docker run -d --restart on-failure --name t debian:bookworm-slim sh -c 'exit 1'
sleep 12 && docker inspect t --format '{{.RestartCount}}'   # > 0
docker rm -f t
```

*Доказывает политику, а не её объявление в YAML. Заодно: после жёсткого убийства
mysqld данные должны остаться на месте — InnoDB восстановится из лога.*

**[ ] 14. Один сервис — один контейнер**
```bash
docker exec nginx ps ax 2>/dev/null || docker exec nginx ls /proc | grep -c '^[0-9]'
docker exec wordpress sh -c 'command -v nginx || echo "nginx НЕ установлен — верно"'
docker exec mariadb sh -c 'command -v nginx || echo "nginx НЕ установлен — верно"'
```
→ в wordpress и mariadb nginx отсутствует. *Субъект: WordPress «without nginx»,
MariaDB «only, without nginx».*

**[ ] 15. Образ MariaDB не тащит предзаполненную базу**
```bash
docker run --rm --entrypoint sh mariadb:inception -c 'ls /var/lib/mysql | wc -l'
```
→ `0`. *Иначе Docker зальёт это в «пустой» том и инициализация будет пропущена —
классический баг этого проекта.*

---

## 3. Сеть (16–22)

**[ ] 16. Сеть объявлена и это bridge**
```bash
docker network inspect inception-network --format '{{.Driver}}'
```
→ `bridge`. *«The network line must be present in your docker-compose.yml».*

**[ ] 17. Все три контейнера в ней**
```bash
docker network inspect inception-network --format '{{range .Containers}}{{.Name}} {{.IPv4Address}}{{"\n"}}{{end}}'
```
→ три строки с IP из одной подсети.

**[ ] 18. Нет `network: host`, нет `links`**
```bash
grep -nE "network_mode:|links:|--link" srcs/docker-compose.yml | grep -v "#"
```
→ пусто. *Прямо запрещено.*

**[ ] 19. DNS по именам сервисов работает** ⭐
```bash
docker exec nginx getent hosts wordpress
docker exec wordpress getent hosts mariadb
docker exec nginx cat /etc/resolv.conf | grep nameserver
```
→ имена резолвятся; `nameserver 127.0.0.11`. *Это и есть замена запрещённым
`links`. Уметь объяснить, откуда берётся 127.0.0.11.*

**[ ] 20. Наружу опубликован только 443** ⭐
```bash
docker ps --format '{{.Names}}\t{{.Ports}}'
```
→ порты хоста есть **только** у nginx, и только 443. У остальных `3306/tcp`,
`9000/tcp` без `->`. *«NGINX must be the only entry point ... via the port 443 only».*

**[ ] 21. БД и PHP-FPM недоступны с хоста** ⭐
```bash
nc -zv localhost 3306 ; nc -zv localhost 9000
```
→ оба `refused`. *Негативная проверка — доказывает изоляцию, а не наличие пароля.*

**[ ] 22. Порт 80 закрыт**
```bash
curl -sS -m 5 http://akuzmin.42.fr/ ; echo "exit=$?"
```
→ connection refused. *Только 443. Редиректа с 80 быть не должно — порт не открыт.*

---

## 4. TLS (23–27)

**[ ] 23. Сайт отвечает по HTTPS**
```bash
curl -k -o /dev/null -w "%{http_code}\n" https://akuzmin.42.fr/
```
→ `200`.

**[ ] 24. TLS 1.0 и 1.1 отвергаются** ⭐
```bash
make tls-test
```
→ `tls1_1 refused`, `tls1_2 ACCEPTED`, `tls1_3 ACCEPTED`. *Главное требование по
TLS. Негативный результат важнее позитивного.*

**[ ] 25. Реально согласуется TLS 1.2/1.3**
```bash
echo | openssl s_client -connect akuzmin.42.fr:443 2>/dev/null | grep -E "Protocol|Cipher"
```
→ `Protocol : TLSv1.3` (или 1.2).

**[ ] 26. Сертификат на нужный домен**
```bash
echo | openssl s_client -connect akuzmin.42.fr:443 2>/dev/null \
  | openssl x509 -noout -subject -text | grep -A1 "Subject Alternative Name"
```
→ `CN=akuzmin.42.fr`, и `DNS:akuzmin.42.fr` в SAN. *Без SAN браузер даст
`ERR_CERT_COMMON_NAME_INVALID` вместо обычного предупреждения о самоподписанном
сертификате: современные браузеры CN игнорируют.*

*(Короткий вариант `-ext subjectAltName` есть в OpenSSL 1.1+, но не в LibreSSL,
которым по умолчанию собран macOS — на Debian-ВМ он работает.)*

**[ ] 27. Приватный ключ не в репозитории**
```bash
git ls-files | grep -iE "\.key$|\.pem$|\.crt$"
```
→ пусто. *Ключ генерируется на старте. Ключ в git = утёкший ключ.*

---

## 5. Домен и WordPress (28–33)

**[ ] 28. Домен резолвится в локальный адрес**
```bash
grep 42.fr /etc/hosts ; getent hosts akuzmin.42.fr
```
→ `127.0.0.1 akuzmin.42.fr` (или IP ВМ). *«This domain name must be login.42.fr».*

**[ ] 29. Отдаётся именно WordPress**
```bash
curl -sk https://akuzmin.42.fr/ | grep -oE "<title>[^<]*</title>|wp-content" | head -3
```
→ заголовок сайта и `wp-content`. *Значит цепочка nginx → php-fpm → mariadb
работает целиком.*

**[ ] 30. Админка отвечает**
```bash
curl -sk -o /dev/null -w "%{http_code}\n" https://akuzmin.42.fr/wp-admin/
```
→ `302` (редирект на логин). Затем войди в браузере под `WP_ADMIN_USER`.

**[ ] 31. Два пользователя, один админ** ⭐
```bash
docker exec wordpress wp --path=/var/www/html --allow-root user list --fields=user_login,roles
```
→ две строки: administrator + вторая роль. *«There must be two users, one of them
being the administrator».*

**[ ] 32. Имя админа без `admin`** ⭐
```bash
docker exec wordpress wp --path=/var/www/html --allow-root user list --role=administrator --field=user_login | grep -i admin
```
→ **пусто**. *Имя не должно содержать admin/Admin/administrator. Частая причина
провала.*

**[ ] 33. Второй пользователь реально может войти**
Зайди в браузере под `WP_USER` — пароль в `secrets/credentials.txt`.
→ вход проходит, прав меньше, чем у админа.

---

## 6. Тома и персистентность (34–37)

**[ ] 34. Тома именованные, привязаны к /home/login/data** ⭐
```bash
docker volume inspect srcs_wordpress-data --format '{{.Driver}} {{.Options}} {{.Mountpoint}}'
```
→ драйвер `local`, опции с `device:/home/akuzmin/data/wordpress`. *Named volume
(есть объект тома) + данные в `/home/login/data` — оба требования сразу.*

**[ ] 35. Нет bind-mount синтаксиса в сервисах**
```bash
grep -A6 "volumes:" srcs/docker-compose.yml | grep -E "^\s+- (/|\./|~)"
```
→ пусто. *Bind mounts для этих томов запрещены.*

**[ ] 36. На хосте реально лежат данные**
```bash
sudo ls /home/akuzmin/data/mariadb | head -3
sudo ls /home/akuzmin/data/wordpress | head -3
```
→ файлы БД и файлы WordPress (`wp-config.php`, `wp-content`).

**[ ] 37. Данные переживают перезапуск** ⭐
```bash
docker exec wordpress wp --path=/var/www/html --allow-root post create \
    --post_title="Persistence probe" --post_status=publish
make down && make && sleep 30
docker exec wordpress wp --path=/var/www/html --allow-root post list --fields=post_title
```
→ `Persistence probe` на месте. *Доказывает, что тома переиспользуются, а не
создаются заново.*

---

## 7. Секреты (38–40)

**[ ] 38. Паролей нет в окружении контейнеров** ⭐
```bash
docker inspect wordpress --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -i password
docker inspect mariadb  --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -i password
```
→ **пусто в обоих**. *Иначе пароль виден любому, кто может звать `docker inspect`.*

**[ ] 39. Секреты присутствуют как файлы**
```bash
docker exec wordpress ls /run/secrets/
docker exec wordpress grep secrets /proc/mounts
```
→ файлы есть, смонтированы `ro`. *Заодно посмотри, что это bind mount, а не
tmpfs — в Compose именно так, tmpfs только в Swarm. На этом ловят.*

**[ ] 40. Паролей нет в Dockerfile и в истории образа**
```bash
grep -riE "password|passwd" srcs/requirements/*/Dockerfile | grep -v "#"
docker history --no-trunc wordpress:inception | grep -ci password
```
→ пусто и `0`. *«No password must be present in your Dockerfiles».*

---

## Итог

```
пройдено ___/40      красных ___
```

Все 40 зелёных — техническая часть готова.

Отмеченные ⭐ (11, 13, 19, 20, 21, 24, 31, 32, 34, 37, 38) спрашивают почти всегда.
По каждой из них уметь ответить на два вопроса: **какую команду ввести** и
**что именно результат доказывает**.

Осталось `04-rewrite-from-memory.md` — там проверяется, сможешь ли ты это
написать, а не только запустить.
