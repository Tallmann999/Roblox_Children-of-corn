"""Read-only audit against the byte-verified archived A checkpoint.

Only four requested SpotLight properties and finite editor camera frames may
change. No Sources, instances, identities, parents, world or Terrain exceptions.
"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import re
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("preset_helpers", ROOT / "scripts/verify-flashlight-copy.py")
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)
spec = importlib.util.spec_from_file_location("preset_frames", ROOT / "scripts/verify-resize-yellow-copy.py")
frames = importlib.util.module_from_spec(spec)
spec.loader.exec_module(frames)
ARCHIVE = ROOT / ".artifacts/scene-archive/2026-10-20-scenes.zip"
ARCHIVE_SHA = "499c06f1f5bfbda032da03a09f7afadf9d548cc186a5c3c4b3807ce3aea4b034"
BASELINE_SHA = "bc85bd9b294a992b0fdff8979b5f56885f0292e12402f51573d613f7acc0ad3f"
B_SHA = "f33571e819fb605130b05489789c93f11c0ef92a3e9762c77691130a60c3d9c0"
LIGHT = "ReplicatedStorage/CornFlashlightSettings/"
ALLOWED = {
    (LIGHT + "Wide", "Brightness"): 2.08,
    (LIGHT + "Wide", "Angle"): 78,
    (LIGHT + "Wide", "Range"): 18,
    (LIGHT + "Core", "Angle"): 12,
}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def check(candidate):
    candidate = Path(candidate).resolve()
    assert candidate.is_file() and candidate.suffix.lower() == ".rbxl"
    assert sha(ARCHIVE) == ARCHIVE_SHA, "Archived immutable bytes changed"
    assert sha(ROOT / "place/Children_of_corn_B.rbxl") == B_SHA, "B changed"
    candidate_sha = sha(candidate)
    with zipfile.ZipFile(ARCHIVE) as archive:
        original_bytes = archive.read("checkpoint/A-before-preset.rbxl")
    assert hashlib.sha256(original_bytes).hexdigest() == BASELINE_SHA
    with tempfile.TemporaryDirectory(prefix="corn-read-only-") as directory:
        original = Path(directory) / "A-before-preset.rbxl"
        original.write_bytes(original_bytes)
        before, bwarn = h.r.p.known_dom(original)
        after, awarn = h.r.p.known_dom(candidate)
        h.r.validate_unknown(h.r.p.unknown_properties(original), h.r.p.unknown_properties(candidate))
    assert len(before) == len(after) == 4529 and set(before) == set(after), "Instance topology changed"
    sources, changes, approved = 0, [], set()
    for path, expected in before.items():
        actual = after[path]
        assert expected["class"] == actual["class"], "Class changed: " + path
        assert set(expected["properties"]) == set(actual["properties"]), "Property set changed: " + path
        if "Source" in expected["properties"]:
            sources += 1
        for prop, value in expected["properties"].items():
            other = actual["properties"][prop]
            key = path, prop
            if key in ALLOWED:
                assert other[0] == "float" and not other[2]
                import struct
                assert struct.pack("<f", float(other[1])) == struct.pack("<f", ALLOWED[key]), "Preset differs: " + path + "/" + prop
            if h.r.normalized(value) == h.r.normalized(other):
                continue
            if key in ALLOWED:
                approved.add(key)
            elif path in h.r.SELECTION_PATHS and expected["class"] == "Instance" and prop == "UniqueId":
                assert expected["properties"]["Name"] == ["string", "FilteredSelection", []]
                assert other[0] == "UniqueId" and not other[2] and re.fullmatch(r"[0-9a-fA-F]{32}", other[1])
            else:
                assert path == "Workspace/Camera" and prop in {"CFrame", "Focus"}, "Unapproved change: " + path + "/" + prop
                frames.validate_camera_frame(other)
            changes.append({"path": path, "property": prop})
    assert sources == 156 and approved == set(ALLOWED), "Expected exactly four settings changes"
    assert after["Lighting"]["properties"]["LightingStyle"] == ["token", "0", []]
    assert sha(candidate) == candidate_sha and sha(ARCHIVE) == ARCHIVE_SHA
    return {"passed": True, "complete": True, "candidate_sha256": candidate_sha,
            "candidate_bytes": candidate.stat().st_size, "baseline_sha256": BASELINE_SHA,
            "instances": len(after), "unchanged_sources": sources, "settings_changes": 4,
            "world_art_identities_parents_lighting_exact": True, "raw_terrain_exact": True,
            "B_unchanged_sha256": B_SHA, "changes": changes, "warnings": [bwarn, awarn]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()
    output = args.report.resolve()
    assert output.is_relative_to(ROOT / ".artifacts/playtests/2026-10-20-A-flashlight-preset") and output.suffix == ".json"
    result = check(args.candidate)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k not in {"changes", "warnings"}}))
