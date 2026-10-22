"""Read-only intake of the five user-supplied FBX assets in a factory Blender process.

Source files are never saved, overwritten, exported, or modified. Images rendered
under this directory are diagnostic previews of imported geometry only.
"""
import hashlib
import json
import os
import sys
from pathlib import Path

import bpy
from mathutils import Vector

OUT = Path(__file__).resolve().parent
BASE = Path(r"D:\ROBLOX\CrazeEfGG\Assets\Sort_main_ferm")
SOURCES = [
    BASE / "трава/SM_Generic_Grass_Patch_01.fbx",
    BASE / "грядка/SM_Env_Dirt_Rows_Center_01.fbx",
    BASE / "грядка/SM_Env_Dirt_Rows_End_Top_01.fbx",
    BASE / "грядка/SM_Env_Dirt_Skirt_01.fbx",
    BASE / "растения/SM_Prop_Plant_Corn_01_L.fbx",
]
sys.path.insert(0, r"C:\Users\User\.codex\skills\blender-asset-qa\scripts")
import qa_check
import review_shots


def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def image_info(im):
    p = Path(bpy.path.abspath(im.filepath)) if im.filepath else None
    return dict(name=im.name, filepath=im.filepath, filepath_resolved=str(p) if p else None,
                exists=bool(p and p.is_file()), packed=bool(im.packed_file),
                source=im.source, size=list(im.size), channels=im.channels,
                alpha_mode=im.alpha_mode, colorspace=im.colorspace_settings.name)


def material_info(mat):
    result = dict(name=mat.name, diffuse_color=list(mat.diffuse_color),
                  use_nodes=mat.use_nodes, surface_render_method=mat.surface_render_method,
                  use_backface_culling=mat.use_backface_culling)
    if mat.node_tree:
        result['nodes'] = []
        for n in mat.node_tree.nodes:
            item = dict(type=n.type, name=n.name)
            if n.type == 'TEX_IMAGE':
                item['image'] = image_info(n.image) if n.image else None
            if n.type == 'BSDF_PRINCIPLED':
                item['inputs'] = {k: list(n.inputs[k].default_value) if k == 'Base Color'
                                  else n.inputs[k].default_value for k in ['Base Color','Metallic','Roughness','Alpha']}
            result['nodes'].append(item)
        result['links'] = [dict(from_node=l.from_node.type, from_socket=l.from_socket.name,
                                to_node=l.to_node.type, to_socket=l.to_socket.name)
                           for l in mat.node_tree.links]
    return result


def object_info(ob):
    result = dict(name=ob.name, type=ob.type, parent=ob.parent.name if ob.parent else None,
                  location=list(ob.location), rotation_euler=list(ob.rotation_euler),
                  scale=list(ob.scale), dimensions=list(ob.dimensions),
                  matrix_world=[list(row) for row in ob.matrix_world])
    if ob.type != 'MESH':
        return result
    me = ob.data
    me.calc_loop_triangles()
    pts = [ob.matrix_world @ v.co for v in me.vertices]
    result.update(vertices=len(me.vertices), edges=len(me.edges), faces=len(me.polygons),
                  triangles=len(me.loop_triangles),
                  bounds_min=[min(p[i] for p in pts) for i in range(3)],
                  bounds_max=[max(p[i] for p in pts) for i in range(3)],
                  material_slots=[mat.name if mat else None for mat in me.materials],
                  material_face_counts={str(i): sum(p.material_index == i for p in me.polygons)
                                        for i in range(len(me.materials))},
                  uv_maps=[dict(name=uv.name, count=len(uv.data),
                                minimum=[min(x.uv[i] for x in uv.data) for i in (0,1)],
                                maximum=[max(x.uv[i] for x in uv.data) for i in (0,1)])
                           for uv in me.uv_layers],
                  vertex_color_attributes=[a.name for a in me.color_attributes],
                  modifiers=[dict(name=m.name, type=m.type) for m in ob.modifiers])
    return result


report = dict(blender=bpy.app.version_string, scope="five exact FBX files; no source writes or exports",
              coordinate_system="Blender importer defaults: 1 unit = 1 metre, +Z up; root transforms retained",
              assets=[])
for source in SOURCES:
    before = digest(source)
    # Only this fresh private background process is reset, never a user session.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    status = bpy.ops.import_scene.fbx(filepath=str(source), use_image_search=False)
    bpy.context.view_layer.update()
    objects = list(bpy.context.scene.objects)
    meshes = [o.name for o in objects if o.type == 'MESH']
    item = dict(source=str(source), file_size=source.stat().st_size, sha256=before,
                import_status=sorted(status), objects=[object_info(o) for o in objects],
                materials=[material_info(m) for m in bpy.data.materials],
                images=[image_info(i) for i in bpy.data.images],
                qa=qa_check.run(objects=meshes, profile='roblox', no_modifiers=True))
    # Diagnostic views only. No .blend or FBX is written.
    item['solid_preview'] = review_shots.run(objects=meshes,
        out=str(OUT / (source.stem + '_solid.png')),
        views=['front','right','top','three_quarter'], mode='solid', res=384)
    item['wire_preview'] = review_shots.run(objects=meshes,
        out=str(OUT / (source.stem + '_wire.png')),
        views=['top','three_quarter'], mode='wire', res=384)
    item['source_unchanged'] = digest(source) == before
    report['assets'].append(item)
    (OUT / 'intake-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print('@@ASSET@@' + json.dumps(dict(source=source.name,
          objects=len(objects), tris=sum(o['triangles'] for o in item['objects'] if o['type']=='MESH'),
          dims=[o['dimensions'] for o in item['objects'] if o['type']=='MESH'],
          materials=[m['name'] for m in item['materials']],
          qa_pass=item['qa']['pass'], qa_errors=item['qa']['errors']), ensure_ascii=False))

textures = []
for p in sorted((BASE/'Textures').iterdir()):
    if p.suffix.lower() in ('.png','.tga','.jpg','.jpeg'):
        im = bpy.data.images.load(str(p), check_existing=True)
        info = image_info(im)
        info.update(file_size=p.stat().st_size, sha256=digest(p))
        textures.append(info)
        bpy.data.images.remove(im)
report['bounded_sibling_texture_inventory'] = textures
report['total_mesh_triangles_single_copy_each'] = sum(o['triangles'] for a in report['assets'] for o in a['objects'] if o['type']=='MESH')
report['all_source_hashes_unchanged'] = all(digest(p)==a['sha256'] for p,a in zip(SOURCES,report['assets']))
(OUT / 'intake-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print('@@JSON@@' + json.dumps(dict(report=str(OUT/'intake-report.json'), total_tris=report['total_mesh_triangles_single_copy_each'], source_unchanged=report['all_source_hashes_unchanged'])))
