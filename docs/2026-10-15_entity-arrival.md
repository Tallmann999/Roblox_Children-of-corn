# Крики подкрепления и увеличенное обнаружение — 2026-10-15

Автор подтвердил увеличение обоих текущих радиусов втрое:16→48studs до ворот,
32→96studs после открытия. Финал по-прежнему создаёт два дополнительных пугала,
увеличивает обнаружение всех трёх вдвое от новой базы и длится120секунд.
LOS, скорости, две поимки, капканы и правила выхода этой правкой не меняются.

После успешного создания обеих дополнительных сущностей сервер один раз
сообщает аудиоконтроллеру об их появлении. Monster2 получает отдельный
пространственный одноразовый крик COC_Monster_01/100872584572146,
Monster3 — COC_Monster_02/92691373477671. Используются существующие импортированные
ассеты и профиль Awakening: громкость0.95, Effects, Linear rolloff20..1400,
чтобы крики были слышны с места открытия ворот. Новых preload ID/remotes нет.

Два выделенных Sound прикрепляются к настоящим серверным Root. Событие
принимается только от распознанных owned Monster2/3 текущего CornRoundRuntime,
каждый индекс допускает один старт за раунд. Обычный snapshot, выбор lead NPC,
Pause/Resume шелеста, повторные polls, revival или освобождение капкана не
переигрывают крики. Захват/завершение раунда очищает соответствующее аудио.
Неудачное создание подкрепления не вызывает криков. SoundId и курсоры
непрерывного шелеста остаются прежними.

Меняются только3существующих Source: Balance, SoloRound и RoundAudio.
Persistent instance count остаётся4160/78Sources; карта630, Lighting, арт,
исходные identities/parents и raw Terrain точные. Перед правкой сохранён
immutable `place/Children_of_corn.before-entity-arrival-20261015.rbxl`:
995988байт/SHA256493bc1f9b512d618d0a815b2197e3af854f775cd711b363db2906d8fbaf1fb68.
Code-only installer и отдельный exact engine save verifier допускают только
эти три Source-дельты, unknown edits/foreign code/open tabs отклоняются.

Текущая production-ветка вернулась к чистой solo версии после удаления
Cooking/Rhythm. Незавершённый multiplayer-код сохранён отдельно в
`.artifacts/wip/2026-10-15-multiplayer-src.zip` с проверенными хэшами; он не
устанавливается вместе с этой правкой и не считается прошедшим живую приёмку.

## Фактическая приёмка

`scripts/check.ps1` PASS: StyLua, Selene0/0/0, code-only Rojo build75,
safe mappings и persistence disabled. Selene использовал существующий API-кеш
после неудачного обновления. Все14 актуальных локальных fixtures PASS:
audio-controller/assets/rules, rustle-continuous client/server/UI,
corn-appearance/backdrop/controller-quality/yellow-startup,
inventory-barrel-clearance, resize-layout, entity-arrival-audio и entity-detection.
[Локальные результаты](../.artifacts/playtests/2026-10-15-entity-arrival/local-tests.json).
Arrival adapter проверил45 невалидных batch,11 foreign takeover и точное число
вызовов Play/отсутствие повторов; это отдельно от фактического воспроизведения.

Реальная Studio `1712610d-6d4d-441b-99a7-3b0598e8a566`, Children_of_corn:
guarded installer изменил3Source/создал0, повтор0/0. Native Start/Confirm,
E-ключ и E-ворота повторены в двух свежих раундах. Оба дополнительных NPC
появились, все3имеют DetectionRadius96. Диагностически перемещался игрок,
камера на3секунды наводилась на настоящий prompt; remote/prompt не подделывались.

