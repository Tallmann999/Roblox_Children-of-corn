"""Build a fixed CFrame-only cluster update; never write a scene. --check is read-only."""
import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / "place/Children_of_corn.before-haze-clusters-20261015.rbxl"
BASELINE_HASH = "a897bb52fa85505090f973e910139915e6ebb2995e44915c31ecbc2b5c511dca"
OUTPUT = ROOT / "scripts/cluster-layout.json"
INSTALLER = ROOT / "scripts/install-cluster-layout.luau"
PREFIX = "Workspace/CornMap"
BARRELS = {3: PREFIX + "/Props/LookoutBarrel", 8: PREFIX + "/Props/LookoutBarrel#2", 13: PREFIX + "/Props/LookoutBarrel#3"}


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


T = module("torch_helpers", ROOT / "scripts/build-finale-torch-layout.py")
T.FIELDS["MeshPart"] = [key for key in T.FIELDS["Part"] if key != "shape"]
T.FIELDS["SpawnLocation"] = T.FIELDS["Part"] + ["Enabled", "Neutral"]
P = module("preservation", ROOT / "scripts/verify-scene-preservation.py")
require, components = T.require, T.components


def close(a, b):
    return len(a) == len(b) and all(abs(x-y) < 0.00001 for x,y in zip(a,b))


def bounds(frame, size):
    extents = [sum(abs(frame[3+a*3+c])*size[c]/2 for c in range(3)) for a in range(3)]
    return [(frame[a]-extents[a], frame[a]+extents[a]) for a in range(3)]


def gap(a, b):
    dx = max(a[0][0]-b[0][1], b[0][0]-a[0][1], 0)
    dz = max(a[2][0]-b[2][1], b[2][0]-a[2][1], 0)
    return math.hypot(dx, dz)


