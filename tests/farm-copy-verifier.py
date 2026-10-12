"""Negative fixtures for the actual read-only farm verifier.
Uses the immutable author baseline and real road/barn/FBX signatures, creates only
Python DOM fixtures in memory, and checks input scene bytes remain unchanged.
"""
import copy
import importlib.util
import json
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("farm", ROOT / "scripts/verify-farm-copy.py")
f = importlib.util.module_from_spec(spec)
spec.loader.exec_module(f)
BASELINE = ROOT / "place/Children_of_corn.before-autumn-20261012.rbxl"
BASELINE_HASH = f.sha256(BASELINE)
BEFORE, _ = f.p.known_dom(BASELINE)
ROAD = f.load_json(ROOT / "build/road-exit-allowlist-20261012.json")
BARNS = f.load_json(ROOT / "build/open-barns-allowlist-20261012.json")
WORLD_CHANGES = f.original_world_changes(ROAD, BARNS, BASELINE_HASH)
SPECS = f.world_specs(ROAD, BARNS, f.geometry_data(), BEFORE)


def leaf(tag, text):
    return [tag, text, []]


def fixture():
    after = {f.moved_path(path): {"class": node["class"], "properties": {key: copy.deepcopy(f.remap_refs(value)) for key, value in node["properties"].items()}} for path, node in BEFORE.items()}
    sources = {path: node["properties"]["Source"][1].replace("\r\n", "\n") for path, node in BEFORE.items() if "Source" in node["properties"]}
    classes = {path: node["class"] for path, node in BEFORE.items() if f.p.owned(path)}
    for index in range(32):
        path = "ReplicatedStorage/GameShared/Game/VerifierChunk%02d" % index
        sources[path] = "return %d\n" % index
        classes[path] = "ModuleScript"
        after[path] = {"class": "ModuleScript", "properties": {"Name": leaf("string", path.rsplit("/", 1)[1]), "Source": leaf("ProtectedString", sources[path]), "UniqueId": leaf("UniqueId", "new-code-%d" % index)}}
    for index, (path, expected) in enumerate(SPECS.items()):
        after[path] = {"class": expected["class"], "properties": {"Name": leaf("string", path.rsplit("/", 1)[1]), "UniqueId": leaf("UniqueId", "new-world-%d" % index), "AttributesSerialize": leaf("BinaryString", "")}}
        if expected["class"] in {"Part", "MeshPart"}:
            after[path]["properties"]["CFrame"] = ["CoordinateFrame", "", [[tag, leaf(tag, "1" if tag in {"R00", "R11", "R22"} else "0")] for tag in ["X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"]]]
    changes = {}
    for (path, prop), (_, expected) in WORLD_CHANGES.items():
        old = BEFORE[path]["properties"][prop]
        new = leaf("bool", "true" if expected else "false") if isinstance(expected, bool) else leaf(old[0], str(expected))
        after[f.moved_path(path)]["properties"][prop] = new
        changes.setdefault(path, {})[prop] = {"before": copy.deepcopy(old), "after": copy.deepcopy(new)}
    # Simulate editor camera/selection-only changes allowed by the real verifier.
    for prop in ("CFrame", "Focus"):
        after["Workspace/Camera"]["properties"][prop][2][0][1][1] = "102.5"
    for path in f.SELECTION_PATHS:
        after[path]["properties"]["UniqueId"] = leaf("UniqueId", "regenerated-editor-selection")
    # Moved values serialize at a different XML indentation depth. No semantic
    # numeric/string property difference may be hidden by normalization.
    after["ServerStorage/CornFarmSceneArchive/HouseEast/Body"]["properties"]["CFrame"][1] = "\n    "
    targets = {f.moved_path(path) for path in BEFORE}
    manifest = {"version": 1, "baseline_sha256": BASELINE_HASH, "expected_sources": 60,
        "moved_roots": copy.deepcopy(f.MOVES), "changes": changes,
        "added_instances": {path: copy.deepcopy(after[path]) for path in set(after) - targets}}
    return after, manifest, sources, classes


def validate(after, manifest, sources, classes):
    return f.validate_dom(BEFORE, after, manifest, sources, classes, WORLD_CHANGES, set(SPECS))


def rejects(name, mutate):
    after, manifest, sources, classes = fixture()
    mutate(after, manifest, sources, classes)
    try:
        validate(after, manifest, sources, classes)
    except (ValueError, KeyError):
        return
    raise AssertionError("Unsafe fixture accepted: " + name)


def typed_actual(expected):
    value = copy.deepcopy(expected)
    if value["type"] == "Instance":
        value = {"type": "Instance", "value": f.moved_path(value.get("value", value.get("path")))}
    elif value["type"] == "EnumItem" and not isinstance(value["value"], dict):
        enum, name = value["name"].rsplit(".", 1)
        value = {"type": "EnumItem", "value": {"enum": enum, "name": name, "value": value["value"]}}
    elif value["type"] == "CFrame" and "position" in value:
        right, up, look = value["right"], value["up"], value["look"]
        value = {"type": "CFrame", "value": value["position"] + [right[0], up[0], -look[0], right[1], up[1], -look[1], right[2], up[2], -look[2]]}
    return value


