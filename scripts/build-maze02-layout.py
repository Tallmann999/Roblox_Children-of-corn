"""Build a pure geometry plan for the author-selected Corn maze sketch 02.

Only layout.json is written. This does not connect to Studio, modify Sources,
deserialize/serialize a scene, or set gameplay rules.
"""

from __future__ import annotations

from collections import defaultdict, deque
from hashlib import sha256
import json
from math import hypot
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REFERENCE = ROOT / ".artifacts/design/2026-10-21-corn-maze-layouts/layouts.json"
OUTPUT = ROOT / ".artifacts/playtests/2026-10-21-maze02/layout.json"
REFERENCE_SHA256 = "57465f8ac0425a3e463308e048e2514d4bf2d9bbd44b5c32799ff63c1d6e6cc3"
GRID = 18
HALF_START_SPAN = 288.75
FLOOR_Y = 14.399986267089844
PATH_WIDTH = 8.0
MASK_PADDING = 1.5
BARN_HALF_X = 20.83707046508789 / 2
BARN_HALF_Z = 15.858614921569824 / 2
ITEM_HULL = (-5.0, 6.6, -3.0, 3.0)
SLOT_MARGIN = 4.0


def digest(path: Path) -> str:
    return sha256(path.read_bytes()).hexdigest()


def node_key(node: tuple[int, int]) -> str:
    return f"{node[0]:02d}_{node[1]:02d}"


def canonical_edge(a, b):
    return tuple(sorted((tuple(a), tuple(b))))


def world_xz(node) -> tuple[float, float]:
    """Match the sketch's 40/900 central gap while preserving all four starts."""
    x, row = node
    return (
        -HALF_START_SPAN
        + (x * 860 / 17 + (40 if x >= 9 else 0)) * (HALF_START_SPAN * 2) / 900,
        HALF_START_SPAN - row * (HALF_START_SPAN * 2) / 17,
    )


def overlaps(a, b, margin=0.0) -> bool:
    """Closed XZ AABBs; an exact edge touch counts as overlap."""
    return not (
        a[1] + margin < b[0]
        or b[1] + margin < a[0]
        or a[3] + margin < b[2]
        or b[3] + margin < a[2]
    )


def item_hull_at(x: float, z: float):
    return (x + ITEM_HULL[0], x + ITEM_HULL[1], z + ITEM_HULL[2], z + ITEM_HULL[3])


def barn_box(barn):
    x, z = barn["center_xz"]
    return (x - BARN_HALF_X, x + BARN_HALF_X, z - BARN_HALF_Z, z + BARN_HALF_Z)


def validate_reference(config):
    if config.get("number") != 2 or config.get("black_is_trail") is not True:
        raise ValueError("The selected input must be the approved black-is-trail sketch 02")
    edges = set()
    for raw in config["edges"]:
        if len(raw) != 2:
            raise ValueError("An edge must have exactly two nodes")
        a, b = raw
        if any(
            len(n) != 2 or any(type(v) is not int or not 0 <= v < GRID for v in n)
            for n in (a, b)
        ):
            raise ValueError("Only integral nodes within the 18 by 18 grid are allowed")
        if abs(a[0] - b[0]) + abs(a[1] - b[1]) != 1:
            raise ValueError("Maze edges must join orthogonally adjacent grid nodes")
        edge = canonical_edge(a, b)
        if edge in edges:
            raise ValueError("Duplicate maze edge")
        edges.add(edge)
    adjacency = {(x, y): set() for x in range(GRID) for y in range(GRID)}
    for a, b in edges:
        adjacency[a].add(b)
        adjacency[b].add(a)
    seen, queue = {(0, 0)}, deque([(0, 0)])
    while queue:
        for node in adjacency[queue.popleft()] - seen:
            seen.add(node)
            queue.append(node)
    if len(seen) != GRID * GRID:
        raise ValueError("The whole maze must connect to every corner")
    if config["exit"] != [6, 0]:
        raise ValueError("The selected off-centre upper finish moved")
    expected_barns = [canonical_edge((8, y), (9, y)) for y in (3, 9, 14)]
    if [canonical_edge(*edge) for edge in config["barns"]] != expected_barns:
        raise ValueError("The three selected pass-through barn bridges moved")
    if any(edge not in edges for edge in expected_barns):
        raise ValueError("A barn must lie on an actual maze edge")
    return edges, adjacency, seen


