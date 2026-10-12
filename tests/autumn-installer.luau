-- File-backed installer refusal/rollback, never serializes or changes input scene.
local adapter=require("./scene-adapter")
local fs,r,I=adapter.fs,adapter.r,adapter.I
local bytes=fs.readFile("place/Children_of_corn.before-autumn-20261012.rbxl")
local function setup() return r.deserializePlace(bytes) end
local function snapshot(place)
 local out={}
 for _,item in place:GetDescendants() do
  if item:IsA("BasePart") then out[item]={cf=item.CFrame,size=item.Size,parent=item.Parent}
  elseif item:IsA("LuaSourceContainer") then out[item]={source=item.Source,parent=item.Parent} end
 end
 return out
end
local function assertWorld(before, sources)
 for item,state in before do
  assert(item.Parent==state.parent,"Parent changed")
  if state.cf then assert(item.CFrame==state.cf and item.Size==state.size,"Author geometry changed")
  elseif sources then assert(item.Source==state.source,"Unapproved Source changed") end
 end
end
local function controllers(p) return p:GetService("StarterPlayer").StarterPlayerScripts.GameClient.Controllers end
local p=setup();local prior=snapshot(p);local update=adapter.runner(p,nil,"scripts/install-autumn.luau")
assert(update());assertWorld(prior,false)
assert(controllers(p).CornAppearanceController:IsA("ModuleScript"));assert(controllers(p).CornWindController:IsA("ModuleScript"));assert(p:GetService("ReplicatedStorage").GameShared.Game.CornAppearance:IsA("ModuleScript"))
local count=0;for _,v in p:GetDescendants() do if v:IsA("LuaSourceContainer") then count+=1 end end
assert(count==31);local installed=snapshot(p);assert(update());assertWorld(installed,true)
print("PASS: 28 to31 sources, real baseline/repeat preserves authored geometry")
for _,kind in {"wrong","manual","open","collision","missing","extra"} do
 local fixture=setup();local solo=fixture:GetService("ServerScriptService").GameServer.Game.SoloRound
 if kind=="wrong" then local v=I.new("Folder");v.Name="Asmr_Base";v.Parent=fixture:GetService("Workspace") end
 if kind=="manual" then solo.Source..="\n-- author edit" end
 if kind=="collision" then local v=I.new("Folder");v.Name="CornAppearanceController";v.Parent=controllers(fixture) end
 if kind=="missing" then fixture:GetService("ReplicatedStorage").GameShared.Game.MinimapGeometry:Destroy() end
 if kind=="extra" then local v=I.new("ModuleScript");v.Name="AuthorExtra";v.Source="return {}";v.Parent=controllers(fixture) end
 local before=snapshot(fixture)
 local fn=adapter.runner(fixture,if kind=="open" then solo else nil,"scripts/install-autumn.luau")
 assert(not fn(),"Guard failed: "..kind);assertWorld(before,true)
 if kind=="collision" then assert(controllers(fixture).CornAppearanceController:IsA("Folder"))
 else assert(not controllers(fixture):FindFirstChild("CornAppearanceController")) end
end
print("PASS: wrong game/manualSource/open tab/collision refuse before mutations")
local source,n=fs.readFile("scripts/install-autumn.luau"):gsub("item.Parent=resolve%(parentPath%)",'item.Parent=resolve(parentPath)\nerror("Injected fixture failure")')
assert(n==1);fs.writeFile("build/autumn-failure-fixture.luau",source)
local failed=setup();local before=snapshot(failed);local fn=adapter.runner(failed,nil,"build/autumn-failure-fixture.luau")
assert(not fn());assertWorld(before,true);assert(not controllers(failed):FindFirstChild("CornAppearanceController"))
print("PASS: injected failure rolls back all Sources and new module")
