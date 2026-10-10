"""Strict read-only validation of the engine-saved code-only lighting modes update.
The author world, Lighting, imported art and raw unknown Terrain must remain exact.
Neither input is ever serialized or modified.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parent.parent
spec=importlib.util.spec_from_file_location('preservation',ROOT/'scripts/verify-scene-preservation.py')
p=importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
ADDITION='ReplicatedStorage/GameShared/Game/LightingModes'

def check(original,candidate):
    before,warning_before=p.known_dom(original)
    after,warning_after=p.known_dom(candidate)
    assert set(before)-set(after)==set(), 'Author instances removed'
    assert set(after)-set(before)=={ADDITION}, 'Unexpected new instances'
    assert p.unknown_properties(original)==p.unknown_properties(candidate), 'Unknown binary property / raw Terrain changed'
    mapping={}
    def walk(node,prefix=None):
        path='' if prefix is None else (prefix+'/'+node['name'] if prefix else node['name'])
        files=[f for f in node.get('filePaths',[]) if f.startswith('src/')]
        if files: mapping[path]=files[0]
        for child in node.get('children',[]): walk(child,path)
    walk(json.loads((ROOT/'build/sourcemap.json').read_text()))
    sources={path:node['properties']['Source'][1] for path,node in after.items() if 'Source' in node['properties']}
    assert len(sources)==len(mapping)==23 and set(sources)==set(mapping)
    for path,source in sources.items():
        assert source.replace('\r\n','\n')==(ROOT/mapping[path]).read_text(encoding='utf-8').replace('\r\n','\n'), 'Source mismatch: '+path
    assert after[ADDITION]['class']=='ModuleScript'
    changes=[]
    for path,node in before.items():
        other=after[path]
        assert node['class']==other['class'], 'Class changed: '+path
        assert set(node['properties'])==set(other['properties']), 'Properties changed: '+path
        for prop,value in node['properties'].items():
            if other['properties'][prop]==value: continue
            allowed=(prop=='Source' and path in mapping) or (path=='Workspace/Camera' and prop in {'CFrame','Focus'})
            assert allowed, 'Author property changed: '+path+'/'+prop
            changes.append({'path':path,'property':prop})
    meta=p.corn_metadata(candidate)
    assert meta['corners_valid'] and meta['overview_owned'] and meta['preview_owned']
    return {'passed':True,'original_sha256':hashlib.sha256(original.read_bytes()).hexdigest(),
        'candidate_sha256':hashlib.sha256(candidate.read_bytes()).hexdigest(),
        'original_instances':len(before),'candidate_instances':len(after),'matching_sources':23,
        'world_and_lighting_exact':True,'raw_unknown_properties':p.unknown_properties(candidate),
        'allowed_changes':changes,'warnings':{'original':warning_before,'candidate':warning_after}}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('original',type=Path);parser.add_argument('candidate',type=Path)
    parser.add_argument('--report',type=Path,required=True)
    args=parser.parse_args();report=check(args.original.resolve(),args.candidate.resolve())
    args.report.parent.mkdir(parents=True,exist_ok=True)
    args.report.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k not in {'allowed_changes','warnings','raw_unknown_properties'}}))
