"""Read-only exact engine-save audit: 75 Sources and 54 fixed torch CFrames.

The immutable before-finale baseline and committed layout are independently
fingerprinted. Three exact audited service metadata additions are recorded
separately; their engine defaults are unverified. Other world/Lighting/art/raw
Terrain remain exact.
"""
import argparse
import importlib.util
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / "place/Children_of_corn.before-finale-20261015.rbxl"
BASELINE_HASH = "9082169a7da5fed15cd962611777285213fce99f23de82f83e0f361a683ecf16"
BASELINE_BYTES = 1015691
MANIFEST = ROOT / "scripts/finale-torch-layout.json"
MANIFEST_HASH = "8129cb70bcbd94338182f69f14661f0387c1be146dd482babd3493f39949fae8"
FRAME_KEYS = ("X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22")
# Narrow audit exception for the author's 2026-10-15 exact engine save.
# These are fixed literals, not inferred engine defaults or candidate allowlists.
SERVICE_METADATA = (
    ("StarterPlayer", "StarterPlayer", "UseImprovedCharacterEvents", ["token", "0", []]),
    ("AvatarSettings", "AvatarSettings", "RulesSchemaVersion", ["int", "0", []]),
    ("Packages", "Packages", "OverridesRecalculated", ["bool", "false", []]),
)
spec = importlib.util.spec_from_file_location("readability", ROOT / "scripts/verify-readability-copy.py")
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)
require = r.require


def layout():
    require(r.sha256(MANIFEST) == MANIFEST_HASH, "Fixed finale torch manifest changed")
    data = r.load_json(MANIFEST)
    require(data["version"] == 2 and data["baseline"] == {
        "path": "place/Children_of_corn.before-finale-20261015.rbxl",
        "bytes": BASELINE_BYTES, "sha256": BASELINE_HASH,
    }, "Unrecognized torch layout baseline")
    require(data["cframe_properties_count"] == len(data["parts"]) == 54 and len(data["models"]) == 27, "Expected fixed 54-Part/27-model layout")
    require(len({part["path"] for part in data["parts"]}) == 54, "Duplicate torch Part path")
    require(len(data["barn_bindings"]) == 3, "Expected three fixed Barn entrance bindings")
    return data


def frame(value):
    require(value[0] == "CoordinateFrame", "Unexpected torch CFrame type")
    require(len(value[2]) == 12, "Unexpected torch CFrame component count")
    parts = {}
    for key, item in value[2]:
        require(key not in parts and key in FRAME_KEYS and item[0] == key and not item[2], "Malformed torch CFrame component")
        parts[key] = float(item[1])
    require(set(parts) == set(FRAME_KEYS) and all(math.isfinite(v) for v in parts.values()), "Nonfinite/incomplete torch CFrame")
    return [parts[key] for key in FRAME_KEYS]


