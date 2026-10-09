# Дети кукурузы — MVP checklist

Дата: 2026-10-09. Отмечаются только фактически выполненные действия. Установка технической основы не означает готовность игровых фич.

## Техническая основа — выполнено

- [x] Прочитаны CODEX_MASTER_INSTRUCTION_RU, каталог модулей, workflow и документация игры.
- [x] Выбран минимум core + network + tags; interaction/ui/audio изучены как blueprints.
- [x] Выполнен штатный bootstrap без force и перезаписи исходных GD-файлов.
- [x] Источник 0.1.0 и revision закреплены в robloxgamekit.lock.json.
- [x] Rojo управляет только GameShared/GameServer/GameClient; mapping мира отсутствует.
- [x] Настроен DEV/solo_local/PC; баланс перенесён из GD spec; persistence отключён.
- [x] Установлены проектные Rokit 1.2.0, Rojo 7.7.0, StyLua 2.5.2 и Selene 0.31.0.
- [x] Установлен RojoManagedPlugin.rbxm в локальную папку Plugins Roblox Studio.
- [x] StyLua check, Selene и Rojo build/sourcemap пройдены; линтер: 0 errors, 0 warnings, 0 parse errors.
- [x] Запущен localhost Rojo на 34872; HTTP 200, project ChildrenOfCorn и версия 7.7.0 подтверждены.
- [x] Созданы technical-plan.md, architecture.md, команды setup/check/serve и инструкция запуска.
- [ ] Плагин Rojo подключён к конкретному открытому миру.
- [ ] Прочитан живой DataModel и подтверждена сохранность Workspace/Terrain/Lighting.
- [ ] Studio Output показывает старт 2 services / 0 controllers без новых ошибок.
- [ ] Play Test основы выполнен в Studio.
- [ ] Доступен Studio MCP для последующих автоматических проверок.

## Последующие MVP-фичи — не реализованы

| feature_id | Минимальная приёмка | Статус |
|---|---|---|
| cornfield_map | Одна проходимая карта, около 15 доступных слотов, обзор с прыжка/бочек, доступный выход | Planned |
| first_person_movement | Первое лицо; спринт 4 с / восстановление 6 с; прыжок без отдельного расхода | Planned |
| key_and_escape | Один ключ, E-подбор/открытие ворот, победа только после пересечения выхода | Planned |
| scarecrow_hunt | Активация 15 с; слышимая угроза, патруль/погоня, выполнимый уход | Planned |
| second_chance | Первый захват роняет ключ и возвращает на старт; второй завершает раунд | Planned |
| sound_and_atmosphere | Собственный/чужой шелест, направление, рычание, тревожный дневной туман | Planned |
| round_ui_restart | Цель/попытки/выносливость/ключ, исход и новый раунд без старых состояний | Planned |
| session_diamonds | +10 один раз за побег; 0 за остальные исходы; баланс до остановки теста | Planned |
| core_round | Полный цикл и ac_01–ac_20 из GD spec; ручной протокол новых игроков | Planned |

До начала следующего slice: прочитать сцену, сопоставить теги из architecture.md с реальными объектами, проверить доступность старта/ворот/слотов. Ни один игровой пункт не отмечать готовым только после code generation или CLI build.

## Записи проверок основы

| Проверка | Фактический результат |
|---|---|
| Bootstrap | core@0.1.0, network@0.1.0, tags@0.1.0 |
| Исходные GD-документы | SHA-256 после bootstrap совпадают с исходными; файлы не изменены |
| Formatting | stylua --check src: успешно |
| Lint | selene src: 0 errors / 0 warnings / 0 parse errors |
| Serialization | rojo build и sourcemap: успешно; три контейнера найдены |
| World ownership | default.project.json не содержит Workspace/Lighting; неизвестные DataModel instances сохраняются |
| Persistence | Disabled; player-data/economy не установлены |
| Plugin | Файл RojoManagedPlugin.rbxm существует; установка CLI завершена |
| Serve | localhost:34872, ответ API 200 и идентичность ChildrenOfCorn/7.7.0 подтверждены |
| Studio / gameplay | Не выполнено: нет доступного Studio MCP и подключённой сцены |

## Ручное подключение Studio

1. Открой нужный локальный мир или Baseplate в Roblox Studio.
2. Сохрани копию в place/dev-world.rbxl.
3. В Plugins открой Rojo и подключись к 127.0.0.1:34872.
4. Проверь в Explorer GameShared, GameServer, GameClient, а также сохранность своего мира; затем Play/Output.

Если текущий локальный сервер остановлен, сначала запусти из корня проекта scripts/serve.ps1. После подключения ответь «готово», чтобы перейти к чтению сцены и следующему slice. Для автоматического чтения и Play Test потребуется также подключить [Studio MCP](https://create.roblox.com/docs/studio/mcp).
