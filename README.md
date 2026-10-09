# Дети кукурузы

Одиночный хоррор для Roblox Studio на ПК. Найти ключ в густом поле, открыть ворота и сбежать. Полный MVP также включает первое лицо, ограниченный спринт, монстра и две попытки; эти механики идут следующими фичами.

Текущий этап — постоянная карта **1200 × 1200 studs** и цикл ключ → ворота → выход → повтор. Подготовлены 15 мест ключа, три бочки, три дома из Parts и ограниченный предпросмотр предоставленной кукурузы. Дома — декорации и препятствия. Кукуруза покрывает всю карту общим дальним слоем; около игрока появляются отдельные плотные растения с шагом 3 studs. Детальные 160 тысяч растений не создаются одновременно.

## Исправление уже установленной сцены

В тесте 2026-10-09 сохранённый CornMap не содержал RoundSpawn: раунд завершался до старта, персонаж оставался на старом нижнем SpawnLocation. [Аудит проекта](docs/2026-10-09_project-audit.md).

1. Открыть **place/Children_of_corn.rbxl**, нажать Stop и закрыть вкладки скриптов Studio.
2. Выполнить весь **scripts/repair-corn-scene.luau** в Command Bar. Это обновление существующей карты; прежний install-editable-scene при наличии CornMap ничего не обновляет.
3. Дождаться `ChildrenOfCorn scene repaired`, нажать F для обзора выделенного углового старта, сохранить Ctrl+S и запустить F5.
4. Проверить старт над землёй уже в меню, четыре доступных угла при повторах, плотную кукурузу рядом и общий вид поля вдали. Перейти к ключу/воротам/выходу после исправного запуска.

Обновление сохраняет дома, ворота, землю и 15 слотов; добавляет четыре реальные точки CornerSpawns и общий слой EditorFieldOverview. Старый нижний Workspace/SpawnLocation сохраняется с Enabled=false. Точная резервная копия текущей сцены — place/Children_of_corn.before-spawn-fix.rbxl. Файловые проверки прошли; установка исправления и визуальная проверка в Studio ещё открыты.

## Установка в правильную сцену

Рабочий файл: `place/Children_of_corn.rbxl`. Резервная копия перед установкой: `place/Children_of_corn.before-editable.rbxl`.

1. Открыть **Children_of_corn.rbxl**, остановить Play и закрыть вкладки скриптов в редакторе Studio.
2. Выполнить весь `scripts/install-editable-scene.luau` в Command Bar. Он проверяет исходные Sources, отказывается в Speed Monkey и не перезаписывает существующий CornMap. Rojo для этой установки не нужен; live sync остаётся отключённым.
3. Увидеть `ChildrenOfCorn editable scene installed`, нажать F на уже выделенном RoundSpawn для обзора старта и сохранить сцену Ctrl+S. Карта находится на высоте Y=80; если выделение потерялось, выбрать Workspace/CornMap/RoundSpawn в Explorer и нажать F.
4. Запустить F5 и пройти [проверку первого этапа](docs/first-slice-playtest.md).

Если Output просит закрыть вкладку скрипта, закрой её и повтори весь установщик: до этого отказа Sources и мир не меняются. Если прежний GreyboxWorld содержит добавленные объекты, установщик также остановится, сохранив их.

Статус: format/lint/Rojo build и файловая проверка установщика пройдены. Установка в живую Studio, визуальная проверка и Play Test пока требуют выполнения этих шагов. Из внешнего CLI исходная .rbxl не перезаписывалась.

## Редактирование и передача тестировщику

[Как двигать дома/ворота/слоты, обновлять предпросмотр и передать .rbxl](docs/map-editing-and-sharing.md). После Stop карта остаётся в Workspace. При новом раунде ручная расстановка сохраняется. Тестировщик открывает сохранённый .rbxl в Roblox Studio и запускает F5; Rojo ему не требуется. Mesh/texture — облачные ассеты, им нужны доступ и загрузка.

## Документы и порядок фич

- [Концепт](docs/project-concept.md), [индекс фич](docs/feature-index.md), [правила цикла](docs/2026-10-09_core-loop_gd-spec.md).
- [Технический план](docs/technical-plan.md), [архитектура](docs/architecture.md), [чеклист](docs/mvp-checklist.md).
- Этапы: карта/ключ/ворота/повтор → первое лицо/спринт → охота/две попытки → звук/атмосфера → полный плейтест.

Магазин, покупки, постоянное сохранение и мультиплеер отложены.

## Команды из корня проекта

```powershell
.\scripts\setup.ps1
.\scripts\check.ps1
```

Закреплены Rokit 1.2.0, Rojo 7.7.0, StyLua 2.5.2, Selene 0.31.0. Portable Lune 0.10.5 установлен в .tools/lune с проверкой официального SHA-256; он используется только для файловых проверок. Исходники синхронизируемого кода находятся в src/shared, src/server, src/client; Rojo не управляет Workspace/Lighting.

После изменения src и check.ps1 установщик пересобирается:

```powershell
C:\Python314\python.exe scripts\build-editable-installer.py
C:\Python314\python.exe scripts\build-scene-repair.py
.\.tools\lune\lune.exe run tests\editable-scene.luau
.\.tools\lune\lune.exe run tests\scene-repair.luau
```

Тест использует ограниченный адаптер геометрии Lune и не заменяет движок/Play Test. После установки и сохранения проверить сохранность первоначальной сцены:

```powershell
C:\Python314\python.exe scripts\verify-scene-preservation.py place\Children_of_corn.before-spawn-fix.rbxl place\Children_of_corn.rbxl --corn-repair
```

build/code-foundation.rbxlx — только проверочная сборка кода; не открывать её вместо рабочей карты. live Rojo намеренно остановлен после ошибочного подключения к другой сцене. Перед будущим serve сначала проверить правильный файл Studio.

Источник основы: [RobloxGameKit_v0.1.0](https://github.com/Tallmann999/RobloxGameKit_v0.1.0), revision 960e068352e187fc1d2129305f8fcfb07faf2782; установлен минимум core/network/tags. [Lock](robloxgamekit.lock.json).
