#!/bin/bash

# Конвертер IPA в DEB (FIXED VERSION)
set -e

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [ $# -lt 1 ]; then
    echo "Usage: $0 <input.ipa> [output.deb]"
    exit 1
fi

INPUT_IPA="$1"
OUTPUT_DEB="${2:-$(basename "$INPUT_IPA" .ipa).deb}"

if [ ! -f "$INPUT_IPA" ]; then
    print_error "Input file not found!"
    exit 1
fi

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

print_status "Extracting IPA..."
unzip -q "$INPUT_IPA" -d "$TEMP_DIR"

PAYLOAD_DIR="$TEMP_DIR/Payload"
APP_BUNDLE=$(find "$PAYLOAD_DIR" -name "*.app" -type d | head -n 1)

if [ -z "$APP_BUNDLE" ]; then
    print_error "No .app bundle found!"
    exit 1
fi

APP_DIR_NAME=$(basename "$APP_BUNDLE")
INFO_PLIST="$APP_BUNDLE/Info.plist"
export INFO_PLIST

# --- СБОР ИНФОРМАЦИИ ЧЕРЕЗ PYTHON ---

# 1. Bundle ID
BUNDLE_ID=$(python3 - << 'PY'
import os, plistlib, sys
try:
    with open(os.environ['INFO_PLIST'], 'rb') as f:
        pl = plistlib.load(f)
    print(pl.get('CFBundleIdentifier', 'com.unknown.app'))
except: print('com.unknown.app')
PY
)

# 2. Display Name
DISPLAY_NAME=$(python3 - << 'PY'
import os, plistlib
try:
    with open(os.environ['INFO_PLIST'], 'rb') as f:
        pl = plistlib.load(f)
    print(pl.get('CFBundleDisplayName') or pl.get('CFBundleName') or 'Unknown')
except: print('Unknown')
PY
)

# 3. Version
APP_VERSION=$(python3 - << 'PY'
import os, plistlib
try:
    with open(os.environ['INFO_PLIST'], 'rb') as f:
        pl = plistlib.load(f)
    print(pl.get('CFBundleShortVersionString') or pl.get('CFBundleVersion') or '1.0')
except: print('1.0')
PY
)

# 4. Executable Name (САМОЕ ВАЖНОЕ!)
EXECUTABLE_NAME=$(python3 - << 'PY'
import os, plistlib
try:
    with open(os.environ['INFO_PLIST'], 'rb') as f:
        pl = plistlib.load(f)
    print(pl.get('CFBundleExecutable', ''))
except: print('')
PY
)

if [ -z "$EXECUTABLE_NAME" ]; then
    # Если в plist нет имени, берем имя папки без .app
    EXECUTABLE_NAME=$(echo "$APP_DIR_NAME" | sed 's/\.app$//')
fi

print_status "App: $DISPLAY_NAME ($BUNDLE_ID)"
print_status "Executable binary: $EXECUTABLE_NAME"

# --- СБОРКА ПАКЕТА ---

# Создаем правильную структуру сразу для /Applications
DEB_DIR="$TEMP_DIR/deb"
mkdir -p "$DEB_DIR/DEBIAN"
mkdir -p "$DEB_DIR/Applications"

# Копируем .app сразу в Applications
cp -r "$APP_BUNDLE" "$DEB_DIR/Applications/"

# Создаем control
cat > "$DEB_DIR/DEBIAN/control" << EOF
Package: $BUNDLE_ID
Name: $DISPLAY_NAME
Version: $APP_VERSION
Architecture: iphoneos-arm
Description: Converted from IPA via script.
Maintainer: slutvibe <alexa.chern22@gmail.com>
Section: Games
Depends: firmware (>= 1.0), ldid
EOF

# --- СОЗДАНИЕ POSTINST ---
# Важно: Мы используем EOF без кавычек, чтобы подставить переменные BASH сейчас,
# но экранируем \$ для переменных, которые должны работать внутри iOS.

cat > "$DEB_DIR/DEBIAN/postinst" << EOF
#!/bin/bash

APP_PATH="/Applications/$APP_DIR_NAME"
BIN_PATH="/Applications/$APP_DIR_NAME/$EXECUTABLE_NAME"

echo "Setting permissions for $DISPLAY_NAME..."

# 1. Исправляем владельца
chown -R root:wheel "\$APP_PATH"

# 2. Делаем бинарник исполняемым (ЭТОГО НЕ ХВАТАЛО)
if [ -f "\$BIN_PATH" ]; then
    chmod 755 "\$BIN_PATH"
    echo "Signing binary: \$BIN_PATH"
    
    # 3. Подписываем ldid
    ldid -S "\$BIN_PATH" 2>/dev/null || echo "Warning: ldid failed or not found"
else
    echo "Error: Binary not found at \$BIN_PATH"
fi

# 4. Обновляем иконки
uicache -p "\$APP_PATH"
exit 0
EOF

chmod 755 "$DEB_DIR/DEBIAN/postinst"

# --- СОЗДАНИЕ PRERM ---
cat > "$DEB_DIR/DEBIAN/prerm" << EOF
#!/bin/bash
# Ничего удалять не надо, dpkg сам удалит папку /Applications/$APP_DIR_NAME
# Нам нужно только почистить кэш
exit 0
EOF
chmod 755 "$DEB_DIR/DEBIAN/prerm"

# Сборка
print_status "Building DEB..."
dpkg-deb -Zgzip -b "$DEB_DIR" "$OUTPUT_DEB"

print_status "Done: $OUTPUT_DEB"