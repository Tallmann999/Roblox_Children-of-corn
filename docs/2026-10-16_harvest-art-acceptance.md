# Сторож урожая: интеграция A/B — 16 октября 2026

Статус: обе версии установлены и проверены в настоящем Studio Play с одним клиентом. Автор сохранил A и отдельный B; строгий аудит обоих engine-сохранений **PASS**. Каждый из 291 нового art nodes независимо рассмотрен до закрепления манифеста. Повторная приёмка после закрытия/reopen остаётся открытой.

## Объём изменения

| Версия | Оформление |
|---|---|
| A | Прежняя кукуруза и красные сараи; добавлены заборы, камни и Classic-Сторож с красными глазами |
| B | Четыре новые формы кукурузы, Detailed-Сторож, тёмные фасады сараев, заборы, камни, покрытия земли и дороги |

Это оформление текущего local Studio DEV/team_local. Общий ключ, ворота, таймер, личные две поимки и +20 session diamonds, предел 1–4, ожидание поздних игроков и правила следующего раунда сохраняются. Баланс обнаружения остаётся 48 до ворот и 96 после появления трёх NPC. Persistence, покупки, lobby и публичная публикация не добавлены.

Blender-пак и реальная интеграция Roblox — разные этапы. Экспортированные FBX/GLB и пять Actions остаются доступными как исходники; игровой адаптер использует отдельные визуальные секции и процедурные позы по серверным состояниям patrol/chase/trapped/capturing. Загрузка этих Actions как cloud AnimationId не заявляется.

## Геометрия, материалы и бюджеты

Из действительных GLB получен [Roblox-каталог](../assets/harvest-warden/roblox-catalog.json): 25 ассетов, 86 мешей, 22 608 треугольников; optional door leaves в активный каталог не входят. [Манифест каталога](../assets/harvest-warden/catalog-manifest.json) содержит происхождение и SHA256 исходников/68 data Sources. Размер каждого data Source не превышает 135 000 UTF-8 байт. Исходные `.blend` и FBX не заменяются этой сборкой.

EditableMesh строится отдельно на каждом peer. Клиентские шаблоны и восстановление сохранённых owned MeshPart не полагаются на перенос динамического Content.Object по сети или на наличие постоянного MeshId. Владение и точная связь с каталогом проверяются атрибутами; изменённый вручную или чужой объект сохраняется при отказе.

В B форма растения определяется целочисленными координатами сетки и остаётся той же при смене LOD. Четыре ближайших dense chunks дают максимум 576 Near-растений; остальные ближние группы используют Mid, полный дальний фон — Far. Near содержит 1378–1470 треугольников на растение, Mid — 276, Far — 100. Основание учитывает асимметричный bbox листьев; базовая высота 8 и прежняя вариация сохраняются. Сетка, просветы, позиции предметов, коллизии растений и предел ветра в четыре контактных стебля не изменены. Эти лимиты не являются измерением FPS.

[Реестр пяти загруженных текстур](../assets/harvest-warden/roblox-textures.json) связывает точные PNG с Roblox URI. В native probe corn leaf, burlap и coat canvas получили AssetFetchStatus.Success; у кукурузы зафиксированы ContentSourceType.Object, высота 8 и URI 130010939468822. Это отдельный [native-geometry.json](../.artifacts/playtests/2026-10-16-harvest-art/native-geometry.json), а не утверждение о всех пикселях/материалах в любых сетевых условиях.

У каждого Сторожа два красных Neon-глаза и два PointLight: Range 24, Brightness 3, Shadows=false. Нативные observers подтвердили оба включённых источника света и меняющиеся относительные позы всех трёх NPC. Высота глаз около 10 studs над землёй; это позволяет расположить их выше обычной кукурузы, но человеческая оценка дальнего свечения, Bloom и страха ещё открыта.

## Установка Sources и сохранность до Save

Неизменяемая исходная сцена: `place/Children_of_corn.before-harvest-art-20261016.rbxl`, 1 003 371 байт, SHA256 `b5084774be98e97a045c6b90a819bdd061b8d4f61b259c3a6e4eb77233ff2646`. Перед установкой все 80 native Sources совпали с принятым checkpoint: [native before](../.artifacts/harvest-art-native-before.json).

[Нативная code-only установка](../.artifacts/playtests/2026-10-16-harvest-art/native-source-install.json) создала 73 ModuleScript и обновила ровно восемь прежних Sources; итог — 150 проектных + 3 Fog = 153 Sources. 68 новых модулей содержат данные, остальные пять — геометрию, визуальный адаптер Сторожа и интеграцию мира/сервисов/клиента. Старые изменения ограничены CornAppearance, тремя corn controllers, MonsterPose, MonsterHunt, MonsterAnimationController и CaptureController.

[Манифест code-only payload](../.artifacts/harvest-install/manifest.json): 3 441 621 байт, SHA256 `0ab19ed60dd76e3440e1b08489092bc19b3bdb5e239de17723cdd0a743d491ec`. Installer допускает целиком принятую baseline либо целиком конечную версию; частичная установка, ручные Source-правки, открытые script tabs, чужие Sources/корни, коллизии классов и неверное поле 630 отвергаются до записи. HTTP wrapper возвращает исходный HttpEnabled перед установкой Sources. Live Rojo и Lune-сериализация сцены не использовались.

