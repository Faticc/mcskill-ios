# HTS для iOS

Лаунчер McSkill под iOS. Пишется на Windows, собирается и проверяется в GitHub Actions (macOS‑раннер).

## Что внутри
- `HTSCore/` — Swift‑пакет без UI: gRPC API McSkill (код из `.proto` генерируется при сборке), сессия в Keychain, кэш серверов, лог.
- `App/` — SwiftUI: вход (с 2FA через Telegram и кодом из приложения), список серверов, страница сервера.
- `project.yml` — описание проекта для XcodeGen, `.xcodeproj` в git не хранится.
- `.github/workflows/ios.yml` — `swift test` → сборка под симулятор → скриншоты → неподписанный `HTS.ipa`.

## Что выдаёт CI (артефакты запуска)
- `HTS-ipa`: ставится на iPhone через Sideloadly или AltStore/SideStore под своим Apple ID.
- `screenshots`: экран входа и список серверов в демо‑режиме (`--demo`), плюс лог приложения из симулятора.
- `logs`: вывод тестов и сборок.

## Логи с телефона
Меню «…» → «Поделиться логами», или приложение «Файлы» → На iPhone → HTS → logs.

## Пока нет
Запуска игры: JRE, LWJGL, рендер и JIT под iOS — следующие этапы.
