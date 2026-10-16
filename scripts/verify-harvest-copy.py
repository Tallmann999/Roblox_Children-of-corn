"""Strict read-only audit of an engine-saved Harvest A or B copy.

Normal verification requires an independently reviewed, hash-pinned full new-node
manifest. --audit-new-nodes performs preservation/closed-contract checks and emits
an explicitly INCOMPLETE first-save review report; it never approves its own input.
No scene is reconstructed, serialized, promoted or overwritten.
"""
import argparse
import copy
import hashlib
import importlib.util
import json
import math
import re
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / "place/Children_of_corn.before-harvest-art-20261016.rbxl"
BASELINE_HASH = "b5084774be98e97a045c6b90a819bdd061b8d4f61b259c3a6e4eb77233ff2646"
BASELINE_BYTES = 1003371
PAYLOAD = ROOT / ".artifacts/harvest-install/payload.json"
CATALOG = ROOT / "assets/harvest-warden/roblox-catalog.json"
MAP = "Workspace/CornMap"
DECOR = MAP + "/HarvestDecor"
HOME = MAP + "/Props/ScarecrowMarker/HarvestWardenHome"
OWNER = "harvest_warden_v1"
PROJECT = "children_of_corn"
HOUSES = ("HouseWest", "HouseEast", "HouseNorthWest")
ORIGINAL_PARTS = ("SM_Bld_Barn_03", "SM_Bld_Barn_03_Shutter_01", "SM_Bld_Barn_03_Shutter_02")
HOME_PARTS = tuple(MAP + "/Props/ScarecrowMarker/" + name for name in ("Head", "Arms", "Body"))
BARN_PARTS = frozenset(MAP + "/Props/" + house + "/" + name for house in HOUSES for name in ORIGINAL_PARTS)
spec = importlib.util.spec_from_file_location("harvest_save_helpers", ROOT / "scripts/verify-multiplayer-copy.py")
old = importlib.util.module_from_spec(spec)
spec.loader.exec_module(old)
r, fog = old.r, old.fog
require, sha256, load_json = r.require, r.sha256, r.load_json
identity, remap_refs = old.helpers.helpers.identity, old.helpers.helpers.remap_refs
GUID = old.GUID
spec = importlib.util.spec_from_file_location("harvest_typed_helpers", ROOT / "scripts/verify-farm-copy.py")
typed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(typed)


def mapping(payload_path=PAYLOAD, sourcemap_path=ROOT / "build/sourcemap.json"):
    payload = load_json(payload_path)
    require(payload["version"] == 1 and payload["owner"] == OWNER and payload["baselineSha256"] == BASELINE_HASH, "Unknown Harvest source payload")
    require(tuple(payload["roots"]) == tuple(r.p.OWNED), "Harvest code roots changed")
    sources, classes = {}, {}
    def walk(node, prefix=None):
        path = "" if prefix is None else (prefix + "/" + node["name"] if prefix else node["name"])
        if r.p.owned(path):
            require(path not in classes, "Duplicate configured code path")
            classes[path] = node["className"]
        files = [name for name in node.get("filePaths", []) if name.startswith("src/") and name.endswith(".luau")]
        require(len(files) <= 1, "Ambiguous source path")
        if files:
            file = (ROOT / files[0]).resolve()
            require(r.p.owned(path) and file.is_relative_to((ROOT / "src").resolve()), "Source outside owned roots")
            sources[path] = file.read_text(encoding="utf-8").replace("\r\n", "\n")
        for child in node.get("children", []): walk(child, path)
    walk(load_json(sourcemap_path))
    require(classes == payload["classes"] and len(sources) == 150, "Stale Harvest sourcemap/payload; expected 150 project Sources")
    entries = {row["path"]: row for row in payload["entries"]}
    assets = fog.current_sources()
    require(len(entries) == len(payload["entries"]) == 153 and set(entries) == set(sources) | set(assets), "Harvest entry set differs")
    for path, source in (sources | assets).items():
        require(hashlib.sha256(source.encode()).hexdigest() == entries[path]["after"] and (path not in classes or entries[path]["class"] == classes[path]), "Source differs from accepted payload: " + path)
    additions = {row["path"]: row["class"] for row in payload["addedNodes"]}
    require(len(additions) == len(payload["addedNodes"]) == 73 and set(additions) == set(classes) - set(payload["beforeClasses"]), "Expected exactly 73 new Source modules")
    require(all(cls == "ModuleScript" and path in sources for path, cls in additions.items()), "Unexpected new code container")
    declared = {path for path, row in entries.items() if row.get("before") and row["before"] != row["after"]}
    require(len(declared) == 8, "Expected eight existing Harvest Source changes")
    return payload, sources, classes, additions, declared