def build_manifest():
    data = BASELINE.read_bytes()
    require(len(data) == 1019419 and hashlib.sha256(data).hexdigest() == BASELINE_HASH, "Immutable cluster baseline changed")
    dom, _ = P.known_dom(BASELINE)
    torch = json.loads((ROOT / "scripts/finale-torch-layout.json").read_text(encoding="utf-8"))
    require(torch["version"] == 2 and len(torch["parts"]) == 54, "Accepted Torch V2 required")
    for row in torch["parts"]:
        require(close(components(dom[row["path"]]["properties"]["CFrame"]), row["after"]), "Baseline is not complete Torch V2: " + row["path"])
    moves, clusters, barrel_bindings = [], [], []

    def move(path, after, role, slot_id):
        before = components(dom[path]["properties"]["CFrame"])
        require(before[1] == after[1] and before[3:] == after[3:], "Only XZ translation allowed")
        if before != after:
            moves.append({"path": path, "before": before, "after": after, "role": role, "slot_id": slot_id})

    for index in range(1, 16):
        slot_id = f"solo_slot_{index:02d}"
        slot_path = PREFIX + "/KeySlots/" + slot_id
        torch_path = PREFIX + "/TorchMarkers/torch_" + slot_id
        slot = dom[slot_path]
        require(slot["class"] == "Part" and T.attributes(slot["properties"]["AttributesSerialize"]) == {"slot_id": slot_id}, "Unexpected slot identity")
        require(bytes.fromhex(slot["properties"]["Tags"][1]).decode().split("\0") == ["corn_key_slot"], "Unexpected slot tags")
        old = components(slot["properties"]["CFrame"])
        pole = components(dom[torch_path + "/Pole"]["properties"]["CFrame"])
        x = pole[0] if abs(pole[0]) >= 21 else math.copysign(21, pole[0])
        z = pole[2] - 4
        after = old.copy()
        after[0], after[2] = T.f32(x), T.f32(z)
        move(slot_path, after, "slot", slot_id)
        for part in ("Pole", "Flame"):
            path = torch_path + "/" + part
            target = components(dom[path]["properties"]["CFrame"])
            target[0], target[2] = T.f32(x), T.f32(z + 4)
            move(path, target, "torch", slot_id)
        delta = [after[0] - old[0], after[2] - old[2]]
        clusters.append({"slot_id": slot_id, "slot_path": slot_path, "torch_id": "torch_" + slot_id,
                         "torch_path": torch_path, "center": after[:3], "delta_xz": delta,
                         "potential_stump_hull_xz": [x-5, x+6.6, z-3, z+3]})
        if index in BARRELS:
            path = BARRELS[index]
            node = dom[path]
            props = node["properties"]
            require(node["class"] == "Part" and T.attributes(props["AttributesSerialize"]) == {}, "Legacy barrel attributes/class changed")
            require(bytes.fromhex(props["Tags"][1]).decode().split("\0") == ["corn_barrel"], "Legacy barrel tag changed")
            before = components(props["CFrame"])
            require(close([before[0]-old[0], before[1]-old[1], before[2]-old[2]], [2.8, 1.94, 0]), "Legacy barrel no longer matches its exact baseline slot")
            target = before.copy()
            target[0], target[2] = T.f32(before[0]+delta[0]), T.f32(before[2]+delta[1])
            move(path, target, "barrel", slot_id)
            barrel_bindings.append({"path": path, "parent": PREFIX + "/Props", "name": "LookoutBarrel",
                                    "tag": "corn_barrel", "slot_id": slot_id, "before": before, "after": target})
    require(len(moves) == 28 and sum(row["role"] == "slot" for row in moves) == 15
            and sum(row["role"] == "torch" for row in moves) == 10 and sum(row["role"] == "barrel" for row in moves) == 3,
            "Expected exactly 15 slot + 10 torch + 3 barrel changed CFrames")
    afters = {row["path"]: row["after"] for row in moves}
    guard_paths = {PREFIX, PREFIX + "/KeySlots", PREFIX + "/TorchMarkers", PREFIX + "/Props"}
    guard_paths.update(path for path in dom if path.startswith(PREFIX + "/KeySlots/") or path.startswith(PREFIX + "/TorchMarkers/"))
    guard_paths.update(row["path"] for row in moves)
    environmental = {PREFIX + "/FieldZone", PREFIX + "/Ground", PREFIX + "/PlayBounds"}
    environmental.update(path for path, node in dom.items() if path.startswith(PREFIX + "/CornerSpawns/") and node["class"] == "SpawnLocation")
    environmental.update(path for path, node in dom.items() if node["class"] in ("Part", "MeshPart") and
        (path.startswith(PREFIX + "/Props/") or path.startswith(PREFIX + "/EscapeGate/") or path.startswith(PREFIX + "/Boundaries/")))
    guard_paths.update(environmental)
    guards = []
    for path in sorted(guard_paths):
        node = dom[path]
        if path in environmental and path not in afters:
            # Exact immutable geometry used to prove clearances.
            fields = {key: T.typed(node["properties"][key]) for key in ("CFrame", "size", "CanCollide") if key in node["properties"]}
            if node["class"] == "SpawnLocation":
                fields.update({key: T.typed(node["properties"][key]) for key in ("Enabled", "Neutral")})
            guard = {"path": path, "class": node["class"], "properties": {T.ALIASES.get(key, key): value for key, value in fields.items()}}
        else:
            guard = T.node_guard(path, node, dom)
            # DOM duplicate suffixes are not actual Roblox names.
            guard["children"] = [name.split("#")[0] for name in guard["children"]]
            if "CFrame" in node["properties"] and path not in afters:
                guard["properties"]["CFrame"] = T.typed(node["properties"]["CFrame"])
        for key, value in list(guard["properties"].items()):
            if isinstance(value, dict) and value.get("type") == "Ref" and value.get("value") is None:
                guard["properties"][key] = {"nil_ref": True}
        guards.append(guard)
    field = components(dom[PREFIX + "/FieldZone"]["properties"]["CFrame"])
    require(close(field[3:], [1,0,0,0,1,0,0,0,1]), "Fixed horizontal field rotation changed")
    size = components(dom[PREFIX + "/FieldZone"]["properties"]["size"])
    spawn_points = [components(dom[path]["properties"]["CFrame"]) for path in environmental if dom[path]["class"] == "SpawnLocation"]
    colliders = []
    for path in environmental:
        props = dom[path]["properties"]
        if props.get("CanCollide", [None, "false"])[1] == "true" and path != PREFIX + "/Ground":
            colliders.append((path, bounds(afters.get(path, components(props["CFrame"])), components(props["size"]))))
    minimum = min(math.hypot(a["center"][0]-b["center"][0], a["center"][2]-b["center"][2]) for i, a in enumerate(clusters) for b in clusters[i+1:])
    require(minimum >= 72, "Cluster centers violate reinforcement separation")
    road_gap, props_gap, spawn_gap = math.inf, math.inf, math.inf
    for cluster in clusters:
        x, y, z = cluster["center"]
        hull = [(x-5, x+6.6), (y-1, y+9), (z-3, z+3)]
        road = min(abs(hull[0][0]), abs(hull[0][1])) - 10.5
        require(hull[0][0] * hull[0][1] > 0 and road >= 3, "Potential stump/steps enters road clearance")
        road_gap = min(road_gap, road)
        require(hull[0][0] >= field[0]-size[0]/2+8 and hull[0][1] <= field[0]+size[0]/2-8 and
                hull[2][0] >= field[2]-size[2]/2+8 and hull[2][1] <= field[2]+size[2]/2-8, "Cluster leaves field bounds")
        for spawn in spawn_points:
            distance = math.hypot(x-spawn[0], z-spawn[2]) - 7
            spawn_gap = min(spawn_gap, distance)
            require(distance >= 30, "Cluster near spawn")
        own_barrel = next((row["path"] for row in barrel_bindings if row["slot_id"] == cluster["slot_id"]), None)
        for path, box in colliders:
            if path == own_barrel:
                require(box[0][0] >= hull[0][0] and box[0][1] <= hull[0][1] and box[2][0] >= hull[2][0] and box[2][1] <= hull[2][1],
                        "Associated barrel outside its existing potential-stump footprint")
                continue
            distance = gap(hull, box)
            props_gap = min(props_gap, distance)
            require(distance >= 2.5, "Cluster hull too near collider: " + cluster["slot_id"] + " -> " + path)
        for other in clusters:
            if other is cluster:
                continue
            box = [(other["center"][0]-5, other["center"][0]+6.6), (0,1), (other["center"][2]-3, other["center"][2]+3)]
            require(gap(hull, box) >= 24, "Cluster hulls too close")
    require(BASELINE.read_bytes() == data, "Baseline changed during read")
    return {"version": 1, "baseline": {"path": str(BASELINE.relative_to(ROOT)).replace("\\", "/"), "bytes": len(data), "sha256": BASELINE_HASH},
            "parts": moves, "clusters": clusters, "barrel_bindings": barrel_bindings, "guards": guards,
            "summary": {"part_changes": 28, "slots": 15, "torch_parts_changed": 10, "barrels": 3,
                        "min_cluster_separation": minimum, "min_road_gap": road_gap, "min_props_gap": props_gap, "min_spawn_gap": spawn_gap,
                        "scope": "CFrame XZ only; no attrs/tags/instances/Sources/pivots/scene serialization. Own barrel is contained inside its existing potential-stump hull; foreign colliders require 2.5 studs. Static AABB proof; live physics/E/render acceptance separate."}}


