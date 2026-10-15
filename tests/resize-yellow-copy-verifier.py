"""In-memory fixtures of the real read-only checker; never serialize a scene."""
import collections
import copy
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("resize_audit", ROOT / "scripts/verify-resize-yellow-copy.py")
f = importlib.util.module_from_spec(spec)
spec.loader.exec_module(f)
assert f.sha256(f.BASELINE) == f.BASELINE_HASH and f.BASELINE.stat().st_size == f.BASELINE_BYTES
BEFORE, _ = f.r.p.known_dom(f.BASELINE)
SOURCES, CLASSES = f.r.mapping_from_sourcemap(ROOT / "build/sourcemap.json")
ASSETS = f.fog.current_sources()
FIXED = f.layout()
AFTER = copy.deepcopy(BEFORE)
for path, source in (SOURCES | ASSETS).items():
    AFTER[path]["properties"]["Source"][1] = source
for entry in FIXED["property_changes"]:
    AFTER[entry["path"]]["properties"][entry["property"]] = copy.deepcopy(entry["after"])
for entry in FIXED["removed_plants"]:
    AFTER.pop(entry["path"])


def reindex(nodes):
    """Reproduce known_dom suffix reassignment when same-name plants disappear."""
    paths, occurrences = {}, collections.Counter()
    for path, node in nodes.items():
        parent = path.rpartition("/")[0]
        actual_parent = paths[parent] if parent else ""
        name = node["properties"]["Name"][1]
        key = actual_parent, node["class"], name
        occurrences[key] += 1
        leaf = name if occurrences[key] == 1 else name + "#" + str(occurrences[key])
        paths[path] = (actual_parent + "/" if actual_parent else "") + leaf
    return {paths[path]: node | {"properties": {prop: f.remap_refs(value, paths) for prop, value in node["properties"].items()}} for path, node in nodes.items()}, paths


AFTER, PATHS = reindex(AFTER)
def current(path):
    return PATHS[path]


def node(after, path):
    after[path] = copy.deepcopy(after[path])
    return after[path]


def original_node(after, path):
    return node(after, current(path))


def leaf(value):
    if value[0] in f.FLOAT32_TYPES and not value[2]:
        return value
    for _, child in value[2]:
        result = leaf(child)
        if result is not None:
            return result
    return None


def validate(after):
    return f.validate_dom(BEFORE, after, SOURCES, CLASSES, ASSETS)


rejected = []
def rejects(name, mutate):
    after = AFTER.copy()
    mutate(after)
    try:
        validate(after)
    except (ValueError, KeyError, IndexError):
        rejected.append(name)
        return
    raise AssertionError("Unsafe resize save accepted: " + name)


report = validate(AFTER)
assert report["matching_sources"] == 75 and report["matching_asset_sources"] == 3 and report["total_sources"] == 78
assert report["new_instances"] == 0 and report["deleted_owned_plants"] == len(FIXED["removed_plants"])
assert len(AFTER) == 6844 - len(FIXED["removed_plants"])
assert report["fixed_property_changes"] == len(FIXED["property_changes"]) and report["reindexed_exporter_paths"] > 0
assert report["unapproved_world_lighting_art_identities_exact"] and report["original_source_art_preserved"]

for prop in sorted({entry["property"] for entry in FIXED["property_changes"]}):
    entry = next(row for row in FIXED["property_changes"] if row["property"] == prop)
    path = entry["path"]
    rejects(prop + " unapplied", lambda a, path=path, prop=prop, entry=entry: original_node(a, path)["properties"].__setitem__(prop, copy.deepcopy(entry["before"])))
    rejects(prop + " missing", lambda a, path=path, prop=prop: original_node(a, path)["properties"].pop(prop))
    rejects(prop + " wrong type", lambda a, path=path, prop=prop: original_node(a, path)["properties"][prop].__setitem__(0, "UnreviewedType"))
    target = leaf(entry["after"])
    if target is not None:
        def change_number(a, path=path, prop=prop, delta=None):
            value = leaf(original_node(a, path)["properties"][prop])
            if delta is None:
                bits = struct.unpack("<I", struct.pack("<f", float(value[1])))[0]
                value[1] = str(struct.unpack("<f", struct.pack("<I", bits + 1))[0])
            else:
                value[1] = delta
        rejects(prop + " next f32", change_number)
        rejects(prop + " nonfinite", lambda a, change=change_number: change(a, delta="nan"))

retained = FIXED["retained_plants"][0]
plant = retained["path"]
for folder in ("EditorPreview", "EditorFieldOverview"):
    entry = next(row for row in FIXED["removed_plants"] if "/" + folder + "/" in row["path"])
    def resurrect(a, entry=entry):
        a[entry["path"] + "#99999"] = copy.deepcopy(BEFORE[entry["path"]])
    rejects(folder + " deleted plant resurrected", resurrect)
    kept = next(row for row in FIXED["retained_plants"] if "/" + folder + "/" in row["path"])
    rejects(folder + " extra retained deletion", lambda a, kept=kept: a.pop(current(kept["path"])))

for path in (plant, "Workspace/CornMap/Props/HouseWest", "Workspace/CornMap/Ground", "Lighting/Bloom", "Workspace/CornfieldFog/RuntimeServer"):
    rejects(path + " identity replaced", lambda a, path=path: original_node(a, path)["properties"]["UniqueId"].__setitem__(1, "f" * 32))
    rejects(path + " real name changed", lambda a, path=path: original_node(a, path)["properties"]["Name"].__setitem__(1, "Changed"))
    rejects(path + " class changed", lambda a, path=path: original_node(a, path).__setitem__("class", "Folder"))
    rejects(path + " new property", lambda a, path=path: original_node(a, path)["properties"].__setitem__("Unreviewed", ["bool", "false", []]))

