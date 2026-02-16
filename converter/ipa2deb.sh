#!/bin/bash

# Конвертер IPA в DEB для iOS
# Использование: ./ipa2deb.sh <входной.ipa> [выходной.deb]

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция для цветного вывода статуса
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Проверка наличия входного файла
if [ $# -lt 1 ]; then
    echo "Usage: $0 <input.ipa> [output.deb]"
    echo "Example: $0 app.ipa app.deb"
    exit 1
fi

INPUT_IPA="$1"
OUTPUT_DEB="${2:-$(basename "$INPUT_IPA" .ipa).deb}"

# Проверка существования файла
if [ ! -f "$INPUT_IPA" ]; then
    print_error "Input file '$INPUT_IPA' not found!"
    exit 1
fi

# Проверка расширения файла
if [[ ! "$INPUT_IPA" =~ \.ipa$ ]]; then
    print_error "Input file must have .ipa extension!"
    exit 1
fi

print_status "Starting conversion: $INPUT_IPA -> $OUTPUT_DEB"

# Создание временной директории
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

print_status "Created temporary directory: $TEMP_DIR"

# Распаковка IPA архива
print_status "Extracting IPA file..."
unzip -q "$INPUT_IPA" -d "$TEMP_DIR"

# Поиск директории Payload
PAYLOAD_DIR="$TEMP_DIR/Payload"
if [ ! -d "$PAYLOAD_DIR" ]; then
    print_error "Payload directory not found in IPA file!"
    exit 1
fi

# Получение app бандла
APP_BUNDLE=$(find "$PAYLOAD_DIR" -name "*.app" -type d | head -n 1)
if [ -z "$APP_BUNDLE" ]; then
    print_error "No .app bundle found in Payload!"
    exit 1
fi

APP_NAME=$(basename "$APP_BUNDLE")
print_status "Found app bundle: $APP_NAME"

# Чтение метаданных из Info.plist (поддержка бинарного plist)
INFO_PLIST="$APP_BUNDLE/Info.plist"
if [ ! -f "$INFO_PLIST" ]; then
    print_warning "Info.plist not found inside app bundle; using fallback metadata"
fi

export INFO_PLIST

BUNDLE_ID=$(python3 - << 'PY'
import os, plistlib, sys
p = os.environ.get('INFO_PLIST')
if not p or not os.path.exists(p):
    print('')
    sys.exit(0)
with open(p, 'rb') as f:
    pl = plistlib.load(f)
print(pl.get('CFBundleIdentifier','') or '')
PY
)

DISPLAY_NAME=$(python3 - << 'PY'
import os, plistlib, sys
p = os.environ.get('INFO_PLIST')
if not p or not os.path.exists(p):
    print('')
    sys.exit(0)
with open(p, 'rb') as f:
    pl = plistlib.load(f)
print(pl.get('CFBundleDisplayName') or pl.get('CFBundleName') or '')
PY
)

APP_VERSION=$(python3 - << 'PY'
import os, plistlib, sys
p = os.environ.get('INFO_PLIST')
if not p or not os.path.exists(p):
    print('')
    sys.exit(0)
with open(p, 'rb') as f:
    pl = plistlib.load(f)
print(pl.get('CFBundleShortVersionString') or pl.get('CFBundleVersion') or '')
PY
)

# Извлечение минимальной версии iOS из Info.plist
MIN_OS_VERSION=$(python3 - << 'PY'
import os, plistlib, sys
p = os.environ.get('INFO_PLIST')
if not p or not os.path.exists(p):
    print('')
    sys.exit(0)
with open(p, 'rb') as f:
    pl = plistlib.load(f)
min_os = pl.get('MinimumOSVersion', '')
if min_os:
    # Extract major version number (e.g., "15.0" -> "15")
    print(min_os.split('.')[0])
else:
    print('')
PY
)

# Проверка версии iOS - пропуск если выше 12
if [ -n "$MIN_OS_VERSION" ] && [ "$MIN_OS_VERSION" -gt 12 ]; then
    print_error "App requires iOS $MIN_OS_VERSION+ but this repo only supports iOS 12 and below. Skipping conversion."
    rm -rf "$TEMP_DIR"
    exit 1
fi

APP_BASE_NAME=$(echo "$APP_NAME" | sed 's/\.app$//')
if [ -z "$DISPLAY_NAME" ]; then
    DISPLAY_NAME="$APP_BASE_NAME"
fi
if [ -z "$BUNDLE_ID" ]; then
    # Fallback if bundle id is missing
    BUNDLE_ID="com.converted.$(echo "$APP_BASE_NAME" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9.-')"
fi
if [ -z "$APP_VERSION" ]; then
    APP_VERSION="1.0"
fi

# Создание структуры DEB пакета
DEB_DIR="$TEMP_DIR/deb"
mkdir -p "$DEB_DIR/DEBIAN"
mkdir -p "$DEB_DIR/var/mobile/Documents"

# Копирование бандла в директорию пакета
print_status "Copying app bundle..."
cp -r "$APP_BUNDLE" "$DEB_DIR/var/mobile/Documents/"

# Создание control файла
print_status "Creating control file..."
cat > "$DEB_DIR/DEBIAN/control" << EOF
Package: $BUNDLE_ID
Name: $DISPLAY_NAME
Version: $APP_VERSION
Architecture: iphoneos-arm
Description: Автоматически сконвертировано из IPA. Требуется iOS 12 или ниже.
Maintainer: slutvibe <alexa.chern22@gmail.com>
Section: App
Depends: firmware (>= 1.0), firmware (<< 13.0), ldid
EOF

# Создание postinst скрипта для установки
cat > "$DEB_DIR/DEBIAN/postinst" << 'EOF'
#!/bin/bash

# Проверка версии iOS - установка только на iOS 12 и ниже
IOS_VERSION=$(defaults read /System/Library/CoreServices/SystemVersion.plist ProductVersion 2>/dev/null | cut -d'.' -f1)
if [ -n "$IOS_VERSION" ] && [ "$IOS_VERSION" -gt 12 ]; then
    echo "Error: This app is only compatible with iOS 12 and below. Current iOS version: $IOS_VERSION"
    exit 1
fi

# Поиск приложения в Documents и перенос в Applications
APP_DIR=$(find /var/mobile/Documents -name "*.app" -type d | head -n 1)

if [ -n "$APP_DIR" ]; then
    APP_NAME=$(basename "$APP_DIR")
    
    # Создание директории Applications
    mkdir -p /Applications
    
    # Перенос приложения
    TARGET_DIR="/Applications/$APP_NAME"
    
    # Move app
    mv "$APP_DIR" "$TARGET_DIR"
    
    # Установка прав доступа
    chown -R root:wheel "$TARGET_DIR"
    chmod -R 755 "$TARGET_DIR"
    
    # Подпись исполняемого файла через ldid (поиск динамически)
    EXECUTABLE=$(find "$TARGET_DIR" -type f -perm +111 -name "$APP_BASE_NAME" 2>/dev/null | head -n 1)
    if [ -z "$EXECUTABLE" ]; then
        # Fallback: try to find any executable in the app bundle
        EXECUTABLE=$(find "$TARGET_DIR" -type f -perm +111 2>/dev/null | grep -v ".app/" | head -n 1)
    fi
    if [ -n "$EXECUTABLE" ] && [ -f "$EXECUTABLE" ]; then
        ldid -S "$EXECUTABLE" 2>/dev/null || echo "Warning: ldid signing failed"
    else
        echo "Warning: No executable found to sign in $TARGET_DIR"
    fi
    
    # Обновление кэша иконок и респринг
    uicache -p "$TARGET_DIR" 2>/dev/null || true
    killall SpringBoard 2>/dev/null || true
    
    echo "App installed successfully!"
else
    echo "No app bundle found!"
fi
EOF

chmod +x "$DEB_DIR/DEBIAN/postinst"

# Создание prerm скрипта для удаления
cat > "$DEB_DIR/DEBIAN/prerm" << 'EOF'
#!/bin/bash

# Поиск и удаление приложения из /Applications
APP_DIR=$(find /Applications -name "*.app" -type d 2>/dev/null | head -n 1)

if [ -n "$APP_DIR" ]; then
    # Очистка кэша иконок перед удалением
    uicache -u "$APP_DIR" 2>/dev/null || true
    rm -rf "$APP_DIR"
    echo "App removed successfully!"
fi
EOF

chmod +x "$DEB_DIR/DEBIAN/prerm"

# Сборка DEB пакета
print_status "Building DEB package..."
dpkg-deb -Zgzip -b "$DEB_DIR" "$OUTPUT_DEB"

# Проверка успешности сборки
if [ -f "$OUTPUT_DEB" ]; then
    SIZE=$(du -h "$OUTPUT_DEB" | cut -f1)
    print_status "Conversion completed successfully!"
    print_status "Output: $OUTPUT_DEB (Size: $SIZE)"
else
    print_error "Failed to create DEB package!"
    exit 1
fi

print_status "Done! You can now install the DEB package on your iOS device."
