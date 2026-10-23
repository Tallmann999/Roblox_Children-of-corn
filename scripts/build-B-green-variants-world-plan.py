"""Freeze 23Oct native editor-corn intent and four new code modules as JSON.

Read-only inputs: immutable accepted B db939878, pinned payload and proposal.
No saved candidate is used to authorize changes. No scene is rewritten.
Native proposal uses the existing public-only schema:
 {version:1,owner:OWNER,baseline_sha256:BASELINE_SHA256,payload_sha256:<pin>,
  old:[{path,oldFrame:[12],beforeSize:[3],oldTexture,nativeDebugId?:string,
        cframe:[12],size:[3],color:[3],texture,transparency}],
  new_nodes:{path:{class,prototype:"ModuleScript"|"Folder",properties:{} or [],
                    attributes:{BGreenVariantsOwner:OWNER,corn_project_id:...},tags:[]}}}
The old 3,480 ordinary-URI editor plants retain all mesh/physics/attribute
metadata. All 1,406 saved beds stay exact. Only their five declared corn
properties may change. New-node complete defaults come from accepted B
ModuleScript/Folder prototypes, with narrow generated metadata validation.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("green_variants_frozen_audit", ROOT / "scripts/verify-B-green-variants-copy.py")
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)
m, require = v.h.m, v.require
OLD_FIELDS = {"path", "oldFrame", "beforeSize", "oldTexture", "cframe", "size", "color", "texture", "transparency"}
ALIASES = {"Size": "size", "Color": "Color3uint8", "TextureID": "TextureContent"}
GREEN = "rbxassetid://137803536172445"
MESH = "rbxassetid://104111861186519"


def vector(kind, values):
    return m.vector_dom("CoordinateFrame" if kind == "CFrame" else kind, values)


def override(value, template, public):
    if public == "TextureID":
        require(template[0] == "Content" and value == GREEN, "Only exact green corn atlas allowed")
        return ["Content", "", [["uri", ["uri", value, []]]]]
    return m.native_to_dom(value, template, public)


def build(before, payload, proposal, payload_sha256):
    require(isinstance(proposal, dict) and set(proposal) == {"version", "owner", "baseline_sha256", "payload_sha256", "old", "new_nodes"}, "Closed native proposal required")
    require(type(proposal["version"]) is int and proposal["version"] == 1 and proposal["owner"] == v.OWNER
            and proposal["baseline_sha256"] == v.BASELINE_SHA256 and proposal["payload_sha256"] == payload_sha256,
            "Native proposal provenance differs")
    _, _, sources = v.source_plan(before, payload)
    index, expected_ids = {}, set()
    for path, node in before.items():
        if node["class"] != "MeshPart" or not any(v.under(path, root) for root in v.EDITOR_ROOTS):
            continue
        props = node["properties"]
        public = path.rpartition("/")[0] + "/" + props["Name"][1]
        position = tuple(m.f32(float(pair[1][1])) for pair in props["CFrame"][2][:3])
        size = tuple(m.f32(float(pair[1][1])) for pair in props["size"][2])
        texture = props["TextureContent"][2][0][1][1]
        index.setdefault((public, position, size, texture), []).append(path)
        expected_ids.add(v.identity(node))
        require(props["MeshContent"][2] == [["uri", ["uri", MESH, []]]], "Accepted ordinary corn URI differs")
    require(len(expected_ids) == 3480, "All 3,480 accepted editor corn required")
    require(isinstance(proposal["old"], list) and len(proposal["old"]) == 3480, "Exactly 3,480 native old-corn rows required")
    seen, changes = set(), []
    for row in proposal["old"]:
        require(isinstance(row, dict) and set(row) in (OLD_FIELDS, OLD_FIELDS | {"nativeDebugId"}), "Closed native corn row required")
        require(v.safe_path(row["path"]), "Invalid native public path")
        old_frame, old_size = vector("CFrame", row["oldFrame"]), vector("Vector3", row["beforeSize"])
        key = (row["path"], tuple(m.f32(n) for n in row["oldFrame"][:3]),
               tuple(m.f32(n) for n in row["beforeSize"]), row["oldTexture"])
        candidates = [path for path in index.get(key, [])
                      if v.expected_same(before[path]["properties"]["CFrame"], old_frame)
                      and v.expected_same(before[path]["properties"]["size"], old_size)]
        require(len(candidates) == 1, "Old native public pose/size/texture must identify one accepted corn")
        path = candidates[0]; uid = v.identity(before[path])
        require(uid not in seen, "Duplicate old native corn target"); seen.add(uid)
        require(row["texture"] == GREEN and row["color"] == [1, 1, 1], "Green atlas and neutral white tint required")
        require(type(row["transparency"]) in {float, int} and row["transparency"] in {0, 1}, "Exact visible/hidden corn state required")
        require(isinstance(row["size"], list) and len(row["size"]) == 3 and all(type(n) in {int, float} and 0 < n < 20 for n in row["size"]), "Finite positive corn size required")
        proposed = {"CFrame": {"kind": "CFrame", "value": row["cframe"]}, "Size": {"kind": "Vector3", "value": row["size"]},
                    "Color": {"kind": "Color3", "value": row["color"]}, "TextureID": row["texture"], "Transparency": row["transparency"]}
        for public, value in proposed.items():
            prop = ALIASES.get(public, public)
            old = before[path]["properties"][prop]
            new = override(value, old, public)
            if not v.expected_same(old, new):
                changes.append({"path": path, "uid": uid, "property": prop, "before": copy.deepcopy(old), "after": new})
    require(seen == expected_ids, "Old corn identity coverage differs")
    rows = proposal["new_nodes"]
    require(isinstance(rows, dict) and set(rows) == v.ALLOWED_NEW_NODES, "Exactly four new modules and their data folder required")
    prototypes = {"ModuleScript": before["ReplicatedStorage/GameShared/Game/CornAppearance"],
                  "Folder": before["ReplicatedStorage/GameShared/Game/GreenBedGeometryData"]}
    nodes = {}
    for path, row in rows.items():
        require(isinstance(row, dict) and set(row) == {"class", "prototype", "properties", "attributes", "tags"}, "Closed new-code node required")
        wanted = "Folder" if path == v.DATA_ROOT else "ModuleScript"
        require(row["class"] == row["prototype"] == wanted, "New code node class/prototype differs")
        require(row["properties"] == {} or row["properties"] == [], "New code nodes permit no hidden/public default overrides")
        require(row["attributes"] == {"BGreenVariantsOwner": v.OWNER, "corn_project_id": "children_of_corn"}
                and row["tags"] == [], "Exact new-code owner/project and no tags required")
        node = copy.deepcopy(prototypes[wanted]); props = node["properties"]
        for generated in v.GENERATED: props.pop(generated, None)
        props["Name"] = v.scalar("string", path.rsplit("/", 1)[-1])
        props["AttributesSerialize"] = m.encode_attributes(row["attributes"])
        props["Tags"] = v.scalar("BinaryString", "")
        if wanted == "ModuleScript": props["Source"] = v.scalar("string", sources[path]["source"])
        nodes[path] = node
    world = {"version": 1, "owner": v.OWNER, "baseline_sha256": v.BASELINE_SHA256,
             "payload_sha256": payload_sha256, "retained_changes": changes, "new_nodes": nodes}
    v.prepare_plan(before, payload, world, payload_sha256)
    return world


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--proposal", type=Path, default=v.OUT / "native-proposal.json")
    parser.add_argument("--payload", type=Path, default=v.OUT / "payload.json")
    parser.add_argument("--proposal-sha256", required=True)
    parser.add_argument("--payload-sha256", required=True)
    parser.add_argument("--output", type=Path, default=v.OUT / "world-plan.json")
    args = parser.parse_args()
    output = args.output.resolve()
    require(output.is_relative_to(v.OUT.resolve()) and output.suffix == ".json" and not output.exists(), "Output must be fresh JSON in 23Oct evidence")
    require(output not in {args.proposal.resolve(), args.payload.resolve()}, "Output must not overwrite an input")
    proposal = v.read_pinned(args.proposal, args.proposal_sha256)
    payload = v.read_pinned(args.payload, args.payload_sha256)
    before, _, _ = v.read_baseline()
    world = build(before, payload, proposal, args.payload_sha256)
    require(v.sha(args.proposal) == args.proposal_sha256 and v.sha(args.payload) == args.payload_sha256, "Frozen inputs changed during build")
    v.invariant_files()
    data = (json.dumps(world, ensure_ascii=False, separators=(",", ":")) + "\n").encode()
    with output.open("xb") as file: file.write(data)
    print(json.dumps({"written": str(output), "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data),
                      "retained_property_changes": len(world["retained_changes"]), "new_code_nodes": len(world["new_nodes"]),
                      "world_additions": 0, "beds_untouched": 1406, "requires_independent_review_before_freeze": True}))
