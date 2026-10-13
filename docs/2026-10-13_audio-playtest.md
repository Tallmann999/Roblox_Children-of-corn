# Звуки: проверка 2026-10-13

Звуковая фича установлена в правильной Children_of_corn и прошла перечисленные ниже engine fixtures и живые проверки. **Финальная версия сохранена точными engine bytes; строгий аудит PASS.** Из 15 авторских ассетов декодируются 14; Fire остаётся недоступен. [Контракт и scope](2026-10-13_audio.md). Только локальный solo PC прототип, Studio `28de7d0d-d3bd-4063-9fe7-5d5b2beacfce`; Rojo остановлен, соседние сцены не менялись.

## Установленная версия

В src/build и открытой Studio установлены **75 Sources**. Четыре новых ModuleScripts: AudioRules, AudioAssets, RoundAudio и AudioController. Геометрия, Lighting, импортированный арт и Terrain не входят в звуковую правку. Пространственные проигрыватели, пять невидимых cricket emitters и SoundGroups создаются только в runtime; постоянных Sound templates или новых объектов карты нет.

Фон — выбранный автором Fon2. Открывание банки и питьё находятся в одном файле, отдельного второго клипа нет. Музыка Enemy Hunt и звуки успешного использования предмета создаются локально. Музыка требует personal active/chase snapshot и совпадения серверного ChaseTargetUserId. Мировые corn rustle, голоса NPC, сверчки и fire запускает сервер без новых клиентских запросов или координат. Для будущих настроек громкости предусмотрены Music/Ambience/Effects SoundGroups; меню настроек этой правкой не добавлено.

По последнему уточнению автора шелест при ходьбе учащён: новый клип начинается через `min(0.45 секунды, длительность клипа)` без дополнительной случайной паузы. При длинном клипе предыдущий Sound останавливается перед сменой URI, один актёр не наслаивает свои клипы. Сервер опрашивает движение раз в 0.1 секунды, поэтому фактический запуск квантуется этим опросом и временем кадра; это не обещание точного интервала 0.45 секунды в renderer.

Штатные Running/Climbing с `rbxasset://sounds/action_footsteps_plastic.mp3` подавляются на клиенте, в том числе после respawn. Штатный скрипт и объекты не удаляются; прыжок, смерть и собственный corn rustle сохраняются. Последний code-only repeat `install-frequent-rustle.request.json.result.json`: `created=0`, `changed=3`, `sources=75` — изменены AudioRules, RoundAudio и AudioController.

## Настоящие ассеты: 14 из 15

`reimport-assets-recheck.request.json.result.json` и итоговый `final-assets-loaded.request.json.result.json` проверили настоящие `Sound.IsLoaded` и `TimeLength` для всех 15 IDs. Итог: `loaded_count=14`, `missing=["COC_Fire"]`, `passed=false`, cleanup=true. После повторного импорта COC_Corn_02 уже загружен, длительность около 0.8524 секунды. Все шесть corn clips, три Monster Spider, фон, Hunt, energy, trap и crickets декодируются.

**Fire не принят как звучащий.** ID `105538100476464` установлен на 27 распознанных факелах, но у Sound `IsLoaded=false`, `TimeLength=0`; production observer также показал `maxPosition=0` и `maxLoudness=0`. Запрос Play/IsPlaying у недоступного ассета не доказывает воспроизведение. Нужны доступный Roblox asset/одобрение и повторная реальная проверка после этого. Подготовленный файл и привязка сохраняются, другой звук вместо авторского Fire не подставлялся.

Ранний `all-assets-status` давал 13/15, а `all-assets-client-loaded` остановился на незагруженном Fire. Эти запуски не объявляются PASS; актуальный результат повторной проверки — 14/15. Громкости и категории заданы в AudioRules, файлы и измерения подготовки записаны в `assets/audio/prepared-manifest.json`. Подбор значений не заменяет оценку микса человеком на его колонках или наушниках.

## Серверный engine fixture — PASS

`tests/studio-round-audio.luau`, финальный артефакт `server-engine-final.request.json.result.json`: `isError=false`, все проверки true. Fixture использует настоящие Parts, Sounds и raycast в изолированном повёрнутом мире, но контролируемые логические часы Step; это проверка расписания и authority, отдельно от слышимого воспроизведения.

