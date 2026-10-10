# Мини-карта — Studio acceptance 2026-10-10

Работа выполнена только в Children_of_corn, studio_id `2aca50b7-fc16-4a1c-aac0-299372b05b92`. Звуки отложены до подборки автора. Local solo PC, без публикации/постоянных данных. Финальные 27 Sources установлены в Edit, совпадают с src, сцена сохранена точными байтами engine AutoRecovery. Studio оставлен в Edit; Rojo остановлен.

## Итоговое поведение

Карта справа сверху под кнопкой завершения: положение/направление игрока, маленькие крестики посещённых просветов/домов, красные векторные черепа. Большая карта открывается M или Alt + клик; закрывается M/кнопкой. Охота продолжается; открытие снимает намерение спринта. После закрытия сохраняется прежнее состояние Alt. Ключ, монстр и непосещённые ориентиры не раскрываются. Серверные отметки сохраняются после первой поимки/в результате и очищаются при start/retry.

15 tagged slots определяются кругом 9 studs (просвет 6 + padding 3), три существующих дома — текущим bounding box  + 3; допуск высоты 12. Авторские CFrames/размеры и map geometry не менялись. Проекция берёт текущие FieldZone CFrame/Size; верх соответствует локальному -Z, положение за границей ограничено краем. Runtime UI обновляется 10 Hz, максимум 18+3 маркера на каждом из двух представлений.

## Фактические результаты

| Проверка | Результат / доказательство |
|---|---|
| Формат/линтер/сборка | scripts/check.ps1 PASS; Selene 0 errors/warnings/parse; code-only mappings, persistence off |
| Проекция | tests/minimap-geometry.luau PASS: повернутое/смещённое прямоугольное поле, все 4 угла / heading, edge clamp, malformed/nonfinite/duplicate payload rejection |
| Серверная геометрия/история | tests/minimap-state.luau PASS на read-only копии сохранённого мира; circle/OBB 37°/высота,18 ориентиров, дедуп, copied/bounded history, reset/clear, visit-before-catch, death root при Health 0 |
| Engine geometry/methods | tests/studio-minimap-state.luau PASS с detached geometry и текущими SoloRound methods; author Workspace untouched |
| Все настоящие посещения | Server-root diagnostic teleport по 15 слотам+3 домам, временная собственная NPC relocation; все восстановлены. Реальный poll + round_snapshot + GUI дают 18/18;3 повтора не добавляют маркеров. Это не обычный обход пешком |
| Стрелка настоящего UI | actual-four-corners: TL/TR/BR/BL и 0/90/180/270°. Временные root-anchor/AutoRotate восстановлены |
| Две настоящие поимки | Первый череп `(310,19.399986,340)` зафиксирован в phase caught; после возврата root `(385,17.398438,385)`18 крестиков и первый череп сохранены. Второй `(-330,19.399986,320)` добавлен перед caught_out;0 награды |
| Обычная смерть | Humanoid.Health=0, Died + automatic respawn: ровно 1 death marker `(-300,19.399986,-330)`, без переноса к старту/дубля |
| Reset | Реальный LoadCharacterAsync/CharacterRemoving/Added из active:1 death marker `(305,18.249825,-350)`; исходный X/Z сохранён |
| Retry / режимы | Реальные remote retry в easy / hard увеличили round_id и очистили крестики/черепа; UI работаетв medium / hard / easy |
| Мышь/Alt/M | Реальные Alt + click/Close click/M open/M close PASS. Проверены оба исходных Alt-state, map-specific hint, held Shift не rearmed |
| Мир/взгляд | При открытой карте за 1.2 с NPC прошёл 11.8307 studs; camera LookVector delta 0. Обычные snapshots не закрывают карту |
| Phase/abort/menu | Phase смена закрывает expanded; abort не добавляет череп; menu скрывает карту |
| Escape handler | tests/studio-minimap-input.luau PASS с текущими методами и реальным engine UI: synthetic Escape при processed=true/false закрывает, Alt-state сохраняется. Дополнительно GuiService.MenuOpened закрывает expanded. Физическое Esc автор подтвердил 2026-10-10: «Да, Esc закрывает и M работает». См. quality report. |
| Защита установки | tests/minimap-installer.luau PASS: wrongscene/manualSource/open-tab/collision refusal, повтор без изменений мира, injected failure rollback |
| Финальный Source / Output |27 Sources=src;3 services / 4 controllers, Output без runtime ошибок в последней fresh сессии |
| Сохранение | Strict source/world/Lighting/art/raw Terrain сравнение PASS;4 новых ModuleScripts,6454 → 6458 instances. Engine bytes atomic promotion, обе SHA-256 guarded |

Диагностический snapshot observer хранится в test-only ScreenGui ResetOnSpawn=false. Первая версия test observer была Folder и очищалась стандартным respawn; fixture исправлена, смерть/Reset повторно выполнены и записаны. Продуктовые GUI пережили respawn.

## Физическое Escape — авторская приёмка 2026-10-10

Официальный Studio MCP user_keyboard_input отказал: `key is permanently bound to a CoreGUI core action. VirtualInput cannot process this key.` Автоматическое физическое нажатие не выполнено; автор отдельно нажал Esc и подтвердил закрытие + Resume/M. Проверка закрыта по человеческому результату; обработчик проверен отдельно выше.

1. Открыть place/Children_of_corn.rbxl в Studio, нажать Play и начать раунд.
2. Нажать M, чтобы открыть большую карту.
3. Нажать Esc: большая карта должна закрыться, стандартное меню Roblox остаётся доступным. Вернуться через Resume и убедиться, что доступны M и первый вид. Автор подтвердил результат: PASS.

Обычный поиск 7–10 минут/сравнение маршрута, страх и длительная FPS/дальняя визуальная приёмка остаются открыты. Звуки ждут автора.

## Сохранённый файл

- Рабочий: `place/Children_of_corn.rbxl`,236519 bytes, SHA-256 `38714df503f02abce02d5555533d7f4949f384690a1a75d9135cfe655015e1fa`.
- Engine AutoRecovery 18:43:10 (Europe/Moscow), без Lune-reserialization.
- Точная baseline backup: `place/Children_of_corn.before-minimap-20261010.rbxl`,231503 bytes, SHA-256 `ccf9eabe433f68f4d4a3f9455da2c759de44003c179f25ac4234241b574c0679`.
- Авторский Save 18:11:58 после lighting менял только Camera.CFrame/Focus относительно предыдущей verified copy. Новая baseline сохранена перед установкой.
- Текущие tools: scripts/check.ps1 → scripts/build-minimap-installer.py → guarded scripts/install-minimap.luau (только verified Children Edit). Для следующего engine Save: scripts/verify-minimap-copy.py (baseline before-minimap либо текущий 27-source файл) + guarded scripts/promote-tested-minimap-copy.py. Прежние installers superseded.

Доказательства: `.artifacts/playtests/2026-10-10-minimap/` — named request/result JSON, screenshots, preservation.json и saved-scene.json. Временные диагностики не входят в saved Edit.
