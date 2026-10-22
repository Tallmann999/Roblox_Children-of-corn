# Живое подключение Rojo B — 22 октября 2026

Автор отдельно разрешил подключить B и проверить сохранение её отличий.
Свежий MCP target `2833e3b5-393b-426e-8775-fb5755a1f9b0` проверен как
Children_of_corn_B.rbxl / B / children_of_corn / 630. Play остановлен штатно.
Все 157 Sources и editor buffers совпали с принятым сохранением; открытых
редакторов скриптов с отдельными правками не было.

Запущен только B.project.json: Rojo7.7.0, 127.0.0.1:34874, PID19324.
Окно плагина и endpoint подготовлены через MCP. У плагина нет публичного
метода Connect для MCP; автор нажал Connect и подтвердил подключение.
Нативная панель Connected показала Children_of_corn_B.rbxl и нужный порт.

Первоначальная синхронизация сохранила точное состояние: 4615 текущих
экземпляров в persistent-service scope, их identities/parents/classes/names,
атрибуты, теги, 236115 читаемых свойств и все157 Sources. Ноль отличий,
добавлений или удалений относительно снимка перед подключением.

Для проверки передачи изменений в variants/B/shared/Game/CornLayout.luau
временно добавлен уникальный комментарий. Rojo передал его ровно в один B
Source; остальные156 сохранились. Затем исходные байты файла восстановлены
с guard обоих SHA256. Rojo убрал комментарий. Финальный полный снимок снова
совпал с первоначальным, включая Sources/world/Lighting/mesh metadata и
Terrain material palette. Служебных __Rojo_ConnectionUrl/session-lock узлов
не появилось. Owned _G снимки после проверки удалены.

Это сравнение доступных native свойств, не чтение скрытых raw mesh/Terrain
данных в RAM. Файлы сцен на диске независимо остались точными:
A c1f054029ca729f314889ce7874c17c6e5f772cb20541a9c0ceedd796f3446b7,
B 37ecae9122294a3cf507ff8942c4eef805db89eb7ae126718d623d87a12a2113.
Save, пересериализация сцен, commit, push и публикация не выполнялись.

Rojo B оставлен подключённым в Edit для дальнейшей работы автора.
Позднее при открытии C окно B исчезло из MCP, сервер PID19324 остался запущен.
Файл B в17:19:58 получил новый SHA256
`268474cacf629bdf450538e86876a8060363a1f458e253b8368cac8126bbab60`
при прежних1499324байтах. Причина записи и её инициатор не установлены.
Независимый строгий аудит complete:true подтвердил те же157Sources,
4634экземпляра, world/art/Lighting/physics/mesh/rawTerrain. Разрешённые отличия
только Camera CFrame/Focus и существующие FilteredSelection UniqueId.
Текущий reviewed hash в rojo/source-map.json обновлён после этого аудита;
повторный --check --saved прошёл для A/B. Это не изменение игровой карты.
Не подключать этот сервер к A, C или соседнему проекту с PlaceId0.
Новая отдельная сцена C заказана автором после завершения этой проверки;
её геометрия и код должны находиться вне A/B mappings.

Доказательства: .artifacts/playtests/2026-10-22-rojo-B-live/ — source-preflight,
native-before, native-initial-sync, native-probe, native-final-sync,
native-snapshot-scope, probe-plan и server-session. В исходниках snapshots
нет Source/property setters; только временное owned _G хранение отчёта.
