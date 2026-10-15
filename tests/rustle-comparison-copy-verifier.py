"""Real source-only checker with current Sources and five controlled Source versions.
No scene is written; engine rendering/audio and final save remain separate.
"""
import copy
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("rustle_audit", ROOT / "scripts/verify-rustle-comparison-copy.py")
f = importlib.util.module_from_spec(spec)
spec.loader.exec_module(f)
assert f.sha256(f.BASELINE) == f.BASELINE_HASH and f.BASELINE.stat().st_size == f.BASELINE_BYTES
BEFORE, _ = f.r.p.known_dom(f.BASELINE)
SOURCES, CLASSES = f.r.mapping_from_sourcemap(ROOT / "build/sourcemap.json")
ASSETS = f.fog.current_sources()
CURRENT = copy.deepcopy(BEFORE)
for path, source in (SOURCES | ASSETS).items():
    CURRENT[path]["properties"]["Source"][1] = source
current_report = f.validate_dom(BEFORE, CURRENT, SOURCES, CLASSES, ASSETS)
EXPECTED = SOURCES.copy()
AFTER = copy.deepcopy(CURRENT)
for path in f.DECLARED_SOURCES:
    EXPECTED[path] += "\n-- controlled five-source checker fixture\n"
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
    raise AssertionError("Unsafe audio-only save accepted: " + name)


report = validate(AFTER)
assert report["total_sources"] == 78 and report["matching_sources"] == 75 and report["matching_asset_sources"] == 3
assert report["new_instances"] == report["removed_instances"] == 0 and report["source_change_count"] == 5
assert set(report["source_changes"]) == f.DECLARED_SOURCES and report["world_and_lighting_exact"]
for path in sorted(f.DECLARED_SOURCES):
    rejects(path + " mismatch", lambda a, path=path: node(a, path)["properties"]["Source"].__setitem__(1, "return 'wrong'"))
    rejects(path + " Source type", lambda a, path=path: node(a, path)["properties"]["Source"].__setitem__(0, "ProtectedString"))
    rejects(path + " identity", lambda a, path=path: node(a, path)["properties"]["UniqueId"].__setitem__(1, "f" * 32))
    rejects(path + " ScriptGuid", lambda a, path=path: node(a, path)["properties"]["ScriptGuid"].__setitem__(1, "{F0000000-0000-0000-0000-000000000000}"))
    rejects(path + " extra property", lambda a, path=path: node(a, path)["properties"].__setitem__("Unreviewed", ["bool", "false", []]))
    rejects(path + " capabilities", lambda a, path=path: node(a, path)["properties"]["Capabilities"].__setitem__(1, "1"))

outside = next(path for path in SOURCES if path not in f.DECLARED_SOURCES)
changed_expected = EXPECTED | {outside: EXPECTED[outside] + "\n-- outside the approved five\n"}
rejects("sixth Source even when equal to src", lambda a: node(a, outside)["properties"]["Source"].__setitem__(1, changed_expected[outside]), sources=changed_expected)
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

positive = AFTER.copy()
for path in EXPECTED | ASSETS:
    node(positive, path)["properties"]["Source"][1] = (EXPECTED | ASSETS)[path].replace("\n", "\r\n")
for index, path in enumerate(sorted(f.r.SELECTION_PATHS), 1):
    node(positive, path)["properties"]["UniqueId"][1] = f"{(1 << 124) + index:032x}"
component(positive, "Workspace/Camera", "CFrame", "X", 10)
component(positive, "Workspace/Camera", "Focus", "Y", 20)
validate(positive)
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
print(json.dumps({"passed": True, "instances": 4160, "sources": 78, "declared_source_paths": sorted(f.DECLARED_SOURCES),
    "current_source_changes": current_report["source_change_count"], "all_five_controlled_versions_accepted": True,
    "world_lighting_art_exact": True, "unsafe_dom_cases_rejected": len(rejected), "raw_terrain_cases_rejected": binary_rejected,
    "scope": "Actual checker/current Source snapshot and five controlled Source versions, in-memory fixtures; immutable baseline unchanged, no engine audio/final-save claim"}))
