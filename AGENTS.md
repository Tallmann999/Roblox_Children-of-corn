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
