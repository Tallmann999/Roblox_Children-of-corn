"""Strict read-only B save audit for frozen corn-edge/shadow/eye Source changes.

The exact accepted narrow-trail B is read from its immutable ZIP outside this
repository. No RBXL is serialized or promoted. Every retained identity, class,
name, parent, Source and property remains exact except the reviewed manifest.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys
import tempfile
import zipfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("corn_edge_shadow_dom_helpers", ROOT / "scripts/verify-maze02-copy.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
r, require, identity, remap_refs = m.r, m.require, m.identity, m.remap_refs
scalar, equivalent, native_to_dom = m.scalar, m.equivalent, m.native_to_dom
decode_attributes, attribute_matches, encode_attributes = m.decode_attributes, m.attribute_matches, m.encode_attributes
f32, vector_dom = m.f32, m.vector_dom
OUT = ROOT / ".artifacts/playtests/2026-10-21-corn-edge-shadows"
ARCHIVE = OUT / "before-corn-edge-shadows.zip"
ARCHIVE_ENTRY = "checkpoint/B-before-corn-edge-shadows.rbxl"
ARCHIVE_SHA256 = "2bf1ac59830101e707d5890875d6a439b8afe26261c89d48b7bde7110708e5cc"
BASELINE_SHA256 = "b113d584f1a60e16f34ba4ec40ce051b0338cab712467f07d762d9fc8528b1d2"
BASELINE_BYTES = 1497688
A_SHA256 = "c1f054029ca729f314889ce7874c17c6e5f772cb20541a9c0ceedd796f3446b7"
A_SCENE = ROOT / "place/Children_of_corn.rbxl"
INFO = OUT / "baseline.json"
PAYLOAD = OUT / "payload.json"
# Root pins this after final Source/native review. A missing pin refuses actual audit.
MANIFEST = OUT / "pipeline-manifest.json"
MANIFEST_SHA256 = "5df399edba71e9e9de6d2391e094dbaee48c5a76582d6add643e192f5def2aeb"
PAYLOAD_SHA256 = "b3217aa53f2b907b335f9288e72c7060dc8e9fd0d9c124ddbb6c5c94936cada6"
OWNER = "corn_edge_shadows_v1"
BASELINE_INSTANCES = 4634
BASELINE_SOURCES = 157
LIGHT_CLASSES = {"PointLight", "SpotLight", "SurfaceLight"}
PART_CLASSES = {"Part", "MeshPart", "UnionOperation", "WedgePart", "CornerWedgePart", "TrussPart", "Seat", "VehicleSeat", "SpawnLocation"}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def source_sha(value):
    require(isinstance(value, str), "Source text must be a string")
    return hashlib.sha256(value.replace("\r\n", "\n").encode()).hexdigest()


def baseline_info():
    info = json.loads(INFO.read_bytes(), object_pairs_hook=m.shadow.unique_object)
    expected = {"archive_sha256": ARCHIVE_SHA256, "baseline_sha256": BASELINE_SHA256,
                "baseline_bytes": BASELINE_BYTES, "untouched_A_sha256": A_SHA256}
    require(info == expected and type(info["baseline_bytes"]) is int, "Immutable corn-edge/shadow metadata differs")
    require(sha(ARCHIVE) == ARCHIVE_SHA256, "Immutable corn-edge/shadow ZIP changed")
    require(sha(A_SCENE) == A_SHA256, "Untouched A changed")
    return info


@contextmanager
def baseline_file():
    info_hash, info = sha(INFO), baseline_info()
    with zipfile.ZipFile(ARCHIVE) as archive:
        require(archive.namelist() == [ARCHIVE_ENTRY], "Unexpected baseline ZIP entries")
        entry = archive.getinfo(ARCHIVE_ENTRY)
        require(entry.file_size == BASELINE_BYTES, "Archived baseline length differs")
        data = archive.read(ARCHIVE_ENTRY)
    require(len(data) == BASELINE_BYTES and hashlib.sha256(data).hexdigest() == BASELINE_SHA256,
            "Archived baseline is not the accepted saved maze B")
    with tempfile.TemporaryDirectory(prefix="corn-edge-shadows-read-only-") as directory:
        path = Path(directory) / "B-before-corn-edge-shadows.rbxl"
        require(not path.resolve().is_relative_to(ROOT.resolve()), "Baseline temporary file must be external")
        path.write_bytes(data)
        yield path
        require(sha(path) == BASELINE_SHA256, "Temporary baseline changed")
    require(sha(INFO) == info_hash and baseline_info() == info, "Baseline inputs changed during read-only audit")


def read_baseline():
    with baseline_file() as path:
        before, warning = r.p.known_dom(path)
        unknown = r.p.unknown_properties(path)
    return before, warning, unknown


ALLOWED_SOURCE_PATHS = {
    "ReplicatedStorage/GameShared/Game/CornLayout",
    "ReplicatedStorage/GameShared/Game/CornAppearance",
    "ReplicatedStorage/GameShared/Game/HarvestWardenVisual",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornController",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornBackdropController",
}
EYE_PREFIX = "Workspace/CornMap/Props/ScarecrowMarker/HarvestWardenHome/Detailed/"
WORLD_CHANGES = [
    {"path": EYE_PREFIX + side + "/001_Material1", "property": prop,
     "attribute": is_attr, "before": 0, "after": 1}
    for side in ("LeftEye", "RightEye")
    for prop, is_attr in (("Transparency", False), ("HarvestVisibleTransparency", True))
]


def read_manifest():
    require(isinstance(MANIFEST_SHA256, str) and re.fullmatch("[0-9a-f]{64}", MANIFEST_SHA256),
            "Final reviewed pipeline manifest SHA256 must be pinned before save audit")
    require(sha(MANIFEST) == MANIFEST_SHA256, "Frozen pipeline manifest bytes changed")
    manifest = json.loads(MANIFEST.read_bytes(), object_pairs_hook=m.shadow.unique_object)
    require(isinstance(manifest, dict) and set(manifest) == {"version", "owner", "payload_sha256", "sourceChanges"}
            and type(manifest["version"]) is int and manifest["version"] == 1
            and manifest["owner"] == OWNER, "Unrecognized pipeline manifest")
    require(isinstance(manifest["payload_sha256"], str)
            and re.fullmatch("[0-9a-f]{64}", manifest["payload_sha256"]), "Invalid frozen payload SHA256")
    changes = manifest["sourceChanges"]
    require(isinstance(changes, dict) and set(changes) == ALLOWED_SOURCE_PATHS,
            "Pipeline must review exactly the five intended B Source replacements")
    for path, row in changes.items():
        require(isinstance(row, dict) and set(row) == {"before_sha256", "after_sha256"}
                and all(isinstance(v, str) and re.fullmatch("[0-9a-f]{64}", v) for v in row.values())
                and row["before_sha256"] != row["after_sha256"], "Invalid frozen Source hash pair: " + path)
    return manifest


def read_payload(expected_sha256=None):
    manifest = read_manifest()
    require(expected_sha256 is None or expected_sha256 == manifest["payload_sha256"],
            "Requested payload SHA256 differs from frozen manifest")
    require(sha(PAYLOAD) == manifest["payload_sha256"], "Reviewed corn-edge/shadow payload bytes changed")
    return json.loads(PAYLOAD.read_bytes(), object_pairs_hook=m.shadow.unique_object)


def resolve_before(before, row, index=None):
    """Resolve exact real Name and optional exact CFrame, including siblings."""
    path = row.get("path")
    # The native core flattens GetFullName dots to slash aliases. Permit only
    # these two reviewed eye aliases; real DOM Name and parent stay exact.
    aliases = {EYE_PREFIX + side + "/001_Material1": EYE_PREFIX + side + ".001_Material1"
               for side in ("LeftEye", "RightEye")}
    path = aliases.get(path, path)
    require(isinstance(path, str) and path and not path.startswith("/") and "//" not in path,
            "Malformed existing target path")
    parent, _, name = path.rpartition("/")
    index = m.resolver_index(before) if index is None else index
    group = index.get((parent, name), {"all": [], "positions": {}})
    candidates = group["all"]
    selector = row.get("selector")
    require("selectorCFrame" not in row, "Use the reviewed selector.CFrame schema")
    if selector is not None:
        require(isinstance(selector, dict) and set(selector) == {"CFrame"}, "Only exact CFrame duplicate selectors allowed")
        frame = selector["CFrame"]
        require(isinstance(frame, dict) and set(frame) == {"kind", "value"}
                and frame["kind"] == "CFrame" and isinstance(frame["value"], list)
                and len(frame["value"]) == 12, "Malformed exact selector CFrame")
        candidates = group["positions"].get(tuple(f32(v) for v in frame["value"][:3]), [])
        candidates = [p for p in candidates if "CFrame" in before[p]["properties"]
                      and equivalent(before[p]["properties"]["CFrame"],
                                     native_to_dom(frame, before[p]["properties"]["CFrame"], "CFrame"))]
    require(len(candidates) == 1, "Ambiguous/missing immutable target: " + path)
    return candidates[0]


def prepare_plan(before, payload):
    require(isinstance(payload, dict) and payload.get("owner") == OWNER, "Unrecognized corn-edge/shadow payload owner")
    reviewed = read_manifest()
    require(set(payload.get("sourceChanges", {})) == ALLOWED_SOURCE_PATHS,
            "Only the five reviewed B Source changes are allowed")
    expected_world = sorted(WORLD_CHANGES, key=lambda row: (row["path"], row["property"]))
    require(isinstance(payload.get("changes"), list)
            and sorted(payload["changes"], key=lambda row: (row.get("path", ""), row.get("property", ""))) == expected_world,
            "Only the exact two B red-eye surfaces and paired visibility metadata may change")
    require(isinstance(payload.get("changes"), list) and 0 < len(payload["changes"]) <= 16384,
            "Unbounded/empty property manifest")
    require(payload.get("nodes") == [], "This corn-edge/shadow audit permits no added world nodes")
    require(len(before) == BASELINE_INSTANCES, "Accepted maze B node count differs")
    retained_sources = {p: n for p, n in before.items() if "Source" in n["properties"]}
    sources = payload.get("sources")
    require(len(retained_sources) == BASELINE_SOURCES and isinstance(sources, dict)
            and set(sources) == set(retained_sources), "All 157 accepted B Sources must be pinned")
    for path, node in retained_sources.items():
        require(sources[path] == {"class": node["class"], "sha256": source_sha(node["properties"]["Source"][1])},
                "Immutable Source manifest differs: " + path)
    replacements = payload.get("sourceChanges", {})
    require(isinstance(replacements, dict) and len(replacements) <= 16, "Unbounded Source replacement manifest")
    source_changes = {}
    for path, row in replacements.items():
        require(path in retained_sources and isinstance(row, dict)
                and set(row) == {"before_sha256", "after_sha256", "source"}, "Malformed existing Source replacement")
        require(row["before_sha256"] == sources[path]["sha256"], "Replacement before Source hash differs")
        require({"before_sha256": row["before_sha256"], "after_sha256": row["after_sha256"]}
                == reviewed["sourceChanges"][path], "Source replacement differs from frozen independent manifest: " + path)
        text = row["source"]
        require(isinstance(text, str) and text.strip() and "\x00" not in text and "\r" not in text
                and len(text.encode()) <= 2_000_000, "Invalid replacement LF Source text")
        require(source_sha(text) == row["after_sha256"] and row["after_sha256"] != row["before_sha256"],
                "Replacement after Source hash differs or is a no-op")
        source_changes[path] = scalar("string", text)
    changes, attribute_changes = {}, {}
    index = m.resolver_index(before)
    for row in payload["changes"]:
        require(isinstance(row, dict) and set(row).issubset({"path", "property", "attribute", "before", "after", "selector", "installedSelector"})
                and {"path", "property", "attribute", "before", "after"}.issubset(row), "Unexpected property change fields")
        if "installedSelector" in row:
            require("selector" in row and row["installedSelector"] == row["selector"],
                    "Refinement installed selector must retain the exact immutable CFrame")
        require(type(row["attribute"]) is bool, "Attribute/property kind missing")
        target = resolve_before(before, row, index)
        prop = row["property"]
        require(isinstance(prop, str) and prop, "Invalid property/attribute name")
        node = before[target]
        in_map = target == m.MAP or target.startswith(m.MAP + "/")
        if row["attribute"]:
            require(in_map and "Source" not in node["properties"], "Attribute edit outside CornMap")
            key = (target, prop)
            require(key not in attribute_changes, "Duplicate declared attribute")
            attrs = decode_attributes(node["properties"]["AttributesSerialize"])
            old = row["before"]
            if old == {"kind": "Nil"}:
                require(prop not in attrs, "New attribute already exists in immutable baseline")
            else:
                require(prop in attrs and attribute_matches(attrs[prop], old), "Immutable attribute before differs: " + target + "/" + prop)
            require(row["before"] != row["after"], "No-op declared attribute")
            attribute_changes[key] = row
        else:
            require(prop not in m.PROTECTED and "Source" not in node["properties"], "Protected existing property declared")
            require(in_map or (prop == "CastShadow" and node["class"] in PART_CLASSES)
                    or (prop == "Shadows" and node["class"] in LIGHT_CLASSES), "Non-shadow edit outside CornMap")
            dom_prop = m.PROPERTY_NAMES.get(prop, prop)
            require(dom_prop in node["properties"], "Unknown existing property")
            key = (target, dom_prop)
            require(key not in changes, "Duplicate declared property")
            original = node["properties"][dom_prop]
            require(equivalent(original, native_to_dom(row["before"], original, prop)),
                    "Immutable before property differs: " + target + "/" + prop)
            expected = native_to_dom(row["after"], original, prop)
            require(not equivalent(original, expected), "No-op declared property")
            changes[key] = expected
    return changes, attribute_changes, source_changes


def canonicalize(before, after):
    old_ids = {identity(node): path for path, node in before.items()}
    require(len(old_ids) == len(before), "Duplicate immutable identity")
    paths, seen, targets = {}, set(), set()
    for path, node in after.items():
        uid = identity(node)
        require(uid not in seen, "Duplicate candidate identity")
        seen.add(uid)
        target = old_ids.get(uid)
        if target is None:
            selection = path in r.SELECTION_PATHS and node["class"] == "Instance" and node["properties"].get("Name") == scalar("string", "FilteredSelection")
            require(selection, "Unexpected/replaced identity: " + path)
            target = path
        require(target not in targets, "Duplicate canonical identity target")
        paths[path], _ = target, targets.add(target)
    require(targets == set(before), "Missing/extra retained objects")
    reindexed = sum(path != target for path, target in paths.items())
    canonical = {}
    for path, target in paths.items():
        actual, original = after[path], before[target]
        require(actual["class"] == original["class"] and actual["properties"].get("Name") == original["properties"]["Name"],
                "Retained class/real Name differs: " + target)
        parent, actual_parent = target.rpartition("/")[0], path.rpartition("/")[0]
        require((not parent and not actual_parent) or paths.get(actual_parent) == parent,
                "Retained parent identity differs: " + target)
        canonical[target] = actual if not reindexed else actual | {"properties": {prop: remap_refs(value, paths) for prop, value in actual["properties"].items()}}
    return canonical, reindexed


def validate_dom(before, after, payload):
    changes, attr_changes, source_changes = prepare_plan(before, payload)
    after, reindexed = canonicalize(before, after)
    require(len(after) == len(before), "Retained node count differs")
    require({p for p, n in before.items() if "Source" in n["properties"]}
            == {p for p, n in after.items() if "Source" in n["properties"]}, "Retained Source set differs")
    recorded, seen_changes, seen_attrs, seen_sources = [], set(), set(), set()
    attr_paths = {p for p, _ in attr_changes}
    for path, original in before.items():
        actual = after[path]
        require(set(actual["properties"]) == set(original["properties"]), "Retained property schema differs: " + path)
        for prop, value in original["properties"].items():
            other, key = actual["properties"][prop], (path, prop)
            if prop == "Source" and path in source_changes:
                require(other[0] == "string" and not other[2]
                        and other[1].replace("\r\n", "\n") == source_changes[path][1], "Declared replacement Source differs: " + path)
                seen_sources.add(path)
                reason = "exact_payload_Source"
            elif key in changes:
                require(equivalent(other, changes[key]), "Declared property differs: " + path + "/" + prop)
                seen_changes.add(key)
                reason = "exact_payload_property"
            elif prop == "AttributesSerialize" and path in attr_paths:
                old, new = decode_attributes(value), decode_attributes(other)
                expected_keys = set(old)
                declared_names = set()
                for (target, name), row in attr_changes.items():
                    if target != path:
                        continue
                    declared_names.add(name)
                    expected = row["after"]
                    if expected == {"kind": "Nil"}:
                        expected_keys.discard(name)
                        require(name not in new, "Deleted attribute retained")
                    else:
                        expected_keys.add(name)
                        require(name in new and attribute_matches(new[name], expected), "Declared attribute differs: " + path + "/" + name)
                    seen_attrs.add((target, name))
                require(set(new) == expected_keys, "Retained attribute set differs: " + path)
                for name in set(old) - declared_names:
                    require(new[name]["raw"] == old[name]["raw"], "Unchanged attribute bytes differ: " + path + "/" + name)
                reason = "exact_payload_attributes"
            elif value == other or r.normalized(value) == r.normalized(other):
                continue
            elif path == "Workspace/Camera" and prop in {"CFrame", "Focus"}:
                m.shadow.h.old.helpers.validate_camera_frame(other)
                reason = "finite_editor_camera"
            elif path in r.SELECTION_PATHS and original["class"] == "Instance" and prop == "UniqueId":
                reason = "editor_filtered_selection_identity"
            else:
                raise ValueError("Undeclared Source/world/art/Lighting/mesh change: " + path + "/" + prop)
            recorded.append({"path": path, "property": prop, "reason": reason})
    require(seen_changes == set(changes) and seen_attrs == set(attr_changes) and seen_sources == set(source_changes),
            "Frozen corn-edge/shadow deltas not fully applied")
    return {"passed": True, "complete": True, "variant": "B", "original_instances": len(before),
            "candidate_instances": len(after), "new_instances": 0, "removed_instances": 0,
            "unchanged_sources": BASELINE_SOURCES - len(source_changes), "total_sources": BASELINE_SOURCES,
            "source_changes": sorted(source_changes), "declared_property_changes": len(changes),
            "declared_attribute_changes": len(attr_changes), "added_world_nodes": 0,
            "reindexed_exporter_paths": reindexed, "retained_identities_classes_names_parents_exact": True,
            "all_other_world_art_lighting_physics_mesh_metadata_exact": True, "changes": recorded}


def check(candidate, expected_payload_sha256=None):
    candidate = Path(candidate).resolve()
    require(candidate.is_file() and candidate.suffix.lower() == ".rbxl", "An engine-saved binary RBXL is required")
    candidate_hash, payload_hash, manifest_hash = sha(candidate), sha(PAYLOAD), sha(MANIFEST)
    payload = read_payload(expected_payload_sha256)
    with baseline_file() as original:
        before, bwarn = r.p.known_dom(original)
        after, awarn = r.p.known_dom(candidate)
        ub, ua = r.p.unknown_properties(original), r.p.unknown_properties(candidate)
        r.validate_unknown(ub, ua)
        report = validate_dom(before, after, payload)
    require(sha(candidate) == candidate_hash and sha(PAYLOAD) == payload_hash and sha(MANIFEST) == manifest_hash, "Candidate/payload/manifest changed during audit")
    return report | {"baseline_sha256": BASELINE_SHA256, "candidate_sha256": candidate_hash,
                     "candidate_bytes": candidate.stat().st_size, "payload_sha256": payload_hash, "manifest_sha256": manifest_hash,
                     "untouched_A_sha256": A_SHA256, "raw_terrain_exact": True,
                     "raw_unknown_properties": ua, "warnings": {"baseline": bwarn, "candidate": awarn},
                     "scope": "Frozen corn-edge/shadow existing property/attribute/Source deltas only. All retained identities, classes, names, parents and all undeclared Source/world/art/physics/Lighting/mesh metadata/raw Terrain exact. Finite editor Camera and existing FilteredSelection identities only. No added nodes, scene serialization or promotion."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--payload-sha256")
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    output = args.report.resolve()
    require(output.is_relative_to(OUT.resolve()) and output.suffix.lower() == ".json", "Report must remain in corn-edge/shadow evidence")
    require(output not in {args.candidate.resolve(), PAYLOAD.resolve(), INFO.resolve(), MANIFEST.resolve(), (OUT / "native-before.json").resolve()},
            "Report would overwrite an audit input")
    report = check(args.candidate, args.payload_sha256)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes((json.dumps(report, ensure_ascii=False, indent=2) + "\n").encode())
    print(json.dumps({k: v for k, v in report.items() if k not in {"changes", "warnings", "raw_unknown_properties"}}))
