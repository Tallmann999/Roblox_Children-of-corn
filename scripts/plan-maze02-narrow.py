"""Propose reversible width edits for the already saved B maze 02.

Only JSON is written. This planner never connects to Studio or serializes a
scene. Studio must check the whole proposed before state before changing it.
The original maze payload and layout are inputs and are never rewritten.
"""

from __future__ import annotations

import argparse
from copy import deepcopy
import hashlib
import json
import math
from pathlib import Path
import struct
import sys


sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
OLD = ROOT / ".artifacts/playtests/2026-10-21-maze02"
OUT = ROOT / ".artifacts/playtests/2026-10-21-maze02-refine/path-plan.json"
BASELINE_SHA = "108066bc0cf2a55f3c90d8db0ba7bef2eccb4a21351d5e9d53983fbcce8c50f3"
PAYLOAD_SHA = "26bca1b53c6b1d5e8007aac52502062f37ad5c273c333d66b1f8a9b0700b31f2"
MAP = "Workspace/CornMap"
TRAIL_ROOT = MAP + "/NoCornZones/Maze02Masks"
ROAD = MAP + "/Props/VillageRoad"


def require(test, message):
    if not test:
        raise ValueError(message)


def f32(number):
    require(type(number) in (int, float) and math.isfinite(number), "Nonfinite geometry")
    return struct.unpack("<f", struct.pack("<f", number))[0]


def typed(kind, values):
    return {"kind": kind, "value": [f32(value) for value in values]}


def near(a, b, epsilon=0.00005):
    return len(a) == len(b) and all(abs(x-y) <= epsilon for x, y in zip(a, b))


def expected_nodes(native, payload, editor):
    """Construct known native values of the saved maze without scene rewriting.

    This is useful when Studio has not been restarted since the accepted save:
    its non-cardinal CFrames retain small rotation residues that compact RBXL
    rotations omit. The native installer still has to prove these exact values.
    """
    require(payload["owner"] == "corn_maze02_v1", "Wrong accepted maze owner")
    nodes = deepcopy(native["nodes"] + editor["nodes"])
    for addition in payload["nodes"]:
        props = addition["properties"]
        row = {"path": addition["path"], "class": addition["class"],
               "attrs": deepcopy(addition["attributes"]), "tags": addition["tags"]}
        for prop, name in (("CFrame", "frame"), ("Size", "size"), ("Transparency", "transparency")):
            if prop in props:
                value = props[prop]
                row[name] = value["value"] if isinstance(value, dict) else value
        nodes.append(row)
    for change in payload["changes"]:
        found = [n for n in nodes if n["path"] == change["path"]
                 and (not change.get("selector") or near(n["frame"], change["selector"]["CFrame"]["value"], 0))]
        require(len(found) == 1, "Ambiguous accepted change: " + change["path"])
        target = found[0]
        after = change["after"]
        if change["attribute"]:
            target["attrs"] = target.get("attrs") or {}
            target["attrs"][change["property"]] = deepcopy(after)
        else:
            name = {"CFrame":"frame", "Size":"size", "Transparency":"transparency"}.get(change["property"])
            require(name is not None, "Unexpected frozen world property")
            target[name] = deepcopy(after["value"] if isinstance(after, dict) else after)
    return nodes


def intersects_plant(node, box, padding):
    """Conservative XZ AABB of the oriented editor plant, including its leaves."""
    frame, size = node["frame"], node["size"]
    half_x = sum(abs(frame[3+i]) * size[i] / 2 for i in range(3))
    half_z = sum(abs(frame[9+i]) * size[i] / 2 for i in range(3))
    x, z, sx, sz = box
    return (abs(frame[0]-x) <= sx/2 + padding + half_x
            and abs(frame[2]-z) <= sz/2 + padding + half_z)


