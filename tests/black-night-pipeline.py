"""Exercise the actual generated installer and strict saved-DOM/Terrain guards.

Reads accepted engine bytes; synthetic mutations remain in memory. No scene
serialization, Studio connection, cloud publication or production file edits.
"""
import copy
import gzip
import importlib.util
import json
from pathlib import Path
import pickle
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("night_pipeline_verifier", ROOT / "scripts/verify-black-night-copy.py")
f = importlib.util.module_from_spec(spec)
spec.loader.exec_module(f)
assert f.sha256(f.BASELINE) == f.BASELINE_HASH and f.BASELINE.stat().st_size == f.BASELINE_BYTES
manifest = json.loads((f.builder.OUT / "pipeline-manifest.json").read_bytes())
installer = ROOT / "scripts/install-black-night.luau"
assert f.sha256(installer) == manifest["installer_sha256"]
assert f.sha256(f.builder.OUT / "payload.json") == manifest["payload_sha256"]
_, SOURCES, CLASSES, _ = f.builder.mapping()
ASSETS = f.fog.current_sources()
MESH_ONLY = "--mesh-cache-only" in sys.argv
if MESH_ONLY:
    # This local cache was produced once by read-only known_dom on both engine
    # files. Input hashes are rechecked; no second whole-scene reader is needed.
    with gzip.open(f.builder.OUT / "saved-dom-cache.pkl.gz", "rb") as stream:
        DOM_CACHE = pickle.load(stream)
    assert DOM_CACHE["baseline_sha256"] == f.sha256(f.BASELINE)
    assert DOM_CACHE["candidate_sha256"] == f.sha256(ROOT / "place/Children_of_corn.rbxl")
    BEFORE = DOM_CACHE["before"]
else:
    BEFORE, _ = f.r.p.known_dom(f.BASELINE)
assert len(BEFORE) == 4526


def scalar(kind, value):
    return [kind, str(value), []]


AFTER = {path: node for path, node in BEFORE.items() if path not in f.AUTHOR_REMOVALS}
for path in f.DECLARED_SOURCES:
    AFTER[path] = copy.deepcopy(BEFORE[path])
    AFTER[path]["properties"]["Source"] = scalar("string", SOURCES[path])
AFTER["Lighting"] = copy.deepcopy(AFTER["Lighting"])
AFTER["Lighting"]["properties"]["Brightness"] = scalar("float", 0)


def validate(after):
    return f.validate_dom(BEFORE, after, SOURCES, CLASSES, ASSETS)


def counter_fixtures():
    contract = f.vertex_cache_contract(BEFORE)
    refused = 0
    for path, row in contract.items():
        original, expected = scalar("int", 0), scalar("int", row["after"])
        f.validate_vertex_cache(path, original, expected, contract)
        invalid = [
            (original, scalar("int", row["after"] + 1)),
            (original, scalar("int", -1)),
            (original, scalar("float", row["after"])),
            (original, scalar("int", 0)),
            (original, ["int", str(row["after"]), [["extra", scalar("int", 1)]]]),
            (scalar("int", row["after"]), expected),
            (["int", "0", [["extra", scalar("int", 1)]]], expected),
            (scalar("string", 0), expected),
        ]
        for before, after in invalid:
            try:
                f.validate_vertex_cache(path, before, after, contract)
            except ValueError:
                refused += 1
            else:
                raise AssertionError("Unsafe rebuilt counter accepted: " + path)
    for path in ("Workspace/CornMap/Ground", "Workspace/CornMap/UnknownMesh", "ServerStorage/Foreign"):
        try:
            f.validate_vertex_cache(path, scalar("int", 0), scalar("int", 72), contract)
        except ValueError:
            refused += 1
        else:
            raise AssertionError("Nonowned counter exception accepted")
    # Verify the guard is actually used by the full scene validation, including
    # wrong metadata outside the reviewed 242 paths and unchanged attribute links.
    rebuilt = AFTER.copy()
    for path, row in contract.items():
        rebuilt[path] = copy.deepcopy(rebuilt[path])
        rebuilt[path]["properties"]["VertexCount"] = scalar("int", row["after"])
    accepted = validate(rebuilt)
    assert accepted["rebuilt_mesh_vertex_counters"] == 242
    first = next(iter(contract))
    nonowned = next(path for path, node in BEFORE.items() if node["class"] == "MeshPart" and path not in contract)
    full_refused = []
    for name, path, prop, value in (
        ("wrong count", first, "VertexCount", scalar("int", contract[first]["after"] + 1)),
        ("missing count", first, "VertexCount", None),
        ("nonowned count", nonowned, "VertexCount", scalar("int", 999999)),
        ("changed mesh-key attributes", first, "AttributesSerialize", scalar("BinaryString", "00")),
    ):
        altered = rebuilt.copy()
        altered[path] = copy.deepcopy(rebuilt[path])
        if value is None:
            altered[path]["properties"].pop(prop)
        else:
            altered[path]["properties"][prop] = value
        try:
            validate(altered)
        except (ValueError, KeyError):
            full_refused.append(name)
        else:
            raise AssertionError("Full scene skipped counter guard: " + name)
    return {"passed": True, "owned_positive_counters": 242, "per_counter_negative_shapes": 8,
        "unsafe_counter_refusals": refused, "full_dom_refusals": full_refused,
        "review_sha256": f.MESH_CACHE_REVIEW_HASH, "catalog_sha256": f.CATALOG_HASH}


