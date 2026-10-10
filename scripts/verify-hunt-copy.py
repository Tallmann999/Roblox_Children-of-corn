"""Read-only validation before promoting the engine-saved 840-stud hunt scene.
Original author content is compared property by property. Unknown Terrain bytes
must stay exact; this script never serializes either input place.
"""
import argparse
import hashlib
import importlib.util
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('preservation', ROOT/'scripts/verify-scene-preservation.py')
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
MAP = 'Workspace/CornMap'
LAYERS = (MAP+'/EditorPreview', MAP+'/EditorFieldOverview')
TORCHES = MAP+'/TorchMarkers'
ADDITIONS = {'ServerScriptService/GameServer/Game/MapTuning', 'ServerScriptService/GameServer/Game/MonsterHunt'}

def inside(path, roots):
    return any(path == root or path.startswith(root+'/') for root in roots)

def values(prop):
    return {name: float(value[1]) for name, value in prop[2]}

def close(actual, expected, tolerance=.002):
    assert set(actual) == set(expected)
    assert all(abs(actual[k]-expected[k]) <= tolerance for k in actual), (actual, expected)

def translated(prop, delta):
    result = values(prop)
    for axis, change in zip('XYZ', delta):
        result[axis] += change
    return result

def pivot(prop):
    return prop[2][0][1]

