"""Geometry and preservation checks for narrowing the accepted B maze."""

from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import unittest


ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location("maze02_narrow",ROOT/"scripts/plan-maze02-narrow.py")
m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class NarrowMaze(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.layout=json.loads((m.OLD/"layout.json").read_text(encoding="utf-8"))
        cls.editor=json.loads((m.OLD/"editor-before.json").read_text(encoding="utf-8"))
        cls.payload=json.loads((m.OLD/"payload.json").read_text(encoding="utf-8"))
        cls.nodes=m.expected_nodes(json.loads((m.OLD/"native-before.json").read_text(encoding="utf-8")),cls.payload,cls.editor)
        cls.plan=m.build_plan(cls.nodes,cls.layout)

    def test_half_width_preserves_centerline_lengths_and_endpoint_connectivity(self):
        originals={s["id"]:s for s in self.layout["segments"]}
        for segment in self.plan["segments"]:
            old=originals[segment["id"]]
            self.assertEqual(segment["center_xz"],old["center_xz"])
            self.assertEqual(segment["start_xz"],old["start_xz"])
            self.assertEqual(segment["end_xz"],old["end_xz"])
            self.assertEqual(segment["start_node"],old["start_node"])
            self.assertEqual(segment["end_node"],old["end_node"])
            self.assertEqual(segment["width"],4)
            self.assertEqual(segment["endpoint_overlap"],2)
            long_axis=0 if segment["axis"]=="X" else 1
            self.assertAlmostEqual(segment["size_xz"][long_axis],old["size_xz"][long_axis]-4,delta=0.00006)
            self.assertEqual(segment["size_xz"][1-long_axis],4)
            # Endpoints sit exactly 2 studs inside each new rectangular end.
            for endpoint in (segment["start_xz"],segment["end_xz"]):
                distance=abs(endpoint[long_axis]-segment["center_xz"][long_axis])
                self.assertAlmostEqual(segment["size_xz"][long_axis]/2-distance,2,delta=0.00006)
        self.assertEqual(len(self.plan["segments"]),100)

    def test_plant_padding_and_leaf_extents_remain_unchanged(self):
        self.assertEqual(self.plan["source_requirements"]["maze_trail_exclusion_padding"],1.5)
        self.assertFalse(self.plan["source_requirements"]["padding_source_change_required"])
        # Half-width = 2, fixed leaf half extent ~1.5, center exclusion half3.5.
        self.assertEqual((4+2*1.5)-2*1.5,4)
        self.assertFalse(any(c["property"]=="Source" for c in self.plan["changes"]))

    def test_approach_and_art_binding_widths_halved_without_shortening_gate_run(self):
        changes={(c["path"],c["property"]):c for c in self.plan["changes"] if "selector" not in c}
        for name,w in (("RoadSurface",4),("RoadClearance",6),("RutLeft",0.8),("RutRight",0.8)):
            change=changes[(m.ROAD+"/"+name,"Size")]
            self.assertAlmostEqual(change["after"]["value"][0],w,delta=0.000001)
            self.assertEqual(change["after"]["value"][2],27.25)
        for path,prop in ((m.MAP+"/HarvestDecor","HarvestRoadSize"),
                          (m.MAP+"/HarvestDecor/VariantB/RoadSurface","HarvestPlacedSize")):
            self.assertTrue(changes[(path,prop)]["attribute"])
            self.assertEqual(changes[(path,prop)]["after"]["value"][0],4)
        self.assertTrue(all(c["property"]!="CFrame" for c in self.plan["changes"] if c["path"].startswith(m.TRAIL_ROOT+"/")))

    def test_four_starts_slots_barns_door_and_gameplay_outside_change_set(self):
        protected=("/CornerSpawns/","/KeySlots/","/HouseWest/","/HouseEast/","/HouseNorthWest/","/EscapeGate/","/Boundaries/")
        self.assertFalse(any(any(part in c["path"] for part in protected) for c in self.plan["changes"]))
        self.assertTrue(all(c["path"].startswith(m.MAP+"/") for c in self.plan["changes"]))
        self.assertEqual(sum(c["path"].startswith(m.TRAIL_ROOT+"/") for c in self.plan["changes"]),100)

    def test_restored_editor_plants_were_known_hidden_and_stay_clear_of_new_trails(self):
        prior={(n["path"],tuple(n["frame"])) for n in self.editor["nodes"]}
        restored=[c for c in self.plan["changes"] if c["property"]=="Transparency"]
        self.assertGreater(len(restored),0)
        self.assertLess(len(restored),len(prior))
        for change in restored:
            frame=change["selector"]["CFrame"]["value"]
            self.assertIn((change["path"],tuple(frame)),prior)
            self.assertEqual(change["installedSelector"],change["selector"])
            self.assertEqual((change["before"],change["after"]),(1,0))
            for segment in self.plan["segments"]:
                x,z=segment["center_xz"]
                sx,sz=segment["size_xz"]
                self.assertTrue(abs(frame[0]-x)>sx/2+3.7 or abs(frame[2]-z)>sz/2+3.7)
        self.assertEqual(len(restored),self.plan["counts"]["editor_restored"])
        self.assertEqual(self.plan["counts"]["editor_restored"]+self.plan["counts"]["editor_retained_hidden"],1441)

    def test_author_geometry_changes_and_missing_art_binding_refused(self):
        mutations=[(m.TRAIL_ROOT+"/trail_001","size",[41,0.08,8]),
                   (m.ROAD+"/RoadSurface","size",[9,0.08,27.25]),
                   (m.MAP+"/HarvestDecor/VariantB/RoadSurface","attrs",{})]
        for path,field,value in mutations:
            with self.subTest(path=path):
                nodes=deepcopy(self.nodes)
                next(n for n in nodes if n["path"]==path)[field]=value
                with self.assertRaises(ValueError):m.build_plan(nodes,self.layout)
        with self.assertRaises(ValueError):m.build_plan(self.nodes,self.layout,trail_padding=0.75)


if __name__=="__main__":
    unittest.main()
