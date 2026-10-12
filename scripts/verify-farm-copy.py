"""Read-only verification of the engine-saved farm update.

Requires an independently audited canonical world allowlist. The allowlist must
NOT be captured from an arbitrary candidate merely to make that candidate pass.
No input scene is written or serialized to disk; only the JSON report is written.
Canonical records use verify-scene-preservation.py's known_dom representation.
"""
import argparse
import copy
import hashlib
import importlib.util
import json
import math
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("preservation", ROOT / "scripts/verify-scene-preservation.py")
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
MINIMUM_SOURCES = 41
BASELINE_SOURCES = 28
HOUSE_NAMES = ("HouseWest", "HouseEast", "HouseNorthWest")
MOVES = [{"from": "Workspace/CornMap/Props/" + name,
          "to": "ServerStorage/CornFarmSceneArchive/" + name} for name in HOUSE_NAMES]
SELECTION_PATHS = {"FilteredSelection", "FilteredSelection#2", "FilteredSelection#3", "FilteredSelection#4"}
MANIFEST_KEYS = {"version", "baseline_sha256", "expected_sources", "moved_roots", "changes", "added_instances"}
SCRIPT_CLASSES = {"ModuleScript", "Script", "LocalScript"}
# Only derived installer sidecars need arithmetic tolerance. Full canonical
# signatures and all original DOM properties remain exact.
SIDECAR_POSITION_TOLERANCE = 1e-4
SIDECAR_ROTATION_TOLERANCE = 2e-6


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_json(path):
    # Duplicate keys would silently replace audited signatures without this guard.
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, "Duplicate JSON key: " + key)
            result[key] = value
        return result
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique)


def moved_path(path):
    for move in MOVES:
        if path == move["from"] or path.startswith(move["from"] + "/"):
            return move["to"] + path[len(move["from"]):]
    return path


def normalized(value):
    result = copy.deepcopy(value)
    # XML indentation follows hierarchy depth; it is not a scene property.
    if result[2] and not result[1].strip():
        result[1] = ""
    result[2] = [[tag, normalized(child)] for tag, child in result[2]]
    return result


def remap_refs(value):
    text = moved_path(value[1]) if value[0] == "Ref" else value[1]
    children = [[tag, remap_refs(child)] for tag, child in value[2]]
    if text == value[1] and all(mapped[1] is original[1] for mapped, original in zip(children, value[2])):
        return value
    return [value[0], text, children]


def canonical_value(value):
    require(isinstance(value, list) and len(value) == 3, "Invalid canonical property")
    require(isinstance(value[0], str) and isinstance(value[1], str) and isinstance(value[2], list), "Invalid canonical property shape")
    for child in value[2]:
        require(isinstance(child, list) and len(child) == 2 and isinstance(child[0], str), "Invalid canonical child")
        canonical_value(child[1])


def canonical_record(node):
    require(isinstance(node, dict) and set(node) == {"class", "properties"}, "Expected full canonical instance record")
    require(isinstance(node["class"], str) and isinstance(node["properties"], dict), "Invalid canonical instance")
    require("Name" in node["properties"], "Canonical instance missing Name")
    for value in node["properties"].values():
        canonical_value(value)


def mapping_from_sourcemap(path):
    mapping, classes = {}, {}
    def walk(node, prefix=None):
        current = "" if prefix is None else (prefix + "/" + node["name"] if prefix else node["name"])
        if p.owned(current):
            require(current not in classes, "Duplicate Rojo path: " + current)
            classes[current] = node["className"]
        files = [f for f in node.get("filePaths", []) if f.startswith("src/") and f.endswith(".luau")]
        require(len(files) <= 1, "Ambiguous source mapping: " + current)
        if files:
            file_path = (ROOT / files[0]).resolve()
            require(file_path.is_relative_to((ROOT / "src").resolve()), "Source mapping escapes src")
            mapping[current] = file_path.read_text(encoding="utf-8").replace("\r\n", "\n")
        for child in node.get("children", []):
            walk(child, current)
    walk(load_json(path))
    require(len(mapping) >= MINIMUM_SOURCES, "Stale build/sourcemap: farm sources missing")
    require(set(mapping).issubset(classes), "Sources outside configured code roots")
    return mapping, classes


