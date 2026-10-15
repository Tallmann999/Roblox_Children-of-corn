# Дети кукурузы — индекс фич

Новый этап15октября: автор выбрал **мультиплеер1–4собщимключом**. Реализация
TeamRound/RoundParticipant и локальные проверки готовы; исправленный живой
тест/сохранение ожидают восстановления чистого Studio после посторонней
подмены Sources. [Правила](2026-10-15_multiplayer.md),
[результаты и продолжение](2026-10-15_multiplayer-playtest.md).
Сохранённый checkpoint ниже пока остаётся solo; multiplayer не объявлен принятым.

Последний сохранённый итог15октября: **непрерывный второй шелест автоматически игроку и всем3монстрам**, без кнопок сравнения. Pause/Resume/полный11.064секцикл, спринт игрока×1.5, независимые spatialNPC5..65 и реальный trap pause проверены в Studio. [Приёмка](2026-10-15_continuous-rustle.md). Strict save995988байт/hash493bc1f9…/78Sources/4160instances:4Source-onlyизменения, весь630мир/Lighting/art/rawTerrain точные. Сводка и промпт: [handoff](2026-10-15_new-chat-prompt.txt). Реестр ниже описывает текущие правила; датированные вводные абзацы до реестра сохраняют историю прежних checkpoints.

История принятого поля до нового аудио: **630 × 630**, жёлтая кукуруза с первого появления; цвет земли сохранён. 2 энергетика/2 капкана/ключ и связанные с факелами15слотов сохранены. Исправлены капканы внутри трёх старых бочек. Native E обоих капканов/энергетиков/ключа, use24, gate120/3NPC, Wexit+20 и hardRetry PASS с диагностической постановкой. Strict save996617байт/SHA256489af64f…/78Sources/4160instances; [результаты](2026-10-15_resize-yellow.md). Следующее временное Alt-сравнение было завершено; MP3 импортирован и принят в итоговой версии выше.

История дымки и кластеров до уменьшения поля: только hard/ночь и20алмазов, без выбора сложности;78 Sources с адаптированным импортированным CornfieldFog. Ключ/предметы/runtime пеньки/посещения следуют пятнадцати группам полевых факелов; шесть факелов у сараев сохранены. Native E/item/key/gate/Wexit20 и hard retry PASS с диагностической постановкой; не blind round. Частый шелест controlled36vs18/12сек,40/40naturalEnds и native16/16,0Stops/URIcuts. **Strict engine save PASS**,1028519байт/SHA256 c7015e55… . [Итоговая приёмка](2026-10-15_haze-night-playtest.md), [контракт](2026-10-15_haze-clusters.md), [шелест](2026-10-15_rustle-cadence.md).

История finale 2026-10-15 до дымки и уменьшения: local solo PC, карта 840 × 840, 75 Sources. Установлены 13 Source правок и два дополнительных исправления: quantization guard неона и отдельное состояние анимации companions. Check PASS; финальная Source equality 75/0/0. Native E-ключ / E-ворота / W-выход приняты во всех режимах: +5 / +10 / +20, NPC удаляются. Диагностические перемещения и взгляд отделены от blind поиска. Настоящий held timeout — 120,004 секунды; regular client анимирует все три NPC. [Scope](2026-10-15_finale.md), [точные результаты и артефакты](2026-10-15_finale-playtest.md).

Пять сверчков прошли реальные decode/fades/Ended без Stop, физический неон — 160 samples и bright GPU без projected HUD. Torch V2 установлена: 54 Part CFrames, повтор 0, 25 ground overlap queries с Props/gate дали 0; пары у West показаны на GPU, остальные два дома подтверждены точными offsets через guards. Foreground A/B завершён условно на Automatic: fixed Quality10 недоступен. Замер был до последнего исправления анимации и до gateOpen с одним NPC; он не доказывает FPS трёх активных пугал или запас GPU. Soft и исходные shadow properties восстановлены; постоянная смена Lighting не рекомендована по этому тесту.

