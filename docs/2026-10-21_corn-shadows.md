# Тени фонаря и ближайшей кукурузы

После следующего запроса автора B переведена на тени всей видимой карты и всех
Near/Far растений; прежний bounded controller для B отключён. ActualFar11180,
Near1532,0видимых частей карты без CastShadow; realmain/fillShadows=true.
[Актуальное refinement и Save](2026-10-21_maze02-refine-B.md) B1497688/b113d584… .
Ниже сохранена история прежнего ограничения256; A-сцена не редактировалась.

Текущий статус после переподключения B: контроллер и оба Shadows установлены
через MCP, повтор0, обычный Bootstrap запустил157Sources. Реальные main/fill
Shadows=true, HandFill=false;20кадров показали115ближайших casters, maxXZ27.696,
scanned593/1296, Far0. Камера поставлена диагностически, GPU кукурузы с фонарём
осмотрен; это не человеческая приёмка теней или долгий FPS. Тестовые Sources и
bindings удалены, B остановлена в Edit. Совместный engine Save с лабиринтом02
PASS: B1497748/SHA256108066bc0cf2a55f3c90d8db0ba7bef2eccb4a21351d5e9d53983fbcce8c50f3,
строгий verify-maze02-copy.py complete:true; точные байты движка, без сериализации.
Будущие saves проверяются новым maze02 verifier, поскольку старый
shadow-only verifier обязан отвергать новые world-дельты. Подробности и
сохранение: [реализация B](2026-10-21_maze02-B.md). Ниже сохранён подготовительный
этап и история первого отключения; его pending больше не означает отсутствие
установки в нынешней открытой B.

## Подготовленное изменение

По запросу автора 21 октября подготовлена узкая установка в B через Studio MCP: разрешить Shadows у Wide/Core и добавить один CornShadowController. Все 156 существующих Sources, включая прежний красноглазый B Warden, сохраняются без изменений. Яркость, угол, дальность и Pitch фонаря не меняются; слабый HandFill остаётся без теней.

Новый клиентский контроллер подхватывается обычным Bootstrap без изменения его Source. Раз в 0.3 секунды он выбирает максимум 256 ближайших собственных растений из плотных runtime chunks: вход в пределах 26 studs, удержание до 28. За обновление проверяется не более 1296 дочерних объектов ближайших chunks. Backdrop, сохранённый overview и геометрические шаблоны не меняются. Позиции/размеры/коллизии растений и обнаружение врагом не меняются.

Контроллер пишет CastShadow только при смене значения и восстанавливает собственные записи при движении, потере карты/персонажа и Destroy. Неизвестные изменения размера, геометрии, атрибутов, тегов, родителей или положения сохраняются; затронутые растения исключаются из дальнейших записей. Ограниченное штатное покачивание CornWind допускается. Изменение, в точности повторяющее текущее собственное булево значение или допустимую позу ветра, нельзя отличить по readback от собственной записи.

## Сохранность и установка

Неизменяемый исходный B помещён в [before-shadows.zip](../.artifacts/playtests/2026-10-21-corn-shadows/before-shadows.zip), без новой loose сцены. Архив SHA256 `86ba89f751d03a7a1b332a614b13bc2febdde88647b7a2db9db0ba8b068c2c29`, внутри точный B1494878/`f33571e819fb605130b05489789c93f11c0ef92a3e9762c77691130a60c3d9c0`. A остаётся `c1f054029ca729f314889ce7874c17c6e5f772cb20541a9c0ceedd796f3446b7`.

`scripts/build-corn-shadows-installer.py` независимо сравнивает 156 нативных Source hashes с чтением сохранённой принятой B. `scripts/install-corn-shadows.luau` принимает только остановленную Corn B с точными variant/project/630 bounds, известными Sources и банком. Неизвестные/частичные состояния и открытая вкладка нового Source отклоняются. При ошибке записи откатываются два Shadows и собственное добавление; повтор принятой установки даёт ноль изменений. Старые preset installers по-прежнему требуют Shadows=false и после новой установки не используются вслепую.

Новый `scripts/verify-corn-shadows-copy.py` предназначен для будущего нативного engine Save: ровно один default ModuleScript и два bank Shadowsfalse→true; все существующие Sources, world/art/Lighting/физика/mesh metadata/identity/parent/raw Terrain точны. Baseline читается из ZIP во внешний TemporaryDirectory; сериализации сцен нет. Неизвестные ручные изменения автора должны сохраняться и отдельно разбираться, а не удаляться ради прохождения verifier.

## Выполненные локальные проверки

- check.ps1 PASS: StyLua, Selene0errors/0warnings/0parse errors, code-only build/sourcemap и safe mappings. Selene использовал существующий API cache после ошибки загрузки. Единственный generated code-only rbxlx после проверки удалён; loose сцен по-прежнему две.
- `tests/corn-shadow-controller.luau` PASS, 668 assertions: бюджет/выбор/частота, A/B, очистка, движение, foreign edits, сохранение исходных теней и совместимость с ветром.
- `tests/corn-shadows-installer.luau` PASS, 49 assertions, 19 unsafe-state refusals и 4 точки отказа записи с откатом.
- Текущий `tests/flashlight-controller.luau` PASS: ЛКМ/default-on/lifecycle, 11 Parts/3 lens-directed Spots и прежние ownership/camera guards.

- `tests/corn-shadows-save-pipeline.py` PASS: 228 DOM refusals и 3 raw Terrain refusals; положительные случаи точного изменения, конечной editor Camera, FilteredSelection и доказанной по UID перестановки экспортных suffixes. Сцены не записывались.

Это приёмка перечисленных актуальных локальных fixtures, не всех исторических тестов и не новый FPS benchmark.

## Статус Studio

В начале заново перечисленная B `b8aaeed9-72e5-406e-a03a-f8b954120baf` была stopped Edit,156Sources,Realistic/GlobalShadows/Quality21/Edit21,5Lighting children,CameraFixed,Httpfalse; банк Shadowsfalse/false. [Нативный снимок](../.artifacts/playtests/2026-10-21-corn-shadows/native-before.json).

До первого исполнения установщика эта B отключилась от MCP. Установочный вызов получил `studio_id is not connected`; последующее перечисление показало только `Showroom.rbxlx`. Установка не произошла, Showroom не изменялся. Автору отправлена просьба открыть B в Edit с подключённым MCP. Нужны новое перечисление/проверка B, нативная установка/повтор, новый обычный Play, проверка реального main/fill/HandFill, близких/дальних casting parts и визуального результата. Затем — engine Save и строгая проверка. Windows мышь/клавиатура, UserGameSettings, плагины и публичная публикация не используются.
