"""Actual finale verifier, fixed-baseline in-memory negatives; no RBXL writes."""
import copy
import importlib.util
import json
import tempfile
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("finale_audit", ROOT / "scripts/verify-finale-copy.py")
f = importlib.util.module_from_spec(spec)
spec.loader.exec_module(f)
assert f.r.sha256(f.BASELINE) == f.BASELINE_HASH and f.BASELINE.stat().st_size == f.BASELINE_BYTES
BEFORE, _ = f.r.p.known_dom(f.BASELINE)
SOURCES, CLASSES = f.r.mapping_from_sourcemap(ROOT / "build/sourcemap.json")
FIXED = f.layout()
assert FIXED["version"] == 2 and len(FIXED["barn_bindings"]) == 3
AFTER = copy.deepcopy(BEFORE)
for path, source in SOURCES.items():
    AFTER[path]["properties"]["Source"][1] = source
for path, cls, prop, literal in f.SERVICE_METADATA:
    assert BEFORE[path]["class"] == cls and prop not in BEFORE[path]["properties"]
    AFTER[path]["properties"][prop] = copy.deepcopy(literal)


def node(after, path):
    after[path] = copy.deepcopy(after[path])
    return after[path]


def component(after, path, prop, key, value):
    for name, item in node(after, path)["properties"][prop][2]:
        if name == key:
            item[1] = str(value)
            return
    raise AssertionError("Missing component " + path + "/" + prop + "/" + key)


for entry in FIXED["parts"]:
    for key, value in zip(f.FRAME_KEYS, entry["after"]):
        component(AFTER, entry["path"], "CFrame", key, value)
    if entry["torch_id"].startswith("torch_House"):
        house = entry["torch_id"].removeprefix("torch_").removesuffix("1").removesuffix("-")
        barn = next(binding for binding in FIXED["barn_bindings"] if binding["path"].endswith("/" + house))
        assert abs(abs(entry["after"][0] - barn["pivot"][0]) - 6) < 0.00001
        assert abs(entry["after"][2] - barn["pivot"][2] + 11.75) < 0.00001


def validate(after):
    return f.validate_dom(BEFORE, after, SOURCES, CLASSES)


rejected = []


def rejects(name, mutate):
    after = AFTER.copy()
    mutate(after)
    try:
        validate(after)
    except (ValueError, KeyError):
        rejected.append(name)
        return
    raise AssertionError("Unsafe finale-save fixture accepted: " + name)


report = validate(AFTER)
assert report["matching_sources"] == 75 and report["new_instances"] == 0
assert report["world_exact_except_54_torch_cframes"] and report["original_art_preserved"]
assert report["service_metadata_default_unverified"] is True
assert len(report["audited_service_metadata"]) == 3
assert all(change["reason"] == "audited_engine_save_service_metadata" and change["default_unverified"] is True for change in report["audited_service_metadata"])
assert len(BEFORE) == len(AFTER) == 6839
changes = [change for change in report["allowed_changes"] if change["reason"] == "fixed_author_approved_torch_translation"]
assert len(changes) == 54 and {change["path"] for change in changes} == {entry["path"] for entry in FIXED["parts"]}
PART = FIXED["parts"][0]["path"]
FLAME = PART.rsplit("/", 1)[0] + "/Flame"
MODEL = PART.rsplit("/", 1)[0]
SOURCE = "ServerScriptService/GameServer/Game/SoloRound"
SIGN = "Workspace/CornMap/Props/VillageRoad/ExitSign"

