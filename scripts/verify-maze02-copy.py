"""Strict read-only B engine-save audit for the reviewed maze-02 payload.

Uses the immutable f335 B inside before-shadows.zip. No scene serialization,
promotion, Source replacement, deletion or broad world exceptions are allowed.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import re
import struct
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("maze02_shadow_helpers", ROOT / "scripts/verify-corn-shadows-copy.py")
shadow = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shadow)
r, require, identity, remap_refs = shadow.r, shadow.require, shadow.identity, shadow.remap_refs
read_baseline, baseline_file = shadow.read_baseline, shadow.baseline_file
OUT = ROOT / ".artifacts/playtests/2026-10-21-maze02"
PAYLOAD = OUT / "payload.json"
PAYLOAD_SHA256 = "26bca1b53c6b1d5e8007aac52502062f37ad5c273c333d66b1f8a9b0700b31f2"
OWNER = "corn_maze02_v1"
MAP = "Workspace/CornMap"
NEW_ROOTS = (MAP + "/Maze02", MAP + "/NoCornZones/Maze02Masks", MAP + "/Props/VillageRoad/Maze02Trails")
FOLDER_TEMPLATE = MAP + "/NoCornZones"
PART_TEMPLATE = FOLDER_TEMPLATE + "/StartClearing"
SHADOW_SOURCE_SHA = "1a2a933017b2b0b4680bbafef5323ee3a67e44c8caa1ce1014f159b0861334be"
PROTECTED = {"Name", "UniqueId", "Source", "ScriptGuid", "HistoryId", "Capabilities", "DefinesCapabilities",
             "SerializedOverrides", "SourceAssetId", "Parent", "ClassName", "AttributesSerialize", "Tags"}
PROPERTY_NAMES = {"Size": "size", "Shape": "shape", "Color": "Color3uint8"}
ENUMS = {
    "Material": {"Plastic": 256, "Neon": 288, "Wood": 512, "WoodPlanks": 528,
                 "Slate": 800, "Concrete": 816, "Grass": 1280, "Sand": 1296,
                 "Ground": 1360, "Mud": 1344, "Asphalt": 1376},
    "SurfaceType": {"Smooth": 0, "Glue": 1, "Weld": 2, "Studs": 3, "Inlet": 4,
                    "Universal": 5, "Hinge": 6, "Motor": 7, "SteppingMotor": 8,
                    "SmoothNoOutlines": 10},
    "PartType": {"Ball": 0, "Block": 1, "Cylinder": 2},
}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def scalar(kind, value):
    return [kind, str(value), []]


def f32(value):
    require(type(value) in (int, float) and math.isfinite(value), "Invalid finite float32")
    try:
        return struct.unpack("<f", struct.pack("<f", value))[0]
    except OverflowError as error:
        raise ValueError("Float32 overflow") from error


def vector_dom(kind, values):
    names = ["X", "Y", "Z"] if kind == "Vector3" else ["X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"]
    require(len(values) == len(names), "Wrong typed component count")
    return [kind, "", [[name, scalar(name, repr(f32(value)))] for name, value in zip(names, values)]]


def numeric_components(value, names):
    require(isinstance(value, list) and len(value) == 3 and isinstance(value[2], list), "Malformed DOM value")
    require([pair[0] for pair in value[2]] == names, "Missing, duplicate or reordered components")
    result = []
    for name, leaf in value[2]:
        require(leaf[0] == name and leaf[2] == [] and isinstance(leaf[1], str), "Malformed component")
        number = float(leaf[1])
        require(math.isfinite(number), "Nonfinite DOM component")
        result.append(f32(number))
    return result


def compact_rotation_equal(actual, expected):
    """The saved axis code removes native sin(pi/2)'s proven 4.371e-8 residue."""
    require(len(actual) == len(expected) == 12, "Invalid CFrame component count")
    if actual[:3] != expected[:3]:
        return False
    matrix = actual[3:]
    if not all(v in (-1, 0, 1) for v in matrix):
        return False
    if any(sum(abs(matrix[r * 3 + c]) for c in range(3)) != 1 for r in range(3)):
        return False
    if any(sum(abs(matrix[r * 3 + c]) for r in range(3)) != 1 for c in range(3)):
        return False
    return all(a == b or (a == 0 and abs(b) <= 4.371139e-8) for a, b in zip(matrix, expected[3:]))


