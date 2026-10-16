"""Build two original Harvest Warden art assets; never opens/writes a Roblox place.

Run with Blender's bundled Python, not the system interpreter:
  blender --background --factory-startup -t 4 --python scripts/blender/harvest_warden.py
Game units: 1 Blender unit = 1 intended Roblox stud. Import scale is checked later.
"""
from pathlib import Path
import bpy
import math
import random
import json
import hashlib
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/harvest-warden"
EXPORT = OUT / "exports/warden"
PREVIEW = OUT / "previews"
for folder in (OUT, EXPORT, PREVIEW):
    folder.mkdir(parents=True, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = 'NONE'
scene.render.fps = 24
scene.render.engine = 'CYCLES'
scene.cycles.samples = 28
scene.cycles.use_denoising = True
scene.render.resolution_x = 1500
scene.render.resolution_y = 1200
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.view_settings.view_transform = 'AgX'
scene.world = bpy.data.worlds.new('HarvestPreviewWorld')
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs[0].default_value = (.085, .105, .16, 1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value = .28


def material(name, color, texture=None, emission=0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = .93
    if texture:
        path = OUT / 'textures' / texture
        if not path.exists():
            raise FileNotFoundError(path)
        image = bpy.data.images.load(str(path), check_existing=True)
        tex = mat.node_tree.nodes.new('ShaderNodeTexImage')
        tex.image = image
        tex.extension = 'REPEAT'
        mat.node_tree.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    if emission:
        bsdf.inputs['Emission Color'].default_value = (*color, 1)
        bsdf.inputs['Emission Strength'].default_value = emission
    return mat


MATS = [
    material('DryMaize', (.47, .29, .09), 'corn_leaf_dry.png'),
    material('OldBurlap', (.40, .27, .14), 'burlap.png'),
    material('CharcoalFarmCoat', (.035, .029, .024), 'coat_canvas.png'),
    material('DarkCord', (.095, .061, .029)),
    material('LanternEye_Red', (1, .0002, .0001), emission=3),
    material('OldIronRim', (.042, .031, .026)),
]


class Geo:
    def __init__(self):
        self.vertices, self.faces, self.uvs, self.materials = [], [], [], []

    def face(self, points, uv, mat):
        clean_points, clean_uv = [], []
        for point, coord in zip(points, uv):
            if not clean_points or (Vector(point) - Vector(clean_points[-1])).length > 1e-7:
                clean_points.append(point)
                clean_uv.append(coord)
        if len(clean_points) > 2 and (Vector(clean_points[0]) - Vector(clean_points[-1])).length < 1e-7:
            clean_points.pop()
            clean_uv.pop()
        if len(clean_points) < 3:
            return
        points, uv = clean_points, clean_uv
        start = len(self.vertices)
        self.vertices.extend(tuple(p) for p in points)
        self.faces.append(tuple(range(start, start + len(points))))
        self.uvs.append(uv)
        self.materials.append(mat)

    def tube(self, points, radii, mat, sides=6, flatten=1):
        points = [Vector(p) for p in points]
        rings = []
        for i, (point, radius) in enumerate(zip(points, radii)):
            tangent = (points[min(i + 1, len(points) - 1)] - points[max(0, i - 1)]).normalized()
            axis = tangent.cross(Vector((0, 1, 0)))
            if axis.length < .1:
                axis = tangent.cross(Vector((1, 0, 0)))
            axis.normalize()
            other = tangent.cross(axis).normalized()
            rings.append([point + radius * (axis * math.cos(j * math.tau / sides)
                                            + other * math.sin(j * math.tau / sides) * flatten)
                          for j in range(sides)])
        for i in range(len(rings) - 1):
            for j in range(sides):
                k = (j + 1) % sides
                self.face([rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j]],
                          [(j / sides, i / 3), ((j + 1) / sides, i / 3),
                           ((j + 1) / sides, (i + 1) / 3), (j / sides, (i + 1) / 3)], mat)
        for index in (0, len(rings) - 1):
            ring = rings[index] if index else list(reversed(rings[index]))
            self.face(ring, [(0.5 + .5 * math.cos(j * math.tau / sides),
                             .5 + .5 * math.sin(j * math.tau / sides)) for j in range(sides)], mat)

    def ribbon(self, points, widths, mat, twist=.0):
        points = [Vector(p) for p in points]
        rings = []
        for i, (p, width) in enumerate(zip(points, widths)):
            angle = twist * i / max(1, len(points) - 1)
            across = Vector((math.cos(angle), math.sin(angle), .1 * math.sin(i)))
            rings.append([p - across * width / 2, p + Vector((0, -.035, 0)), p + across * width / 2])
        for i in range(len(rings) - 1):
            for j in range(2):
                self.face([rings[i][j], rings[i][j + 1], rings[i + 1][j + 1], rings[i + 1][j]],
                          [(j / 2, i / 3), ((j + 1) / 2, i / 3), ((j + 1) / 2, (i + 1) / 3),
                           (j / 2, (i + 1) / 3)], mat)

    def object(self, name, collection):
        mesh = bpy.data.meshes.new(name + '_Mesh')
        mesh.from_pydata(self.vertices, [], self.faces)
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        collection.objects.link(obj)
        for mat in MATS:
            mesh.materials.append(mat)
        uv_layer = mesh.uv_layers.new(name='UVMap')
        for poly, uv, material_index in zip(mesh.polygons, self.uvs, self.materials):
            poly.material_index = material_index
            for li, coordinate in zip(poly.loop_indices, uv):
                uv_layer.data[li].uv = coordinate
        # Weld coincident vertices, recalculate normals. Keep cloth leaves two-sided.
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.mesh.remove_doubles(threshold=.000001)
        bpy.ops.mesh.normals_make_consistent(inside=False)
        bpy.ops.object.mode_set(mode='OBJECT')
        obj.select_set(False)
        obj['corn_project_id'] = 'children_of_corn'
        obj['art_asset_version'] = 1
        obj['roblox_can_collide'] = False
        obj['roblox_can_query'] = False
        obj['roblox_can_touch'] = False
        return obj


def ellipsoid(geo, center, scale, mat, segments, rings, skew=0):
    cx, cy, cz = center
    for row in range(rings):
        a0, a1 = math.pi * row / rings, math.pi * (row + 1) / rings
        for col in range(segments):
            b0, b1 = math.tau * col / segments, math.tau * (col + 1) / segments
            def point(a, b):
                wobble = 1 + .035 * math.sin(b * 3 + a * 4)
                return (cx + math.sin(a) * math.cos(b) * scale[0] * wobble + skew * math.cos(a),
                        cy + math.sin(a) * math.sin(b) * scale[1] * wobble,
                        cz + math.cos(a) * scale[2])
            geo.face([point(a0, b0), point(a0, b1), point(a1, b1), point(a1, b0)],
                     [(col / segments, row / rings), ((col + 1) / segments, row / rings),
                      ((col + 1) / segments, (row + 1) / rings), (col / segments, (row + 1) / rings)], mat)


def ring_cord(geo, center, rx, ry, mat=3, sides=14, radius=.025):
    points = [(center[0] + rx * math.cos(i * math.tau / sides),
               center[1] + ry * math.sin(i * math.tau / sides), center[2]) for i in range(sides + 1)]
    geo.tube(points, [radius] * len(points), mat, sides=4)


def stalk_bundle(geo, a, b, radius, count, rng, detailed):
    a, b = Vector(a), Vector(b)
    core = .61 if detailed else 1
    geo.tube([a, (a + b) / 2, b], [radius * core, radius * .87 * core, radius * .65 * core], 0,
             sides=8 if detailed else 5)
    for i in range(count):
        angle = i * math.tau / count + rng.uniform(-.2, .2)
        offset = Vector((math.cos(angle), math.sin(angle), 0)) * radius * .8
        mid = (a + b) / 2 + offset * .8 + Vector((rng.uniform(-.05, .05), 0, 0))
        end = b + offset + Vector((rng.uniform(-.08, .08), rng.uniform(-.07, .07), rng.uniform(-.16, .16)))
        geo.tube([a + offset * .7, mid, end], [.034, .025, .009], 0, sides=4 if detailed else 3)
        if detailed and i % 3 == 0:
            tip = end + Vector((math.cos(angle) * .18, math.sin(angle) * .20, -.28))
            geo.ribbon([mid, end, tip], [.06, .09, .002], 0, twist=angle)


def sack(geo, detailed):
    segments = 20 if detailed else 10
    rows = [(6.85, .25, .23), (7.03, .45, .32), (7.46, .57, .43),
            (7.97, .54, .41), (8.38, .49, .33), (8.48, .38, .25)]
    points = []
    for r, (z, rx, ry) in enumerate(rows):
        ring = []
        for j in range(segments):
            angle = math.tau * j / segments
            co, si = math.cos(angle), math.sin(angle)
            x = math.copysign(abs(co) ** .60, co) * rx
            y = math.copysign(abs(si) ** .65, si) * ry
            crease = .025 * math.sin(angle * 5 + r * .85)
            ring.append((x + (z - 7.64) * .13 + crease, y + crease * .6,
                         z + .028 * math.sin(angle * 3 + .4)))
        points.append(ring)
    for r in range(len(rows) - 1):
        for j in range(segments):
            k = (j + 1) % segments
            geo.face([points[r][j], points[r][k], points[r + 1][k], points[r + 1][j]],
                     [(j / segments, r / 5), ((j + 1) / segments, r / 5),
                      ((j + 1) / segments, (r + 1) / 5), (j / segments, (r + 1) / 5)], 1)
    geo.face(list(reversed(points[0])), [(j / segments, 0) for j in range(segments)], 1)
    geo.face(points[-1], [(j / segments, 1) for j in range(segments)], 1)


def build(variant, detailed):
    rng = random.Random(371 if detailed else 372)
    collection = bpy.data.collections.new('Warden_' + variant)
    scene.collection.children.link(collection)
    parts = {name: Geo() for name in ['Coat', 'LeftArm', 'RightArm', 'LeftLeg', 'RightLeg',
                                    'Head', 'Hat', 'LeftEye', 'RightEye']}
    coat = parts['Coat']
    stalk_bundle(coat, (0, 0, 3.5), (0, 0, 6.7), .46, 10 if detailed else 4, rng, detailed)
    # Open-front, irregularly torn coat, with actual thickness at the cut edges.
    rows = [(3.15, .87, .49), (4.0, .76, .45), (5.05, .68, .40), (6.25, 1.03, .45), (6.65, .55, .32)]
    cols = 22 if detailed else 12
    coat_rings = []
    for row, (z, rx, ry) in enumerate(rows):
        ring = []
        for j in range(cols + 1):
            a = -.5 * math.pi + .24 + (math.tau - .48) * j / cols
            ragged = rng.uniform(-.28, .08) if row == 0 else rng.uniform(-.035, .035)
            ring.append((rx * math.cos(a), ry * math.sin(a), z + ragged))
        coat_rings.append(ring)
    for row in range(len(rows) - 1):
        for col in range(cols):
            if row == 0 and col % 5 == 2:
                continue
            points = [coat_rings[row][col], coat_rings[row][col + 1],
                      coat_rings[row + 1][col + 1], coat_rings[row + 1][col]]
            coat.face(points, [(col / cols * 2, row / 2), ((col + 1) / cols * 2, row / 2),
                              ((col + 1) / cols * 2, (row + 1) / 2), (col / cols * 2, (row + 1) / 2)], 2)
    # Folded lapels, asymmetric loose hems and a stitched pocket.
    for side in (-1, 1):
        coat.face([(side * .22, -.36, 6.65), (side * .58, -.44, 6.25),
                   (side * .31, -.57, 5.8), (side * .08, -.49, 6.05)],
                  [(0, 0), (1, 0), (1, 1), (0, 1)], 2)
        for j in range(3 if detailed else 1):
            x = side * (.45 + j * .11)
            coat.ribbon([(x, -.48, 3.6), (x + side * .06, -.5, 3.0),
                         (x + side * .13, -.46, 2.6 + .13 * j)], [.17, .18, .005], 2, side * .4)
    if detailed:
        coat.face([(.34, -.46, 4.75), (.65, -.46, 4.75), (.65, -.5, 4.35), (.34, -.5, 4.35)],
                  [(0, 0), (.5, 0), (.5, .5), (0, .5)], 2)
        for z in (5.65, 5.17, 4.7):
            ellipsoid(coat, (.13, -.49, z), (.045, .025, .045), 5, 6, 3)

    for side, arm_name, leg_name in [(-1, 'LeftArm', 'LeftLeg'), (1, 'RightArm', 'RightLeg')]:
        arm = parts[arm_name]
        shoulder = (side * .90, 0, 6.38)
        elbow = (side * 1.32, -.02, 4.90)
        wrist = (side * (1.64 if side < 0 else 1.48), -.07, 2.95 if side < 0 else 3.85)
        arm.tube([shoulder, (side * 1.12, 0, 5.75), elbow, (side * 1.38, -.025, 4.55)],
                 [.36, .35, .29, .30], 2, sides=12 if detailed else 7)
        stalk_bundle(arm, elbow, wrist, .24, 9 if detailed else 3, rng, detailed)
        ring_cord(arm, (side * 1.4, -.04, 4.30), .255, .24, sides=12 if detailed else 8, radius=.045)
        ring_cord(arm, wrist, .18, .17, sides=12 if detailed else 8, radius=.045)
        # Sparse crooked stalk fingers: genuine geometry, attached to their arm section.
        for finger in range(4):
            x = wrist[0] + (finger - 1.5) * .12
            z = wrist[2] - .16
            length = (.85 if side < 0 else .58) * (1 - abs(finger - 1.5) * .12)
            arm.tube([(x, -.11, z), (x + side * .08, -.20, z - length * .55),
                      (x + side * .12, -.37, z - length)], [.049, .036, .009], 0, sides=5 if detailed else 3)
        arm.tube([(wrist[0] - side * .2, -.04, wrist[2]),
                  (wrist[0] - side * .35, -.13, wrist[2] - .35),
                  (wrist[0] - side * .25, -.26, wrist[2] - .52)], [.06, .045, .012], 0, sides=5)
        leg = parts[leg_name]
        hip, knee, ankle = (side * .37, 0, 3.75), (side * .45, .06, 2.0), (side * .49, -.03, .35)
        stalk_bundle(leg, hip, knee, .26, 9 if detailed else 4, rng, detailed)
        stalk_bundle(leg, knee, ankle, .24, 8 if detailed else 3, rng, detailed)
        for z, rx in ((2.35, .26), (1.05, .22), (.45, .19)):
            ring_cord(leg, (side * .47, 0, z), rx, rx, sides=12 if detailed else 8, radius=.043)
        for toe in range(4):
            x = side * .48 + (toe - 1.5) * .1
            leg.tube([(x, 0, .3), (x + side * .03, -.28, .13),
                      (x + side * .06, -.49 - toe * .035, .055)], [.055, .041, .014], 0, sides=5 if detailed else 3)

    head = parts['Head']
    sack(head, detailed)
    ring_cord(head, (.00, .0, 6.94), .31, .28, sides=16 if detailed else 10, radius=.045)
    # The stitched sack seam is modeled, not a face baked into the texture.
    for i in range(13 if detailed else 7):
        z = 7.04 + i * (1.34 / (13 if detailed else 7))
        seam_x = .05 + (z - 7.64) * .16
        y = -.43 * math.sqrt(max(.1, 1 - ((z - 7.64) / .84) ** 2)) - .025
        head.tube([(seam_x - .052, y, z - .016), (seam_x + .055, y - .008, z + .02)],
                  [.014, .014], 3, sides=4 if detailed else 3)
    # "Hat" compatibility section is a dry husk collar; this design has no hat.
    collar = parts['Hat']
    for i in range(22 if detailed else 10):
        angle = i * math.tau / (22 if detailed else 10)
        base = Vector((.26 * math.cos(angle), .22 * math.sin(angle), 6.8))
        tip = base + Vector((.45 * math.cos(angle), .38 * math.sin(angle), rng.uniform(.1, .45)))
        collar.ribbon([base, (base + tip) / 2 + Vector((0, 0, .10)), tip], [.12, .18, .002], 0, twist=angle)

    for side, name in [(-1, 'LeftEye'), (1, 'RightEye')]:
        geo = parts[name]
        center = (side * .24 + .06, -.431, 7.71 + side * .025)
        ellipsoid(geo, center, (.193, .092, .193), 4, 14 if detailed else 8, 8 if detailed else 5)
        # Thin iron rim keeps the two lantern eyes readable against burlap.
        points = [(center[0] + .205 * math.cos(i * math.tau / 20), -.46,
                   center[2] + .205 * math.sin(i * math.tau / 20)) for i in range(21)]
        geo.tube(points, [.014] * len(points), 5, sides=5 if detailed else 3)
        # Ragged brow shadows integrate lights into the sack rather than goggles.
        head.ribbon([(center[0] - .22, -.44, center[2] + .22),
                     (center[0], -.51, center[2] + .19),
                     (center[0] + .20, -.45, center[2] + .22)], [.10, .14, .03], 1, twist=.4)

    objects = {name: geo.object(name, collection) for name, geo in parts.items()}
    # Real rigid-weight armature, with actual animation clips. Movement/AI remains Roblox's job.
    armature = bpy.data.armatures.new('Warden_' + variant + '_Bones')
    rig = bpy.data.objects.new('Warden_' + variant + '_Rig', armature)
    collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    root = armature.edit_bones.new('Root')
    root.head, root.tail = (0, 0, 0), (0, 0, 1)
    coordinates = {
        'Coat': ((0, 0, 3.7), (0, 0, 6.2)),
        'LeftLeg': ((-.37, 0, 3.75), (-.49, 0, .35)),
        'RightLeg': ((.37, 0, 3.75), (.49, 0, .35)),
        'LeftArm': ((-.9, 0, 6.38), (-1.64, -.07, 2.95)),
        'RightArm': ((.9, 0, 6.38), (1.48, -.07, 3.85)),
        'Head': ((0, 0, 6.85), (.06, 0, 8.42)),
        'Hat': ((0, 0, 6.8), (0, 0, 7.0)),
        'LeftEye': ((-.18, -.41, 7.71), (-.18, -.41, 7.92)),
        'RightEye': ((.30, -.41, 7.735), (.30, -.41, 7.945)),
    }
    for name, (head_pos, tail_pos) in coordinates.items():
        bone = armature.edit_bones.new(name)
        bone.head, bone.tail = head_pos, tail_pos
        bone.parent = armature.edit_bones['Head'] if name in ('Hat', 'LeftEye', 'RightEye') else root
    bpy.ops.object.mode_set(mode='OBJECT')
    rig.select_set(False)
    for name, obj in objects.items():
        group = obj.vertex_groups.new(name=name)
        group.add(list(range(len(obj.data.vertices))), 1, 'REPLACE')
        modifier = obj.modifiers.new('RigidSectionArmature', 'ARMATURE')
        modifier.object = rig
        obj.parent = rig
        obj['section_name'] = name
        obj['units'] = 'stud'
        obj['pivot_studs'] = list(coordinates[name][0])
    rig['variant'] = variant
    rig['units'] = 'stud'
    rig['roblox_runtime_adapter_required'] = True
    rig['suggested_eye_range_studs'] = 24
    rig['suggested_eye_brightness'] = 3
    actions = []
    for label, duration, amplitude in [('Idle', 72, .025), ('Walk', 32, .24), ('Chase', 22, .40),
                                        ('Trapped', 30, .10), ('Capture', 18, .0)]:
        action = bpy.data.actions.new(variant + '_' + label)
        rig.animation_data_create()
        rig.animation_data.action = action
        for frame in range(1, duration + 2, max(1, duration // 8)):
            t = (frame - 1) / duration * math.tau
            for name in coordinates:
                bone = rig.pose.bones[name]
                bone.rotation_mode = 'XYZ'
                bone.rotation_euler = (0, 0, 0)
                if 'Leg' in name:
                    bone.rotation_euler.x = math.sin(t) * amplitude * (-1 if name.startswith('Left') else 1)
                elif 'Arm' in name:
                    side = -1 if name.startswith('Left') else 1
                    bone.rotation_euler.x = -math.sin(t) * amplitude * .55 * side
                    bone.rotation_euler.z = side * (.07 + (.14 if label == 'Chase' else 0))
                    if label == 'Capture':
                        bone.rotation_euler.x = -.90 * min(1, (frame - 1) / duration * 2)
                elif name == 'Head':
                    bone.rotation_euler.z = .07 + math.sin(t) * .035
                elif name == 'Coat':
                    bone.rotation_euler.z = math.sin(t) * amplitude * .09
                bone.keyframe_insert(data_path='rotation_euler', frame=frame, group=name)
        track = rig.animation_data.nla_tracks.new()
        track.name = label
        strip = track.strips.new(label, 1, action)
        strip.action_frame_start, strip.action_frame_end = 1, duration + 1
        track.mute = True
        actions.append({'name': label, 'action': action.name, 'frames': duration + 1,
                        'seconds_at_24fps': round(duration / 24, 4)})
    rig.animation_data.action = None
    for bone in rig.pose.bones:
        bone.rotation_euler = (0, 0, 0)
    return collection, rig, objects, actions


def stats(obj):
    mesh = obj.data
    mesh.calc_loop_triangles()
    coords = [obj.matrix_world @ v.co for v in mesh.vertices]
    for vertex in coords:
        assert all(math.isfinite(v) for v in vertex), obj.name
    assert mesh.uv_layers.active and len(mesh.uv_layers.active.data) == len(mesh.loops)
    for uv in mesh.uv_layers.active.data:
        assert all(math.isfinite(v) for v in uv.uv)
    return {'vertices': len(mesh.vertices), 'triangles': len(mesh.loop_triangles),
            'bounds_studs': [[round(min(v[i] for v in coords), 6) for i in range(3)],
                             [round(max(v[i] for v in coords), 6) for i in range(3)]],
            'uv_corners': len(mesh.loops)}


def select(objects):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]


def export(variant, rig, objects, actions):
    members = [rig, *objects.values()]
    select(members)
    folder = EXPORT / variant.lower()
    folder.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.fbx(filepath=str(folder / 'HarvestWarden.fbx'), use_selection=True,
                             object_types={'MESH', 'ARMATURE'}, add_leaf_bones=False,
                             bake_anim=False, bake_anim_use_all_actions=False, bake_anim_use_nla_strips=False,
                             bake_anim_simplify_factor=0, path_mode='COPY', embed_textures=True,
                             apply_unit_scale=False, axis_forward='-Z', axis_up='Y')
    bpy.ops.export_scene.gltf(filepath=str(folder / 'HarvestWarden.glb'), export_format='GLB',
                              use_selection=True, export_extras=True, export_animations=True,
                              export_animation_mode='ACTIONS', export_anim_single_armature=False,
                              export_yup=True)
    animation_folder = folder / 'animations'
    animation_folder.mkdir(exist_ok=True)
    for item in actions:
        rig.animation_data.action = bpy.data.actions[item['action']]
        scene.frame_start, scene.frame_end = 1, item['frames']
        select([rig])
        bpy.ops.export_scene.fbx(filepath=str(animation_folder / (item['name'] + '.fbx')),
                                 use_selection=True, object_types={'ARMATURE'}, add_leaf_bones=False,
                                 bake_anim=True, bake_anim_use_all_actions=False,
                                 bake_anim_use_nla_strips=False, bake_anim_simplify_factor=0,
                                 apply_unit_scale=False, axis_forward='-Z', axis_up='Y')
    rig.animation_data.action = None
    scene.frame_start, scene.frame_end = 1, 73
    for bone in rig.pose.bones:
        bone.rotation_euler = (0, 0, 0)
    record = {name: stats(obj) for name, obj in objects.items()}
    # A neutral, auditable data representation for the existing EditableMesh pipeline.
    neutral = {'units': 'stud', 'coordinate_system': 'RobloxYUp; front=+Z', 'sections': {}}
    for name, obj in objects.items():
        mesh = obj.data
        mesh.calc_loop_triangles()
        neutral['sections'][name] = {
            'vertices': [[round(v.co.x, 6), round(v.co.z, 6), round(-v.co.y, 6)] for v in mesh.vertices],
            'triangles': [list(t.vertices) for t in mesh.loop_triangles],
            'triangle_uvs': [[[round(mesh.uv_layers.active.data[i].uv.x, 6),
                               round(1 - mesh.uv_layers.active.data[i].uv.y, 6)] for i in t.loops]
                             for t in mesh.loop_triangles],
            'triangle_materials': [t.material_index for t in mesh.loop_triangles],
            'pivot': [obj['pivot_studs'][0], obj['pivot_studs'][2], -obj['pivot_studs'][1]],
        }
    (folder / 'mesh-data.json').write_text(json.dumps(neutral, separators=(',', ':')), encoding='utf-8')
    return {'variant': variant, 'objects': record, 'triangles': sum(v['triangles'] for v in record.values()),
            'bone_count': len(rig.data.bones), 'animations': actions,
            'directory': str(folder.relative_to(ROOT)).replace('\\', '/')}


def area(name, location, energy, color, size, target):
    light = bpy.data.lights.new(name, 'AREA')
    light.energy, light.color, light.shape, light.size = energy, color, 'DISK', size
    obj = bpy.data.objects.new(name, light)
    scene.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()
    return obj


def render(collection, rig, name):
    for col in (col_a, col_b):
        col.hide_render = col != collection
    camera.location = (10, -16, 7.9)
    camera.rotation_euler = (Vector((0, 0, 4.5)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
    scene.render.filepath = str(PREVIEW / name)
    scene.frame_set(1)
    bpy.ops.render.render(write_still=True)


col_a, rig_a, obj_a, actions_a = build('Classic', False)
col_b, rig_b, obj_b, actions_b = build('Detailed', True)
reports = [export('Classic', rig_a, obj_a, actions_a), export('Detailed', rig_b, obj_b, actions_b)]
scene.render.fps = 24
scene.frame_start, scene.frame_end = 1, 72

# Preview floor/lights never included in individual exports.
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.015))
floor = bpy.context.object
floor.name = 'PREVIEW_ONLY_Floor'
floor.data.materials.append(material('PreviewFloor', (.025, .033, .045)))
area('ColdMoon', (-5, -3, 13), 1500, (.49, .66, 1), 7, (0, 0, 4))
area('BarnWarmFill', (4, 3, 7), 1900, (1, .52, .20), 5, (0, 0, 4))
area('SoftFrontReadability', (1, -8, 7), 700, (.8, .84, 1), 6, (0, 0, 5))
for side in (-1, 1):
    light = bpy.data.lights.new('PREVIEW_ONLY_RedEye_' + str(side), 'POINT')
    light.color, light.energy, light.shadow_soft_size = (1, .005, .002), 7, .12
    eye = bpy.data.objects.new(light.name, light)
    scene.collection.objects.link(eye)
    eye.location = (side * .24 + .06, -.7, 7.72)

camera_data = bpy.data.cameras.new('PreviewCamera')
camera = bpy.data.objects.new('PreviewCamera', camera_data)
scene.collection.objects.link(camera)
camera_data.lens = 56
scene.camera = camera

# Lightweight compositor bloom makes the emissive-eye goal visible in previews.
tree = bpy.data.node_groups.new('HarvestPreviewCompositor', 'CompositorNodeTree')
scene.compositing_node_group = tree
tree.interface.new_socket(name='Image', in_out='OUTPUT', socket_type='NodeSocketColor')
layer = tree.nodes.new('CompositorNodeRLayers')
glare = tree.nodes.new('CompositorNodeGlare')
glare.inputs['Type'].default_value = 'Fog Glow'
composite = tree.nodes.new('NodeGroupOutput')
tree.links.new(layer.outputs['Image'], glare.inputs['Image'])
tree.links.new(glare.outputs['Image'], composite.inputs['Image'])

render(col_a, rig_a, 'warden_classic.png')
render(col_b, rig_b, 'warden_detailed.png')
col_a.hide_render = True
col_b.hide_render = False
bpy.ops.file.pack_all()
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'warden.blend'))
manifest = {
    'asset_pack': 'Harvest Warden', 'date': '2026-10-16', 'blender': bpy.app.version_string,
    'original_design': True, 'unit': '1 Blender unit = 1 intended Roblox stud',
    'engine_import_and_playtest': 'PENDING; offline assets only; no Roblox scene changed',
    'animation_note': 'Rigid sections with a real 10-bone armature and five exported clips; not a Roblox Humanoid.',
    'eye_light_note': 'Emissive geometry is exported. Add Roblox PointLight with initial Range24/Brightness3 per eye; tune in engine.',
    'variants': reports,
    'source_textures': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (OUT / 'textures').glob('*.png')},
}
(OUT / 'warden-manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
print('HARVEST_WARDEN_RESULT ' + json.dumps({'ok': True, 'variants': reports}))
