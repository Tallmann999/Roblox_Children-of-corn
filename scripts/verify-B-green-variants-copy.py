"""Read-only, explicitly pinned B green-corn variants engine-save audit.

The reviewed payload pins every old/new Source. The independently frozen
world-plan pins every changed retained property and the COMPLETE known DOM of
each addition (except engine-generated UniqueId/HistoryId/ScriptGuid, which
normal Studio APIs cannot read). Neither input scene is rewritten.
Unknown binary properties, including raw Terrain, must remain byte-identical.

world-plan schema:
  {version:1, owner:OWNER, baseline_sha256:BASELINE_SHA256,
   payload_sha256:<reviewed hash>,
   retained_changes:[{path,uid,property,before:<DOM triple>,after:<DOM triple>}],
   new_nodes:{path:{class,properties:{<complete DOM except generated metadata>}}}}

Payload sources/sourceChanges use the existing guarded-installer schema;
newSources is {path:{class,sha256,source}}. Explicit CLI pins are required.
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
spec = importlib.util.spec_from_file_location("green_variants_dom_helpers", ROOT / "scripts/verify-corn-edge-shadows-copy.py")
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)
r, require = h.r, h.require
identity, remap_refs, scalar = h.identity, h.remap_refs, h.scalar
source_sha = h.source_sha
OUT = ROOT / ".artifacts/playtests/2026-10-23-B-green-variants"
ARCHIVE = OUT / "before-green-variants.zip"
ARCHIVE_ENTRY = "B-before-green-variants.rbxl"
ARCHIVE_SHA256 = "d61ef19552dadfdb402b87c9482d62b7693824f51ff7f5b35703d3a2b8d279a2"
BASELINE_SHA256 = "db9398781ec6d68da97bfadb1514e5a589cdf5a293424538e19bc29869f7a371"
BASELINE_BYTES = 1585269
BASELINE_INSTANCES = 6048
BASELINE_SOURCES = 163
A_SHA256 = "c1f054029ca729f314889ce7874c17c6e5f772cb20541a9c0ceedd796f3446b7"
C_SHA256 = "24a2d0ff9711d0805d3bcc738a156939574384d859ee3ec8493cc24621712010"
A_SCENE = ROOT / "place/Children_of_corn.rbxl"
C_SCENE = ROOT / "place/Children_of_corn_TestScene.rbxl"
OWNER = "corn_B_green_variants_v1"
CODE_ROOTS = ("ReplicatedStorage/GameShared", "ServerScriptService/GameServer",
              "StarterPlayer/StarterPlayerScripts/GameClient")
WORLD_ROOT = "Workspace/CornMap"
EDITOR_ROOTS = (WORLD_ROOT + "/EditorPreview", WORLD_ROOT + "/EditorFieldOverview")
ALLOWED_CORN_PROPERTIES = {"CFrame", "size", "Color3uint8", "TextureContent", "Transparency"}
ALLOWED_SOURCE_CHANGES = {
    "ReplicatedStorage/GameShared/Game/CornAppearance",
    "ReplicatedStorage/GameShared/Game/CornLayout",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornWindController",
}
DATA_ROOT = "ReplicatedStorage/GameShared/Game/CornGreenGeometryData"
ALLOWED_NEW_SOURCES = {"ReplicatedStorage/GameShared/Game/CornGreenGeometry"} | {
    DATA_ROOT + "/" + key for key in ("Var01", "Var02", "Var03")
}
ALLOWED_NEW_NODES = ALLOWED_NEW_SOURCES | {DATA_ROOT}
PROTECTED = {"Source", "UniqueId", "Name", "ScriptGuid", "HistoryId", "Capabilities",
             "DefinesCapabilities", "SerializedOverrides", "SourceAssetId", "Parent", "ClassName"}
GENERATED = {"UniqueId", "HistoryId", "ScriptGuid"}
GUID = re.compile(r"\{[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\}")


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def valid_sha(value):
    return isinstance(value, str) and re.fullmatch("[0-9a-f]{64}", value) is not None


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "Duplicate JSON key: " + key)
        result[key] = value
    return result


def safe_path(path):
    return (isinstance(path, str) and bool(path) and not path.startswith("/")
            and not path.endswith("/") and not any(c in path for c in ("\\", "\x00", "//"))
            and all(part not in {".", ".."} for part in path.split("/")))


def under(path, root):
    return path == root or path.startswith(root + "/")


def dom_value(value, depth=0):
    require(depth < 64 and isinstance(value, list) and len(value) == 3,
            "Malformed or overdeep DOM triple")
    kind, text, children = value
    require(isinstance(kind, str) and bool(kind) and isinstance(text, str)
            and isinstance(children, list), "Malformed DOM triple fields")
    require(not text.startswith("UNRESOLVED_SHARED_STRING:"), "Unresolved shared string")
    for child in children:
        require(isinstance(child, list) and len(child) == 2 and isinstance(child[0], str),
                "Malformed DOM child")
        dom_value(child[1], depth + 1)
    return value


def same(actual, expected):
    """No numerical tolerance: the plan freezes engine-serialized values."""
    return actual == expected or r.normalized(actual) == r.normalized(expected)


def expected_same(actual, expected):
    """Exact float32 semantics for explicitly frozen native property values.

    The XML writer chooses its own shortest decimal representation. The known
    serializer's compact axis-rotation rule is shared with earlier strict
    save audits; it permits only the engine's documented-in-fixtures tiny
    quarter-turn residue, never a distance/angle tolerance.
    """
    if same(actual, expected):
        return True
    if not (isinstance(actual, list) and isinstance(expected, list)
            and len(actual) == len(expected) == 3 and actual[0] == expected[0]):
        return False
    if expected[0] in {"CoordinateFrame", "Vector3", "float"}:
        return h.equivalent(actual, expected)
    return False


def attributes_same(actual, expected):
    """Exact logical attributes; engine may reorder keys/compact rotations."""
    left, right = h.decode_attributes(actual), h.decode_attributes(expected)
    return set(left) == set(right) and all(h.attribute_matches(left[key], row["value"]) for key, row in right.items())


def tags_same(actual, expected):
    def decode(value):
        require(value[0] == "BinaryString" and not value[2], "Malformed tag encoding")
        tags = bytes.fromhex(value[1]).decode().split("\x00") if value[1] else []
        require(len(tags) == len(set(tags)) and all(tags), "Empty/duplicate serialized tags")
        return set(tags)
    return decode(actual) == decode(expected)


def invariant_files():
    require(sha(A_SCENE) == A_SHA256, "A changed; preserve and independently review the author Save")
    require(sha(C_SCENE) == C_SHA256, "C changed; preserve and independently review the author Save")
    require(sha(ARCHIVE) == ARCHIVE_SHA256, "Immutable before-green-beds ZIP changed")


@contextmanager
def baseline_file():
    invariant_files()
    with zipfile.ZipFile(ARCHIVE) as archive:
        require(archive.namelist() == [ARCHIVE_ENTRY], "Unexpected immutable ZIP entries")
        data = archive.read(ARCHIVE_ENTRY)
    require(len(data) == BASELINE_BYTES and hashlib.sha256(data).hexdigest() == BASELINE_SHA256,
            "Archived B is not the accepted db939878 baseline")
    with tempfile.TemporaryDirectory(prefix="corn-green-variants-read-only-") as directory:
        path = Path(directory) / ARCHIVE_ENTRY
        require(not path.resolve().is_relative_to(ROOT.resolve()), "Temporary baseline must be external")
        path.write_bytes(data)
        yield path
        require(sha(path) == BASELINE_SHA256, "Temporary baseline changed during audit")
    invariant_files()


def read_baseline():
    with baseline_file() as path:
        before, warning = r.p.known_dom(path)
        unknown = r.p.unknown_properties(path)
    return before, warning, unknown


def read_pinned(path, expected_hash):
    require(valid_sha(expected_hash), "An explicit independently reviewed SHA256 pin is required")
    data = Path(path).read_bytes()
    require(hashlib.sha256(data).hexdigest() == expected_hash, "Frozen input differs from reviewed pin: " + str(path))
    value = json.loads(data, object_pairs_hook=unique_object)
    require(isinstance(value, dict), "Frozen input must be a JSON object")
    return value


def source_plan(before, payload):
    require(isinstance(payload, dict) and payload.get("owner") == OWNER, "Wrong green-variants payload owner")
    retained = {p: n for p, n in before.items() if "Source" in n["properties"]}
    require(len(before) == BASELINE_INSTANCES and len(retained) == BASELINE_SOURCES,
            "Accepted B baseline topology differs")
    guards, changes, additions = payload.get("sources"), payload.get("sourceChanges"), payload.get("newSources")
    require(isinstance(guards, dict) and set(guards) == set(retained), "All 163 retained Sources must be guarded")
    require(isinstance(changes, dict) and isinstance(additions, dict), "Exact Source replacement/addition maps required")
    require(set(changes) == ALLOWED_SOURCE_CHANGES and set(additions) == ALLOWED_NEW_SOURCES,
            "Only three exact existing Sources and four exact new modules are allowed")
    replacements, new_sources = {}, {}
    for path, original in retained.items():
        require(guards[path] == {"class": original["class"], "sha256": source_sha(original["properties"]["Source"][1])},
                "Immutable Source guard differs: " + path)
    for path, row in changes.items():
        require(path in retained and any(under(path, root) for root in CODE_ROOTS), "Invalid retained Source target")
        require(isinstance(row, dict) and set(row) == {"before_sha256", "after_sha256", "source"},
                "Malformed Source replacement")
        require(row["before_sha256"] == guards[path]["sha256"]
                and valid_sha(row["after_sha256"]) and row["after_sha256"] != row["before_sha256"],
                "Wrong/no-op replacement hash pair")
        text = row["source"]
        require(isinstance(text, str) and text.strip() and "\x00" not in text and "\r" not in text
                and len(text.encode()) <= 2_000_000 and source_sha(text) == row["after_sha256"],
                "Replacement Source bytes differ")
        replacements[path] = scalar("string", text)
    for path, row in additions.items():
        require(safe_path(path) and path not in before and any(under(path, root) for root in CODE_ROOTS),
                "Invalid new Source target")
        require(isinstance(row, dict) and set(row) == {"class", "sha256", "source"}
                and row["class"] == "ModuleScript" and valid_sha(row["sha256"]),
                "Malformed new Source")
        text = row["source"]
        require(isinstance(text, str) and text.strip() and "\x00" not in text and "\r" not in text
                and len(text.encode()) <= 2_000_000 and source_sha(text) == row["sha256"],
                "New Source bytes differ")
        new_sources[path] = row
    require(replacements and new_sources, "Green-variants migration needs explicit changed and new Sources")
    return retained, replacements, new_sources


def prepare_plan(before, payload, world, payload_sha256):
    retained, replacements, sources = source_plan(before, payload)
    require(isinstance(world, dict) and set(world) == {"version", "owner", "baseline_sha256", "payload_sha256", "retained_changes", "new_nodes"},
            "Unrecognized frozen world-plan schema")
    require(type(world["version"]) is int and world["version"] == 1 and world["owner"] == OWNER
            and world["baseline_sha256"] == BASELINE_SHA256 and valid_sha(payload_sha256)
            and world["payload_sha256"] == payload_sha256, "World-plan provenance differs")
    rows, nodes = world["retained_changes"], world["new_nodes"]
    require(isinstance(rows, list) and 0 < len(rows) <= 100_000 and isinstance(nodes, dict)
            and 0 < len(nodes) <= 100_000, "Unbounded/empty world manifest")
    require(set(nodes) == ALLOWED_NEW_NODES, "Exactly four code modules and their data folder may be added; no new world nodes")
    changes = {}
    for row in rows:
        require(isinstance(row, dict) and set(row) == {"path", "uid", "property", "before", "after"}, "Malformed retained property change")
        path, prop = row["path"], row["property"]
        require(path in before and any(under(path, root) for root in EDITOR_ROOTS)
                and before[path]["class"] == "MeshPart" and prop in ALLOWED_CORN_PROPERTIES,
                "Only five editor-corn properties may change; beds and other world remain exact")
        require(row["uid"] == identity(before[path]), "Retained target identity differs")
        require(prop in before[path]["properties"], "Retained property schema must not expand")
        dom_value(row["before"]); dom_value(row["after"])
        require(same(before[path]["properties"][prop], row["before"]), "Retained before-property differs")
        require(not same(row["before"], row["after"]), "No-op retained change")
        key = (path, prop)
        require(key not in changes, "Duplicate retained property change")
        changes[key] = row["after"]
    for path, row in nodes.items():
        require(safe_path(path) and path not in before and (under(path, WORLD_ROOT) or any(under(path, root) for root in CODE_ROOTS)),
                "New object outside authorized corn/code roots")
        require(isinstance(row, dict) and set(row) == {"class", "properties"} and isinstance(row["class"], str)
                and isinstance(row["properties"], dict), "Malformed complete new node")
        require(row["class"] == ("Folder" if path == DATA_ROOT else "ModuleScript"), "New code node class differs")
        props = row["properties"]
        require(not (GENERATED & set(props)) and props.get("Name") == scalar("string", path.rsplit("/", 1)[-1]),
                "New node must have exact real Name and engine-generated metadata")
        require(path.rpartition("/")[0] in before or path.rpartition("/")[0] in nodes, "Missing declared new-node parent")
        for prop, value in props.items():
            require(isinstance(prop, str) and bool(prop), "Malformed new property name")
            dom_value(value)
        attrs = h.decode_attributes(props["AttributesSerialize"])
        require(set(attrs) == {"BGreenVariantsOwner", "corn_project_id"}
                and h.attribute_matches(attrs["BGreenVariantsOwner"], OWNER)
                and h.attribute_matches(attrs["corn_project_id"], "children_of_corn"), "New module/folder ownership attributes differ")
        require(props["Tags"] == scalar("BinaryString", ""), "New code nodes must have no unexpected tags")
        if "Source" in props:
            require(path in sources and row["class"] == sources[path]["class"]
                    and props["Source"] == scalar("string", sources[path]["source"]), "New node Source differs from frozen payload")
        elif row["class"] in {"ModuleScript", "LocalScript", "Script"}:
            raise ValueError("New Source container lacks exact Source")
    require({path for path, row in nodes.items() if "Source" in row["properties"]} == set(sources),
            "New Source graph and new world-plan nodes differ")
    return retained, replacements, sources, changes, nodes


def canonicalize(before, after, additions):
    old_ids = {identity(node): path for path, node in before.items()}
    require(len(old_ids) == len(before), "Duplicate immutable identity")
    paths, seen, targets = {}, set(), set()
    for path, node in after.items():
        uid = identity(node)
        require(uid not in seen, "Duplicate candidate identity")
        seen.add(uid)
        target = old_ids.get(uid)
        if target is None:
            selection = (path in r.SELECTION_PATHS and path in before and node["class"] == "Instance"
                         and node["properties"].get("Name") == scalar("string", "FilteredSelection"))
            require(path in additions or selection, "Unexpected/replaced identity: " + path)
            target = path
        require(target not in targets, "Duplicate canonical target")
        paths[path], _ = target, targets.add(target)
    require(targets == set(before) | set(additions), "Missing/extra retained or new objects")
    canonical, reindexed = {}, sum(path != target for path, target in paths.items())
    for path, target in paths.items():
        actual = after[path]
        expected = before[target] if target in before else additions[target]
        require(actual["class"] == expected["class"] and actual["properties"].get("Name") == expected["properties"]["Name"],
                "Class/real Name changed: " + target)
        parent, actual_parent = target.rpartition("/")[0], path.rpartition("/")[0]
        require((not parent and not actual_parent) or paths.get(actual_parent) == parent, "Parent identity changed: " + target)
        canonical[target] = actual if not reindexed else actual | {"properties": {p: remap_refs(value, paths) for p, value in actual["properties"].items()}}
    return canonical, reindexed


def validate_dom(before, after, payload, world, payload_sha256):
    retained, sources, new_sources, changes, additions = prepare_plan(before, payload, world, payload_sha256)
    after, reindexed = canonicalize(before, after, additions)
    require({p for p, n in after.items() if "Source" in n["properties"]} == set(retained) | set(new_sources), "Candidate Source set differs")
    recorded, seen_changes, seen_sources = [], set(), set()
    for path, original in before.items():
        actual = after[path]
        require(set(actual["properties"]) == set(original["properties"]), "Retained property schema differs: " + path)
        for prop, value in original["properties"].items():
            other, key = actual["properties"][prop], (path, prop)
            if prop == "Source" and path in sources:
                require(other[0] == "string" and not other[2] and other[1].replace("\r\n", "\n") == sources[path][1], "Replacement Source differs: " + path)
                seen_sources.add(path)
                reason = "exact_frozen_Source"
            elif key in changes:
                require(expected_same(other, changes[key]), "Frozen retained property differs: " + path + "/" + prop)
                seen_changes.add(key)
                reason = "exact_frozen_world_property"
            elif same(value, other):
                continue
            elif path == "Workspace/Camera" and prop in {"CFrame", "Focus"}:
                h.m.shadow.h.old.helpers.validate_camera_frame(other)
                reason = "finite_editor_camera"
            elif path in r.SELECTION_PATHS and original["class"] == "Instance" and prop == "UniqueId":
                reason = "existing_filtered_selection_identity"
            else:
                raise ValueError("Undeclared retained Source/world/art/Lighting/physics/mesh change: " + path + "/" + prop)
            recorded.append({"path": path, "property": prop, "reason": reason})
    require(seen_changes == set(changes) and seen_sources == set(sources), "Frozen changes were not fully applied")
    old_guids = {node["properties"]["ScriptGuid"][1].lower() for node in before.values() if "ScriptGuid" in node["properties"]}
    new_guids = set()
    for path, expected in additions.items():
        actual = after[path]
        generated = {"UniqueId", "HistoryId"} | ({"ScriptGuid"} if expected["class"] in {"ModuleScript", "LocalScript", "Script"} else set())
        require(set(actual["properties"]) == set(expected["properties"]) | generated, "New node complete property schema differs: " + path)
        history = actual["properties"]["HistoryId"]
        require(history[0] == "UniqueId" and history[2] == [] and re.fullmatch(r"[0-9a-fA-F]{32}", history[1]), "Malformed generated HistoryId")
        if "ScriptGuid" in generated:
            guid = actual["properties"]["ScriptGuid"]
            require(guid[0] == "string" and guid[2] == [] and GUID.fullmatch(guid[1]) is not None
                    and int(guid[1][1:-1].replace("-", ""), 16) != 0, "Malformed/zero generated ScriptGuid")
            value = guid[1].lower()
            require(value not in old_guids and value not in new_guids, "Generated ScriptGuid must be fresh and globally unique")
            new_guids.add(value)
        for prop, value in expected["properties"].items():
            other = actual["properties"][prop]
            equal = attributes_same(other, value) if prop == "AttributesSerialize" else tags_same(other, value) if prop == "Tags" else expected_same(other, value)
            require(equal, "New node frozen property differs: " + path + "/" + prop)
    return {"passed": True, "complete": True, "variant": "B", "original_instances": len(before),
            "candidate_instances": len(after), "new_instances": len(additions), "removed_instances": 0,
            "total_sources": len(retained) + len(new_sources), "unchanged_sources": len(retained) - len(sources),
            "source_changes": sorted(sources), "new_sources": sorted(new_sources),
            "new_engine_generated_metadata": ["UniqueId", "HistoryId", "fresh nonzero globally unique ScriptGuid"],
            "declared_retained_property_changes": len(changes), "added_world_and_code_nodes": len(additions),
            "new_world_nodes": 0, "unchanged_saved_bed_meshes": 1406,
            "reindexed_exporter_paths": reindexed, "retained_identities_classes_names_parents_exact": True,
            "all_other_world_art_lighting_physics_mesh_metadata_exact": True, "changes": recorded}


def check(candidate, payload_path, world_plan_path, payload_sha256, world_plan_sha256):
    candidate, payload_path, world_plan_path = map(lambda p: Path(p).resolve(), (candidate, payload_path, world_plan_path))
    require(candidate.is_file() and candidate.suffix.lower() == ".rbxl", "Engine-saved binary RBXL required")
    candidate_hash = sha(candidate)
    payload = read_pinned(payload_path, payload_sha256)
    world = read_pinned(world_plan_path, world_plan_sha256)
    with baseline_file() as original:
        before, before_warning = r.p.known_dom(original)
        after, after_warning = r.p.known_dom(candidate)
        ub, ua = r.p.unknown_properties(original), r.p.unknown_properties(candidate)
        r.validate_unknown(ub, ua)
        report = validate_dom(before, after, payload, world, payload_sha256)
    require(sha(candidate) == candidate_hash and sha(payload_path) == payload_sha256 and sha(world_plan_path) == world_plan_sha256,
            "Candidate or frozen review inputs changed during audit")
    return report | {"baseline_sha256": BASELINE_SHA256, "candidate_sha256": candidate_hash,
                     "candidate_bytes": candidate.stat().st_size, "payload_sha256": payload_sha256,
                     "world_plan_sha256": world_plan_sha256, "untouched_A_sha256": A_SHA256,
                     "untouched_C_sha256": C_SHA256, "raw_terrain_exact": True,
                     "raw_unknown_properties": ua, "warnings": {"baseline": before_warning, "candidate": after_warning},
                     "scope": "Only independently frozen exact Source/property changes and complete new-node DOM. All other retained identities, parents, art, Lighting, physics, mesh metadata and raw Terrain exact. Existing finite Camera/FilteredSelection editor metadata only. No scene rewriting or promotion."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--payload", type=Path, default=OUT / "payload.json")
    parser.add_argument("--world-plan", type=Path, default=OUT / "world-plan.json")
    parser.add_argument("--payload-sha256", required=True)
    parser.add_argument("--world-plan-sha256", required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    output = args.report.resolve()
    require(output.is_relative_to(OUT.resolve()) and output.suffix.lower() == ".json", "Report must remain in green-beds evidence")
    require(output not in {args.candidate.resolve(), args.payload.resolve(), args.world_plan.resolve(), ARCHIVE.resolve(),
                           (OUT / "baseline.json").resolve(), (OUT / "native-inputs.json").resolve()}, "Report would overwrite an audit input")
    result = check(args.candidate, args.payload, args.world_plan, args.payload_sha256, args.world_plan_sha256)
    output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: value for key, value in result.items() if key not in {"changes", "warnings"}}))
