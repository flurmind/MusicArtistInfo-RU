#!/bin/bash

# --- НАСТРОЙКИ ---
PLUGIN_NAME="MusicArtistInfo"
GITHUB_TAR_URL="https://github.com/flurmind/MusicArtistInfo-RU/archive/refs/heads/master.tar.gz"
TARGET_DIR="$PLUGINS_DIR/$PLUGIN_NAME"

# ⚠️ ИЗМЕНИТЕ ЭТИ ДВЕ СТРОЧКИ ПОД ВАШУ СИСТЕМУ ⚠️
PLUGINS_DIR="/srv/ssd/appdata/lms/config/cache/InstalledPlugins/Plugins"
DOCKER_CONTAINER_NAME="lms" 
# ------------------

echo "🚀 Начинаем чистую установку плагина из твоего репозитория..."

# 1. Зачистка временных папок
rm -rf /tmp/lms_src /tmp/plugin.tar.gz
mkdir -p /tmp/lms_src

# 2. Скачиваем архив
echo "📥 Скачиваем исходники..."
curl -L "$GITHUB_TAR_URL" -o /tmp/plugin.tar.gz

# 3. Распаковываем
echo "📦 Распаковываем..."
tar -xzf /tmp/plugin.tar.gz -C /tmp/lms_src/

# 4. Ищем, где внутри архива лежат файлы
REAL_SRC_DIR=$(find /tmp/lms_src -name "Plugin.pm" -exec dirname {} \;)

if [ -z "$REAL_SRC_DIR" ]; then
    echo "❌ Ошибка: В скачанном репозитории не найден файл Plugin.pm!"
    exit 1
fi
echo "🔍 Найдена папка с кодом: $REAL_SRC_DIR"

# 5. Подготавливаем папку в LMS
mkdir -p "$TARGET_DIR"
find "$TARGET_DIR" -mindepth 1 -delete

# 6. Логируем файлы перед копированием
echo "📋 Список копируемых файлов и их размеры:"
echo "--------------------------------------------------------"
# Находим все файлы (не папки) и выводим их относительный путь и размер в читаемом виде (Кб/б)
find "$REAL_SRC_DIR" -type f | while read -r file; do
    # Считаем размер файла
    size=$(du -sh "$file" | awk '{print $1}')
    # Отрезаем временный путь, чтобы в логе был только чистый путь внутри плагина
    rel_path=${file#"$REAL_SRC_DIR/"}
    printf "  📄 %-40s [%s]\n" "$rel_path" "$size"
done
echo "--------------------------------------------------------"

# 7. Копируем ВСЕ файлы
echo "🚚 Копируем файлы в плагины LMS..."
cp -r "$REAL_SRC_DIR"/* "$TARGET_DIR/"

# 8. Права доступа
chmod -R 755 "$TARGET_DIR"

# 9. Очистка мусора
rm -rf /tmp/lms_src /tmp/plugin.tar.gz

# 10. Перезапуск контейнера
echo "🔄 Перезапускаем Docker [$DOCKER_CONTAINER_NAME]..."
docker restart "$DOCKER_CONTAINER_NAME"

echo "✨ Скрипт успешно завершил работу!"
