"""Full frozen maze save positive and unsafe DOM refusals, in memory only."""
import copy
import importlib.util
import json
from pathlib import Path
import struct
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("maze02_save_audit", ROOT / "scripts/verify-maze02-copy.py")
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)


def fixture_after(before, payload, shadows):
    additions, changes, attributes = v.prepare_plan(before, payload)
    after = before.copy()

    def node(path):
        if after[path] is before.get(path):
            after[path] = copy.deepcopy(after[path])
        return after[path]

    for (path, prop), value in changes.items():
        node(path)["properties"][prop] = copy.deepcopy(value)
    for path in {path for path, _ in attributes}:
        raw = {name: bytes.fromhex(entry["raw"]) for name, entry in v.decode_attributes(before[path]["properties"]["AttributesSerialize"]).items()}
        for (target, name), row in attributes.items():
            if target != path:
                continue
            wanted = row["after"]
            if isinstance(wanted, dict) and wanted.get("kind") == "Nil":
                raw.pop(name, None)
            else:
                raw[name] = bytes.fromhex(v.encode_attributes({name: wanted})[1])[4:]
        data = struct.pack("<I", len(raw)) + b"".join(raw[name] for name in sorted(raw))
        node(path)["properties"]["AttributesSerialize"] = v.scalar("BinaryString", data.hex())
    for index, (path, row) in enumerate(additions.items(), 1):
        after[path] = v.default_node(before, row)
        after[path]["properties"]["UniqueId"] = v.scalar("UniqueId", f"{(1 << 124) + index:032x}")
    if shadows:
        module = copy.deepcopy(before[v.shadow.MODULE_TEMPLATE])
        module["properties"].update({"Name": v.scalar("string", "CornShadowController"),
                                     "Source": v.scalar("string", v.shadow.controller_source()),
                                     "UniqueId": v.scalar("UniqueId", f"{(15 << 124) + 1000:032x}"),
                                     "ScriptGuid": v.scalar("string", "{F1234567-89AB-CDEF-0123-456789ABCDEF}")})
        after[v.shadow.ADDED] = module
        for path in v.shadow.SHADOW_PATHS:
            node(path)["properties"]["Shadows"] = v.scalar("bool", "true")
    return after


