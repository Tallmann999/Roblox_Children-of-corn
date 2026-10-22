# Whole-field B density doubling

Read-only analysis used the exact saved B `94c55e17bed0dc2f4b2e7c6020f60c031d80bc636be16166fe0effb6df146d5f`, deserialized only into a private Lune DOM. No scene was serialized and no Studio operation was performed by this analysis task.

The production B spacing factor changes from `1 / sqrt(1.3)` to `1 / sqrt(2.6)`: 2.6311740579 to 1.8605210188 studs. Thus spacing decreases by 29.2893% along both axes and nominal per-area density doubles across the field, independently of trails. Original trail projections and all exclusions remain unchanged.

| Measurement | Accepted B | Proposed B |
| --- | ---: | ---: |
| Dense candidate cells | 57,121 | 114,921 |
| Eligible dense cells after exclusions | 50,187 | 100,790 |
| Far candidate cells at stride 2 | 14,161 | 28,561 |
| Eligible Far cells | 12,433 | 24,954 |
| Nominal density per square stud | 0.1444444 | 0.2888889 |

Actual Far count increases 2.00708 times because the new finite grid samples the fixed map clearances differently. The full-field 16-sector analysis shows the increase throughout the map, rather than only along trail edges. Counts are recorded in `density-analysis.json` with a reproducible standalone analysis script.

The old Far cap of 20,000 checks candidate count before building. Without changing that cap, the new 28,561-cell grid would be rejected altogether and the old saved overview would remain. The B cap is therefore 30,000 in preflight, metadata and build loop; A remains 20,000.

Near B caps double to 8,064 plants / 200 chunks. Of 441 uniform map samples, maximum fresh normal detail is 5,855 eligible plants / 112 chunks; elevated detail is 6,461 / 135. A conservative combination of all maximum dense/elevated hysteresis boundaries reaches 8,125 / 158, so the doubled 8,064 cap can clip a small part of that retained bound. The prior 4,032 cap likewise clipped the old conservative 4,130 bound. This is a retained upper-bound limitation, not a missing whole-field Far layer.

Highest-detail geometry allowance doubles from 4 chunks / 576 plants to 8 / 1,152, maintaining approximately the same physical coverage as cells become smaller. B wind index ceilings match the larger renderer layers at 8,192 Near / 30,000 Far. Indexing ceilings do not increase wind actor, scan, animated-part, clone-per-frame or time budgets. A and foreign-field defaults remain unchanged.

Source scope is exactly CornLayout, CornAppearance, CornController, CornBackdropController and CornWindController. Gameplay, physical collision, world objects, trail widths, other sources and canonical geometry are unchanged. The static-content shadow pipeline remains intact.

Focused regression `tests/corn-double-density.luau` passes 64,931 assertions. It executes production methods for layout determinism, A/foreign defaults, full 28,561-cell B Far publication, bounds and stride metadata, clone publication, Near count/chunk/highest-LOD limits, and both index-ceiling boundaries. Existing corn static-shadow (19,708 assertions), renderer quality/overview lifecycle, wind lifecycle and classic backdrop fixtures also pass. These file-backed tests do not establish native rendering or sustained FPS.