def equivalent(actual, expected):
    """Float32 comparison only for explicitly declared engine properties."""
    if r.normalized(actual) == r.normalized(expected):
        return True
    require(actual[0] == expected[0], "Declared property DOM type differs")
    if expected[0] == "CoordinateFrame":
        names = ["X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"]
        left, right = numeric_components(actual, names), numeric_components(expected, names)
        return left == right or compact_rotation_equal(left, right)
    if expected[0] == "Vector3":
        return numeric_components(actual, ["X", "Y", "Z"]) == numeric_components(expected, ["X", "Y", "Z"])
    if expected[0] == "float":
        require(actual[2] == expected[2] == [], "Scalar float has children")
        return f32(float(actual[1])) == f32(float(expected[1]))
    return False


def native_to_dom(value, template, public_name):
    kind = value.get("kind") if isinstance(value, dict) else None
    if kind in {"CFrame", "Vector3"}:
        require(set(value) == {"kind", "value"}, "Unknown typed value fields")
        wanted = "CoordinateFrame" if kind == "CFrame" else "Vector3"
        require(template[0] == wanted, "Typed property kind differs")
        return vector_dom(wanted, value["value"])
    if kind == "Color3":
        require(set(value) == {"kind", "value"} and len(value["value"]) == 3
                and template[0] == "Color3uint8", "Invalid Part color")
        channels = [f32(v) for v in value["value"]]
        require(all(0 <= v <= 1 for v in channels), "Color outside RGB range")
        rgb = [math.floor(v * 255 + .5) for v in channels]
        return scalar("Color3uint8", (rgb[0] << 16) | (rgb[1] << 8) | rgb[2])
    if template[0] == "token":
        enum = "Material" if public_name == "Material" else "PartType" if public_name == "Shape" else "SurfaceType"
        if kind == "Enum":
            require(set(value) == {"kind", "value"} and len(value["value"]) == 2
                    and value["value"][0] == enum, "Wrong enum family")
            value = value["value"][1]
        require(isinstance(value, str) and value in ENUMS[enum], "Unrecognized scoped enum")
        return scalar("token", ENUMS[enum][value])
    require(kind is None, "Unexpected typed property")
    if template[0] == "bool":
        require(type(value) is bool, "Boolean property type differs")
        return scalar("bool", str(value).lower())
    if template[0] == "float":
        return scalar("float", repr(f32(value)))
    if template[0] in {"int", "int64"}:
        require(type(value) is int, "Integral property required")
        return scalar(template[0], value)
    if template[0] == "string":
        require(isinstance(value, str), "String property type differs")
        return scalar("string", value)
    raise ValueError("Unsupported declared property: " + public_name)


