-- Actual generated HTTP/direct installer against immutable accepted engine bytes.
-- No scene file write, Studio call, mesh render or engine-save acceptance.
local r, fs = require("@lune/roblox"), require("@lune/fs")
local serde = require("@lune/serde")
local I = r.Instance
local raw = fs.readFile(".artifacts/harvest-install/payload.json")
local payload = serde.decode("json", raw)
local direct = fs.readFile("scripts/install-harvest-direct.luau")
local http = fs.readFile("scripts/install-harvest.luau")
local bytes = fs.readFile("place/Children_of_corn.before-harvest-art-20261016.rbxl")
assert(
	serde.hash("sha256", bytes)
		== "b5084774be98e97a045c6b90a819bdd061b8d4f61b259c3a6e4eb77233ff2646"
)
local mode, openScript = "positive", nil
r.implementMethod("RunService", "IsStudio", function()
	return mode ~= "not-studio"
end)
r.implementMethod("RunService", "IsRunning", function()
	return mode == "running"
end)
r.implementMethod("RunService", "IsEdit", function()
	return mode ~= "running" and mode ~= "paused-play"
end)
r.implementMethod("ChangeHistoryService", "SetWaypoint", function() end)
r.implementMethod("ScriptEditorService", "FindScriptDocument", function(_, item)
	return if item == openScript then {} else nil
end)
r.implementMethod("HttpService", "JSONDecode", function(_, value)
	return serde.decode("json", value)
end)
r.implementMethod("HttpService", "GetAsync", function(_, url)
	assert(url == "http://127.0.0.1:8768/payload.json")
	return raw
end)
r.implementMethod("EncodingService", "ComputeStringHash", function(_, value, algorithm)
	assert(algorithm == r.Enum.HashAlgorithm.Sha256)
	return (
		serde.hash("sha256", value):gsub("..", function(pair)
			return string.char(tonumber(pair, 16))
		end)
	)
end)
local function resolve(place, path)
	local item = place
	for _, name in path:split("/") do
		item = item and item:FindFirstChild(name)
	end
	return item
end
local function pathOf(item)
	return item:GetFullName():gsub("%.", "/")
end
local function setup()
	local place = r.deserializePlace(bytes)
	for _, name in
		{ "RunService", "ScriptEditorService", "EncodingService", "ChangeHistoryService", "HttpService" }
	do
		place:GetService(name)
	end
	return place
end
local function run(place, code, value, isHttp)
	local env = setmetatable(
		{ game = place, Instance = I, Vector3 = r.Vector3, Enum = r.Enum },
		{ __index = getfenv() }
	)
	local fn = assert(loadstring(code or direct))
	setfenv(fn, env)
	if isHttp then
		return pcall(fn)
	end
	local installer = fn()
	return pcall(installer, value or raw)
end
local function snapshot(place)
	local result = {}
	for _, item in place:GetDescendants() do
		local values = {}
		for _, key in
			{
				"Source",
				"Disabled",
				"RunContext",
				"CFrame",
				"Size",
				"TextureID",
				"MeshId",
				"Color",
				"Material",
				"CanCollide",
				"Transparency",
				"WorldPivotData",
				"PrimaryPart",
				"Brightness",
				"Ambient",
				"OutdoorAmbient",
				"FogStart",
				"FogEnd",
				"FogColor",
				"CameraType",
				"FieldOfView",
			}
		do
			local ok, value = pcall(function()
				return item[key]
			end)
			if ok then
				values[key] = value
			end
		end
		result[item] = {
			parent = item.Parent,
			name = item.Name,
			class = item.ClassName,
			attrs = item:GetAttributes(),
			tags = item:GetTags(),
			values = values,
		}
	end
	return result
end
local function equal(a, b)
	for key, value in a do
		assert(b[key] == value, "Table changed: " .. tostring(key))
	end
	for key, value in b do
		assert(a[key] == value, "Table added: " .. tostring(key))
	end
end
local added = {}
for _, row in payload.addedNodes do
	added[row.path] = row.class
