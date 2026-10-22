"""Promote only strictly audited native B bytes; never serialize a scene."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("B_double_density_save_audit", ROOT / "scripts/verify-B-double-density-copy.py")
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)
TARGET = ROOT / "place/Children_of_corn_B.rbxl"


def main():
    require = audit.require
    require(len(sys.argv) == 2, "Provide one native engine-saved B candidate")
    candidate = Path(sys.argv[1]).resolve()
    require(candidate.is_file() and candidate.suffix.lower() == ".rbxl"
            and candidate != TARGET.resolve(), "Candidate must be a separate native engine-saved binary RBXL")
    original_hash = audit.sha(TARGET)
    if original_hash != audit.BASELINE_SHA256:
        # A concurrent author Save takes priority; validate it without overwriting.
        report = audit.check(TARGET)
        report.update(method="Existing author-saved B independently audited; no replacement",
                      engine_source=str(TARGET), replaced=False)
    else:
        report = audit.check(candidate)
        data = candidate.read_bytes()
        require(hashlib.sha256(data).hexdigest() == report["candidate_sha256"], "Candidate changed after audit")
        require(audit.sha(TARGET) == original_hash, "Author saved B after audit; preserve that Save")
        audit.baseline_info()
        with audit.baseline_file() as original:
            require(original.read_bytes() == TARGET.read_bytes(), "Working B differs from immutable exact baseline")
        temporary = TARGET.with_name(".Children_of_corn_B.double-density.tmp")
        require(temporary.resolve().parent == (ROOT / "place").resolve() and not temporary.exists(), "Unsafe/existing promotion temporary file")
        try:
            with temporary.open("xb") as output:
                output.write(data)
                output.flush()
                os.fsync(output.fileno())
            require(audit.sha(temporary) == report["candidate_sha256"], "Exact-byte temporary copy differs")
            require(audit.sha(candidate) == report["candidate_sha256"], "Engine candidate changed during promotion")
            require(audit.sha(TARGET) == original_hash, "Author saved B during promotion; preserve that Save")
            audit.baseline_info()
            os.replace(temporary, TARGET)
        finally:
            if temporary.exists():
                temporary.unlink()
        require(audit.sha(TARGET) == report["candidate_sha256"], "Promoted B bytes differ")
        # Full independent re-audit of actual working bytes, after replacement.
        verified = audit.check(TARGET)
        require(verified["candidate_sha256"] == report["candidate_sha256"], "Working B changed during final audit")
        report = verified
        report.update(method="Exact native AutoRecovery bytes; hash-guarded atomic replacement; no serialization",
                      engine_source=str(candidate), replaced=True, previous_working_sha256=original_hash)
    report.update(working_B_sha256=audit.sha(TARGET), working_B_bytes=TARGET.stat().st_size,
                  untouched_A_sha256=audit.sha(audit.A_SCENE))
    (audit.OUT / "saved-scenes.json").write_bytes((json.dumps(report, ensure_ascii=False, indent=2) + "\n").encode())
    print(json.dumps({key: report[key] for key in ("passed", "complete", "replaced", "method",
                                                  "working_B_sha256", "working_B_bytes", "untouched_A_sha256")}))


if __name__ == "__main__":
    main()
