"""Actual strict scarecrow engine-copy verifier, positive/negative DOM fixtures.
No RBXL is created or rewritten; the immutable 65-Source file is read only.
"""
import copy
import importlib.util
import json
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("scarecrow", ROOT / "scripts/verify-scarecrow-copy.py")
f = importlib.util.module_from_spec(spec)
spec.loader.exec_module(f)
assert f.sha256(f.BASELINE) == f.BASELINE_HASH and f.BASELINE.stat().st_size == f.BASELINE_BYTES
BEFORE, _ = f.p.known_dom(f.BASELINE)
AFTER = copy.deepcopy(BEFORE)
SOURCES = {path: node["properties"]["Source"][1].replace("\r\n", "\n") for path, node in BEFORE.items() if "Source" in node["properties"]}
CLASSES = {path: node["class"] for path, node in BEFORE.items() if f.p.owned(path)}
for index, path in enumerate(sorted(f.ADDITIONS), 1):
    node = f.addition_template(BEFORE, path)
    node["properties"]["UniqueId"] = ["UniqueId", "%032x" % (2 ** 124 + 100 + index), []]
    node["properties"]["ScriptGuid"] = ["string", "{F0000000-0000-0000-0000-%012x}" % (100 + index), []]
    SOURCES[path] = "return %d\n" % index
    node["properties"]["Source"] = ["string", SOURCES[path], []]
    CLASSES[path] = "ModuleScript"
    AFTER[path] = node
EDITED_SOURCE = "ServerScriptService/GameServer/Game/MonsterHunt"
SOURCES[EDITED_SOURCE] += "\n-- exact fixture source update\n"
AFTER[EDITED_SOURCE]["properties"]["Source"][1] = SOURCES[EDITED_SOURCE]
for prop in ("CFrame", "Focus"):
    AFTER["Workspace/Camera"]["properties"][prop][2][0][1][1] = "102.5"
for path in f.SELECTION_PATHS:
    AFTER[path]["properties"]["UniqueId"] = ["UniqueId", "1000000000000000000000000000cafe", []]


def validate(after, sources=None, classes=None):
    return f.validate_dom(BEFORE, after, SOURCES if sources is None else sources, CLASSES if classes is None else classes)


def node(after, path):
    after[path] = copy.deepcopy(after[path])
    return after[path]


rejected = []
def rejects(name, mutate):
    after, sources, classes = AFTER.copy(), SOURCES.copy(), CLASSES.copy()
    mutate(after, sources, classes)
    try:
        validate(after, sources, classes)
    except (ValueError, KeyError):
        rejected.append(name)
        return
    raise AssertionError("Unsafe scarecrow fixture accepted: " + name)