def validate_dom(before, after, sources, classes):
    require(len(before) == len(after) == 6839, "Expected exact 6839-instance finale topology")
    fixed = layout()
    adjusted = before.copy()
    changes = []
    for entry in fixed["parts"]:
        path = entry["path"]
        require(path in before and path in after and before[path]["class"] == after[path]["class"] == "Part", "Fixed torch Part missing/reclassified: " + path)
        original, actual = before[path]["properties"]["CFrame"], after[path]["properties"]["CFrame"]
        old, new = frame(original), frame(actual)
        # known_dom's engine XML prints a shorter decimal than the manifest's
        # exact f32 value; the immutable binary hash remains the baseline guard.
        require(all(abs(a - b) <= 0.00001 for a, b in zip(old, entry["before"])), "Immutable torch baseline frame changed: " + path)
        require(all(abs(a - b) <= 0.00001 for a, b in zip(new, entry["after"])), "Unapproved/incomplete torch placement: " + path)
        adjusted[path] = before[path] | {"properties": before[path]["properties"] | {"CFrame": actual}}
        changes.append({"path": path, "property": "CFrame", "reason": "fixed_author_approved_torch_translation", "before": old, "after": new})
    for entry in fixed["models"]:
        path = entry["path"]
        require(path in before and before[path]["class"] == "Model", "Fixed torch model missing")
        require(before[path]["properties"].get("WorldPivotData") == entry["world_pivot_data"], "Immutable torch pivot metadata changed: " + path)
        require(path in after and after[path]["properties"].get("WorldPivotData") == entry["world_pivot_data"], "Unapproved Model pivot metadata change: " + path)
    service_metadata = []
    for path, cls, prop, literal in SERVICE_METADATA:
        require(path in before and path in after and before[path]["class"] == after[path]["class"] == cls, "Audited service class/path changed: " + path)
        require(prop not in before[path]["properties"], "Audited service property already present in immutable baseline: " + path + "/" + prop)
        require(after[path]["properties"].get(prop) == literal, "Unapproved/missing service metadata: " + path + "/" + prop)
        adjusted[path] = before[path] | {"properties": before[path]["properties"] | {prop: literal}}
        service_metadata.append({"path": path, "class": cls, "property": prop,
            "reason": "audited_engine_save_service_metadata", "before": None,
            "after": literal, "default_unverified": True})
    result = r.validate_dom(adjusted, after, sources, classes)
    result["allowed_changes"].extend(changes)
    result["allowed_changes"].extend(service_metadata)
    result["audited_service_metadata"] = service_metadata
    result["service_metadata_default_unverified"] = True
    result["world_and_lighting_exact"] = False
    result["world_exact_except_54_torch_cframes"] = True
    result["torch_models"] = 27
    result["torch_part_cframes"] = 54
    return result


def check(original, candidate):
    original, candidate = original.resolve(), candidate.resolve()
    old_hash, new_hash = r.sha256(original), r.sha256(candidate)
    require(original == BASELINE.resolve() and old_hash == BASELINE_HASH and original.stat().st_size == BASELINE_BYTES, "Immutable before-finale baseline changed")
    require(candidate.is_file() and candidate.suffix.lower() == ".rbxl", "Candidate must be an exact engine-saved RBXL")
    fixed_hash = r.sha256(MANIFEST)
    sources, classes = r.mapping_from_sourcemap(ROOT / "build/sourcemap.json")
    before, warnings_before = r.p.known_dom(original)
    after, warnings_after = r.p.known_dom(candidate)
    unknown_before, unknown_after = r.p.unknown_properties(original), r.p.unknown_properties(candidate)
    r.validate_unknown(unknown_before, unknown_after)
    result = validate_dom(before, after, sources, classes)
    meta = r.p.corn_metadata(candidate)
    require(meta["corners_valid"] and meta["overview_owned"] and meta["preview_owned"], "CornMap guards invalid")
    require(r.sha256(original) == old_hash and r.sha256(candidate) == new_hash, "Input changed during audit")
    require(r.sha256(MANIFEST) == fixed_hash == MANIFEST_HASH, "Fixed torch layout changed during audit")
    require(r.mapping_from_sourcemap(ROOT / "build/sourcemap.json") == (sources, classes), "Source/build changed during audit")
    return result | {"passed": True, "original_sha256": old_hash, "candidate_sha256": new_hash,
        "original_instances": len(before), "candidate_instances": len(after), "bytes": candidate.stat().st_size,
        "layout_sha256": fixed_hash, "raw_unknown_properties": unknown_after,
        "warnings": {"original": warnings_before, "candidate": warnings_after},
        "scope": "Read-only exact engine bytes; 75 Sources, zero new instances; only fixed 54 torch Part CFrames, Sources, approved editor metadata and three exact audited service metadata additions differ. Service defaults are unverified. Model pivots and all other original properties/world/Lighting/art/raw Terrain stay exact."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("original", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    report_path = args.report.resolve()
    require(report_path.suffix.lower() == ".json" and any(report_path.is_relative_to((ROOT / folder).resolve()) for folder in ("build", ".artifacts")), "Report must stay in owned artifact/build directory")
    result = check(args.original, args.candidate)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k not in {"allowed_changes", "warnings", "raw_unknown_properties"}}))
