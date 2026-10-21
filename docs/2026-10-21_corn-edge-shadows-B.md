# B: кукуруза у края троп, настоящие тени и глаза врага — 21 октября 2026

## Статус и сохранение

По запросу автора в B убраны красные светящиеся глаза врага, исправлена причина
отсутствия теней кукурузы и придвинуты растения к краям четырёхстудовых троп.
Изменения установлены только через Studio MCP в проверенную
`Children_of_corn_B.rbxl`, Studio `8382bdc2-d369-4b51-97ec-08cd99cdad84`.
Нативная установка пяти Sources и четырёх world-значений прошла; повтор дал
ноль изменений. Всего остаётся 157 Sources.

**Сохранение автора и строгий аудит PASS / complete:true.** Рабочий B после
обычного сохранения Studio: 1 499 095 байт, SHA256
`94c55e17bed0dc2f4b2e7c6020f60c031d80bc636be16166fe0effb6df146d5f`.
[Отчёт author-save-preservation.json](../.artifacts/playtests/2026-10-21-corn-edge-shadows/author-save-preservation.json)
подтверждает 4634→4634 instances, 152 неизменённых Sources, пять точных Source
замен, два свойства и два атрибута глаз. Добавлений, удалений, reparenting и
переиндексации нет; остальные world/art/Lighting/physics/mesh metadata,
идентичности, родители и raw Terrain точны. Сцена не пересериализовывалась.

A сохраняет 1 491 827 байт/SHA256
`c1f054029ca729f314889ce7874c17c6e5f772cb20541a9c0ceedd796f3446b7`.
Другие игры, Windows-ввод и live Rojo не использовались. Старые архивы
сохранены, дополнительных loose rbxl/rbxlx не осталось. Коммита, push и
публичной публикации не было.

Исходный принятый B: 1 497 688 байт/SHA256
`b113d584f1a60e16f34ba4ec40ce051b0338cab712467f07d762d9fc8528b1d2`.
Его точные байты находятся в неизменяемом
[before-corn-edge-shadows.zip](../.artifacts/playtests/2026-10-21-corn-edge-shadows/before-corn-edge-shadows.zip),
SHA256 `2bf1ac59830101e707d5890875d6a439b8afe26261c89d48b7bde7110708e5cc`.
Контрольные значения записаны в
[baseline.json](../.artifacts/playtests/2026-10-21-corn-edge-shadows/baseline.json).

## Почему прежние флаги не давали тень

В текущем B уже работали Realistic, GlobalShadows и Level21; у растений был
`CastShadow=true`, у действительных main/fill фонаря — `Shadows=true`.
Предыдущая проверка этих значений не доказывала наличие отбрасываемого
силуэта на GPU. Данный запрос выявил отдельное ограничение: кукуруза B
рисовалась через peer-local EditableMesh с `MeshContent.SourceType.Object`.

Проведено контролируемое сравнение в Client Play: собственные белые
приёмники на стене/полу и один SpotLight, одна и та же геометрия растения,
размер, поза и текстура. Исходный Object mesh не дал силуэта. После преобразования
того же меша в статический `ContentSourceType.Opaque` силуэт листьев и стебля
появился; отключение только `CastShadow` снова убрало его. Обычный куб дал
сильную контрольную тень. Это устанавливает причину для проверенной нативной
сборки Studio, без вывода из одних только свойств.

Доказательства и точные условия:
[native-shadow-diagnosis.json](../.artifacts/playtests/2026-10-21-corn-edge-shadows/native-shadow-diagnosis.json),
[Object](../.artifacts/playtests/2026-10-21-corn-edge-shadows/edge-object-same-light2.jpg),
[Opaque с исходной текстурой](../.artifacts/playtests/2026-10-21-corn-edge-shadows/edge-opaque-textured.jpg),
[CastShadow off](../.artifacts/playtests/2026-10-21-corn-edge-shadows/edge-opaque-off.jpg),
[куб](../.artifacts/playtests/2026-10-21-corn-edge-shadows/edge-cube-positive.jpg).
Во время пробы обнаружено, что `ApplyMesh` сбрасывает TextureID; перед финальным
сравнением исходный TextureContent/атлас восстановлен. Все пробные объекты,
LocalScript, camera binding и временное состояние удалены.

