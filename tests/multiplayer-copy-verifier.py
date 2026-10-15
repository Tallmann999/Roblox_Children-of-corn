"""Real exact save checker with 2 ModuleScript additions and 16 declared Sources.
No scene is written; engine rendering/audio and final save remain separate.
"""
import copy
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("multiplayer_audit", ROOT / "scripts/verify-multiplayer-copy.py")
f = importlib.util.module_from_spec(spec)
spec.loader.exec_module(f)
assert f.sha256(f.BASELINE) == f.BASELINE_HASH and f.BASELINE.stat().st_size == f.BASELINE_BYTES
BEFORE, _ = f.r.p.known_dom(f.BASELINE)
SOURCES, CLASSES = f.mapping_from_sourcemap(ROOT / "build/sourcemap.json")
ASSETS = f.fog.current_sources()
CURRENT = copy.deepcopy(BEFORE)
for index, path in enumerate(sorted(f.ADDITIONS), 1):
    CURRENT[path] = copy.deepcopy(BEFORE["ServerScriptService/GameServer/Game/RoundAudio"])
    props = CURRENT[path]["properties"]
    props["Name"][1] = path.rsplit("/", 1)[1]
    props["UniqueId"][1] = f"{(1 << 125) + index:032x}"
    props["ScriptGuid"][1] = "{A0000000-0000-0000-0000-" + f"{index:012x}" + "}"

for path, source in (SOURCES | ASSETS).items():
    CURRENT[path]["properties"]["Source"][1] = source
current_report = f.validate_dom(BEFORE, CURRENT, SOURCES, CLASSES, ASSETS)
EXPECTED = SOURCES.copy()
AFTER = copy.deepcopy(CURRENT)
for path in f.DECLARED_SOURCES:
    EXPECTED[path] += "\n-- controlled sixteen-source checker fixture\n"
    AFTER[path]["properties"]["Source"][1] = EXPECTED[path]


def node(after, path):
    after[path] = copy.deepcopy(after[path])
    return after[path]


def component(after, path, prop, key, text):
    for name, child in node(after, path)["properties"][prop][2]:
        if name == key:
            child[1] = str(text)
            return
    raise AssertionError("Missing test component")


def validate(after, sources=None, assets=None):
    return f.validate_dom(BEFORE, after, sources or EXPECTED, CLASSES, assets or ASSETS)


rejected = []
def rejects(name, mutate, sources=None, assets=None):
    after = AFTER.copy()
    mutate(after)
    try:
        validate(after, sources, assets)
    except (ValueError, KeyError, IndexError):
        rejected.append(name)
        return
    raise AssertionError("Unsafe multiplayer save accepted: " + name)


report = validate(AFTER)
assert report["total_sources"] == 80 and report["matching_sources"] == 77 and report["matching_asset_sources"] == 3
assert report["new_instances"] == 2 and report["removed_instances"] == 0 and report["source_change_count"] == 16
assert set(report["source_changes"]) == f.DECLARED_SOURCES and report["world_and_lighting_exact"]
for path in sorted(f.DECLARED_SOURCES | f.ADDITIONS):
    rejects(path + " mismatch", lambda a, path=path: node(a, path)["properties"]["Source"].__setitem__(1, "return 'wrong'"))
    rejects(path + " Source type", lambda a, path=path: node(a, path)["properties"]["Source"].__setitem__(0, "ProtectedString"))
    rejects(path + " identity", lambda a, path=path: node(a, path)["properties"]["UniqueId"].__setitem__(1, BEFORE["Workspace/CornMap/Ground"]["properties"]["UniqueId"][1] if path in f.ADDITIONS else "f" * 32))
    rejects(path + " ScriptGuid", lambda a, path=path: node(a, path)["properties"]["ScriptGuid"].__setitem__(1, "not-a-guid" if path in f.ADDITIONS else "{F0000000-0000-0000-0000-000000000000}"))
    rejects(path + " extra property", lambda a, path=path: node(a, path)["properties"].__setitem__("Unreviewed", ["bool", "false", []]))
    rejects(path + " capabilities", lambda a, path=path: node(a, path)["properties"]["Capabilities"].__setitem__(1, "1"))

