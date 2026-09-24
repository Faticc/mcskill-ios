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

5. **Java в симуляторе CI** (шаг «Java and rendering in the simulator», артефакт `java-probe`): `pack-jre.sh … simulator` меняет тег платформы JRE на 7 (`vtool`) и подписывает ad-hoc, `scripts/sim-java-probe.sh` запускает приложение с `--probe-java 8|17|25`. Итог пишется в `logs/jvm-probe.json`. Все три JVM стартуют (72–159 мс), mixed mode, JIT через зеркальный кэш iOS 26 (`[JIT26] mapping at RW/RX`). Это не проверяет `csops`, StikDebug, TXM и лимиты памяти настоящего iPhone.
6. **Рендер: SDL3 + ANGLE + gl4es + LWJGL 3.4.1** (коммиты `Render path…` и дальше).
   - `sdl/SDL_uikit_hts.m` + `scripts/build-sdl.sh`: SDL 3.4.16 под iOS (device и simulator, кэш `build/sdl-out`). Файл встраивается в бэкенд uikit (хук в конце `UIKit_CreateDevice`):
     - всё, что трогает UIKit (окно, текстовый ввод, Metal‑view, экраны), выполняется в главном потоке через `dispatch_sync`; `PumpEvents` вне главного потока runloop не крутит;
     - GL через EGL ANGLE на `CAMetalLayer` Metal‑view окна (как `gl_bridge.m` у Amethyst). Конфигурация перебирается от ES3/24/8 к ES2/0/0 и пишется в stdout (`[HTS] EGL …`);
     - экспорт `HTS_SendKey/Text/MouseMotion/MouseButton/MouseWheel`, `HTS_RelativeMouse` для оверлея управления (внутренние вызовы SDL, чтобы его состояние клавиш и мыши было верным).
   - `scripts/pack-game-libs.sh`: ANGLE (`libEGL/libGLESv2.framework`), `libgl4es_114.dylib`, `libopenal.dylib` из Amethyst‑iOS (коммит `9212a18`), LWJGL 3.4.1 (натив + jar из одной сборки, релиз **`deps-1`** этого репо, взято из артефакта AngelAuraMC/lwjgl3 `wip/rebase_3.4.1`), наш SDL3 → `HTS.app/Frameworks`; jar → `HTS.app/game/lwjgl-3.4.1`; `hts-lwjgl-patch.jar` (CI собирает `lwjgl-patch/`), `MioLibPatcher.jar`, `log4j-rce-patch-1.7.xml` (папка `game/`) → `HTS.app/game`.
   - `HTSJava launch(javaHome:…mainClass:…)`: JVM + `main(String[])` на своём потоке (16 МБ стека), переменные окружения, `SDL_SetMainReady` по `HTS_SDL_LIBRARY`. `App/GameRuntime.swift`: пути, опции LWJGL, env gl4es.
   - `tests/gltest/HtsGLTest.java` (`--gltest`, скрипт `scripts/sim-gltest.sh`): окно SDL, GL 2.1 через gl4es, треугольник, отчёт `logs/gltest.json`, скриншот `gltest.png`.
   - **Состояние на прогоне `35980389631`:** SDL стартует (`uikit`), окно создаётся из потока Java, gl4es грузится и видит ANGLE (свой контекст ES2 создал), оверлей управления появляется над окном SDL. Падало на `eglChooseConfig` (ни одной конфигурации ES3/24/8 + PBUFFER). Исправление с перебором конфигураций закоммичено, но **ещё не прогонялось**: закончились минуты Actions.
   - Форк LWJGL от Amethyst в `Library.<clinit>` делает `System.load($BUNDLE_PATH/AngelAuraAmethyst)` (мост GLFW Pojav); для SDL‑паков не нужно, ошибка перехватывается.
