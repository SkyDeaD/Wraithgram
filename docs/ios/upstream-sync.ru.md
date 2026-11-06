# Обновление до нового релиза Telegram iOS

Wraithgram — это Telegram iOS плюс изменения Wraithgram. Здесь написано, как перенести в Wraithgram новый релиз
Telegram iOS и проверить результат.

## Как устроены обновления

- Релизы Telegram iOS — это коммиты в `master` репозитория
  [TelegramMessenger/Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS). Релиз — это коммит,
  который меняет `app` в `versions.json`, обычно с заголовком `Bump version`. Тегов релизов в репозитории нет
  с 2023 года.
- История Git Wraithgram начинается с одного коммита и не содержит коммитов Telegram, поэтому релизы не
  вливаются слиянием. Коммит Telegram, на котором основан Wraithgram, записан в `build-system/upstream-base`.
- `build-system/WGUpstreamSync.sh` накладывает разницу между этим коммитом и новым релизом как патч, с
  трёхсторонним слиянием там, где патч не ложится сам. Там, где Telegram и Wraithgram меняли одни и те же
  строки, в файле остаются маркеры конфликта. Изменения файлов Telegram, которые Wraithgram удаляет (например,
  `CLAUDE.md` и `AGENTS.md`), пропускаются.
- Код Wraithgram лежит в `Wraithgram/`. Правки в файлах самого Telegram маленькие и помечены `// WRAITH:`.
  Конфликты бывают именно в этих правках.
- Изменения Wraithgram внутри Git-сабмодулей хранятся патчами в `build-system/WGPatches/`, а не коммитами
  в сабмодулях. Их накладывает `build-system/WGBuild.sh`.

## Перед началом

Нужно:

- Клон Wraithgram с сабмодулями (`git clone --recursive`).
- Рабочая сборка, как описано в README.
- Никаких незакоммиченных изменений. Сабмодули, которые патчит `WGBuild.sh`, могут оставаться изменёнными.
- Версия Xcode, которую новый релиз указывает в `versions.json`. Если она поменялась, установи этот Xcode и
  выбери его через `xcode-select` перед сборкой.

## Перенеси релиз

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

5. Необязательно: посмотри файлы, которые меняли и Telegram, и Wraithgram. Конфликты возможны только в них.

   ```sh
   BASE=$(cat build-system/upstream-base)
   comm -12 <(git diff --name-only $BASE COMMIT | sort) <(git diff --name-only $BASE HEAD | sort)
   ```

6. Наложи релиз.

   ```sh
   build-system/WGUpstreamSync.sh COMMIT
   ```

   Скрипт выводит базу, релиз и пропущенные файлы, а затем один из результатов:

   - `Applied cleanly.` — переходи к шагу 8.
   - `Applied with conflicts.` и список файлов — переходи к шагу 7.
   - `ERROR: the patch did not apply` — ничего не изменилось. Обычно это значит, что Telegram поменял файл,
     который Wraithgram тоже изменил так, что трёхстороннее слияние не справляется, например сабмодуль, который
     Wraithgram переключил на другой коммит. Исправь этот файл вручную и запусти скрипт снова.

7. Разреши каждый конфликт и добавь файл командой `git add FILE`. Список файлов с конфликтами:
   `git diff --name-only --diff-filter=U`.

   В конфликте бери новый код Telegram и заново добавляй в него строки `// WRAITH:`. Например, в 13.1.2
   Telegram добавил поле рядом с полем эквалайзера Wraithgram в `ChunkMediaPlayerV2.swift`, и при разрешении
   оставили оба поля. Если Telegram переписал код, к которому был привязан блок `// WRAITH:`, найди место, где
   новый код делает то же самое, и перенеси блок туда.

   `versions.json` конфликтует, когда Telegram меняет версию Xcode, потому что Wraithgram ставит свой `xcode`.
   Бери `app` и остальные поля от Telegram, а из двух значений `xcode` оставляй более новое.

8. Закоммить обновление. Скрипт уже добавил в индекс изменения и новый `build-system/upstream-base`.

   ```sh
   git commit -m "Update to Telegram-iOS VERSION (COMMIT)"
   ```

9. Переключи сабмодули на коммиты, которые использует релиз.

   ```sh
   git submodule update --init --recursive
   ```

## Проверь результат

1. Убедись, что от Telegram отличаются только изменения Wraithgram. Команда выводит изменённые файлы вне
   `Wraithgram/`. Каждый из них должен быть исходником с правками `// WRAITH:` или файлом, который Wraithgram
   добавляет или заменяет, например скрипты сборки в `build-system/`, иконки и название приложения,
   документация, `.gitignore` и `.gitattributes`.

   ```sh
   git diff --name-only COMMIT HEAD -- . ':!Wraithgram'
   ```

2. Собери приложение. `WGBuild.sh` заодно накладывает патчи сабмодулей.

   ```sh
   build-system/WGBuild.sh --continueOnError
   ```

   Если сборка остановилась с `neither applies nor is already applied`, сабмодуль изменился под патчем.
   В этом сабмодуле повтори изменение вручную, потом перезапиши патч командой
   `git -C SUBMODULE diff > build-system/WGPatches/PATCH.patch`. `SUBMODULE` — путь сабмодуля, `PATCH` — имя
   файла патча из ошибки.

3. Запусти проверки строк и тесты Wraithgram.

   ```sh
   python3 Wraithgram/Strings/check.py
   python3 Wraithgram/Strings/tests/test_tools.py
   ```

   Хостовые тестовые цели выводит `rg -l swift_test Wraithgram -g BUILD`. Запускай каждую через
   `./build-input/bazel-BAZEL_VERSION-darwin-arm64 test TARGET`, где `BAZEL_VERSION` — версия из
   `versions.json`, а `TARGET` — метка цели из этого файла `BUILD`.

4. Установи сборку на симулятор и открой экраны, которые рисуют файлы с конфликтами.

5. Обнови версию Telegram в `README.md` и `README.ru.md`.
