"""Build the offline Harvest Warden maize pack. Run with Blender background.

All modelling is original, deterministic geometry. No Roblox file/API is opened.
One Blender unit represents one Roblox stud; exports are Y-up. Foliage is
intentionally open, opaque, double-sided geometry, not transparent image cards.
"""
import hashlib
import json
import math
import random
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "harvest-warden"
EXPORT = OUT / "exports" / "corn"
PREVIEW = OUT / "previews"
TEXTURE = OUT / "textures" / "corn_leaf_dry.png"
SEED = 20261016
TAU = math.tau
for folder in (OUT, EXPORT, PREVIEW):
    folder.mkdir(parents=True, exist_ok=True)
assert TEXTURE.is_file(), f"The shared generated leaf texture is required: {TEXTURE}"

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.unit_settings.system = "NONE"
scene.unit_settings.scale_length = 1.0
scene["unit_contract"] = "One Blender unit = one Roblox stud. Asset import must retain numeric dimensions."
scene["pack_seed"] = SEED

image = bpy.data.images.load(str(TEXTURE), check_existing=True)
image.pack()
material = bpy.data.materials.new("Corn_DryLeaf_Shared")
material.use_nodes = True
material.diffuse_color = (0.48, 0.32, 0.13, 1)
nodes = material.node_tree.nodes
shader = nodes.get("Principled BSDF")
shader.inputs["Roughness"].default_value = 0.88
shader.inputs["Specular IOR Level"].default_value = 0.22
texture = nodes.new("ShaderNodeTexImage")
texture.name = "Shared_DryCorn_Texture"
texture.image = image
material.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
material.use_backface_culling = False


class Geometry:
    def __init__(self):
        self.vertices = []
        self.faces = []
        self.uvs = []
        self.components = {}

    def vertex(self, value):
        result = len(self.vertices)
        self.vertices.append(tuple(value))
        return result

    def face(self, values, uvs):
        self.faces.append(values)
        self.uvs.append(uvs)

    def tube(self, points, radii, sides, u=0.3, span=0.04, closed=True):
        start = len(self.vertices)
        points = [Vector(p) for p in points]
        rings = []
        for j, (point, radius) in enumerate(zip(points, radii)):
            tangent = (points[min(j + 1, len(points) - 1)] - points[max(0, j - 1)]).normalized()
            if abs(tangent.z) < 0.9:
                right = tangent.cross(Vector((0, 0, 1))).normalized()
            else:
                right = tangent.cross(Vector((0, 1, 0))).normalized()
            other = tangent.cross(right).normalized()
            ring = []
            for k in range(sides):
                angle = TAU * k / sides
                ring.append(self.vertex(point + radius * (right * math.cos(angle) + other * math.sin(angle))))
            rings.append(ring)
        for j in range(len(rings) - 1):
            for k in range(sides):
                nxt = (k + 1) % sides
                self.face((rings[j][k], rings[j][nxt], rings[j + 1][nxt], rings[j + 1][k]),
                          ((u + span*k/sides, j/(len(rings)-1)),
                           (u + span*(k+1)/sides, j/(len(rings)-1)),
                           (u + span*(k+1)/sides, (j+1)/(len(rings)-1)),
                           (u + span*k/sides, (j+1)/(len(rings)-1))))
        if closed:
            self.face(tuple(reversed(rings[0])), [(u, 0)] * sides)
            self.face(tuple(rings[-1]), [(u, 1)] * sides)
        return len(self.vertices) - start

    def leaf(self, base, angle, length, width, droop, twist, bend, segments, columns, phase, uv_u):
        base = Vector(base)

        def center_at(t):
            a = angle + bend * (0.20*t + 0.80*t*t)
            radial = Vector((math.cos(a), math.sin(a), 0))
            lateral = Vector((-math.sin(a), math.cos(a), 0))
            # A continuous arch with an increasingly hanging tip, rather than
            # two almost straight sides meeting at a sharp inverted V.
            center = base + radial * (length * (1.08*t - 0.18*t*t))
            center.z += length * (0.69*math.sin(math.pi*t*0.92) - droop*t*t)
            center += lateral * (0.105*length*math.sin(math.pi*t)*math.sin(phase))
            return center

        grid = []
        for j in range(segments + 1):
            t = j / segments
            center = center_at(t)
            forward = (center_at(min(1,t+0.002)) - center_at(max(0,t-0.002))).normalized()
            lateral = Vector((-math.sin(angle+bend*t*t), math.cos(angle+bend*t*t), 0))
            lateral = (lateral-forward*lateral.dot(forward)).normalized()
            up = forward.cross(lateral).normalized()
            # Twist is strongest in the visible broad middle, not only in the
            # very narrow tip. The frame remains perpendicular to the curve.
            roll = twist * (0.12 + 0.88*math.sin(math.pi*t*0.91))
            cross = lateral*math.cos(roll) + up*math.sin(roll)
            normal = forward.cross(cross).normalized()
            breadth = width * (0.035 + 0.965*max(0, math.sin(math.pi*t))**0.70) * (1 - 0.10*t)
            if j == segments:
                breadth = 0.006
            row = []
            for k in range(columns + 1):
                v = k / columns * 2 - 1
                # W-shaped section: raised central rib, folded gutters, rolled rims.
                crease = breadth*(0.13*(1-abs(v)) + 0.28*abs(v)**3)
                crinkle = breadth*0.035*abs(v)*math.sin(t*TAU*2.0 + phase)
                position = center + cross*(v*breadth/2) + normal*(crease + crinkle)
                row.append(self.vertex(position))
            grid.append(row)
        for j in range(segments):
            for k in range(columns):
                self.face((grid[j][k], grid[j+1][k], grid[j+1][k+1], grid[j][k+1]),
                          ((uv_u + k/columns*0.055, j/segments*0.94),
                           (uv_u + k/columns*0.055, (j+1)/segments*0.94),
                           (uv_u + (k+1)/columns*0.055, (j+1)/segments*0.94),
                           (uv_u + (k+1)/columns*0.055, j/segments*0.94)))


