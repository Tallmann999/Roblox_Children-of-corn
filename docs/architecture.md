# Дети кукурузы — архитектура

## Ручная карта B — 2026-10-23, авторский Save принят

Актуальный [контракт ручной B](2026-10-23_B-manual-authoring.md) включён
`CornMap.BManualAuthoringVersion=1`. Источник —70664 реальных MeshParts в
`CornAuthoring`, сгруппированных в576 Models. При Play ManualSceneService
переносит chunks в `ReplicatedStorage.BManualEditorSources.CornAuthoring`,
сохраняя параметры растений, затем выставляет readiness. AuthoringCornController
строит ограниченные Near/Far копии из текущих CFrame/Size/variety/opacity;
пространственные buckets опираются на реальные корни, дубликаты независимы,
удалённые растения не возникают по старым cell IDs. Legacy renderers
отключают свою генерацию только для валидной ручной B. Звук и Wind используют
согласованные реальные растения; режим hard прежний.

15 Site Models связывают прежние tagged slots, факелы и EnergyPoint/TrapPoint;
InventoryWorld читает их реальные CFrame, сохраняя случайный выбор2+2предметов.
Домовые overlays/fences/torches вложены в соответствующий исходный Model;
ручные Harvest и GreenBed ветки восстанавливают геометрию в текущих позах.
Четыре прежних старта и ScarecrowMarker остаются игровыми источниками.

Локальные ManualScene и CornManualSceneEditor восстанавливают отсутствующий
session MeshContent в остановленном Edit без перестройки расстановки. Новый
asset upload не требуется. Native RestoreEdit/Play и новый строгий авторский
Save приняты: B3793205bytes/4c5c0c54…/77554savednodes/171Sources. Полные схемы
новых узлов, точные позы, независимые hull mass/inertia и все retained объекты
проверены; сырой Terrain неизменён. Повторное открытие процесса пока не принято.
Ранее сохранённый c91/168Sources остаётся историческим baseline в frozenZIP.

Rojo теперь142shared/11split/12legacyunmapped; A153owned/165classes,
B168owned/182classes. Source map не владеет Workspace/Lighting/Terrain.

## Текущий B: геометрия с тенями и кукуруза у края — 2026-10-21

В [новом сохранённом уточнении](2026-10-21_corn-edge-shadows-B.md) изменены
ровно пять Sources относительно предыдущего B: CornLayout, оба рендера,
CornAppearance и точный B HarvestWardenVisual. Остальные152 Sources сохранены.
CornAppearance запекает12личных шаблонов в Opaque session Content через
AssetService:CreateDataModelContentAsync; канонический HarvestArtGeometry не
меняется. Это исправляет подтверждённое на GPU отсутствие теней у Object
EditableMesh. После ApplyMesh восстанавливаются исходные атласы/свойства;
успешный кэш общий для Near/Far, ошибки очищают временные объекты и допускают
повтор. Покачивание продолжает вращать части целиком.

Только точные собственные Maze02-тропы B получают padding0 вместо1.5.
Одинаковая TrailEdgePosition в Near/Far проецирует существующие крайние ячейки
на2.05stud от центра тропы; результат повторно проверяется по всем просветам.
Шаг, ячейки, вариации, yaw, высота и бюджеты сохранены. Плотность на площадь
не менялась; освобождённые обочины увеличили Far11180→12433.
В B скрываются две красные Neon-поверхности глаз и не создаются их PointLights;
тёмные глазницы остаются. Source взят из сохранённого B, а не текущей A-версии src.
Strict Save PASS:1499095/94c55e17…,4634instances/157Sources,0adds/deletes.

## Предыдущий checkpoint B: ширина, плотность и флаги теней — 2026-10-21

Тропы Maze02 сужены8→4, продольный endpoint overlap4→2, существующий подход к
воротам согласован. BOX_PADDING1.5 сохранён, поскольку ширина самих листьев
остаётся прежней. `CornLayout.SpacingFor(FieldZone)` возвращает для проверенной
CornMap B шаг `3/sqrt(1.3)`≈2.631174, для A и прочих карт прежний3. Near/chunk/
overview coverage/Far stride используют один и тот же шаг. Высота10,4формы,
3LOD и бюджеты клонирования сохранены. Все новые B near/Far клоны получают
CastShadow=true до публикации. Старый ограниченный CornShadowController для B
отключён, для A прежнее поведение сохранено. Статические BaseParts всей B
получили CastShadow=true; два HarvestCastShadow attributes обновлены вместе с
ними. Main/Wide фонаря продолжают разрешать тени. Невидимые runtime audio anchors
и камерные представления рук/фонаря сохраняют прежнее поведение.
4точных Source-замены,153 остальных Sources не меняются; A-сцена не редактируется.
Полный manifest/guard/save workflow отдельный `maze02-refine`; старые shadow-only
и maze02 installers/verifiers несовместимы с новыми Source hashes.
Native установка/повтор/Play прошли; статус engine Save указан в
[записи уточнения B](2026-10-21_maze02-refine-B.md).

## Лабиринт B, вариант 2 — 2026-10-21

Заказана установка варианта 2 из `maze-layout-02.png` только в B через Studio MCP.
`CornMap/NoCornZones/Maze02Masks` содержит 100 неподвижных прямоугольных дорожек:
каждая Part одновременно видимая земля и XZ-зона исключения растений для прежнего
CornLayout. `CanCollide/CanTouch/CanQuery/CastShadow=false`; игрок свободно идёт
через кукурузу. Folder и Parts имеют `corn_project_id=children_of_corn` и
`CornMazeOwner=corn_maze02_v1`; игровых тегов/ремоутов не добавляется.
Существующие 15 `corn_key_slot`, 4 `corn_spawn` и `corn_exit` сохраняют ID и
родителей; три сарая, связанные декорации и факелы перемещаются вместе с
проверенными Harvest binding attributes. Ворота смещаются по X на верхнем краю.
Ни серверное обнаружение 48/96, ни таймер, ни награды геометрией не меняются.
Editor overview остаётся приближённым: растения над новыми тропами скрываются
без удаления, подробное поле B создаётся обычным Bootstrap в Play.
Установочный manifest и строгая проверка engine Save — отдельный maze02 pipeline;
он не даёт разрешения на остальные world/Source изменения. Статус и фактические
результаты проверок фиксируются в отдельной записи реализации.

## Фонарик и более высокая кукуруза B — 2026-10-20

В B переносятся FlashlightController/FlashlightPresentation/FlashlightTuning,
прежние интеграция RoundController и подсказки ЛКМ, чёрная ночь LightingModes.
Контроллер допускает owned A/B, все игровые запросы/серверные правила прежние.
LightingStyle.Realistic задаётся на самой B-сцене. Банк двух SpotLight (Wide2/100/32,Core13/30/4,Pitch−4)
создаётся отдельно в B; исходные объекты A не перемещаются. Локальные B render
templates всех четырёх форм Near/Mid/Far растут с8до10stud только по Y, сохраняя
каталог, основание, вариацию, LOD/число растений и exclusions. Старые Editor preview
и исходные меши сохраняются; увеличенная подробная кукуруза отображается в Play.
Установка/сохранение — отдельный B-only guarded pipeline против immutable
Children_of_corn_B.before-flashlight-tall-20261020.rbxl.

## Освещение Realistic варианта A — 2026-10-20

[Сохранённый контракт](2026-10-20_flashlight-lookdown.md): LightingStyle.Realistic
закреплён непосредственно в A-сцене для Edit и всех участников Play. Код фонаря,
положение линзы и параметры Wide/Core прежние;156Sources без изменений.
Клиентский временный override не устанавливался. Прежние world/Lighting/Terrain
сохранены; отдельно зафиксированы два новых авторских объекта Part/SpotLight,
существовавшие до Save. Engine-save audit/build/install — flashlight-lookdown.

## Авторский SpotLight и панель настройки A — 2026-10-20

Текущий [контракт](2026-10-20_flashlight-author-tuning.md): сохранённый авторский SpotLight
в банке ReplicatedStorage.CornFlashlightSettings.Wide и более яркий Core.
Личный runtime помещает оба источника непосредственно в Lens/LensAim, на переднюю
плоскость линзы;11Parts/3SpotLight/0Point/0Beam. Studio-only панель справа управляет
двумя brightness/angle/range и общим pitch; Alt-cursor не скрывает свет при настройке,
клики панели проходят без toggle. ЛКМ, плавная походка, server/network/economy прежние.
156Sources: две правки и один новый client Game/FlashlightTuning Module; банк3узла
вне code roots. Только явно указанный авторский unsaved Part удалён после переноса.
Новый workflow build/install/verify-flashlight-author; прежние155Source installers устарели.

## Фонарик A: свет поверхностей и ЛКМ — 2026-10-20

Актуальный [контракт](2026-10-20_flashlight-directional.md) заменяет прежний воздушный туннель:
два SpotLight из LensAim в линзе дают яркий круг и слабую широкую подсветку;
отдельный слабый направленный свет освещает хват.12Parts/3SpotLight/0Beam.
ЛКМ переключает свет, новый раунд включает; F не привязана. RoundText содержит ЛКМ.
Motion, ownership, camera/lifecycle guards прежние. Ровно три Source-правки,
без world/Lighting/fog/B/server/economy/remotes изменений. Установка и строгая проверка
сохранения — по новому directional workflow.

## Направленный туннель фонарика A — 2026-10-20

[Уточнение света](2026-10-20_flashlight-cone.md): только две прежние flashlight Sources,
без новых Modules и изменений мира. Узкий SpotLight + локальные затухающие Beam-плоскости
показывают расширяющийся конус от линзы. Направленный hand fill заменяет PointLight.
Один Raycast ограничивает конец у стены; F и прежние lifecycle/ownership guards управляют
светом и Beam вместе. B, глобальный fog, серверные правила и camera motion сохраняются.

## Ручной фонарик A — 2026-10-20

[Контракт и проверки](2026-10-20_flashlight.md): два новых ModuleScript
FlashlightController/FlashlightPresentation, две Source-правки RoundController/RoundText.
Только личная camera-local presentation для A: CornPersonalFlashlight с точными ownership/project/version,
двумя SpotLight, ближним PointLight2 для хвата и коротким viewmodel в левой руке. F включает/выключает, новый round_id
начинается со светом. Серверный инвентарь, multiplayer/economy/NPC detection и remotes прежние.
Мягкий camera offset выполняется после штатного CameraModule; снимается только собственная
точная последняя добавка. Capture/menu/Alt/map/death/terminal/чужая камера блокируют presentation.
Новые persistent world/Lighting nodes не добавляются; отдельный B-файл сохраняется.

## Вариант A: чёрная ночь и белые лучи — 2026-10-20

Текущий разрешённый scope — [контракт ночи и глаз](2026-10-20_black-night.md).
Classic/A меняет только вложенную peer-local внешность: два белых SpotLight
и Beam с owned Attachments, без изменения Root, физики и gameplay remotes.
В hard-раунде убирается фоновое освещение, луна и звёзды; факелы сохраняются.
Runtime-only Sky CornBlackNightSky использует CornBlackNightSkyOwned=true,
corn_project_id=children_of_corn и точный guard удаления. Существующие Sky
временно перенастраиваются и восстанавливаются без замены экземпляра.
Новые fog/VFX не добавляются; текущие Atmosphere/Fog параметры сохранены.
Отдельный сохранённый B и immutable backups остаются неизменными.

## Два оформления Harvest Warden — 2026-10-16

Текущая визуальная интеграция сохраняет принятые правила multiplayer 1–4:
общий ключ/ворота/deadline, личные две поимки/+20, поздние игроки ждут.
Принятый сетевой baseline 15 октября — 1003371 байт/b5084774…;
его actual server + четыре клиента и clean Source Save подтверждены
[приёмкой](2026-10-15_multiplayer-playtest.md). Нижние датированные разделы
с прежними pending/solo статусами являются историей.