def decode_attributes(value):
    require(value[0] == "BinaryString" and value[2] == [], "Malformed attribute encoding")
    data, offset = bytes.fromhex(value[1]), 0

    def take(fmt):
        nonlocal offset
        count = struct.calcsize(fmt)
        require(offset + count <= len(data), "Truncated attribute value")
        result = struct.unpack_from(fmt, data, offset)
        offset += count
        return result[0] if len(result) == 1 else list(result)

    def string():
        nonlocal offset
        count = take("<I")
        require(offset + count <= len(data), "Truncated attribute string")
        result = data[offset:offset + count].decode("utf-8")
        offset += count
        return result

    result = {}
    for _ in range(take("<I") if data else 0):
        start = offset
        name, kind = string(), take("<B")
        require(name not in result, "Duplicate serialized attribute")
        if kind == 2:
            decoded = string()
        elif kind == 3:
            number = take("<B")
            require(number in (0, 1), "Invalid bool attribute")
            decoded = bool(number)
        elif kind == 6:
            decoded = take("<d")
            require(math.isfinite(decoded), "Nonfinite numeric attribute")
        elif kind in (15, 17):
            decoded = {"kind": "Color3" if kind == 15 else "Vector3", "value": take("<fff")}
        elif kind == 20:
            position, rotation = take("<fff"), take("<B")
            if rotation == 0:
                matrix = take("<fffffffff")
            else:
                normals = ((1, 0, 0), (0, 1, 0), (0, 0, 1), (-1, 0, 0), (0, -1, 0), (0, 0, -1))
                right_index, up_index = divmod(rotation - 1, 6)
                require(0 <= right_index < 6 and 0 <= up_index < 6, "Invalid compressed attribute rotation")
                right, up = normals[right_index], normals[up_index]
                require(sum(a * b for a, b in zip(right, up)) == 0, "Parallel attribute rotation axes")
                back = (right[1] * up[2] - right[2] * up[1], right[2] * up[0] - right[0] * up[2], right[0] * up[1] - right[1] * up[0])
                matrix = [axis[row] for row in range(3) for axis in (right, up, back)]
            decoded = {"kind": "CFrame", "value": position + matrix}
        else:
            raise ValueError("Unsupported attribute kind: " + str(kind))
        result[name] = {"kind": kind, "value": decoded, "raw": data[start:offset].hex()}
    require(offset == len(data), "Trailing attribute bytes")
    return result


def attribute_matches(entry, expected):
    if isinstance(expected, dict):
        require(set(expected) == {"kind", "value"}, "Unexpected typed attribute fields")
        kind = {"CFrame": 20, "Vector3": 17, "Color3": 15}.get(expected["kind"])
        if entry["kind"] != kind or not isinstance(entry["value"], dict):
            return False
        values = expected["value"]
        require(len(values) == (12 if kind == 20 else 3), "Wrong attribute component count")
        actual, wanted = [f32(v) for v in entry["value"]["value"]], [f32(v) for v in values]
        return entry["value"]["kind"] == expected["kind"] and (actual == wanted or (kind == 20 and compact_rotation_equal(actual, wanted)))
    if type(expected) is bool:
        return entry["kind"] == 3 and entry["value"] is expected
    if type(expected) in (int, float):
        return entry["kind"] == 6 and math.isfinite(expected) and entry["value"] == expected
    if isinstance(expected, str):
        return entry["kind"] == 2 and entry["value"] == expected
    raise ValueError("Unsupported attribute value")


def encode_attributes(values):
    """In-memory fixture/default construction; never writes an RBXL."""
    def string(value):
        encoded = value.encode("utf-8")
        return struct.pack("<I", len(encoded)) + encoded
    rows = []
    for name, value in sorted(values.items()):
        if type(value) is bool:
            body = b"\x03" + bytes([int(value)])
        elif isinstance(value, str):
            body = b"\x02" + string(value)
        elif type(value) in (int, float):
            require(math.isfinite(value), "Nonfinite fixture attribute")
            body = b"\x06" + struct.pack("<d", value)
        else:
            kind = {"CFrame": 20, "Vector3": 17, "Color3": 15}[value["kind"]]
            numbers = [f32(v) for v in value["value"]]
            body = bytes([kind]) + struct.pack("<fff", *numbers[:3])
            if kind == 20:
                body += b"\x00" + struct.pack("<fffffffff", *numbers[3:])
        rows.append(string(name) + body)
    return scalar("BinaryString", (struct.pack("<I", len(rows)) + b"".join(rows)).hex() if rows else "")


def read_payload(expected_sha256=None):
    expected_sha256 = expected_sha256 or PAYLOAD_SHA256
    require(isinstance(expected_sha256, str) and re.fullmatch("[0-9a-f]{64}", expected_sha256),
            "A reviewed, frozen payload SHA256 is required")
    require(sha(PAYLOAD) == expected_sha256, "Reviewed maze payload bytes changed")
    return json.loads(PAYLOAD.read_bytes(), object_pairs_hook=shadow.unique_object)


