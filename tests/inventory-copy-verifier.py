"""Actual read-only inventory preservation verifier with negative DOM fixtures.
Fixtures stay in Python memory. No engine scene is generated or reserialized.
"""
import copy
import importlib.util
import json
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("inventory", ROOT / "scripts/verify-inventory-copy.py")
f = importlib.util.module_from_spec(spec)
spec.loader.exec_module(f)
assert f.sha256(f.BASELINE) == f.BASELINE_HASH and f.BASELINE.stat().st_size == f.BASELINE_BYTES
BEFORE, _ = f.p.known_dom(f.BASELINE)
SOURCES = {path: node["properties"]["Source"][1].replace("\r\n", "\n") for path, node in BEFORE.items() if "Source" in node["properties"]}
CLASSES = {path: node["class"] for path, node in BEFORE.items() if f.p.owned(path)}
AFTER = {f.moved_path(path): {"class": node["class"], "properties": {key: copy.deepcopy(f.remap_refs(value)) for key, value in node["properties"].items()}} for path, node in BEFORE.items()}
for (path, prop), value in f.world_changes(BEFORE).items():
    AFTER[f.moved_path(path)]["properties"][prop] = copy.deepcopy(value)
for index, path in enumerate(sorted(f.ADDITIONS | {f.ARCHIVE}), 1):
    node = f.addition_template(BEFORE, path)
    node["properties"]["UniqueId"] = ["UniqueId", "%032x" % (2 ** 124 + index), []]
    if path in f.ADDITIONS:
        SOURCES[path] = "return %d\n" % index
        CLASSES[path] = "ModuleScript"
        node["properties"]["Source"] = ["string", SOURCES[path], []]
        node["properties"]["ScriptGuid"] = ["string", "{F0000000-0000-0000-0000-%012x}" % index, []]
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
    # Negative fixtures copy just their changed record, preserving the full
    # independently constructed 6829-node reference without repeated huge copies.
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
    raise AssertionError("Unsafe inventory fixture accepted: " + name)


report = validate(AFTER)
assert report["matching_sources"] == 65 and report["new_instances"] == 6
assert report["approved_torch_properties"] == 35 and report["archived_original_instances"] == 20
assert len(AFTER) == len(BEFORE) + 6 == 6829
assert f.world_changes(BEFORE)[(f.TORCH_ROOT + "/road_exit_row_01/Pole", "CFrame")][2][0][1][1] == "-14"
assert f.world_changes(BEFORE)[(f.TORCH_ROOT + "/road_exit_row_07/Pole", "CFrame")][2][2][1][1] == "385"

