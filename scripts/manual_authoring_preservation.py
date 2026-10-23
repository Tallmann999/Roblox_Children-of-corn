"""Retained-node half of the manual B engine-Save audit.

Permissions come only from the independently frozen Source payload, native
transaction journal and reviewed native-build algorithm. Candidate differences
are observations, never permissions. New-node and corn validation is external.
All retained properties, including optional WorldPivotData and mesh/physics
metadata, remain exact unless an independently derived exact restoration plan
is supplied. This module never opens Studio or rewrites a scene.
"""
from __future__ import annotations

import collections
import hashlib
import gzip
import importlib.util
import json
from pathlib import Path
import re
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".artifacts/playtests/2026-10-23-B-manual-authoring"
spec = importlib.util.spec_from_file_location("manual_preservation_dom_helpers", ROOT / "scripts/verify-B-green-variants-copy.py")
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)
h, require, identity, scalar = v.h, v.require, v.identity, v.scalar
BASELINE_NODES = 6056  # Includes all three unlike-class root services named Instance.
BASELINE_SHA256 = "c91efe74d1750095eac19390800192ad03b264d7a99de46cf21d170fcb4ed31f"
CANDIDATE_SHA256 = "4c5c0c5454da2689996babca4a88b66256240ebb2fb0ac7aa2f787b2ecd8227a"
JOURNAL_SHA256 = "83364c9e2b2e12e2940129afcf0a10cfa8c60d9d6308783c896b31aefc7f5f89"
PAYLOAD_SHA256 = "dd8d3492d53f77ba99d39c50e7581f28821acdb3c305f64931e5eb2d74563e6f"
BUILD_SHA256 = "b17dfb535f8fb5adc82af7da2706521daf77fb259b755bfb7786e7375cd40ae0"
BASELINE_DOM_JSON_SHA256 = "4c924e7592f91def4afe0ad9ab7e30d9a629c85d8ed01f1a6497d6277e9d0b28"
AUTHOR_FIXTURE_SHA256 = "5a22304e0ca9e3c0032c0bb64130a5c66a3d748c6a34e89f121f4449134ed342"
EDITOR_ROOTS = ("Workspace/CornMap/EditorPreview", "Workspace/CornMap/EditorFieldOverview")
PART_CLASSES = h.PART_CLASSES


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def pinned_json(name, expected):
    raw = (OUT / name).read_bytes()
    require(digest(raw) == expected, "Frozen audit evidence changed: " + name)
    return json.loads(raw, object_pairs_hook=v.unique_object)


def pin_inputs(payload, journal):
    require(payload == pinned_json("payload-editor-pool.json", PAYLOAD_SHA256), "Caller Source payload differs from frozen review")
    require(journal == pinned_json("native-change-journal.json", JOURNAL_SHA256), "Caller journal differs from frozen review")
    require(digest((OUT / "native-build.luau").read_bytes()) == BUILD_SHA256, "Reviewed native grouping algorithm changed")
    require(journal["owner"] == "CornBManualAuthoringV1" and journal["baselineSHA256"] == BASELINE_SHA256
            and journal["journalRows"] == len(journal["rows"]) == 1960, "Journal provenance differs")


def index(dom):
    by_uid = {}
    for path, node in dom.items():
        uid = identity(node)
        require(re.fullmatch(r"[0-9a-fA-F]{32}", uid) and int(uid, 16) != 0, "Missing/zero/malformed saved identity: " + path)
        require(uid not in by_uid, "Duplicate saved identity: " + path)
        by_uid[uid] = path
    return by_uid


def live_paths(before):
    cache = {}
    def name(path):
        if not path:
            return ""
        if path not in cache:
            parent = path.rpartition("/")[0]
            prefix = name(parent)
            cache[path] = (prefix + "/" if prefix else "") + before[path]["properties"]["Name"][1]
        return cache[path]
    lookup = collections.defaultdict(list)
    for path in before:
        lookup[name(path)].append(path)
    return dict(lookup)


