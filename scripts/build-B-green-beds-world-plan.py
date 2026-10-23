"""Build the reviewed B world-plan from immutable B/C DOM and native intent.

This writes JSON only, never a scene. C supplies complete known default/private
DOM for the EXACT same three baked soil templates. Every existing B corn UID
resolves into the immutable B baseline. Only CFrame/Size/Color/TextureID/
Transparency may change. Every other B field stays pinned by the save audit.

Native proposal JSON schema:
 {version:1,owner:OWNER,baseline_sha256:BASELINE_SHA256,payload_sha256:<pin>,
  old:[{path,oldFrame:[12],beforeSize:[3],oldTexture:<uri>,nativeDebugId?:<text>,
        cframe:[12],size:[3],color:[3],texture:<uri>,transparency:<number>}],
  new_nodes:{path:{class,prototype:"Center"|"End"|"Skirt"|"Folder"|"ModuleScript",
    properties:{CFrame:{kind:"CFrame",value:[12]},Size:{kind:"Vector3",value:[3]},
      InitialSize:{kind:"Vector3",value:[3]},PivotOffset:{kind:"CFrame",value:[12]},
      ...explicit public overrides...},attributes:{...all attrs},tags:[...all tags]}}}

Property overrides accept booleans/strings/numbers and typed CFrame/Vector3/
Color3/Enum({kind:"Enum",value:<numeric enum token>}). Public aliases are
Size, Color, TextureID and MeshSize. Opaque MeshContent is fixed to the C
prototype's engine-saved None; pass no session token. Module Source comes only
from the hash-pinned payload. New engine-generated UniqueId/HistoryId/ScriptGuid
cannot be read through normal Studio APIs; only those metadata fields are
omitted. The validator requires valid fresh UniqueId/ScriptGuid and HistoryId
syntax, while every retained metadata field stays exact.
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
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("green_beds_frozen_dom_audit", ROOT / "scripts/verify-B-green-beds-copy.py")
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)
m = v.h.m
require = v.require
PROTOTYPE_NAMES = {
    "Center": "SM_Env_Dirt_Rows_Center_01",
    "End": "SM_Env_Dirt_Rows_End_Top_01",
    "Skirt": "SM_Env_Dirt_Skirt_01",
}
OLD_FIELDS = {"path", "oldFrame", "beforeSize", "oldTexture", "cframe", "size", "color", "texture", "transparency"}
ALIASES = {"Size": "size", "Color": "Color3uint8", "TextureID": "TextureContent", "MeshSize": "InitialSize", "MaterialVariant": "MaterialVariantSerialized"}
FORBIDDEN_OVERRIDES = {"Name", "UniqueId", "HistoryId", "ScriptGuid", "Source", "AttributesSerialize", "Tags", "Parent", "ClassName",
                       "AeroMeshData", "PhysicalConfigData", "PhysicsData", "MeshContent", "MeshId", "MeshData"}
GUID = re.compile(r"\{[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\}")


def vector(kind, values):
    return m.vector_dom("CoordinateFrame" if kind == "CFrame" else kind, values)


def override(value, template, prop):
    kind = value.get("kind") if isinstance(value, dict) else None
    if kind in {"CFrame", "Vector3"}:
        require(set(value) == {"kind", "value"}, "Malformed native typed value")
        expected = "CoordinateFrame" if kind == "CFrame" else "Vector3"
        require(template[0] == expected, "Native property type differs: " + prop)
        return vector(kind, value["value"])
    if prop == "TextureID":
        require(template[0] == "Content" and isinstance(value, str)
                and re.fullmatch(r"rbxassetid://[1-9][0-9]*", value), "Invalid texture URI")
        return ["Content", "", [["uri", ["uri", value, []]]]]
    if prop == "Color":
        require(kind == "Color3", "Typed Color3 required")
        return m.native_to_dom(value, template, prop)
    if template[0] == "UniqueId":
        require(isinstance(value, str) and re.fullmatch(r"[0-9a-fA-F]{32}", value), "Native HistoryId must be 32 hex digits")
        return v.scalar("UniqueId", value.lower())
    if template[0] == "token":
        require(kind == "Enum" and set(value) == {"kind", "value"}
                and type(value["value"]) is int and 0 <= value["value"] < 2 ** 32, "Native enum token required")
        return v.scalar("token", value["value"])
    if template[0] == "bool":
        require(type(value) is bool, "Native boolean required")
        return v.scalar("bool", str(value).lower())
    if template[0] == "float":
        return v.scalar("float", repr(m.f32(value)))
    if template[0] == "double":
        require(type(value) in {float, int} and math.isfinite(value), "Native finite double required")
        return v.scalar("double", repr(float(value)))
    if template[0] in {"int", "int64"}:
        require(type(value) is int, "Native integer required")
        return v.scalar(template[0], value)
    if template[0] == "string":
        require(isinstance(value, str), "Native string required")
        if prop == "ScriptGuid":
            require(GUID.fullmatch(value) is not None, "Actual native ScriptGuid required")
        return v.scalar("string", value)
    raise ValueError("Unsupported native override: " + prop + "/" + template[0])


def prototype_nodes(c):
    result = {}
    for key, name in PROTOTYPE_NAMES.items():
        rows = [node for path, node in c.items() if path.startswith("Workspace/CornCTestWorld/Decor/")
                and node["class"] == "MeshPart" and node["properties"].get("Name") == v.scalar("string", name)]
        require(rows, "Exact C soil prototype missing: " + key)
        node = copy.deepcopy(rows[0])
        content = node["properties"]["MeshContent"]
        require(content[0] == "Content" and len(content[2]) == 1 and content[2][0][0] == "null", "C prototype must save session geometry as None")
        result[key] = node
    result["Folder"] = copy.deepcopy(c["ReplicatedStorage/CornCTestSystem/Data"])
    result["ModuleScript"] = copy.deepcopy(c["ReplicatedStorage/CornCTestSystem/Data/Center"])
    require(result["Folder"]["class"] == "Folder" and result["ModuleScript"]["class"] == "ModuleScript", "C code prototypes differ")
    return result


def build(before, c, payload, proposal, payload_sha256):
    require(isinstance(proposal, dict) and set(proposal) == {"version", "owner", "baseline_sha256", "payload_sha256", "old", "new_nodes"},
            "Malformed native proposal")
    require(type(proposal["version"]) is int and proposal["version"] == 1 and proposal["owner"] == v.OWNER
            and proposal["baseline_sha256"] == v.BASELINE_SHA256 and proposal["payload_sha256"] == payload_sha256,
            "Native proposal provenance differs")
    _, _, source_additions = v.source_plan(before, payload)
    prototypes = prototype_nodes(c)
    by_id = {v.identity(node): path for path, node in before.items()}
    require(len(by_id) == len(before), "Duplicate baseline UID")
    by_public_pose = {}
    for path, node in before.items():
        if node["class"] != "MeshPart" or not (v.under(path, "Workspace/CornMap/EditorFieldOverview") or v.under(path, "Workspace/CornMap/EditorPreview")):
            continue
        public = path.rpartition("/")[0] + "/" + node["properties"]["Name"][1]
        props = node["properties"]
        position = tuple(m.f32(float(pair[1][1])) for pair in props["CFrame"][2][:3])
        size = tuple(m.f32(float(pair[1][1])) for pair in props["size"][2])
        texture = props["TextureContent"][2][0][1][1]
        by_public_pose.setdefault((public, position, size, texture), []).append(path)
    rows = proposal["old"]
    require(isinstance(rows, list) and len(rows) == 3480, "Exactly 3,480 old editor corn rows required")
    changes, seen = [], set()
    for row in rows:
        require(isinstance(row, dict) and set(row) in (OLD_FIELDS, OLD_FIELDS | {"nativeDebugId"}), "Closed existing-corn row required")
        require(v.safe_path(row["path"]), "Malformed old public path")
        old_frame, old_size = vector("CFrame", row["oldFrame"]), vector("Vector3", row["beforeSize"])
        key = (row["path"], tuple(m.f32(value) for value in row["oldFrame"][:3]),
               tuple(m.f32(value) for value in row["beforeSize"]), row["oldTexture"])
        candidates = [path for path in by_public_pose.get(key, [])
                      if v.expected_same(before[path]["properties"]["CFrame"], old_frame)
                      and v.expected_same(before[path]["properties"]["size"], old_size)
                      and before[path]["properties"]["TextureContent"][2] == [["uri", ["uri", row["oldTexture"], []]]]]
        require(len(candidates) == 1, "Old public path/frame/size/texture did not resolve uniquely: " + row["path"])
        path = candidates[0]
        uid = v.identity(before[path])
        require(uid not in seen, "Duplicate existing-corn target"); seen.add(uid)
        original = before[path]
        require(original["class"] == "MeshPart" and (v.under(path, "Workspace/CornMap/EditorFieldOverview")
                or v.under(path, "Workspace/CornMap/EditorPreview")), "Only exact old editor corn may change")
        old_mesh = original["properties"]["MeshContent"]
        require(old_mesh[0] == "Content" and old_mesh[2] == [["uri", ["uri", "rbxassetid://104111861186519", []]]], "Old corn original URI differs")
        require(row["texture"] == "rbxassetid://137803536172445", "Only requested green corn atlas permitted")
        require(type(row["transparency"]) in {int, float} and row["transparency"] in {0, 1}, "Only exact visible/hidden editor corn state permitted")
        require(len(row["color"]) == 3 and row["color"] == [1, 1, 1], "Green corn must use neutral white tint")
        proposed = {"CFrame": {"kind": "CFrame", "value": row["cframe"]},
                    "Size": {"kind": "Vector3", "value": row["size"]},
                    "Color": {"kind": "Color3", "value": row["color"]},
                    "TextureID": row["texture"], "Transparency": row["transparency"]}
        for public, value in proposed.items():
            prop = ALIASES.get(public, public)
            old = original["properties"][prop]
            new = override(value, old, public)
            if not v.expected_same(old, new):
                changes.append({"path": path, "uid": uid, "property": prop, "before": copy.deepcopy(old), "after": new})
    expected_old = {v.identity(node) for path, node in before.items() if node["class"] == "MeshPart"
                    and (v.under(path, "Workspace/CornMap/EditorFieldOverview") or v.under(path, "Workspace/CornMap/EditorPreview"))}
    require(seen == expected_old, "Old corn manifest must cover all and only retained previews")
    new_rows = proposal["new_nodes"]
    require(isinstance(new_rows, dict) and new_rows, "Complete new-node proposal required")
    nodes, bed_count = {}, 0
    for path, row in new_rows.items():
        require(v.safe_path(path) and path not in before and isinstance(row, dict)
                and set(row) == {"class", "prototype", "properties", "attributes", "tags"}, "Malformed new native node")
        key = row["prototype"]
        require(key in prototypes, "Unknown exact C prototype")
        prototype = prototypes[key]
        require(row["class"] == prototype["class"], "New node class differs from C prototype")
        item = copy.deepcopy(prototype)
        props = item["properties"]
        for generated in v.GENERATED:
            props.pop(generated, None)
        props["Name"] = v.scalar("string", path.rsplit("/", 1)[-1])
        overrides = row["properties"]
        # HttpService encodes an empty Luau table as [] even for a map. Only
        # these two classes intentionally have no public property overrides.
        if overrides == [] and row["class"] in {"ModuleScript", "Folder"}:
            overrides = {}
        require(isinstance(overrides, dict), "Exact public new-node overrides required")
        if row["class"] == "ModuleScript":
            require(path in source_additions, "Exact pinned new Source required")
            props["Source"] = v.scalar("string", source_additions[path]["source"])
        if row["class"] == "MeshPart":
            bed_count += 1
            require(v.under(path, "Workspace/CornMap/GreenBedEditor")
                    and set(overrides) >= {"CFrame", "Size", "InitialSize", "PivotOffset", "TextureID", "Color", "Transparency"},
                    "Complete public new-bed geometry and exact owned root required")
            require(overrides["TextureID"] == "rbxassetid://95855894892409", "Exact requested soil atlas required")
        mapped = set()
        for public, value in overrides.items():
            prop = ALIASES.get(public, public)
            require(public not in FORBIDDEN_OVERRIDES and prop in props and prop not in mapped,
                    "Unknown/duplicate/private new-node override: " + public)
            mapped.add(prop)
            props[prop] = override(value, props[prop], public)
        require(isinstance(row["attributes"], dict), "Complete native attributes required")
        props["AttributesSerialize"] = m.encode_attributes(row["attributes"])
        tags = row["tags"]
        require(isinstance(tags, list) and all(isinstance(tag, str) and tag and "\x00" not in tag for tag in tags)
                and len(set(tags)) == len(tags), "Complete unique native tags required")
        props["Tags"] = v.scalar("BinaryString", "\x00".join(sorted(tags)).encode().hex())
        nodes[path] = item
    require(bed_count == 1406, "Exactly 1,406 reviewed bed meshes required")
    world = {"version": 1, "owner": v.OWNER, "baseline_sha256": v.BASELINE_SHA256,
             "payload_sha256": payload_sha256, "retained_changes": changes, "new_nodes": nodes}
    v.prepare_plan(before, payload, world, payload_sha256)
    return world


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--proposal", type=Path, default=v.OUT / "native-proposal.json")
    parser.add_argument("--payload", type=Path, default=v.OUT / "payload.json")
    parser.add_argument("--proposal-sha256", required=True)
    parser.add_argument("--payload-sha256", required=True)
    parser.add_argument("--output", type=Path, default=v.OUT / "world-plan.json")
    args = parser.parse_args()
    output = args.output.resolve()
    require(output.is_relative_to(v.OUT.resolve()) and output.suffix == ".json"
            and not output.exists(), "World-plan output must be a fresh JSON in green-beds evidence")
    protected = {args.proposal.resolve(), args.payload.resolve(), v.ARCHIVE.resolve(), v.A_SCENE.resolve(), v.C_SCENE.resolve()}
    require(output not in protected, "Output must not replace a review input")
    proposal = v.read_pinned(args.proposal, args.proposal_sha256)
    payload = v.read_pinned(args.payload, args.payload_sha256)
    before, _, _ = v.read_baseline()
    c, _ = v.r.p.known_dom(v.C_SCENE)
    world = build(before, c, payload, proposal, args.payload_sha256)
    require(v.sha(args.proposal) == args.proposal_sha256 and v.sha(args.payload) == args.payload_sha256,
            "Native proposal or payload changed during build")
    v.invariant_files()
    data = (json.dumps(world, ensure_ascii=False, separators=(",", ":")) + "\n").encode()
    with output.open("xb") as file:
        file.write(data)
    print(json.dumps({"written": str(output), "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data),
                      "retained_property_changes": len(world["retained_changes"]), "new_nodes": len(world["new_nodes"]),
                      "source_graph": "all157guarded+explicitnewSources", "requires_independent_review_before_freeze": True,
                      "scope": "Immutable B/C prototypes plus pinned native proposal; no final-save-derived allowance; no scene writes"}))


if __name__ == "__main__":
    main()