def resolver_index(before):
    result = {}
    for path, node in before.items():
        key = (path.rpartition("/")[0], node["properties"]["Name"][1])
        group = result.setdefault(key, {"all": [], "positions": {}})
        group["all"].append(path)
        frame = node["properties"].get("CFrame")
        if frame is not None:
            position = tuple(f32(float(pair[1][1])) for pair in frame[2][:3])
            group["positions"].setdefault(position, []).append(path)
    return result


def resolve_before(before, row, index=None):
    path = row["path"]
    require(path == MAP or path.startswith(MAP + "/"), "Payload change outside CornMap")
    parent, _, name = path.rpartition("/")
    if index is None:
        index = resolver_index(before)
    group = index.get((parent, name), {"all": [], "positions": {}})
    candidates = group["all"]
    selector = row.get("selector")
    if selector is not None:
        require(isinstance(selector, dict) and set(selector) == {"CFrame"}, "Only exact CFrame duplicate selectors allowed")
        value = selector["CFrame"]
        require(isinstance(value, dict) and value.get("kind") == "CFrame" and len(value.get("value", [])) == 12,
                "Malformed exact selector CFrame")
        candidates = group["positions"].get(tuple(f32(v) for v in value["value"][:3]), [])
        candidates = [p for p in candidates if "CFrame" in before[p]["properties"]
                      and equivalent(before[p]["properties"]["CFrame"],
                                     native_to_dom(selector["CFrame"], before[p]["properties"]["CFrame"], "CFrame"))]
    require(len(candidates) == 1, "Ambiguous/missing immutable target: " + path)
    return candidates[0]


def prepare_plan(before, payload):
    require(payload.get("owner") == OWNER and isinstance(payload.get("changes"), list)
            and isinstance(payload.get("nodes"), list), "Unrecognized maze payload")
    require(0 < len(payload["nodes"]) <= 4096 and len(payload["changes"]) <= 8192, "Unbounded world manifest")
    retained_sources = {p: n for p, n in before.items() if "Source" in n["properties"]}
    require(len(before) == 4532 and len(retained_sources) == 156, "Immutable f335 B DOM topology differs")
    sources = payload.get("sources")
    require(isinstance(sources, dict) and set(sources) in (set(retained_sources), set(retained_sources) | {shadow.ADDED}), "All 156 B Sources must be pinned")
    for path, node in retained_sources.items():
        source = node["properties"]["Source"]
        require(sources[path] == {"class": node["class"], "sha256": hashlib.sha256(source[1].replace("\r\n", "\n").encode()).hexdigest()}, "Baseline Source manifest differs: " + path)
    if shadow.ADDED in sources:
        require(sources[shadow.ADDED] == {"class": "ModuleScript", "sha256": SHADOW_SOURCE_SHA}, "Unknown optional controller manifest")
    additions = {}
    for row in payload["nodes"]:
        path = row["path"]
        require(path not in before and path not in additions and any(path == root or path.startswith(root + "/") for root in NEW_ROOTS), "Unknown/duplicate new world path")
        require(row["class"] in {"Folder", "Part"} and isinstance(row["properties"], dict)
                and isinstance(row["attributes"], dict) and isinstance(row["tags"], list), "New world node schema differs")
        require(row["attributes"].get("corn_project_id") == "children_of_corn" and row["attributes"].get("CornMazeOwner") == OWNER, "New node lacks exact ownership")
        require(not (set(row["properties"]) & PROTECTED), "Protected new property declared")
        require(len(row["tags"]) == len(set(row["tags"])) and all(isinstance(t, str) and t and "\x00" not in t for t in row["tags"]), "Malformed/duplicate tags")
        additions[path] = row
    require(all(p.rpartition("/")[0] in before or p.rpartition("/")[0] in additions for p in additions), "New world parent missing")
    changes, attribute_changes = {}, {}
    index = resolver_index(before)
    for row in payload["changes"]:
        require(type(row.get("attribute")) is bool, "Attribute/property change kind missing")
        target = resolve_before(before, row, index)
        prop = row["property"]
        if row["attribute"]:
            require(isinstance(prop, str) and prop, "Invalid attribute name")
            key = (target, prop)
            require(key not in attribute_changes, "Duplicate planned attribute")
            attrs = decode_attributes(before[target]["properties"]["AttributesSerialize"])
            old = row["before"]
            if isinstance(old, dict) and old.get("kind") == "Nil":
                require(prop not in attrs, "New attribute already exists in immutable checkpoint")
            else:
                require(prop in attrs and attribute_matches(attrs[prop], old), "Immutable attribute before value differs: " + target + "/" + prop)
            attribute_changes[key] = row
        else:
            require(prop not in PROTECTED, "Protected existing property declared")
            dom_prop = PROPERTY_NAMES.get(prop, prop)
            require(dom_prop in before[target]["properties"] and "Source" not in before[target]["properties"], "Invalid world property target")
            key = (target, dom_prop)
            require(key not in changes, "Duplicate planned property")
            original = before[target]["properties"][dom_prop]
            require(equivalent(original, native_to_dom(row["before"], original, prop)), "Immutable before property differs: " + target + "/" + prop)
            expected = native_to_dom(row["after"], original, prop)
            require(not equivalent(original, expected), "No-op planned property")
            changes[key] = expected
    return additions, changes, attribute_changes