def native_value(row):
    require(isinstance(row, dict), "Malformed native value")
    kind = row.get("kind")
    if kind == "nil":
        require(set(row) == {"kind"}, "Malformed nil value")
        return None
    if kind in {"number", "boolean", "string"}:
        require(set(row) == {"kind", "value"}, "Malformed primitive value")
        return row["value"]
    require(kind in {"CFrame", "Vector3", "Color3"}, "Unsupported native value kind")
    return row


def prepare_plan(before, payload, journal):
    """Derive every explicit retained edit without consulting the candidate."""
    pin_inputs(payload, journal)
    require(len(before) == BASELINE_NODES, "Full 6056-node baseline required; legacy known_dom overwrote two root services")
    index(before)
    lookup = live_paths(before)
    def resolve(path):
        matches = lookup.get(path, [])
        require(len(matches) == 1, "Ambiguous/nonexistent non-corn journal target: " + str(path))
        return matches[0]
    properties, parents, attrs = {}, {}, {}
    native_ids, source_rows = {}, set()
    hidden = collections.defaultdict(set)
    old_sources = {p for p, n in before.items() if "Source" in n["properties"]}
    require(old_sources == set(payload["expectedBeforeSources"]) and len(old_sources) == 168, "Original 168-Source graph differs")
    for path in old_sources:
        row = payload["expectedBeforeSources"][path]
        require(before[path]["class"] == row["class"]
                and h.source_sha(before[path]["properties"]["Source"][1]) == row["sha256"], "Original Source pin differs: " + path)
    # The reviewed group() loop hides every BasePart in exactly these two roots.
    # Native GetFullName is ambiguous for 431 Corn + 1383 DistantCorn objects;
    # enumerate their saved UIDs independently, never assign one native ID to all.
    hide_by_live = collections.defaultdict(set)
    for path, node in before.items():
        if node["class"] in PART_CLASSES and any(path.startswith(root + "/") for root in EDITOR_ROOTS):
            if not v.expected_same(node["properties"]["Transparency"], scalar("float", "1")):
                properties[path, "Transparency"] = scalar("float", "1")
                for live, matches in lookup.items():
                    if path in matches:
                        hide_by_live[live].add(path)
                        break
    require(sum(map(len, hide_by_live.values())) == 1814, "Reviewed old preview-hide set differs")
    for row in journal["rows"]:
        baseline_path, prop = row.get("baselinePath"), row.get("property")
        if not baseline_path:
            require(prop == "Source" and row["path"] in payload["newSources"] and row.get("exactBytesDefinedByFrozenPayload") is True,
                    "Unrecognized journal row for a new node")
            continue
        if prop == "Transparency" and baseline_path in hide_by_live:
            require(native_value(row["before"]) == 0 and native_value(row["after"]) == 1, "Preview-hide row differs")
            require(row["id"] not in hidden[baseline_path], "Duplicate native preview-hide row")
            hidden[baseline_path].add(row["id"])
            continue
        path = resolve(baseline_path)
        if path in native_ids:
            require(native_ids[path] == row["id"], "One saved target has multiple native identities")
        native_ids[path] = row["id"]
        original = before[path]
        if prop == "Source":
            require(path in payload["sourceChanges"] and row.get("exactBytesDefinedByFrozenPayload") is True, "Unreviewed Source journal row")
            properties[path, "Source"] = scalar("string", payload["sourceChanges"][path]["source"])
            source_rows.add(path)
        elif prop == "Parent":
            require(path not in parents and row["before"]["kind"] == row["after"]["kind"] == "Instance", "Repeated/malformed parent move")
            old_parent = path.rpartition("/")[0]
            require(resolve(row["before"].get("baselinePath", row["before"]["path"])) == old_parent, "Parent before-value differs")
            target = row["after"]
            if target.get("baselinePath"):
                destination = ("retained", resolve(target["baselinePath"]))
            else:
                destination = ("new", target["path"])
                parent = target["path"].rpartition("/")[0]
                real_name = target["path"].rsplit("/", 1)[-1]
                if real_name.startswith("Site_"):
                    require(parent == "Workspace/CornMap/KeySlots" and real_name[5:] in {
                        h.decode_attributes(n["properties"]["AttributesSerialize"])["slot_id"]["value"]
                        for p, n in before.items() if p.rpartition("/")[0] == parent and "slot_id" in h.decode_attributes(n["properties"]["AttributesSerialize"])
                    }, "Unreviewed new Site parent")
                else:
                    require(real_name == "B_Visuals" and parent in {"Workspace/CornMap/Props/" + x for x in ("HouseWest", "HouseEast", "HouseNorthWest")}, "Unreviewed new overlay parent")
            parents[path] = destination
        elif prop in {"Transparency", "Color"}:
            stored = "Color3uint8" if prop == "Color" else prop
            require((path, stored) not in properties and stored in original["properties"], "Repeated/unknown retained property row")
            template = original["properties"][stored]
            previous = h.native_to_dom(native_value(row["before"]), template, prop)
            require(v.expected_same(template, previous), "Retained before-property differs: " + path + "/" + prop)
            properties[path, stored] = h.native_to_dom(native_value(row["after"]), template, prop)
        else:
            require(prop is None and row.get("attribute") in {"BAuthoringHelper", "BManualAuthoringVersion"}, "Unreviewed journal property/attribute")
            key = row["attribute"]
            values = attrs.setdefault(path, {k: r["value"] for k, r in h.decode_attributes(original["properties"]["AttributesSerialize"]).items()})
            previous, after = native_value(row["before"]), native_value(row["after"])
            require((key not in values if previous is None else values.get(key) == previous), "Attribute before-value differs")
            require(after is not None, "Reviewed transaction adds, never removes, authoring attributes")
            values[key] = after
    require({k: len(vv) for k, vv in hidden.items()} == {k: len(vv) for k, vv in hide_by_live.items()}, "Native hide journal does not cover independent saved preview set")
    require(source_rows == set(payload["sourceChanges"]) and len(source_rows) == 8, "Complete eight-Source replacement set required")
    require(len(parents) == 75 and len(attrs) == 20, "Explicit move/attribute set differs")
    for path, values in attrs.items():
        properties[path, "AttributesSerialize"] = h.encode_attributes(values)
    return {"properties": properties, "parents": parents, "preview_hidden": 1814,
            "source_changes": sorted(source_rows), "new_parent_paths": sorted({p for kind, p in parents.values() if kind == "new"})}


