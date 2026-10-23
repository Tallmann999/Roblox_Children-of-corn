"""Meaningful strict-save refusal fixtures on the complete accepted B DOM.

Only in-memory dictionaries are altered; no scene or frozen plan is written.
"""
from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("B_green_beds_save_audit", ROOT / "scripts/verify-B-green-beds-copy.py")
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)
builder_spec = importlib.util.spec_from_file_location("B_green_beds_plan_builder", ROOT / "scripts/build-B-green-beds-world-plan.py")
b = importlib.util.module_from_spec(builder_spec)
builder_spec.loader.exec_module(b)


def fixture(before):
    sources = {p: {"class": n["class"], "sha256": v.source_sha(n["properties"]["Source"][1])}
               for p, n in before.items() if "Source" in n["properties"]}
    changed = "ReplicatedStorage/GameShared/Game/CornAppearance"
    text = before[changed]["properties"]["Source"][1].replace("\r\n", "\n") + "\n-- In-memory green-beds fixture.\n"
    added_source = "ReplicatedStorage/GameShared/Game/GreenBedsFixture"
    added_part = "Workspace/CornMap/GreenBedFixture"
    body = "return { Owned = true }\n"
    payload = {"owner": v.OWNER, "sources": sources,
               "sourceChanges": {changed: {"before_sha256": sources[changed]["sha256"],
                                           "after_sha256": v.source_sha(text), "source": text}},
               "newSources": {added_source: {"class": "ModuleScript", "sha256": v.source_sha(body), "source": body}}}
    corn = next(p for p, n in before.items() if p.startswith("Workspace/CornMap/EditorFieldOverview/") and n["class"] == "MeshPart")
    world = {"version": 1, "owner": v.OWNER, "baseline_sha256": v.BASELINE_SHA256,
             "payload_sha256": "a" * 64,
             "retained_changes": [{"path": corn, "uid": v.identity(before[corn]), "property": "TextureContent",
                                   "before": copy.deepcopy(before[corn]["properties"]["TextureContent"]),
                                   "after": ["Content", "", [["uri", ["uri", "rbxassetid://137803536172445", []]]]]}],
             "new_nodes": {}}
    source_node = copy.deepcopy(before[changed])
    for generated in v.GENERATED:
        source_node["properties"].pop(generated, None)
    source_node["properties"]["Name"] = v.scalar("string", "GreenBedsFixture")
    source_node["properties"]["Source"] = v.scalar("string", body)
    world["new_nodes"][added_source] = source_node
    part_node = copy.deepcopy(before[corn])
    for generated in v.GENERATED:
        part_node["properties"].pop(generated, None)
    part_node["properties"]["Name"] = v.scalar("string", "GreenBedFixture")
    part_node["properties"]["MeshContent"] = ["Content", "", [["null", ["null", "", []]]]]
    world["new_nodes"][added_part] = part_node
    after = before.copy()
    after[changed] = copy.deepcopy(before[changed])
    after[changed]["properties"]["Source"] = v.scalar("string", text)
    after[corn] = copy.deepcopy(before[corn])
    after[corn]["properties"]["TextureContent"] = copy.deepcopy(world["retained_changes"][0]["after"])
    for i, (path, expected) in enumerate(world["new_nodes"].items(), 1):
        after[path] = copy.deepcopy(expected)
        after[path]["properties"]["UniqueId"] = v.scalar("UniqueId", f"f00000000000000000000000000000{i:02x}")
        after[path]["properties"]["HistoryId"] = v.scalar("UniqueId", "0" * 32)
        if expected["class"] == "ModuleScript":
            after[path]["properties"]["ScriptGuid"] = v.scalar("string", "{12345678-9ABC-DEF0-1234-56789ABCDEF0}")
    return payload, world, after, changed, corn, added_source, added_part