Исторический авторский save finale проверен: 1019419 байт, hash `a897bb52fa85505090f973e910139915e6ebb2995e44915c31ecbc2b5c511dca`, 75 Sources / 6839 instances, 54 фиксированных CFrame и три точных аудированных служебных дополнения. Дымка/кластеры ещё не входили в этот checkpoint. Отдельно остаются общие исследования MVP: blind поиск 7–10 минут, обычные повторные раунды, страх/микс, safe perch и длительный маршрут с тремя NPC. Core_round остаётся in_progress.

`MVP` — обязательная часть первого полного игрового цикла. `P1` — следующий этап после проверки MVP. `P2` — отложенные расширения. Приоритеты не являются обещанием сроков. Владелец дизайн-решений всех фич — автор проекта; исполнители и сроки — TBD.

## Текущий реестр — 2026-10-15

Общий сохранённый checkpoint реестра:995988байт/SHA256 `493bc1f9b512d618d0a815b2197e3af854f775cd711b363db2906d8fbaf1fb68`,78Sources=75проектных+3Fog/4160instances. Ссылки на прежние fixtures сохраняют дату и пределы своей приёмки; сохранение текущих Sources не означает повтор всех исторических игровых тестов. Local solo PC, только hard; blind full round/страх/микс/длительный3NPC FPS/safe-perch/reopen остаются открытыми, multiplayer не принят.