rejects("unapplied single Part", lambda a: node(a, PART)["properties"].__setitem__("CFrame", copy.deepcopy(BEFORE[PART]["properties"]["CFrame"])))
rejects("all torches unapplied", lambda a: [node(a, entry["path"])["properties"].__setitem__("CFrame", copy.deepcopy(BEFORE[entry["path"]]["properties"]["CFrame"])) for entry in FIXED["parts"]])
rejects("unapproved X placement", lambda a: component(a, PART, "CFrame", "X", 100))
rejects("unapproved Y lift", lambda a: component(a, PART, "CFrame", "Y", 20))
rejects("changed rotation", lambda a: component(a, PART, "CFrame", "R00", 0.5))
rejects("flame offset changed", lambda a: component(a, FLAME, "CFrame", "Y", 25))
rejects("nonfinite frame", lambda a: component(a, PART, "CFrame", "X", "nan"))
rejects("wrong CFrame type", lambda a: node(a, PART)["properties"]["CFrame"].__setitem__(0, "Vector3"))
rejects("missing frame component", lambda a: node(a, PART)["properties"]["CFrame"][2].pop())
rejects("duplicate frame component", lambda a: node(a, PART)["properties"]["CFrame"][2].__setitem__(1, copy.deepcopy(a[PART]["properties"]["CFrame"][2][0])))
rejects("Part size changed", lambda a: component(a, PART, "size", "X", 2))
rejects("torch material changed", lambda a: node(a, PART)["properties"]["Material"].__setitem__(1, "0"))
rejects("torch color changed", lambda a: node(a, PART)["properties"]["Color3uint8"].__setitem__(1, "0"))
rejects("torch light changed", lambda a: node(a, FLAME + "/TorchLight")["properties"]["Brightness"].__setitem__(1, "2"))
rejects("torch fire changed", lambda a: node(a, FLAME + "/TorchFire")["properties"]["heat_xml"].__setitem__(1, "10"))
rejects("model pivot edited", lambda a: node(a, MODEL)["properties"].__setitem__("WorldPivotData", ["OptionalCoordinateFrame", "modified", []]))
rejects("torch ownership edited", lambda a: node(a, MODEL)["properties"]["AttributesSerialize"].__setitem__(1, ""))
rejects("torch identity edited", lambda a: node(a, PART)["properties"]["UniqueId"].__setitem__(1, "different-id"))
rejects("torch reclassified", lambda a: node(a, PART).__setitem__("class", "MeshPart"))
rejects("missing torch", lambda a: a.pop(PART))
rejects("extra persistent instance", lambda a: a.__setitem__(MODEL + "/Extra", {"class": "Part", "properties": {"Name": ["string", "Extra", []]}}))
rejects("sign changed again", lambda a: component(a, SIGN, "size", "X", 37))
rejects("sign overlay changed", lambda a: node(a, SIGN + "/ExitTextSurface")["properties"]["AlwaysOnTop"].__setitem__(1, "true"))
rejects("other map geometry changed", lambda a: component(a, "Workspace/CornMap/Ground", "size", "X", 900))
rejects("Lighting changed", lambda a: node(a, "Lighting")["properties"]["Brightness"].__setitem__(1, "999"))
rejects("imported art identity changed", lambda a: node(a, "ServerStorage/SM_Prop_Plant_Corn_01_L")["properties"]["UniqueId"].__setitem__(1, "new-id"))
rejects("Source mismatch", lambda a: node(a, SOURCE)["properties"]["Source"].__setitem__(1, "return 'wrong'"))
rejects("Source class changed", lambda a: node(a, SOURCE).__setitem__("class", "Script"))
rejects("Source identity changed", lambda a: node(a, SOURCE)["properties"]["UniqueId"].__setitem__(1, "new-id"))
rejects("Barn body moved", lambda a: component(a, FIXED["barn_bindings"][0]["body_path"], "CFrame", "X", -127))
rejects("Barn pivot changed", lambda a: node(a, FIXED["barn_bindings"][0]["path"])["properties"].__setitem__("WorldPivotData", ["OptionalCoordinateFrame", "changed", []]))


def superseded_scatter(after):
    old = {"torch_HouseWest-1": (-10, -6), "torch_HouseWest1": (6, -10),
           "torch_HouseEast-1": (-11, -6), "torch_HouseEast1": (9, -10),
           "torch_HouseNorthWest-1": (-12, -5), "torch_HouseNorthWest1": (8, -11)}
    for entry in FIXED["parts"]:
        if entry["torch_id"] in old:
            dx, dz = old[entry["torch_id"]]
            component(after, entry["path"], "CFrame", "X", entry["before"][0] + dx)
            component(after, entry["path"], "CFrame", "Z", entry["before"][2] + dz)