def builder_fixture(before, payload):
    c, _ = v.r.p.known_dom(v.C_SCENE)
    prototypes = b.prototype_nodes(c)
    def numbers(value):
        return [b.m.f32(float(row[1][1])) for row in value[2]]
    proposal = {"version": 1, "owner": v.OWNER, "baseline_sha256": v.BASELINE_SHA256,
                "payload_sha256": "a" * 64, "old": [], "new_nodes": {}}
    for path, node in before.items():
        if node["class"] != "MeshPart" or not (v.under(path, "Workspace/CornMap/EditorFieldOverview") or v.under(path, "Workspace/CornMap/EditorPreview")):
            continue
        props = node["properties"]
        old_frame, size = numbers(props["CFrame"]), numbers(props["size"])
        frame = old_frame.copy(); frame[0] += .25
        proposal["old"].append({"path": path.rpartition("/")[0] + "/" + props["Name"][1],
                                "oldFrame": old_frame, "beforeSize": size,
                                "oldTexture": props["TextureContent"][2][0][1][1],
                                "cframe": frame, "size": size, "color": [1, 1, 1],
                                "texture": "rbxassetid://137803536172445", "transparency": int(props["Transparency"][1])})
    folder = "Workspace/CornMap/GreenBedEditor"
    proposal["new_nodes"][folder] = {"class": "Folder", "prototype": "Folder", "properties": {},
                                     "attributes": {"GreenBedEditorOwned": True}, "tags": []}
    for i in range(1406):
        key = ("Center", "End", "Skirt")[i % 3]
        source = prototypes[key]["properties"]
        props = {"CFrame": {"kind": "CFrame", "value": [float(i), 15, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1]},
                 "Size": {"kind": "Vector3", "value": numbers(source["size"])},
                 "InitialSize": {"kind": "Vector3", "value": numbers(source["InitialSize"])},
                 "PivotOffset": {"kind": "CFrame", "value": numbers(source["PivotOffset"])},
                 "Color": {"kind": "Color3", "value": [1, 1, 1]},
                 "TextureID": "rbxassetid://95855894892409", "Transparency": 0}
        path = folder + "/" + b.PROTOTYPE_NAMES[key] + f"_{i + 1:04d}"
        proposal["new_nodes"][path] = {"class": "MeshPart", "prototype": key, "properties": props,
                                       "attributes": {"GreenBedOwned": True, "Key": key}, "tags": []}
    for path, row in payload["newSources"].items():
        proposal["new_nodes"][path] = {"class": row["class"], "prototype": "ModuleScript", "properties": {},
                                       "attributes": {"GreenBedCodeOwned": True}, "tags": []}
    world = b.build(before, c, payload, proposal, proposal["payload_sha256"])
    assert len(world["new_nodes"]) == 1408 and len(world["retained_changes"]) >= 3480
    assert all(not (v.GENERATED & set(row["properties"])) for row in world["new_nodes"].values())
    empty_arrays = copy.deepcopy(proposal)
    for row in empty_arrays["new_nodes"].values():
        if row["class"] in {"ModuleScript", "Folder"}:
            row["properties"] = []  # HttpService's empty-table encoding.
    assert b.build(before, c, payload, empty_arrays, proposal["payload_sha256"]) == world
    failed = []
    for name, mutate in (
            ("old missing corn", lambda p: p["old"].pop()),
            ("old wrong before pose", lambda p: p["old"][0]["oldFrame"].__setitem__(0, 9999)),
            ("old duplicate target", lambda p: p["old"].__setitem__(1, copy.deepcopy(p["old"][0]))),
            ("old yellow texture", lambda p: p["old"][0].__setitem__("texture", "rbxassetid://103653296385119")),
            ("old physics allowance", lambda p: p["old"][0].__setitem__("CanCollide", True)),
            ("new source protected GUID request", lambda p: p["new_nodes"][next(iter(payload["newSources"]))]["properties"].__setitem__("ScriptGuid", "{12345678-9ABC-DEF0-1234-56789ABCDEF0}")),
            ("new private geometry allowance", lambda p: p["new_nodes"][next(path for path, row in p["new_nodes"].items() if row["class"] == "MeshPart")]["properties"].__setitem__("PhysicalConfigData", "bad")),
            ("new mesh empty overrides", lambda p: p["new_nodes"][next(path for path, row in p["new_nodes"].items() if row["class"] == "MeshPart")].__setitem__("properties", [])),
            ("new source nonempty override array", lambda p: p["new_nodes"][next(iter(payload["newSources"]))].__setitem__("properties", ["unsafe"])),
    ):
        bad = copy.deepcopy(proposal)
        mutate(bad)
        try:
            b.build(before, c, payload, bad, proposal["payload_sha256"])
        except (ValueError, TypeError, KeyError):
            failed.append(name)
        else:
            raise AssertionError("Unsafe world-plan proposal accepted: " + name)
    return {"passed": True, "old_corn": len(proposal["old"]), "new_beds": 1406,
            "new_nodes": len(world["new_nodes"]), "property_changes": len(world["retained_changes"]),
            "refusals": failed, "C_proto_private_fields_preserved": True}


