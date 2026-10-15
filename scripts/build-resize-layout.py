"""Fixed 840->630 plan from immutable engine bytes; never serialize a scene."""
import argparse
import copy
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / "place/Children_of_corn.before-resize-yellow-20261015.rbxl"
BASELINE_HASH = "c7015e55a7cf4a020fe0ae1e3d40d4c69c17faf10a8f01d8ce4379066c955fed"
PREFIX = "Workspace/CornMap"
MANIFEST = ROOT / "scripts/resize-layout.json"
INSTALLER = ROOT / "scripts/install-resize-layout.luau"
GREEN = "rbxassetid://137803536172445"
DRY = "rbxassetid://103653296385119"
MESH = "rbxassetid://104111861186519"

def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

T = module("torch_resize_helpers", ROOT / "scripts/build-finale-torch-layout.py")
P = module("resize_preservation", ROOT / "scripts/verify-scene-preservation.py")
require, components, f32 = T.require, T.components, T.f32

def attrs(value):
    data = bytes.fromhex(value[1]); offset = 0
    def take(fmt):
        nonlocal offset
        result = struct.unpack_from(fmt, data, offset)
        offset += struct.calcsize(fmt)
        return result[0] if len(result) == 1 else list(result)
    def string():
        nonlocal offset
        size = take("<I"); result = data[offset:offset+size].decode(); offset += size
        return result
    result = {}
    for _ in range(take("<I") if data else 0):
        key, kind = string(), take("<B")
        if kind == 2: value = string()
        elif kind == 3: value = bool(take("<B"))
        elif kind == 6: value = take("<d")
        elif kind == 17: value = {"type":"Vector3","value":take("<fff")}
        elif kind == 20:
            position, rotation = take("<fff"), take("<B")
            require(rotation in (0, 2), "Unexpected attribute rotation")
            matrix = take("<fffffffff") if rotation == 0 else [1,0,0,0,1,0,0,0,1]
            value = {"type": "CoordinateFrame", "value": position + matrix}
        else: raise ValueError("Unsupported fixed attribute: " + str(kind))
        result[key] = value
    require(offset == len(data), "Trailing attribute data")
    return result

def typed_dom(kind, values):
    names = ["X", "Y", "Z"] if kind == "Vector3" else ["X","Y","Z","R00","R01","R02","R10","R11","R12","R20","R21","R22"]
    return [kind, "", [[key, [key, repr(f32(value)), []]] for key, value in zip(names, values)]]

def uri(value):
    require(value[0] == "Content" and len(value[2]) == 1 and value[2][0][0] == "uri", "Unexpected content")
    return value[2][0][1][1]

def pivot(node):
    value = node["properties"].get("WorldPivotData")
    return components(value[2][0][1]) if value and value[2] else None

def frame_delta(frame, delta):
    out = frame.copy(); out[0] = f32(out[0] + delta[0]); out[2] = f32(out[2] + delta[1]); return out

