"""Strict read-only 2026-10-14 engine-save audit: 75 Sources + three exit-sign properties."""
import argparse
import copy
import importlib.util
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / "place/Children_of_corn.before-rustle-20261014.rbxl"
BASELINE_HASH = "ef0731f3235a26e4aa76dd26a7853be4d67e9ccc934f4f054428e5cbd6d146f0"
SIGN = "Workspace/CornMap/Props/VillageRoad/ExitSign"
spec = importlib.util.spec_from_file_location("readability", ROOT / "scripts/verify-readability-copy.py")
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)
require = r.require


def components(value):
    require(value[0] in {"Vector3", "CoordinateFrame"}, "Unexpected sign property type")
    require(all(not item[1][2] for item in value[2]), "Unexpected nested sign component")
    result = {key: float(item[1]) for key, item in value[2]}
    require(len(result) == len(value[2]) and all(math.isfinite(v) for v in result.values()), "Invalid sign components")
    return result


def validate_dom(before, after, sources, classes):
    require(SIGN in before and SIGN in after and before[SIGN]["class"] == "Part", "Owned exit sign missing")
    adjusted = copy.deepcopy(before)
    changes = []
    for prop in ("size", "CFrame"):
        original = before[SIGN]["properties"][prop]
        actual = after[SIGN]["properties"][prop]
        require(original[0] == actual[0], "Sign property type changed: " + prop)
        old, new = components(original), components(actual)
        require(set(old) == set(new), "Sign component set changed: " + prop)
        if prop == "size":
            require(set(old) == {"X", "Y", "Z"}, "Unexpected original Size")
            require(all(abs(old[k] - v) < 0.00001 for k, v in {"X": 12, "Y": 3.2, "Z": 0.3}.items()), "Unrecognized baseline sign size")
            expected = {key: value * 3 for key, value in old.items()}
        else:
            require(set(old) == {"X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"}, "Unexpected original CFrame")
            require(abs(old["Y"] - 36.199986) < 0.00001 and old["X"] == 0 and abs(old["Z"] - 419.7) < 0.00001, "Unrecognized baseline sign position")
            expected = old | {"Y": old["Y"] + 3.2}
        for key, value in expected.items():
            tolerance = 0.00001 if prop == "size" or key == "Y" else 0
            require(abs(new[key] - value) <= tolerance, "Unapproved sign change: " + prop + "/" + key)
        # Only representational float rounding for these two authorized
        # properties is taken from the candidate after checking fixed values.
        adjusted[SIGN]["properties"][prop] = actual
        changes.append({"path": SIGN, "property": prop, "reason": "author_approved_exit_sign_3x", "before": old, "after": new})
    surface_path = SIGN + "/ExitTextSurface"
    original_top = before[surface_path]["properties"]["AlwaysOnTop"]
    actual_top = after[surface_path]["properties"]["AlwaysOnTop"]
    require(original_top == actual_top == ["bool", "false", []], "Exit text overlay must remain the authored false state")
    original_pixels = before[surface_path]["properties"]["PixelsPerStud"]
    actual_pixels = after[surface_path]["properties"]["PixelsPerStud"]
    require(original_pixels == ["float", "48", []] and actual_pixels == ["float", "16", []], "Unapproved exit text pixel density")
    adjusted[surface_path]["properties"]["PixelsPerStud"] = actual_pixels
    changes.append({"path": surface_path, "property": "PixelsPerStud", "reason": "author_approved_physical_exit_letters_3x", "before": 48, "after": 16})
    result = r.validate_dom(adjusted, after, sources, classes)
    result["allowed_changes"].extend(changes)
    result["world_and_lighting_exact"] = False
    result["world_exact_except_three_exit_sign_properties"] = True
    return result


def check(original, candidate):
    original, candidate = original.resolve(), candidate.resolve()
    old_hash, new_hash = r.sha256(original), r.sha256(candidate)
    require(original == BASELINE.resolve() and old_hash == BASELINE_HASH and original.stat().st_size == 1009332, "Immutable before-rustle baseline changed")
    sources, classes = r.mapping_from_sourcemap(ROOT / "build/sourcemap.json")
    before, warnings_before = r.p.known_dom(original)
    after, warnings_after = r.p.known_dom(candidate)
    unknown_before, unknown_after = r.p.unknown_properties(original), r.p.unknown_properties(candidate)
    r.validate_unknown(unknown_before, unknown_after)
    result = validate_dom(before, after, sources, classes)
    meta = r.p.corn_metadata(candidate)
    require(meta["corners_valid"] and meta["overview_owned"] and meta["preview_owned"], "CornMap guards invalid")
    require(r.sha256(original) == old_hash and r.sha256(candidate) == new_hash, "Input changed during audit")
    require(r.mapping_from_sourcemap(ROOT / "build/sourcemap.json") == (sources, classes), "Source/build changed during audit")
    return result | {"passed": True, "original_sha256": old_hash, "candidate_sha256": new_hash, "original_instances": len(before), "candidate_instances": len(after), "bytes": candidate.stat().st_size,
        "raw_unknown_properties": unknown_after, "warnings": {"original": warnings_before, "candidate": warnings_after}, "scope": "Exact engine bytes, no scene write; 75 Sources, no new instances; only authorized ExitSign size/CFrame and text PixelsPerStud, Sources and editor metadata differ. AlwaysOnTop remains false."}


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
