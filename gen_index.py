#!/usr/bin/env python3
"""Regenerate the site's index.html from the generated Packages file."""

from pathlib import Path
import html
import json
import sys


ROOT = Path(__file__).resolve().parent
META_PATH = ROOT / "packages_meta.json"
TITLE = "slutvibe Legacy Repo"
DESCRIPTION = "Небольшой репозиторий пакетов для jailbreak-устройств."
REPO_URL = "https://ios.slutvibe.site"

CSS = """
    * { box-sizing: border-box; }
    body { margin: 0; background: #171713; color: #f3f0df; font: 16px/1.45 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; }
    .wrap { width: 92%; max-width: 760px; margin: 0 auto; padding: 46px 0 64px; }
    header { border-left: 7px solid #c7ff4a; padding: 4px 0 6px 18px; margin-bottom: 34px; }
    h1 { margin: 0; font-size: 42px; line-height: 1; letter-spacing: -2px; }
    header p { color: #aaa993; margin: 10px 0 0; }
    .actions { margin: 24px 0 38px; }
    .button { display: inline-block; margin: 0 8px 8px 0; padding: 12px 17px; border: 1px solid #c7ff4a; color: #171713; background: #c7ff4a; text-decoration: none; font-weight: 700; border-radius: 4px; }
    .button.secondary { color: #c7ff4a; background: transparent; }
    h2 { color: #aaa993; font-size: 13px; letter-spacing: 2px; text-transform: uppercase; margin: 0 0 12px; }
    .package { display: block; position: relative; min-height: 104px; margin: 0 0 12px; padding: 18px 18px 18px 106px; background: #22221d; border: 1px solid #35352c; color: inherit; text-decoration: none; border-radius: 8px; }
    .package img { position: absolute; left: 18px; top: 18px; width: 68px; height: 68px; border-radius: 15px; }
    .package h3 { margin: 0 0 5px; font-size: 19px; }
    .package p { color: #aaa993; margin: 0; font-size: 14px; }
    .tag { display: inline-block; margin: 8px 5px 0 0; padding: 3px 7px; color: #c7ff4a; background: #303324; font-size: 12px; border-radius: 3px; }
    footer { margin-top: 34px; color: #727268; font-size: 13px; }
    @media (max-width: 480px) { h1 { font-size: 34px; } .wrap { padding-top: 28px; } }
"""


def parse_packages(path: Path) -> list:
    stanzas = path.read_text().strip().split("\n\n")
    packages = []
    for stanza in stanzas:
        fields = dict(line.split(": ", 1) for line in stanza.splitlines() if ": " in line)
        if "Package" not in fields:
            continue
        packages.append(fields)
    packages.sort(key=lambda f: f.get("Name", f["Package"]).lower())
    return packages


def load_tags() -> dict:
    if META_PATH.is_file():
        try:
            meta = json.loads(META_PATH.read_text())
            return {pkg: fields.get("Tags", []) for pkg, fields in meta.items()}
        except (json.JSONDecodeError, OSError):
            return {}
    return {}


def render_card(fields: dict, tags: list) -> str:
    name = html.escape(fields.get("Name", fields["Package"]))
    version = html.escape(fields.get("Version", ""))
    description = html.escape(fields.get("Description", ""))
    icon = fields.get("Icon", f"{REPO_URL}/CydiaIcon.png")
    depiction = fields.get("Depiction", f"{REPO_URL}/depictions/{fields['Package']}.html")
    tag_html = "".join(f'<span class="tag">{html.escape(t)}</span>' for t in tags)
    return (
        f'    <a class="package" href="{html.escape(depiction)}">\n'
        f'      <img src="{html.escape(icon)}" alt="">\n'
        f'      <h3>{name} <small>{version}</small></h3>\n'
        f'      <p>{description}</p>\n'
        f'      {tag_html}\n'
        f'    </a>\n'
    )


def main() -> int:
    packages_path = ROOT / "Packages"
    if not packages_path.is_file():
        print("Packages not found; run ./update.sh first", file=sys.stderr)
        return 1

    packages = parse_packages(packages_path)
    tags = load_tags()
    cards = "".join(render_card(f, tags.get(f["Package"], [])) for f in packages)

    page = f"""<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="theme-color" content="#171713">
  <title>{TITLE}</title>
  <style>{CSS}
  </style>
</head>
<body>
  <main class="wrap">
    <header>
      <h1>slutvibe</h1>
      <p>{DESCRIPTION}</p>
    </header>

    <div class="actions">
      <a class="button" href="cydia://url/https://cydia.saurik.com/api/share#?source={REPO_URL}/">Добавить в Cydia</a>
      <a class="button secondary" href="sileo://source/{REPO_URL}/">Sileo</a>
      <a class="button secondary" href="zbra://sources/add/{REPO_URL}/">Zebra</a>
    </div>

    <h2>Пакеты</h2>
{cards}
    <footer>Совместимость проверяется по control metadata и Mach-O load commands. Перед установкой читай страницу пакета.</footer>
  </main>
</body>
</html>
"""
    (ROOT / "index.html").write_text(page)
    print(f"index.html written: {len(packages)} packages")
    return 0


if __name__ == "__main__":
    sys.exit(main())