def frame(position=(0, 0, 0), rotation=(1, 0, 0, 0, 1, 0, 0, 0, 1)):
    return list(position) + list(rotation)


def transform(a, b):
    ap, ar, bp, br = a[:3], a[3:], b[:3], b[3:]
    position = [ap[i] + sum(ar[i * 3 + k] * bp[k] for k in range(3)) for i in range(3)]
    rotation = [sum(ar[i * 3 + k] * br[k * 3 + j] for k in range(3)) for i in range(3) for j in range(3)]
    return frame(position, rotation)


def yaw(angle):
    c, s = math.cos(angle), math.sin(angle)
    return frame(rotation=(c, 0, s, 0, 1, 0, -s, 0, c))


def tv(kind, value): return {"type": kind, "value": value}


def basepart_color(channels):
    # BasePart.Color is backed by Color3uint8. The engine truncates each
    # float32 channel; World then snapshots the resulting property value.
    return [math.floor(struct.unpack("<f", struct.pack("<f", channel))[0] * 255) / 255 for channel in channels]


def world_contract(baseline_typed, catalog, variant):
    """Independent closed placement/catalog contract matching the guarded authoring module."""
    require(variant in ("A", "B") and catalog["version"] == 1 and catalog["owner"] == OWNER, "Unknown Harvest art contract")
    specs = {}
    owner = {"corn_project_id": tv("string", PROJECT), "HarvestGeometryOwner": tv("string", OWNER)}
    def add(path, cls, attrs=None, props=None):
        require(path not in specs, "Duplicate Harvest contract path")
        specs[path] = {"class": cls, "attributes": owner | (attrs or {}), "properties": props or {}, "tags": []}
    def part(path, cls, branch, cf, size, texture="", color=(1, 1, 1), material="Plastic", cast=True, attrs=None):
        color = basepart_color(color)
        visible = 0 if branch == "Common" or branch == variant else 1
        extra = {"HarvestBranch": tv("string", branch), "HarvestPlacedFrame": tv("CFrame", cf), "HarvestPlacedSize": tv("Vector3", size), "HarvestVisibleTransparency": tv("number", 0), "HarvestTexture": tv("string", texture), "HarvestColor": tv("Color3", list(color)), "HarvestMaterial": tv("string", material), "HarvestCastShadow": tv("boolean", cast)}
        props = {"CFrame": tv("CFrame", cf), "Size": tv("Vector3", size), "Transparency": tv("number", visible), "Anchored": tv("boolean", True), "CanCollide": tv("boolean", False), "CanTouch": tv("boolean", False), "CanQuery": tv("boolean", False), "CastShadow": tv("boolean", cast), "Color": tv("Color3", list(color)), "Material": {"type": "EnumItem", "name": material}}
        add(path, cls, extra | (attrs or {}), props)
    def clone(asset_key, path, cf, branch, scale=1):
        add(path, "Model", {"HarvestAssetKey": tv("string", asset_key)})
        for mesh_key in catalog["assets"][asset_key]["meshes"]:
            mesh = catalog["meshes"][mesh_key]
            name = mesh["name"] + "_Material" + mesh_key.rsplit("/", 1)[1]
            center = mesh["center"]
            attrs = {"HarvestAssetKey": tv("string", asset_key), "HarvestMeshKey": tv("string", mesh_key), "HarvestOffset": tv("CFrame", frame(center))}
            if mesh.get("section"): attrs["HarvestSection"] = tv("string", mesh["section"])
            part(path + "/" + name, "MeshPart", branch, transform(cf, frame([v * scale for v in center])), [v * scale for v in mesh["size"]], mesh["textureId"], mesh["color"], mesh["material"], True, attrs)
    ground = baseline_typed[MAP + "/Ground"]["properties"]
    road = baseline_typed[MAP + "/Props/VillageRoad/RoadSurface"]["properties"]
    ground_cf, ground_size = ground["CFrame"]["value"], ground["Size"]["value"]
    road_cf, road_size = road["CFrame"]["value"], road["Size"]["value"]
    floor = ground_cf[1] + ground_size[1] / 2
    add(DECOR, "Folder", {"HarvestWorldVersion": tv("number", 1), "HarvestGroundFrame": ground["CFrame"], "HarvestGroundSize": ground["Size"], "HarvestRoadFrame": road["CFrame"], "HarvestRoadSize": road["Size"], "HarvestCommonModels": tv("number", 39), "HarvestAppliedVariant": tv("string", variant)})
    add(DECOR + "/Common", "Folder")
    add(DECOR + "/VariantB", "Folder")
    for house_index, house in enumerate(HOUSES, 1):
        source = baseline_typed[MAP + "/Props/" + house + "/SM_Bld_Barn_03"]["properties"]["CFrame"]["value"]
        origin = frame((source[0], floor, source[2]), source[3:])
        for side in (-1, 1):
            for index, x in enumerate((-6, 6), 1):
                key = "Fence_0" + str((house_index + index + (1 if side == 1 else 0)) % 3 + 1)
                clone(key, DECOR + f"/Common/{house}_Fence_{side}_{index}", transform(origin, frame((x, 0, side * 12.5))), "Common")
        for index in range(1, 6):
            cf = transform(transform(origin, frame((-15 - index % 2 * 1.8, 0, (index - 3) * 3.3))), yaw(index * 1.73))
            clone("Rock_0" + str(index), DECOR + f"/Common/{house}_Rock_{index}", cf, "Common")
    for side in (-1, 1):
        for index, z in enumerate((-240, -140, -60, 60, 140, 240), 1):
            clone("Fence_0" + str(index % 3 + 1), DECOR + f"/Common/RoadFence_{side}_{index}", transform(frame((side * 11.5, floor, z)), yaw(math.pi / 2)), "Common")
    barn_keys = catalog["assets"]["BarnDark_Open"]["meshes"]
    for house in HOUSES:
        for name in ORIGINAL_PARTS:
            source = baseline_typed[MAP + "/Props/" + house + "/" + name]["properties"]
            selected = [key for key in barn_keys if catalog["meshes"][key]["sourceName"].removeprefix("HW_Dark_").removesuffix("_Export") == name]
            low = [min(catalog["meshes"][key]["center"][i] - catalog["meshes"][key]["size"][i] / 2 for key in selected) for i in range(3)]
            high = [max(catalog["meshes"][key]["center"][i] + catalog["meshes"][key]["size"][i] / 2 for key in selected) for i in range(3)]
            center = [(a + b) / 2 for a, b in zip(low, high)]
            ratio = [source["Size"]["value"][i] / (high[i] - low[i]) for i in range(3)]
            for index, key in enumerate(selected, 1):
                mesh = catalog["meshes"][key]
                cf = transform(source["CFrame"]["value"], frame([(mesh["center"][i] - center[i]) * ratio[i] for i in range(3)]))
                attrs = {"HarvestAssetKey": tv("string", "BarnDark_Open"), "HarvestMeshKey": tv("string", key), "HarvestOffset": tv("CFrame", frame(mesh["center"])), "HarvestSourceHouse": tv("string", house), "HarvestSourceName": tv("string", name), "HarvestSourceFrame": source["CFrame"], "HarvestSourceSize": source["Size"], "HarvestSourceTransparency": tv("number", 0)}
                part(DECOR + f"/VariantB/{house}_{name}_{index}", "MeshPart", "B", cf, [mesh["size"][i] * ratio[i] for i in range(3)], mesh["textureId"], mesh["color"], mesh["material"], True, attrs)
    for name, props, offset in (("GroundSurface", ground, 0.015), ("RoadSurface", road, 0.035)):
        cf, size = props["CFrame"]["value"], props["Size"]["value"]
        path = DECOR + "/VariantB/" + name
        part(path, "Part", "B", transform(cf, frame((0, size[1] / 2 + offset, 0))), [size[0], 0.02, size[2]], color=[104 / 255, 86 / 255, 66 / 255], material="Ground", cast=False)
        texture = catalog["textures"]["soil_gravel"]
        add(path + "/HarvestSurface", "Texture", {"HarvestTexture": tv("string", texture), "HarvestTileSize": tv("number", 8), "HarvestBranch": tv("string", "B"), "HarvestVisibleTransparency": tv("number", 0)})
    home_attrs = {"HarvestWorldVersion": tv("number", 1), "HarvestAppliedVariant": tv("string", variant)}
    for path in HOME_PARTS:
        props = baseline_typed[path]["properties"]
        name = path.rsplit("/", 1)[1]
        home_attrs |= {name + "SourceFrame": props["CFrame"], name + "SourceSize": props["Size"], name + "SourceTransparency": tv("number", 0)}
    add(HOME, "Folder", home_attrs)
    head = baseline_typed[HOME_PARTS[0]]["properties"]["CFrame"]["value"]
    home_frame = transform(frame((head[0], floor, head[2])), yaw(math.pi))
    clone("WardenClassic", HOME + "/Classic", home_frame, "A", 1.3)
    clone("WardenDetailed", HOME + "/Detailed", home_frame, "B", 1.3)
    for path, record in specs.items():
        record["attributes"] |= {"HarvestExpectedName": tv("string", path.rsplit("/", 1)[1]), "HarvestExpectedChildren": tv("number", sum(other.rpartition("/")[0] == path for other in specs))}
    require(len(specs) == 291 and sum(row["class"] in ("Part", "MeshPart") for row in specs.values()) == 244, "Harvest placement/catalog contract changed")
    return specs