def reparent(a):
    a["Workspace/CornMap/Props/IllegallyMovedCorn"] = a.pop(current(plant))
rejects("plant parent identity changed", reparent)
def duplicate(a):
    other = next(row["path"] for row in FIXED["retained_plants"] if row["path"] != plant)
    original_node(a, other)["properties"]["UniqueId"] = copy.deepcopy(a[current(plant)]["properties"]["UniqueId"])
rejects("duplicate original identity", duplicate)
rejects("foreign added instance", lambda a: a.__setitem__("Workspace/Unexpected", copy.deepcopy(BEFORE["Workspace/CornMap/Ground"])))
rejects("Lighting modified", lambda a: original_node(a, "Lighting")["properties"]["FogEnd"].__setitem__(1, "60"))
rejects("Bloom author choice overwritten", lambda a: original_node(a, "Lighting/Bloom")["properties"]["Intensity"].__setitem__(1, "1"))
rejects("Baseplate modified", lambda a: original_node(a, "Workspace/Baseplate")["properties"]["Transparency"].__setitem__(1, "1"))
rejects("new service metadata", lambda a: original_node(a, "StarterPlayer")["properties"].__setitem__("Unreviewed", ["int", "0", []]))
rejects("CameraType changed", lambda a: original_node(a, "Workspace/Camera")["properties"]["CameraType"].__setitem__(1, "5"))
for path in (next(iter(SOURCES)), next(iter(ASSETS))):
    rejects(path + " Source mismatch", lambda a, path=path: original_node(a, path)["properties"]["Source"].__setitem__(1, "return 'wrong'"))
    rejects(path + " Source wrong type", lambda a, path=path: original_node(a, path)["properties"]["Source"].__setitem__(0, "ProtectedString"))
    rejects(path + " ScriptGuid changed", lambda a, path=path: original_node(a, path)["properties"]["ScriptGuid"].__setitem__(1, "{F0000000-0000-0000-0000-000000000000}"))
rejects("fog server disabled", lambda a: original_node(a, "Workspace/CornfieldFog/RuntimeServer")["properties"]["Disabled"].__setitem__(1, "true"))
rejects("fog READ_ME edited", lambda a: original_node(a, "Workspace/CornfieldFog/READ_ME")["properties"]["Value"].__setitem__(1, "Changed"))
source_art = next(path for path, item in BEFORE.items() if path.startswith("ServerStorage/") and item["class"] == "MeshPart" and "137803536172445" in str(item["properties"].get("TextureContent")))
rejects("original green source texture replaced", lambda a: original_node(a, source_art)["properties"].__setitem__("TextureContent", ["Content", "", [["uri", ["uri", "rbxassetid://103653296385119", []]]]]))
for path in ("Workspace/CornMap", "Workspace/CornfieldFog"):
    rejects(path + " undeclared tags", lambda a, path=path: original_node(a, path)["properties"]["Tags"].__setitem__(1, "manual"))

camera_rejected_before = len(rejected)
for prop in ("CFrame", "Focus"):
    def frame(a, prop=prop):
        return original_node(a, "Workspace/Camera")["properties"][prop]
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
for index, path in enumerate(sorted(f.r.SELECTION_PATHS), 1):
    original_node(positive, path)["properties"]["UniqueId"][1] = "f000000000000000000000000000" + f"{index:04x}"
for path in SOURCES | ASSETS:
    original_node(positive, path)["properties"]["Source"][1] = (SOURCES | ASSETS)[path].replace("\n", "\r\n")
# Both allowed editor properties accept a complete finite twelve-component frame.
for prop, coordinate, number in (("CFrame", "X", "10"), ("Focus", "Y", "20")):
    value = original_node(positive, "Workspace/Camera")["properties"][prop]
    assert value[0] == "CoordinateFrame" and {key for key, _ in value[2]} == set(f.FRAME_KEYS)
    next(child for key, child in value[2] if key == coordinate)[1] = number
validate(positive)

with tempfile.TemporaryDirectory(prefix="corn-resize-fixed-manifest-") as temporary:
    wrong = Path(temporary) / "manifest.json"
    modified = copy.deepcopy(FIXED)
    modified["property_changes"][0]["after"][2][0][1][1] = "631"
    wrong.write_text(json.dumps(modified), encoding="utf-8")
    with patch.object(f, "MANIFEST", wrong):
        try:
            validate(AFTER)
        except ValueError:
            rejected.append("modified fixed manifest")
        else:
            raise AssertionError("Modified fixed manifest accepted")

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
assert f.sha256(f.BASELINE) == f.BASELINE_HASH and f.sha256(f.MANIFEST) == f.MANIFEST_HASH
print(json.dumps({"passed": True, "original_instances": 6844, "candidate_instances": len(AFTER),
    "sources": 78, "fixed_property_changes": len(FIXED["property_changes"]), "deleted_owned_plants": len(FIXED["removed_plants"]),
    "reindexed_exporter_paths": report["reindexed_exporter_paths"], "unsafe_dom_cases_rejected": len(rejected), "raw_terrain_cases_rejected": binary_rejected,
    "camera_dom_cases_rejected": camera_dom_cases_rejected, "valid_camera_frames_accepted": 2,
    "scope": "Actual checker/current Sources/fixed world manifest, in-memory fixtures; immutable scene inputs unchanged, no engine-save claim"}))
