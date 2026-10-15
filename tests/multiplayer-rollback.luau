-- Actual generated installer against the immutable engine baseline in memory.
-- Native Studio networking, authority/physics and engine save are separate tests.
local r, fs = require("@lune/roblox"), require("@lune/fs")
local I = r.Instance
local serde = require("@lune/serde")
local source = fs.readFile(".artifacts/playtests/2026-10-15-multiplayer/initial-attempt/install-initial-multiplayer.luau"):gsub("\r\n", "\n")
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
local rollback = fs.readFile("scripts/rollback-initial-multiplayer.luau"):gsub("\r\n", "\n")
local place = setup()
local original = snapshot(place)
local ok, result = run(place)
assert(ok and result.changed == 7 and result.created == 2, result)
local diagnostics = {}
for _, cls in {"Script", "LocalScript", "StringValue"} do
    local item = I.new(cls)
    item.Name = "CornRollbackFixtureDiagnostic_" .. cls
    if cls == "StringValue" then item.Value = "failed attempt evidence" else item.Source = "-- temporary diagnostic" end
    item.Parent = place.Workspace
    table.insert(diagnostics, item)
end
local withDiagnostics = snapshot(place)
for _, item in diagnostics do original[item] = withDiagnostics[item] end
ok, result = run(place, rollback)
assert(ok and result.changed == 7 and result.removed == 2 and result.sources == 75 and result.totalSources == 78 and result.outsideDiagnosticsUntouched, result)
unchanged(place, original)
for _, item in diagnostics do assert(item.Parent == place.Workspace) end
place:Destroy()
local rejected = {}
local function rejects(name, mutate, injected)
    kind, openScript = "positive", nil
    local fixture = setup()
    local installed, why = run(fixture)
    assert(installed, why)
    kind = name
    mutate(fixture)
    local before = snapshot(fixture)
    local accepted = run(fixture, injected or rollback)
    assert(not accepted, "Unsafe rollback accepted: " .. name)
    unchanged(fixture, before)
    fixture:Destroy()
    table.insert(rejected, name)
end
for _, name in {"not-studio", "running", "paused-play"} do rejects(name, function() end) end
rejects("manual-original", function(p) p.ServerScriptService.GameServer.Services.RoundService.Source ..= "\n-- manual" end)
rejects("manual-new", function(p) p.ServerScriptService.GameServer.Game.TeamRound.Source ..= "\n-- manual" end)
rejects("manual-fog", function(p) p.Workspace.CornfieldFog.RuntimeServer.Source ..= "\n-- manual" end)
rejects("open-new", function(p) openScript=p.ServerScriptService.GameServer.Game.TeamRound end)
rejects("partial-missing-new", function(p) p.ServerScriptService.GameServer.Game.TeamRound:Destroy() end)
rejects("extended-new", function(p) p.ServerScriptService.GameServer.Game.TeamRound:SetAttribute("manual", true) end)
rejects("extra-owned", function(p) local item=I.new("Folder") item.Name="Manual" item.Parent=p.ServerScriptService.GameServer.Game end)
local failedDetach, count = rollback:gsub("item.Parent=nil", "item.Parent=nil\n            error('Injected detach failure')", 1)
assert(count==1)
rejects("detach-error-restores-initial", function() end, failedDetach)
local marker = "    for _,entry in entries do\n        local item=resolve(entry.path)\n        if additions[entry.path] then assert(not item"
local first = assert(rollback:find(marker, 1, true))
local failedVerify = rollback:sub(1, first-1) .. "    error('Injected baseline verification failure')\n" .. rollback:sub(first)
rejects("verification-error-restores-initial", function() end, failedVerify)
print(serde.encode("json", {passed=true, exactInitialSources=80, restoredSources=7, removedModules=2, diagnosticObjectsPreserved=3, originalWorldAndSourcesRestored=true, unsafeCasesRejected=#rejected, cases=rejected, scope="Actual generated initial installer and rollback against immutable baseline in memory; no live Studio or scene writes"}))
