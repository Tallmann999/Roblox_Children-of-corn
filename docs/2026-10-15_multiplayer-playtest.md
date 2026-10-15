# Мультиплеер: проверка реализации — 2026-10-15

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
