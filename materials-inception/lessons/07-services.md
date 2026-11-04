# Урок 7. MariaDB, WordPress и NGINX

⏱ 3 часа · блок вопросов G (Q55–Q60) · смена порта

**На защите:** большинство пунктов таблицы проверяет именно эти сервисы.

## Прочитай

### Путь одного запроса. Выучи и расскажи без подсказок

Запрос `https://akuzmin.42.fr/`:

1. `/etc/hosts` превращает имя в адрес.
2. Браузер подключается к порту 443. Правило DNAT на хосте направляет трафик в контейнер nginx.
3. nginx и браузер выполняют TLS-рукопожатие: сертификат, версия протокола, ключи.
4. nginx расшифровывает запрос. `try_files $uri $uri/ /index.php?$args` не находит файла и передаёт запрос на `index.php`.
5. Блок `location ~ \.php$` отправляет его по FastCGI на `wordpress:9000`. Имя разрешает DNS Docker.
6. php-fpm берёт файл из `SCRIPT_FILENAME` и выполняет его в рабочем процессе.
7. WordPress читает `wp-config.php` и подключается к `mariadb:3306` как `wp_user`.
8. MariaDB возвращает данные, PHP строит HTML, ответ идёт обратно через nginx, зашифрованный TLS.

Статические файлы (CSS, картинки) nginx отдаёт сам с общего тома, без PHP.

### MariaDB

| Настройка | Зачем |
|---|---|
| `bind-address = 0.0.0.0` | иначе база слушает только свой loopback и WordPress из другого контейнера не подключится |
| `wp_user@'%'` | IP контейнера WordPress меняется, поэтому «с любого хоста»; изоляцию даёт сеть |
| `root@localhost` | root разрешён только локально, поэтому WordPress им не пользуется |

**Настройка при первом запуске (`init.sh`):**

1. `mysql_install_db` создаёт системные таблицы.
2. `mysqld --bootstrap` выполняет SQL с переднего плана и завершается. Таблица запрещает фоновые процессы, поэтому `mysqld &`
   нельзя. Порт в этот момент не открыт, поэтому к базе без пароля root подключиться невозможно.
3. Первым идёт `FLUSH PRIVILEGES`: в этом режиме таблицы привилегий не загружены, а `CREATE USER` они нужны.
4. Маркер записывается только после успеха, поэтому незавершённая настройка повторится.
5. `exec mysqld`.

**Два вида пользователей.** `siteowner` и `visitor` — пользователи **WordPress** (таблица `wp_users`), о них говорит Subject. `root` и `wp_user` —
пользователи **MariaDB**.

### WordPress и PHP-FPM

- **php-fpm** держит рабочие процессы, выполняющие PHP. nginx сам выполнять PHP не умеет.
- **FastCGI** — двоичный протокол между ними. nginx передаёт уже разобранные параметры (`SCRIPT_FILENAME`, `QUERY_STRING`), а не HTTP.
- **Порт, а не UNIX-сокет:** сокет — это файл в файловой системе одного контейнера, а nginx в другом. Общая у них только сеть.
- **WP-CLI** (`wp`) устанавливает WordPress и создаёт двух пользователей без браузера. На защите страницы установки быть не должно.

**`setup.sh`.** Каждый шаг проверяет свой результат: `wp-load.php`, `wp-config.php`, `wp core is-installed`, `wp user get`. Поэтому после сбоя
установка продолжается с нужного места.

`DB_HOST`, `WP_HOME`, `WP_SITEURL` применяются при **каждом** старте: `wp-config.php` лежит на томе и сам не обновится, а без этого смена порта
сломает сайт.

### NGINX и TLS

| Строка | Зачем |
|---|---|
| `ssl_protocols TLSv1.2 TLSv1.3;` | главное требование; остальные версии отключены |
| `listen 443 ssl http2;` | только 443. На nginx 1.22 из bookworm директивы `http2 on;` нет, и nginx с ней не запустится |
| `try_files $uri $uri/ /index.php?$args;` | постоянные ссылки: таких файлов нет на диске, запрос идёт в WordPress |
| `fastcgi_pass wordpress:9000;` | адрес php-fpm по имени сервиса |
| `fastcgi_param SCRIPT_FILENAME ...` | какой файл выполнить; путь верен, потому что том смонтирован по одному пути в обоих контейнерах |
| `fastcgi_param HTTPS on;` | TLS завершился в nginx, а PHP должен знать, что клиент на HTTPS, иначе появятся ссылки `http://` |
| `fastcgi_param HTTP_HOST $http_host;` | сохраняет порт в адресе, иначе на порту не 443 будет бесконечный редирект |

**Сертификат.** Самоподписанный, потому что `akuzmin.42.fr` — имя из `/etc/hosts`, и публичный центр сертификации его не подпишет. Шифрование
полноценное, предупреждение браузера относится только к доверию. Создаётся при запуске, чтобы приватный ключ не попал ни в git, ни в слой образа. SAN
нужен, потому что браузеры проверяют имя по нему, а не по CN.