`CornMap.HarvestArtVariant=A|B` выбирает оформление. Новые owned bindings:
`CornMap/HarvestDecor` и узкий `Props/ScarecrowMarker/HarvestWardenHome`;
owner `HarvestGeometryOwner=harvest_warden_v1`, проект `children_of_corn`.
`HarvestAssetKey/HarvestMeshKey` ссылаются только на сохранённый каталог.
Все 244 новые визуальные части имеют выключенные collide/touch/query.
A сохраняет прежние растения/сараи/землю; B добавляет четыре формы кукурузы
с Near/Mid/Far и тёмные покрытия. Точные исключения для исходного мира —
три Transparency домашнего чучела, девять barn Transparency только B
и атрибут варианта. Серверный Root/коллизия/LOS/радиусы 48/96 не меняются.

EditableMesh восстанавливается из сохранённых Source-чанков на каждом peer,
а не из сериализованного Content.Object. Серверный HarvestArtService имеет
Order17 после Farm15; клиентский HarvestGeometryController — Order45 после
Farm40. Клиентские части движущегося чучела вложены под прежний Root,
две красные лампы Range24/Brightness3 принадлежат его глазам. Полный
[контракт владения](2026-10-16_harvest-art.md) и
[приёмка/сохранения](2026-10-16_harvest-art-acceptance.md) описывают текущий
статус: оба отдельных engine Save A/B приняты строгим аудитом, 4526 экземпляров,
153 точных Sources, исходный мир/Lighting/идентичности/родители/raw Terrain
сохранены за исключением явно перечисленных art-изменений.

Source workflow: check.ps1 → build-harvest-installer.py → guarded
install-harvest.luau только в проверенном Corn stopped Edit. Старые
multiplayer/solo installers не накладываются на новые 153 Sources.
Мир меняет только guarded HarvestWorld.Ensure('A'|'B'); engine-файлы
проверяет verify-harvest-copy.py относительно неизменяемого
before-harvest-art-20261016.rbxl и независимо рассмотренного pinned manifest.
Публичная публикация, persistence, покупки и lobby остаются вне задачи.

## Сохранённый baseline: появление подкрепления — 2026-10-15

После восстановления принятого solo checkpoint автор подтвердил крики при
появлении Monster2/3 и радиусы обнаружения48/96studs. Server-only уведомление
`RoundAudio:ReinforcementsSpawned` вызывается после успешного создания обеих
сущностей; Sound отдельные от rustle, по одному старту на индекс за раунд.
Новых remotes или persistent world bindings нет.
[Контракт и точный scope](2026-10-15_entity-arrival.md).
Этот чистый solo baseline сохранён автором Ctrl+S14:52:11:997184байт,
SHA256 `b5ef0471325bbe5c9ab7178575753453cbf59afb15ed905eb12dfc70a4bbf6c8`,
78Sources=75проектных+3Fog/4160instances. Strict engine audit допускает только
3Source-дельты Balance/SoloRound/RoundAudio к прежнему493bc1f9… и подтверждает
точный мир/Lighting/art/identities/parents/rawTerrain. После чужого Cooking/Rhythm
sync чистые engine-байты были восстановлены без сериализации;
[история восстановления](2026-10-15_foreign-cleanup.md).

## Текущий этап в разработке: общий multiplayer round — 2026-10-15

Автор подтвердил1–4игрока на ПК в Studio DEV, общий ключ, личные две поимки
и+20алмазов каждому сбежавшему. Лобби, matchmaking, persistence, покупки
и публичная публикация в текущий этап не входят. Реализация возобновлена из
проверенного WIP-архива поверх принятого baseline997184/b5ef0471…; прежний
архив не устанавливается целиком поверх текущих Sources. Контракт первой
реализации и расширение `round_snapshot.team` описаны в
[спецификации](2026-10-15_multiplayer.md). Один TeamRound владеет общим миром,
ключом, воротами, финальным deadline, предметами, охотой и аудио; личный
RoundParticipant хранит персонажа/инвентарь/попытки/награду/лимиты/мини-карту.
Четыре gameplay remotes и persistent world bindings остаются прежними.
Ни выход, ни поимка одного не сбрасывают команду. Проверка живого отправителя,
фазы, дистанции, LOS и server transaction обязательна для каждого pickup/use.
Все допущенные подключённые игроки подтверждают готовность; следующий общий
раунд начинается после завершения/ухода всех текущих участников. Поздние
подключения ждут следующего раунда. Время команды и общий аудиопланировщик
продолжаются при личной поимке: меняются только controls/eligibility пойманного
игрока и состояние захватившего NPC; чужие фон/шелест/охота не останавливаются.
Радиусы48до ворот/96у всех3после, два Root-bound arrival крика Monster_01/02
и независимые rustle cursors сохраняются. TeamRound сообщает об arrival только
после успешного создания обеих дополнительных сущностей и commit общего
deadline; ошибка аудио не отменяет ворота, повторный prompt не повторяет крики.
Один NPC делает один Step за тик и публикует выбранный сервером UserId; отрицательные
целые Studio IDs поддерживаются только как идентичности зарегистрированных Players.
Новая native multiplayer приёмка и точное сохранение ещё предстоят: локальные
fixtures и этот контракт не заменяют настоящий server с несколькими клиентами.
До такой приёмки сохранённым checkpoint остаётся solo997184/b5ef0471… выше.

## Текущий сохранённый контракт — 2026-10-15

Сохранённый local solo PC checkpoint: поле630×630, только hard/ночь20:30 без выбора сложности, побег+20сессионных алмазов. Мир сохраняет15связанных с факелами слотов/27факелов,2энергетика/2капкана/ключ; сухой атлас103653296385119 задаётся до первого появления, trap pickup использует X−3.6 от slot. Сервер владеет движением/предметами/поимками/воротами и120-секундным финалом с3NPC; deadline идёт во время окна возрождения. В сохранённом checkpoint multiplayer отсутствует; текущий этап1–4игрока описан выше. Persistence/покупки/lobby/publishing не добавляются.

Окончательный шелест138698164682825 включается автоматически при проверенном движении в кукурузе: один personal2D loop владельца и до10отдельных Root-attached spatial loops (7других Players+3NPC), максимум11. Каждый использует первый Play и последующие Pause/Resume/Looped с независимым cursor; owner walk1/sprint1.5, spatial range5..65 и validated speed1..2. Server CornAudio_corn_rustle — silent metadata Sound/Volume0, on-change AudioCornActive/AudioCornSpeed на прежнем10Hz poll, никогда не Play. A/Bкнопки/API удалены, обычный Alt сохранён; старые6коротких corn assets архивны и исключены из10активных preloadIDs. Подробный текущий контракт — в последнем разделе этого документа и [итоговой приёмке](2026-10-15_continuous-rustle.md).

Текущий saved checkpoint — Ctrl+S14:52:11/997184байт/b5ef0471… из верхнего раздела. Для возобновлённого multiplayer immutable baseline — `place/Children_of_corn.before-multiplayer-resume-20261015.rbxl` с этими точными байтами и полным SHA256. Прежний `before-multiplayer-20261015.rbxl`/995988/493bc1f9… сохраняется как исторический backup и не является baseline новой установки. Рабочий code-only workflow: check.ps1 → build-multiplayer-installer.py --compact → guarded install-multiplayer.luau только в проверенной Children_of_corn stopped Edit; exact engine save проверяет verify-multiplayer-copy.py относительно актуального resume baseline. Допускаются только объявленные Source-дельты и2ModuleScript TeamRound/RoundParticipant в прежнем GameServer/Game; ожидается80Sources=77src+3Fog/4162instances, без других instance/world/Lighting/art/identity/parent/rawTerrain дельт. Отдельные engine candidates — guarded promote-tested-multiplayer-copy.py с обоими хэшами. Никакой Lune scene serialization/live Rojo/исторических world installers. FarmGeometry Edit restore после reopen остаётся отдельным guarded шагом.

Исторический continuous-rustle checkpoint12:48:01 —995988байт/SHA256 `493bc1f9b512d618d0a815b2197e3af854f775cd711b363db2906d8fbaf1fb68`:78Sources/4160instances, четыреSource-дельты от поля489af64f… и точный MovementController. Его readability installer/rustle-only verifier относятся к той приёмке и не заменяют текущий entity-arrival/resume pipeline.

Actual native owner/3NPC/trap/cleanup прошли с диагностической постановкой; blind full round/страх/человеческий микс/длительный3NPC FPS/safe-perch/reopen и multiplayer не приняты. Fire105538100476464 остаётся внешним not-approved asset. Датированные разделы ниже сохраняют историю; при конфликте размеров/режимов/коротких cues/A-B UI/старых pending применяется этот итог и последние разделы15октября.

## Первая погоня, сцена и выбор после поимки —2026-10-14

Актуальная версия содержит75Sources без новых Modules или remotes. Первая погоня за раунд длится максимум10сек и с первого обнаружения использует серверный WalkSpeed цели; первые2сек захват запрещён. По окончании монстр возвращается в patrol с1сек grace до нового обнаружения. Поздние погони сохраняют скорость13, прежние LOS/дистанции/потерю цели. Только сервер расходует first-chase marker.

Обе подтверждённые поимки сохраняют1сек локального представления. После первой сервер удерживает phase=caught/capture.remaining0: controls/prompts/hunt выключены, elapsed_sec заморожен. `request_round_action("revive")` проверяет владельца, фазу, окончание capture, первую попытку, живого исходного персонажа и world/hunt validity; возрождение возвращает к прежнему старту с защитой и возобновляет таймер без времени ожидания. Menu из завершённой первой поимки очищает раунд по серверному пути. После второй поимки caught_out показывает тот же выбор; «Возродиться» открывает objective перед прежним validated retry, а «Выход» возвращает меню. Snapshot fields и Endpoint names прежние; revive — дополнительный action существующего remote. Runtime client mouth/head/camera/paint effects описаны в [контракте](2026-10-14_capture-visuals.md); Root и authoritative capture.frame не меняются.

Вывеска ExitSign имеет ровно три разрешённых постоянных изменения: Size36×9.6×0.9, подъём центра на3.2studs при прежнем размещении по X/Z и SurfaceGui.PixelsPerStud16. AlwaysOnTop сохраняется исходнымfalse. Эти свойства установлены в проверенной Edit; остальные world/Lighting/art/rawTerrain сохраняются. Owned client presentation мигает до10Hz через LTM и локальный projected ScreenGui с guarded restore, без новых persistentworld instances. Реальные samples подтверждают период1.6сек; после foreground nativeGPU world видим, нормальный Surfaceтекст видим и увеличен. ProductionGPU projectedfarlabel570studday/dusk/night иnear39.7studPASS; final1015691байт/hash9082169a7da5fed15cd962611777285213fce99f23de82f83e0f361a683ecf16 strictsaved. Наличие TextLabel/проекции/мигания не заменяет проверку пикселей.

## Шелест целиком —2026-10-14

Сервер на10Hz сам подтверждает живого движущегося corn actor, grounded/field/exclusions, отсутствие teleport и разрешённое состояние NPC. Для каждого нового клипа он публикует единый атомарный Attribute `AudioRustleStart="id:key"` на прежнем owned server Sound: id строго возрастает, key принадлежит шести corn clips. Серверная eligibility и выбор клипа не принимаются от клиента. Нет нового remote, Source или постоянного world binding.