- Созданы пять anchored invisible/noncollision/nonquery emitters и Sound только под 27 owned факелами. Чужой факел и авторский Sound сохраняются.
- Сверчки соблюдают границы 15 секунд включено / 15 секунд выключено со сдвигом старта между точками. Easy выключает fire, medium/hard запрашивают его.
- Три голоса идут перемешанными тройками без одновременного наложения и повторения на границе; паузы после окончания голоса в диапазоне 4–7.5 секунды. Начало chase задерживает первый голос на 0.4 секунды.
- Trapped и caught прекращают голоса и NPC rustle немедленно, в том числе между опросами движения. Ambience при caught сохраняется.
- Перемещение NPC внутри кукурузы запускает шелест; неподвижность, телепорт, дорога, сарай, просвет, выход за поле и воздушное положение его не запускают. Exclusions читаются при создании раунда, обход растений на каждый кадр отсутствует.
- Учащённая cadence `min(interval,duration)` проверена без дополнительной паузы и наложения старого клипа.
- Смена NPC удаляет старые проигрыватели. Terminal/Stop/Destroy очищают owned runtime идемпотентно, чужой вставленный дочерний объект сохраняется.

Fixture проверяет AudioRequestedPlaying как намерение сервера. Его PASS не подтверждает слышимость Fire, multiplayer или человеческий микс.

## Клиентский engine fixture — PASS

`tests/studio-audio-controller.luau`, `client-engine-final.request.json.result.json`: `isError=false`, cleanup=true. Реальные SoundService SoundGroups/Sounds и четыре доступных личных ассета загрузились; их TimePosition продвигался:

| Звук | TimeLength, секунд | Зафиксированный TimePosition, секунд |
|---|---:|---:|
| Фон2 | 61.8840 | 0.171 |
| Hunt | 90 | 0.171 |
| Energy | 1.3061 | 0.149 |
| Trap | 0.5486 | 0.128 |

Проверены initial sync без исторического use, плавное начало фона и Hunt, спад/Stop при смене цели, тишина для далёкой цели, однократные energy/trap по принятому use.id, дубликаты и старые ids, немедленная остановка Hunt/предметов при caught, terminal, retry и Clear. Камера и WalkSpeed не изменились, connections и owned папка fixture очищены.

Цель в этом fixture — отдельный тестовый Model с контролируемым attribute; это не подделка обнаружения в рабочем NPC. Предыдущий клиентский запуск до восстановления загрузки не проходил; `client-engine-fixture-recovered` и финальный `client-engine-final` прошли после исправления восстановления Sound, который загрузился после transient preload failure.

## Штатные шаги: engine fixture и рабочий персонаж — PASS

`tests/studio-audio-footsteps.luau`, `footsteps-engine-final.request.json.result.json`: все проверки true. Настоящие события Model/Part/Sound подтверждают existing/late/respawn binding, повторные изменения штатных SoundId/Volume, возврат при cleanup и сохранение изменённой автором identity. Jump, death, corn и посторонний duplicate не затронуты; fixture и connections удалены.

Финальный production observer отдельно зафиксировал у рабочего персонажа Running и Climbing с исходным штатным URI и `Volume=0`. Изолированная проверка respawn не означает проведённый multiplayer playtest.

## Живой production observer: 120 секунд — PASS в указанном scope

`production-observer-final.request.json.result.json` завершён (`done=true`, длительность около 119.98 секунды). Ограниченный наблюдатель считывал настоящие проигрыватели рабочего раунда и их IsLoaded/IsPlaying/TimePosition/PlaybackLoudness; SoundId, громкости и состояние игры он не задавал.

| Источник | Максимальный TimePosition, секунд | PlaybackLoudness |
|---|---:|---|
| Фон2 | 61.845 | >0 |
| Реальный energy | 1.259 | >0 |
| Реальный trap | 0.427 | >0 |
| Личная Hunt | 1.835 | >0 |
| NPC Monster Spider01 | 1.661 | >0 |
| Движение NPC через кукурузу | 0.8328 | >0 |

