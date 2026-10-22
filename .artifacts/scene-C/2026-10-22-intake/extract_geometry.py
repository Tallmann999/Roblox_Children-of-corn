"""Read imported mesh arrays into JSON; no mesh or source-file modifications."""
import hashlib
import json
from pathlib import Path
import bpy

OUT = Path(__file__).resolve().parent
intake = json.loads((OUT / 'intake-report.json').read_text(encoding='utf-8'))
result = dict(coordinates='world metres, +Z up (Blender importer); right-handed',
              faces='triangles; zero-based vertex indices; UV and normals are per triangle corner',
              notes='Read-only extraction. No welding, unwrap, transform application, normals recalculation, asset upload, or FBX export.',
              assets=[])
for asset in intake['assets']:
    source = Path(asset['source'])
    sha = hashlib.sha256(source.read_bytes()).hexdigest()
    assert sha == asset['sha256']
    bpy.ops.wm.read_factory_settings(use_empty=True)
    assert bpy.ops.import_scene.fbx(filepath=str(source), use_image_search=False) == {'FINISHED'}
    bpy.context.view_layer.update()
    for ob in bpy.context.scene.objects:
        if ob.type != 'MESH': continue
        me = ob.data
        me.calc_loop_triangles()
        uv = me.uv_layers.active.data if me.uv_layers.active else None
        cn = me.corner_normals
        nm = ob.matrix_world.to_3x3().inverted().transposed()
        data = dict(name=ob.name, source=str(source), source_sha256=sha,
                    vertices=[list(ob.matrix_world @ v.co) for v in me.vertices], triangles=[])
        for tri in me.loop_triangles:
            data['triangles'].append(dict(vertices=list(tri.vertices),
                uv=[list(uv[i].uv) for i in tri.loops] if uv else None,
                normals=[list((nm @ cn[i].vector).normalized()) for i in tri.loops],
                material_index=tri.material_index))
        data['palette_uv_faces'] = sum(len({tuple(uv[i].uv) for i in p.loop_indices}) == 1
                                       for p in me.polygons) if uv else 0
        data['polygon_count'] = len(me.polygons)
        result['assets'].append(data)
    assert hashlib.sha256(source.read_bytes()).hexdigest() == sha
(OUT/'mesh-arrays.json').write_text(json.dumps(result, ensure_ascii=False, separators=(',',':')),encoding='utf-8')
print('@@JSON@@'+json.dumps(dict(path=str(OUT/'mesh-arrays.json'), assets=[dict(name=a['name'], tris=len(a['triangles']), palette_uv_faces=a['palette_uv_faces'], polygon_count=a['polygon_count']) for a in result['assets']])))
