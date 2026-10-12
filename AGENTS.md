# Project Agent Rules

- Read `docs/` before implementation.
- Keep current MVP scope explicit.
- Server-authoritative gameplay/economy/persistence/purchases.
- Client requests are untrusted and must be validated.
- Prefer Tags + Attributes for world binding.
- Do not modify/delete Workspace content without explicit task scope.
- Rojo owns only the configured code containers unless architecture docs explicitly say otherwise.
- Every completed feature requires an actual test result, not only code generation.
- If blocked by a manual/auth/Studio/account step, provide exact numbered steps and resume after the user reports success.

## Children of Corn scope

- Current milestone: persistent editable CornMap 1200 x 1200 studs and key/gate/escape/retry. User explicitly authorized authoring this map in Children_of_corn only. Preserve imported art and unrelated scene content; use a backed-up guarded installer or verified new file. Key/gate/escape/retry received live Studio acceptance on 2026-10-10; distant overview quality and long-run performance remain pending; the tested scene is saved.
- Source of truth: docs/project-concept.md and docs/2026-10-09_core-loop_gd-spec.md.
- Local solo PC prototype. No persistence, purchases, lobby, public publishing or multiplayer in this milestone.
- Use scripts/use-project-tools.ps1 for the project-local toolchain. Run scripts/check.ps1 after code changes.
- Keep world tags and remote contracts in docs/architecture.md before implementing them.

## Studio target correction (2026-10-09)

- Work only on place/Children_of_corn.rbxl in this project. Never connect this project's Rojo server to New_+1 speed monkey or another Studio scene.
- ChildrenOfCorn Rojo was stopped after an accidental connection to Speed Monkey. Do not restart live sync until the correct Studio scene is verified. See docs/2026-10-09_wrong-scene-cleanup.md.


- User reported the Speed Monkey cleanup complete and resumed Children_of_corn work. Live Rojo remains stopped; protected file/Command Bar installation is preferred until the correct Studio target is verified.

- Repair scope: four authored corner SpawnLocations, server-selected start and full-field overview plus dense nearby corn. Preserve existing map geometry and source asset. The saved lower Workspace/SpawnLocation may be disabled only by the guarded Corn repair with rollback. Use scripts/repair-corn-scene.luau for installed maps; live spawn/key-loop acceptance passed on 2026-10-10. Distant overview quality remains open.

- The saved corner-spawn repair is installed. Preserve the author’s current CornMap/baseplate coordinates. Correct flat EditorFieldOverview only with guarded scripts/fix-corn-proportions.luau: normal aspect ratio, owned Size changes in place, one MapAuthoring leaf update, rollback. Dense local Preview/runtime and sparse whole-field overview are distinct; do not stretch X/Z to claim dense distant corn. Studio MCP is live through the official STDIO interface. Verified Children_of_corn studio_id on 2026-10-10: 2aca50b7-fc16-4a1c-aac0-299372b05b92; re-list after any Studio restart.


## Autonomous follow-up 2026-10-10

- User authorized completing/testing the current feature and immediately implementing the next without confirmation while away. Key/gate/escape/retry and first_person_movement are now installed and tested in the verified Children_of_corn window. See docs/2026-10-10_studio-playtest.md.
- Server-authoritative stamina: sprint 4 seconds/refill 6; first-person client camera and HUD. Twenty live Sources match src. New guarded code-only installer: scripts/install-movement.luau; regenerate with scripts/check.ps1 then build-movement-installer.py. Historical owned Source versions are explicitly fingerprinted; refuse unknown manual edits.
- Preserve current map/baseplate/art. Rojo remains stopped. No monster, captures, sounds, persistence, purchases, lobby, publishing or multiplayer were implemented in this follow-up.
- The tested .rbxl is now saved: the engine-generated AutoRecovery 13:20:08 was strictly verified and atomically copied over the original after checking both the working-file and baseline-backup hashes. No Lune reserialization. SHA-256 c4d027d34540118cb1c037f00bb4efd0dbb3d673a0a4194c03968ea28d577cb8, 141703 bytes. All original props/art/CFrames and raw Terrain preserved; only approved overview sizes/annotations, code and editor camera pose differ. Exact pre-edit backup: place/Children_of_corn.before-live-proportion-fix-20261010.rbxl. Revalidate any future recovery candidate with scripts/verify-tested-corn-copy.py before file replacement.