Отдельный [native-world-install-A.json](../.artifacts/playtests/2026-10-16-harvest-art/native-world-install-A.json) зафиксировал Farm Ensure: 40 targets/applied 40/built 10/pending 0; Harvest A: один новый owned root, 39 common models, 244 parts. [Снимок мира A перед финальным Save](../.artifacts/playtests/2026-10-16-harvest-art/native-A-world-snapshot.json) сохранён для строгого сравнения. Эти runtime/Edit результаты не заменяют аудит engine-saved байтов ниже.

## Настоящий Studio Play

Обе версии запускались с обычным bootstrap и **одним реальным клиентом**. Игрок и NPC диагностически перемещались; взаимодействия выполнялись через engine ProximityPrompt/InputHoldBegin/End и production server flow. Это не физическое нажатие E, клики обычного пользовательского интерфейса или слепой поиск маршрута.

| Проверка | Сохранённое доказательство | Результат |
|---|---|---|
| A: ключ → ворота → три NPC → выход | [A escape](../.artifacts/playtests/2026-10-16-harvest-art/native-A-escape.json) | escaped, gate_open=true, reward=20, diamonds=20, team finished |
| A: визуальные тела трёх NPC | [A three](../.artifacts/playtests/2026-10-16-harvest-art/native-A-three.json) | 46 samples/1.261 s, каждый animated=true, 19 mesh parts и два включённых света |
| B: первый NPC | [B one](../.artifacts/playtests/2026-10-16-harvest-art/native-B-one.json) | 49 samples/1.262 s, animated=true, 20 mesh parts и два включённых света |
| B: ключ → ворота → три NPC → выход | [B escape](../.artifacts/playtests/2026-10-16-harvest-art/native-B-escape.json) | escaped, gate_open=true, reward=20, diamonds=20, team finished |
| B: визуальные тела трёх NPC | [B three](../.artifacts/playtests/2026-10-16-harvest-art/native-B-three.json) | 49 samples/1.264 s, каждый animated=true, 20 mesh parts и два включённых света |
| B: первая поимка и новый capture visual | [B capture](../.artifacts/playtests/2026-10-16-harvest-art/native-B-capture.json) | 14 samples/8.032 s, Detailed visual, два Neon-глаза/света, caught, одна попытка, reward=0 |

После открытия ворот в этих запусках проверены три серверных NPC с DetectionRadius=96. Для B также выполнены revive и retry. Capture JSON фиксирует состояние поимки и визуальный observer; полного trace всех UI-шагов в нём нет. Награда ранее завершённого побега остаётся в session balance; поимка не создаёт новую награду.

Новая проверка с четырьмя клиентами для art A/B не проводилась. Прежняя [четырёхклиентная multiplayer приёмка 15 октября](2026-10-15_multiplayer-playtest.md) остаётся историческим доказательством прежней версии, а не результатом этих запусков.

## Локальные проверки

Фактически выполнены с PASS `scripts/check.ps1` (StyLua, Selene 0 errors/0 warnings/0 parse errors, code-only Rojo build/sourcemap, безопасные mappings и disabled persistence), `harvest-art-geometry.luau`, `harvest-world.luau`, `harvest-geometry-controller.luau`, `harvest-corn.luau`, `harvest-corn-data.py`, `harvest-installer.py`, `harvest-installer-http.luau` и все пять `harvest-warden-{server,visual,pose,animation,capture}.luau`. Повторены прежние `corn-controller-quality`, `corn-backdrop`, `corn-yellow-startup`, `corn-appearance`, `corn-wind`. Также прошли текущие legacy fixtures анимации, захвата, ловушек, обнаружения, multiplayer hunt/round и аудио. Это локальные adapters; новой нативной аудиоприёмкой они не являются. Общего утверждения «все исторические тесты проекта проходят» нет.

- [Офлайн binary validation](../assets/harvest-warden/validation.json): реальные 26 GLB, 36 FBX, пять PNG, четыре разные формы растений, убывающие LOD, кости/веса и пять отдельных экспортных клипов. Это результат этапа подготовки пакета; его прежняя проверка 45 protected binaries относится к тому этапу до игровой интеграции.
- [Catalog manifest](../assets/harvest-warden/catalog-manifest.json): 68 исходников данных, точная реконструкция каталога и SHA256. Локальный data fixture проверил каналы всех 86 мешей и 22 608 невырожденных треугольников после округления, единичные normals и четыре Neon eye primitives двух Сторожей.
- [Actual installer fixture report](../.artifacts/harvest-install/fixture-report.json): установка в адаптере на immutable baseline, repeat 0/0 через direct и HTTP, CRLF, 33 отрицательных случая и rollback после внедрённой ошибки записи; оригинальные world objects сохранены в адаптере. Отдельный HTTP fixture проверил восстановление исходных true/false после fetch failure и отказ включения без входа в Source installer.
- Строгий save verifier fixture после сверки с реальными engine-файлами: обе A/B положительные, 489 небезопасных DOM/typed/manifest состояний и три raw Terrain изменения отвергнуты. В том числе точная производная A→B допускает только 55 новых Transparency и два root AppliedVariant, три произвольных отклонения отвергаются. Два исправления checker касались только точного представления пустого GetTags как `{}`/`[]` и вычисления фактического float32→8bit floor Color; production Sources и сцены при этом не менялись. [Фактический отчёт](../.artifacts/playtests/2026-10-16-harvest-art/verifier-fixtures.json).

