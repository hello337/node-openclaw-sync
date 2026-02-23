# node-openclaw-sync

Синхронизация конфига и OAuth между [xNode](https://xnode.pro) и локальным инстансом [OpenClaw](https://docs.openclaw.ai). Запускается на сервере, где установлен OpenClaw: тянет настройки из xNode API и применяет их (agents_defaults, tools_web_search, OAuth-токены, запросы ссылок для device flow).

**Требования на сервере:** `curl`, `jq`, `openclaw` в PATH.

---

## Первый запуск на сервере

Папку `/opt` создавать не обязательно. Клонируй репо **куда удобно** (домашний каталог, `/opt`, `/srv` — без разницы); установка идёт «на месте»: systemd будет запускать скрипт из этой же папки.

### 1. Клонировать репозиторий

```bash
git clone https://github.com/YOUR_USER/node-openclaw-sync.git
cd node-openclaw-sync
```

(Замени `YOUR_USER` на свой GitHub. Путь может быть любым, например `~/node-openclaw-sync` или `/opt/node-openclaw-sync`.)

### 2. Задать токен

Токен берёшь в админке xNode: **Pending Nodes** (или All Users Nodes) → нужная запись **OpenClaw** → кнопка **«Token»** → скопировать.

```bash
cp env.example env
nano env
```

В файле `env` укажи:

```
OPENCLAW_CONFIG_TOKEN=вставь_сюда_токен_из_админки
```

Опционально, если API не на api.xnode.pro:

```
OPENCLAW_API_BASE=https://your-api-host
```

Сохрани и закрой.

### 3. Установить и включить таймер

```bash
chmod +x install.sh
sudo ./install.sh
```

Скрипт не копирует файлы в другую папку: он записывает в systemd путь **к текущей папке** (где лежит репо) и поднимает таймер (каждые **10 секунд**). Файл `env` при первом запуске создаётся из `env.example`, если его ещё нет.

### 4. Проверить

```bash
systemctl status openclaw-sync.timer
journalctl -u openclaw-sync.service -f
```

Таймер должен быть `active`, в логах не должно быть ошибок про токен или сеть.

---

## Обновления: как стягивать с GitHub и перезапускать

Перейди в папку репо и подтяни изменения, затем перезапусти таймер:

```bash
cd /путь/к/node-openclaw-sync   # тот путь, куда клонировал
sudo git pull
sudo systemctl restart openclaw-sync.timer
```

Или одной строкой (подставь свой путь):

```bash
cd ~/node-openclaw-sync && sudo git pull && sudo systemctl restart openclaw-sync.timer
```

Файл `env` при `git pull` не трогается (он в `.gitignore`).

**Через update.sh:**

```bash
cd /путь/к/node-openclaw-sync
git pull
sudo ./update.sh
```

`update.sh` делает `git pull` и перезапускает таймер.

---

## Что делает скрипт

- **GET /openclaw/config** — получает конфиг по токену.
- Применяет **agents_defaults** и **tools_web_search** к локальному OpenClaw через `openclaw gateway call config.patch`.
- Обрабатывает **oauth_url_requests**: по запросу ссылки (например Qwen Portal) запускает `openclaw models auth login --provider ...`, забирает URL из вывода и шлёт его в xNode (**POST /openclaw/oauth-auth-url**).
- Применяет **oauth_pending** (токены/callback URL) через OpenClaw CLI и помечает их как применённые (**POST /openclaw/oauth-consumed**).

Токен и API base задаются через файл `env` в корне репо (см. `env.example`).
