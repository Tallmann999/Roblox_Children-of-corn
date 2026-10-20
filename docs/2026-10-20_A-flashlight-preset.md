# A: выбранный круг фонаря и сохранение параметров

## Дополнение: штатное игровое качество закреплено через MCP

После сообщения автора о новом сбросе повторная диагностика обнаружила в памяти
Studio UserGameSettings.Automatic и renderQuality.Automatic, хотя файлы настроек
содержали21/10. Предыдущая запись XML не применилась к уже работающему процессу;
прежняя проверка сохранения качества была недостаточной.

Через виртуальный ввод Studio MCP открыто стандартное меню Roblox:
Escape→Settings→Graphics Mode Manual→Graphics Quality10→Escape. Это штатная UI
операция: CoreGui применил SavedQualityLevel.QualityLevel10 и renderQuality.Level21.
Настройки Windows, мышь/клавиатура рабочего стола, код игры и соседние сцены не менялись.

Затем выполнены два новых Stop/Play без дополнительных вызовов setter качества.
В первом4samples с интервалом1s, во втором после3s и после штатного production Start
сохранились manual10/Level21. Фонарь автоматически прочитал screenshot preset;
30samples вперёд/вниз−75° ON/owned и с правильными двумя пучками. Подготовка
camera/focus/cursor диагностическая, Root не менялся. Observer/binding убраны,
финал Edit/CameraFixed/156Sources/Httpfalse. А и B на диске не менялись.
Доказательство: native-quality-menu-restarts.json. Полный выход из процесса Studio
с последующим открытием не выполнялся; проверены именно два перезапуска Play.

Следующие разделы описывают предыдущий этап до этой успешной настройки через меню.

Пользователь подтвердил, что после временного Studio QualityLevel21 появился
нужный круг света, и выбрал параметры на снимке 2026-10-20_15-47-49.png.
В A сохранён постоянный банк ReplicatedStorage.CornFlashlightSettings:

| Параметр | Широкий пучок | Центральный пучок |
|---|---:|---:|
| Яркость | 2.08 | 22.62 |
| Угол | 78° | 12° |
| Дальность | 18 | 24 |

Наклон фонаря −6°, прежняя камера/FOV70 и движение сохранены.
Runtime панель по-прежнему меняет только текущий Play; Reset теперь возвращает
выбранный постоянный preset A. LightingStyle.Realistic в A/B уже был сохранён.

A:1491827байт/SHA256 `c1f054029ca729f314889ce7874c17c6e5f772cb20541a9c0ceedd796f3446b7`.
Штатная AutoRecovery движка от16:00:07 строго проверена и атомарно скопирована
без пересериализации. Все156Sources и4529instances сохранены, изменились только
четыре свойства банка; четыре FilteredSelection UID — метаданные редактора.
Мир, арт, остальные свойства Lighting, родители, идентичности мира и rawTerrain точны.
B1494881/`8160b71046a7c56a8a0c536ecfd3b9b9ca51a4e183c8f42cfb0b2458b81c837c` неизменён.

## Причина различавшегося света

Realistic был включён и в сохранённых файлах, и в открытой A. Пользовательский
снимок показывал другой результат, чем MCP capture. В момент диагностики
QualityLevel был Automatic, AutoFRMLevel4. Переключение Studio QualityLevel21
вернуло нужную границу света, что пользователь подтвердил своим снимком.
Само наличие Realistic и инструментальный capture оказались недостаточной проверкой.

Повторный Play выявил дополнительный сброс: начальное игровое предпочтение
UserGameSettings.SavedQualityLevel.Automatic возвращало QualityLevel.Automatic.
Прямое изменение SavedQualityLevel через MCP API отказано движком:
`lacking capability RobloxScript`. Код игры не менялся для обхода этого ограничения.

По прямому запросу автора сохранены только два локальных предпочтения Studio:
GlobalSettings_13.xml/RenderSettings.QualityLevel=21 и
GlobalBasicSettings_13_Studio.xml/UserGameSettings.SavedQualityLevel=10
(максимальное ручное игровое качество). Каждый файл проверен по исходному SHA,
заменён только соответствующий XML token, все остальные байты сохранены.
Патчи не затрагивают отдельный Roblox Player. В текущем Edit повторно выставлен21.

**Полный перезапуск Corn Studio и проверка загруженного качества ещё не выполнены.**
Текущий процесс держит старое UserGameSettings в памяти; автор просит работать
только через MCP без управления его окнами. Поэтому гарантия после перезапуска
пока не заявляется. При следующем открытии проверить SavedQualityLevel и фактический
QualityLevel после начала Play, а также сохранность обоих XML предпочтений.

## Проверки и очистка

Guarded install-A-flashlight-preset.luau сверил все156Source SHA256 и неизменённый
банк/остановленный Corn A. Native4property changes, repeat0. Исходники не менялись;
check.ps1 не повторялся для этой настройки и не создавал новую build-сцену.
Fresh normalbootstrap, один клиент, штатный production Start вызван программно:
30render samples вперёд и вниз−75°, правильные параметры/ON/ownership во всех.
Камера/focus/cursor временно подготовлены диагностикой; Root/мышь/клавиатура не
управлялись. Observer и render binding удалены, финал stoppedEdit/CameraFixed/156Sources.
Это проверка нового preset, а не новая человеческая визуальная/FPS/reopen приёмка.

Автор потребовал оставить только две сцены.50лишних RBXL/RBXLX убраны из place,
build и .tools после полного byte/hash ZIP сравнения. Единственные loose scene files:
place/Children_of_corn.rbxl и place/Children_of_corn_B.rbxl. Старые immutable сцены
с их точными исходными байтами доступны внутри единственного служебного архива
.artifacts/scene-archive/2026-10-20-scenes.zip,37064436байт/SHA256
`499c06f1f5bfbda032da03a09f7afadf9d548cc186a5c3c4b3807ce3aea4b034`.
Исторические скрипты с прежними loose baseline paths не следует запускать вслепую.
Текущий verify-A-flashlight-preset.py читает archived checkpoint/A-before-preset.rbxl
через внешний временный каталог и не создаёт дополнительных сцен в проекте.

Доказательства: .artifacts/playtests/2026-10-20-A-flashlight-preset/
{preservation,recovery-preservation,saved-scenes,native-acceptance,
studio-quality-file,studio-play-quality-file}.json и .artifacts/scene-archive/cleanup.json.

При подготовке общего A/B checkpoint checker обновил только пин соседнего B: теперь
ожидается принятый f33571e8…, вместо прежнего8160b710…. Повторный строгий аудит A
PASS:156Sources неизменны, только4настройки; B audit также PASS. Сама A не менялась.
