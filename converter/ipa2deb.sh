#!/bin/bash

# i2d: IPA to DEB Converter (Final Fix)
set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

if [ $# -lt 1 ]; then
    echo "Usage: $0 <input.ipa> [output.deb]"
    exit 1
fi

INPUT_IPA="$1"
OUTPUT_DEB="${2:-$(basename "$INPUT_IPA" .ipa).deb}"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

unzip -q "$INPUT_IPA" -d "$TEMP_DIR"
PAYLOAD_DIR="$TEMP_DIR/Payload"
APP_BUNDLE=$(find "$PAYLOAD_DIR" -name "*.app" -type d | head -n 1)
INFO_PLIST="$APP_BUNDLE/Info.plist"
export INFO_PLIST

APP_DATA=$(python3 - << 'PY'
import os, plistlib
try:
    with open(os.environ['INFO_PLIST'], 'rb') as f:
        pl = plistlib.load(f)
    print(pl.get('CFBundleIdentifier', 'com.unknown.app'))
    print(pl.get('CFBundleDisplayName') or pl.get('CFBundleName') or 'App')
    print(pl.get('CFBundleShortVersionString') or pl.get('CFBundleVersion') or '1.0')
    print(pl.get('CFBundleExecutable', ''))
    print(pl.get('MinimumOSVersion', 'Неизвестно'))
    is_game = 'game' in str(pl.get('LSApplicationCategoryType', '')).lower() or \
              'Games' in str(pl.get('UIRequiredDeviceCapabilities', ''))
    print('Games' if is_game else 'Applications')
except:
    print("com.unknown\nApp\n1.0\n\nНеизвестно\nApplications")
PY
)

BUNDLE_ID=$(echo "$APP_DATA" | sed -n '1p')
DISPLAY_NAME=$(echo "$APP_DATA" | sed -n '2p')
APP_VERSION=$(echo "$APP_DATA" | sed -n '3p')
EXEC_NAME=$(echo "$APP_DATA" | sed -n '4p')
MIN_OS=$(echo "$APP_DATA" | sed -n '5p')
SECTION=$(echo "$APP_DATA" | sed -n '6p')

if [ -z "$EXEC_NAME" ]; then EXEC_NAME=$(basename "$APP_BUNDLE" .app); fi

DEB_DIR="$TEMP_DIR/deb"
mkdir -p "$DEB_DIR/DEBIAN" "$DEB_DIR/Applications"
cp -r "$APP_BUNDLE" "$DEB_DIR/Applications/"

# --- РАБОТА С ИКОНКОЙ ---
mkdir -p ./icons

# Ищем иконку в приложении
ICON_FILE=$(find "$APP_BUNDLE" -maxdepth 1 -name "*120x120*" -o -name "*60x60@2x.png" -o -name "*AppIcon*" | head -n 1)

ICON_LINE=""
if [ -n "$ICON_FILE" ]; then
    # Сначала копируем иконку как есть
    cp "$ICON_FILE" "./icons/$BUNDLE_ID.png"
    echo -e "${GREEN}[ICON]${NC} Иконка скопирована: icons/$BUNDLE_ID.png"

    # Пытаемся исправить иконку (если не получится - оставляем как есть)
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    if python3 "$REPO_ROOT/fix_icons.py" "./icons/$BUNDLE_ID.png" "./icons/${BUNDLE_ID}_fixed.png" >/dev/null 2>&1; then
        # Если фикс удался - заменяем оригинал
        mv "./icons/${BUNDLE_ID}_fixed.png" "./icons/$BUNDLE_ID.png"
        echo -e "${GREEN}[ICON]${NC} Иконка исправлена"
        ICON_LINE="Icon: icons/$BUNDLE_ID.png"
    else
        echo -e "${YELLOW}[ICON]${NC} Фикс не удался, используем оригинал"
        ICON_LINE="Icon: icons/$BUNDLE_ID.png"
    fi

    # Копируем в DEB для Sileo
    cp "./icons/$BUNDLE_ID.png" "$DEB_DIR/icon.png"
fi

# Создание control (без лишних пустых строк)
cat > "$DEB_DIR/DEBIAN/control" << EOF
Package: $BUNDLE_ID
Name: $DISPLAY_NAME
Version: $APP_VERSION
Architecture: iphoneos-arm
Description: Мин. ОС: $MIN_OS. Авто-конверт i2d.
Maintainer: slutvibe <alexa.chern22@gmail.com>
Section: $SECTION
Depends: firmware (>= 7.0), ldid
EOF

# Добавляем строку иконки только если она есть
if [ -n "$ICON_LINE" ]; then
    echo "$ICON_LINE" >> "$DEB_DIR/DEBIAN/control"
fi

# Создание postinst
cat > "$DEB_DIR/DEBIAN/postinst" << EOF
#!/bin/bash
APP_PATH="/Applications/$(basename "$APP_BUNDLE")"
BIN_PATH="\$APP_PATH/$EXEC_NAME"
chown -R root:wheel "\$APP_PATH"
chmod -R 755 "\$APP_PATH"
if [ -f "\$BIN_PATH" ]; then
    ldid -S "\$BIN_PATH" 2>/dev/null || true
fi
uicache -p "\$APP_PATH"
exit 0
EOF
chmod 755 "$DEB_DIR/DEBIAN/postinst"

dpkg-deb -Zgzip -b "$DEB_DIR" "$OUTPUT_DEB"
echo -e "${GREEN}[DONE]${NC} Пакет собран: $OUTPUT_DEB"