def typed_fixture():
    result = {}
    for path, expected in SPECS.items():
        attrs = expected.get("attrs", expected.get("attributes", expected.get("required_attributes", {})))
        props = expected.get("props", expected.get("properties", {}))
        tags = expected.get("tags", [])
        result[path] = {"class": expected["class"], "attributes": {key: typed_actual(v) for key, v in attrs.items()}, "properties": {key: typed_actual(v) for key, v in props.items()}, "tags": sorted(tags)}
    return result


def rejects_signature(name, mutate):
    signatures = typed_fixture()
    mutate(signatures)
    try:
        f.validate_world_signatures(signatures, SPECS)
    except (ValueError, KeyError):
        return
    raise AssertionError("Unsafe typed signature accepted: " + name)


after, manifest, sources, classes = fixture()
report = validate(after, manifest, sources, classes)
assert report["matching_sources"] == 60 and report["new_instances"] == 363
assert report["archived_original_instances"] == 15
assert len(manifest["changes"]) == 199
assert len(SPECS) == 331 and len(WORLD_CHANGES) == 223

rejects("original ground geometry", lambda a, *_: a["Workspace/CornMap/Ground"]["properties"]["CFrame"][2][0][1].__setitem__(1, "900"))
rejects("original corn asset UID", lambda a, *_: a["ServerStorage/SM_Prop_Plant_Corn_01_L"]["properties"]["UniqueId"].__setitem__(1, "new-id"))
rejects("archived roof size", lambda a, *_: a["ServerStorage/CornFarmSceneArchive/HouseEast/Roof"]["properties"]["size"][2][0][1].__setitem__(1, "500"))
rejects("archived body UID", lambda a, *_: a["ServerStorage/CornFarmSceneArchive/HouseEast/Body"]["properties"]["UniqueId"].__setitem__(1, "new-id"))
rejects("archive removal", lambda a, *_: a.pop("ServerStorage/CornFarmSceneArchive/HouseWest/Body"))
rejects("original camera type", lambda a, *_: a["Workspace/Camera"]["properties"]["CameraType"].__setitem__(1, "999"))
rejects("original property addition", lambda a, *_: a["Workspace/CornMap/Ground"]["properties"].__setitem__("Fake", leaf("bool", "true")))
rejects("unknown owned-looking addition", lambda a, *_: a.__setitem__("Workspace/CornMap/Props/Foreign", {"class": "Model", "properties": {"Name": leaf("string", "Foreign")}}))
rejects("source mismatch", lambda a, m, s, c: a[next(iter(s))]["properties"]["Source"].__setitem__(1, "return 'wrong'"))
rejects("extra Source", lambda a, *_: a.__setitem__("ServerStorage/FakeScript", {"class": "ModuleScript", "properties": {"Name": leaf("string", "FakeScript"), "Source": leaf("ProtectedString", "return 0")}}))
rejects("code Folder class", lambda a, *_: a["ReplicatedStorage/GameShared/Game"].__setitem__("class", "Model"))
rejects("changed move", lambda a, m, *_: m["moved_roots"][0].__setitem__("to", "ServerStorage/Other"))
rejects("missing allowlist new signature", lambda a, m, *_: m["added_instances"].pop("Workspace/CornMap/Props/RustedTruck"))
rejects("new signature mismatch", lambda a, *_: a["Workspace/CornMap/Props/RustedTruck"]["properties"]["UniqueId"].__setitem__(1, "new-unknown"))
rejects("manifest extra original delta", lambda a, m, *_: m["changes"].__setitem__("Workspace/CornMap/Ground", {"Name": {"before": leaf("string", "Ground"), "after": leaf("string", "Wrong")}}))
rejects("manifest forged before-value", lambda a, m, *_: m["changes"][next(iter(m["changes"]))]["Transparency"]["before"].__setitem__(1, "0.5"))
rejects("manifest broadened schema", lambda a, m, *_: m.__setitem__("ignore_unique_id", True))
rejects("manifest stale source count", lambda a, m, *_: m.__setitem__("expected_sources", 41))
rejects("selection arbitrary property", lambda a, *_: a["FilteredSelection"]["properties"]["SourceAssetId"].__setitem__(1, "55"))
rejects("missing authored UID", lambda a, *_: a["Workspace/CornMap/Ground"]["properties"].pop("UniqueId"))