def matches(actual, expected):
    require(isinstance(actual, dict) and actual.get("type") == expected["type"], "Typed value kind differs")
    kind, a, b = actual["type"], actual.get("value"), expected.get("value")
    if kind == "EnumItem" and "name" in expected:
        return a.get("enum") == "Enum.Material" and a.get("name") == expected["name"]
    if kind in ("CFrame", "Vector3", "Color3"):
        require(isinstance(a, list) and len(a) == (12 if kind == "CFrame" else 3), "Malformed typed vector/frame")
        for index, (x, y) in enumerate(zip(a, b)):
            tolerance = 0.5 / 255 + 1e-7 if kind == "Color3" else 2e-6 if kind == "CFrame" and index >= 3 else 0.00015
            if not math.isfinite(x) or not math.isfinite(y) or abs(x - y) > tolerance: return False
        return True
    if kind == "number": return isinstance(a, (float, int)) and not isinstance(a, bool) and math.isfinite(a) and a == b
    return a == b


def validate_world_signatures(signatures, specs):
    for path, expected in specs.items():
        require(path in signatures and signatures[path]["class"] == expected["class"], "Harvest world class missing: " + path)
        actual = signatures[path]
        # Lune serde encodes an empty GetTags() table as {}, while populated
        # tag tables are arrays. Both empty encodings mean exactly zero tags.
        require(set(actual["attributes"]) == set(expected["attributes"]) and actual["tags"] in ([], {}), "Harvest world metadata/tag set differs: " + path)
        for key, value in expected["attributes"].items(): require(matches(actual["attributes"][key], value), "Harvest attribute differs: " + path + "/" + key)
        for key, value in expected["properties"].items(): require(key in actual["properties"] and matches(actual["properties"][key], value), "Harvest placement/physics differs: " + path + "/" + key)


