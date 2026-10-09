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

- Current milestone: persistent editable CornMap 1200 x 1200 studs and key/gate/escape/retry. User explicitly authorized authoring this map in Children_of_corn only. Preserve imported art and unrelated scene content; use a backed-up guarded installer or verified new file. Studio gameplay acceptance remains pending.
- Source of truth: docs/project-concept.md and docs/2026-10-09_core-loop_gd-spec.md.
- Local solo PC prototype. No persistence, purchases, lobby, public publishing or multiplayer in this milestone.
- Use scripts/use-project-tools.ps1 for the project-local toolchain. Run scripts/check.ps1 after code changes.
- Keep world tags and remote contracts in docs/architecture.md before implementing them.

## Studio target correction (2026-10-09)

- Work only on place/Children_of_corn.rbxl in this project. Never connect this project's Rojo server to New_+1 speed monkey or another Studio scene.
- ChildrenOfCorn Rojo was stopped after an accidental connection to Speed Monkey. Do not restart live sync until the correct Studio scene is verified. See docs/2026-10-09_wrong-scene-cleanup.md.


- User reported the Speed Monkey cleanup complete and resumed Children_of_corn work. Live Rojo remains stopped; protected file/Command Bar installation is preferred until the correct Studio target is verified.

- Current repair scope: four authored corner SpawnLocations, server-selected start and full-field overview plus dense nearby corn. Preserve existing map geometry and source asset. The saved lower Workspace/SpawnLocation may be disabled only by the guarded Corn repair with rollback. Use scripts/repair-corn-scene.luau for installed maps; actual Studio acceptance remains pending.
