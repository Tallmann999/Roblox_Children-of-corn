"""Negative fixtures for the actual closed saved-Source and identity graph."""
import copy
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('manual_saved_source_fixture', ROOT / 'scripts/verify-B-manual-authoring-copy.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
m.invariants()
before = m.load_gzip('baseline-known-dom.json.gz')
after = m.load_gzip('candidate-noncorn-dom.json.gz')
payload = json.loads((m.OUT / 'payload-editor-pool.json').read_text(encoding='utf-8'))
inventory = m.load_gzip('candidate-identity-inventory.json.gz')
assert m.validate_sources(before, after, payload)['total_sources'] == 171
assert m.validate_inventory(before, inventory)['candidate_instances'] == 77554
target = 'ServerScriptService/GameServer/Game/InventoryWorld'
assert 'Подобрать' in after[target]['properties']['Source'][1]
new = 'ReplicatedStorage/GameShared/Game/ManualScene'
checks = 3

def rejected(nodes):
    global checks
    try:
        m.validate_sources(before, nodes, payload)
    except ValueError:
        checks += 1
        return
    raise AssertionError('Damaged Source graph accepted')

def mutate_node(path, callback):
    nodes = dict(after)
    nodes[path] = copy.deepcopy(nodes[path])
    callback(nodes[path])
    rejected(nodes)

mutate_node(target, lambda n: n['properties']['Source'].__setitem__(1, n['properties']['Source'][1] + '\n-- wrong saved source'))
mutate_node(new, lambda n: n['properties'].__setitem__('Tags', ['BinaryString', '756e6578706563746564', []]))
mutate_node(new, lambda n: n['properties'].__setitem__('SourceAssetId', ['int64', '0', []]))
mutate_node(target, lambda n: n.__setitem__('class', 'LocalScript'))
nodes = dict(after)
del nodes[target]
rejected(nodes)
nodes = dict(after)
nodes[new + '/unexpected'] = {'class': 'Folder', 'properties': {}}
rejected(nodes)
nodes = dict(after)
nodes['ServerStorage/UnexpectedSource'] = copy.deepcopy(after[new])
rejected(nodes)

for variant in ('duplicate_uid', 'invalid_guid', 'extra_instance'):
    entries = copy.deepcopy(inventory)
    if variant == 'duplicate_uid':
        entries[1][2] = copy.deepcopy(entries[0][2])
    elif variant == 'invalid_guid':
        next(e for e in entries if e[4] is not None)[4] = ['string', '{00000000-0000-0000-0000-000000000000}', []]
    else:
        entries.append(copy.deepcopy(entries[0]))
    try:
        m.validate_inventory(before, entries)
    except ValueError:
        checks += 1
    else:
        raise AssertionError('Damaged identity inventory accepted: ' + variant)
m.invariants()
print(f'manual saved Sources/identity: {checks} checks PASS')
