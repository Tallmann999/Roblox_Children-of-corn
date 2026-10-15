# Мультиплеер: проверка реализации — 2026-10-15

## Текущая приёмка PASS: настоящий сервер и четыре клиента

Полный сценарий завершён: **30проверок PASS за251.974942секунды**.
[Точный native отчёт](../.artifacts/playtests/2026-10-15-multiplayer-resume/native-final.json).
Клиенты настоящие, UserId−1..−4; сначала2, затем поздние3и4 подключены
последовательно. Финальный запуск использовал обычный3Dрендер.

- Общий ключ, ворота,120секунд и3NPC; личные20алмазов без сброса товарища
  и повторной награды. Настоящая первая поимка роняет ключ; revive сохраняет
  чужие попытки и NPC. Дальнейший abort носителя и смерть последнего
  участника завершают раунд без награды и убирают ключ.
- Поздние игроки ждут; их реальные start-запросы укладываются в наблюдаемые
  rate budgets, но не включают их в активный раунд. Три готовых не запускают
  четвёртого. Следующий общий раунд даёт четыре разных угла: все6пар разнесены.
- Настоящий LeaveTest/PlayerRemoving носителя оставляет3активных и ровно
  один доступный ключ. Другой игрок подбирает его, открывает общие ворота
  и получает личные20 (кошелёк20→40), пока остальные2продолжают. Их abort
  завершает cleanup без незаработанных алмазов.

После вторых ворот все3NPC имеют DetectionRadius96; оба крика сохранены:
100872584572146 и92691373477671, Linear20..1400, Looped=false. Это проверка
сохранённых свойств звуков, а не новое утверждение об audibility/миксе.

Использованы диагностические позиции, временные elevated anchors и реальные
engine InputHoldBegin/End с production remotes/LOS. Все anchors восстановлены.
Это не физический E, native UI-click, визуальный тест, слепой поиск или FPS.
1и3участника отдельно покрыты production adapter fixtures; новый полный
native запуск с одним участником не заявлен.

После теста удалены ровно3известных owned childless diagnostic узла.
Guarded installer repeat0created/0changed/77проектных+3Fog80Sources.
Stopped Edit/CameraFixed, Ground630×2×630/Field630×10×630, runtime/audio/
diagnostic/foreignSource names отсутствуют. FarmEnsure после reopen восстановил
40targets/applied40/built10; repeat0/0/pending0.
[Итог Studio](../.artifacts/playtests/2026-10-15-multiplayer-resume/studio-final.json).
Рабочий файл остаётся точным чистым b5084774… engine Save ниже;
новой сериализации/подмены сцены/Source-изменений после Save нет.
[Независимый финальный аудит](../.artifacts/playtests/2026-10-15-multiplayer-resume/final-state-audit.json)
и [строгая сохранность файла](../.artifacts/playtests/2026-10-15-multiplayer-resume/preservation.json)
PASS после завершения теста.

Перед коммитом точные байты установщика, двух pipeline Luau fixtures и frozen
multiplayer-resume evidence закреплены узкими `.gitattributes -text` правилами.
Иначе Git менял CRLF на LF при checkout и нарушал записанные raw SHA256;
игровые Sources и их обычная LF-нормализация не менялись.

## Сохранение после повторного входа и история диагностических повторов

Автор отменил прежнюю паузу, закрыл лишние окна, затем повторно вошёл в
Roblox/Studio и сохранил Children_of_corn. Проверенный Edit target после
перезапуска — `eb588c51-4726-41c4-b052-3a5f36b31d1d`.

Чистый engine Save18:06:02:1003371байт/SHA256
`b5084774be98e97a045c6b90a819bdd061b8d4f61b259c3a6e4eb77233ff2646`.
`clean-source-save-audit.json` и независимый `final-disk-audit.json` PASS:
77project+3Fog Sources/4162instances, только16существующих Source правок
и2Module additions; все исходные world/Lighting/art/identities/parents/rawTerrain
точны. Точная immutable `before-multiplayer-network-20261015.rbxl` совпадает
с этим сохранением; verifier baseline остаётся before-multiplayer-resume/b5ef.

Прерванное сохранение содержало только2owned diagnostic Scripts и1result
StringValue сверх ожидаемых экземпляров. Их точная forensic-копия с SHA256
b0881f9f… сохранена. Проверка всех production Sources, исходного мира и70raw
Terrain properties PASS; только эти3известных childless узла удалены перед
чистым авторским Save. Пустой прерванный `{ok:true}` не считается приёмкой.
[Forensic](../.artifacts/playtests/2026-10-15-multiplayer-resume/interrupted-save-forensic-audit.json),
[Terrain](../.artifacts/playtests/2026-10-15-multiplayer-resume/interrupted-save-raw-terrain-audit.json).

