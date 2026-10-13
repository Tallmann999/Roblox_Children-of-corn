"""Actual strict code-only readability verifier, in-memory positive/negative fixtures.
The immutable 75-Source engine baseline is read only; no RBXL is rewritten.
"""
import copy
import importlib.util
import json
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("readability", ROOT / "scripts/verify-readability-copy.py")
f = importlib.util.module_from_spec(spec)
spec.loader.exec_module(f)
assert f.sha256(f.BASELINE) == f.BASELINE_HASH and f.BASELINE.stat().st_size == f.BASELINE_BYTES
BEFORE, _ = f.p.known_dom(f.BASELINE)
AFTER = copy.deepcopy(BEFORE)
SOURCES = {path: node["properties"]["Source"][1].replace("\r\n", "\n") for path, node in BEFORE.items() if "Source" in node["properties"]}
CLASSES = {path: node["class"] for path, node in BEFORE.items() if f.p.owned(path)}
EDITED_SOURCE = "ServerScriptService/GameServer/Game/MonsterHunt"
SOURCES[EDITED_SOURCE] += "\n-- exact fixture source update\n"
AFTER[EDITED_SOURCE]["properties"]["Source"][1] = SOURCES[EDITED_SOURCE]
for prop in ("CFrame", "Focus"):
    AFTER["Workspace/Camera"]["properties"][prop][2][0][1][1] = "102.5"
for path in f.SELECTION_PATHS:
    if path in AFTER:
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
    raise AssertionError("Unsafe readability fixture accepted: " + name)


report = validate(AFTER)
assert report["matching_sources"] == 75 and report["new_instances"] == 0
assert report["world_and_lighting_exact"] and report["original_art_preserved"]
assert len(BEFORE) == 6839 and len(AFTER) == 6839
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
rejects("persistent raised stump", lambda a, *_: a.__setitem__("Workspace/CornMap/Props/CornEnergyStump", {"class": "Part", "properties": {"Name": ["string", "CornEnergyStump", []]}}))
rejects("persistent wooden step", lambda a, *_: a.__setitem__("Workspace/CornMap/Props/CornWoodenStep", {"class": "Part", "properties": {"Name": ["string", "CornWoodenStep", []]}}))
rejects("persistent awakening scream", lambda a, *_: a.__setitem__("Workspace/CornMap/ScarecrowMarker/CornAwakening", {"class": "Sound", "properties": {"Name": ["string", "CornAwakening", []]}}))
rejects("persistent cricket emitter", lambda a, *_: a.__setitem__("Workspace/CornMap/CornAudioCricket", {"class": "Part", "properties": {"Name": ["string", "CornAudioCricket", []]}}))
rejects("persistent torch sound", lambda a, *_: a.__setitem__("Workspace/CornMap/TorchMarkers/road_exit_row_01/Flame/CornFire", {"class": "Sound", "properties": {"Name": ["string", "CornFire", []]}}))
rejects("persistent sound category", lambda a, *_: a.__setitem__("SoundService/CornMusic", {"class": "SoundGroup", "properties": {"Name": ["string", "CornMusic", []]}}))
rejects("source mismatch", lambda a, *_: node(a, EDITED_SOURCE)["properties"]["Source"].__setitem__(1, "return 'wrong'"))
rejects("Source type changed", lambda a, *_: node(a, EDITED_SOURCE)["properties"]["Source"].__setitem__(0, "ProtectedString"))
rejects("Source nested value", lambda a, *_: node(a, EDITED_SOURCE)["properties"]["Source"].__setitem__(2, [["Bad", ["string", "payload", []]]]))
rejects("Source removed", lambda a, *_: node(a, EDITED_SOURCE)["properties"].pop("Source"))
rejects("existing Source property added", lambda a, *_: node(a, EDITED_SOURCE)["properties"].__setitem__("Fake", ["bool", "true", []]))
rejects("existing Source identity changed", lambda a, *_: node(a, EDITED_SOURCE)["properties"]["UniqueId"].__setitem__(1, "new-id"))
rejects("existing Source GUID changed", lambda a, *_: node(a, EDITED_SOURCE)["properties"]["ScriptGuid"].__setitem__(1, "{F0000000-0000-0000-0000-000000000001}"))
rejects("existing Source attribute changed", lambda a, *_: node(a, EDITED_SOURCE)["properties"]["AttributesSerialize"].__setitem__(1, "ffff"))
rejects("existing Source capabilities changed", lambda a, *_: node(a, EDITED_SOURCE)["properties"]["Capabilities"].__setitem__(1, "100"))
rejects("existing Source asset changed", lambda a, *_: node(a, EDITED_SOURCE)["properties"]["SourceAssetId"].__setitem__(1, "55"))
rejects("code Folder changed class", lambda a, *_: node(a, "ReplicatedStorage/GameShared/Game").__setitem__("class", "Model"))
rejects("existing Module changed class", lambda a, *_: node(a, EDITED_SOURCE).__setitem__("class", "Script"))
rejects("unknown Source", lambda a, *_: a.__setitem__("ServerStorage/FakeScript", {"class": "ModuleScript", "properties": {"Name": ["string", "FakeScript", []], "Source": ["string", "return 0", []]}}))
rejects("unknown code Folder", lambda a, *_: a.__setitem__("ReplicatedStorage/GameShared/Unknown", {"class": "Folder", "properties": {"Name": ["string", "Unknown", []]}}))
rejects("owned new Module", lambda a, *_: a.__setitem__("ReplicatedStorage/GameShared/Game/FakeScript", copy.deepcopy(AFTER[EDITED_SOURCE])))
rejects("authored property added", lambda a, *_: node(a, "Workspace/CornMap/Ground")["properties"].__setitem__("Fake", ["bool", "true", []]))
rejects("authored property removed", lambda a, *_: node(a, "Workspace/CornMap/Ground")["properties"].pop("UniqueId"))
rejects("camera type changed", lambda a, *_: node(a, "Workspace/Camera")["properties"]["CameraType"].__setitem__(1, "999"))
rejects("camera subject changed", lambda a, *_: node(a, "Workspace/Camera")["properties"]["CameraSubject"].__setitem__(1, "Workspace/CornMap/Props/RustedTruck"))
rejects("selection unrelated property", lambda a, *_: node(a, "FilteredSelection")["properties"]["SourceAssetId"].__setitem__(1, "55"))
rejects("authored whitespace string", lambda a, *_: node(a, "Workspace/CornMap/Ground")["properties"]["MaterialVariantSerialized"].__setitem__(1, "   "))
rejects("missing source mapping", lambda a, s, *_: s.pop(EDITED_SOURCE))
rejects("missing class mapping", lambda a, s, c: c.pop(EDITED_SOURCE))
rejects("baseline code missing", lambda a, *_: a.pop(EDITED_SOURCE))

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
with tempfile.TemporaryDirectory(prefix="corn-readability-verifier-") as temporary:
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
    "matching_sources": 75, "new_instances": 0, "unsafe_dom_cases_rejected": len(rejected),
    "raw_binary_mutations_rejected": 3, "scope": "Actual verifier, in-memory fixtures, all world/art/Lighting preserved, baseline bytes unchanged"}))
