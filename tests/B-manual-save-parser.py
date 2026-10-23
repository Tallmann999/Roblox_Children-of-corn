"""Regression: equal names across distinct service classes must never collapse."""
import gzip
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('manual_stream_parser_fixture', ROOT / 'scripts/read-manual-authoring-save.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
elements = []
for index, cls in enumerate(('TimerService', 'ScriptService', 'LodDataService'), 1):
    elements.append(f'<Item class="{cls}" referent="R{index}"><Properties>'
                    '<string name="Name">Instance</string>'
                    f'<UniqueId name="UniqueId">{index:032x}</UniqueId>'
                    f'<Ref name="Pointer">R{index % 3 + 1}</Ref></Properties></Item>')
xml = ('<roblox>' + ''.join(elements) + '</roblox>').encode()

class FakeProcess:
    def __init__(self, *args, **kwargs):
        self.stdout = io.BytesIO(xml)
        self.stderr = io.BytesIO(b'')
    def wait(self):
        return 0

with tempfile.TemporaryDirectory(prefix='corn-stream-parser-fixture-') as directory:
    root = Path(directory)
    candidate = root / 'readonly-fixture.bin'
    candidate.write_bytes(b'fixture input, never a scene')
    m.OUT = root
    with patch.object(m.subprocess, 'Popen', FakeProcess):
        result = m.read_candidate(candidate, hashlib.sha256(candidate.read_bytes()).hexdigest(), 'fixture')
    with gzip.open(root / 'fixture-noncorn-dom.json.gz', 'rt', encoding='utf-8') as stream:
        nodes = json.load(stream)
    assert result['instances'] == result['noncorn_instances'] == 3
    assert list(nodes) == ['Instance', 'Instance#2', 'Instance#3']
    assert [n['class'] for n in nodes.values()] == ['TimerService', 'ScriptService', 'LodDataService']
    assert [n['properties']['Pointer'][1] for n in nodes.values()] == ['Instance#2', 'Instance#3', 'Instance']
    assert (root / 'fixture-corn-dom.jsonl.gz').is_file()
    assert not (root / '-noncorn-dom.json.gz').exists()
    assert candidate.read_bytes() == b'fixture input, never a scene'
print('manual save streaming parser: 7 checks PASS')
