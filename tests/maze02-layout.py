"""Independent graph/clearance checks for the selected Corn maze geometry plan."""

from collections import defaultdict, deque
from copy import deepcopy
import importlib.util
import json
from math import hypot, isfinite
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("maze02_plan", ROOT / "scripts/build-maze02-layout.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)
REFERENCE = json.loads(builder.REFERENCE.read_text(encoding="utf-8"))[1]


def edge(a, b):
    return tuple(sorted((tuple(a), tuple(b))))


class Maze02Layout(unittest.TestCase):
    def setUp(self):
        self.plan = builder.build_layout(deepcopy(REFERENCE))

    def test_exact_graph_union_without_added_or_lost_edges(self):
        original = {edge(*e) for e in REFERENCE["edges"]}
        expanded = []
        trails = [s for s in self.plan["segments"] if s["kind"] == "trail"]
        self.assertEqual(len(trails), 100)
        for segment in trails:
            a, b = segment["start_node"], segment["end_node"]
            if a[0] == b[0]:
                expanded += [edge((a[0], row), (a[0], row + 1)) for row in range(a[1], b[1])]
            else:
                self.assertEqual(a[1], b[1])
                expanded += [edge((col, a[1]), (col + 1, a[1])) for col in range(a[0], b[0])]
        self.assertEqual(len(expanded), len(set(expanded)))
        self.assertEqual(set(expanded), original)
        self.assertEqual(len(expanded), 329)

    def test_reachability_from_each_corner_through_all_slots_and_finish(self):
        graph = defaultdict(set)
        for a, b in self.plan["edges"]:
            graph[tuple(a)].add(tuple(b))
            graph[tuple(b)].add(tuple(a))
        required = {tuple(s["node"]) for s in self.plan["key_slots"]}
        required.add(tuple(self.plan["finish"]["node"]))
        for corner in self.plan["corner_spawns"]:
            start = tuple(corner["node"])
            seen, queue = {start}, deque([start])
            while queue:
                for node in graph[queue.popleft()] - seen:
                    seen.add(node)
                    queue.append(node)
            self.assertEqual(len(seen), 324)
            self.assertTrue(required <= seen)
        self.assertEqual(len(self.plan["edges"]) - len(graph) + 1, 6)

    def test_geometry_uses_approved_gap_width_and_does_not_open_non_edges(self):
        nodes = {tuple(n["node"]): n["position"] for n in self.plan["nodes"]}
        self.assertEqual(len(nodes), 324)
        self.assertEqual(nodes[(0, 0)], [-288.75, builder.FLOOR_Y, 288.75])
        self.assertEqual(nodes[(17, 17)], [288.75, builder.FLOOR_Y, -288.75])
        self.assertAlmostEqual(nodes[(9, 0)][0] - nodes[(8, 0)][0], 58.127450980392155)
        edges = {edge(*e) for e in self.plan["edges"]}

        def inside(x, z):
            for segment in self.plan["segments"]:
                cx, cz = segment["center_xz"]
                sx, sz = segment["size_xz"]
                if abs(x - cx) <= sx / 2 + 1.5 and abs(z - cz) <= sz / 2 + 1.5:
                    return True
            return False

        for x in range(18):
            for y in range(18):
                for b in ((x + 1, y), (x, y + 1)):
                    if max(b) >= 18:
                        continue
                    a = (x, y)
                    ax, _, az = nodes[a]
                    bx, _, bz = nodes[b]
                    self.assertEqual(inside((ax + bx) / 2, (az + bz) / 2), edge(a, b) in edges)
        for segment in self.plan["segments"]:
            self.assertEqual(segment["width"], 8)
            self.assertEqual(segment["exclusion_padding"], 1.5)
            self.assertTrue(all(isfinite(v) and v > 0 for v in segment["size_xz"]))

    def test_three_barn_bridges_cross_the_shell_in_the_passage_direction(self):
        edges = {edge(*e) for e in self.plan["edges"]}
        for barn, row in zip(self.plan["barns"], (3, 9, 14), strict=True):
            self.assertEqual(barn["bridge"], [[8, row], [9, row]])
            self.assertIn(edge(*barn["bridge"]), edges)
            self.assertAlmostEqual(barn["center_xz"][0], 0)
            self.assertEqual(barn["passage_axis"], "X")
            self.assertEqual(barn["target_main_mesh_yaw_degrees"], 0)
            endpoints = [builder.world_xz(n) for n in barn["bridge"]]
            self.assertLess(endpoints[0][0], -barn["shell_size_xz"][0] / 2 - 4)
            self.assertGreater(endpoints[1][0], barn["shell_size_xz"][0] / 2 + 4)
            bx, bz = barn["center_xz"]
            sx, sz = barn["shell_size_xz"]
            obstacle = (bx - sx / 2, bx + sx / 2, bz - sz / 2, bz + sz / 2)
            crossings = []
            for segment in self.plan["segments"]:
                cx, cz = segment["center_xz"]
                px, pz = segment["size_xz"]
                box = (cx - px / 2 - 1.5, cx + px / 2 + 1.5,
                       cz - pz / 2 - 1.5, cz + pz / 2 + 1.5)
                if builder.overlaps(box, obstacle):
                    crossings.append(segment)
            self.assertEqual(len(crossings), 1)
            crossing = crossings[0]
            self.assertEqual(crossing["axis"], "X")
            self.assertEqual(crossing["start_node"][1], row)
            self.assertLessEqual(crossing["start_node"][0], 8)
            self.assertGreaterEqual(crossing["end_node"][0], 9)

    def test_fifteen_stable_slots_and_whole_item_torch_clearance(self):
        slots = self.plan["key_slots"]
        self.assertEqual([s["id"] for s in slots], [f"solo_slot_{i:02d}" for i in range(1, 16)])
        self.assertEqual(len({tuple(s["node"]) for s in slots}), 15)
        self.assertEqual([s["row_band"] for s in slots], [row for row in range(1, 6) for _ in range(3)])
        for index, slot in enumerate(slots):
            x, _, z = slot["position"]
            # Independently derive the InventoryWorld offset/stump collider union.
            hull = (x - 5, x + 6.6, z - 3, z + 3)
            self.assertEqual(list(hull), slot["item_hull_xz"])
            torch = (x - .325, x + .325, z + 3.675, z + 4.325)
            self.assertEqual(slot["torch_position"], [x, builder.FLOOR_Y, z + 4])
            for barn in self.plan["barns"]:
                bx, bz = barn["center_xz"]
                sx, sz = barn["shell_size_xz"]
                obstacle = (bx - sx / 2, bx + sx / 2, bz - sz / 2, bz + sz / 2)
                for footprint in (hull, torch):
                    separated = (footprint[1] + 4 < obstacle[0] or obstacle[1] + 4 < footprint[0]
                                 or footprint[3] + 4 < obstacle[2] or obstacle[3] + 4 < footprint[2])
                    self.assertTrue(separated, (slot["id"], barn["id"]))
            for corner in self.plan["corner_spawns"]:
                sx, _, sz = corner["position"]
                self.assertGreaterEqual(hypot(x - sx, z - sz), 26)
            for other in slots[:index]:
                ox, _, oz = other["position"]
                self.assertGreaterEqual(hypot(x - ox, z - oz), 28)

    def test_off_centre_gate_single_approach_and_no_spawn_overlap(self):
        gate = self.plan["finish"]["gate_center_xz"]
        self.assertAlmostEqual(gate[0], -93.98529411764704)
        self.assertEqual(gate[1], 316)
        self.assertNotEqual(gate[0], 0)
        self.assertEqual(len(self.plan["segments"]), 101)
        approach = self.plan["segments"][-1]
        self.assertEqual(approach["id"], "gate_approach")
        self.assertEqual(approach["start_node"], [6, 0])
        self.assertEqual(approach["end_xz"], gate)
        self.assertAlmostEqual(approach["start_xz"][1], 288.75)
        expected = {"NW": (-288.75, 288.75), "NE": (288.75, 288.75),
                    "SW": (-288.75, -288.75), "SE": (288.75, -288.75)}
        for start in self.plan["corner_spawns"]:
            x, _, z = start["position"]
            self.assertEqual((x, z), expected[start["name"]])
            self.assertTrue(start["preserve_existing_cframe"])
            self.assertGreater(hypot(x - gate[0], z - gate[1]), 26)

    def test_refuses_invalid_or_different_reference_topology(self):
        cases = []
        bad = deepcopy(REFERENCE); bad["edges"].append(bad["edges"][0]); cases.append(bad)
        bad = deepcopy(REFERENCE); bad["edges"][0] = [[0, 0], [1, 1]]; cases.append(bad)
        bad = deepcopy(REFERENCE); bad["edges"][0] = [[-1, 0], [0, 0]]; cases.append(bad)
        bad = deepcopy(REFERENCE); bad["exit"] = [9, 0]; cases.append(bad)
        bad = deepcopy(REFERENCE); bad["barns"][0] = [[8, 4], [9, 4]]; cases.append(bad)
        bad = deepcopy(REFERENCE); bad["black_is_trail"] = False; cases.append(bad)
        bad = deepcopy(REFERENCE); bad["edges"] = [e for e in bad["edges"] if [0, 0] not in e]; cases.append(bad)
        for bad in cases:
            with self.assertRaises(ValueError):
                builder.build_layout(bad)


if __name__ == "__main__":
    unittest.main(verbosity=2)
