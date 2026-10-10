"""Strict read-only verification of the engine-saved, tested movement scene.
Allows only current source files, two planned modules, guarded overview Size/attrs,
and editor Camera CFrame/Focus. All other original properties and raw Terrain stay exact.
"""
import argparse
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('preservation', ROOT/'scripts/verify-scene-preservation.py')
preservation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preservation)
OVERVIEW = 'Workspace/CornMap/EditorFieldOverview'
ADDITIONS = {'ReplicatedStorage/GameShared/Game/Stamina', 'StarterPlayer/StarterPlayerScripts/GameClient/Controllers/MovementController'}

def vector(prop):
    assert prop[0] == 'Vector3'
    return {axis: float(value[1]) for axis, value in prop[2]}

def check(original, candidate):
    report = preservation.compare(original, candidate)
    before, _ = preservation.known_dom(original)
    after, _ = preservation.known_dom(candidate)
    old_meta = preservation.corn_metadata(original)
    new_meta = preservation.corn_metadata(candidate)
    assert new_meta['corners_valid'] and new_meta['overview_owned'] and new_meta['preview_owned']
    assert old_meta['map_attrs'] == new_meta['map_attrs']
    assert set(after)-set(before) == ADDITIONS, 'Unexpected added objects'
    assert all(after[p]['class']=='ModuleScript' for p in ADDITIONS)
    expected_attrs = old_meta['overview_attrs'] | {
        'OverviewApproximation': {'type':'boolean','value':'true'},
        'OverviewPlantScale': {'type':'number','value':'1'},
    }
    assert new_meta['overview_attrs'] == expected_attrs, 'Unexpected overview attributes'
    mapping = {}
    def walk(node, prefix=None):
        path = '' if prefix is None else (prefix+'/'+node['name'] if prefix else node['name'])
        files = [f for f in node.get('filePaths',[]) if f.startswith('src/')]
        if files: mapping[path] = files[0]
        for child in node.get('children',[]): walk(child,path)
    walk(json.loads((ROOT/'build/sourcemap.json').read_text()))
    sources = {p:v['properties']['Source'][1] for p,v in after.items() if 'Source' in v['properties']}
    assert len(sources)==len(mapping)==20
    for path, source in sources.items():
        assert source.replace('\r\n','\n') == (ROOT/mapping[path]).read_text(encoding='utf-8').replace('\r\n','\n'), path
    permitted, unexpected = [], []
    for problem in report['problems']:
        path, prop = problem.get('path'), problem.get('property')
        if path == 'Workspace/Camera' and prop in {'CFrame','Focus'}:
            permitted.append(problem | {'reason':'editor_view_only'})
        elif path == OVERVIEW and prop == 'AttributesSerialize':
            permitted.append(problem | {'reason':'exact_guarded_overview_annotations'})
        elif path and path.startswith(OVERVIEW+'/') and prop == 'size':
            assert before[path]['class'] == after[path]['class'] == 'MeshPart'
            old, new = vector(before[path]['properties'][prop]), vector(after[path]['properties'][prop])
            assert abs(new['Y']-8)<0.0001 and abs(old['Y']-8)<0.001, path
            assert abs(old['X']/6-new['X'])<0.0001 and abs(old['Z']/6-new['Z'])<0.0001, path
            permitted.append(problem | {'reason':'remove_owned_xz_stretch'})
        else:
            unexpected.append(problem)
    assert len([p for p in permitted if p['reason']=='remove_owned_xz_stretch']) == 5524
    assert report['unknown_original_properties'] == report['unknown_candidate_properties']
    report['allowed_changes'] = permitted
    report['problems'] = unexpected
    report['passed'] = not unexpected
    report['known_dom_preserved'] = not unexpected
    report['matching_tested_sources'] = len(sources)
    report['scope'] = 'All author instances/properties preserved exactly, except 5524 verified Size normalizations, exact overview annotations and editor Camera pose; all 20 sources match src; raw Terrain exact.'
    return report

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('original',type=Path)
    parser.add_argument('candidate',type=Path)
    parser.add_argument('--report',type=Path,required=True)
    args = parser.parse_args()
    report = check(args.original.resolve(),args.candidate.resolve())
    args.report.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({k:report[k] for k in ['passed','original_sha256','candidate_sha256','original_instances','candidate_instances','compared_original_instances','matching_tested_sources','scope']}))
    raise SystemExit(0 if report['passed'] else 1)