def installer(manifest):
    moves = [{"path": row["path"], "before": {"type": "CoordinateFrame", "value": row["before"]},
              "after": {"type": "CoordinateFrame", "value": row["after"]}} for row in manifest["parts"]]
    bindings = [dict(row, before={"type": "CoordinateFrame", "value": row["before"]},
                     after={"type": "CoordinateFrame", "value": row["after"]}) for row in manifest["barrel_bindings"]]
    return '''-- Generated fixed CFrame-only clusters; accepted baseline a897bb52.
local run=game:GetService("RunService")
assert(run:IsStudio() and not run:IsRunning(),"Stop Children_of_corn Play first")
assert(not workspace:FindFirstChild("Asmr_Base") and not workspace:FindFirstChild("ASMR_Models"),"Wrong scene")
local map=workspace:FindFirstChild("CornMap")
assert(map and map:IsA("Model") and map:GetAttribute("corn_project_id")=="children_of_corn","Wrong project")
assert(not map:FindFirstChild("CornRoundRuntime"),"Unexpected runtime; nothing changed")
local barrelBindings=''' + T.lua(bindings) + '''
local function equal(a,b)
    if typeof(a)=="EnumItem" then
        a=a.Value
    end
    if typeof(a)~=typeof(b) then
        return false
    end
    if typeof(a)=="CFrame" then
        local x,y={a:GetComponents()},{b:GetComponents()}
        for i=1,12 do
            if math.abs(x[i]-y[i])>0.00001 then
                return false
            end
        end
        return true
    elseif typeof(a)=="Vector3" then
        return (a-b).Magnitude<0.00001
    elseif typeof(a)=="Color3" then
        return math.abs(a.R-b.R)<0.00001 and math.abs(a.G-b.G)<0.00001 and math.abs(a.B-b.B)<0.00001
    elseif type(a)=="number" then
        return math.abs(a-b)<0.00001
    end
    return a==b
end
local function resolve(path)
    for _,binding in barrelBindings do
        if binding.path==path then
            local found=nil
            local count=0
            for _,item in map.Props:GetChildren() do
                if item.Name==binding.name and item:IsA("BasePart") and item:HasTag(binding.tag) then
                    count+=1
                    if equal(item.CFrame,binding.before) or equal(item.CFrame,binding.after) then
                        assert(not found,"Ambiguous legacy barrel frame; nothing changed")
                        found=item
                    end
                end
            end
            assert(count==3,"Legacy barrel count/tag/class changed; nothing changed")
            return found
        end
    end
    local item=game
    for _,segment in string.split(path,"/") do
        item=item and item:FindFirstChild(segment)
    end
    return item
end
local guards=''' + T.lua(manifest["guards"]) + '''
local moves=''' + T.lua(moves) + '''
for _,entry in guards do
    local item=assert(resolve(entry.path),"Missing guarded cluster node; nothing changed: "..entry.path)
    assert(item.ClassName==entry.class,"Cluster class changed; nothing changed: "..entry.path)
    if entry.children then
        local names={}
        for _,child in item:GetChildren() do
            table.insert(names,child.Name)
        end
        table.sort(names)
        local expected=table.clone(entry.children)
        table.sort(expected)
        assert(#names==#expected,"Cluster topology changed; nothing changed: "..entry.path)
        for i,name in names do
            assert(name==expected[i],"Cluster child name changed; nothing changed")
        end
    end
    if entry.attributes then
        local count=0
        for key,value in item:GetAttributes() do
            count+=1
            assert(entry.attributes[key]==value,"Cluster attribute changed; nothing changed")
        end
        local expected=0
        for _ in entry.attributes do
            expected+=1
        end
        assert(count==expected,"Cluster attributes missing; nothing changed")
    end
    if entry.tags then
        local tags=item:GetTags()
        assert(#tags==#entry.tags,"Cluster tags changed; nothing changed")
        for _,tag in entry.tags do
            assert(item:HasTag(tag),"Cluster tag missing; nothing changed")
        end
    end
    for key,value in entry.properties do
        local current=item[key]
        if type(value)=="table" and value.nil_ref then
            value=nil
        elseif type(value)=="table" and value.reference then
            value=resolve(value.reference)
        end
        assert(equal(current,value),"Cluster/clearance property changed; nothing changed: "..entry.path.."."..key)
    end
end
local before,after=true,true
for _,entry in moves do
    local item=assert(resolve(entry.path),"Missing bound cluster part; nothing changed: "..entry.path)
    before=before and equal(item.CFrame,entry.before)
    after=after and equal(item.CFrame,entry.after)
end
assert(before or after,"Partial/manual cluster placement; nothing changed")
if after then
    return {changed=0,repeated=true,clusters=15,slots=15,torchParts=10,barrels=3}
end
local history=game:GetService("ChangeHistoryService")
history:SetWaypoint("Before Corn cluster bindings")
local changed={}
local ok,problem=pcall(function()
    for _,entry in moves do
        local item=assert(resolve(entry.path))
        table.insert(changed,{part=item,frame=item.CFrame})
        item.CFrame=entry.after
        -- CLUSTER_AFTER_WRITE
    end
end)
if not ok then
    for index=#changed,1,-1 do
        changed[index].part.CFrame=changed[index].frame
    end
    error("Cluster update rolled back: "..tostring(problem))
end
history:SetWaypoint("Installed Corn cluster bindings")
return {changed=#changed,repeated=false,clusters=15,slots=15,torchParts=10,barrels=3}
'''


def build(check=False):
    manifest = build_manifest()
    outputs = {OUTPUT: json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", INSTALLER: installer(manifest)}
    for path, text in outputs.items():
        if check:
            require(path.exists() and path.read_text(encoding="utf-8") == text, "Stale cluster output: " + str(path))
        else:
            path.write_text(text, encoding="utf-8")
    print(json.dumps(dict(manifest["summary"], checked=check, scene_written=False), ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    build(parser.parse_args().check)