VARIANTS = {
    "A": {"label": "Upright / alternating long leaves", "count": 9, "lean": (0.12, -0.14), "width": 3.16, "twist": 0.38, "droop": 0.57, "angle": 0.2},
    "B": {"label": "Crooked / broad hanging leaves", "count": 10, "lean": (0.38, 0.10), "width": 3.35, "twist": -0.74, "droop": 0.70, "angle": 1.0},
    "C": {"label": "Wind-bent / narrow curled leaves", "count": 9, "lean": (-0.34, 0.30), "width": 3.08, "twist": 0.98, "droop": 0.63, "angle": 2.25},
    "D": {"label": "Forked silhouette / splayed leaves", "count": 10, "lean": (-0.12, -0.38), "width": 3.35, "twist": -0.54, "droop": 0.52, "angle": -0.6},
}


def stem_at(z, cfg):
    a, b = cfg["lean"]
    t = z / 7.25
    return Vector((a*t*t + 0.07*math.sin(t*4)*t, b*t*t, z))


def make_plant(variant, lod):
    cfg = VARIANTS[variant]
    rng = random.Random(SEED + ord(variant)*971)
    g = Geometry()
    near = lod == "Near"
    middle = lod == "Mid"
    stem_rings, stem_sides = (9, 6) if near else ((6, 5) if middle else (4, 3))
    heights = [7.18*i/(stem_rings-1) for i in range(stem_rings)]
    g.tube([stem_at(z, cfg) for z in heights], [0.078*(1-z/8.1)+0.014 for z in heights], stem_sides, u=0.12)
    leaves = []
    for i in range(cfg["count"]):
        z = 0.95 + i*0.60 + rng.uniform(-0.08, 0.08)
        angle = cfg["angle"] + i*2.40 + rng.uniform(-0.32, 0.32)
        length = (1.64 + 0.50*math.sin((i+1)/(cfg["count"]+1)*math.pi)) * rng.uniform(0.91, 1.08)
        width = rng.uniform(0.34, 0.48) * (1 - 0.19*i/cfg["count"])
        droop = cfg["droop"] + rng.uniform(-0.09, 0.09)
        # Lower leaves do not penetrate the ground even before normalization.
        droop = min(droop, 0.69*math.sin(math.pi*0.92) + (z-0.18)/length)
        twist = cfg["twist"]+rng.uniform(-0.35,0.35)
        if i%3 == 1:
            twist *= 1.55
        bend = rng.uniform(-0.58,0.58)
        leaves.append((z, angle, length, width, droop, twist, bend, rng.random()*TAU, 0.04 + rng.random()*0.84))
    indices = list(range(cfg["count"])) if near else ([0, 2, 4, 6, cfg["count"]-1] if middle else [0, cfg["count"]//2, cfg["count"]-2])
    for i in indices:
        z, a, length, width, droop, twist, bend, phase, uv = leaves[i]
        if near:
            # Raised collars at alternating leaf nodes are actual mesh geometry.
            radius = (0.078*(1-z/8.1)+0.014)*1.22
            g.tube([stem_at(z-0.025,cfg), stem_at(z+0.025,cfg)], [radius,radius], 4, u=0.18, span=0.035)
        g.leaf(stem_at(z, cfg), a, length, width, droop, twist, bend,
               10 if near else (4 if middle else 3), 4 if near else 2, phase, uv)
    # Husk-covered ears, each separate from the stalk and visibly pointed upward.
    cob_count = 2 if near else 1
    for c in range(cob_count):
        z = 3.20 + c*1.38 + (ord(variant)-65)*0.10
        angle = cfg["angle"] + 0.60 + c*2.8
        direction = Vector((math.cos(angle), math.sin(angle), 0))
        base = stem_at(z, cfg) + direction*0.16
        rings, sides = (5, 8) if near else ((3, 6) if middle else (2, 4))
        axis = direction*0.28 + Vector((0, 0, 1.0))
        points = [base + axis*(j/(rings-1)) for j in range(rings)]
        radii = [0.038 + 0.080*math.sin(math.pi*j/(rings-1))**0.6 for j in range(rings)]
        g.tube(points, radii, sides, u=0.62, span=0.035)
        if lod != "Far":
            for h in range(3 if near else 2):
                g.leaf(base+axis*0.08, angle+h*2.1, 1.02, 0.17, -0.05,
                       0.74+h*0.18, 0.22,
                       7 if near else 3, 2, h, 0.28+h*0.08)
    # Actual branching tassel geometry, including the tall central spike.
    top = stem_at(7.05, cfg)
    branch_count = 8 if near else (5 if middle else 3)
    for j in range(branch_count):
        angle = cfg["angle"] + j*2.4
        distance = 0.19 + (j%3)*0.045
        branch_base = top + Vector((0, 0, 0.15 + j/branch_count*0.35))
        tip = branch_base + Vector((math.cos(angle)*distance, math.sin(angle)*distance, 0.30 + (j%2)*0.10))
        if lod == "Far":
            g.tube([branch_base,tip], [0.023,0.006], 3, u=0.46, span=0.02)
        else:
            g.tube([branch_base, (branch_base+tip)/2 + Vector((0,0,0.04)), tip], [0.023,0.017,0.006], 3, u=0.46, span=0.02)
    if lod == "Far":
        g.tube([top,Vector((top.x,top.y,8))],[0.030,0.004],3,u=0.48,span=0.02)
    else:
        g.tube([top, top+Vector((0,0,0.55)), Vector((top.x,top.y,8))], [0.030,0.017,0.004], 3, u=0.48, span=0.02)
    low_z = min(p[2] for p in g.vertices)
    high_z = max(p[2] for p in g.vertices)
    width = max(max(p[axis] for p in g.vertices)-min(p[axis] for p in g.vertices) for axis in (0,1))
    g.vertices = [(x*cfg["width"]/width, y*cfg["width"]/width, (z-low_z)*8/(high_z-low_z)) for x,y,z in g.vertices]
    name = f"Corn_{variant}_{lod}"
    mesh = bpy.data.meshes.new(name+"_Mesh")
    mesh.from_pydata(g.vertices, [], g.faces)
    mesh.update()
    layer = mesh.uv_layers.new(name="UVMap")
    for polygon, face_uvs in zip(mesh.polygons, g.uvs):
        for loop, uv in zip(polygon.loop_indices, face_uvs):
            layer.data[loop].uv = uv
        polygon.use_smooth = True
    mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    obj["roblox_height_studs"] = 8.0
    obj["roblox_double_sided"] = True
    obj["roblox_collision"] = "None: Anchored=true, CanCollide/CanTouch/CanQuery=false"
    obj["foliage_topology"] = "Opaque open curved leaf surfaces; render DoubleSided=true"
    obj["variant_description"] = cfg["label"]
    obj["lod"] = lod
    return obj


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def export_asset(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.hide_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    folder = EXPORT / obj.name
    folder.mkdir(exist_ok=True)
    fbx = folder / (obj.name+".fbx")
    glb = folder / (obj.name+".glb")
    bpy.ops.export_scene.fbx(filepath=str(fbx), use_selection=True, object_types={"MESH"},
                             global_scale=1.0, apply_unit_scale=False, apply_scale_options="FBX_SCALE_ALL",
                             axis_forward="-Z", axis_up="Y", bake_space_transform=True,
                             use_mesh_modifiers=True, use_triangles=True, mesh_smooth_type="FACE",
                             path_mode="COPY", embed_textures=True, add_leaf_bones=False,
                             bake_anim=False, use_custom_props=True)
    bpy.ops.export_scene.gltf(filepath=str(glb), export_format="GLB", use_selection=True,
                              export_yup=True, export_materials="EXPORT", export_extras=True)
    mesh = obj.data
    mesh.calc_loop_triangles()
    vertices = [[float(v.co.x),float(v.co.z),float(-v.co.y)] for v in mesh.vertices]
    uv_data = mesh.uv_layers.active.data
    corners, triangles = [], []
    for triangle in mesh.loop_triangles:
        corner_indices = []
        for loop_index, vertex in zip(triangle.loops, triangle.vertices):
            uv = uv_data[loop_index].uv
            normal = mesh.corner_normals[loop_index].vector
            corner_indices.append(len(corners)+1)
            corners.append({"vertex":int(vertex)+1, "uv":[float(uv.x),float(uv.y)],
                            "normal":[float(normal.x),float(normal.z),float(-normal.y)]})
        triangles.append(corner_indices)
    assert all(math.isfinite(n) for v in vertices for n in v)
    assert all(math.isfinite(n) for c in corners for n in c["uv"]+c["normal"])
    assert all(0 <= n <= 1 for c in corners for n in c["uv"])
    assert all(sum(n*n for n in c["normal"]) > 0.99 for c in corners)
    bad_area = sum(1 for t in mesh.loop_triangles if t.area < 1e-10)
    assert bad_area == 0, f"Degenerate triangles in {obj.name}: {bad_area}"
    bounds = {"min":[min(v[a] for v in vertices) for a in range(3)],
              "max":[max(v[a] for v in vertices) for a in range(3)]}
    size = [b-a for a,b in zip(bounds["min"],bounds["max"])]
    limit = 1800 if obj["lod"] == "Near" else (350 if obj["lod"] == "Mid" else 120)
    assert len(triangles) <= limit, (obj.name,len(triangles),limit)
    assert abs(size[1]-8) < 1e-5 and max(size[0],size[2]) <= 3.5
    neutral = {"schema":"harvest-corn-neutral-v1", "name":obj.name, "units":"Roblox studs",
               "coordinate_system":"right-handed Y-up; Blender(x,y,z) -> Roblox(x,z,-y)",
               "index_base":1, "origin":[0,0,0], "pivot":"stalk base on ground",
               "double_sided":True, "alpha_cards":False,
               "texture":"../../../textures/corn_leaf_dry.png", "positions":vertices,
               "corners":corners, "triangles":triangles, "bounds":bounds}
    neutral_path = folder / (obj.name+".neutral.json")
    neutral_path.write_text(json.dumps(neutral, separators=(",",":")), encoding="utf-8")
    return {"name":obj.name, "lod":obj["lod"], "vertices":len(vertices), "triangles":len(triangles),
            "bounds_y_up":bounds, "size_studs":size,
            "validation":{"finite_positions_uv_normals":True,"unit_normals":True,"degenerate_triangles":0,
                          "uv_in_unit_square":True,"root_ground_y":bounds["min"][1],
                          "open_leaf_surfaces_intentional":True,"render_double_sided":True},
            "files":[{"path":p.relative_to(OUT).as_posix(),"bytes":p.stat().st_size,"sha256":sha(p)} for p in (fbx,glb,neutral_path)]}


assets = []
objects = {}
for variant in VARIANTS:
    collection = bpy.data.collections.new("Corn_"+variant+"_Assets")
    scene.collection.children.link(collection)
    for lod in ("Near","Mid","Far"):
        obj = make_plant(variant,lod)
        collection.objects.link(obj)
        objects[(variant,lod)] = obj
        assets.append(export_asset(obj))
        obj.hide_render = True
        obj.hide_set(True)

# Gallery uses copies, leaving export assets and their root origins untouched.
gallery = bpy.data.collections.new("Corn_Preview_Gallery")
scene.collection.children.link(gallery)
for index, variant in enumerate(VARIANTS):
    obj = objects[(variant,"Near")].copy()
    obj.data = obj.data.copy()
    obj.name = "Gallery_"+variant
    gallery.objects.link(obj)
    obj.hide_set(False)
    obj.hide_render = False
    obj.location = ((index-1.5)*4.1,0,0)
    obj.rotation_euler.z = (0.0,-0.25,0.35,-0.25)[index]


def plain_material(name,color,roughness=0.8):
    result=bpy.data.materials.new(name)
    result.use_nodes=True
    p=result.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value=(*color,1)
    p.inputs["Roughness"].default_value=roughness
    return result


bpy.ops.mesh.primitive_plane_add(size=200, location=(0,0,-0.025))
floor=bpy.context.object
floor.name="Gallery_Charcoal_Floor"
floor.data.materials.append(plain_material("Gallery_DarkGray",(0.045,0.052,0.060)))
world=bpy.data.worlds.new("Corn_Gallery_World")
world.use_nodes=True
world.node_tree.nodes["Background"].inputs[0].default_value=(0.07,0.085,0.11,1)
world.node_tree.nodes["Background"].inputs[1].default_value=0.35
scene.world=world


def point_at(obj,point):
    obj.rotation_euler=(Vector(point)-obj.location).to_track_quat("-Z","Y").to_euler()


def area(name,at,energy,color,size):
    data=bpy.data.lights.new(name,"AREA")
    data.energy=energy
    data.color=color
    data.shape="DISK"
    data.size=size
    obj=bpy.data.objects.new(name,data)
    scene.collection.objects.link(obj)
    obj.location=at
    point_at(obj,(0,0,4))


area("Gallery_Key",(-6,-8,13),1750,(1.0,0.83,0.62),8)
area("Gallery_Fill",(9,-3,9),1200,(0.68,0.80,1.0),7)
area("Gallery_Rim",(0,6,13),2400,(1.0,0.73,0.39),6)
camera_data=bpy.data.cameras.new("Corn_Gallery_Camera")
camera=bpy.data.objects.new("Corn_Gallery_Camera",camera_data)
scene.collection.objects.link(camera)
camera.location=(8,-25,13)
point_at(camera,(0,0,3.9))
camera_data.type="ORTHO"
camera_data.ortho_scale=19.7
camera_data.lens=50
scene.camera=camera
scene.render.engine="BLENDER_EEVEE"
scene.render.resolution_x=1800
scene.render.resolution_y=1150
scene.render.resolution_percentage=100
scene.render.image_settings.file_format="PNG"
scene.render.film_transparent=False
scene.render.image_settings.color_mode="RGBA"
scene.view_settings.view_transform="AgX"
scene.render.filepath=str(PREVIEW/"corn-gallery.png")
bpy.ops.render.render(write_still=True)

# Close-up of an actual asset, including leaf folds and covered cobs.
for obj in gallery.objects:
    obj.hide_render=obj.name!="Gallery_B"
subject=gallery.objects.get("Gallery_B")
camera.location=subject.location+Vector((4,-8,5))
point_at(camera,subject.location+Vector((0,0,4.1)))
camera_data.ortho_scale=8.8
scene.render.resolution_x=1200
scene.render.resolution_y=1400
scene.render.filepath=str(PREVIEW/"corn-detail.png")
bpy.ops.render.render(write_still=True)
for obj in gallery.objects:
    obj.hide_render=False
camera.location=(8,-25,13)
point_at(camera,(0,0,3.9))
camera_data.ortho_scale=19.7
scene.render.resolution_x=1800
scene.render.resolution_y=1150
scene.render.filepath=str(PREVIEW/"corn-gallery.png")

bpy.ops.object.select_all(action="DESELECT")
blend=OUT/"corn.blend"
image.filepath="//textures/corn_leaf_dry.png"
scene.render.filepath="//previews/corn-gallery.png"
scene.render.use_file_extension=True
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(blend))
manifest={"schema":"harvest-corn-pack-v1","seed":SEED,"generator":"scripts/blender/harvest_corn.py",
          "blender_version":bpy.app.version_string,"status":"offline authored and rendered; NOT imported or Studio tested",
          "units":{"blender_unit":"one Roblox stud","height":8,"axes":"Y-up exports; Blender Z-up source"},
          "materials":{"shared_texture":"textures/corn_leaf_dry.png","texture_sha256":sha(TEXTURE),
                       "texture_is_real_bitmap":True,"opacity":1,"roblox_double_sided_required":True},
          "variants":VARIANTS,"assets":assets,
          "blend":{"path":"corn.blend","bytes":blend.stat().st_size,"sha256":sha(blend)},
          "previews":[{"path":p.relative_to(OUT).as_posix(),"sha256":sha(p)} for p in (PREVIEW/"corn-gallery.png",PREVIEW/"corn-detail.png")],
          "integration_notes":["Requires explicit versioned corn template catalog; existing game accepts only original mesh ID.",
                               "Use Near locally and simplified LODs at distance. Triangle budgets are not a Roblox FPS result.",
                               "Leaves are opaque folded 3D surfaces; set DoubleSided=true. No transparency maps are required.",
                               "Do not replace existing green source or overwrite existing corn atlas.",
                               "Single joined mesh per plant, with UVs and shared real leaf texture embedded in FBX and GLB."]}
(OUT/"corn-manifest.json").write_text(json.dumps(manifest,indent=2),encoding="utf-8")
print("CORN_PACK_SUCCESS",json.dumps({"assets":len(assets),"triangles":{a["name"]:a["triangles"] for a in assets},"blend":str(blend)}))
