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

- Current milestone: first key/gate/escape/retry slice on an owned temporary runtime greybox. Foundation startup verified by user screenshot; gameplay is unverified until tested in Studio. Never edit the saved .rbxl or original world content for this runtime slice.
- Source of truth: docs/project-concept.md and docs/2026-10-09_core-loop_gd-spec.md.
- Local solo PC prototype. No persistence, purchases, lobby, public publishing or multiplayer in this milestone.
- Use scripts/use-project-tools.ps1 for the project-local toolchain. Run scripts/check.ps1 after code changes.
- Keep world tags and remote contracts in docs/architecture.md before implementing them.
