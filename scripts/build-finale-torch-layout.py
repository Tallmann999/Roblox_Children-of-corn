"""Build a fixed 27-torch/54-CFrame update from the immutable engine baseline.

No candidate input, live Studio calls or scene writes. --check only verifies the
checked-in manifest and installer against the immutable source bytes.
"""
import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / "place/Children_of_corn.before-finale-20261015.rbxl"
BASELINE_HASH = "9082169a7da5fed15cd962611777285213fce99f23de82f83e0f361a683ecf16"
PREFIX = "Workspace/CornMap/TorchMarkers"
MANIFEST = ROOT / "scripts/finale-torch-layout.json"
INSTALLER = ROOT / "scripts/install-finale-torches.luau"
SLOT_OFFSETS = [(-13, 7), (11, -12), (8, 11), (-10, -6), (-14, 9),
                (12, -15), (17, 5), (13, -8), (-9, -13), (-12, 14),
                (-11, -5), (7, 9), (15, -9), (-16, 6), (-8, 16)]
HOUSE_TARGETS = {"torch_HouseWest-1": (-132, -144.75), "torch_HouseWest1": (-120, -144.75),
                 "torch_HouseEast-1": (141, 72.25), "torch_HouseEast1": (153, 72.25),
                 "torch_HouseNorthWest-1": (-300, 156.25), "torch_HouseNorthWest1": (-288, 156.25)}
EXIT_TARGETS = {"road_exit_row_01": (-27, 408), "road_exit_row_03": (18, 374),
                "road_exit_row_05": (-22, 365), "road_exit_row_07": (31, 394)}
WALL_DELTAS = {"road_exit_wall_left": (-3, 0), "road_exit_wall_right": (5, 0)}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def f32(number):
    return struct.unpack("<f", struct.pack("<f", number))[0]


def components(value):
    return [f32(float(child[1])) for _, child in value[2]]


def attributes(value):
    data = bytes.fromhex(value[1])
    if not data:
        return {}
    offset = 0
    def count():
        nonlocal offset
        result = struct.unpack_from("<I", data, offset)[0]
        offset += 4
        return result
    def string():
        nonlocal offset
        size = count()
        result = data[offset:offset + size].decode("utf-8")
        offset += size
        return result
    result = {}
    for _ in range(count()):
        key = string()
        kind = data[offset]
        offset += 1
        require(key not in result, "Duplicate baseline attribute")
        if kind == 2:
            result[key] = string()
        elif kind == 3:
            result[key] = bool(data[offset])
            offset += 1
        elif kind == 6:
            result[key] = struct.unpack_from("<d", data, offset)[0]
            offset += 8
        else:
            raise ValueError("Unexpected torch attribute type: " + str(kind))
    require(offset == len(data), "Trailing baseline attribute bytes")
    return result


def typed(value):
    tag, text, _ = value
    if tag in ("Vector3", "CoordinateFrame", "Color3"):
        return {"type": tag, "value": components(value)}
    if tag == "Color3uint8":
        packed = int(text)
        return {"type": "Color3", "value": [((packed >> shift) & 255) / 255 for shift in (16, 8, 0)]}
    if tag == "bool":
        return text == "true"
    if tag == "token":
        return {"type": "Enum", "value": int(text)}
    if tag in ("float", "double", "int", "int64"):
        return float(text)
    if tag == "Ref":
        return {"type": "Ref", "value": None if text == "null" else text}
    require(tag == "string", "Unsupported guarded value: " + tag)
    return text


FIELDS = {
    "Folder": [],
    "Model": ["PrimaryPart", "ModelStreamingMode", "LevelOfDetail"],
    "Part": ["size", "Color3uint8", "shape", "Anchored", "CanCollide", "CanTouch", "CanQuery",
             "CastShadow", "Material", "MaterialVariantSerialized", "Reflectance", "Transparency",
             "CollisionGroup", "Locked", "Massless", "PivotOffset"],
    "Fire": ["Enabled", "heat_xml", "size_xml", "Color", "SecondaryColor", "TimeScale"],
    "PointLight": ["Enabled", "Brightness", "Range", "Color", "Shadows"],
}
ALIASES = {"size": "Size", "shape": "Shape", "Color3uint8": "Color", "MaterialVariantSerialized": "MaterialVariant",
           "heat_xml": "Heat", "size_xml": "Size"}