После входа настоящий2client запуск прошёл11проверок до revive. Ошибка late
join оказалась чтением старого count3 snapshot одного клиента, когда второй
уже получил count4; повтор обнаружил аналогичную начальную гонку count1/2.
Игровой код не менялся. Harness теперь ожидает согласованные membership,
roundID/remaining и terminal snapshots всех затронутых recipients; late sync
получает1.2s settling до попытки start. Неудачные отчёты сохранены:
[late join](../.artifacts/playtests/2026-10-15-multiplayer-resume/native-after-login-late-join-failure.json),
[startup](../.artifacts/playtests/2026-10-15-multiplayer-resume/native-startup-membership-race.json).
Эти запуски не считаются приёмкой; успешный полный повтор приведён выше.

Дополнительные неудачные попытки сохранены отдельно: потерян ACK late-action
([отчёт](../.artifacts/playtests/2026-10-15-multiplayer-resume/native-four-client-command-timeout.json)),
child metadata timeout до gameplay
([журнал](../.artifacts/playtests/2026-10-15-multiplayer-resume/metadata-startup-timeout.json)),
незапуск четвёртого клиента
([отчёт](../.artifacts/playtests/2026-10-15-multiplayer-resume/native-late-client-startup-timeout.json)).
Main Edit оставался авторизованным. Попытка отключить3D отклонена capability
RobloxScript; фактически рендер не отключался, вызов удалён из финального
harness. Последовательный AddPlayers(1) избегает одновременного старта двух
поздних окон; причинная связь прежних отказов с ресурсами не установлена.

Последующий key-recovery timeout
([отчёт](../.artifacts/playtests/2026-10-15-multiplayer-resume/native-sequential-key-recovery-timeout.json))
не сопровождается доказанной причиной. Финальный test-only setup держит A
припаркованным до его действия и отводит aborted B на10studs. Перед подбором
записаны реальные distance≈2.83/clear rays, recovery принят. Prospective ray
до отвода B в успешном повторе не попал в B: называть прежнее перекрытие
аватаром доказанным нельзя. Production Sources при этих повторах не менялись.

## История паузы после криков — отменена автором перед повторным входом

Автор попросил вернуться к тесту позже. Текущий код установлен в правильную
Children_of_corn, но сетевой сценарий ещё не принят и нового engine Save нет.
На диске остаётся проверенный solo baseline997184байт/SHA256
`b5ef0471325bbe5c9ab7178575753453cbf59afb15ed905eb12dfc70a4bbf6c8`.
Он сохранён точной immutable копией `before-multiplayer-resume-20261015.rbxl`;
старый `before-multiplayer-20261015.rbxl`493bc не перезаписан.

В src77Sources/сFog80:16существующих Source правок и2ModuleScript.
Согласованные48/96 и оба крика сохранены. TeamRound уведомляет RoundAudio
после создания обоих NPC и commit общего deadline; личный caught не
останавливает общий scheduler. `check.ps1`,20базовых текущих fixtures и
расширенный multiplayer-round PASS. Pipeline24installer/186unsafeDOM/
3Terrain/17promoter PASS; прежние promoter/foreignroot результаты явно
переиспользованы после изменения только нового Participant.
[Отчёты](../.artifacts/playtests/2026-10-15-multiplayer-resume/pipeline-fixtures.json).

Независимый review обнаружил гонку нового старта до удаления старого тела.
Исправлены только события Died/CharacterRemoving: завершать попытку может
персонаж текущего раунда. Точный архивный Source в памяти дал8/8expectedFAIL,
исправленный8/8PASS; текущая смерть/removal active/caught по-прежнему
завершает попытку и восстанавливает ключ.
[Регрессия](../.artifacts/playtests/2026-10-15-multiplayer-resume/corpse-retry-fixtures.json).

Первый direct native запуск2клиентов подтвердил личные HUD/team snapshots,
но первый start не перевёл ready=true. Пока не доказано, почему он отклонён;
startup sync/rate burst — гипотеза, не установленная причина.
[Результат](../.artifacts/playtests/2026-10-15-multiplayer-resume/native-first-ready-failure.json).
Harnеss получил read-only журнал фактических запросов и1.2сек settling.
Второй запуск не получил ни одного Player за120сек, audit пуст; gameplay
вообще не начался.
[Результат](../.artifacts/playtests/2026-10-15-multiplayer-resume/native-second-startup-failure.json).
Предшествующая async Edit попытка не дала принятого результата. Ни один
из этих запусков не считается успешной сетевой приёмкой.

Одновременно было7процессов Studio/~12ГБ working set; появилась ещё одна
Cooking Edit сцена. Это наблюдение не доказывает причину отказа подключения.
Соседние сцены не изменялись. Предложенный изолированный повтор автор отложил.
Все3точно owned временных тестовых объекта удалены. Последний правильный
Studio1712610d-6d4d-441b-99a7-3b0598e8a566 stoppedEdit/CameraFixed/runtimefalse,
80Sources, текущий installer repeat0changed/0created/77.

