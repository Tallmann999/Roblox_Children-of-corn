-- Execute the generated source installer and author-Part transfer in memory.
local r, fs, serde = require("@lune/roblox"), require("@lune/fs"), require("@lune/serde")
local payload = serde.decode("json", fs.readFile(".artifacts/playtests/2026-10-20-flashlight-optics/payload.json"))
local code = fs.readFile("scripts/install-flashlight-author.luau")
local transfer = fs.readFile("scripts/install-flashlight-author-settings.luau")
local bytes = fs.readFile("place/Children_of_corn.before-flashlight-author-20261020.rbxl")
local mode, open = "edit", nil
r.implementMethod("RunService", "IsStudio", function() return mode ~= "foreign" end)
r.implementMethod("RunService", "IsEdit", function() return mode == "edit" end)
r.implementMethod("RunService", "IsRunning", function() return mode == "play" end)
r.implementMethod("ScriptEditorService", "FindScriptDocument", function(_, s) return if s == open then {} else nil end)
r.implementMethod("ChangeHistoryService", "SetWaypoint", function() end)
r.implementMethod("HttpService", "JSONDecode", function(_, s) return serde.decode("json", s) end)
r.implementMethod("EncodingService", "ComputeStringHash", function(_, s) return (serde.hash("sha256",s):gsub("..", function(x) return string.char(tonumber(x,16)) end)) end)
local function resolve(p, path)
	for _, name in path:split("/") do p = p and p:FindFirstChild(name) end
	return p
end
local function setup()
	local p = r.deserializePlace(bytes)
	for _, name in {"RunService","ScriptEditorService","ChangeHistoryService","HttpService","EncodingService"} do p:GetService(name) end
	return p
end
local function run(p, source)
	local fn = assert(loadstring(source or code))
	setfenv(fn, setmetatable({game=p, workspace=p:GetService("Workspace"), Instance=r.Instance,Enum=r.Enum,Vector3=r.Vector3,Color3=r.Color3},{__index=getfenv()}))
	return pcall(fn)
end
local function snapshot(p)
	local out={}
	for _,d in p:GetDescendants() do out[d]={parent=d.Parent,name=d.Name,source=if d:IsA("LuaSourceContainer") then d.Source else nil} end
	return out
end
local function unchanged(p,before)
	local n=0
	for _,d in p:GetDescendants() do n+=1;local old=assert(before[d],"new node leaked");assert(d.Parent==old.parent and d.Name==old.name);if old.source then assert(d.Source==old.source,"Source not rolled back") end end
	local old=0;for _ in before do old+=1 end;assert(n==old)
end
local p=setup();local ok,v=run(p);assert(ok,tostring(v));assert(v.changed==2 and v.created==1 and v.totalSources==156)
for _,e in payload.entries do assert(serde.hash("sha256",resolve(p,e.path).Source:gsub("\r\n","\n"))==e.after) end
local final=snapshot(p);ok,v=run(p);assert(ok and v.repeated and v.changed==0 and v.created==0);unchanged(p,final)
local rejected={}
local function reject(name,edit,source)
	mode,open="edit",nil;local candidate=setup();if edit then edit(candidate) end;local before=snapshot(candidate)
	local accepted=run(candidate,source);assert(not accepted,"Unsafe install accepted: "..name);unchanged(candidate,before);table.insert(rejected,name)
end
for _,state in {"foreign","play","paused"} do reject(state,function() mode=state end) end
reject("B",function(x)x.Workspace.CornMap:SetAttribute("HarvestArtVariant","B")end)
reject("foreign-root",function(x)local d=r.Instance.new("Folder");d.Name="Cooking_Cheff";d.Parent=x.Workspace end)
reject("wrong-field",function(x)x.Workspace.CornMap.Ground.Size=r.Vector3.new(1200,2,1200)end)
for _,e in payload.entries do if e.before and e.source then
	reject("manual:"..e.path,function(x)resolve(x,e.path).Source..="\n-- user edit"end)
	reject("open:"..e.path,function(x)open=resolve(x,e.path)end)
	reject("partial:"..e.path,function(x)resolve(x,e.path).Source=e.source end)
end end
reject("added-name-collision",function(x)local d=r.Instance.new("Folder");d.Name="FlashlightTuning";d.Parent=resolve(x,"StarterPlayer/StarterPlayerScripts/GameClient/Game")end)
reject("extra-Source",function(x)local d=r.Instance.new("ModuleScript");d.Name="RhythmController";d.Parent=x.ReplicatedStorage end)
reject("changed-Fog",function(x)x.Workspace.CornfieldFog.RuntimeServer.Source..="\n-- edit"end)
for point=1,3 do
	local injected="local writes=0;local function inject()writes+=1;if writes=="..point.." then error('write failure')end end\n"..code
	injected=injected:gsub("item.Source = assert%(entry.source%)", "item.Source = assert(entry.source);inject()")
	injected=injected:gsub("item.Source = entry.source", "item.Source = entry.source;inject()")
	reject("rollback:"..point,nil,injected)
end
local function seed(x)
	local part=r.Instance.new("Part");part.Name="Flashlight";part.Parent=x.Workspace
	local l=r.Instance.new("SpotLight");l.Name="SpotLight";l.Range=24;l.Angle=54;l.Brightness=15.08;l.Face=r.Enum.NormalId.Front;l.Shadows=false;l.Enabled=true;l.Color=r.Color3.new(1,1,1);l.Parent=part
	return part,l
end
mode,open="edit",nil;p=setup();local part,light=seed(p)
ok,v=run(p,transfer);assert(ok,tostring(v));assert(v.removedParts==1 and v.retainedAuthorLight)
assert(not p.Workspace:FindFirstChild("Flashlight") and light==p.ReplicatedStorage.CornFlashlightSettings.Wide)
assert(light.Range==24 and light.Angle==54 and math.abs(light.Brightness-15.08)<1e-5)
assert(p.ReplicatedStorage.CornFlashlightSettings.Core.Brightness>light.Brightness)
ok,v=run(p,transfer);assert(ok and v.repeated)
local worldRejected=0
for _,kind in {"extra-child","changed-light","foreign-attributes","unknown-bank"} do
	p=setup();part,light=seed(p)
	if kind=="extra-child" then local d=r.Instance.new("Folder");d.Parent=part
	elseif kind=="changed-light" then light.Range=25
	elseif kind=="foreign-attributes" then part:SetAttribute("UserAuthored",true)
	else local d=r.Instance.new("Folder");d.Name="CornFlashlightSettings";d.Parent=p.ReplicatedStorage end
	local before=snapshot(p);ok=run(p,transfer);assert(not ok);unchanged(p,before);worldRejected+=1
end
local result={passed=true,sourceUpdate={changed=2,added=1,total=156,repeated=true,refusals=rejected},authorTransfer={retainsOriginalSpot=true,partRemoved=true,repeated=true,refusals=worldRejected},sceneWritten=false}
fs.writeFile(".artifacts/playtests/2026-10-20-flashlight-optics/installer-fixtures.json",serde.encode("json",result))
print(serde.encode("json",result))