| feature_id | feature_name | brief | player_value | priority | depends_on | distribution | status | owner | spec_doc |
|---|---|---|---|---|---|---|---|---|---|
| handheld_items | Предметы в руках | Выбранный ключ/банка/капкан, однократные жесты принятого use | Видеть выбранный предмет и его применение | P1 | inventory_consumables, first_person_movement, scarecrow_presentation | all | tested (Studio; saved) | Автор проекта | [контракт и проверки](2026-10-12_handheld-playtest.md) |
| scarecrow_presentation | Движения и сцена поимки | Три рига, 27 writes / 30 Hz / 0 Root; capture 13 local Parts, рот/краска, скрытие 27 деталей | Видимая угроза | P1 | scarecrow_hunt, second_chance | all | tested: actual regular client,8изменённых деталей у каждого из3 в finale; current save493bc1f9…; reopen отдельно | Автор проекта | [контракт](2026-10-15_finale.md), [проверки](2026-10-15_finale-playtest.md) |
| inventory_consumables | Инвентарь и расходники | Пять слотов,2энергетика×2/30сек,2капканаNPC10сек,ключ | Дополнительные способы уйти от охоты | P1 | key_and_escape, scarecrow_hunt | all | tested (Studio; saved) | Автор проекта | [контракт](2026-10-12_inventory.md) |
| core_round | Основной игровой цикл | Случайный угловой старт, поиск, охота, исход и новый раунд | Полное повторяемое прохождение | MVP | cornfield_map, first_person_movement, key_and_escape, scarecrow_hunt, sound_and_atmosphere, second_chance, round_ui_restart, session_diamonds | all | in_progress | Автор проекта; исполнитель TBD | [docs/2026-10-09_core-loop_gd-spec.md](2026-10-09_core-loop_gd-spec.md) |
| cornfield_map | Кукурузное поле и просветы | 630 × 630, 4 угла, 15 просветов, жёлтая кукуруза с первого появления, backdrop/LOD, ферма и27факелов | Ориентиры поля | MVP | — | all | tested: guarded resize/yellow, item clearance/native E/retry; saved493bc1f9…; reopen/FPS отдельно | Автор проекта | [мир и результаты](2026-10-15_resize-yellow.md) |
| first_person_movement | Первое лицо и передвижение | Ходьба, прыжок, первое лицо, серверная выносливость и шкала | Ограниченный обзор и решение, когда тратить спринт | MVP | — | all | tested (Studio; saved) | Автор проекта; исполнитель TBD | [спецификация движения](2026-10-10_first-person-movement_gd-spec.md) |
| key_and_escape | Ключ и ворота | Один ключ, серверный gateOpen, 120 секунд и физический ExitZone | Ясная цель и победа | MVP | cornfield_map, first_person_movement | all | tested: native hard E/E/Wexit+20 на630 с диагностической постановкой; saved493bc1f9…; blind/reopen отдельно | Автор проекта | [финал](2026-10-15_finale.md), [текущая приёмка](2026-10-15_resize-yellow.md) |
| scarecrow_hunt | Охота пугал | До ворот 1 NPC / 16 LOS, после 3 / 32; первая особая погоня 10 секунд, loss 42/1,25 | Усиление угрозы у выхода | MVP | cornfield_map, first_person_movement | all | tested: server3NPC/captor/revive + actual3animations в finale,3NPC/trap audio в continuous; current save493bc1f9…; reopen отдельно | Автор проекта | [первая погоня](2026-10-14_first-chase.md), [финал](2026-10-15_finale.md) |
| sound_and_atmosphere | Звук и атмосфера | Автоматический continuous138698164682825: owner2D+до10spatial loops, independent Pause/Resume; nearest Hunt,5cricket | Слышать угрозу и окружение | MVP | cornfield_map | all | tested: native owner и3NPC/trap/wrap/cleanup; saved493bc1f9…; human mix/FPS/reopen/multiplayer отдельно, Fire external | Автор проекта/Codex | [итоговый шелест](2026-10-15_continuous-rustle.md), [прежние остальные звуки](2026-10-15_finale-playtest.md) |
| second_chance | Дополнительная попытка | Первая ждёт revive/menu, все 3 ResetHome, deadline идёт; вторая — поражение/retry | Исправить ошибку с потерей времени | MVP | key_and_escape, scarecrow_hunt | all | tested: server hold/revive,real120-second timeout и native choices прежних этапов; current save493bc1f9…; reopen отдельно | Автор проекта | [выбор](2026-10-14_capture-choices.md), [финал](2026-10-15_finale-playtest.md) |
| round_ui_restart | Подсказки, результат и повтор | Objective/Confirm/Back, capture choices, серверный MM:SS HUD; без выбора сложности | Понятная цель и время | MVP | first_person_movement, key_and_escape, second_chance | all | tested: прежние intro/HUD,native hard retry на630 и Start/Confirm/AltLeaveRound в continuous; saved493bc1f9…; reopen отдельно | Автор проекта | [контракт](2026-10-15_finale.md), [текущая приёмка](2026-10-15_continuous-rustle.md) |
| exit_beacon | Физический неоновый выход | Size ×3 / PPS 16 / AOT false; цветовой цикл 14,3 секунды, без projected слова | Физический ориентир | P1 (по запросу автора) | cornfield_map, key_and_escape | all | tested: quantization fix,160production samples/bright GPU/no overlay в finale; current save493bc1f9…; reopen отдельно | Автор проекта | [контракт](2026-10-15_finale.md), [приёмка](2026-10-15_finale-playtest.md) |
| lighting_modes | Ночной режим | Только hard/ночь20:30; прежний выбор easy/medium удалён из UI и server whitelist | Единая видимость поля | MVP | round_ui_restart, cornfield_map | all | tested:20invalid-mode guards/native hard retry; saved493bc1f9…; прежние3режима исторические | Автор проекта | [текущий контракт](2026-10-15_haze-clusters.md), [приёмка](2026-10-15_haze-night-playtest.md) |
| minimap | Мини-карта | Справа сверху стрелка; крестики посещённых просветов/домов, красные черепа, большая карта по нажатию | Помнить проверенные места и направление | P1 (реализовано по запросу автора) | cornfield_map, first_person_movement, second_chance, round_ui_restart | all | tested (Studio; saved; Esc/M подтверждены автором) | Автор проекта | [мини-карта](2026-10-10_minimap_gd-spec.md) |
| session_diamonds | Тестовая награда | Побег hard:+20 один раз, сессионный баланс; persistence отсутствует | Награда за победу | MVP | key_and_escape, lighting_modes | all | tested: server reward20once/native Wexit+20 на630; saved493bc1f9…; blind/reopen отдельно | Автор проекта | [награды](2026-10-15_finale.md), [текущая приёмка](2026-10-15_resize-yellow.md) |
| evacuation_finale | Двухминутный финал | gateOpen → 120 секунд / 3 NPC; timeout перед capture/exit, время идёт при caught | Давление времени | MVP (по запросу автора) | key_and_escape, scarecrow_hunt, round_ui_restart | all | tested: real120,004-second held expiry в finale,native hard gate/3NPC на630; saved493bc1f9…; reopen отдельно | Автор проекта | [контракт](2026-10-15_finale.md), [результаты timeout](2026-10-15_finale-playtest.md), [поле630](2026-10-15_resize-yellow.md) |
| torch_scatter | Асимметричные факелы | Существующие27:2wall/19scatter/6barn pairs,15torch-linkedслотов; размеры и яркость прежние | Менее регулярные ориентиры | P1 (по запросу автора) | cornfield_map | all | tested: исторический Torch V2,затем guarded clusters/resize630/сохранение barn pairs; saved493bc1f9…; reopen отдельно | Автор проекта | [scope](2026-10-15_haze-clusters.md), [текущая приёмка](2026-10-15_resize-yellow.md) |
| multi_spawn_competition | Соревнование нескольких игроков | До 4 стартов, чужой шелест, правила ключей, побегов и победителей | Неопределённость «игрок или монстр» и гонка за выходом | P1 | core_round; отдельные сетевые правила и проверка синхронных действий TBD | all | planned | Автор проекта; исполнитель TBD | TBD |
| lobby_party_modes | Лобби и формирование группы | Варианты один / три / четыре / с друзьями; состав режимов TBD | Выбрать способ игры и собрать участников | P1 | core_round, multi_spawn_competition; групповой вход TBD | all | planned | Автор проекта; исполнитель TBD | TBD |
| persistent_progress | Постоянный прогресс | Сохранение алмазов между игровыми сессиями | Долгосрочная ценность побед | P1 | session_diamonds; правила опубликованной экономики TBD | f2p | planned | Автор проекта; исполнитель TBD | TBD |
| diamond_shop | Магазин за алмазы | Каталог, цены, покупка и правила использования предметов | Потратить накопленные алмазы | P1 | persistent_progress; хотя бы один отдельно согласованный предмет | f2p | planned | Автор проекта; исполнитель TBD | TBD |
| robux_shop | Необязательные покупки за Robux | Предложение платных товаров и правила получения | Дополнительный выбор в бесплатной игре | P2 | persistent_progress; модель товаров и платежей TBD | f2p | planned | Автор проекта; исполнитель TBD | TBD |
| scan_radar | Сканер или радар | Временно помогает искать; различие вариантов TBD | Дополнительная информация в поле | P2 | core_round; способ получения и влияние на соревнование TBD | all | planned | Автор проекта; исполнитель TBD | TBD |
| night_vision | Ночное видение | Альтернативная читаемость окружения; длительность TBD | Лучше видеть в полумраке | P2 | core_round, sound_and_atmosphere; способ получения TBD | all | planned | Автор проекта; исполнитель TBD | TBD |
| timed_xray | Рентген на 10 секунд | Временный специальный обзор; объекты видимости и перезарядка TBD | Краткое преимущество в поиске | P2 | core_round; способ получения и баланс TBD | all | planned | Автор проекта; исполнитель TBD | TBD |
| extra_maps_content | Новые карты и декор | Дополнительные поля, фонари, кристаллы и вариации | Разнообразие после проверки одной карты | P2 | core_round; контентный план TBD | all | planned | Автор проекта; исполнитель TBD | TBD |


