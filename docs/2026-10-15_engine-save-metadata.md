# Три служебных свойства в engine save — 2026-10-15

После подтверждённого автором Ctrl+S файл `place/Children_of_corn.rbxl` имеет 1019419 bytes, SHA-256 `a897bb52fa85505090f973e910139915e6ebb2995e44915c31ecbc2b5c511dca`. Immutable before-finale остаётся 1015691 bytes, SHA-256 `9082169a7da5fed15cd962611777285213fce99f23de82f83e0f361a683ecf16`.

Полный read-only known DOM diff: 6839→6839 instances, без добавлений/удалений/смен классов. Помимо 75 разрешённых Sources, 54 fixed torch CFrames и прежних разрешённых editor metadata, найдены ровно три добавленных свойства:

| Точный путь и класс | Свойство | Сохранённый literal |
| --- | --- | --- |
| StarterPlayer / StarterPlayer | UseImprovedCharacterEvents | token 0 |
| AvatarSettings / AvatarSettings | RulesSchemaVersion | int 0 |
| Packages / Packages | OverridesRecalculated | bool false |

В baseline все три свойства отсутствуют. AvatarSettings и Packages в обоих файлах имеют 0 children/descendants, пустые Attributes и Tags; никакого авторского package content не появилось. StarterPlayer сохраняет 2 children/23 descendants и пустые Attributes/Tags. Все исходные свойства и существующая иерархия проверяются прежними строгими правилами.

Независимое доказательство engine defaults получить не удалось. Bundled Lune reflection 0.728.0.7280895, локальный Selene dump и установленный ReflectionMetadata.xml этих полей не содержат. Native Play probe не смог прочитать их как доступные свойства новых сервисов. Значение Enum.RolloutState.Default=0 известно отдельно, но само по себе не доказывает тип или default нового скрытого поля. Причина появления полей и смена версии движка не установлены.

Для этого подтверждённого engine save принята узкая аудированная exception в `scripts/verify-finale-copy.py`: только exact path + exact class + отсутствие свойства в фиксированном baseline + точный literal с типом и пустым payload. Reason — `audited_engine_save_service_metadata`, в report каждое дополнение содержит `default_unverified=true`. Это не общее разрешение новых свойств и не утверждение доказанных engine defaults.

Любой другой путь, класс, тип, ненулевое/true значение, nested payload, отсутствие одного из трёх обязательных полей, новая посторонняя property или удаление исходной property отклоняются. Historical readability verifier и scene bytes не менялись. World, Lighting, art, raw Terrain и Model pivots продолжают проверяться строго; единственный world allowlist — прежние 54 fixed Part CFrames.
