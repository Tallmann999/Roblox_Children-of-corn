# Реалистичный свет и тени: предварительный анализ — 2026-10-15

## Фактический короткий A/B в активном окне

Автор подтвердил активное окно, затем выполнены пять последовательных этапов по 5 секунд прогрева и 25 секунд измерения. Камера неподвижна у выхода, ночь 20:30, viewport 1914×801. В измеренных этапах нет фоновых кадров или кадров с неизвестным фокусом. LightingStyle переключается через клиентский API; установка фиксированного Quality10 запрещена capability RobloxScript. Поэтому все значения ниже получены на **Automatic** и не измеряют запас GPU при фиксированном качестве. Предыдущий фоновый сбор около 15 FPS исключён.

| Вариант | FPS | p95, мс | p99, мс | Кадры >50 мс за 25 с |
|---|---:|---:|---:|---:|
| Soft, исходный профиль | 59.97 | 18.68 | 20.40 | 0 |
| Только Realistic | 59.81 | 19.32 | 22.51 | 1 |
| Realistic и тени 37 ближайших деталей кукурузы | 59.70 | 19.36 | 24.19 | 2 |
| То же и два ближайших теневых факела | 58.78 | 20.15 | 39.28 | 8 |
| Soft повторно | 60.03 | 20.25 | 21.73 | 0 |

Максимальный кадр у варианта с двумя теневыми факелами —142.91 мс. Средний FPS меняется мало, но редкие длинные кадры в этом варианте заметнее. Это наблюдение одного короткого статического теста, не доказательство причин каждого отдельного скачка и не прогноз для всего поля. Фактически протестированы37 деталей, а не предлагаемый предел256. Не проверялись тени всех19343 дальних растений, дневной маршрут, движущаяся камера или три активных преследователя. A/B проведён до последнего исправления запуска анимации дополнительных NPC и с одним основным NPC; это не итоговый FPS финальной погони.

Решение этого этапа: оставить авторский Soft, не включать постоянные тени кукурузы/факелов. При следующем визуальном проходе можно отдельно оценить Realistic с ограниченными тенями рядом с игроком; локальные теневые факелы требуют более длинной проверки. Все временные Lighting, CastShadow, Light.Shadows и качество восстановлены; итоговая Edit сверка: Soft, PrioritizeLightingQuality=true, GlobalShadows=true, ShadowSoftness≈0.2. [Полные данные A/B](../.artifacts/playtests/2026-10-15-finale/shadows-foreground-automatic.json).

Ниже сохранён исходный анализ и план эксперимента; его формулировки «нужен замер» относятся к состоянию до приведённого короткого A/B. Длительная проверка на фиксированной графике и обычном маршруте остаётся открыта.

Scope: текущий локальный solo PC MVP, CornMap 840×840, 75 Sources. Это чтение проекта и проверка официальной документации Roblox; Studio, Sources, Lighting, карта и плагины этим анализом не изменялись. Новых измерений FPS здесь нет. Практический вывод: штатные реалистичные тени стоит проверить с ограниченным числом близких растений и теневых факелов. Включать тени всем примерно 20 тысячам дальних растений сразу для первого варианта не предлагается.

## Что уже делает наш проект

| Область | Подтверждено кодом/отчётом | Значение для теней |
|---|---|---|
| Дальний corn backdrop | Шаг 6 studs, прежний замер 19715 растений, лимит 20000, `CastShadow=false`, наследуемый Automatic; генерация до 18 клонов/2 мс за batch | Один переход на Realistic не включит тени этих растений |
| Ближняя кукуруза | Радиусы 150/200, dense 60, до 4032 растений/100 групп; подготовленный template тоже `CastShadow=false` | Для теней кукурузы нужно отдельно разрешить casting выбранным runtime растениям |
| Листья | `CornLayout.PrepareTemplate` включает `MeshPart.DoubleSided=true` | Это двухсторонний рендер, а не переключатель теней. Не отключать его вслепую: обратные стороны листьев исчезнут |
| Факелы | Всего 27 после inventory update, Brightness 1; исходный TorchLight имеет Range 18 и Shadows false | Уменьшенная яркость сама по себе не доказывает соответствующее уменьшение GPU стоимости |
| Torch FX | Встроены в `CornController:_step`: раз в 0.3 с PointLight включён только ближе 90 studs, Fire — 220; easy выключает факелы | 27 факелов в сцене не означают 27 одновременно активных теневых источников. Особенно проверять плотную группу возле выхода |
| Режимы | Easy 13.5, medium 17.9, hard 20.5; меняют Brightness/Ambient/Fog/Atmosphere, но не LightingStyle | День/сумерки/ночь — отдельная ось настройки; текущий стиль нужно прочитать у фактической сцены |

