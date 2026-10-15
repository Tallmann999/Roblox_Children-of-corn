"""Actual escape-save verifier, bounded in-memory fixtures; no RBXL writes."""
import copy
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("escape_audit", ROOT / "scripts/verify-escape-copy.py")
f = importlib.util.module_from_spec(spec)
spec.loader.exec_module(f)
assert f.r.sha256(f.BASELINE) == f.BASELINE_HASH and f.BASELINE.stat().st_size == 1009332
BEFORE, _ = f.r.p.known_dom(f.BASELINE)
SOURCES, CLASSES = f.r.mapping_from_sourcemap(ROOT / "build/sourcemap.json")
AFTER = copy.deepcopy(BEFORE)
for path, source in SOURCES.items():
    AFTER[path]["properties"]["Source"][1] = source


def node(after, path):
    # Negative fixtures clone only the node they mutate; immutable siblings
    # remain shared and the actual verifier only reads candidate properties.
    after[path] = copy.deepcopy(after[path])
    return after[path]


def component(after, path, prop, key, value):
    for name, item in node(after, path)["properties"][prop][2]:
        if name == key:
            item[1] = str(value)
            return
    raise AssertionError("Missing component " + path + "/" + prop + "/" + key)


old_size = f.components(BEFORE[f.SIGN]["properties"]["size"])
old_frame = f.components(BEFORE[f.SIGN]["properties"]["CFrame"])
for key, value in old_size.items():
    component(AFTER, f.SIGN, "size", key, value * 3)
component(AFTER, f.SIGN, "CFrame", "Y", old_frame["Y"] + 3.2)
SURFACE = f.SIGN + "/ExitTextSurface"
assert BEFORE[SURFACE]["properties"]["AlwaysOnTop"] == ["bool", "false", []]
assert BEFORE[SURFACE]["properties"]["PixelsPerStud"] == ["float", "48", []]
AFTER[SURFACE]["properties"]["PixelsPerStud"] = ["float", "16", []]
EDITED_SOURCE = "ServerScriptService/GameServer/Game/RoundAudio"


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
    raise AssertionError("Unsafe escape-save fixture accepted: " + name)


report = validate(AFTER)
assert report["matching_sources"] == 75 and report["new_instances"] == 0
assert report["world_exact_except_three_exit_sign_properties"] and report["original_art_preserved"]
assert len(BEFORE) == len(AFTER) == 6839
world_changes = [change for change in report["allowed_changes"] if change["path"] in {f.SIGN, SURFACE}]
assert {(change["path"], change["property"]) for change in world_changes} == {
    (f.SIGN, "size"), (f.SIGN, "CFrame"), (SURFACE, "PixelsPerStud")
} and len(world_changes) == 3

rejects("one sign axis not 3x", lambda a: component(a, f.SIGN, "size", "Z", 1))
rejects("wrong vertical lift", lambda a: component(a, f.SIGN, "CFrame", "Y", old_frame["Y"] + 3.3))
rejects("sign shifted horizontally", lambda a: component(a, f.SIGN, "CFrame", "X", 1))
rejects("sign rotated", lambda a: component(a, f.SIGN, "CFrame", "R00", 0.5))
rejects("nonfinite sign component", lambda a: component(a, f.SIGN, "size", "X", "nan"))
rejects("unapplied physical text density", lambda a: node(a, SURFACE)["properties"]["PixelsPerStud"].__setitem__(1, "48"))
rejects("unknown pixel density type", lambda a: node(a, SURFACE)["properties"]["PixelsPerStud"].__setitem__(0, "string"))
rejects("unapproved pixel density", lambda a: node(a, SURFACE)["properties"]["PixelsPerStud"].__setitem__(1, "24"))
rejects("intermediate overlay retained", lambda a: node(a, SURFACE)["properties"]["AlwaysOnTop"].__setitem__(1, "true"))
rejects("unknown overlay type", lambda a: node(a, SURFACE)["properties"]["AlwaysOnTop"].__setitem__(0, "string"))
rejects("sign material changed", lambda a: node(a, f.SIGN)["properties"]["Material"].__setitem__(1, "0"))
rejects("exit label edited", lambda a: node(a, f.SIGN + "/ExitTextSurface/ExitText")["properties"]["Text"].__setitem__(1, "Другой текст"))
rejects("other map geometry changed", lambda a: component(a, "Workspace/CornMap/Ground", "size", "X", 900))
rejects("Lighting changed", lambda a: node(a, "Lighting")["properties"]["Brightness"].__setitem__(1, "999"))
rejects("imported art identity changed", lambda a: node(a, "ServerStorage/SM_Prop_Plant_Corn_01_L")["properties"]["UniqueId"].__setitem__(1, "new-id"))
rejects("new persistent instance", lambda a: a.__setitem__("Workspace/CornMap/Props/ExitBeacon", {"class": "Part", "properties": {"Name": ["string", "ExitBeacon", []]}}))
rejects("Source mismatch", lambda a: node(a, EDITED_SOURCE)["properties"]["Source"].__setitem__(1, "return 'wrong'"))
rejects("Source class changed", lambda a: node(a, EDITED_SOURCE).__setitem__("class", "Script"))
rejects("Source identity changed", lambda a: node(a, EDITED_SOURCE)["properties"]["UniqueId"].__setitem__(1, "new-id"))

unknown = f.r.p.unknown_properties(f.BASELINE)
f.r.validate_unknown(unknown, copy.deepcopy(unknown))
terrain_key = next((key for key in unknown["properties"] if "Terrain" in key), None)
assert terrain_key, "Expected raw Terrain preservation coverage"
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

assert f.r.sha256(f.BASELINE) == f.BASELINE_HASH
print(json.dumps({"passed": True, "baseline_instances": len(BEFORE), "matching_sources": 75,
                  "new_instances": 0, "approved_exit_sign_properties": 3,
                  "unsafe_dom_cases_rejected": len(rejected), "raw_terrain_cases_rejected": binary_rejected,
                  "scope": "Actual verifier, current exact Sources/classes, in-memory cases, immutable baseline unchanged"}))
