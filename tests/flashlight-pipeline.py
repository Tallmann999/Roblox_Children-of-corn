"""Actual generated flashlight installer plus strict saved-DOM guard fixtures.

All mutations are in memory; accepted scenes and old pipelines remain read-only.
"""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("flashlight_pipeline_audit", ROOT / "scripts/verify-flashlight-copy.py")
f = importlib.util.module_from_spec(spec)
spec.loader.exec_module(f)
f.builder.require_baseline()
_, SOURCES, CLASSES, DECLARED = f.builder.mapping()
ASSETS = f.fog.current_sources()
MANIFEST = json.loads((f.builder.OUT / "pipeline-manifest.json").read_bytes())
assert f.sha256(ROOT / "scripts/install-flashlight.luau") == MANIFEST["installer_sha256"]
BEFORE, _ = f.r.p.known_dom(f.BASELINE)
assert len(BEFORE) == 4521


def scalar(kind, value):
    return [kind, str(value), []]


AFTER = BEFORE.copy()
template = BEFORE["ServerScriptService/GameServer/Game/RoundAudio"]
for index, path in enumerate(sorted(f.ADDITIONS), 1):
    AFTER[path] = copy.deepcopy(template)
    props = AFTER[path]["properties"]
    props["Name"] = scalar("string", path.rsplit("/", 1)[-1])
    props["UniqueId"] = scalar("UniqueId", f"{(1 << 127) + index:032x}")
    props["ScriptGuid"] = scalar("string", "{F0000000-0000-0000-0000-" + f"{index:012x}" + "}")
for path in set(DECLARED) | f.ADDITIONS:
    AFTER[path] = copy.deepcopy(AFTER[path])
    AFTER[path]["properties"]["Source"] = scalar("string", SOURCES[path])


def validate(after):
    return f.validate_dom(BEFORE, after, SOURCES, CLASSES, ASSETS, DECLARED)


positive = validate(AFTER)
assert positive["passed"] and positive["complete"] and positive["total_sources"] == 155
assert positive["new_instances"] == 2 and positive["source_changes"] == sorted(DECLARED)
rejected = []


def rejects(name, mutate):
    after = AFTER.copy()
    def node(path):
        if after[path] is AFTER.get(path):
            after[path] = copy.deepcopy(after[path])
        return after[path]
    mutate(after, node)
    try:
        validate(after)
    except (ValueError, KeyError, TypeError, IndexError):
        rejected.append(name)
        return
    raise AssertionError("Unsafe flashlight save accepted: " + name)


for path in sorted(set(SOURCES) | set(ASSETS)):
    rejects("foreign Source:" + path, lambda a, n, p=path: n(p)["properties"].__setitem__("Source", scalar("string", "return 'foreign'")))
for path in sorted(f.ADDITIONS):
    rejects("missing added Module:" + path, lambda a, n, p=path: a.pop(p))
    rejects("wrong added class:" + path, lambda a, n, p=path: n(p).__setitem__("class", "Script"))
    rejects("wrong added Name:" + path, lambda a, n, p=path: n(p)["properties"].__setitem__("Name", scalar("string", "Other")))
    rejects("added capabilities:" + path, lambda a, n, p=path: n(p)["properties"].__setitem__("Capabilities", scalar("SecurityCapabilities", 1)))
    rejects("added attributes:" + path, lambda a, n, p=path: n(p)["properties"].__setitem__("AttributesSerialize", scalar("BinaryString", "00")))
    rejects("added invalid GUID:" + path, lambda a, n, p=path: n(p)["properties"].__setitem__("ScriptGuid", scalar("string", "arbitrary")))
    rejects("added zero GUID:" + path, lambda a, n, p=path: n(p)["properties"].__setitem__("ScriptGuid", scalar("string", "{00000000-0000-0000-0000-000000000000}")))
    rejects("added duplicate GUID:" + path, lambda a, n, p=path: n(p)["properties"].__setitem__("ScriptGuid", copy.deepcopy(template["properties"]["ScriptGuid"])))
    rejects("added duplicate UID:" + path, lambda a, n, p=path: n(p)["properties"].__setitem__("UniqueId", copy.deepcopy(template["properties"]["UniqueId"])))
    rejects("added wrong parent:" + path, lambda a, n, p=path: a.__setitem__("Workspace/" + p.rsplit("/", 1)[-1], a.pop(p)))
