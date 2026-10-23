"""Render the frozen green palette on the original and three shape variants.
Only this private Blender process changes placement/light/camera; no blend save.
"""
import bpy, json, math
from pathlib import Path
from mathutils import Vector

OUT=Path(__file__).resolve().parent
names=["SM_Prop_Plant_Corn_01_L"]+["SM_Prop_Plant_Corn_01_L_Var_%02d"%i for i in range(1,4)]
scene=bpy.context.scene
scene.render.engine="BLENDER_EEVEE"
scene.render.resolution_x=1400
scene.render.resolution_y=700
scene.render.resolution_percentage=100
scene.render.image_settings.file_format="PNG"
scene.render.image_settings.color_mode="RGBA"
scene.render.film_transparent=False
scene.view_settings.view_transform="AgX"
scene.world=bpy.data.worlds.new("CornVariantsReviewWorld")
scene.world.color=(0.13,0.13,0.13)
background=scene.world.node_tree.nodes.get("Background")
if background:background.inputs["Color"].default_value=(0.20,0.23,0.28,1);background.inputs["Strength"].default_value=0.5
for index,name in enumerate(names):
    ob=bpy.data.objects[name];ob.location.x=index*1.6
    text=bpy.data.curves.new("VariantLabel_%d"%index,"FONT")
    text.body=["Original","01: Curved stalk","02: Broad leaves","03: Twisted canopy"][index]
    text.align_x="CENTER";text.size=0.12;text.extrude=0
    label=bpy.data.objects.new(text.name,text);scene.collection.objects.link(label)
    label.location=(index*1.6,-0.72,0.02);label.rotation_euler=(math.pi/2,0,0)
    labelmat=bpy.data.materials.new("LabelInk_%d"%index)
    emission=labelmat.node_tree.nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value=(0.8,0.9,1,1)
    labelmat.node_tree.links.new(emission.outputs[0],next(n for n in labelmat.node_tree.nodes if n.type=="OUTPUT_MATERIAL").inputs["Surface"])
    text.materials.append(labelmat)
floorMesh=bpy.data.meshes.new("ReviewFloor")
floorMesh.from_pydata([(-2,-2,-0.015),(7,-2,-0.015),(7,2,-0.015),(-2,2,-0.015)],[],[(0,1,2,3)])
floor=bpy.data.objects.new("ReviewFloor",floorMesh);scene.collection.objects.link(floor)
floorMat=bpy.data.materials.new("ReviewFloor_M");floorMat.diffuse_color=(0.055,0.063,0.075,1)
next(n for n in floorMat.node_tree.nodes if n.type=="BSDF_PRINCIPLED").inputs["Base Color"].default_value=floorMat.diffuse_color
floorMesh.materials.append(floorMat)
for name,where,energy,size in [("Key",(0,-4,6),1200,5),("Fill",(6,2,4),750,4)]:
    light=bpy.data.lights.new(name,"AREA");light.energy=energy;light.shape="DISK";light.size=size
    ob=bpy.data.objects.new(name,light);scene.collection.objects.link(ob);ob.location=where
    ob.rotation_euler=(Vector((2.4,0,1.0))-ob.location).to_track_quat("-Z","Y").to_euler()
camera=bpy.data.cameras.new("ReviewCamera");camera.type="ORTHO";camera.ortho_scale=7.0
ob=bpy.data.objects.new(camera.name,camera);scene.collection.objects.link(ob);scene.camera=ob
ob.location=(3.6,-10,3.4);ob.rotation_euler=(Vector((2.4,0,1.05))-ob.location).to_track_quat("-Z","Y").to_euler()
scene.render.filepath=str(OUT/"green-variants-textured-comparison.png")
bpy.ops.render.render(write_still=True)
print("@@JSON@@"+json.dumps({"image":scene.render.filepath,"source_blend_unchanged":True,"palette_color_only":True}))