counter_report = counter_fixtures()
if MESH_ONLY:
    actual = validate(DOM_CACHE["canonical"])
    assert actual["rebuilt_mesh_vertex_counters"] == 242
    focused = counter_report | {"cached_actual_dom_pass": True,
        "candidate_sha256": DOM_CACHE["candidate_sha256"], "scene_written": False,
        "verifier_sha256": f.sha256(ROOT / "scripts/verify-black-night-copy.py"),
        "fixture_sha256": f.sha256(Path(__file__))}
    (f.builder.OUT / "mesh-counter-fixtures.json").write_bytes((json.dumps(focused, indent=2) + "\n").encode())
    print(json.dumps(focused))
    raise SystemExit(0)


report = validate(AFTER)
assert report["passed"] and report["complete"] and report["removed_instances"] == 5
assert report["source_changes"] == sorted(f.DECLARED_SOURCES)
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
    raise AssertionError("Unsafe night save accepted: " + name)


for path in sorted(set(SOURCES) | set(ASSETS)):
    rejects("foreign Source:" + path, lambda a, n, p=path: n(p)["properties"].__setitem__("Source", scalar("string", "return 'foreign'")))
for path in sorted(f.DECLARED_SOURCES):
    rejects("Source identity:" + path, lambda a, n, p=path: n(p)["properties"].__setitem__("UniqueId", scalar("UniqueId", "9" * 32)))
    rejects("Source capabilities:" + path, lambda a, n, p=path: n(p)["properties"].__setitem__("Capabilities", scalar("SecurityCapabilities", 1)))
    rejects("missing declared Source:" + path, lambda a, n, p=path: a.__setitem__(p, BEFORE[p]))
    rejects("Source class:" + path, lambda a, n, p=path: n(p).__setitem__("class", "Script"))
for path in sorted(f.AUTHOR_REMOVALS):
    rejects("restored author Lighting object:" + path, lambda a, n, p=path: a.__setitem__(p, BEFORE[p]))
rejects("extra world instance", lambda a, n: a.__setitem__("Workspace/Foreign", copy.deepcopy(BEFORE["Workspace/CornMap/Ground"])))
rejects("removed authored map", lambda a, n: a.pop("Workspace/CornMap"))
rejects("map class", lambda a, n: n("Workspace/CornMap").__setitem__("class", "Folder"))
rejects("world renamed", lambda a, n: n("Workspace/CornMap/Ground")["properties"].__setitem__("Name", scalar("string", "Foreign")))
rejects("world attributes", lambda a, n: n("Workspace/CornMap")["properties"].__setitem__("AttributesSerialize", scalar("BinaryString", "00")))
rejects("world physics", lambda a, n: n("Workspace/CornMap/Ground")["properties"].__setitem__("CanCollide", scalar("bool", "false")))
rejects("world size", lambda a, n: n("Workspace/CornMap/Ground")["properties"]["size"][2][0][1].__setitem__(1, "631"))
rejects("world reparent", lambda a, n: a.__setitem__("Workspace/MovedGround", a.pop("Workspace/CornMap/Ground")))
rejects("wrong Brightness", lambda a, n: n("Lighting")["properties"].__setitem__("Brightness", scalar("float", ".1")))
for prop in ("FogStart", "FogEnd", "OutdoorAmbient", "Ambient"):
    rejects("unapproved Lighting:" + prop, lambda a, n, p=prop: n("Lighting")["properties"].__setitem__(p, scalar("float", "999")))