def merged_edges(edges):
    """Union consecutive collinear edges, preserving junctions and dead ends."""
    buckets = defaultdict(list)
    for a, b in edges:
        if a[1] == b[1]:
            buckets[("X", a[1])].append(min(a[0], b[0]))
        else:
            buckets[("Z", a[0])].append(min(a[1], b[1]))
    result = []
    for (axis, fixed), starts in sorted(buckets.items()):
        starts = sorted(starts)
        first = last = starts[0]
        for value in starts[1:] + [None]:
            if value is not None and value == last + 1:
                last = value
                continue
            a, b = ((first, fixed), (last + 1, fixed)) if axis == "X" else (
                (fixed, first), (fixed, last + 1)
            )
            result.append((axis, a, b))
            first = last = value
    return result


def segment(identifier, axis, a, b, *, kind="trail", start=None, end=None):
    x1, z1 = world_xz(a) if start is None else start
    x2, z2 = world_xz(b) if end is None else end
    return {
        "id": identifier,
        "kind": kind,
        "axis": axis,
        "start_node": list(a) if a is not None else None,
        "end_node": list(b) if b is not None else None,
        "start_xz": [x1, z1],
        "end_xz": [x2, z2],
        "center_xz": [(x1 + x2) / 2, (z1 + z2) / 2],
        "size_xz": [abs(x2 - x1) + PATH_WIDTH, abs(z2 - z1) + PATH_WIDTH],
        "width": PATH_WIDTH,
        "endpoint_overlap": PATH_WIDTH / 2,
        "exclusion_padding": MASK_PADDING,
    }


def select_slots(adjacency, barns, gate_x):
    """Keep fifteen stable IDs in five broad rows, all on reachable trail nodes.

    Search stumps may appear at any non-key slot. Reserve their whole asymmetric
    collider footprint plus the existing torch position, not only the key anchor.
    Prefer dead ends to busy intersections within each planned map band.
    """
    starts = [world_xz(n) for n in ((0, 0), (17, 0), (0, 17), (17, 17))]
    door_box = (gate_x - 6, gate_x + 6, 315, 317)
    chosen = []
    for band, target_row in enumerate((2, 5, 9, 12, 15)):
        for column_band, (target_x, low, high) in enumerate(((2, 1, 4), (6, 5, 7), (14, 12, 16))):
            candidates = []
            for node, neighbors in adjacency.items():
                x, z = world_xz(node)
                if not low <= node[0] <= high or abs(node[1] - target_row) > 1:
                    continue
                hull = item_hull_at(x, z)
                torch = (x - 0.325, x + 0.325, z + 3.675, z + 4.325)
                if any(overlaps(hull, barn_box(b), SLOT_MARGIN) or overlaps(torch, barn_box(b), SLOT_MARGIN) for b in barns):
                    continue
                if overlaps(hull, door_box, SLOT_MARGIN):
                    continue
                if any(hypot(x - sx, z - sz) < 26 for sx, sz in starts):
                    continue
                if any(hypot(x - old["position"][0], z - old["position"][2]) < 28 for old in chosen):
                    continue
                score = (
                    abs(node[1] - target_row) * 4 + abs(node[0] - target_x) * 2,
                    len(neighbors), node[1], node[0],
                )
                candidates.append((score, node))
            if not candidates:
                raise ValueError(f"No safe slot in row {band + 1}, column band {column_band + 1}")
            _, node = min(candidates)
            x, z = world_xz(node)
            index = len(chosen) + 1
            chosen.append({
                "id": f"solo_slot_{index:02d}",
                "node": list(node),
                "position": [x, FLOOR_Y + 0.06, z],
                "torch_position": [x, FLOOR_Y, z + 4],
                "item_hull_xz": list(item_hull_at(x, z)),
                "row_band": band + 1,
                "column_band": column_band + 1,
                "graph_degree": len(adjacency[node]),
            })
    return chosen


