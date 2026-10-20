"""Guarded permanent A LightingStyle update; all Sources unchanged. No scene serialization."""
from pathlib import Path
import importlib.util,json,subprocess
ROOT=Path(__file__).resolve().parents[1]
BASELINE=ROOT/'place/Children_of_corn.before-flashlight-lookdown-20261020.rbxl'
BASELINE_SHA='4c8d831bb38440e95889eab9f4680a78c83191c73b9138f458ff9870e139f3c1'
BASELINE_BYTES=1491650
OUT=ROOT/'.artifacts/playtests/2026-10-20-flashlight-lookdown'
ACCEPTED_PAYLOAD=ROOT/'.artifacts/playtests/2026-10-20-flashlight-optics/payload.json'
ACCEPTED_PAYLOAD_SHA='9332af431aa98ba829e6406acda6ca3ba25681092b501ca21d9b87f4830574f0'
OWNER='corn_flashlight_lookdown_20261020'
CHANGED=frozenset()
ALLOWED_CHANGED=CHANGED
ADDITIONS=frozenset()
spec=importlib.util.spec_from_file_location('author_harvest',ROOT/'scripts/build-harvest-installer.py')
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
require,sha,compact=h.require,h.sha,h.compact

def accepted_payload():
    require(sha(ACCEPTED_PAYLOAD.read_bytes())==ACCEPTED_PAYLOAD_SHA,'Frozen saved author-light payload differs')
    return json.loads(ACCEPTED_PAYLOAD.read_bytes())

def require_baseline():
    require(BASELINE.stat().st_size==BASELINE_BYTES and sha(BASELINE.read_bytes())==BASELINE_SHA,'Exact before-author baseline required')

def mapping():
    prior=accepted_payload();sources,classes=h.current_mapping()
    old={e['path']:e for e in prior['entries']}
    require(len(sources)==153 and len(old)==156,'Expected153project+3Fog Sources')
    require(set(classes)-set(prior['classes'])==ADDITIONS and all(classes.get(p)==c for p,c in prior['classes'].items()),'Unexpected code topology')
    require(set(sources)=={p for p in old if h.owned(p)}|ADDITIONS,'Unexpected Source set')
    changes={p for p,s in sources.items() if p in old and sha(s.encode())!=old[p]['after']}
    require(changes==CHANGED,'All saved Sources must remain exact')
    return prior,sources,classes,changes

def build():
    require_baseline();prior,sources,classes,_=mapping()
    run=subprocess.run([str(ROOT/'.tools/lune/lune.exe'),'run',str(ROOT/'.artifacts/harvest-install/read-baseline.luau'),str(BASELINE)],cwd=ROOT,capture_output=True,check=True)
    baseline=json.loads(run.stdout)
    require({p:{'class':e['class'],'sha256':e['sha256']} for p,e in baseline['sources'].items()}=={e['path']:{'class':e['class'],'sha256':e['after']} for e in prior['entries']},'Saved baseline Sources differ')
    require(baseline['classes']==prior['classes'],'Saved baseline classes differ')
    entries=[]
    for old in prior['entries']:
        p=old['path'];source=sources.get(p)
        row={'path':p,'class':old['class'],'before':old['after'],'after':sha(source.encode()) if source is not None else old['after']}
        if p in CHANGED:row['source']=source
        entries.append(row)
    for p in sorted(ADDITIONS):entries.append({'path':p,'class':'ModuleScript','after':sha(sources[p].encode()),'source':sources[p]})
    payload={'version':1,'owner':OWNER,'baselineSha256':BASELINE_SHA,'roots':list(h.ROOTS),'beforeClasses':prior['classes'],'classes':classes,'addedNodes':[{'path':p,'class':'ModuleScript'} for p in sorted(ADDITIONS)],'entries':entries}
    raw=compact(payload)
    core=h.CORE.replace('Harvest','Flashlight lookdown')
    core=core.replace('payload.owner == "harvest_warden_v1"','payload.owner == "'+OWNER+'"')
    core=core.replace('if baseline then 80 else #payload.entries','if baseline then 156 else #payload.entries')
    needle='local ground, field = map:FindFirstChild("Ground"), map:FindFirstChild("FieldZone")'
    require(core.count(needle)==1,'Guard template changed')
    core=core.replace(needle,'assert(map:GetAttribute("HarvestArtVariant") == "A", "Look-down flashlight is A-only")\n'+needle)
    core=core.replace('@PAYLOAD_SHA@',sha(raw)).replace('@BASELINE_SHA@',BASELINE_SHA)
    eq='=='
    while (']'+eq+']').encode() in raw:eq+='='
    code='-- Guarded A LightingStyle.Soft -> Realistic only; no Source/world geometry writes.\nlocal verified = (function()\nlocal raw = ['+eq+'['+raw.decode()+']'+eq+']\n'+core+'\nend)()\n'+STYLE_CORE
    require(len(code.encode())<195000,'Installer exceeds native inline limit')
    OUT.mkdir(exist_ok=True,parents=True)
    (OUT/'payload.json').write_bytes(raw)
    target=ROOT/'scripts/install-flashlight-lookdown.luau';target.write_text(code,encoding='utf-8',newline='\n')
    manifest={'owner':OWNER,'baseline_sha256':BASELINE_SHA,'baseline_sources':156,'final_sources':156,'project_sources':153,'changed_existing':sorted(CHANGED),'added_modules':sorted(ADDITIONS),'installer_sha256':sha(target.read_bytes()),'installer_bytes':len(target.read_bytes()),'payload_sha256':sha(raw),'scene_written':False,'source_changes':0,'lighting_property':'LightingStyle','before':'Soft','after':'Realistic'}
    (OUT/'pipeline-manifest.json').write_bytes(compact(manifest)+b'\n');print(json.dumps(manifest));require_baseline()


STYLE_CORE = r"""
local lighting = game:GetService("Lighting")
local before = lighting.LightingStyle
assert(before == Enum.LightingStyle.Soft or before == Enum.LightingStyle.Realistic, "Unknown LightingStyle; preserved")
if before == Enum.LightingStyle.Realistic then
    return { repeated = true, changed = 0, changedProperties = 0, created = 0, totalSources = verified.totalSources }
end
game:GetService("ChangeHistoryService"):SetWaypoint("Before Corn A Realistic lighting")
local ok, problem = pcall(function()
    lighting.LightingStyle = Enum.LightingStyle.Realistic
    assert(lighting.LightingStyle == Enum.LightingStyle.Realistic, "LightingStyle readback differs")
end)
if not ok then
    lighting.LightingStyle = before
    error("LightingStyle rolled back: " .. tostring(problem))
end
game:GetService("ChangeHistoryService"):SetWaypoint("Corn A Realistic lighting")
return { repeated = false, changed = 0, changedProperties = 1, created = 0, totalSources = verified.totalSources, before = tostring(before), after = tostring(lighting.LightingStyle) }
"""

if __name__=='__main__':build()
