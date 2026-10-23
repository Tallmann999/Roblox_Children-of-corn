"""Read-only streaming known-DOM observation cache; never writes a scene.

Corn observations are kept separately to bound Python memory. Cache values are
observations of a hash-pinned candidate, never an expected-value allowlist.
"""
from __future__ import annotations
import base64
import collections
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '.artifacts/playtests/2026-10-23-B-manual-authoring'
CORN = 'Workspace/CornMap/CornAuthoring'
CANDIDATE_SHA = '4c5c0c5454da2689996babca4a88b66256240ebb2fb0ac7aa2f787b2ecd8227a'
BASE_SHA = 'c91efe74d1750095eac19390800192ad03b264d7a99de46cf21d170fcb4ed31f'
ARCHIVE_SHA = 'cd2b0a34b50b31693aa1911d958805ba0e0ed5d1230940a01477365feda80682'

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def load_helpers():
    spec = importlib.util.spec_from_file_location('manual_read_helpers', ROOT / 'scripts/verify-B-green-variants-copy.py')
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

def dump(path, value):
    with gzip.open(path, 'wt', encoding='utf-8') as stream:
        json.dump(value, stream, separators=(',', ':'))

def read_candidate(candidate, expected_sha=CANDIDATE_SHA, prefix='candidate'):
    assert sha(candidate) == expected_sha, 'Scene changed; preserve author edits and review'
    command = [str(ROOT / '.tools/lune/lune.exe'), 'run', str(ROOT / 'scripts/export-known-place.luau'), str(candidate)]
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    states, refs, shared, records, inventory = [], {}, {}, {}, []
    roots = collections.Counter()
    raw = OUT / (prefix + '-corn-dom.unresolved.jsonl.gz')
    counts = collections.Counter()

    def value(node):
        text = node.text or ''
        if node.tag == 'BinaryString':
            text = base64.b64decode(text).hex()
        return [node.tag, text, [[child.tag, value(child)] for child in node]]

    with gzip.open(raw, 'wt', encoding='utf-8') as corn:
        for event, element in ET.iterparse(process.stdout, events=('start', 'end')):
            if event == 'start' and element.tag == 'Item':
                states.append({'element': element, 'class': element.attrib['class'], 'ref': element.attrib.get('referent'), 'counts': collections.Counter()})
            elif event == 'end' and element.tag == 'Properties':
                state = states[-1]
                props = {p.attrib['name']: value(p) for p in element}
                name = props.get('Name', ['string', state['class'], []])[1]
                counter = states[-2]['counts'] if len(states) > 1 else roots
                # Paths must disambiguate equal names even across different classes.
                # The legacy reader silently collapsed Timer/Script/LodDataService.
                key = name
                counter[key] += 1
                component = name if counter[key] == 1 else name + '#' + str(counter[key])
                parent_path = states[-2]['path'] if len(states) > 1 else ''
                path = parent_path + '/' + component if parent_path else component
                state['path'] = path
                refs[state['ref']] = path
                node = {'class': state['class'], 'properties': props}
                inventory.append([path, state['class'], props.get('UniqueId'), props.get('HistoryId'), props.get('ScriptGuid')])
                counts[state['class']] += 1
                if path == CORN or path.startswith(CORN + '/'):
                    corn.write(json.dumps([path, node], separators=(',', ':')) + '\n')
                else:
                    assert path not in records, 'Ambiguous duplicate path: ' + path
                    records[path] = node
                element.clear()
            elif event == 'end' and element.tag == 'Item':
                state = states.pop()
                assert state['element'] is element
                if states:
                    states[-1]['element'].remove(element)
                element.clear()
            elif event == 'end' and element.tag == 'SharedString' and element.attrib.get('md5'):
                shared[element.attrib['md5']] = base64.b64decode(element.text or '').hex()
                element.clear()
    warning = process.stderr.read().decode('utf-8', 'replace').strip()
    assert process.wait() == 0, warning
    assert not states

    def resolve(v):
        if v[0] == 'Ref':
            v[1] = refs.get(v[1], v[1])
        elif v[0] == 'SharedString':
            assert v[1] in shared, 'Unresolved shared string'
            v[1] = shared[v[1]]
        for _, child in v[2]:
            resolve(child)
    for node in records.values():
        for v in node['properties'].values():
            resolve(v)
    corn_count = 0
    with gzip.open(raw, 'rt', encoding='utf-8') as source, gzip.open(OUT / (prefix + '-corn-dom.jsonl.gz'), 'wt', encoding='utf-8') as target:
        for line in source:
            path, node = json.loads(line)
            for v in node['properties'].values():
                resolve(v)
            target.write(json.dumps([path, node], separators=(',', ':')) + '\n')
            corn_count += 1
    raw.unlink()
    assert sha(candidate) == expected_sha, 'Scene changed while reading'
    dump(OUT / (prefix + '-noncorn-dom.json.gz'), records)
    dump(OUT / (prefix + '-identity-inventory.json.gz'), inventory)
    if prefix == 'baseline':
        dump(OUT / 'baseline-known-dom.json.gz', records)
    return {'candidate_sha256': expected_sha, 'candidate_bytes': candidate.stat().st_size, 'instances': len(inventory), 'noncorn_instances': len(records), 'corn_instances': corn_count, 'classes': dict(counts), 'warning': warning}

def main():
    candidate = ROOT / 'place/Children_of_corn_B.rbxl'
    archive_path = OUT / 'before-manual-authoring.zip'
    assert sha(archive_path) == ARCHIVE_SHA
    with zipfile.ZipFile(archive_path) as archive:
        assert archive.namelist() == ['B-before-manual-authoring.rbxl']
        data = archive.read(archive.namelist()[0])
    assert len(data) == 1759554 and hashlib.sha256(data).hexdigest() == BASE_SHA
    helper = load_helpers()
    with tempfile.TemporaryDirectory(prefix='corn-author-save-read-') as directory:
        base = Path(directory) / 'B-before-manual-authoring.rbxl'
        base.write_bytes(data)
        baseline_result = read_candidate(base, BASE_SHA, 'baseline')
        ub = helper.r.p.unknown_properties(base)
    result = read_candidate(candidate)
    ua = helper.r.p.unknown_properties(candidate)
    helper.r.validate_unknown(ub, ua)
    result.update({'baseline_sha256': BASE_SHA, 'baseline_instances': baseline_result['instances'], 'baseline_warning': baseline_result['warning'], 'raw_unknown_terrain_exact': True, 'raw_unknown_before': ub, 'raw_unknown_after': ua, 'observation_cache_only': True})
    cache_names = ['baseline-known-dom.json.gz', 'candidate-noncorn-dom.json.gz',
                   'candidate-identity-inventory.json.gz', 'candidate-corn-dom.jsonl.gz']
    result['cache_sha256'] = {name: sha(OUT / name) for name in cache_names}
    result['parser_sha256'] = sha(Path(__file__))
    (OUT / 'save-read-observation.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in {'raw_unknown_before','raw_unknown_after','classes','warning','baseline_warning'}}))

if __name__ == '__main__':
    main()
