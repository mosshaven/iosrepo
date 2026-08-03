# Repo bot

Telegram-бот: кидаешь `.deb` или `.ipa` — пакет попадает в репозиторий, индексы
пересобираются, изменения пушатся в GitHub (сайт обновляется сам).

## Настройка

1. Создай бота у [@BotFather](https://t.me/BotFather) (`/newbot`), получи токен.
2. Узнай свой Telegram user id (например через @userinfobot).
3. Создай конфиг:

```sh
cp bot/.env.example bot/.env
```

Заполни `bot/.env`:

```
BOT_TOKEN=123456:ABC...
BOT_ADMIN_IDS=111222333
```

`BOT_ADMIN_IDS` — разрешённые user id через запятую. Пустое = принимает всех.

## Запуск

```sh
bot/run.sh
```

Первый запуск сам создаст venv и поставит зависимости. Для фоновой работы:

```sh
tmux new -s bot -d 'bot/run.sh'
# или systemd unit ниже
```

## Что делает

- `.ipa` → конвертация через `converter/ipa2deb.sh` → `.deb` в `debs/`
- `.deb` → валидация `dpkg-deb`, копирование в `debs/`
- старые версии того же пакета удаляются
- генерится depiction-страница `depictions/<pkg>.html`
- `packages_meta.json` пополняется (имя, иконка, теги)
- `./update.sh`: Packages, Packages.gz/bz2, Release (с checksum'ами), index.html
- `git add -A && commit && push`

## Лимит 20 MB

Обычный Bot API не отдаёт файлы больше 20 MB (бот скачивает по `getFile`).
Если кидаешь большие IPA (>20 MB) — поставь локальный
[Bot API server](https://core.telegram.org/bots/api#using-a-local-bot-api-server)
и укажи в коде `local_mode=True` / `base_url` у `Application.builder()`.
