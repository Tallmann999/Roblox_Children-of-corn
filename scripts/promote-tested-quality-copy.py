"""Verify and atomically promote an engine-saved Children_of_corn copy.
Both hashes are required. Never reconstructs RBXL via Lune.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path

ROOT=Path(__file__).resolve().parent.parent
spec=importlib.util.spec_from_file_location('quality_check',ROOT/'scripts/verify-quality-copy.py')
checker=importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)
digest=lambda data:hashlib.sha256(data).hexdigest()
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('candidate',type=Path)
parser.add_argument('--expected-original',required=True)
parser.add_argument('--expected-candidate',required=True)
args=parser.parse_args()
target=(ROOT/'place/Children_of_corn.rbxl').resolve()
assert target.parent==(ROOT/'place').resolve()
original=target.read_bytes()
data=args.candidate.resolve().read_bytes()
assert digest(original)==args.expected_original.lower(), 'Working scene changed; stop and inspect author edits'
assert digest(data)==args.expected_candidate.lower(), 'Recovery changed; inspect the new copy'
snapshot=ROOT/'build/tested-quality-candidate.rbxl'
snapshot.write_bytes(data)
report=checker.check(target,snapshot)
assert report['passed'] and report['candidate_sha256']==digest(data)
backup=target.with_name('Children_of_corn.before-quality-20261010.rbxl')
if backup.exists() and backup.read_bytes()!=original:
    # Keep the first pre-quality backup; a later save gets its own immutable bytes.
    backup=target.with_name('Children_of_corn.before-quality-save-'+digest(original)[:12]+'.rbxl')
if backup.exists():
    assert backup.read_bytes()==original, 'Backup collision; preserve both files'
else:
    with backup.open('xb') as f: f.write(original)
output=ROOT/'.artifacts/playtests/2026-10-10-quality'
output.mkdir(parents=True,exist_ok=True)
(output/'preservation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
temp=target.with_suffix('.verified.tmp')
assert not temp.exists(), 'Temporary path collision'
try:
    with temp.open('xb') as f:
        f.write(data); f.flush(); os.fsync(f.fileno())
    assert target.read_bytes()==original, 'Working scene changed during verification'
    assert digest(temp.read_bytes())==args.expected_candidate.lower()
    os.replace(temp,target)
finally:
    if temp.exists(): temp.unlink()
assert target.read_bytes()==data
saved={'target':str(target),'sha256':digest(data),'bytes':len(data),'engine_copy':str(args.candidate.resolve()),
    'backup':str(backup),'backup_sha256':digest(original),'field_side':840,'torches':21,'sources':28,
    'raw_terrain_preserved':True,'method':'Verified exact engine bytes; atomic replacement, no Lune serialization'}
(output/'saved-scene.json').write_text(json.dumps(saved,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(saved,ensure_ascii=False))
