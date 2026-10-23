"""Create three independent original-corn shape variants in a private Blender process.
Original FBX/PNG are read-only; UVs, triangle topology and custom corner normals
are carried through smooth, positive-Jacobian shape maps. No asset publication.
"""
from __future__ import annotations
import hashlib, json, math, sys
from collections import Counter
from pathlib import Path

import bpy
from mathutils import Matrix, Vector
from mathutils.kdtree import KDTree
from itertools import permutations

ROOT = Path(r"D:\ROBLOX\My_Projects\Roblox_Children of Corn")
OUT = ROOT / ".artifacts/asset-variants/2026-10-23-green-corn"
SOURCE = Path(r"D:\ROBLOX\CrazeEfGG\Assets\Sort_main_ferm\растения\SM_Prop_Plant_Corn_01_L.fbx")
TEXTURE = ROOT / "assets/corn/01_roblax_style.png"
PIN = "259fbe167d4c0a24e6813282a5f3026d582b67d7af1f701bad39bed706a193df"
sys.path.insert(0, r"C:\Users\User\.codex\skills\blender-asset-qa\scripts")
import qa_check, review_shots
sys.path.insert(0, r"C:\Users\User\.codex\skills\blender-game-optimization\scripts")
import mesh_stats
sys.path.insert(0, r"C:\Users\User\.codex\skills\blender-export-pipelines\scripts")
import export_asset

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def save_json(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
def bounds(points):
    lo = Vector(tuple(min(p[i] for p in points) for i in range(3)))
    hi = Vector(tuple(max(p[i] for p in points) for i in range(3)))
    return lo, hi

OUT.mkdir(parents=True, exist_ok=True)
assert sha(SOURCE) == PIN, "Supplied FBX changed"
texture_before = sha(TEXTURE)
bpy.ops.wm.read_factory_settings(use_empty=True)  # This private factory process only.
bpy.context.scene.unit_settings.system = "METRIC"
bpy.context.scene.unit_settings.scale_length = 1.0
assert bpy.ops.import_scene.fbx(filepath=str(SOURCE), use_image_search=False) == {"FINISHED"}
bpy.context.view_layer.update()
imported = list(bpy.context.scene.objects)
meshes = [ob for ob in imported if ob.type == "MESH"]
assert len(meshes) == 1, "Source is no longer a single mesh"
original_ob = meshes[0]
original_ob.name = "ReadOnlyImportedOriginal"
source_mesh = original_ob.data
source_mesh.calc_loop_triangles()
world = original_ob.matrix_world.copy()
normal_matrix = world.to_3x3().inverted().transposed()
points = [world @ vertex.co for vertex in source_mesh.vertices]
lo, hi = bounds(points)
height = hi.z - lo.z
source_base = Vector((0, 0, lo.z))
base_points = [point - source_base for point in points]
triangles = [tuple(tri.vertices) for tri in source_mesh.loop_triangles]
loop_sources = [tuple(tri.loops) for tri in source_mesh.loop_triangles]
smooth = [source_mesh.polygons[tri.polygon_index].use_smooth for tri in source_mesh.loop_triangles]
normals_source = [(normal_matrix @ normal.vector).normalized() for normal in source_mesh.corner_normals]
uv_source = [tuple(loop.uv) for loop in source_mesh.uv_layers.active.data]
colors_source = {}
for attribute in source_mesh.color_attributes:
    if attribute.domain == "CORNER":
        colors_source[attribute.name] = [tuple(value.color) for value in attribute.data]
    elif attribute.domain == "POINT":
        colors_source[attribute.name] = [tuple(attribute.data[loop.vertex_index].color) for loop in source_mesh.loops]
assert len(points) == 377 and len(triangles) == 510, "Original topology changed"
assert len(uv_source) == len(source_mesh.loops)
imported_hash = sha(SOURCE)

# The three maps change the geometry with height; none is an object rotation.
def deform(point, variant):
    x, y, z = point
    t = z / height
    if variant == 0:
        return Vector((x, y, z))
    if variant == 1:  # Slender wind-bent stalk; upper canopy follows the curve.
        theta = math.radians(10) * t
        sx, sy = 0.94 + 0.06 * math.sin(math.pi*t), 0.96
        bx, by = 0.33*t*t, -0.09*t*t
        zz = z
    elif variant == 2:  # Broad middle leaves with a gentle outer-leaf droop.
        theta = math.radians(-7) * t*t
        sx, sy = 1.22 + 0.12*math.sin(math.pi*t), 1.12 + 0.07*math.sin(math.pi*t)
        bx, by = -0.04*t*t, 0.03*t*t
        zz = z - 0.12*(x*x+y*y)/height*math.sin(math.pi*t)**2
    else:  # Height-dependent spiral leaf arrangement and lifted leaf planes.
        theta = math.radians(72) * t*t
        sx, sy = 1.02, 1.02
        bx, by = -0.21*t*t, 0.14*t*t
        zz = z + 0.12*(x*math.sin(math.pi*t)-y*math.sin(2*math.pi*t))
    c, s = math.cos(theta), math.sin(theta)
    return Vector((c*sx*x-s*sy*y+bx, s*sx*x+c*sy*y+by, zz))

def jacobian(point, variant):
    eps = 1e-5
    columns = []
    for axis in range(3):
        step = Vector((0, 0, 0)); step[axis] = eps
        columns.append((deform(point+step, variant)-deform(point-step, variant))/(2*eps))
    return Matrix(columns).transposed()

image = bpy.data.images.load(str(TEXTURE), check_existing=True)
image.pack()
material = bpy.data.materials.new("M_Corn_Green_OriginalPalette")
material.diffuse_color = (0.19, 0.43, 0.10, 1)
material.use_backface_culling = False
nodes, links = material.node_tree.nodes, material.node_tree.links
principled = next(node for node in nodes if node.type == "BSDF_PRINCIPLED")
principled.inputs["Roughness"].default_value = 0.9
principled.inputs["Metallic"].default_value = 0.0
tex = nodes.new("ShaderNodeTexImage"); tex.image = image
links.new(tex.outputs["Color"], principled.inputs["Base Color"])
objects, report = [], {"blender": bpy.app.version_string, "source": str(SOURCE),
    "source_sha256": imported_hash, "texture_sha256": texture_before,
    "source_vertices": len(points), "source_triangles": len(triangles),
    "source_height_m": height, "source_base_world_m": list(source_base),
    "source_corner_color_ranges": {key: {"minimum": [min(row[i] for row in values) for i in range(4)],
        "maximum": [max(row[i] for row in values) for i in range(4)]} for key,values in colors_source.items()},
    "coordinate_system": "Blender metres +Z up, base (0,0,0); runtime [x,z,-y] scaled to 8 studs and bbox-centred",
    "runtime_data": [], "variants": [], "accepted_warnings": [
        "Source palette UVs intentionally collapse faces to palette texels/lines; UVs are preserved exactly, not unwrapped.",
        "Original thin foliage contains 218 open boundary edges. This topology is retained with DoubleSided runtime art and no physical mesh collision.",
        "Original FBX vertex color channel is preserved in blend/FBX and included as optional corner colors in runtime JSON. Palette material preview uses the green texture, matching C white-tint rendering."
        ,"Existing green atlas is 1254x1254, above the skill's 1024 guidance but below Roblox 4096 maximum. It is intentionally preserved byte-for-byte and shared by every instance."
    ]}
for variant in range(4):
    key = "Original" if variant == 0 else "Var%02d" % variant
    name = "SM_Prop_Plant_Corn_01_L" + ("" if variant == 0 else "_Var_%02d" % variant)
    changed = [deform(point, variant) for point in base_points]
    low, high = bounds(changed)
    assert abs(low.z) < 1e-6, "Shape map shifted the base"
    zscale = height / high.z
    changed = [Vector((p.x, p.y, p.z*zscale)) for p in changed]
    jacobians = [Matrix.Diagonal((1,1,zscale)) @ jacobian(point, variant) for point in base_points]
    minimum_det = min(matrix.determinant() for matrix in jacobians)
    assert minimum_det > 0.65, "Shape map folds or inverts source geometry"
    corner_normals = []
    for tri, loops in zip(triangles, loop_sources):
        for vertex, loop in zip(tri, loops):
            corner_normals.append((jacobians[vertex].inverted().transposed() @ normals_source[loop]).normalized())
    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(changed, [], triangles)
    mesh.materials.append(material)
    mesh.update()
    uv_layer = mesh.uv_layers.new(name=source_mesh.uv_layers.active.name)
    for loop, source_index in zip(uv_layer.data, [loop for triangle in loop_sources for loop in triangle]):
        loop.uv = uv_source[source_index]
    for attribute_name, values in colors_source.items():
        attr = mesh.color_attributes.new(name=attribute_name, type="FLOAT_COLOR", domain="CORNER")
        for value, source_index in zip(attr.data, [loop for triangle in loop_sources for loop in triangle]):
            value.color = values[source_index]
    for polygon, is_smooth in zip(mesh.polygons, smooth): polygon.use_smooth = is_smooth
    mesh.normals_split_custom_set(corner_normals)
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(ob)
    ob["SourceSHA256"] = PIN
    ob["ShapeVariant"] = key
    ob["RootBase"] = "(0,0,0), metres, +Z up"
    objects.append(ob)
    bpy.context.view_layer.update()
    raw_qa = qa_check.run(objects=[name], profile="roblox", no_modifiers=True)
    geometric_qa = qa_check.run(objects=[name], profile="roblox", no_modifiers=True, uv=False)
    save_json(OUT/(key+"-qa-raw.json"), raw_qa)
    save_json(OUT/(key+"-qa-geometry.json"), geometric_qa)
    assert geometric_qa["pass"], (key, geometric_qa["errors"])
    stats = mesh_stats.run(objects=[name], budget="roblox")
    assert stats["total_tris"] <= 20000 and stats["unique_materials"] == 1
    assert all(item.startswith("textures > 1024px:") for item in stats["budget"]["over"]), stats
    save_json(OUT/(key+"-stats.json"), stats)
    mesh.calc_loop_triangles()
    final_points = [vertex.co.copy() for vertex in mesh.vertices]
    bmin, bmax = bounds(final_points)
    scale = 8 / (bmax.z-bmin.z)
    rb = lambda p: Vector((p.x, p.z, -p.y))
    center = rb((bmin+bmax)/2)*scale
    rpoints = [rb(p)*scale-center for p in final_points]
    rnormals = [rb(normal.vector).normalized() for normal in mesh.corner_normals]
    # Preserve every native float from the loop channels; only identical tuples deduplicate.
    def channel(values):
        lookup, unique, indices = {}, [], []
        for value in values:
            value = tuple(float(number) for number in value)
            if value not in lookup:
                lookup[value] = len(unique)+1; unique.append(value)
            indices.append(lookup[value])
        return unique, indices
    uv_values, uv_indices = channel((loop.uv.x, 1-loop.uv.y) for loop in mesh.uv_layers.active.data)
    normal_values, normal_indices = channel(rnormals)
    data = {"version":1, "key":key, "name":name, "source_sha256":PIN,"original_source_sha256":PIN,
        "texture_uri":"rbxassetid://137803536172445", "height_studs":8,
        "positions":[list(p) for p in rpoints], "triangles":[], "triangle_uvs":[],
        "triangle_normals":[], "uvs":uv_values, "normals":normal_values,
        "bounds":{"size":list(rb(bmax-bmin).copy()), "center_from_root_studs":list(center)},
        "root_offset_studs":list(-center), "bbox_center_from_root_studs":list(center),
        "blender_units_to_studs":scale,
        "envelope_from_root_studs":{"minimum":[min((p+center)[i] for p in rpoints) for i in range(3)],
            "maximum":[max((p+center)[i] for p in rpoints) for i in range(3)],
            "max_horizontal_radius":max(math.hypot((p+center).x,(p+center).z) for p in rpoints)},
        "corner_colors":{}}
    # The Z component of a size is a magnitude, whereas coordinates flip -Y.
    data["bounds"]["size"] = [(bmax.x-bmin.x)*scale, 8.0, (bmax.y-bmin.y)*scale]
    for triangle in mesh.loop_triangles:
        data["triangles"].append([i+1 for i in triangle.vertices])
        data["triangle_uvs"].append([uv_indices[i] for i in triangle.loops])
        data["triangle_normals"].append([normal_indices[i] for i in triangle.loops])
    for attr in mesh.color_attributes:
        values, indices = channel(value.color for value in attr.data)
        data["corner_colors"][attr.name] = {"colors":values,
            "triangle_colors":[[indices[i] for i in triangle.loops] for triangle in mesh.loop_triangles]}
    data_path = OUT/(key+"-runtime.json")
    save_json(data_path, data)
    comparison = {"key":key,"name":name,"vertices":len(mesh.vertices),"triangles":len(mesh.loop_triangles),
        "dimensions_m":list(ob.dimensions),"height_studs":8,"minimum_jacobian_determinant":minimum_det,
        "max_vertex_displacement_m":max((p-base).length for p,base in zip(final_points,base_points)),
        "uv_identical_to_original_corners":all(tuple(uv_layer.data[i].uv)==uv_source[source_index]
            for i,source_index in enumerate([loop for triangle in loop_sources for loop in triangle])),
        "source_triangle_topology_identical": [tuple(triangle.vertices) for triangle in mesh.loop_triangles] == triangles,
        "qa_geometry_pass":geometric_qa["pass"], "raw_qa_errors":raw_qa["errors"],
        "qa_warnings":geometric_qa["warnings"],"runtime_json":str(data_path),"runtime_sha256":sha(data_path),
        "root_offset_studs":data["root_offset_studs"],
        "bbox_center_from_root_studs":data["bbox_center_from_root_studs"],
        "bounds_studs":data["bounds"]["size"],"envelope_from_root_studs":data["envelope_from_root_studs"]}
    assert comparison["uv_identical_to_original_corners"] and comparison["source_triangle_topology_identical"]
    report["runtime_data"].append(comparison)
    if variant: report["variants"].append(comparison)

for ob in imported: bpy.data.objects.remove(ob, do_unlink=True)
bpy.context.scene.view_settings.view_transform = "AgX"
blend_path = OUT/"Green_Corn_Variants.blend"
bpy.ops.wm.save_as_mainfile(filepath=str(blend_path), check_existing=False)
report["blend"] = {"path":str(blend_path),"sha256":sha(blend_path)}
save_json(OUT/"build-report.json", report)

# QA precedes export. Only our selected private objects are exported.
for ob in objects[1:]:
    path = ROOT/(ob.name+".fbx")
    export_result = export_asset.run(preset="roblox", objects=[ob.name], out=str(path), no_anim=True)
    assert export_result["ok"] and path.stat().st_size > 1000, export_result
    record = next(row for row in report["variants"] if row["name"]==ob.name)
    record["fbx"] = {"path":str(path),"bytes":path.stat().st_size,"sha256":sha(path),"settings":export_result}
    data_path=Path(record["runtime_json"])
    runtime_data=json.loads(data_path.read_text(encoding="utf-8"))
    runtime_data["exported_fbx_sha256"]=record["fbx"]["sha256"]
    save_json(data_path,runtime_data)
    record["runtime_sha256"]=sha(data_path)
save_json(OUT/"build-report.json", report)

# Round-trip each export in its own temporary scene; the source blend is retained.
def corner_records(obs):
    records = []
    for ob in obs:
        me=ob.data; me.calc_loop_triangles()
        nm=ob.matrix_world.to_3x3().inverted().transposed()
        for triangle in me.loop_triangles:
            corners=[]
            for vi,li in zip(triangle.vertices,triangle.loops):
                point=ob.matrix_world @ me.vertices[vi].co
                normal=(nm @ me.corner_normals[li].vector).normalized()
                uv=me.uv_layers.active.data[li].uv
                corners.append((point.copy(),uv.copy(),normal.copy()))
            records.append(corners)
    return records
def compare_roundtrip(expected, actual):
    tree=KDTree(len(expected))
    for index,triangle in enumerate(expected):
        tree.insert(sum((corner[0] for corner in triangle),Vector())/3,index)
    tree.balance()
    used=set(); maxima=[0.0,0.0,0.0]
    for triangle in actual:
        center=sum((corner[0] for corner in triangle),Vector())/3
        best=None
        for _,index,_ in tree.find_n(center,8):
            if index in used:continue
            for perm in permutations(range(3)):
                errors=[]
                for corner,reference in zip(triangle,(expected[index][i] for i in perm)):
                    errors.append(((corner[0]-reference[0]).length,(corner[1]-reference[1]).length,(corner[2]-reference[2]).length))
                score=sum(row[0]**2+row[1]**2*0.001+row[2]**2*1e-8 for row in errors)
                if best is None or score<best[0]:best=(score,index,errors)
        assert best is not None
        used.add(best[1])
        for row in best[2]:
            for i,value in enumerate(row):maxima[i]=max(maxima[i],value)
    return {"unique_triangles_matched":len(used),"max_position_error_m":maxima[0],
        "max_UV_error":maxima[1],"max_unit_normal_vector_error":maxima[2],
        "position_tolerance_m":0.00001,"UV_tolerance":0.000002,"normal_tolerance":0.0005,
        "pass":len(expected)==len(actual)==len(used) and maxima[0]<0.00001 and maxima[1]<0.000002 and maxima[2]<0.0005}
original_scene=bpy.context.scene
for ob in objects[1:]:
    expected=corner_records([ob])
    temporary=bpy.data.scenes.new("RoundTrip_"+ob.name)
    bpy.context.window.scene=temporary
    before=set(bpy.data.objects)
    assert bpy.ops.import_scene.fbx(filepath=str(ROOT/(ob.name+".fbx")),use_image_search=False)=={"FINISHED"}
    bpy.context.view_layer.update()
    reimported=[value for value in bpy.data.objects if value not in before and value.type=="MESH"]
    assert len(reimported)==1
    actual=corner_records(reimported)
    re_lo,re_hi=bounds([value.matrix_world @ vertex.co for value in reimported for vertex in value.data.vertices])
    record=next(row for row in report["variants"] if row["name"]==ob.name)
    comparison=compare_roundtrip(expected,actual)
    record["roundtrip"]={"meshes":len(reimported),"triangles":sum(len(value.data.loop_triangles) for value in reimported),
        "dimensions_m":list(re_hi-re_lo),"lowest_z_m":re_lo.z,
        "corner_comparison":comparison}
    save_json(OUT/"build-report.json",report)
    assert comparison["pass"], record["roundtrip"]
    for value in list(temporary.objects): bpy.data.objects.remove(value,do_unlink=True)
    bpy.context.window.scene=original_scene
    bpy.data.scenes.remove(temporary)

# Required multi-angle material and wire contact sheets, per asset.
for ob in objects:
    key="Original" if ob==objects[0] else ob["ShapeVariant"]
    for mode in ["material","wire"]:
        result=review_shots.run(objects=[ob.name],out=str(OUT/(key+"-"+mode+".png")),
            views=["front","right","top","three_quarter"],mode=mode,res=384)
        record=next(row for row in report["runtime_data"] if row["name"]==ob.name)
        record[mode+"_review"]=result
report["source_unchanged"]=sha(SOURCE)==PIN and sha(TEXTURE)==texture_before
assert report["source_unchanged"]
save_json(OUT/"build-report.json",report)
print("@@JSON@@"+json.dumps({"pass":True,"source_unchanged":True,"blender":bpy.app.version_string,
    "vertices_each":377,"triangles_each":510,"root_fbx":[row["fbx"] for row in report["variants"]],
    "report":str(OUT/"build-report.json")}))
