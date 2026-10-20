# Вариант B: высокая кукуруза, фонарь и Realistic — сохранено

Пользователь открыл B и поручил сделать кукурузу выше и перенести фонарь с Realistic
из A. Проверена единственная открытая Corn B-сцена e675da66-7001-4541-a1d4-97623322c8c4.
Все153исходных Sources совпали с принятым B checkpoint. Незнакомых авторских правок
в code roots и новых Workspace объектов не обнаружено. Перед работой создан точный
immutable Children_of_corn_B.before-flashlight-tall-20261020.rbxl1485700/e34fe75f… .
Предыдущий before-realistic backup того же B также не заменялся.

## Результат

Базовая высота подробной B-кукурузы увеличена с8до10stud (+25%) на всех12шаблонах:
четыре формы × Near/Mid/Far. CornAppearance создаёт отдельные более высокие render
клоны; исходный каталог/меши высотой8 и готовые geometry templates не меняются.
Увеличивается только Size.Y. DetailedPivot сохраняет правильное основание и старую
вариацию; X/Z, exclusions, число растений, Near576/four chunks и streaming18 не меняются.
При неудачном построении временные высокие клоны уничтожаются. Сохранённые Editor
preview/overview прежние: высокая подробная кукуруза, как и прежнее B-оформление,
показывается в Play. В native:10578Far и до1362ближних на проверенном старте,
405Near; высота измеренных растений8.679…11.4999stud, все четыре формы присутствуют.

В B установлены FlashlightController/FlashlightPresentation/FlashlightTuning,
RoundController и подсказки ЛКМ. Общий controller допускает owned A/B; чужая variant
отвергается. Сохранённый файл A не обновлялся. Два направленных SpotLight находятся
в Lens/LensAim короткого ручного фонаря; tipError0/axisDot≈1,11Parts/3Spots включая
слабый свет хвата, без PointLight/Beam/декоративных Raycast. ЛКМ включает/выключает,
F не связана, новый раунд ON. Прежние плавные camera motion/aimlag/ownership guards.
Studio-only панель:Alt→Настройка фонаря, яркость/угол/дальность двух пучков, наклон,
reset/export; значения Play временные. Постоянный B-банк доступен в ReplicatedStorage.

LightingStyle.Realistic закреплён в сцене. Runtime LightingModes перенесён из A:
чёрная ночь, факелы и прежний fog; пять исходных Lighting объектов B сохранены,
параметры временно восстанавливаются при cleanup. Яркий стандартный A preset
пересвечивал B-листья на фактическом кадре. В B закреплены последние авторские
параметры A:Wide brightness2/angle100/range32,Core13/30/4,Pitch−4. Вторая картинка
native-field.jpg показывает фактуру листьев без прежнего большого белого пятна.
Это рабочая настройка, не новая человеческая приёмка страха/микса/общего баланса.

Источник HarvestWardenVisual в B оставлен точным старым B. Красные глаза/существо,
48/96, аудио, gameplay/economy/network/persistence/purchases/lobby прежние.
Все68data Sources и raw Terrain сохранены; новых облачных ассетов/публикации нет.

## Проверки и сохранение

check.ps1 PASS:StyLua/Selene0errors/0warnings/0parse (cached API), code-onlyRojo,
безопасные mappings/persistencefalse. PASS harvest-corn (все LOD/основания/ширина/
exclusions/лимиты/отмена/immutable templates), flashlight-controller A/B + foreign
variant/lifecycle/ЛКМ/ownership/camera rollback/noRootwrites, flashlight-presentation
5824poses/30…240FPS, round-intro, lighting-modes Capture/Apply/Restore.

Guarded build-B-flashlight-tall-installer.py → install-B-flashlight-tall.luau:
все153Sources/классы/остановленный Corn B/630field/нет чужих корней/открытых tabs,
создаёт3Modules и меняет ровно4Sources: CornAppearance,LightingModes,RoundText,
RoundController. Изначальный B HarvestWardenVisual сохраняется из baseline, хотя
локальный src содержит более поздний A-вариант этого файла. Затем только
LightingStyle и отдельный новый B bank Folder+2Spots. Банк проверяется до Source
изменений, неизвестные ручные параметры не затираются. Native4changed/3created,
repeat0; банк3узла затемrepeat0; последняя полная повторная установка0/0.
Fixture29unsafe/rollback refusals PASS, включая семь Source-write отказов и foreignbank.
Save fixture202DOM/3rawTerrain refusals PASS: Modules/default metadata, bank props/
attributes/history/extra nodes, все Sources и retainedworld; мутации только в памяти.

Normal bootstrap, один реальный клиент. Нативные UI команды Start/Confirm,
ЛКМ OFF→F unchanged→ЛКМ ON. При открытой панели реальный widebrightnessPlus15.08→16.08
и reset сработали без toggle. После применения B-банка выполнен новый Play:
settings2/100/32,13/30/4,−4 прочитаны штатным Controller, ON/exactownership/Realistic/
Brightness0/Ambient0/fog0.27/1.8. Измерены12templates и реальные near/far растения.
50samples при pitch−75°: все ON-owned,41grounded/9air от настоящего Space, точка
под центром камеры всегда внутри широкого пучка. Native кадр показал освещённый
Spawn/землю под ногами. Pitch/focus/cursor стабилизированы точными временными
bindings/LocalScripts; Root не перемещался. Это не физический mouse-look, blind
round, новый4client/longFPS/reopen/fear/mix acceptance. Ранние OFF/Alt/panel-open
снимки не приняты как доказательство луча. Все точные тестовые Scripts/bindings
убраны до Stop/Save, Edit CameraFixed/Httpfalse/156Sources/5Lightingchildren.

Обычный Ctrl+S через computer-use в уникальном окне Children_of_corn_B.rbxl.
Сохранённый B1494881bytes/SHA256
`8160b71046a7c56a8a0c536ecfd3b9b9ca51a4e183c8f42cfb0b2458b81c837c`.
Strict verify-B-flashlight-tall-copy.py PASS/complete:true4526→4532instances:
ровно4Source edits+3default Modules+Folder+2Spots+LightingStyle.Soft→Realistic.
Все прежние identities/classes/names/parents/world/art/прочийLighting/mesh metadata/
rawTerrain точны; reindex0, только12компонентные конечные Camera.CFrame/Focus
могут отличаться. A1491821/bc85bd9b… и immutable B1485700/e34fe75f… независимо
перехэшированы и неизменны. Scene не сериализовалась Lune/Python/liveRojo.

Evidence: .artifacts/playtests/2026-10-20-B-flashlight-tall/ (native-before,
native-acceptance,native-field.jpg,pipeline-manifest,installer-fixtures,save-fixtures,
preservation,saved-scenes). Будущие B Source updates — только актуальный guarded
build/install-B-flashlight-tall, engine Save — verify-B-flashlight-tall-copy.py против
immutable B before-flashlight-tall. Старые153/155Source и A-only installers не применять.