def node_guard(path, node, dom):
    props = node["properties"]
    fields = FIELDS[node["class"]]
    return {"path": path, "class": node["class"],
            "attributes": attributes(props["AttributesSerialize"]),
            "tags": sorted(x for x in bytes.fromhex(props["Tags"][1]).decode().split("\0") if x),
            "properties": {ALIASES.get(key, key): typed(props[key]) for key in fields if key in props},
            "children": sorted([child.rsplit("/", 1)[-1] for child in dom if child.rsplit("/", 1)[0] == path])}


def aabb(node):
    frame, size = components(node["properties"]["CFrame"]), components(node["properties"]["size"])
    extents = [sum(abs(frame[3 + axis * 3 + column]) * size[column] / 2 for column in range(3)) for axis in range(3)]
    return [(frame[axis] - extents[axis], frame[axis] + extents[axis]) for axis in range(3)]


def build_manifest():
    data = BASELINE.read_bytes()
    require(len(data) == 1015691 and hashlib.sha256(data).hexdigest() == BASELINE_HASH, "Immutable before-finale baseline changed")
    spec = importlib.util.spec_from_file_location("preservation", ROOT / "scripts/verify-scene-preservation.py")
    preservation = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(preservation)
    dom, _ = preservation.known_dom(BASELINE)
    torches = sorted(path for path, node in dom.items() if path.startswith(PREFIX + "/") and node["class"] == "Model")
    require(len(torches) == 27, "Expected exactly 27 original torch models")
    guards = [node_guard(path, node, dom) for path, node in sorted(dom.items()) if path == PREFIX or path.startswith(PREFIX + "/")]
    require(len(guards) == 136, "Unexpected original torch topology")
    barns = []
    for name in ("HouseWest", "HouseEast", "HouseNorthWest"):
        path = "Workspace/CornMap/Props/" + name
        model, body = dom[path], dom[path + "/SM_Bld_Barn_03"]
        require(model["class"] == "Model" and body["class"] == "MeshPart", "Expected fixed Barn03")
        require(model["properties"]["PrimaryPart"] == ["Ref", "null", []], "Unexpected Barn primary part")
        pivot = model["properties"]["WorldPivotData"]
        require(pivot[0] == "OptionalCoordinateFrame" and len(pivot[2]) == 1, "Expected saved Barn pivot")
        barn_guard = node_guard(path, model, dom)
        del barn_guard["properties"]["PrimaryPart"]  # nil is checked explicitly in the live preflight
        guards.append(barn_guard)
        barns.append({"path": path, "pivot": components(pivot[2][0][1]),
                      "body_path": path + "/SM_Bld_Barn_03", "body_frame": components(body["properties"]["CFrame"]),
                      "body_size": components(body["properties"]["size"])})
    parts, models, positions = [], [], []
    for path in torches:
        name = path.rsplit("/", 1)[-1]
        pole = components(dom[path + "/Pole"]["properties"]["CFrame"])
        if name.startswith("torch_solo_slot_"):
            index = int(name.rsplit("_", 1)[-1]) - 1
            dx, slot_z = SLOT_OFFSETS[index]
            dz = slot_z - 4  # exact old marker offset from its clearing centre
            require(8 <= math.hypot(dx, slot_z) <= 20, "Slot torch too near/far")
            kind = "clearing"
        elif name in HOUSE_TARGETS:
            target_x, target_z = HOUSE_TARGETS[name]
            dx, dz = target_x - pole[0], target_z - pole[2]
            kind = "house"
        elif name in EXIT_TARGETS:
            target_x, target_z = EXIT_TARGETS[name]
            dx, dz = target_x - pole[0], target_z - pole[2]
            kind = "exit_ground"
        else:
            require(name in WALL_DELTAS, "Unknown torch ID: " + name)
            dx, dz = WALL_DELTAS[name]
            kind = "exit_wall"
        model_attrs = attributes(dom[path]["properties"]["AttributesSerialize"])
        require(model_attrs["torch_id"] == name and model_attrs["CornTorchOwned"] is True, "Unexpected torch identity")
        models.append({"path": path, "world_pivot_data": dom[path]["properties"].get("WorldPivotData")})
        for part in ("Pole", "Flame"):
            part_path = path + "/" + part
            before = components(dom[part_path]["properties"]["CFrame"])
            after = before.copy()
            after[0], after[2] = f32(before[0] + dx), f32(before[2] + dz)
            require(before != after and before[1] == after[1] and before[3:] == after[3:], "Only XZ translation permitted")
            parts.append({"path": part_path, "torch_id": name, "part": part, "before": before, "after": after,
                          "delta_xz": [dx, dz]})
        positions.append({"torch_id": name, "kind": kind, "x": f32(pole[0] + dx), "z": f32(pole[2] + dz)})
    colliders = {path: aabb(node) for path, node in dom.items() if path.startswith("Workspace/CornMap/Props/")
                 and node["class"] in ("Part", "MeshPart") and node["properties"].get("CanCollide", [None, "false"])[1] == "true"}
    spawns = [components(node["properties"]["CFrame"]) for path, node in dom.items()
              if path.startswith("Workspace/CornMap/CornerSpawns/") and node["class"] == "SpawnLocation"]
    require(len(spawns) == 4, "Expected original four corner spawns")
    minimum_clearance = math.inf
    for point in positions:
        if point["kind"] == "exit_wall":
            continue
        x, z = point["x"], point["z"]
        require(abs(x) <= 410 and abs(z) <= 410 and abs(x) >= 10, "Ground torch intersects field edge/road corridor")
        require(min(math.hypot(x - spawn[0], z - spawn[2]) for spawn in spawns) >= 30, "Torch near corner spawn")
        for path, bounds in colliders.items():
            dx = max(bounds[0][0] - x, 0, x - bounds[0][1])
            dz = max(bounds[2][0] - z, 0, z - bounds[2][1])
            gap = math.hypot(dx, dz)
            require(gap >= (1.25 if point["kind"] == "house" else 2.5), "Torch too close to saved prop: " + point["torch_id"] + " -> " + path)
            minimum_clearance = min(minimum_clearance, gap)
    require(len(parts) == 54 and len({row["path"] for row in parts}) == 54, "Expected 54 fixed CFrame targets")
    require(BASELINE.read_bytes() == data, "Immutable baseline changed during read")
    return {"version": 2, "baseline": {"path": str(BASELINE.relative_to(ROOT)).replace("\\", "/"), "bytes": len(data), "sha256": BASELINE_HASH},
            "cframe_properties_count": 54, "parts": parts, "models": models, "guards": guards, "barn_bindings": barns,
            "summary": {"models": 27, "ground": 25, "wall": 2, "part_changes": 54, "yaw_changes": 0,
                        "barn_pair_fixed_offset": {"x": [-6, 6], "z": -11.75, "scope": "Fixed baseline entrance positions; moved barns refuse, no runtime auto-follow."},
                        "minimum_saved_props_aabb_gap": minimum_clearance, "positions": positions,
                        "scope": "Saved baseline AABBs only; actual live clearances/physics require Studio acceptance."}}


