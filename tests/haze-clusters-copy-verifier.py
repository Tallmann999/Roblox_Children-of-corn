"""Actual saved-copy verifier in memory; no RBXL writes or serialization."""
import copy
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("haze_audit", ROOT / "scripts/verify-haze-clusters-copy.py")
f = importlib.util.module_from_spec(spec)
spec.loader.exec_module(f)
assert f.r.sha256(f.BASELINE) == f.BASELINE_HASH and f.BASELINE.stat().st_size == f.BASELINE_BYTES
BEFORE, _ = f.r.p.known_dom(f.BASELINE)
SOURCES, CLASSES = f.r.mapping_from_sourcemap(ROOT / "build/sourcemap.json")
ASSETS = f.fog.current_sources()
FIXED = f.layout()
AFTER = copy.deepcopy(BEFORE)
for path, source in SOURCES.items():
    AFTER[path]["properties"]["Source"][1] = source
NEW = f.fog_schema(ASSETS)
for index, (path, node) in enumerate(NEW.items(), 1):
    node["properties"]["UniqueId"] = ["UniqueId", f"f000000000000000000000000000{index:04x}", []]
    if path in ASSETS:
        node["properties"]["ScriptGuid"] = ["string", f"{{B0000000-0000-0000-0000-{index:012x}}}", []]
    AFTER[path] = copy.deepcopy(node)


def node(after, path):
    after[path] = copy.deepcopy(after[path])
    return after[path]


def component(after, path, prop, key, value):
    for name, child in node(after, path)["properties"][prop][2]:
        if name == key:
            child[1] = str(value)
            return
    raise AssertionError("Missing component " + path + "/" + prop + "/" + key)


for entry in FIXED["parts"]:
    for key, value in zip(f.FRAME_KEYS, entry["after"]):
        component(AFTER, entry["path"], "CFrame", key, value)
for prop, (_, target) in f.BLOOM_VALUES.items():
    AFTER[f.BLOOM_PATH]["properties"][prop] = f.scalar("float", target)


def validate(after):
    return f.validate_dom(BEFORE, after, SOURCES, CLASSES, ASSETS)


rejected = []


def rejects(name, mutate):
    after = AFTER.copy()
    mutate(after)
    try:
        validate(after)
    except (ValueError, KeyError):
        rejected.append(name)
        return
    raise AssertionError("Unsafe haze/cluster save accepted: " + name)


report = validate(AFTER)
assert len(BEFORE) == 6839 and len(AFTER) == 6844
assert report["matching_sources"] == 75 and report["matching_asset_sources"] == 3 and report["total_sources"] == 78
assert report["new_instances"] == 5 and report["cluster_cframes"] == 28
assert len([change for change in report["allowed_changes"] if change["reason"] == "fixed_author_approved_cluster_translation"]) == 28
assert report["world_exact_except_28_cluster_cframes_five_fog_nodes_and_two_bloom_values"]
assert report["bloom_property_changes"] == 2
assert len([change for change in report["allowed_changes"] if change["reason"] == "fixed_author_approved_bloom"]) == 2
OLD_ID = next(item["properties"]["UniqueId"][1] for item in BEFORE.values() if "UniqueId" in item["properties"])
OLD_GUID = next(item["properties"]["ScriptGuid"][1] for item in BEFORE.values() if "ScriptGuid" in item["properties"])
FOG = f.fog.FOG
for path in NEW:
    label = path.rsplit("/", 1)[-1]
    rejects(label + " missing", lambda a, path=path: a.pop(path))
    rejects(label + " wrong class", lambda a, path=path: node(a, path).__setitem__("class", "Folder"))
    rejects(label + " unknown property", lambda a, path=path: node(a, path)["properties"].__setitem__("Unreviewed", ["bool", "false", []]))
    rejects(label + " unknown name", lambda a, path=path: node(a, path)["properties"]["Name"].__setitem__(1, "Other"))
    rejects(label + " capabilities", lambda a, path=path: node(a, path)["properties"]["Capabilities"].__setitem__(1, "1"))
    rejects(label + " sandbox", lambda a, path=path: node(a, path)["properties"]["DefinesCapabilities"].__setitem__(1, "true"))
    rejects(label + " attribute", lambda a, path=path: node(a, path)["properties"]["AttributesSerialize"].__setitem__(1, "manual"))
    rejects(label + " tag", lambda a, path=path: node(a, path)["properties"]["Tags"].__setitem__(1, "manual"))
    rejects(label + " malformed identity", lambda a, path=path: node(a, path)["properties"]["UniqueId"].__setitem__(1, "not-an-id"))
    rejects(label + " identity wrong type", lambda a, path=path: node(a, path)["properties"]["UniqueId"].__setitem__(0, "string"))
    rejects(label + " original identity duplicated", lambda a, path=path: node(a, path)["properties"]["UniqueId"].__setitem__(1, OLD_ID.upper()))
    rejects(label + " default wrong type", lambda a, path=path: node(a, path)["properties"]["SourceAssetId"].__setitem__(0, "string"))
    rejects(label + " missing default property", lambda a, path=path: node(a, path)["properties"].pop("SerializedOverrides"))
