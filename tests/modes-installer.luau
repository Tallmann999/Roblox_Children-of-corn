-- File-backed, in-memory guard/rollback tests. Never saves/serializes the input place.
local adapter=require("./scene-adapter")
local fs,r,I=adapter.fs,adapter.r,adapter.I
local bytes=fs.readFile("place/Children_of_corn.before-lighting-modes-20261010.rbxl")
local function setup()
    local place=r.deserializePlace(bytes)
    return place
end
local function snapshot(place)
    local out={}
    for _,item in place:GetDescendants() do
        if item:IsA("BasePart") then out[item]={cf=item.CFrame,size=item.Size,parent=item.Parent}
        elseif item:IsA("LuaSourceContainer") then out[item]={source=item.Source,parent=item.Parent} end
    end
    return out
end
local function assertWorld(before)
    for item,state in before do if state.cf then
        assert(item.CFrame==state.cf and item.Size==state.size and item.Parent==state.parent,"Author geometry changed")
    end end
end
local place=setup()
local before=snapshot(place)
local install=adapter.runner(place,nil,"scripts/install-modes.luau")
assert(install())
assertWorld(before)
local shared=place:GetService("ReplicatedStorage").GameShared
local client=place:GetService("StarterPlayer").StarterPlayerScripts.GameClient
assert(shared.Game.LightingModes)
local count=0
for _,item in place:GetDescendants() do if item:IsA("LuaSourceContainer") then count+=1 end end
assert(count==23)
assert(install())
assertWorld(before)
print("PASS: lighting modes add one module and update owned code; 23 sources; repeat keeps all authored geometry")
for _,kind in {"wrong","manual","open","collision"} do
    local p=setup()
    local solo=p:GetService("ServerScriptService").GameServer.Game.SoloRound
    if kind=="wrong" then local marker=I.new("Folder");marker.Name="Asmr_Base";marker.Parent=p:GetService("Workspace") end
    if kind=="manual" then solo.Source..="\n-- author edit" end
    if kind=="collision" then local item=I.new("Folder");item.Name="LightingModes";item.Parent=p:GetService("ReplicatedStorage").GameShared.Game end
    local prior=snapshot(p)
    local update=adapter.runner(p,if kind=="open" then solo else nil,"scripts/install-modes.luau")
    assert(not update(),"Guard failed: "..kind)
    assertWorld(prior)
    for item,state in prior do if state.source then assert(item.Source==state.source and item.Parent==state.parent) end end
    if kind == "collision" then
        assert(p:GetService("ReplicatedStorage").GameShared.Game.LightingModes:IsA("Folder"))
    else
        assert(not p:GetService("ReplicatedStorage").GameShared.Game:FindFirstChild("LightingModes"))
    end
end
print("PASS: wrong scene/manual Source/open tab/name collision refused before mutations")
local failureSource,n=fs.readFile("scripts/install-modes.luau"):gsub("item.Parent=resolve%(parentPath%)",'item.Parent=resolve(parentPath)\nerror("Injected fixture failure")')
assert(n==1)
fs.writeFile("build/modes-failure-fixture.luau",failureSource)
local failed=setup()
local prior=snapshot(failed)
local failUpdate=adapter.runner(failed,nil,"build/modes-failure-fixture.luau")
assert(not failUpdate())
assertWorld(prior)
for item,state in prior do if state.source then assert(item.Source==state.source and item.Parent==state.parent) end end
assert(not failed:GetService("ReplicatedStorage").GameShared.Game:FindFirstChild("LightingModes"))

print("PASS: injected installation failure rolls back sources and added modules")
