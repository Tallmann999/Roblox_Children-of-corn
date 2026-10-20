"""Strict read-only audit: two Source edits, one default UI Module and three settings nodes."""
from pathlib import Path
import argparse,copy,importlib.util,json,re,struct
ROOT=Path(__file__).resolve().parents[1]
def load(name,path):
    s=importlib.util.spec_from_file_location(name,ROOT/path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
builder=load('author_save_builder','scripts/build-flashlight-author-installer.py')
old=load('author_save_helpers','scripts/verify-flashlight-copy.py')
r,fog=old.r,old.fog
require,sha256,identity,remap_refs=r.require,r.sha256,old.identity,old.remap_refs
BANK='ReplicatedStorage/CornFlashlightSettings'
NEW={next(iter(builder.ADDITIONS)):'ModuleScript',BANK:'Folder',BANK+'/Wide':'SpotLight',BANK+'/Core':'SpotLight'}
BASELINE,BASELINE_HASH=builder.BASELINE,builder.BASELINE_SHA

def attributes(value):
    require(value[0]=='BinaryString' and not value[2],'Malformed attributes')
    b=bytes.fromhex(value[1]);offset=0;result={}
    def take(n):
        nonlocal offset
        require(offset+n<=len(b),'Truncated attributes');v=b[offset:offset+n];offset+=n;return v
    def string():return take(struct.unpack('<I',take(4))[0]).decode('utf-8')
    count=struct.unpack('<I',take(4))[0]
    require(count==3,'Unexpected bank attribute count')
    for _ in range(count):
        name=string();require(name not in result,'Duplicate attribute');kind=take(1)[0]
        require(kind in (2,6),'Unexpected attribute type')
        result[name]=string() if kind==2 else struct.unpack('<d',take(8))[0]
    require(offset==len(b),'Trailing attribute bytes')
    return result

def canonicalize(before,after):
    index={identity(n):p for p,n in before.items()};require(len(index)==len(before),'Duplicate original identity')
    paths,seen,targets={},set(),set()
    for p,n in after.items():
        uid=identity(n);require(uid not in seen,'Duplicate identity');seen.add(uid)
        target=index.get(uid)
        if target is None:
            require((p in NEW and n['class']==NEW[p]) or (p in r.SELECTION_PATHS and n['class']=='Instance' and n['properties'].get('Name')==['string','FilteredSelection',[]]),'Unapproved new/replaced identity: '+p)
            target=p
        require(target not in targets,'Duplicate target');paths[p]=target;targets.add(target)
    require(targets==set(before)|set(NEW),'Missing/extra instance')
    reindexed=sum(p!=t for p,t in paths.items())
    result={}
    for p,target in paths.items():
        actual=after[p]
        if target in before:
            require(actual['class']==before[target]['class'] and actual['properties'].get('Name')==before[target]['properties'].get('Name'),'Original class/name changed')
        else:
            require(actual['properties'].get('Name')==['string',target.rsplit('/',1)[-1],[]],'Added name changed')
        parent,pactual=target.rpartition('/')[0],p.rpartition('/')[0]
        require((not parent and not pactual) or paths.get(pactual)==parent,'Original/added parent changed')
        result[target]=actual if not reindexed else actual|{'properties':{k:remap_refs(v,paths) for k,v in actual['properties'].items()}}
    return result,reindexed

def added(before,after):
    old.ADDITIONS=builder.ADDITIONS;old.validate_added_modules(before,after)
    folder=before['Workspace/CornMap/NoCornZones']['properties']
    point=before['Workspace/CornMap/TorchMarkers/torch_solo_slot_01/Flame/TorchLight']['properties']
    for path,cls in NEW.items():
        props=after[path]['properties'];require(after[path]['class']==cls,'New class mismatch')
        uid=props['UniqueId'];require(uid[0]=='UniqueId' and not uid[2] and re.fullmatch('[0-9a-fA-F]{32}',uid[1]) and int(uid[1],16)!=0,'Malformed added UID')
        if cls=='ModuleScript':continue
        template=folder if cls=='Folder' else point
        require(set(props)==set(template)|(set() if cls=='Folder' else {'Angle','Face'}),'Unknown added property set: '+path)
        allowed={'Name','UniqueId','AttributesSerialize'} if cls=='Folder' else {'Name','UniqueId','Angle','Face','Brightness','Range','Color'}
        for prop,v in props.items():
            if path==BANK+'/Core' and prop=='HistoryId':
                require(v==after[BANK+'/Wide']['properties']['UniqueId'],'Core clone history must reference the original author Wide UID')
                continue
            if prop not in allowed:require(r.normalized(v)==r.normalized(template[prop]),'Nondefault added metadata: '+path+'/'+prop)
        if cls=='Folder':
            require(attributes(props['AttributesSerialize'])=={'corn_project_id':'children_of_corn','CornFlashlightSettingsVersion':1,'Pitch':-6},'Bank attributes differ')
        else:
            expected={'Range':24,'Angle':54 if path.endswith('/Wide') else 26,'Brightness':15.08 if path.endswith('/Wide') else 22.62}
            for prop,n in expected.items():
                v=props[prop];n=struct.unpack('<f',struct.pack('<f',n))[0]
                require(v[0]=='float' and not v[2] and abs(float(v[1])-n)<0.000001,'Spot parameter differs: '+path+'/'+prop)
            require(props['Face']==['token','5',[]],'Spot Face differs')
            color=props['Color'];require(color[0]=='Color3' and len(color[2])==3 and {k:float(v[1]) for k,v in color[2]}=={'R':1,'G':1,'B':1},'Spot color differs')
            require(not any(p.startswith(path+'/') for p in after),'Children inside saved Spot')

def validate_dom(before,after,sources,classes,assets):
    require(len(before)==4523 and len(after)==4527,'Expected4523->4527 exact nodes')
    after,reindexed=canonicalize(before,after)
    require(len(sources)==153 and len(assets)==3 and len(sources|assets)==156,'Source counts differ')
    require({p for p,n in after.items() if 'Source' in n['properties']}==set(sources|assets),'Source paths differ')
    require({p for p in after if r.p.owned(p)}==set(classes),'Code topology differs')
    prior={e['path']:e for e in builder.accepted_payload()['entries']}
    for p,source in (sources|assets).items():
        v=after[p]['properties']['Source'];require(v[0]=='string' and not v[2] and v[1].replace('\r\n','\n')==source,'Source mismatch:'+p)
        require(after[p]['class']==classes.get(p,prior.get(p,{}).get('class')),'Source class mismatch')
    added(before,after);changed=[];metadata=[]
    for p,n in before.items():
        props,other=n['properties'],after[p]['properties'];require(set(props)==set(other),'Original property set changed')
        for k,v in props.items():
            actual=other[k]
            if k=='Source':
                require(builder.sha(v[1].replace('\r\n','\n').encode())==prior[p]['after'],'Baseline Source differs')
                if v[1].replace('\r\n','\n')!=actual[1].replace('\r\n','\n'):
                    require(p in builder.CHANGED,'Unapproved Source change');changed.append(p)
                continue
            if v==actual or r.normalized(v)==r.normalized(actual):continue
            camera=p=='Workspace/Camera' and k in {'CFrame','Focus'}
            selection=p in r.SELECTION_PATHS and k=='UniqueId'
            require(camera or selection,'Unapproved world/Lighting/art/metadata change:'+p+'/'+k)
            if camera:old.old.helpers.validate_camera_frame(actual)
            metadata.append({'path':p,'property':k})
    require(set(changed)==builder.CHANGED,'Expected exactly two existing Source changes')
    return {'passed':True,'complete':True,'variant':'A','total_sources':156,'matching_sources':153,'matching_asset_sources':3,'original_instances':4523,'candidate_instances':4527,'new_instances':4,'removed_instances':0,'changed_sources':sorted(changed),'approved_additions':NEW,'reindexed_exporter_paths':reindexed,'retained_world_lighting_art_mesh_identities_parents_exact':True,'allowed_editor_metadata':metadata}

def check(original,candidate):
    require(original.resolve()==BASELINE.resolve(),'Wrong baseline path');builder.require_baseline()
    start=sha256(candidate);_,sources,classes,_=builder.mapping();assets=fog.current_sources()
    before,bw=r.p.known_dom(original);after,aw=r.p.known_dom(candidate)
    ub,ua=r.p.unknown_properties(original),r.p.unknown_properties(candidate);r.validate_unknown(ub,ua)
    result=validate_dom(before,after,sources,classes,assets)
    require(sha256(candidate)==start and sha256(original)==BASELINE_HASH,'Inputs changed during read-only audit')
    return result|{'candidate_sha256':start,'original_sha256':BASELINE_HASH,'bytes':candidate.stat().st_size,'raw_terrain_exact':True,'warnings':{'baseline':bw,'candidate':aw}}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('original',type=Path);p.add_argument('candidate',type=Path);p.add_argument('--report',type=Path,required=True);a=p.parse_args()
    require(a.report.resolve().is_relative_to(builder.OUT.resolve()) and a.report.suffix=='.json','Report outside own evidence folder')
    report=check(a.original,a.candidate);a.report.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps({k:v for k,v in report.items() if k!='warnings'}))