**Шаблон и `envsubst`.** В `nginx.conf` нет своих переменных окружения, поэтому домен подставляется при старте. Список `'${DOMAIN_NAME}'` обязателен: иначе
`envsubst` сотрёт и переменные самого nginx (`$uri`, `$args`).

**В таблице написано «TLS v1.2 certificate» — это неточность.** Версию имеет протокол, а не сертификат.

### Прочитай в проекте

Прочитай целиком: `mariadb.cnf`, `init.sh`, `www.conf`, `setup.sh`, `nginx.conf.template`, `entrypoint.sh`. Для каждого файла объясни вслух каждую строку.
Что не можешь объяснить, запиши и спроси у меня.

## Сделай руками

`cd ~/42-inception/Inception`, стек запущен, `D=https://akuzmin.42.fr`.

**Шаг 1. Кто что обслуживает.** Предскажи результат **до** запуска:

```bash
curl -sk -o /dev/null -w 'readme: %{http_code}\n' $D/readme.html
docker stop wordpress
curl -sk -o /dev/null -w 'без php, readme: %{http_code}\n' $D/readme.html       # 200: статику отдаёт nginx
curl -sk -o /dev/null -w 'без php, главная: %{http_code}\n' $D/                 # 502: некому выполнить PHP
docker start wordpress; sleep 8

docker stop mariadb
curl -sk $D/ | grep -oi 'Error establishing a database connection'              # PHP работает, базы нет
docker start mariadb; sleep 6
curl -sk -o /dev/null -w 'всё работает: %{http_code}\n' $D/
```

**Шаг 2. TLS:**

```bash
make tls-test
echo | openssl s_client -connect akuzmin.42.fr:443 2>/dev/null | openssl x509 -noout -subject -issuer -ext subjectAltName
echo | openssl s_client -connect akuzmin.42.fr:443 -tls1_1 2>&1 | grep -E 'no protocols|alert'
echo | openssl s_client -connect akuzmin.42.fr:443 -tls1_1 -cipher 'DEFAULT@SECLEVEL=0' 2>&1 | grep -E 'no protocols|alert'
docker history --no-trunc nginx:inception | grep -c 'BEGIN PRIVATE'             # 0
```

Как читать ответ:

- `alert protocol version` — соединение **отклонил сервер**. Это и доказывает требование.
- `no protocols available` — запрос **не отправил твой клиент**: новые версии OpenSSL сами не предлагают TLS 1.1. О сервере это ничего не говорит.

Что покажет третья команда, зависит от версии OpenSSL на машине. Флаг `@SECLEVEL=0` в четвёртой команде заставляет клиент предложить старый протокол, поэтому её результат
всегда говорит о сервере. По этой же причине он есть в `make tls-test`.

**Шаг 3. Ловушка `envsubst`:**

```bash
docker exec nginx sh -c 'envsubst < /etc/nginx/nginx.conf.template | grep "try_files .*index"'
# try_files  / /index.php?;     <- конфиг молча сломан
docker exec nginx sh -c "envsubst '\${DOMAIN_NAME}' < /etc/nginx/nginx.conf.template | grep 'try_files .*index'"
```

**Шаг 4. База.** Пароль: `cat secrets/db_root_password.txt`.

```bash
docker exec -it mariadb mariadb -u root -p
```

```sql
SHOW DATABASES;
SELECT user, host FROM mysql.user;
SHOW GRANTS FOR 'wp_user'@'%';
SELECT @@bind_address, @@port;
USE wordpress;
SELECT user_login FROM wp_users;
exit
```

**Шаг 5. Найди и исправь неисправность.** Вноси по одной, сначала **предскажи** симптом, затем проверь. После каждой верни файл через
`git checkout -- <файл>` и запусти `make`.

| Измени | Файл | Что увидишь |
|---|---|---|
| Удали строку с `SCRIPT_FILENAME` | `nginx.conf.template` | 404 и `Primary script unknown` в логах |
| Добавь `http2 on;` в блок `http` | `nginx.conf.template` | `make` падает, `unknown directive "http2"` |
| `bind-address = 127.0.0.1` | `mariadb.cnf` | `make` успешен, на сайте ошибка базы, код 500 |

**Шаг 6. Смена порта.** Выполни варианты A, C и D из [runbook §12](../defense/runbook.md). С первого раза можно подглядывать, потом с таймером, 3 минуты на
каждый.

**Запиши в [`labs.md`](../my-work/labs.md), раздел «Лаба 7»** и скажи «проверь лабу 7». Затем скажи «сломай мне проект».

## Ответь

Блок G в [`answers.md`](../my-work/answers.md). Затем «проверь блок G».

## Глубже, по желанию

[nginx: модуль SSL](https://nginx.org/en/docs/http/ngx_http_ssl_module.html),
[конфигурация PHP-FPM](https://www.php.net/manual/en/install.fpm.configuration.php),
[команды WP-CLI](https://developer.wordpress.org/cli/commands/).