outside = next(path for path in SOURCES if path not in f.DECLARED_SOURCES | f.ADDITIONS)
changed_expected = EXPECTED | {outside: EXPECTED[outside] + "\n-- outside the approved sixteen\n"}
rejects("seventeenth existing Source even when equal to src", lambda a: node(a, outside)["properties"]["Source"].__setitem__(1, changed_expected[outside]), sources=changed_expected)
# The resumed baseline already contains the accepted48/96 Balance and arrival
# callback in SoloRound. Neither may be silently reverted by archived WIP.
for protected in ("ReplicatedStorage/GameShared/Game/Balance", "ServerScriptService/GameServer/Game/SoloRound"):
    assert protected not in f.DECLARED_SOURCES
    changed_protected = EXPECTED | {protected: EXPECTED[protected] + "\n-- unapproved accepted-solo change\n"}
    rejects("accepted solo Source preserved: " + protected,
        lambda a, protected=protected, changed_protected=changed_protected: node(a, protected)["properties"]["Source"].__setitem__(1, changed_protected[protected]),
        sources=changed_protected)
fog_path = next(iter(ASSETS))
changed_assets = ASSETS | {fog_path: ASSETS[fog_path] + "\n-- unapproved fog change\n"}
rejects("Fog Source even when equal to assets", lambda a: node(a, fog_path)["properties"]["Source"].__setitem__(1, changed_assets[fog_path]), assets=changed_assets)
for path in ("Workspace/CornMap/Ground", "Workspace/CornMap/Props/HouseWest", "Lighting/Bloom"):
    rejects(path + " class", lambda a, path=path: node(a, path).__setitem__("class", "Folder"))
    rejects(path + " Name", lambda a, path=path: node(a, path)["properties"]["Name"].__setitem__(1, "Changed"))
    rejects(path + " identity", lambda a, path=path: node(a, path)["properties"]["UniqueId"].__setitem__(1, "e" * 32))
    rejects(path + " extra property", lambda a, path=path: node(a, path)["properties"].__setitem__("Unreviewed", ["int", "0", []]))
rejects("field resized again", lambda a: component(a, "Workspace/CornMap/FieldZone", "size", "X", 629))
rejects("ground moved", lambda a: component(a, "Workspace/CornMap/Ground", "CFrame", "X", 1))
rejects("barn pivot moved", lambda a: node(a, "Workspace/CornMap/Props/HouseWest")["properties"].__setitem__("WorldPivotData", ["OptionalCoordinateFrame", "", []]))
rejects("Lighting fog changed", lambda a: node(a, "Lighting")["properties"]["FogEnd"].__setitem__(1, "60"))
rejects("Bloom author setting changed", lambda a: node(a, "Lighting/Bloom")["properties"]["Intensity"].__setitem__(1, "1"))
rejects("Baseplate hidden", lambda a: node(a, "Workspace/Baseplate")["properties"]["Transparency"].__setitem__(1, "1"))
rejects("map tags changed", lambda a: node(a, "Workspace/CornMap")["properties"]["Tags"].__setitem__(1, "manual"))
rejects("map attributes changed", lambda a: node(a, "Workspace/CornMap")["properties"]["AttributesSerialize"].__setitem__(1, "manual"))
rejects("new service metadata", lambda a: node(a, "StarterPlayer")["properties"].__setitem__("Unreviewed", ["bool", "false", []]))
rejects("camera type changed", lambda a: node(a, "Workspace/Camera")["properties"]["CameraType"].__setitem__(1, "6"))
rejects("camera FOV changed", lambda a: node(a, "Workspace/Camera")["properties"]["FieldOfView"].__setitem__(1, "60"))
rejects("camera NaN", lambda a: component(a, "Workspace/Camera", "CFrame", "X", "nan"))
rejects("camera frame wrong type", lambda a: node(a, "Workspace/Camera")["properties"]["CFrame"].__setitem__(0, "Vector3"))
rejects("camera frame component removed", lambda a: node(a, "Workspace/Camera")["properties"]["Focus"][2].pop())
source_art = next(path for path, item in BEFORE.items() if path.startswith("ServerStorage/") and item["class"] == "MeshPart" and "137803536172445" in str(item["properties"].get("TextureContent")))
rejects("source art altered", lambda a: node(a, source_art)["properties"]["TextureContent"].__setitem__(1, "manual"))
rejects("source art texture URI replaced", lambda a: node(a, source_art)["properties"]["TextureContent"][2][0][1].__setitem__(1, "rbxassetid://0"))
plant = next(path for path, item in BEFORE.items() if path.startswith("Workspace/CornMap/EditorFieldOverview/") and item["class"] == "MeshPart")
rejects("yellow editor corn altered", lambda a: node(a, plant)["properties"]["TextureContent"].__setitem__(1, "manual"))
rejects("yellow editor texture URI replaced", lambda a: node(a, plant)["properties"]["TextureContent"][2][0][1].__setitem__(1, "rbxassetid://137803536172445"))
rejects("world instance removed", lambda a: a.pop(plant))
rejects("new instance", lambda a: a.__setitem__("Workspace/Unexpected", copy.deepcopy(BEFORE[plant])))
def reparent(a):
    a["Workspace/CornMap/Props/IllegallyMovedCorn"] = a.pop(plant)
