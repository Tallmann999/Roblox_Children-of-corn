"""Promote only strictly audited native B bytes, with immutable baseline guards."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('maze02_save_audit', ROOT/'scripts/verify-maze02-copy.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)
TARGET = ROOT/'place/Children_of_corn_B.rbxl'

def main():
    candidate = Path(sys.argv[1]).resolve()
    assert candidate.is_file() and candidate != TARGET.resolve()
    before_target = audit.sha(TARGET)
    if before_target != audit.shadow.BASELINE_SHA:
        # A simultaneous author Save always wins; inspect it instead of overwriting it.
        report = audit.check(TARGET)
        report.update(method='Existing author-saved B independently audited; no replacement',
                      engine_source=str(TARGET), replaced=False)
    else:
        report = audit.check(candidate)
        data = candidate.read_bytes()
        assert hashlib.sha256(data).hexdigest() == report['candidate_sha256']
        assert audit.sha(TARGET) == before_target
        audit.shadow.baseline_info()  # Exact immutable ZIP and untouched A.
        with audit.baseline_file() as original:
            assert original.read_bytes() == TARGET.read_bytes(), 'Working B baseline differs from archived bytes'
        temp = TARGET.with_name('.Children_of_corn_B.maze02.tmp')
        assert temp.resolve().parent == (ROOT/'place').resolve() and not temp.exists()
        try:
            with temp.open('xb') as f:
                f.write(data)
                f.flush()
                os.fsync(f.fileno())
            assert audit.sha(temp) == report['candidate_sha256']
            assert audit.sha(candidate) == report['candidate_sha256'], 'Engine candidate changed during promotion'
            assert audit.sha(TARGET) == before_target, 'Author saved B during promotion; preserving it'
            audit.shadow.baseline_info()
            os.replace(temp, TARGET)
        finally:
            if temp.exists(): temp.unlink()
        assert audit.sha(TARGET) == report['candidate_sha256']
        report.update(method='Exact native AutoRecovery bytes; hash-guarded atomic replacement; no serialization',
                      engine_source=str(candidate), replaced=True, previous_working_sha256=before_target)
    report['working_B_sha256'] = audit.sha(TARGET)
    report['working_B_bytes'] = TARGET.stat().st_size
    report['untouched_A_sha256'] = audit.sha(audit.shadow.A_SCENE)
    (audit.OUT/'saved-scenes.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
    print(json.dumps({k:report[k] for k in ('passed','complete','replaced','method','working_B_sha256','working_B_bytes','untouched_A_sha256')}))

if __name__=='__main__': main()
