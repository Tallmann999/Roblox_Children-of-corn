# Отдельные Rojo-конфигурации A и B — 22 октября 2026

Актуальное дополнение23октября: [ручная B](2026-10-23_B-manual-authoring.md)
теперь имеет168ownedSources/182classes (171totalс3Fog), A153/165 прежняя.
142shared,11split,12legacyunmapped. Четыре новых split-пары:
InventoryWorld,HarvestWorld,RoundAudio,HarvestGeometryController; A-копии
побайтно соответствуют прежним shared. Новые B-only ManualScene,
ManualSceneService,AuthoringCornController.24isolation/refusal tests и
GET-only smoke PASS; live sync не включён. После авторского Ctrl+S и нового
строгого аудита PASS manifest принят для B3793205bytes/4c5c0c54…;
Rojo --check --saved PASS A153/156total,B168/171total,scene bytes unchanged.
Ниже — исходная настройка.

Автор разрешил настроить отдельные конфигурации Rojo для кода A и B,
чтобы различия сцен не перезаписывались общим `src`. Конфигурации созданы;
локальные проверки и сравнение с сохранёнными сценами прошли.
Локальный HTTP smoke также прошёл.
Live-подключение к Studio и сохранение сцен в эту задачу не входят.

## Состав конфигураций

| Конфигурация | Имя проекта | Адрес | Собственные Sources | Существующие вне Rojo |
| --- | --- | --- | ---: | --- |
| `A.project.json` | `Children_of_corn.rbxl` | `127.0.0.1:34873` | 153 | 3 Sources CornfieldFog |
| `B.project.json` | `Children_of_corn_B.rbxl` | `127.0.0.1:34874` | 154 | 3 Sources CornfieldFog |

Обе конфигурации используют 146 одинаковых Sources из `src`. Семь путей,
которые отличаются в принятых A и B, подключены из отдельных `variants/A`
и `variants/B`. В B также подключён собственный CornShadowController.
Всего в `variants` 15 файлов: семь пар и один файл только для B.

| Путь относительно `variants/A` или `variants/B` | A | B |
| --- | --- | --- |
| `shared/Game/CornAppearance.luau` | свой Source | свой Source |
| `shared/Game/CornLayout.luau` | свой Source | свой Source |
| `shared/Game/HarvestWardenVisual.luau` | свой Source | свой Source |
| `client/Controllers/CornBackdropController.luau` | свой Source | свой Source |
| `client/Controllers/CornController.luau` | свой Source | свой Source |
| `client/Controllers/CornWindController.luau` | свой Source | свой Source |
| `client/Controllers/FlashlightController.luau` | свой Source | свой Source |
| `client/Controllers/CornShadowController.luau` | отсутствует | свой Source |

