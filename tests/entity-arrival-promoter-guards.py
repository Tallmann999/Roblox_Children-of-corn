"""Promotion guards using temporary placeholder bytes, never a real Roblox scene.
The strict checker is patched here; its real preservation checks have separate fixtures.
"""
import importlib.util
import json
import tempfile
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("entity-arrival_promoter", ROOT / "scripts/promote-tested-entity-arrival-copy.py")
promoter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(promoter)


def require(condition, message):
    if not condition:
        raise ValueError(message)


cases = []


def fixture(kind):
    with tempfile.TemporaryDirectory(prefix="corn-entity-arrival-promoter-") as temporary:
        root = Path(temporary).resolve()
        place = root / "place"
        place.mkdir()
        target = place / "Children_of_corn.rbxl"
        baseline = place / "Children_of_corn.before-entity-arrival-20261015.rbxl"
        candidate = root / "engine-placeholder.rbxl"
        original = b"PLACEHOLDER ORIGINAL; not a Roblox scene"
        new = b"PLACEHOLDER ENGINE COPY; not a Roblox scene"
        baseline.write_bytes(original)
        target.write_bytes(original)
        candidate.write_bytes(new)
        check_calls = []
        baseline_hash = promoter.digest(original)

        def check(old, snapshot):
            assert old == baseline and snapshot != candidate and snapshot.read_bytes() == new
            check_calls.append((old, snapshot))
            if kind == "verification-failed":
                raise ValueError("Injected strict verification failure")
            if kind == "target-race":
                target.write_bytes(b"AUTHOR UPDATE")
            if kind == "candidate-race":
                candidate.write_bytes(b"NEW ENGINE SAVE")
            if kind == "baseline-race":
                baseline.write_bytes(b"CHANGED BASELINE")
            return {"passed": True, "candidate_sha256": promoter.digest(new), "matching_sources": 75, "source_change_count": 2, "source_changes": ["declared-two-placeholder"], "matching_asset_sources": 3, "total_sources": 78, "layout_sha256": "fixed-manifest-proof"}

        checker = SimpleNamespace(BASELINE=baseline, BASELINE_HASH=baseline_hash, require=require, check=check)
        original_hash, candidate_hash = baseline_hash, promoter.digest(new)
        supplied = candidate
        if kind == "wrong-original-hash":
            original_hash = "0" * 64
        if kind == "wrong-candidate-hash":
            candidate_hash = "0" * 64
        if kind == "candidate-is-target":
            supplied = target
        if kind == "candidate-is-baseline":
            supplied = baseline
        if kind == "wrong-baseline-path":
            wrong = place / "NeighbourBaseline.rbxl"
            wrong.write_bytes(original)
            checker.BASELINE = wrong
        if kind == "baseline-altered":
            baseline.write_bytes(b"CHANGED BASELINE")
        if kind == "snapshot-collision":
            snapshot = root / "build" / ("tested-entity-arrival-candidate-" + candidate_hash[:16] + ".rbxl")
            snapshot.parent.mkdir()
            snapshot.write_bytes(b"OTHER SNAPSHOT")
        if kind == "temporary-collision":
            target.with_suffix(".verified-entity-arrival.tmp").write_bytes(b"FOREIGN TEMPORARY FILE")
        if kind == "hash-backup":
            original = b"PLACEHOLDER LATER AUTHOR SAVE; not a Roblox scene"
            target.write_bytes(original)
            original_hash = promoter.digest(original)
        if kind == "backup-collision":
            original = b"PLACEHOLDER LATER AUTHOR SAVE; not a Roblox scene"
            target.write_bytes(original)
            original_hash = promoter.digest(original)
            target.with_name("Children_of_corn.before-entity-arrival-save-" + original_hash[:16] + ".rbxl").write_bytes(b"OTHER BACKUP")
        real_resolve = Path.resolve

        def resolve(path, *args, **kwargs):
            if kind == "redirected-target" and path == target:
                return place / "NeighbourScene.rbxl"
            return real_resolve(path, *args, **kwargs)

        with patch.object(promoter, "ROOT", root), patch.object(promoter, "checker", checker), patch.object(Path, "resolve", resolve):
            if kind in {"positive", "hash-backup"}:
                saved = promoter.promote(supplied, original_hash, candidate_hash)
                assert target.read_bytes() == new and candidate.read_bytes() == new
                assert baseline.read_bytes() == b"PLACEHOLDER ORIGINAL; not a Roblox scene"
                assert Path(saved["backup"]).read_bytes() == original
                assert saved["sources"] == 78 and saved["rojo_sources"] == 75 and saved["fog_asset_sources"] == 3 and saved["exit_text_always_on_top"] is False
                assert saved["exit_text_pixels_per_stud"] == 16 and saved["source_change_count"] == 2 and saved["source_changes"] == ["declared-two-placeholder"] and saved["world_and_lighting_exact"] is True
                assert len(check_calls) == 1
                assert not target.with_suffix(".verified-entity-arrival.tmp").exists()
            else:
                try:
                    promoter.promote(supplied, original_hash, candidate_hash)
                except ValueError:
                    pass
                else:
                    raise AssertionError("Unsafe promotion fixture accepted: " + kind)
                assert target.read_bytes() == (b"AUTHOR UPDATE" if kind == "target-race" else original)
                assert candidate.read_bytes() == (b"NEW ENGINE SAVE" if kind == "candidate-race" else new)
                assert baseline.read_bytes() == (b"CHANGED BASELINE" if kind in {"baseline-race", "baseline-altered"} else b"PLACEHOLDER ORIGINAL; not a Roblox scene")
                if kind == "temporary-collision":
                    assert target.with_suffix(".verified-entity-arrival.tmp").read_bytes() == b"FOREIGN TEMPORARY FILE"
                else:
                    assert not target.with_suffix(".verified-entity-arrival.tmp").exists()
        cases.append(kind)


for kind in (
    "positive", "hash-backup", "wrong-original-hash", "wrong-candidate-hash",
    "candidate-is-target", "candidate-is-baseline", "wrong-baseline-path",
    "redirected-target", "baseline-altered", "verification-failed", "snapshot-collision",
    "backup-collision", "temporary-collision", "target-race", "candidate-race", "baseline-race",
):
    fixture(kind)
print(json.dumps({"passed": True, "guard_cases": len(cases), "scope": "Temporary placeholder bytes + patched strict checker; no real scene read/written/promoted", "cases": cases}))
