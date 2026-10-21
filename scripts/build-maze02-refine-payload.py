"""Build the exact B width/density/world-shadow transaction, without scene writes."""
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'.artifacts/playtests/2026-10-21-maze02-refine'
SOURCES={
 'ReplicatedStorage/GameShared/Game/CornLayout':'src/shared/Game/CornLayout.luau',
 'StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornController':'src/client/Controllers/CornController.luau',
 'StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornBackdropController':'src/client/Controllers/CornBackdropController.luau',
 'StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornShadowController':'src/client/Controllers/CornShadowController.luau',
}
def typed(kind,value): return {'kind':kind,'value':value}
def main():
 native=json.loads((OUT/'native-before.json').read_text())
 plan=json.loads((OUT/'path-plan.json').read_text())
 assert native['name']=='Children_of_corn_B.rbxl' and len(native['sources'])==157
 changes=list(plan['changes'])
 guards=[]
 count={}
 for n in native['nodes']:count[n['path']]=count.get(n['path'],0)+1
 for n in native['nodes']:
  props={}
  if 'frame' in n:
   props={'CFrame':typed('CFrame',n['frame']),'Size':typed('Vector3',n['size'])}
   for field,prop in {'transparency':'Transparency','material':'Material','anchored':'Anchored',
     'collide':'CanCollide','touch':'CanTouch','query':'CanQuery','castShadow':'CastShadow',
     'meshId':'MeshId','textureId':'TextureID'}.items():
    if field in n:props[prop]=n[field]
  guard={'path':n['path'],'class':n['class'],'properties':props,'attributes':n['attrs'] or {},'tags':n['tags'] or []}
  if count[n['path']]>1:
   assert 'frame' in n,'Duplicate non-part path'
   guard['selector']={'CFrame':typed('CFrame',n['frame'])}
   guard['installedSelector']=guard['selector']
  guards.append(guard)
  if n.get('castShadow') is False:
   row={'path':n['path'],'property':'CastShadow','attribute':False,'before':False,'after':True}
   if 'selector' in guard:row.update(selector=guard['selector'],installedSelector=guard['selector'])
   changes.append(row)
  if (n['attrs'] or {}).get('HarvestCastShadow') is False:
   row={'path':n['path'],'property':'HarvestCastShadow','attribute':True,'before':False,'after':True}
   if 'selector' in guard:row.update(selector=guard['selector'],installedSelector=guard['selector'])
   changes.append(row)
 source_changes={}
 for path,file in SOURCES.items():
  source=(ROOT/file).read_text(encoding='utf-8').replace('\r\n','\n')
  before=native['sources'][path]['sha256']
  after=hashlib.sha256(source.encode()).hexdigest()
  assert before!=after,path+' has no declared change'
  source_changes[path]={'before_sha256':before,'after_sha256':after,'source':source}
 payload={'owner':'corn_maze02_refine_v1','sources':native['sources'],'sourceChanges':source_changes,
  'changes':changes,'nodes':[],'guards':guards,'expectedWorkspaceDescendants':native['total']-1}
 data=json.dumps(payload,ensure_ascii=False,separators=(',',':'))+'\n'
 (OUT/'payload.json').write_text(data,encoding='utf-8',newline='\n')
 core=ROOT/'scripts/maze02-refine-native-core.luau'
 if core.exists():
  installer='local payload=game:GetService("HttpService"):JSONDecode([====['+data+']====])\nlocal factory=(function()\n'+core.read_text()+'\nend)()\nreturn game:GetService("HttpService"):JSONEncode(factory(payload))\n'
  (ROOT/'scripts/install-maze02-refine.luau').write_text(installer,encoding='utf-8',newline='\n')
 summary={'payload_sha256':hashlib.sha256(data.encode()).hexdigest(),'payload_bytes':len(data.encode()),
  'changes':len(changes),'sourceChanges':len(source_changes),'guards':len(guards),
  'world_shadow_flags':sum(c['property']=='CastShadow' and not c['attribute'] for c in changes),
  'harvest_shadow_flags':sum(c['property']=='HarvestCastShadow' and c['attribute'] for c in changes),
  'path_and_editor_changes':len(plan['changes']),'density_per_area_multiplier':1.3}
 (OUT/'pipeline-manifest.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8',newline='\n')
 print(json.dumps(summary))
if __name__=='__main__':main()
