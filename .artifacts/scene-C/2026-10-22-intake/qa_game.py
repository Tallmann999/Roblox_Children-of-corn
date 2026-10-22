"""Run unchanged-source profile=game QA and classify source-preservation findings."""
import hashlib
import json
from pathlib import Path
import sys
import bpy

OUT=Path(__file__).resolve().parent
sys.path.insert(0,r'C:\Users\User\.codex\skills\blender-asset-qa\scripts')
import qa_check
inventory=json.loads((OUT/'intake-report.json').read_text(encoding='utf-8'))
result=dict(profile='game', scope='exact original supplied FBX geometry, no source repair or normalization',
            all_raw_qa_pass=False, assets=[])
for a in inventory['assets']:
    p=Path(a['source'])
    sha=hashlib.sha256(p.read_bytes()).hexdigest()
    assert sha==a['sha256']
    bpy.ops.wm.read_factory_settings(use_empty=True)
    assert bpy.ops.import_scene.fbx(filepath=str(p),use_image_search=False)=={'FINISHED'}
    bpy.context.view_layer.update()
    names=[o.name for o in bpy.context.scene.objects if o.type=='MESH']
    raw=qa_check.run(objects=names,profile='game',no_modifiers=True)
    classifications=[]
    for failure in raw['errors']:
        if 'unapplied scale' in failure:
            classifications.append(dict(finding=failure,disposition='source-preservation exception for imported FBX only',reason='FBX centimetre-to-metre scale .01; read-only mesh arrays already contain transformed world points. Reconstructed native mesh uses these points and unit instance transform. Source FBX not rewritten.'))
        elif 'zero-area UV faces' in failure:
            classifications.append(dict(finding=failure,disposition='intentional palette lookup preserved',reason='Source uses collapsed/line UVs to sample flat atlas colors. Retain exact UV values; unwrap would change source look. RGB8 atlas has no alpha.'))
        elif failure.startswith('z-fighting:') and 'Grass' in failure:
            classifications.append(dict(finding=failure,disposition='original source overlap retained for this test',reason='Four coplanar triangle pairs in 3-blade grass patch, no duplicate vertices or faces/zero-area geometry, solid+wire preview inspected. Keep exact supplied mesh; native GPU appearance remains a separate check.'))
        else:
            classifications.append(dict(finding=failure,disposition='unresolved',reason='Requires review before delivery.'))
    for ob,metrics in raw['objects'].items():
        if metrics.get('boundary_edges'):
            classifications.append(dict(finding=f'{ob}: {metrics["boundary_edges"]} open boundary edges',disposition='original foliage/soil surface boundary retained',reason='Decorative source surface; no collision mesh, capping or welding. Use separate smooth ground collision; preserve source silhouette and UV.'))
    result['assets'].append(dict(source=str(p),source_sha256=sha,raw=raw,classifications=classifications,source_unchanged=hashlib.sha256(p.read_bytes()).hexdigest()==sha))
result['all_raw_qa_pass']=all(a['raw']['pass'] for a in result['assets'])
result['unclassified_failures']=[c for a in result['assets'] for c in a['classifications'] if c['disposition']=='unresolved']
result['all_sources_unchanged']=all(a['source_unchanged'] for a in result['assets'])
(OUT/'qa-game-preserving-source.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print('@@JSON@@'+json.dumps(dict(report=str(OUT/'qa-game-preserving-source.json'),all_raw_qa_pass=result['all_raw_qa_pass'],unclassified=result['unclassified_failures'],all_sources_unchanged=result['all_sources_unchanged'],counts=[dict(asset=Path(a['source']).name,errors=len(a['raw']['errors']),warnings=len(a['raw']['warnings'])) for a in result['assets']])))