## Current map/hunt scope 2026-10-10 (supersedes 1200/20-source history)

- User authorized side reduction 30% to 840, night torch poles at all 15 slots and two per house, optimized elevated corn view and deterministic position/yaw/height variation, then the next feature. Map relocation preserves human-scale props, Ground height, Baseplate and imported art.
- Map v3: MapTuningVersion=1, TorchClearanceVersion=1; 21 torches, 4977 overview/1187 preview; 22 Sources. Server hunt and two catches passed engine tests; see docs/2026-10-10_map-tuning-and-hunt-playtest.md. Full sound/fear/search-duration/FPS acceptance remains pending.
- Use scripts/check.ps1 then scripts/build-hunt-installer.py and guarded scripts/install-hunt.luau only in verified Children_of_corn Edit. Do not replay historical 1200/20-source installers. Repeated current installer must preserve authored map; unknown Source edits/open script tabs cause refusal.
- Promote only engine-saved copies after scripts/verify-hunt-copy.py, source equality and original/raw Terrain preservation checks; retain pre-edit backups and guard both hashes before atomic replacement. No Lune reserialization of the scene.
- Final tested scene saved from engine AutoRecovery 16:35:39: 228018 bytes, SHA-256 c2a58d56a1adf964dd617e5eca81fb6e83707b79a9244adae4f45739aa27e5e1. Exact author-save backup: place/Children_of_corn.before-map-tuning-author-save-20261010.rbxl. All 22 Sources verified; original CameraType restored after a timed-out MCP capture. Keep working on this Corn file only.

## Lighting modes and minimap documentation 2026-10-10

- Current code-only feature `lighting_modes` installed, live tested and saved: easy/day 13:30, medium/dusk 17:54 + torches, hard/night 20:30 + light fog. Only illumination/visibility differ. Hunt/sprint/key/reward rules and all authored world/Lighting/art remain intact. See docs/2026-10-10_lighting-modes-playtest.md.
- Current scene has 23 Sources. Use scripts/check.ps1 then scripts/build-modes-installer.py and guarded scripts/install-modes.luau in verified Children_of_corn Edit. Historical 1200/20/22-source installers are superseded; never replay them for this scene. Unknown Source edits/open tabs refuse installation.
- `minimap` is documented/planned only in docs/2026-10-10_minimap_gd-spec.md and feature-index. No minimap UI, world zones or gameplay code installed. Reset/preserve rules and unresolved choices are explicitly proposals/TBD.
- Final exact engine AutoRecovery 17:53:10 promoted after scripts/verify-modes-copy.py: 231503 bytes, SHA-256 6fa3c8f2bc14481bfd5122101b421d205e5122d07ca2f508eb8eb792722f7df4; 23 Sources equal src, all original world/Lighting/art/raw Terrain preserved. Exact pre-feature backup: place/Children_of_corn.before-lighting-modes-20261010.rbxl. Future engine saves use verify-modes-copy.py and guarded promote-tested-modes-copy.py; no Lune reserialization. Rojo remains stopped; Studio left in Edit.

## Current minimap scope 2026-10-10 (supersedes 23-source/planned history)

- User selected minimap next and deferred sounds until their own asset selection. Compact arrow, visited crosses, red skulls and expanded map are installed, tested and saved. Server owns 15-slot/3-house visits and capture/death history; no new world geometry/tags or hidden key/monster markers. First catch preserves; retry clears. M/Alt/mouse and real visits/catches/death/Reset/corners passed. Physical Escape is manual pending because official MCP rejects CoreGUI keys; actual engine handler passed. See docs/2026-10-10_minimap-playtest.md for exact manual steps.
- Current 27 Sources. Use scripts/check.ps1 then scripts/build-minimap-installer.py and guarded scripts/install-minimap.luau only in verified Children_of_corn Edit. Historical modes/hunt/movement installers are superseded; never replay them. Preserve current map/Baseplate/imported art/Lighting/raw Terrain. Rojo remains stopped.
- Saved exact engine AutoRecovery 18:43:10: 236519 bytes, SHA-256 38714df503f02abce02d5555533d7f4949f384690a1a75d9135cfe655015e1fa. Exact author baseline backup: place/Children_of_corn.before-minimap-20261010.rbxl (ccf9eabe433f68f4d4a3f9455da2c759de44003c179f25ac4234241b574c0679). All 27 Sources equal src; author world/Lighting/art/raw Terrain preserved. Use scripts/verify-minimap-copy.py against this backup or the current saved 27-source file; guarded scripts/promote-tested-minimap-copy.py preserves both hashes for future exact engine copies. No Lune serialization. Studio left in Edit. Full ordinary search/fear/FPS acceptance remains pending.