## Зависимости и порядок будущей разработки

1. На сохранённом поле630 остаются2576overview/904preview растений с сухим атласом; исходный арт сохранён. Runtime CornBackdrop с шагом6/Automatic/без теней и жёлтое первое появление проверены; длительный FPS текущего поля отдельно.
2. Текущий финал120секунд/3NPC и hard-награда20 прошли native E/E/W на630 с диагностической постановкой. Исторические проверки прежних3режимов/5–10–20 и real held timeout120,004секунды сохранены в finale-отчёте; blind поиск отдельно.
3. Первое лицо и спринт проверены: расход 4.003 с, восстановление 6.046 с, шкала/Alt/прыжок/повтор. Калибровка обзора с бочки и разных аватаров позже.
4. Серверный captor frame / ResetHome всех трёх / deadline при caught и actual regular client анимация трёх NPC приняты. Обычный самостоятельный раунд остаётся общей приёмкой MVP.
5. Fades/физический неон/Torch V2 имеют историческую приёмку; непрерывный шелест принят для owner/3NPC в текущей версии. Exact engine save/preservation493bc1f9… PASS. Reopen, blind поиск7–10минут, страх/микс, safe perch и длительный FPS с3NPC остаются открытыми; прежний foreground A/B не заменяет их, Fire external.
6. После успешного MVP отдельно определить мультиплеерные правила, лобби/группы и постоянную экономику.