def original_world_changes(road, barns, baseline_hash):
    require(road["baseline_sha256"] == barns["baseline_sha256"] == baseline_hash, "Road/barn baseline hash mismatch")
    expected = {}
    for row in road["changes"]:
        require(row["property"] == "Transparency" and row["before"] == 0 and row["after"] == 1, "Unexpected road change")
        require(row["path"].startswith("Workspace/CornMap/EditorFieldOverview/") or row["path"].startswith("Workspace/CornMap/EditorPreview/"), "Road change outside owned corn")
        key = (row["path"], row["property"])
        require(key not in expected, "Duplicate world change")
        expected[key] = (row["before"], row["after"])
    require(len(expected) == road["hidden_count"] == 193, "Expected 193 road changes")
    count = 0
    for path, record in barns["changed_originals"].items():
        require(path in {"Workspace/CornMap/Props/" + name + "/" + child for name in HOUSE_NAMES for child in ("Body", "DecorativeDoor")}, "Unexpected barn original")
        require(record["class"] == "Part", "Unexpected original barn class")
        require(set(record["properties"]) == {"Transparency", "CanCollide", "CanQuery", "CanTouch", "CastShadow"}, "Unexpected barn property set")
        for prop, values in record["properties"].items():
            old, new = values["before"]["value"], values["after"]["value"]
            require((old, new) == ((0, 1) if prop == "Transparency" else (True, False)), "Unexpected barn change values")
            expected[(path, prop)] = (old, new)
            count += 1
    require(count == barns["world_changes_count"] == 30, "Expected 30 open-barn changes")
    return expected


def leaf_matches(value, expected):
    if isinstance(expected, bool):
        return value == ["bool", "true" if expected else "false", []]
    return value[0] in {"float", "double", "int", "int64"} and value[2] == [] and float(value[1]) == expected


def validate_dom(before, after, manifest, sources, code_classes, world_changes, world_paths):
    require(set(manifest) == MANIFEST_KEYS, "Unexpected or missing farm allowlist fields")
    require(manifest["version"] == 1 and type(manifest["expected_sources"]) is int and manifest["expected_sources"] >= MINIMUM_SOURCES, "Unrecognized farm allowlist version/count")
    require(sorted(manifest["moved_roots"], key=lambda x: x["from"]) == sorted(MOVES, key=lambda x: x["from"]), "Only the three exact House archive moves are allowed")
    require(sum("Source" in n["properties"] for n in before.values()) == BASELINE_SOURCES, "Expected immutable 28-Source before-autumn baseline")
    require(set(sources) == {path for path, node in after.items() if "Source" in node["properties"]} and len(sources) == manifest["expected_sources"], "Candidate Source paths/count differ from sourcemap")
    for path, text in sources.items():
        require(after[path]["class"] == code_classes[path] and after[path]["class"] in SCRIPT_CLASSES, "Source class mismatch: " + path)
        require(after[path]["properties"]["Source"][1].replace("\r\n", "\n") == text, "Source mismatch: " + path)
    require({path for path in after if p.owned(path)} == set(code_classes), "Unexpected/missing code/data instance")
    for path, cls in code_classes.items():
        require(after[path]["class"] == cls, "Code/data class mismatch: " + path)
    manifest_changes = {}
    for path, changes in manifest["changes"].items():
        require(path in before and isinstance(changes, dict) and changes, "Invalid original change path: " + path)
        for prop, values in changes.items():
            require(set(values) == {"before", "after"}, "Invalid change record")
            canonical_value(values["before"])
            canonical_value(values["after"])
            manifest_changes[(path, prop)] = values
    require(set(manifest_changes) == set(world_changes), "Manifest original changes differ from road/barn allowlists")
    for (path, prop), values in manifest_changes.items():
        require(before[path]["properties"].get(prop) == values["before"], "Manifest before-value differs from immutable baseline: " + path + "/" + prop)
        old, new = world_changes[(path, prop)]
        require(leaf_matches(values["before"], old) and leaf_matches(values["after"], new), "Manifest changes exceed approved typed delta")
    targets = {moved_path(path) for path in before}
    require(len(targets) == len(before), "Archive target collision")
    require(targets.issubset(after), "Original/archived instance missing")
    additions = set(after) - targets
    expected_additions = world_paths | (set(code_classes) - set(before))
    require(additions == expected_additions, "Unexpected/missing new world/code instance: " + str(sorted(additions ^ expected_additions)[:10]))
    require(set(manifest["added_instances"]) == additions, "Full new-instance signatures missing or unexpected")
    for path, expected in manifest["added_instances"].items():
        canonical_record(expected)
        require(after[path] == expected, "New instance differs from full audited signature: " + path)
    changes = []
    for path, node in before.items():
        target = moved_path(path)
        other = after[target]
        require(node["class"] == other["class"], "Original class changed: " + path)
        require(set(node["properties"]) == set(other["properties"]), "Original property set changed: " + path)
        for prop, original in node["properties"].items():
            actual = other["properties"][prop]
            expected = remap_refs(original)
            values = manifest_changes.get((path, prop))
            if values:
                expected = remap_refs(values["after"])
            if actual == expected or normalized(actual) == normalized(expected):
                if actual != original and normalized(actual) != normalized(original):
                    changes.append({"path": path, "target": target, "property": prop, "reason": "approved_world_delta" if values else "archive_ref_remap"})
                continue
            allowed = (path in sources and prop == "Source") or (path == "Workspace/Camera" and prop in {"CFrame", "Focus"}) or (path in SELECTION_PATHS and node["class"] == "Instance" and prop == "UniqueId")
            require(allowed and not values, "Original property changed: " + path + "/" + prop)
            changes.append({"path": path, "target": target, "property": prop, "reason": "source" if prop == "Source" else "editor_metadata"})
    return {"allowed_changes": changes, "new_instances": len(additions), "archived_original_instances": sum(moved_path(path) != path for path in before), "matching_sources": len(sources)}


