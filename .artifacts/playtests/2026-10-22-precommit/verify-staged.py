"""Read-only byte checks for the explicitly requested 2026-10-22 commit."""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / '.artifacts/playtests/2026-10-22-precommit'
DENSITY = ROOT / '.artifacts/playtests/2026-10-22-B-double-density'


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)


def sha(data):
    return hashlib.sha256(data).hexdigest()


report = json.loads((DENSITY / 'precommit-preservation.json').read_bytes())
assert report['passed'] and report['complete']
assert sha((ROOT / 'place/Children_of_corn_B.rbxl').read_bytes()) == report['candidate_sha256']
assert sha((ROOT / 'place/Children_of_corn.rbxl').read_bytes()) == report['untouched_A_sha256']
payload_raw = (DENSITY / 'payload.json').read_bytes()
assert sha(payload_raw) == report['payload_sha256']
assert sha((DENSITY / 'pipeline-manifest.json').read_bytes()) == report['manifest_sha256']
payload = json.loads(payload_raw)
for path, row in payload['sourceChanges'].items():
    if path.startswith('ReplicatedStorage/GameShared/'):
        source = ROOT / ('src/shared/' + path.removeprefix('ReplicatedStorage/GameShared/') + '.luau')
    else:
        source = ROOT / ('src/client/' + path.removeprefix('StarterPlayer/StarterPlayerScripts/GameClient/') + '.luau')
    raw = source.read_bytes().replace(b'\r\n', b'\n')
    assert sha(raw) == row['after_sha256'] and raw == row['source'].encode(), path

names = git('diff', '--cached', '--name-only', '-z').decode().split('\0')[:-1]
assert names and 'place/Children_of_corn_B.rbxl' in names
assert 'place/Children_of_corn.rbxl' not in names
assert not git('diff', '--cached', '--diff-filter=D', '--name-only', '--', '*.zip')
assert not git('diff', '--cached', '--diff-filter=M', '--name-only', '--', '*.zip')
exact = {}
for name in names:
    if name.startswith('.artifacts/') or name.endswith(('.rbxl', '.zip')):
        working = (ROOT / name).read_bytes()
        staged = git('cat-file', 'blob', ':' + name)
        assert staged == working, 'Staged bytes differ: ' + name
        if name != str((OUT / 'staged-bytes.json').relative_to(ROOT)).replace('\\', '/'):
            exact[name] = {'bytes': len(working), 'sha256': sha(working)}
scenes = sorted(p.relative_to(ROOT).as_posix() for p in ROOT.rglob('*')
                if p.is_file() and p.suffix.lower() in {'.rbxl', '.rbxlx'})
assert scenes == ['place/Children_of_corn.rbxl', 'place/Children_of_corn_B.rbxl'], scenes
summary = {'passed': True, 'staged_files_checked': len(names), 'exact_staged_artifact_scene_files': len(exact),
           'B_sha256': report['candidate_sha256'], 'A_unchanged': True,
           'old_archives_unchanged': True, 'loose_scenes': scenes, 'exact': exact}
print(json.dumps(summary, ensure_ascii=False, indent=2))
