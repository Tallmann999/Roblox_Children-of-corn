"""Temporary placeholder file guards only. Never applies to a real Roblox scene.

The scene evidence function is patched here; run the recovery script without
--apply for its actual read-only DOM/Terrain audit against the real files.
"""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("foreign_sync_recovery", ROOT / "scripts/restore-corn-after-foreign-sync.py")
recovery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recovery)
cases = []


def fixture(kind):
    with tempfile.TemporaryDirectory(prefix="corn-foreign-recovery-guard-") as directory:
        root = Path(directory).resolve()
        place = root / "place"
        place.mkdir()
        working = place / "Children_of_corn.rbxl"
        clean = place / "Children_of_corn.before-multiplayer-20261015.rbxl"
        backup = place / "Children_of_corn.before-foreign-cleanup-20261015.rbxl"
        temporary = place / "Children_of_corn.foreign-recovery-493bc1f9b512d618.tmp"
        mixed_data = b"PLACEHOLDER MIXED FILE; not a Roblox scene"
        clean_data = b"PLACEHOLDER EXACT CLEAN ENGINE BYTES; not a Roblox scene"
        working.write_bytes(mixed_data)
        clean.write_bytes(clean_data)
        audit_calls = []

        def audit(old, mixed):
            assert old == clean and mixed == working
            audit_calls.append((old, mixed))
            if kind == "scene-evidence-rejected":
                raise ValueError("Injected foreign module/world preservation failure")
            if kind == "scene-evidence-false":
                return {"passed": False}
            if kind == "working-race":
                working.write_bytes(b"AUTHOR UPDATE")
            if kind == "clean-race":
                clean.write_bytes(b"CHANGED CLEAN BACKUP")
            if kind == "backup-race":
                backup.write_bytes(b"OTHER FORENSIC EVIDENCE")
            return {"passed": True, "world_instances_exact": 4069, "raw_terrain_exact": True, "foreign_source_paths": ["placeholder fourteen Cooking/Rhythm paths"]}

        if kind == "existing-exact-backup":
            backup.write_bytes(mixed_data)
        if kind == "backup-collision":
            backup.write_bytes(b"OTHER FORENSIC EVIDENCE")
        if kind == "temporary-collision":
            temporary.write_bytes(b"FOREIGN TEMPORARY")
        real_resolve = Path.resolve

        def resolve(path, *args, **kwargs):
            redirected = {
                "redirected-working": working,
                "redirected-clean": clean,
                "redirected-backup": backup,
                "redirected-temporary": temporary,
                "redirected-place": place,
            }.get(kind)
            if path == redirected:
                return root / "NeighbourProject" / path.name
            return real_resolve(path, *args, **kwargs)

        expected_mixed_hash = recovery.digest(mixed_data)
        expected_clean_hash = recovery.digest(clean_data)
        mixed_size, clean_size = len(mixed_data), len(clean_data)
        if kind == "wrong-working-hash":
            expected_mixed_hash = "0" * 64
        if kind == "wrong-clean-hash":
            expected_clean_hash = "0" * 64
        if kind == "wrong-working-size":
            mixed_size += 1
        if kind == "wrong-clean-size":
            clean_size += 1
        real_write = recovery.write_exclusive

        def write(path, data):
            real_write(path, data)
            if kind == "backup-write-mismatch":
                path.write_bytes(b"CORRUPTED BACKUP COPY")
            if kind == "working-race-after-backup":
                working.write_bytes(b"AUTHOR UPDATE")
            if kind == "clean-race-after-backup":
                clean.write_bytes(b"CHANGED CLEAN BACKUP")

        with patch.object(recovery, "ROOT", root), patch.object(recovery, "MIXED_HASH", expected_mixed_hash), patch.object(recovery, "CLEAN_HASH", expected_clean_hash), patch.object(recovery, "MIXED_BYTES", mixed_size), patch.object(recovery, "CLEAN_BYTES", clean_size), patch.object(recovery, "validate_scene_evidence", audit), patch.object(recovery, "write_exclusive", write), patch.object(Path, "resolve", resolve):
            if kind in {"dry-run", "apply", "existing-exact-backup"}:
                report = recovery.recover(apply=kind != "dry-run")
                assert report["passed"] and len(audit_calls) == 1
                assert clean.read_bytes() == clean_data
                assert not temporary.exists()
                if kind == "dry-run":
                    assert report["applied"] is False and working.read_bytes() == mixed_data and not backup.exists()
                else:
                    assert report["applied"] is True and working.read_bytes() == clean_data and backup.read_bytes() == mixed_data
                    assert report["restored_sha256"] == recovery.digest(clean_data)
                    assert report["mixed_backup_sha256"] == recovery.digest(mixed_data)
            else:
                try:
                    recovery.recover(apply=True)
                except (ValueError, OSError):
                    pass
                else:
                    raise AssertionError("Unsafe recovery fixture accepted: " + kind)
                assert working.read_bytes() == (b"AUTHOR UPDATE" if kind in {"working-race", "working-race-after-backup"} else mixed_data)
                assert clean.read_bytes() == (b"CHANGED CLEAN BACKUP" if kind in {"clean-race", "clean-race-after-backup"} else clean_data)
                if kind == "temporary-collision":
                    assert temporary.read_bytes() == b"FOREIGN TEMPORARY"
                else:
                    assert not temporary.exists(), "Owned temporary leaked after rejection"
        cases.append(kind)


for kind in (
    "dry-run", "apply", "existing-exact-backup",
    "wrong-working-hash", "wrong-clean-hash", "wrong-working-size", "wrong-clean-size",
    "scene-evidence-rejected", "scene-evidence-false", "backup-collision", "temporary-collision",
    "redirected-working", "redirected-clean", "redirected-backup", "redirected-temporary", "redirected-place",
    "working-race", "clean-race", "backup-race", "backup-write-mismatch",
    "working-race-after-backup", "clean-race-after-backup",
):
    fixture(kind)
print(json.dumps({"passed": True, "guard_cases": len(cases), "positive_cases": 3, "unsafe_cases_rejected": len(cases) - 3,
    "cases": cases, "scope": "Temporary placeholder bytes plus patched scene audit; no real Roblox scene read, written, restored or serialized"}))