def default_node(before, row):
    """Independent accepted class templates plus documented Instance.new defaults."""
    template = FOLDER_TEMPLATE if row["class"] == "Folder" else PART_TEMPLATE
    node = copy.deepcopy(before[template])
    props = node["properties"]
    props["Name"] = scalar("string", row["path"].rsplit("/", 1)[-1])
    props["AttributesSerialize"] = encode_attributes(row["attributes"])
    props["Tags"] = scalar("BinaryString", "\x00".join(sorted(row["tags"])).encode().hex())
    if row["class"] == "Part":
        props.update({"Anchored": scalar("bool", "false"), "CanCollide": scalar("bool", "true"),
                      "CanTouch": scalar("bool", "true"), "CanQuery": scalar("bool", "true"),
                      "Color3uint8": scalar("Color3uint8", 10724005),
                      "TopSurface": scalar("token", 3), "BottomSurface": scalar("token", 4),
                      "CFrame": vector_dom("CoordinateFrame", [0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1]),
                      "size": vector_dom("Vector3", [4, 1.2, 2])})
    for prop, value in row["properties"].items():
        key = PROPERTY_NAMES.get(prop, prop)
        require(key in props and prop not in PROTECTED, "Unknown new class property: " + prop)
        props[key] = native_to_dom(value, props[key], prop)
    return node


def canonicalize(before, after, additions, has_shadow):
    old_ids = {identity(n): p for p, n in before.items()}
    require(len(old_ids) == len(before), "Duplicate immutable identity")
    expected_additions = set(additions) | ({shadow.ADDED} if has_shadow else set())
    paths, seen, targets = {}, set(), set()
    for path, node in after.items():
        uid = identity(node)
        require(uid not in seen, "Duplicate candidate identity")
        seen.add(uid)
        target = old_ids.get(uid)
        if target is None:
            selection = path in r.SELECTION_PATHS and node["class"] == "Instance" and node["properties"].get("Name") == scalar("string", "FilteredSelection")
            require(path in expected_additions or selection, "Unexpected/replaced identity: " + path)
            target = path
        require(target not in targets, "Duplicate canonical identity target")
        paths[path], _ = target, targets.add(target)
    require(targets == set(before) | expected_additions, "Missing/extra retained or new objects")
    canonical = {}
    reindexed = sum(p != t for p, t in paths.items())
    for path, target in paths.items():
        actual = after[path]
        expected_class = before[target]["class"] if target in before else "ModuleScript" if target == shadow.ADDED else additions[target]["class"]
        expected_name = before[target]["properties"]["Name"] if target in before else scalar("string", target.rsplit("/", 1)[-1])
        require(actual["class"] == expected_class and actual["properties"].get("Name") == expected_name, "Class/real Name changed: " + target)
        parent, actual_parent = target.rpartition("/")[0], path.rpartition("/")[0]
        require((not parent and not actual_parent) or paths.get(actual_parent) == parent, "Parent identity changed: " + target)
        canonical[target] = actual if not reindexed else actual | {"properties": {prop: remap_refs(value, paths) for prop, value in actual["properties"].items()}}
    return canonical, reindexed


