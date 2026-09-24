# HTS iOS: прогресс и текущие задачи

Файл для передачи между сессиями. Обновлён 2026-09-24.

## Где что лежит

- Код: `C:\Users\User\Desktop\htsandroid\ios\`. Это отдельный git‑репозиторий, remote `github.com/Faticc/mcskill-ios` (приватный), ветка `main`.
- Android‑проект: `htsandroid\` (корень), remote `github.com/Faticc/McSkill-Android` (приватный). `ios/` и `backup/` в нём в `.gitignore`.
- Mac и iPhone нет, всё собирается и проверяется в GitHub Actions (`.github/workflows/ios.yml`, runner `macos-26`, прогон около 12 минут).
- `gh`: `C:\Program Files\GitHub CLI\gh.exe`, в старых окнах его нет в PATH. Залогинен как Faticc.
  - список запусков: `gh run list -R Faticc/mcskill-ios`
  - ошибки упавшего запуска: `gh run view <id> -R Faticc/mcskill-ios --log-failed`
  - артефакты (скриншоты, ipa, логи): `gh run download <id> -R Faticc/mcskill-ios -D <папка>`

## Что сделано

1. **Ядро `HTSCore`** (Swift‑пакет): gRPC‑клиент McSkill из тех же `.proto`, что на Android. Код генерируют плагины при сборке, `protoc` берётся из Homebrew (`protocPath`).
   - Уже есть: вход (MFA/TOTP), профиль, выход, список серверов, `clientProfile` (GetClient), ошибки с русскими текстами, сессия в Keychain, кэш серверов, лог `Documents/logs/launcher.log`.
   - Тесты: `swift test`. Живой тест с выдуманной сессией проходит, сервер отвечает `unauthenticated`, значит TLS и gRPC работают.
2. **CI:** `swift test` → XcodeGen → сборка под симулятор → скриншоты (`scripts/sim-screenshots.sh`) → неподписанный `HTS.ipa`.
3. **Интерфейс, скопированный с Android** (коммит `01e35b2`, проверен скриншотами CI).
   - Ориентация только горизонтальная, полноэкранный режим, шрифт Inter, иконки из Android (`scripts/import_android_assets.py` → `App/Assets.xcassets/Icons`), иконка приложения.
   - Файлы: `App/Theme.swift`, `Components.swift`, `Modal.swift` (окна и тосты), `AuthScreen.swift`, `HomeScreen.swift`, `Windows.swift` (настройки, помощь, список модов), `AppModel.swift` (состояние, сценарий «Играть», `LoginFlow`), `Prefs.swift`, `Platform.swift` (шаринг, «Файлы», голова скина), `DeviceInfo.swift` (данные для `--demo`).
   - Демо для скриншотов: `--demo --screen menu|settings|java|probe|help|mods|progress|unavailable|mfa|totp`. Скриншоты поворачиваются `sips -r 270` (simctl снимает портретный буфер).
4. **Java 8/17/25 и JIT из Amethyst‑iOS** (коммиты `4ac6067`…`CI: export check`, CI‑запуск `35970303659` зелёный, ipa 125 МБ; на телефоне **ещё не проверено**).
   - CI: `scripts/pack-jre.sh` кладёт JRE из `assets.angelauramc.dev` в `HTS.app/java_runtimes/java-N-openjdk` (чистка как в Makefile Amethyst, кэш `jre-cache`), `ldid` подписывает dylib и приложение с `entitlements.sideload.xml`. Проверка платформы Mach‑O для iOS не нужна (в Amethyst она только для PLATFORM≠2). ipa растёт примерно на 111 МБ.
   - `App/Native/HTSJava.{h,m}` + `App/HTS-Bridging-Header.h`, JNI‑заголовки в `App/Native/include` (jni.h из JDK 21, свой jni_md.h):
     - JIT: `csops` → `CS_DEBUGGED`; флаги iOS 26 / зеркальный JIT / TXM (A12 без TXM, A13–A14/M1 с iOS 27, остальные с iOS 19); на TXM нужен ещё подключённый отладчик.
     - `DeviceHasTXM` экспортирована: `libjvm` ищет её через `dlsym`, иначе читает `XNU_HAS_TXM` (ставим и её). Запросы `[JIT26]` к отладчику делает сама `libjvm`.
     - На TXM перед стартом JVM: проверка «legacy»‑брейкпоинта, отправка `UniversalJIT26Extension.js`, `JIT26SetDetachAfterFirstBr(YES)` (как в Amethyst). Скрипты в `Resources/JIT`, `UniversalJIT26.js` при запуске копируется в `Documents/JIT` для StikDebug.
     - Проверка: `JNI_CreateJavaVM` на своём потоке (8 МБ стека, поток потом паркуется), опции Amethyst (`DisablePrimordialThreadGuardPages`, `-UseCompressedClassPointers`, `MirrorMappedCodeCache` на iOS 26) + «Доп. аргументы JVM» из настроек, куча 256 МБ. Замеры: свойства, `Arrays.sort` 1 млн int × 6, `CompilationMXBean`. stdout/stderr → `Documents/logs/jvm.log`.
     - Одна JVM на процесс: вторая версия только после перезапуска.
   - Swift: `App/JavaRuntimes.swift` (список, выбор под клиент: 8 → 8, иначе ближайшая ≥, т.е. 21 → 25; `JITStatus`; `JavaProbeResult`). Настройки → Продвинутые → «Java». «Играть» показывает, какая Java пойдёт, и кнопку «Проверить Java». Метка `logs/jvm-probe.running`: если JVM уронила приложение, при следующем запуске окно с концом `jvm.log`.

## Уроки CI (уже наступали)

- В цели SwiftPM, где только `.proto`, нужен хотя бы один `.swift`, иначе SwiftPM её пропускает (`McSkillProto.swift`).
- Нельзя передавать `-sdk iphoneos` или `-sdk iphonesimulator` в `xcodebuild` вместе с плагинами: не находятся `protoc-gen-*`. Платформу задаём только через `-destination`.
- В `info.properties` XcodeGen ключи `CFBundleIdentifier`, `CFBundleExecutable` и другие надо прописывать явно.
- Успех сборки проверяем по наличию `HTS.app/Info.plist`, а не только папки.
- `grep -q` в пайпе под `pipefail` (bash в Actions) роняет шаг: писатель получает SIGPIPE. Сначала в файл, потом grep.
- `Platform` — `@MainActor`; из `static let` вне главного актора его не трогать.
- Генерическая сборка под симулятор собирает и x86_64: ассемблер arm64 закрывать `#if defined(__arm64__)`.

## Следующие шаги

1. **Проверить на телефоне.** Тестовый iPhone XR (A12, TXM нет, iOS не больше 18; версия пока неизвестна). JIT: StikDebug на iOS 17.4+, SideStore/JitStreamer на iOS 16 и ниже. Ставим ipa через Sideloadly, включаем JIT, «Настройки → Продвинутые → Java → Проверить» для 8, 17, 25 (с перезапуском между ними). Смотреть `jvm.log` и `launcher.log` (Файлы → HTS → logs).
   - Если не стартует: подписи dylib после пересборки сайдлоадером, `dyld_bypass_validation` (в Amethyst включается, когда TXM нет), память (у XR 3 ГБ).
2. LWJGL и рендер под iOS (GL4ES/ANGLE поверх Metal), ввод, окно игры.
3. Загрузка клиентов (BLAKE3/CDN, как `ClientSync` на Android), сам запуск через `JLI_Launch` или свою точку входа.

### Открытые вопросы

- Версия iOS на XR (от неё способ JIT).
- Лицензия: код Amethyst под GPL‑3.0. Для личного использования проблем нет, при распространении нужно открыть исходники.
