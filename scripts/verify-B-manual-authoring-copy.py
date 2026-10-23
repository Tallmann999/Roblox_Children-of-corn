"""Read-only, closed-plan audit of the author-saved manual B scene.

The candidate observation cache is produced by read-manual-authoring-save.py.
Expected values come from the immutable c91 scene, frozen source payload,
explicit native builder/journal and independent validators, never the candidate.
"""
from __future__ import annotations
import argparse
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '.artifacts/playtests/2026-10-23-B-manual-authoring'
CANDIDATE = ROOT / 'place/Children_of_corn_B.rbxl'
BASE_SHA = 'c91efe74d1750095eac19390800192ad03b264d7a99de46cf21d170fcb4ed31f'
CANDIDATE_SHA = '4c5c0c5454da2689996babca4a88b66256240ebb2fb0ac7aa2f787b2ecd8227a'
PAYLOAD_SHA = 'dd8d3492d53f77ba99d39c50e7581f28821acdb3c305f64931e5eb2d74563e6f'
ARCHIVE_SHA = 'cd2b0a34b50b31693aa1911d958805ba0e0ed5d1230940a01477365feda80682'
JOURNAL_SHA = '83364c9e2b2e12e2940129afcf0a10cfa8c60d9d6308783c896b31aefc7f5f89'
A_SHA = 'c1f054029ca729f314889ce7874c17c6e5f772cb20541a9c0ceedd796f3446b7'
C_SHA = '24a2d0ff9711d0805d3bcc738a156939574384d859ee3ec8493cc24621712010'
GENERATED = {'UniqueId', 'HistoryId', 'ScriptGuid'}

def require(condition, message):
    if not condition:
        raise ValueError(message)

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module

v = load_module('manual_authoring_dom_helpers', ROOT / 'scripts/verify-B-green-variants-copy.py')

def invariants():
    files = {
        CANDIDATE: CANDIDATE_SHA,
        ROOT / 'place/Children_of_corn.rbxl': A_SHA,
        ROOT / 'place/Children_of_corn_TestScene.rbxl': C_SHA,
        OUT / 'before-manual-authoring.zip': ARCHIVE_SHA,
        OUT / 'payload-editor-pool.json': PAYLOAD_SHA,
        OUT / 'native-change-journal.json': JOURNAL_SHA,
    }
    for path, expected in files.items():
        require(sha(path) == expected, 'Audit input changed; preserve and review: ' + str(path))
    return files

def load_gzip(name):
    with gzip.open(OUT / name, 'rt', encoding='utf-8') as stream:
        return json.load(stream)

def validate_sources(before, after, payload):
    old = {p:n for p,n in before.items() if 'Source' in n['properties']}
    actual = {p:n for p,n in after.items() if 'Source' in n['properties']}
    expected = payload['expectedBeforeSources']
    changes = payload['sourceChanges']
    additions = payload['newSources']
    require(payload['owner'] == 'CornBManualAuthoringV1' and payload['baselineSha256'] == BASE_SHA,
            'Frozen source payload provenance differs')
    require(len(old) == len(expected) == 168 and len(changes) == 8 and len(additions) == 3,
            'Closed source plan counts differ')
    require(set(old) == set(expected) and set(actual) == set(old) | set(additions),
            'Missing, extra or moved persistent Source')
    for path, original in old.items():
        raw = original['properties']['Source'][1].replace('\r\n', '\n')
        require(original['class'] == expected[path]['class'] and hashlib.sha256(raw.encode()).hexdigest() == expected[path]['sha256'],
                'Immutable before Source pin differs: ' + path)
        node = actual[path]
        require(node['class'] == original['class'], 'Source class changed: ' + path)
        target = changes[path]['source'] if path in changes else raw
        require(node['properties']['Source'][0] == 'string' and not node['properties']['Source'][2]
                and node['properties']['Source'][1].replace('\r\n', '\n') == target,
                'Saved Source bytes differ from the frozen plan: ' + path)
        if path in changes:
            require(changes[path]['beforeSha256'] == expected[path]['sha256']
                    and hashlib.sha256(target.encode()).hexdigest() == changes[path]['sha256'], 'Changed Source payload pin differs')
    prototype = before['StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornWindController']
    for path, record in additions.items():
        node = actual[path]
        require(node['class'] == record['class'] == 'ModuleScript', 'New Source class differs')
        target = {k:value for k,value in prototype['properties'].items() if k not in GENERATED}
        target['Name'] = v.scalar('string', path.rsplit('/', 1)[-1])
        target['Source'] = v.scalar('string', record['source'])
        require(hashlib.sha256(record['source'].encode()).hexdigest() == record['sha256'], 'New Source pin differs')
        require(set(node['properties']) == set(target) | GENERATED, 'New Module complete property schema differs: ' + path)
        for key, expected_value in target.items():
            require(v.same(node['properties'][key], expected_value), 'New Module metadata/Source differs: ' + path + '/' + key)
        require(not any(p.startswith(path + '/') for p in after), 'New Module must be childless: ' + path)
    return {'passed': True, 'complete': True, 'retained_sources': 168, 'unchanged_sources': 160,
            'exact_changed_sources': 8, 'new_default_modules': 3, 'total_sources': 171,
            'source_changes': sorted(changes), 'new_sources': sorted(additions)}