def canonicalize(before, after, additions):
    old_ids = {identity(node): path for path, node in before.items()}
    require(len(old_ids) == len(before), "Duplicate immutable identity")
    paths, ids, targets = {}, set(), set()
    for path, node in after.items():
        uid = identity(node)
        require(uid not in ids, "Duplicate candidate identity")
        ids.add(uid)
        target = old_ids.get(uid)
        if target is None:
            require(path in additions or path in r.SELECTION_PATHS, "Unexpected/replaced instance identity: " + path)
            target = path
        require(target not in targets, "Duplicate canonical target")
        targets.add(target)
        paths[path] = target
    require(targets == set(before) | set(additions), "Missing or extra original/new instance")
    result = {}
    reindexed = sum(path != target for path, target in paths.items())
    for path, target in paths.items():
        node = after[path]
        parent, actual_parent = target.rpartition("/")[0], path.rpartition("/")[0]
        require((not parent and not actual_parent) or paths.get(actual_parent) == parent, "Original/new parent identity changed: " + target)
        if target in before: require(node["class"] == before[target]["class"] and node["properties"]["Name"] == before[target]["properties"]["Name"], "Original class/name changed: " + target)
        result[target] = node if not reindexed else node | {"properties": {name: remap_refs(value, paths) for name, value in node["properties"].items()}}
    return result, paths, reindexed


