# Language / Язык
[English](#music-and-artist-information-plugin-for-the-squeezebox-ecosystem) | [Русский](#плагин-music-and-artist-information-для-экосистемы-squeezebox)

---

# Music And Artist Information plugin for the Squeezebox ecosystem

This plugin for Logitech Media Server (LMS) and the Squeezebox ecosystem provides additional information for your music collection: biographies, album reviews, credits, related artists etc.

The information presented by this plugin are sourced from:
* [Wikipedia](https://wikipedia.org)
* [Last.fm](https://last.fm)
* [Discogs](https://discogs.com)
* [MusicBrainz](https://musicbrainz.org)

## 🚀 Fork Features & Enhancements (RU / Local Lyrics)
This fork introduces deep optimization for Russian language metadata retrieval and enhances local lyrics file handling:

* **Advanced Russian Language Support:** Added `RU` to content languages. Forced initial Russian queries for Wikipedia and Last.fm, with a safe fallback to English to prevent infinite request loops.
* **Smart RU-Wikipedia Search Algorithm:** Implemented a robust 3-step search mechanism for albums and works in the Russian segment:
  1. *Direct Title Lookup:* Quick check via MediaWiki API.
  2. *Disambiguation Protection:* Automatic category filtering (`Страницы_значений`, `Неоднозначности`) to skip lists of meanings.
  3. *Validated Full-Text Search:* Fallback to full-text search with strict validation ensuring the artist's name is actually mentioned in the article snippet.
* **Wikidata Language Fix:** Upstream API (lms-community.org) explicitly forces English page IDs for Wikidata objects. This fork bypasses that limitation, searching by artist name/album title in Russian Wikipedia first.
* **Enhanced Local Lyrics (LRC/TXT) Matching:** * Bypassed forced online lyric providers cached in preferences.
  * Added automated lookup for files formatted as `Artist - Title.lrc` or `Artist - Title.txt`.
  * The plugin now checks both the track's folder and the global central lyrics directory.
  * Fixed a critical Perl regex syntax error related to filename sanitization (`/` divider inside character classes).

---

# Плагин Music And Artist Information для экосистемы Squeezebox

Этот плагин для Logitech Media Server (LMS) и экосистемы Squeezebox предоставляет дополнительную информацию о вашей музыкальной коллекции: биографии исполнителей, обзоры альбомов, сведения об участниках записи, похожих артистах и многое другое.

Информация, отображаемая плагином, запрашивается из следующих источников:
* [Wikipedia](https://wikipedia.org)
* [Last.fm](https://last.fm)
* [Discogs](https://discogs.com)
* [MusicBrainz](https://musicbrainz.org)

## 🚀 Особенности и улучшения форка (RU локализация / Локальная лирика)
Этот форк добавляет глубокую оптимизацию для работы с русскоязычными метаданными и расширяет возможности поиска локальных файлов субтитров/текстов песен:

* **Полноценная поддержка русского языка:** В список поддерживаемых языков добавлен `RU`. Все первичные запросы к Wikipedia и Last.fm принудительно отправляются на русском языке с безопасным автоматическим переключением на английский в случае отсутствия статьи (защита от бесконечного цикла).
* **Умный алгоритм поиска в русскоязычной Википедии:** Для поиска обзоров альбомов внедрена трехступенчатая система:
  1. *Прямой поиск:* Проверка точного совпадения заголовка статьи.
  2. *Фильтрация страниц значений (дизамбигов):* Анализ скрытых категорий статьи на маркеры неоднозначности. Если это список, плагин автоматически идет дальше.
  3. *Полнотекстовый поиск с валидацией:* Поиск по тексту статей с проверкой обязательного упоминания имени конкретного исполнителя в аннотации.
* **Исправление привязки к Wikidata:** Оригинальный API lms-community жестко возвращает английские идентификаторы страниц (ID), из-за чего плагин всегда открывал англоязычную Википедию. Форк исправляет это, заставляя систему сначала искать текстовое имя артиста в ру-сегменте.
* **Расширенный поиск локальной лирики (LRC/TXT):** * Отключен принудительный приоритет онлайн-провайдеров лирики, если они были сохранены в настройках сервера.
  * Добавлен гибкий поиск файлов в формате `Артист - Название.lrc` и `Артист - Название.txt`.
  * Поиск корректно работает как в папке с аудиофайлом, так и в централизованной папке с текстами.
  * Исправлена критическая синтаксическая ошибка регулярного выражения Perl при очистке спецсимволов в именах файлов.
