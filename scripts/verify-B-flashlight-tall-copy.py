"""Strict B engine save: flashlight/night Sources, runtime corn height, LightingStyle only."""
from pathlib import Path
import argparse,importlib.util,json
ROOT=Path(__file__).resolve().parents[1]
def load(name,path):
 s=importlib.util.spec_from_file_location(name,ROOT/path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
builder=load('b_feature_builder','scripts/build-B-flashlight-tall-installer.py')
h=load('b_feature_save_helpers','scripts/verify-flashlight-copy.py')
h.ADDITIONS=builder.ADDITIONS
author=load('b_bank_save_helpers','scripts/verify-flashlight-author-copy.py')
BANK='ReplicatedStorage/CornFlashlightSettings'
NEW={p:'ModuleScript' for p in builder.ADDITIONS}|{BANK:'Folder',BANK+'/Wide':'SpotLight',BANK+'/Core':'SpotLight'}
author.NEW=NEW
r,require,sha,identity=h.r,h.require,builder.sha,h.identity
BASELINE=builder.BASELINE


def validate_bank(before,after):
 for path,cls in NEW.items():
  if cls=='ModuleScript':continue
  props=after[path]['properties'];template=before['Workspace/CornMap/NoCornZones' if cls=='Folder' else 'Workspace/CornMap/TorchMarkers/torch_solo_slot_01/Flame/TorchLight']['properties']
  require(after[path]['class']==cls and set(props)==set(template)|(set() if cls=='Folder' else {'Face','Angle'}),'Bank property set/class differs')
  require(props['UniqueId'][0]=='UniqueId' and not props['UniqueId'][2] and len(props['UniqueId'][1])==32 and int(props['UniqueId'][1],16)>0,'Invalid bank UID')
  allowed={'Name','UniqueId','AttributesSerialize'} if cls=='Folder' else {'Name','UniqueId','Brightness','Range','Angle','Color','Face'}
  for k,v in props.items():
   if k not in allowed:require(r.normalized(v)==r.normalized(template[k]),'Nondefault bank metadata:'+path+'/'+k)
  if cls=='Folder':require(author.attributes(props['AttributesSerialize'])=={'corn_project_id':'children_of_corn','CornFlashlightSettingsVersion':1,'Pitch':-4},'Wrong B tuning attrs')
  else:
   for k,v in {'Brightness':2 if path.endswith('/Wide') else 13,'Range':32 if path.endswith('/Wide') else 4,'Angle':100 if path.endswith('/Wide') else 30}.items():require(props[k]==['float',str(v),[]],'Wrong B light parameter')
   require(props['Face']==['token','5',[]],'Wrong light face')
   color=props['Color'];require(color[0]=='Color3' and len(color[2])==3 and {k:float(v[1]) for k,v in color[2]}=={'R':1,'G':1,'B':1},'Wrong light color')
   require(not any(p.startswith(path+'/')for p in after),'Children in B light')

def validate_dom(before,after):
 require(len(before)==4526 and len(after)==4532,'Expected4526->4532 exact B nodes')
 after,reindexed=author.canonicalize(before,after);h.validate_added_modules(before,after);validate_bank(before,after)
 payload=json.loads((builder.OUT/'payload.json').read_bytes());entries={e['path']:e for e in payload['entries']}
 require(sum('Source' in n['properties'] for n in after.values())==156,'Exact156 Sources required')
 require({p for p,n in after.items() if 'Source' in n['properties']}==set(entries),'Source paths differ')
 for path,e in entries.items():
  require(after[path]['class']==e['class'],'Source class differs')
  source=after[path]['properties']['Source'];require(source[0]=='string' and not source[2] and sha(source[1].replace('\r\n','\n').encode())==e['after'],'Source differs:'+path)
  if path in before:require(sha(before[path]['properties']['Source'][1].replace('\r\n','\n').encode())==e['before'],'Baseline Source differs')
 changes=[];source_changes=[]
 for path,node in before.items():
  actual=after[path];require(set(node['properties'])==set(actual['properties']),'Original property set differs')
  for prop,value in node['properties'].items():
   other=actual['properties'][prop]
   if value==other or r.normalized(value)==r.normalized(other):continue
   if prop=='Source':
    require(path in builder.CHANGED,'Unapproved Source change');source_changes.append(path);reason='declared_B_feature_source'
   elif path=='Lighting' and prop=='LightingStyle':
    require(value==['token','1',[]] and other==['token','0',[]],'OnlySoft->Realistic allowed');reason='realistic_style'
   elif path=='Workspace/Camera' and prop in {'CFrame','Focus'}:
    h.old.helpers.validate_camera_frame(other);reason='finite_editor_camera'
   elif path in r.SELECTION_PATHS and prop=='UniqueId':reason='editor_selection'
   else:raise ValueError('Unapproved world/art/Lighting/metadata change:'+path+'/'+prop)
   changes.append({'path':path,'property':prop,'reason':reason})
 require(set(source_changes)==builder.CHANGED,'All four Source changes required')
 require(sum(c['reason']=='realistic_style' for c in changes)==1,'Exactlyone style change required')
 return {'passed':True,'complete':True,'variant':'B','sources':156,'changed_sources':sorted(source_changes),'new_modules':sorted(builder.ADDITIONS),'original_instances':4526,'candidate_instances':4532,'new_settings_nodes':3,'removed_instances':0,'reindexed_exporter_paths':reindexed,'world_art_other_lighting_mesh_identities_parents_exact':True,'changes':changes}

def check(candidate):
 builder.baseline();start=sha(candidate.read_bytes())
 before,bw=r.p.known_dom(BASELINE);after,aw=r.p.known_dom(candidate)
 ub,ua=r.p.unknown_properties(BASELINE),r.p.unknown_properties(candidate);r.validate_unknown(ub,ua)
 report=validate_dom(before,after)
 require(sha(BASELINE.read_bytes())==builder.BASELINE_SHA and sha(candidate.read_bytes())==start,'Inputs changed during read-only audit')
 return report|{'baseline_sha256':builder.BASELINE_SHA,'candidate_sha256':start,'bytes':candidate.stat().st_size,'raw_terrain_exact':True,'warnings':{'baseline':bw,'candidate':aw}}
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('candidate',type=Path);p.add_argument('--report',type=Path,required=True);args=p.parse_args()
 require(args.candidate.resolve()!=BASELINE.resolve(),'Separate candidate required');require(args.report.resolve().is_relative_to(builder.OUT.resolve()) and args.report.suffix=='.json','New evidence directory required')
 report=check(args.candidate);args.report.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8');print(json.dumps({k:v for k,v in report.items() if k not in {'changes','warnings'}}))