def geometry_data():
    result = {}
    for key in ("SM_Bld_Barn_03", "SM_Prop_Truck_Rusted_01", "SM_Prop_Tyre_01", "SM_Prop_Rubbish_Pile_05"):
        path = ROOT / "assets/farm/neutral" / (key + ".json")
        data = load_json(path)
        require(data["file"] == path.stem + ".fbx" and data["index_base"] == 1, "Unrecognized FarmGeometryData")
        result[path.stem] = data
    require(set(result) == {"SM_Bld_Barn_03", "SM_Prop_Truck_Rusted_01", "SM_Prop_Tyre_01", "SM_Prop_Rubbish_Pile_05"}, "Farm source assets differ")
    return result


def canonical_frame(value):
    require(value[0] == "CoordinateFrame", "Expected original canonical CFrame")
    components = {tag: float(child[1]) for tag, child in value[2]}
    tags = ["X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"]
    require(set(components) == set(tags), "Original CFrame components missing")
    return {"type": "CFrame", "value": [components[tag] for tag in tags]}


def world_specs(road, barns, geometry, original_dom=None):
    specs = {row["path"]: copy.deepcopy(row) for row in road["new_instances"]}
    if original_dom is None:
        immutable = ROOT / "place/Children_of_corn.before-autumn-20261012.rbxl"
        require(sha256(immutable) == road["baseline_sha256"] == barns["baseline_sha256"], "Sidecar immutable baseline mismatch")
        original_dom, _ = p.known_dom(immutable)
    # Lune's Part.CFrame getter quantizes rotations in the typed sidecar. These
    # reference snapshots must match the original referenced part, whose exact
    # canonical geometry is independently preserved by validate_dom.
    for path, record in specs.items():
        if path.startswith("Workspace/CornMap/Props/VillageRoad/HiddenCornIndex/"):
            require(record["class"] == "ObjectValue", "Unexpected hidden-corn record class")
            reference = record["props"]["Value"]["path"]
            require(reference in original_dom and reference in {row["path"] for row in road["changes"]}, "Hidden-corn reference not in approved baseline delta")
            require("OriginalFrame" in record["attrs"], "OriginalFrame snapshot missing")
            record["attrs"]["OriginalFrame"] = canonical_frame(original_dom[reference]["properties"]["CFrame"])

    require(len(specs) == len(road["new_instances"]) == 252, "Expected 252 road additions")
    for path, row in barns["added_instances"].items():
        require(moved_path(path) not in specs, "Added shell path collision")
        specs[moved_path(path)] = row
    require(len(barns["added_instances"]) == 21, "Expected 21 archived shell additions")
    project = {"type": "string", "value": "children_of_corn"}
    def owned(flag):
        return {flag: {"type": "boolean", "value": True}, "corn_project_id": project}
    specs["ServerStorage/CornFarmSceneArchive"] = {"class": "Folder", "attributes": owned("CornFarmArchiveOwned"), "tags": []}
    specs["ServerStorage/CornFarmAssets"] = {"class": "Folder", "attributes": owned("CornFarmAssetsOwned"), "tags": []}
    models = {"ServerStorage/CornFarmAssets/" + key: key for key in geometry}
    models.update({"Workspace/CornMap/Props/" + name: "SM_Bld_Barn_03" for name in HOUSE_NAMES})
    models["Workspace/CornMap/Props/RustedTruck"] = "SM_Prop_Truck_Rusted_01"
    models.update({"Workspace/CornMap/Props/Tyre_%02d" % n: "SM_Prop_Tyre_01" for n in range(1, 6)})
    models.update({"Workspace/CornMap/Props/RubbishPile_%02d" % n: "SM_Prop_Rubbish_Pile_05" for n in range(1, 4)})
    for path, key in models.items():
        attrs = owned("CornFarmAssetOwned") | {"AssetKey": {"type": "string", "value": key}, "FarmGeometryVersion": {"type": "number", "value": 1}, "SourceFbxSHA256": {"type": "string", "value": geometry[key]["source_sha256"]}}
        scale = 1
        if path.startswith("Workspace/"):
            scale = {"SM_Bld_Barn_03": 7.5 / 351.6280822753906, "SM_Prop_Truck_Rusted_01": 18 / geometry[key]["world_bounds"]["size"][2], "SM_Prop_Tyre_01": 1.8 / geometry[key]["world_bounds"]["size"][0], "SM_Prop_Rubbish_Pile_05": 3.2 / geometry[key]["world_bounds"]["size"][0]}[key]
        attrs["FarmUniformScale"] = {"type": "number", "value": scale}
        specs[path] = {"class": "Model", "attributes": attrs, "tags": []}
        names = set()
        for index, mesh in enumerate(geometry[key]["meshes"], 1):
            require(mesh["name"] not in names, "Duplicate farm mesh names")
            names.add(mesh["name"])
            meshattrs = owned("CornFarmMeshOwned") | {"AssetKey": {"type": "string", "value": key}, "MeshIndex": {"type": "number", "value": index}, "FarmGeometryVersion": {"type": "number", "value": 1}}
            if path.startswith("Workspace/") and key == "SM_Bld_Barn_03" and "_Door_" in mesh["name"]:
                meshattrs["FarmDoorHeldOpen"] = {"type": "boolean", "value": True}
            specs[path + "/" + mesh["name"]] = {"class": "MeshPart", "attributes": meshattrs, "tags": []}
    return specs


