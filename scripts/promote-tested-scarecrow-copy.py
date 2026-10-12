"""Verify and atomically promote exact engine-saved Children_of_corn bytes.
Requires both input hashes and the immutable before-scarecrow baseline.
No scene is reconstructed or serialized through Lune.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("scarecrow_check", ROOT / "scripts/verify-scarecrow-copy.py")
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def promote(candidate, expected_original, expected_candidate):
    target = (ROOT / "place/Children_of_corn.rbxl").resolve()
    candidate = candidate.resolve()
    checker.require(target.parent == (ROOT / "place").resolve(), "Wrong scene target")
    checker.require(candidate != target and candidate != checker.BASELINE.resolve(), "Candidate must be a separate engine-saved copy")
    checker.require(checker.sha256(checker.BASELINE) == checker.BASELINE_HASH, "Immutable before-scarecrow baseline changed")
    original, data = target.read_bytes(), candidate.read_bytes()
    checker.require(digest(original) == expected_original.lower(), "Working scene changed; inspect author edits")
    checker.require(digest(data) == expected_candidate.lower(), "Engine copy changed; inspect the new save")
    snapshot = ROOT / "build" / ("tested-scarecrow-candidate-" + digest(data)[:16] + ".rbxl")
    snapshot.parent.mkdir(parents=True, exist_ok=True)
    if snapshot.exists():
        checker.require(snapshot.read_bytes() == data, "Candidate snapshot hash collision")
    else:
        with snapshot.open("xb") as handle:
            handle.write(data)
    report = checker.check(checker.BASELINE, snapshot)
    checker.require(report["passed"] and report["candidate_sha256"] == digest(data), "Candidate did not pass preservation verification")
    if digest(original) == checker.BASELINE_HASH:
        backup = checker.BASELINE
        checker.require(backup.read_bytes() == original, "Immutable backup collision")
    else:
        backup = target.with_name("Children_of_corn.before-scarecrow-save-" + digest(original)[:16] + ".rbxl")
        if backup.exists():
            checker.require(backup.read_bytes() == original, "Save backup collision; preserve both files")
        else:
            with backup.open("xb") as handle:
                handle.write(original)
    output = ROOT / ".artifacts/playtests/2026-10-12-scarecrow"
    output.mkdir(parents=True, exist_ok=True)
    (output / "preservation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary = target.with_suffix(".verified-scarecrow.tmp")
    checker.require(not temporary.exists(), "Temporary path collision")
    try:
        with temporary.open("xb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        checker.require(target.read_bytes() == original, "Working scene changed during verification")
        checker.require(candidate.read_bytes() == data, "Engine copy changed during verification")
        checker.require(checker.sha256(checker.BASELINE) == checker.BASELINE_HASH, "Immutable backup changed during verification")
        checker.require(digest(temporary.read_bytes()) == expected_candidate.lower(), "Temporary copy differs")
        os.replace(temporary, target)
    finally:
        if temporary.exists():
            temporary.unlink()
    checker.require(target.read_bytes() == data, "Promoted engine bytes differ")
    saved = {"target": str(target), "sha256": digest(data), "bytes": len(data), "engine_copy": str(candidate),
        "backup": str(backup), "backup_sha256": digest(original), "immutable_baseline_sha256": checker.BASELINE_HASH,
        "field_side": 840, "torches": 27, "exit_poles": 4, "wall_torches": 2, "sources": report["matching_sources"],
        "raw_terrain_preserved": True, "method": "Verified exact engine bytes; atomic replacement, no Lune scene serialization"}
    (output / "saved-scene.json").write_text(json.dumps(saved, ensure_ascii=False, indent=2), encoding="utf-8")
    return saved


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--expected-original", required=True)
    parser.add_argument("--expected-candidate", required=True)
    args = parser.parse_args()
    print(json.dumps(promote(args.candidate, args.expected_original, args.expected_candidate), ensure_ascii=False))