def validate_new_code(before, after, additions):
    template = before["ServerScriptService/GameServer/Game/RoundAudio"]["properties"]
    guids = {node["properties"]["ScriptGuid"][1].lower() for node in before.values() if "ScriptGuid" in node["properties"]}
    for path, cls in additions.items():
        node, props = after[path], after[path]["properties"]
        require(node["class"] == cls == "ModuleScript" and set(props) == set(template), "New code property/class set differs: " + path)
        for prop, value in props.items():
            if prop in ("Name", "Source", "UniqueId"): continue
            if prop == "ScriptGuid":
                require(value[0] == "string" and not value[2] and GUID.fullmatch(value[1]) and int(value[1].replace("-", "")[1:-1], 16), "Malformed new ScriptGuid")
                require(value[1].lower() not in guids, "Duplicate ScriptGuid")
                guids.add(value[1].lower())
            else: require(r.normalized(value) == r.normalized(template[prop]), "New code nondefault property: " + path + "/" + prop)


def validate_art_links(value, texture=False):
    """Procedural art has no instance references or other external content links."""
    if value[0] == "Ref": require(value[1] == "null" and not value[2], "New art has a foreign instance reference")
    if value[0] in ("uri", "url"): require(texture and value[0] == "uri" and not value[2], "Unapproved new art content link")
    for _, child in value[2]: validate_art_links(child, texture)


def derive_variant_b_manifest(reviewed_a, baseline_typed, catalog):
    """Derive B from reviewed A, changing only 55 visibility and two root attributes.

    This never takes candidate records as authority. String-attribute payloads
    are changed by an exact unique serialized A->B pattern, preserving all other
    bytes; ordinary verification still independently checks decoded attributes.
    """
    require(reviewed_a["version"] == 1 and reviewed_a["owner"] == OWNER and reviewed_a["variant"] == "A" and reviewed_a["baseline_sha256"] == BASELINE_HASH, "Reviewed A manifest required")
    a_specs, b_specs = world_contract(baseline_typed, catalog, "A"), world_contract(baseline_typed, catalog, "B")
    require(set(reviewed_a["nodes"]) == set(a_specs) == set(b_specs), "Reviewed A world paths differ")
    result = copy.deepcopy(reviewed_a)
    result["variant"] = "B"
    changes = []
    for path, spec in a_specs.items():
        if spec["class"] not in ("Part", "MeshPart", "Texture"): continue
        branch = spec["attributes"]["HarvestBranch"]["value"]
        visible = spec["attributes"]["HarvestVisibleTransparency"]["value"]
        before, after = (visible if branch in ("Common", "A") else 1), (visible if branch in ("Common", "B") else 1)
        if before == after: continue
        prop = result["nodes"][path]["properties"]["Transparency"]
        require(prop[0] == "float" and not prop[2] and float(prop[1]) == before, "Reviewed A visibility does not match A contract")
        result["nodes"][path]["properties"]["Transparency"] = ["float", str(after), []]
        changes.append({"path": path, "property": "Transparency", "before": before, "after": after})
    name = b"HarvestAppliedVariant"
    pattern = struct.pack("<I", len(name)) + name + bytes([2]) + struct.pack("<I", 1) + b"A"
    for path in (DECOR, HOME):
        prop = result["nodes"][path]["properties"]["AttributesSerialize"]
        require(prop[0] == "BinaryString" and not prop[2], "Malformed reviewed A attributes")
        raw = bytes.fromhex(prop[1])
        require(raw.count(pattern) == 1, "Reviewed A variant attribute payload is not unique")
        prop[1] = raw.replace(pattern, pattern[:-1] + b"B").hex()
        changes.append({"path": path, "property": "AttributesSerialize", "attribute": "HarvestAppliedVariant", "before": "A", "after": "B"})
    require(len(changes) == 57 and sum(row["property"] == "Transparency" for row in changes) == 55, "Expected exact A-to-B appearance delta")
    return result, changes