def main():
    before, _, unknown = v.read_baseline()
    payload = v.read_payload()
    after = fixture_after(before, payload, True)
    positive = v.validate_dom(before, after, payload)
    assert positive["passed"] and positive["complete"]
    assert positive["added_world_nodes"] == 101 and positive["new_instances"] == 102
    assert positive["declared_property_changes"] == 1664 and positive["declared_attribute_changes"] == 131
    assert positive["unchanged_sources"] == 156 and positive["total_sources"] == 157
    without = fixture_after(before, payload, False)
    assert v.validate_dom(before, without, payload)["total_sources"] == 156
    refused = []

    def reject(name, edit):
        tree = after.copy()

        def node(path):
            if tree[path] is after.get(path):
                tree[path] = copy.deepcopy(tree[path])
            return tree[path]

        edit(tree, node)
        try:
            v.validate_dom(before, tree, payload)
        except (ValueError, KeyError, TypeError, IndexError):
            refused.append(name)
            return
        raise AssertionError("Unsafe maze save accepted: " + name)

    ground = "Workspace/CornMap/Ground"
    new = "Workspace/CornMap/NoCornZones/Maze02Masks/trail_001"
    folder = new.rpartition("/")[0]
    source = "ServerScriptService/GameServer/Game/MonsterHunt"
    reject("unchanged Source", lambda t, n: n(source)["properties"].__setitem__("Source", v.scalar("string", "return 0")))
    reject("optional Source", lambda t, n: n(v.shadow.ADDED)["properties"].__setitem__("Source", v.scalar("string", "return 0")))
    reject("ground position", lambda t, n: n(ground)["properties"]["CFrame"][2][0][1].__setitem__(1, "1"))
    reject("ground size", lambda t, n: n(ground)["properties"]["size"][2][0][1].__setitem__(1, "631"))
    reject("world deletion", lambda t, n: t.pop(ground))
    reject("world replacement UID", lambda t, n: n(ground)["properties"].__setitem__("UniqueId", v.scalar("UniqueId", "d" * 32)))
    reject("retained parent", lambda t, n: t.__setitem__("Workspace/Ground", t.pop(ground)))
    reject("new parent", lambda t, n: t.__setitem__(folder + "/Nested/trail_001", t.pop(new)))
    reject("missing trail", lambda t, n: t.pop(new))
    reject("extra child", lambda t, n: t.__setitem__(new + "/Extra", copy.deepcopy(after[new])))
    reject("new Source property", lambda t, n: n(new)["properties"].__setitem__("Source", v.scalar("string", "return 0")))
    reject("new nondefault capability", lambda t, n: n(new)["properties"].__setitem__("Capabilities", v.scalar("SecurityCapabilities", 1)))
    reject("new nondefault history", lambda t, n: n(new)["properties"].__setitem__("HistoryId", v.scalar("UniqueId", "b" * 32)))
    reject("new material variant", lambda t, n: n(new)["properties"].__setitem__("MaterialVariantSerialized", v.scalar("string", "Foreign")))
    reject("new collider", lambda t, n: n(new)["properties"].__setitem__("CanCollide", v.scalar("bool", "true")))
    reject("new wrong frame", lambda t, n: n(new)["properties"]["CFrame"][2][0][1].__setitem__(1, "0"))
    reject("new extra attribute", lambda t, n: n(new)["properties"].__setitem__("AttributesSerialize", v.encode_attributes(dict(payload["nodes"][1]["attributes"], Foreign=True))))
    reject("new missing ownership", lambda t, n: n(new)["properties"].__setitem__("AttributesSerialize", v.encode_attributes({"corn_project_id": "children_of_corn"})))
    reject("new tags", lambda t, n: n(new)["properties"].__setitem__("Tags", v.scalar("BinaryString", "666f726569676e")))
    reject("new zero UID", lambda t, n: n(new)["properties"].__setitem__("UniqueId", v.scalar("UniqueId", "0" * 32)))
    reject("new duplicate UID", lambda t, n: n(new)["properties"].__setitem__("UniqueId", copy.deepcopy(after[ground]["properties"]["UniqueId"])))
    reject("new missing property", lambda t, n: n(new)["properties"].pop("Massless"))
    reject("new wrong class", lambda t, n: n(new).__setitem__("class", "MeshPart"))
    changed = next(row for row in payload["changes"] if row["property"] == "Transparency")
    target = v.resolve_before(before, changed)
    reject("editor plant visibility partial", lambda t, n: n(target)["properties"].__setitem__("Transparency", v.scalar("float", 0)))
    barn = "Workspace/CornMap/Props/HouseWest/SM_Bld_Barn_03"
    reject("barn collision", lambda t, n: n(barn)["properties"].__setitem__("CanCollide", v.scalar("bool", "false")))
    reject("barn mesh hidden counter", lambda t, n: n(barn)["properties"].__setitem__("VertexCount", v.scalar("int", 9999)))
    reject("Lighting", lambda t, n: n("Lighting")["properties"].__setitem__("Brightness", v.scalar("float", 2)))
    reject("partial shadow flags", lambda t, n: n(sorted(v.shadow.SHADOW_PATHS)[0])["properties"].__setitem__("Shadows", v.scalar("bool", "false")))
    reject("controller missing but flags true", lambda t, n: t.pop(v.shadow.ADDED))
    reject("malformed Camera", lambda t, n: n("Workspace/Camera")["properties"].__setitem__("CFrame", v.scalar("CoordinateFrame", "foreign")))
    reject("Camera infinity", lambda t, n: n("Workspace/Camera")["properties"]["CFrame"][2][0][1].__setitem__(1, "inf"))
    reject("Camera type", lambda t, n: n("Workspace/Camera")["properties"].__setitem__("CameraType", v.scalar("token", 999)))
    edited_attrs = next(iter(v.prepare_plan(before, payload)[2]))[0]
    reject("attribute extra key", lambda t, n: n(edited_attrs)["properties"].__setitem__("AttributesSerialize", v.encode_attributes({"Foreign": True})))

    # Existing editor metadata remains narrow and independent of world changes.
    camera = after.copy()
    camera["Workspace/Camera"] = copy.deepcopy(camera["Workspace/Camera"])
    for prop in ("CFrame", "Focus"):
        camera["Workspace/Camera"]["properties"][prop][2][0][1][1] = "12.5"
    v.validate_dom(before, camera, payload)
    selection = after.copy()
    for index, path in enumerate(sorted(v.r.SELECTION_PATHS), 1):
        selection[path] = copy.deepcopy(selection[path])
        selection[path]["properties"]["UniqueId"] = v.scalar("UniqueId", f"{(2 << 124) + index:032x}")
    v.validate_dom(before, selection, payload)
    barrels = sorted(p for p, n in before.items() if n["properties"]["Name"] == v.scalar("string", "LookoutBarrel"))
    swap = {barrels[0]: barrels[1], barrels[1]: barrels[0]}
    reindexed = {swap.get(p, p): node | {"properties": {k: v.remap_refs(value, swap) for k, value in node["properties"].items()}} for p, node in after.items()}
    assert v.validate_dom(before, reindexed, payload)["reindexed_exporter_paths"] == 2
    for row in payload["changes"]:
        if row["path"].endswith("/LookoutBarrel"):
            assert row["selector"]["CFrame"] == row["before"]

    # The native CFrame constructor residue is accepted only against exact axis
    # compression; translation and a larger rotation edit remain refusals.
    axis = [0, 0, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0]
    residue = axis.copy(); residue[3] = residue[-1] = -4.371138828673793e-8
    assert v.compact_rotation_equal(axis, residue)
    residue[0] = .001; assert not v.compact_rotation_equal(axis, residue)
    residue[0] = 0; residue[3] = -1e-7; assert not v.compact_rotation_equal(axis, residue)

    terrain_refused = []
    v.r.validate_unknown(unknown, copy.deepcopy(unknown))
    for field in ("payload_sha256", "payload_bytes", "instance_count"):
        bad = copy.deepcopy(unknown)
        row = next(iter(bad["properties"].values()))
        row[field] = "0" * 64 if field == "payload_sha256" else row[field] + 1
        try:
            v.r.validate_unknown(unknown, bad)
        except ValueError:
            terrain_refused.append(field)
        else:
            raise AssertionError("Changed raw Terrain accepted")
    assert v.sha(v.PAYLOAD) == v.PAYLOAD_SHA256
    v.shadow.baseline_info()
    print(json.dumps({"passed": True, "refused_dom": len(refused), "refused_terrain": len(terrain_refused),
                      "declared_property_changes": positive["declared_property_changes"],
                      "declared_attribute_changes": positive["declared_attribute_changes"],
                      "new_world_nodes": 101, "unchanged_sources": 156,
                      "positives": ["full frozen maze with and without optional shadows", "finite Camera", "FilteredSelection", "UID-proven barrel sibling reindex"],
                      "scene_written": False}))


if __name__ == "__main__":
    main()
