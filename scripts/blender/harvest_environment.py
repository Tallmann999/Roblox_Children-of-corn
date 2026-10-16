"""Create the editable Harvest Warden environment pack; never writes a Roblox place.

Run with Blender 5.2:
  blender --background --factory-startup -t 4 --python scripts/blender/harvest_environment.py
One Blender unit is one intended Roblox stud. Import scale must be checked in Studio.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import math
import random
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
PACK = ROOT / "assets/harvest-warden"
OUT = PACK / "exports/environment"
PREVIEWS = PACK / "previews"
TEXTURES = PACK / "textures"
SOURCE = ROOT / "assets/farm/SM_Bld_Barn_03_textured.fbx"
SOURCE_ATLAS = ROOT / "assets/farm/PolygonFarm_Texture_01_A.png"
SEED = 20261016


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def collection(name: str, parent=None):
    result = bpy.data.collections.new(name)
    (parent or bpy.context.scene.collection).children.link(result)
    return result


def relink(obj, target):
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    target.objects.link(obj)


def material(name: str, texture=None, color=(0.24, 0.20, 0.16, 1), roughness=0.94):
    result = bpy.data.materials.new(name)
    result.use_nodes = True
    result.diffuse_color = color
    shader = result.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Roughness"].default_value = roughness
    if texture:
        image = bpy.data.images.load(str(texture), check_existing=True)
        # Keep absolute while export runs from an unsaved factory scene.
        image.filepath = str(texture)
        node = result.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = image
        node.interpolation = "Linear"
        node.extension = "REPEAT"
        result.node_tree.links.new(node.outputs["Color"], shader.inputs["Base Color"])
    return result


def mesh_object(name, vertices, faces, target, mat):
    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    target.objects.link(obj)
    mesh.materials.append(mat)
    obj["AssetProject"] = "ChildrenOfCorn_HarvestWarden"
    obj["Units"] = "1 unit = 1 Roblox stud; verify importer scale"
    return obj


def planar_uv(obj, tile=4.0, long_axis=None):
    layer = obj.data.uv_layers.new(name="UVMap_Harvest")
    for polygon in obj.data.polygons:
        dominant = max(range(3), key=lambda axis: abs(polygon.normal[axis]))
        axes = [axis for axis in range(3) if axis != dominant]
        if long_axis is not None and long_axis in axes:
            axes.remove(long_axis)
            axes.append(long_axis)
        elif 2 in axes:
            axes.remove(2)
            axes.append(2)
        for loop_index in polygon.loop_indices:
            v = obj.data.vertices[obj.data.loops[loop_index].vertex_index].co
            layer.data[loop_index].uv = (v[axes[0]] / tile, v[axes[1]] / tile)
    obj.data.uv_layers.active = layer
    # Exporters use the active/render layer, not the original palette coordinates.
    layer.active_render = True
    for other in list(obj.data.uv_layers):
        if other != layer:
            obj.data.uv_layers.remove(other)


def choose_objects(objects):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]


def bounds(objects):
    points = [obj.matrix_world @ v.co for obj in objects for v in obj.data.vertices]
    low = [min(v[i] for v in points) for i in range(3)]
    high = [max(v[i] for v in points) for i in range(3)]
    return {"min": low, "max": high, "size": [b - a for a, b in zip(low, high)]}


def check_objects(objects):
    for obj in objects:
        assert obj.type == "MESH" and len(obj.data.vertices) > 0
        assert all(math.isfinite(n) for v in obj.data.vertices for n in v.co)
        assert len(obj.data.uv_layers) == 1, f"one exported UV layer required: {obj.name}"
        assert all(math.isfinite(n) for uv in obj.data.uv_layers[0].data for n in uv.uv)
        assert all(len(p.vertices) >= 3 for p in obj.data.polygons)
        assert len(obj.data.materials) > 0
        for mat in obj.data.materials:
            assert mat and mat.use_nodes
            for node in mat.node_tree.nodes:
                if node.type == "TEX_IMAGE":
                    assert node.image and all(node.image.size), "texture image failed to load"
                    assert Path(bpy.path.abspath(node.image.filepath, start=str(PACK))).is_file()


def export_asset(name, objects):
    check_objects(objects)
    directory = OUT / name
    directory.mkdir(parents=True, exist_ok=True)
    fbx = directory / (name + ".fbx")
    glb = directory / (name + ".glb")
    # FBX's triangulation pipeline can validate/mutate the selected mesh datablock.
    # Keep all raw source polygons in the editable .blend, and export separate data.
    temporary = collection("HW_EXPORT_TEMPORARY")
    exported, removed, degenerate = [], [], []
    source_counts = [(o, len(o.data.polygons), sum(len(p.vertices) - 2 for p in o.data.polygons)) for o in objects]
    for original in objects:
        seen, keep = {}, []
        for polygon in original.data.polygons:
            key = tuple(sorted(polygon.vertices))
            if key in seen:
                # Only the original barn contains these two coincident quads.
                assert original.name == "HW_Dark_SM_Bld_Barn_03"
                assert key in ((3, 5, 24, 25), (2, 4, 24, 25))
                removed.append({"source_object": original.name, "polygon": polygon.index,
                                "duplicate_of": seen[key], "triangles": len(polygon.vertices) - 2})
            else:
                seen[key] = polygon.index
                keep.append(polygon)
        data = bpy.data.meshes.new(original.data.name + "_Export")
        data.from_pydata([v.co.copy() for v in original.data.vertices], [], [tuple(p.vertices) for p in keep])
        data.update()
        for mat in original.data.materials:
            data.materials.append(mat)
        uv = data.uv_layers.new(name="UVMap_Harvest")
        for target_poly, source_poly in zip(data.polygons, keep):
            target_poly.material_index = source_poly.material_index
            target_poly.use_smooth = source_poly.use_smooth
            for target_loop, source_loop in zip(target_poly.loop_indices, source_poly.loop_indices):
                uv.data[target_loop].uv = original.data.uv_layers[0].data[source_loop].uv
        # Source FBX also contains collinear corner triangles in each barn part.
        # Preserve them in the source .blend, but do not send zero-area faces to Roblox.
        data.calc_loop_triangles()
        triangle_faces, triangle_uv, triangle_material, triangle_smooth = [], [], [], []
        for triangle in data.loop_triangles:
            a, b, c = (data.vertices[index].co for index in triangle.vertices)
            cross_squared = (b - a).cross(c - a).length_squared
            if cross_squared < 1e-18:
                assert "SM_Bld_Barn_03" in original.name
                degenerate.append({"source_object": original.name,
                                   "source_polygon": keep[triangle.polygon_index].index,
                                   "vertices": list(triangle.vertices),
                                   "squared_cross_product": cross_squared})
                continue
            triangle_faces.append(tuple(triangle.vertices))
            triangle_uv.append([uv.data[index].uv.copy() for index in triangle.loops])
            triangle_material.append(triangle.material_index)
            triangle_smooth.append(data.polygons[triangle.polygon_index].use_smooth)
        clean = bpy.data.meshes.new(original.data.name + "_TriangulatedExport")
        clean.from_pydata([v.co.copy() for v in data.vertices], [], triangle_faces)
        clean.update()
        for mat in data.materials:
            clean.materials.append(mat)
        clean_uv = clean.uv_layers.new(name="UVMap_Harvest")
        for polygon, coords, mat_index, smooth in zip(clean.polygons, triangle_uv, triangle_material, triangle_smooth):
            polygon.material_index = mat_index
            polygon.use_smooth = smooth
            for loop, coord in zip(polygon.loop_indices, coords):
                clean_uv.data[loop].uv = coord
        bpy.data.meshes.remove(data)
        duplicate = original.copy()
        duplicate.name = original.name + "_Export"
        duplicate.data = clean
        temporary.objects.link(duplicate)
        exported.append(duplicate)
    check_objects(exported)
    choose_objects(exported)
    bpy.ops.export_scene.fbx(
        filepath=str(fbx), use_selection=True, object_types={"MESH"},
        global_scale=1.0, apply_unit_scale=False, apply_scale_options="FBX_SCALE_NONE",
        axis_forward="-Z", axis_up="Y", use_space_transform=True,
        use_mesh_modifiers=True, use_triangles=True, mesh_smooth_type="FACE",
        path_mode="COPY", embed_textures=True, add_leaf_bones=False,
        bake_anim=False, use_custom_props=True,
    )
    bpy.ops.export_scene.gltf(
        filepath=str(glb), export_format="GLB", use_selection=True,
        export_apply=True, export_animations=False, export_extras=True,
        export_yup=True, export_materials="EXPORT", export_cameras=False,
        export_lights=False, export_texcoords=True, export_normals=True,
    )
    row = {
        "name": name, "collection": objects[0].users_collection[0].name,
        "meshes": len(exported), "vertices": sum(len(o.data.vertices) for o in exported),
        "triangles": sum(len(p.vertices) - 2 for o in exported for p in o.data.polygons),
        "export_cleanup": {"duplicate_index_polygons_removed": removed,
                           "zero_area_triangles_removed": degenerate,
                           "zero_area_squared_cross_threshold": 1e-18,
                           "source_blend_unchanged": True},
        "bounds_blender_z_up": bounds(objects),
        "files": [{"path": str(p.relative_to(PACK)).replace("\\", "/"),
                   "bytes": p.stat().st_size, "sha256": sha(p)} for p in (fbx, glb)],
    }
    for original, polygon_count, triangle_count in source_counts:
        assert len(original.data.polygons) == polygon_count
        assert sum(len(p.vertices) - 2 for p in original.data.polygons) == triangle_count
    for obj in exported:
        data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.meshes.remove(data)
    bpy.data.collections.remove(temporary)
    return row


def make_barn(parent, wood, roof):
    # Blender's importer silently drops two original body polygons (4 triangles).
    # The project's audited extractor retains all raw FBX vertices/polygons.
    spec = importlib.util.spec_from_file_location("harvest_fbx_extract", ROOT / "scripts/export-farm-editable-mesh.py")
    extractor = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(extractor)
    neutral = extractor.extract(SOURCE)
    parsed = extractor.fbx.read_fbx(SOURCE)
    source_objects = next(n for n in parsed["nodes"] if n.name == "Objects")
    geometries = {n.props[0]: n for n in source_objects.children if n.name == "Geometry"}
    assert len(neutral["meshes"]) == 7
    names = sorted(m["name"] for m in neutral["meshes"])
    door_data = next(m for m in neutral["meshes"] if m["name"].endswith("Door_01"))
    source_height = max(v[1] for v in door_data["positions"]) - min(v[1] for v in door_data["positions"])
    scale = 7.5 / source_height
    barn_collection = collection("HW_BarnDark_Open", parent)
    archive = collection("HW_BarnDark_OriginalDoorLeaves", parent)
    max_error = 0.0
    visible, doors, comparisons = [], [], []
    for source_mesh in neutral["meshes"]:
        original_name = source_mesh["name"]
        positions = [Vector((p[0] * scale, -p[2] * scale, p[1] * scale)) for p in source_mesh["positions"]]
        indices = geometries[source_mesh["geometry_id"]].child("PolygonVertexIndex").props[0]
        source_faces, current = [], []
        for index in indices:
            current.append(index if index >= 0 else -index - 1)
            if index < 0:
                source_faces.append(tuple(current))
                current = []
        assert not current
        is_door = "_Door_" in original_name
        obj = mesh_object("HW_Dark_" + original_name, positions, source_faces,
                          archive if is_door else barn_collection, wood)
        assert [tuple(p.vertices) for p in obj.data.polygons] == source_faces
        assert sum(len(p.vertices) - 2 for p in obj.data.polygons) == len(source_mesh["triangles"])
        error = max((vertex.co - position).length for vertex, position in zip(obj.data.vertices, positions))
        max_error = max(max_error, error)
        assert error < 0.00001, (original_name, error)
        obj.data.materials.append(roof)
        # The complete source body includes already-modelled roof panels. Only material changes.
        if original_name == "SM_Bld_Barn_03":
            for polygon in obj.data.polygons:
                center = sum((obj.data.vertices[i].co for i in polygon.vertices), Vector()) / len(polygon.vertices)
                if center.z > 9.0 and 0.30 < abs(polygon.normal.z) < 0.95 and abs(polygon.normal.y) > 0.30:
                    polygon.material_index = 1
        planar_uv(obj, tile=5.0)
        obj["OriginalMesh"] = original_name
        obj["SourceGeometryPreserved"] = True
        obj["UVChange"] = "palette UV replaced by metric planar weathered wood UV"
        obj["DoorLeafArchiveOnly"] = is_door
        (doors if is_door else visible).append(obj)
        comparisons.append({"source_mesh": original_name,
                            "vertices": len(obj.data.vertices), "polygons": len(obj.data.polygons),
                            "triangles": len(source_mesh["triangles"]), "topology_identical": True,
                            "max_scaled_world_position_error": error,
                            "uv_changed": True, "door_archived_for_open_passage": is_door})
    assert sum(row["triangles"] for row in comparisons) == 8160
    assert len(doors) == 4 and len(visible) == 3
    return visible, doors, {
        "source": str(SOURCE.relative_to(ROOT)).replace("\\", "/"),
        "source_mesh_names": names, "uniform_scale": scale,
        "source_positions_units": "FBX centimetres; source Y-up converted to Blender Z-up",
        "geometry_input": "read-only original FBX raw polygons; avoids importer polygon loss",
        "source_door_height": source_height, "exported_door_height_studs": 7.5,
        "all_seven_source_meshes_preserved_in_blend": True,
        "open_export_omits_four_archived_door_leaves": True,
        "max_position_error": max_error, "mesh_checks": comparisons,
        "appearance_only": "new planar UV, dark wood texture, matte desaturated roof material",
    }


def rough_beam(name, start, end, width, depth, target, wood, rng, bend=0.06):
    start, end = Vector(start), Vector(end)
    direction = (end - start).normalized()
    tangent = direction.cross(Vector((0, 0, 1)))
    if tangent.length < 0.01:
        tangent = Vector((1, 0, 0))
    tangent.normalize()
    second = direction.cross(tangent).normalized()
    vertices = []
    segments = 4
    for ring in range(segments + 1):
        t = ring / segments
        center = start.lerp(end, t) + second * (math.sin(t * math.pi) * bend)
        taper = 1 + rng.uniform(-0.10, 0.10)
        for a, b in ((-1, -1), (-1, 1), (1, 1), (1, -1)):
            point = center + tangent * (a * width * 0.5 * taper) + second * (b * depth * 0.5 * taper)
            vertices.append(tuple(point))
    faces = [(3, 2, 1, 0)]
    for ring in range(segments):
        for corner in range(4):
            a, b = ring * 4 + corner, ring * 4 + (corner + 1) % 4
            faces.append((a, b, b + 4, a + 4))
    faces.append(tuple(range(segments * 4, segments * 4 + 4)))
    obj = mesh_object(name, vertices, faces, target, wood)
    long_axis = max(range(3), key=lambda i: abs(end[i] - start[i]))
    planar_uv(obj, tile=2.0, long_axis=long_axis)
    return obj


def make_fence(variant, parent, wood):
    rng = random.Random(SEED + variant)
    coll = collection(f"HW_Fence_{variant:02d}", parent)
    objects = []
    for index, x in enumerate((-6, 0, 6)):
        top = (x + rng.uniform(-0.10, 0.13), rng.uniform(-0.09, 0.09), 4.0 + rng.uniform(-0.12, 0.15))
        objects.append(rough_beam(f"Fence{variant:02d}_Post{index + 1}", (x, 0, 0), top,
                                  0.38, 0.42, coll, wood, rng, 0.025))
    for span, (left, right) in enumerate(((-6, 0), (0, 6))):
        for rail, z in enumerate((1.45, 2.85)):
            start = (left - 0.12, -0.08, z + rng.uniform(-0.08, 0.08))
            end = (right + 0.12, -0.08, z + rng.uniform(-0.12, 0.12))
            if variant == 2 and span == 1 and rail == 1:
                objects.append(rough_beam("Fence02_BrokenRailA", start, (2.0, -0.15, z - 0.22),
                                          0.22, 0.34, coll, wood, rng, 0.07))
                objects.append(rough_beam("Fence02_BrokenRailB", (3.5, -0.1, z - 0.37), end,
                                          0.22, 0.34, coll, wood, rng, 0.09))
            elif variant == 3 and span == 0 and rail == 0:
                objects.append(rough_beam("Fence03_DroppedRail", (-5.8, -0.35, 0.18), (-0.3, -0.7, 0.38),
                                          0.22, 0.34, coll, wood, rng, 0.06))
            else:
                objects.append(rough_beam(f"Fence{variant:02d}_Rail{span}_{rail}", start, end,
                                          0.22, 0.34, coll, wood, rng, 0.11))
    for index, obj in enumerate(objects):
        obj["FenceVariant"] = variant
        obj["RobloxPhysicsHint"] = "decorative non-collidable; use simple post collision only if required"
    return objects


def make_rock(index, parent, stone):
    rng = random.Random(SEED + index * 31)
    coll = collection(f"HW_Rock_{index:02d}", parent)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1)
    obj = bpy.context.object
    obj.name = f"HW_Rock_{index:02d}"
    relink(obj, coll)
    sx, sy, sz = rng.uniform(0.65, 1.0), rng.uniform(0.45, 0.80), rng.uniform(0.30, 0.62)
    for vertex in obj.data.vertices:
        point = vertex.co
        point.x *= sx * rng.uniform(0.85, 1.12)
        point.y *= sy * rng.uniform(0.85, 1.10)
        point.z *= sz * rng.uniform(0.83, 1.11)
        point.z = max(-sz * 0.55, point.z)
    low = min(v.co.z for v in obj.data.vertices)
    for vertex in obj.data.vertices:
        vertex.co.z -= low
    obj.data.update()
    obj.data.materials.append(stone)
    obj["RockVariant"] = index
    obj["RobloxPhysicsHint"] = "decorative, non-collidable, no touch/query"
    planar_uv(obj, tile=2.0)
    return [obj]


def make_tile(name, parent, mat, road=False):
    coll = collection(name, parent)
    # Geometry is actual editable mesh, not an image backdrop.
    vertices = [(-4, -4, 0), (4, -4, 0), (4, 4, 0), (-4, 4, 0)]
    faces = [(0, 1, 2, 3)]
    obj = mesh_object(name, vertices, faces, coll, mat)
    planar_uv(obj, tile=8 if road else 4)
    obj["TileSizeStuds"] = 8
    obj["RoadDirectionBlender"] = "+Y" if road else "none"
    obj["RobloxPhysicsHint"] = "surface mesh only; reuse existing authoritative ground collision"
    objects = [obj]
    if road:
        # Uneven shoulder strips help blend the tile against darker ground.
        for side in (-1, 1):
            x = side * 3.77
            points = [(x - 0.25, -4, 0.015), (x + 0.25, -4, 0.015),
                      (x + 0.31, 0, 0.025), (x + 0.20, 4, 0.015),
                      (x - 0.30, 4, 0.015), (x - 0.18, 0, 0.02)]
            shoulder = mesh_object(f"{name}_Shoulder_{side}", points, [(0, 1, 2, 3, 4, 5)], coll, GROUND)
            planar_uv(shoulder, tile=4)
            objects.append(shoulder)
    return objects


def aim(obj, at):
    obj.rotation_euler = (Vector(at) - obj.location).to_track_quat("-Z", "Y").to_euler()


def render_preview(environment, assets):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.threads_mode = "FIXED"
    scene.render.threads = 4
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 800
    scene.render.resolution_percentage = 100
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.12, 0.16, 0.23, 1)
    background.inputs["Strength"].default_value = 0.65
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.exposure = 0.65
    preview_collection = collection("HW_Environment_Preview")
    copies = []
    layout = {
        "BarnDark_Open": ((0, 9, 0), 0),
        "Fence_01": ((-10, -6, 0), math.radians(7)),
        "Fence_02": ((5, -9, 0), math.radians(-8)),
        "Fence_03": ((14, 0, 0), math.radians(82)),
        "Rock_01": ((-7, -3, 0), 0), "Rock_02": ((-4, -4, 0), 0.6),
        "Rock_03": ((10, -7, 0), 1.5), "Rock_04": ((12, -4, 0), 0.9),
        "Rock_05": ((6, -2, 0), 0.2),
    }
    # Exports stay at origin; preview instances are explicitly excluded from all asset exports.
    for key, (position, yaw) in layout.items():
        matrix = Matrix.Translation(Vector(position)) @ Matrix.Rotation(yaw, 4, "Z")
        for original in assets[key]:
            duplicate = original.copy()
            preview_collection.objects.link(duplicate)
            duplicate.matrix_world = matrix @ original.matrix_world
            duplicate.hide_render = False
            copies.append(duplicate)
    floor = mesh_object("PreviewFloor", [(-60, -50, -0.05), (60, -50, -0.05),
                                         (60, 70, -0.05), (-60, 70, -0.05)],
                        [(0, 1, 2, 3)], preview_collection, GROUND)
    planar_uv(floor, tile=7)
    road = mesh_object("PreviewPath", [(-5, -50, -0.02), (5, -50, -0.02),
                                        (4, 25, -0.02), (-4, 25, -0.02)],
                       [(0, 1, 2, 3)], preview_collection, PATH)
    planar_uv(road, tile=13)
    for item in environment.all_objects:
        item.hide_render = True
    for duplicate in copies:
        duplicate.hide_render = False
    light_data = bpy.data.lights.new("PreviewMoonSoftbox", "AREA")
    light_data.energy = 10500
    light_data.shape = "DISK"
    light_data.size = 25
    light = bpy.data.objects.new("PreviewMoonSoftbox", light_data)
    preview_collection.objects.link(light)
    light.location = (-15, -10, 30)
    aim(light, (0, 5, 4))
    light_data.color = (0.68, 0.77, 1.0)
    fill_data = bpy.data.lights.new("PreviewWarmDoor", "AREA")
    fill_data.energy = 1800
    fill_data.size = 14
    fill_data.color = (1.0, 0.62, 0.32)
    fill = bpy.data.objects.new("PreviewWarmDoor", fill_data)
    preview_collection.objects.link(fill)
    fill.location = (-12, -13, 12)
    aim(fill, (0, 8, 7))
    door_data = bpy.data.lights.new("PreviewDoorLantern", "POINT")
    door_data.energy = 440
    door_data.shadow_soft_size = 1.2
    door_data.color = (1.0, 0.37, 0.12)
    door = bpy.data.objects.new("PreviewDoorLantern", door_data)
    preview_collection.objects.link(door)
    door.location = (-8.1, 9, 3.8)
    camera_data = bpy.data.cameras.new("EnvironmentPreviewCamera")
    camera = bpy.data.objects.new("EnvironmentPreviewCamera", camera_data)
    preview_collection.objects.link(camera)
    camera.location = (-38, -35, 23)
    aim(camera, (1, 3, 6))
    camera_data.lens = 44
    scene.camera = camera
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(PREVIEWS / "environment-overview.png")
    bpy.ops.render.render(write_still=True)
    camera.location = (-33, -24, 18)
    aim(camera, (0, 8, 8.2))
    camera_data.lens = 43
    scene.render.filepath = str(PREVIEWS / "environment-barn-dark.png")
    bpy.ops.render.render(write_still=True)
    # Keep a ready-to-render preview scene in the source .blend.
    return preview_collection


def main():
    for path in (SOURCE, SOURCE_ATLAS, TEXTURES / "barn_wood_dark.png", TEXTURES / "soil_gravel.png"):
        assert path.is_file(), f"required input missing: {path}"
    originals = {str(p.relative_to(ROOT)).replace("\\", "/"): sha(p) for p in (SOURCE, SOURCE_ATLAS)}
    OUT.mkdir(parents=True, exist_ok=True)
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.context.preferences.filepaths.save_version = 0
    scene = bpy.context.scene
    scene.unit_settings.system = "NONE"
    scene.unit_settings.scale_length = 1.0
    scene["IntendedUnits"] = "1 Blender unit = 1 Roblox stud; validate importer at door7.5studs"
    environment = collection("HW_ENVIRONMENT")
    wood = material("HW_Weathered_Dark_Wood", TEXTURES / "barn_wood_dark.png")
    roof = material("HW_Dark_Matte_Roof", color=(0.075, 0.083, 0.088, 1))
    global GROUND, PATH
    GROUND = material("HW_Soil_Ground", TEXTURES / "soil_gravel.png")
    PATH = material("HW_Gravel_Path", TEXTURES / "soil_gravel.png", roughness=0.88)
    stone = material("HW_Weathered_Rock", TEXTURES / "soil_gravel.png", roughness=0.97)
    barn, doors, preservation = make_barn(environment, wood, roof)
    assets = {"BarnDark_Open": barn, "BarnDark_DoorLeaves_Optional": doors}
    for index in range(1, 4):
        assets[f"Fence_{index:02d}"] = make_fence(index, environment, wood)
    for index in range(1, 6):
        assets[f"Rock_{index:02d}"] = make_rock(index, environment, stone)
    assets["Ground_Tile_8"] = make_tile("HW_GroundTile8", environment, GROUND)
    assets["Path_Tile_8"] = make_tile("HW_PathTile8", environment, PATH, road=True)
    rows = []
    for name, objects in assets.items():
        rows.append(export_asset(name, objects))
    assert sum(len(p.vertices) - 2 for obj in barn + doors for p in obj.data.polygons) == 8160
    assert rows[0]["triangles"] == 6600
    assert rows[1]["triangles"] == 1528
    preservation["export_duplicate_cleanup"] = rows[0]["export_cleanup"]["duplicate_index_polygons_removed"]
    preservation["export_zero_area_triangle_cleanup"] = sum(len(row["export_cleanup"]["zero_area_triangles_removed"]) for row in rows)
    assert preservation["export_zero_area_triangle_cleanup"] == 28
    preservation["export_open_barn_triangles"] = rows[0]["triangles"]
    preservation["export_all_parts_triangles"] = rows[0]["triangles"] + rows[1]["triangles"]
    for obj in doors:
        obj.hide_render = True
        obj.hide_set(True)
    for key, expected in originals.items():
        assert sha(ROOT / key) == expected, f"original input changed: {key}"
    render_preview(environment, assets)
    blend = PACK / "environment.blend"
    for image in bpy.data.images:
        if image.source == "FILE" and image.filepath:
            image.pack()
            image.filepath = bpy.path.relpath(image.filepath, start=str(PACK))
    bpy.ops.wm.save_as_mainfile(filepath=str(blend), check_existing=False)
    for key, expected in originals.items():
        assert sha(ROOT / key) == expected
    manifest = {
        "format": "ChildrenOfCorn_HarvestEnvironment_v1", "seed": SEED,
        "blender_version": bpy.app.version_string, "root_collection": environment.name,
        "units": "1 Blender unit = 1 intended Roblox stud; Z-up .blend, Y-up FBX/glTF",
        "roblox_import_acceptance": "pending actual Studio import, eye/gameplay integration and FPS",
        "original_input_hashes": originals, "barn_preservation": preservation,
        "assets": rows,
        "textures": [{"path": str(p.relative_to(PACK)).replace("\\", "/"),
                      "sha256": sha(p)} for p in (TEXTURES / "barn_wood_dark.png", TEXTURES / "soil_gravel.png")],
        "checks": {"finite_positions": True, "finite_uv": True, "materials_resolve": True,
                   "original_inputs_unchanged": True, "barn_topology_preserved": True,
                   "barn_world_geometry_uniform_scale_only": True,
                   "asset_exports_triangulated": True, "preview_from_actual_3d_meshes": True},
        "notes": ["Source .blend retains all seven original barn meshes; four door leaves are hidden and separately exported.",
                  "Open barn export contains body plus two shutters; original four closed door leaves omitted for existing passage.",
                  "Barn palette UV replaced by metric planar wood UV; topology and uniformly-scaled positions unchanged.",
                  "Export-only copies remove two coincident source quads (four redundant triangles); all 8160 source triangles remain editable in the .blend.",
                  "Export-only triangulated copies also omit 28 exactly collinear source triangles (four in each original barn part); no exported barn surface has zero area.",
                  "Fences and rocks are decorative assets; authoritative collisions must remain separate.",
                  "Ground/path are repeatable surface tiles. Importing does not alter original map or terrain."],
    }
    (PACK / "environment-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("HARVEST_ENVIRONMENT_PASS=" + json.dumps({"assets": len(rows), "barn_triangles": 8160,
                                                  "open_barn_triangles": rows[0]["triangles"],
                                                  "blend": str(blend), "manifest": str(PACK / "environment-manifest.json")}))


if __name__ == "__main__":
    main()
