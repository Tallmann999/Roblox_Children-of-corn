"""Read-only audit against the byte-verified archived B checkpoint.

Only six requested SpotLight properties, one Pitch attribute and finite editor camera frames may
change. No Sources, instances, identities, parents, world or Terrain exceptions.
"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import re
import tempfile
import struct
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("preset_helpers", ROOT / "scripts/verify-flashlight-copy.py")
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)
spec = importlib.util.spec_from_file_location("preset_frames", ROOT / "scripts/verify-resize-yellow-copy.py")
frames = importlib.util.module_from_spec(spec)
spec.loader.exec_module(frames)
ARCHIVE = ROOT / ".artifacts/playtests/2026-10-20-B-flashlight-preset/before-preset.zip"
ARCHIVE_SHA = "81eef324002c87ce769538f444e288db55c238ed067bfa48b8dad6006afa967b"
BASELINE_SHA = "8160b71046a7c56a8a0c536ecfd3b9b9ca51a4e183c8f42cfb0b2458b81c837c"
A_SHA = "c1f054029ca729f314889ce7874c17c6e5f772cb20541a9c0ceedd796f3446b7"
LIGHT = "ReplicatedStorage/CornFlashlightSettings/"
ALLOWED = {
    (LIGHT + "Wide", "Brightness"): 2.08,
    (LIGHT + "Wide", "Angle"): 78,
    (LIGHT + "Wide", "Range"): 18,
    (LIGHT + "Core", "Angle"): 12,
    (LIGHT + "Core", "Brightness"): 22.62,
    (LIGHT + "Core", "Range"): 24,
}


PITCH_KEY = ("ReplicatedStorage/CornFlashlightSettings", "AttributesSerialize")


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def check(candidate):
    candidate = Path(candidate).resolve()
    assert candidate.is_file() and candidate.suffix.lower() == ".rbxl"
    assert sha(ARCHIVE) == ARCHIVE_SHA, "Archived immutable bytes changed"
    assert sha(ROOT / "place/Children_of_corn.rbxl") == A_SHA, "A changed"
    candidate_sha = sha(candidate)
    with zipfile.ZipFile(ARCHIVE) as archive:
        original_bytes = archive.read("checkpoint/B-before-preset.rbxl")
    assert hashlib.sha256(original_bytes).hexdigest() == BASELINE_SHA
    with tempfile.TemporaryDirectory(prefix="corn-read-only-") as directory:
        original = Path(directory) / "B-before-preset.rbxl"
        original.write_bytes(original_bytes)
        before, bwarn = h.r.p.known_dom(original)
        after, awarn = h.r.p.known_dom(candidate)
        h.r.validate_unknown(h.r.p.unknown_properties(original), h.r.p.unknown_properties(candidate))
    assert len(before) == len(after) == 4532 and set(before) == set(after), "Instance topology changed"
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
                assert struct.pack("<f", float(other[1])) == struct.pack("<f", ALLOWED[key]), "Preset differs: " + path + "/" + prop
            if key == PITCH_KEY:
                assert value != other, "Pitch must change -4 to -6"
            if h.r.normalized(value) == h.r.normalized(other):
                continue
            if key in ALLOWED:
                approved.add(key)
            elif key == PITCH_KEY:
                assert value[0] == other[0] == "BinaryString" and not value[2] and not other[2]
                original_attrs, new_attrs = bytes.fromhex(value[1]), bytes.fromhex(other[1])
                old_pitch, new_pitch = struct.pack("<d", -4), struct.pack("<d", -6)
                assert original_attrs.count(old_pitch) == 1
                assert new_attrs == original_attrs.replace(old_pitch, new_pitch), "Only exact Pitch -4 to -6 is allowed"
                approved.add(key)
            elif path in h.r.SELECTION_PATHS and expected["class"] == "Instance" and prop == "UniqueId":
                assert expected["properties"]["Name"] == ["string", "FilteredSelection", []]
                assert other[0] == "UniqueId" and not other[2] and re.fullmatch(r"[0-9a-fA-F]{32}", other[1])
            else:
                assert path == "Workspace/Camera" and prop in {"CFrame", "Focus"}, "Unapproved change: " + path + "/" + prop
                frames.validate_camera_frame(other)
            changes.append({"path": path, "property": prop})
    assert sources == 156 and approved == set(ALLOWED) | {PITCH_KEY}, "Expected exactly seven settings changes"
    assert after["Lighting"]["properties"]["LightingStyle"] == ["token", "0", []]
    assert sha(candidate) == candidate_sha and sha(ARCHIVE) == ARCHIVE_SHA
    return {"passed": True, "complete": True, "candidate_sha256": candidate_sha,
            "candidate_bytes": candidate.stat().st_size, "baseline_sha256": BASELINE_SHA,
            "instances": len(after), "unchanged_sources": sources, "settings_changes": 7,
            "world_art_identities_parents_lighting_exact": True, "raw_terrain_exact": True,
            "A_unchanged_sha256": A_SHA, "changes": changes, "warnings": [bwarn, awarn]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()
    output = args.report.resolve()
    assert output.is_relative_to(ROOT / ".artifacts/playtests/2026-10-20-B-flashlight-preset") and output.suffix == ".json"
    result = check(args.candidate)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k not in {"changes", "warnings"}}))