rejects("superseded house scatter", superseded_scatter)

for path, cls, prop, literal in f.SERVICE_METADATA:
    label = path + "/" + prop
    rejects(label + " missing exact audited property", lambda a, path=path, prop=prop: node(a, path)["properties"].pop(prop))
    rejects(label + " wrong type", lambda a, path=path, prop=prop: node(a, path)["properties"][prop].__setitem__(0, "string"))
    rejects(label + " nonzero/nonfalse", lambda a, path=path, prop=prop, literal=literal: node(a, path)["properties"][prop].__setitem__(1, "true" if literal[0] == "bool" else "1"))
    rejects(label + " unexpected nested payload", lambda a, path=path, prop=prop: node(a, path)["properties"][prop][2].append(["extra", ["string", "x", []]]))
    rejects(label + " unexpected class", lambda a, path=path: node(a, path).__setitem__("class", "Folder"))
    rejects(label + " unexpected path", lambda a, prop=prop, literal=literal: node(a, "Lighting")["properties"].__setitem__(prop, copy.deepcopy(literal)))
    rejects(label + " extra metadata addition", lambda a, path=path: node(a, path)["properties"].__setitem__("UnreviewedEngineProperty", ["bool", "false", []]))
    rejects(label + " original property removed", lambda a, path=path: node(a, path)["properties"].pop("UniqueId"))
    altered_before = BEFORE.copy()
    node(altered_before, path)["properties"][prop] = copy.deepcopy(literal)
    try:
        f.validate_dom(altered_before, AFTER, SOURCES, CLASSES)
    except ValueError:
        rejected.append(label + " unexpected baseline property")
    else:
        raise AssertionError("Audited absent-to-literal rule accepted a changed baseline: " + label)

# The only numeric allowance is the explicit fixed target CFrame tolerance.
rounded = AFTER.copy()
component(rounded, PART, "CFrame", "X", FIXED["parts"][0]["after"][0] + 0.000005)
validate(rounded)
rejects("placement outside 1e-5 tolerance", lambda a: component(a, PART, "CFrame", "X", FIXED["parts"][0]["after"][0] + 0.00002))

with tempfile.TemporaryDirectory(prefix="corn-finale-manifest-") as temporary:
    counterfeit = Path(temporary) / "layout.json"
    changed = copy.deepcopy(FIXED)
    changed["parts"][0]["after"][0] += 1
    counterfeit.write_text(json.dumps(changed), encoding="utf-8")
    with patch.object(f, "MANIFEST", counterfeit):
        try:
            validate(AFTER)
        except ValueError:
            rejected.append("modified fixed manifest")
        else:
            raise AssertionError("Candidate-derived/modified torch manifest accepted")

unknown = f.r.p.unknown_properties(f.BASELINE)
f.r.validate_unknown(unknown, copy.deepcopy(unknown))
terrain_key = next(key for key in unknown["properties"] if "Terrain" in key)
binary_rejected = 0
for mutation in ("payload_sha256", "instance_count", "payload_bytes"):
    altered = copy.deepcopy(unknown)
    altered["properties"][terrain_key][mutation] = "changed"
    try:
        f.r.validate_unknown(unknown, altered)
    except ValueError:
        binary_rejected += 1
    else:
        raise AssertionError("Raw Terrain mutation accepted: " + mutation)
assert f.r.sha256(f.BASELINE) == f.BASELINE_HASH and f.r.sha256(f.MANIFEST) == f.MANIFEST_HASH
print(json.dumps({"passed": True, "baseline_instances": len(BEFORE), "matching_sources": 75,
    "new_instances": 0, "approved_part_cframes": 54, "unsafe_dom_cases_rejected": len(rejected),
    "audited_service_metadata_additions": 3, "service_metadata_default_unverified": True,
    "raw_terrain_cases_rejected": binary_rejected,
    "scope": "Actual verifier/current Sources/classes, in-memory cases; immutable baseline and fixed manifest unchanged"}))
