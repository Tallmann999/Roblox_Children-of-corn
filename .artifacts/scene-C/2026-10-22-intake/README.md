# Scene C: read-only FBX intake, 2026-10-22

Blender: `D:\Steam\steamapps\common\Blender\blender.exe`, 5.2.2 LTS. First Blender invocation ran `blender-core/scripts/env_report.py`; factory background process, NVIDIA GeForce GTX 1060 6 GB reported. No live Blender or Studio session was touched. Five exact supplied FBX source SHA-256 values were checked before and after import; all unchanged.

| Exact asset | Triangles | World width × depth × height, metres |
|---|---:|---|
| SM_Generic_Grass_Patch_01 | 42 | 0.287026 × 0.309168 × 0.620244 |
| SM_Env_Dirt_Rows_Center_01 | 364 | 5 × 5 × 0.194514 |
| SM_Env_Dirt_Rows_End_Top_01 | 469 | 5 × 5 × 0.194514 |
| SM_Env_Dirt_Skirt_01 | 352 | 5.917633 × 5.826114 × 0.355311 |
| SM_Prop_Plant_Corn_01_L | 510 | 0.820575 × 0.855623 × 2.186265 |

`intake-report.json` records meshes, raw transforms, world bounds, exact Sources, materials, missing image paths, bounded sibling texture inventory, hashes and unmodified automatic QA findings. Use `world_aabb_dimensions`; direct imported root `ob.dimensions` reports an unexpected local-axis ordering in this Blender session. Transformed vertex bounds and reviewed previews have +Z up.

`mesh-arrays.json` is a read-only extraction of original world-space mesh data, 1,737 triangles total: vertices are metres, +Z up; triangle indices are zero-based; UV and original split normals are per triangle corner. A right-handed conversion to Roblox is `[x, z, -y]`, followed by one common scale. No mesh repair, transform application, normals recalculation, UV rework or FBX export was performed.

## Materials and source correspondence

- Corn and grass FBX contain no texture reference. Soil FBX references missing `U:\Dropbox\SyntyStudios\PolygonFarm\_Working\_Textures\PolygonFarm_Texture_01_A_2k.psd`; no texture is embedded.
- Sibling `Textures/PolygonFarm_Texture_01_A.png` is RGB8 2048 × 2048, without alpha, and byte-identical to `assets/farm/PolygonFarm_Texture_01_A.png` (`ae59540e…`).
- Supplied corn FBX is byte-identical to `assets/corn/SM_Prop_Plant_Corn_01_L.fbx` (`259fbe16…`); sibling `Textures/01_roblax_style.png` is RGB8 1254 × 1254 without alpha and byte-identical to `assets/corn/01_roblax_style.png` (`843644a1…`). Existing `assets/corn/README.md` documents that exact source's saved mesh URI `104111861186519` and green texture URI `137803536172445`. Source-byte correspondence is proved; a new native content read was outside this intake scope.

## Visual observations and QA interpretation

All solid contact sheets were inspected, plus grass wire view. Center and EndTop are square shallow ribbed tiles, with row grooves running along imported world −Y; EndTop tapers their end on one side. Skirt is a rounded shallow soil pad meant beneath/around a tile. Corn has a stalk and volume-shaped leaves with 12 mesh islands; no alpha cutout is required. Grass is three angular blades.

Automatic QA is deliberately retained without hiding failures: each imported object has scale 0.01 and rotation X +90°; soil and corn have open edges; grass has four reported overlapping coplanar triangle pairs near blade intersections. No degenerate faces, inconsistent winding, inverted closed islands, loose vertices or nonmanifold edges were reported. The assets use a color palette: many polygon UVs collapse to one atlas point or a short line. Re-unwrapping would change the source appearance. These source properties have not been repaired or accepted as a newly delivered mesh; they are intake findings.

For a walk-through inspection, use a smooth ground collider and keep decorative corn, grass and shallow soil meshes noncollidable. Using convex mesh collision for the whole foliage/soil would obstruct the intended passage and create misleading movement behavior. Preserve original UVs and the RGB atlas.

No `.blend`, FBX, OBJ, GLB, Roblox scene, Source, asset upload, publication, or external-project write was created in this subtask. Output files are reports, read-only mesh arrays, diagnostic PNGs and helper scripts/logs within this directory.