`core_round` — интеграционная фича, объединяющая восемь небольших составляющих MVP. Подфичи не зависят от неё обратно, чтобы карта зависимостей оставалась однозначной. Магазин допускается только после выбора хотя бы одного товара; наличие валюты не требует добавлять гаджеты в MVP.

## Три наиболее рискованные фичи

| Фича | Почему риск существенен | Что проверяем до расширения |
|---|---|---|
| cornfield_map | Густота/новые позиции факелов и тени могут закрыть ориентиры или перегрузить сцену | Проходимость, клиренсы, GPU/foreground frame times и текущий обычный маршрут |
| scarecrow_hunt | Три NPC и120сек могут сделать финал неизбежным либо безопасный пенёк обесценит угрозу | Выполнимый native финал, уход/защита/таймер при revive и баланс высокого места |
| multi_spawn_competition | Состязание зависит от спорных правил общего ключа и награды | До реализации выбрать победителей, продолжение после побега и одновременный подбор |

## Решения, отложенные до соответствующей фичи

- Полный состав режимов лобби; «с друзьями» пока описывает способ собрать группу.
- Один общий ключ, несколько ключей или новый ключ после каждого побега.
- Кто получает 10 алмазов в мультиплеере и какие награды получают остальные.
- Цены, ассортимент, повторное использование и условия получения гаджетов.
- Требования к постоянному прогрессу, онлайн-проверкам и публикации.
- Поддержка телефона и других устройств; точные сроки всех P1/P2-фич.

Текущая сохранённая версия15октября содержит78Sources=75проектных+3Fog/4160instances, поле630/hard20 и автоматический непрерывный шелест. Последний exact engine save/preservation PASS:995988байт/hash493bc1f9…; [итог](2026-10-15_continuous-rustle.md). Reopen, blind round/страх/микс/safe-perch/длительный3NPC FPS и multiplayer не приняты. Следующие датированные обновления сохраняют историю.


## Обновление2026-10-12

Фермерский этап установлен, проверен в Studio и сохранён: [actual tests/save](2026-10-12_farm-playtest.md). Дорога/Truck/Barn03/шины/мусор,31 факел/неон выхода/STOP, реальные mode photos, cyan arrow/blue gate, сухая кукуруза и hard-only ветер. EditableMesh local reconstruction в Play; Edit restore после reopen отдельной командой. Итог60Sources. Открыты: повторный reopen, окончательный вид после Farm01A texture correction, обычный успешный побег/страх/поиск и новый FPS после farm additions. Звуки ожидают ассеты автора.