def reference_identity(value, dom):
    """Compare saved references by target identity, independent of exporter paths."""
    kind, text, children = value
    if kind == "Ref" and text in dom:
        text = "UID:" + identity(dom[text])
    return [kind, text, [[name, reference_identity(child, dom)] for name, child in children]]


def summarize(value):
    raw = json.dumps(value, separators=(",", ":"), ensure_ascii=False).encode()
    return value if len(raw) <= 400 else {"type": value[0], "bytes": len(raw), "sha256": digest(raw)}


def independent_vertex_restoration(before):
    """Expected VertexCount from immutable geometry channels, never the candidate.

    Farm/Harvest allocate one position vertex per data position. The opaque
    green-bed bake expands indexed position/UV/normal corner combinations.
    Every expected number is recomputed from the accepted Source data.
    """
    decoded = {}
    def data(path):
        if path not in decoded:
            require(path in before and "Source" in before[path]["properties"], "Immutable geometry Source missing: " + path)
            source = before[path]["properties"]["Source"][1]
            inline = re.search(r"\[==\[(.*?)\]==\]", source, re.S)
            if inline:
                text = inline.group(1)
            else:
                names = re.findall(r'"(Chunk\d+)"', source)
                require(names and len(names) == len(set(names)), "Explicit geometry chunks required: " + path)
                chunks = []
                for name in names:
                    chunk = before[path + "/" + name]["properties"]["Source"][1]
                    match = re.search(r"\[==\[(.*?)\]==\]", chunk, re.S)
                    require(match is not None, "Exact literal geometry chunk required")
                    chunks.append(match.group(1))
                text = "".join(chunks)
            decoded[path] = json.loads(text, object_pairs_hook=v.unique_object)
        return decoded[path]
    changes, counts = {}, collections.Counter()
    for path, node in before.items():
        if node["class"] != "MeshPart":
            continue
        attrs = {k: row["value"] for k, row in h.decode_attributes(node["properties"]["AttributesSerialize"]).items()}
        expected, evidence, family = None, None, None
        if attrs.get("BGreenBedsOwner") == "corn_B_green_beds_v1":
            require(path.startswith("Workspace/CornMap/GreenBedEditor/"), "Owned bed outside original folder")
            key = attrs.get("BGreenBedGeometryKey")
            require(key in {"Center", "End", "Skirt"}, "Unknown canonical bed geometry")
            source = "ReplicatedStorage/GameShared/Game/GreenBedGeometryData/" + key
            geometry = data(source)
            require(geometry["key"] == key and attrs["BGreenBedSourceSHA256"] == geometry["source_sha256"], "Bed geometry provenance differs")
            require(len(geometry["triangles"]) == len(geometry["triangle_uvs"]) == len(geometry["triangle_normals"]), "Bed channel counts differ")
            corners = set()
            for positions, uvs, normals in zip(geometry["triangles"], geometry["triangle_uvs"], geometry["triangle_normals"]):
                require(len(positions) == len(uvs) == len(normals) == 3, "Bed triangle corner count differs")
                for position, uv, normal in zip(positions, uvs, normals):
                    require(1 <= position <= len(geometry["positions"]) and 1 <= uv <= len(geometry["uvs"])
                            and 1 <= normal <= len(geometry["normals"]), "Bed corner index outside canonical channels")
                    corners.add((position, uv, normal))
            expected, family = len(corners), "beds"
            evidence = source + ": exact distinct (position,UV,normal) indices of opaque bake"
        elif attrs.get("HarvestGeometryOwner") == "harvest_warden_v1":
            key = attrs.get("HarvestMeshKey")
            require(isinstance(key, str) and "/" in key and attrs.get("corn_project_id") == "children_of_corn", "Harvest mesh ownership/key differs")
            asset = key.split("/", 1)[0]
            source = "ReplicatedStorage/GameShared/Game/HarvestGeometryData/" + asset
            geometry = data(source)["meshes"][key]
            require(geometry["assetKey"] == asset and len(geometry["positions"]) == len(geometry["normals"]) == len(geometry["uvs"]), "Harvest per-vertex channels differ")
            used = {index for triangle in geometry["triangles"] for index in triangle}
            require(used == set(range(1, len(geometry["positions"]) + 1)), "Harvest geometry has unreferenced/missing vertices")
            expected, family = len(geometry["positions"]), "harvest"
            evidence = source + ": exact canonical position/normal/UV vertex allocation for " + key
        elif attrs.get("CornFarmMeshOwned") is True:
            asset, mesh_index = attrs.get("AssetKey"), attrs.get("MeshIndex")
            require(isinstance(asset, str) and type(mesh_index) in {int, float} and int(mesh_index) == mesh_index, "Farm geometry binding differs")
            source = "ReplicatedStorage/GameShared/Game/FarmGeometryData/" + asset
            meshes = data(source)["meshes"]
            require(1 <= mesh_index <= len(meshes), "Farm mesh index outside canonical data")
            geometry = meshes[int(mesh_index) - 1]
            expected, family = len(geometry["positions"]), "farm"
            evidence = source + ": exact EditableMesh position allocation, mesh index " + str(int(mesh_index))
        if expected is not None:
            old = node["properties"]["VertexCount"]
            require(old[0] == "int" and not old[2] and int(old[1]) in {0, expected}, "Unexpected pre-existing canonical VertexCount: " + path)
            changes[path, "VertexCount"] = {"before": old, "after": scalar("int", expected), "evidence": evidence}
            counts[family] += 1
    # Harvest's 244 art objects include two ordinary Parts; only 242 have mesh
    # vertex metadata. The 40 Farm meshes include 12 ServerStorage templates.
    require(dict(counts) == {"harvest": 242, "farm": 40, "beds": 1406}, "Complete fixed restoration population differs")
    return changes, dict(counts)