rejects("original parent changed", reparent)
def duplicate_id(a):
    node(a, plant)["properties"]["UniqueId"] = copy.deepcopy(a["Workspace/CornMap/Ground"]["properties"]["UniqueId"])
rejects("duplicate identity", duplicate_id)
rejects("fog disabled", lambda a: node(a, "Workspace/CornfieldFog/RuntimeServer")["properties"]["Disabled"].__setitem__(1, "true"))
rejects("fog READ_ME edited", lambda a: node(a, "Workspace/CornfieldFog/READ_ME")["properties"]["Value"].__setitem__(1, "Changed"))

for path in sorted(f.ADDITIONS):
    rejects(path + " missing", lambda a, path=path: a.pop(path))
    rejects(path + " external LinkedSource", lambda a, path=path: node(a, path)["properties"]["LinkedSource"].__setitem__(2, [["url", ["url", "rbxassetid://1", []]]]))
    rejects(path + " nondefault SourceAssetId", lambda a, path=path: node(a, path)["properties"]["SourceAssetId"].__setitem__(1, "1"))
    rejects(path + " nondefault Attributes", lambda a, path=path: node(a, path)["properties"]["AttributesSerialize"].__setitem__(1, "00"))
    rejects(path + " nondefault Tags", lambda a, path=path: node(a, path)["properties"]["Tags"].__setitem__(1, "00"))
    rejects(path + " malformed ScriptGuid", lambda a, path=path: node(a, path)["properties"]["ScriptGuid"].__setitem__(1, "garbage"))
    rejects(path + " duplicate original ScriptGuid", lambda a, path=path: node(a, path)["properties"].__setitem__("ScriptGuid", copy.deepcopy(BEFORE["ServerScriptService/GameServer/Game/RoundAudio"]["properties"]["ScriptGuid"])))
    def move_added(a, path=path):
        a["ServerScriptService/GameServer/Services/" + path.rsplit("/", 1)[1]] = a.pop(path)
    rejects(path + " reparented", move_added)
    rejects(path + " new child", lambda a, path=path: a.__setitem__(path + "/Unexpected", copy.deepcopy(BEFORE[plant])))