## Инвентарь и отмена общего ветра —2026-10-12

[Инвентарь](2026-10-12_inventory.md) установлен и сохранён; [проверки](2026-10-12_inventory-playtest.md):5слотов,2энергетика/2капкана/ключ, ×2скорость30сек/задержкаNPC10сек,27полутусклыхфакелов и4выходных poles. Общее hard покачивание отменено: максимум2стебля возле игрока+2возле монстра.65Sources, source equality и exact world/rawTerrain preservation PASS. Исторические31факел/hard-onlywind выше относятся к фермерскому этапу до этого обновления.

Автор подтвердил ручные1–5 и отсутствие сильных лагов в hard после отмены общего ветра.

## Движения чучела —2026-10-12

[Фича проверена и сохранена](2026-10-12_scarecrow-playtest.md):69Sources,9visualParts/30Hz без Rootwrites; обе реальные поимки1sec и камера восстановлены. Nightface QA исправлен локальным4studoffset. Все world/Lighting/art/rawTerrain exact. Звуки позже; обычный fullround/страх/длительныйFPS остаются отдельнойприёмкой.


## Предметы в руках — 2026-10-12

[Версия 71 установлена, проверена и сохранена](2026-10-12_handheld-playtest.md): локальный выбранный предмет, питьё 0.9 секунды / установка 0.55 секунды, однократный серверный use.id. Server/client fixtures PASS; реальные E энергетика, капкана и пассивного ключа/ворот, walking exit и +10 подтверждены с диагностическими перемещениями. Ночная читаемость исправлена этикеткой без мировых источников света; финальные E/M, GPU, check/reinstall и Source equality PASS. Сохранённый файл: 71 Source, 999458 байт, SHA-256 `681f433cd71240e0d682f829649f5ff0ae36ec9ea1892ee4aefcbbb23088fa6a`; весь мир/Lighting/art/raw Terrain точные, backup69 сохранён. Самостоятельный поиск, страх и длительный FPS остаются отдельной приёмкой; звуки ждут ассетов автора.


## Звуки —2026-10-13

Историческая сохранённая аудиоверсия: [реальные тесты](2026-10-13_audio-playtest.md),75Sources,4новых Modules; server/client/footsteps fixtures и local tests PASS. Настоящий E проигрывает energy/trap после серверного use; рабочие Sound.TimePosition/PlaybackLoudness подтвердили фон2/Hunt/все3голоса/оба corn actors/близких сверчков. Пять15/15 точек наблюдались120секунд. Погоня серверной цели плавно затихает при уходе; поимка и terminal очищают звуки. Шелест около0.513сек между клипами, на остановке/дороге тихо; штатные Running/Climbing Volume0.14из15 ассетов декодируются, Fire105538100476464 отвечает not approved for requester. Source equality75/0changed PASS; точный engine save1007172байт/SHA-256 `4ee103b95110e2a2a1a691d58a7bb5cdc34d0dc466d3c5265b47eb5823986546` прошёл строгую проверку75Sources/4Modules/exact world/Lighting/art/rawTerrain; immutablebackup71 сохранён. Полный хоррор core_round остаётся in_progress.


## История реакции на монстра —2026-10-13

[Контракт](2026-10-13_hunt-readability.md), [проверки](2026-10-13_readability-playtest.md).75Sources,12Source правок,0новых постоянных объектов. Радиус16/LOS, задержка2сек, рост×1.3, цель до подтверждения start/retry, отсчёт5→1, пробуждение20сек и пеньки8со ступенями проверены в engine и живом вводе. Сохранение автора Ctrl+S и строгий audit PASS:1009332байт/hash`ef0731f3235a26e4aa76dd26a7853be4d67e9ccc934f4f054428e5cbd6d146f0`. В том сеансе все15ID получили Unauthorized; это историческая регрессия, а не текущий статус.14октября повторный decoder дал14/15, только Fire failed, без изменения ассетов/permissions/reimport/publishing.
