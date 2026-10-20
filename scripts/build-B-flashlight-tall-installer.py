"""Build a guarded B-only flashlight/height/night update; never write scenes."""
from pathlib import Path
import importlib.util,json,subprocess
ROOT=Path(__file__).resolve().parents[1]
BASELINE=ROOT/'place/Children_of_corn_B.before-flashlight-tall-20261020.rbxl'
BASELINE_SHA='e34fe75f598aa99c121c0e271a1b3b2ed071b5f090a9dfdb6245c116da0565d7'
OUT=ROOT/'.artifacts/playtests/2026-10-20-B-flashlight-tall'
OWNER='corn_B_flashlight_tall_20261020'
CHANGED=frozenset({'ReplicatedStorage/GameShared/Game/CornAppearance','ReplicatedStorage/GameShared/Game/LightingModes','ReplicatedStorage/GameShared/Game/RoundText','StarterPlayer/StarterPlayerScripts/GameClient/Controllers/RoundController'})
ADDITIONS=frozenset({'ReplicatedStorage/GameShared/Game/FlashlightPresentation','StarterPlayer/StarterPlayerScripts/GameClient/Controllers/FlashlightController','StarterPlayer/StarterPlayerScripts/GameClient/Game/FlashlightTuning'})
s=importlib.util.spec_from_file_location('b_feature_harvest',ROOT/'scripts/build-harvest-installer.py');h=importlib.util.module_from_spec(s);s.loader.exec_module(h)
require,sha,compact=h.require,h.sha,h.compact
def baseline():
 require(BASELINE.stat().st_size==1485700 and sha(BASELINE.read_bytes())==BASELINE_SHA,'Exact B baseline required')
 result=subprocess.run([str(ROOT/'.tools/lune/lune.exe'),'run',str(ROOT/'.artifacts/harvest-install/read-baseline.luau'),str(BASELINE)],capture_output=True,check=True,cwd=ROOT)
 return json.loads(result.stdout)
def mapping():
 before=baseline();sources,classes=h.current_mapping()
 require(len(before['sources'])==153 and len(sources)==153,'Expected153->156 Sources')
 require(set(classes)-set(before['classes'])==ADDITIONS and all(classes.get(p)==c for p,c in before['classes'].items()),'Code topology differs')
 require(all(p in sources and sha(sources[p].encode())!=before['sources'][p]['sha256'] for p in CHANGED),'Declared B Source changes missing')
 ignored={p for p,v in before['sources'].items() if p in sources and p not in CHANGED and sha(sources[p].encode())!=v['sha256']}
 require(ignored=={'ReplicatedStorage/GameShared/Game/HarvestWardenVisual'},'Unexpected uninstalled local differences')
 return before,sources,classes
def build():
 before,sources,classes=mapping();entries=[]
 for p,v in sorted(before['sources'].items()):
  row={'path':p,'class':v['class'],'before':v['sha256'],'after':sha(sources[p].encode()) if p in CHANGED else v['sha256']}
  if p in CHANGED:row['source']=sources[p]
  entries.append(row)
 for p in sorted(ADDITIONS):entries.append({'path':p,'class':'ModuleScript','source':sources[p],'after':sha(sources[p].encode())})
 payload={'version':1,'owner':OWNER,'baselineSha256':BASELINE_SHA,'roots':list(h.ROOTS),'beforeClasses':before['classes'],'classes':classes,'addedNodes':[{'path':p,'class':'ModuleScript'} for p in sorted(ADDITIONS)],'entries':entries}
 raw=compact(payload);core=h.CORE.replace('payload.owner == "harvest_warden_v1"','payload.owner == "'+OWNER+'"').replace('if baseline then 80 else #payload.entries','if baseline then 153 else #payload.entries')
 needle='local ground, field = map:FindFirstChild("Ground"), map:FindFirstChild("FieldZone")'
 require(core.count(needle)==1,'Guard template changed')
 core=core.replace(needle,'assert(map:GetAttribute("HarvestArtVariant") == "B", "B feature is B-only")\n'+needle)
 core=core.replace('@PAYLOAD_SHA@',sha(raw)).replace('@BASELINE_SHA@',BASELINE_SHA)
 eq='=='
 while (']'+eq+']').encode() in raw:eq+='='
 lighting='''
local lighting = game:GetService("Lighting")
assert(lighting.LightingStyle == Enum.LightingStyle.Soft or lighting.LightingStyle == Enum.LightingStyle.Realistic, "Unknown LightingStyle")
'''
 bank_code=(ROOT/'scripts/B-flashlight-settings.luau').read_text(encoding='utf-8')
 preflight='local function ensureBank()\n'+bank_code+'\nend\nif game:GetService("ReplicatedStorage"):FindFirstChild("CornFlashlightSettings") then ensureBank() end\n'
 code='-- B-only flashlight, taller runtime corn and black-night Sources.\n'+preflight+lighting+'local installed = (function()\nlocal raw = ['+eq+'['+raw.decode()+']'+eq+']\n'+core+'\nend)()\n'+'''local prior = lighting.LightingStyle
local changed = prior ~= Enum.LightingStyle.Realistic
local ok, problem = pcall(function() lighting.LightingStyle = Enum.LightingStyle.Realistic end)
if not ok then lighting.LightingStyle = prior; error(problem) end
installed.changedLightingProperties = if changed then 1 else 0
'''
 code+='local bankResult = ensureBank()\ninstalled.addedSettings = bankResult.addedSettings\nreturn installed\n'
 require(len(code.encode())<195000,'Inline installer too large')
 OUT.mkdir(parents=True,exist_ok=True);(OUT/'payload.json').write_bytes(raw)
 target=ROOT/'scripts/install-B-flashlight-tall.luau';target.write_text(code,encoding='utf-8',newline='\n')
 manifest={'baseline_sha256':BASELINE_SHA,'sources_before':153,'sources_after':156,'changed_existing':sorted(CHANGED),'added_modules':sorted(ADDITIONS),'height_before':8,'height_after':10,'lighting_style':'Realistic','payload_sha256':sha(raw),'installer_sha256':sha(target.read_bytes()),'installer_bytes':len(code.encode()),'settings_preset':{'wide':[2,100,32],'core':[13,30,4],'pitch':-4},'new_settings_nodes':3,'retained_B_visual_source':True,'scene_written':False}
 (OUT/'pipeline-manifest.json').write_bytes(compact(manifest)+b'\n');print(json.dumps(manifest))
if __name__=='__main__':build()
