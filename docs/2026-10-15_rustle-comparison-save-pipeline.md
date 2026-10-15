# Сохранение сравнения шелеста — 15 октября 2026

Фактический итог уже сохранён автором Ctrl+S15.10.2026в12:48:01:995988байт/SHA256 `493bc1f9b512d618d0a815b2197e3af854f775cd711b363db2906d8fbaf1fb68`,78Sources/4160instances, strict checker exit0 и независимый hash PASS. Выбран автоматический непрерывный звук для владельца и3NPC; временный A/B UI удалён. Фактически изменены4из5разрешённых Sources, MovementController равен baseline; мир/Lighting/art/identities/parents/rawTerrain точные. [Итоговая приёмка и ограничения](2026-10-15_continuous-rustle.md), [точный continuous preservation report](../.artifacts/playtests/2026-10-15-continuous-rustle/preservation.json). Историческое имя pipeline сохранено; его checker проверяет текущие src. Ниже — устройство и историческая локальная приёмка pipeline, а не ожидание нового сохранения.

Неизменяемый baseline создан точной копией принятого авторского Ctrl+S: `place/Children_of_corn.before-rustle-comparison-20261015.rbxl`, 996617 байт, SHA256 `489af64fb7f36bdfd7756f1e1d701324c6f202cf931422cf91c72be476a9965d`. Копирование проверило размер/хэш до записи, исключило перезапись существующего отличающегося backup и повторно сравнило оба файла после записи. Рабочая сцена не менялась. Baseline содержит принятое поле630, жёлтую кукурузу и исправленные капканы: 4160 экземпляров и 78 Sources.

`scripts/verify-rustle-comparison-copy.py` разрешает изменение содержимого только пяти существующих Sources:

- `ReplicatedStorage/GameShared/Game/AudioRules`.
- `ReplicatedStorage/GameShared/Game/AudioAssets`.
- `ServerScriptService/GameServer/Game/RoundAudio`.
- `StarterPlayer/StarterPlayerScripts/GameClient/Controllers/AudioController`.
- `StarterPlayer/StarterPlayerScripts/GameClient/Controllers/MovementController`.

Все75Sources из `src` и три Fog Sources из `assets/CornfieldFog` должны точно совпадать с текущими файлами после нормализации CRLF. Остальные Sources должны также сохранять исходное содержимое baseline: изменение шестого Source или Fog отвергается даже при его совпадении с изменённым локальным файлом. Новый числовой аудио Asset ID входит в существующий AudioAssets Source; отдельного разрешения менять мир нет. Проверка сохранения не подтверждает доступность ID или воспроизведение звука.

Здесь нет прежних исключений resize manifest. Нельзя добавлять/удалять экземпляры, менять мир, Lighting, атрибуты, теги, Service metadata, SourceAssetId, ScriptGuid, Disabled, RunContext, Art, размеры или текстуры. Сохраняются исходные UniqueId, Name, классы и идентичности родителей. Сопоставление по UniqueId учитывает возможную перенумерацию экспортных суффиксов одноимённых объектов и приводит Ref к исходным идентичностям. Сырой неизвестный блок Terrain сверяется независимо от Lune DOM.

Прежние узкие метаданные редактора остаются допустимыми: конечные двенадцатикомпонентные Camera.CFrame/Focus и четыре корневых FilteredSelection с прежними именем/классом и уникальными корректными UID. CameraType, FOV и другие свойства камеры не получают исключений. В конце аудита повторно проверяются оба хэша файлов и все текущие Source/asset файлы, чтобы обнаружить изменения во время проверки.

После финального авторского Ctrl+S:

```powershell
. ./scripts/use-project-tools.ps1
python scripts/verify-rustle-comparison-copy.py place/Children_of_corn.before-rustle-comparison-20261015.rbxl place/Children_of_corn.rbxl --report .artifacts/playtests/2026-10-15-rustle-comparison/preservation.json
```

Для отдельной engine-сохранённой копии предусмотрен `scripts/promote-tested-rustle-comparison-copy.py`: обязательны ожидаемые хэши рабочего файла и кандидата, неизменяемый baseline, проверенный snapshot и backup, повторные проверки гонок и атомарная замена точных байтов. Кандидат должен пройти тот же strict checker. Сцены не пересоздаются и не сериализуются через Lune. Обычный Ctrl+S не требует promotion.

Fixtures `tests/rustle-comparison-copy-verifier.py` используют реальный checker, текущий Source snapshot и пять контролируемых Source версий с добавленным комментарием для проверки узкого списка. Проверяются отказ шестому Source/Fog даже при совпадении локальных файлов, неизменность мира/Lighting/art/identities, Camera metadata, CRLF и raw Terrain. `tests/rustle-comparison-promoter-guards.py` проверяет16 файловых защит только на временных placeholder bytes с подменённым checker. Эти тесты не являются проверкой звучания, Studio ввода или финального engine save.

Локальная приёмка pipeline: PASS,68 запрещённых DOM изменений и3 raw Terrain изменения отвергнуты; пять контролируемых Source версий приняты, допустимые Camera/selection metadata и CRLF приняты;16 promoter guards PASS. Четыре Python файла прошли py_compile. Результаты лежат в `.artifacts/playtests/2026-10-15-rustle-comparison/`. Финальный engine save проверен отдельно, как указано в начале; будущие изменённые engine saves требуют нового strict аудита.