def main():
    before, warning, unknown = v.read_baseline()
    payload, world, after, changed, corn, new_source, new_part = fixture(before)
    positive = v.validate_dom(before, after, payload, world, world["payload_sha256"])
    assert positive["complete"] and positive["total_sources"] == 158 and positive["new_instances"] == 2
    refused = []

    def reject(name, mutate):
        tree, proposal, planned = after.copy(), copy.deepcopy(payload), copy.deepcopy(world)
        copied = set()
        def node(path):
            if path not in copied:
                tree[path] = copy.deepcopy(tree[path]); copied.add(path)
            return tree[path]
        mutate(tree, node, proposal, planned)
        try:
            v.validate_dom(before, tree, proposal, planned, world["payload_sha256"])
        except (ValueError, KeyError, TypeError, IndexError):
            refused.append(name)
            return
        raise AssertionError("Unsafe candidate/manifest accepted: " + name)

    ground = "Workspace/CornMap/Ground"
    retained_source = next(p for p in payload["sources"] if p != changed)
    reject("undeclared retained Source", lambda t, n, p, w: n(retained_source)["properties"].__setitem__("Source", v.scalar("string", "return 0")))
    reject("partial changed Source", lambda t, n, p, w: n(changed)["properties"].__setitem__("Source", before[changed]["properties"]["Source"]))
    reject("changed Source hidden property", lambda t, n, p, w: n(changed)["properties"].__setitem__("Archivable", v.scalar("bool", "false")))
    reject("missing Source guard", lambda t, n, p, w: p["sources"].pop(retained_source))
    reject("wrong Source class", lambda t, n, p, w: p["sources"][retained_source].__setitem__("class", "Script"))
    reject("wrong Source body", lambda t, n, p, w: p["sourceChanges"][changed].__setitem__("source", "return 0"))
    reject("wrong new Source body", lambda t, n, p, w: n(new_source)["properties"].__setitem__("Source", v.scalar("string", "return 0")))
    reject("new Source disabled delta", lambda t, n, p, w: n(new_source)["properties"].__setitem__("Disabled", v.scalar("bool", "true")))
    reject("new Source malformed ScriptGuid", lambda t, n, p, w: n(new_source)["properties"].__setitem__("ScriptGuid", v.scalar("string", "invalid")))
    reject("new Source old ScriptGuid", lambda t, n, p, w: n(new_source)["properties"].__setitem__("ScriptGuid", before[changed]["properties"]["ScriptGuid"]))
    reject("new Source zero ScriptGuid", lambda t, n, p, w: n(new_source)["properties"].__setitem__("ScriptGuid", v.scalar("string", "{00000000-0000-0000-0000-000000000000}")))
    reject("new node malformed HistoryId", lambda t, n, p, w: n(new_part)["properties"].__setitem__("HistoryId", v.scalar("UniqueId", "bad")))
    reject("new Source graph missing", lambda t, n, p, w: p["newSources"].clear())
    reject("new Source graph extra", lambda t, n, p, w: p["newSources"].__setitem__(new_source + "X", copy.deepcopy(p["newSources"][new_source])))
    reject("retained world removed", lambda t, n, p, w: t.pop(ground))
    reject("retained world identity replaced", lambda t, n, p, w: n(ground)["properties"].__setitem__("UniqueId", v.scalar("UniqueId", "b" * 32)))
    reject("retained world zero identity", lambda t, n, p, w: n(ground)["properties"].__setitem__("UniqueId", v.scalar("UniqueId", "0" * 32)))
    reject("retained world duplicate identity", lambda t, n, p, w: n(ground)["properties"].__setitem__("UniqueId", copy.deepcopy(t[corn]["properties"]["UniqueId"])))
    reject("retained world class", lambda t, n, p, w: n(ground).__setitem__("class", "MeshPart"))
    reject("retained world Name", lambda t, n, p, w: n(ground)["properties"].__setitem__("Name", v.scalar("string", "Changed")))
    reject("retained parent", lambda t, n, p, w: t.__setitem__("Workspace/Ground", t.pop(ground)))
    reject("world position", lambda t, n, p, w: n(ground)["properties"]["CFrame"][2][0][1].__setitem__(1, "999"))
    reject("world geometry", lambda t, n, p, w: n(ground)["properties"]["size"][2][0][1].__setitem__(1, "999"))
    reject("world physics", lambda t, n, p, w: n(ground)["properties"].__setitem__("CanCollide", v.scalar("bool", "false")))
    reject("world Lighting", lambda t, n, p, w: n("Lighting")["properties"].__setitem__("Brightness", v.scalar("float", "99")))
    reject("undeclared corn property", lambda t, n, p, w: n(corn)["properties"].__setitem__("DoubleSided", v.scalar("bool", "false" if before[corn]["properties"]["DoubleSided"][1] == "true" else "true")))
    reject("partial corn mesh change", lambda t, n, p, w: n(corn)["properties"].__setitem__("TextureContent", before[corn]["properties"]["TextureContent"]))
    reject("wrong original corn UID", lambda t, n, p, w: w["retained_changes"][0].__setitem__("uid", "b" * 32))
    reject("wrong original property", lambda t, n, p, w: w["retained_changes"][0].__setitem__("before", v.scalar("string", "wrong")))
    reject("duplicated declared property", lambda t, n, p, w: w["retained_changes"].append(copy.deepcopy(w["retained_changes"][0])))
    reject("protected property allowed", lambda t, n, p, w: w["retained_changes"][0].__setitem__("property", "UniqueId"))
    reject("Lighting allowance widened", lambda t, n, p, w: w["retained_changes"][0].__setitem__("path", "Lighting"))
    reject("undeclared added node", lambda t, n, p, w: t.__setitem__("Workspace/CornMap/Extra", copy.deepcopy(t[new_part])))
    reject("new node omitted", lambda t, n, p, w: t.pop(new_part))
    reject("new node real Name", lambda t, n, p, w: n(new_part)["properties"].__setitem__("Name", v.scalar("string", "Different")))
    reject("new node class", lambda t, n, p, w: n(new_part).__setitem__("class", "Part"))
    reject("new node parent", lambda t, n, p, w: t.__setitem__("Workspace/GreenBedFixture", t.pop(new_part)))
    reject("new mesh content", lambda t, n, p, w: n(new_part)["properties"].__setitem__("MeshContent", before[corn]["properties"]["MeshContent"]))
    reject("new mesh hidden data", lambda t, n, p, w: n(new_part)["properties"].__setitem__("AeroMeshData", v.scalar("SharedString", "01")))
    reject("new node added property", lambda t, n, p, w: n(new_part)["properties"].__setitem__("Unexpected", v.scalar("string", "x")))
    reject("new node omitted property", lambda t, n, p, w: n(new_part)["properties"].pop("CastShadow"))
    reject("new node attributes", lambda t, n, p, w: n(new_part)["properties"].__setitem__("AttributesSerialize", v.scalar("BinaryString", "00000000")))
    reject("new node tags", lambda t, n, p, w: n(new_part)["properties"].__setitem__("Tags", v.scalar("BinaryString", "61")))
    reject("world-plan owner", lambda t, n, p, w: w.__setitem__("owner", "foreign"))
    reject("world-plan bool version", lambda t, n, p, w: w.__setitem__("version", True))
    reject("world-plan baseline", lambda t, n, p, w: w.__setitem__("baseline_sha256", "b" * 64))
    reject("world-plan payload pin", lambda t, n, p, w: w.__setitem__("payload_sha256", "b" * 64))
    reject("world-plan unknown skip flag", lambda t, n, p, w: w.__setitem__("skip", True))
    reject("world-plan missing complete property", lambda t, n, p, w: w["new_nodes"][new_part]["properties"].pop("CanCollide"))
    reject("world-plan new UID exception widened", lambda t, n, p, w: w["new_nodes"][new_part]["properties"].__setitem__("UniqueId", t[new_part]["properties"]["UniqueId"]))

    camera = after.copy()
    camera["Workspace/Camera"] = copy.deepcopy(camera["Workspace/Camera"])
    camera["Workspace/Camera"]["properties"]["CFrame"][2][0][1][1] = "1"
    assert v.validate_dom(before, camera, payload, world, world["payload_sha256"])["complete"]
    reject("nonfinite Camera", lambda t, n, p, w: n("Workspace/Camera")["properties"]["CFrame"][2][0][1].__setitem__(1, "nan"))

    # Exporter sibling suffixes may reindex without changing any real identities.
    candidates = [p for p in after if p.startswith("Workspace/CornMap/EditorFieldOverview/") and "#" in p]
    first = candidates[0]
    second = candidates[1]
    reindexed = after.copy()
    reindexed[first], reindexed[second] = reindexed[second], reindexed[first]
    assert v.validate_dom(before, reindexed, payload, world, world["payload_sha256"])["complete"]

    v.r.validate_unknown(unknown, copy.deepcopy(unknown))
    terrain_refusals = []
    for field in ("payload_sha256", "instance_count", "payload_bytes"):
        bad = copy.deepcopy(unknown)
        row = next(iter(bad["properties"].values()))
        row[field] = "f" * 64 if field == "payload_sha256" else row[field] + 1
        try:
            v.r.validate_unknown(unknown, bad)
        except ValueError:
            terrain_refusals.append(field)
        else:
            raise AssertionError("Changed unknown/raw Terrain accepted")
    try:
        v.unique_object([("owner", "one"), ("owner", "two")])
    except ValueError:
        pass
    else:
        raise AssertionError("Duplicate JSON key accepted")
    builder_result = builder_fixture(before, payload)
    print(json.dumps({"passed": True, "baseline_instances": len(before), "baseline_sources": len(payload["sources"]),
                      "candidate_instances": positive["candidate_instances"], "candidate_sources": positive["total_sources"],
                      "refusals": len(refused), "refused": refused, "raw_terrain_refusals": terrain_refusals,
                      "positive_camera": True, "positive_sibling_reindex": True, "duplicate_json_refused": True,
                      "world_plan_builder": builder_result,
                      "scope": "In-memory fixtures only; no scene or production manifest mutation", "baseline_warning": warning}))


if __name__ == "__main__":
    main()
