# Урок 5. Хранение данных

⏱ 1 час · блок вопросов E (Q41–Q48)

**На защите:** `docker volume inspect` должен показать `/home/akuzmin/data/`, а данные должны пережить перезагрузку.

## Прочитай

### Три вида хранения

| Вид | Что это | Что с данными при удалении контейнера |
|---|---|---|
| Записываемый слой | часть контейнера | пропадают |
| **Named volume** | объект Docker с именем и драйвером | остаются |
| **Bind mount** | путь хоста, смонтированный напрямую | остаются |
| tmpfs | в памяти | пропадают |

### Требование Subject: два условия сразу

- Только **named volumes**, bind mounts запрещены.
- Данные должны лежать в **`/home/login/data`**.

Обычный named volume лежит в `/var/lib/docker/volumes/`, а обычный bind mount запрещён. Решение — named volume с
драйвером `local`, которому указан каталог:

```yaml
volumes:
  mariadb-data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/akuzmin/data/mariadb
```

Запрещённый вариант выглядит так, прямо внутри сервиса: `- /home/akuzmin/data/mariadb:/var/lib/mysql`.

**Честный ответ на вопрос «это же bind?»:** механизм монтирования действительно bind. Разница в том, что это объект
Docker: он есть в `docker volume ls`, удаляется через Docker, сервисы обращаются к нему по имени.

### Три поведения, которые надо знать

Каждое проверишь в лабе.

1. **Каталог должен существовать заранее.** Обычный bind mount Docker создаст сам, а том с `o: bind` выдаст ошибку.
   Поэтому в Makefile есть цель `setup` с `mkdir -p`.
2. **Пустой том заполняется из образа.** Если в образе по этому пути есть файлы, Docker скопирует их в пустой том при
   первом запуске. Поэтому в Dockerfile MariaDB есть `rm -rf /var/lib/mysql/*`: иначе том получил бы системные таблицы
   из сборки, а не созданные скриптом. Заполняется том только один раз, поэтому новая сборка образа не обновит уже
   заполненный том. Поэтому WordPress скачивается при запуске, а не в Dockerfile.
3. **`docker volume rm` не удаляет файлы тома с `o: bind`.** Удаляется только объект, файлы остаются в каталоге. Поэтому
   в `make fclean` есть отдельный `sudo rm -rf`, а `sudo` нужен потому, что файлы принадлежат `mysql` и `www-data`.

### Что переживает каждая команда

| Команда | Контейнеры | Образы | Объекты томов | Данные на диске |
|---|---|---|---|---|
| `make down` | удалены | есть | есть | **есть** |
| `make clean` | удалены | удалены | есть | **есть** |
| `make fclean` | удалены | удалены | удалены | **удалены** |
| команда очистки из таблицы | удалены | удалены | удалены | **есть** |

### Том в nginx только для чтения

`wordpress-data:/var/www/html:ro`. NGINX только отдаёт статику. Если его взломают, он не сможет записать `shell.php`,
который потом выполнил бы PHP-FPM.

### Прочитай в проекте

В `docker-compose.yml` найди оба тома и `:ro`. В `Makefile` найди `setup` и `fclean`. В Dockerfile MariaDB найди
очистку `/var/lib/mysql`.

## Сделай руками

**Шаг 1. Записываемый слой пропадает:**

```bash
docker run --name lab-w alpine:3.20 sh -c 'echo hi > /f.txt'
docker diff lab-w                                     # A /f.txt
docker rm lab-w
docker run --rm alpine:3.20 cat /f.txt                # нет файла
```

**Шаг 2. Named volume остаётся:**

```bash
docker volume create labvol
docker run --rm -v labvol:/data alpine:3.20 sh -c 'echo persistent > /data/f.txt'
docker run --rm -v labvol:/data alpine:3.20 cat /data/f.txt        # persistent
docker volume inspect labvol -f '{{.Mountpoint}}'
docker volume rm labvol
```

**Шаг 3. Пустой том заполняется из образа, в том числе том с `o: bind`:**

```bash
mkdir /tmp/bv
docker volume create --driver local -o type=none -o o=bind -o device=/tmp/bv bvol
docker run --rm -v bvol:/etc/apk alpine:3.20 true
ls /tmp/bv                                            # файлы из образа
docker volume inspect bvol -f '{{.Driver}} {{.Options}}'
docker volume rm bvol
ls /tmp/bv | wc -l                                    # файлы остались: удалён только объект
sudo rm -rf /tmp/bv                                   # файлы принадлежат root
```

**Шаг 4. Несуществующий каталог даёт ошибку, а обычный bind создаётся сам:**

```bash
docker volume create --driver local -o type=none -o o=bind -o device=/tmp/nonexist nvol
docker run --rm -v nvol:/x alpine:3.20 true           # ошибка монтирования: no such file or directory
docker volume rm nvol

docker run --rm -v /tmp/auto-created:/x alpine:3.20 true
ls -ld /tmp/auto-created                              # создан, владелец root
docker volume ls | grep auto                          # пусто: это не объект Docker
sudo rm -rf /tmp/auto-created
```

**Шаг 5. Только чтение:**

```bash
docker exec nginx touch /var/www/html/shell.php       # Read-only file system
```

**Шаг 6. Команды проекта.** После каждой команды заполни строку таблицы выше, не подглядывая:

```bash
cd ~/42-inception/Inception
check() { echo "containers=$(docker ps -aq --filter name=mariadb | wc -l) images=$(docker images -q '*:inception' | wc -l) volumes=$(docker volume ls -q | grep -c srcs_) data=$(sudo ls /home/akuzmin/data/mariadb 2>/dev/null | wc -l)"; }
make down;   check
make;        make clean;  check
make;        make fclean; check
make                       # возвращаем стек
docker volume inspect srcs_mariadb-data | grep device
```

**Запиши в [`labs.md`](../my-work/labs.md), раздел «Лаба 5»** и скажи «проверь лабу 5».

## Ответь

Блок E в [`answers.md`](../my-work/answers.md). Затем «проверь блок E».

## Глубже, по желанию

[Docker volumes](https://docs.docker.com/engine/storage/volumes/).
