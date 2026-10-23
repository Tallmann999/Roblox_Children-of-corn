"""Independent, read-only audit of the authored B corn subtree.

Expectations are regenerated from the immutable c91 scene and the reviewed native
builder, never from candidate placements. The caller may stream canonical DOM
records as (path, node) pairs to avoid keeping 70,664 MeshParts in Python memory.
No RBXL is serialized, rewritten or promoted by this helper.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import re
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".artifacts/playtests/2026-10-23-B-manual-authoring"
BASELINE_SHA256 = "c91efe74d1750095eac19390800192ad03b264d7a99de46cf21d170fcb4ed31f"
CANDIDATE_SHA256 = "4c5c0c5454da2689996babca4a88b66256240ebb2fb0ac7aa2f787b2ecd8227a"
BUILD_SHA256 = "b17dfb535f8fb5adc82af7da2706521daf77fb259b755bfb7786e7375cd40ae0"
PREFIX = "Workspace/CornMap/CornAuthoring"
spec = importlib.util.spec_from_file_location("manual_corn_helpers", ROOT / "scripts/verify-B-green-variants-copy.py")
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)
require, f32 = v.require, v.h.m.f32


REGENERATE = r'''
local fs, serde, r, process = require("@lune/fs"), require("@lune/serde"), require("@lune/roblox"), require("@lune/process")
local input = serde.decode("json", fs.readFile(process.args[1]))
local V, CF = r.Vector3, r.CFrame
local methods, mt = {}, {}
local base = {Part=true,MeshPart=true,SpawnLocation=true,WedgePart=true,UnionOperation=true}
function methods:IsA(class) return self.ClassName==class or (class=="BasePart" and base[self.ClassName]==true) end
function methods:GetChildren() return table.clone(self._children) end
function methods:GetDescendants()
 local out={}; local function walk(node) for _,c in node._children do table.insert(out,c);walk(c) end end;walk(self);return out
end
function methods:GetAttribute(key) return self._attributes[key] end
function methods:SetAttribute(key,value) self._attributes[key]=value end
function methods:HasTag(key) return self._tags[key]==true end
function methods:FindFirstChild(name,recursive)
 for _,c in self._children do if c.Name==name then return c end end
 if recursive then for _,c in self._children do local found=c:FindFirstChild(name,true);if found then return found end end end
end
function methods:GetFullName() return if self._parent then self._parent:GetFullName().."."..self.Name else self.Name end
function methods:IsDescendantOf(root) local p=self._parent;while p do if p==root then return true end;p=p._parent end;return false end
mt.__index=function(self,key)
 if key=="Parent" then return rawget(self,"_parent") end
 if key=="Position" then return self.CFrame.Position end
 return methods[key] or self:FindFirstChild(key)
end
mt.__newindex=function(self,key,value)
 if key=="Parent" then
  local old=rawget(self,"_parent");if old then for i,c in old._children do if c==self then table.remove(old._children,i);break end end end
  rawset(self,"_parent",value);if value then table.insert(value._children,self) end
 else rawset(self,key,value) end
end
local function new(class)
 return setmetatable({ClassName=class,Name=class,_children={},_attributes={},_tags={},CFrame=CF.identity,Size=V.new(1,1,1)},mt)
end
local objects={}
for _,row in input.nodes do
 local o=new(row.class);o.Name=row.name
 if row.frame then o.CFrame=CF.new(table.unpack(row.frame)) end
 if row.size then o.Size=V.new(table.unpack(row.size)) end
 for key,value in row.attributes do o._attributes[key]=value end
 for _,tag in row.tags do o._tags[tag]=true end
 objects[row.path]=o
end
for _,row in input.nodes do if row.parent and objects[row.parent] then objects[row.path].Parent=objects[row.parent] end end
local map=assert(objects["Workspace/CornMap"])
local game={GetService=function(_,name)
 if name=="HttpService" then return {JSONDecode=function(_,text) return serde.decode("json",text) end} end
 return {IsClient=function() return false end}
end}
local function load(source,environment)
 local fn=assert(loadstring(source));setfenv(fn,setmetatable(environment,{__index=getfenv()}));return fn()
end
local common={game=game,Vector3=V,Vector2=r.Vector2,CFrame=CF,Color3=r.Color3,Enum=r.Enum,Instance={new=new},task={wait=function() end}}
local beds=load(input.sources.beds,common)
local layoutSource,n=input.sources.layout:gsub('assert%(matches, "B clearances changed; regenerate the guarded green%-bed plan"%)','assert(#boxes==188 and #circles==19,"Immutable clearance inventory differs")')
assert(n==1,"Frozen signature spelling changed")
local environment=table.clone(common);environment.script={Parent={GreenBedLayout={}}};environment.require=function() return beds end
-- Conservative spatial indices change only which provably distant clearances
-- are skipped. The original point-in-box/circle arithmetic remains untouched.
local function indexRectangle(index,value,x,z,hx,hz)
 for bx=math.floor((x-hx-0.0001)/24),math.floor((x+hx+0.0001)/24) do
  for bz=math.floor((z-hz-0.0001)/24),math.floor((z+hz+0.0001)/24) do
   local key=bx..":"..bz;index[key]=index[key] or {};table.insert(index[key],value)
  end
 end
end
local function lookup(index,point) return index[math.floor(point.X/24)..":"..math.floor(point.Z/24)] or {} end
local clearanceIndices={}
local function indices(exclusions)
 if not clearanceIndices[exclusions] then
  local boxes,circles={},{}
  for _,b in exclusions.Boxes do
   local cf,h=b.Frame,b.HalfSize
   indexRectangle(boxes,b,cf.X,cf.Z,math.abs(cf.RightVector.X)*h.X+math.abs(cf.LookVector.X)*h.Y,
    math.abs(cf.RightVector.Z)*h.X+math.abs(cf.LookVector.Z)*h.Y)
  end
  for _,c in exclusions.Circles do indexRectangle(circles,c,c.Center.X,c.Center.Z,c.Radius,c.Radius) end
  clearanceIndices[exclusions]={boxes,circles}
 end
 return clearanceIndices[exclusions]
end
environment.cornBoxes=function(point,exclusions) return lookup(indices(exclusions)[1],point) end
environment.cornCircles=function(point,exclusions) return lookup(indices(exclusions)[2],point) end
local replacements
layoutSource,replacements=layoutSource:gsub("for _, box in exclusions%.Boxes do","for _, box in cornBoxes(position, exclusions) do");assert(replacements==1)
layoutSource,replacements=layoutSource:gsub("for _, circle in exclusions%.Circles do","for _, circle in cornCircles(position, exclusions) do");assert(replacements==1)
local layout=load(layoutSource,environment)
local descriptions={}
for index,row in input.descriptions do
 descriptions[index]={size=V.new(table.unpack(row.size)),rootOffset=V.new(table.unpack(row.offset)),sourceHash=row.hash}
end
local geometry={Describe=function(key) return descriptions[tonumber(key:match("%d+"))+1] end}
environment=table.clone(common);environment.script={Parent={CornGreenGeometry={}}};environment.require=function() return geometry end
local appearance=load(input.sources.appearance,environment)
local itemModels=load(input.sources.items,common)
local old=layout.ReadExclusions(map,map.FieldZone)
local boxes,circles={},{}
local function box(part,padding)
 local half=part.Size/2;local cf=part.CFrame
 local hx=math.abs(cf.RightVector.X)*half.X+math.abs(cf.UpVector.X)*half.Y+math.abs(cf.LookVector.X)*half.Z+padding
 local hz=math.abs(cf.RightVector.Z)*half.X+math.abs(cf.UpVector.Z)*half.Y+math.abs(cf.LookVector.Z)*half.Z+padding
 table.insert(boxes,{x=cf.X,z=cf.Z,hx=hx,hz=hz})
end
for _,part in map.NoCornZones.Maze02Masks:GetChildren() do box(part,0) end
for _,part in map.Props:GetDescendants() do
 if part:IsA("BasePart") and (part:GetAttribute("CornFarmMeshOwned")==true or part.Parent==map.Props or part:IsDescendantOf(map.Props.VillageRoad)) then box(part,0.5) end
end
for _,part in map.CornerSpawns:GetChildren() do box(part,1) end
box(map.EscapeGate.Door,3);box(map.EscapeGate.ApproachClearance,0)
local ground=map.Ground.Position.Y+map.Ground.Size.Y/2
for _,slot in map.KeySlots:GetChildren() do
 local stump=new("Model");local pos=V.new(slot.Position.X+3.6,ground,slot.Position.Z)
 itemModels.Stump(stump,CF.new(pos+V.new(0,4,0)))
 for _,part in stump:GetDescendants() do if part:IsA("BasePart") then box(part,0.35) end end
 table.insert(circles,{x=slot.Position.X,z=slot.Position.Z,r2=2.2*2.2})
end
assert(#boxes==234,"Independent box count differs")
local newBoxIndex,newCircleIndex={},{}
for _,b in boxes do indexRectangle(newBoxIndex,b,b.x,b.z,b.hx,b.hz) end
for _,c in circles do indexRectangle(newCircleIndex,c,c.x,c.z,math.sqrt(c.r2),math.sqrt(c.r2)) end
local function excluded(point)
 for _,b in lookup(newBoxIndex,point) do if math.abs(point.X-b.x)<=b.hx and math.abs(point.Z-b.z)<=b.hz then return true end end
 for _,c in lookup(newCircleIndex,point) do if (point.X-c.x)^2+(point.Z-c.z)^2<=c.r2 then return true end end
 return false
end
local result={rows={},boxes=#boxes,previous=0,filled=0,removed=0,chunks={}}
local minC,maxC,minR,maxR=layout.GetCellBounds(map.FieldZone)
for column=minC,maxC do for row=minR,maxR do
 local p=layout.CellPosition(map.FieldZone,column,row);local existed=not layout.IsExcluded(p,old)
 if existed then result.previous+=1 end
 local accepted=false
 if not excluded(p) then
  if existed then p=layout.TrailEdgePosition(p,old) end
  if not excluded(p) then
   p=V.new(p.X,beds.GetHeight(p) or ground,p.Z)
   local variety=appearance.Variety(column,row);local description=descriptions[variety]
   local part=new("MeshPart");part.Size=description.size
   part:SetAttribute("CornGreenOriginal",true);part:SetAttribute("corn_project_id","children_of_corn")
   part:SetAttribute("HarvestRootOffset",description.rootOffset);part:SetAttribute("CornGreenTemplateSize",description.size)
   layout.ApplyVariation(part,column,row)
   local pivot=appearance.DetailedPivot(part,p,layout.CellYaw(column,row))
   table.insert(result.rows,{column,row,variety,{pivot:GetComponents()},{part.Size.X,part.Size.Y,part.Size.Z}})
   result.chunks[math.floor(column/12)..":"..math.floor(row/12)]=true
   if not existed then result.filled+=1 end;accepted=true
  end
 end
 if existed and not accepted then result.removed+=1 end
end end
require("@lune/stdio").write(serde.encode("json",result))
'''


def components(value):
    return [f32(float(row[1][1])) for row in value[2]]


def text_source(before, name):
    node = before[name]
    require(node["class"] == "ModuleScript", "Immutable module class differs: " + name)
    return node["properties"]["Source"][1].replace("\r\n", "\n")


def description_data(before):
    original = next(node for node in before.values() if node["class"] == "MeshPart"
                    and "104111861186519" in json.dumps(node["properties"].get("MeshContent")))
    size = components(original["properties"]["size"])
    appearance = text_source(before, "ReplicatedStorage/GameShared/Game/CornAppearance")
    attribute_size = [f32(float(value)) for value in re.search(r"EXPECTED_SIZE = Vector3\.new\(([^)]+)\)", appearance)[1].split(",")]
    descriptions = [{"size": [size[0], 8, size[2]], "attribute_size": attribute_size, "offset": [0, 4, 0],
                     "hash": "259fbe167d4c0a24e6813282a5f3026d582b67d7af1f701bad39bed706a193df"}]
    for index in range(1, 4):
        source = text_source(before, f"ReplicatedStorage/GameShared/Game/CornGreenGeometryData/Var{index:02}")
        data = json.loads(re.search(r"\[==\[(.*?)\]==\]", source, re.S)[1])
        descriptions.append({"size": [f32(x) for x in data["bounds"]["size"]],
                             "offset": [f32(x) for x in data["bbox_center_from_root_studs"]],
                             "hash": data["exported_fbx_sha256"]})
    return descriptions


def convex_mass_metadata(positions):
    """Integrate the convex hull of immutable float32 mesh vertices.

    Roblox retains mesh-space hull mass properties even for Box collision.
    This calculation uses no candidate data or fitted coefficients: an
    incremental oriented hull followed by exact tetrahedron moment formulas.
    Values are rounded once to the engine's serialized float32 fields.
    """
    points = list(dict.fromkeys(tuple(f32(x) for x in row) for row in positions))

    def sub(a, b):
        return tuple(x - y for x, y in zip(a, b))

    def dot(a, b):
        return sum(x * y for x, y in zip(a, b))

    def cross(a, b):
        return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])

    def determinant(a, b, c):
        return dot(a, cross(b, c))

    a = min(range(len(points)), key=lambda i: points[i][0])
    b = max(range(len(points)), key=lambda i: points[i][0])
    line = sub(points[b], points[a])
    c = max(range(len(points)), key=lambda i: dot(cross(sub(points[i], points[a]), line),
                                                 cross(sub(points[i], points[a]), line)))
    normal = cross(sub(points[b], points[a]), sub(points[c], points[a]))
    d = max(range(len(points)), key=lambda i: abs(dot(normal, sub(points[i], points[a]))))
    inside = tuple(sum(points[k][axis] for k in (a, b, c, d))/4 for axis in range(3))

    def face(i, j, k):
        return (i, j, k) if determinant(sub(points[j], points[i]), sub(points[k], points[i]),
                                       sub(inside, points[i])) < 0 else (i, k, j)

    faces = [face(a, b, c), face(a, d, b), face(a, c, d), face(b, d, c)]
    for i, point in enumerate(points):
        visible = []
        for triangle in faces:
            normal = cross(sub(points[triangle[1]], points[triangle[0]]),
                           sub(points[triangle[2]], points[triangle[0]]))
            # Numerical degeneracy handling affects hull membership only;
            # the final saved values still require exact float32 equality.
            if dot(normal, sub(point, points[triangle[0]])) > 1e-8 * math.sqrt(dot(normal, normal)):
                visible.append(triangle)
        if not visible:
            continue
        edges = {}
        for j, k, l in visible:
            for start, end in ((j, k), (k, l), (l, j)):
                key = tuple(sorted((start, end)))
                if key in edges:
                    edges.pop(key)
                else:
                    edges[key] = (start, end)
        faces = [triangle for triangle in faces if triangle not in visible] + [
            face(start, end, i) for start, end in edges.values()]
    edge_uses = {}
    for triangle in faces:
        for j, k in zip(triangle, triangle[1:]+triangle[:1]):
            key = tuple(sorted((j, k)))
            edge_uses[key] = edge_uses.get(key, 0) + 1
    require(all(count == 2 for count in edge_uses.values()), "Independent convex hull is not closed")
    volume, first = 0.0, [0.0]*3
    second = [[0.0]*3 for _ in range(3)]
    for triangle in faces:
        q = [points[index] for index in triangle]
        tetra_volume = determinant(*q)/6
        volume += tetra_volume
        sums = [sum(row[axis] for row in q) for axis in range(3)]
        for i in range(3):
            first[i] += tetra_volume*sums[i]/4
            for j in range(3):
                second[i][j] += tetra_volume*(sum(row[i]*row[j] for row in q) + sums[i]*sums[j])/20
    require(volume > 0, "Independent convex hull has no positive volume")
    center = [value/volume for value in first]
    centered = [[second[i][j]-volume*center[i]*center[j] for j in range(3)] for i in range(3)]
    return {"InitialSize": [f32(max(row[i] for row in points)-min(row[i] for row in points)) for i in range(3)],
            "UnscaledVolume": f32(volume), "UnscaledCofm": list(map(f32, center)),
            "UnscaledVolInertiaDiags": list(map(f32, [centered[1][1]+centered[2][2],
                centered[0][0]+centered[2][2], centered[0][0]+centered[1][1]])),
            "UnscaledVolInertiaOffDiags": list(map(f32, [-centered[0][1], -centered[0][2], -centered[1][2]]))}


def expected_property_templates(before):
    """Complete defaults derive from accepted objects and explicit builder writes."""
    original = next(node for node in before.values() if node["class"] == "MeshPart"
                    and "104111861186519" in json.dumps(node["properties"].get("MeshContent")))
    metadata = [None]
    for index in range(1, 4):
        source = text_source(before, f"ReplicatedStorage/GameShared/Game/CornGreenGeometryData/Var{index:02}")
        data = json.loads(re.search(r"\[==\[(.*?)\]==\]", source, re.S)[1])
        metadata.append(convex_mass_metadata(data["positions"]))
    return original["properties"], before["Workspace/CornMap/EditorFieldOverview"]["properties"], \
        before["Workspace/CornMap/Props/VillageRoad"]["properties"], metadata


def validate_default_properties(props, template, separately_validated, path):
    # Every other property, including previously unexamined hidden metadata,
    # must exactly match the independently accepted default/template object.
    require(set(props) == set(template), "New authored property inventory differs: " + path)
    for name, expected in template.items():
        if name not in separately_validated | {"UniqueId", "HistoryId"}:
            require(v.same(props[name], expected), "Unexplained authored property: " + path + "/" + name)


def regenerate(before):
    require(len(before) == 6056, "Immutable baseline must contain the complete 6056-object graph")
    info = json.loads((OUT / "baseline.json").read_bytes())
    require(info["scene_files"]["B"]["sha256"] == BASELINE_SHA256, "Wrong independent baseline")
    require(hashlib.sha256((OUT / "native-build.luau").read_bytes()).hexdigest() == BUILD_SHA256,
            "Reviewed native builder changed")
    actual_sources = {path: node for path, node in before.items() if "Source" in node["properties"]}
    require(set(actual_sources) == set(info["expected_sources"]), "Immutable Source inventory differs")
    for path, entry in info["expected_sources"].items():
        raw = actual_sources[path]["properties"]["Source"][1].replace("\r\n", "\n")
        require(actual_sources[path]["class"] == entry["class"] and hashlib.sha256(raw.encode()).hexdigest() == entry["sha256"],
                "Immutable Source pin differs: " + path)
    nodes = []
    for path, node in before.items():
        if path != "Workspace" and not path.startswith("Workspace/CornMap"):
            continue
        props = node["properties"]
        attrs = v.h.decode_attributes(props["AttributesSerialize"])
        row = {"path": path, "parent": path.rpartition("/")[0], "class": node["class"],
               "name": props["Name"][1], "attributes": {k: entry["value"] for k, entry in attrs.items()},
               "tags": bytes.fromhex(props["Tags"][1]).decode().split("\0") if props["Tags"][1] else []}
        # Only scalar attributes participate in the old layout's ownership tests.
        row["attributes"] = {k: val for k, val in row["attributes"].items() if not isinstance(val, dict)}
        if "CFrame" in props:
            row["frame"] = components(props["CFrame"])
        if "size" in props:
            row["size"] = components(props["size"])
        nodes.append(row)
    sources = {
        "layout": text_source(before, "ReplicatedStorage/GameShared/Game/CornLayout"),
        "beds": text_source(before, "ReplicatedStorage/GameShared/Game/GreenBedLayout"),
        "appearance": text_source(before, "ReplicatedStorage/GameShared/Game/CornAppearance"),
        "items": text_source(before, "ServerScriptService/GameServer/Game/ItemModels"),
    }
    for name, path in (("layout", "ReplicatedStorage/GameShared/Game/CornLayout"),
                       ("beds", "ReplicatedStorage/GameShared/Game/GreenBedLayout"),
                       ("appearance", "ReplicatedStorage/GameShared/Game/CornAppearance"),
                       ("items", "ServerScriptService/GameServer/Game/ItemModels")):
        require(hashlib.sha256(sources[name].encode()).hexdigest() == info["expected_sources"][path]["sha256"],
                "Frozen Source pin differs: " + path)
    descriptions = description_data(before)
    payload = {"nodes": nodes, "sources": sources, "descriptions": descriptions}
    with tempfile.TemporaryDirectory(prefix="corn-independent-grid-") as directory:
        directory = Path(directory)
        program, data = directory / "regenerate.luau", directory / "baseline.json"
        program.write_text(REGENERATE, encoding="utf-8")
        data.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
        result = subprocess.run([str(v.r.p.LUNE), "run", str(program), str(data)],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    expected = json.loads(result.stdout)
    require((len(expected["rows"]), len(expected["chunks"]), expected["boxes"], expected["previous"], expected["filled"], expected["removed"])
            == (70664, 576, 234, 58942, 11725, 3), "Independent native-plan counts differ: " + str({k: expected[k] for k in ("boxes", "previous", "filled", "removed")}))
    return expected, descriptions


def validate(before, after_iterable, expected=None):
    """Validate streamed corn nodes; raises on every unexplained discrepancy."""
    expected, descriptions = regenerate(before) if expected is None else expected
    part_defaults, folder_defaults, model_defaults, mass_metadata = expected_property_templates(before)
    wanted = {(row[0], row[1]): row for row in expected["rows"]}
    seen, chunks, folder_count = set(), set(), 0
    pose_differences = []
    for path, node in after_iterable:
        if path != PREFIX and not path.startswith(PREFIX + "/"):
            continue
        props = node["properties"]
        require(props.get("Name") == ["string", path.rsplit("/", 1)[-1], []], "Authored node name differs: " + path)
        attrs = v.h.decode_attributes(props["AttributesSerialize"])
        values = {key: row["value"] for key, row in attrs.items()}
        if path == PREFIX:
            root_attrs = {"corn_project_id": "children_of_corn", "BManualAuthoringVersion": 1, "Ready": True, "InitialPlantCount": 70664}
            require(node["class"] == "Folder" and set(attrs) == set(root_attrs)
                    and all(v.h.attribute_matches(attrs[k], value) for k, value in root_attrs.items()), "Author source root class/attributes differ")
            folder_count += 1
            validate_default_properties(props, folder_defaults, {"Name", "AttributesSerialize"}, path)
            continue
        if node["class"] == "Model":
            match = re.fullmatch(re.escape(PREFIX) + r"/Chunk_(-?\d+)_(-?\d+)", path)
            require(match is not None, "Unexpected nested corn Model: " + path)
            key = f"{int(match[1])}:{int(match[2])}"
            require(key in expected["chunks"] and key not in chunks, "Unknown/duplicate corn chunk: " + path)
            chunk_attrs = {"corn_project_id": "children_of_corn", "BManualAuthoringVersion": 1}
            require(set(attrs) == set(chunk_attrs) and all(v.h.attribute_matches(attrs[k], value) for k, value in chunk_attrs.items()), "Chunk attributes differ")
            require(props["ModelStreamingMode"][0] == "token" and props["ModelStreamingMode"][1] == "1", "Corn chunks must remain Atomic")
            validate_default_properties(props, model_defaults, {"Name", "AttributesSerialize", "ModelStreamingMode"}, path)
            chunks.add(key)
            continue
        require(node["class"] == "MeshPart", "Foreign authored corn child: " + path)
        match = re.fullmatch(re.escape(PREFIX) + r"/Chunk_(-?\d+)_(-?\d+)/Corn_(-?\d+)_(-?\d+)", path)
        require(match is not None, "Unexpected corn name/parent: " + path)
        column, row = int(match[3]), int(match[4])
        key = (column, row)
        require(key in wanted and key not in seen, "Extra/duplicate cell: " + path)
        require((column // 12, row // 12) == (int(match[1]), int(match[2])), "Wrong source chunk: " + path)
        seen.add(key)
        record = wanted[key]
        variety, frame, size = record[2:]
        desc = descriptions[variety - 1]
        expected_attributes = {"corn_project_id": "children_of_corn", "CornPlantTemplateOwned": True,
            "CornGreenOriginal": True, "CornGreenTemplateOwned": True, "CornGreenTemplateVersion": 2,
            "CornGreenSourceSHA256": desc["hash"], "CornGreenVariety": variety, "CornGreenLod": "Near",
            "HarvestRootOffset": {"kind": "Vector3", "value": desc["offset"]},
            "CornGreenTemplateSize": {"kind": "Vector3", "value": desc.get("attribute_size", desc["size"])},
            "CornAuthorColumn": column, "CornAuthorRow": row, "CornAuthorPlant": True}
        require(set(attrs) == set(expected_attributes) and all(v.h.attribute_matches(attrs[k], value) for k, value in expected_attributes.items()),
                "Authored corn attributes differ: " + path)
        require(components(props["size"]) == [f32(x) for x in size], "Deterministic authored height/size differs: " + path)
        actual_frame = components(props["CFrame"])
        if actual_frame != [f32(x) for x in frame]:
            if len(pose_differences) < 10:
                pose_differences.append({"path": path, "actual": actual_frame, "regenerated": frame,
                                         "max_error": max(abs(a-b) for a,b in zip(actual_frame,frame))})
        for property_name, expected_value in {"Anchored": True, "CanCollide": False, "CanTouch": False,
                "CanQuery": False, "CastShadow": True, "DoubleSided": True, "Massless": True}.items():
            require(props[property_name][0] == "bool" and props[property_name][1] == str(expected_value).lower(),
                    "Corn physics/shadow differs: " + path + "/" + property_name)
        require(props["Material"][1] == "256" and props["Color3uint8"][1] == "16777215"
                and f32(float(props["Transparency"][1])) == 0 and f32(float(props["Reflectance"][1])) == 0,
                "Corn material/appearance differs: " + path)
        def exact_uri(value, uri):
            return value and value[0] == "Content" and len(value[2]) == 1 and value[2][0][0] == "uri" \
                and value[2][0][1] == ["uri", uri, []]
        require(exact_uri(props.get("TextureContent"), "rbxassetid://137803536172445"), "Corn texture differs: " + path)
        mesh = props.get("MeshContent")
        require(exact_uri(mesh, "rbxassetid://104111861186519") if variety == 1 else
                (mesh and mesh[0] == "Content" and [x[0] for x in mesh[2]] == ["null"]),
                "Saved URI/session content differs: " + path)
        require(props["Tags"][1] == "", "Decorative corn acquired tags: " + path)
        require(props["CollisionGroup"] == ["string", "Default", []]
                and props["CollisionGroupId"] == ["int", "0", []]
                and props["RootPriority"] == ["int", "0", []], "Corn collision binding differs: " + path)
        require(props["CustomPhysicalProperties"][0] == "PhysicalProperties"
                and props["CustomPhysicalProperties"][2] == [["CustomPhysics", ["CustomPhysics", "false", []]]],
                "Corn acquired custom physics: " + path)
        require(components(props["PivotOffset"]) == [0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1]
                and components(props["Velocity"]) == [0, 0, 0] and components(props["RotVelocity"]) == [0, 0, 0],
                "Corn pivot or velocity changed: " + path)
        require(props["PhysicalConfigData"] == ["SharedString", "43534750485300000000424c4f434b", []]
                and props["PhysicsData"] == ["BinaryString", "", []]
                and props["RenderFidelity"] == ["token", "1", []]
                and props["MaterialVariantSerialized"] == ["string", "", []],
                "Corn static-box collision/fidelity/material variant changed: " + path)
        require(props["VertexCount"] == ["int", "0", []], "New factory mesh VertexCount cache differs: " + path)
        vector_metadata = {"InitialSize", "UnscaledCofm", "UnscaledVolInertiaDiags", "UnscaledVolInertiaOffDiags"}
        if variety == 1:
            for name in vector_metadata:
                require(components(props[name]) == components(part_defaults[name]),
                        "Original URI mesh-space metadata changed: " + path + "/" + name)
            require(f32(float(props["UnscaledVolume"][1])) == f32(float(part_defaults["UnscaledVolume"][1])),
                    "Original URI unscaled volume changed: " + path)
        else:
            metadata = mass_metadata[variety - 1]
            for name in vector_metadata:
                require(components(props[name]) == metadata[name],
                        "Independent hull mass metadata differs: " + path + "/" + name + ": "
                        + str(components(props[name])) + " != " + str(metadata[name]))
            require(f32(float(props["UnscaledVolume"][1])) == metadata["UnscaledVolume"],
                    "Independent hull volume differs: " + path)
        validate_default_properties(props, part_defaults, {
            "Name", "AttributesSerialize", "CFrame", "size", "Anchored", "CanCollide", "CanTouch", "CanQuery",
            "CastShadow", "DoubleSided", "Massless", "Material", "Color3uint8", "Transparency", "Reflectance",
            "TextureContent", "MeshContent", "Tags", "CollisionGroup", "CollisionGroupId", "RootPriority",
            "CustomPhysicalProperties", "PivotOffset", "Velocity", "RotVelocity", "PhysicalConfigData", "PhysicsData",
            "RenderFidelity", "MaterialVariantSerialized", "VertexCount", "UnscaledVolume", *vector_metadata}, path)
    require(folder_count == 1 and seen == set(wanted) and chunks == set(expected["chunks"]),
            "Exact authored corn set/chunks differ")
    require(not pose_differences, "Exact independent CFrame regeneration differs; no tolerance accepted: " + json.dumps(pose_differences))
    return {"passed": True, "complete": True, "plants": len(seen), "chunks": len(chunks),
            "baseline_sha256": BASELINE_SHA256, "native_builder_sha256": BUILD_SHA256,
            "independent_construction_boxes": 234, "new_cells": 11725, "avoided_obstacles": 3,
            "all_cell_sets_frames_sizes_varieties_attributes_materials_public_physics_exact": True,
            "scope": "Complete new corn subtree property inventory. Exact independent construction/poses/size/variety/attributes; all other properties match immutable defaults or explicit construction writes; new form hull mass/inertia independently integrated. Only generated UniqueId/HistoryId values are delegated to the global identity audit.",
            "all_new_corn_properties_independently_validated": True,
            "engine_generated_mesh_mass_inertia_independently_regenerated": True,
            "independent_hull_metadata": mass_metadata[1:]}


def read_stream(path):
    with gzip.open(path, "rt", encoding="utf-8") as stream:
        for line in stream:
            yield json.loads(line)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-dom", type=Path, default=OUT / "baseline-known-dom.json.gz")
    parser.add_argument("--corn-dom-gzip", type=Path, default=OUT / "candidate-corn-dom.jsonl.gz")
    parser.add_argument("--expected-output", type=Path)
    parser.add_argument("--report", type=Path, default=OUT / "save-corn-validation.json")
    args = parser.parse_args()
    try:
        candidate = ROOT / "place/Children_of_corn_B.rbxl"
        require(hashlib.sha256(candidate.read_bytes()).hexdigest() == CANDIDATE_SHA256, "Author-saved candidate changed")
        if args.baseline_dom.suffix == ".gz":
            with gzip.open(args.baseline_dom, "rt", encoding="utf-8") as stream:
                before = json.load(stream)
        else:
            before = json.loads(args.baseline_dom.read_bytes())
        require(len(before) == 6056, "Final audit requires the full service-disambiguated 6056 baseline")
        expected = regenerate(before)
        if args.expected_output:
            args.expected_output.write_text(json.dumps(expected, separators=(",", ":")), encoding="utf-8")
        report = validate(before, read_stream(args.corn_dom_gzip), expected) if args.corn_dom_gzip else {
            "regenerated": True, "plants": len(expected[0]["rows"]), "chunks": len(expected[0]["chunks"])}
        require(hashlib.sha256(candidate.read_bytes()).hexdigest() == CANDIDATE_SHA256, "Candidate changed during read-only audit")
        report["candidate_sha256"] = CANDIDATE_SHA256
    except Exception as error:
        report = {"passed": False, "complete": False, "error": str(error)}
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report))
    if report.get("passed") is False:
        raise SystemExit(1)
