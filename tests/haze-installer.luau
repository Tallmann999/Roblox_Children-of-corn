-- Exact immutable XML + actual generated installer, no scene writes or Studio.
local adapter = require("./scene-adapter")
local fs, r, I = adapter.fs, adapter.r, adapter.I
local original = fs.readFile("assets/CornfieldFog/original.rbxmx")
local baselinePath = "place/Children_of_corn.before-haze-clusters-20261015.rbxl"
local baseline = fs.readFile(baselinePath)
local source = fs.readFile("scripts/install-haze.luau")
local serde = require("@lune/serde")
local priorSources =
	serde.decode("json", fs.readFile("scripts/haze-source-history.json")).bundles[1].sources
local paths = {
	Config = "assets/CornfieldFog/Config.luau",
	RuntimeServer = "assets/CornfieldFog/RuntimeServer.server.luau",
	ClientTemplate = "assets/CornfieldFog/ClientTemplate.client.luau",
}
local function normalize(value)
	return (value:gsub("\r\n", "\n"))
end
local function setup()
	local place = r.deserializePlace(baseline)
	place:GetService("RunService")
	place:GetService("ChangeHistoryService")
	-- Lune's document detector expects <roblox directly, before XML declaration.
	local fog = r.deserializeModel((original:gsub("^<%?xml.-%?>%s*", "")))[1]
	fog.Parent = place:GetService("Workspace")
	return place, fog
end
local function run(place, code, kind)
	local gameProxy = {
		GetService = function(_, name)
			if name == "RunService" then
				return {
					IsStudio = function()
						return kind ~= "not-studio"
					end,
					IsRunning = function()
						return kind == "running"
					end,
				}
			elseif name == "ScriptEditorService" then
				return {
					FindScriptDocument = function(_, item)
						return if (kind == "open-tab" or kind == "prior-open-tab")
								and item.Name == "ClientTemplate"
							then {}
							else nil
					end,
				}
			end
			return place:GetService(name)
		end,
	}
	local fn = assert(loadstring(code or source))
	setfenv(fn, setmetatable({ game = gameProxy, Enum = r.Enum }, { __index = getfenv() }))
	return pcall(fn)
end
local function equalTable(a, b)
	for key, value in a do
		assert(b[key] == value, "Table value changed: " .. tostring(key))
	end
	for key, value in b do
		assert(a[key] == value, "Table value added: " .. tostring(key))
	end
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
				"Value",
				"CFrame",
				"Size",
				"Color",
				"Material",
				"CanCollide",
				"Transparency",
				"WorldPivotData",
				"PrimaryPart",
				"ModelStreamingMode",
				"LevelOfDetail",
				"Brightness",
				"Ambient",
				"OutdoorAmbient",
				"FogStart",
				"FogEnd",
				"FogColor",
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
local function unchanged(place, before, approved)
	local count, expected = 0, 0
	for _, item in place:GetDescendants() do
		assert(before[item], "Persistent instance added")
		count += 1
	end
	for item, state in before do
		expected += 1
		assert(
			item.Parent == state.parent
				and item.Name == state.name
				and item.ClassName == state.class
		)
		equalTable(state.attrs, item:GetAttributes())
		equalTable(state.tags, item:GetTags())
		for key, value in state.values do
			local target = approved and approved[item]
			assert(
				item[key] == (if key == "Source" and target then target else value),
				"Unapproved change: " .. item:GetFullName() .. "/" .. key
			)
		end
	end
	assert(count == expected, "Persistent instance removed")
end
local function setCurrent(fog, crlf)
	for _, item in fog:GetDescendants() do
		if item:IsA("LuaSourceContainer") then
			local target = normalize(fs.readFile(paths[item.Name]))
			item.Source = if crlf then target:gsub("\n", "\r\n") else target
		end
	end
end
local function setPrior(fog)
	for _, item in fog:GetDescendants() do
		if item:IsA("LuaSourceContainer") then
			local path = item:GetFullName():gsub("%.", "/")
			item.Source = assert(priorSources[path], "Missing exact prior Source")
		end
	end
end
local place, fog = setup()
local before, approved = snapshot(place), {}
for _, item in fog:GetDescendants() do
	if item:IsA("LuaSourceContainer") then
		approved[item] = normalize(fs.readFile(paths[item.Name]))
	end
end
local ok, result = run(place)
assert(ok, result)
assert(
	result.changed == 3 and result.sources == 3 and result.instances == 5 and not result.repeated
)
unchanged(place, before, approved)
local installed = snapshot(place)
ok, result = run(place)
assert(ok and result.changed == 0 and result.repeated)
unchanged(place, installed)
setCurrent(fog, true)
installed = snapshot(place)
ok, result = run(place)
assert(ok and result.changed == 0 and result.repeated, "Normalized CRLF repeat refused")
unchanged(place, installed)
local priorPlace, priorFog = setup()
setPrior(priorFog)
local priorBefore, expectedUpgrade = snapshot(priorPlace), {}
local upgradeCount = 0
for _, item in priorFog:GetDescendants() do
	if item:IsA("LuaSourceContainer") then
		local target = normalize(fs.readFile(paths[item.Name]))
		expectedUpgrade[item] = target
		if normalize(item.Source) ~= target then
			upgradeCount += 1
		end
	end
