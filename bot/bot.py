#!/usr/bin/env python3
"""Telegram bot for the slutvibe iOS repo (Pyrogram).

Receives .deb tweaks and .ipa apps, converts/validates them, drops them into
the repo, regenerates indexes, commits and pushes.

Run:
    BOT_TOKEN=123:abc ./bot/run.sh
"""

import asyncio
import html
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from pyrogram import Client, filters

ROOT = Path(__file__).resolve().parents[1]
REPO_URL = os.environ.get("REPO_URL", "https://ios.slutvibe.site")
DEBS = ROOT / "debs"
ICONS = ROOT / "icons"
DEPICTIONS = ROOT / "depictions"
META_PATH = ROOT / "packages_meta.json"
CONVERTER = ROOT / "converter" / "ipa2deb.sh"

MAX_BOT_DOWNLOAD = 20 * 1024 * 1024
ALLOWED_IDS = {int(x) for x in os.environ.get("BOT_ADMIN_IDS", "").split(",") if x.strip()}

process_lock = asyncio.Lock()

DEPICTION_TEMPLATE = """<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="theme-color" content="#171713">
  <title>{name}</title>
  <style>
    * {{ box-sizing: border-box; }}
    body {{ margin: 0; background: #171713; color: #f3f0df; font: 16px/1.45 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; }}
    .wrap {{ width: 92%; max-width: 760px; margin: 0 auto; padding: 46px 0 64px; }}
    header {{ border-left: 7px solid #c7ff4a; padding: 4px 0 6px 18px; margin-bottom: 34px; }}
    h1 {{ margin: 0; font-size: 42px; line-height: 1.1; letter-spacing: -2px; }}
    header p {{ color: #aaa993; margin: 10px 0 0; }}
    .actions {{ margin: 24px 0 38px; }}
    .button {{ display: inline-block; margin: 0 8px 8px 0; padding: 12px 17px; border: 1px solid #c7ff4a; color: #171713; background: #c7ff4a; text-decoration: none; font-weight: 700; border-radius: 4px; }}
    .button.secondary {{ color: #c7ff4a; background: transparent; }}
    table {{ border-collapse: collapse; width: 100%; margin-bottom: 22px; }}
    td {{ padding: 8px 12px; border-bottom: 1px solid #2c2c25; vertical-align: top; }}
    td:first-child {{ color: #aaa993; white-space: nowrap; }}
    .desc {{ color: #f3f0df; line-height: 1.6; }}
    footer {{ margin-top: 34px; color: #727268; font-size: 13px; }}
  </style>
</head>
<body>
  <main class="wrap">
    <header>
      <h1>{name}</h1>
      <p>{pkg} · v{version}</p>
    </header>
    <div class="actions">
      <a class="button" href="cydia://url/https://cydia.saurik.com/api/share#?source={repo_url}/">Установить в Cydia</a>
      <a class="button secondary" href="{repo_url}/">Список пакетов</a>
    </div>
    <table>
      <tr><td>Пакет</td><td>{pkg}</td></tr>
      <tr><td>Версия</td><td>{version}</td></tr>
      <tr><td>Раздел</td><td>{section}</td></tr>
      <tr><td>Архитектура</td><td>{arch}</td></tr>
      <tr><td>ОС</td><td>{minos}</td></tr>
    </table>
    <p class="desc">{description}</p>
    <footer>Совместимость проверяется по control metadata и Mach-O load commands.</footer>
  </main>
</body>
</html>
"""


def load_env():
    env_path = Path(__file__).resolve().parent / ".env"
    if not env_path.is_file():
        return
    for line in env_path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def is_allowed(user_id: int) -> bool:
    return not ALLOWED_IDS or user_id in ALLOWED_IDS


def run(cmd: list, cwd=None) -> tuple:
    proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    return proc.returncode, proc.stdout, proc.stderr


def deb_fields(path: Path) -> dict:
    code, out, _ = run(["dpkg-deb", "-f", str(path), "Package", "Name", "Version",
                        "Architecture", "Section", "Description", "Depends"])
    if code != 0:
        raise RuntimeError("dpkg-deb failed")
    fields = {}
    current = None
    for line in out.splitlines():
        if re.match(r"^[A-Za-z0-9-]+: ", line):
            key, _, value = line.partition(": ")
            current = key
            fields[key] = value
        elif line.startswith(" ") and current:
            fields[current] += "\n" + line
    return fields


def min_os_from_depends(depends: str) -> str:
    match = re.search(r"firmware\s*\(\s*>=\s*([0-9]+(?:\.[0-9]+)?)", depends or "")
    return match.group(1) if match else ""


def safe_name(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9.+~-]", "", value)


def load_meta() -> dict:
    if META_PATH.is_file():
        return json.loads(META_PATH.read_text())
    return {}


def save_meta(meta: dict):
    META_PATH.write_text(json.dumps(meta, indent=2, ensure_ascii=False) + "\n")


def write_depiction(pkg: str, fields: dict, minos: str):
    name = html.escape(fields.get("Name") or pkg)
    version = html.escape(fields.get("Version", "1.0"))
    section = html.escape(fields.get("Section", "Applications"))
    arch = html.escape(fields.get("Architecture", "iphoneos-arm"))
    description = html.escape((fields.get("Description") or "—").strip())
    page = DEPICTION_TEMPLATE.format(
        name=name, pkg=html.escape(pkg), version=version, section=section,
        arch=arch, minos=html.escape(minos or "не указано"), description=description,
        repo_url=REPO_URL,
    )
    DEPICTIONS.mkdir(parents=True, exist_ok=True)
    (DEPICTIONS / f"{pkg}.html").write_text(page)