Штатное исправление находится в `CornAppearance.DetailedTemplates`: только
двенадцать приватных B-шаблонов — четыре формы × Near/Mid/Far — один раз за
сеанс преобразуются через
[AssetService:CreateDataModelContentAsync](https://create.roblox.com/docs/reference/engine/classes/AssetService#CreateDataModelContentAsync).
После `Success` и проверки `ContentSourceType.Opaque` создаётся временный
MeshPart-carrier, геометрия применяется к приватному клону, а все исходные
свойства, исходный TextureContent и настройки материала восстанавливаются.
Carrier удаляется; готовые render templates кэшируются. Частичный сбой очищает
созданные приватные клоны. Исходный каталог, world art и mesh payload не меняются.

Здесь `Opaque` означает тип статического Content, а не новую настройку
прозрачности листьев. Геометрия, UV и атлас сохранены. API и контекст перехода
EditableMesh→static content описаны в официальном
[объявлении Roblox](https://devforum.roblox.com/t/full-release-introducing-createdatamodelcontent-convert-editable-mesh-and-image-data-into-static-content/4541898/1).
Новые asset ID, загрузка ассетов и публикация не требуются.

## Кукуруза непосредственно у троп

Видимая ширина троп остаётся 4 studs. Раньше общий `BOX_PADDING=1.5` оставлял
семь studs между разрешёнными центрами стеблей; фаза сетки с шагом 2.631174
создавала дополнительный пустой край. Теперь нулевой запас применяется только
к точным собственным B `NoCornZones/Maze02Masks/trail_001`…`trail_100`:
проверяются проект, вариант, владельцы папки/части, имя, ширина 4, толщина 0.08,
длина и отсутствие поворота. У прочих объектов прежний запас сохранён.

Существующие подходящие ячейки в пределах одного шага от края придвигаются
к линии 2.05 studs от центра тропы. Используются те же ячейки, четыре формы,
вариация высоты и три LOD; ближний слой и backdrop вызывают одну функцию
`TrailEdgePosition`. Отдельный ряд дополнительных объектов не создаётся.
Исходный и конечный корень должны пройти все исключения, поэтому сараи,
площадки ключа, спавны, ворота и пересечения троп сохраняют расчистки.
Эффективный padding входит в Signature; изменение владения или размеров
инвалидирует старые chunks. Физическая кукуруза остаётся noncollidable,
nontouch и nonquery.

Read-only анализ принятого B использует production grid и исключения;
[edge-fixture.json](../.artifacts/playtests/2026-10-21-corn-edge-shadows/edge-fixture.json)
фиксирует 5078 assertions PASS, включая A/foreign, неверное владение/размеры,
сараи, спавны, ключ, ворота, перекрёстки, предел смещения и сохранение Y.
[edge-summary.json](../.artifacts/playtests/2026-10-21-corn-edge-shadows/edge-summary.json)
даёт следующие результаты:

| Измерение | Результат |
| --- | ---: |
| Разрешённые dense cells до/после возврата плеч троп | 45257 / 50187 |
| Разрешённые Far even-grid cells до/после | 11180 / 12433 |
| Существующие ячейки, придвинутые к краям | 7985 |
| Максимальное смещение корня | 2.580322 studs |
| Точные дубликаты корней | 0 |
| Пары корней ближе 0.75 stud среди 50187 | 310 |
| Медианное расстояние листьев на высоте лица от центра, до/после | 3.3425 / .7014 studs |

Последние геометрические значения вычислены по Near mesh vertices в полосе
высот 4…6.6 studs над землёй и продольном окне 2 studs на 3447 точках прямых троп.
В 94.98% выборки листья оказываются ближе 2 studs с обеих сторон. Это оценка
геометрии, а не человеческое подтверждение касания лица. Тесные пары —
проходимые кластеры, минимальное расстояние корней 0.0353 stud; они не добавляют
клонов и не меняют budgets. Прежний шаг плотности B = 3 / sqrt(1.3), высота 10,
Near limit 576 и остальные лимиты сохранены. Рост Far count объясняется
возвращёнными плечами троп, а не ещё одним изменением плотности на площадь.

## Удаление красных глаз B

Для `WardenDetailed` скрыты только две красные Neon-поверхности глаз;
соответствующие PointLights больше не создаются. Тёмные глазницы и остальная
геометрия лица сохранены. Та же презентация обслуживает погоню и capture.
У двух статических глаз домашнего чучела установлена Transparency1 и
согласована `HarvestVisibleTransparency=1`, чтобы обычный HarvestWorld не
восстановил их. Это два свойства и два атрибута, без удаления instances.

Нативный Play подтвердил один visual врага с двумя Neon-частями глаз
Transparency1 и нулём lights; обе статические поверхности также имеют
Transparency1. B получает узкую замену своего прежнего Source; текущий
A-вариант с белыми глазами поверх B не переносился. Файл A не меняется.

## Нативная проверка и её пределы

Полный source/world preflight проверил 157 Sources и 4315 instances. Новый
обычный Play прошёл штатный Bootstrap и реальные HUD Start/Confirm.
Проверены 2066 ближних runtime-частей: 500 Near + 1566 Mid, все с Opaque MeshContent
и CastShadow=true. Far Ready содержит 12433 Opaque части, все casting.
Реальные main/fill фонаря сохраняют Shadows=true и прежний банк:
Wide 2.08/78/18, Core 22.62/12/24, Pitch −6; слабый HandFill не менялся.

Сохранены обычные field GPU кадры с реальным фонарём и листьями в проходе:
[edge-field-real-flashlight.jpg](../.artifacts/playtests/2026-10-21-corn-edge-shadows/edge-field-real-flashlight.jpg)
и [edge-field-after-walk.jpg](../.artifacts/playtests/2026-10-21-corn-edge-shadows/edge-field-after-walk.jpg).
Камера, focus и Root перед измерением выставлялись диагностически.
Название второго файла не является доказательством полного прохода:
`character_navigation` вернул Success, но измеренное перемещение было лишь
около 0.5/0.9 stud, поэтому новый 24 stud walk PASS не заявляется.

Короткая полевая выборка: 120 кадров за 2.085948 s, MaxDt 0.107096 s. Она не заменяет
длительный FPS, слепой полный раунд, человеческую приёмку касания листвы,
четыре клиента, страх или звуковой микс. Новый полный key→gate→escape в этой
правке не принимался. AI concealment внутри кукурузы остаётся отдельной
нереализованной задачей; правила 48/96, 120 секунд, поимки и +20 не менялись.

Автор остановил Play и сохранил B во время проверки. Финальное состояние:
Edit, 157 Sources, CameraFixed, Httpfalse, Level21, без CornRoundRuntime,
диагностических объектов, LocalScripts, camera/focus bindings и транспорта.
Финальный guarded repeat дал ноль изменений.

## Проверки и будущий workflow

[check.log](../.artifacts/playtests/2026-10-21-corn-edge-shadows/check.log):
check.ps1 PASS, cached Selene 0 errors / 0 warnings / 0 parse errors, code-only build
и sourcemap; сгенерированная code-only сцена удалена.
[Installer fixture](../.artifacts/playtests/2026-10-21-corn-edge-shadows/installer-fixture.log)
проверил полный payload и дал 109 assertions / 34 refusals / 11 rollback points.
[Save fixture](../.artifacts/playtests/2026-10-21-corn-edge-shadows/save-fixture.log):
29 DOM / 19 manifest / 3 Terrain / 14 manifest-reader / 8 frozen-partial отказов,
положительные точный полный DOM, finite Camera, FilteredSelection и доказанная
UID-переиндексация одинаковых barrel siblings. Исторические fixtures с прежними
Source hashes или поведением B не объявляются прошедшими.

Текущий frozen payload
[pipeline-manifest.json](../.artifacts/playtests/2026-10-21-corn-edge-shadows/pipeline-manifest.json):
SHA256 `b3217aa53f2b907b335f9288e72c7060dc8e9fd0d9c124ddbb6c5c94936cada6`.
Только пять Sources: CornLayout, CornAppearance, B HarvestWardenVisual,
CornController и CornBackdropController. Остальные 152 сохранены.
Не устанавливать весь текущий src поверх A/B: варианты по-прежнему отличаются.

Будущая проверка сохранённых файлов использует
`scripts/verify-corn-edge-shadows-copy.py` с этим неизменяемым baseline,
payload и manifest. Старые maze02-refine/shadow-only allowlists относятся к
истории и должны отклонять нынешнее состояние. Подготовка Source/world
транзакции — `build-corn-edge-shadows-payload.py` →
`corn-edge-shadows-native-core.luau` / `install-corn-edge-shadows.luau`;
повторная установка допускается только после свежего Studio/name/B/project/
Source guard. Принятый текущий B уже сохранён; дополнительного Ctrl+S не нужно.