def validate_dom(before, after, payload):
    additions, changes, attr_changes = prepare_plan(before, payload)
    has_shadow = shadow.ADDED in after
    after, reindexed = canonicalize(before, after, additions, has_shadow)
    require(len(after) == len(before) + len(additions) + int(has_shadow), "Exact declared node count differs")
    require({p for p, n in after.items() if "Source" in n["properties"]} == {p for p, n in before.items() if "Source" in n["properties"]} | ({shadow.ADDED} if has_shadow else set()), "Persistent Source set differs")
    if has_shadow:
        source = shadow.controller_source()
        require(hashlib.sha256(source.encode()).hexdigest() == SHADOW_SOURCE_SHA, "Optional shadow Source checkpoint differs")
        shadow.validate_added_module(before, after, source)
    for path, row in additions.items():
        expected = default_node(before, row)
        actual = after[path]
        require(set(actual["properties"]) == set(expected["properties"]), "New node hidden property schema differs: " + path)
        for prop, value in expected["properties"].items():
            other = actual["properties"][prop]
            if prop == "UniqueId":
                continue  # canonicalize proved fresh, nonzero, globally unique identity.
            if prop == "AttributesSerialize":
                attrs = decode_attributes(other)
                require(set(attrs) == set(row["attributes"]) and all(attribute_matches(attrs[k], v) for k, v in row["attributes"].items()), "New node attributes differ: " + path)
            elif prop == "Tags":
                require(other[0] == "BinaryString" and other[2] == [], "Malformed new tags")
                tags = bytes.fromhex(other[1]).decode().split("\x00") if other[1] else []
                require(len(tags) == len(set(tags)) and set(tags) == set(row["tags"]), "New node tags differ")
            elif prop in {PROPERTY_NAMES.get(k, k) for k in row["properties"]}:
                require(equivalent(other, value), "New node explicit property differs: " + path + "/" + prop)
            else:
                require(r.normalized(other) == r.normalized(value), "Nondefault new node hidden property: " + path + "/" + prop)
    recorded, seen_changes, seen_attrs = [], set(), set()
    attr_paths = {p for p, _ in attr_changes}
    for path, original in before.items():
        actual = after[path]
        require(set(original["properties"]) == set(actual["properties"]), "Retained property schema changed: " + path)
        for prop, value in original["properties"].items():
            other = actual["properties"][prop]
            key = (path, prop)
            if key in changes:
                require(equivalent(other, changes[key]), "Declared world property differs: " + path + "/" + prop)
                seen_changes.add(key)
                reason = "exact_payload_property"
            elif prop == "AttributesSerialize" and path in attr_paths:
                old, new = decode_attributes(value), decode_attributes(other)
                expected_keys = set(old)
                for (target, name), row in attr_changes.items():
                    if target != path:
                        continue
                    expected = row["after"]
                    if isinstance(expected, dict) and expected.get("kind") == "Nil":
                        expected_keys.discard(name)
                        require(name not in new, "Deleted attribute retained")
                    else:
                        expected_keys.add(name)
                        require(name in new and attribute_matches(new[name], expected), "Declared attribute differs: " + path + "/" + name)
                    seen_attrs.add((target, name))
                require(set(new) == expected_keys, "Retained attribute set differs: " + path)
                for name in set(old) - {n for p, n in attr_changes if p == path}:
                    require(new[name]["raw"] == old[name]["raw"], "Unchanged attribute bytes differ: " + path + "/" + name)
                reason = "exact_payload_attributes"
            elif path in shadow.SHADOW_PATHS and prop == "Shadows":
                require(value == scalar("bool", "false") and other == scalar("bool", str(has_shadow).lower()), "Shadow flags/controller must be all present or absent")
                if not has_shadow:
                    continue
                reason = "optional_exact_shadow_flags"
            elif value == other or r.normalized(value) == r.normalized(other):
                continue
            elif path == "Workspace/Camera" and prop in {"CFrame", "Focus"}:
                shadow.h.old.helpers.validate_camera_frame(other)
                reason = "finite_editor_camera"
            elif path in r.SELECTION_PATHS and original["class"] == "Instance" and prop == "UniqueId":
                reason = "editor_filtered_selection_identity"
            else:
                raise ValueError("Undeclared Source/world/art/Lighting/mesh change: " + path + "/" + prop)
            recorded.append({"path": path, "property": prop, "reason": reason})
    require(seen_changes == set(changes) and seen_attrs == set(attr_changes), "Payload deltas not fully applied")
    return {"passed": True, "complete": True, "variant": "B", "original_instances": len(before),
            "candidate_instances": len(after), "new_instances": len(additions) + int(has_shadow),
            "removed_instances": 0, "unchanged_sources": 156, "total_sources": 156 + int(has_shadow),
            "optional_shadows_installed": has_shadow, "source_changes": [],
            "declared_property_changes": len(changes), "declared_attribute_changes": len(attr_changes),
            "added_world_nodes": len(additions), "reindexed_exporter_paths": reindexed,
            "retained_identities_classes_names_parents_exact": True,
            "all_other_world_art_lighting_physics_mesh_metadata_exact": True, "changes": recorded}


