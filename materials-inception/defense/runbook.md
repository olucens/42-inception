# Защита Inception по реальной таблице оценки

Источник таблицы: [`evaluation-scale.pdf`](../sources/evaluation-scale.pdf)
(<https://www.42evalhub.com/common/inception>). Страница помечена как устаревшая,
поэтому перед защитой сверься с актуальной таблицей на Intra. Если они расходятся,
верить нужно Intra и Subject.

Разделы идут в том порядке, в каком идёт проверяющий. **СТОП** означает, что при
провале этого пункта проверка заканчивается.

Все команды выполняются из корня сданного репозитория, если не сказано иное.

---

## 0. Подготовка до прихода проверяющего

**Сдаётся не этот учебный репозиторий целиком.** Таблица требует, чтобы `Makefile`,
`srcs`, `README.md`, `USER_DOC.md` и `DEV_DOC.md` лежали **в корне репозитория**.
Здесь они внутри `Inception/`. В репозиторий Intra (Vogsphere) нужно положить именно
содержимое `Inception/`, без `materials-inception/`, `tests/`, `notes/`, PDF и архива:

```bash
git clone <URL репозитория с Intra> ~/inception-submit
cd ~/42-inception/Inception
git ls-files -z | xargs -0 -I{} cp --parents {} ~/inception-submit/
cd ~/inception-submit && ls -A
# .gitignore  DEV_DOC.md  Makefile  README.md  USER_DOC.md  srcs
git add . && git status          # проверь глазами: нет secrets/ и srcs/.env
git commit -m "Inception" && git push
```

**На VM заранее:**

- Пользователь VM — `akuzmin`, он в группе `docker`, у него есть `sudo`.
- Установлены `docker`, `docker compose` v2, `make`, `git`, `openssl`, браузер.
- В `/etc/hosts` есть `127.0.0.1 akuzmin.42.fr`.
- Заняты ли порты 443 и 80 чем-то ещё: `sudo ss -tlnp | grep -E ':(80|443) '` → пусто.
- Удалены старые данные: `sudo rm -rf /home/akuzmin/data/*`.

---

## 1. Preliminaries

**Что смотрит проверяющий:** в репозитории нет паролей. Найдены — **СТОП, оценка 0**.

```bash
git ls-files | grep -E 'secrets/|\.env$'        # пусто
git log --all --name-only --format= | sort -u | grep -E 'secrets/|\.env$'    # пусто
grep -rnIiE 'password *= *[^$ ]' . --exclude-dir=.git | grep -v '#'          # смотри глазами
```

**Клонирование в пустой каталог на твоей машине, затем:**

```bash
git clone <repo> ~/eval && cd ~/eval
make init     # создаёт srcs/.env и случайные секреты
```

Таблица это разрешает: «secrets files created during the evaluation».

**Ловушка.** `make init` создаёт новые пароли, а старые данные в `/home/akuzmin/data`
помнят прежние. WordPress тогда не войдёт в базу, и `docker logs wordpress` покажет
`cannot log in to MariaDB`. Поэтому `make init` предупреждает, а данные перед защитой
надо удалить (раздел 0).

---

## 2. General instructions

**Команда-очистка из таблицы (она удаляет ВСЁ в Docker на этой машине, запускай только
на VM):**

```bash
docker stop $(docker ps -qa); docker rm $(docker ps -qa); \
docker rmi -f $(docker images -qa); docker volume rm $(docker volume ls -q); \
docker network rm $(docker network ls -q) 2>/dev/null
```

Каталоги на хосте эта команда не трогает. Если там остались данные и секреты те же,
сайт поднимется со старым содержимым. Это нормальное поведение.

| Проверка (все — **СТОП**) | Команда | Что должно быть |
|---|---|---|
| `srcs` и `Makefile` в корне | `ls` | есть |
| Нет `network: host`, `links:` | `grep -nE 'network(_mode)?: *host\|links:' srcs/docker-compose.yml` | пусто |
| Есть `networks` | `grep -n '^networks:' srcs/docker-compose.yml` | есть |
| Нет `--link` | `grep -rn -- '--link' Makefile srcs` | пусто |
| Нет фоновых процессов и `tail -f` | `grep -nE '&\s*$\|tail -f\|sleep infinity\|while true' srcs/requirements/*/tools/*.sh` | пусто |
| Нет бесконечных циклов | читаешь `tools/*.sh` вместе с проверяющим | см. ниже |
| База | `grep -h '^FROM' srcs/requirements/*/Dockerfile` | `debian:bookworm-slim` |

**Что сказать, если спросят:**

- *«В `setup.sh` есть цикл и `sleep`».* Это `for i in $(seq 1 120)`: он ограничен и
  заканчивается либо успешным запросом, либо ошибкой. Запрещён цикл, который держит
  контейнер живым, а этот завершается до старта демона.
- *«`bash` в первой строке скрипта».* Таблица запрещает `bash` как процесс-заглушку
  (`nginx & bash`). Здесь `bash` только выполняет скрипт, который заканчивается `exec`.
- *«Почему bookworm?»* Сейчас stable — Debian 13 (trixie), предпоследняя —
  Debian 12 (bookworm). Проверяется на <https://www.debian.org/releases/>.

Затем: `make` — должен завершиться без ошибок. Он ждёт, пока все контейнеры станут
`healthy`, поэтому сайт отвечает сразу, как только `make` вернул управление.

---

## 3. Activity overview: объяснить простыми словами

Отрепетируй вслух, по минуте на вопрос. Не читай по бумаге.

**Как работают Docker и Docker Compose.** Docker запускает процессы в изоляции на общем
ядре. Клиент `docker` передаёт команду демону `dockerd`, тот через `containerd` и `runc`
создаёт контейнер: namespaces ограничивают, что процесс видит, cgroups — сколько он
потребляет, а OverlayFS собирает его файловую систему из неизменяемых слоёв образа и
одного записываемого слоя. Compose — это клиент, который читает YAML и делает те же
вызовы API: собирает образы, создаёт сеть и тома, запускает контейнеры в нужном порядке.

**Образ с Compose и без Compose.** Сам образ тот же самый, разница в управлении. Без
Compose я вручную пишу `docker build` и длинный `docker run` с сетью, томами, секретами и
политикой рестарта для каждого сервиса и сам соблюдаю порядок запуска. С Compose всё это
описано в одном файле, который лежит в git, и запускается одной командой. Compose также
объединяет сервисы в проект и подключает их к общей сети с DNS по именам сервисов.

**Преимущество Docker перед VM.** Контейнер не загружает своё ядро: это обычный процесс
на ядре хоста. Поэтому он стартует за доли секунды, занимает мегабайты и описывается
файлами, которые воспроизводят среду. Цена — изоляция слабее: граница VM — гипервизор, а
граница контейнера — системные вызовы общего ядра, поэтому чужой недоверенный код надёжнее
запускать в VM. Поэтому же проект работает внутри VM, а контейнеры — внутри неё.

**Зачем такая структура каталогов.**

- Один каталог на сервис = один контекст сборки = один `Dockerfile`. `COPY` физически не
  может взять файлы другого сервиса.
- `conf/` и `tools/` разделяют настройки сервиса и скрипты запуска.
- `secrets/` лежит вне `srcs/requirements/`, то есть вне любого контекста сборки: пароль
  не может попасть в образ даже по ошибке в `COPY`.
- `Makefile` в корне — единая точка входа, `srcs/` — всё, что описывает конфигурацию.

---

## 4. README и документация (**СТОП**)

```bash
head -1 README.md
grep -n '^#' README.md | head -20
wc -l USER_DOC.md DEV_DOC.md
```

- Первая строка: `*This project has been created as part of the 42 curriculum by akuzmin.*`
- Есть разделы Description, Instructions, Resources с описанием использования ИИ.
- `USER_DOC.md`: запуск и остановка, сайт и админка, пароли, базовые проверки.
- `DEV_DOC.md`: требования, настройка, Makefile, команды Compose, хранение данных.

**Раздел про ИИ должен быть правдивым.** Subject разрешает только то, что ты полностью
понимаешь. Прочитай раздел и поправь его под то, как всё было на самом деле: на защите он должен
совпасть с твоим рассказом.

---

## 5. Simple setup (**СТОП**)

```bash
docker compose -f srcs/docker-compose.yml ps    # только nginx публикует 443
curl -s -m 4 http://akuzmin.42.fr/; echo "exit=$?"    # exit=7: соединение отклонено
```

Открой в браузере `https://akuzmin.42.fr`. Появится предупреждение о сертификате: нажми
«Дополнительно → Перейти» (в Chrome можно набрать `thisisunsafe`). Должен открыться сайт, а
**не страница установки WordPress**.

---

## 6. Docker Basics (**СТОП**)

```bash
wc -l srcs/requirements/*/Dockerfile          # три непустых файла
grep -h '^FROM' srcs/requirements/*/Dockerfile
docker images                                 # mariadb, wordpress, nginx с тегом inception
docker compose -f srcs/docker-compose.yml ps  # все Up (healthy)
```

- Имя образа совпадает с именем сервиса: `image: mariadb:inception`. Явный тег нужен,
  потому что без него был бы запрещённый `latest`.
- Образ `debian:bookworm-slim` скачивается с Docker Hub, и это разрешено Subject'ом:
  «Alpine/Debian being excluded from this rule».

---

## 7. Docker Network (**СТОП**)

```bash
grep -n -A3 '^networks:' srcs/docker-compose.yml
docker network ls                                  # inception-network, bridge
docker network inspect inception-network --format '{{range .Containers}}{{.Name}} {{.IPv4Address}}{{"\n"}}{{end}}'
docker exec nginx getent hosts wordpress
```

**Простое объяснение.** Docker-сеть — это виртуальный коммутатор. Каждый контейнер
подключён к нему своим виртуальным кабелем (veth) и получает свой IP. В пользовательской
сети работает встроенный DNS на `127.0.0.11`, поэтому контейнеры находят друг друга по
имени сервиса: `fastcgi_pass wordpress:9000`. Наружу виден только опубликованный порт 443.

---

## 8. NGINX и TLS (**СТОП**)

```bash
curl -s -m 4 http://akuzmin.42.fr/; echo "exit=$?"  # порт 80 не отвечает
make tls-test
# tls1 refused / tls1_1 refused / tls1_2 ACCEPTED / tls1_3 ACCEPTED
echo | openssl s_client -connect akuzmin.42.fr:443 2>/dev/null | grep -E 'Protocol|New,'
grep -n ssl_protocols srcs/requirements/nginx/conf/nginx.conf.template
```

**Точность формулировки.** В таблице написано «TLS v1.2 or v1.3 certificate». Версию
имеет не сертификат, а **протокол**. Сертификат подтверждает, кто владелец домена, а
протокол `ssl_protocols TLSv1.2 TLSv1.3;` определяет, как шифруется соединение.

**Почему `make tls-test` использует `@SECLEVEL=0`.** Новые версии OpenSSL сами могут не предлагать
TLS 1.1 (`no protocols available`), и такой отказ ничего не говорит о сервере. С флагом клиент
предлагает старый протокол, и его отвергает именно NGINX (`alert protocol version`).

**Почему сертификат самоподписанный.** `akuzmin.42.fr` — имя из `/etc/hosts`, публичный
центр сертификации такой домен не подпишет. Шифрование при этом полноценное, а
предупреждение браузера относится только к тому, кто поручился за сертификат.

---

## 9. WordPress + php-fpm и том (**СТОП**)

```bash
grep -i nginx srcs/requirements/wordpress/Dockerfile     # пусто
docker exec wordpress sh -c 'command -v nginx || echo нет'
docker volume ls
docker volume inspect srcs_wordpress-data | grep device  # /home/akuzmin/data/wordpress
```

**В браузере** (пароли: `cat secrets/credentials.txt`):

1. **Комментарий.** Войди как `visitor` на `/wp-login.php`, открой запись «Hello world!»,
   оставь комментарий. Он сразу появится на странице.
   - Второй комментарий быстрее чем через 15 секунд WordPress отклонит: «posting comments
     too quickly». Это его защита от флуда, а не поломка.
2. **Админка.** Выйди и войди как `siteowner` на `/wp-admin/`. В имени нет `admin`.
3. **Правка страницы.** Pages → Sample Page → Edit, измени заголовок, Update, затем View
   Page. Изменение видно на сайте.

---

## 10. MariaDB и том (**СТОП**)

```bash
grep -i nginx srcs/requirements/mariadb/Dockerfile       # пусто
docker volume inspect srcs_mariadb-data | grep device    # /home/akuzmin/data/mariadb
docker exec -it mariadb mariadb -u root -p               # пароль: secrets/db_root_password.txt
```

```sql
SHOW DATABASES;
USE wordpress;
SHOW TABLES;
SELECT user_login FROM wp_users;       -- siteowner, visitor
SELECT user, host FROM mysql.user;     -- root@localhost, wp_user@%
```

**Не путай два вида пользователей.** `siteowner` и `visitor` — пользователи **WordPress**,
строки в таблице `wp_users`; именно о них пишет Subject. `root` и `wp_user` — пользователи
**MariaDB**. WordPress подключается к базе как `wp_user`.

---

## 11. Persistence (**СТОП**)

Сделай правки из раздела 9 **до** этого шага, затем:

```bash
sudo reboot
# после загрузки:
cd ~/eval && make
```

Проверь комментарий и изменённую страницу. Команда `make down && make` — это **не** тот
тест, который просит таблица: нужна настоящая перезагрузка VM.

Контейнеры могут подняться сами ещё до `make`, потому что политика `unless-stopped`
запускает их при старте демона. `make` при этом ничего не сломает.

**Почему данные живы.** Они лежат не в записываемом слое контейнера, а в named volumes, в
`/home/akuzmin/data`. Скрипты при старте видят, что всё уже сделано, и пропускают настройку.

---

## 12. Configuration modification (**СТОП**)

Проверяющий просит сменить порт сервиса. Каждый вариант проверен на живом стеке.

Сначала назови, что и почему меняешь. После правки: `make`, затем проверка.

### A. NGINX: внешний порт 443 → 8443

| Файл | Правка |
|---|---|
| `srcs/docker-compose.yml` | `- "8443:443"` |
| `srcs/.env` | `WP_URL=https://akuzmin.42.fr:8443` |

```bash
make
curl -skL -o /dev/null -w '%{http_code} redirects=%{num_redirects}\n' https://akuzmin.42.fr:8443/   # 200 redirects=0
```

**Почему меняется `WP_URL`.** WordPress строит все ссылки из этого адреса. Если его не
сменить, CSS и вход в админку будут указывать на закрытый порт 443. `setup.sh` применяет
`WP_HOME` при каждом старте, поэтому новое значение дойдёт до сайта.

### B. NGINX: порт 8443 и внутри контейнера

То же, что A, но `- "8443:8443"`, плюс `listen 8443 ssl http2;` в
`requirements/nginx/conf/nginx.conf.template` и `EXPOSE 8443` в его `Dockerfile`.

### C. PHP-FPM: 9000 → 9001

| Файл | Правка |
|---|---|
| `requirements/wordpress/conf/www.conf` | `listen = 0.0.0.0:9001` |
| `requirements/nginx/conf/nginx.conf.template` | `fastcgi_pass wordpress:9001;` |
| `srcs/docker-compose.yml` | `expose: - "9001"` у wordpress |
| `requirements/wordpress/Dockerfile` | `EXPOSE 9001` |

```bash
make
curl -sk -o /dev/null -w '%{http_code}\n' https://akuzmin.42.fr/       # 200
docker exec wordpress sh -c "grep -E '^listen' /etc/php/8.2/fpm/pool.d/www.conf"
```

Порт нужно менять с двух сторон: сервер слушает, клиент подключается.

### D. MariaDB: 3306 → 3307

| Файл | Правка |
|---|---|
| `requirements/mariadb/conf/mariadb.cnf` | `port = 3307` |
| `srcs/.env` | `MYSQL_PORT=3307` |
| `srcs/docker-compose.yml` | `expose: - "3307"` у mariadb |
| `requirements/mariadb/Dockerfile` | `EXPOSE 3307` |

```bash
make
curl -sk -o /dev/null -w '%{http_code}\n' https://akuzmin.42.fr/       # 200
docker exec wordpress wp --path=/var/www/html --allow-root config get DB_HOST    # mariadb:3307
```

**Что будет, если забыть `EXPOSE`.** Ничего не сломается: это документация. `docker ps`
покажет два порта, например `3306-3307/tcp`. Проверяющему лучше сказать об этом самому.

### Откат

```bash
git checkout -- srcs        # файлы под git
# srcs/.env не под git: верни значения вручную или: rm srcs/.env && make init
make
```

---

## 13. Если что-то потерялось или сломалось

### Симптом → причина → действие

| Симптом | Причина | Действие |
|---|---|---|
| `ERROR: ... is missing. Run: make init` | свежий клон | `make init` |
| `no such file or directory` у тома | нет каталога данных | `make` создаст его целью `setup` |
| `wordpress` не становится healthy, в логах `cannot log in to MariaDB` | секреты новые, данные старые | вернуть старые секреты или `make fclean && make` |
| `502 Bad Gateway` | PHP-FPM лежит | `docker logs wordpress` |
| `ERR_TOO_MANY_REDIRECTS` | `WP_URL` не совпадает с адресом в браузере | поправить `.env`, `make` |
| Сайт без стилей | то же | то же |
| `Address already in use` на 443 | порт занят | `sudo ss -tlnp \| grep :443` |
| контейнер `Restarting` | падает при старте | `docker logs --tail 40 <имя>` |
| `make fclean` просит пароль | файлы принадлежат `mysql`/`www-data` | это ожидаемо: нужен `sudo` |

### Потерян файл

Всё, кроме `srcs/.env` и `secrets/`, лежит в git: `git checkout -- <файл>`. Но требование
подготовки строже: уметь написать файл заново. Ниже минимум, без которого файл не
работает. Полная тренировка — в [уроке 8](../lessons/08-rewrite.md).

| Файл | Ядро, которое надо помнить |
|---|---|
| `Makefile` | `compose -f srcs/docker-compose.yml`; `mkdir -p` данных; `up --build -d --wait`; `down --rmi all -v`; `sudo rm -rf` |
| `docker-compose.yml` | 3 сервиса: `build`, `image: X:inception`, `env_file`, `networks`, `restart`, `healthcheck`; `secrets:` с `file:`; `volumes:` с `driver_opts` (`type: none`, `o: bind`, `device`); сеть `driver: bridge`; `ports` только у nginx |
| `mariadb/Dockerfile` | `FROM debian:bookworm-slim`; `apt-get install mariadb-server mariadb-client`; `rm -rf /var/lib/mysql/*`; `COPY` конфига и скрипта; `ENTRYPOINT` в exec-форме |
| `mariadb.cnf` | `bind-address = 0.0.0.0`; `port`; `datadir`; `socket` |
| `init.sh` | пароли из `/run/secrets`; `chown`; маркер; `mysql_install_db`; `mysqld --bootstrap <<SQL` с `USE mysql; FLUSH PRIVILEGES;` в начале; `exec mysqld --user=mysql` |
| `wordpress/Dockerfile` | `php8.2-fpm php8.2-mysql`, клиент MariaDB, WP-CLI с закреплённой версией; `mkdir /run/php`; `www.conf`; `ENTRYPOINT` |
| `www.conf` | `listen = 0.0.0.0:9000`; `user`, `group`; `pm` |
| `setup.sh` | ожидание БД; `core download`; `config create`; `config set` при каждом старте; `core install`; `user create`; `chown`; `exec php-fpm8.2 --nodaemonize` |
| `nginx/Dockerfile` | `nginx openssl gettext-base`; шаблон; `rm` default vhost; `ENTRYPOINT` |
| `nginx.conf.template` | `listen 443 ssl`; `ssl_protocols TLSv1.2 TLSv1.3`; `root`; `try_files`; `fastcgi_pass wordpress:9000`; `SCRIPT_FILENAME`; `HTTPS on`; `HTTP_HOST $http_host` |
| `entrypoint.sh` | `envsubst '${DOMAIN_NAME}'`; `openssl req -x509 -nodes` с SAN; `nginx -t`; `exec nginx -g "daemon off;"` |
| `.env` | `DOMAIN_NAME`, `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PORT`, `WP_DB_HOST`, `WP_TITLE`, `WP_URL`, `WP_ADMIN_*`, `WP_USER*` |

---

## 14. Вопросы строгого проверяющего

Ответь сам и только потом сверяйся.

1. **«Том с `o: bind` — это же bind mount. Subject его запрещает».**
   Механизм монтирования действительно bind, это честно признаю. Но Subject требует два
   условия сразу: named volume и данные в `/home/login/data`. Это именованный объект Docker с
   драйвером и жизненным циклом: он виден в `docker volume ls`, удаляется `down -v`, и
   сервисы ссылаются на него по имени. Запрещённый вариант — `- /path:/var/lib/mysql` в
   сервисе, без объекта тома.
2. **«Docker secrets работают только в Swarm».** В Compose они реализованы как read-only
   bind mount файла в `/run/secrets`, без шифрования и tmpfs. Проверка:
   `docker exec wordpress grep secrets /proc/mounts`. Выигрыш перед переменными окружения
   есть: пароль не виден в `docker inspect` и не наследуется процессами.
3. **«Где пароль базы лежит в открытом виде?»** В `secrets/`, не в git, и в `wp-config.php` на
   томе: WordPress без него не подключится. HTTP-доступ к файлу закрыт
   (`location = /wp-config.php { deny all; }`, ответ 403).
4. **«Почему не `mysqld &` с временным сервером?»** Таблица запрещает фоновые программы в
   entrypoint. `--bootstrap` работает на переднем плане и не открывает порт, пока у root нет
   пароля.
5. **«Что будет, если SQL упадёт в середине?»** `mysqld --bootstrap` завершится с ошибкой,
   `set -e` остановит скрипт, маркер не появится. Контейнер перезапустится и повторит
   настройку. Проверено паролем с символом `'`.
6. **«Что будет, если контейнер упадёт в середине установки WordPress?»** При рестарте каждый
   шаг проверит свой результат и продолжит с незавершённого. Проверено: удалял пользователя
   и `wp-load.php`.
7. **«Что делает `exec` и что будет без него?»** Заменяет процесс shell демоном с тем же PID,
   поэтому демон получает SIGTERM от `docker stop` напрямую. Без него PID 1 останется shell:
   он не передаст сигнал, через 10 секунд придёт SIGKILL, и база может остановиться в
   середине записи.
8. **«`docker kill mariadb` — контейнер не поднялся. Где перезапуск?»** Docker считает
   `docker kill` и `docker stop` ручной остановкой при любой политике. Настоящий сбой:
   `sudo kill -9 $(docker inspect -f '{{.State.Pid}}' mariadb)`. После этого
   `docker inspect mariadb -f '{{.RestartCount}}'` покажет увеличение.
9. **«`docker exec mariadb kill -9 1` ничего не делает».** Ядро не доставляет процессу с
   PID 1 сигнал из его же PID namespace, если на сигнал нет обработчика, а на SIGKILL его
   поставить нельзя.
10. **«Почему `unless-stopped`, а не `on-failure`?»** `kill 1` изнутри завершает демон с кодом
    0, и при `on-failure` контейнер остался бы лежать. Ручная остановка уважается в обоих
    случаях.
11. **«Зачем healthcheck и цикл ожидания одновременно?»** `service_healthy` работает только во
    время `compose up`. Перезапуск после падения делает демон Docker, без Compose, и его
    закрывает цикл.
12. **«Что именно проверяет healthcheck WordPress?»** Что PID 1 стал `php-fpm`, то есть
    установка завершилась и выполнился `exec`. Зависшего воркера он не заметит. Для этого
    проекта его цель — порядок запуска, а не мониторинг, и он не зависит от номера порта.
13. **«Почему FPM слушает TCP, а не UNIX-сокет?»** Сокет — файл в файловой системе одного
    контейнера, а NGINX в другом. Их объединяет сеть.
14. **«Почему том смонтирован в NGINX как `:ro`?»** NGINX только читает статику. Взломанный
    NGINX не сможет записать PHP-файл, который затем выполнит FPM.
15. **«Зачем `fastcgi_param HTTP_HOST $http_host`?»** `fastcgi_params` из пакета Debian передаёт
    `$host` без порта. На нестандартном порту WordPress видел бы адрес, отличный от
    `WP_HOME`, и бесконечно редиректил на самого себя.
16. **«Почему именно `MYSQL_HOST` нельзя было оставить?»** Клиент MariaDB читает эту переменную
    как хост по умолчанию. В контейнере mariadb `mariadb -u root -p` уходил бы по TCP и получал
    `Access denied`, потому что root разрешён только с `localhost`.
17. **«Почему `/var/lib/mysql` очищается в Dockerfile?»** Пакет создаёт там системные таблицы при
    сборке, и Docker скопировал бы их в пустой том при первом запуске. Настройка должна
    выполняться на настоящем томе.
18. **«Измени код: добавь третьего пользователя WordPress».** В `setup.sh`, по образцу второго:
    переменные в `.env`, пароль в `credentials.txt`, блок `wp user get … || wp user create …`.
    Сработает на следующем `make`, даже на уже установленном сайте.

---

## 15. Как отвечать

1. Сначала команда, затем что должно получиться, затем почему это доказывает требование.
2. Не знаешь — так и скажи, а потом предложи способ проверить. Выдуманный ответ хуже.
3. Показывай в коде, а не пересказывай по памяти: открой файл и укажи строку.
4. Проверяющий имеет право понимать проект иначе. Спорь спокойно и опирайся на текст Subject.