Клиент поддерживает максимум8player actors+1NPC и один owned local shadow Sound на существующем Root каждого actor. Он приглушает только точно распознанный owned server corn Sound, запоминает его прежнюю громкость и guarded restore; прочие server sounds/арт сохраняются. Atomic cue не разрывается между отдельными id/key updates. Для каждого actor хранится только один latest pending cue, без растущей очереди. Текущий локальный клип доигрывается полностью при остановке/air/выходе из поля/капкане/caught; следующий подтверждённый cue запускается после его естественного Ended, без overlap и таймерного Stop.8сек fallback освобождает только клип, который ни разу не начал decode/playback; уже звучащий длинный клип не обрывается. Root replacement/death и terminal/retry/Destroy очищают shadow, pending и listeners, восстанавливают принадлежащие контроллеру volume values. Кукуруза и gameplay этим слоем не изменяются.

Фактические проверки текущего этапа: server fixture8 natural ends, client fixture4 natural ends и production playback6 natural ends без Stop — PASS. Decoder14/15; Fire остаётся внешним asset access failure, grants/reimport/publishing не изменялись. Это проверка доступных звуков и lifecycle, а не human mix/fear/full-round/FPS acceptance. Предыдущая реализация с завершением по server IsLoaded/IsPlaying и частыми restart остаётся исторической; актуальный client Ended contract описан в [аудиоспецификации](2026-10-13_audio.md).

## Реакция на монстра и обзор —2026-10-13

[Контракт](2026-10-13_hunt-readability.md): сервер detect16, awakening20сек, chase grace2сек до ускорения/захвата. Состояния и remotes прежние; клиентский objective modal подтверждает прежний start/retry, awakening5→1 использует elapsed_sec. Рост visual NPC×1.3/pose/capture при прежнем Root; runtime пеньки/ступени/энергетики выше. Новый одноразовый owned spatial awakening scream у исходной точки, обычные голоса не перекрывают его. Все additions runtime/code-only; сохранённый мир/Lighting/art/Terrain точные.

Runtime InventoryItems/LookoutStumps содержит два отдельно от pickup owned Model с tag corn_lookout_stump и corn_inventory_owned/corn_project_id/LookoutVersion=1. Подбор банка удаляет только прежний pickup; lookout остаётся до terminal/retry cleanup того же inventory folder. Дополнительных скрытых loot/minimap markers нет.

## Звук —2026-10-13

По уточнению автора штатный footsteps Sound Running/Climbing локально приглушается по точной идентичности/asset URI; character lifecycle подписки и guarded restore, без удаления чужих объектов или нового remote. Corn rustle учащается только при серверно подтверждённом движении, cadence ограничен независимо от длины длинного клипа.

[Звуковая фича](2026-10-13_audio.md): runtime server spatial Sounds для движения в кукурузе, chase голосов, пяти15/15 cricket emitters и распознанных факелов; client personal фон2/Enemy Hunt и подтверждённые use sounds. Новый runtime tag corn_audio_emitter, attributes CornAudioOwned/corn_project_id/audio_role; создаются только owned эмиттеры/звуки текущего раунда, cleanup сохраняет оригинальные объекты. Monster.ChaseTargetUserId задаётся сервером:0 вне chase, ID цели при chase. Прежние round_snapshot/inventory.use contracts, новых remotes или непроверенных клиентских координат нет. Только solo local Studio; публичное прохождение/мультиплеер не реализуются этой фичей. Регуляторы категорий вынесены в AudioRules/SoundGroups для будущего меню.

## Предметы в руках —2026-10-12

Автор выбрал [локальныепредметы/жесты](2026-10-12_handheld-items.md). Сервер расширяет inventory.use={id>=0,kind:none|energy|trap}, увеличиваетidтолькопослеуспешнойtransaction; remotes прежние. Клиентпоказываетвыбранныйпредмет иоднократныйподтверждённыйжест поround_id/use.id, не проигрываетисториюприизначальномsync. Одинownedлокальныйviewmodel ≤24Parts, одинPivotTo/кадр, безWorld/Root/gameplaywrites. Захват/меню/карта/смерть/чужаякамера очищаютпредставление. На банке SurfaceGui этикетка без AlwaysOnTop и влияния мирового света; новых источников света нет.71Sources установлены, проверены и сохранены; постояннаясцена/артнеизменны; звукипозже.

## Анимация и сцена поимки —2026-10-12

Автор разрешил [представление чучела](2026-10-12_scarecrow-presentation.md), звуки отложены. Существующий owned runtime Monster получает отдельные named limbs; клиентские pose/controller работают только с его9визуальными частями до30Hz, Root/серверная физика не меняются. Обе поимки phase=caught1sec, hunt=capturing; следующий переход первая→active/вторая→caught_out серверный и epoch guarded. Обязательный capture={id0..2,remaining0..1,frame:CFrame} в round_snapshot сообщается лишь после подтверждённой поимки. Новый remote/worldtag отсутствует. CaptureController управляет только собственной временной камерой/локальной копией, восстанавливает состояние; Movement/RoundHud согласуют владение. Ни одну часть поля не анимирует эта фича. Постоянный мир и исходный арт сохраняются точно.

## Инвентарь и реактивная кукуруза — 2026-10-12

Текущий разрешённый scope расширен [контрактом инвентаря](2026-10-12_inventory.md): пять серверных слотов, request_inventory_action(select/use, slot1..5), обязательный inventory в round_snapshot, два энергетика ×2/30sec, два player-safe капкана с остановкой NPC10sec и ключ. Runtime binding использует corn_item_pickup / corn_placed_trap, corn_inventory_owned / corn_project_id / item_id / item_kind. Непроверенные клиентские координаты и тип предмета не принимаются. E уступает доступным мировым prompt. Retry очищает предметы/эффекты; первый catch сохраняет расходники, роняет ключ и завершает ускорение. monster_state допускает trapped. Авторская постоянная геометрия сохраняется кроме явно разрешённых факелов; модель ключа и пеньки создаются только в runtime.

Общий ветер отменён по сообщению автора о сильных лагах. CornWindController двигает максимум два ближайших стебля при контакте игрока и два возле движущегося NPC; full-field неподвижен. Подробности и пределы в актуальном corn-wind.md.

## Дорога, фермерские FBX, выход и кадры выбора — 2026-10-12

Автор разрешил дорогу через всю карту от выхода, косо стоящий ржавый грузовик, замену трёх временных House на предоставленный Barn03, шины/мусор, восемь рядовых факелов у выхода, два настенных факела под45° и неоновую надпись ВЫХОД. Новое размещение ограничено CornMap; импортные оригиналы хранятся отдельно, прежние временные модели сохраняются в собственном архиве. Ground/Baseplate/Terrain, key slots, CornerSpawns и EscapeGate Door/Anchor/ExitZone/границы не меняются. Solo PC DEV, звуки отложены.

[Дорога/выход](2026-10-12_road-exit.md): VillageRoad14studs по оси от локального-Z края FieldZone к EscapeGate; собственный невидимый RoadClearance использует существующий tag `corn_no_corn_zone` и `corn_project_id`, поэтому runtime посадка исключает полосу без нового gameplay remote. Сохранённые strictly owned overview/preview растения в полосе скрываются Transparency в месте, с exact snapshot и rollback. Чужие растения сохраняются. Новый декор имеет собственные owner/version attributes; installer отказывается от unknown/manual edits. Дополнительные10 torch models используют прежний `corn_torch`/torch_id и owner attrs, размещаются в существующем TorchMarkers, дистанционные/режимные правила прежние. Повтор проверяет полный состав и не дублирует объекты.

[Подсказка выхода](2026-10-12_exit-hint.md): GateHintController получает только уже валидированный RoundController snapshot. В active без ключа/открытых ворот и при живом персонаже около публичного InteractionAnchor показывает STOP/Нужно найти ключ; ready/result/ключ/уход скрывают. Подсказка не блокирует мышь/ходьбу, не открывает ворота и не создаёт remote. Серверная _canInteract/_openGate сохраняется.

[Фермерские ассеты](2026-10-12_farm-assets.md), [локальный EditableMesh](2026-10-12_editable-farm.md): исходные FBX копируются побайтово; geometry/UV/normals и transforms сохраняются в проверенных neutral данных. Автор выбрал EditableMesh без мыши. CreateAssetAsync в текущем Studio отвечает unavailable, поэтому постоянные cloud mesh URI не создаются. Edit installer собирает четыре шаблона в собственном ServerStorage/CornFarmAssets и human-scale копии в Props. Прежние три временных House сохраняются целиком в CornFarmSceneArchive; новые House имеют прежние имена minimap binding. FarmGeometryService Order15 восстанавливает серверную geometry/collision до Round30. FarmGeometryController Order40 строит клиентскую geometry из тех же shared builder и четырёх наборов данных из23 Sources: серверные EditableMesh объекты не реплицируются. Никакого нового remote/hidden state. Заданные автором CFrame/Size/appearance/physics восстанавливаются точно после ApplyMesh; повтор бережёт placements. Открытые двери копий скрыты и не имеют коллизии, оригинальные шаблоны сохраняют все семь mesh частей сарая. Solo PC Studio DEV; cloud publishing и изменение соседней сцены исключены.

Карточки сложности используют отдельные ImageLabel с кадрами текущего реального renderer: easy/day зелёная кукуруза и светлое небо, medium/dusk сухая кукуруза, hard/night сухая кукуруза и туман. Кадры снимаются в controlled DEV test с сохранением/возвратом камеры и GUI; это не новые правила раунда. PNG/asset URI сохраняются в проекте, UI не клонирует CornMap и не создаёт новую искусственную мини-сцену. Сохранение только точными байтами движка с проверкой узко разрешённой разницы и raw Terrain.

## Маркеры, сухая кукуруза, ветер и открытые сараи — 2026-10-12

Автор разрешил голубую вытянутую стрелку и синий квадрат ворот на обеих картах ([маркеры](2026-10-12_minimap-markers.md)), жёлтую сухую кукурузу в medium/hard, лёгкий ветер только в hard ([ветер](2026-10-12_corn-wind.md)) и открытый пустой вход в существующие временные сараи ([сараи](2026-10-12_open-barns.md)). Solo PC DEV и отложенные звуки сохраняются. Новых remote contracts и gameplay tags нет. Публичный существующий CornMap/EscapeGate/InteractionAnchor задаёт положение ворот; скрытый ключ и NPC не раскрываются.

CornAppearanceController (Order 54) получает режим только через проверенный RoundController snapshot. Он меняет TextureID только у распознанных декоративных MeshPart копий текущего corn mesh: подготовленный ReplicatedStorage/CornRuntimeArt/CornPlantTemplate, owned saved overview и owned runtime near/backdrop. Shared CornAppearance хранит URI отдельного сухого атласа, не заменяет зелёный файл/импорт/UV/геометрию. easy/ready восстанавливают точные исходные URI; medium/hard используют жёлтый атлас. Регистрация и бюджетная очередь обновлений событийные, без полного обхода поля каждый кадр; чужие объекты и ручные неизвестные texture edits сохраняются. Изменения текстуры только на клиенте в Play, источник ServerStorage и сохранённое поле остаются зелёными. EditorPreview не имеет индивидуальных owned flags и сохраняется; рабочий near renderer скрывает его и заменяет распознанными runtime копиями.

CornWindController (Order 55) получает тот же подтверждённый режим, создаёт только декоративное локальное покачивание вокруг основания. Ограниченный пространственный индекс и число обновляемых близких растений сохраняют бюджет; full-field 19715 копий не двигаются одновременно. В easy/medium/ready и при cleanup возвращаются точные исходные CFrame. Ни коллизии, ни raycasts охоты, ни серверная геометрия не изменяются.

Изменения сараев разрешены узко: только три существующих CornMap/Props/HouseWest, HouseEast, HouseNorthWest. Guarded installer сохраняет Body/DecorativeDoor как исходные части, скрывает и выключает их коллизии, добавляет распознанную полую оболочку с открытым входом в прежних габаритах. Крыши, позиции, размеры исходников и другие Props сохраняются. Точная текущая авторская .rbxl копируется до установки; сохранение только байтами движка со строгой проверкой этой разрешённой разницы и raw Terrain.

