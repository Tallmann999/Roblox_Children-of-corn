"""Build exact five-Source B density update. No scene writes or world changes."""
from pathlib import Path
import copy
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '.artifacts/playtests/2026-10-22-B-double-density'
FILES = {
    'ReplicatedStorage/GameShared/Game/CornLayout': 'src/shared/Game/CornLayout.luau',
    'ReplicatedStorage/GameShared/Game/CornAppearance': 'src/shared/Game/CornAppearance.luau',
    'StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornController': 'src/client/Controllers/CornController.luau',
    'StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornBackdropController': 'src/client/Controllers/CornBackdropController.luau',
    'StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornWindController': 'src/client/Controllers/CornWindController.luau',
}


def main():
    old_raw = (ROOT / '.artifacts/playtests/2026-10-21-corn-edge-shadows/payload.json').read_bytes()
    assert hashlib.sha256(old_raw).hexdigest() == 'b3217aa53f2b907b335f9288e72c7060dc8e9fd0d9c124ddbb6c5c94936cada6'
    old = json.loads(old_raw)
    sources = copy.deepcopy(old['sources'])
    for path, row in old['sourceChanges'].items():
        sources[path]['sha256'] = row['after_sha256']
    native = json.loads((OUT / 'native-before.json').read_text())
    assert native['name'] == 'Children_of_corn_B.rbxl' and native['variant'] == 'B'
    assert native['sources'] == sources and len(sources) == 157
    changes = {}
    for path, file in FILES.items():
        source = (ROOT / file).read_text().replace('\r\n', '\n')
        after = hashlib.sha256(source.encode()).hexdigest()
        assert after != sources[path]['sha256'], path + ': no change'
        changes[path] = {'before_sha256': sources[path]['sha256'], 'after_sha256': after, 'source': source}
    payload = {'owner': 'corn_double_density_v1', 'sources': sources, 'sourceChanges': changes, 'changes': [], 'nodes': []}
    raw = json.dumps(payload, ensure_ascii=False, separators=(',', ':')) + '\n'
    (OUT / 'payload.json').write_text(raw, encoding='utf-8', newline='\n')
    manifest = {'version': 1, 'owner': payload['owner'], 'payload_sha256': hashlib.sha256(raw.encode()).hexdigest(),
                'sourceChanges': {p: {k: v for k, v in row.items() if k != 'source'} for p, row in changes.items()}}
    mraw = json.dumps(manifest, indent=2) + '\n'
    (OUT / 'pipeline-manifest.json').write_text(mraw, encoding='utf-8', newline='\n')
    core = (ROOT / 'scripts/corn-double-density-native-core.luau').read_text()
    installer = 'local payload=game:GetService("HttpService"):JSONDecode([====[' + raw + ']====])\nlocal factory=(function()\n' + core + '\nend)()\nreturn game:GetService("HttpService"):JSONEncode(factory(payload))\n'
    (ROOT / 'scripts/install-corn-double-density.luau').write_text(installer, encoding='utf-8', newline='\n')
    print(json.dumps({'payload_bytes': len(raw.encode()), 'payload_sha256': manifest['payload_sha256'],
                      'manifest_sha256': hashlib.sha256(mraw.encode()).hexdigest(), 'sourceChanges': len(changes)}))


if __name__ == '__main__':
    main()