def check(candidate, expected_payload_sha256=None):
    candidate = Path(candidate).resolve()
    require(candidate.is_file() and candidate.suffix.lower() == ".rbxl", "An engine-saved binary RBXL is required")
    candidate_hash, payload_hash = sha(candidate), sha(PAYLOAD)
    payload = read_payload(expected_payload_sha256)
    with baseline_file() as original:
        before, bwarn = r.p.known_dom(original)
        after, awarn = r.p.known_dom(candidate)
        ub, ua = r.p.unknown_properties(original), r.p.unknown_properties(candidate)
        r.validate_unknown(ub, ua)
        report = validate_dom(before, after, payload)
    require(sha(candidate) == candidate_hash and sha(PAYLOAD) == payload_hash, "Candidate/payload changed during audit")
    return report | {"baseline_sha256": shadow.BASELINE_SHA, "candidate_sha256": candidate_hash,
                     "candidate_bytes": candidate.stat().st_size, "payload_sha256": payload_hash,
                     "untouched_A_sha256": shadow.A_SHA, "raw_terrain_exact": True,
                     "raw_unknown_properties": ua, "warnings": {"baseline": bwarn, "candidate": awarn},
                     "scope": "Frozen maze payload world deltas and default Folder/Part additions only; optional exact known shadow controller plus two flags. All 156 retained Sources, retained identities/classes/names/parents and every other world/art/physics/Lighting/mesh property/raw Terrain exact. Finite editor Camera and existing FilteredSelection identities only. No scene serialization or promotion."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--payload-sha256")
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    output = args.report.resolve()
    require(output.is_relative_to(OUT.resolve()) and output.suffix.lower() == ".json", "Report must remain in maze-02 evidence")
    require(output not in {args.candidate.resolve(), PAYLOAD.resolve(), (OUT / "native-before.json").resolve(), (OUT / "layout.json").resolve()}, "Report would overwrite audit input")
    report = check(args.candidate, args.payload_sha256)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes((json.dumps(report, ensure_ascii=False, indent=2) + "\n").encode())
    print(json.dumps({k: v for k, v in report.items() if k not in {"changes", "warnings", "raw_unknown_properties"}}))
