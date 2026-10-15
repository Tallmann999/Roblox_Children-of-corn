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
local before = snapshot(place)
local ok, result = run(place)
assert(ok, result)
assert(result.sources == 77 and result.totalSources == 80 and result.created == 2 and not result.repeated)
local changed = result.changed
assert(changed > 0 and changed <= 16)
unchanged(place, before, true, true)
local installed = snapshot(place)
ok, result = run(place)
assert(ok and result.changed == 0 and result.created == 0 and result.repeated, result)
unchanged(place, installed)
for _, item in place:GetDescendants() do
	if item:IsA("LuaSourceContainer") then item.Source = item.Source:gsub("\r\n", "\n"):gsub("\n", "\r\n") end
end
local normalized = snapshot(place)
ok, result = run(place)
assert(ok and result.changed == 0 and result.repeated, result)
unchanged(place, normalized)
place:Destroy()

local rejected = {}
local function rejects(name, mutate, isFinal, injected)
	kind, openScript = name, nil
	local fixture = setup()
	if isFinal then
		kind = "positive"
		local installedOk, why = run(fixture)
		assert(installedOk, why)
		kind = name
	end
	mutate(fixture)
	local original = snapshot(fixture)
	local accepted, message = run(fixture, injected)
	assert(not accepted, "Unsafe installer accepted: " .. name)
	assert(type(message) == "string")
	unchanged(fixture, original)
	fixture:Destroy()
	table.insert(rejected, name)
end
for _, name in {"not-studio", "running", "paused-play"} do rejects(name, function() end) end
rejects("wrong-project", function(p) p.Workspace.CornMap:SetAttribute("corn_project_id", "other") end)
rejects("wrong-ground", function(p) p.Workspace.CornMap.Ground.Size = r.Vector3.new(840, 2, 840) end)
rejects("wrong-field", function(p) p.Workspace.CornMap.FieldZone.Size = r.Vector3.new(840, 10, 840) end)
rejects("runtime-present", function(p) local x=I.new("Folder") x.Name="Runtime" x.Parent=p.Workspace.CornMap end)
rejects("manual-source", function(p) p.ServerScriptService.GameServer.Services.RoundService.Source ..= "\n-- manual" end)
rejects("manual-fog", function(p) p.Workspace.CornfieldFog.RuntimeServer.Source ..= "\n-- manual" end)
rejects("missing-original", function(p) p.ServerScriptService.GameServer.Services.RoundService:Destroy() end)
rejects("missing-folder", function(p) p.ServerScriptService.GameServer.Game:Destroy() end)
rejects("extra-code", function(p) local x=I.new("Folder") x.Name="Unexpected" x.Parent=p.ServerScriptService.GameServer end)
rejects("extra-source", function(p) local x=I.new("ModuleScript") x.Name="Unexpected" x.Parent=p.Workspace end)
rejects("duplicate-code", function(p) local x=I.new("ModuleScript") x.Name="RoundService" x.Parent=p.ServerScriptService.GameServer.Services end)
rejects("open-original", function(p) openScript=p.ServerScriptService.GameServer.Services.RoundService end)
rejects("open-fog", function(p) openScript=p.Workspace.CornfieldFog.RuntimeServer end)
rejects("open-new", function(p) openScript=p.ServerScriptService.GameServer.Game.TeamRound end, true)
rejects("partial-addition", function(p) local x=I.new("ModuleScript") x.Name="TeamRound" x.Source="return {}" x.Parent=p.ServerScriptService.GameServer.Game end)
rejects("partial-final", function(p) p.ServerScriptService.GameServer.Game.TeamRound:Destroy() end, true)
rejects("wrong-code-class", function(p)
	local old=p.ServerScriptService.GameServer.Services.RoundService
	local x=I.new("Folder") x.Name=old.Name x.Parent=old.Parent old:Destroy()
end)
rejects("source-payload-mismatch", function() end, false,
	(source:gsub("local expectedClasses=", "for _, entry in entries do if entry.source then entry.source ..= 'tampered' break end end\nlocal expectedClasses=", 1)))
local createMark = '            item.Parent=assert(resolve(string.match(entry.path,"^(.*)/[^/]+$")))'
local createStart, createEnd = assert(source:find(createMark, 1, true))
local failedCreate = source:sub(1, createEnd) .. "\n            if #created == 1 then error('Injected creation failure') end" .. source:sub(createEnd+1)
assert(createStart < createEnd)
rejects("rollback-created-and-sources", function() end, false, failedCreate)
local old = "    for _,entry in entries do\n        local item=resolve(entry.path)\n        assert(item and digest"
assert(source:find(old, 1, true), "Missing rollback insertion point")
local startAt, endAt = assert(source:find(old, 1, true))
local failedFinal = source:sub(1, startAt-1) .. "    error('Injected final verification failure')\n" .. source:sub(startAt)
rejects("rollback-after-all-writes", function() end, false, failedFinal)
assert(serde.hash("sha256", bytes) == "493bc1f9b512d618d0a815b2197e3af854f775cd711b363db2906d8fbaf1fb68")
print(serde.encode("json", {passed=true, baselineSources=78, finalSources=80, projectSources=77, created=2, changed=changed,
	unsafeCasesRejected=#rejected, cases=rejected, repeatAndCrLf=true,
	scope="Actual generated installer, immutable engine baseline in-memory; no scene writes, Studio Play or networking claims"}))