for prop in ("CFrame", "Focus"):
    rejects("malformed Camera:" + prop, lambda a, n, p=prop: n("Workspace/Camera")["properties"].__setitem__(p, scalar("CoordinateFrame", "arbitrary")))
    for value in ("nan", "inf", "1e40"):
        rejects("nonfinite/overflow Camera:" + prop + ":" + value, lambda a, n, p=prop, v=value: n("Workspace/Camera")["properties"][p][2][0][1].__setitem__(1, v))
    rejects("duplicate Camera component:" + prop, lambda a, n, p=prop: n("Workspace/Camera")["properties"][p][2].__setitem__(1, copy.deepcopy(n("Workspace/Camera")["properties"][p][2][0])))
camera = AFTER.copy()
camera["Workspace/Camera"] = copy.deepcopy(camera["Workspace/Camera"])
for prop in ("CFrame", "Focus"):
    camera["Workspace/Camera"]["properties"][prop][2][0][1][1] = "12.5"
validate(camera)
terrain = f.r.p.unknown_properties(f.BASELINE)
f.r.validate_unknown(terrain, copy.deepcopy(terrain))
terrain_rejected = []
for key in ("payload_sha256", "payload_bytes", "instance_count"):
    bad = copy.deepcopy(terrain)
    row = next(iter(bad["properties"].values()))
    row[key] = "0" * 64 if key == "payload_sha256" else row[key] + 1
    try:
        f.r.validate_unknown(terrain, bad)
    except ValueError:
        terrain_rejected.append(key)
    else:
        raise AssertionError("Unsafe raw Terrain accepted: " + key)