Остальные перечисленные локальные результаты находятся в tool output текущей работы; отдельные JSON-отчёты для них не выдумываются. Ни Lune fixtures, ни экспорт Blender не подтверждают рендер, сетевой transport, человеческий страх или engine Save.

## Сохранённые файлы — строгая приёмка PASS

| Файл | Полученные байты | Статус |
|---|---|---|
| A: `place/Children_of_corn.rbxl` | 1 485 712 байт; SHA256 `2672483f1313180152856e82b971a98f6f2b784639778a7ee6cff9d546050a11` | [Strict preservation PASS](../.artifacts/playtests/2026-10-16-harvest-art/A-preservation.json) |
| B: `place/Children_of_corn_B.rbxl` | 1 485 700 байт; SHA256 `e34fe75f598aa99c121c0e271a1b3b2ed071b5f090a9dfdb6245c116da0565d7` | [Strict preservation PASS](../.artifacts/playtests/2026-10-16-harvest-art/B-preservation.json) |
| Итоговый реестр байтов | [saved-scenes.json](../.artifacts/playtests/2026-10-16-harvest-art/saved-scenes.json) | Независимый повтор SHA256 обоих файлов, исходного baseline и pinned manifests |

Оба файла содержат ровно 153 текущих Sources и 4526 экземпляров: 4162 прежних +73 code +291 art. Идентичности, классы, родители и все свойства исходного мира/Lighting/raw Terrain точны, кроме явно разрешённых map variant, трёх home Transparency и девяти barn Transparency только B. Нет добавленных remotes, посторонних Sources или тестовых узлов. Файлы не реконструировались и не продвигались из recovery: проверены точные авторские engine-байты.

[Независимый review A](../.artifacts/playtests/2026-10-16-harvest-art/A-independent-world-review.json) сравнил 291 art record/244 позы, 4644 native-readable свойства и остальные canonical property groups, включая 242 fixed-box mesh bounds/inertial metadata. [Review B](../.artifacts/playtests/2026-10-16-harvest-art/B-independent-world-review.json) подтвердил, что полный манифест B отличается от рассмотренного A только 55 новыми Transparency и двумя root AppliedVariant; девять исходных barn hides проверены отдельно strict verifier. Native A reader ошибочно заменял точки внутри 20 имён Detailed на `/`; только для этого снимка применено однозначное сопоставление с точными ExpectedName. Disk path/identity guards не ослаблялись; [native B snapshot](../.artifacts/playtests/2026-10-16-harvest-art/native-B-world-snapshot.json) уже использует буквальные Parent/Name.

LF-only [A manifest](../.artifacts/playtests/2026-10-16-harvest-art/A-world-manifest.json), SHA256 `226fe9428f9485030f009ad90cea68e43d560880f88d294acdfddb1f18c9818c`; [B manifest](../.artifacts/playtests/2026-10-16-harvest-art/B-world-manifest.json), SHA256 `690eeb26c312b0e37bad87f220acb8a48cdeae58b6d48f5324c79be75fc5047f`. Оба полных манифеста по 4163685 байт, без CRLF-нормализации при checkout. First-save A/B-review.json намеренно содержит passed=false/complete=false до независимого рассмотрения; окончательными являются A/B-preservation.json.

Для просмотра новой геометрии после открытия файла запускать Play: Sources восстанавливают EditableMesh отдельно на каждом peer. Редакторский overview кукурузы B остаётся исходным. Guarded Edit-восстановление возможно через HarvestWorld.Ensure('A'|'B') после проверки Corn и FarmGeometry; повторная приёмка после фактического закрытия/reopen конечных файлов ещё не выполнена. [Финальный stopped Edit](../.artifacts/playtests/2026-10-16-harvest-art/native-final-Edit.json): B, 153 Sources, 244 art parts, CameraFixed/HttpEnabledfalse, runtime/foreign/diagnostics отсутствуют. Оба временных local HTTP сервера установки остановлены.

## Открытые проверки

Обычный полный раунд без диагностических перемещений; физический E и native UI после смены оформления; человеческая оценка кукурузы, сараев, страха и дальних красных глаз; баланс безопасного пенька; длительный FPS с тремя NPC; новый multiplayer прогон art A/B; reopen acceptance.

В Output текущих запусков были предупреждения загрузки прежних звуковых ID. Новая проверка audibility/человеческого микса не принята; art-приёмка не доказывает исправность аудио и не устанавливает причину этих предупреждений.