for path in sorted(DECLARED):
    rejects("undeployed required Source:" + path, lambda a, n, p=path: a.__setitem__(p, BEFORE[p]))
    rejects("retained class:" + path, lambda a, n, p=path: n(p).__setitem__("class", "Script"))
    rejects("retained UID:" + path, lambda a, n, p=path: n(p)["properties"].__setitem__("UniqueId", scalar("UniqueId", "9" * 32)))
rejects("extra instance", lambda a, n: a.__setitem__("Workspace/Foreign", copy.deepcopy(template)))
rejects("missing original world", lambda a, n: a.pop("Workspace/CornMap/Ground"))
rejects("world parent", lambda a, n: a.__setitem__("Workspace/RelocatedGround", a.pop("Workspace/CornMap/Ground")))
rejects("world physics", lambda a, n: n("Workspace/CornMap/Ground")["properties"].__setitem__("CanCollide", scalar("bool", "false")))
rejects("world attributes", lambda a, n: n("Workspace/CornMap")["properties"].__setitem__("AttributesSerialize", scalar("BinaryString", "00")))
rejects("world size", lambda a, n: n("Workspace/CornMap/Ground")["properties"]["size"][2][0][1].__setitem__(1, "631"))
mesh = "Workspace/CornMap/Props/ScarecrowMarker/HarvestWardenHome/Classic/Coat_Material1"
rejects("changed existing mesh counter", lambda a, n: n(mesh)["properties"].__setitem__("VertexCount", scalar("int", 171)))
for prop in ("Brightness", "Ambient", "OutdoorAmbient", "FogStart", "FogEnd"):
    rejects("Lighting:" + prop, lambda a, n, p=prop: n("Lighting")["properties"].__setitem__(p, scalar("float", 999)))
for prop in ("CFrame", "Focus"):
    rejects("arbitrary Camera:" + prop, lambda a, n, p=prop: n("Workspace/Camera")["properties"].__setitem__(p, scalar("CoordinateFrame", "arbitrary")))
    for value in ("nan", "inf", "1e40"):
        rejects("nonfinite Camera:" + prop + value, lambda a, n, p=prop, v=value: n("Workspace/Camera")["properties"][p][2][0][1].__setitem__(1, v))
    rejects("duplicate Camera component:" + prop, lambda a, n, p=prop: n("Workspace/Camera")["properties"][p][2].__setitem__(1, copy.deepcopy(n("Workspace/Camera")["properties"][p][2][0])))
camera = AFTER.copy()
camera["Workspace/Camera"] = copy.deepcopy(camera["Workspace/Camera"])
for prop in ("CFrame", "Focus"):
    camera["Workspace/Camera"]["properties"][prop][2][0][1][1] = "12.5"
validate(camera)
terrain = f.r.p.unknown_properties(f.BASELINE)
f.r.validate_unknown(terrain, copy.deepcopy(terrain))
terrain_rejected = []
for field in ("payload_sha256", "payload_bytes", "instance_count"):
    bad = copy.deepcopy(terrain)
    row = next(iter(bad["properties"].values()))
    row[field] = "0" * 64 if field == "payload_sha256" else row[field] + 1
    try:
        f.r.validate_unknown(terrain, bad)
    except ValueError:
        terrain_rejected.append(field)
    else:
        raise AssertionError("Changed raw Terrain accepted")