Источники проекта: [CornBackdropController](../src/client/Controllers/CornBackdropController.luau), строки 13–17 и 280–310; [CornController](../src/client/Controllers/CornController.luau), строки 65–70 и 683–705; [CornLayout](../src/shared/Game/CornLayout.luau), строки 116–123; [MapTuning](../src/server/Game/MapTuning.luau), строки 49–54; [inventory torch update](../scripts/install-inventory-torches.luau); [LightingModes](../src/shared/Game/LightingModes.luau).

Последний длинный зафиксированный foreground результат: GTX 1060 6 GB / i5-4460 3.20 GHz, Studio Automatic, viewport 1914×801, 603.509 с, средний 59.850 FPS, p95 19.005 мс/p99 23.409 мс. Это версия **28 Sources от 10 октября**, до текущих фермы/инвентаря/аудио/нового capture. Ровные 15 FPS в фоне тогда исключили. Этот отчёт не является baseline производительности нынешних 75 Sources и не показывает запас GPU под новые тени. [Фактический отчёт качества](2026-10-10_quality-playtest.md).

Координатор 15 октября отдельно прочитал в проверенной Studio текущую baseline: `LightingStyle=Soft`, `PrioritizeLightingQuality=true`, `GlobalShadows=true`, `ShadowSoftness=0.2`; обращение к старому Technology недоступно. Это чтение параметров, не новый FPS тест. Для этой baseline отдельный A1b с включением GlobalShadows не нужен: они уже включены. Доступность setter LightingStyle и фактический A/B остаются отдельной проверкой координатора.

## Актуальные штатные API