def frame_components(value):
    require(value[0] in {"CFrame", "CoordinateFrame"}, "Exact frame DOM required")
    names = ["X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"]
    require([row[0] for row in value[2]] == names, "Frame component schema differs")
    return [h.f32(float(row[1][1])) for row in value[2]]


def independent_model_mesh_restoration(before):
    """Four exact hidden residues of two documented, restored edit fixtures.

    Native arithmetic was evaluated from immutable pre-fixture CFrames only;
    its input, pure-math Source and result are separately pinned. There is no
    general model metadata allowance or candidate-value-derived permission.
    """
    require(digest((OUT / "native-author-edit-fixture.luau").read_bytes()) == AUTHOR_FIXTURE_SHA256, "Reviewed two-Stage fixture changed")
    inputs = pinned_json("model-metadata-math-input.json", "e17216bacb5d6bfd134a3cea9ee91e23fe489530e8e49a43ab773f240985abd6")
    outputs = pinned_json("model-metadata-readonly-math.json", "7e89abb7e16cb058a2d4638edd40995dc5202dc272ab6055a8d3b340aa53b2e5")
    require(digest((OUT / "model-metadata-readonly-math.luau").read_bytes()) == "bf4ee201fc84e99d769744a295b01b64bff607a089fd0d3bc10dd566ea47da26", "Reviewed independent native arithmetic changed")
    require(inputs["stage_count"] == outputs["stage_count"] == 2 and inputs["baseline_only"] is outputs["baseline_only"] is True
            and inputs["author_fixture_sha256"] == outputs["author_fixture_sha256"] == AUTHOR_FIXTURE_SHA256
            and inputs["native_build_sha256"] == BUILD_SHA256, "Model arithmetic provenance differs")
    targets = {"Workspace/CornMap/Props/" + name for name in ("HouseWest", "HouseEast", "HouseNorthWest", "ScarecrowMarker")}
    rows = {row["path"]: row for row in inputs["rows"] if row["path"] in targets}
    require(set(rows) == targets, "Four retained model arithmetic inputs required")
    changes = {}
    for path, row in rows.items():
        original = before[path]
        require(original["class"] == "Model", "Retained arithmetic target must be Model")
        pivot = original["properties"]["WorldPivotData"]
        require(pivot[0] == "OptionalCoordinateFrame" and len(pivot[2]) == 1 and pivot[2][0][0] == "CFrame", "Immutable explicit original model pivot required")
        require(row["pivot"] == frame_components(pivot[2][0][1])
                and row["before"] == frame_components(original["properties"]["ModelMeshCFrame"]), "Native arithmetic input differs from immutable model")
        warden = path.endswith("/ScarecrowMarker")
        require(row["offset"] == ([1, 0, 1] if warden else [0.25, 0, 0.5]) and row["yaw"] == (0 if warden else 0.01), "Stage transform differs from reviewed fixture")
        after = h.vector_dom("CoordinateFrame", outputs["modelMeshCFrames"][path])
        changes[path, "ModelMeshCFrame"] = {"before": original["properties"]["ModelMeshCFrame"], "after": after,
                                             "evidence": "Immutable model pivot + frozen Stage/Restore transform, exact native float32 evaluation twice; result 7e89abb7"}
    return changes


