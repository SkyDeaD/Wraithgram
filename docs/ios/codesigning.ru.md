# Подпись своими профилями

Для сборки на устройство нужны свои профили подготовки (provisioning profiles). Для симулятора — нет: без
своих профилей сборка берёт тестовые профили Telegram из `build-system/fake-codesigning`, а
`build-system/WGSimProfiles.py` продлевает им срок, истёкший 30 октября 2026 года. Здесь написано, как сделать
свои профили.

Нужен аккаунт Apple Developer. На бесплатном аккаунте нельзя создать App Groups и push-уведомления, а они нужны
приложению.

## Выбери идентификаторы

1. Придумай bundle ID приложения, например `org.example.wraithgram`.
2. Найди свой Team ID в разделе **Membership details** на
   [developer.apple.com/account](https://developer.apple.com/account).
3. Впиши оба значения в `build-system/wraithgram-configuration.json`:

   ```json
   {
     "bundle_id": "org.example.wraithgram",
     "team_id": "ABCDE12345"
   }
   ```

   Остальные поля файла не трогай.

## Создай App ID

В [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) создай
один App ID для приложения и по одному для каждого расширения. `BUNDLE` — твой bundle ID.

| App ID | Имя профиля, под которым его ищет сборка |
|--------|------------------------------------------|
| `BUNDLE` | `Telegram` |
| `BUNDLE.Share` | `Share` |
| `BUNDLE.NotificationService` | `NotificationService` |
| `BUNDLE.NotificationContent` | `NotificationContent` |
| `BUNDLE.Widget` | `Widget` |
| `BUNDLE.SiriIntents` | `Intents` |
| `BUNDLE.BroadcastUpload` | `BroadcastUpload` |

На App ID приложения включи **Push Notifications**: если в профиле приложения нет push-права, сборка
останавливается с ошибкой `Could not find a valid aps-environment entitlement`. На каждом App ID включи
**App Groups** и добавь их все в одну группу `group.BUNDLE`.

## Создай профили

1. Для каждого App ID создай профиль **iOS App Development**. Профиля разработки хватает для симулятора и для
   своих устройств.
2. Скачай профили и положи их в `build-system/wraithgram-codesigning/profiles/`. Имена файлов любые: сборка
   находит каждый профиль по его App ID и копирует под именем из таблицы.
3. Собери:

   ```sh
   build-system/WGBuild.sh
   ```

   В первой строке вывода должно быть `signing    : build-system/wraithgram-codesigning`.

Папка в `.gitignore`. Чтобы хранить профили в другом месте, укажи в `WG_CODESIGN` папку, внутри которой есть
`profiles/`.

Для IPA на устройство `build-system/WGBuildRelease.sh` нужен ещё сертификат распространения (`.p12` с пустым
паролем) в `build-system/wraithgram-codesigning/certs/` и профили распространения для тех же App ID.

Эти шаги повторяют то, что проверяют скрипты сборки (`build-system/Make/BuildConfiguration.py`). На настоящем
аккаунте их ещё не проверяли. Если сборка пишет, что не хватает права (entitlement) или оно не совпадает,
включи эту возможность на App ID и скачай профиль заново.

## Подпись купленным сертификатом

Купленный сертификат обычно состоит из `.p12` с паролем и одного ad-hoc `.mobileprovision` для твоего
устройства. Его профиль покрывает один App ID и задаёт свои App Groups. Сборка может его использовать, но
приложение собирается без расширений: без «Поделиться», виджетов, Siri и расширения уведомлений.

1. Посмотри профиль:

   ```sh
   security cms -D -i PROFILE.mobileprovision
   ```

   `PROFILE` — имя файла профиля. Запиши `application-identifier` (`TEAM.BUNDLE`), первую группу из
   `com.apple.security.application-groups` и проверь, что есть `aps-environment`.

2. Создай `build-system/wraithgram-configuration-device.json` — копию `build-system/wraithgram-configuration.json`,
   где `bundle_id` равен `BUNDLE`, `team_id` равен `TEAM`, и добавь поле `app_group` с группой из шага 1. Файл в
   `.gitignore`.

3. Создай папку `build-system/wraithgram-codesigning-device/`:
   - в `profiles/` положи профиль;
   - в `certs/` положи `.p12`, файл `password` с его паролем и промежуточный сертификат Apple
     [`AppleWWDRCAG3.cer`](https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer).

   Папка в `.gitignore`. Если импорт падает с `MAC verification failed`, перепакуй `.p12` в алгоритмы, которые
   принимает macOS:

   ```sh
   openssl pkcs12 -in OLD.p12 -passin pass:PASSWORD -legacy -nodes -out identity.pem
   openssl pkcs12 -export -in identity.pem -out NEW.p12 -passout pass:PASSWORD -legacy \
       -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1
   rm identity.pem
   ```

4. Собери:

   ```sh
   WG_CONFIG=build-system/wraithgram-configuration-device.json \
   WG_CODESIGN=build-system/wraithgram-codesigning-device \
   build-system/WGBuildRelease.sh 1 --disableExtensions
   ```

   Скрипт на время сборки импортирует сертификат во временную связку ключей и потом возвращает список связок
   как был. Результат — `build-output/ipa/Wraithgram.ipa`, подписанный для твоего устройства.

Когда продавец сертификата его отзовёт, установленное приложение перестанет запускаться, пока его не подпишут
заново.

### Или переподпиши на устройстве

Программы вроде ESign или LCSign переподписывают IPA твоим сертификатом прямо на iPhone, вместе с
расширениями. Для них собери IPA со своим bundle ID:

```sh
build-system/WGBuildResign.sh
```

Результат — `build-output/ipa/Wraithgram-for-resign.ipa` с bundle ID `org.wraithgram.app` (поменять можно через
`WG_RESIGN_BUNDLE_ID`). Она подписана тестовыми профилями Telegram, перенацеленными на этот ID; программа
подписи заменит подпись. Никогда не переподписывай IPA с bundle ID `ph.telegra.Telegraph`: программа подписи
может его оставить, и тогда IPA встанет поверх официального Telegram. `WGBuildRelease.sh` такой bundle ID не
принимает. При запуске приложение и каждое расширение открывают App Group из
профиля, которым их переподписали (первую группу в `embedded.mobileprovision`), если `group.<bundle ID>`
недоступна.