f.validate_world_signatures(typed_fixture(), SPECS)
# Derived OriginalFrame uses immutable canonical geometry, never the rounded
# getter or an arbitrary candidate snapshot. Changing the source sidecar alone
# must not alter the expected original reference frame.
rounded = copy.deepcopy(ROAD)
rounded_record = next(row for row in rounded["new_instances"] if "OriginalFrame" in row.get("attrs", {}))
rounded_record["attrs"]["OriginalFrame"]["right"][0] += 0.2
stable_specs = f.world_specs(rounded, BARNS, f.geometry_data(), BEFORE)
assert stable_specs[rounded_record["path"]]["attrs"]["OriginalFrame"] == SPECS[rounded_record["path"]]["attrs"]["OriginalFrame"]
# Studio and Lune arithmetic may differ by one float32 ULP in derived sidecars.
expected_frame = {"type": "CFrame", "value": [0, 23.399993896484375, 421, 1, 0, 0, 0, 1, 0, 0, 0, 1]}
actual_frame = copy.deepcopy(expected_frame)
actual_frame["value"][1] = 23.399986267089844
assert f.typed_matches(actual_frame, expected_frame)
actual_frame["value"][3] += 1e-6
assert f.typed_matches(actual_frame, expected_frame)
actual_frame["value"][3] += 3e-6
assert not f.typed_matches(actual_frame, expected_frame)
actual_frame = copy.deepcopy(expected_frame)
actual_frame["value"][0] += 2e-4
assert not f.typed_matches(actual_frame, expected_frame)
assert f.typed_matches({"type": "Vector3", "value": [20, 12.00005, 24]}, {"type": "Vector3", "value": [20, 12, 24]})
assert not f.typed_matches({"type": "Vector3", "value": [20, 12.0002, 24]}, {"type": "Vector3", "value": [20, 12, 24]})
assert not f.typed_matches({"type": "Vector3", "value": [20, float("nan"), 24]}, {"type": "Vector3", "value": [20, 12, 24]})
# Even sidecar-permitted differences must not pass final exact canonical checks.
rejects("sub-ULP canonical new property", lambda a, m, *_: a["Workspace/CornMap/Props/RustedTruck/SM_Prop_Truck_Rusted_01"]["properties"]["CFrame"][2][0][1].__setitem__(1, "0.0000001"))
mesh_path = next(path for path, node in SPECS.items() if node["class"] == "MeshPart")
rejects_signature("mesh ownership false", lambda s: s[mesh_path]["attributes"]["CornFarmMeshOwned"].__setitem__("value", False))
rejects_signature("mesh project foreign", lambda s: s[mesh_path]["attributes"]["corn_project_id"].__setitem__("value", "foreign"))
rejects_signature("unknown extra attrs", lambda s: s[mesh_path]["attributes"].__setitem__("Manual", {"type": "boolean", "value": True}))
rejects_signature("new gameplay tag", lambda s: s[mesh_path]["tags"].append("corn_key_slot"))
rejects_signature("truck scale", lambda s: s["Workspace/CornMap/Props/RustedTruck"]["attributes"]["FarmUniformScale"].__setitem__("value", 1))
road_part = next(path for path, node in SPECS.items() if "CFrame" in node.get("props", {}) )
rejects_signature("road geometry", lambda s: s[road_part]["properties"]["CFrame"]["value"].__setitem__(0, 900))
shell = "ServerStorage/CornFarmSceneArchive/HouseEast/OpenBarnShell/LeftWall"
rejects_signature("archived shell geometry", lambda s: s[shell]["properties"]["Size"]["value"].__setitem__(0, 900))
rejects_signature("asset source hash", lambda s: s["ServerStorage/CornFarmAssets/SM_Bld_Barn_03"]["attributes"]["SourceFbxSHA256"].__setitem__("value", "bad"))

unknown = f.p.unknown_properties(BASELINE)
f.validate_unknown(unknown, copy.deepcopy(unknown))
changed = copy.deepcopy(unknown)
changed["properties"]["Terrain.VoxelGridAssetContentMap"]["payload_sha256"] = "changed"
try:
    f.validate_unknown(unknown, changed)
except ValueError:
    pass
else:
    raise AssertionError("Raw Terrain mutation accepted")
try:
    f.validate_unknown({"supported": False}, {"supported": False})
except ValueError:
    pass
else:
    raise AssertionError("Unsupported binary check accepted")

# Duplicate-key signatures must not silently replace a canonical record.
with tempfile.TemporaryDirectory(prefix="corn-farm-verifier-") as temporary:
    duplicate = Path(temporary) / "duplicate.json"
    duplicate.write_text('{"version":1,"version":2}', encoding="utf-8")
    try:
        f.load_json(duplicate)
    except ValueError:
        pass
    else:
        raise AssertionError("Duplicate JSON key accepted")

# Exercise the actual read-only Lune metadata helper on the real author file.
signatures, warning = f.typed_scene(BASELINE)
assert set(signatures) == set(BEFORE)
assert signatures["Workspace/CornMap"]["attributes"]["corn_project_id"] == {"type": "string", "value": "children_of_corn"}
assert signatures["Workspace/CornMap/Ground"]["properties"]["Material"]["type"] == "EnumItem"
assert f.sha256(BASELINE) == BASELINE_HASH
print("PASS: actual verifier on6459-node baseline DOM,223 deltas,331 new world paths,60 Source chunk adapter;21 unsafe DOM cases rejected; scoped sidecar ULP/rotation/vector tolerances")
print("PASS:8 unsafe ownership/geometry signatures +rawTerrain/unsupported/duplicateJSON rejected; actual typed metadata6459 paths; baseline bytes unchanged")