def validate_inventory(before, inventory):
    require(len(before) == 6056 and len(inventory) == 77554, 'Complete saved instance count differs')
    ids, guids, paths = {}, set(), set()
    old_ids = {v.identity(node) for node in before.values()}
    require(len(old_ids) == len(before), 'Immutable UniqueId collision')
    new, retained = 0, 0
    for path, cls, uid, history, guid in inventory:
        require(path not in paths, 'Ambiguous saved path: ' + path)
        paths.add(path)
        require(uid and uid[0] == 'UniqueId' and not uid[2] and re.fullmatch('[0-9a-fA-F]{32}', uid[1]),
                'Invalid UniqueId: ' + path)
        identity = uid[1].lower()
        require(identity not in ids, 'Duplicate saved UniqueId: ' + path)
        ids[identity] = path
        if identity in old_ids:
            retained += 1
        else:
            new += 1
            require(int(identity, 16) != 0, 'Zero new UniqueId: ' + path)
        require(history and history[0] == 'UniqueId' and not history[2]
                and re.fullmatch('[0-9a-fA-F]{32}', history[1]), 'Invalid HistoryId: ' + path)
        if guid is not None:
            require(guid[0] == 'string' and not guid[2] and v.GUID.fullmatch(guid[1])
                    and int(guid[1][1:-1].replace('-', ''), 16) != 0, 'Invalid ScriptGuid: ' + path)
            key = guid[1].lower()
            require(key not in guids, 'Duplicate global ScriptGuid: ' + path)
            guids.add(key)
    require(not any('ManualAcceptanceCopy' in p or 'BManualEditorSources' in p for p in paths),
            'Temporary test copy/runtime archive saved')
    # FilteredSelection identities may be replaced by normal editor selection.
    missing = old_ids - set(ids)
    allowed_selection = {v.identity(n) for p,n in before.items() if p in v.r.SELECTION_PATHS and n['class'] == 'Instance'}
    require(missing <= allowed_selection, 'Retained identities missing')
    return {'passed': True, 'complete': True, 'candidate_instances': len(inventory),
            'unique_nonzero_new_ids': new, 'retained_original_ids': retained,
            'filtered_selection_ids_replaced': len(missing), 'globally_unique_script_guids': len(guids),
            'temporary_test_runtime_nodes': 0}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', type=Path, default=OUT / 'author-save-preservation.json')
    args = parser.parse_args()
    require(args.report.resolve().parent == OUT.resolve(), 'Report must remain in task evidence')
    inputs = invariants()
    observation = json.loads((OUT / 'save-read-observation.json').read_text(encoding='utf-8'))
    require(observation['candidate_sha256'] == CANDIDATE_SHA and observation['baseline_sha256'] == BASE_SHA
            and observation['raw_unknown_terrain_exact'], 'Read-only observation provenance differs')
    for name, digest in observation['cache_sha256'].items():
        require(Path(name).name == name and sha(OUT / name) == digest, 'Observation cache changed: ' + name)
    before = load_gzip('baseline-known-dom.json.gz')
    after = load_gzip('candidate-noncorn-dom.json.gz')
    payload = json.loads((OUT / 'payload-editor-pool.json').read_text(encoding='utf-8'))
    result = {'sources': validate_sources(before, after, payload),
              'identity_inventory': validate_inventory(before, load_gzip('candidate-identity-inventory.json.gz'))}
    # The three validators independently prove the remainder of the closed plan.
    # Their reports are generated by the corresponding scripts in this audit.
    validators = {'retained': 'manual_authoring_preservation.py',
                  'groups': 'verify-B-manual-groups.py', 'corn': 'verify-B-manual-corn.py'}
    for name, script in validators.items():
        execution = subprocess.run([sys.executable, str(ROOT / 'scripts' / script)],
                                   capture_output=True, text=True, encoding='utf-8', timeout=360)
        require(execution.returncode == 0, name + ' validator failed: ' + execution.stdout[-3000:] + execution.stderr[-1000:])
        path = OUT / ('save-' + name + '-validation.json')
        report = json.loads(path.read_text(encoding='utf-8'))
        require(report.get('candidate_sha256') == CANDIDATE_SHA and report.get('passed') is True
                and report.get('complete') is True, 'Independent ' + name + ' audit is not complete')
        if name == 'corn':
            require(report.get('all_new_corn_properties_independently_validated') is True
                    and report.get('engine_generated_mesh_mass_inertia_independently_regenerated') is True,
                    'Full corn property and mass/inertia proof is required')
        result[name] = report
    for path, expected in inputs.items():
        require(sha(path) == expected, 'Input changed during audit: ' + str(path))
    for name, digest in observation['cache_sha256'].items():
        require(sha(OUT / name) == digest, 'Observation cache changed during audit: ' + name)
    result.update({'passed': True, 'complete': True, 'variant': 'B', 'baseline_sha256': BASE_SHA,
                   'baseline_bytes': 1759554, 'candidate_sha256': CANDIDATE_SHA,
                   'candidate_bytes': CANDIDATE.stat().st_size, 'candidate_instances': observation['instances'],
                   'raw_terrain_exact': True, 'untouched_A_sha256': A_SHA, 'untouched_C_sha256': C_SHA,
                   'payload_sha256': PAYLOAD_SHA, 'journal_sha256': JOURNAL_SHA,
                   'scope': 'New manual-authoring audit. No scene rewriting, Studio mutation, Save, promotion, commit, push or publishing.'})
    args.report.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if not isinstance(v, dict)}))

if __name__ == '__main__':
    main()
