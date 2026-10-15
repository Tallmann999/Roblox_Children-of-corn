# Шелест целиком и приёмка — 2026-10-14

Начавшийся шелест доигрывается после короткого движения, остановки, прыжка, выхода на дорогу и перехода NPC в trapped/caught. Следующий клип не обрывает предыдущий. Смерть/замена actor, terminal/retry и Destroy сохраняют обязательную очистку. Solo PC prototype; авторские IDs, громкости, движение, карта и частота серверного опроса10Hz не менялись. Число Sources75, новых remotes нет.

Сервер сначала обновляет motion sample, затем ждёт nominal duration и реального IsPlaying. Завершение отмечается без Stop. Не начавшаяся загрузка освобождается через8сек, чтобы недоступный ассет не блокировал actor. Это не таймер остановки уже звучащего клипа.

Первая реальная серверная проверка дала8естественных Ended, однако клиентский observer обнаружил смену реплицируемого URI до клиентского окончания. Поэтому один server PASS был недостаточен. Финальное исправление в существующем AudioController принимает атомарный серверный AudioRustleStart=id:key и использует один локальный spatial Sound на зарегистрированном Root. Следующий newest pending запускается только после собственного Ended, на ближайшем Heartbeat. История не переигрывается, очередь ограничена1, server Sound приглушается локально с guarded restore. См. [клиентский контракт](2026-10-14_rustle-client.md).

## Фактические результаты

- Local audio-assets/audio-rules/audio-controller/round-audio/rustle-client — PASS. Проверены короткий шаг, непрерывные commits, поздний decoder, более длинный фактический клип, newest pending, malformed/stale/foreign identity,8сек не начавшейся загрузки и cleanup.
- scripts/check.ps1 — PASS:0errors/0warnings/0parse, code-only build, sourcemap, безопасные mappings, persistence disabled. Selene использовал cached API dump после ошибки сетевого обновления.
- Настоящий Roblox server decoder:6corn assets decoded,8естественных Ended,0unexpectedStop/URI-beforeEnded, cleanup PASS. .artifacts/playtests/2026-10-14-rustle/server-playback.json.
- Настоящий client decoder на isolated actor с контролируемыми accepted metadata:6corn assets decoded,4естественных Ended (короткий шаг13; continuous13→11→20),0Stopped/URI-beforeEnded, фактический TimePosition и ненулевой PlaybackLoudness, cleanup PASS. .artifacts/playtests/2026-10-14-escape/rustle-engine.json.
- Рабочий раунд, фактический Studio VirtualInput W90ms/keyUp и W5500ms/keyUp:6production clips на CornLocalRustle дали собственный Ended,0Stopped/URI-beforeEnded, ненулевой PlaybackLoudness. Игрок диагностически поставлен в кукурузу, поэтому это проверка движения/звука, а не обычный поиск. .artifacts/playtests/2026-10-14-escape/production-engine.json.
- Общая decoder проверка сейчас14/15. Только Fire105538100476464 не загрузился;6corn загружаются. Ассеты/права/публикация не менялись. Старый отчёт client-playback.json показывает обнаруженный дефект до клиентского исправления, его нельзя считать финальным PASS.

## Установка и сохранение

После reopen положительно проверена только Children_of_corn.rbxl, studio_id67e899f3-fed7-46c7-8d90-9626871f2d38. Соседняя Moon_Test_animation не затронута, Rojo live остановлен. Guarded compact install-readability установил код; финальный повтор в Edit:created0/changed0/Sources75. Native EncodingService SHA256 проверен. --compact сохраняет полные topology/open-tab/Source-history/refusal/rollback guards и не повторяет неизменные geometry-data payloads.

Точный immutable baseline place/Children_of_corn.before-rustle-20261014.rbxl:1009332байта, SHA256ef0731f3235a26e4aa76dd26a7853be4d67e9ccc934f4f054428e5cbd6d146f0, неизменён. Финальный exactengineAutoRecovery19:05:32 строго проверен и atomicallypromoted с обоимиhashguards: рабочийfile1015691байт/SHA2569082169a7da5fed15cd962611777285213fce99f23de82f83e0f361a683ecf16. Sources75=src/6839instances/0additions/3fixedexitproperties, allotherworldLightingart/rawTerrain exact. saved-scene.json иpreservation.json фиксируютрезультат.

Поскольку автор одновременно разрешил3× вывеску, итоговый файл проверяется scripts/verify-escape-copy.py против immutable before-rustle:75Sources=src,6839instances/no additions, только ExitSign.Size/CFrame и ExitTextSurface.PixelsPerStud48→16 (AlwaysOnTopfalseсохранён) плюс утверждённые Sources/editor metadata; остальные world/Lighting/art/rawTerrain точные. Не использовать старый Source-only verifier для изменённой вывески. Никакой Lune scene serialization.

Обычный blind round7–10мин, человеческий микс/страх, новая длительная FPS проверка и повторное открытие финального файла остаются отдельной приёмкой.
