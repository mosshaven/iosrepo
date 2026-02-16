#!/usr/bin/env python3
"""
fix_icons.py - Исправляет поврежденные иконки iOS приложений (CgBI PNG -> нормальный PNG)
Использование: python3 fix_icons.py <путь_к_иконке> [выходной_файл]
"""

import sys
import os
import subprocess
from PIL import Image

def has_tool(tool_name):
    """Проверяет, установлен ли инструмент"""
    try:
        subprocess.run([tool_name, '--version'], capture_output=True, check=True)
        return True
    except:
        return False

def fix_with_pyiPNG(input_path, output_path):
    """Исправляет CgBI PNG с помощью PyiPNG"""
    try:
        import pyipng

        with open(input_path, 'rb') as f:
            bytes_data = f.read()

        # Конвертируем CgBI в обычный PNG
        fixed_bytes = pyipng.convert(bytes_data)

        with open(output_path, 'wb') as f:
            f.write(fixed_bytes)

        print(f"✅ PyiPNG исправил иконку: {output_path}")
        return True

    except ImportError:
        print("❌ PyiPNG не установлен")
        return False
    except Exception as e:
        print(f"❌ Ошибка PyiPNG: {e}")
        return False

def fix_with_convert(input_path, output_path):
    """Исправляет с помощью ImageMagick convert"""
    try:
        result = subprocess.run([
            'convert', input_path, output_path
        ], capture_output=True, text=True, timeout=30)

        if result.returncode == 0 and os.path.exists(output_path):
            print(f"✅ ImageMagick convert исправил иконку: {output_path}")
            return True
        else:
            print(f"❌ ImageMagick convert не смог исправить: {result.stderr}")
            return False
    except Exception as e:
        print(f"❌ Ошибка ImageMagick: {e}")
        return False

def fix_cgbi_png(input_path, output_path):
    """Специальная обработка CgBI PNG файлов"""
    try:
        with open(input_path, 'rb') as f:
            data = f.read()

        # Проверяем сигнатуру CgBI
        if len(data) < 12 or data[12:16] != b'CgBI':
            # Не CgBI, пробуем обычное открытие
            return False

        print("🔧 Обнаружен CgBI PNG, исправляем...")

        # Пробуем PyiPNG в первую очередь
        if fix_with_pyiPNG(input_path, output_path):
            return True

        # Fallback на системные инструменты
        if has_tool('pngcrush'):
            return fix_with_pngcrush(input_path, output_path)
        elif has_tool('convert'):
            return fix_with_convert(input_path, output_path)
        else:
            # Fallback на ручную обработку
            modified_data = data[:12] + b'IHDR' + data[16:]
            temp_path = output_path + '.temp'
            with open(temp_path, 'wb') as f:
                f.write(modified_data)

            try:
                with Image.open(temp_path) as img:
                    img.save(output_path, 'PNG')
                os.remove(temp_path)
                print(f"✅ Ручной CgBI фикс сработал: {output_path}")
                return True
            except Exception as e:
                os.remove(temp_path)
                print(f"❌ Ручной фикс не сработал: {e}")
                return False

    except Exception as e:
        print(f"❌ Ошибка обработки CgBI: {e}")
        return False

def fix_icon(input_path, output_path=None):
    """Исправляет иконку с множественными fallback"""
    if not output_path:
        output_path = input_path

    print(f"🔍 Обрабатываем иконку: {input_path}")

    # Сначала пробуем обычное открытие PIL
    try:
        with Image.open(input_path) as img:
            img.save(output_path, 'PNG')
            print(f"✅ Иконка исправлена через PIL: {output_path}")
            return True
    except Exception as e:
        print(f"⚠️  PIL не сработал ({e}), пробуем другие методы...")

    # Пробуем CgBI обработку
    if fix_cgbi_png(input_path, output_path):
        return True

    print(f"❌ Все методы исправления иконки провалились для {input_path}")
    return False

def main():
    if len(sys.argv) < 2:
        print("Использование: python3 fix_icons.py <иконка.png> [выходная_иконка.png]")
        print("Пример: python3 fix_icons.py icons/com.example.app.png")
        print(f"Доступные инструменты: PIL={has_tool('python3')}, pngcrush={has_tool('pngcrush')}, convert={has_tool('convert')}")
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) > 2 else input_path

    if not os.path.exists(input_path):
        print(f"❌ Файл не найден: {input_path}")
        sys.exit(1)

    if fix_icon(input_path, output_path):
        sys.exit(0)
    else:
        sys.exit(1)

if __name__ == "__main__":
    main()
