# Плагин Music And Artist Information для экосистемы Squeezebox

Этот плагин для Logitech Media Server (LMS) и экосистемы Squeezebox предоставляет дополнительную информацию о вашей музыкальной коллекции: биографии исполнителей, обзоры альбомов, сведения об участниках записи, похожих артистах и многое другое.

Информация, отображаемая плагином, запрашивается из следующих источников:
* [Wikipedia](https://wikipedia.org)
* [Last.fm](https://last.fm)
* [Discogs](https://discogs.com)
* [MusicBrainz](https://musicbrainz.org)

### Особенности форка

- **Поддержка русского языка:** Добавлен RU, приоритет русского сегмента Wikipedia/Last.fm с fallback на английский.
- **Умный поиск в Wikipedia:** 3-ступенчатый алгоритм (прямой поиск → фильтр дизамбигов → полнотекстовый поиск с проверкой упоминания артиста).
- **Исправление Wikidata:** Обход принудительной английской pageid — сначала поиск по имени в русской Википедии.
- **Приоритет локальной лирики:** Локальный поиск в первую очередь, поддержка файлов `Артист - Название.lrc/txt`.

---

## Установка в Docker

Скрипт автоматически скачает актуальные файлы плагина из репозитория и заменит ими существующие в примонтированной папке на хосте. Затем перезапустит контейнер Docker, чтобы LMS подхватила изменения.

1. **Скачайте скрипт установки:**
```bash
   curl -O https://raw.githubusercontent.com/flurmind/MusicArtistInfo-RU/master/install.sh
   chmod +x install.sh
```
2. Подготовьте данные (пример вашего docker-compose.yml):
```yaml
   services:
     lms:
       container_name: lms
       image: lmscommunity/lyrionmusicserver:stable
       volumes:
         - /srv/ssd/appdata/lms/config:/config:rw
```
3. Отредактируйте install.sh и укажите параметры под вашу систему:
   ```bash
   nano install.sh
   ```
* **PLUGINS_DIR** — путь к папке плагинов на хосте. Для примера выше это будет: ***/srv/ssd/appdata/lms/config***/cache/InstalledPlugins/Plugins
* **DOCKER_CONTAINER_NAME** — имя вашего контейнера (например, lms).

4. Запустите скрипт (он заменит файлы плагина и перезапустит контейнер):
```Bash
   ./install.sh
```
