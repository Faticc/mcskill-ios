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
3. **Интерфейс, скопированный с Android** (коммит `01e35b2`, CI‑запуск `35965227231` на момент записи ещё шёл, результат **не проверен**).
   - Ориентация только горизонтальная, полноэкранный режим, шрифт Inter, иконки из Android (`scripts/import_android_assets.py` → `App/Assets.xcassets/Icons`), иконка приложения.
   - Файлы: `App/Theme.swift`, `Components.swift`, `Modal.swift` (окна и тосты), `AuthScreen.swift`, `HomeScreen.swift`, `Windows.swift` (настройки, помощь, список модов), `AppModel.swift` (состояние, сценарий «Играть», `LoginFlow`), `Prefs.swift`, `Platform.swift` (шаринг, «Файлы», голова скина), `DeviceInfo.swift` (данные для `--demo`).
   - Демо для скриншотов: `--demo --screen menu|settings|help|mods|progress|unavailable|mfa|totp`.
   - «Играть» сейчас доходит до профиля клиента и показывает окно «Клиент недоступен на iOS».

## Уроки CI (уже наступали)

- В цели SwiftPM, где только `.proto`, нужен хотя бы один `.swift`, иначе SwiftPM её пропускает (`McSkillProto.swift`).
- Нельзя передавать `-sdk iphoneos` или `-sdk iphonesimulator` в `xcodebuild` вместе с плагинами: не находятся `protoc-gen-*`. Платформу задаём только через `-destination`.
- В `info.properties` XcodeGen ключи `CFBundleIdentifier`, `CFBundleExecutable` и другие надо прописывать явно.
- Успех сборки проверяем по наличию `HTS.app/Info.plist`, а не только папки.

## Текущая задача: встроить JRE 8/17/25 и JIT из Amethyst‑iOS

Просьба владельца: «установка и встройка jre jit из amethyst, только сразу 8 17 25».

### Что выяснено

Источник: github.com/AngelAuraMC/Amethyst-iOS (GPL‑3.0). Копии нужных файлов лежат в `/tmp/amethyst/` (bash): `JavaLauncher.m`, `main.m`, `utils.m/.h`, `dyld_bypass_validation.m`, `Makefile`, entitlements.

**JRE**
- Адреса: `https://assets.angelauramc.dev/openjdk/ios-arm64/jre{8,17,21,25}-ios-aarch64.zip`. Внутри zip лежит `jre*.tar.xz`.
- Уже скачаны в scratchpad прошлой сессии (`...\scratchpad\jre\jre{8,17,25}.zip`, 21–27 МБ каждый). Их может не оказаться, тогда скачать заново.
- Amethyst кладёт их в бандл как `App.app/java_runtimes/java-N-openjdk`. Удаляет `ASSEMBLY_EXCEPTION, bin, include, jre, legal, LICENSE, man, THIRD_PARTY_README, lib/{ct.sym,jspawnhelper,libjsig.dylib,src.zip,tools.jar}`.
- Для Mach‑O выполняется `METHOD_CHANGE_PLAT` (исправление тега платформы). Его ещё надо посмотреть в `Makefile`; в CI это, вероятно, `vtool`.

**Запуск JVM** (`JavaLauncher.m`)
- `dlopen` `lib/jli/libjli.dylib` (Java 8) или `lib/libjli.dylib` (11+), затем `JLI_Launch`.
- Переменная окружения `HACK_IGNORE_START_ON_FIRST_THREAD=1`, JVM работает в отдельном потоке.
- Флаги: `-XX:+UnlockExperimentalVMOptions -XX:+DisablePrimordialThreadGuardPages`, `-XX:-UseCompressedClassPointers` (без entitlement extended‑VA), `-XX:+MirrorMappedCodeCache` на iOS 26.
- Перед запуском проверяют, что свободно достаточно виртуальной памяти.
- `JLI_Launch` вызывает `exit()` при завершении JVM, приложение закрывается. Вторую JVM в том же процессе не создать.

**JIT** (`utils.m`)
- `isJITEnabled`: `csops` → флаг `CS_DEBUGGED`.
- На iOS 26 или с TXM дополнительно нужен подключённый отладчик (`getppid() != 1`) и скрипт StikDebug.
- Функции `JIT26*` — это `brk #0xf00d` с кодом в `x16`: 1 PrepareRegion, 2 SendScript, 3 DetachAfterFirstBr, 4 PrepareRegionForPatching.
- Скрипты `Natives/resources/UniversalJIT26.js` и `UniversalJIT26Extension.js`.
- `DeviceHasTXM` помечен `__exported`: JVM, видимо, ищет его через `dlsym`. **Проверить** строками `libjvm.dylib`, какие символы JVM ждёт от приложения (`DeviceHasTXM`, `JIT26*`).
- `dyld_bypass_validation.m` нужен для загрузки неподписанных `.dylib` (JRE вне бандла, JNA, натив модов).

**Entitlements** (`entitlements.sideload.xml`): `get-task-allow`, `extended-virtual-addressing`, `increased-memory-limit`. В Amethyst их вшивают через `ldid -S`. У нас подписи сейчас нет (`CODE_SIGNING_ALLOWED=NO`). Можно добавить `ldid` в CI.

### План

1. **CI:** скачать JRE 8/17/25, распаковать, почистить, исправить платформу, положить в `HTS.app/java_runtimes/`. Проверить размер ipa.
2. **Нативная часть в приложении** (Objective‑C/C в `App/`, bridging header):
   - перенести проверку JIT и флагов TXM, `JIT26*`, обход проверки dyld, `DeviceHasTXM` с экспортом;
   - добавить загрузчик `libjli` / `libjvm`.
3. **Проверка Java**: `JNI_CreateJavaVM` в процессе приложения.
   - Прочитать `java.version` и `java.vm.info`, прогнать небольшой бенчмарк (заранее скомпилированный `Bench.class` через `DefineClass`), чтобы увидеть, что JIT работает.
   - Одна JVM на процесс: для следующей версии нужен перезапуск приложения.
   - Без JIT HotSpot не стартует даже с `-Xint` (шаблонный интерпретатор тоже генерирует код), поэтому без JIT показывать окно с инструкцией.
4. **Интерфейс:** в «Настройки → Продвинутые» раздел «Java»: список 8/17/25 с версией из файла `release`, статус JIT/TXM, кнопки «Проверить».
   - В «Играть» подбирать JRE по `javaMajor` (8/17/25; для 21 брать 25?) и проверять JIT.
5. Потом: LWJGL и рендер под iOS, загрузка клиентов (BLAKE3/CDN из `ClientSync`), сам запуск игры.

### Открытые вопросы

- Какой iPhone и какая iOS у друга (от этого зависит способ JIT: StikDebug или скрипт для TXM на iOS 26).
- Лицензия: код Amethyst под GPL‑3.0. Для личного использования проблем нет, при распространении нужно открыть исходники.