Два read-only клиентских наблюдения приняли по одному Root-bound Sound
на Monster2/3. Оба действительно декодированы2.34/3.03сек, продвигают курсор,
имеют положительный PlaybackLoudness, Ended1/Stopped0 и не повторяются
12.030/12.016сек после первого появления. Во втором прогоне360samples/звук,
положительная громкость69/90samples, max91.259/94.492; во всех samples
сохраняются ожидаемыеURI/group/Linear20..1400/speed1/Loopedfalse.
[Первый клиентский отчёт](../.artifacts/playtests/2026-10-15-entity-arrival/live-client-first.json),
[повтор](../.artifacts/playtests/2026-10-15-entity-arrival/live-client-final.json).
Initial preload warnings не принимаются за итоговый отказ этих двух
звуков: позднее реальное воспроизведение подтверждено данными клиента.
Fire105538100476464 остаётся прежним внешним not-approved asset.

Серверный isolated engine fixture использует реальные MonsterHunt/Balance
и physics raycast:47.99chase/48.01patrol, у всех трёх95.99chase/96.01patrol,
реальное препятствие и защита блокируют обнаружение40. Scratch удалён;
saved map, рабочие NPC и игрок этой проверкой не менялись.
[Результат](../.artifacts/playtests/2026-10-15-entity-arrival/live-detection.json).
Native Alt/Leave удалил оба arrival Sound на сервере и клиенте; немедленная
серверная выборка ещё видела основного Monster, поэтому этот trace не
используется как доказательство полного удаления всех NPC.

Два серверных диагностических счётчика не приняты для подсчёта Play:
DescendantAdded подключился после синхронного Play (Ended1 подтверждён),
а временный `_sound` wrapper из MCP context не увидел production вызовов.
Причина второго предположительно связана с контекстом require; это не
установленный факт. Wrapper точно восстановлен по watchdog. Native client
initialPlaying/cursor/loudness/Ended/no-repeat принимаются, Played0 из
позднего listener не означает отсутствие звука и не доказывает число вызовов.
Production Sources ради этих наблюдателей не менялись.

Неблокирующее замечание независимого review: factory публикует Parent до
присвоения arrival RollOffMode=Linear. При синхронном постороннем ChildAdded
hook, который перехватил бы Sound прямо при создании, возможна эта одна
запись после takeover;11fixture guards относятся к последующему takeover.
В текущем solo runtime такого hook нет. Дополнительная защита этого узкого
случая не включалась в проверенную правку.

Pipeline fixtures PASS:20 installer refusals/rollback/repeat/CRLF,
76 unsafe DOM (включая20Camera)/3Terrain и16promoter guards.
[Отчёт](../.artifacts/playtests/2026-10-15-entity-arrival/pipeline-fixtures.json).
В конце stopped Edit:78Sources сверены installer native SHA256, foreign
Rhythm/Dance/Cooking Sources отсутствуют, CameraFixed, Ground630×2×630,
FieldZone630×10×630, runtime/owned runtime audio отсутствуют. Farm Ensure
восстановил40targets/10meshes, повтор40targets/applied0/built0/pending0.
[Сводка живой приёмки](../.artifacts/playtests/2026-10-15-entity-arrival/live-acceptance.json).

Автор Ctrl+S14:52:11 сохранил `place/Children_of_corn.rbxl`:997184байт,
SHA256`b5ef0471325bbe5c9ab7178575753453cbf59afb15ed905eb12dfc70a4bbf6c8`.
`verify-entity-arrival-copy.py` PASS против immutable before-entity-arrival:
4160→4160instances/75src+3Fog, ровно3Source изменения,0additions/deletions,
мир/Lighting/art/identities/parents/rawTerrain точные. Независимый SHA256 совпал.
[Строгий read-only аудит](../.artifacts/playtests/2026-10-15-entity-arrival/preservation.json).
Замена файла или ресериализация не выполнялись; будущие engine Save проверять
этим актуальным verifier, никогда не сериализовать сцену через Lune.
Это local solo acceptance;
обычный слепой раунд, human mix/fear, длительный3NPC FPS и multiplayer
остаются отдельными открытыми проверками.