end
local function unchanged(place, before, allowInstall)
	local count = 0
	for _, item in place:GetDescendants() do
		local old = before[item]
		if old then
			assert(
				item.Parent == old.parent and item.Name == old.name and item.ClassName == old.class,
				"Original identity/topology changed"
			)
			equal(old.attrs, item:GetAttributes())
			equal(old.tags, item:GetTags())
			for key, value in old.values do
				assert(
					(allowInstall and key == "Source") or item[key] == value,
					"Unexpected mutation: " .. item:GetFullName() .. "/" .. key
				)
			end
			before[item] = nil
		else
			assert(
				allowInstall and added[pathOf(item)] == item.ClassName,
				"Unexpected added object: " .. pathOf(item)
			)
			count += 1
		end
	end
	assert(next(before) == nil, "Original instance removed")
	assert(count == (if allowInstall then #payload.addedNodes else 0))
end
local place = setup()
local before = snapshot(place)
local ok, result = run(place)
assert(ok, result)
assert(
	result.created == #payload.addedNodes
		and result.totalSources == #payload.entries
		and result.changed > 0
		and not result.repeated
)
unchanged(place, before, true)
local installed = snapshot(place)
ok, result = run(place, http, nil, true)
assert(ok and result.repeated and result.changed == 0 and result.created == 0, result)
unchanged(place, installed)
for _, item in place:GetDescendants() do
	if item:IsA("LuaSourceContainer") then
		item.Source = item.Source:gsub("\r\n", "\n"):gsub("\n", "\r\n")
	end
end
local normalized = snapshot(place)
ok, result = run(place)
assert(ok and result.repeated and result.changed == 0, result)
unchanged(place, normalized)
place:Destroy()
local rejected = {}
local function reject(name, mutate, final, code, value)
	mode, openScript = "positive", nil
	local fixture = setup()
	if final then
		local success, why = run(fixture)
		assert(success, why)
	end
	mode = name
	if mutate then
		mutate(fixture)
	end
	local state = snapshot(fixture)
	local accepted, message = run(fixture, code, value)
	assert(not accepted, "Unsafe installation accepted: " .. name)
	assert(type(message) == "string")
	unchanged(fixture, state)
	fixture:Destroy()
	table.insert(rejected, name)
end
for _, name in { "not-studio", "running", "paused-play" } do
	reject(name)
end
reject("wrong-project", function(p)
	p.Workspace.CornMap:SetAttribute("corn_project_id", "foreign")
end)
reject("wrong-ground", function(p)
	p.Workspace.CornMap.Ground.Size = r.Vector3.new(840, 2, 840)
end)
reject("wrong-field", function(p)
	p.Workspace.CornMap.FieldZone.Size = r.Vector3.new(840, 10, 840)
end)
for _, name in { "Runtime", "CornRoundRuntime", "CornClientPlants", "CornClientBackdrop" } do
	reject("runtime-" .. name, function(p)
		local n = I.new("Folder")
		n.Name = name
		n.Parent = p.Workspace.CornMap
	end)
end
for _, name in { "Asmr_Base", "ASMR_Models", "Cooking_Cheff", "SpeedMonkey", "New_+1 speed monkey" } do
	reject("foreign-" .. name, function(p)
		local n = I.new("Model")
		n.Name = name
		n.Parent = p.Workspace
	end)
end
reject("runtime-art", function(p)
	local n = I.new("Folder")
	n.Name = "CornRuntimeArt"
	n.Parent = p.ReplicatedStorage
end)
reject("manual-old", function(p)
	p.ServerScriptService.GameServer.Services.RoundService.Source ..= "\n-- manual"
end)
reject("manual-fog", function(p)
	p.Workspace.CornfieldFog.RuntimeServer.Source ..= "\n-- manual"
end)
reject("missing-original", function(p)
	p.ServerScriptService.GameServer.Services.RoundService:Destroy()
end)
reject("missing-parent", function(p)
	p.ServerScriptService.GameServer.Game:Destroy()
end)
reject("extra-source", function(p)
	local n = I.new("ModuleScript")
	n.Name = "RhythmController"
	n.Parent = p.Workspace
end)
reject("extra-container", function(p)
	local n = I.new("Folder")
	n.Name = "Unknown"
	n.Parent = p.ReplicatedStorage.GameShared
end)
reject("duplicate-code", function(p)
	local n = I.new("ModuleScript")
	n.Name = "RoundService"
	n.Parent = p.ServerScriptService.GameServer.Services
end)
reject("wrong-class", function(p)
	local old = p.ServerScriptService.GameServer.Services.RoundService
	old:Destroy()
	local n = I.new("Folder")
	n.Name = "RoundService"
	n.Parent = p.ServerScriptService.GameServer.Services
end)
reject("open-old", function(p)
	openScript = p.ServerScriptService.GameServer.Services.RoundService
end)
reject("open-fog", function(p)
	openScript = p.Workspace.CornfieldFog.RuntimeServer
end)
reject("open-new", function(p)
	openScript = resolve(p, payload.addedNodes[1].path)
end, true)
reject("partial-new", function(p)
	local row = payload.addedNodes[1]
	local n = I.new(row.class)
	n.Name = row.path:match("[^/]+$")
	n.Parent = resolve(p, row.path:match("^(.*)/[^/]+$"))
end)
reject("partial-final", function(p)
	resolve(p, payload.addedNodes[#payload.addedNodes].path):Destroy()
end, true)
reject("partial-changed-old", function(p)
	for _, entry in payload.entries do
		if entry.before and entry.source then
			resolve(p, entry.path).Source = entry.source
			break
		end
	end
end)
reject("payload-byte-tamper", nil, false, nil, raw .. " ")
reject("payload-json-tamper", nil, false, nil, "{}")
local injected, count = direct:gsub(
	"    for path, class in payload.classes do assert",
	'    error("Injected post-write failure")\n    for path, class in payload.classes do assert',
	1
)
assert(count == 1)
reject("post-write-rollback", nil, false, injected)
local report = {
	passed = true,
	baseline_sources = 80,
	final_sources = #payload.entries,
	new_nodes = #payload.addedNodes,
	rejected = rejected,
	negative_cases = #rejected,
	actual_generated_installer = true,
	world_objects_preserved = true,
	http_and_direct = true,
	repeat_zero = true,
	crlf_normalization = true,
	post_write_rollback = true,
	studio_render_acceptance = false,
}
fs.writeFile(".artifacts/harvest-install/fixture-report.json", serde.encode("json", report))
print(serde.encode("json", report))