for path in ASSETS:
    rejects(path + " Source mismatch", lambda a, path=path: node(a, path)["properties"]["Source"].__setitem__(1, "return 'wrong'"))
    rejects(path + " Source type", lambda a, path=path: node(a, path)["properties"]["Source"].__setitem__(0, "ProtectedString"))
    rejects(path + " malformed ScriptGuid", lambda a, path=path: node(a, path)["properties"]["ScriptGuid"].__setitem__(1, "not-a-guid"))
    rejects(path + " duplicate original ScriptGuid", lambda a, path=path: node(a, path)["properties"]["ScriptGuid"].__setitem__(1, OLD_GUID.lower()))
SERVER = FOG + "/RuntimeServer"
CLIENT = SERVER + "/ClientTemplate"
rejects("server Disabled", lambda a: node(a, SERVER)["properties"]["Disabled"].__setitem__(1, "true"))
rejects("client Enabled", lambda a: node(a, CLIENT)["properties"]["Disabled"].__setitem__(1, "false"))
rejects("server RunContext", lambda a: node(a, SERVER)["properties"]["RunContext"].__setitem__(1, "1"))
rejects("READ_ME edited", lambda a: node(a, FOG + "/READ_ME")["properties"]["Value"].__setitem__(1, "Edited"))
rejects("new property on READ_ME", lambda a: node(a, FOG + "/READ_ME")["properties"].__setitem__("Disabled", ["bool", "false", []]))
rejects("new fog child", lambda a: a.__setitem__(FOG + "/Unexpected", {"class": "Folder", "properties": {}}))
rejects("transient Atmosphere persisted", lambda a: a.__setitem__("Lighting/CornfieldFogAtmosphere", {"class": "Atmosphere", "properties": {}}))
rejects("duplicate new identity", lambda a: node(a, CLIENT)["properties"].__setitem__("UniqueId", copy.deepcopy(a[SERVER]["properties"]["UniqueId"])))
rejects("duplicate new ScriptGuid", lambda a: node(a, CLIENT)["properties"].__setitem__("ScriptGuid", copy.deepcopy(a[SERVER]["properties"]["ScriptGuid"])))
rejects("fog model pivot changed", lambda a: node(a, FOG)["properties"].__setitem__("WorldPivotData", ["OptionalCoordinateFrame", "changed", []]))
rejects("fog model empty pivot", lambda a: node(a, FOG)["properties"].__setitem__("WorldPivotData", ["OptionalCoordinateFrame", "", []]))
rejects("fog model translated pivot", lambda a: node(a, FOG)["properties"]["WorldPivotData"][2][0][1][2][0][1].__setitem__(1, "1"))
rejects("fog model rotated pivot", lambda a: node(a, FOG)["properties"]["WorldPivotData"][2][0][1][2][3][1].__setitem__(1, "0"))
for role in ("slot", "torch", "barrel"):
    entry = next(part for part in FIXED["parts"] if part["role"] == role)
    path = entry["path"]
    rejects(role + " unapplied", lambda a, path=path: node(a, path)["properties"].__setitem__("CFrame", copy.deepcopy(BEFORE[path]["properties"]["CFrame"])))
    rejects(role + " target moved", lambda a, path=path, entry=entry: component(a, path, "CFrame", "X", entry["after"][0] + 1))
    rejects(role + " Y changed", lambda a, path=path: component(a, path, "CFrame", "Y", 999))
    rejects(role + " nonfinite", lambda a, path=path: component(a, path, "CFrame", "X", "nan"))