def float32(value):
    return struct.unpack("<f", struct.pack("<f", float(value)))[0]


def typed_matches(actual, expected):
    kind = expected["type"]
    if actual["type"] != kind:
        return False
    if kind == "CFrame" and "position" in expected:
        expected = {"type": kind, "value": expected["position"] + [expected["right"][0], expected["up"][0], -expected["look"][0], expected["right"][1], expected["up"][1], -expected["look"][1], expected["right"][2], expected["up"][2], -expected["look"][2]]}
    a, e = actual.get("value"), expected.get("value", expected.get("path"))
    if kind == "Instance":
        return a == moved_path(e)
    if kind == "EnumItem":
        if isinstance(e, dict):
            return a == e
        return a["value"] == e and expected["name"] == a["enum"] + "." + a["name"]
    if kind == "number":
        return float32(a) == float32(e)
    if kind in {"Vector3", "CFrame", "Color3"}:
        count = 12 if kind == "CFrame" else 3
        if len(a) != count or len(e) != count:
            return False
        for index, (x, y) in enumerate(zip(a, e)):
            tolerance = (0.5 / 255 + 1e-7 if kind == "Color3" else
                         SIDECAR_ROTATION_TOLERANCE if kind == "CFrame" and index >= 3 else
                         SIDECAR_POSITION_TOLERANCE)
            if not math.isfinite(x) or not math.isfinite(y) or abs(x - y) > tolerance:
                return False
        return True
    return a == e