camera_rejected_before = len(rejected)
for prop in ("CFrame", "Focus"):
    def frame(a, prop=prop):
        return node(a, "Workspace/Camera")["properties"][prop]
    def duplicate_component(a, frame=frame):
        value = frame(a)
        value[2][-1] = copy.deepcopy(value[2][0])
    rejects("Camera " + prop + " empty frame", lambda a, frame=frame: frame(a).__setitem__(2, []))
    rejects("Camera " + prop + " missing component", lambda a, frame=frame: frame(a)[2].pop())
    rejects("Camera " + prop + " wrong frame type", lambda a, frame=frame: frame(a).__setitem__(0, "Vector3"))
    rejects("Camera " + prop + " duplicate component", duplicate_component)
    rejects("Camera " + prop + " wrong child tag", lambda a, frame=frame: frame(a)[2][0][1].__setitem__(0, "float"))
    rejects("Camera " + prop + " nested component", lambda a, frame=frame: frame(a)[2][0][1].__setitem__(2, [["X", ["X", "0", []]]]))
    for invalid in ("nan", "inf", "-inf", "3.4028236e38"):
        rejects("Camera " + prop + " nonfinite/overflow " + invalid, lambda a, frame=frame, invalid=invalid: frame(a)[2][-1][1].__setitem__(1, invalid))
camera_dom_cases_rejected = len(rejected) - camera_rejected_before

positive = AFTER.copy()
for path in EXPECTED | ASSETS:
    node(positive, path)["properties"]["Source"][1] = (EXPECTED | ASSETS)[path].replace("\n", "\r\n")
for index, path in enumerate(sorted(f.r.SELECTION_PATHS), 1):
    node(positive, path)["properties"]["UniqueId"][1] = f"{(1 << 124) + index:032x}"
component(positive, "Workspace/Camera", "CFrame", "X", 10)
component(positive, "Workspace/Camera", "Focus", "Y", 20)
validate(positive)
# Exporter suffix order may change for two same-name leaf siblings. Their
# immutable identities and all Ref targets must still resolve to the same art.
siblings = {}
pair = None
for path, item in BEFORE.items():
    if path.startswith("Workspace/CornMap/EditorFieldOverview/") and item["class"] == "MeshPart":
        key = (path.rpartition("/")[0], item["class"], item["properties"]["Name"][1])
        if key in siblings:
            pair = (siblings[key], path)
            break
        siblings[key] = path
assert pair, "Expected same-name editor plant siblings"
left, right = pair
swapped = AFTER.copy()
swapped[left], swapped[right] = swapped[right], swapped[left]
ref_paths = {left: right, right: left}
for path, item in list(swapped.items()):
    swapped[path] = item | {"properties": {prop: f.helpers.helpers.remap_refs(value, ref_paths) for prop, value in item["properties"].items()}}
suffix_report = validate(swapped)
assert suffix_report["reindexed_exporter_paths"] == 2
unknown = f.r.p.unknown_properties(f.BASELINE)
f.r.validate_unknown(unknown, copy.deepcopy(unknown))
terrain = next(key for key in unknown["properties"] if "Terrain" in key)
binary_rejected = 0
for field in ("payload_sha256", "instance_count", "payload_bytes"):
    changed = copy.deepcopy(unknown)
    changed["properties"][terrain][field] = "changed"
    try:
        f.r.validate_unknown(unknown, changed)
    except ValueError:
        binary_rejected += 1
    else:
        raise AssertionError("Raw Terrain mutation accepted")
assert f.sha256(f.BASELINE) == f.BASELINE_HASH
print(json.dumps({"passed": True, "original_instances": 4160, "candidate_instances": 4162, "sources": 80, "declared_source_paths": sorted(f.DECLARED_SOURCES),
    "current_source_changes": current_report["source_change_count"], "all_sixteen_controlled_versions_accepted": True, "new_modules_accepted": 2,
    "world_lighting_art_exact": True, "unsafe_dom_cases_rejected": len(rejected), "camera_dom_cases_rejected": camera_dom_cases_rejected, "raw_terrain_cases_rejected": binary_rejected, "identity_preserving_suffix_reindexes_accepted": 2,
    "scope": "Actual checker/current Source snapshot and sixteen controlled Source versions, in-memory fixtures; immutable baseline unchanged, no engine audio/final-save claim"}))