barrel = next(part for part in FIXED["parts"] if part["role"] == "barrel")
assert barrel["after"][0] == 262.79998779296875
shortest = AFTER.copy()
component(shortest, barrel["path"], "CFrame", "X", "262.8")
validate(shortest)
bits = struct.unpack("<I", struct.pack("<f", barrel["after"][0]))[0]
next_f32 = struct.unpack("<f", struct.pack("<I", bits + 1))[0]
assert next_f32 - barrel["after"][0] > 0.00001
rejects("barrel next representable f32", lambda a: component(a, barrel["path"], "CFrame", "X", next_f32))
rejects("Lighting fog changed", lambda a: node(a, "Lighting")["properties"]["FogEnd"].__setitem__(1, "60"))
for prop, (old, target) in f.BLOOM_VALUES.items():
    rejects("Bloom " + prop + " old value", lambda a, prop=prop, old=old: node(a, f.BLOOM_PATH)["properties"][prop].__setitem__(1, str(old)))
    rejects("Bloom " + prop + " wrong type", lambda a, prop=prop: node(a, f.BLOOM_PATH)["properties"][prop].__setitem__(0, "double"))
rejects("Bloom wrong class", lambda a: node(a, f.BLOOM_PATH).__setitem__("class", "BlurEffect"))
rejects("Bloom unapproved property", lambda a: node(a, f.BLOOM_PATH)["properties"]["Threshold"].__setitem__(1, "0.5"))
rejects("Bloom original identity", lambda a: node(a, f.BLOOM_PATH)["properties"]["UniqueId"].__setitem__(1, "f" * 32))
for prop in f.BLOOM_VALUES:
    rejects("Bloom " + prop + " missing", lambda a, prop=prop: node(a, f.BLOOM_PATH)["properties"].pop(prop))
    target = f.BLOOM_VALUES[prop][1]
    bits = struct.unpack("<I", struct.pack("<f", target))[0]
    next_f32 = struct.unpack("<f", struct.pack("<I", bits + 1))[0]
    rejects("Bloom " + prop + " next f32", lambda a, prop=prop, next_f32=next_f32: node(a, f.BLOOM_PATH)["properties"][prop].__setitem__(1, str(next_f32)))
rejects("original map size changed", lambda a: component(a, "Workspace/CornMap/Ground", "size", "X", 900))
rejects("original Source changed", lambda a: node(a, "ServerScriptService/GameServer/Game/SoloRound")["properties"]["Source"].__setitem__(1, "return 'wrong'"))
rejects("original identity changed", lambda a: node(a, "ServerScriptService/GameServer/Game/SoloRound")["properties"]["UniqueId"].__setitem__(1, "new-id"))
rejects("baseline service metadata changed", lambda a: node(a, "StarterPlayer")["properties"]["UseImprovedCharacterEvents"].__setitem__(1, "1"))
rejects("new service metadata", lambda a: node(a, "Packages")["properties"].__setitem__("Unreviewed", ["int", "0", []]))

# Formatting-only Source differences remain supported for all three asset files.
crlf = AFTER.copy()
for path in ASSETS:
    node(crlf, path)["properties"]["Source"][1] = ASSETS[path].replace("\n", "\r\n")
validate(crlf)
with tempfile.TemporaryDirectory(prefix="corn-cluster-manifest-") as temporary:
    wrong = Path(temporary) / "manifest.json"
    data = copy.deepcopy(FIXED)
    data["parts"][0]["after"][0] += 1
    wrong.write_text(json.dumps(data), encoding="utf-8")
    with patch.object(f, "MANIFEST", wrong):
        try:
            validate(AFTER)
        except ValueError:
            rejected.append("modified fixed manifest")
        else:
            raise AssertionError("Candidate-derived fixed manifest accepted")
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
assert f.r.sha256(f.BASELINE) == f.BASELINE_HASH and f.r.sha256(f.MANIFEST) == f.MANIFEST_HASH
print(json.dumps({"passed": True, "original_instances": 6839, "candidate_instances": 6844,
    "rojo_sources": 75, "fog_asset_sources": 3, "persistent_sources": 78, "fixed_cframes": 28,
    "unsafe_dom_cases_rejected": len(rejected), "raw_terrain_cases_rejected": binary_rejected,
    "scope": "Actual checker/current Sources/declared assets; in-memory fixtures, immutable inputs unchanged; no engine-save claim"}))
