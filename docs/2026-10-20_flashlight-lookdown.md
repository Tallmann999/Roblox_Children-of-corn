# Фонарик A: освещение Realistic — сохранено 2026-10-20

Автор посмотрел временное переключение Soft→Realistic и подтвердил:
«надо освещение делать Realistic, вот так выглядит круче».
В A закреплено Lighting.LightingStyle=Realistic непосредственно в сцене.
Это работает в Edit и Play для всех участников. Код фонаря, его положение,
линзовые SpotLight, временная панель и банк постоянных параметров не менялись.

Сохранён Children_of_corn.rbxl:1491821bytes/SHA256
`bc85bd9b294a992b0fdff8979b5f56885f0292e12402f51573d613f7acc0ad3f`.
Immutable before-flashlight-lookdown-20261020.rbxl1491650/4c8d831b… сохранён точно.
Отдельный B1485700/e34fe75f… и предыдущий author backup1487942/bdda… неизменны.

## Диагностика

Видео автора D:/Desktop/2026-10-20 13-23-46.mp4:27.40s/1280×720/30fps,
21143871bytes/SHA256546de57968c0aeac33b3eb793e67ade83d563b93cf8f84a72f90aa0513a051dd.
Просмотрены12кадров: впереди светлая кукуруза, при наклоне вниз почти чёрная земля.
Первый pitch probe0/−35/−60/−75/−80/−85 измерил линзу3.21…3.98stud над Ground;
провала источника под землю в этих позах нет. Фонарь тогда был OFF — только геометрия.
Soft/PrioritizeLightingQuality=true/Automatic были исходными настройками.
Официальное описание [Realistic/Soft](https://create.roblox.com/docs/environment/lighting#lightingstyle)
соответствует выбранному направлению. Объяснение через конкретный внутренний размер
сетки рендера не доказывалось. Автор принял внешний вид Realistic, отдельного
контролируемого сравнения обоих режимов при одинаковом качестве/позе не выполнялось.

## Авторская работа, сохранённая вместе с исправлением

Перед Ctrl+S обнаружен новый авторский Workspace.Part с дочерним SpotLight,
отсутствовавший в baseline. Мы его не создавали и не меняли. Оба объекта сохранены.
Независимый native inspect до Save записал их UID, полные читаемые свойства,
родителей и детей в author-part-before-save.json/SHA256
`e76c1b34bec0d307f4e0d80a93915a2edd1f8d7762ebcbca41b49bf2cedba385`.
Part UID42f159d6c65591c90ae8a38b00004de8,1.8×0.39999998×8.7,
позиция−4.9/20.754341/−8.215997,наклон−10°,Anchoredfalse/CanCollidetrue,
обычный серый Plastic. Spot UID…4f86,90°/24/10/white/Front/Enabled/noShadows.
FormFactor.Brick подтверждён отдельным native read. Скрытые/default поля строго
сверены с immutable Baseplate и исходным Wide; frame/size — точные native float32,
без произвольной структуры или допуска дополнительных детей/свойств/метаданных.

## Проверки

check.ps1 PASS:StyLua/Selene cached API0errors/0warnings/0parse/code-onlyRojo/safe
mappings/persistencefalse. Итоговый production Source полностью равен принятому
156-Source payload предыдущего checkpoint. Подготовленный ранее клиентский
Source-only эксперимент НЕ установлен; предложение осталось в evidence отдельно.

Guarded install-flashlight-lookdown.luau сначала проверяет все156Sources/классы,
остановленный Corn A/630world/чужие корни/открытые script tabs, затем меняет ровно
LightingStyle.Soft→Realistic с rollback. Native changedProperties1/Sources0/add0,
repeat0; после Play ещё repeat0. Fixture11unsafe/rollback refusals PASS.
Save fixture257DOM/3rawTerrain refusals и2validCamera frames PASS, включая каждое свойство авторской заготовки.
Новые pipeline/fixture не пишут .rbxl и не запускают liveRojo/publishing.

Normal bootstrap/настоящие UI Start/Confirm/ЛКМ/Space, один реальный клиент.
Server и Client сохранили Realistic после старта; старый runtime LightingModes его
не перезаписывает. Финальный same-context observer100samples/6.333249s:
92grounded+8air,100%exact-owned и ON, ось Spot совпадает с линзой,
луч вниз попадает в Ground. Настоящий Space изменял Humanoid state/высоту;
Root не перемещался диагностикой. Pitch−80° и focus/cursor стабилизированы
временными owned bindings199/200.5: это не физический mouse-look/blind round.
Первая попытка с открытым Alt и OFF не является доказательством видимого луча.
MCP теперь возвратил настоящий кадр мира: native-grounded-realistic.jpg показывает
землю/листья при взгляде вниз. Это не принятие общего баланса яркости/FPS/страха.
Все observer Scripts/bindings удалены перед Stop/Save.

Строгий read-only preservation.json PASS/complete:true:4527→4529instances,
0Source changes/156exactSources,1LightingStyle,2точно зафиксированных авторских
объекта; ни одной потери/перепривязки исходных identities/classes/names/parents,
прежний world/art/Lighting/mesh metadata/rawTerrain точны кроме разрешённого стиля
и конечных Camera.CFrame/Focus. Обычный Ctrl+S через computer-use в уникальном
Corn окне; соседнее Speed Monkey не управлялось. Windows capture по-прежнему
даёт FrameArrived timeout; сохранение прошло через screenshot-free accessibility.

Workflow: build-flashlight-lookdown-installer.py → install-flashlight-lookdown.luau.
Все будущие engine saves сравнивать verify-flashlight-lookdown-copy.py с immutable
before-flashlight-lookdown; этот guard уже учитывает два авторских объекта.
Предыдущие payload/baseline не перезаписывать.

Перед Stop записаны текущие временные значения панели:
Wide brightness2/angle100/range32,Core13/30/range4,Pitch−4.
Editor bank по-прежнему54°/24/15.08 и26°/24/22.62,Pitch−6;
выбор Realistic сам по себе не утверждает новые постоянные параметры фонаря.
Временные значения восстановлены для продолжения Play после сохранения.
Evidence: .artifacts/playtests/2026-10-20-flashlight-lookdown/.