- `Lighting.LightingStyle = Enum.LightingStyle.Realistic` — текущий художественный стиль реалистичного света; `Soft` — более плоский стилизованный вид. `Lighting.PrioritizeLightingQuality` управляет тем, что движок раньше снижает на меньшей графике: детализацию света или дальность. При этом Soft не означает безусловное отсутствие shadow maps: путь зависит также от этого приоритета. [LightingStyle](https://create.roblox.com/docs/reference/engine/enums/LightingStyle), [официальное описание Lighting](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Lighting.yaml).
- `Lighting.Technology` заменён новой парой свойств и deprecated; не строить новый код вокруг `Future`/`ShadowMap`/`Unified` enum. Это не требование выбирать устаревший `Enum.Technology.Unified`. [Technology](https://create.roblox.com/docs/reference/engine/enums/Technology).
- `Lighting.GlobalShadows` разрешает глобальные тени; `ShadowSoftness` задаёт жёсткость края 0…1. Текущая environment-статья связывает softness с Realistic. Это регулировка вида, а не обещанный переключатель дешёвого рендера. [Global lighting](https://create.roblox.com/docs/environment/lighting).
- `BasePart.CastShadow` выбирает объекты, отбрасывающие тень, а `Light.Shadows` — затенение от конкретного PointLight/SpotLight/SurfaceLight. Для corn-тени от факела нужны подходящие настройки и источника, и растений; одного Realistic недостаточно. [Light sources](https://create.roblox.com/docs/effects/light-sources), [BasePart.CastShadow](https://create.roblox.com/docs/reference/engine/classes/BasePart#CastShadow).
- `DoubleSided` рисует обе стороны полигонов; он полезен для листьев-карточек, но увеличивает работу рендера. Если ассет использует альфа-листья, качество их силуэта и тени надо увидеть в настоящем GPU кадре; документация не доказывает, как будет выглядеть именно наш импорт. Не объявлять CastShadow гарантией красивой альфа-тени. [Asset render parameters](https://create.roblox.com/docs/tutorials/curriculums/environmental-art/assemble-an-asset-library).

Есть расхождение официальных описаний доступности: [light-sources prose](https://create.roblox.com/docs/effects/light-sources) ещё говорит о выборе LightingStyle через Properties, а актуальный first-party `Lighting.yaml` у LightingStyle и PrioritizeLightingQuality указывает write `None`, capability Environment; у Technology — RobloxScriptSecurity. Поэтому координатор A/B должен проверить **pcall setter + readback в текущем Studio**, а не предполагать доступность или запрет. Если среда не разрешает изменение стиля в Play, сравнение делается через временную настройку правильной сцены в Edit с последующим точным восстановлением; это не требует установки плагина.

## Практическая оценка стоимости

Главный риск — плотная двусторонняя кукуруза, которой дополнительно нужен shadow rendering, и несколько перекрывающихся локальных источников. Roblox прямо относит большую плотность casting lights и мелких shadowed parts к причинам проблем; полупрозрачные перекрытия также создают overdraw. Одинаковый mesh/texture может инстанситься: **19715 растений не равны 19715 отдельным draw calls**. Это не делает их геометрию и тени бесплатными. [Rendering performance](https://create.roblox.com/docs/performance-optimization/improve#rendering).

PointLight светит во все стороны; официальная Roblox lighting-статья рекомендует особенно сдерживать число таких источников на слабых устройствах. Для нашего поля рационально оставить большую часть света без shadow casting и дать тени нескольким источникам возле игрока. Это инженерная гипотеза для проверки, а не измеренная экономия. [Realistic local lighting tutorial](https://create.roblox.com/docs/tutorials/use-case-tutorials/lighting/enhance-indoor-environments).

Без A/B нельзя честно назвать «минус 10%», «останется 60 FPS» или «будет лагать». Даже одинаковые 60 FPS могут скрывать разный запас до лимита кадра. Сравнивать нужно клиентское время кадра и GPU/render scopes, а не только FPS или серверный Heartbeat.

## Ограниченный A/B план

Следующие числа — **предложенный тестовый бюджет**, не уже установленная фича и не прогноз FPS.

| Вариант | Что меняется относительно предыдущего | Что оставляем |
|---|---|---|
| A0 | Прочитать фактические LightingStyle/GlobalShadows/PrioritizeLightingQuality/ShadowSoftness и графическое качество; текущая сцена как есть | Полная baseline текущей версии |
| A1 | Только Realistic, сохранив прочие параметры | Corn CastShadow=false; текущий culling факелов |
| A1b, если нужен | Если baseline GlobalShadows=false, отдельно проверить true | Не смешивать стоимость этого изменения с включением corn/torch casting |
| B1 | Разрешить CastShadow максимум 256 близким BaseParts LOD1 в радиусе около 24 studs | Весь backdrop/overview и дальние LOD остаются без новых теней; без включения всех 4032 near растений |
| C1 | К B1 добавить Shadows максимум двум ближайшим включённым owned TorchLight, Range оставить 18 | Остальные факелы светят по прежним правилам без новых теней |
| C2, если есть запас | Отдельно сравнить четыре близких shadow lights или увеличенный corn cap | Не принимать расширение без измеримого визуального выигрыша |

256 — лимит именно BaseParts, не Models. Радиус 24 studs на сетке 3 даёт порядок двухсот клеток до исключений; это только ориентир выбора кандидатов, а не фактический count модели или оценка render cost. Для будущего движущегося профиля нужен кэш по существующим chunks, редкое обновление и hysteresis, а не обход 20000 растений каждый кадр. Текущий эксперимент можно ограничить одним набором кандидатов при фиксированной камере.

В каждом основном варианте нужны одинаковые позиции/взгляд: густое поле, выход с группой факелов, фермерский дом, высокая точка; отдельно day/dusk/night. Прогреть backdrop/LOD/mesh reconstruction, затем записывать одинаковые foreground интервалы, например 30–60 с × два прогона, с baseline повторно после опытов. Зафиксировать точное качество, viewport, active near/far counts, число реально включённых lights/casters, среднее время/p95/p99/пики и screenshots. Для итогового принятого варианта нужен более длительный обычный маршрут с погоней; короткий статический A/B этого не заменяет.

Сначала сравнить при фиксированном ручном графическом качестве, затем отдельно Automatic: иначе движок может компенсировать нагрузку ухудшением вида. По официальной оптимизации на графике ниже 4 тени могут вовсе отключаться, поэтому «на низком FPS не изменился» не доказывает работающие тени. В MicroProfiler полезны `ShadowMapSystem`, `computeLightingPerform` и `RenderView`; фоновые интервалы исключать. [Roblox profiling/quality guidance](https://create.roblox.com/docs/performance-optimization/improve).

Точное восстановление обязательно: `LightingModes.Capture/Restore` **не сохраняет** LightingStyle, PrioritizeLightingQuality, GlobalShadows или ShadowSoftness. Для A/B нужен отдельный snapshot/finally restore этих полей и исходных CastShadow/Shadows, включая cleanup при Stop/error; нельзя полагаться только на menu/переключение режима. Авторский template, сохранённый overview, art, материалы, геометрия/коллизии и raw Terrain не изменять ради эксперимента. Этот анализ не разрешает сохранять временный профиль в .rbxl.

## Нужен ли плагин

Для такого света плагин не нужен: Realistic, GlobalShadows, CastShadow и Light.Shadows — встроенные средства Roblox. Плагин может удобнее применять presets или редактировать свет, но не даёт отдельного бесплатного движка теней. Bloom/цветокоррекция/Atmosphere меняют восприятие и могут сами иметь стоимость; это отдельные варианты, не замена проверки casting. Официальный пример настраивает всё обычными Properties. [Configure realistic lighting](https://create.roblox.com/docs/tutorials/use-case-tutorials/lighting/enhance-indoor-environments).

Плагины не устанавливались и не предлагаются обязательной зависимостью. Реальный A/B и решение о переносе профиля в игру выполняются координатором отдельно; в этом документе нет engine/FPS PASS для новых теней.