def build_layout(config):
    edges, adjacency, seen = validate_reference(config)
    merged = merged_edges(edges)
    if len(edges) != 329 or len(merged) != 100:
        raise ValueError("The approved sketch must have 329 edges and 100 merged segments")
    barns = []
    for index, (a, b) in enumerate(config["barns"], 1):
        ax, az = world_xz(a)
        bx, bz = world_xz(b)
        barns.append({
            "id": f"barn_{index:02d}", "bridge": [a, b],
            "center_xz": [(ax + bx) / 2, (az + bz) / 2],
            "shell_size_xz": [BARN_HALF_X * 2, BARN_HALF_Z * 2],
            "target_main_mesh_yaw_degrees": 0,
            "passage_axis": "X",
        })
    exit_x, exit_z = world_xz(config["exit"])
    segments = [segment(f"trail_{i:03d}", axis, a, b) for i, (axis, a, b) in enumerate(merged, 1)]
    segments.append(segment("gate_approach", "Z", config["exit"], None,
                            kind="gate_approach", start=(exit_x, exit_z), end=(exit_x, 316.0)))
    slots = select_slots(adjacency, barns, exit_x)
    corners = []
    # Existing author names describe +Z as north; keep their existing identity.
    for name, node in (("NW", (0, 0)), ("NE", (17, 0)), ("SW", (0, 17)), ("SE", (17, 17))):
        x, z = world_xz(node)
        corners.append({"name": name, "spawn_id": f"solo_corner_{name.lower()}",
                        "node": list(node), "position": [x, FLOOR_Y + 0.075, z],
                        "preserve_existing_cframe": True})
    return {
        "schema_version": 1, "project_id": "children_of_corn", "scene_variant": "B",
        "layout_number": 2, "title": config["title"], "grid_size": GRID,
        "field_size_xz": [630, 630], "floor_y": FLOOR_Y,
        "coordinate_mapping": {"top_is_positive_z": True, "start_half_span": HALF_START_SPAN,
                               "sketch_extent": 900, "sketch_gap_x": 40, "sketch_grid_steps": 17},
        "nodes": [{"id": node_key(n), "node": list(n), "position": [world_xz(n)[0], FLOOR_Y, world_xz(n)[1]]}
                  for n in sorted(adjacency)],
        "edges": [[list(a), list(b)] for a, b in sorted(edges)],
        "segments": segments, "barns": barns, "corner_spawns": corners, "key_slots": slots,
        "finish": {"node": config["exit"], "gate_center_xz": [exit_x, 316.0],
                   "gate_size_xz": [12, 2], "exit_zone_center_xz": [exit_x, 325.0],
                   "gate_id": "solo_gate", "delta_x": exit_x},
        "clearance_contract": {"path_width": PATH_WIDTH, "corn_box_padding": MASK_PADDING,
                               "item_hull_offsets_xz": list(ITEM_HULL), "torch_offset_z": 4,
                               "slot_barn_margin": SLOT_MARGIN,
                               "corn_remains_traversable": True,
                               "server_ai_concealment_changed": False},
        "proofs": {"connected_nodes": len(seen), "source_edges": len(edges),
                   "merged_trail_segments": len(merged), "total_segments": len(segments),
                   "cycles": len(edges) - len(seen) + 1,
                   "all_corners_reachable": all(tuple(s["node"]) in seen for s in corners),
                   "all_slots_reachable": all(tuple(s["node"]) in seen for s in slots),
                   "finish_reachable": tuple(config["exit"]) in seen,
                   "stable_slot_count": len(slots),
                   "clearance_is_geometric_only": True,
                   "native_barn_collision_and_play_acceptance_pending": True},
    }


def main():
    if digest(REFERENCE) != REFERENCE_SHA256:
        raise ValueError("Reference sketch bytes changed; review the author-selected input")
    configurations = json.loads(REFERENCE.read_text(encoding="utf-8"))
    selected = [config for config in configurations if config.get("number") == 2]
    if len(selected) != 1:
        raise ValueError("Exactly one approved sketch 02 is required")
    plan = build_layout(selected[0])
    inputs = [REFERENCE, ROOT / "src/shared/Game/CornLayout.luau",
              ROOT / "src/server/Game/InventoryWorld.luau", ROOT / "src/server/Game/ItemModels.luau",
              Path(__file__)]
    native = OUTPUT.parent / "native-before.json"
    if native.exists():
        inputs.append(native)
    plan["input_sha256"] = {str(p.relative_to(ROOT)).replace("\\", "/"): digest(p) for p in inputs}
    plan["plan_sha256"] = sha256(json.dumps(plan, ensure_ascii=False, sort_keys=True,
                                            separators=(",", ":")).encode("utf-8")).hexdigest()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"path": str(OUTPUT), "sha256": digest(OUTPUT), "proofs": plan["proofs"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
