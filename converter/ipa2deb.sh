#!/bin/bash

# i2d: IPA to DEB Converter (iOS 12 & below optimized)
set -e

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [ $# -lt 1 ]; then
    echo "Usage: $0 <input.ipa> [output.deb]"
    exit 1
fi

INPUT_IPA="$1"
OUTPUT_DEB="${2:-$(basename "$INPUT_IPA" .ipa).deb}"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

print_status "Распаковка IPA..."
unzip -q "$INPUT_IPA" -d "$TEMP_DIR"

PAYLOAD_DIR="$TEMP_DIR/Payload"
APP_BUNDLE=$(find "$PAYLOAD_DIR" -name "*.app" -type d | head -n 1)
INFO_PLIST="$APP_BUNDLE/Info.plist"
export INFO_PLIST

# Собираем данные через Python (чтобы не упасть на бинарных plist)
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
except:
    print("com.unknown\nApp\n1.0\n\nНеизвестно")
PY
)

BUNDLE_ID=$(echo "$APP_DATA" | sed -n '1p')
DISPLAY_NAME=$(echo "$APP_DATA" | sed -n '2p')
APP_VERSION=$(echo "$APP_DATA" | sed -n '3p')
EXEC_NAME=$(echo "$APP_DATA" | sed -n '4p')
MIN_OS=$(echo "$APP_DATA" | sed -n '5p')

if [ -z "$EXEC_NAME" ]; then
    EXEC_NAME=$(basename "$APP_BUNDLE" .app)
fi

# Подготовка структуры
DEB_DIR="$TEMP_DIR/deb"
mkdir -p "$DEB_DIR/DEBIAN"
mkdir -p "$DEB_DIR/Applications"

print_status "Копирование файлов..."
cp -r "$APP_BUNDLE" "$DEB_DIR/Applications/"

# Ищем иконку для Sileo (берем покрупнее)
ICON_FILE=$(find "$APP_BUNDLE" -maxdepth 1 -name "*60x60@2x.png" -o -name "*AppIcon*" -o -name "Icon-60.png" | head -n 1)
if [ -n "$ICON_FILE" ]; then
    cp "$ICON_FILE" "$DEB_DIR/icon.png"
    ICON_LINE="Icon: /icon.png"
else
    ICON_LINE=""
fi

# Создание control
cat > "$DEB_DIR/DEBIAN/control" << EOF
Package: $BUNDLE_ID
Name: $DISPLAY_NAME
Version: $APP_VERSION
Architecture: iphoneos-arm
Description: Мин. версия ОС: $MIN_OS и выше.
 Авто-конвертировано через i2d.
 $ICON_LINE
Maintainer: slutvibe <alexa.chern22@gmail.com>
Section: Applications
Depends: firmware (>= 7.0), ldid
EOF

# Создание postinst
cat > "$DEB_DIR/DEBIAN/postinst" << EOF
#!/bin/bash
APP_PATH="/Applications/$(basename "$APP_BUNDLE")"
BIN_PATH="\$APP_PATH/$EXEC_NAME"

echo "Настройка прав для $DISPLAY_NAME..."
chown -R root:wheel "\$APP_PATH"
chmod -R 755 "\$APP_PATH"

if [ -f "\$BIN_PATH" ]; then
    echo "Подпись бинарника..."
    ldid -S "\$BIN_PATH" 2>/dev/null || true
fi

echo "Обновление кэша иконок..."
uicache -p "\$APP_PATH"
exit 0
EOF

chmod 755 "$DEB_DIR/DEBIAN/postinst"

# Сборка
print_status "Сборка DEB пакета..."
dpkg-deb -Zgzip -b "$DEB_DIR" "$OUTPUT_DEB"

print_status "Готово! Пакет: $OUTPUT_DEB"