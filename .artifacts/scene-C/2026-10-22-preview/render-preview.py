"""Three offline Scene C preparation views from exact supplied FBX arrays/layout.

No live Studio, asset upload, source edits, .blend save or FBX export.
"""
import hashlib
import json
import math
import sys
from collections import Counter
from pathlib import Path

import bpy
from mathutils import Vector

OUT=Path(__file__).resolve().parent
ROOT=OUT.parents[2]
arrays_path=ROOT/'.artifacts/scene-C/2026-10-22-intake/mesh-arrays.json'
manifest_path=ROOT/'scene-c/data/manifest.json'
layout_path=ROOT/'scene-c/runtime/layout.json'
arrays=json.loads(arrays_path.read_text(encoding='utf-8'))
manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
layout=json.loads(layout_path.read_text(encoding='utf-8'))
scale=manifest['uniform_studs_per_metre']
sha=lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
assert sha(arrays_path)==manifest['intake_sha256']
assert len(layout['poses'])==368
report=dict(kind='offline preparation render; not native Studio acceptance',
    blender=bpy.app.version_string,layout_sha256=sha(layout_path),manifest_sha256=sha(manifest_path),
    arrays_sha256=sha(arrays_path),counts=dict(Counter(p['key'] for p in layout['poses'])),
    scale=scale,coordinates='Render world (x,-Roblox z,Roblox y); +Z up; units = Roblox studs.',
    exact_uv_preserved=True,corner_normals_preserved=True,triangle_winding_preserved=True,
    source_files_unchanged=True,outputs=[],templates=[])
sys.path.insert(0,r'C:\Users\User\.codex\skills\blender-asset-qa\scripts')
import qa_check

bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene
scene.render.engine='BLENDER_EEVEE'
scene.render.resolution_x=640
scene.render.resolution_y=400
scene.render.resolution_percentage=100
scene.render.image_settings.media_type='IMAGE'
scene.render.image_settings.file_format='PNG'
scene.render.image_settings.color_mode='RGB'
scene.render.film_transparent=False
if hasattr(scene.eevee,'taa_render_samples'): scene.eevee.taa_render_samples=32
if hasattr(scene.eevee,'use_raytracing'): scene.eevee.use_raytracing=False
scene.view_settings.view_transform='Khronos PBR Neutral'
scene.view_settings.exposure=0
scene.view_settings.gamma=1
scene.world=bpy.data.worlds.new('C_Preview_Daylight')
scene.world.use_nodes=True
background=next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND')
background.inputs['Color'].default_value=(0.40,0.58,0.77,1)
background.inputs['Strength'].default_value=.65