end
assert(upgradeCount == 1, "This approved upgrade changes only close.Modal client Source")
ok, result = run(priorPlace)
assert(
	ok and result.changed == upgradeCount and not result.repeated,
	"Exact installed prior bundle refused"
)
unchanged(priorPlace, priorBefore, expectedUpgrade)
ok, result = run(priorPlace)
assert(ok and result.changed == 0 and result.repeated)
local rejected = 0
for _, kind in
	{
		"wrong-project",
		"wrong-scene",
		"not-studio",
		"running",
		"open-tab",
		"unknown-source",
		"partial",
		"readme",
		"server-disabled",
		"client-enabled",
		"run-context",
		"streaming",
		"extra-node",
		"missing-node",
		"duplicate-name",
		"client-parent",
		"attributes",
		"tags",
		"class",
		"prior-mixed-original",
		"prior-open-tab",
		"prior-unknown-source",
	}
do
	local fixture, group = setup()
	if kind:find("prior-", 1, true) then
		setPrior(group)
	end
	if kind == "prior-mixed-original" then
		group.Config.Source =
			r.deserializeModel((original:gsub("^<%?xml.-%?>%s*", "")))[1].Config.Source
	end
	if kind == "prior-unknown-source" then
		group.RuntimeServer.ClientTemplate.Source ..= "\n-- unknown manual edit"
	end
	if kind == "wrong-project" then
		fixture:GetService("Workspace").CornMap:SetAttribute("corn_project_id", "other")
	end
	if kind == "wrong-scene" then
		local other = I.new("Folder")
		other.Name = "Asmr_Base"
		other.Parent = fixture:GetService("Workspace")
	end
	if kind == "unknown-source" then
		group.Config.Source ..= "\n-- unknown manual edit"
	end
	if kind == "partial" then
		group.Config.Source = normalize(fs.readFile(paths.Config))
	end
	if kind == "readme" then
		group.READ_ME.Value = "Edited"
	end
	if kind == "server-disabled" then
		group.RuntimeServer.Disabled = true
	end
	if kind == "client-enabled" then
		group.RuntimeServer.ClientTemplate.Disabled = false
	end
	if kind == "run-context" then
		group.RuntimeServer.RunContext = r.Enum.RunContext.Server
	end
	if kind == "streaming" then
		group.ModelStreamingMode = r.Enum.ModelStreamingMode.Atomic
	end
	if kind == "extra-node" then
		local extra = I.new("Folder")
		extra.Name = "Extra"
		extra.Parent = group
	end
	if kind == "missing-node" then
		group.Config.Parent = nil
	end
	if kind == "duplicate-name" then
		group.Config:Clone().Parent = group
	end
	if kind == "client-parent" then
		group.RuntimeServer.ClientTemplate.Parent = group
	end
	if kind == "attributes" then
		group:SetAttribute("Manual", true)
	end
	if kind == "tags" then
		group:AddTag("manual")
	end
	if kind == "class" then
		group.Config.Parent = nil
		local other = I.new("Folder")
		other.Name = "Config"
		other.Parent = group
	end
	local previous = snapshot(fixture)
	ok, result = run(fixture, nil, kind)
	assert(not ok, "Unsafe fog installation accepted: " .. kind)
	unchanged(fixture, previous)
	rejected += 1
end
for point = 1, 3 do
	local rollback = setup()
	before = snapshot(rollback)
	local injected, count = source:gsub(
		"%-%- HAZE_AFTER_SOURCE_WRITE",
		"if #changed==" .. point .. ' then error("Injected haze write failure") end'
	)
	assert(count == 1)
	ok, result = run(rollback, injected)
	assert(not ok and tostring(result):find("rolled back", 1, true))
	unchanged(rollback, before)
end
assert(
	fs.readFile(baselinePath) == baseline
		and fs.readFile("assets/CornfieldFog/original.rbxmx") == original
)
local priorRollback, priorGroup = setup()
setPrior(priorGroup)
before = snapshot(priorRollback)
local priorInjected, replacements =
	source:gsub("%-%- HAZE_AFTER_SOURCE_WRITE", 'error("Injected prior upgrade failure")')
assert(replacements == 1)
ok, result = run(priorRollback, priorInjected)
assert(not ok and tostring(result):find("rolled back", 1, true))
unchanged(priorRollback, before)
print(
	"PASS: exact original XML, three Source-only writes, whole-world/75 Source/READ_ME/flags preservation, repeat/CRLF, "
		.. rejected
		.. " refusals, exact prior upgrade1/repeat0, rollback after original writes1/2/3 and prior upgrade; immutable bytes unchanged. Adapter only."
)