## Runtime кукурузы — оптимизация обзора/FPS 2026-10-10

Текущий код содержит 28 Sources. CornBackdropController (Order 45) создаёт только в Play CornMap/CornClientBackdrop с шагом 6 studs и нормальной высотой 8 с прежней вариацией. На текущих авторских зонах живой слой содержит 19715 копий; предел 20000, бюджет 18 созданий/Heartbeat и 2 ms за batch. Копии наследуют RenderFidelity шаблона (Automatic у текущего ассета), CastShadow=false. Сохранённые CornMap/EditorFieldOverview, импортированный арт и X/Z размеры не меняются. CornLayout исключает owned backdrop subtree из ReadExclusions: дальние копии не становятся world bindings и не добавляют полный обход 20 тысяч частей к регулярному обновлению.

CornClientBackdrop публикуется Ready=true только после полного завершения. CornController выбирает его при совпадении FolderName+Parent+CornClientBackdropOwned=true+CornEditorOverview=true+corn_project_id=children_of_corn+Ready; иначе использует сохранённый EditorFieldOverview. Перед публикацией и освобождением backdrop вызывает UseBackdropReady: прежняя локальная coverage-маска восстанавливается до snapshot/hide/restore авторского overview. Полный контейнер проверяется при bind; folder topology/ownership/Ready и FieldZone инвалидируют кэш и восстанавливают прежние LocalTransparencyModifier. Сохранённый overview имеет четыре geometry/ownership signals на каждый part. Runtime копии неизменяемы после генерации; ручные правки этих копий в Play не поддерживаются и не сохраняются. Per-part signals для 19715 частей не создаются; ownership каждого dirty entry проверяется перед новой visibility-маской. Connections отключаются при restore/Destroy. При Ready backdrop DetailStride=6 renderer создаёт только LOD1/2: sparse LOD3=9 удаляется и не скрывает более плотный дальний фон. Без backdrop сохраняется fallback 3/6/9.

Обычный профиль: radius 150 / dense 60 / medium 130. При высоте root или CurrentCamera больше 6 studs над землёй: radius 200 / medium 144 с удержанием 2 s, dense 60 сохраняется. LOD переключается с hysteresis ±12 studs; существующие внешние группы удерживаются ещё на 18 studs, новые за основным radius не создаются. Лимиты 100 групп/4032 растений и бюджет 18 созданий/3 ms за batch сохраняются. Runtime LocalScript не присваивает RenderFidelity: живой тест выявил setter capability PluginOrOpenCloud, поэтому копии наследуют свойство источника. Авторские части и источник не меняются.

[Отчёт качества](2026-10-10_quality-playtest.md) фиксирует 15/15 просветов к 479.865 s при обычной ходьбе и замер готового слоя: 603.509 s / 36120 клиентских кадров, средний FPS 59.850, p95 19.005 ms на GTX1060/i5-4460 в активной Studio с Automatic. Обход не завершился подбором ключа/побегом; диагностические паузы исключают вывод о длительности активного поиска. Это измерение конкретного ПК, а не полная приёмка производительности или гарантия 60 FPS. Итоговый engine fixture после последней правки путей и сохранение версии 28 ещё ожидаются. Страх нового игрока, медиана поиска 7–10 минут и финальная игровая приёмка остаются открытыми. FPS измеряется по клиентским кадрам; серверный Heartbeat не считается FPS.

## Мини-карта — контракт реализации 2026-10-10

Автор разрешил реализацию minimap; звуки отложены до его подборки. Только код и runtime UI, без изменений авторского Workspace/Lighting/Terrain и без новых world Parts/Tags. Shared `MinimapGeometry` хранит CompactSize=180, UpdateHz=10, VisitPadding=3, VisitHeight=12, ClearingRadius=6 и проекцию относительно актуального CFrame/Size FieldZone. Локальные -Z — верх карты; стрелка по LookVector HumanoidRootPart. Координаты вне поля ограничиваются краем.

Серверный `MinimapState` вычисляет посещения только живого владельца active: 15 `corn_key_slot`/slot_id — горизонтальные круги радиусом 6+3 studs вокруг текущего слота; три существующих Props/HouseWest, HouseEast, HouseNorthWest — горизонтальные bounding boxes +3 studs. Допуск высоты +/-12 относительно FieldZone.Position.Y для просветов и центра bounding box дома. По одной записи на ориентир; оба факела дома дают одну запись. Новые зоны/перестройка Props не нужны. Позиции ориентиров читаются в каждом poll, поэтому ручное перемещение/поворот до Play сохраняется.

`round_snapshot` расширяется обязательным `minimap={round_id:number, visited:{ {id:string,kind:"clearing"|"house",position:Vector3} }, deaths:{ {id:number,kind:"caught"|"death",position:Vector3} }}`. round_id — отдельный возрастающий номер старта, не epoch переходов. Только посещённые ориентиры и уже произошедшие смерти отправляются владельцу; ни скрытый ключ, ни монстр, ни непосещённые места в payload не входят. Максимум 18 visited и 3 deaths (две поимки и обычная смерть/Reset); client->server remote для отметок отсутствует. Сервер фиксирует поимку до телепорта, обычную смерть/CharacterRemoving — по доступному root; одно событие смерти дедуплицируется для текущего персонажа. Abort кнопкой не создаёт череп.

start/retry очищают записи и увеличивают round_id. Первая поимка сохраняет записи и добавляет череп; вторая сохраняет второй. Результат оставляет карту завершённого раунда, ready/preparing скрывают. Menu скрывает историю; следующий start очищает её. Stop очищает runtime. `RoundController` валидирует структуру/границы/конечность/уникальные IDs и передаёт snapshot MinimapController.

`MinimapController`/`MinimapHud` — собственный ScreenGui: карта 180 справа сверху под LeaveRound, север относительно FieldZone, простая схема поля без скрытых объектов, стрелка/крестики/красные черепа. Открыть: Alt освобождает мышь, клик по мини-карте; также M. Большая карта адаптируется по viewport, кнопка закрытия/M возвращает compact. Esc закрывает карту и не блокирует системное меню Roblox. Физическое закрытие по Esc и работа M подтверждены автором 2026-10-10; автоматическая проверка Escape-handler и GuiService.MenuOpened отделена от этого ручного подтверждения, поскольку Studio VirtualInput не разрешает CoreGUI-клавишу. Большая карта автоматически закрывается при смене phase/round_id. Мир не ставится на паузу. MovementController:SetMapOpen(bool) освобождает курсор и снимает спринт независимо от Alt; закрытие возвращает прежний Alt-state. Обычные snapshots не закрывают карту и не сбрасывают взгляд. Обновление положения 10 Hz, количество UI-маркеров ограничено; CornMap в ViewportFrame не клонируется.

## Выбор освещения — контракт 2026-10-10

Перед каждым новым раундом доступны easy (день), medium (сумерки/факелы), hard (ночь/небольшой туман). Меняются только видимость и освещение; правила охоты, скорости, спринта, ключа и +10 общие. Rojo остановлен. Исторический `scripts/install-modes.luau` устанавливал версию с 23 Sources; на текущую версию его не повторять. Карта/арт/редакторский Lighting не меняются.

`request_round_action(action, lighting_mode?)`: start/retry требуют строку easy/medium/hard. Владелец, фаза и прежний token bucket 2/2 проверяются до применения. Неизвестное, отсутствующее или нестроковое значение отвергается без старта и изменения Lighting. sync/abort/menu принимаются без режима. Смены режима в active/caught/preparing нет. `round_snapshot` содержит обязательное `lighting_mode` — серверный режим текущего/последнего раунда, medium до первого старта. Клиент не передаёт свойства Lighting или настройки монстра.

Shared `LightingModes` хранит профили и whitelist. Сервер при старте сохраняет изменяемые свойства Lighting и всех существующих Atmosphere, затем применяет профиль. Результат/первая поимка сохраняют освещение; menu/уход владельца восстанавливают точные исходные значения. Sky/Atmosphere/Bloom/DOF не удаляются и не создаются. Изменения только в Play; Stop возвращает Edit. CornController получает подтверждённый snapshot: easy выключает огонь/свет/светящуюся верхушку собственных факелов; medium/hard используют прежние дистанционные бюджеты. Шесты сохраняются. В ready используется исходное поведение факелов.

RoundCard 780 × 510 масштабируется по viewport. Три карточки содержат небольшие самостоятельные 3D-превью поля и кнопки выбора; превью не клонируют CornMap и не требуют публикации изображений. Выбор локален до start/retry, рамка и текст отмечают карточку. Повтор позволяет сменить режим; первый выбор medium — предложение по умолчанию для прототипа. Active HUD сообщает подтверждённый режим.

Мини-карта реализована по контракту выше и [спецификации](2026-10-10_minimap_gd-spec.md); статус planned в историческом отчёте относится к этапу выбора освещения.


Текущий код — 28 Sources. Мини-карта установлена, проверена и сохранена в предыдущей версии с 27 Sources ([приёмка](2026-10-10_minimap-playtest.md)); физические Esc/M подтверждены автором. Новый runtime CornBackdrop и настройка охоты проходят текущую [проверку качества](2026-10-10_quality-playtest.md). Установка: scripts/check.ps1 → scripts/build-quality-installer.py → guarded scripts/install-quality.luau только в проверенной Children_of_corn Edit. Unknown Sources/открытые script tabs вызывают отказ; сохранения движка проверяются scripts/verify-quality-copy.py, без Lune-пересериализации. Прежние installers исторические. Карта 840, 21 факел, map_version=3, MapTuningVersion=1, TorchClearanceVersion=1; сохранённые Preview 1187 / overview 4977 и runtime backdrop 19715. Столб просвета расположен на +4 Z от слота. Исторические 22/23/27-source отчёты сохраняют собственные результаты; они не задают число текущих Sources. Rojo остаётся остановлен; звуки отложены до ассетов автора.

## Карта 840 и охота — контракт 2026-10-10

Новая авторизация: уменьшить каждую сторону поля на 30% до 840; перенести точки и модели относительно центра, сохранив размеры домов/ворот/бочек и высоту земли. Только CornMap и ночное освещение этой сцены. Защищённый MapTuning сохраняет исходные свойства и отделяет старые owned-слои до успешного завершения; отказ/ошибка возвращает их и Sources. Исходный imported asset и остальные объекты Workspace не меняются.

`TorchMarkers` — owned Folder; модели с tag `corn_torch`, `torch_id`, `corn_project_id`, `CornTorchOwned=true`. По одной у каждого из 15 key slots, две у каждого из трёх домов. Шест 13 studs; Fire и PointLight без теней. Факел обозначает возможное место поиска, а не наличие ключа. Клиент включает эффекты только вблизи: свет 90, огонь 220 studs; верхушка плавно скрывается на 240–320. Существующая Atmosphere сохраняется, поэтому один FogEnd не гарантирует точную дальность тумана. Ночь — редактируемый профиль ClockTime=20.5, FogEnd=320.

Кукуруза: базовый шаг 3, детерминированные смещения ±0.3 studs, yaw ±10–30°, изменение высоты ±10–15%. Дальняя сохранённая сетка 12 studs остаётся авторской. Текущий CornBackdrop заполняет всё поле в Play с шагом 6 и лимитом 20000, затем скрывает сохранённый слой локально. Под готовым фоном ближний renderer использует только шаги 3/6; при fallback сохранённого overview — 3/6/9. Профили, кэш/hysteresis и бюджет 100 групп/4032 ближних растений описаны выше. Stop восстанавливает Edit без добавления растений в сохранённый мир.