def lua(value):
    if value is None:
        return "nil"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, (int, float)):
        require(math.isfinite(value), "Non-finite generated number")
        return repr(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return "{" + ",".join(lua(x) for x in value) + "}"
    if "type" in value and "value" in value:
        kind, payload = value["type"], value["value"]
        if kind == "Enum":
            return lua(payload)
        if kind == "Ref":
            return "{reference=" + lua(payload) + "}"
        return {"Vector3": "Vector3.new", "CoordinateFrame": "CFrame.new", "Color3": "Color3.new"}[kind] + "(" + ",".join(lua(x) for x in payload) + ")"
    return "{" + ",".join("[" + lua(key) + "]=" + lua(item) for key, item in value.items()) + "}"


def installer(manifest):
    rows = [{"path": row["path"], "before": {"type": "CoordinateFrame", "value": row["before"]},
             "after": {"type": "CoordinateFrame", "value": row["after"]}} for row in manifest["parts"]]
    barns = [{"path": row["path"], "pivot": {"type": "CoordinateFrame", "value": row["pivot"]},
              "body_path": row["body_path"], "body_frame": {"type": "CoordinateFrame", "value": row["body_frame"]},
              "body_size": {"type": "Vector3", "value": row["body_size"]}} for row in manifest["barn_bindings"]]
    return '''-- Generated fixed 27-torch layout v2; no Sources/Model pivots/other scene properties.
-- Immutable baseline SHA256: ''' + BASELINE_HASH + '''
local run=game:GetService("RunService")
assert(run:IsStudio() and not run:IsRunning(),"Stop Children_of_corn Play first")
assert(not workspace:FindFirstChild("Asmr_Base") and not workspace:FindFirstChild("ASMR_Models"),"Wrong scene")
local map=workspace:FindFirstChild("CornMap")
assert(map and map:IsA("Model") and map:GetAttribute("corn_project_id")=="children_of_corn","Wrong project")
local function resolve(path)
    local item=game
    for _,segment in string.split(path,"/") do item=item and item:FindFirstChild(segment) end
    return item
end
local function equal(a,b)
    if typeof(a)=="EnumItem" then a=a.Value end
    if type(b)=="table" and b.reference then return a==resolve(b.reference) end
    if typeof(a)~=typeof(b) then return false end
    if typeof(a)=="CFrame" then
        local x,y={a:GetComponents()},{b:GetComponents()}
        for i=1,12 do if math.abs(x[i]-y[i])>0.00001 then return false end end
        return true
    elseif typeof(a)=="Vector3" then return (a-b).Magnitude<0.00001
    elseif typeof(a)=="Color3" then return math.abs(a.R-b.R)<0.00001 and math.abs(a.G-b.G)<0.00001 and math.abs(a.B-b.B)<0.00001
    elseif type(a)=="number" then return math.abs(a-b)<0.00001 end
    return a==b
end
local guards=''' + lua(manifest["guards"]) + '''
local moves=''' + lua(rows) + '''
local barns=''' + lua(barns) + '''
for _,entry in guards do
    local item=assert(resolve(entry.path),"Missing owned torch node; nothing changed: "..entry.path)
    assert(item.ClassName==entry.class,"Torch class changed; nothing changed: "..entry.path)
    local children=item:GetChildren()
    assert(#children==#entry.children,"Torch children changed; nothing changed: "..entry.path)
    for _,name in entry.children do assert(item:FindFirstChild(name),"Torch child renamed; nothing changed") end
    local attrs=item:GetAttributes()
    local count=0
    for key,value in attrs do count+=1 assert(entry.attributes[key]==value,"Torch attribute changed; nothing changed: "..entry.path) end
    local expectedCount=0 for _ in entry.attributes do expectedCount+=1 end
    assert(count==expectedCount,"Torch attributes missing; nothing changed: "..entry.path)
    local tags=item:GetTags()
    assert(#tags==#entry.tags,"Torch tags changed; nothing changed: "..entry.path)
    for _,tag in entry.tags do assert(item:HasTag(tag),"Torch tag missing; nothing changed") end
    for key,value in entry.properties do assert(equal(item[key],value),"Torch property changed; nothing changed: "..entry.path.."."..key) end
end
for _,entry in barns do
    local barn=assert(resolve(entry.path))
    local body=assert(resolve(entry.body_path))
    assert(barn.PrimaryPart==nil and equal(barn:GetPivot(),entry.pivot),"Barn pivot moved; nothing changed: "..entry.path)
    assert(body:IsA("MeshPart") and equal(body.CFrame,entry.body_frame) and equal(body.Size,entry.body_size),"Barn geometry moved; nothing changed: "..entry.path)
end
local before,after=true,true
for _,entry in moves do
    local part=assert(resolve(entry.path))
    before=before and equal(part.CFrame,entry.before)
    after=after and equal(part.CFrame,entry.after)
end
assert(before or after,"Partial/manual torch placement; nothing changed")
if after then return {changed=0,repeated=true,models=27,parts=54} end
local history=game:GetService("ChangeHistoryService")
history:SetWaypoint("Before Corn finale torch layout")
local changed={}
local ok,problem=pcall(function()
    for _,entry in moves do
        local part=assert(resolve(entry.path))
        table.insert(changed,{part=part,frame=part.CFrame})
        part.CFrame=entry.after
        -- FINALE_TORCH_AFTER_WRITE
    end
end)
if not ok then
    for index=#changed,1,-1 do changed[index].part.CFrame=changed[index].frame end
    error("Finale torch layout rolled back: "..tostring(problem))
end
history:SetWaypoint("Installed Corn finale torch layout")
return {changed=#changed,repeated=false,models=27,parts=54}
'''


def build(check=False):
    manifest = build_manifest()
    outputs = {MANIFEST: json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", INSTALLER: installer(manifest)}
    for path, content in outputs.items():
        if check:
            require(path.exists() and path.read_text(encoding="utf-8") == content, "Stale fixed torch output: " + str(path))
        else:
            path.write_text(content, encoding="utf-8")
    require(hashlib.sha256(BASELINE.read_bytes()).hexdigest() == BASELINE_HASH, "Immutable baseline changed")
    print(json.dumps({"checked": check, "manifest": str(MANIFEST), "installer": str(INSTALLER),
                      "models": 27, "part_cframes": 54, "baseline_unchanged": True,
                      "minimum_saved_props_gap": manifest["summary"]["minimum_saved_props_aabb_gap"], "scene_written": False}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    build(args.check)
