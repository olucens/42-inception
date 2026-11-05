# Урок 0. Среда и первый запуск

⏱ 2,5 часа. Большая часть уходит на установку системы.

Незнакомое слово ищи в [терминах](terms.md).

**Результат:** на домашнем компьютере есть VM, почти как в школе, в её браузере открывается сайт, а Claude Code работает в VS Code прямо в этой VM.

## 1. Что мы строим

```
Браузер  ──https, порт 443──►  nginx
                                 │  FastCGI, wordpress:9000
                                 ▼
                               wordpress (php-fpm)
                                 │  MySQL, mariadb:3306
                                 ▼
                               mariadb

Том wordpress-data → /home/akuzmin/data/wordpress   (wordpress: чтение и запись; nginx: только чтение)
Том mariadb-data   → /home/akuzmin/data/mariadb     (mariadb)
```

- Три контейнера в одной сети `inception-network`.
- С хоста доступен только порт 443.
- Пароли лежат в `secrets/`, остальные настройки в `srcs/.env`. Оба пути не попадают в git.

## 2. Почему VM, а не сразу домашний Linux

Subject требует работать в виртуальной машине, и дома это тоже удобнее:

- **Реальная репетиция.** Перезагрузка VM не трогает твой компьютер, а она обязательна на защите.
- **Безопасная очистка.** Команда из таблицы оценки удаляет **все** контейнеры, образы и тома
  на машине. В VM удалять нечего, кроме проекта.
- **Правильные пути.** В VM есть пользователь `akuzmin`, поэтому `/home/akuzmin/data` работает как в
  школе.
- **Свободные порты.** Порт 443 ничем не занят.

## 3. Сделай руками: домашняя VM

**Создай VM** в любой знакомой программе (VirtualBox или virt-manager):

- Debian 12 или 13 с рабочим столом (подойдёт Xfce), чтобы был браузер;
- 2 CPU, диск от 30 ГБ, 6 ГБ памяти: проекту хватит и 4 ГБ, но память нужна ещё VS Code и Claude Code;
- при установке создай пользователя **`akuzmin`**.

**Дай `akuzmin` права sudo** (выполни под root):

```bash
su -
apt-get update && apt-get install -y sudo
usermod -aG sudo akuzmin
exit
```

Выйди из сеанса и войди снова. Дальше все команды выполняются от `akuzmin`.

**Поставь Docker из официального репозитория.** Docker Desktop здесь не нужен:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl make git openssl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $VERSION_CODENAME stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker akuzmin
```

Снова выйди из сеанса и войди: только после этого начнёт действовать группа `docker`. Проверь:

```bash
docker run --rm hello-world     # печатает "Hello from Docker!"
docker compose version
```

**Поставь VS Code и Claude Code.** Скачай `.deb` с code.visualstudio.com и установи его, затем в разделе
Extensions найди расширение Claude Code и войди в аккаунт. Так я смогу проверять работу прямо в VM: читать
`my-work/` и смотреть на запущенные контейнеры.

**Если VM поставить не получается,** запасной вариант — работать прямо на домашнем Linux:

```bash
sudo mkdir -p /home/akuzmin/data && sudo chown -R "$USER" /home/akuzmin
sudo ss -tlnp | grep -E ':(80|443) '     # должно быть пусто
```

В этом случае **нельзя запускать команду очистки из таблицы**: она удалит и другие твои контейнеры.
Перезагрузку придётся проверять на самом компьютере.

## 4. Сделай руками: первый запуск

```bash
git clone -b solution/core https://github.com/olucens/42-inception.git ~/42-inception
cd ~/42-inception/Inception
echo "127.0.0.1 akuzmin.42.fr" | sudo tee -a /etc/hosts
make init     # создаёт srcs/.env и случайные пароли в secrets/
make          # сборка и запуск, первый раз несколько минут
make ps       # три контейнера, все Up (healthy)
```

Открой папку `~/42-inception` в VS Code и запусти там Claude Code. Чтобы работал `git push`, войди в GitHub.

Теперь в браузере внутри VM:

1. Открой `https://akuzmin.42.fr`. Браузер предупредит о сертификате: это нормально, причину разберём
   в уроке 7. Нажми «Дополнительно → Принять риск». Должен открыться сайт, а не страница установки.
2. Открой `/wp-login.php` и войди как `siteowner`. Пароль: `grep ADMIN secrets/credentials.txt`.
3. Открой `http://akuzmin.42.fr`: сайт **не** должен открыться.

**Запиши в [`labs.md`](../my-work/labs.md), раздел «Лаба 0»** и скажи «проверь лабу 0» в Claude Code на этой VM.

Если что-то не работает, сначала посмотри `make logs`, затем пришли мне вывод.

## 5. Школьная VM (день 7)

VM с Debian, VS Code и репозиторием там уже есть, поэтому заново ставить систему не нужно. Проверь её так:

```bash
whoami                                        # akuzmin
docker context show                           # default
docker info --format '{{.OperatingSystem}}'   # Debian, а не Docker Desktop
```

**Если стоит Docker Desktop,** выполни `docker context use default`. Desktop держит контейнеры в собственной
скрытой VM, поэтому том в `/home/akuzmin/data` и порт 443 будут работать не так, как в проекте. Если `default` не
отвечает, значит Docker Engine нет: поставь его как в части 3. Затем пройди часть 4 с чистого клона.

Я не знаю, как настроены школьные компьютеры, поэтому заранее выясни:

- **Можно ли хранить VM на диске так, чтобы она не удалялась?** На некоторых школьных машинах
  локальный диск очищается.
- **Есть ли `sudo` на самом компьютере?** Если нет, ты не сможешь изменить его `/etc/hosts`, поэтому
  браузер должен быть внутри VM. Для этого и нужен рабочий стол.
- **Хватает ли места и памяти для VM?**

Если что-то из этого не так, заложи до 1,5 часа на исправление. Сама сдача проходит в этой VM, с чистого клона
репозитория Intra: см. [runbook §0–1](../defense/runbook.md). На защите Claude Code не запускай, а если VM общая,
выйди из GitHub и Claude, когда закончишь.
