"""Offline A/B ownership and refusal checks; fixtures never alter working scenes."""
from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest import mock


sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("rojo_ab", ROOT / "scripts/rojo-ab.py")
rojo = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rojo)

SHADOW = "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornShadowController"
NIGHT = "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/NightModeController"
NIGHT_FILE = "variants/B/client/Controllers/NightModeController.luau"
GREEN_BEDS = {
    "ReplicatedStorage/GameShared/Game/GreenBedLayout": "variants/B/shared/Game/GreenBedLayout.luau",
    "ReplicatedStorage/GameShared/Game/GreenBedGeometry": "variants/B/shared/Game/GreenBedGeometry.luau",
    "ReplicatedStorage/GameShared/Game/GreenBedGeometryData/Center": "variants/B/shared/Game/GreenBedGeometryData/Center.luau",
    "ReplicatedStorage/GameShared/Game/GreenBedGeometryData/End": "variants/B/shared/Game/GreenBedGeometryData/End.luau",
    "ReplicatedStorage/GameShared/Game/GreenBedGeometryData/Skirt": "variants/B/shared/Game/GreenBedGeometryData/Skirt.luau",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/GreenBedController": "variants/B/client/Controllers/GreenBedController.luau",
}
GREEN_SHAPES = {
    "ReplicatedStorage/GameShared/Game/CornGreenGeometry": "variants/B/shared/Game/CornGreenGeometry.luau",
    **{f"ReplicatedStorage/GameShared/Game/CornGreenGeometryData/Var{i:02}":
       f"variants/B/shared/Game/CornGreenGeometryData/Var{i:02}.luau" for i in range(1, 4)},
}
MANUAL_SPLITS = {
    "ServerScriptService/GameServer/Game/InventoryWorld": "server/Game/InventoryWorld.luau",
    "ServerScriptService/GameServer/Game/HarvestWorld": "server/Game/HarvestWorld.luau",
    "ServerScriptService/GameServer/Game/RoundAudio": "server/Game/RoundAudio.luau",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/HarvestGeometryController": "client/Controllers/HarvestGeometryController.luau",
}
MANUAL_B_ONLY = {
    "ReplicatedStorage/GameShared/Game/ManualScene": "variants/B/shared/Game/ManualScene.luau",
    "ServerScriptService/GameServer/Services/ManualSceneService": "variants/B/server/Services/ManualSceneService.luau",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/AuthoringCornController": "variants/B/client/Controllers/AuthoringCornController.luau",
}


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8", newline="\n")


def project_nodes(project):
    nodes = {}

    def visit(node, path):
        nodes[path] = node
        for name, child in node.items():
            if not name.startswith("$"):
                visit(child, (path + "/" if path else "") + name)

    visit(project["tree"], "")
    return nodes