def validate_world_signatures(signatures, specs):
    for path, expected in specs.items():
        require(path in signatures and signatures[path]["class"] == expected["class"], "World signature/class missing: " + path)
        actual = signatures[path]
        attrs = expected.get("attrs", expected.get("attributes"))
        if attrs is not None:
            require(set(actual["attributes"]) == set(attrs), "Unexpected world attributes: " + path)
        for key, value in (attrs or expected.get("required_attributes", {})).items():
            require(key in actual["attributes"] and typed_matches(actual["attributes"][key], value), "World ownership/attribute changed: " + path + "/" + key)
        for key, value in expected.get("props", expected.get("properties", {})).items():
            require(key in actual["properties"] and typed_matches(actual["properties"][key], value), "Road/shell geometry changed: " + path + "/" + key)
        if "tags" in expected:
            tags = expected["tags"]
            expected_tags = sorted(tags if isinstance(tags, list) else [key for key, enabled in tags.items() if enabled])
            require(sorted(actual["tags"]) == expected_tags, "World tags changed: " + path)


def typed_scene(path):
    result = subprocess.run([str(p.LUNE), "run", str(ROOT / "tests/farm-copy-metadata.luau"), str(path)], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return json.loads(result.stdout), result.stderr.decode("utf-8", "replace").strip()


def validate_unknown(before, after):
    require(before.get("supported") and after.get("supported"), "Raw binary property check unavailable")
    require(before == after, "Unknown binary property / raw Terrain changed")


def check(original, candidate, allowlist):
    original_hash, candidate_hash, allowlist_hash = sha256(original), sha256(candidate), sha256(allowlist)
    manifest = load_json(allowlist)
    require(manifest.get("baseline_sha256") == original_hash, "Farm allowlist baseline_sha256 mismatch")
    road = load_json(ROOT / "build/road-exit-allowlist-20261012.json")
    barns = load_json(ROOT / "build/open-barns-allowlist-20261012.json")
    world_changes = original_world_changes(road, barns, original_hash)
    sources, classes = mapping_from_sourcemap(ROOT / "build/sourcemap.json")
    before, warning_before = p.known_dom(original)
    specs = world_specs(road, barns, geometry_data(), before)
    after, warning_after = p.known_dom(candidate)
    unknown_before, unknown_after = p.unknown_properties(original), p.unknown_properties(candidate)
    validate_unknown(unknown_before, unknown_after)
    result = validate_dom(before, after, manifest, sources, classes, world_changes, set(specs))
    signatures, typed_warning = typed_scene(candidate)
    validate_world_signatures(signatures, specs)
    meta = p.corn_metadata(candidate)
    require(meta["corners_valid"] and meta["overview_owned"] and meta["preview_owned"], "CornMap ownership/corners invalid")
    # Guard against externally modified inputs during validation.
    require(sha256(original) == original_hash and sha256(candidate) == candidate_hash and sha256(allowlist) == allowlist_hash, "Input scene/allowlist changed during validation")
    return result | {"passed": True, "original_sha256": original_hash, "candidate_sha256": candidate_hash,
        "original_instances": len(before), "candidate_instances": len(after), "allowlist_sha256": allowlist_hash,
        "original_world_preserved_except_explicit_deltas": True, "raw_unknown_properties": unknown_after,
        "warnings": {"original": warning_before, "candidate": warning_after, "typed": typed_warning},
        "scope": "Read-only engine copy validation against independently audited canonical signatures; no promotion or scene write."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("original", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--allowlist", type=Path, default=ROOT / "build/farm-world-allowlist.json")
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    original, candidate, allowlist, report_path = (x.resolve() for x in (args.original, args.candidate, args.allowlist, args.report))
    require(report_path not in {original, candidate, allowlist}, "Report must not overwrite scene or allowlist")
    report = check(original, candidate, allowlist)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k not in {"allowed_changes", "warnings", "raw_unknown_properties"}}))