report = validate(AFTER)
assert report["matching_sources"] == 69 and report["new_instances"] == 4
assert report["world_and_lighting_exact"] and report["original_art_preserved"]
assert len(BEFORE) == 6829 and len(AFTER) == 6833
rejects("ground moved", lambda a, *_: node(a, "Workspace/CornMap/Ground")["properties"]["CFrame"][2][0][1].__setitem__(1, "900"))
rejects("ground size", lambda a, *_: node(a, "Workspace/CornMap/Ground")["properties"]["size"][2][0][1].__setitem__(1, "900"))
rejects("corn imported identity", lambda a, *_: node(a, "ServerStorage/SM_Prop_Plant_Corn_01_L")["properties"]["UniqueId"].__setitem__(1, "new-id"))
rejects("farm removed", lambda a, *_: a.pop("Workspace/CornMap/Props/RustedTruck"))
rejects("old farm archive roof changed", lambda a, *_: node(a, "ServerStorage/CornFarmSceneArchive/HouseEast/Roof")["properties"]["size"][2][0][1].__setitem__(1, "500"))
rejects("torch brighter", lambda a, *_: node(a, "Workspace/CornMap/TorchMarkers/road_exit_row_01/Flame/TorchLight")["properties"]["Brightness"].__setitem__(1, "2"))
rejects("torch shifted", lambda a, *_: node(a, "Workspace/CornMap/TorchMarkers/road_exit_row_01/Pole")["properties"]["CFrame"][2][0][1].__setitem__(1, "-13"))
rejects("archived torch changed", lambda a, *_: node(a, "ServerStorage/CornInventoryTorchArchive/road_exit_row_02/Flame/TorchLight")["properties"]["Brightness"].__setitem__(1, "1"))
rejects("archived torch reference", lambda a, *_: node(a, "ServerStorage/CornInventoryTorchArchive/road_exit_row_02")["properties"]["PrimaryPart"].__setitem__(1, "null"))
rejects("new persistent monster", lambda a, *_: a.__setitem__("Workspace/CornMap/Props/Monster", {"class": "Model", "properties": {"Name": ["string", "Monster", []]}}))
rejects("owned-looking runtime saved", lambda a, *_: a.__setitem__("Workspace/CornMap/CornRoundRuntime", {"class": "Folder", "properties": {"Name": ["string", "CornRoundRuntime", []]}}))
rejects("source mismatch", lambda a, *_: node(a, EDITED_SOURCE)["properties"]["Source"].__setitem__(1, "return 'wrong'"))
rejects("existing Source property added", lambda a, *_: node(a, EDITED_SOURCE)["properties"].__setitem__("Fake", ["bool", "true", []]))
rejects("existing Source identity changed", lambda a, *_: node(a, EDITED_SOURCE)["properties"]["UniqueId"].__setitem__(1, "new-id"))
rejects("code Folder changed class", lambda a, *_: node(a, "ReplicatedStorage/GameShared/Game").__setitem__("class", "Model"))
rejects("unknown Source", lambda a, *_: a.__setitem__("ServerStorage/FakeScript", {"class": "ModuleScript", "properties": {"Name": ["string", "FakeScript", []], "Source": ["string", "return 0", []]}}))
rejects("unknown code Folder", lambda a, *_: a.__setitem__("ReplicatedStorage/GameShared/Unknown", {"class": "Folder", "properties": {"Name": ["string", "Unknown", []]}}))
rejects("authored property added", lambda a, *_: node(a, "Workspace/CornMap/Ground")["properties"].__setitem__("Fake", ["bool", "true", []]))
rejects("authored property removed", lambda a, *_: node(a, "Workspace/CornMap/Ground")["properties"].pop("UniqueId"))
rejects("camera type changed", lambda a, *_: node(a, "Workspace/Camera")["properties"]["CameraType"].__setitem__(1, "999"))
rejects("camera subject changed", lambda a, *_: node(a, "Workspace/Camera")["properties"]["CameraSubject"].__setitem__(1, "Workspace/CornMap/Props/RustedTruck"))
rejects("selection unrelated property", lambda a, *_: node(a, "FilteredSelection")["properties"]["SourceAssetId"].__setitem__(1, "55"))
rejects("authored whitespace string", lambda a, *_: node(a, "Workspace/CornMap/Ground")["properties"]["MaterialVariantSerialized"].__setitem__(1, "   "))
rejects("new Source missing", lambda a, *_: a.pop(sorted(f.ADDITIONS)[0]))
rejects("new Source default metadata", lambda a, *_: node(a, sorted(f.ADDITIONS)[0])["properties"]["SourceAssetId"].__setitem__(1, "50"))
rejects("new Source attribute", lambda a, *_: node(a, sorted(f.ADDITIONS)[0])["properties"]["AttributesSerialize"].__setitem__(1, "ffff"))
rejects("new Source capabilities", lambda a, *_: node(a, sorted(f.ADDITIONS)[0])["properties"]["Capabilities"].__setitem__(1, "100"))
rejects("new Source invalid identity", lambda a, *_: node(a, sorted(f.ADDITIONS)[0])["properties"]["UniqueId"].__setitem__(1, "invalid"))
rejects("new Source reused identity", lambda a, *_: node(a, sorted(f.ADDITIONS)[0])["properties"].__setitem__("UniqueId", copy.deepcopy(BEFORE[EDITED_SOURCE]["properties"]["UniqueId"])))
rejects("new Source missing GUID", lambda a, *_: node(a, sorted(f.ADDITIONS)[0])["properties"].pop("ScriptGuid"))
rejects("new Source invalid GUID", lambda a, *_: node(a, sorted(f.ADDITIONS)[0])["properties"]["ScriptGuid"].__setitem__(1, "invalid"))
rejects("new Source duplicate GUID", lambda a, *_: node(a, sorted(f.ADDITIONS)[0])["properties"].__setitem__("ScriptGuid", copy.deepcopy(AFTER[sorted(f.ADDITIONS)[1]]["properties"]["ScriptGuid"])))
rejects("new Source duplicate identity", lambda a, *_: node(a, sorted(f.ADDITIONS)[0])["properties"].__setitem__("UniqueId", copy.deepcopy(AFTER[sorted(f.ADDITIONS)[1]]["properties"]["UniqueId"])))
rejects("new Source extra property", lambda a, *_: node(a, sorted(f.ADDITIONS)[0])["properties"].__setitem__("Fake", ["bool", "true", []]))
rejects("missing mapping", lambda a, s, *_: s.pop(sorted(f.ADDITIONS)[0]))

indented = AFTER.copy()
new_path = sorted(f.ADDITIONS)[0]
node(indented, new_path)["properties"]["LinkedSource"][1] = "\n   "
validate(indented)
assert f.normalized(["string", "   ", []]) == ["string", "   ", []]
unknown = f.p.unknown_properties(f.BASELINE)
f.validate_unknown(unknown, copy.deepcopy(unknown))
for mutation in ("payload_sha256", "instance_count", "payload_bytes"):
    changed = copy.deepcopy(unknown)
    key = next(iter(changed["properties"]))
    changed["properties"][key][mutation] = "changed"
    try:
        f.validate_unknown(unknown, changed)
    except ValueError:
        pass
    else:
        raise AssertionError("Unknown raw property mutation accepted: " + mutation)
try:
    f.validate_unknown({"supported": False}, {"supported": False})
except ValueError:
    pass
else:
    raise AssertionError("Unavailable binary check accepted")
with tempfile.TemporaryDirectory(prefix="corn-scarecrow-verifier-") as temporary:
    duplicate = Path(temporary) / "duplicate.json"
    duplicate.write_text('{"version":1,"version":2}', encoding="utf-8")
    try:
        f.load_json(duplicate)
    except ValueError:
        pass
    else:
        raise AssertionError("Duplicate build JSON accepted")
assert f.sha256(f.BASELINE) == f.BASELINE_HASH
print(json.dumps({"passed": True, "baseline_instances": len(BEFORE), "candidate_fixture_instances": len(AFTER),
    "matching_sources": 69, "new_module_scripts": 4, "unsafe_dom_cases_rejected": len(rejected),
    "raw_binary_mutations_rejected": 3, "scope": "Actual verifier, in-memory fixtures, all world/art/Lighting preserved, baseline bytes unchanged"}))