def build_plan(nodes, layout, *, trail_padding=1.5):
    require(trail_padding == 1.5, "Accepted BOX_PADDING must remain unchanged at1.5")
    unique = {}
    for node in nodes:
        unique.setdefault(node["path"], []).append(node)
    def node(path):
        found = unique.get(path, [])
        require(len(found) == 1, "Unique accepted path required: " + path)
        return found[0]
    changes, keys = [], set()
    def add(target, prop, before, after, *, attribute=False, selector=None):
        require(before != after, "No-op proposed change")
        row = {"path":target["path"], "property":prop, "attribute":attribute,
               "before":deepcopy(before), "after":deepcopy(after)}
        if selector is not None:
            row["selector"] = deepcopy(selector)
            row["installedSelector"] = deepcopy(selector)
        key = (row["path"], prop, attribute, json.dumps(selector, sort_keys=True))
        require(key not in keys, "Duplicate planned property")
        keys.add(key)
        changes.append(row)
    def size(target, values):
        add(target, "Size", typed("Vector3",target["size"]), typed("Vector3",values))
    def size_attr(target, name, values):
        old = (target.get("attrs") or {}).get(name)
        require(isinstance(old, dict) and old.get("kind") == "Vector3", "Missing exact size binding")
        add(target, name, old, typed("Vector3", values), attribute=True)

    trails = [s for s in layout["segments"] if s["kind"] == "trail"]
    require(len(trails) == 100 and len({s["id"] for s in trails}) == 100, "Accepted 100 trails required")
    existing_paths = {p for p in unique if p.startswith(TRAIL_ROOT + "/")}
    require(existing_paths == {TRAIL_ROOT+"/"+s["id"] for s in trails}, "Maze trail set changed")
    narrowed, boxes = [], []
    for segment in trails:
        target = node(TRAIL_ROOT + "/" + segment["id"])
        require(target["class"] == "Part" and (target.get("attrs") or {}).get("CornMazeOwner") == "corn_maze02_v1",
                "Unrecognized maze trail")
        require(near(target["size"][::2], segment["size_xz"]), "Accepted trail size changed")
        require(near([target["frame"][0],target["frame"][2]],segment["center_xz"]),
                "Accepted trail center changed")
        start, end = segment["start_xz"], segment["end_xz"]
        sx, sz = abs(end[0]-start[0])+4, abs(end[1]-start[1])+4
        new_size = [sx,target["size"][1],sz]
        size(target, new_size)
        item = deepcopy(segment)
        item.update(size_xz=[f32(sx),f32(sz)], width=4, endpoint_overlap=2,
                    exclusion_padding=trail_padding)
        narrowed.append(item)
        boxes.append((target["frame"][0],target["frame"][2],f32(sx),f32(sz)))

    surface, clearance = node(ROAD+"/RoadSurface"), node(ROAD+"/RoadClearance")
    require(near(surface["size"],[8,0.08,27.25]) and near(clearance["size"],[12,10,27.25]), "Accepted gate approach changed")
    size(surface,[4,surface["size"][1],surface["size"][2]])
    size(clearance,[6,clearance["size"][1],clearance["size"][2]])
    for name in ("RutLeft","RutRight"):
        rut = node(ROAD+"/"+name)
        require(abs(rut["size"][0]-1.6)<0.0001 and near(rut["size"][1:],[0.02,27.25]), "Accepted rut geometry changed")
        cf = list(rut["frame"])
        cf[0] = f32(surface["frame"][0] + (cf[0]-surface["frame"][0])/2)
        add(rut,"CFrame",typed("CFrame",rut["frame"]),typed("CFrame",cf))
        size(rut,[rut["size"][0]/2,rut["size"][1],rut["size"][2]])
    overlay = node(MAP+"/HarvestDecor/VariantB/RoadSurface")
    require(near(overlay["size"][::2],surface["size"][::2]), "Road art size changed")
    size(overlay,[4,overlay["size"][1],overlay["size"][2]])
    size_attr(overlay,"HarvestPlacedSize",[4,overlay["size"][1],overlay["size"][2]])
    size_attr(node(MAP+"/HarvestDecor"),"HarvestRoadSize",[4,surface["size"][1],surface["size"][2]])

    # The frozen previous proposal only hid plants that were visible beforehand.
    # Narrowing produces a subset of the old clearing. No additional editor
    # plant can need hiding. Restore only those whose entire leaf bbox safely
    # clears the new trail area, retaining a conservative extra plant margin.
    frozen_editor = json.loads((OLD/"editor-before.json").read_text(encoding="utf-8"))["nodes"]
    other_boxes, circles = [], []
    for target in nodes:
        path=target["path"]
        if "frame" not in target or "size" not in target or path.startswith(TRAIL_ROOT+"/"):
            continue
        tags=target.get("tags") or []
        if (path.startswith(MAP+"/Props/") or path.startswith(MAP+"/NoCornZones/")
                or "corn_no_corn_zone" in tags):
            sx,_,sz=target["size"]
            if path == ROAD+"/RoadSurface": sx=4
            if path == ROAD+"/RoadClearance": sx=6
            if path in {ROAD+"/RutLeft",ROAD+"/RutRight"}: continue
            # AABB encloses any oriented authored prop. This is deliberately
            # conservative for the sparse editor overview, never gameplay.
            frame=target["frame"]
            half_x=sum(abs(frame[3+i])*[sx,target["size"][1],sz][i]/2 for i in range(3))
            half_z=sum(abs(frame[9+i])*[sx,target["size"][1],sz][i]/2 for i in range(3))
            other_boxes.append((frame[0],frame[2],half_x*2,half_z*2))
        if "corn_spawn" in tags or "corn_key_slot" in tags:
            circles.append((target["frame"][0],target["frame"][2],10 if "corn_spawn" in tags else 6))
        if path == MAP+"/EscapeGate/Door":
            other_boxes.append((target["frame"][0],target["frame"][2],target["size"][0]+12,target["size"][2]+12))
    restored, retained = [], []
    for original in frozen_editor:
        candidates = [n for n in unique.get(original["path"],[]) if near(n.get("frame",[]),original["frame"],0.000001)]
        require(len(candidates)==1, "Exact frozen editor plant missing")
        target=candidates[0]
        require(target.get("transparency")==1 and near(target["size"],original["size"],0), "Known hidden editor plant changed")
        # Native editor selection used a 3.7 stud center-to-trail-edge margin,
        # which already covers this art's leaf footprint. Keep that same margin
        # and retain full-leaf overlaps with future authored prop clearances.
        keep=(any(abs(target["frame"][0]-x)<=sx/2+3.7 and abs(target["frame"][2]-z)<=sz/2+3.7
                  for x,z,sx,sz in boxes)
              or any(intersects_plant(target,box,1.5) for box in other_boxes)
              or any(math.hypot(target["frame"][0]-x,target["frame"][2]-z)<=radius+3.7
                     for x,z,radius in circles))
        if keep:
            retained.append(original["frame"][:3])
            continue
        selector={"CFrame":typed("CFrame",target["frame"])}
        add(target,"Transparency",1,0,selector=selector)
        restored.append(original["frame"][:3])
    require(restored, "Narrowing unexpectedly restored no editor corn")
    return {"schema_version":1,"baseline_sha256":BASELINE_SHA,"scene_variant":"B",
            "changes":changes,"segments":narrowed,
            "trail_width_before":8,"trail_width_after":4,
            "trail_endpoint_overlap_before":4,"trail_endpoint_overlap_after":2,
            "source_requirements":{"maze_trail_exclusion_padding":trail_padding,"padding_source_change_required":False,
                "note":"CornLayout BOX_PADDING remains1.5. Visible trail width halves8to4; plant-center clearing11to7 retains unchanged leaf half-extents, giving an approximately4stud leaf-free corridor. Barn and gate clearances remain wider."},
            "counts":{"trail_sizes":100,"editor_restored":len(restored),"editor_retained_hidden":len(retained),"changes":len(changes)},
            "preserved":{"centerline_graph":True,"all_4_spawns":True,"all_15_slot_ids_positions":True,
                         "barn_geometry":True,"gate_door_width_12":True,"all_node_identities_parents":True},
            "editor_note":"Only exact previously hidden editor plants are restored; editor overview remains approximate. Actual Play corn regenerates from current exclusions."}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native",type=Path,help="Optional fresh compact native snapshot, including all 1441 previously hidden editor plants")
    args=parser.parse_args()
    payload_bytes=(OLD/"payload.json").read_bytes()
    require(hashlib.sha256(payload_bytes).hexdigest()==PAYLOAD_SHA,"Frozen maze payload changed")
    require(hashlib.sha256((ROOT/"place/Children_of_corn_B.rbxl").read_bytes()).hexdigest()==BASELINE_SHA,"Saved B baseline changed")
    layout=json.loads((OLD/"layout.json").read_text(encoding="utf-8"))
    if args.native:
        nodes=json.loads(args.native.read_text(encoding="utf-8"))["nodes"]
    else:
        nodes=expected_nodes(json.loads((OLD/"native-before.json").read_text()),json.loads(payload_bytes),
                             json.loads((OLD/"editor-before.json").read_text()))
    plan=build_plan(nodes,layout)
    OUT.parent.mkdir(parents=True,exist_ok=True)
    OUT.write_text(json.dumps(plan,ensure_ascii=False,indent=2)+"\n",encoding="utf-8",newline="\n")
    print(json.dumps(plan["counts"]))


if __name__=="__main__":
    main()
