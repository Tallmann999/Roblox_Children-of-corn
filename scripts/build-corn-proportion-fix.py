"""Build a surgical Studio-only correction; never write a place file."""
from pathlib import Path
import subprocess
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / 'place/Children_of_corn.before-proportion-fix.rbxl'
MODULE_PATH = 'ServerScriptService/GameServer/Game/MapAuthoring'
result = subprocess.run(
    [str(ROOT / '.tools/lune/lune.exe'), 'run',
     str(ROOT / 'scripts/export-known-place.luau'), str(BASELINE)],
    capture_output=True, check=True)
xml = ET.fromstring(result.stdout[result.stdout.index(b'<roblox '):])


def find_source():
    matches = []
    def visit(item, prefix):
        name = item.find("Properties/string[@name='Name']").text
        path = prefix + '/' + name if prefix else name
        if path == MODULE_PATH:
            assert item.attrib['class'] == 'ModuleScript'
            assert not item.findall('Item'), 'MapAuthoring has extra children'
            source = item.find("Properties/*[@name='Source']")
            assert source is not None
            matches.append(source.text or '')
        for child in item.findall('Item'):
            visit(child, path)
    for item in xml.findall('Item'):
        visit(item, '')
    assert len(matches) == 1
    return matches[0]


def literal(value):
    # Encode dots to keep the limited Lune adapter from rewriting fingerprint text.
    return json.dumps(value.replace('\r\n', '\n'), ensure_ascii=False).replace('.', r'\046')


prior = find_source()
latest = (ROOT / 'src/server/Game/MapAuthoring.luau').read_text(encoding='utf-8')
assert 'prepared.Size.X * 6' in prior, 'Expected the observed anisotropic overview baseline'
assert 'prepared.Size.X * 6' not in latest
head = (ROOT / 'scripts/corn-proportion-fix-head.luau').read_text(encoding='utf-8')
tail = (ROOT / 'scripts/corn-proportion-fix-tail.luau').read_text(encoding='utf-8')
output = (head + '\nlocal baselineSource = ' + literal(prior)
          + '\nlocal latestSource = ' + literal(latest) + '\n' + tail)
path = ROOT / 'scripts/fix-corn-proportions.luau'
path.write_text(output, encoding='utf-8')
print(f'Built {path.name}: {len(output.encode())} bytes; one code module and owned overview Sizes only; no place files written')