def texture_mat(name,path):
    material=bpy.data.materials.new(name)
    material.diffuse_color=(1,1,1,1)
    material.use_backface_culling=False
    shader=next(n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    shader.inputs['Base Color'].default_value=(1,1,1,1)
    shader.inputs['Roughness'].default_value=.95
    shader.inputs['Metallic'].default_value=0
    texture=material.node_tree.nodes.new('ShaderNodeTexImage')
    texture.image=bpy.data.images.load(str(path),check_existing=True)
    texture.image.colorspace_settings.name='sRGB'
    texture.interpolation='Linear'
    material.node_tree.links.new(texture.outputs['Color'],shader.inputs['Base Color'])
    return material

corn_path=ROOT/'assets/corn/01_roblax_style.png'
farm_path=ROOT/'assets/farm/PolygonFarm_Texture_01_A.png'
materials={'Corn':texture_mat('White tint with exact Corn RGB atlas',corn_path),
           'Farm':texture_mat('White tint with exact Farm01A RGB atlas',farm_path)}
report['atlases']=[dict(path=str(p),sha256=sha(p)) for p in [corn_path,farm_path]]
meshes={}
for entry in manifest['assets']:
    source=next(a for a in arrays['assets'] if a['name']==entry['name'])
    assert source['source_sha256']==entry['source_sha256']==sha(source['source'])
    center_r=entry['source_center_studs']
    center_b=Vector((center_r[0],-center_r[2],center_r[1]))
    vertices=[tuple(Vector(v)*scale-center_b) for v in source['vertices']]
    mesh=bpy.data.meshes.new('C_'+entry['key']+'_ExactSource')
    mesh.from_pydata(vertices,[],[t['vertices'] for t in source['triangles']])
    mesh.update()
    uv=mesh.uv_layers.new(name='map1_exact_source')
    normals=[]
    for polygon,triangle in zip(mesh.polygons,source['triangles']):
        polygon.use_smooth=True
        for corner,loop_index in enumerate(polygon.loop_indices):
            uv.data[loop_index].uv=triangle['uv'][corner]
            normals.append(tuple(triangle['normals'][corner]))
    mesh.normals_split_custom_set(normals)
    mesh.materials.append(materials['Corn' if entry['key']=='Corn' else 'Farm'])
    meshes[entry['key']]=mesh
    probe=bpy.data.objects.new('QA_'+entry['key'],mesh)
    scene.collection.objects.link(probe)
    bpy.context.view_layer.update()
    qa=qa_check.run(objects=[probe.name],profile='game',no_modifiers=True)
    report['templates'].append(dict(key=entry['key'],source_sha256=entry['source_sha256'],
        vertices=len(vertices),triangles=len(mesh.polygons),qa_raw=qa,
        qa_interpretation='Unit scale now applied in read-only mesh-array representation. Palette-point/line UVs and original Grass intersections are retained intentionally; see intake qa-game-preserving-source.json. No source repair.'))
    bpy.data.objects.remove(probe,do_unlink=True)

for i,pose in enumerate(layout['poses']):
    ob=bpy.data.objects.new(f'C_{pose["key"]}_{i+1:03d}',meshes[pose['key']])
    scene.collection.objects.link(ob)
    x,y,z=pose['position']
    ob.location=(x,-z,y)
    ob.rotation_euler=(0,0,pose['yaw'])

# A simple flat render-only floor: same green and extent as the native layout.
floor_mesh=bpy.data.meshes.new('C_Ground_Surface')
half=layout['groundSize'][0]/2
floor_mesh.from_pydata([(-half,-half,.05),(half,-half,.05),(half,half,.05),(-half,half,.05)],[],[(0,1,2,3)])
floor_mesh.update()
floor=bpy.data.objects.new('C_Ground_Surface',floor_mesh)
scene.collection.objects.link(floor)
floor_mat=bpy.data.materials.new('C_Ground_91_112_59_sRGB')
floor_shader=next(n for n in floor_mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
linear=lambda c: c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4
floor_shader.inputs['Base Color'].default_value=tuple(linear(c/255) for c in [91,112,59])+(1,)
floor_shader.inputs['Roughness'].default_value=.95
floor_mesh.materials.append(floor_mat)

sun_data=bpy.data.lights.new('C_Daylight_Sun','SUN')
sun_data.energy=2.25
sun_data.angle=math.radians(3)
sun=bpy.data.objects.new('C_Daylight_Sun',sun_data)
scene.collection.objects.link(sun)
sun.rotation_euler=(math.radians(30),math.radians(-18),math.radians(-25))
fill_data=bpy.data.lights.new('C_Daylight_AmbientFill','AREA')
fill_data.energy=18000
fill_data.shape='DISK'
fill_data.size=80
fill=bpy.data.objects.new('C_Daylight_AmbientFill',fill_data)
scene.collection.objects.link(fill)
fill.location=(-18,-20,34)
fill.rotation_euler=(Vector((0,0,0))-fill.location).to_track_quat('-Z','Y').to_euler()

camera_data=bpy.data.cameras.new('C_Review_Camera')
camera_data.sensor_fit='HORIZONTAL'
camera_data.sensor_width=36
camera_data.clip_start=.05
camera_data.clip_end=500
camera=bpy.data.objects.new('C_Review_Camera',camera_data)
scene.collection.objects.link(camera)
scene.camera=camera
views=[dict(name='overview',position=(52,-65,38),target=(0,0,2.8),lens=32),
       dict(name='eye-through-path',position=(0,-35,5.3),target=(0,0,4.8),lens=16.1),
       dict(name='inside-corn',position=(10.7,-15,5.5),target=(10.7,0,5),lens=16.1)]
bpy.context.view_layer.update()
for view in views:
    camera.location=view['position']
    camera.rotation_euler=(Vector(view['target'])-camera.location).to_track_quat('-Z','Y').to_euler()
    camera_data.lens=view['lens']
    file=OUT/(view['name']+'.png')
    scene.render.filepath=str(file)
    assert bpy.ops.render.render(write_still=True)=={'FINISHED'}
    assert file.is_file() and file.stat().st_size>0
    report['outputs'].append(dict(**view,path=str(file),bytes=file.stat().st_size,sha256=sha(file)))
    print('@@VIEW@@'+json.dumps(dict(name=view['name'],bytes=file.stat().st_size)),flush=True)
report['all_source_files_unchanged']=all(sha(a['source'])==a['source_sha256'] for a in arrays['assets'])
assert report['all_source_files_unchanged']
(OUT/'preview-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('@@JSON@@'+json.dumps(dict(report=str(OUT/'preview-report.json'),outputs=report['outputs'])),flush=True)