Итого принятые сцены содержат 156 Sources в A и 157 в B. Упомянутые три
Fog-Sources остаются в сценах и не входят в управление Rojo. Каждый явно
описанный узел A/B имеет `$ignoreUnknownInstances: true`. Это сохраняет
неописанные объекты при синхронизации; известные Rojo скрипты по-прежнему
получают Source из соответствующего файла. Семантика параметра приведена
в [официальном формате проекта Rojo](https://rojo.space/docs/v7/project-format/).

Workspace, CornfieldFog, Lighting, банк фонаря, Terrain, меши и остальной
мир не включены в A/B mappings. Существующие различия геометрии и настроек
сцен продолжают храниться в `.rbxl`. Ручную копию
`Workspace.CornPlant_Editable_A` и её InspectionLight нужно сохранять.

Восемь прежних файлов с перечисленными именами остаются в `src` для
существующих fixtures и исторических проверок. Ни A, ни B не подключает
эти восемь legacy-путей из `src`. Для дальнейших правок перечисленных
Sources каноническими являются файлы `variants/A` и `variants/B`.
Остальные 146 общих Sources редактируются в `src` и меняются для обеих
вариантных конфигураций.

Имена проектов совпадают с `game.Name` соответствующих принятых сцен.
Связь Instance → файл и классы зафиксированы в `rojo/source-map.json`.
При добавлении нового кодового узла этот manifest нужно обновить явно;
`python .\scripts\rojo-ab.py --write-projects` пересоздаёт только A/B JSON
из manifest, после чего требуется `--check`. Перед `--write-projects`
нужно остановить работающие Rojo-серверы. Команда сначала валидирует план,
затем атомарно заменяет каждый JSON. Она не извлекает Sources из сцены и
не пересоздаёт frozen payload.

В Rojo 7.7.0 data-модули с `init.luau` должны подключаться через их
директорию. Прямой `$path` на `init.luau` не поддерживается, а совмещение
директории с явным повторным описанием её детей создаёт дубликаты. Поэтому
эти деревья подключены через директории, а 91 новый `.meta.json` задаёт
`{"ignoreUnknownInstances": true}` каждому автоматически включённому
кодовому узлу. Source существующих скриптов при этом не меняется.
Проверка контролирует состав всех таких директорий, точное содержимое
metadata, множество подключённых файлов и классы собранных Instances.

## Проверочная схема default

`default.project.json` сохраняет прежнее смешанное дерево из `src`, которое
используют проверки и code-only build. Его имя — `ChildrenOfCorn_CodeCheckOnly`,
а `servePlaceIds: []` запрещает live-подключение официальному плагину Rojo
7.7.0 для любого PlaceId. В этой версии плагин ищет текущий ID в списке
`expectedPlaceIds` и отклоняет соединение, если ID не найден; пустой список
не содержит ни одного разрешённого ID. Это подтверждено исходным кодом
[ApiContext.lua v7.7.0](https://github.com/rojo-rbx/rojo/blob/v7.7.0/plugin/src/ApiContext.lua).

`default.project.json` не является конфигурацией для редактирования A или B
через live sync. Запускать сервер нужно через вариантный wrapper.

## Обычный запуск

Из корня репозитория:

```powershell
.\scripts\serve.ps1 -Variant B
```

Для A используется `-Variant A`. Параметр `-Variant` обязателен; wrapper сам
выбирает конфигурацию, адрес localhost и порт. В плагине Rojo нужно выбрать
`localhost` и порт выбранной сцены: A — `34873`, B — `34874`. Остановка
сервера — `Ctrl+C` в терминале. Имя проекта и разный порт помогают
различать серверы, но не подтверждают принадлежность открытой сцены.

Локальные A и B имеют PlaceId `0`, поэтому проверка только по PlaceId не
может отличить их. Перед каждым первым live-подключением к процессу Studio
нужен свежий MCP preflight: точный Studio target, остановленный Edit,
имя `Children_of_corn.rbxl` либо `Children_of_corn_B.rbxl`, соответствующий
вариант A/B, project ID `children_of_corn` и размер поля `630`.
Нужно проверить ручные изменения управляемых Sources и сохранить их в
соответствующих файлах до подключения. Затем просмотреть initial diff
плагина: сопоставление должно относиться только к Sources выбранной
конфигурации. Неизвестные Sources и авторские объекты сохраняются.

Для первого live-подключения нужен отдельный запрос автора и описанный
MCP preflight. Настройка конфигураций не отменяет прежнее ограничение на
live sync. В ходе этой задачи сервер к Studio не подключается, открытая B
в Play не перезапускается и не сохраняется. Действия со Studio остаются
через MCP, без Windows-ввода и без изменения других игр.

## Локальная проверка

```powershell
. .\scripts\use-project-tools.ps1
python .\scripts\rojo-ab.py --check
python .\scripts\rojo-ab.py --check --saved
```

`--check` проверяет mappings, состав Sources, разделение overrides и
фактические Rojo builds A/B. Проверочные builds содержат код и не заменяют
рабочие `.rbxl`: мир не входит в проект. Это также соответствует
[описанию преобразования файлов и ограничений live sync Rojo](https://rojo.space/docs/v7/sync-details/).

`--check --saved` дополнительно читает принятые `.rbxl` и сравнивает их
Sources с конфигурациями. Это read-only проверка исходного baseline:
после намеренных правок кода отличие от старого сохранения ожидаемо,
и его нужно оценить перед синхронизацией. Изменённые сохранённые `.rbxl`
также требуют нового отдельного аудита: исходные размеры и SHA256
в manifest не являются разрешением перезаписать более свежую сцену.
Команда не устанавливает код,
не меняет `.rbxl` и не пересоздаёт frozen payload.

Исходные принятые файлы:

| Сцена | Размер | SHA256 |
| --- | ---: | --- |
| `place/Children_of_corn.rbxl` | 1 491 827 байт | `c1f054029ca729f314889ce7874c17c6e5f772cb20541a9c0ceedd796f3446b7` |
| `place/Children_of_corn_B.rbxl` | 1 499 324 байта | `268474cacf629bdf450538e86876a8060363a1f458e253b8368cac8126bbab60` |

Новый B hash принят после открытия C и строгого повторного аудита:
игровые данные/Sources/rawTerrain сохранены, отличаются только допустимые
Camera/FilteredSelection editor metadata. Первоначальный setup checkpoint
имел hash37ecae91…; подробности в docs/2026-10-22_rojo-B-live.md.

Фактическая проверка `--check --saved` прошла: A — 153 управляемых
Sources/165 кодовых Instances, B — 154/166. Все 156 Sources сохранённой A
и 157 Sources B соответствуют выбранным mappings и unmanaged Fog;
размеры и SHA256 обеих сцен остались неизменными.

Локальные проверки:

- `check.ps1` — PASS с cached API dump, Selene: 0 errors/0 warnings/0 parse
  errors; стиль проверен для `src` и `variants`.
- 16 тестов Rojo A/B — PASS.
- `serve.ps1 -Variant B -CheckOnly` — PASS, без запуска сервера.
- Вызов wrapper без `-Variant` отклонён до запуска — PASS.
- Реальный build/sourcemap и `--check --saved` для обеих сцен — PASS.

Локальный HTTP smoke — PASS: настоящий сервер A выдаёт 170 узлов/153 Sources,
B — 171/154; у каждого узла, включая все implicit data-модули, установлен
`ignoreUnknownInstances=true`. Точные имена, классы и Sources совпали с
вариантными файлами; Properties содержат только Source и Legacy RunContext.
Default API вернул `expectedPlaceIds=[]`. Все три временных сервера остановлены;
использовались только GET-запросы без подключения Studio и синхронизации.
Воспроизведение: `python .\tests\rojo-serve-smoke.py` при свободных портах
34872–34874; тест не завершает чужие процессы.

Результаты: [validation.json](../.artifacts/playtests/2026-10-22-rojo-variants/validation.json)
и [serve-smoke.json](../.artifacts/playtests/2026-10-22-rojo-variants/serve-smoke.json).

Старая цепочка guarded installers и строгих аудитов сохранения остаётся
исторической и относится к своим frozen payload. Нельзя генерировать её
payload заново из будущих `src`/`variants` или запускать старые installers
поверх нового кода. Настройка Rojo не подтверждает FPS, прохождение,
визуальную приёмку теней или иные игровые проверки.
