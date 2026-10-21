"""Meaningful B shadow save refusals, all DOM mutations in memory only.

This fixture reads the immutable ZIP baseline once and never writes a scene,
report or parser cache. It does not launch Studio or replay historical installers.
"""
import copy
import importlib.util
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "corn_shadows_save_audit", ROOT / "scripts/verify-corn-shadows-copy.py"
)
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)


def scalar(kind, value):
    return [kind, str(value), []]


def main():
    before, _, unknown = v.read_baseline()
    source = v.controller_source()
    after = before.copy()
    module = copy.deepcopy(before[v.MODULE_TEMPLATE])
    props = module["properties"]
    props["Name"] = scalar("string", "CornShadowController")
    props["UniqueId"] = scalar("UniqueId", "ff0123456789abcdef0123456789abcd")
    props["ScriptGuid"] = scalar("string", "{F1234567-89AB-CDEF-0123-456789ABCDEF}")
    props["Source"] = scalar("string", source)
    after[v.ADDED] = module
    for path in v.SHADOW_PATHS:
        after[path] = copy.deepcopy(before[path])
        after[path]["properties"]["Shadows"] = scalar("bool", "true")

    def validate(tree):
        return v.validate_dom(before, tree, source)

    positive = validate(after)
    assert positive["passed"] and positive["complete"]
    assert positive["unchanged_sources"] == 156 and positive["total_sources"] == 157
    assert positive["new_instances"] == 1 and positive["shadow_changes"] == 2
    rejected = []

    def reject(name, edit):
        tree = after.copy()

        def node(path):
            if tree[path] is after.get(path):
                tree[path] = copy.deepcopy(tree[path])
            return tree[path]

        edit(tree, node)
        try:
            validate(tree)
        except (ValueError, KeyError, TypeError, IndexError):
            rejected.append(name)
            return
        raise AssertionError("Unsafe shadow save accepted: " + name)

    sources = sorted(path for path, node in before.items() if "Source" in node["properties"])
    for path in sources + [v.ADDED]:
        reject("changed Source:" + path,
               lambda tree, node, p=path: node(p)["properties"].__setitem__("Source", scalar("string", "return 'foreign'")))
    reject("missing new controller", lambda tree, node: tree.pop(v.ADDED))
    reject("missing retained world", lambda tree, node: tree.pop("Workspace/CornMap/Ground"))
    reject("new wrong parent", lambda tree, node: tree.__setitem__("Workspace/CornShadowController", tree.pop(v.ADDED)))
    reject("world wrong parent", lambda tree, node: tree.__setitem__("Workspace/Ground", tree.pop("Workspace/CornMap/Ground")))
    reject("extra instance", lambda tree, node: tree.__setitem__("Workspace/Foreign", copy.deepcopy(module)))
    for kind in ("Script", "LocalScript", "Folder"):
        reject("new class:" + kind, lambda tree, node, k=kind: node(v.ADDED).__setitem__("class", k))
    metadata = {
        "Name": scalar("string", "Other"),
        "UniqueId": scalar("UniqueId", "0" * 32),
        "ScriptGuid": scalar("string", "arbitrary"),
        "Capabilities": scalar("SecurityCapabilities", 1),
        "DefinesCapabilities": scalar("bool", "true"),
        "AttributesSerialize": scalar("BinaryString", "00"),
        "Tags": scalar("BinaryString", "00"),
        "SerializedOverrides": scalar("BinaryString", "00"),
        "SourceAssetId": scalar("int64", 123),
        "HistoryId": scalar("UniqueId", "f" * 32),
        "LinkedSource": scalar("ContentId", "rbxassetid://123"),
    }
    for prop, value in metadata.items():
        reject("new metadata:" + prop,
               lambda tree, node, p=prop, val=value: node(v.ADDED)["properties"].__setitem__(p, val))
    reject("new zero GUID", lambda tree, node: node(v.ADDED)["properties"].__setitem__("ScriptGuid", scalar("string", "{00000000-0000-0000-0000-000000000000}")))
    for prop in ("UniqueId", "ScriptGuid"):
        reject("new duplicate:" + prop,
               lambda tree, node, p=prop: node(v.ADDED)["properties"].__setitem__(p, copy.deepcopy(before[v.MODULE_TEMPLATE]["properties"][p])))
    reject("new extra property", lambda tree, node: node(v.ADDED)["properties"].__setitem__("Foreign", scalar("string", "bad")))
    reject("new missing property", lambda tree, node: node(v.ADDED)["properties"].pop("Capabilities"))
    reject("new Source type", lambda tree, node: node(v.ADDED)["properties"].__setitem__("Source", scalar("BinaryString", source)))
    reject("new Source children", lambda tree, node: node(v.ADDED)["properties"]["Source"][2].append(["null", scalar("null", "")]))
    reject("new child", lambda tree, node: tree.__setitem__(v.ADDED + "/Foreign", copy.deepcopy(module)))
    for path in sorted(v.SHADOW_PATHS):
        for value in (scalar("bool", "false"), scalar("string", "true"), scalar("bool", "1")):
            reject("bank Shadows:" + path + ":" + value[0] + value[1],
                   lambda tree, node, p=path, val=value: node(p)["properties"].__setitem__("Shadows", val))
        for prop in ("Brightness", "Range", "Angle", "Enabled", "Color", "HistoryId"):
            reject("bank other property:" + path + "/" + prop,
                   lambda tree, node, p=path, k=prop: node(p)["properties"].__setitem__(k, scalar("string", "foreign")))
    reject("bank pitch/attrs", lambda tree, node: node(v.BANK)["properties"].__setitem__("AttributesSerialize", scalar("BinaryString", "00")))
    ground = "Workspace/CornMap/Ground"
    for prop, value in {
        "CanCollide": scalar("bool", "false"),
        "UniqueId": scalar("UniqueId", "e" * 32),
        "Name": scalar("string", "MovedGround"),
    }.items():
        reject("retained world:" + prop, lambda tree, node, p=prop, val=value: node(ground)["properties"].__setitem__(p, val))
    reject("retained world class", lambda tree, node: node(ground).__setitem__("class", "MeshPart"))
    reject("retained property schema", lambda tree, node: node(ground)["properties"].__setitem__("Foreign", scalar("string", "bad")))
    reject("world dimensions", lambda tree, node: node(ground)["properties"]["size"][2][0][1].__setitem__(1, "631"))
    reject("map ownership", lambda tree, node: node("Workspace/CornMap")["properties"].__setitem__("AttributesSerialize", scalar("BinaryString", "00")))
    mesh = next(path for path, node in before.items()
                if path.startswith("Workspace/CornMap/") and "VertexCount" in node["properties"])
    reject("retained mesh counter", lambda tree, node: node(mesh)["properties"].__setitem__("VertexCount", scalar("int", 999999)))
    for prop in ("Brightness", "Ambient", "OutdoorAmbient", "FogStart", "FogEnd", "LightingStyle"):
        reject("Lighting:" + prop, lambda tree, node, p=prop: node("Lighting")["properties"].__setitem__(p, scalar("float", 999)))
    for prop in ("CFrame", "Focus"):
        reject("Camera malformed:" + prop, lambda tree, node, p=prop: node("Workspace/Camera")["properties"].__setitem__(p, scalar("CoordinateFrame", "arbitrary")))
        for value in ("nan", "inf", "1e40"):
            reject("Camera nonfinite:" + prop + value,
                   lambda tree, node, p=prop, val=value: node("Workspace/Camera")["properties"][p][2][0][1].__setitem__(1, val))
        reject("Camera duplicate component:" + prop,
               lambda tree, node, p=prop: node("Workspace/Camera")["properties"][p][2].__setitem__(1, copy.deepcopy(node("Workspace/Camera")["properties"][p][2][0])))
    camera = after.copy()
    camera["Workspace/Camera"] = copy.deepcopy(camera["Workspace/Camera"])
    for prop in ("CFrame", "Focus"):
        camera["Workspace/Camera"]["properties"][prop][2][0][1][1] = "12.5"
    validate(camera)
    selection = after.copy()
    for index, path in enumerate(sorted(v.r.SELECTION_PATHS), 1):
        selection[path] = copy.deepcopy(selection[path])
        selection[path]["properties"]["UniqueId"] = scalar("UniqueId", f"{(1 << 124) + index:032x}")
    validate(selection)

    # A legal sibling suffix reorder is proven through unchanged real Names,
    # unique IDs, parent IDs and remapped Ref values, never through path text.
    siblings = {}
    parents = {path.rpartition("/")[0] for path in after}
    for path, node in before.items():
        if path in parents or path in v.r.SELECTION_PATHS:
            continue
        key = (path.rpartition("/")[0], node["class"], node["properties"]["Name"][1])
        siblings.setdefault(key, []).append(path)
    pair = next(paths[:2] for paths in siblings.values() if len(paths) >= 2)
    swap = {pair[0]: pair[1], pair[1]: pair[0]}
    reindexed = {
        swap.get(path, path): node | {
            "properties": {prop: v.remap_refs(value, swap)
                           for prop, value in node["properties"].items()}
        } for path, node in after.items()
    }
    assert validate(reindexed)["reindexed_exporter_paths"] == 2
    reject("arbitrary sibling reindex Name change",
           lambda tree, node: node(pair[0])["properties"].__setitem__("Name", scalar("string", "Foreign")))

    v.r.validate_unknown(unknown, copy.deepcopy(unknown))
    terrain_rejected = []
    for field in ("payload_sha256", "payload_bytes", "instance_count"):
        bad = copy.deepcopy(unknown)
        row = next(iter(bad["properties"].values()))
        row[field] = "0" * 64 if field == "payload_sha256" else row[field] + 1
        try:
            v.r.validate_unknown(unknown, bad)
        except ValueError:
            terrain_rejected.append(field)
        else:
            raise AssertionError("Changed raw Terrain accepted: " + field)
    assert v.controller_source() == source
    v.baseline_info()
    print(json.dumps({
        "passed": True, "refused_dom": len(rejected), "refused_terrain": len(terrain_rejected),
        "unchanged_sources": 156, "total_sources": 157, "new_instances": 1,
        "positive_cases": ["exact requested change", "finite editor Camera",
                           "FilteredSelection identity", "identity-proven sibling suffix reorder"],
        "scene_written": False,
    }))


if __name__ == "__main__":
    main()
