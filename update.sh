#!/bin/bash
# Удаляем старые индексы
rm -f Packages Packages.bz2 Packages.gz

# Генерируем новый Packages
# Флаг -m заставляет искать во вложенных папках
dpkg-scanpackages -m debs /dev/null > Packages

# Сжимаем
bzip2 -c9 Packages > Packages.bz2
gzip -c9 Packages > Packages.gz

echo "Done! Repositories updated."