# Дети кукурузы

Одиночный психологический хоррор для Roblox: найти ключ в густом поле и сбежать от ожившего чучела. Первый MVP рассчитан на локальный тест Roblox Studio на ПК.

**Текущий результат — техническая основа, а не готовая игра.** Установлены core/network/tags из RobloxGameKit 0.1.0; игровое поле, ключевой цикл, монстр и интерфейс ещё предстоит реализовать и проверить в Studio.

## Документы

- [Концепт](docs/project-concept.md)
- [MVP и отложенные фичи](docs/feature-index.md)
- [Правила основного цикла](docs/2026-10-09_core-loop_gd-spec.md)
- [Технический план](docs/technical-plan.md)
- [Архитектура и контракты мира](docs/architecture.md)
- [Чеклист и фактические проверки](docs/mvp-checklist.md)

## Команды из корня проекта

PowerShell; установка закреплённых инструментов и Studio plugin:

```powershell
.\scripts\setup.ps1
```

Проверка форматирования, lint, Rojo build и sourcemap:

```powershell
.\scripts\check.ps1
```

Запуск локального сервера синхронизации:

```powershell
.\scripts\serve.ps1
```

Сейчас сервер уже запущен на 127.0.0.1:34872. В Roblox Studio открой мир и Plugins → Rojo → Connect. После перезапуска компьютера/остановки сервера команда serve запускает его снова. Останавливать foreground-сервер можно Ctrl+C.

Для прямых команд в текущем терминале:

```powershell
. .\scripts\use-project-tools.ps1
rojo --version
stylua --check src
selene src
```

Инструменты находятся в игнорируемой .tools/, версии закреплены в rokit.toml; настройки системного PATH и PowerShell profile не менялись. Rokit 1.2.0 скачивается из официального релиза с проверкой SHA-256. Для новой установки нужен доступ к GitHub.

## Мир и код

Studio владеет Workspace/Terrain/Lighting. Rojo синхронизирует только:

- ReplicatedStorage/GameShared ← src/shared
- ServerScriptService/GameServer ← src/server
- StarterPlayer/StarterPlayerScripts/GameClient ← src/client

Рабочая сцена сохранена как place/Children_of_corn.rbxl. Все 8 скриптов в сохранённой сцене сверены с src; запуск Test и Output ещё предстоит проверить. Не подменяй её build/code-foundation.rbxlx: это пустой по окружению проверочный артефакт кода.

Публикация, DataStore, магазины и мультиплеер в этот этап не входят. Подключение Studio и Play Test отмечаются отдельно после фактической проверки.

Источник основы: [RobloxGameKit_v0.1.0](https://github.com/Tallmann999/RobloxGameKit_v0.1.0), revision 960e068352e187fc1d2129305f8fcfb07faf2782. [Установленные модули](robloxgamekit.lock.json).