def independent_torch_pivot_restoration(before):
    """Six exact materialized pivots from immutable oriented two-part bounds."""
    inputs = pinned_json("model-pivot-math-input.json", "48fbfb6dafbcf7e1089acb1d30b4453c63160a0aada88b787ce27bf38c439c22")
    outputs = pinned_json("model-pivot-readonly-math.json", "5a64fad3c5c7f8f42086da4c3a819730f779d5deb471c90aa9d0a4210db39c81")
    require(digest((OUT / "model-pivot-readonly-math.luau").read_bytes()) == "d42914f16e26eedf65c6a3eee69bea8af23c7e5166462730d59166e9f98ddedc", "Independent oriented-bound arithmetic changed")
    require(inputs["baseline_only"] is outputs["baseline_only"] is True and inputs["stage_count"] == 2
            and inputs["author_fixture_sha256"] == outputs["author_fixture_sha256"] == AUTHOR_FIXTURE_SHA256
            and inputs["native_build_sha256"] == BUILD_SHA256, "Pivot arithmetic provenance differs")
    targets = {"Workspace/CornMap/TorchMarkers/torch_" + house + side
               for house in ("HouseWest", "HouseEast", "HouseNorthWest") for side in ("-1", "1")}
    rows = {row["path"]: row for row in inputs["rows"] if row["path"] in targets}
    require(set(rows) == targets, "Six exact original house torch inputs required")
    changes = {}
    for path, row in rows.items():
        original = before[path]
        pivot = original["properties"]["WorldPivotData"]
        require(original["class"] == "Model" and pivot[0] == "OptionalCoordinateFrame" and not pivot[2], "Only original absent house-torch pivots may materialize")
        primary = original["properties"]["PrimaryPart"]
        require(primary == scalar("Ref", path + "/Pole") and primary[1] in before, "Original torch basis differs")
        require(row["basis"] == frame_components(before[primary[1]]["properties"]["CFrame"]), "Oriented-bound basis differs from original Pole")
        parts = []
        for child_path, node in before.items():
            if child_path.startswith(path + "/") and node["class"] in PART_CLASSES:
                size = node["properties"]["size"]
                require(size[0] == "Vector3" and [x[0] for x in size[2]] == ["X", "Y", "Z"], "Original torch part size schema differs")
                parts.append((tuple(frame_components(node["properties"]["CFrame"])), tuple(h.f32(float(x[1][1])) for x in size[2])))
        given = [(tuple(x["frame"]), tuple(x["size"])) for x in row["parts"]]
        require(len(parts) == len(given) == 2 and collections.Counter(parts) == collections.Counter(given), "Oriented-bound input differs from original exact two torch parts")
        expected = h.vector_dom("CoordinateFrame", outputs["worldPivots"][path])
        expected[0] = "CFrame"
        after = ["OptionalCoordinateFrame", "", [["CFrame", expected]]]
        changes[path, "WorldPivotData"] = {"before": pivot, "after": after,
                                            "evidence": "Original Pole basis + exact original two cuboids; independent native oriented-bound arithmetic 5a64fad3; materialized by documented Stage/Restore"}
    return changes


