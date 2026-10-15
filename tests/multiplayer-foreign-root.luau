-- Actual generated installer against the immutable engine baseline in memory.
-- Native Studio networking, authority/physics and engine save are separate tests.
local r, fs = require("@lune/roblox"), require("@lune/fs")
local I = r.Instance
local serde = require("@lune/serde")
local source = fs.readFile("scripts/install-multiplayer.luau"):gsub("\r\n", "\n")
local bytes = fs.readFile("place/Children_of_corn.before-multiplayer-20261015.rbxl")
assert(serde.hash("sha256", bytes) == "493bc1f9b512d618d0a815b2197e3af854f775cd711b363db2906d8fbaf1fb68")
local kind, openScript = "positive", nil
r.implementMethod("RunService", "IsStudio", function() return kind ~= "not-studio" end)
r.implementMethod("RunService", "IsRunning", function() return kind == "running" end)
r.implementMethod("RunService", "IsEdit", function() return kind ~= "running" and kind ~= "paused-play" end)
r.implementMethod("ChangeHistoryService", "SetWaypoint", function() end)
r.implementMethod("ScriptEditorService", "FindScriptDocument", function(_, item)
	return if item == openScript then {} else nil
end)
r.implementMethod("EncodingService", "ComputeStringHash", function(_, value, algorithm)
	assert(algorithm == r.Enum.HashAlgorithm.Sha256)
	local hex = serde.hash("sha256", value)
	return (hex:gsub("..", function(pair) return string.char(assert(tonumber(pair, 16))) end))
end)
local function resolve(place, path)
	local item = place
	for _, name in path:split("/") do item = item and item:FindFirstChild(name) end
	return item
end
local function setup()
	local place = r.deserializePlace(bytes)
	for _, name in {"RunService", "ScriptEditorService", "EncodingService", "ChangeHistoryService"} do place:GetService(name) end
	return place
end
local function run(place, code)
	local fn = assert(loadstring(code or source))
	setfenv(fn, setmetatable({game = place, Instance = I, Vector3 = r.Vector3, Enum = r.Enum}, {__index=getfenv()}))
	return pcall(fn)
end
local function snapshot(place)
	local result = {}
	for _, item in place:GetDescendants() do
		local values = {}
		for _, key in {"Source", "Disabled", "RunContext", "CFrame", "Size", "TextureID", "MeshId", "Color", "Material", "CanCollide", "Transparency", "WorldPivotData", "PrimaryPart", "Brightness", "Ambient", "OutdoorAmbient", "FogStart", "FogEnd", "FogColor", "CameraType", "FieldOfView"} do
			local ok, value = pcall(function() return item[key] end)
			if ok then values[key] = value end
		end
		result[item] = {parent=item.Parent, name=item.Name, class=item.ClassName, attrs=item:GetAttributes(), tags=item:GetTags(), values=values}
	end
	return result
end
local function equal(a, b)
	for key, value in a do assert(b[key] == value, "Table value changed: " .. tostring(key)) end
	for key, value in b do assert(a[key] == value, "Table value added: " .. tostring(key)) end
end
local additions = {
	["ServerScriptService/GameServer/Game/TeamRound"]=true,
	["ServerScriptService/GameServer/Game/RoundParticipant"]=true,
}
local function pathOf(item)
	return item:GetFullName():gsub("%.", "/")
end
local function unchanged(place, before, allowSources, allowAdditions)
	local count = 0
	for _, item in place:GetDescendants() do
		local state = before[item]
		if state then
			assert(item.Parent == state.parent and item.Name == state.name and item.ClassName == state.class, "Original topology changed")
			equal(state.attrs, item:GetAttributes())
			equal(state.tags, item:GetTags())
			for key, value in state.values do
				assert((allowSources and key == "Source") or item[key] == value, "Unapproved mutation: " .. item:GetFullName() .. "/" .. key)
			end
			before[item] = nil
		else
			assert(allowAdditions and additions[pathOf(item)] and item.ClassName == "ModuleScript", "Unexpected new instance")
			count += 1
		end
	end
	assert(next(before) == nil, "Original instance removed")
	assert(count == (if allowAdditions then 2 else 0), "Added Module count differs")
end
local place = setup()
place.ReplicatedStorage.GameShared:Destroy()
place.ServerScriptService.GameServer:Destroy()
place.StarterPlayer.StarterPlayerScripts.GameClient:Destroy()
local server, client = I.new("Folder"), I.new("Folder")
server.Name="GameServer" server.Parent=place.ServerScriptService
client.Name="GameClient" client.Parent=place.StarterPlayer.StarterPlayerScripts
for _, row in {{server,"RhythmService"},{client,"RhythmController"},{client,"DanceClip"}} do
    local item=I.new("ModuleScript") item.Name=row[2] item.Source="return {foreign=true}" item.Parent=row[1]
end
assert(place.Workspace.CornMap:GetAttribute("corn_project_id")=="children_of_corn" and place.Workspace.CornMap.Ground.Size.X==630)
local before=snapshot(place)
local ok, why=run(place)
assert(not ok and type(why)=="string")
unchanged(place,before)
local rollback=fs.readFile("scripts/rollback-initial-multiplayer.luau"):gsub("\r\n","\n")
before=snapshot(place)
ok,why=run(place,rollback)
assert(not ok and type(why)=="string")
unchanged(place,before)
place:Destroy()
print(serde.encode("json",{passed=true,validCornMapWithForeignCode=true,installerRefused=true,initialRollbackRefused=true,mutations=0,scope="In-memory explicit foreign-owned-code replacement fixture; native live Studio remains untouched"}))