def validate_dom(before, after, sources, classes, code_added, declared, asset_sources, before_typed, after_typed, specs, variant, manifest=None):
    additions = dict(code_added) | {path: row["class"] for path, row in specs.items()}
    after, paths, reindexed = canonicalize(before, after, additions)
    after_typed = {paths[path]: value for path, value in after_typed.items() if path in paths}
    require(len(sources) == 150 and len(asset_sources) == 3 and len(code_added) == 73, "Harvest Source/addition count differs")
    require(sum("Source" in row["properties"] for row in before.values()) == 80, "Immutable multiplayer Source count differs")
    require({path for path in after if r.p.owned(path)} == set(classes), "Configured code topology differs")
    for path, cls in classes.items(): require(after[path]["class"] == cls, "Configured code class differs")
    all_sources = sources | asset_sources
    require({path for path, node in after.items() if "Source" in node["properties"]} == set(all_sources), "Persistent Source set differs")
    for path, source in all_sources.items():
        value = after[path]["properties"]["Source"]
        require(value[0] == "string" and not value[2] and value[1].replace("\r\n", "\n") == source, "Source differs: " + path)
    validate_new_code(before, after, code_added)
    validate_world_signatures(after_typed, specs)
    map_attrs = before_typed[MAP]["attributes"] | {"HarvestArtVariant": tv("string", variant)}
    require(after_typed[MAP]["attributes"] == map_attrs, "Original map attributes differ beyond exact HarvestArtVariant")
    template_sets = {cls: set(next(row for row in before.values() if row["class"] == cls)["properties"]) for cls in ("Folder", "Model", "MeshPart", "Part", "Texture")}
    for path, expected in specs.items():
        node = after[path]
        require(node["class"] == expected["class"] and set(node["properties"]) == template_sets[node["class"]], "New art property set/class differs: " + path)
        require(node["properties"]["Name"] == ["string", path.rsplit("/", 1)[1], []], "New art name differs")
        require(node["properties"]["Capabilities"] == ["SecurityCapabilities", "0", []] and node["properties"]["DefinesCapabilities"] == ["bool", "false", []], "New art capability changed")
        require(node["properties"]["SerializedOverrides"] == ["BinaryString", "", []] and node["properties"]["Tags"] == ["BinaryString", "", []], "New art overrides/tags present")
        for prop, value in node["properties"].items(): validate_art_links(value, prop == "TextureContent")
        if node["class"] in ("Part", "MeshPart"):
            require(node["properties"]["CanCollide"] == node["properties"]["CanTouch"] == node["properties"]["CanQuery"] == ["bool", "false", []], "New art changes physics/LOS")
        if node["class"] == "MeshPart":
            value = node["properties"]["TextureContent"]
            texture = expected["attributes"]["HarvestTexture"]["value"]
            require(value[0] == "Content" and len(value[2]) == 1, "Malformed new art texture content")
            tag, leaf = value[2][0]
            require(leaf[0] == tag and not leaf[2] and ((tag == "uri" and leaf[1] == texture) if texture else (tag == "null" and not leaf[1].strip())), "New art texture content differs: " + path)
        if node["class"] == "Texture":
            require(node["properties"]["TextureContent"][2] == [["uri", ["uri", expected["attributes"]["HarvestTexture"]["value"], []]]], "Ground texture URI differs")
            require(node["properties"]["Face"] == ["token", "1", []] and float(node["properties"]["StudsPerTileU"][1]) == float(node["properties"]["StudsPerTileV"][1]) == 8, "Ground texture tiling/face differs")
    changes, source_changes = [], []
    for path, node in before.items():
        actual = after[path]
        require(set(node["properties"]) == set(actual["properties"]), "Original property set changed: " + path)
        for prop, value in node["properties"].items():
            other = actual["properties"][prop]
            if prop == "Source":
                if value[1].replace("\r\n", "\n") == other[1].replace("\r\n", "\n"): continue
                require(path in declared, "Source outside eight declared changes: " + path)
                source_changes.append(path)
                changes.append({"path": path, "property": prop, "reason": "declared_source"})
                continue
            if other == value or r.normalized(other) == r.normalized(value): continue
            camera = path == "Workspace/Camera" and prop in ("CFrame", "Focus")
            selection = path in r.SELECTION_PATHS and prop == "UniqueId"
            map_variant = path == MAP and prop == "AttributesSerialize"
            art_hide = prop == "Transparency" and (path in HOME_PARTS or (variant == "B" and path in BARN_PARTS))
            require(camera or selection or map_variant or art_hide, "Original world/art/Lighting changed: " + path + "/" + prop)
            if camera: old.helpers.validate_camera_frame(other)
            if art_hide: require(value[0] == other[0] == "float" and float(value[1]) == 0 and float(other[1]) == 1 and not value[2] and not other[2], "Original hide must be exactly 0 -> 1")
            changes.append({"path": path, "property": prop, "reason": "editor" if camera or selection else "owned_art_appearance"})
    require(set(source_changes) == set(declared), "Declared Source changes differ")
    for path in HOME_PARTS: require(after[path]["properties"]["Transparency"] == ["float", "1", []], "Legacy home part was not hidden")
    for path in BARN_PARTS: require(float(after[path]["properties"]["Transparency"][1]) == (1 if variant == "B" else 0), "Barn visibility differs from variant")
    if manifest is not None:
        require(set(manifest) == {"version", "owner", "baseline_sha256", "catalog_sha256", "payload_sha256", "variant", "nodes"}, "World manifest schema differs")
        require(manifest["version"] == 1 and manifest["owner"] == OWNER and manifest["baseline_sha256"] == BASELINE_HASH and manifest["catalog_sha256"] == sha256(CATALOG) and manifest["payload_sha256"] == sha256(PAYLOAD) and manifest["variant"] == variant, "Unrecognized frozen world manifest")
        require(set(manifest["nodes"]) == set(specs), "Frozen world node set differs")
        for path, expected in manifest["nodes"].items():
            require(expected["class"] == after[path]["class"] and set(expected["properties"]) == set(after[path]["properties"]), "Frozen world record/class differs")
            for prop, value in expected["properties"].items():
                if prop == "UniqueId": continue
                require(r.normalized(value) == r.normalized(after[path]["properties"][prop]), "Frozen world property differs: " + path + "/" + prop)
    return {"passed": manifest is not None, "complete": manifest is not None, "requires_independent_world_review": manifest is None, "variant": variant, "matching_sources": 150, "matching_asset_sources": 3, "total_sources": 153, "new_code_instances": len(code_added), "new_art_instances": len(specs), "new_instances": len(additions), "original_instances": len(before), "candidate_instances": len(after), "source_changes": sorted(source_changes), "allowed_changes": changes, "reindexed_exporter_paths": reindexed, "original_identities_classes_names_parents_exact": True, "original_world_preserved_except_exact_art_transparency": True}, after


