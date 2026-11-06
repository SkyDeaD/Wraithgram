# Обновление до нового релиза Telegram iOS

Ghostgram — это Telegram iOS плюс изменения Ghostgram, и его история Git продолжает историю Telegram. Здесь
написано, как влить новый релиз Telegram iOS в Ghostgram и проверить результат.

## Как устроена история

- Релизы Telegram iOS — это коммиты в `master` репозитория
  [TelegramMessenger/Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS). Релиз — это коммит,
  который меняет `app` в `versions.json`, обычно с заголовком `Bump version`. Тегов релизов в репозитории нет
  с 2023 года.
- Коммиты Ghostgram лежат поверх коммитов Telegram. Каждый релиз Telegram входит merge-коммитом с именем
  `Merge Telegram-iOS <версия> (<коммит>)`.
- Код Ghostgram лежит в `Ghostgram/`. Правки в файлах самого Telegram маленькие и помечены `// GHOST:`.
  Конфликты слияния бывают именно в этих правках.
- Изменения Ghostgram внутри Git-сабмодулей хранятся патчами в `build-system/GGPatches/`, а не коммитами
  в сабмодулях. Их накладывает `build-system/GGBuild.sh`.

## Перед началом

Нужно:

- Полный клон Ghostgram с сабмодулями (`git clone --recursive`), не shallow.
- Рабочая сборка, как описано в README.
- Версия Xcode, которую новый релиз указывает в `versions.json`. Если она поменялась, установи этот Xcode и
  выбери его через `xcode-select` перед сборкой.

## Влей релиз

1. Добавь Telegram iOS как remote. Если он уже есть, пропусти шаг.

   ```sh
   git remote add upstream https://github.com/TelegramMessenger/Telegram-iOS.git
   ```

2. Скачай `master` Telegram.

   ```sh
   git fetch upstream master
   ```

3. Найди коммит релиза. Команда выводит коммиты, которые меняли `versions.json`, от новых к старым:

   ```sh
   git log --format='%h %ad %s' --date=short upstream/master -- versions.json
   ```

   Версию коммита смотри через `git show COMMIT:versions.json`. `COMMIT` — хеш из списка.

4. Создай ветку для обновления от `main`.

   ```sh
   git switch -c telegram-VERSION main
   ```

   `VERSION` — версия Telegram, например `13.1.3`.

5. Необязательно: посмотри файлы, которые меняли и Telegram, и Ghostgram. Конфликты возможны только в них.
   `BASE` — коммит Telegram из прошлого слияния, `COMMIT` — новый релиз.

   ```sh
   comm -12 <(git diff --name-only BASE COMMIT | sort) <(git diff --name-only BASE main | sort)
   ```

6. Влей релиз.

   ```sh
   git merge --no-ff -m "Merge Telegram-iOS VERSION (COMMIT)" COMMIT
   ```

7. Разреши каждый конфликт. Список файлов с конфликтами: `git diff --name-only --diff-filter=U`.

   В конфликте бери новый код Telegram и заново добавляй в него строки `// GHOST:`. Например, в 13.1.2
   Telegram добавил поле рядом с полем эквалайзера Ghostgram в `ChunkMediaPlayerV2.swift`, и при разрешении
   оставили оба поля. Если Telegram переписал код, к которому был привязан блок `// GHOST:`, найди место, где
   новый код делает то же самое, и перенеси блок туда.

   `versions.json` конфликтует, когда Telegram меняет версию Xcode, потому что Ghostgram ставит свой `xcode`.
   Бери `app` и остальные поля от Telegram, а из двух значений `xcode` оставляй более новое.

   Ghostgram удаляет файлы Telegram `CLAUDE.md` и `AGENTS.md`. Когда Telegram меняет один из них, файл
   конфликтует как удалённый у нас (deleted by us); разреши конфликт командой `git rm CLAUDE.md AGENTS.md`.

8. Заверши слияние.

   ```sh
   git add -A
   git commit --no-edit
   ```

9. Переключи сабмодули на коммиты, которые использует релиз.

   ```sh
   git submodule update --init --recursive
   ```

## Проверь результат

1. Убедись, что от Telegram отличаются только изменения Ghostgram. Команда выводит изменённые файлы вне
   `Ghostgram/`. Каждый из них должен быть исходником с правками `// GHOST:` или файлом, который Ghostgram
   добавляет или заменяет,
   например скрипты сборки в `build-system/`, иконки и название приложения, `README.md`, `.gitignore` и
   `.gitattributes`.

   ```sh
   git diff --name-only COMMIT HEAD -- . ':!Ghostgram'
   ```

2. Собери приложение. `GGBuild.sh` заодно накладывает патчи сабмодулей.

   ```sh
   build-system/GGBuild.sh --continueOnError
   ```

   Если сборка остановилась с `neither applies nor is already applied`, сабмодуль изменился под патчем.
   В этом сабмодуле повтори изменение вручную, потом перезапиши патч командой
   `git -C SUBMODULE diff > build-system/GGPatches/PATCH.patch`. `SUBMODULE` — путь сабмодуля, `PATCH` — имя
   файла патча из ошибки.

3. Запусти проверки строк и тесты Ghostgram.

   ```sh
   python3 Ghostgram/Strings/check.py
   python3 Ghostgram/Strings/tests/test_tools.py
   ```

   Хостовые тестовые цели выводит `rg -l swift_test Ghostgram -g BUILD`. Запускай каждую через
   `./build-input/bazel-BAZEL_VERSION-darwin-arm64 test TARGET`, где `BAZEL_VERSION` — версия из
   `versions.json`, а `TARGET` — метка цели из этого файла `BUILD`.

4. Установи сборку на симулятор и открой экраны, которые рисуют файлы с конфликтами.

5. Обнови версию Telegram в `README.md` и `README.ru.md`.