def check(original, candidate):
    before, warning_before = p.known_dom(original)
    after, warning_after = p.known_dom(candidate)
    old = p.corn_metadata(original)
    new = p.corn_metadata(candidate)
    def details(path):
        result = subprocess.run([str(p.LUNE),'run',str(ROOT/'scripts/read-hunt-metadata.luau'),str(path)],check=True,capture_output=True)
        return json.loads(result.stdout)
    before_details, after_details = details(original), details(candidate)
    assert after_details['home_attributes'] == before_details['home_attributes'] | {'monster_home_id':'solo_home'}
    assert after_details['torch_count']==21 and after_details['torches_valid']
    assert new['corners_valid'] and new['overview_owned'] and new['preview_owned']
    number = lambda n: {'type':'number','value':str(n)}
    assert new['map_attrs'] == old['map_attrs'] | {
        'map_version':number(3), 'MapTuningVersion':number(1), 'FieldSide':number(840),
        'EditorCornCount':number(1187), 'TorchClearanceVersion':number(1),
    }
    assert new['overview_attrs'] == old['overview_attrs'] | {'OverviewSpacing':number(12), 'PlantCount':number(4977)}
    assert p.unknown_properties(original) == p.unknown_properties(candidate), 'Unknown binary property changed'

    mapping = {}
    def walk(node, prefix=None):
        path = '' if prefix is None else (prefix+'/'+node['name'] if prefix else node['name'])
        files = [f for f in node.get('filePaths', []) if f.startswith('src/')]
        if files: mapping[path] = files[0]
        for child in node.get('children', []): walk(child, path)
    walk(json.loads((ROOT/'build/sourcemap.json').read_text()))
    sources = {path: node['properties']['Source'][1] for path,node in after.items() if 'Source' in node['properties']}
    assert len(sources) == len(mapping) == 22 and set(sources) == set(mapping)
    for path, source in sources.items():
        assert source.replace('\r\n','\n') == (ROOT/mapping[path]).read_text(encoding='utf-8').replace('\r\n','\n'), path
    assert all(after[path]['class'] == 'ModuleScript' for path in ADDITIONS)

    for path in set(before)-set(after):
        assert inside(path, LAYERS), 'Missing author object: '+path
    for path in set(after)-set(before):
        assert inside(path, LAYERS+(TORCHES,)) or path in ADDITIONS, 'Unexpected object: '+path

    model_deltas = {}
    for path,node in before.items():
        if path.startswith(MAP+'/Props/') and path.count('/') == 3 and node['class'] == 'Model':
            xyz = values(pivot(node['properties']['WorldPivotData']))
            model_deltas[path] = (-.3*xyz['X'], 0, -.3*xyz['Z'])
    model_deltas[MAP+'/EscapeGate'] = (0,0,-180)
    walls = {'West':(-421,0,2,844),'East':(421,0,2,844),'South':(0,-421,840,2),
             'NorthLeft':(-213,421,414,2),'NorthRight':(213,421,414,2)}
    allowed = []
    lighting = after['Lighting']['properties']
    assert float(lighting['Brightness'][1]) == 1
    assert float(lighting['FogStart'][1]) == 55 and float(lighting['FogEnd'][1]) == 320
    assert lighting['TimeOfDay'][1] == '20:30:00'
    for name,rgb in {'Ambient':(18,22,30),'OutdoorAmbient':(38,42,53),'FogColor':(20,27,36)}.items():
        close(values(lighting[name]), dict(zip('RGB',[x/255 for x in rgb])), .00001)

    for path,node in before.items():
        if inside(path, LAYERS): continue
        other = after[path]
        assert other['class'] == node['class'], path
        assert set(other['properties']) == set(node['properties']), 'Property set changed: '+path
        for prop,value in node['properties'].items():
            actual = other['properties'][prop]
            if actual == value: continue
            approved = False
            if prop == 'Source' and path in mapping:
                approved = True
            elif prop == 'UniqueId' and path in {'ReplicatedStorage/GameShared/Game/CornLayout','ServerScriptService/GameServer/Game/MapAuthoring'}:
                approved = True  # Planned cold module clones invalidate Edit require cache.
            elif path == 'Workspace/Camera' and prop in {'CFrame','Focus'}:
                approved = True
            elif path == MAP and prop == 'AttributesSerialize':
                approved = True  # Exact decoded attributes checked above.
            elif path == MAP+'/Props/ScarecrowMarker' and prop == 'Tags':
                expected = set(filter(None,bytes.fromhex(value[1]).split(b'\0'))) | {b'corn_monster_home'}
                assert set(filter(None,bytes.fromhex(actual[1]).split(b'\0'))) == expected
                approved = True
            elif path == MAP+'/Props/ScarecrowMarker' and prop == 'AttributesSerialize':
                # Exact decoded attributes are checked above.
                approved = True
            elif path == 'Lighting' and prop in {'Ambient','Brightness','FogStart','FogEnd','FogColor','OutdoorAmbient','TimeOfDay'}:
                approved = True
            elif path in {MAP+'/Ground',MAP+'/FieldZone',MAP+'/PlayBounds'} and prop == 'size':
                expected = values(value) | {'X':840,'Z':880 if path.endswith('PlayBounds') else 840}
                close(values(actual), expected)
                approved = True
            elif path.startswith(MAP+'/Boundaries/') and prop in {'CFrame','size'}:
                x,z,sx,sz = walls[path.rsplit('/',1)[1]]
                expected = values(value) | ({'X':x,'Z':z} if prop=='CFrame' else {'X':sx,'Z':sz})
                close(values(actual), expected)
                approved = True
            elif prop in {'CFrame','WorldPivotData','ModelMeshCFrame'}:
                delta = next((d for model,d in model_deltas.items() if path==model or path.startswith(model+'/')), None)
                if delta is None and inside(path,(MAP+'/KeySlots',MAP+'/CornerSpawns',MAP+'/NoCornZones',MAP+'/Props')):
                    v = values(value)
                    delta = (-.3*v['X'],0,-.3*v['Z'])
                if delta is not None:
                    close(values(pivot(actual) if prop=='WorldPivotData' else actual),
                          translated(pivot(value) if prop=='WorldPivotData' else value,delta))
                    approved = True
            assert approved, 'Unplanned author property change: '+path+'/'+prop
            allowed.append({'path':path,'property':prop})

    for root,count in zip(LAYERS,(1187,4977)):
        plants = {path:node for path,node in after.items() if path.startswith(root+'/')}
        assert len(plants) == count and all(node['class']=='MeshPart' for node in plants.values())
        sample = next(node for path,node in before.items() if path.startswith(LAYERS[1]+'/'))
        reference = sample['properties']
        for path,node in plants.items():
            props = node['properties']
            for art in ('MeshId','TextureID','TextureContent','MeshContent'):
                if art in reference: assert props.get(art)==reference[art], path+'/'+art
            size = values(props['size']); old_size=values(reference['size'])
            assert 6.799 <= size['Y'] <= 9.201
            close({'X':size['X'],'Z':size['Z']},{'X':old_size['X'],'Z':old_size['Z']},.001)
            frame = values(props['CFrame'])
            assert abs(frame['R11']-1)<.0001 and abs(frame['R01'])<.0001 and abs(frame['R21'])<.0001

    torch_models = [path for path,node in after.items() if path.startswith(TORCHES+'/') and node['class']=='Model']
    slot_names = [path.rsplit('/',1)[1] for path in after if path.startswith(MAP+'/KeySlots/')]
    houses = ['HouseWest','HouseEast','HouseNorthWest']
    assert set(torch_models) == {TORCHES+'/torch_'+name for name in slot_names} | {
        TORCHES+'/torch_'+name+str(side) for name in houses for side in (-1,1)}
    assert len([path for path in after if inside(path,(TORCHES,))]) == 106
    for model in torch_models:
        assert after[model+'/Pole']['class']=='Part' and after[model+'/Flame']['class']=='Part'
        assert after[model+'/Flame/TorchFire']['class']=='Fire'
        assert after[model+'/Flame/TorchLight']['class']=='PointLight'
        assert after[model+'/Pole']['properties']['CanCollide'][1]=='false'
        close(values(after[model+'/Pole']['properties']['size']),dict(zip('XYZ',(.45,13,.45))))
        name = model.rsplit('/',1)[1].removeprefix('torch_')
        if name.startswith('solo_slot_'):
            slot = values(after[MAP+'/KeySlots/'+name]['properties']['CFrame'])
            pole = values(after[model+'/Pole']['properties']['CFrame'])
            close({a:pole[a] for a in 'XZ'},{'X':slot['X'],'Z':slot['Z']+4})

    return {'passed':True,'original_sha256':hashlib.sha256(original.read_bytes()).hexdigest(),
        'candidate_sha256':hashlib.sha256(candidate.read_bytes()).hexdigest(),
        'original_instances':len(before),'candidate_instances':len(after),'matching_tested_sources':22,
        'field_side':840,'torches':21,'overview':4977,'preview':1187,'allowed_author_changes':allowed,
        'raw_unknown_properties':p.unknown_properties(candidate),
        'warnings':{'original':warning_before,'candidate':warning_after},
        'scope':'Exact original property comparison outside authorized geometry relocations, map size, owned corn layers, marker metadata, night Lighting, 22 sources and editor camera; raw Terrain exact.'}

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('original',type=Path); parser.add_argument('candidate',type=Path)
    parser.add_argument('--report',type=Path,required=True)
    args=parser.parse_args()
    report=check(args.original.resolve(),args.candidate.resolve())
    args.report.parent.mkdir(parents=True,exist_ok=True)
    args.report.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k not in {'allowed_author_changes','warnings','raw_unknown_properties'}}))