def check(original, candidate, variant, manifest_path=None, manifest_hash=None, audit_new_nodes=False):
    original, candidate = original.resolve(), candidate.resolve()
    old_hash, new_hash = sha256(original), sha256(candidate)
    require(original == BASELINE.resolve() and old_hash == BASELINE_HASH and original.stat().st_size == BASELINE_BYTES, "Immutable before-harvest baseline changed")
    require(candidate.is_file() and candidate.suffix.lower() == ".rbxl" and candidate != original, "Candidate must be a separate exact engine-saved RBXL")
    require(audit_new_nodes or (manifest_path is not None and re.fullmatch(r"[0-9a-f]{64}", manifest_hash or "")), "Normal verification requires independently reviewed manifest and SHA256")
    require(not audit_new_nodes or manifest_path is None, "First-save review cannot also approve a manifest")
    manifest = None
    if manifest_path:
        require(sha256(manifest_path) == manifest_hash, "Frozen world manifest SHA256 differs")
        manifest = load_json(manifest_path)
    payload, sources, classes, additions, declared = mapping()
    input_hashes = {PAYLOAD: sha256(PAYLOAD), CATALOG: sha256(CATALOG)}
    before, warning_before = r.p.known_dom(original)
    after, warning_after = r.p.known_dom(candidate)
    unknown_before, unknown_after = r.p.unknown_properties(original), r.p.unknown_properties(candidate)
    r.validate_unknown(unknown_before, unknown_after)
    before_typed, _ = typed.typed_scene(original)
    after_typed, _ = typed.typed_scene(candidate)
    specs = world_contract(before_typed, load_json(CATALOG), variant)
    assets = fog.current_sources()
    require({path: row["class"] for path, row in before.items() if r.p.owned(path)} == payload["beforeClasses"], "Immutable baseline code topology differs from payload")
    for row in payload["entries"]:
        if row.get("before"):
            text = before[row["path"]]["properties"]["Source"][1].replace("\r\n", "\n")
            require(hashlib.sha256(text.encode()).hexdigest() == row["before"], "Payload source baseline hash differs")
    result, canonical = validate_dom(before, after, sources, classes, additions, declared, assets, before_typed, after_typed, specs, variant, manifest)
    require(sha256(original) == old_hash and sha256(candidate) == new_hash and all(sha256(path) == digest for path, digest in input_hashes.items()), "Input changed during read-only audit")
    require(mapping()[1:3] == (sources, classes) and fog.current_sources() == assets, "Project sources/assets changed during audit")
    result |= {"original_sha256": old_hash, "candidate_sha256": new_hash, "bytes": candidate.stat().st_size, "raw_terrain_exact": True, "raw_unknown_properties": unknown_after, "warnings": {"original": warning_before, "candidate": warning_after}, "world_manifest_sha256": manifest_hash, "scope": "Exact engine bytes; retained world/Lighting/art/identities/parents/raw Terrain, 153 exact Sources, 291 closed-contract art nodes and narrow explicit transparency/variant/editor changes. First-save audit is incomplete until independent full new-node manifest review."}
    draft = {"version": 1, "owner": OWNER, "baseline_sha256": BASELINE_HASH, "catalog_sha256": input_hashes[CATALOG], "payload_sha256": input_hashes[PAYLOAD], "variant": variant, "nodes": {path: canonical[path] for path in specs}}
    return result, draft


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("original", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--variant", choices=("A", "B"), required=True)
    parser.add_argument("--world-manifest", type=Path)
    parser.add_argument("--manifest-sha256")
    parser.add_argument("--audit-new-nodes", action="store_true")
    parser.add_argument("--draft-manifest", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    for path in (args.report, args.draft_manifest):
        if path:
            resolved = path.resolve()
            require(resolved.suffix.lower() == ".json" and any(resolved.is_relative_to((ROOT / folder).resolve()) for folder in ("build", ".artifacts")), "Outputs must remain in owned artifact/build directories")
            require(resolved not in {args.original.resolve(), args.candidate.resolve(), PAYLOAD.resolve(), CATALOG.resolve(), args.world_manifest.resolve() if args.world_manifest else None}, "Output would overwrite an input")
    require(not args.draft_manifest or args.audit_new_nodes, "Draft manifest only belongs to explicitly incomplete first-save review")
    report, draft = check(args.original, args.candidate, args.variant, args.world_manifest, args.manifest_sha256, args.audit_new_nodes)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_bytes((json.dumps(report, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
    if args.draft_manifest:
        args.draft_manifest.parent.mkdir(parents=True, exist_ok=True)
        args.draft_manifest.write_bytes((json.dumps(draft, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
    print(json.dumps({key: value for key, value in report.items() if key not in {"allowed_changes", "warnings", "raw_unknown_properties"}}))
