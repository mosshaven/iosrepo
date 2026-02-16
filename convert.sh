#!/bin/bash

# Автоматический конвертер IPA в DEB с обновлением репозитория
# Использование: ./convert-and-update.sh [входной.ipa] [--watch]

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INPUT_DIR="input"
OUTPUT_DIR="debs"
CONVERTER_SCRIPT="converter/ipa2deb.sh"
UPDATE_SCRIPT="update.sh"

# Функции для цветного вывода
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    -echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

# Создание необходимых директорий
setup_directories() {
    mkdir -p "$INPUT_DIR" "$OUTPUT_DIR"
    print_status "Directories created/verified"
}

# Конвертация одного IPA файла
convert_ipa() {
    local ipa_file="$1"
    local filename=$(basename "$ipa_file")
    local deb_name=$(basename "$ipa_file" .ipa).deb
    
    print_header "Converting $filename"
    
    # Проверка наличия скрипта конвертера
    if [ ! -f "$CONVERTER_SCRIPT" ]; then
        print_error "Converter script not found: $CONVERTER_SCRIPT"
        return 1
    fi
    
    # Запуск конвертации
    if bash "$CONVERTER_SCRIPT" "$ipa_file" "$OUTPUT_DIR/$deb_name"; then
        print_status "Successfully converted: $filename -> $deb_name"
        return 0
    else
        print_error "Failed to convert: $filename"
        return 1
    fi
}

# Update repository
update_repository() {
    print_header "Updating Repository"
    
    if [ -f "$UPDATE_SCRIPT" ]; then
        bash "$UPDATE_SCRIPT"
        print_status "Repository updated successfully"
    else
        print_error "Update script not found: $UPDATE_SCRIPT"
        return 1
    fi
}

# Режим наблюдения - мониторинг директории входных файлов
watch_mode() {
    print_header "Watch Mode Enabled"
    print_status "Monitoring $INPUT_DIR for new .ipa files..."
    print_status "Press Ctrl+C to stop"
    
    # Использование inotifywait или поллинг
    if command -v inotifywait >/dev/null 2>&1; then
        while true; do
            # Ожидание новых файлов
            inotifywait -e create --include '.*\.ipa$' "$INPUT_DIR" 2>/dev/null
            
            # Обработка всех IPA файлов
            for ipa_file in "$INPUT_DIR"/*.ipa; do
                if [ -f "$ipa_file" ]; then
                    convert_ipa "$ipa_file"
                    # Перемещение обработанного файла
                    mv "$ipa_file" "${ipa_file}.processed"
                fi
            done
            
            # Обновление репозитория при наличии новых пакетов
            update_repository
        done
    else
        # Резервный метод поллинга
        print_warning "inotifywait not found, using polling (slower)"
        
        while true; do
            for ipa_file in "$INPUT_DIR"/*.ipa; do
                if [ -f "$ipa_file" ]; then
                    convert_ipa "$ipa_file"
                    mv "$ipa_file" "${ipa_file}.processed"
                    update_repository
                fi
            done
            sleep 5
        done
    fi
}

# Конвертация всех IPA файлов
convert_all() {
    print_header "Converting All IPA Files"
    
    local converted_count=0
    local failed_count=0
    
    for ipa_file in "$INPUT_DIR"/*.ipa; do
        if [ -f "$ipa_file" ]; then
            if convert_ipa "$ipa_file"; then
                ((converted_count++))
                # Move processed file
                mv "$ipa_file" "${ipa_file}.processed"
            else
                ((failed_count++))
                # Перемещение неудачного файла
                mv "$ipa_file" "${ipa_file}.failed"
            fi
        fi
    done
    
    print_status "Conversion complete: $converted_count successful, $failed_count failed"
    
    # Обновление репозитория при наличии новых пакетов
    if [ $converted_count -gt 0 ]; then
        update_repository
    fi
}

# Главная функция
main() {
    print_header "IPA to DEB Auto Converter"
    
    # Создание директорий
    setup_directories
    
    # Проверка аргументов
    case "${1:-}" in
        --watch|-w)
            watch_mode
            ;;
        --all|-a)
            convert_all
            ;;
        ""|--help|-h)
            echo "Usage: $0 [option]"
            echo ""
            echo "Options:"
            echo "  <file.ipa>     Convert specific IPA file"
            echo "  --all, -a      Convert all IPA files in input directory"
            echo "  --watch, -w    Watch input directory for new IPA files"
            echo "  --help, -h     Show this help"
            echo ""
            echo "Directories:"
            echo "  input/         Place IPA files here"
            echo "  debs/          Converted DEB files appear here"
            exit 0
            ;;
        *)
            # Конвертация конкретного файла
            if [ -f "$1" ]; then
                if [[ "$1" =~ \.ipa$ ]]; then
                    # Копирование в директорию входных файлов
                    cp "$1" "$INPUT_DIR/"
                    convert_ipa "$INPUT_DIR/$(basename "$1")"
                    update_repository
                else
                    print_error "File must have .ipa extension"
                    exit 1
                fi
            else
                print_error "File not found: $1"
                exit 1
            fi
            ;;
    esac
}

# Запуск главной функции
main "$@"
