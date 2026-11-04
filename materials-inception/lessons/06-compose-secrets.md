# Урок 6. Compose, Makefile и секреты

⏱ 1,5 часа · блок вопросов F (Q49–Q54)

**На защите:** пароль в репозитории даёт **оценку 0**. Ещё спросят про разницу образа с Compose и без него и про смысл структуры
каталогов.

## Прочитай

### Что делает Compose

Compose — клиент Docker. Он читает YAML и делает те же действия, что ты сделал бы вручную: `docker build`,
`network create`, `volume create`, `docker run` со всеми флагами, в нужном порядке.

**Образ с Compose и без него** — один и тот же образ. Разница в управлении: без Compose всё пишется и запускается вручную, с
Compose описано в одном файле в git. Compose также подключает сервисы к общей сети и даёт им DNS по именам.

### `depends_on` и готовность

| Запись | Чего ждёт |
|---|---|
| `depends_on: [mariadb]` | только запуска контейнера |
| `condition: service_healthy` | успешного `healthcheck` |

Проект использует второй вариант плюс `up --wait`, поэтому `make` возвращает управление, когда сайт уже отвечает. Цикл ожидания
в `setup.sh` всё равно нужен: когда контейнер после сбоя перезапускает сам демон Docker, Compose в этом не участвует.
Цикл выполняет настоящий вход в базу с паролем (`SELECT 1`), потому что открытый порт ещё не значит, что есть
пользователь и права.

### `.env` и секреты

| | `srcs/.env` | `secrets/*.txt` |
|---|---|---|
| Что хранит | домен, имя БД, имена пользователей | пароли |
| Критерий | утечка не даёт доступа | утечка даёт доступ |
| Как попадает в контейнер | переменные окружения (`env_file`) | файл `/run/secrets/<имя>` (только чтение) |
| В git | нет, только `.env.example` | нет |

### Как утекает переменная окружения

1. `docker inspect` показывает её открытым текстом.
2. `docker compose config` тоже.
3. Её наследуют дочерние процессы (`/proc/<pid>/environ`).
4. Заданная через `ENV` в Dockerfile, она остаётся в образе.

Секрет — это файл, поэтому ни в одном из этих мест его нет.

**Где ловят на защите.** В Swarm секрет шифруется и лежит в tmpfs. В Compose это обычный read-only bind mount файла с хоста, без
шифрования. Говорить «в Compose секреты в памяти» неверно. Проверка: `docker exec wordpress grep secrets /proc/mounts`.

### Почему `credentials.txt` читается через `grep`, а не `source`

`source` выполняет файл как код: пароль `a$(rm -rf /)b` запустит команду. `grep | cut` оставляет содержимое данными.

### Пароль попал в коммит

Удалить следующим коммитом недостаточно: он останется в истории и во всех клонах. Сначала сменить пароль, затем при необходимости
переписать историю. Проверка перед отправкой: `git ls-files | grep -E 'secrets/|\.env$'` должна быть пустой.

### Зачем такая структура каталогов

- Один каталог на сервис = один контекст сборки = один `Dockerfile`. `COPY` не может взять файлы другого сервиса.
- `conf/` — настройки сервиса, `tools/` — скрипты запуска.
- `secrets/` лежит вне всех контекстов сборки: пароль не попадёт в образ даже по ошибке.
- `Makefile` в корне — одна точка входа, `srcs/` — всё, что описывает конфигурацию.

### Прочитай в проекте

Прочитай `docker-compose.yml` и `Makefile` целиком. Для каждого блока объясни вслух, зачем он нужен и что сломается без него.

## Сделай руками

```bash
mkdir -p ~/lab/sec && cd ~/lab/sec
echo 'file-secret' > pw.txt
echo 'PLAIN=env-secret' > .env
```

**Шаг 1.** Напиши `docker-compose.yml` сам: сервис `demo` на `alpine:3.20`, команда `["sleep", "600"]`, `env_file: .env`, секрет
`pw` из файла `./pw.txt`. Сверься только если не получилось запустить.

```bash
docker compose up -d
C=$(docker compose ps -q demo)
docker inspect $C --format '{{range .Config.Env}}{{println .}}{{end}}' | grep PLAIN      # виден
docker inspect $C | grep -c file-secret                  # 0
docker compose config | grep -E 'PLAIN|file-secret'      # виден только PLAIN
docker compose exec demo sh -c 'tr "\0" "\n" < /proc/1/environ | grep PLAIN'             # виден
docker compose exec demo cat /run/secrets/pw             # file-secret
docker compose exec demo grep secrets /proc/mounts       # ro, не tmpfs
docker compose exec demo sh -c 'echo x > /run/secrets/pw'   # Read-only file system
docker compose down
```

**Шаг 2. Порядок запуска и готовность.** Сервис `db` готов только через 8 секунд:

```yaml
services:
  db:
    image: alpine:3.20
    command: ["sh", "-c", "sleep 8; touch /tmp/ready; exec sleep 600"]
  app:
    image: alpine:3.20
    command: ["sleep", "600"]
    depends_on:
      - db
```

```bash
time docker compose up -d                                 # около 1 секунды
docker compose exec db sh -c 'test -f /tmp/ready && echo yes || echo no'     # no
docker compose down -t 1
```

Теперь сам добавь `db` такой `healthcheck`, а в `app` укажи `condition: service_healthy`:

```yaml
    healthcheck:
      test: ["CMD", "test", "-f", "/tmp/ready"]
      interval: 2s
      retries: 20
```

Те же команды должны дать около 9 секунд и `yes`.

**Шаг 3. Опасность `source`:**

```bash
printf 'PW=a$(touch /tmp/pwned)b\n' > c.txt
bash -c 'source ./c.txt'; ls /tmp/pwned                  # файл создан: команда выполнилась
rm /tmp/pwned
grep -m1 '^PW=' c.txt | cut -d= -f2-; ls /tmp/pwned      # просто текст, файла нет
```

**Шаг 4. Проверка репозитория:**

```bash
cd ~/42-inception
git ls-files | grep -E 'secrets/|srcs/\.env$'            # пусто
git status --ignored --short | grep -E 'secrets|\.env'   # файлы есть, но игнорируются
bash tests/check_inception_rules.sh | tail -1            # failed: 0
```

**Запиши в [`labs.md`](../my-work/labs.md), раздел «Лаба 6»** и скажи «проверь лабу 6».

## Ответь

Блок F в [`answers.md`](../my-work/answers.md). Затем «проверь блок F».

## Глубже, по желанию

[Secrets в Compose](https://docs.docker.com/compose/how-tos/use-secrets/).