`ScarecrowMarker` получает tag `corn_monster_home`, `monster_home_id=solo_home`; это авторское место пробуждения. Сервер создаёт только `CornRoundRuntime/Monster`, двигает его по PathfindingService с патрульной скоростью 10 и скоростью погони 13 studs/с, проверяет шаг Blockcast. Ни клиент, ни декоративная кукуруза не сообщают поимку. До 15 с движение и захват запрещены. Обнаружение требует дистанции до 32 и прямой видимости (LOS). Погоня идёт к последней видимой позиции: скрытое движение игрока не обновляет цель. Потеря LOS или дистанция больше 42 запускает таймер 1.25 с, затем монстр возвращается к патрулю. Патруль сначала выбирает ближайший к монстру просвет, далее циклически обходит отсортированные slot_id с шагом 7; положение скрытого игрока не используется. Если патруль заблокирован больше 2 с, выбирается следующая точка. Переход состояния отменяет старые пути; обычный visible poll погони не сбрасывает путь каждый раз. Захват требует горизонтальной дистанции до 3, разницы высоты до 7 и LOS. Первый захват: phase `caught` на 1 с, ключ падает на доступную землю в пределах 6, тот же старт, полный запас, защита 5 с, монстр возвращается домой. Второй: terminal `caught_out`, награда 0. Захват проверяется раньше выхода. GateOpen сохраняется после первой поимки.

`round_snapshot` дополнительно: `catches_remaining` (0–2), `monster_state` (dormant/patrol/chase/stopped), `protection_sec` (>=0). Новых клиентских gameplay remotes нет. Epoch отменяет старые переходы/пути; retry/menu/Stop очищают охоту. HUD сообщает пробуждение, первую поимку, последнюю попытку и поражение. Первое лицо сохраняется в caught; abort отменяет возврат и восстанавливает камеру. Рычание/полная звуковая атмосфера остаются отдельной фичей.

## Передвижение — контракт 2026-10-10

Первое лицо и выносливость реализованы и прошли [живую проверку](2026-10-10_studio-playtest.md). `request_sprint_intent(boolean)` — RemoteEvent клиент → сервер. Только владелец одиночного раунда может передать булевое намерение; true принимается только с текущим живым персонажем в active. Изменения true ограничены token bucket 12, восстановление 6/с; false всегда безопасно снимает запрос. Клиент не передаёт скорость, запас, dt или награду.

`round_snapshot` получает `stamina`, `stamina_capacity`, `is_sprinting`, `sprint_exhausted`, `start_look` (нормализованный горизонтальный Vector3 выбранного авторского старта). При входе в active клиент применяет направление к камере один раз; обычные snapshots не сбрасывают взгляд. Сервер обновляет ресурс и WalkSpeed на Heartbeat, snapshot — каждые 0.25 с. Горизонтальная AssemblyLinearVelocity >0.5 studs/с считается движением; MoveDirection не используется на сервере. На Humanoid сервер пишет диагностические/визуальные read-only Attributes `corn_stamina`, `corn_sprinting`, `corn_sprint_exhausted`; клиент их не задаёт. Новых world tags нет. Inactive запрещает бег; начало нового раунда сбрасывает ресурс и намерение.

Клиент фиксирует CameraMode=LockFirstPerson и пределы zoom=0.5 в active, восстанавливает исходную камеру вне раунда. Alt включает Modal на видимой кнопке завершения раунда для свободного курсора, снимая намерение спринта. UI показывает серверный запас. Передвижение не изменяет Workspace/Edit, импортированный ассет и авторские координаты.

История раннего этапа 2026-10-10 (20 Sources, до карты 840/охоты). Ключевой цикл и движение проверены в живой Children_of_corn; [результаты](2026-10-10_studio-playtest.md). Все 20 Sources установлены в Edit. Пропорции исправлены, авторские координаты сохранены. Дальний обзор остаётся редким; рабочая .rbxl обновлена проверенной AutoRecovery Studio без пересериализации. Полный MVP с охотой/поимками/атмосферой ещё не завершён.

## Владение сценой

- Рабочая сцена: `place/Children_of_corn.rbxl`. Все операции установки проверяют её маркеры и отказываются при наличии маркеров Speed Monkey.
- Workspace/Terrain/Lighting и импортированный ServerStorage-ассет принадлежат автору. Rojo по-прежнему отображает только GameShared/GameServer/GameClient. Live sync остановлен; новую карту переносим одним защищённым установщиком или в отдельной проверенной копии файла.
- Пользователь явно разрешил постоянный CornMap для ручного редактирования. Прежний CornPrototypeRuntime 120 × 120 заменяется привязкой к готовой сцене. Иные пользовательские объекты не удаляются.
- Повтор раунда не перестраивает карту. Меняются только собственный временный ключ, состояние ворот и раунда. Остановка Test возвращает Studio Edit-состояние.

## Контракт постоянного CornMap

Workspace/CornMap — Model с `corn_project_id = children_of_corn`; текущая map_version=3, MapTuningVersion=1, TorchClearanceVersion=1. Версия 2 относится к историческому стартовому ремонту. Первая установка не перезаписывает существующий CornMap; последующие обновления изменяют только явно проверенные собственные объекты. Автор переместил текущую карту и Baseplate вниз: их CFrame сохраняются, исходный Y=80 не является обязательной высотой.

| Объект | Контракт |
|---|---|
| Ground | Якорный Part, поверхность 840 × 840 studs. Текущая высота задаётся авторским CFrame; Y=80 относится к первой установке |
| FieldZone | Невидимый Part 840 × 10 × 840; tag corn_field_zone. Авторские положение и горизонтальный CFrame задают посадку; нижняя поверхность согласована с Ground |
| PlayBounds | Невидимый Part 840 × 50 × 880, расширяет безопасную проверку до внешнего выхода; tag corn_play_bounds |
| CornerSpawns | Четыре настоящие нейтральные SpawnLocation, уникальные spawn_id, tag corn_spawn, Enabled/Anchored=true. Сервер выбирает угол при новом раунде/повторе; CFrame задаёт направление и высоту. Legacy RoundSpawn поддерживается как fallback прежних карт |
| KeySlots | Folder с 15 якорными Parts, tag corn_key_slot, уникальный непустой slot_id. Ключ появляется над перемещённым/повёрнутым слотом |
| EscapeGate | Model, tag corn_gate, gate_id = solo_gate. Door, InteractionAnchor и ExitZone внутри одной Model, перемещаются и поворачиваются вместе |
| Door | Якорный BasePart ворот. Закрытые исходные Transparency/CanCollide/CanQuery сохраняются привязкой; открытие скрывает и выключает только эту часть |
| InteractionAnchor | Невидимый Part на стороне входа; создаваемый на время теста E ProximityPrompt, радиус 4. Передняя сторона определяется локальным Z Door относительно Anchor |
| ExitZone | Невидимый неконфликтующий Part за воротами, tag corn_exit, gate_id совпадает. Победа только при открытых воротах и внутри локального объёма |
| NoCornZones | Folder с якорными Parts-зонами: просветы, старт, ворота, центральный ориентир. Сдвиг/поворот/Size меняют область без декоративной кукурузы |
| Props | Folder; дома и прочие декорации из Parts. Дома — препятствия, ключ ищется только в просветах поля. Автор может редактировать их независимо |
| EditorPreview / EditorFieldOverview | Авторские owned Folder сохранённого предпросмотра и дальнего слоя. В Test preview удаляется локально; overview используется до Ready нового runtime backdrop, затем скрывается с сохранением прежнего LocalTransparencyModifier |

Слоты сортируются по slot_id, проверяются количество и уникальность. Tags учитываются только внутри данного CornMap. Источник ворот, старт, FieldZone и PlayBounds должны оставаться доступны. Поворот ворот не ломает проверку передней стороны и выхода. Наклоны земли/FieldZone и вертикальные ступени в этом первом этапе не поддерживаются; горизонтальные координаты и размеры редактируются вручную.

## Кукуруза

ServerStorage содержит импортированный `SM_Prop_Plant_Corn_01_L`; допустимый альтернативный явный идентификатор `CornPlantTemplate`. Источник сохраняется целиком и не масштабируется на месте. В сохранённой сцене MeshContent Uri = rbxassetid://104111861186519, TextureContent Uri = rbxassetid://137803536172445.

Game/CornField.Prepare() проверяет art-only источник и создаёт нормализованный клон высотой 8 studs в ReplicatedStorage/CornRuntimeArt/CornPlantTemplate во время Test. При неоднозначных источниках или коде внутри art сообщает ошибку; исходный ассет не меняется. Родитель содержит атрибут принадлежности Corn. Геометрия/UV и texture Uri сохраняются.

Shared Game/CornLayout задаёт базовый шаг 3 studs, клетки относительно FieldZone, детерминированные вариации и локальные исключения NoCornZones/просветов/Props. Собственные CornClientPlants и CornClientBackdrop исключаются из обхода world binding; одно имя папки без ownership не даёт права пропустить авторское содержимое. Клиентский CornController создаёт ограниченные порции ближних растений (150/200 studs с LOD), удаляет дальние группы. CornBackdropController отдельно создаёт полный runtime слой с шагом 6 и cap 20000. Все растения Anchored=true, CanCollide/CanTouch/CanQuery=false, CastShadow=false. Кукуруза — клиентский декор; серверные ключ, ворота и награда от него не зависят. Полная плотная сетка шага 3 требует около 78 тысяч растений; она одновременно не создаётся.

Для редактирования сохраняются EditorPreview (1187 растений на текущей карте) и EditorFieldOverview (4977, шаг 12). Историческое растягивание X/Z было исправлено защищённым fix-corn-proportions; [живой отчёт](2026-10-10_studio-playtest.md) фиксирует применение и сохранность авторских координат. Новый runtime фон сохраняет нормальные пропорции и не меняет saved Size. При Ready он скрывает saved overview, а ближние полностью готовые группы локально скрывают только свои участки фона. Выгрузка/Stop точно восстанавливают прежнюю локальную прозрачность.

Полноценный лёгкий ассет группы стоящих растений и густая посадка во всём Edit остаются возможными будущими улучшениями. Текущий шаг 6 не объявляется такой заменой. Предпросмотр выбранной области может пересоздать только свою Folder; ручные растения и Props не удаляются. Дома исключаются из посадки по footprint Parts (Box); новые ручные сооружения дополняются NoCornZone. Итоговая визуальная/FPS и обычная игровая приёмка фиксируются отдельно от файловых fixture.

## Lifecycle и игровой цикл

Bootstrap загружает Services/Controllers по Order, Init всех затем Start всех. Services: Network 10, Tag 20, Round 30. Controllers: CornBackdrop 45, Corn 50, Movement 90, Minimap 95, Round 100. Весь игровой код запускается только Studio/DEV/solo_local. Основной игровой мир читает постоянный CornMap; скрытого построения другой маленькой карты больше нет.

SoloRound — серверный владелец одного игрока, фазы, случайного слота ключа, ворот, выносливости, охоты/двух попыток, истории мини-карты, результата и временных алмазов. Клиент занимается интерфейсом, камерой и декором. Полная приёмка хоррор-MVP остаётся открытой из-за отложенного звука и непроверенных страха/времени поиска.

| Endpoint | Payload |
|---|---|
| request_round_action Client → Server | action: sync/start/retry/abort/menu; start/retry требуют lighting_mode easy/medium/hard; token bucket capacity 2, refill 2/sec |
| request_sprint_intent Client → Server | boolean; сервер проверяет владельца, фазу и живого персонажа, true ограничен token bucket 12/6; false снимает запрос |
| round_snapshot Server → Client | phase, lighting_mode, minimap, has_key, gate_open, session_diamonds, reward_diamonds, elapsed_sec, notice, stamina, stamina_capacity, is_sprinting, sprint_exhausted, start_look, catches_remaining, monster_state, protection_sec |