def restoration_equal(actual, expected):
    if v.expected_same(actual, expected):
        return True
    if actual[0] == expected[0] == "OptionalCoordinateFrame":
        if len(actual[2]) == len(expected[2]) == 1 and actual[2][0][0] == expected[2][0][0] == "CFrame":
            left, right = actual[2][0][1], expected[2][0][1]
            require(left[0] == right[0] == "CFrame", "Optional CFrame payload type differs")
            return h.equivalent(["CoordinateFrame", left[1], left[2]], ["CoordinateFrame", right[1], right[2]])
    return False


def validate(before, after, payload, journal, restoration_plan=None):
    """Validate all retained nodes; unexplained mesh/pivot deltas return incomplete.

    restoration_plan, when supplied, must be independent baseline+canonical-data
    output of the main validator, never constructed from observed differences:
    {(baseline_path, property): {before:<DOM>, after:<DOM>, evidence:<str>}}.
    This helper does not certify that external derivation's provenance itself.
    """
    plan = prepare_plan(before, payload, journal)
    before_ids, after_ids = index(before), index(after)
    vertex_plan, vertex_population = independent_vertex_restoration(before)
    model_mesh_plan = independent_model_mesh_restoration(before)
    torch_pivot_plan = independent_torch_pivot_restoration(before)
    restoration_plan = restoration_plan or {}
    require(not (set(vertex_plan) | set(model_mesh_plan) | set(torch_pivot_plan)) & set(restoration_plan), "External plan cannot override independent canonical derivations")
    restoration_plan = vertex_plan | model_mesh_plan | torch_pivot_plan | restoration_plan
    missing, errors, changes = [], [], []
    candidates, selection_identity_changes = {}, set()
    for uid, path in before_ids.items():
        target = after_ids.get(uid)
        if target is None and path in v.r.SELECTION_PATHS and path in after:
            if before[path]["class"] == after[path]["class"] == "Instance" and before[path]["properties"]["Name"] == after[path]["properties"].get("Name"):
                target = path; selection_identity_changes.add(path)
        if target is None:
            missing.append(path)
        else:
            candidates[path] = target
    for path, target in candidates.items():
        original, actual = before[path], after[target]
        if original["class"] != actual["class"] or original["properties"]["Name"] != actual["properties"].get("Name"):
            errors.append({"path": path, "candidate_path": target, "problem": "retained_class_or_real_name_changed"}); continue
        old_parent, actual_parent = path.rpartition("/")[0], target.rpartition("/")[0]
        destination = plan["parents"].get(path, ("retained", old_parent))
        kind, expected_parent = destination
        if kind == "retained":
            wanted_uid = identity(before[expected_parent]) if expected_parent else None
            actual_uid = identity(after[actual_parent]) if actual_parent else None
            parent_ok = wanted_uid == actual_uid
        else:
            parent_node = after.get(actual_parent)
            parent_ok = (actual_parent == expected_parent and parent_node is not None and parent_node["class"] == "Model"
                         and parent_node["properties"]["Name"] == scalar("string", expected_parent.rsplit("/", 1)[-1])
                         and identity(parent_node) not in before_ids)
        if not parent_ok:
            errors.append({"path": path, "candidate_path": target, "problem": "undeclared_parent_change", "expected_parent": destination, "actual_parent": actual_parent})
        elif path in plan["parents"]:
            changes.append({"path": path, "property": "Parent", "reason": "exact_pinned_native_journal"})
        if set(original["properties"]) != set(actual["properties"]):
            errors.append({"path": path, "problem": "retained_property_schema_changed", "missing": sorted(set(original["properties"]) - set(actual["properties"])),
                           "extra": sorted(set(actual["properties"]) - set(original["properties"]))}); continue
        for prop, value in original["properties"].items():
            other, key = actual["properties"][prop], (path, prop)
            if key in plan["properties"]:
                wanted = plan["properties"][key]
                same = v.attributes_same(other, wanted) if prop == "AttributesSerialize" else v.expected_same(other, wanted)
                if same:
                    changes.append({"path": path, "property": prop, "reason": "exact_pinned_native_journal_or_preview_algorithm"})
                else:
                    errors.append({"path": path, "property": prop, "problem": "declared_after_value_differs", "expected": summarize(wanted), "after": summarize(other)})
                continue
            left, right = reference_identity(value, before), reference_identity(other, after)
            if v.same(left, right):
                # An unchanged saved cache value remains exact preservation;
                # the restoration plan permits a precise alternate value only.
                continue
            if key in restoration_plan:
                row = restoration_plan[key]
                require(set(row) == {"before", "after", "evidence"} and isinstance(row["evidence"], str) and row["evidence"], "Malformed independent restoration permission")
                require(v.same(value, row["before"]), "Independent restoration baseline differs")
                if restoration_equal(other, row["after"]):
                    if not v.same(left, right):
                        changes.append({"path": path, "property": prop, "reason": "independent_exact_restoration", "evidence": row["evidence"]})
                else:
                    errors.append({"path": path, "property": prop, "problem": "independent_restoration_value_differs", "after": summarize(other)})
            elif path == "Workspace/Camera" and prop in {"CFrame", "Focus"}:
                h.m.shadow.h.old.helpers.validate_camera_frame(other)
                changes.append({"path": path, "property": prop, "reason": "finite_existing_editor_camera"})
            elif path in selection_identity_changes and prop == "UniqueId":
                changes.append({"path": path, "property": prop, "reason": "existing_filtered_selection_identity"})
            else:
                errors.append({"path": path, "candidate_path": target, "property": prop, "problem": "unapproved_retained_property_change",
                               "before": summarize(value), "after": summarize(other)})
    unresolved = collections.Counter(row.get("property", row["problem"]) for row in errors)
    return {"passed": not missing and not errors, "complete": not missing and not errors,
            "scope": "All 6056 retained saved objects only; new-node/corn/raw-unknown validation is external",
            "baseline_sha256": BASELINE_SHA256, "candidate_sha256": CANDIDATE_SHA256,
            "retained_expected": BASELINE_NODES, "retained_found": len(candidates), "retained_missing": missing,
            "retained_parent_changes": len(plan["parents"]), "declared_property_changes": len(plan["properties"]),
            "independently_hidden_old_preview_plants": 1814, "changed_sources": plan["source_changes"],
            "new_parent_paths_requiring_external_new_node_validation": plan["new_parent_paths"],
            "unresolved_by_property": dict(unresolved), "unapproved_changes": errors, "changes": changes,
            "optional_world_pivots_have_no_general_exception": True,
            "independent_vertex_restoration_population": vertex_population,
            "independently_derived_hidden_model_mesh_frames": len(model_mesh_plan),
            "independently_derived_materialized_old_torch_pivots": len(torch_pivot_plan),
            "all_retained_mesh_physics_properties_have_no_general_exception": True}