def build_manifest():
    data = BASELINE.read_bytes()
    require(len(data) == 1028519 and hashlib.sha256(data).hexdigest() == BASELINE_HASH, "Immutable resize baseline changed")
    dom, _ = P.known_dom(BASELINE)
    global BASELINE_DOM
    BASELINE_DOM = dom
    after = copy.deepcopy(dom)
    changes, attribute_changes = [], []
    def change(path, prop, value):
        before = dom[path]["properties"][prop]
        if before == value: return
        after[path]["properties"][prop] = value
        changes.append({"path": path, "uid": dom[path]["properties"]["UniqueId"][1], "class": dom[path]["class"],
                        "property": prop, "before": before, "after": value})
    def cf(path, delta): change(path, "CFrame", typed_dom("CoordinateFrame", frame_delta(components(dom[path]["properties"]["CFrame"]), delta)))
    def size(path, values): change(path, "size", typed_dom("Vector3", values))
    def attribute(path, key, value):
        old = attrs(dom[path]["properties"]["AttributesSerialize"])[key]
        if old == value: return
        attribute_changes.append({"path": path,"uid": dom[path]["properties"]["UniqueId"][1],"key":key,"before":old,"after":value})
    field = components(dom[PREFIX+"/FieldZone"]["properties"]["CFrame"])
    require(field[0] == 0 and field[2] == 0 and field[3:] == [1,0,0,0,1,0,0,0,1], "Fixed author center changed")
    require(components(dom[PREFIX+"/FieldZone"]["properties"]["size"]) == [840,10,840], "Field not 840")
    for name in ("Ground", "FieldZone"):
        path = PREFIX+"/"+name; old = components(dom[path]["properties"]["size"]); size(path,[630,old[1],630])
    size(PREFIX+"/PlayBounds", [630,50,670])
    attribute(PREFIX,"FieldSide",630)
    for name, pos, dimensions in [
        ("West",[-316,0],[2,20,634]),("East",[316,0],[2,20,634]),
        ("South",[0,-316],[630,20,2]),("NorthLeft",[-160.5,316],[309,20,2]),("NorthRight",[160.5,316],[309,20,2])]:
        path=PREFIX+"/Boundaries/"+name; old=components(dom[path]["properties"]["CFrame"])
        cf(path,[pos[0]-old[0],pos[1]-old[2]]); size(path,dimensions)
    gate = PREFIX+"/EscapeGate"
    for path,node in dom.items():
        if path.startswith(gate+"/") and "CFrame" in node["properties"]: cf(path,[0,-105])
    for name in ("RoadSurface","RutLeft","RutRight","RoadClearance"):
        path=PREFIX+"/Props/VillageRoad/"+name; old=components(dom[path]["properties"]["size"]); size(path,[old[0],old[1],630])
    cf(PREFIX+"/Props/VillageRoad/ExitSign",[0,-105])
    group_names=["ScarecrowMarker","HouseWest","HouseEast","HouseNorthWest","RustedTruck"]
    support={"Tyre_01":"HouseWest","Tyre_02":"HouseEast","Tyre_03":"HouseNorthWest","Tyre_04":"RustedTruck","Tyre_05":"RustedTruck",
             "RubbishPile_01":"HouseWest","RubbishPile_02":"HouseEast","RubbishPile_03":"RustedTruck"}
    group_delta={}
    for name in group_names:
        frame=pivot(dom[PREFIX+"/Props/"+name]); require(frame is not None,"Explicit group pivot missing")
        group_delta[name]=[-frame[0]*.25,-frame[2]*.25]
    for name, parent in support.items(): group_delta[name]=group_delta[parent]
    for name, delta in group_delta.items():
        path=PREFIX+"/Props/"+name
        for child,node in dom.items():
            if child.startswith(path+"/") and "CFrame" in node["properties"]: cf(child,delta)
        frame=pivot(dom[path]); require(frame is not None,"Supporting explicit pivot missing")
        value=copy.deepcopy(dom[path]["properties"]["WorldPivotData"])
        value[2][0][1]=["CFrame","",typed_dom("CoordinateFrame",frame_delta(frame,delta))[2]]
        change(path,"WorldPivotData",value)
    slots=[]
    for index in range(1,16):
        slot_id=f"solo_slot_{index:02d}";path=PREFIX+"/KeySlots/"+slot_id; old=components(dom[path]["properties"]["CFrame"])
        x=old[0]*.75; x=math.copysign(max(abs(x),21),x); z=old[2]*.75; delta=[x-old[0],z-old[2]]
        cf(path,delta);slots.append({"slot_id":slot_id,"center":[f32(x),old[1],f32(z)],"delta":delta})
        for part in ("Pole","Flame"):cf(PREFIX+"/TorchMarkers/torch_"+slot_id+"/"+part,delta)
        if index in (3,8,13):
            barrel=PREFIX+"/Props/LookoutBarrel"+({3:"",8:"#2",13:"#3"}[index]);cf(barrel,delta)
    for name in ("HouseWest","HouseEast","HouseNorthWest"):
        for sign in ("-1","1"):
            for part in ("Pole","Flame"): cf(PREFIX+"/TorchMarkers/torch_"+name+sign+"/"+part,group_delta[name])
    for path,node in dom.items():
        if path.startswith(PREFIX+"/TorchMarkers/road_exit_") and "CFrame" in node["properties"]:
            old=components(node["properties"]["CFrame"]);cf(path,[0 if "_wall_" in path else -old[0]*.25,-105])
        if path.startswith(PREFIX+"/CornerSpawns/") or path.startswith(PREFIX+"/NoCornZones/"):
            if "CFrame" in node["properties"]:
                old=components(node["properties"]["CFrame"]); cf(path,[-old[0]*.25,-old[2]*.25])
    # Fixed new exclusions conservatively remove saved decoration from clearings.
    boxes=[]; circles=[(s["center"][0],s["center"][2],6)for s in slots]
    for path,node in after.items():
        a=node["properties"]
        if "CFrame" not in a:continue
        tags=bytes.fromhex(a.get("Tags",[0,""])[1]).decode().split("\0")
        if path.startswith(PREFIX+"/Props/") or path.startswith(PREFIX+"/NoCornZones/") or "corn_no_corn_zone"in tags:
            boxes.append((components(a["CFrame"]),components(a["size"]),1.5))
        if "corn_spawn"in tags:
            f=components(a["CFrame"]);circles.append((f[0],f[2],10)); boxes.append((f,components(a["size"]),4))
        if path==gate+"/Door":boxes.append((components(a["CFrame"]),components(a["size"]),6))
    def excluded(frame,size):
        # Conservative world AABBs include plant half-width to keep whole leaves outside props.
        x,z=frame[0],frame[2]; halfx=(abs(frame[3])*size[0]+abs(frame[5])*size[2])/2;halfz=(abs(frame[9])*size[0]+abs(frame[11])*size[2])/2
        if abs(x)+halfx>315 or abs(z)+halfz>315:return True
        for cx,cz,radius in circles:
            if math.hypot(x-cx,z-cz)<=radius+max(halfx,halfz):return True
        for f,s,padding in boxes:
            extx=sum(abs(f[3+i])*s[i]/2 for i in range(3));extz=sum(abs(f[9+i])*s[i]/2 for i in range(3))
            if abs(x-f[0])<=extx+padding+halfx and abs(z-f[2])<=extz+padding+halfz:return True
        return False
    plants,removed,retained=[],[],[]
    for path,node in dom.items():
        folder=next((name for name in ("EditorPreview","EditorFieldOverview")if path.startswith(PREFIX+"/"+name+"/")),None)
        if not folder:continue
        a=node["properties"]; require(node["class"]=="MeshPart" and uri(a["MeshContent"])==MESH and uri(a["TextureContent"])==GREEN,"Unknown saved corn art")
        require(not any(p.startswith(path+"/")for p in dom),"Manual corn child")
        frame=components(a["CFrame"]); target=frame_delta(frame,[96.25,96.25])if folder=="EditorPreview"else frame
        plant={"path":path,"uid":a["UniqueId"][1],"folder":folder,"class":"MeshPart","before_frame":frame,"after_frame":target,
               "size":components(a["size"]),"removed":excluded(target,components(a["size"]))}
        plants.append(plant)
        if plant["removed"]:removed.append({"path":path,"uid":a["UniqueId"][1],"class":"MeshPart"})
        else:
            retained.append(plant)
            if folder=="EditorPreview":change(path,"CFrame",typed_dom("CoordinateFrame",target))
            value=copy.deepcopy(a["TextureContent"]);value[2][0][1][1]=DRY;change(path,"TextureContent",value)
    counts={name:sum(p["folder"]==name for p in retained)for name in ("EditorPreview","EditorFieldOverview")}
    removed_paths={row["path"]for row in removed}
    for path,node in dom.items():
        for prop,raw in node["properties"].items():
            if raw[0]=="Ref" and raw[1]in removed_paths:
                require(node["class"]=="ObjectValue" and prop=="Value" and path.startswith(PREFIX+"/Props/VillageRoad/HiddenCornIndex/"),"Unexpected reference into removed corn")
                change(path,prop,["Ref","null",[]])
    for name,count in counts.items():attribute(PREFIX+"/"+name,"PlantCount",count)
    attribute(PREFIX,"EditorCornCount",counts["EditorPreview"])
    # Record full exact serialized attributes for strict saved-byte verification.
    for path in sorted({row["path"] for row in attribute_changes}):
        values=attrs(dom[path]["properties"]["AttributesSerialize"])
        for row in attribute_changes:
            if row["path"]==path:values[row["key"]]=row["after"]
        raw=struct.pack("<I",len(values))
        for key,value in values.items():
            encoded=key.encode();raw+=struct.pack("<I",len(encoded))+encoded
            if isinstance(value,bool):raw+=bytes([3,int(value)])
            elif isinstance(value,(int,float)):raw+=bytes([6])+struct.pack("<d",value)
            elif isinstance(value,str):
                encoded=value.encode();raw+=bytes([2])+struct.pack("<I",len(encoded))+encoded
            else:raise ValueError("Unexpected changed attribute encoding")
        change(path,"AttributesSerialize",["BinaryString",raw.hex(),[]])
    require(counts["EditorPreview"]>500 and counts["EditorFieldOverview"]>2000,"Insufficient saved crop")
    require(len(plants)==6164 and len(slots)==15,"Unexpected plant/slot topology")
    # Full potential lookout hull must clear central road (width18 + padding1.5).
    roadgap=min(min(abs(s["center"][0]-5),abs(s["center"][0]+6.6))-10.5 for s in slots)
    require(roadgap>=3.9-1e-5,"Stump hull enters road")
    sep=min(math.hypot(a["center"][0]-b["center"][0],a["center"][2]-b["center"][2])for i,a in enumerate(slots)for b in slots[i+1:])
    require(sep>=72,"Reinforcement slot separation too small")
    def bounds(frame,dimensions):
        ext=[sum(abs(frame[3+i*3+j])*dimensions[j]/2 for j in range(3))for i in range(3)]
        return [(frame[i]-ext[i],frame[i]+ext[i])for i in range(3)]
    def boxgap(a,b):
        return math.hypot(max(a[0][0]-b[0][1],b[0][0]-a[0][1],0),max(a[2][0]-b[2][1],b[2][0]-a[2][1],0))
    colliders=[]
    spawns=[]
    for path,node in after.items():
        a=node["properties"]
        if "CFrame"not in a:continue
        if path.startswith(PREFIX+"/CornerSpawns/"):spawns.append(components(a["CFrame"]))
        if a.get("CanCollide",[0,"false"])[1]=="true" and (path.startswith(PREFIX+"/Props/")or path.startswith(gate+"/")or path.startswith(PREFIX+"/Boundaries/")):
            colliders.append((path,bounds(components(a["CFrame"]),components(a["size"]))))
    propgap,spawngap=math.inf,math.inf
    for index,slot in enumerate(slots,1):
        x,y,z=slot["center"];hull=[(x-5,x+6.6),(y-1,y+9),(z-3,z+3)]
        own=PREFIX+"/Props/LookoutBarrel"+{3:"",8:"#2",13:"#3"}[index]if index in(3,8,13)else None
        for path,box in colliders:
            if path==own:
                require(box[0][0]>=hull[0][0]and box[0][1]<=hull[0][1]and box[2][0]>=hull[2][0]and box[2][1]<=hull[2][1],"Own barrel leaves stump union")
                continue
            distance=boxgap(hull,box);propgap=min(propgap,distance)
            require(distance>=2.5,"New stump hull touches collider: "+slot["slot_id"]+" -> "+path)
        for spawn in spawns:
            distance=math.hypot(x-spawn[0],z-spawn[2])-7;spawngap=min(spawngap,distance);require(distance>=30,"New stump near spawn")
        for other in slots:
            if other is slot:continue
            ox,oy,oz=other["center"];require(boxgap(hull,[(ox-5,ox+6.6),(oy-1,oy+9),(oz-3,oz+3)])>=24,"Stump hulls touch")
    # Runtime bindings are preserved exactly; no scale of prop or plant dimensions.
    require(BASELINE.read_bytes()==data,"Immutable baseline changed while reading")
    return {"version":1,"baseline":{"path":str(BASELINE.relative_to(ROOT)).replace("\\","/"),"bytes":len(data),"sha256":BASELINE_HASH},
            "field_side_before":840,"field_side_after":630,"property_changes":changes,"attribute_changes":attribute_changes,
            "removed_plants":removed,"retained_plants":retained,"plants":plants,"slots":slots,
            "summary":{"property_changes":len(changes),"removed_plants":len(removed),"retained_plants":len(retained),"counts":counts,
                       "minimum_slot_separation":sep,"minimum_road_stump_gap":roadgap,"prop_group_delta":group_delta,
                       "minimum_foreign_collider_gap":propgap,"minimum_spawn_gap":spawngap,
                       "scope":"Rigid human-scale prop groups; crop old overview, rigid SW preview; surviving corn dry before visible; original art/Baseplate/Lighting/rawTerrain preserved. Actual Studio acceptance separate."}}