Фазы: ready/preparing/active/caught/escaped/caught_out/aborted. Клиент не объявляет победу, не выбирает скрытый слот и не задаёт награду. E-взаимодействие проверяет владельца, фазу, текущего живого персонажа, Enabled, дистанцию 4, луч без твёрдой преграды и для ворот входную сторону. Ключ расходуется при открытии. Пересечение ExitZone живым игроком даёт +10 один раз. Retry возвращает на авторский старт, закрывает ворота, выбирает новый слот и сохраняет баланс; Reset/смерть/уход прерывают раунд без награды.

## Проверка и границы

Нужны format/lint/Rojo build, проверка сохранения пользовательских instances/ассета и локальный Studio Test: карта видна в Edit; кукуруза видна у игрока; передвижение Gate Model работает; пройти ключ → ворота → выход → retry; награда не дублируется. CLI-проверка не заменяет Test. Сцена для тестировщика сохраняет код и карту в .rbxl; Rojo ему не требуется, облачным mesh/texture нужны доступ и загрузка.

## История файловых проверок (2026-10-09)

- scripts/check.ps1: StyLua, Selene 0/0/0, Rojo build и sourcemap, безопасный mapping и отключённый persistence — PASS.
- tests/editable-scene.luau: защищённая установка карты/предпросмотра, неизменность исходной mesh-модели, динамический старт, ключ/закрытие ворот, поворот gate/exit, сохранение ручных изменений при повторной установке, отказ в Speed Monkey/при изменённых Sources/открытых вкладках скриптов/дочерних объектах старого GreyboxWorld и откат при ошибке art — PASS. Это копии DataModel в памяти с ограниченным Lune-адаптером, без Roblox physics/network/rendering.
- Исторический CornLayout fixture до ремонта: сетка 267 × 267 при шаге 4.5, нижняя поверхность/yaw FieldZone, детерминированный yaw, перемещённый слот, повёрнутая NoCornZone, Props footprints — PASS. Текущая подробная посадка имеет шаг 3; прежняя сетка не описывает новый слой.
- Агент не пересериализовал бинарную сцену. Пользователь применил стартовый ремонт и сохранил файл 17:12:53 (138 811 байт); четыре угла и Enabled=false нижнего старта подтверждены. Пользователь сообщил об обычной плотной кукурузе в Play; это частичное наблюдение, а не приёмка полного цикла/FPS.

## Исправление старта и заполнения поля (2026-10-09, после Studio Test)

Пользовательский тест выявил отсутствие RoundSpawn в сохранённой карте: привязка раунда завершилась ошибкой, персонаж остался на нижнем стандартном SpawnLocation. Новый контракт допускает CornerSpawns: четыре редактируемые SpawnLocation с уникальными spawn_id и тегом corn_spawn, направленные внутрь поля. Сервер выбирает случайный угол при новом раунде и повторе, задаёт Player.RespawnLocation и перемещает готового персонажа на выбранный старт уже в меню. Выбранная точка сохраняется в пределах раунда. Старый нижний Workspace/SpawnLocation сохраняется, отключение Enabled входит в защищённое обновление с откатом. Legacy RoundSpawn поддерживается для прежних карт.

Посадка получает шаг 3 studs и ChunkCells=12 (группа шириной 36 studs). Вся область поля содержит сохранённый EditorFieldOverview: редкие декоративные MeshParts с отключёнными коллизиями и просветами. Растягивание X/Z этих копий признано визуальной регрессией и устраняется отдельным обновлением пропорций. Детальные растения высотой 8 studs подгружаются вокруг персонажа, дальний слой скрывается локально только там, где готова детальная группа. В Edit около выбора остаётся детальный предпросмотр. Источник ассета, Props, ворота, Ground, KeySlots и ручные координаты не пересоздаются. Графические результаты и FPS требуют повторного Studio Test.

Обновление существующей сцены проверяет её сохранённые Sources и маркеры до записи; новый установщик не использует ранний return при наличии CornMap. Повторное применение сохраняет имеющиеся углы и ручные правки.

## Проверки исправления после наблюдаемого сбоя

check.ps1 и tests/editable-scene.luau пройдены. tests/scene-repair.luau выполнен на копии точной сцены before-spawn-fix: отсутствующий старт восстановлен, все четыре угла доступны, серверные menu/start/retry-функции перемещают модель выше поля и назначают RespawnLocation; выход выдаёт награду один раз. События и Player/Humanoid заменены заглушками, геометрия ограничена Lune: это не проверка Roblox physics/rendering. Проверены полный дальний слой (5524 MeshParts), плотные детали/локальное скрытие/восстановление, сохранение ручных углов при повторе, откат Sources/слоёв/старого спавна и отказ при ручных объектах слоя либо другой игре. Пользователь позже подтвердил плотные обычные растения в Play; направление взгляда, полный цикл, итоговые пропорции Edit и FPS требуют Studio Test.

Проверка сохранности ремонта: tests/test_scene_preservation.py — 6 PASS (явные изменения ремонта допускаются, чужой дом/верхний спавн/прочие атрибуты/неизвестные данные Terrain не допускаются). До применения ремонта исходная сцена и точная копия before-spawn-fix имеют одинаковый SHA-256 df831a6af024f9d8b4667ff3b67974b8a3c0c541afb3a54e2bb4a0da7831274b. Текущий пользовательский Save содержит ручное перемещение CornMap/Baseplate: сравнение геометрии с before-spawn-fix ожидаемо расходится и не считается PASS неизменности. Неизвестный 9-byte payload Terrain стабилен; сохранность текущих авторских CFrame должна проверяться относительно снимка 17:12:53 перед новым исправлением.

## История подключения 2026-10-09

Снимок 17:12:53: 138 811 байт, SHA-256 `58c708359df037c85a7dc777dc46dbcad88af86ac8ede588472fc294b0759105`. Исходники и saved-файл читаются; несохранённые правки не видны. Регистрация встроенного MCP в Codex выполнена и параметры проверены с сохранением прежних настроек; ручное Enable Studio as MCP server и перезапуск Codex ещё предстоят. Живые MCP tools не доступны до успешного подключения и проверки конкретного окна Children_of_corn. [Инструкция подключения](studio-connection.md).


## Итог фермерского этапа — 2026-10-12

[Фактическая приёмка и сохранение](2026-10-12_farm-playtest.md). Итог60 Sources; данные FBX разбиты на19 string chunks и4 init ModuleScripts из-за реального лимита Studio Source200000 символов. Каждый chunk Source≤140000 UTF8bytes, concat точно совпадает с neutral JSON. Server geometry/collision строит10 shared-by-copy meshes для40 owned targets; client держит fixed-size geometry, не реплицирует EditableMesh через server Object. У новых моделей ModelStreamingMode.Atomic; исходный Workspace.StreamingEnabled=true сохранён. Client runtime-only CornMap attrs: CornFarmGeometryStatus, CornFarmGeometryPending, CornFarmGeometryError. Сервер не доверяет им; saved Edit map attrs не меняются.

Фермерские модели используют точный предоставленный PolygonFarm_Texture_01_A.png из Sort_main_ferm/Textures, URI rbxassetid://95855894892409; прежние Corn/Lighting/imported assets сохраняются. Первоначальная проверка с общим corn atlas выявила неправильный цвет сарая, после чего atlas исправлен только у40 farm MeshParts. UI фотографии: easy88962075064935, medium104212461922179, hard96153574471723. Они сняты из реального renderer и проверены как загруженные ImageLabels.

EditableMesh имеет локальный Object content, не permanent cloud mesh URI. Geometry data сохраняются в .rbxl Sources; обычный Play восстанавливает модели на server/client автоматически. Для восстановления видимых моделей в Edit после повторного открытия выполняется guarded scripts/restore-farm-editor.luau через MCP/Command Bar. Прямой запуск через Command Bar: require(game.ServerScriptService.GameServer.Game.FarmGeometry).Ensure(). Новое размещение не требуется. Настоящий повторный reopen файла ещё не проверен; это отдельная граница приёмки, не утверждение о permanent Editor Object serialization.

## Коррекция дальнего текста вывески —2026-10-14

Foreground GPU выявил: SurfaceGui.AlwaysOnToptrue не показывает букв, false показывает. PPS48 оставляет TextScaled capped100 при увеличенииPart×3; PPS16 возвращает исходныйcanvas576×153.6 и увеличиваетphysicalбуквы×3. Итоговые постоянные3props: ExitSign.Size/CFrame и ExitTextSurface.PixelsPerStud48→16; AlwaysOnTop сохраняетсяисходнымfalse. Guardedinstaller принимает прежнее промежуточноеAOTtrue тольконаточнойувеличеннойгеометрии, восстанавливаетfalse. Nootherworld/Lightingdelta.

Для дальнего видимого выхода существующий GateHintController создаёт одинлокальныйownedScreenGui+TextLabel+UIStroke вPlayerGui; имяCornExitBeacon, attrsCornExitBeaconOwned/project/version1, noinput/resetOnSpawnfalse, displayorder5. ТолькоexactownedpublicExitSign, active/caught snapshots/livingcharacter, Camera:WorldToViewportPoint(signPosition); visibleonlyinfront/onScreen/<=1300stud andfield-facingnormal. Размер из projectedsignsize (FOV/viewport), clampmin96×26/max600×160; pale-greenВЫХОД/darkgreenbackground/lightoutline/TextScaled, duty1.05on/.55off.10Hz, constantboundedreferences/nofieldscans/noRoot/camerawrites/newremote. OriginalSurface.Enabledfalseonlywhileownedlocaloverlay, safeidentity/propertyguardrestore/foreignedits/refusedrebind; beaconforeigninsertionspreservedoncleanup, streaming/ready/menu/death/Destroy cleanup. No newSource/persistentinstances. GPUnear/far/day/dusk/night andlifecyclefixturesrequired beforeacceptance.

## Финал, награды, неон и факелы —2026-10-15

Текущий разрешённыйscope: локальныйsoloPC; multiplayer/persistence/purchases/publishingне добавляются. Автор подтвердил: воВСЕХрежимах открытиеворот валиднымключом одинраз запускаетserverdeadline120сек. Таймернеприостанавливаетсяприcapture/ожиданииВозрождения. Победа—толькоphysicalcrossingExitZone послеgateOpen; серверфиксируетescaped/однократнуюнаграду easy5/medium10/hard20. Поdeadlineдо обработкиcapture/escape проигрышcaught_out/noticeevacuationexpired, reward0; меню/retry/выходвладельца очищаютdeadline/всехNPC.

Snapshot existinground_snapshot расширяется evacuation={active:boolean,remaining:number0..120,duration:120}; сервервсегдапубликует, клиентдлясовместимыхстарыхfixturesможетприниматьотсутствиекакinactive, присутствующееMalformedотвергает. UIвверхупоцентру MM:SS/плавноепульсирование, толькоpresentationserverremaininginterpolation, неуправляетwin/reward. No newremote.

НаgateOpenсерверединождысоздаётMonster2/Monster3 вownedCornRoundRuntime, техже9visualParts+Root/owned/project/rigVersion1 + MonsterIndex1..3. Позиции—изсуществующихбезопасныхSlots вдалиотигрока, неслучайныепроизвольныекоординатыклиента. Detectionall3×2(16→32), lossradius42неувеличиваем. ДополнительныеNPCсразуpatrol/безновогопробуждения/безбонуснойпервой10секпогони; исходныйсохраняетпервую10секпопытку. СервероднимцикломStep/CheckTraps,однаcapturetransactionнаtick; capture.frameберётсяупоймавшегоNPC, остальныеостанавливаютсявcapturing; revivalResetHomeвсех3сзащитой, deadlineпродолжается. Всеcleanupпоepoch, повторноевскрытиенеспавнит/непродлевает. Клиентанимацияограниченатремяexactownedименами/27visualwritesmax30Hz,Rootнепишет; chaseHUD/audioвыбираетактивногоближайшегоиз3, cornmax8players+3NPC. Сохранятьbudgetfieldwindmax4plants; 3NPCнеувеличиваютэтотбюджет.