Продолжение только после сообщения автора: заново проверить Studio и новые
авторские правки, изолированно выполнить настоящий2→4client сценарий,
проверить ready/key/gate/личные20/revive/latejoin/реальныйdisconnect,
удалить owned harnesses, проверить Sources/Farm/camera, затем engine Save
и `verify-multiplayer-copy.py` против before-multiplayer-resume. Документация
[StudioTestService](https://create.roblox.com/docs/reference/engine/classes/StudioTestService)
описывает используемые реальные клиенты/AddPlayers/LeaveTest; наличие API
не заменяет успешный результат. Публикация/persistence/покупки не добавлялись.

## История первоначальной реализации до восстановления solo

Статус: **реализован в src, живой тест и сохранение ещё не приняты**.
Автор подтвердил1–4игрока, общий ключ, личные две поимки и20алмазов за личный
побег, следующий раунд после результатов всех и ожидание поздних подключений.
Правила и контракт: [спецификация](2026-10-15_multiplayer.md).

## Что проверено

`check.ps1` PASS после исправления всех session guards: StyLua, Selene0/0/0,
code-only Rojo build/sourcemap, safe mappings и выключенная persistence.
Selene не смог обновить API dump и использовал существующий кеш.

16 Luau fixtures PASS: audio-controller/assets/rules, rustle-continuous
client/server/UI, corn-appearance/backdrop/controller-quality/yellow-startup,
inventory-barrel-clearance, resize-layout и новые multiplayer round/hunt/audio/UI.
[Выводы](../.artifacts/playtests/2026-10-15-multiplayer/local-tests.json).
Round fixture выполняет production TeamRound/RoundParticipant и личные helpers,
проверяет гонки ключа/предметов, gate/deadline/3NPC, личные поимки/revive,
выпадение ключа, disconnect/death/abort, единственную награду, late join,
четыре разных старта, очередь пятого, rate limits и cleanup.
NPC/геометрия/аудиорендер там адаптированы, а не испытаны сетевым движком.

Дополнительно `client-startup.luau` прогнал полный production Bootstrap corpus
для solo_local и team_local; `multiplayer-session-gates.luau` —432комбинации
девяти production guards и42реальных вызова RoundService Init/Start. Оба PASS.
UI fixture отверг67malformed team payloads. Старые fixtures без team остаются
совместимыми там, где это явно проверено; это не утверждение о всех старых тестах.

## Первый настоящий сервер и найденная ошибка

Code-only installer в подтверждённой Children_of_corn поменял7Sources и
добавил2ModuleScript; мир/арт не записывал. StudioTestService создал настоящий
server с Player1/UserId−1 и Player2/UserId−2. Оба HUD не подтвердились за120сек;
тест завершился с FAIL до первого gameplay check.
[Точный результат](../.artifacts/playtests/2026-10-15-multiplayer/initial-client-startup-failure.json).

Причина: девять существующих client/farm/corn guards ещё требовали solo_local.
В src они исправлены на разрешение solo_local/team_local только в Studio DEV;
добавлены отдельные regression fixtures. Итоговый installer/verifier разрешает
16Source-дельт и2новых модуля, всего77проектных/80сFog,4162экземпляра после save.

## Прерванная установка исправления

Перед исправленной установкой readonly inspection обнаружил в прежнем Corn
окне GameShared/Game с DanceClip/RhythmConfig и серверный RhythmService:
game.Name=Roblox_Cooking_Shef_Music_Founder,22Sources, при сохранившемся CornMap630.
Запущен Rojo из другого Cooking проекта. Защищённый откат отказал на отсутствующем
CornAppearance до первой мутации. Неизвестные Sources не перезаписывались,
посторонний Rojo не останавливался; соседнее окно Cooking не изменялось.
[Данные](../.artifacts/playtests/2026-10-15-multiplayer/studio-target-block.json).

Рабочий RBXL и immutable before-multiplayer по-прежнему995988байт/hash493bc1f9…,
то есть сохранённая continuous-solo версия. Мультиплеер в файл ещё не сохранён.

## Как продолжить

1. Остановить постороннее Rojo-подключение. Если нужны чужие незаписанные
   изменения смешанного окна, сохранить их отдельно, не поверх Corn baseline.
2. Открыть `place/Children_of_corn.rbxl` заново; re-list Studio, проверить stopped
   Edit, CornMap630, native SHA всех78Sources и отсутствие постороннего кода.
3. После актуального check.ps1 собрать `build-multiplayer-installer.py --compact`,
   применить guarded `install-multiplayer.luau`; repeat должен дать0/0/77.
4. Повторить настоящие2клиента временными тестовыми harnesses вне code roots;
   проверить ready/key/gate/exit/retry/capture/revive/late join и cleanup.
   Prompt harness использует engine InputHoldBegin/End и реальные gameplay remotes,
   диагностические позиции; это не физический E и не обычный слепой раунд.
5. Удалить только точные owned test harnesses/result; восстановить Edit camera,
   FarmGeometry, Source equality и проверить отсутствие runtime.
6. Выполнить engine Save. `verify-multiplayer-copy.py` должен принять точный
   файл против immutable before-multiplayer; Lune-сериализация запрещена.

Публикация, persistence и покупки не добавляются. Blind round/страх/человеческий
микс/длительный3NPC FPS/баланс пенька/reopen и внешний Fire105538100476464
остаются открытыми отдельными пунктами.