Все три голоса декодируются; в этом живом окне фактически звучал Spider01, а чередование всей тройки отдельно проверяет серверный fixture. Одновременных NPC voices наблюдалось не больше одного.

Рабочий NPC прошёл `dormant → patrol → chase → capturing → patrol`. В chase цель имела настоящий UserId `11644801627`; при capturing и последующем patrol target стал 0. Capturing наступил примерно на 75.55 секунде наблюдения, возврат patrol — на 76.60. Hunt действительно запустилась во время погони и прекратилась при поимке. Это настоящий серверный catch, а не локальная смена атрибута fixture.

Пять реальных cricket Sounds загрузились и показали продвижение TimePosition примерно до 14.93–14.97 секунды. Их переходы за окно наблюдения дают полные интервалы звучания около 14.88–15.13 секунды и тишины около 14.87–15.13 секунды; первые/последние неполные отрезки не использованы для этой оценки. Разброс связан с дискретным наблюдением. У близких emitters PlaybackLoudness >0; у далёких мог быть 0 вследствие пространственной дальности. Это подтверждает цикл пяти источников, не слышимость всех пяти одновременно в одной точке.

Подбор и использование предметов производились настоящим E. Перед взаимодействиями применялись диагностические перемещения и временное направление взгляда на pickup; observer подтвердил реальные короткие energy/trap клипы после accepted use. `real-energy-use-passed` дополнительно содержит WalkSpeed=24, timer=true и штатные footsteps Volume=0. Более поздние команды статуса могли видеть уже окончившийся эффект или результат поимки; их одиночный `playing=false` не заменяет временную запись observer.

Ранний неограниченный observer превысил лимит StringValue 200000 символов и не дал пригодный итоговый отчёт. Он не считается PASS. Финальная ограниченная запись завершилась и читается целиком.

## Живая ходьба, потеря погони и terminal — PASS

`real-walking-corn-road` использует настоящий Humanoid.MoveTo после диагностического перемещения. При ходьбе внутри кукурузы сервер менял corn clips и запрашивал их воспроизведение; на дороге `roadRequested=false`. Эта запись содержит намерение сервера, а не полную клиентскую TimePosition/Loudness запись шагов. Её одиночное `stationaryRequested=true` не принимается как проверка тишины после полной остановки; stationary отдельно проверен engine fixture.

`real-chase-and-loss-final` зафиксировал реальную серверную погоню с target=UserId игрока и последующий `patrol`, `targetAfter=0` после диагностического ухода от NPC. Эти действия после первого observer отдельно записаны новым production observer; snapshot `production-followup-observer.request.json.result.json` снят примерно на 14.47 секунде, а `production-followup-terminal` — на 110.11. У этих промежуточных snapshots `done=false`; они используются для конкретных уже записанных событий, не объявляются полными 120-секундными замерами.

Рабочий игрок двигался обычным Humanoid.MoveTo после диагностического перемещения. Настоящий клиентский corn Sound сделал шесть записанных стартов на 2.2168, 2.6830, 3.2331, 3.7658, 4.2165 и 4.7826 секунде; средний интервал около 0.513 секунды соответствует cadence 0.45 с учётом серверного опроса. TimePosition достиг 0.726, PlaybackLoudness — около 116.99. `real-player-corn-cadence-final` подтверждает `actual_walk=true`, WalkSpeed=12 и `stationaryRequested=false` после полной остановки с ожиданием; roadRequested=false уже записан отдельно. Это реальное воспроизведение шелеста персонажа, а не только server intent.

При реальной потере погони Hunt набрала Volume примерно 0.30875 к 9.033 секунде записи, затем плавно снижалась до 0 и `IsPlaying=false` на 11.416. Сервер перешёл из chase около 7.534 секунды в patrol около 10.317, target `11644801627 → 0`. В начале затухания distance уже снижал цель громкости; музыка продолжила плавно затухать после выхода из chase. Её TimePosition продвинулся до 3.556 и PlaybackLoudness был >0. Этот production trace подтверждает fade-out/Stop на настоящих проигрывателях; постоянная громкость или подделанный локальный hunt state не задавались.

В дополнительном живом окне Spider02 достиг TimePosition примерно 2.1985 и PlaybackLoudness около 88.81; позднее Spider03 — 0.571 и около 78.71. Вместе с Spider01 первого observer фактически воспроизведены все три NPC voices, без одновременных голосов (`maxVoices=1`).

