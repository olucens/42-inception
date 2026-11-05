# Урок 2. Образы и Dockerfile

⏱ 1,5 часа · блок вопросов B (Q11–Q22)

Незнакомое слово ищи в [терминах](terms.md).

**На защите:** «одна служба — один свой Dockerfile», «почему bookworm», пароли в образе.

## Прочитай

**Образ** — неизменяемая стопка слоёв. **Контейнер** — запущенный процесс поверх образа плюс его
записываемый слой.

### Главные инструкции

| Инструкция | Что делает | Что важно |
|---|---|---|
| `FROM` | базовый образ | только Debian или Alpine с явным тегом |
| `RUN` | выполняет команду, результат становится слоем | очистка должна быть в том же `RUN` |
| `COPY` | копирует файлы из контекста сборки | предпочтительнее `ADD`, который ещё и распаковывает архивы и качает по URL |
| `ARG` | переменная сборки, в окружении контейнера её нет | значение всё равно видно в истории образа |
| `ENV` | переменная сборки и работы контейнера | сохраняется в образе, пароли сюда нельзя |
| `WORKDIR` | рабочий каталог | лучше, чем `cd` в `RUN` |
| `EXPOSE` | только документация | порт не публикует и связь не открывает |
| `ENTRYPOINT` | программа, которая запускается всегда | аргументы `docker run` становятся её аргументами |
| `CMD` | команда или аргументы по умолчанию | легко заменяется при `docker run` |

### Exec-форма и shell-форма

```dockerfile
ENTRYPOINT ["/usr/local/bin/init.sh"]    # exec-форма: скрипт сам становится PID 1
ENTRYPOINT /usr/local/bin/init.sh        # shell-форма: PID 1 это /bin/sh -c ...
```

В проекте везде exec-форма. Почему это критично, разберём в уроке 3.

### Кеш сборки

Docker кеширует результат каждой инструкции. Если изменилась инструкция или файл для неё, пересобирается
она и **всё, что ниже**. Поэтому сначала идёт редко меняющаяся установка пакетов, а копирование настроек — в
конце.

### Контекст сборки и `.dockerignore`

`docker build` отправляет демону весь каталог-контекст. `.dockerignore` исключает лишнее, чтобы сборка шла
быстрее, а `COPY .` случайно не взял пароль. В проекте у каждого сервиса свой контекст
(`srcs/requirements/<сервис>`), а `secrets/` лежит вне всех контекстов.

### «Предпоследняя стабильная версия» — как определить

Это значение вычисляется, а не заучивается. Открой <https://www.debian.org/releases/>: сейчас stable —
Debian 13 (trixie), значит предпоследняя — **Debian 12 (bookworm)**. Когда выйдет Debian 14, ответ
изменится.

### `latest` запрещён

Его запрещает Subject, и есть практическая причина: это просто имя тега, а не гарантия свежести. Тот же
Dockerfile позже соберёт другой образ. Тег без версии тоже означает `latest`, поэтому в проекте явно
написано `image: mariadb:inception`.

### Прочитай в проекте

Открой все три `Dockerfile` в `Inception/srcs/requirements/`. Для каждой строки объясни вслух, что она делает
и почему стоит на этом месте. Особое внимание двум местам:

- `--no-install-recommends` даёт меньше лишних пакетов и меньшую поверхность атаки.
- `DEBIAN_FRONTEND` объявлен как `ARG`, а не как `ENV`: настройка нужна только при сборке.
- `rm -rf /var/lib/mysql/*` в MariaDB: причину разберём в уроке 5.

## Сделай руками

```bash
mkdir -p ~/lab/img && cd ~/lab/img
```

**Шаг 1. Удаление в другом слое не уменьшает образ.** Создай два файла:

```dockerfile
# Dockerfile.bad
FROM debian:bookworm-slim
RUN apt-get update
RUN rm -rf /var/lib/apt/lists/*
```

```dockerfile
# Dockerfile.good
FROM debian:bookworm-slim
RUN apt-get update && rm -rf /var/lib/apt/lists/*
```

```bash
docker build -q -t lab:bad -f Dockerfile.bad .
docker build -q -t lab:good -f Dockerfile.good .
docker images | grep -E '^lab'         # bad заметно больше good
docker history lab:bad                 # виден слой apt-get update со своим весом
```

**Шаг 2. Кеш.** Напиши `Dockerfile.cache` сам: `FROM alpine:3.20`, затем `RUN echo slow-step`,
`COPY hello.txt /hello.txt`, `RUN cat /hello.txt`.

```bash
echo one > hello.txt
docker build --progress=plain -t lab:c -f Dockerfile.cache . 2>&1 | grep -E 'CACHED|^#[0-9]+ \['
docker build --progress=plain -t lab:c -f Dockerfile.cache . 2>&1 | grep -c CACHED
echo two > hello.txt
docker build --progress=plain -t lab:c -f Dockerfile.cache . 2>&1 | grep -E 'CACHED|^#[0-9]+ \['
```

Объясни, какие шаги взяты из кеша после изменения файла и почему.

**Шаг 3. Как утекает пароль.** Создай `Dockerfile.leak`:

```dockerfile
FROM alpine:3.20
ARG DB_PASS
ENV API_KEY=env-secret
RUN echo "$DB_PASS" > /dev/null
```

```bash
docker build -q --build-arg DB_PASS=arg-secret -t lab:leak -f Dockerfile.leak .
docker history --no-trunc lab:leak | grep arg-secret      # значение ARG видно
docker inspect lab:leak --format '{{.Config.Env}}'        # значение ENV видно
```

**Шаг 4. `ENTRYPOINT` и `CMD`.** Создай `Dockerfile.ec`:

```dockerfile
FROM alpine:3.20
ENTRYPOINT ["echo", "entry:"]
CMD ["default-arg"]
```

```bash
docker build -q -t lab:ec -f Dockerfile.ec .
docker run --rm lab:ec            # entry: default-arg
docker run --rm lab:ec custom     # entry: custom
```

**Шаг 5. `.dockerignore`:**

```bash
mkdir ctx && cd ctx
echo pw > secret.txt; echo ok > keep.txt
printf 'FROM alpine:3.20\nCOPY . /app\nCMD ["ls","/app"]\n' > Dockerfile
docker build -q -t lab:ctx . && docker run --rm lab:ctx      # secret.txt попал в образ
echo secret.txt > .dockerignore
docker build -q -t lab:ctx . && docker run --rm lab:ctx      # больше не попал
cd ..
```

**Шаг 6. Образы проекта:**

```bash
docker images | grep inception
docker history mariadb:inception
docker run --rm --entrypoint sh mariadb:inception -c 'ls -A /var/lib/mysql | wc -l'     # 0
```

**Уборка:** `docker rmi lab:bad lab:good lab:c lab:leak lab:ec lab:ctx`

**Запиши в [`labs.md`](../my-work/labs.md), раздел «Лаба 2»** и скажи «проверь лабу 2».

## Ответь

Блок B в [`answers.md`](../my-work/answers.md). Затем «проверь блок B».

## Глубже, по желанию

[Dockerfile reference](https://docs.docker.com/reference/dockerfile/).