Сверчки: прежние5spatialemitters/15on15off/staggered30sec. NonloopedSoundначинаетсяVolume0; однасilentPlayпопыткавслоте, boundedcoldstart≤1сек. Начавшийсявовремязвукfadein1секотфактическогостарта/fadeout1секпередmin(slotend,knownclipend). Позднийнеозвученныйdecodeпропускаетсядоследующегослота, безочереди/историческогодогона. Нормальныйslotend—Volume0/intentfalseбезStop; naturalEnd. TerminalcleanupможетStop. Неизменятьcornfulltails/voices/othermix.

Вывеска: удалитьprojectedScreenGuiCornExitBeacon/видимостьсквозьполе; физическийownedNeonPart+исходныйSurfaceText(occluded/AOTfalse/PPS16/Size3x) остаются. Color-onlyнеоновыйцикл14.3сек: bright.8/dim.7/bright.6/dim.9/bright4.5/dim.8/bright6, повторяется; минимумсегмента.6сек. DimSign=originalColor×.06,DimText=originalColor×.1; дваboundedwrites≤10Hz, noLTM/Material/Enabledwrites/newlights/instances. Ready/menu/capture/death/streaming/Destroy guardedrestore, foreigncolor/path/ownership/material/enabled/LTM stickyrefusal.

Факелы: авторразрешилрассеятьвсе27ownedTorchMarkers. Сохранить2настенныхнаворотахинаихвысотах(сдвигвдольстены/зеркальностьасимметрична); все25напольных—детерминированныеасимметричныеXZ/Yawвнутриполя, preservePole/Flameотносительныйoffset/height/size/арт/lightbrightness. Никакихновыхфакелов/другойгеометрии. Безопасныеклиренсыотдороги/ворот/Spawn/стен/входов/домов/слотов; существующиепуть/спавны/ключнеперекрывать. Guardedinstallerbefore/repeat/refusal/rollback ификсированныйallowlistтолько54PartCFrames(илименьшепринастенныхнесдвигаемых) +knownModelpivotmetadata; newimmutablebefore-finalebackup. RuntimeTorchFx/readbindingsновыепозициикакобычно.

Уточнение автора15октября: шесть факелов у трёх сараев не разбрасывать. Фиксированные пары относительно исходного barn pivot: X±6/Z−11.75, исходные Y/поворот/свет. West X−132/−120,Z−144.75; East X141/153,Z72.25; NorthWest X−300/−288,Z156.25. Это близкое размещение по бокам входов; автоматического следования за будущими ручными переносами сараев нет. Установщик дополнительно проверяет исходные barn pivot/body/топологию и отказывает при перемещённом сарае. Остальные21факел сохраняют утверждённый разброс. Model.WorldPivotData не меняется.

Тени: покаТОЛЬКОанализ/временныйboundedA/B сrestoreLighting/nearshadowprops, непостояннаясменапрофиля. СравнитьbaselineSoft/Realistic/Realistic+boundednearCastShadow, не20kfullfieldshadows. FPS—клиентскийRenderSteppedforeground/currentviewport, p50/p95/p99/hitches; никакойгарантиичеловеческогостраха/ordinaryround/будущегомультиплеера.

## Дымка и связанные точки предметов — 2026-10-15

Автор разрешил доработать вручную вставленную Workspace/CornfieldFog и связать точки предметов с расставленными факелами. Новый неизменяемый файловый baseline — before-haze-clusters-20261015.rbxl, a897bb52fa85505090f973e910139915e6ebb2995e44915c31ecbc2b5c511dca. Он содержит принятую finale-версию75Sources; импорт Fog пока есть только в Edit. Исходный внешний Cornfield_Fog.rbxmx (SHA256 84c534d23645e84d1f585dde206680396204dd8070186c2b4824dbe5b97834e7) сохраняется без правок. Перед установкой сверить пять импортированных узлов и три нормализованных Sources с XML, сохранить их точный snapshot, отказаться при неизвестных ручных изменениях. Код ассета хранится в assets/CornfieldFog вне Rojo; это точечное разрешённое исключение для трёх Sources импортированной модели, а не новое владение Workspace через Rojo.

Дымка использует штатный Atmosphere, а не жёсткую границу FogStart12/FogEnd60. Не переносить/не удалять чужие Atmosphere и не записывать FogStart/FogEnd/FogColor. Работать с одним существующим эффектом; если его нет, допустим один помеченный временный клиентский Atmosphere, удаляемый при cleanup. Сохранять текущий режим освещения, не задавать ночь для всех сложностей. Начальные художественные цели Haze около0.5/1.25/1.8 и Density около0.08/0.18/0.27 для дня/сумерек/ночи требуют GPU-проверки. Интенсивность панели не обещает точную дальность в studs; подписи изменить соответственно. Palette применяется как оттенок с сохранением режима. Плавный переход максимум10Hz, без постоянных записей после стабилизации. Сторонние/серверные изменения LightingModes становятся новой baseline; при выключении возвращать только всё ещё принадлежащие контроллеру значения. Новый baseline нельзя заменять историческим activation snapshot после смены режима. Без сетки частиц, прозрачных плоскостей, дополнительных источников света или новой геометрии на первом варианте.

Существующая переносимая модель имеет ровно Model/Config/RuntimeServer/ClientTemplate/READ_ME, три Sources. RuntimeServer сохраняет серверную проверку Studio/admin, допустимых конечных значений и rate limit; клиентская панель остаётся инструментом текущего локального прототипа. Существующий Control RemoteEvent в CornfieldFogRuntime используется только для визуальных настроек, не для gameplay, наград или таймера. Новые gameplay remotes не добавляются. При удалении модели/клиента/персонажа — guarded cleanup сигналов, GUI, собственного runtime и возвращение последней baseline; чужие объекты сохраняются.

Полевой кластер определяется стабильными slot_id и torch_id='torch_'..slot_id. Для пятнадцати field slots переносится сама corn_key_slot точка так, чтобы факел сохранил исходное относительное смещение X0/Z+4; текущая нерегулярная расстановка TorchV2 задаёт центр кластера. Сохраняются имена, теги, Y, поворот, атрибуты и число точек. Ключ, случайные четыре предмета и два runtime пенька получают новые позиции через существующий world.Slots; minimap посещения, clearing radius6, патрули и точки подкреплений используют те же реальные slot.Position. Не создавать вторую таблицу координат предметов. Три домашних key slots и шесть парных факелов у сараев остаются у зданий. Связанные исходные смотровые пеньки/бочки при наличии перемещать тем же delta кластера только после проверки точного владельца/исходной привязки. Прочий арт, сараи, дорога, ворота и спавны сохраняются. Добавление тегов/атрибутов связи допустимо только для проверенных owned точек, без скрытых item/key markers.

Мир меняется отдельным guarded installer с фиксированным manifest: распознаёт только принятый baseline/полный repeat, отказывает при partial/manual edits, откатывает все сделанные записи при сбое. Проверить расстояния кластеров/пеньков от домов, дороги, спавнов, друг друга и факелов; реальные E/key/item/lookout/мини-карта и перезапуск раунда требуют Studio-теста. Source-only build не заменяет world install, а новый точный engine save — отдельную проверку всех разрешённых дельт и raw Terrain. MVP остаётся локальным solo PC без persistence, purchases, lobby, multiplayer или публикации.

Уточнение клиренсов: центральные пять полевых кластеров получают |X| не менее21 с сохранением стороны дороги; факел перемещается вместе с центром, сохраняя Z+4. Полный возможный footprint runtime пенька со ступенями — X от slot−5 до slot+6.6, Z±3; его нельзя заводить в RoadClearance±9 с corn padding1.5. Три существующие owned Props/LookoutBarrel03/08/13 входят в разрешённый перенос вместе со своими slot03/08/13, сохраняя все собственные размеры, Y, поворот и относительные координаты деталей. Не передвигать другие Props и не изменять WorldPivotData моделей. Точный список CFrame-дельт фиксируется в cluster-layout.json; это дополняет прежний TorchV2, а не разрешает повторно применять его поверх нового расположения.

### Последнее решение автора: один ночной режим

Лёгкий и средний игровые режимы удаляются из доступных правил и интерфейса. Единственный режим — hard, ночь20:30, прежние hard Lighting и награда20алмазов за подтверждённый выход. Shared LightingModes.Default='hard', Order={'hard'}, IsValid отвергает easy/medium и любые неизвестные значения; сервер не принимает обход через старый start/retry remote. В готовности и после результата нет карточек или выбора сложности. Единственные Start/Repeat продолжают существующую полноэкранную цель и отправляют hard после подтверждения. Первая revival продолжает тот же раунд, вторая запускает hard retry; menu возвращает на главный Start. Игровой таймер не начинается до подтверждения цели. Баланс преследования, ключ/предметы, три NPC после ворот и120сек deadline не меняются.

Дымка переносимого ассета по-прежнему умеет корректно сопровождать изменение ClockTime/палитры для авторской настройки и cleanup, но игра использует только ночь. Тесты прежних дневного/сумеречного вариантов в сохранённой finale a897 являются историческими результатами. Новый hard-only follow-up требует отдельной проверки Start/Repeat, серверного отказа easy/medium, дымки ночью и точного сохранения; не переписывать историю старого save под новые правила.

### Последнее решение автора: шелест вдвое чаще

Автор разрешил вдвое более частые новые шелесты при движении в кукурузе, сохраняя полное естественное окончание каждого начавшего звучать клипа. Это заменяет ограничение одного локального Sound без наложения из контракта 14 октября. Серверная проверка движения, grounded/corn/exclusions, телепорта и состояний NPC остаётся прежней на 10 Hz. Интервал новых подтверждённых cues — max(0.45 секунды, manifest duration предыдущего выбранного cue) / 2. Пока движение непрерывно допустимо, deadline продвигается от предыдущего с остатком не более 0.1 секунды; новый deadline не бывает раньше now+0.125. После остановки, прыжка, дороги, телепорта или ineligible следующий принятый cue снова привязывает deadline к now. Один cue за Step, без очереди пропущенных cues или catch-up bursts. Частота фактически слышимых начал ограничена двумя голосами, естественными окончаниями и network/decode задержками.

RoundAudio публикует прежний атомарный AudioRustleStart=id:key и строго возрастающий id для каждого нового валидированного cue. Один прежний server Sound продолжает естественно проигрывать свой клип: более частый cue не вызывает Stop, замену его URI или restart. Он получает следующий доступный выбранный клип только после прежней проверки duration/IsPlaying; восьмисекундное освобождение не начавшейся загрузки сохраняется. Клиентское представление не зависит от очередности репликации URI и не возвращает окончание звука серверу.

AudioController имеет ровно два owned local spatial Sound на actor и один общий newest pending cue. Максимум 8 Players и 3 проверенных NPC дают 11 actors и 22 локальных голоса; новых Sources, remotes и постоянных Instances нет. Свободный голос может начать следующий принятый cue, пока второй доигрывает; занятому голосу нельзя менять URI, Stop или TimePosition до собственного natural Ended. Когда оба заняты, принимается только newest pending, без накопления истории. Остановка, дорога, прыжок, trapped/caught и обычное меню не обрывают начатые локальные хвосты; death/root replacement/terminal/retry/Clear/Destroy очищают оба голоса и pending. Восьмисекундный timeout касается только голоса, который ни разу не начал звучать; retry не возвращает старый cue, если более новый уже был принят. Авторские ID, gain, SoundGroup и rolloff сохранены. Подробности и границы приёмки — в [контракте частоты](2026-10-15_rustle-cadence.md).