После следующего диагностического приближения произошла настоящая вторая поимка: `chase → capturing → stopped`. `production-followup-terminal` содержит `allPersonalStopped=true`, а `third-voice-and-terminal-capture` — `ownedRuntimeSoundsAfter=0`, `monsterRemoved=true`. Это подтверждает terminal cleanup рабочего раунда; тест не выдавал поимку через remote или локальную смену атрибута.

Ни эти перемещения, ни observer не подтверждают самостоятельный поиск ключа, длительность обычного полного раунда, человеческое ощущение страха, длительный FPS или прохождение 4–8 игроков.

## Сохранение — PASS

Найдена точная engine AutoRecovery копия от2026-10-13 12:33:15. `recovery-preservation.json` подтвердил75Sources=src, ровно4новых Modules,6835→6839объектов, exact world/Lighting/art/raw Terrain. Проверенную копию атомарно перенесли в `place/Children_of_corn.rbxl` через `promote-tested-audio-copy.py`, защищая оба входных SHA и immutable baseline.1007172байт, SHA-256 `4ee103b95110e2a2a1a691d58a7bb5cdc34d0dc466d3c5265b47eb5823986546`. Immutable backup — `place/Children_of_corn.before-audio-20261013.rbxl`,71Sources,999458байт, SHA-256 `bdebd256fb5d2ad74a9ed5dc51b93f254e592b0d510a0d2b8b797d63847811e6`; bytes неизменны. Сцену через Lune не пересериализовали.

Позднее автор подтвердил Ctrl+S: mtime рабочего файла 2026-10-13 13:36:27. Повторная строгая read-only проверка `author-save-preservation.json` — PASS: прежние 1007172 байта и SHA-256, 75 Sources=src, ровно четыре новых ModuleScripts, весь world/Lighting/art/raw Terrain сохранён точно. Дополнительная замена или пересериализация файла после авторского сохранения не потребовалась.

Studio остановлена в Edit; `final-source-equality.request.json.result.json` — PASS, `created=0`, `changed=0`, `sources=75`. Финальный `check.ps1` PASS:0errors/0warnings/0parse, code-only build/sourcemap/disabled persistence. Точный аудит и результаты atomic save находятся в `preservation.json`/`saved-scene.json`; backup сохранён. Будущие engine-save файлы проверяются командой:

```powershell
python -X utf8 scripts/verify-audio-copy.py place/Children_of_corn.before-audio-20261013.rbxl place/Children_of_corn.rbxl --report .artifacts/playtests/2026-10-13-audio/preservation.json
```

Получен PASS: ровно75Sources=src,6835→6839объектов, четыре новых ModuleScript с независимыми default properties, весь original world/Lighting/art/raw Terrain точен. Только Source и разрешённые editor Camera/selection metadata могут отличаться. Проверка не пишет сцену; при прямом авторском Ctrl+S promotion или Lune scene serialization не нужны. Для отдельной engine-copy предусмотрен `promote-tested-audio-copy.py` с обоими hash guards.

Защита verifier уже прошла in-memory fixture: 39 недопустимых DOM изменений и три изменения неизвестных raw binary свойств отвергнуты, immutable bytes не менялись. Это проверка verifier, не замена проверки настоящего окончательного engine-save файла.

Все упомянутые `.request.json.result.json` находятся в `.artifacts/playtests/2026-10-13-audio/`. Открытый внешний пункт этой приёмки: Fire. Итоговый `live-acceptance.json` отдельно фиксирует behavior/playback PASS и all_assets_passed=false (14/15). Самостоятельный полный раунд, человеческий микс/страх, длительный FPS и multiplayer остаются отдельными проверками.

После авторского сохранения выполнена повторная проверка Fire в Edit: временный muted Sound10сек ожидал загрузку, IsLoaded=false/TimeLength=0. Контрольный утверждённый Corn02 в том же контексте загрузился с TimeLength0.8524263. Временные Sounds удалены; Source/world не менялись. Артефакты: fire-after-author-save.json и edit-decoder-control-after-save.json. Fire остаётся pending.