LUA = r'''
local r,fs,serde=require("@lune/roblox"),require("@lune/fs"),require("@lune/serde")
local raw=fs.readFile(".artifacts/playtests/2026-10-20-flashlight/payload.json")
local payload=serde.decode("json",raw)
local code=fs.readFile("scripts/install-flashlight.luau")
local bytes=fs.readFile("place/Children_of_corn.before-flashlight-20261020.rbxl")
local mode,openScript="normal",nil
r.implementMethod("RunService","IsStudio",function()return mode~="not-studio" end)
r.implementMethod("RunService","IsEdit",function()return mode~="running" and mode~="paused-play" end)
r.implementMethod("RunService","IsRunning",function()return mode=="running" end)
r.implementMethod("ScriptEditorService","FindScriptDocument",function(_,item)return if item==openScript then {} else nil end)
r.implementMethod("ChangeHistoryService","SetWaypoint",function()end)
r.implementMethod("HttpService","JSONDecode",function(_,text)return serde.decode("json",text)end)
r.implementMethod("EncodingService","ComputeStringHash",function(_,value,algorithm)
 assert(algorithm==r.Enum.HashAlgorithm.Sha256)
 return(serde.hash("sha256",value):gsub("..",function(pair)return string.char(tonumber(pair,16))end))
end)
local function resolve(place,path)
 local item=place for _,name in path:split("/") do item=item and item:FindFirstChild(name) end return item
end
local function pathOf(item)
 local names={} while item.Parent do table.insert(names,1,item.Name)item=item.Parent end return table.concat(names,"/")
end
local function setup()
 local place=r.deserializePlace(bytes)
 for _,name in {"RunService","ScriptEditorService","ChangeHistoryService","HttpService","EncodingService"} do place:GetService(name) end
 return place
end
local function run(place,source)
 local fn=assert(loadstring(source or code))
 setfenv(fn,setmetatable({game=place,Instance=r.Instance,Vector3=r.Vector3,Enum=r.Enum},{__index=getfenv()}))
 return pcall(fn)
end
local changed,added={},{}
for _,entry in payload.entries do if entry.before and entry.before~=entry.after then changed[entry.path]=true end end
for _,entry in payload.addedNodes do added[entry.path]=entry.class end
local function snapshot(place)
 local result={}
 for _,item in place:GetDescendants() do
  local props={}
  local keys={}
  if item:IsA("LuaSourceContainer") then keys={"Source"}
  elseif item:IsA("BasePart") then keys={"CFrame","Size","Color","Material","CanCollide","CanQuery","CanTouch","Transparency"}
  elseif item:IsA("Lighting") then keys={"Brightness","Ambient","OutdoorAmbient","FogStart","FogEnd","FogColor"}
  elseif item:IsA("Camera") then keys={"CFrame","Focus","CameraType","FieldOfView"} end
  for _,key in keys do local ok,value=pcall(function()return item[key]end)if ok then props[key]=value end end
  result[item]={parent=item.Parent,name=item.Name,class=item.ClassName,attrs=item:GetAttributes(),tags=item:GetTags(),props=props}
 end
 return result
end
local function equal(a,b)
 for k,v in a do assert(b[k]==v,"Changed table value") end
 for k,v in b do assert(a[k]==v,"Added table value") end
end
local function unchanged(place,before,allowInstall)
 local count,created=0,0
 for _,item in place:GetDescendants() do
  count+=1 local row=before[item] local path=pathOf(item)
  if not row then
   assert(allowInstall and added[path]==item.ClassName and #item:GetChildren()==0,"Unexpected new instance:"..path)
   created+=1 continue
  end
  assert(item.Parent==row.parent and item.Name==row.name and item.ClassName==row.class,"Topology changed")
  equal(row.attrs,item:GetAttributes())equal(row.tags,item:GetTags())
  for k,v in row.props do assert((allowInstall and k=="Source" and changed[path])or item[k]==v,"Unexpected property mutation:"..path.."/"..k)end
 end
 local expected=0 for _ in before do expected+=1 end
 assert(count==expected+created and created==(if allowInstall then 2 else 0),"Instance count changed")
end
local place=setup()local before=snapshot(place)
local ok,result=run(place)assert(ok,tostring(result))assert(result.changed==2 and result.created==2 and result.totalSources==155)
unchanged(place,before,true)
for _,entry in payload.entries do assert(serde.hash("sha256",resolve(place,entry.path).Source:gsub("\r\n","\n"))==entry.after)end
local after=snapshot(place)
ok,result=run(place)assert(ok and result.changed==0 and result.created==0 and result.repeated)
unchanged(place,after,false)
local crlf=setup()
for _,entry in payload.entries do local item=resolve(crlf,entry.path)if item then item.Source=item.Source:gsub("\r\n","\n"):gsub("\n","\r\n")end end
ok,result=run(crlf)assert(ok and result.changed==2 and result.created==2)
local rejected={}
local function reject(name,mutate,source)
 mode="normal"openScript=nil
 local candidate=setup()if mutate then mutate(candidate)end
 local original=snapshot(candidate)local accepted=run(candidate,source)
 assert(not accepted,"Unsafe installer accepted:"..name)unchanged(candidate,original,false)
 table.insert(rejected,name)
end
for _,kind in {"not-studio","running","paused-play"}do reject(kind,function()mode=kind end)end
for _,name in {"Cooking_Cheff","SpeedMonkey"}do reject("foreign-root:"..name,function(p)local x=r.Instance.new("Folder")x.Name=name x.Parent=p:GetService("Workspace")end)end
reject("variant-B",function(p)resolve(p,"Workspace/CornMap"):SetAttribute("HarvestArtVariant","B")end)
reject("foreign-map",function(p)resolve(p,"Workspace/CornMap"):SetAttribute("corn_project_id","foreign")end)
reject("wrong-field",function(p)resolve(p,"Workspace/CornMap/FieldZone").Size=r.Vector3.new(840,10,840)end)
reject("live-runtime",function(p)local x=r.Instance.new("Folder")x.Name="Runtime"x.Parent=resolve(p,"Workspace/CornMap")end)
reject("foreign-Source",function(p)local x=r.Instance.new("ModuleScript")x.Name="RhythmController"x.Source="return {}"x.Parent=p:GetService("ReplicatedStorage")end)
reject("foreign-code-child",function(p)local x=r.Instance.new("Folder")x.Name="Unknown"x.Parent=resolve(p,"ReplicatedStorage/GameShared")end)
reject("changed-Fog",function(p)resolve(p,"Workspace/CornfieldFog/RuntimeServer").Source..="\n-- foreign"end)
reject("open-Fog",function(p)openScript=resolve(p,"Workspace/CornfieldFog/RuntimeServer")end)
for path in changed do
 reject("manual-Source:"..path,function(p)resolve(p,path).Source..="\n-- manual"end)
 reject("open-Source:"..path,function(p)openScript=resolve(p,path)end)
 reject("partial-existing:"..path,function(p)for _,e in payload.entries do if e.path==path then resolve(p,path).Source=e.source end end end)
 reject("missing-Source:"..path,function(p)resolve(p,path):Destroy()end)
end
for path in added do
 local function insert(p,class,source)
  local x=r.Instance.new(class)x.Name=path:match("[^/]+$")if source then x.Source=source end x.Parent=resolve(p,path:match("^(.*)/[^/]+$"))
 end
 reject("added-class-collision:"..path,function(p)insert(p,"Folder")end)
 reject("partial-addition:"..path,function(p)for _,e in payload.entries do if e.path==path then insert(p,"ModuleScript",e.source)end end end)
end
for point=1,2 do
 local injected=code:gsub("local ok, problem = pcall%(function%(%)","local injectedWrites=0\nlocal ok, problem = pcall(function()",1)
 injected=injected:gsub("item.Source = entry.source","item.Source = entry.source\ninjectedWrites+=1\nif injectedWrites=="..point.." then error(\"Injected write failure\")end",1)
 reject("existing-write-rollback:"..point,nil,injected)
 local created=code:gsub("local ok, problem = pcall%(function%(%)","local injectedCreates=0\nlocal ok, problem = pcall(function()",1)
 created=created:gsub("item.Parent = parent","item.Parent = parent\ninjectedCreates+=1\nif injectedCreates=="..point.." then error(\"Injected creation failure\")end",1)
 reject("created-module-rollback:"..point,nil,created)
end
reject("payload-hash",nil,code:gsub('"owner":"corn_flashlight_20261020"','"owner":"foreign_flashlight_2026"',1))
print(serde.encode("json",{passed=true,baseline=153,final=155,changed=2,added=2,repeatChanged=0,crlfAccepted=true,rejected=rejected}))
'''
result = subprocess.run([str(ROOT / ".tools/lune/lune.exe"), "run", "-"], input=LUA.encode(), cwd=ROOT,
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
(f.builder.OUT / "installer-fixture-run.log").write_bytes(result.stdout + b"\n" + result.stderr)
if result.returncode:
    raise RuntimeError(result.stderr.decode("utf-8", "replace"))
installer_report = json.loads(result.stdout)
report = {"passed": True, "baseline_sha256": f.BASELINE_HASH, "installer_sha256": MANIFEST["installer_sha256"],
    "payload_sha256": MANIFEST["payload_sha256"], "installer": installer_report,
    "save_positive": {"sources": 155, "source_changes": 2, "added_modules": 2, "finite_camera_frames": 2,
        "world_lighting_mesh_metadata_exact": True}, "unsafe_dom_rejected": len(rejected), "unsafe_dom_cases": rejected,
    "unsafe_terrain_rejected": len(terrain_rejected), "unsafe_terrain_cases": terrain_rejected,
    "scene_written": False, "native_acceptance": False}
(f.builder.OUT / "pipeline-fixtures.json").write_bytes((json.dumps(report, ensure_ascii=False, indent=2) + "\n").encode())
print(json.dumps({key: value for key, value in report.items() if key not in {"unsafe_dom_cases", "unsafe_terrain_cases"}}))
