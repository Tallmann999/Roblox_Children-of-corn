"""Plan explicit, reversible Corn B world property deltas from a native MCP snapshot.

This script never opens, serializes, or writes a Roblox scene. It writes only a
JSON proposal. All existing node identities, art, Sources and unknown properties
remain outside the proposal. Studio installation must recheck every before value.
"""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import re
import struct


ROOT = "Workspace/CornMap"
PROJECT = "children_of_corn"
HOUSES = ("HouseNorthWest", "HouseEast", "HouseWest")
BARN_PARTS = {
    "SM_Bld_Barn_03",
    "SM_Bld_Barn_03_Shutter_01",
    "SM_Bld_Barn_03_Shutter_02",
    "SM_Bld_Barn_03_Door_01",
    "SM_Bld_Barn_03_Door_02",
    "SM_Bld_Barn_03_Door_03",
    "SM_Bld_Barn_03_Door_04",
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def f32(value):
    require(isinstance(value, (int, float)) and math.isfinite(value), "Nonfinite geometry")
    return struct.unpack("<f", struct.pack("<f", value))[0]


def unpack(value):
    if isinstance(value, dict) and "value" in value and ("kind" in value or "type" in value):
        return value["value"]
    return value


def typed(kind, value):
    return {"kind": kind, "value": [f32(v) for v in value]}


def near(left, right, epsilon=0.0001):
    left, right = unpack(left), unpack(right)
    if isinstance(left, (list, tuple)) and isinstance(right, (list, tuple)):
        return len(left) == len(right) and all(near(a, b, epsilon) for a, b in zip(left, right))
    if isinstance(left, (int, float)) and isinstance(right, (int, float)):
        return abs(left - right) <= epsilon
    return left == right


def read_nodes(data):
    """Accept the current compact native schema and earlier full read-only exports."""
    if "nodes" in data:
        nodes = data["nodes"]
    elif "records" in data and isinstance(data["records"], dict):
        nodes = [dict(value, path=path) for path, value in data["records"].items()]
    else:
        nodes = data.get("groups", []) + data.get("parts", [])
    require(isinstance(nodes, list) and nodes, "Native snapshot has no nodes")
    duplicate_counts = Counter(node["path"] for node in nodes)
    for path, count in duplicate_counts.items():
        require(count == 1 or (path == ROOT + "/Props/LookoutBarrel" and count == 3),
                "Ambiguous duplicate native path: " + path)
    result = {}
    for original in nodes:
        node = dict(original)
        path = node["path"]
        require(path == ROOT or path.startswith(ROOT + "/"), "Snapshot contains non-Corn path")
        node["attrs"] = node.get("attrs", node.get("attributes", {})) or {}
        require(isinstance(node["attrs"], dict), "Invalid native attributes")
        props = node.get("properties", {})
        for dest, key in (("frame", "CFrame"), ("size", "Size")):
            if dest not in node and key in props:
                node[dest] = unpack(props[key])
        for field in ("frame", "size"):
            if field in node:
                node[field] = unpack(node[field])
        key = path
        if duplicate_counts[path] > 1:
            require("frame" in node, "Duplicate barrel lacks geometric selector")
            node["_selector"] = {"CFrame": typed("CFrame", node["frame"])}
            key += "\x00" + json.dumps(node["frame"], separators=(",", ":"))
        require(key not in result, "Duplicate barrel geometric selector")
        result[key] = node
    return result


def attr(node, name):
    return unpack(node["attrs"].get(name))


def translated(frame, dx, dz):
    require(len(frame) == 12, "Invalid CFrame")
    result = list(frame)
    result[0] = f32(frame[0] + dx)
    result[2] = f32(frame[2] + dz)
    return result


def rotated_barn(frame, source_center, target_center):
    """Delta world Y +90 degrees, centered on the native main barn body."""
    require(len(frame) == 12, "Invalid CFrame")
    x, y, z, *m = frame
    # R(+90) = [0,0,1; 0,1,0; -1,0,0]. Keep native Y exactly.
    return [
        f32(target_center[0] + z - source_center[1]), y,
        f32(target_center[1] - x + source_center[0]),
        *[f32(v) for v in (m[6], m[7], m[8], m[3], m[4], m[5], -m[0], -m[1], -m[2])],
    ]


def layout_values(layout):
    centers = layout.get("barnCenters", layout.get("barns"))
    if centers is None:
        centers = [[0, 186.83823529411765], [0, -16.985294117647058], [0, -186.83823529411765]]
    parsed_centers = []
    for center in centers:
        if isinstance(center, dict):
            center = center.get("center_xz", center.get("center", [center.get("x"), center.get("z")]))
        require(isinstance(center, list) and len(center) in (2, 3), "Invalid barn center")
        parsed_centers.append([center[0], center[-1]])
    require(len(parsed_centers) == 3, "Exactly three barn centers required")
    require(all(abs(c[0]) < 0.001 for c in parsed_centers), "Barns must bridge the two branches")
    parsed_centers.sort(key=lambda p: -p[1])
    source_slots = layout.get("slotPositions", layout.get("slots", layout.get("key_slots")))
    require(source_slots is not None, "Layout must explicitly list all 15 stable slot IDs")
    slots = {}
    if isinstance(source_slots, dict):
        iterator = source_slots.items()
    else:
        require(isinstance(source_slots, list), "Invalid slots layout")
        iterator = ((entry.get("id", entry.get("slot_id")), entry) for entry in source_slots)
    for slot_id, item in iterator:
        require(isinstance(slot_id, str) and re.fullmatch(r"solo_slot_\d{2}", slot_id), "Unknown slot ID")
        if isinstance(item, dict):
            if "position" in item:
                point = item["position"]
            elif "world" in item:
                point = item["world"]
            else:
                point = [item.get("x"), item.get("z")]
        else:
            point = item
        require(isinstance(point, list) and len(point) in (2, 3), "Invalid slot position")
        require(slot_id not in slots, "Duplicate slot ID")
        slots[slot_id] = [point[0], point[-1]]
    require(set(slots) == {f"solo_slot_{i:02d}" for i in range(1, 16)}, "All 15 stable slots required")
    require(len({tuple(p) for p in slots.values()}) == 15, "Slots must remain distinct")
    require(all(all(isinstance(v, (int, float)) and math.isfinite(v) and abs(v) < 300 for v in p)
                for p in slots.values()), "Slots outside the field or nonfinite")
    finish = layout.get("finish", {})
    gate_point = finish.get("gate_center_xz", [-93.98529411764706, 316])
    gate_x = layout.get("gateX", gate_point[0])
    gate_z = layout.get("gateZ", gate_point[1])
    require(abs(gate_z - 316) < 0.001, "This proposal preserves the existing +Z exit side")
    require(-280 < gate_x < 280, "Gate would cover a corner start")
    return parsed_centers, slots, gate_x


class Planner:
    def __init__(self, nodes):
        self.nodes = nodes
        self.changes = []
        self.keys = set()
        self.moved = set()
        self.associations = {}
        self.barn_transforms = {}

    def node(self, path):
        require(path in self.nodes, "Missing native node: " + path)
        return self.nodes[path]

    def children_parts(self, prefix):
        return [n for p, n in self.nodes.items() if p.startswith(prefix + "/") and "frame" in n]

    def add(self, node, prop, kind, before, after, attribute=False):
        before_value, after_value = typed(kind, unpack(before)), typed(kind, unpack(after))
        if near(before_value, after_value, 0):
            return
        selector = node.get("_selector")
        key = (node["path"], json.dumps(selector, sort_keys=True), attribute, prop)
        require(key not in self.keys, "Overlapping planned change: " + str(key))
        self.keys.add(key)
        change = {"path": node["path"], "property": prop, "attribute": attribute,
                  "before": before_value, "after": after_value}
        if selector:
            change["selector"] = selector
            change["installedSelector"] = {"CFrame": after_value if prop == "CFrame" else selector["CFrame"]}
        self.changes.append(change)

    def frame(self, node, new_frame):
        self.add(node, "CFrame", "CFrame", node["frame"], new_frame)
        self.moved.add((node["path"], json.dumps(node.get("_selector"), sort_keys=True)))

    def size(self, node, new_size):
        self.add(node, "Size", "Vector3", node["size"], new_size)

    def frame_attr(self, node, name, transform, required=False):
        old = attr(node, name)
        require(old is not None or not required, "Missing binding " + node["path"] + "/" + name)
        if old is not None:
            self.add(node, name, "CFrame", old, transform(old), True)

    def size_attr(self, node, name, new_size, required=False):
        old = attr(node, name)
        require(old is not None or not required, "Missing binding " + node["path"] + "/" + name)
        if old is not None:
            self.add(node, name, "Vector3", old, new_size, True)

    def barn(self, name, target):
        prefix = ROOT + "/Props/" + name
        body = self.node(prefix + "/SM_Bld_Barn_03")
        require(body["class"] == "MeshPart" and attr(body, "CornFarmMeshOwned") is True,
                "Unrecognized native barn mesh")
        parts = self.children_parts(prefix)
        require({p["path"].rsplit("/", 1)[1] for p in parts} == BARN_PARTS and len(parts) == 7,
                "Author barn composition changed: " + prefix)
        center = [body["frame"][0], body["frame"][2]]
        transform = lambda cf: rotated_barn(cf, center, target)
        self.barn_transforms[name] = transform
        for node in parts:
            require(node["class"] == "MeshPart" and attr(node, "corn_project_id") == PROJECT,
                    "Unexpected physical barn part")
            self.frame(node, transform(node["frame"]))
        overlays = [node for p, node in self.nodes.items()
                    if p.startswith(ROOT + "/HarvestDecor/VariantB/") and attr(node, "HarvestSourceHouse") == name]
        require(overlays and all("frame" in node for node in overlays), "B barn overlay missing")
        for node in overlays:
            source = self.node(prefix + "/" + attr(node, "HarvestSourceName"))
            require(near(attr(node, "HarvestSourceFrame"), source["frame"]), "B barn source binding differs")
            require(near(attr(node, "HarvestPlacedFrame"), node["frame"]), "B barn placement binding differs")
            self.frame(node, transform(node["frame"]))
            self.frame_attr(node, "HarvestPlacedFrame", transform, True)
            self.frame_attr(node, "HarvestSourceFrame", transform, True)
        common_prefix = ROOT + "/HarvestDecor/Common/" + name + "_"
        common = [n for p, n in self.nodes.items() if p.startswith(common_prefix) and "frame" in n]
        common_groups = {n["path"].split("/Common/", 1)[1].split("/", 1)[0] for n in common}
        require(len(common_groups) == 9, "Expected four fences and five rocks for " + name)
        for node in common:
            require(near(attr(node, "HarvestPlacedFrame"), node["frame"]), "Common placement binding differs")
            self.frame(node, transform(node["frame"]))
            self.frame_attr(node, "HarvestPlacedFrame", transform, True)
        for suffix in ("-1", "1"):
            torch = ROOT + "/TorchMarkers/torch_" + name + suffix
            parts = self.children_parts(torch)
            require({p["path"].rsplit("/", 1)[1] for p in parts} == {"Pole", "Flame"}, "Barn torch differs")
            for node in parts:
                self.frame(node, transform(node["frame"]))
        self.associations[name] = {"oldCenter": center, "newCenter": target,
                                   "rotationDeltaY": 90, "physicalParts": 7,
                                   "overlayParts": len(overlays), "commonParts": len(common)}

    def slots(self, desired):
        slots = [self.node(ROOT + "/KeySlots/" + name) for name in sorted(desired)]
        deltas = {}
        for slot in slots:
            slot_id = slot["path"].rsplit("/", 1)[1]
            require(attr(slot, "slot_id") == slot_id, "Slot identity differs")
            target = desired[slot_id]
            dx, dz = target[0] - slot["frame"][0], target[1] - slot["frame"][2]
            deltas[slot_id] = (dx, dz)
            self.frame(slot, translated(slot["frame"], dx, dz))
            torch_prefix = ROOT + "/TorchMarkers/torch_" + slot_id
            parts = self.children_parts(torch_prefix)
            require({n["path"].rsplit("/", 1)[1] for n in parts} == {"Pole", "Flame"}, "Slot torch missing")
            for node in parts:
                require(abs(node["frame"][0] - slot["frame"][0]) < 0.001
                        and abs(node["frame"][2] - slot["frame"][2] - 4) < 0.001,
                        "Slot/torch offset changed")
                self.frame(node, translated(node["frame"], dx, dz))
        barrels = [n for p, n in self.nodes.items() if p.startswith(ROOT + "/Props/")
                   and "frame" in n and ("LookoutBarrel" in p or "corn_barrel" in n.get("tags", []))]
        require(len(barrels) == 3, "Expected exactly three native legacy barrels; no guessing")
        associations = []
        for barrel in barrels:
            distances = sorted((math.hypot(barrel["frame"][0] - s["frame"][0],
                                         barrel["frame"][2] - s["frame"][2]), s["path"].rsplit("/", 1)[1])
                               for s in slots)
            require(distances[0][0] < 6 and distances[1][0] > 15, "Ambiguous barrel cluster")
            slot_id = distances[0][1]
            require(slot_id not in [a["slot_id"] for a in associations], "Two barrels linked to the same slot")
            require(slot_id in {"solo_slot_03", "solo_slot_08", "solo_slot_13"}, "Legacy barrel slot differs")
            associations.append({"path": barrel["path"], "selector": barrel.get("_selector"), "slot_id": slot_id})
            self.frame(barrel, translated(barrel["frame"], *deltas[slot_id]))
        self.associations["barrels"] = associations

    def gate_and_road(self, gate_x):
        door = self.node(ROOT + "/EscapeGate/Door")
        require(near(door["frame"][:3:2], [0, 316]), "Existing gate unexpectedly moved")
        for node in self.children_parts(ROOT + "/EscapeGate"):
            self.frame(node, translated(node["frame"], gate_x, 0))
        for name in ("road_exit_wall_left", "road_exit_wall_right"):
            parts = self.children_parts(ROOT + "/TorchMarkers/" + name)
            require({n["path"].rsplit("/", 1)[1] for n in parts} == {"Pole", "Flame"}, "Gate wall torch missing")
            for node in parts:
                self.frame(node, translated(node["frame"], gate_x, 0))
        sign = self.node(ROOT + "/Props/VillageRoad/ExitSign")
        self.frame(sign, translated(sign["frame"], gate_x, 0))
        for name, lo, hi in (("NorthLeft", -315, gate_x - 6), ("NorthRight", gate_x + 6, 315)):
            node = self.node(ROOT + "/Boundaries/" + name)
            require(abs(node["frame"][2] - 316) < 0.001 and abs(node["size"][2] - 2) < 0.001,
                    "Unknown north boundary geometry")
            frame = list(node["frame"])
            frame[0] = (lo + hi) / 2
            self.frame(node, frame)
            self.size(node, [hi - lo, node["size"][1], node["size"][2]])
        road_center_z, road_length = (288.75 + 316) / 2, 316 - 288.75
        road_prefix = ROOT + "/Props/VillageRoad/"
        road = self.node(road_prefix + "RoadSurface")
        require(near(road["size"][::2], [14, 630]), "Road dimensions changed")
        for name in ("RoadSurface", "RoadClearance", "RutLeft", "RutRight"):
            node = self.node(road_prefix + name)
            frame, size = list(node["frame"]), list(node["size"])
            frame[0] = gate_x + (node["frame"][0] * 8 / 14 if name.startswith("Rut") else 0)
            frame[2] = road_center_z
            if not name.startswith("Rut"):
                size[0] = 8 if name == "RoadSurface" else 12
            size[2] = road_length
            self.frame(node, frame)
            self.size(node, size)
        overlay = self.node(ROOT + "/HarvestDecor/VariantB/RoadSurface")
        require(near(attr(overlay, "HarvestPlacedFrame"), overlay["frame"]), "B road placement binding differs")
        overlay_frame, overlay_size = list(overlay["frame"]), list(overlay["size"])
        overlay_frame[0], overlay_frame[2] = gate_x, road_center_z
        overlay_size[0], overlay_size[2] = 8, road_length
        self.frame(overlay, overlay_frame)
        self.size(overlay, overlay_size)
        self.frame_attr(overlay, "HarvestPlacedFrame", lambda _: overlay_frame, True)
        self.size_attr(overlay, "HarvestPlacedSize", overlay_size, True)
        decor = self.node(ROOT + "/HarvestDecor")
        require(near(attr(decor, "HarvestRoadFrame"), road["frame"])
                and near(attr(decor, "HarvestRoadSize"), road["size"]), "Harvest road root binding differs")
        new_road_frame = list(road["frame"])
        new_road_frame[0], new_road_frame[2] = gate_x, road_center_z
        self.frame_attr(decor, "HarvestRoadFrame", lambda _: new_road_frame, True)
        self.size_attr(decor, "HarvestRoadSize", [8, road["size"][1], road_length], True)
        self.associations["exit"] = {"gateX": gate_x, "gateZ": 316, "roadLength": road_length,
                                      "roadCenterZ": road_center_z, "doorWidth": 12}

    def clear_known_barn_props(self):
        """Preserve the two former East-barn props now crossing the selected trail."""
        house = self.node(ROOT + "/Props/HouseEast/SM_Bld_Barn_03")
        moved = []
        for model, mesh in (("RubbishPile_02", "SM_Prop_Rubbish_Pile_05"),
                            ("Tyre_02", "SM_Prop_Tyre_01")):
            node = self.node(ROOT + "/Props/" + model + "/" + mesh)
            require(node["class"] == "MeshPart" and attr(node, "CornFarmMeshOwned") is True,
                    "Unrecognized related barn prop")
            distances = sorted((math.hypot(node["frame"][0] - self.node(ROOT + "/Props/" + name
                                                                     + "/SM_Bld_Barn_03")["frame"][0],
                                         node["frame"][2] - self.node(ROOT + "/Props/" + name
                                                                     + "/SM_Bld_Barn_03")["frame"][2]), name)
                               for name in HOUSES)
            require(distances[0][1] == "HouseEast" and distances[0][0] < 16 and distances[1][0] > 50,
                    "Related barn prop association is ambiguous")
            require(len(self.children_parts(ROOT + "/Props/" + model)) == 1,
                    "Related barn prop composition changed")
            self.frame(node, self.barn_transforms["HouseEast"](node["frame"]))
            moved.append({"path": node["path"], "house": "HouseEast", "reason": "clear trail_087"})
        self.associations["relatedBarnProps"] = moved

    def collision_audit(self, layout):
        changed = {(c["path"], json.dumps(c.get("selector"), sort_keys=True), c["property"]): unpack(c["after"])
                   for c in self.changes if not c["attribute"]}
        colliders = []
        for node in self.nodes.values():
            if "frame" not in node or not node.get("collide") or not node["path"].startswith(ROOT + "/Props/"):
                continue
            key = (node["path"], json.dumps(node.get("_selector"), sort_keys=True))
            frame = changed.get((*key, "CFrame"), node["frame"])
            size = changed.get((*key, "Size"), node["size"])
            half = [sum(abs(frame[3 + row * 3 + col]) * size[col] / 2 for col in range(3))
                    for row in range(3)]
            colliders.append({"node": node, "xz": [frame[0] - half[0], frame[0] + half[0],
                                                    frame[2] - half[2], frame[2] + half[2]],
                              "minY": frame[1] - half[1]})

        def overlap(a, b):
            return min(a[1], b[1]) > max(a[0], b[0]) and min(a[3], b[3]) > max(a[2], b[2])

        slot_collisions = []
        for slot in layout["key_slots"]:
            for collider in colliders:
                node = collider["node"]
                if "LookoutBarrel" in node["path"]:
                    own = next((a["slot_id"] for a in self.associations["barrels"]
                                if a["selector"] == node.get("_selector")), None)
                    if own == slot["id"]:
                        continue
                if overlap(slot["item_hull_xz"], collider["xz"]):
                    slot_collisions.append([slot["id"], node["path"]])
        trail_collisions = []
        for segment in layout["segments"]:
            x, z = segment["center_xz"]
            sx, sz = segment["size_xz"]
            box = [x - sx / 2, x + sx / 2, z - sz / 2, z + sz / 2]
            for collider in colliders:
                path = collider["node"]["path"]
                # Barn shells require real mesh collision tests; slot barrels are
                # intentional inherited cover inside their own item clearings.
                if "/House" in path or "LookoutBarrel" in path:
                    continue
                if collider["minY"] > layout["floor_y"] + 7:
                    continue
                if overlap(box, collider["xz"]):
                    trail_collisions.append([segment["id"], path])
        require(not slot_collisions, "Slot overlaps foreign colliders: " + str(slot_collisions))
        require(not trail_collisions, "Trail overlaps unrelated colliders: " + str(trail_collisions))
        return {"method": "conservative horizontal world AABBs of native collidable Props after deltas",
                "colliderCount": len(colliders), "slotCount": len(layout["key_slots"]),
                "segmentCount": len(layout["segments"]), "slotForeignColliderOverlaps": slot_collisions,
                "trailUnrelatedColliderOverlaps": trail_collisions,
                "throughBarnMeshPhysics": "native Play test required",
                "ownSlotBarrels": "retained inside their original cluster hull"}


def build(snapshot, layout):
    require(snapshot.get("running", False) is False, "Stopped Edit snapshot required")
    nodes = read_nodes(snapshot)
    if ROOT in nodes:
        require(attr(nodes[ROOT], "corn_project_id") == PROJECT
                and attr(nodes[ROOT], "HarvestArtVariant") == "B", "Verified Corn B root required")
    planner = Planner(nodes)
    require(near(planner.node(ROOT + "/Ground")["size"], [630, 2, 630])
            and near(planner.node(ROOT + "/FieldZone")["size"], [630, 10, 630]), "630 field required")
    centers, slots, gate_x = layout_values(layout)
    for name, center in zip(HOUSES, centers):
        planner.barn(name, center)
    planner.slots(slots)
    planner.gate_and_road(gate_x)
    planner.clear_known_barn_props()
    audit = planner.collision_audit(layout)
    planner.changes.sort(key=lambda c: (c["path"], c["attribute"], c["property"]))
    return {"version": 1, "project": PROJECT, "variant": "B", "changes": planner.changes,
            "associations": planner.associations, "collisionAudit": audit,
            "counts": {"changes": len(planner.changes), "movedParts": len(planner.moved),
                       "propertyChanges": sum(not c["attribute"] for c in planner.changes),
                       "attributeChanges": sum(c["attribute"] for c in planner.changes)},
            "scope": {"Sources": "unchanged", "identities": "unchanged", "parents": "unchanged",
                      "barnSizes": "unchanged", "cornTemplates": "unchanged", "Lighting": "unchanged",
                      "allOtherProperties": "unchanged"},
            "notes": ["Only explicit property/attribute changes; no node additions/removals in this plan.",
                      "Road-row torches, unrelated props and road-fence decorations remain at their authored positions.",
                      "Physical through-barn passage and mesh rendering require native Play acceptance.",
                      "No AI concealment, timer or balance changes are included."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native", type=Path, default=Path(".artifacts/playtests/2026-10-21-maze02/native-before.json"))
    parser.add_argument("--layout", type=Path, required=True)
    parser.add_argument("--out", type=Path, default=Path(".artifacts/playtests/2026-10-21-maze02/world-delta.json"))
    args = parser.parse_args()
    require(args.out.suffix.lower() == ".json", "Proposal output must be JSON")
    require(args.out.resolve() not in {args.native.resolve(), args.layout.resolve()}, "Never overwrite evidence")
    native_bytes, layout_bytes = args.native.read_bytes(), args.layout.read_bytes()
    proposal = build(json.loads(native_bytes), json.loads(layout_bytes))
    proposal["inputs"] = {"native": str(args.native), "nativeSha256": hashlib.sha256(native_bytes).hexdigest(),
                          "layout": str(args.layout), "layoutSha256": hashlib.sha256(layout_bytes).hexdigest()}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(proposal, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"output": str(args.out), **proposal["counts"]}))


if __name__ == "__main__":
    main()