## Current quality work 2026-10-10 (supersedes minimap-only installer)

- User requested distant corn/FPS, ordinary search/escape/fear testing and physical Esc; sound assets are explicitly deferred. Physical Esc was author-confirmed: closes expanded map and M reopens after Resume.
- Current src/build is28Sources. Only code changes: client far backdrop19715 real plants at6studs, normal aspect/variation and inherited Automatic; event-invalidated coverage/LOD hysteresis; independent patrol, LOS/last-seen chase13/lose42 for1.25s; red chase warning. Map840/author geometry/art/Lighting/raw Terrain stay exact. Use scripts/check.ps1 then scripts/build-quality-installer.py and guarded scripts/install-quality.luau only in verified Children_of_corn stopped Edit. Earlier installers are historical.
- Final local fixtures and check.ps1 PASS. Final LocalScript Automatic measured603seconds/~59.85FPS/p95~19ms on GTX1060 6GB/i5-4460,1914x801, Studio foreground; background15FPS excluded. See docs/2026-10-10_quality-playtest.md for limits and actual artifacts. This does not imply human fear or successful duration acceptance.
- IN PROGRESS: Studio Play has28Sources, but latest MonsterHunt._state async-route cancellation fix is in src/build, not installed yet. Install it after the pending real E interaction; rerun tests/studio-hunt-quality.luau and Source equality.
- Ordinary blind route15/15 clearings reached479.865seconds with one real catch/return. Camera did not show the key at feet in first clearing; afterwards diagnostic ordinary walking returned to key(252,14.82,-252). Current official MCP E is blocked by CoreGUI focus; GuiService.MenuIsOpen=true. Pending author step: Resume, click game viewport, look down, E, report pickup. Do not replace that test with remote/prompt forging or claim successful full round. Continue key→gate→exit/reward/retry and real sprint after unblock.
- SAVED FILE STILL27Sources,236519bytes,SHA25638714df503f02abce02d5555533d7f4949f384690a1a75d9135cfe655015e1fa. Exact backup place/Children_of_corn.before-quality-20261010.rbxl has identical bytes. AutoRecovery last checked19:18:10 is also old27Source; never promote it as new quality.
- Final engine save must pass scripts/verify-quality-copy.py(28Sources=src, exact world/Lighting/art/raw Terrain), then scripts/promote-tested-quality-copy.py with both current/candidate hashes. First backup is immutable; repeat saves get a hash-named backup. No Lune serialization. Final save/hash and elevated/day/dusk/night/retry results remain to document. Rojo remains stopped.


## Current farm scope2026-10-12 (supersedes28-source quality)