7. **Синхронизация клиентов** (`HTSCore/…/ClientSync.swift`, `Blake3.swift`): порт Android `ClientSync` (правила путей лаунчера, `HashIndex` по размеру и mtime, режимы целостности, CDN `base/hh/hash` с докачкой `.part` и хешем на лету, узел‑замена, gRPC пачками, удаление лишнего, проверка места), `PatchLedger` (правленые конфиги не перекачиваются). BLAKE3 сверен с официальными векторами в `swift test`. Папки: `Documents/clients/<client_dir>`, `Documents/assets/<assets_dir>`, записи в `Documents/installed/<client_dir>`. **С настоящим сервером ещё не запускалось.**
8. **Запуск пака** (`App/GameLauncher.swift`): порт `LaunchSpec`+`JvmLauncher` для SDL‑паков (Forge 1.7.10 + lwjgl3ify 3, главный класс `…MainStartOnFirstThread`: HiTech, TechnoMagic, Galaxy). Аргументы JVM из профиля без ПК‑флагов (+ `-XX:+UseCompactObjectHeaders` выкидывается: без extended VA нет сжатых указателей классов), `--add-opens x` склеивается в `--add-opens=x`, API‑аргументы McSkill, classpath: патч → LWJGL 3.4.1 iOS → jar пака без заменённых модулей LWJGL и десктопных нативов; аргументы аккаунта как `play.py`; env `HTS_GL_PROFILE=es`, `MAJOR=3`, `HTS_GL_PROC_LIB=gl4es`; правки `lwjgl3ify.cfg` (sharedContext=false), `splash.properties`, ALS, FpsReducer, optional. NeoForge и GLFW‑паки (Oneblock3) показывают окно «пока не запускается».
   - «Играть»: профиль → проверки (Java, тип пака, JIT, библиотеки) → синхронизация с прогрессом и отменой → запуск → оверлей управления.
9. **Управление** (`App/Native/HTSControls.m`): окно над окном SDL (ищется по `SDL_uikitviewcontroller`): стик WASD, прыжок, присед‑переключатель, Esc/E/T/Q/F5, экранная клавиатура (скрытый `UITextField` → `HTS_SendText`, Backspace/Enter), хотбар по GUI‑масштабу из `options.txt`. В мире: ведение = камера (относительная мышь), короткий тап = ПКМ, удержание 0,3 с = ЛКМ (ломать). В меню: касание = курсор + ЛКМ.

## Уроки CI (уже наступали)

- В цели SwiftPM, где только `.proto`, нужен хотя бы один `.swift`, иначе SwiftPM её пропускает (`McSkillProto.swift`).
- Нельзя передавать `-sdk iphoneos` или `-sdk iphonesimulator` в `xcodebuild` вместе с плагинами: не находятся `protoc-gen-*`. Платформу задаём только через `-destination`.
- В `info.properties` XcodeGen ключи `CFBundleIdentifier`, `CFBundleExecutable` и другие надо прописывать явно.
- Успех сборки проверяем по наличию исполняемого `HTS.app/HTS` (а не `Info.plist`: он появляется до линковки).
- `grep -q` в пайпе под `pipefail` (bash в Actions) роняет шаг: писатель получает SIGPIPE. Сначала в файл, потом grep.
- `Platform` — `@MainActor`; из `static let` вне главного актора его не трогать.
- Генерическая сборка под симулятор собирает и x86_64: ассемблер arm64 закрывать `#if defined(__arm64__)`.
- Swift сам переименовывает методы Objective‑C, убирая слово из имени класса (`launchJavaHome` → `launchHome`): имена закреплять `NS_SWIFT_NAME`. `int` в заголовке = `Int32` в Swift.
- Workflow запускается только на ветки: тег от `gh release create` иначе стартует лишнюю сборку.
- **Минуты:** репозиторий приватный, macOS‑минуты идут ×10. 24.09 после ~20 прогонов лимит кончился («spending limit needs to be increased»). Коммиты собирать крупнее.
- Bash‑heredoc в этом окружении портит `\\` → файлы с обратными слэшами писать через Write/Edit.

## Следующие шаги

1. **CI**: репозиторий публичный с 24.09, минуты бесплатны. Первый же прогон проверит перебор EGL‑конфигураций: смотреть `java-probe/gltest.json`, `gltest-jvm.log` (`[HTS] EGL …`), `gltest.png`.
2. Когда треугольник нарисуется в симуляторе: проверить на XR (Sideloadly, JIT через StikDebug): «Проверить Java», затем «Играть» на HiTech (1.7.10, Java 25). Логи: Файлы → HTS → logs (`launcher.log`, `jvm.log`).
3. Дальше по результатам: HtsGLBaton/сплэш, темп кадров (`HtsSurface` без Android‑файла), звук (OpenAL из Amethyst), клавиатура чата, GLFW‑паки через Pojav‑GLFW Amethyst (мост `AngelAuraAmethyst`), NeoForge.

### Открытые вопросы

- XR: iOS 18.6.2 (A12, TXM нет) → JIT через StikDebug (нужен pairing file с компьютера один раз).
- Лицензия: код Amethyst под GPL‑3.0. Для личного использования проблем нет, при распространении нужно открыть исходники.