### Одобренный автором Bloom — 2026-10-15

Автор явно подтвердил сохранение текущего `Lighting/Bloom` класса `BloomEffect`: `Intensity=0.85` и `Size=32`. От immutable before-haze-clusters baseline a897 это ровно две фиксированные дельты: float Intensity1→0.85 (engine f32 `0.8500000238418579`) и float Size24→32. Saved-copy verifier требует оба новых значения и прежний класс/путь; неизвестные значения, типы, новые свойства или другие Lighting-дельты отклоняются. Эти две дельты дополняют ранее разрешённые 28 cluster CFrames и пять imported Fog nodes. Все остальные исходные свойства, identities, Model pivots и raw Terrain сохраняются строго; это не разрешение перезаписывать Lighting из runtime.

### Жёлтая кукуруза до первого появления — 2026-10-15

Автор запросил жёлтую кукурузу сразу при запуске, без зелёного состояния и поздней подмены. Это заменяет прежнее восстановление зелёного атласа в ready/menu. Единственный hard-режим и ready используют существующий сухой атлас CornAppearance.DryTextureId=103653296385119 с исходными UV/mesh104111861186519; исходный импорт ServerStorage и зелёный cloud atlas137803536172445 остаются неизменными. Не создавать новый uploaded asset и не перерисовывать геометрию.

CornField.Prepare проверяет нормализованный отдельный MeshPart на точный mesh, green/dry known URI и отсутствие SurfaceAppearance, назначает сухой TextureID ДО помещения копии в ReplicatedStorage. При неизвестном URI/mesh — отказ до публикации/замены существующего шаблона. Near/backdrop клонируют этот уже жёлтый шаблон до собственного Parent, поэтому не ждут snapshot/очередь appearance. Сохранённые owned EditorFieldOverview/EditorPreview меняют только точные known TextureID в отдельном guarded world installer текущего уменьшения поля; оригинальный арт не входит в список дельт. Не выводить зелёный saved fallback в ожидании client controllers.

CornAppearanceController сохраняет точный зарегистрированный TextureID, включая уже сухой; cleanup и ready не должны выводить унаследованные сухие копии обратно в зелёный. Ручной неизвестный URI/mesh и SurfaceAppearance сохраняются прежними guards. Бюджетная очередь остаётся для контролируемых appearance updates, но первое жёлтое состояние создаётся до публикации, а не через full-field проход после начала игры. Проверка: реальный production CornField на unparented clone с проверкой URI непосредственно в момент Parent, original-art preservation/отказы/repeat; контроллер ready/hard/cleanup/inherited dry; Studio холодный Start/Retry и реальные URI/GPU после guarded установки. Адаптер не подтверждает скорость cloud texture decode или GPU пиксели.
### Поле 630 и готовая жёлтая кукуруза — 2026-10-15

Автор уменьшает сторону текущего поля на25%:840→630studs. Это изменение горизонтального плана вокруг неизменного центра FieldZone; высоты, масштаб и относительные детали человеческих Props не сжимаются. Ground/FieldZone получают630×630; PlayBounds сохраняет40studs дополнительной длины для выхода. Boundary thickness2,gate width12,road width14 и все Y сохраняются. Ворота, exit ground/zone/clearance/sign/wall torches перемещаются единым deltaZ−105; четыре наземных exit-факела сохраняют расстояния поZ от ворот. Сараи и грузовик переносятся жёстко по .75 координатам их pivots; привязанные пары факелов, домашние предметные точки, шины и мусор переносятся тем же delta соответствующего здания/грузовика. Пятнадцать field-slot кластеров сохраняют torch offsetX0/Z4 и barrel offset; центральные |X| остаются≥21 для полного footprint runtimeпенька/ступеней вне road clearance. Спавны/остальные плановые anchors получают .75XZ. Новых gameplay remotes или скрытых item positions нет.

EditorPreview переносится жёстко вместе со SWspawn, без сжатия межрастительных расстояний; EditorFieldOverview сохраняет прежнюю сетку. Только проверенные owned MeshParts исходного corn mesh разрешено удалить за новыми границами либо внутри новых просветов/Props footprints. У выживших растений сохраняются размеры, Y/yaw/нормальные пропорции; меняется только approvedpreviewtranslation и TextureID137803536172445→103653296385119. Исходный ServerStorage art остаётся точным. Сохранённый sparseoverview может сохранять старые пустоты; runtime всегда строит актуальную посадку по630/новымисключениям. Это не densewholefieldEdit/reopen/FPSприёмка.

Изменение мира — отдельный fixedmanifest guardedinstaller относительно immutable c7015e55… engine baseline; exactknownbefore либо fullrepeat, unknown/partial/manual/topology/foreignownedplant refusal, rollback каждого CF/Size/pivot/attribute/texture/reparent при ошибке. Удаление ownedрастений откладывается до успешного применения; импортированный/посторонний арт и Baseplate не затрагиваются. Scene-файлы не пересериализуются. Runtimeключ/2energy/2traps/2lookouts, minimap,сбросиnativeE/escape/retry требуют настоящейStudioпроверки после переноса.

### Доступные капканы рядом с факелами — 2026-10-15

Аудит обнаружил старое пересечение: legacy corn_barrel у slot03/08/13 стоит относительно slot на X+2.8, имеет радиус1.6 и высоту4; прежний ground pickup капкана на X+3.6/Yground+0.22 оказывался внутри дерева. Для доступности предметов сервер создаёт капканы с противоположной стороны той же группы: X−3.6/Z0/Yground+0.22. Энергетики и их высокие пеньки остаются на X+3.6; key slot, случайный выбор четырёх различных групп, два энергетика/два капкана, tags/attrs, promptsE/4studs/LOS и серверные проверки не меняются. Постоянные бочки/факелы/слоты не двигаются ради этого исправления; fixed resize manifest остаётся прежним. Полный runtime footprint капкана укладывается в ранее проверенный диапазон Xslot−5..slot+6.6/Z±3 и clearing radius6.

Проверка использует настоящую геометрию трёх исходных цилиндров и production InventoryWorld: до исправления anchor внутри дерева, после исправления все части капкана вне дерева и внутри прежнего footprint. Все15 групп и исключение ключевого slot проверяются отдельно; actual engine rays/native E должны подтвердить доступность двух капканов, включая группу с legacy barrel. Локальный адаптер не заменяет эти Studio проверки. Новых remotes, постоянных экземпляров и Sources нет; обновляется один существующий Source InventoryWorld.

### История временного сравнения двух звуков через Alt — 2026-10-15

После строго проверенного сохранения поля630 (SHA256489af64f…,996617байт,4160instances/78Sources) автор разрешил переключатель двух локальных представлений шелеста. Звук1 сохраняет нынешние шесть клипов/два голоса/полные хвосты. Звук2 использует предоставленный MP3 как один owned local loop внутри прежней CornPersonalAudio/Effects; первое допустимое движение вызывает Play, последующее после Pause — Resume с прежней TimePosition. Looped сам обходит весь11.064-секундный клип. Остановка/дорога/просвет/воздух/поимка/меню/смена режима/раунда/Root ставят только этот loop на Pause без сброса позиции. Серверное is_sprinting меняет PlaybackSpeed1→1.5; игровой баланс и скорость персонажа не меняются.

RoundAudio на прежнем валидированном actor poll10Hz публикует boolean AudioCornActive на существующем owned CornAudio_corn_rustle, первоначальноfalse и далее только при изменении. Значение равно eligible AND actual nonteleport movement AND inCorn; считается независимо от короткого Sound busy/nextAt. Клиент читает только распознанный server Sound своего текущего живого Root, требует active snapshot/отсутствие захвата и Roblox menu. Исчезновение источника, Root или ownership запрещает loop. Выбор варианта, TimePosition и локальный playback не отправляются на сервер; новых remotes/постоянных instances/Sources нет.

Две кнопки Звук1/Звук2 находятся в существующем CornMovementHud над выносливостью. Нажатие разрешено только в активном Alt-cursor состоянии без карты/захвата/menu; MovementController владеет прежней Alt-привязкой и предоставляет IsCursorOpen/BindRustleComparison/SetRustleComparison. Выбор и курсор клипа сохраняются только в сеансе. Переход1→2 очищает свой pending и подавляет новые собственные короткие cues, уже начатые хвосты заканчиваются естественно. Собственные id продолжают учитываться; возврат1 не воспроизводит историю. NPC и другие actors сохраняют прежние голоса.

Автор импортировал AudioAssets.COC_Corn_Continuous_02 как настоящий AssetID138698164682825/Duration11.064/Gain1. Отдельный временный owned Sound в правильной Studio Edit декодирован: AssetFetchStatus.Success/IsLoadedtrue/TimeLength11.064, cleanup выполнен. Интерфейс явно сообщает необходимость импорта при отсутствующем ID либо недоступность при отказе decoder, не выбирает недоступный второй режим и не подставляет другой клип. Исходный локальный файл и его byte-identical подготовленная копия сохраняются. Затронуты только пять прежних Sources: RoundAudio, AudioController, AudioRules, AudioAssets, MovementController. Общий personal-audio cleanup/preload не должен вызывать Stop для loop; guarded foreign identity/URI/parent/group/Looped сохраняются. Два новых runtime TextButton и один local Sound имеют ограниченное количество; нет новых field scans или world/camera writes. Реальный native Alt/button/W/stop/resume/sprint/wrap и точный engine save проверяются отдельно от decoder и локальных адаптеров.

### Итоговый выбор автора: непрерывный шелест всем — 2026-10-15

Автор выбрал второй звук138698164682825 окончательно для игроков и монстров. Это заменяет временное сравнение выше: убрать обе кнопки и comparison API/Alt glue, сохранив обычные Alt, HUD, инвентарь и мини-карту. Непрерывный звук включается автоматически без выбора. Шесть старых коротких corn assets остаются архивными записями AudioAssets, но gameplay не запускает их ни на сервере, ни на клиенте; новая ветка не наслаивается на старые короткие cues/пул.

Собственный игрок сохраняет один прежний CornPersonalAudio.CornLoop (2D) с курсором сеанса через остановки/меню/поимку/retry/Root. Остальные поддерживаемые игроки и максимум три NPC имеют по одному owned spatial local loop на своём Root, rolloff5..65; лимит8Players+3NPC даёт максимум11проигрывателей вместе с собственным. Первый запуск каждого — Play, затем Pause/Resume; никакой замены URI, Stop или seek между движениями. Удаление/замена Root очищает лишь его пространственный loop с guarded сохранением чужих правок; после терминала чужие/NPC loops очищаются, собственный остаётся paused. Движение NPC, trap/capture/patrol/chase и случайные независимые позиции не делят один курсор.

Существующий серверный CornAudio_corn_rustle становится только silent metadata source с continuous URI/Volume0: никогда не вызывает Play/Resume. На прежних проверках10Hz сохраняется AudioCornActive, добавляется on-change AudioCornSpeed. Для других игроков скорость берётся из проверенного Humanoid.WalkSpeed/12, clamp1..2 с округлением0.1. Для NPC предпочтительна стабильная authoritative hunt speed/10; fallback фактического горизонтального движения округляется0.1/clamp1..2. Неподвижность/невалидное движение ставят activefalse и speed1. Собственный клиент сохраняет уже принятые walk1/sprint1.5 по серверному is_sprinting. Никаких новых remotes, Sources, world/Lighting/art/Terrain дельт, field scans или клиентских gameplay запросов. Existing music/голоса/scream/сверчки/Fire не меняются. Новый источник и loops требуют actual automatic player и всех3NPC spatial Pause/Resume/speed/cursor/cleanup проверки; прежний A/B Play остаётся историческим и не заменяет её.