- User chose EditableMesh and parallel Studio MCP without native mouse. Only Children_of_corn target28de7d0d-d3bd-4063-9fe7-5d5b2beacfce; re-list after restart. Rojo stopped. Neighbor scenes untouched.
- Saved60Sources,981060bytes, SHA2566f9a95e624a96ab6c318a4a1912db0c5aae7b6d6e1dfa0d92f70dcc97638e03a. Immutable before-autumn backup239719bytes/hash0e8a382fcd5b3e61f696e5e40ffa7a33a45436058aa9544ec2b409e4de89e410. Exactengine copy promoted with strict331world/33code additions,223 approved original deltas,3 originalHouse archive moves and rawTerrain preservation. See docs/2026-10-12_farm-playtest.md.
- Four supplied FBX preserved; Barn03x3, crookedTruck,5tyres/3rubbish, road840,8row+2wall45 torches/neon/STOP and3actual modephotos installed/tested. Source atlas fixedtoexact Farm01A95855894892409; originalcorn137803536172445 untouched. End-color after correction and actual reopen remain pending; no claim new FPS/humanfear/ordinaryfullround. Sounds deferred.
- EditableMesh Objects have no permanent uploaded URI (CreateAssetAsync unavailable). Geometry saved in23data Sources; all60Source limit<200000. ServerService15 reconstructs40targets; clientController40 usesfixedcache/streamingAtomic. Bootstrap waitsserverbindings/art60sec beforecontrollers. RegularScript/LocalScript, actualbarnentry/truckbypass/liveSTOP/modeImages testsPASS. New count60.
- After opening Edit restore farm geometry with scripts/restore-farm-editor.luau (or require(game.ServerScriptService.GameServer.Game.FarmGeometry).Ensure()). Play restoreautomatic. FirstverifycorrectScene, Sourceequality and unknown/manual edits. Do not replayhistoricalmovement/modes/minimap/quality/autumnworld installers.
- Use check.ps1 then build-farm-installer.py/install-farm.luau code-only guard. World installer install-farm-world.luau only for matching initial/repeatfarmstate; originals archived. Do not replayoldopen-barns overnewFBXhouses. SavedScene updates require verify-farm-copy.py with audited build/farm-world-allowlist.json and guardedhashpromotion. No Lune scene serialization.

## Current inventory scope 2026-10-12 (supersedes farm installer)

- User authorized inventory5slots,2energy/2traps/1key on all modes, recognizable key,half-bright torches and4exit poles(2wall45 retained). General wind canceled after severe lag: only2contact/front plants plus2near moving NPC, max4/32parts,12Hz/5Hz. Sounds still deferred.
- Saved by author Ctrl+S and strict verified:65Sources,989746bytes,SHA25695d87061a83808a139da4c98c7552b65b3c8e86137dff5f472c362c7fd984d5d. Immutable baseline place/Children_of_corn.before-inventory-20261012.rbxl981060bytes/hash6f9a95e624a96ab6c318a4a1912db0c5aae7b6d6e1dfa0d92f70dcc97638e03a. See docs/2026-10-12_inventory-playtest.md.
- Server owns slots/selection/energy×2/30sec/traps/NPC10sec. request_inventory_action(select/use,slot1..5) validates owner/phase/alive/rate/selecteditem andworldpromptpriority. Firstcatch retainsconsumables,dropskey,clearsboost;terminal/retry clearsall. Runtime owned bindings only, no persistent hidden-item markers.
- Real E energy pickup/use andspeed24,real E trap pickup/place,controlled liveNPCtrap→trapped→patrol PASS. Engine isolatedround/NPC/actualGUI andlocalfixtures/check.ps1 PASS. Author confirmed physical1–5 work andhard no severe lag; mixed-focus FPS isnotcleanbenchmark; no ordinaryfullround/fear guarantee. Pink cloudtassels actuallycream/meshcolorswhite;mediumambientneutralized,assetsunchanged.
- Torch updater archives4exactmodels,remaining27lights2→1,4groundexitPolesX±14Z409/385. Strict save verifier permitsonlythese35propertydeltas/20archivedinstances/6codefolderadditions andpreserves rawTerrain/allotherart/world. Use check.ps1 then build-inventory-installer.py/install-inventory.luau only inverifiedChildren_of_corn Edit. Earlier farm/autumn/quality installers superseded. UnknownSource/openScript refusals stay. Future engine save verify-inventory-copy.py andguarded promote-tested-inventory-copy.py; no Lune scene serialization. FarmEditrestore still required afterreopen,Playautomatic. Neighbor scenes untouched.

## Current scarecrow presentation 2026-10-12 (supersedes inventory installer)