def build(check=False):
    manifest=build_manifest()
    source=installer(manifest)
    outputs={MANIFEST:json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",INSTALLER:source}
    for path,text in outputs.items():
        if check:require(path.exists() and path.read_text(encoding="utf8")==text,"Stale resize output: "+str(path))
        else:path.write_text(text,encoding="utf8")
    print(json.dumps(dict(manifest["summary"],checked=check,scene_written=False),ensure_ascii=False))

def installer(manifest):
    dom=BASELINE_DOM
    changed={(row["path"],row["property"]):row for row in manifest["property_changes"]}
    plantpaths={row["path"]for row in manifest["plants"]}
    def value(raw):
        if raw[0]=="OptionalCoordinateFrame":return {"type":"CoordinateFrame","value":components(raw[2][0][1])}
        if raw[0]=="Content":return uri(raw)
        return T.typed(raw)
    mutations=[]
    for row in manifest["property_changes"]:
        if row["path"]in plantpaths or row["property"]=="AttributesSerialize" or row["property"]=="Value":continue
        mutations.append({"path":row["path"],"property":{"size":"Size","WorldPivotData":"WorldPivot"}.get(row["property"],row["property"]),
                          "before":value(row["before"]),"after":value(row["after"])})
    guards=[]
    fields={"Folder":[],"Model":["PrimaryPart","ModelStreamingMode","LevelOfDetail"],
            "Part":T.FIELDS["Part"],"SpawnLocation":T.FIELDS["Part"]+["Enabled","Neutral"],
            "MeshPart":[key for key in T.FIELDS["Part"]if key!="shape"],"Fire":T.FIELDS["Fire"],"PointLight":T.FIELDS["PointLight"],
            "SurfaceGui":["Enabled","AlwaysOnTop","PixelsPerStud","LightInfluence","Brightness"],
            "TextLabel":["Text","Visible","BackgroundTransparency","TextScaled","TextColor3"]}
    for path,node in dom.items():
        if path!=PREFIX and not path.startswith(PREFIX+"/"):continue
        if path in plantpaths:continue
        props=node["properties"]
        keys=fields.get(node["class"],[]).copy()
        if "CFrame"in props:keys.append("CFrame")
        if pivot(node) is not None:keys.append("WorldPivotData")
        selected={}
        for key in keys:
            if key not in props or (path,key)in changed:continue
            typed=value(props[key]); actual={"size":"Size","WorldPivotData":"WorldPivot"}.get(key,T.ALIASES.get(key,key))
            if isinstance(typed,dict)and typed.get("type")=="Ref":typed={"reference":typed["value"]}if typed["value"]else{"nil_ref":True}
            selected[actual]=typed
        if node["class"]=="MeshPart":selected["TextureID"]=uri(props["TextureContent"])
        oldattrs=attrs(props["AttributesSerialize"]);newattrs=copy.deepcopy(oldattrs)
        for row in manifest["attribute_changes"]:
            if row["path"]==path:newattrs[row["key"]]=row["after"]
        children=[child.rsplit("/",1)[-1].split("#")[0]for child in dom if child.rsplit("/",1)[0]==path]
        guards.append({"path":path,"class":node["class"],"properties":selected,"before_attrs":oldattrs,"after_attrs":newattrs,
                       "tags":sorted(x for x in bytes.fromhex(props["Tags"][1]).decode().split("\0")if x),
                       "children":None if path in (PREFIX+"/EditorPreview",PREFIX+"/EditorFieldOverview")else sorted(children)})
    # Compact per-plant fixed rows: before/after frame, Size and deletion flag. Shared
    # asset/physics/color/attributes are verified for every child, no suffix paths.
    compact={name:[]for name in ("EditorPreview","EditorFieldOverview")}
    for row in manifest["plants"]:
        f=row["before_frame"]; require(abs(f[3]-f[11])<1e-7 and abs(f[5]+f[9])<1e-7 and abs(f[7]-1)<1e-7,"Corn not pure upright yaw")
        require(abs(row["size"][0]-3.002729)<1e-6 and abs(row["size"][2]-3.1309776)<1e-6,"Corn dimensions changed")
        before=[round(f[0],6),round(f[1],6),round(f[2],6),round(f[3],9),round(f[5],9)]
        target=row["after_frame"]if row["folder"]=="EditorPreview"and not row["removed"]else False
        transparency=float(dom[row["path"]]["properties"]["Transparency"][1])
        require(transparency in(0,1),"Unknown saved corn transparency")
        compact[row["folder"]].append([before,target,round(row["size"][1],7),row["removed"],transparency])
    plant_by_path={row["path"]:row for row in manifest["plants"]}
    references=[]
    for path,node in dom.items():
        raw=node["properties"].get("Value")
        if raw and raw[0]=="Ref" and raw[1]in plant_by_path:
            row=plant_by_path[raw[1]]
            references.append({"path":path,"folder":row["folder"],"before_frame":row["before_frame"],"before_size":row["size"],
                               "transparency":float(dom[row["path"]]["properties"]["Transparency"][1]),"removed":row["removed"]})
    barrels=[]
    for row in mutations:
        if "/LookoutBarrel"in row["path"]:barrels.append(row)
    source=r'''-- Generated fixed resize from exact engine c7015e55; no scene serialization.
local run=game:GetService("RunService")
assert(run:IsStudio() and not run:IsRunning(),"Stop Children_of_corn Play first")
assert(not workspace:FindFirstChild("Asmr_Base") and not workspace:FindFirstChild("ASMR_Models"),"Wrong scene")
local map=workspace:FindFirstChild("CornMap")
assert(map and map:IsA("Model") and map:GetAttribute("corn_project_id")=="children_of_corn","Wrong project")
assert(not map:FindFirstChild("CornRoundRuntime"),"Unexpected runtime")
local function stillEdit()
 assert(not run:IsRunning() and map.Parent==workspace and not map:FindFirstChild("CornRoundRuntime"),"Scene changed during resize")
end
local function batch(index)
 if index%500==0 then stillEdit();task.wait();stillEdit() end
end
local function equal(a,b)
 if typeof(a)=="EnumItem" then a=a.Value end
 if typeof(a)~=typeof(b) then return false end
 if typeof(a)=="CFrame" then
  local aa,bb={a:GetComponents()},{b:GetComponents()}
  for i=1,12 do if math.abs(aa[i]-bb[i])>0.00002 then return false end end
  return true
 elseif typeof(a)=="Vector3" then return (a-b).Magnitude<0.00002
 elseif typeof(a)=="Color3" then return math.abs(a.R-b.R)<0.00001 and math.abs(a.G-b.G)<0.00001 and math.abs(a.B-b.B)<0.00001
 elseif type(a)=="number" then return math.abs(a-b)<0.00002 end
 return a==b
end
local state=if equal(map.Ground.Size,Vector3.new(840,2,840)) then "before" elseif equal(map.Ground.Size,Vector3.new(630,2,630)) then "after" else nil
assert(state,"Unknown field geometry; nothing changed")
local barrelBindings=__BARRELS__
local function resolve(path)
 for _,binding in barrelBindings do
  if binding.path==path then
   local found,count=nil,0
   for _,item in map.Props:GetChildren() do
    if item.Name=="LookoutBarrel" and item:IsA("BasePart") and item:HasTag("corn_barrel") then
     count+=1
     if equal(item.CFrame,binding[state]) then assert(not found,"Ambiguous barrel");found=item end
    end
   end
   assert(count==3,"Legacy barrel topology changed")
   return found
  end
 end
 local item=game
 for _,name in string.split(path,"/") do item=item and item:FindFirstChild(name) end
 return item
end
local function properties(item,values)
 for key,expected in values do
  if type(expected)=="table" and expected.nil_ref then expected=nil
  elseif type(expected)=="table" and expected.reference then expected=assert(resolve(expected.reference)) end
  assert(equal(item[key],expected),"Resize guarded property changed: "..item:GetFullName().."."..key)
 end
end
local function attrs(item,expected)
 local count=0
 for key,current in item:GetAttributes() do count+=1;assert(equal(current,expected[key]),"Resize attributes changed: "..item:GetFullName().."."..key) end
 local total=0;for _ in expected do total+=1 end
 assert(count==total,"Resize attribute missing")
end
local guards=__GUARDS__
for _,entry in guards do
 local item=assert(resolve(entry.path),"Missing resize node: "..entry.path)
 assert(item.ClassName==entry.class,"Resize class changed")
 properties(item,entry.properties)
 attrs(item,if state=="before" then entry.before_attrs else entry.after_attrs)
 local tags=item:GetTags();assert(#tags==#entry.tags,"Resize tags changed")
 for _,tag in entry.tags do assert(item:HasTag(tag),"Resize tag missing") end
 if entry.children then
  local names={};for _,child in item:GetChildren() do table.insert(names,child.Name) end;table.sort(names)
  assert(#names==#entry.children,"Resize topology changed: "..entry.path)
  for i,name in names do assert(name==entry.children[i],"Resize child changed") end
 end
end
local mutations=__MUTATIONS__
for _,entry in mutations do
 local item=assert(resolve(entry.path),"Missing resize target")
 assert(equal(item[entry.property],entry[state]),"Partial/manual resize: "..entry.path.."."..entry.property)
 entry.item=item
end
local plantRows=__PLANTS__
local matched={}
local function key(frame,offset)
 local p=frame.Position
 local shift=offset or 0
 return tostring(math.round((p.X-shift)/3))..":"..tostring(math.round((p.Z-shift)/3))
end
local function rowFrame(row,after)
 if after and row[2] then return CFrame.new(table.unpack(row[2])) end
 local f=row[1]
 return CFrame.new(f[1],f[2],f[3],f[4],0,f[5],0,1,0,-f[5],0,f[4])
end
local boundPlants={EditorPreview={},EditorFieldOverview={}}
for folderName,rows in plantRows do
 local folder=assert(map:FindFirstChild(folderName))
 local offset=if state=="after" and folderName=="EditorPreview" then 96.25 else 0
 local lookup={};local expected=0
 for _,row in rows do
  if state=="before" or not row[4] then
   local frame=rowFrame(row,state=="after")
   local id=key(frame,offset);assert(not lookup[id],"Ambiguous fixed corn key");lookup[id]=row;expected+=1
  end
 end
 local children=folder:GetChildren();assert(#children==expected,"Saved corn count/topology changed: "..folderName)
 for childIndex,item in children do
  assert(item:IsA("MeshPart") and #item:GetChildren()==0,"Unknown saved corn child")
  local id=key(item.CFrame,offset);local row=assert(lookup[id],"Unknown saved corn position");lookup[id]=nil
  assert(item.Name==(if folderName=="EditorPreview" then "Corn" else "DistantCorn"),"Corn name changed")
  assert(equal(item.CFrame,rowFrame(row,state=="after")),"Corn pose changed")
  properties(item,{Size=Vector3.new(3.002729,row[3],3.1309776),MeshId="rbxassetid://104111861186519",TextureID=if state=="before" then "rbxassetid://137803536172445" else "rbxassetid://103653296385119",
   Anchored=true,CanCollide=false,CanTouch=false,CanQuery=false,CastShadow=false,Transparency=row[5],Color=Color3.fromRGB(163,162,165)})
  attrs(item,if folderName=="EditorPreview" then {} else {CornEditorOverview=true,corn_project_id="children_of_corn"})
  assert(#item:GetTags()==0,"Corn tags changed")
  table.insert(matched,{item=item,row=row,parent=folder})
  boundPlants[folderName][key(rowFrame(row,false))]=item
  batch(childIndex)
 end
end
local references=__REFERENCES__
local function refGet(item) return item.Value end
local function refSet(item,value) item.Value=value end
local referenceCleanup={}
for _,entry in references do
 local expected=boundPlants[entry.folder][key(CFrame.new(table.unpack(entry.before_frame)))]
 local item=assert(resolve(entry.path))
 if state=="after" and entry.removed then
  expected=nil
  if refGet(item)~=nil then
   -- The first accepted installer relied on Destroy clearing ObjectValue. In
   -- Studio the reference can survive until save; accept only its exact known
   -- detached removed leaf, then explicitly clear the already-declared delta.
   local leaf=refGet(item)
   assert(leaf:IsA("MeshPart") and leaf.Parent==nil and #leaf:GetChildren()==0,"Unknown detached corn reference")
   assert(leaf.Name==(if entry.folder=="EditorPreview" then "Corn" else "DistantCorn"),"Detached corn name changed")
   properties(leaf,{CFrame=CFrame.new(table.unpack(entry.before_frame)),Size=Vector3.new(table.unpack(entry.before_size)),
    MeshId="rbxassetid://104111861186519",TextureID="rbxassetid://137803536172445",Transparency=entry.transparency,
    Anchored=true,CanCollide=false,CanTouch=false,CanQuery=false,CastShadow=false,Color=Color3.fromRGB(163,162,165)})
   attrs(leaf,if entry.folder=="EditorPreview" then {} else {CornEditorOverview=true,corn_project_id="children_of_corn"})
   assert(#leaf:GetTags()==0,"Detached corn tags changed")
   table.insert(referenceCleanup,{item=item,value=leaf})
  end
 else
  assert(refGet(item)==expected,"Saved corn reference changed")
 end
end
if state=="after" then
 assert(#referenceCleanup==0 or #referenceCleanup==193,"Partial reference cleanup; nothing changed")
 if #referenceCleanup==0 then return {repeated=true,changed=0,fieldSide=630,removed=0,preview=__PREVIEW__,overview=__OVERVIEW__} end
 local repaired={}
 local ok,problem=pcall(function()
  stillEdit()
  for _,entry in referenceCleanup do
   table.insert(repaired,entry);refSet(entry.item,nil)
   -- RESIZE_AFTER_REFERENCE_REPAIR
  end
  stillEdit()
 end)
 if not ok then
  for _,entry in repaired do refSet(entry.item,entry.value) end
  error("Reference cleanup rolled back: "..tostring(problem))
 end
 return {repeated=false,referenceCleanup=true,changed=#repaired,fieldSide=630,removed=0,preview=__PREVIEW__,overview=__OVERVIEW__}
end
local history=game:GetService("ChangeHistoryService")
history:SetWaypoint("Before Corn field 630")
local changed={};local removed={};local attributes=__ATTRIBUTES__
local ok,problem=pcall(function()
 stillEdit()
 for _,entry in mutations do
  table.insert(changed,{item=entry.item,key=entry.property,value=entry.item[entry.property]})
  entry.item[entry.property]=entry.after
  -- RESIZE_AFTER_WRITE
  batch(#changed)
 end
 for _,entry in attributes do
  local item=assert(resolve(entry.path));table.insert(changed,{item=item,attribute=entry.key,value=item:GetAttribute(entry.key)})
  item:SetAttribute(entry.key,entry.after)
  -- RESIZE_AFTER_WRITE
  batch(#changed)
 end
 for _,entry in references do
  if entry.removed then
   local item=assert(resolve(entry.path))
   table.insert(changed,{item=item,reference=true,value=refGet(item)});refSet(item,nil)
   -- RESIZE_AFTER_WRITE
   batch(#changed)
  end
 end
 for plantIndex,entry in matched do
  local item,row=entry.item,entry.row
  if row[4] then
   table.insert(removed,entry);item.Parent=nil
  else
   if entry.parent.Name=="EditorPreview" then
    table.insert(changed,{item=item,key="CFrame",value=item.CFrame});item.CFrame=CFrame.new(table.unpack(row[2]))
   end
   table.insert(changed,{item=item,key="TextureID",value=item.TextureID});item.TextureID="rbxassetid://103653296385119"
  end
  -- RESIZE_AFTER_PLANT
  batch(plantIndex)
 end
 stillEdit()
end)
if not ok then
 for i=#changed,1,-1 do local entry=changed[i];if entry.attribute then entry.item:SetAttribute(entry.attribute,entry.value) elseif entry.reference then refSet(entry.item,entry.value) else entry.item[entry.key]=entry.value end end
 for _,entry in removed do entry.item.Parent=entry.parent end
 error("Resize rolled back: "..tostring(problem))
end
-- Final destruction is an uninterrupted commit after every reversible write and
-- yielded batch passed. No yield can leave a half-destroyed installation.
for _,entry in removed do entry.item:Destroy() end
history:SetWaypoint("Installed Corn field 630")
return {repeated=false,changed=#changed,removed=#removed,fieldSide=630,preview=__PREVIEW__,overview=__OVERVIEW__}
'''
    for key,replacement in {"__BARRELS__":T.lua(barrels),"__GUARDS__":T.lua(guards),"__MUTATIONS__":T.lua(mutations),
                            "__PLANTS__":T.lua(compact),"__ATTRIBUTES__":T.lua(manifest["attribute_changes"]),
                            "__REFERENCES__":T.lua(references),
                            "__PREVIEW__":str(manifest["summary"]["counts"]["EditorPreview"]),"__OVERVIEW__":str(manifest["summary"]["counts"]["EditorFieldOverview"])}.items():source=source.replace(key,replacement)
    return source

if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--check",action="store_true");build(parser.parse_args().check)
