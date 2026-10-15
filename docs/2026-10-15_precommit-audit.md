# Аудит перед коммитом — 15 октября 2026

Прочитана передача контекста, AGENTS.md и актуальная документация. Проверены незакоммиченные изменения поля630, начальной жёлтой кукурузы, доступности предметов и непрерывного шелеста. Отдельные независимые проверки охватили аудио, resize/save pipeline и документацию. Новая игровая фича не добавлялась.

## Сохранённая сцена

Повторный read-only `verify-rustle-comparison-copy.py` прошёл: `place/Children_of_corn.rbxl`, 995988 байт, SHA256 `493bc1f9b512d618d0a815b2197e3af854f775cd711b363db2906d8fbaf1fb68`. Все78 Sources соответствуют75 проектным и3 Fog исходникам;4160 экземпляров. Относительно immutable поля630 меняются только4 Source: AudioAssets, AudioRules, RoundAudio и AudioController. MovementController равен baseline; мир, Lighting, арт, идентичности, родители и raw Terrain сохранены. Независимые хэши обеих резервных сцен и frozen resize manifest совпали с объявленными.

В открытой `Children_of_corn.rbxl` заново подтверждён Studio ID `23ea8e48-309b-41f3-8083-cef1a81600b2`. Read-only проверка native SHA256 всех75 проектных Sources обнаружила0 расхождений. Всего78 Sources, stopped Edit, камера Fixed, Ground630×2×630, FieldZone630×10×630, runtime corn audio Sounds отсутствуют. Соседняя Cooking_Cheff не изменялась. Мир, Sources и сцена не записывались; новых Play/reopen/человеческих испытаний этот аудит не добавляет.

## Исправления аудита

- Для `scripts/resize-layout.json` отключена Git-нормализация строк: frozen SHA256 включает исходные CRLF. Без исключения общее `*.json text eol=lf` меняло бы байты после checkout и ломало проверку. Git-хэши исходных и фильтрованных байтов теперь совпадают. Для MP3 явно задан binary.
- В resize save checker усилена проверка разрешённых Camera.CFrame/Focus: ровно12 уникальных конечных числовых компонентов, без произвольной структуры. Актуальный rustle checker уже имел эту защиту; игровая сцена не меняется.
- В основных документах устранены устаревшие текущие статусы ожидаемого импорта и A/B-сравнения, актуализирован реестр; исторические результаты сохранены.
- Из Git исключены пять локальных resize probe/DOM черновиков. Они сохранены на диске; resize-dom.json занимает137574328 байт. Playtest evidence, исходный MP3 и обе immutable резервные сцены входят в checkpoint.

## Проверки

`scripts/check.ps1` PASS: StyLua, Selene0errors/0warnings/0parse errors, code-only Rojo build/sourcemap, безопасные mappings, persistence disabled. При обновлении API dump Selene использовал существующий кеш. `build-readability-installer.py --compact` повторно собрал75Sources/0additions, без записи сцены.

Повторены12 актуальных Luau fixtures: audio-controller/assets/rules; rustle-continuous client/server/UI; corn-appearance/backdrop/controller-quality/yellow-startup; inventory-barrel-clearance; resize-layout. Все PASS. Четыре Python fixtures resize/rustle verifier и promoter guards также PASS: исходные verifier-прогоны отвергли по68unsafe DOM и3raw Terrain случая; каждый promoter —16 файловых нарушений. После усиления Camera guards resize fixture повторён с PASS:88DOM отказов, включая20новых Camera случаев,3Terrain отказа и2принятых корректных Camera frame.

Доказательства: [сцена](../.artifacts/playtests/2026-10-15-precommit-audit/preservation.json), [Studio](../.artifacts/playtests/2026-10-15-precommit-audit/studio-read-only.json), [Luau](../.artifacts/playtests/2026-10-15-precommit-audit/luau-tests.json), [Python](../.artifacts/playtests/2026-10-15-precommit-audit/python-tests.json), [Camera guards](../.artifacts/playtests/2026-10-15-precommit-audit/resize-camera-fixtures.json), [точные staged bytes сцены/резервов/manifest/MP3](../.artifacts/playtests/2026-10-15-precommit-audit/staged-bytes.json).

## Открытые замечания

Блокирующих дефектов в проверенных production изменениях не обнаружено. Низкоприоритетное усиление на будущее: `AudioController.spatialOwned` проверяет ссылку на Effects SoundGroup, но не родителя самой группы; ручное переподчинение группы не прекращает управление spatial loops. Обычный solo runtime этим не затронут; аудио Sources сохранены без дополнительных изменений.

Исторические `round-audio.luau`, `rustle-client.luau` и A/B comparison fixtures ожидают прежние короткие cues/кнопки и не проходят на финальном continuous runtime. Их setup используется новыми актуальными тестами; это не заявление «все тесты проекта проходят». Исторический статус описан в [continuous rustle](2026-10-15_continuous-rustle.md).

Остаются открытыми обычный слепой полный раунд после уменьшения поля, страх/человеческий микс, баланс безопасного пенька, длительный FPS с3NPC и reopen acceptance. Fire105538100476464 остаётся внешним not-approved asset. Текущий milestone — local solo PC; persistence, покупки, lobby, multiplayer и публичная публикация не добавляются.