- User authorized proceduralNPCanimation andcapture scene; sounds later. One ownedruntimeNPC with9namedvisualParts,30Hz/9writes/0Rootwrites; patrol/chase/trapped/capturing. No new persistent world changes/remotes. Both catches phase=caught1sec, first→active/second→caught_out; serverepoch/LOS/capture remainauthoritative. Snapshot capture={id0..2,remaining0..1,frame:CFrame}, shownonlyafteractualcatch. Client ownedcamera/copycleanup+fourstudvisualoffset, originalruntimeLTM guardedrestore, nofieldanimation.
- Saved workingfile strictly verified afterinternetresume:69Sources,995413bytes,SHA25666997087e67a05e0095448c8c1fb91b51d61f6acf1de865a78df3b376fb87d93. Immutable place/Children_of_corn.before-scarecrow-20261012.rbxl989746bytes/hash95d87061a83808a139da4c98c7552b65b3c8e86137dff5f472c362c7fd984d5d. Exactworld/Lighting/art/rawTerrain;4Module additions. See docs/2026-10-12_scarecrow-playtest.md.
- Regularpatrolanimation andcontrolledrealfirst/secondcapture PASS: each60camera/visualframes, FOV70→62→70, Customrestored/copydeleted/tokencleared. Trappedpose checkedwithclientattributeoverride ONLY; realserver10secfreeze independentlycheckedviaenginefixture. No claim repeatedEtrap/fullround/fear/longFPS. CorrectednightGPUfaceclear;temporary10secpreviewcleanupchecked. Finalcheck.ps1/sourceequality0changedPASS.
- Use check.ps1 then build-scarecrow-installer.py/install-scarecrow.luau only inverifiedChildren_of_corn stoppedEdit; earlierinstallers superseded. UnknownSource/openTab/topology refusal androllback stay. Future engine saves use verify-scarecrow-copy.py andguarded promote-tested-scarecrow-copy.py; no Lune serialization. FarmgeometryEditrestoreafterreopen stillrequired/Playautomatic. Rojo stopped,neighbor scenes untouched,Studio leftEdit.

## Current handheld items 2026-10-12 (supersedes scarecrow installer)

- User selected items in hands and use animations; sounds deferred. HandheldPresentation + HandheldController add two Modules,71Sources. Server inventory.use={id:integer>=0,kind:none|energy|trap} advances only after validated committed consumption/placement; no new remote. First sync skips historical use, duplicates/stale ids do not replay. Energy drink0.9sec, trap placement0.55sec, key passive/gate consumption unchanged. One owned local camera model6/17/18Parts, onePivot/render, no fieldscans/camera/Root/gameplay writes. Capture/menu/map/death/retry/foreigncamera cleanup guarded.
- Night can has a small EnergyLabel SurfaceGui FaceBack/LightInfluence0/AlwaysOnTopfalse/Activefalse256² inside Can. No extra BaseParts or lights. Ineffective temporary fill-light experiment was removed from final Sources. Do not claim changed world illumination or a new FPS benchmark.
- Saved author engine Ctrl+S16:04:22:71Sources=src,999458bytes,SHA256681f433cd71240e0d682f829649f5ff0ae36ec9ea1892ee4aefcbbb23088fa6a. Immutable place/Children_of_corn.before-handheld-20261012.rbxl995413bytes/hash66997087e67a05e0095448c8c1fb91b51d61f6acf1de865a78df3b376fb87d93. Strict6833→6835instances exactly2Module additions, all world/Lighting/art/rawTerrain exact; no file replacement/reserialization needed. See docs/2026-10-12_handheld-playtest.md and .artifacts/playtests/2026-10-12-handheld/saved-scene.json.
- Actual server/client engine fixtures and local tests/check.ps1 PASS. Real E energy/trap/key and gate→walking exit/+10 passed with diagnostic relocations/temporary aiming, not ordinary blind search. Final label version repeated real E energy/use24/cleanup and M hide/show; night GPU label readable. Fixture cameraFixed precondition failures came from MCP startup camera restoration; temporary camera restore allowed final passing fixture without production camera edits. Source equality repeat created0/changed0/71, FarmEditrestore40targets/applied0/built0; Studio left Edit. Ordinary fullround/fear/longFPS remain separate acceptance.
- Use scripts/check.ps1 then scripts/build-handheld-installer.py and guarded scripts/install-handheld.luau only in verified Children_of_corn stopped Edit. Historical scarecrow/inventory/farm installers superseded. Unknown Source/open-tab/topology refusal and rollback retained. Future exact engine saves: scripts/verify-handheld-copy.py against immutable before-handheld, scripts/promote-tested-handheld-copy.py only for separate verified candidates with both hashes guarded. No Lune scene serialization. Farm geometry Edit restore after reopen still required; Play automatic. Rojo stopped and neighbor scenes untouched.
