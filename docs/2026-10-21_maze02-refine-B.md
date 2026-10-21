# B: узкие тропы, плотная кукуруза и тени — 21 октября 2026

## Статус

По запросу автора тропы второго лабиринта уменьшены с 8 до 4 studs, плотность
кукурузы B увеличена на 30% на единицу площади, а видимые объекты мира и все
runtime-растения B получили `CastShadow=true`. Изменения установлены через
Studio MCP в проверенную `Children_of_corn_B.rbxl`, Studio
`8382bdc2-d369-4b51-97ec-08cd99cdad84`. Нативная установка, повтор без изменений
и новый обычный Play прошли.

**Engine Save и строгая проверка PASS/complete:true.** В 17:24:39 по Москве
Studio создала новый AutoRecovery; он прошёл полный аудит дважды и был перенесён
точными байтами в B через guarded atomic replacement, без сериализации.
Затем автор подтвердил Ctrl+S; рабочий файл независимо проверен повторно.
Финальный B1497688байт/SHA256
`b113d584f1a60e16f34ba4ec40ce051b0338cab712467f07d762d9fc8528b1d2`.
Первый AutoRecovery имел SHA256ea19ecda…; обе версии прошли тот же строгий
allowlist. [Финальный отчёт](../.artifacts/playtests/2026-10-21-maze02-refine/author-save-preservation.json),
[сохранение](../.artifacts/playtests/2026-10-21-maze02-refine/saved-scenes.json).
4634instances/157Sources,0adds/0deletes/0reindex,4точных Source-замены,
4050properties+4attrs; остальной мир/арт/Lighting/physics/mesh/identities/parents/
rawTerrain точны. A1491827/c1f05402… и старые архивы не изменены.

Итоговое состояние Studio: stopped Edit, 157 Sources, `CameraType.Fixed`,
`HttpEnabled=false`, без CornRoundRuntime, временных LocalScripts, тестового
куба, camera/focus bindings и транспортного `_G`-состояния. Финальный повтор
установщика дал ноль изменений. Все операции Studio выполнялись через MCP;
Windows-ввод, live Rojo, пересериализация сцен и другие игры не использовались.
Коммит, push и публикация не выполнялись.

## Исходный файл и сохранность

Принятый B до этой правки: 1 497 748 байт, SHA256
`108066bc0cf2a55f3c90d8db0ba7bef2eccb4a21351d5e9d53983fbcce8c50f3`.
Точные байты сохранены в неизменяемом
[before-refine.zip](../.artifacts/playtests/2026-10-21-maze02-refine/before-refine.zip),
entry `checkpoint/B-before-refine.rbxl`; SHA256 архива
`facdfe7e63fafd1eeb8fce784ec2172378db56c7b48ea306b1ec01e24105106e`.
Контрольные значения записаны в
[baseline.json](../.artifacts/playtests/2026-10-21-maze02-refine/baseline.json).

A не редактировалась и сохраняет 1 491 827 байт/SHA256
`c1f054029ca729f314889ce7874c17c6e5f772cb20541a9c0ceedd796f3446b7`.
Новые loose rbxl/rbxlx не создавались; прежние архивы сохранены.

## Тропы и количество растений

Граф, центры троп, четыре исходных угловых старта, все 15 slot ID и их позиции,
три проходных сарая и ворота сохранены. Ширина 100 trail masks уменьшена
8→4 studs; продолжение за концами рёбер уменьшено 4→2, чтобы соединения
сохранились без прежних широких выступов. Короткий подход к воротам, его колеи,
clearance и связанные road metadata согласованы с новой шириной. Сам проём
ворот остаётся 12 studs, сараи сохраняют физические размеры и проходы.

`CornLayout.BOX_PADDING` остаётся 1.5: ширина исключения центров растений теперь
7 вместо 11 studs, с прежним запасом на листья. Из ранее скрытых editor-растений
точечно возвращены 290; ещё 1151 остаются скрытыми. Editor overview по-прежнему
приблизительный. Обычный Play заново строит поле по актуальным исключениям.

В проверенной B `CornLayout.SpacingFor(field)` возвращает `3 / sqrt(1.3)` =
2.6311740579 studs; A и посторонние карты сохраняют шаг 3. Расчёт ячеек,
смещений, chunks, маскирования overview и backdrop stride использует один шаг.
Ширина chunk B — 31.5740886951, Far stride — 5.2623481158 studs. Высота10,
четыре формы/три LOD, радиусы, лимит Near576 и бюджеты создания сохранены.

Read-only [density-analysis.json](../.artifacts/playtests/2026-10-21-maze02-refine/density-analysis.json)
использует production `CellPosition` и `IsExcluded` с принятым B и 399 точными
path/editor deltas в приватной модели в памяти. Сцена не записывается.

| Состояние | Поле Far после исключений |
| --- | ---: |
| Прежние тропы и шаг | 7561 |
| Только узкие тропы | 8847 |
| Только новый шаг | 9709 |
| Узкие тропы и новый шаг | 11180 |

Плотность на единицу площади увеличилась ровно на 30%. Общий Far count вырос
на 47.864%, поскольку узкие тропы отдельно освобождают место для кукурузы.
Конечная сетка содержит 14161 Far candidate cells, из них 2981 исключены;
лимит20000 не достигнут. На конечном поле границы сетки и исключения объясняют,
почему изолированное изменение шага даёт +28.409% фактических Far-растений.

## Тени и узкие Source-изменения

Из 157 существующих Sources изменены только четыре:

- `CornLayout`: отдельный шаг B с проверкой FieldZone/CornMap/project/variant.
- `CornController`: согласованный шаг и тени всех BaseParts нового B-клона
  до его помещения в runtime, на каждом LOD.
