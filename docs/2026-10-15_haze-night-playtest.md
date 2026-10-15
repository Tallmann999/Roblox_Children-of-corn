# Дымка, группы предметов и только ночь — 15 октября 2026

Текущий MVP остаётся локальным solo PC. Единственная игровая среда — hard/ночь20:30,20алмазов за проверенный выход. Карточки easy/medium удалены; старые значения отвергаются сервером. Start/Retry сохраняют подтверждение цели перед запуском таймера. Дымка меняет существующий Atmosphere плавно, без прежнего Fog12→60 и удаления эффекта. Предметы/ключ/runtime пеньки/посещения используют пятнадцать перенесённых slot points у факелов; шесть парных факелов сараев сохранены. Автор отдельно подтвердил сохранение текущего Bloom.Intensity0.85/Size32.

## Настоящая Studio

Работа только в Children_of_corn, target23ea8e48-309b-41f3-8083-cef1a81600b2. Rojo live остановлен; соседние сцены не изменялись.

- Native Start→Confirm запускает hard. Карточек сложности нет. Native Retry→Confirm запускает следующий hard раунд, очищает visited, сохраняет session reward20.
- Двадцать forbidden start/retry payload проверены actual SoloRound без мировых/Lighting/character мутаций. Actual key/gate120once, три owned rigs, обнаружение31yes/33no и physical exit20once/menu cleanup PASS. Это изолированная server fixture; файл `night-server-fixture.json`.
- После диагностического перемещения к новым точкам настоящий E подобрал energy на пеньке у slot10, ключ у slot06, E открыл ворота; W вывел Root до Z428.54. Награда и session20, evacuation terminal cleanup PASS. Мини-карта отметила clearing10/06. Это не слепой поиск и не подъём на пенёк с земли.
- Runtime binding key/item/lookout к slot/torch дал XZerror≤0.0000061, key distance4, item/lookout5.38145 до факела. Все15 факелов сохраняют относительно slot смещение X0/Z4. World repeat изменяет0.
- После ручного Resume/foreground получены реальные GPU night-haze-on/off и new-cluster-stump. В окончательной Source установлен Modal=true только у дочерней кнопки закрытия панели. Native F6/Activated toggle off вернул Haze0.8, on плавно дал1.8; тестовые имена восстановлены. Нет записи FogStart/FogEnd/FogColor. Координатный MCP click смещался на58px; использован уникальный instance_path. Final production Source repeat меняет0.
- Fresh final Play: настоящий W1.6сек при Custom camera/walk12 дал19.8579studs. В предыдущем диагностическом Play после camera/fixture staging W не двигал персонажа, поэтому та попытка не принята. Новая сессия с обычной камерой работает без Source правок.

## Удвоенный шелест с полными хвостами

Период нового server cue уменьшен вдвое при прежних10Hz и проверках земли/движения/кукурузы. Остаток времени переносится максимум на0.1сек при непрерывном движении; пауза/дорога/прыжок/телепорт сбрасывает накопление. Два фиксированных локальных Sound на actor и newest pending1 сохраняют естественное окончание каждого начавшегося звука. Максимум8игроков+3NPC/22voices. Авторские IDs/gains/rolloff не менялись.

- Локальный actual-module scheduler: одинаковые12сек/120polls дают прежние18/current36 cues,2.000×. Pause/resume не создаёт burst; server Sound не перезапускается и не обрывается ради metadata cue. Четыре audio fixtures PASS.
- Actual client decoder fixture: все6авторских corn Sounds загрузились.40plays/40naturalEnded,0Stop, оба голоса реально перекрываются; TimePosition/PlaybackLoudness/full decoded duration PASS. Контрольные12.00076сек:36accepted/36started/36ended, по18наканал, прежняяформула18. Cleanup actor count0, оба localSounds удалены, source gain восстановлен. Это управляемые metadata на isolated actor, отдельно от движения. `rustle-client-decode.json`.
- Initial client fixture ошибочно проверял pending до deferred AttributeChanged; initial failure сохранён отдельно. Исправлены только ожидания/учёт callbacks и нулевая TimeLength в первом Played кадре. Production не менялась ради passing fixture.
- Production native W12сек: Root(180,17.398,200)→(195.256,17.398,89.806),17server cues/16localplays/16naturalEnded,0Stops/0activeURIcuts. Диагностически задана начальная позиция/одно направление камеры; NPC временно удерживался вдали32сек с восстановлением для изоляции звука. Остановка движения дала хвостам завершиться. `rustle-native-walk.json`.
- Отдельная scripted Humanoid.Move физическая ходьба144studs:22cues/20plays/20naturalEnded/0Stops/0URIcuts. Не считать её native input. Первый interrupted capture и второй stationary native attempts исключены из приёмки.

Случайная длина клипов, два занятых голоса и newest-only pending могут уменьшить число слышимых запусков относительно числа контактов. Удвоенный период/контрольная2×частота не обещают звук на каждом стебле. Fire105538100476464 остаётся прежней внешней недоступностью; к шести декодированным corn asset это не относится.

## Защита и сохранение

Локально PASS: check.ps1, hard-only lighting/HUD/intro fixtures, Fog latest-baseline/admin/finite/clamp/rate/cleanup/modal и≤10Hz/0settledwrites. Cluster installer:28fixedCF,25refusals, rollback1/14/28; Fog installer22refusals, exactknownpriorupgrade1/repeat0, original/prior rollback. Финальная Studio Edit equality75created0/changed0, asset3changed0, clusterchanged0, FarmEnsure40/applied0/built0/pending0, CameraTypeFixed, transient round runtime отсутствует.

Автор сохранил Ctrl+S в11:01:56. Strict read-only audit PASS:1028519байт, SHA256 `c7015e55a7cf4a020fe0ae1e3d40d4c69c17faf10a8f01d8ce4379066c955fed`,6844instances/78Sources. Все75code Sources равны src,3assetSources равны assets. Immutable before-haze-clusters a897bb52…/1019419байт не изменён. Только28фиксированных CF,5importedFog nodes,Source updates и2подтверждённых Bloomсвойства; остальные исходные identities/world/Lighting/art/Model pivots/rawTerrain точные.121DOMnegative/3Terrainnegative/16promoterguards PASS. Exact engine bytes, без promotion или scene reserialization. Артефакты `preservation.json` и `saved-scene.json`.

Остаются отдельными: blind поиск/обычная успешная игра без диагностических перемещений, человеческий микс/страх, длинная погоня трёх NPC/FPS, safe-perch баланс, повторный reopen. Старый статический EditorPreview/Overview не перестроен; runtime clearing positions актуальны.
