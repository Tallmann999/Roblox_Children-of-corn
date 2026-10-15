"""Verify and atomically promote exact engine-saved Children_of_corn bytes.
Both input hashes and the immutable before-multiplayer baseline are required.
No scene is reconstructed or serialized through Lune.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("multiplayer_check", ROOT / "scripts/verify-multiplayer-copy.py")
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def promote(candidate, expected_original, expected_candidate):
    place = (ROOT / "place").resolve()
    target_path = place / "Children_of_corn.rbxl"
    target = target_path.resolve()
    baseline_path = place / "Children_of_corn.before-multiplayer-20261015.rbxl"
    baseline = checker.BASELINE.resolve()
    candidate = candidate.resolve()
    checker.require(place == ROOT.resolve() / "place", "Redirected scene directory")
    checker.require(target == target_path, "Wrong scene target or redirected working file")
    checker.require(baseline == baseline_path and baseline_path.resolve() == baseline_path, "Wrong immutable before-multiplayer baseline path")
    checker.require(candidate != target and candidate != baseline, "Candidate must be a separate engine-saved copy")
    checker.require(candidate.suffix.lower() == ".rbxl" and candidate.is_file(), "Candidate must be a saved RBXL file")
    checker.require(digest(baseline.read_bytes()) == checker.BASELINE_HASH, "Immutable before-multiplayer baseline changed")
    original, data = target.read_bytes(), candidate.read_bytes()
    checker.require(digest(original) == expected_original.lower(), "Working scene changed; inspect author edits")
    checker.require(digest(data) == expected_candidate.lower(), "Engine copy changed; inspect the new save")
    snapshot = ROOT / "build" / ("tested-multiplayer-candidate-" + digest(data)[:16] + ".rbxl")
    snapshot.parent.mkdir(parents=True, exist_ok=True)
    checker.require(snapshot.resolve() == snapshot, "Redirected candidate snapshot")
    if snapshot.exists():
        checker.require(snapshot.read_bytes() == data, "Candidate snapshot hash collision")
    else:
        with snapshot.open("xb") as handle:
            handle.write(data)
    report = checker.check(baseline, snapshot)
    checker.require(report["passed"] and report["candidate_sha256"] == digest(data), "Candidate did not pass preservation verification")
    if digest(original) == checker.BASELINE_HASH:
        backup = baseline
        checker.require(backup.read_bytes() == original, "Immutable backup collision")
    else:
        backup = target.with_name("Children_of_corn.before-multiplayer-save-" + digest(original)[:16] + ".rbxl")
        checker.require(backup.resolve() == backup, "Redirected save backup")
        if backup.exists():
            checker.require(backup.read_bytes() == original, "Save backup collision; preserve both files")
        else:
            with backup.open("xb") as handle:
                handle.write(original)
    output = ROOT / ".artifacts/playtests/2026-10-15-multiplayer"
    checker.require(output.resolve() == output, "Redirected preservation artifact directory")
    output.mkdir(parents=True, exist_ok=True)
    (output / "preservation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary = target.with_suffix(".verified-multiplayer.tmp")
    checker.require(not temporary.exists(), "Temporary path collision")
    created_temporary = False
    try:
        with temporary.open("xb") as handle:
            created_temporary = True
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        checker.require(target.read_bytes() == original, "Working scene changed during verification")
        checker.require(candidate.read_bytes() == data, "Engine copy changed during verification")
        checker.require(digest(baseline.read_bytes()) == checker.BASELINE_HASH, "Immutable backup changed during verification")
        checker.require(digest(temporary.read_bytes()) == expected_candidate.lower(), "Temporary copy differs")
        os.replace(temporary, target)
    finally:
        if created_temporary and temporary.exists():
            temporary.unlink()
    checker.require(target.read_bytes() == data, "Promoted engine bytes differ")
    saved = {
        "target": str(target), "sha256": digest(data), "bytes": len(data), "engine_copy": str(candidate),
        "backup": str(backup), "backup_sha256": digest(original), "immutable_baseline_sha256": checker.BASELINE_HASH,
        "field_side": 630, "torches": 27, "exit_poles": 4, "wall_torches": 2, "sources": report["total_sources"], "rojo_sources": report["matching_sources"], "fog_asset_sources": report["matching_asset_sources"],
        "added_module_paths": report["added_module_paths"], "new_instances": report["new_instances"], "source_change_count": report["source_change_count"], "source_changes": report["source_changes"], "world_and_lighting_exact": True, "exit_sign_scale": 3, "exit_text_pixels_per_stud": 16, "exit_text_always_on_top": False, "raw_terrain_preserved": True,
        "method": "Verified exact engine bytes; atomic replacement, no Lune scene serialization",
    }
    (output / "saved-scene.json").write_text(json.dumps(saved, ensure_ascii=False, indent=2), encoding="utf-8")
    return saved


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--expected-original", required=True)
    parser.add_argument("--expected-candidate", required=True)
    args = parser.parse_args()
    print(json.dumps(promote(args.candidate, args.expected_original, args.expected_candidate), ensure_ascii=False))