LUA = r'''
local r,fs,serde=require("@lune/roblox"),require("@lune/fs"),require("@lune/serde")
local raw=fs.readFile(".artifacts/playtests/2026-10-20-black-night/payload.json")
local payload=serde.decode("json",raw)
local code=fs.readFile("scripts/install-black-night.luau")
local bytes=fs.readFile("place/Children_of_corn.before-black-night-20261020.rbxl")
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
local changed={}
for _,entry in payload.entries do if entry.before~=entry.after then changed[entry.path]=true end end
local function snapshot(place)
 local result={}
 for _,item in place:GetDescendants() do
  local props={}
  for _,key in {"Source","Disabled","RunContext","CFrame","Size","TextureID","MeshId","Color","Material","CanCollide","CanQuery","CanTouch","Transparency","Brightness","Ambient","OutdoorAmbient","FogStart","FogEnd","FogColor","CameraType","FieldOfView"} do
   local ok,value=pcall(function()return item[key]end) if ok then props[key]=value end
  end
  result[item]={parent=item.Parent,name=item.Name,class=item.ClassName,attrs=item:GetAttributes(),tags=item:GetTags(),props=props}
 end
 return result
end
local function equal(a,b)
 for k,v in a do assert(b[k]==v,"Changed table value") end
 for k,v in b do assert(a[k]==v,"Added table value") end
end
local function unchanged(place,before,allowSources)
 local count=0
 for _,item in place:GetDescendants() do
  count+=1 local row=assert(before[item],"Unexpected new instance")
  assert(item.Parent==row.parent and item.Name==row.name and item.ClassName==row.class,"Topology changed")
  equal(row.attrs,item:GetAttributes()) equal(row.tags,item:GetTags())
  local path=item:GetFullName():gsub("%.","/")
  for k,v in row.props do assert((allowSources and k=="Source" and changed[path])or item[k]==v,"Unexpected property mutation:"..path.."/"..k) end
 end
 local expected=0 for _ in before do expected+=1 end assert(count==expected,"Instance count changed")
end
local place=setup() local before=snapshot(place)
local ok,result=run(place) assert(ok,tostring(result)) assert(result.changed==2 and result.created==0 and result.totalSources==153)
unchanged(place,before,true)
for _,entry in payload.entries do assert(serde.hash("sha256",resolve(place,entry.path).Source:gsub("\r\n","\n"))==entry.after) end
local after=snapshot(place)
ok,result=run(place) assert(ok and result.changed==0 and result.created==0 and result.repeated)
unchanged(place,after,false)
local crlf=setup()
for _,entry in payload.entries do local item=resolve(crlf,entry.path)item.Source=item.Source:gsub("\r\n","\n"):gsub("\n","\r\n") end
ok,result=run(crlf) assert(ok and result.changed==2)
local rejected={}
local function reject(name,mutate,source)
 mode="normal" openScript=nil
 local candidate=setup() if mutate then mutate(candidate) end
 local original=snapshot(candidate) local accepted=run(candidate,source)
 assert(not accepted,"Unsafe installer accepted:"..name) unchanged(candidate,original,false)
 table.insert(rejected,name)
end
for _,kind in {"not-studio","running","paused-play"} do reject(kind,function()mode=kind end) end
for _,name in {"Asmr_Base","Cooking_Cheff","SpeedMonkey"} do reject("foreign-root:"..name,function(p)local part=r.Instance.new("Folder")part.Name=name part.Parent=p:GetService("Workspace")end)end
reject("variant-B",function(p)resolve(p,"Workspace/CornMap"):SetAttribute("HarvestArtVariant","B")end)
reject("map-owner",function(p)resolve(p,"Workspace/CornMap"):SetAttribute("corn_project_id","foreign")end)
reject("wrong-field",function(p)resolve(p,"Workspace/CornMap/FieldZone").Size=r.Vector3.new(840,10,840)end)
reject("live-runtime",function(p)local x=r.Instance.new("Folder")x.Name="Runtime"x.Parent=resolve(p,"Workspace/CornMap")end)
reject("foreign-source",function(p)local x=r.Instance.new("ModuleScript")x.Name="RhythmController"x.Source="return {}"x.Parent=p:GetService("ReplicatedStorage")end)
reject("foreign-owned-code",function(p)local x=r.Instance.new("Folder")x.Name="Unknown"x.Parent=resolve(p,"ReplicatedStorage/GameShared")end)
reject("changed-Fog",function(p)resolve(p,"Workspace/CornfieldFog/RuntimeServer").Source..="\n-- foreign"end)
reject("open-Fog",function(p)openScript=resolve(p,"Workspace/CornfieldFog/RuntimeServer")end)
for path in changed do
 reject("manual-Source:"..path,function(p)resolve(p,path).Source..="\n-- manual"end)
 reject("open-Source:"..path,function(p)openScript=resolve(p,path)end)
 reject("partial-install:"..path,function(p)for _,e in payload.entries do if e.path==path then resolve(p,path).Source=e.source end end end)
 reject("missing-Source:"..path,function(p)resolve(p,path):Destroy()end)
end
for point=1,2 do
 local injected=code:gsub("local ok, problem = pcall%(function%(%)","local injectedWrites = 0\nlocal ok, problem = pcall(function()",1)
 injected=injected:gsub("item.Source = entry.source","item.Source = entry.source\ninjectedWrites += 1\nif injectedWrites == "..point.." then error(\"Injected write failure\") end",1)
 reject("rollback:"..point,nil,injected)
end
reject("payload-hash",nil,code:gsub('"owner":"corn_black_night_20261020"','"owner":"foreign_black_night_2026"',1))
print(serde.encode("json",{passed=true,baseline=153,changed=2,added=0,repeatChanged=0,crlfAccepted=true,rejected=rejected}))
'''
result = subprocess.run([str(ROOT / ".tools/lune/lune.exe"), "run", "-"], input=LUA.encode(), cwd=ROOT,
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
installer_report = json.loads(result.stdout)
report = {"passed": True, "baseline_sha256": f.BASELINE_HASH, "installer_sha256": f.sha256(installer),
    "payload_sha256": manifest["payload_sha256"], "installer": installer_report,
    "save_positive": {"sources": 153, "source_changes": 2, "author_preexisting_removed_lighting": 5,
                      "author_preexisting_brightness": 0, "finite_camera_frames": 2},
    "unsafe_dom_rejected": len(rejected), "unsafe_dom_cases": rejected,
    "unsafe_terrain_rejected": len(terrain_rejected), "unsafe_terrain_cases": terrain_rejected,
    "mesh_counter_guards": counter_report, "scene_written": False, "native_acceptance": False}
output = f.builder.OUT / "pipeline-fixtures.json"
output.write_bytes((json.dumps(report, ensure_ascii=False, indent=2) + "\n").encode())
print(json.dumps({key: value for key, value in report.items() if key not in {"unsafe_dom_cases", "unsafe_terrain_cases"}}, ensure_ascii=False))
