# Погоня, поимка, выбор и вывеска — 2026-10-14

Scope: local solo PC, Children_of_corn only,75Sources/6839persistentinstances. Первое обнаружение за раунд получает10сек при текущем серверном WalkSpeed, затем patrol/grace1; поздние погони прежние. После1сек поимки первая ждёт validatedrevive/menu, вторая — новый retry через прежний objective. Локальный рот/headshake/camerashake/краска. Автор явно разрешил вывеску3×/мигание/дальнюю видимость; постоянные изменения только Size/CFrame/PixelsPerStud48→16; AlwaysOnTopfalseсохранён. Rojo live остановлен, соседняя Moon_Test_animation не затронута.

## Фактическая проверка

- scripts/check.ps1 PASS: StyLua/Selene0errors/0warnings/0parse, code-only build/sourcemap/safe mappings/persistence disabled; cached Roblox API dump после сетевой ошибки.
- Local first-chase, hunt-quality, monster-trap, round-intro, mode-photo-cards, capture-presentation, gate-hint, round-audio, rustle-client/audio regression PASS.
- Engine first-chase PASS: real isolated Parts/Humanoid/LOS, current server methods, controlled logical clocks. Скорости12/18/24/36, noCapture2s, deadline10beforecapture, grace1, subsequent10→13, consumption across trap/capture/home/LOS/protection и stale route cancellation. first-engine.json.
- Engine server choices PASS: originalcharacter/owner/phase/rate/duplicate/early/foreign validation, firsthold/revive key+consumables+map+elapsed/protection; firstmenu cleanup, secondterminal/epoch abort. choices-engine.json.
- Engine client actual GUI fixture PASS: firstpopup, secondobjective/Back/Confirm, hidden/modal/busy/malformed/snapshot guards. intro-engine.json.
- Engine capture presentation PASS:13parts/21paintdrops/headgroup/camera/Rootimmutable/cleanup/foreign guards. capture-engine.json.
- Рабочая первая настоящая LOS поимка после диагностического размещения у NPC:15camera/visualframes,14headchanges,7paintframes, max13parts/mouthheight1.3, FOVmin62→70, Custom/Humanoid восстановлены, visual/paint удалены, окноmodal. realFirstCapture.json.
- Настоящий native click Возрождение: тот же угол(385,17.398,-385), speed12, NPCpatrol/activeHUD/popupgone. realRevive.json.
- Настоящая вторая поимка: terminal/popup, NPC удалён. Native Возрождение→objective с тем же режимом; Back→popup; Возрождение→Confirm→новый раунд. realSecondCapture.json/realRetryGoal.json.
- Настоящая первая поимка нового раунда→native Выход: modecards/start видимы, popup/activeHUD/NPC удалены, вывескаrestoreEnabled/LTM0. realExitMenu.json. Поле active в сыром отчёте означает notActiveStatus.Visible, а не phaseactive.
- Mouth-paint-gpu.png: native GPU кадр статического controlledpreview показывает большой открытый рот/зубы/глаза и цветную краску. Движение/cleanup проверены отдельно. Preview и диагностическая постановка catch не объявляются обычным прохождением или страхом.
- FinalExit guarded installer: Size/CFrame3× иPixelsPerStud48→16. ПромежуточныйAOTtrue послеforegroundGPU superseded: finalAOTfalseсохранён. PPS16 сохраняетcanvasисходным, физическиувеличиваетбуквы×3; loweredgeexact. finalPhysicalSignInstall.json.
- FinalGateHintController:3ownedGUIinstances/ScreenGui/TextLabel/UIStroke,10Hz/min96×26max600×160/distance≤1300/front/onscreen/fieldnormal; active/caughtlivingexceptactualcapture. NoRoot/camerawrites/fieldscan. Adapterprojection/phase/death/capturehide/foreignGUI/identity/cleanup PASS.
- ProductionGPU: «ВЫХОД» читаетсяс570studs вday/night/dusk, крупныйnear39.7studкадр. exit-night-far.jpg/exit-near.jpg; другиеnativeGPUкадрыданывчате. Источникданных—рабочийконтроллер, постановкакамерыдиагностическая; noordinaryblindroundclaim.
- Finalactualnightblink20samples10on/10off: Surface suppressed, GUIEnabled/LTM0or1coherent. Nativeabort/menu removesownedGUI/restoresSurface.Enabled+LTM0. exit-render-acceptance.json/beaconActualMenuCleanup.json. Раннийblink-engine.json относитсяксupersededSurface-onlyварианту.
- Finallocalguards: initial3props/repeat0/bothknownmigrations,16refusals/injectedSize/PPS/AOTresetrollback PASS; verifier75/6839/noadditions/3fixedprops/19DOMnegative+3rawTerrainnegative PASS; promoter16tempguardcases PASS.
- Ранниеblank3Dкадрынеacceptance: пользовательforeground/clickviewportвосстановилотрисовку. NearnormalSurfacefalse показалбуквы; overlaySurfacetrue не показал. ДополнительныеSource/worldпоправкипримененылишькразрешённойвывеске. Всеcamera/probe callbacks/GUI удаленыStop. Duskprobe exact-equality ClockTime assertionfailed; значениеневыдаётсязаengineassertPASS, actualHUD«Средне»иnativeGPUподтвердилирежим.

## Сохранение

FinalEdit75Source equalitycreated0/changed0PASS; FarmGeometry.Ensure40targets/applied0/built0/pending0, CameraTypeFixedmatchesimmutablebaseline. StudioleftEdit; Rojo live stopped.

Рабочий .rbxl СОХРАНЁН exactengineAutoRecovery19:05:32:1015691байт/SHA2569082169a7da5fed15cd962611777285213fce99f23de82f83e0f361a683ecf16. verify-escape-copy.py PASS:75Sources=src,6839instances/noadditions, only3fixedexitworldprops+Sources/editorpose, allotherart/worldLighting/rawTerrainexact. Guardedpromote-tested-escape-copy.py atomicallyreplacedworkingfileafterbothhashguards; independentGetFileHashconfirmed. saved-scene.json/preservation.json. NoLune serialization.

Immutablebefore-rustle1009332байт/hash ef0731f3235a26e4aa76dd26a7853be4d67e9ccc934f4f054428e5cbd6d146f0 remainsunchanged. OldAutoRecovery16:53 refused; earlierA5AOTcandidate notpromotedasfinal.

Обычный blind fullround7–10мин, новый длительный FPS/человеческийfear/микс/reopen и баланс8studsafeperch не приняты этим тестом. [MVP audit](2026-10-14_mvp-readiness.md).