- `CornBackdropController`: тот же шаг и тени всех Far-клонов до публикации.
- `CornShadowController`: прежний ограниченный выбор casters отключён для B;
  поведение A с лимитом256 и scan1296 сохранено.

Оставшиеся 153 Sources сохранены. В частности, B сохраняет прежний Warden,
геометрические шаблоны и CornAppearance. Изменения всего текущего `src`
поверх сцены не устанавливались.

У существующих world BaseParts включены 3653 флага `CastShadow`; два связанных
атрибута `HarvestCastShadow` согласованы, чтобы штатный HarvestWorld принял арт.
В Edit частей мира с `CastShadow=false` не осталось. В Play все видимые части
карты и все near/Far растения имеют тени. Шесть невидимых звуковых anchors
создаются с прежним `CastShadow=false`; они не видны и не влияют на силуэты.
Личные camera viewmodels сохранены. Реальные main/fill фонаря имеют
`Shadows=true`; прежний слабый HandFill с дальностью1.5 сохраняет `false`.
Яркость, угол, дальность и Pitch основного фонаря не менялись.

Новые ограничения обнаружения внутри кукурузы не добавлялись. Она по-прежнему
проходима и закрывает обзор человеку; серверное AI concealment остаётся
отдельной задачей. Радиусы48/96, финальные120секунд, общий ключ/ворота,
индивидуальные поимки и награда+20 не менялись.

## Установка и нативная проверка

[pipeline-manifest.json](../.artifacts/playtests/2026-10-21-maze02-refine/pipeline-manifest.json)
фиксирует payload6 595 004байт/SHA256
`2b4c993ff531bb96fe5f7e8099327f437f60d2b7d8871810a45134fd294c4217`.
Он содержит 4 Source replacements и 4054 изменения мира: 4050 свойств и
4 атрибута. Из них399 — тропы/подход/editor,3653 — world CastShadow и
2 — Harvest shadow metadata. Новых instances, удалений или reparenting нет.

Полный preflight проверил4315instances и все157Sources. Установщик принимает
только целое исходное либо целое установленное состояние; неизвестные ручные
правки и частичная установка отклоняются, ошибки собственной записи
откатываются. Native apply дал `changedSources=4 / changedProperties=4054`,
повтор — `0 / 0`.

[native-acceptance.json](../.artifacts/playtests/2026-10-21-maze02-refine/native-acceptance.json):
обычный Bootstrap подготовил Farm40/HarvestB244 и17контроллеров. Far Ready=true,
LoadedPlants=11180 точно совпал с анализом; у всех11180 Far и1532 near частей
`CastShadow=true`. Старый ограниченный shadow controller в B отключён.

Через MCP character navigation выполнен наземный проход примерно24studs по
узкой тропе: старт `(-288.75,17.4,-270)`, фактический конец
`(-288.74994,17.39801,-246.78888)`. До движения Root выставлялся диагностически;
это проверка проходимости, а не полный слепой маршрут. GPU с кукурузой и
собственным тестовым кубом при on/off фонаря осмотрен. Куб и вся диагностика
после проверки удалены.

Собраны60кадров короткой проверки. Они не заменяют длительный FPS, человеческую
приёмку теней/формы круга, обычный полный лабиринт, четыре клиента или проверку
страха и звукового микса.

## Проверки и workflow сохранения

[check.log](../.artifacts/playtests/2026-10-21-maze02-refine/check.log): check.ps1
PASS, cached Selene0errors/0warnings/0parse errors, code-only build/sourcemap и
safe mappings. Generated code-only scene после проверки удалена.

- [corn-density-all-shadows.luau](../tests/corn-density-all-shadows.luau):
  5578assertions PASS; A layout/lifecycle/cap/foreign edits, B grid/strides,
  shadow flags до публикации всех near LOD/Far и отключение прежнего B выбора.
  Текущий `corn-backdrop.luau` для A также PASS.
- [maze02-refine-installer.luau](../tests/maze02-refine-installer.luau):
  106assertions/34refusals/10rollback points PASS, включая полный payload
  4054changes/4Sources/4315guards.
- [maze02-refine-save.py](../tests/maze02-refine-save.py):
  29DOM/15manifest/3rawTerrain refusals и10frozen partial-state refusals PASS.
  Положительные случаи полного manifest, конечной Camera, FilteredSelection и
  доказанного по UID sibling reindex проверены без записи сцен.

Это актуальные перечисленные fixtures. Старые проверки с шагом B=3 и
ограниченным B casting относятся к прежней реализации.

Workflow: [plan-maze02-narrow.py](../scripts/plan-maze02-narrow.py) →
[build-maze02-refine-payload.py](../scripts/build-maze02-refine-payload.py) →
[maze02-refine-native-core.luau](../scripts/maze02-refine-native-core.luau)/
[install-maze02-refine.luau](../scripts/install-maze02-refine.luau).
Расчёт количества растений повторяется
[analyze-maze02-refine-density.luau](../scripts/analyze-maze02-refine-density.luau)
с точным baseline108066; по умолчанию helper читает ZIP прямо в память без
дополнительной loose сцены. Installer fixture также использует immutableZIP.

После engine Save проверять новый файл нужно refinement verifier:

```powershell
python scripts/verify-maze02-refine-copy.py place/Children_of_corn_B.rbxl --report .artifacts/playtests/2026-10-21-maze02-refine/preservation.json
```

Verifier читает неизменяемый108066baseline из ZIP во внешний temporary
directory и допускает только замороженный manifest, четыре точных Sources и
узкие editor metadata. Остальные Sources, исходные identities/classes/names/
parents, world/art/Lighting/physics/mesh metadata и raw Terrain должны остаться
точными. Старые maze02/shadow-only verifiers не предназначены для этой версии.
Новые ручные изменения автора следует сохранить и отдельно разобрать.
