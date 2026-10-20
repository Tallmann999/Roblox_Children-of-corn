# Studio: удержание Level21 для Corn A/B

## Причина и границы прежних проверок

После полного выхода и открытия B автор снова увидел свет без выраженной границы.
Новый Studio `5833a5f3-9553-4fdc-908a-ff9c03ac8522` прочитал правильный сохранённый
банк B и LightingStyle.Realistic, но UserGameSettings.SavedQualityLevel и
RenderSettings.QualityLevel оказались Automatic. Файл B остался точным f33571e8… .
Studio-specific GlobalBasicSettings_13_Studio.xml снова содержал SavedQualityLevel0;
mtime соответствовал 16:48:36. Общий RenderSettings XML всё ещё содержал21.
Конкретный процесс/механизм перезаписи пользовательского XML не установлен.

Два прежних Stop/Play проверяли перезапуск игрового runtime внутри Studio.
Они не подтверждали сохранение качества после выхода из процесса Studio.
Временная проверка EditQualityLevel21 + FrameRateManager.Off с игровым Automatic
не дала нужной границы по ответу автора; оба параметра возвращены в Automatic.
Этот вариант не сохранён и не считается исправлением.

## Локальный плагин

Подготовлен `studio-plugins/CornStudioQualityGuard.luau`, сборщик
`scripts/build-corn-quality-plugin.py` и модель локального плагина
`studio-plugins/CornStudioQuality21.rbxmx`. Установщик
`scripts/install-local-corn-quality-plugin.py` проверяет точный SHA256 и отказывается
заменять неизвестный существующий файл. Установлен только новый файл:

`C:/Users/User/AppData/Local/Roblox/Plugins/CornStudioQuality21.rbxmx`

4793байта/SHA256 `5b25f94bd58ee116c65f345e7a7f931407fe016560d952ece41effb288babf43`.
Модель содержит обычный Script локального Studio-плагина; это не дополнительная
сцена и не облачный asset. Другие плагины, CoreScripts и security settings не менялись.

Плагин действует только при полном совпадении имени и варианта:
Children_of_corn.rbxl/A либо Children_of_corn_B.rbxl/B, CornMap.corn_project_id
children_of_corn, Ground630×2×630 и FieldZone630×10×630. До загрузки карты он ждёт.
Он удерживает Rendering.QualityLevel и EditQualityLevel на Level21, восстанавливая
их при сбросе Automatic. Нативная проверка показала, что setter этих параметров не
вызывал GetPropertyChangedSignal; поэтому дополнительно используется Heartbeat
с проверкой не чаще4раз/сек. Запись выполняется только при отличающемся значении.

При уходе из Corn или plugin.Unloading отключаются подписки и возвращаются
исходные значения, если они ещё равны установленному плагином21. Последующая чужая
запись сохраняется. UserGameSettings не записывается; обход denied RobloxScript
capability не используется. Плагин не меняет игровые Sources, экземпляры, Lighting,
FrameRateManager, физику, gameplay или сеть. Он работает в локальном Studio;
публичный Roblox Player этим плагином не управляется.

## Выполненные проверки

- StyLua для core/fixture PASS; Lune fixture17 lifecycle/ownership проверок PASS:
  A/B startup, Automatic reset, отсутствие property event, поздняя карта,
  уход/удаление карты, чужой проект/вариант, unload и сохранение чужой записи.
- B Client, реальный RenderSettings: в ограниченном MCP-вызове core трижды
  восстановил Level21 после намеренного Automatic, пока SavedQualityLevel оставался
  Automatic. После Destroy оба параметра вернулись в исходный Automatic.
  Это проверка core, а не автоматической загрузки установленного файла плагина.
- Установленный файл побайтно проверен. В текущем уже открытом Studio автоматическая
  загрузка плагина не наблюдалась: его сообщения не было, качество оставалось
  Automatic до отдельного MCP setter. Для текущего просмотра Level21 применён отдельно.
- A1491827/c1f054029ca729f314889ce7874c17c6e5f772cb20541a9c0ceedd796f3446b7 и
  B1494878/f33571e819fb605130b05489789c93f11c0ef92a3e9762c77691130a60c3d9c0
  повторно проверены неизменными. Только эти два loose rbxl/rbxlx в проекте.
  Production Source не менялся; check.ps1 и генерация code-only сцены не требовались.

Предварительный этап завершён остановкой B через MCP в Edit и просьбой полностью
перезапустить Studio и открыть B. На том этапе автоматическая загрузка ещё не была принята.
MCP не предоставляет команду полного перезапуска приложения/открытия локальной сцены;
Windows mouse/keyboard не использовались, согласно просьбе автора.

## Полное открытие B: нативная проверка PASS

Автор сообщил: «Полностью перезапустил Studio и открыл B». Заново найден единственный
Corn B `ab6571a4-d231-4506-9c9b-90ae60d6b695`. В новом процессе до дополнительных
quality setter console уже содержала `[CornStudioQuality21]` activation.
Вначале пользовательский Play сменился Edit между двумя MCP-вызовами; первая
попытка Client read получила datamodel unavailable и не используется как измерение.

Read-only Edit:4измерения через0.4s — QualityLevel21/EditQualityLevel21 при
UserSavedQuality.Automatic. B/630/projectID/Realistic/156Sources/Httpfalse/CameraFixed
и весь выбранный банк совпали. Затем через MCP выполнен обычный новый Play:
6измерений через0.5s сохранили21/editor21/Automatic. **Ни один Level21 setter в этом
процессе до этих проверок не выполнялся.**

Штатные игровые Start/Confirm нажаты через Studio MCP virtual game UI, без Windows
мыши/клавиатуры. Создался настоящий CornPersonalFlashlight: main Spot12°/24/22.62,
fill78°/18/2.08 и HandFill75°/1.5/.08, все enabled; Realistic сохранён.
Для проверки именно установленного плагина QualityLevel и EditQualityLevel намеренно
сброшены в Automatic. Без прямой установки21 они вернулись в21 уже к первому0.3s
измерению и сохранились в4последовательных измерениях; UserSavedQuality остался
Automatic. Временные Source/observer узлы, изменение игрока/камеры не требовались.

**Полный выход/открытие B и автоматическое удержание качества: PASS.** B оставлена
в Play для визуальной проверки автором. Автор подтвердил: «Да, круг и фокус света
правильные». Зрительная приёмка границы и фокуса после полного открытия B: PASS.
A полный выход/открытие отдельно не испытывался; обе сцены
охвачены guard и offline tests. Не заявляются приёмка на всех устройствах, FPS/страх
или публичный Player. Старые event-only пробы остаются неуспешной историей.

Оба файла сцен и установленный plugin повторно хэшированы: точные прежние SHA256,
только две loose сцены, ноль изменений Sources/сцен. Сохранение сцены не выполнялось.
Существующие предупреждения MaterialManager/CoreGui/audio в console не связаны
этой проверкой с плагином и не объявлены исправленными.

Доказательства: `.artifacts/playtests/2026-10-20-studio-quality-lock/`
`install.json`, `native-recovery.json`, `saved-scenes.json`, `full-reopen.json`,
`after-reopen-files.json`; manifest рядом с плагином.
Отключение доступно через управление локальными плагинами Studio либо удаление
только установленного CornStudioQuality21.rbxmx после закрытия Studio.