class RojoVariants(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="corn-rojo-refusal-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.manifest = copy.deepcopy(rojo.load_manifest(ROOT))
        for directory in ("src", "variants"):
            sources = list((ROOT / directory).rglob("*.luau"))
            metadata = list((ROOT / directory).rglob("*.meta.json"))
            for source in sources + metadata:
                target = self.root / source.relative_to(ROOT)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, target)
        for name in ("default.project.json", "A.project.json", "B.project.json"):
            shutil.copyfile(ROOT / name, self.root / name)
        self.write_manifest()

    def write_manifest(self, regenerate_projects=False):
        write_json(self.root / "rojo/source-map.json", self.manifest)
        if regenerate_projects:
            for variant in ("A", "B"):
                write_json(self.root / (variant + ".project.json"), rojo.make_project(self.manifest, variant))

    def assert_refused(self):
        with self.assertRaises(ValueError):
            rojo.validate_projects(self.root)

    def test_reviewed_configuration_validates_without_scenes_or_studio(self):
        self.assertFalse((self.root / "place").exists())
        self.assertEqual(rojo.validate_projects(self.root), self.manifest)

    def test_common_and_variant_sources_have_independent_ownership(self):
        shared = self.manifest["shared_sources"]
        split = set(self.manifest["split_paths"])
        a, b = (self.manifest["variants"][v]["sources"] for v in ("A", "B"))
        self.assertEqual(len(shared), 142)
        self.assertEqual(len(split), 11)
        self.assertEqual(set(a), set(shared) | split)
        self.assertEqual(set(b), set(a) | {SHADOW, NIGHT} | set(GREEN_BEDS) | set(GREEN_SHAPES) | set(MANUAL_B_ONLY))
        self.assertEqual({path: a[path] for path in shared}, shared)
        self.assertEqual({path: b[path] for path in shared}, shared)
        self.assertEqual(len({row["file"] for path, row in a.items() if path not in shared}), 11)
        self.assertEqual(len({row["file"] for path, row in b.items() if path not in shared}), 26)
        for path in split:
            self.assertNotEqual(a[path]["file"], b[path]["file"])
            self.assertTrue(a[path]["file"].startswith("variants/A/"))
            self.assertTrue(b[path]["file"].startswith("variants/B/"))

    def test_green_beds_are_explicitly_owned_only_by_B(self):
        a = self.manifest["variants"]["A"]
        b = self.manifest["variants"]["B"]
        for path, file in GREEN_BEDS.items():
            with self.subTest(path=path):
                self.assertNotIn(path, a["sources"])
                self.assertNotIn(path, a["classes"])
                self.assertNotIn(path, self.manifest["shared_sources"])
                self.assertEqual(b["sources"][path]["file"], file)
                self.assertEqual(b["sources"][path]["class"], "ModuleScript")
                self.assertEqual(b["classes"][path], "ModuleScript")

    def test_manual_world_modules_are_independent_and_legacy_copies_stay_unmapped(self):
        a, b = (self.manifest["variants"][v]["sources"] for v in ("A", "B"))
        for path, suffix in MANUAL_SPLITS.items():
            with self.subTest(path=path):
                self.assertIn(path, self.manifest["split_paths"])
                self.assertNotIn(path, self.manifest["shared_sources"])
                self.assertIn("src/" + suffix, self.manifest["legacy_unmapped_files"])
                for variant, sources in (("A", a), ("B", b)):
                    self.assertEqual(sources[path]["file"], "variants/" + variant + "/" + suffix)
                self.assertEqual((self.root / a[path]["file"]).read_bytes(),
                                 (self.root / ("src/" + suffix)).read_bytes())
                # Counts and the generated project remain internally consistent;
                # serving the old src for either variant must still refuse.
                for variant, sources in (("A", a), ("B", b)):
                    original = sources[path]["file"]
                    sources[path]["file"] = "src/" + suffix
                    self.write_manifest(regenerate_projects=True)
                    self.assert_refused()
                    sources[path]["file"] = original
        self.write_manifest(regenerate_projects=True)
        self.assertEqual(rojo.validate_projects(self.root), self.manifest)

    def test_manual_split_same_variant_swaps_are_refused_without_count_or_inventory_change(self):
        paths = list(MANUAL_SPLITS)
        for variant in ("A", "B"):
            sources = self.manifest["variants"][variant]["sources"]
            for path in paths:
                other = paths[(paths.index(path) + 1) % len(paths)]
                with self.subTest(variant=variant, path=path):
                    sources[path]["file"], sources[other]["file"] = sources[other]["file"], sources[path]["file"]
                    self.write_manifest(regenerate_projects=True)
                    self.assert_refused()
                    sources[path]["file"], sources[other]["file"] = sources[other]["file"], sources[path]["file"]

    def test_manual_authoring_modules_are_B_only_with_exact_canonical_files(self):
        a, b = (self.manifest["variants"][v] for v in ("A", "B"))
        for path, file in MANUAL_B_ONLY.items():
            with self.subTest(path=path):
                self.assertNotIn(path, a["sources"])
                self.assertNotIn(path, a["classes"])
                self.assertNotIn(path, self.manifest["shared_sources"])
                self.assertEqual(b["sources"][path]["file"], file)
                self.assertEqual(b["sources"][path]["class"], "ModuleScript")
                self.assertEqual(b["classes"][path], "ModuleScript")
                self.assertEqual(project_nodes(rojo.make_project(self.manifest, "B"))[path],
                                 {"$ignoreUnknownInstances": True, "$path": file})
                a["sources"][path] = copy.deepcopy(b["sources"][path])
                a["classes"][path] = "ModuleScript"
                self.write_manifest(regenerate_projects=True)
                self.assert_refused()
                del a["sources"][path]
                del a["classes"][path]
        self.write_manifest(regenerate_projects=True)

    def test_manual_B_only_modules_cannot_swap_files_or_change_class(self):
        b = self.manifest["variants"]["B"]
        for path in MANUAL_B_ONLY:
            with self.subTest(path=path):
                original = b["sources"][path]["file"]
                b["sources"][path]["file"], b["sources"][SHADOW]["file"] = b["sources"][SHADOW]["file"], original
                self.write_manifest(regenerate_projects=True)
                self.assert_refused()
                b["sources"][SHADOW]["file"], b["sources"][path]["file"] = b["sources"][path]["file"], original
                b["sources"][path]["class"] = b["classes"][path] = "Script"
                self.write_manifest(regenerate_projects=True)
                self.assert_refused()
                b["sources"][path]["class"] = b["classes"][path] = "ModuleScript"
        self.write_manifest(regenerate_projects=True)

    def test_project_regeneration_refuses_active_loopback_listener(self):
        with mock.patch.object(rojo.socket, "socket") as socket_factory:
            connection = socket_factory.return_value.__enter__.return_value
            connection.connect_ex.return_value = 0
            with self.assertRaisesRegex(ValueError, "listener is active: 34873"):
                rojo.require_project_ports_idle(self.manifest)
            connection.connect_ex.assert_called_once_with(("127.0.0.1", 34873))
        with mock.patch.object(rojo.socket, "socket") as socket_factory:
            connection = socket_factory.return_value.__enter__.return_value
            connection.connect_ex.side_effect = [111, 111]
            rojo.require_project_ports_idle(self.manifest)
            self.assertEqual(connection.connect_ex.call_args_list,
                             [mock.call(("127.0.0.1", 34873)), mock.call(("127.0.0.1", 34874))])

    def test_green_shapes_and_data_folder_are_explicitly_owned_only_by_B(self):
        a = self.manifest["variants"]["A"]
        b = self.manifest["variants"]["B"]
        folder = "ReplicatedStorage/GameShared/Game/CornGreenGeometryData"
        self.assertNotIn(folder, a["classes"])
        self.assertNotIn(folder, a["sources"])
        self.assertNotIn(folder, self.manifest["shared_sources"])
        self.assertEqual(b["classes"][folder], "Folder")
        self.assertNotIn(folder, b["sources"])
        self.assertEqual({path for path in b["classes"] if path.startswith(folder + "/")},
                         {path for path in GREEN_SHAPES if path.startswith(folder + "/")})
        for path, file in GREEN_SHAPES.items():
            with self.subTest(path=path):
                self.assertNotIn(path, a["sources"])
                self.assertNotIn(path, a["classes"])
                self.assertNotIn(path, self.manifest["shared_sources"])
                self.assertEqual(b["sources"][path]["file"], file)
                self.assertEqual(b["sources"][path]["class"], "ModuleScript")
                self.assertEqual(b["classes"][path], "ModuleScript")

    def test_night_mode_is_B_only_and_cross_variant_or_unmapped_injection_is_refused(self):
        a = self.manifest["variants"]["A"]
        b = self.manifest["variants"]["B"]
        self.assertNotIn(NIGHT, a["sources"])
        self.assertNotIn(NIGHT, a["classes"])
        self.assertNotIn(NIGHT, self.manifest["shared_sources"])
        self.assertEqual(b["sources"][NIGHT]["file"], NIGHT_FILE)
        self.assertEqual(b["sources"][NIGHT]["class"], "ModuleScript")
        self.assertEqual(b["classes"][NIGHT], "ModuleScript")
        self.assertEqual(len(b["sources"]), 168)
        self.assertEqual(len(b["classes"]), 182)
        node = project_nodes(rojo.make_project(self.manifest, "B"))[NIGHT]
        self.assertEqual(node, {"$ignoreUnknownInstances": True, "$path": NIGHT_FILE})
        # A deliberate addition to A must not become valid even with a
        # regenerated project; the controller belongs exclusively to B.
        a["sources"][NIGHT] = copy.deepcopy(b["sources"][NIGHT])
        a["classes"][NIGHT] = "ModuleScript"
        self.write_manifest(regenerate_projects=True)
        self.assert_refused()
        del a["sources"][NIGHT]
        del a["classes"][NIGHT]
        self.write_manifest(regenerate_projects=True)
        # A same-variant file swap preserves counts, unique files and source
        # inventory, but must still refuse a redirected night controller.
        night_file = b["sources"][NIGHT]["file"]
        shadow_file = b["sources"][SHADOW]["file"]
        b["sources"][NIGHT]["file"] = shadow_file
        b["sources"][SHADOW]["file"] = night_file
        self.write_manifest(regenerate_projects=True)
        self.assert_refused()
        b["sources"][NIGHT]["file"] = night_file
        b["sources"][SHADOW]["file"] = shadow_file
        self.write_manifest(regenerate_projects=True)
        # A same-name shared copy cannot enter either graph implicitly.
        shared_copy = self.root / "src/client/Controllers/NightModeController.luau"
        shared_copy.write_bytes((self.root / NIGHT_FILE).read_bytes())
        self.assert_refused()

    def test_projects_preserve_all_classes_and_nested_unknown_instances(self):
        for variant in ("A", "B"):
            with self.subTest(variant=variant):
                row = self.manifest["variants"][variant]
                project = rojo.make_project(self.manifest, variant)
                self.assertEqual(project["name"], Path(row["scene"]).name)
                self.assertEqual(project["serveAddress"], "127.0.0.1")
                self.assertEqual(project["servePort"], row["port"])
                self.assertNotIn("placeId", project)
                self.assertNotIn("gameId", project)
                nodes = project_nodes(project)
                directories = {path for path, entry in row["sources"].items()
                               if entry["file"].endswith("/init.luau")}
                implicit = {path for path in row["classes"]
                            if any(path.startswith(parent + "/") for parent in directories)}
                self.assertEqual(set(nodes), {""} | set(rojo.SERVICES) | (set(row["classes"]) - implicit))
                for path, node in nodes.items():
                    self.assertIs(node["$ignoreUnknownInstances"], True, path)
                    self.assertNotIn("$properties", node, path)
                    if path in row["sources"]:
                        self.assertIn("$path", node, path)
                    else:
                        expected = "DataModel" if not path else (rojo.SERVICES | row["classes"])[path]
                        self.assertEqual(node["$className"], expected, path)
                # Directory-backed data modules import their descendants once;
                # each implicit script separately preserves unknown Studio children.
                for path in implicit:
                    entry = row["sources"][path]
                    self.assertEqual(row["classes"][path], entry["class"], path)
                    metadata = (self.root / entry["file"]).with_suffix(".meta.json")
                    self.assertEqual(json.loads(metadata.read_text(encoding="utf-8")),
                                     {"ignoreUnknownInstances": True}, path)

    def test_opposite_variant_source_is_refused_even_with_matching_generated_project(self):
        path = self.manifest["split_paths"][0]
        self.manifest["variants"]["A"]["sources"][path] = copy.deepcopy(
            self.manifest["variants"]["B"]["sources"][path]
        )
        self.write_manifest(regenerate_projects=True)
        self.assert_refused()

    def test_shared_source_cannot_be_redirected_for_one_variant(self):
        path = next(iter(self.manifest["shared_sources"]))
        split = self.manifest["split_paths"][0]
        replacement = self.manifest["variants"]["A"]["sources"][split]["file"]
        self.manifest["variants"]["A"]["sources"][path]["file"] = replacement
        self.write_manifest(regenerate_projects=True)
        self.assert_refused()

    def test_shared_source_cannot_be_redirected_to_variant_files_for_both_scenes(self):
        path = next(iter(self.manifest["shared_sources"]))
        split = self.manifest["split_paths"][0]
        replacement = self.manifest["variants"]["A"]["sources"][split]["file"]
        self.manifest["shared_sources"][path]["file"] = replacement
        for variant in ("A", "B"):
            self.manifest["variants"][variant]["sources"][path] = copy.deepcopy(
                self.manifest["shared_sources"][path]
            )
        self.write_manifest(regenerate_projects=True)
        self.assert_refused()

    def test_unmapped_legacy_source_cannot_be_served(self):
        path = self.manifest["split_paths"][0]
        self.manifest["variants"]["A"]["sources"][path]["file"] = self.manifest["legacy_unmapped_files"][0]
        self.write_manifest(regenerate_projects=True)
        self.assert_refused()

    def test_world_properties_and_nested_deletion_are_refused(self):
        project_file = self.root / "A.project.json"
        baseline = json.loads(project_file.read_text(encoding="utf-8"))
        modified = copy.deepcopy(baseline)
        modified["tree"]["Workspace"] = {"$className": "Workspace", "$properties": {"Gravity": 0}}
        write_json(project_file, modified)
        self.assert_refused()
        modified = copy.deepcopy(baseline)
        nodes = project_nodes(modified)
        nodes["StarterPlayer/StarterPlayerScripts/GameClient/Controllers"]["$ignoreUnknownInstances"] = False
        write_json(project_file, modified)
        self.assert_refused()

    def test_default_requires_empty_live_place_allowlist(self):
        file = self.root / "default.project.json"
        baseline = json.loads(file.read_text(encoding="utf-8"))
        self.assertEqual(baseline["servePlaceIds"], [])
        for value in (None, [0], [123456]):
            with self.subTest(servePlaceIds=value):
                modified = copy.deepcopy(baseline)
                modified["servePlaceIds"] = value
                write_json(file, modified)
                self.assert_refused()
        modified = copy.deepcopy(baseline)
        del modified["servePlaceIds"]
        write_json(file, modified)
        self.assert_refused()

    def test_default_cannot_rewrite_place_or_universe_id(self):
        file = self.root / "default.project.json"
        baseline = json.loads(file.read_text(encoding="utf-8"))
        for field in ("placeId", "gameId"):
            with self.subTest(field=field):
                modified = copy.deepcopy(baseline)
                modified[field] = 0
                write_json(file, modified)
                self.assert_refused()

    def test_script_class_change_is_refused(self):
        path = next(iter(self.manifest["shared_sources"]))
        self.manifest["variants"]["B"]["classes"][path] = "Script"
        self.write_manifest(regenerate_projects=True)
        self.assert_refused()

    def test_source_cannot_escape_project(self):
        path = self.manifest["split_paths"][0]
        self.manifest["variants"]["A"]["sources"][path]["file"] = "../outside.luau"
        self.write_manifest(regenerate_projects=True)
        self.assert_refused()

    def test_new_source_requires_deliberate_manifest_update(self):
        source = self.root / "src/client/Controllers/Accidental.server.luau"
        source.write_text("return nil\n", encoding="utf-8")
        self.assert_refused()

    def test_modified_or_missing_implicit_metadata_is_refused(self):
        metadata = next((self.root / "src").rglob("*.meta.json"))
        original = metadata.read_bytes()
        write_json(metadata, {"ignoreUnknownInstances": False})
        self.assert_refused()
        metadata.write_bytes(original)
        metadata.unlink()
        self.assert_refused()

    def test_new_metadata_cannot_add_properties_to_an_explicit_source(self):
        path = self.manifest["split_paths"][0]
        source = self.root / self.manifest["variants"]["A"]["sources"][path]["file"]
        for extension in (".meta.json", ".meta.jsonc"):
            with self.subTest(extension=extension):
                metadata = source.with_suffix(extension)
                self.assertFalse(metadata.exists())
                write_json(metadata, {"properties": {"Archivable": False}})
                self.assert_refused()
                metadata.unlink()

    def test_model_injection_in_implicitly_mapped_data_is_refused(self):
        entry = next(row for row in self.manifest["shared_sources"].values()
                     if row["file"].endswith("/init.luau"))
        directory = (self.root / entry["file"]).parent
        write_json(directory / "Injected.model.json", {"ClassName": "Part"})
        self.assert_refused()


if __name__ == "__main__":
    unittest.main()
