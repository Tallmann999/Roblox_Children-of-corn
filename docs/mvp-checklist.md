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
- [x] Три контейнера кода в открытой Studio подтверждены скриншотом пользователя.
- [x] Сцена place/Children_of_corn.rbxl сохранена; все 8 скриптов сверены с src, обе Bootstrap включены; структура Workspace/Lighting прежняя.
- [ ] Прочитан живой DataModel и подтверждена сохранность Workspace/Terrain/Lighting.
- [x] Studio Output показывает старт 2 services / 0 controllers без новых ошибок основы; подтверждено скриншотом пользователя 13:48:32.
- [x] Test основы выполнен пользователем; оба Bootstrap сообщения видны на скриншоте.
- [ ] Доступен Studio MCP для последующих автоматических проверок.

## Игровые MVP-фичи — прототип подготовлен, Studio приёмка открыта

| feature_id | Минимальная приёмка | Статус |
|---|---|---|
| cornfield_map | Одна проходимая карта, около 15 доступных слотов, обзор с прыжка/бочек, доступный выход | Prototype / Test pending |
| first_person_movement | Первое лицо; спринт 4 с / восстановление 6 с; прыжок без отдельного расхода | Planned |
| key_and_escape | Один ключ, E-подбор/открытие ворот, победа только после пересечения выхода | Prototype / Test pending |
| scarecrow_hunt | Активация 15 с; слышимая угроза, патруль/погоня, выполнимый уход | Planned |
| second_chance | Первый захват роняет ключ и возвращает на старт; второй завершает раунд | Planned |
| sound_and_atmosphere | Собственный/чужой шелест, направление, рычание, тревожный дневной туман | Planned |
| round_ui_restart | Цель/попытки/выносливость/ключ, исход и новый раунд без старых состояний | Prototype / Test pending |
| session_diamonds | +10 один раз за побег; 0 за остальные исходы; баланс до остановки теста | Prototype / Test pending |
| core_round | Полный цикл и ac_01–ac_20 из GD spec; ручной протокол новых игроков | Planned |

До начала следующего slice: прочитать сцену, сопоставить теги из architecture.md с реальными объектами, проверить доступность старта/ворот/слотов. Ни один игровой пункт не отмечать готовым только после code generation или CLI build.

## Записи проверок основы

| Проверка | Фактический результат |
|---|---|
| Bootstrap | core@0.1.0, network@0.1.0, tags@0.1.0 |
| Исходные GD-документы | Во время bootstrap SHA-256 совпали с исходными; последующие GD-правки отражают только статусы реализации |
| Formatting | stylua --check src: успешно |
| Lint | selene src: 0 errors / 0 warnings / 0 parse errors |
| Serialization | rojo build и sourcemap: успешно; три контейнера найдены |
| World ownership | default.project.json не содержит Workspace/Lighting; неизвестные DataModel instances сохраняются |
| Persistence | Disabled; player-data/economy не установлены |
| Plugin | Файл RojoManagedPlugin.rbxm существует; установка CLI завершена |
| Serve | localhost:34872, ответ API 200 и идентичность ChildrenOfCorn/7.7.0 подтверждены |
| Сохранённая сцена | 09.10.2026 13:43:12, 80 231 байт; 3 контейнера, 8/8 источников совпадают с src, обе Bootstrap включены |
| Studio / gameplay | Test основы выполнен пользователем, Output: 2 services / 0 controllers; игровые механики ещё не проверены; живой DataModel/MCP недоступны |

## Сохранённая сцена и ближайший ручной шаг

Рабочий snapshot: place/Children_of_corn.rbxl. Первая версия файла, сохранённая в 13:33:31, содержала только исходную сцену без скриптов. После сообщения пользователя «сохранил сцену» повторное чтение файла, сохранённого в 13:43:12, подтвердило подключённую основу. SHA-256: e5b3c90d6ea34000c96cbaa57bc8651785f5e6f77cae06620f1366673ef46f4c. Файл не изменялся проверкой.

В Workspace: Camera, Baseplate с Texture, Terrain и SpawnLocation с Decal. В Lighting: Sky, SunRays, Atmosphere, Bloom и DepthOfField. Эта структура прежняя; содержимое Terrain отдельно не проверено. Непустых сохранённых тегов нет. Кукурузное поле, ворота, слоты ключа и монстр ещё не созданы.

Проверка запуска основы выполнена пользователем и подтверждена скриншотом 2026-10-09_13-48-32.png. Следующий этап — временный прототип ключевого цикла из architecture.md; его игровая приёмка остаётся открытой.

## Подготовлен первый игровой этап

- [x] RoundService + SoloRound: состояние, проверяемые E-взаимодействия, выход, +10 один раз, повтор/меню/прерывание, сброс при Reset.
- [x] Клиентское меню/цель/результат и начальная синхронизация состояния.
- [x] Временная площадка, 15 слотов, три бочки из Parts; клонирование шаблона кукурузы.
- [x] Предоставленные FBX/PNG скопированы; подготовлена отдельная копия FBX с привязкой изображения, исходные geometry/UV не изменены.
- [x] Format/lint/build/sourcemap первого этапа выполнены, линтер без ошибок/предупреждений.
- [ ] Кукуруза импортирована в Studio и текстура визуально подтверждена.
- [ ] Новый код сохранён в пользовательской сцене после синхронизации Rojo.
- [ ] Выполнен Test нового этапа: ожидаемые 3 services / 1 controllers, проверки slice_01–slice_12.

Ближайшее действие пользователя — импортировать подготовленный FBX в ServerStorage/CornPlantTemplate. Шаги и приёмка: [first-slice-playtest.md](first-slice-playtest.md). Все функциональные статусы остаются открытыми до реального Test.