def main():
    """Fresh no-argument retained proof over the root's lossless stream caches."""
    baseline_raw = gzip.decompress((OUT / "baseline-known-dom.json.gz").read_bytes())
    require(digest(baseline_raw) == BASELINE_DOM_JSON_SHA256, "Full immutable baseline DOM cache changed")
    candidate = ROOT / "place/Children_of_corn_B.rbxl"
    candidate_bytes = candidate.read_bytes()
    require(len(candidate_bytes) == 3793205 and digest(candidate_bytes) == CANDIDATE_SHA256, "Author-saved candidate changed")
    before = json.loads(baseline_raw, object_pairs_hook=v.unique_object)
    cache = OUT / "candidate-noncorn-dom.json.gz"
    after_raw = gzip.decompress(cache.read_bytes())
    after = json.loads(after_raw, object_pairs_hook=v.unique_object)
    payload = pinned_json("payload-editor-pool.json", PAYLOAD_SHA256)
    journal = pinned_json("native-change-journal.json", JOURNAL_SHA256)
    report = validate(before, after, payload, journal)
    require(candidate.read_bytes() == candidate_bytes, "Author-saved candidate changed during retained validation")
    require(digest(gzip.decompress(cache.read_bytes())) == digest(after_raw), "Candidate observation cache changed during validation")
    report.update({"candidate_bytes": len(candidate_bytes), "baseline_dom_json_sha256": digest(baseline_raw),
                   "candidate_noncorn_dom_json_sha256": digest(after_raw),
                   "journal_sha256": JOURNAL_SHA256, "payload_sha256": PAYLOAD_SHA256,
                   "observed_noncorn_nodes": len(after), "scene_bytes_unchanged_during_audit": True})
    (OUT / "save-retained-validation.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: value for key, value in report.items() if key not in {"changes", "unapproved_changes"}}, indent=2))
    if report["unapproved_changes"]:
        print(json.dumps({"first_unapproved_changes": report["unapproved_changes"][:8]}, indent=2))


if __name__ == "__main__":
    main()
