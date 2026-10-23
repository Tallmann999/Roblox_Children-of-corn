"""Freeze only reviewed B Sources; never write a scene or touch Studio."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '.artifacts/playtests/2026-10-22-B-green-beds'


def build():
    before = json.loads((OUT / 'expected-before-sources.json').read_text(encoding='utf-8'))
    manifest = json.loads((ROOT / 'rojo/source-map.json').read_text(encoding='utf-8'))
    changes, additions = {}, {}
    for path, row in manifest['variants']['B']['sources'].items():
        source = (ROOT / row['file']).read_text(encoding='utf-8').replace('\r\n', '\n')
        digest = hashlib.sha256(source.encode()).hexdigest()
        if path in before and digest != before[path]['sha256']:
            changes[path] = {'before_sha256': before[path]['sha256'], 'after_sha256': digest, 'source': source}
        elif path not in before:
            additions[path] = {'class': row['class'], 'sha256': digest, 'source': source}
    assert len(before) == 157 and len(changes) == 2 and len(additions) == 6
    assert set(changes) == {'ReplicatedStorage/GameShared/Game/CornAppearance', 'ReplicatedStorage/GameShared/Game/CornLayout'}
    value = {'owner': 'corn_B_green_beds_v1', 'sources': before, 'sourceChanges': changes, 'newSources': additions}
    raw = (json.dumps(value, ensure_ascii=False, separators=(',', ':')) + '\n').encode()
    digest = hashlib.sha256(raw).hexdigest()
    (OUT / 'payload.json').write_bytes(raw)
    info = {'payload_sha256': digest, 'payload_bytes': len(raw), 'old_sources': 157,
            'replacements': list(changes), 'additions': list(additions), 'total_sources': 163}
    (OUT / 'payload-info.json').write_text(json.dumps(info, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(json.dumps(info))


if __name__ == '__main__':
    build()