rejects("ground geometry", lambda a, *_: node(a, "Workspace/CornMap/Ground")["properties"]["CFrame"][2][0][1].__setitem__(1, "900"))
rejects("imported corn identity", lambda a, *_: node(a, "ServerStorage/SM_Prop_Plant_Corn_01_L")["properties"]["UniqueId"].__setitem__(1, "new-id"))
rejects("farm asset removal", lambda a, *_: a.pop("Workspace/CornMap/Props/RustedTruck"))
rejects("farm archive roof edit", lambda a, *_: node(a, "ServerStorage/CornFarmSceneArchive/HouseEast/Roof")["properties"]["size"][2][0][1].__setitem__(1, "500"))
rejects("source mismatch", lambda a, *_: node(a, EDITED_SOURCE)["properties"]["Source"].__setitem__(1, "return 'wrong'"))
rejects("source instance metadata", lambda a, *_: node(a, EDITED_SOURCE)["properties"]["UniqueId"].__setitem__(1, "new-id"))
rejects("unexpected source", lambda a, *_: a.__setitem__("ServerStorage/FakeScript", {"class": "ModuleScript", "properties": {"Name": ["string", "FakeScript", []], "Source": ["ProtectedString", "return 0", []]}}))
rejects("code Folder class", lambda a, *_: node(a, "ReplicatedStorage/GameShared/Game").__setitem__("class", "Model"))
rejects("original property addition", lambda a, *_: node(a, "Workspace/CornMap/Ground")["properties"].__setitem__("Fake", ["bool", "true", []]))
rejects("original property removal", lambda a, *_: node(a, "Workspace/CornMap/Ground")["properties"].pop("UniqueId"))
rejects("camera type edit", lambda a, *_: node(a, "Workspace/Camera")["properties"]["CameraType"].__setitem__(1, "999"))
rejects("selection arbitrary property", lambda a, *_: node(a, "FilteredSelection")["properties"]["SourceAssetId"].__setitem__(1, "55"))
rejects("original whitespace string edit", lambda a, *_: node(a, "Workspace/CornMap/Ground")["properties"]["MaterialVariantSerialized"].__setitem__(1, "   "))
rejects("archive removal", lambda a, *_: a.pop(f.ARCHIVE + "/road_exit_row_02/Pole"))
rejects("archive brightness changed", lambda a, *_: node(a, f.ARCHIVE + "/road_exit_row_02/Flame/TorchLight")["properties"]["Brightness"].__setitem__(1, "1"))
rejects("wrong archive reference", lambda a, *_: node(a, f.ARCHIVE + "/road_exit_row_02")["properties"]["PrimaryPart"].__setitem__(1, f.TORCH_ROOT + "/road_exit_row_02/Pole"))
rejects("archive rotation changed", lambda a, *_: node(a, f.ARCHIVE + "/road_exit_row_04/Pole")["properties"]["CFrame"][2][3][1].__setitem__(1, "0.99"))
rejects("retained brightness unhalved", lambda a, *_: node(a, f.TORCH_ROOT + "/road_exit_row_01/Flame/TorchLight")["properties"]["Brightness"].__setitem__(1, "2"))
rejects("retained brightness manual", lambda a, *_: node(a, f.TORCH_ROOT + "/road_exit_row_01/Flame/TorchLight")["properties"]["Brightness"].__setitem__(1, "0.99"))
rejects("exit light range edit", lambda a, *_: node(a, f.TORCH_ROOT + "/road_exit_row_01/Flame/TorchLight")["properties"]["Range"].__setitem__(1, "30"))
rejects("unapproved torch yaw", lambda a, *_: node(a, f.TORCH_ROOT + "/road_exit_row_01/Pole")["properties"]["CFrame"][2][3][1].__setitem__(1, "0.9"))
rejects("incorrect exit translation", lambda a, *_: node(a, f.TORCH_ROOT + "/road_exit_row_01/Pole")["properties"]["CFrame"][2][0][1].__setitem__(1, "-13"))
rejects("sub-ULP exit height edit", lambda a, *_: node(a, f.TORCH_ROOT + "/road_exit_row_01/Pole")["properties"]["CFrame"][2][1][1].__setitem__(1, "20.8999860000001"))
rejects("new rogue model", lambda a, *_: a.__setitem__("Workspace/CornMap/Props/Foreign", {"class": "Model", "properties": {"Name": ["string", "Foreign", []]}}))
rejects("new archive unexpected class", lambda a, *_: node(a, f.ARCHIVE).__setitem__("class", "Model"))
rejects("new archive attribute", lambda a, *_: node(a, f.ARCHIVE)["properties"]["AttributesSerialize"].__setitem__(1, "ffff"))
rejects("new archive added property", lambda a, *_: node(a, f.ARCHIVE)["properties"].__setitem__("Fake", ["bool", "true", []]))
rejects("new archive reused identity", lambda a, *_: node(a, f.ARCHIVE)["properties"].__setitem__("UniqueId", copy.deepcopy(BEFORE["Workspace/CornMap/KeySlots"]["properties"]["UniqueId"])))
rejects("new script nondefault capabilities", lambda a, *_: node(a, sorted(f.ADDITIONS)[0])["properties"]["Capabilities"].__setitem__(1, "100"))
rejects("new script invalid identity", lambda a, *_: node(a, sorted(f.ADDITIONS)[0])["properties"]["UniqueId"].__setitem__(1, "invalid"))
rejects("new script missing GUID", lambda a, *_: node(a, sorted(f.ADDITIONS)[0])["properties"].pop("ScriptGuid"))
rejects("new script invalid GUID", lambda a, *_: node(a, sorted(f.ADDITIONS)[0])["properties"]["ScriptGuid"].__setitem__(1, "invalid"))
rejects("new script duplicate GUID", lambda a, *_: node(a, sorted(f.ADDITIONS)[0])["properties"].__setitem__("ScriptGuid", copy.deepcopy(AFTER[sorted(f.ADDITIONS)[1]]["properties"]["ScriptGuid"])))
rejects("new script duplicate identity", lambda a, *_: node(a, sorted(f.ADDITIONS)[0])["properties"].__setitem__("UniqueId", copy.deepcopy(AFTER[sorted(f.ADDITIONS)[1]]["properties"]["UniqueId"])))
rejects("missing mapped new Source", lambda a, s, *_: s.pop(sorted(f.ADDITIONS)[0]))

indented = AFTER.copy()
moved = f.ARCHIVE + "/road_exit_row_02"
node(indented, moved)["properties"]["WorldPivotData"][1] = "\n       "
node(indented, moved + "/Pole")["properties"]["CFrame"][1] = "\n   "
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
        raise AssertionError("Unknown raw binary mutation accepted: " + mutation)
try:
    f.validate_unknown({"supported": False}, {"supported": False})
except ValueError:
    pass
else:
    raise AssertionError("Unavailable binary check accepted")
with tempfile.TemporaryDirectory(prefix="corn-inventory-verifier-") as temporary:
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
    "matching_sources": 65, "typed_torch_deltas": 35, "moved_instances": 20, "unsafe_dom_cases_rejected": len(rejected),
    "raw_binary_mutations_rejected": 3, "scope": "Real read-only verifier, baseline-derived in-memory fixtures, exact baseline bytes unchanged"}))
