"""Exact B transaction: private static corn, brushing trail edges, hidden red eyes.

Reuses the accepted previous native guard, advanced through its frozen transaction.
It is validated in full against fresh stopped Studio before any installation.
No scene serialization or world generation.
"""
import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '.artifacts/playtests/2026-10-21-corn-edge-shadows'
PREVIOUS = ROOT / '.artifacts/playtests/2026-10-21-maze02-refine'
OWNER = 'corn_edge_shadows_v1'
SOURCE_FILES = {
    'ReplicatedStorage/GameShared/Game/CornLayout': 'src/shared/Game/CornLayout.luau',
    'ReplicatedStorage/GameShared/Game/CornAppearance': 'src/shared/Game/CornAppearance.luau',
    'ReplicatedStorage/GameShared/Game/HarvestWardenVisual': '.artifacts/playtests/2026-10-21-corn-edge-shadows/eyes-proposed-HarvestWardenVisual.luau',
    'StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornController': 'src/client/Controllers/CornController.luau',
    'StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornBackdropController': 'src/client/Controllers/CornBackdropController.luau',
}


def main():
    raw = (PREVIOUS / 'payload.json').read_bytes()
    assert hashlib.sha256(raw).hexdigest() == '2b4c993ff531bb96fe5f7e8099327f437f60d2b7d8871810a45134fd294c4217'
    previous = json.loads(raw)
    guards = copy.deepcopy(previous['guards'])
    for delta in previous['changes']:
        matches = [g for g in guards if g['path'] == delta['path'] and
                   (not delta.get('selector') or g.get('selector') == delta['selector'])]
        assert len(matches) == 1, delta
        target = matches[0]['attributes' if delta['attribute'] else 'properties']
        assert target[delta['property']] == delta['before'], delta
        target[delta['property']] = copy.deepcopy(delta['after'])
        if delta['property'] == 'CFrame' and delta.get('selector'):
            matches[0]['selector'] = {'CFrame': delta['after']}
            matches[0]['installedSelector'] = matches[0]['selector']
    sources = copy.deepcopy(previous['sources'])
    for path, delta in previous['sourceChanges'].items():
        sources[path]['sha256'] = delta['after_sha256']
    fresh = json.loads((OUT / 'native-source-before.json').read_text())
    assert fresh['name'] == 'Children_of_corn_B.rbxl' and fresh['total'] == 4315
    assert fresh['sources'] == sources and len(sources) == 157
    eyes = json.loads((OUT / 'eyes-proposal.json').read_text())
    assert len(eyes['changes']) == 4
    changes = eyes['changes']
    source_changes = {}
    for path, file in SOURCE_FILES.items():
        source = (ROOT / file).read_text(encoding='utf-8').replace('\r\n', '\n')
        before = sources[path]['sha256']
        after = hashlib.sha256(source.encode()).hexdigest()
        assert before != after, path + ' has no change'
        source_changes[path] = {'before_sha256': before, 'after_sha256': after, 'source': source}
    payload = {'owner': OWNER, 'sources': sources, 'sourceChanges': source_changes,
               'changes': changes, 'nodes': [], 'guards': guards, 'expectedWorkspaceDescendants': 4314}
    data = json.dumps(payload, ensure_ascii=False, separators=(',', ':')) + '\n'
    (OUT / 'payload.json').write_text(data, encoding='utf-8', newline='\n')
    manifest = {'version': 1, 'owner': OWNER, 'payload_sha256': hashlib.sha256(data.encode()).hexdigest(),
                'sourceChanges': {p: {k: v for k, v in row.items() if k != 'source'}
                                  for p, row in source_changes.items()}}
    manifest_data = json.dumps(manifest, indent=2) + '\n'
    (OUT / 'pipeline-manifest.json').write_text(manifest_data, encoding='utf-8', newline='\n')
    core = (ROOT / 'scripts/corn-edge-shadows-native-core.luau').read_text()
    installer = 'local payload=game:GetService("HttpService"):JSONDecode([====[' + data + ']====])\nlocal factory=(function()\n' + core + '\nend)()\nreturn game:GetService("HttpService"):JSONEncode(factory(payload))\n'
    (ROOT / 'scripts/install-corn-edge-shadows.luau').write_text(installer, encoding='utf-8', newline='\n')
    print(json.dumps({'payload_sha256': manifest['payload_sha256'], 'payload_bytes': len(data.encode()),
                      'manifest_sha256': hashlib.sha256(manifest_data.encode()).hexdigest(),
                      'guards': len(guards), 'sourceChanges': len(source_changes), 'worldChanges': len(changes)}))


if __name__ == '__main__':
    main()