def install_deb(deb_path: Path) -> dict:
    fields = deb_fields(deb_path)
    pkg = fields.get("Package", "")
    if not pkg:
        raise RuntimeError("Package field missing in control")
    version = fields.get("Version", "1.0")
    arch = fields.get("Architecture", "iphoneos-arm")

    for old in DEBS.glob(f"{safe_name(pkg)}_*.deb"):
        if old.resolve() != deb_path.resolve():
            old.unlink()

    target = DEBS / f"{safe_name(pkg)}_{safe_name(version)}_{arch}.deb"
    if deb_path.resolve() != target.resolve():
        shutil.copy2(deb_path, target)

    minos = min_os_from_depends(fields.get("Depends", ""))
    tags = [f"iOS {minos}+"] if minos else []

    icon_candidate = ICONS / f"{pkg}.png"
    icon_rel = f"{REPO_URL}/icons/{pkg}.png" if icon_candidate.is_file() else f"{REPO_URL}/CydiaIcon.png"

    write_depiction(pkg, fields, minos)

    meta = load_meta()
    meta[pkg] = {
        "Name": fields.get("Name") or pkg,
        "Depiction": f"{REPO_URL}/depictions/{pkg}.html",
        "Icon": icon_rel,
        "Tags": tags,
    }
    save_meta(meta)

    return {"pkg": pkg, "version": version, "name": fields.get("Name") or pkg,
            "minos": minos, "arch": arch, "target": target.name}


def update_and_push(pkg: str) -> str:
    code, out, err = run(["./update.sh"], cwd=ROOT)
    if code != 0:
        return f"update.sh failed:\n{err or out}"

    git = ["git", "-C", str(ROOT)]
    code, out, _ = run(git + ["diff", "--quiet", "HEAD"])
    if code == 0:
        return "no changes to commit"
    run(git + ["add", "-A"])
    code, out, err = run(git + ["commit", "-m", f"bot: add {pkg}"])
    if code != 0:
        return f"commit failed:\n{err or out}"
    code, out, err = run(git + ["push", "origin", "HEAD"])
    if code != 0:
        return f"push failed (committed locally):\n{err or out}"
    return "pushed"


async def handle_document(client, message):
    fname = message.document.file_name or "file"
    ext = Path(fname).suffix.lower()

    if ext not in (".deb", ".ipa"):
        await message.reply_text("Отправь .deb (твик) или .ipa (приложение).")
        return

    if message.document.file_size and message.document.file_size > MAX_BOT_DOWNLOAD:
        await message.reply_text(
            f"Файл {message.document.file_size / 1024 / 1024:.1f} MB — больше лимита бота "
            f"(20 MB). Поставь локальный Bot API server (см. bot/README.md)."
        )
        return

    if not is_allowed(message.from_user.id):
        await message.reply_text("Недоступно.")
        return

    async with process_lock:
        status = await message.reply_text("Обрабатываю…")
        with tempfile.TemporaryDirectory() as tmp:
            try:
                tmp_path = Path(tmp) / fname
                await message.download(file_name=str(tmp_path))

                if ext == ".ipa":
                    out_deb = Path(tmp) / f"{safe_name(Path(fname).stem)}.deb"
                    code, _, err = await asyncio.to_thread(
                        run, ["bash", str(CONVERTER), str(tmp_path), str(out_deb)], ROOT
                    )
                    if code != 0:
                        await status.edit_text(f"Конвертация IPA не удалась:\n{err}")
                        return
                    result = await asyncio.to_thread(install_deb, out_deb)
                else:
                    result = await asyncio.to_thread(install_deb, tmp_path)

                out = await asyncio.to_thread(update_and_push, result["pkg"])
                await status.edit_text(
                    f"Готово: {result['name']} ({result['pkg']}) v{result['version']}\n"
                    f"OS: {result['minos'] or '—'} · {result['arch']}\n"
                    f"deb: debs/{result['target']}\n"
                    f"Repo: {out}"
                )
            except Exception as exc:  # noqa: BLE001
                await status.edit_text(f"Ошибка: {exc}")


async def cmd_start(client, message):
    await message.reply_text(
        "slutvibe repo bot\n\n"
        "Присылай:\n"
        "• .deb — твик/пакет\n"
        "• .ipa — приложение (сконвертится в .deb)\n\n"
        "Файл проверится, попадёт в репозиторий и сайт обновится."
    )


def main():
    load_env()
    token = os.environ.get("BOT_TOKEN")
    api_id = os.environ.get("API_ID")
    api_hash = os.environ.get("API_HASH")
    if not token or not api_id or not api_hash:
        print("BOT_TOKEN, API_ID and API_HASH must be set (env or bot/.env)", file=sys.stderr)
        sys.exit(1)

    app = Client(
        "slutvibe_repo_bot",
        api_id=int(api_id),
        api_hash=api_hash,
        bot_token=token,
        workdir=str(Path(__file__).resolve().parent),
    )

    app.on_message(filters.command(["start", "help"]))(cmd_start)
    app.on_message(filters.document)(handle_document)

    print("Polling…")
    app.run()


if __name__ == "__main__":
    main()
