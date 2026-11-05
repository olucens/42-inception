# Урок 8. Написать проект с нуля

⏱ 3 часа

Незнакомое слово ищи в [терминах](terms.md).

**На защите:** таблица требует изменить проект прямо при проверяющем, а Subject предупреждает о провале, если автор не может объяснить свой код. Здесь
проверяется, можешь ли ты написать проект, а не просто его запустить.

## Правила

```bash
cd ~/42-inception
git checkout -b drill-1
rm -rf Inception/srcs/requirements/*/conf/* Inception/srcs/requirements/*/tools/* \
       Inception/srcs/requirements/*/Dockerfile \
       Inception/srcs/docker-compose.yml Inception/Makefile
```

**Можно:** `man`, официальная документация, `--help`, собственные логи.

**Нельзя:** свой прежний код, уроки, ИИ, чужие репозитории.

**Подглядывать можно**, но каждый раз записывай, **что именно** искал, в [`labs.md`](../my-work/labs.md), раздел «Лаба 8». Этот список и есть главный результат.

Не успеваешь за 3 часа: остановись на том, где дошёл. На защите важнее понимать структуру, чем помнить каждый флаг.

## Этап 1. На бумаге, 15 минут

1. Нарисуй схему: контейнеры, порты, тома, что опубликовано наружу.
2. Выпиши 11 файлов, которые предстоит создать.
3. Для каждого сервиса напиши **последнюю строку** его entrypoint.
4. Выпиши по памяти строку `ssl_protocols`, блок `volumes:` и блок `networks:`.

## Этап 2. MariaDB, 45 минут

Снизу вверх: каждый слой проверяется до того, как на него что-то ставится.

**Напиши:** `Dockerfile`, `conf/mariadb.cnf`, `tools/init.sh`, `docker-compose.yml` с одним сервисом.

Вспомни сам:

- база и тег, почему именно этот;
- почему очистка apt в том же `RUN` и почему пустой `/var/lib/mysql`;
- `bind-address`;
- `mysqld --bootstrap`: почему не `mysqld &` и зачем первым идёт `FLUSH PRIVILEGES`;
- маркер: где и когда пишется;
- пароли из `/run/secrets/`, а не из окружения;
- последняя строка.

```bash
mkdir -p /home/akuzmin/data/mariadb
docker compose -f Inception/srcs/docker-compose.yml up --build -d
docker logs mariadb | grep mariadb-init
docker exec mariadb cat /proc/1/comm                  # mysqld
docker exec -it mariadb mariadb -u root -p -e "SHOW DATABASES; SELECT user,host FROM mysql.user;"
```

Должны быть база `wordpress` и пользователь `wp_user@%`.

## Этап 3. WordPress, 45 минут

**Напиши:** `Dockerfile`, `conf/www.conf`, `tools/setup.sh`, добавь сервис в Compose.

Вспомни сам:

- какие пакеты нужны и зачем каждый;
- на чём слушает FPM и почему не сокет;
- зачем цикл ожидания при наличии healthcheck;
- что проверяет каждый шаг установки;
- что применяется при каждом старте и как это связано со сменой порта;
- два пользователя и ограничение на имя администратора;
- зачем `chown` в конце;
- флаги php-fpm в последней строке.

```bash
docker exec wordpress cat /proc/1/comm                # php-fpm8.2
docker exec wordpress wp --path=/var/www/html --allow-root user list
```

## Этап 4. NGINX, 30 минут

**Напиши:** `Dockerfile`, `conf/nginx.conf.template`, `tools/entrypoint.sh`, добавь сервис.

Вспомни сам: `ssl_protocols`, откуда берётся сертификат, SAN, ловушка `envsubst`, `try_files`, все `fastcgi_param` и зачем каждый, `:ro`, последняя строка.

```bash
docker exec nginx cat /proc/1/comm                    # nginx
curl -k -o /dev/null -w "%{http_code}\n" https://akuzmin.42.fr/
```

## Этап 5. Makefile и полная проверка, 30 минут

**Напиши:** `Makefile` с целями `all`, `init`, `check`, `setup`, `down`, `clean`, `fclean`, `re`, `tls-test`.

```bash
cd Inception && make re && make tls-test
```

## Разбор

Только после того, как закончил:

```bash
git add -A && git commit -m "drill" 
git diff solution/core -- Inception/
```

Ищи не отличия, а **где у тебя хуже и почему**. Другой рабочий вариант — это нормально, а выбор без причины — нет.

Вернись на основную ветку: `git checkout solution/core`.

## Оценка

| Результат | Вывод |
|---|---|
| Всё работает, до 2 подглядываний | отлично |
| Всё работает, до 8 подглядываний | проверка пройдена; разбери список |
| Больше 8, или застрял намертво | вернись к уроку этой темы и повтори этот сервис |

Подглядывать в синтаксис не страшно, его смотрят и на работе. Плохо, если пришлось подглядывать в **структуру** или **причину**: значит, не понята архитектура.

Скажи «проверь лабу 8» и пришли список.
