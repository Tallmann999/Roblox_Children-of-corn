"""Strict added-node/default-metadata/world/Terrain guard fixtures; no scene writes."""
from pathlib import Path
import copy,importlib.util,json,struct
ROOT=Path(__file__).resolve().parents[1]
s=importlib.util.spec_from_file_location('author_verify',ROOT/'scripts/verify-B-flashlight-tall-copy.py');v=importlib.util.module_from_spec(s);s.loader.exec_module(v)
before,_=v.r.p.known_dom(v.BASELINE);payload=json.loads((v.builder.OUT/'payload.json').read_bytes());sources={e['path']:e['source'] for e in payload['entries'] if 'source' in e}
after=copy.deepcopy(before)
after['Lighting']['properties']['LightingStyle']=['token','0',[]]
for p in v.builder.CHANGED:after[p]['properties']['Source']=['string',sources[p],[]]
def typed(kind,value):return[kind,str(value),[]]
def attribute_data(values):
    def st(x):b=x.encode();return struct.pack('<I',len(b))+b
    b=struct.pack('<I',len(values))
    for k,val in values.items():b+=st(k)+(b'\x02'+st(val) if isinstance(val,str) else b'\x06'+struct.pack('<d',val))
    return typed('BinaryString',b.hex())
for index,(p,cls) in enumerate(v.NEW.items(),1):
    template='ServerScriptService/GameServer/Game/RoundAudio' if cls=='ModuleScript' else ('Workspace/CornMap/NoCornZones' if cls=='Folder' else 'Workspace/CornMap/TorchMarkers/torch_solo_slot_01/Flame/TorchLight')
    n=copy.deepcopy(before[template]);n['class']=cls;n['properties']['Name']=typed('string',p.rsplit('/',1)[-1]);n['properties']['UniqueId']=typed('UniqueId',f'{index:032x}')
    props=n['properties']
    if cls=='ModuleScript':props['ScriptGuid']=typed('string','{F0000000-0000-0000-0000-'+f'{index:012x}'+'}');props['Source']=typed('string',sources[p])
    elif cls=='Folder':props['AttributesSerialize']=attribute_data({'corn_project_id':'children_of_corn','CornFlashlightSettingsVersion':1,'Pitch':-4})
    else:
        props['Face']=typed('token',5);props['Angle']=typed('float',100 if p.endswith('/Wide') else 30);props['Range']=typed('float',32 if p.endswith('/Wide') else 4)
        props['Brightness']=typed('float',2 if p.endswith('/Wide') else 13)
        props['Color']=['Color3','',[[key,[key,'1',[]]] for key in ('R','G','B')]]
    after[p]=n

def validate(tree):return v.validate_dom(before,tree)
positive=validate(after);assert positive['passed'] and positive['complete']
refused=[]
def reject(name,edit):
    tree=after.copy()
    def node(p):
        if tree[p] is after.get(p):tree[p]=copy.deepcopy(tree[p])
        return tree[p]
    edit(tree,node)
    try:validate(tree)
    except(ValueError,KeyError,TypeError,IndexError):refused.append(name);return
    raise AssertionError('Unsafe save accepted:'+name)
for p in {e['path'] for e in payload['entries']}:reject('Source:'+p,lambda t,n,p=p:n(p)['properties'].__setitem__('Source',typed('string','return "foreign"')))
for p in v.NEW:
    reject('missing:'+p,lambda t,n,p=p:t.pop(p))
    reject('class:'+p,lambda t,n,p=p:n(p).__setitem__('class','Folder')) if v.NEW[p]!='Folder' else None
    reject('metadata:'+p,lambda t,n,p=p:n(p)['properties'].__setitem__('SourceAssetId',typed('int64',123)))
    reject('extra-property:'+p,lambda t,n,p=p:n(p)['properties'].__setitem__('Foreign',typed('string','bad')))
for p in (v.BANK+'/Wide',v.BANK+'/Core'):
    for prop in ('Range','Angle','Brightness','Face','Shadows','Enabled','Tags','AttributesSerialize'):
        reject(p+'/'+prop,lambda t,n,p=p,prop=prop:n(p)['properties'].__setitem__(prop,typed('string','foreign')))
reject('bank-attrs',lambda t,n:n(v.BANK)['properties'].__setitem__('AttributesSerialize',attribute_data({'corn_project_id':'foreign','CornFlashlightSettingsVersion':1,'Pitch':-4})))
reject('core-clone-history-arbitrary',lambda t,n:n(v.BANK+'/Core')['properties'].__setitem__('HistoryId',typed('UniqueId','f'*32)))
reject('wide-history-arbitrary',lambda t,n:n(v.BANK+'/Wide')['properties'].__setitem__('HistoryId',typed('UniqueId','f'*32)))
for p,prop,value in [('Workspace/CornMap/Ground','CanCollide',typed('bool','false')),('Lighting','Brightness',typed('float',999))]:
    reject(p+'/'+prop,lambda t,n,p=p,prop=prop,value=value:n(p)['properties'].__setitem__(prop,value))
reject('extra-Part',lambda t,n:t.__setitem__('Workspace/Flashlight',copy.deepcopy(before['Workspace/CornMap/Ground'])))
reject('removed-world',lambda t,n:t.pop('Workspace/CornMap/Ground'))
raw=v.r.p.unknown_properties(v.BASELINE);v.r.validate_unknown(raw,copy.deepcopy(raw));terrain=[]
for k in ('payload_sha256','payload_bytes','instance_count'):
    other=copy.deepcopy(raw);row=next(iter(other['properties'].values()));row[k]='0'*64 if k=='payload_sha256' else row[k]+1
    try:v.r.validate_unknown(raw,other)
    except ValueError:terrain.append(k)
    else:raise AssertionError('Terrain accepted')
result={'passed':True,'positive':positive,'refused_dom':len(refused),'cases':refused,'refused_terrain':terrain,'scene_written':False}
(v.builder.OUT/'save-fixtures.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'passed':True,'refused_dom':len(refused),'refused_terrain':len(terrain),'source_count':156,'new_nodes':6,'scene_written':False}))
