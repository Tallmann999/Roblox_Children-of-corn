"""Build a guarded update for the saved Corn scene. Never rewrites a place file."""
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET
ROOT = Path(__file__).resolve().parent.parent
result = subprocess.run([str(ROOT/'.tools/lune/lune.exe'), 'run', str(ROOT/'scripts/export-known-place.luau'), str(ROOT/'place/Children_of_corn.before-spawn-fix.rbxl')], capture_output=True, check=True)
original = ET.fromstring(result.stdout[result.stdout.index(b'<roblox '):])
installed_result = subprocess.run([str(ROOT/'.tools/lune/lune.exe'), 'run', str(ROOT/'scripts/export-known-place.luau'), str(ROOT/'place/Children_of_corn.before-proportion-fix.rbxl')], capture_output=True, check=True)
installed = ET.fromstring(installed_result.stdout[installed_result.stdout.index(b'<roblox '):])
updated = ET.parse(ROOT/'build/code-foundation.rbxlx').getroot()
PREFIXES = ('ReplicatedStorage/GameShared', 'ServerScriptService/GameServer', 'StarterPlayer/StarterPlayerScripts/GameClient')
def literal(s):
    assert ']========]' not in s
    return '[========['+s+']========]'
def entries(xml):
    result = []
    def visit(item, prefix):
        name = item.find("Properties/string[@name='Name']").text
        path = prefix+'/'+name if prefix else name
        source = item.find("Properties/*[@name='Source']")
        if source is not None and any(path.startswith(p+'/') for p in PREFIXES):
            result.append((path, item.attrib['class'], source.text or ''))
        for child in item.findall('Item'): visit(child, path)
    for item in xml.findall('Item'): visit(item, '')
    return result
def table(rows):
    return '{\n'+',\n'.join('{ path = '+literal(path)+', class = '+literal(cls)+', source = '+literal(source.replace('\r\n','\n'))+' }' for path, cls, source in rows)+'\n}'
old = entries(original)
previous_repair = entries(installed)
new = entries(updated)
assert len(old) == len(previous_repair) == len(new) == 18
assert {p for p,_,_ in old} == {p for p,_,_ in previous_repair} == {p for p,_,_ in new}
head = (ROOT/'scripts/scene-repair-head.luau').read_text(encoding='utf-8')
tail = (ROOT/'scripts/scene-repair-tail.luau').read_text(encoding='utf-8')
output = head+'\nlocal baseline = '+table(old)+'\nlocal previousRepair = '+table(previous_repair)+'\nlocal updates = '+table(new)+'\n'+tail
path = ROOT/'scripts/repair-corn-scene.luau'
path.write_text(output, encoding='utf-8')
print(f'Built {path.name}: {len(output.encode())} bytes, {len(new)} sources; no place files written')
