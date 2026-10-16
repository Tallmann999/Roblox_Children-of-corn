"""Render two offline asset comparisons. No Studio, place or game-code writes.

blender --background --factory-startup -t 4 --python scripts/blender/harvest_showcase.py
The scene layout is illustrative; it is not a reproduction or saved Roblox map.
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
PREVIEW = PACK / "previews"
SEED = 20261016


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def collection(name, parent):
    result = bpy.data.collections.new(name)
    parent.children.link(result)
    return result


def append_collections(path, names):
    requested = tuple(names)
    with bpy.data.libraries.load(str(path), link=False) as (available, loaded):
        assert set(requested).issubset(available.collections)
        loaded.collections = list(requested)
    return dict(zip(requested, loaded.collections))


def append_objects(path, names):
    requested = tuple(names)
    with bpy.data.libraries.load(str(path), link=False) as (available, loaded):
        assert set(requested).issubset(available.objects)
        loaded.objects = list(requested)
    return dict(zip(requested, loaded.objects))


def image_material(name, image_path, color=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.94
    if image_path:
        texture = mat.node_tree.nodes.new("ShaderNodeTexImage")
        texture.image = bpy.data.images.load(str(image_path), check_existing=True)
        mat.node_tree.links.new(texture.outputs["Color"], bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = (*color, 1)
    return mat


def original_meshes(path, mat, scale, prefix, parent, omit_doors=False, ground_origin=False):
    neutral = EXTRACTOR.extract(path)
    source_low = min(v[1] for m in neutral["meshes"] for v in m["positions"]) if ground_origin else 0
    objects = []
    for part in neutral["meshes"]:
        if omit_doors and "_Door_" in part["name"]:
            continue
        mesh = bpy.data.meshes.new(prefix + part["name"])
        positions = [(v[0] * scale, -v[2] * scale, (v[1] - source_low) * scale) for v in part["positions"]]
        faces = [tuple(i - 1 for i in face) for face in part["triangles"]]
        mesh.from_pydata(positions, [], faces)
        mesh.update()
        uv = mesh.uv_layers.new(name="Original_FBX_UV")
        for polygon, corners in zip(mesh.polygons, part["triangle_uvs"]):
            for loop, index in zip(polygon.loop_indices, corners):
                uv.data[loop].uv = part["uvs_fbx"][index - 1]
        mesh.materials.append(mat)
        obj = bpy.data.objects.new(prefix + part["name"], mesh)
        parent.objects.link(obj)
        obj["OriginalFBX"] = str(path.relative_to(ROOT)).replace("\\", "/")
        obj["GeometryChange"] = "uniform normalization and Y-up to Z-up only; original triangle positions/UV"
        objects.append(obj)
    return objects


def plane(name, parent, width, depth, mat, z, tile=8):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([(-width / 2, -depth / 2, z), (width / 2, -depth / 2, z),
                      (width / 2, depth / 2, z), (-width / 2, depth / 2, z)], [], [(0, 1, 2, 3)])
    mesh.update()
    mesh.materials.append(mat)
    uv = mesh.uv_layers.new(name="Tiled_UV")
    for loop in mesh.loops:
        co = mesh.vertices[loop.vertex_index].co
        uv.data[loop.index].uv = (co.x / tile, co.y / tile)
    obj = bpy.data.objects.new(name, mesh)
    parent.objects.link(obj)
    return obj


def transform_collection(coll, matrix):
    # Parentless armatures move their children; mesh-only assets have no parent.
    for obj in coll.all_objects:
        if obj.parent is None:
            obj.matrix_world = matrix @ obj.matrix_world


def duplicate_asset(originals, parent, prefix, position, yaw=0):
    matrix = Matrix.Translation(Vector(position)) @ Matrix.Rotation(yaw, 4, "Z")
    result = []
    for original in originals:
        obj = original.copy()
        obj.name = prefix + original.name
        obj.hide_render = False
        parent.objects.link(obj)
        obj.hide_set(False)
        obj.matrix_world = matrix @ original.matrix_world
        result.append(obj)
    return result


def aim(obj, point):
    obj.rotation_euler = (Vector(point) - obj.location).to_track_quat("-Z", "Y").to_euler()


def light(parent, name, kind, position, power, color, target=None, size=5):
    data = bpy.data.lights.new(name, kind)
    data.energy, data.color = power, color
    if kind == "AREA":
        data.shape, data.size = "DISK", size
    else:
        data.shadow_soft_size = 0.6
    obj = bpy.data.objects.new(name, data)
    parent.objects.link(obj)
    obj.location = position
    if target:
        aim(obj, target)
    return obj


def corn_positions():
    rng = random.Random(SEED)
    positions = []
    # Broad footpath at center; preserve a clear full-body silhouette and barn approach.
    for x in (-18, -15.5, -13, -10.5, -8, -5.5, 5.5, 8, 10.5, 13, 15.5, 18):
        for y in (-10, -7.5, -5, -2.5, 0, 2.5, 5, 7.5, 10, 12.5, 15, 17.5, 20, 22.5, 25, 27.5, 30, 32.5):
            # Barn footprint (rotated from original) plus entrance/path clearance.
            if 0 < x < 17 and y >= 7:
                continue
            # Right side camera corridor; nearest plants still frame the lower right.
            if 3 < x < 11 and y < -6:
                continue
            if (4 < x < 10 and 2 <= y <= 5) or (10 < x < 11 and y == 5):
                continue
            positions.append((x + rng.uniform(-0.24, 0.24), y + rng.uniform(-0.24, 0.24),
                              rng.uniform(-math.pi, math.pi), rng.uniform(0.94, 1.04)))
    assert 150 <= len(positions) <= 250
    return positions


def compositor(scene):
    tree = bpy.data.node_groups.new(scene.name + "_EyeBloom", "CompositorNodeTree")
    scene.compositing_node_group = tree
    tree.interface.new_socket(name="Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    layer = tree.nodes.new("CompositorNodeRLayers")
    layer.scene = scene
    glare = tree.nodes.new("CompositorNodeGlare")
    glare.inputs["Type"].default_value = "Fog Glow"
    if "Threshold" in glare.inputs:
        glare.inputs["Threshold"].default_value = 0.65
    output = tree.nodes.new("NodeGroupOutput")
    tree.links.new(layer.outputs["Image"], glare.inputs["Image"])
    tree.links.new(glare.outputs["Image"], output.inputs["Image"])


def build_scene(name, detailed, source_corn, original_barn, environment, warden):
    scene = bpy.data.scenes.new(name)
    bpy.context.window.scene = scene
    scene["OfflineAssetPreview"] = True
    scene["SceneLayout"] = "Illustrative asset comparison, not the authored Roblox map"
    scene["Units"] = "1 Blender unit = 1 intended Roblox stud"
    scene["RobloxIntegration"] = "pending actual Studio import and gameplay verification"
    scene.unit_settings.system = "NONE"
    scene.unit_settings.scale_length = 1
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.threads_mode, scene.render.threads = "FIXED", 4
    scene.render.resolution_x, scene.render.resolution_y = 1200, 800
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.exposure = 0.0
    scene.render.fps = 24
    scene.frame_start, scene.frame_end = 1, 73
    world = bpy.data.worlds.new(name + "_NightSky")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.045, 0.075, 0.14, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.32
    scene.world = world
    parent = collection(name + "_Assets", scene.collection)
    ground = plane(name + "_Ground", parent, 180, 180, SOIL if detailed else FLAT_GROUND, -0.025, tile=7)
    if detailed:
        path = plane(name + "_DirtPath", parent, 7.5, 100, PATH_MATERIAL, -0.01, tile=12)
    else:
        path = plane(name + "_CurrentPathApproximation", parent, 7.5, 100, FLAT_PATH, -0.01, tile=12)
    foliage = collection(name + "_CornInstances", parent)
    corn_sources = list(source_corn.values()) if detailed else [source_corn]
    positions = corn_positions()
    for index, (x, y, yaw, size) in enumerate(positions):
        source = corn_sources[index % len(corn_sources)]
        duplicate = source.copy()
        duplicate.name = ("Detailed" if detailed else "Original") + f"Corn_{index:03d}"
        duplicate.hide_render = False
        foliage.objects.link(duplicate)
        duplicate.hide_set(False)
        duplicate.location = (x, y, 0)
        duplicate.rotation_euler = (0, 0, yaw)
        duplicate.scale = (size, size, size)
        duplicate["SharesMeshData"] = source.name
    barn_collection = collection(name + "_Barn", parent)
    barn_sources = list(environment["HW_BarnDark_Open"].objects) if detailed else original_barn
    barn = duplicate_asset(barn_sources, barn_collection, name + "_", (8, 19, 0), math.radians(70))
    prop_collection = collection(name + "_FenceAndRocks", parent)
    for index, (position, yaw) in enumerate((((5.3, -1, 0), math.pi / 2), ((5.3, 9.8, 0), math.pi / 2),
                                            ((-7.2, 6.4, 0), 0.08), ((17.3, 4, 0), math.pi / 2))):
        source = environment[f"HW_Fence_{index % 3 + 1:02d}"]
        duplicate_asset(list(source.objects), prop_collection, f"SceneFence{index}_", position, yaw)
    for index, position in enumerate(((-3.3, -5, 0), (3.1, -2, 0), (-3.8, 2, 0), (4.1, 5.5, 0),
                                       (6.1, 8, 0), (-5.2, 8, 0), (2.6, -6, 0))):
        source = environment[f"HW_Rock_{index % 5 + 1:02d}"]
        duplicate_asset(list(source.objects), prop_collection, f"SceneRock{index}_", position, index * 0.77)
    scene.collection.children.link(warden)
    warden.hide_render, warden.hide_viewport = False, False
    for obj in warden.all_objects:
        obj.hide_render = False
        obj.hide_set(False)
    rig = next(o for o in warden.objects if o.type == "ARMATURE")
    rig.location = (0, 0, 0)
    rig.rotation_euler.z = 0.10
    idle = next((a for a in bpy.data.actions if a.name.startswith(("Detailed" if detailed else "Classic") + "_Idle")), None)
    if idle:
        rig.animation_data.action = idle
    light(parent, name + "_ColdMoon", "AREA", (-12, 0, 30), 12500, (0.48, 0.65, 1), (0, 6, 3), 18)
    light(parent, name + "_FrontReadability", "AREA", (2, -13, 13), 2300, (0.63, 0.76, 1), (0, 2, 4), 12)
    light(parent, name + "_BarnDoorAmber", "AREA", (8, 15, 5), 1600, (1, 0.38, 0.10), (8, 5, 3), 5)
    light(parent, name + "_DoorLantern", "POINT", (8, 10.2, 4), 250, (1, 0.26, 0.055))
    for side in (-1, 1):
        eye = light(parent, name + "_EyeRed" + str(side), "POINT", (side * .24 + .06, -.68, 7.72), 5, (1, .002, .001))
        eye.data.shadow_soft_size = .15
        eye["RobloxStartingRangeStuds"] = 24
        eye["RobloxStartingBrightness"] = 3
        eye["PreviewOnly"] = "Roblox PointLight adapter pending"
    camera_data = bpy.data.cameras.new(name + "_Camera")
    camera = bpy.data.objects.new(name + "_Camera", camera_data)
    parent.objects.link(camera)
    camera.location = (6, -24, 9.3)
    aim(camera, (1, 8, 6.5))
    camera_data.lens = 34
    scene.camera = camera
    compositor(scene)
    scene.frame_set(1)
    scene.render.filepath = str(PREVIEW / ("variant-b.png" if detailed else "variant-a.png"))
    bpy.ops.render.render(write_still=True)
    return scene, {"scene": name, "variant": "B" if detailed else "A", "plant_instances": len(positions),
                   "plant_mesh_datablocks": len(corn_sources), "barn": "weathered dark derivative" if detailed else "original red barn/atlas",
                   "corn": [o.name for o in corn_sources], "warden": warden.name,
                   "image": str(Path(scene.render.filepath).relative_to(PACK)).replace("\\", "/"),
                   "objects": len(scene.objects), "mesh_objects": sum(o.type == "MESH" for o in scene.objects),
                   "camera": {"location": list(camera.location), "lens_mm": camera_data.lens}}


def main():
    protected = [ROOT / "assets/corn/SM_Prop_Plant_Corn_01_L_textured.fbx",
                 ROOT / "assets/corn/01_roblax_style_dry_corn.png",
                 ROOT / "assets/farm/SM_Bld_Barn_03_textured.fbx",
                 ROOT / "assets/farm/PolygonFarm_Texture_01_A.png",
                 PACK / "corn.blend", PACK / "environment.blend", PACK / "warden.blend",
                 ROOT / "place/Children_of_corn.rbxl"]
    protected_hashes = {str(p.relative_to(ROOT)).replace("\\", "/"): sha(p) for p in protected}
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.context.preferences.filepaths.save_version = 0
    original_scene = bpy.context.scene
    library_root = collection("Comparison_Source_Library_NotInScenes", original_scene.collection)
    environment = append_collections(PACK / "environment.blend", ["HW_BarnDark_Open", "HW_Fence_01", "HW_Fence_02", "HW_Fence_03"] + [f"HW_Rock_{i:02d}" for i in range(1, 6)])
    for coll in environment.values():
        library_root.children.link(coll)
    wardens = append_collections(PACK / "warden.blend", ["Warden_Classic", "Warden_Detailed"])
    new_corn = append_objects(PACK / "corn.blend", [f"Corn_{variant}_Near" for variant in "ABCD"])
    for obj in new_corn.values():
        library_root.objects.link(obj)
    global EXTRACTOR, SOIL, PATH_MATERIAL, FLAT_GROUND, FLAT_PATH
    spec = importlib.util.spec_from_file_location("showcase_original_fbx", ROOT / "scripts/export-farm-editable-mesh.py")
    EXTRACTOR = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(EXTRACTOR)
    original_corn_data = EXTRACTOR.extract(protected[0])
    height = original_corn_data["world_bounds"]["size"][1]
    old_corn_mat = image_material("OriginalCorn_DryAtlas", protected[1])
    old_corn = original_meshes(protected[0], old_corn_mat, 8 / height, "Original_", library_root, ground_origin=True)[0]
    barn_mat = image_material("OriginalBarn_RedAtlas", protected[3])
    barn_scale = json.loads((PACK / "environment-manifest.json").read_text(encoding="utf-8"))["barn_preservation"]["uniform_scale"]
    old_barn = original_meshes(protected[2], barn_mat, barn_scale, "OriginalRed_", library_root, omit_doors=True)
    SOIL = bpy.data.materials["HW_Soil_Ground"] if "HW_Soil_Ground" in bpy.data.materials else image_material("ShowcaseSoil", PACK / "textures/soil_gravel.png")
    PATH_MATERIAL = image_material("ShowcaseGravelPath", PACK / "textures/soil_gravel.png")
    FLAT_GROUND = image_material("CurrentGroundApproximation", None, (0.14, 0.095, 0.045))
    FLAT_PATH = image_material("CurrentDirtPathApproximation", None, (0.22, 0.165, 0.10))
    scene_a, row_a = build_scene("Variant_A_Current_Field", False, old_corn, old_barn, environment, wardens["Warden_Classic"])
    scene_b, row_b = build_scene("Variant_B_Detailed_Field", True, new_corn, old_barn, environment, wardens["Warden_Detailed"])
    bpy.context.window.scene = scene_b
    # Remove the temporary scene only; source-library datablocks remain available
    # for comparing original geometry, but do not belong to either render scene.
    bpy.data.scenes.remove(original_scene)
    for image in bpy.data.images:
        if image.source == "FILE" and image.filepath:
            if not image.packed_file:
                image.pack()
            image.filepath = bpy.path.relpath(bpy.path.abspath(image.filepath), start=str(PACK))
    for scene in (scene_a, scene_b):
        for screen in bpy.data.screens:
            for area in screen.areas:
                if area.type == "VIEW_3D":
                    area.spaces.active.region_3d.view_perspective = "CAMERA"
    blend = PACK / "comparison.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend), check_existing=False)
    for relative, expected in protected_hashes.items():
        assert sha(ROOT / relative) == expected, "Protected input changed: " + relative
    manifest = {"format": "ChildrenOfCorn_HarvestComparison_v1", "date": "2026-10-16", "seed": SEED,
                "blender": bpy.app.version_string, "status": "offline Blender asset preview; NOT game integration or Studio acceptance",
                "layout": "illustrative night scene; not the authored map, corn placement or Lighting",
                "units": "1 Blender unit = 1 intended Roblox stud", "scenes": [row_a, row_b],
                "original_corn_source_triangles": len(original_corn_data["meshes"][0]["triangles"]),
                "original_corn_height_normalized_to": 8, "original_corn_uv_retained": True,
                "active_scene": scene_b.name, "all_textures_packed": all(i.packed_file for i in bpy.data.images if i.source == "FILE"),
                "protected_inputs_unchanged": protected_hashes,
                "outputs": [{"path": str(p.relative_to(PACK)).replace("\\", "/"), "bytes": p.stat().st_size, "sha256": sha(p)}
                            for p in (blend, PREVIEW / "variant-a.png", PREVIEW / "variant-b.png")],
                "remaining": ["actual Roblox asset import and IDs", "rig/animation runtime adapter", "PointLight tuning", "two game copies and guarded installation", "gameplay and FPS acceptance"]}
    (PACK / "showcase-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("HARVEST_SHOWCASE_PASS=" + json.dumps({"scenes": [row_a, row_b], "all_textures_packed": manifest["all_textures_packed"]}))


if __name__ == "__main__":
    main()
