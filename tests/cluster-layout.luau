-- Immutable saved bytes, actual generated installer in a bounded Lune adapter.
-- No scene writes/reserialization, live Studio/physics or GPU claim.
local adapter = require("./scene-adapter")
local fs, r, I = adapter.fs, adapter.r, adapter.I
local serde = require("@lune/serde")
local path = "place/Children_of_corn.before-haze-clusters-20261015.rbxl"
local bytes = fs.readFile(path)
local source = fs.readFile("scripts/install-cluster-layout.luau")
local manifest = serde.decode("json", fs.readFile("scripts/cluster-layout.json"))
assert(
	#bytes == 1019419 and #manifest.parts == 28 and #manifest.clusters == 15,
	"Unexpected fixed scope"
)
assert(manifest.version == 1 and #manifest.barrel_bindings == 3, "Unexpected manifest schema")
assert(
	manifest.baseline.sha256 == "a897bb52fa85505090f973e910139915e6ebb2995e44915c31ecbc2b5c511dca",
	"Wrong immutable baseline"
)
assert(
	not source:find(":PivotTo", 1, true) and not source:find(".WorldPivot=", 1, true),
	"Unexpected pivot writes"
)
local function matches(frame, values)
	local components = { frame:GetComponents() }
	for index, value in components do
		if math.abs(value - values[index]) > 0.00001 then
			return false
		end
	end
	return true
end
local function resolve(place, nodePath)
	for _, binding in manifest.barrel_bindings do
		if binding.path == nodePath then
			local found
			for _, item in place:GetService("Workspace").CornMap.Props:GetChildren() do
				if
					item.Name == "LookoutBarrel"
					and item:IsA("BasePart")
					and item:HasTag("corn_barrel")
					and (
						matches(item.CFrame, binding.before) or matches(item.CFrame, binding.after)
					)
				then
					assert(not found, "Ambiguous test barrel frame")
					found = item
				end
			end
			return found
		end
	end
	local item = place
	for _, name in string.split(nodePath, "/") do
		item = item and item:FindFirstChild(name)
	end
	return item
end
local function setup()
	local place = r.deserializePlace(bytes)
	place:GetService("RunService")
	place:GetService("ChangeHistoryService")
	return place
end
local function run(place, code, running, studio)
	local proxy = {
		FindFirstChild = function(_, name)
			return place:FindFirstChild(name)
		end,
		GetService = function(_, name)
			if name == "RunService" then
				return {
					IsRunning = function()
						return running == true
					end,
					IsStudio = function()
						return studio ~= false
					end,
				}
			end
			return place:GetService(name)
		end,
	}
	local fixtureSource = code or source
	local fn = assert(loadstring(fixtureSource))
	setfenv(
		fn,
		setmetatable({
			game = proxy,
			workspace = place:GetService("Workspace"),
			CFrame = r.CFrame,
			Vector3 = r.Vector3,
			Color3 = r.Color3,
			typeof = typeof,
		}, { __index = getfenv() })
	)
	return pcall(fn)
end
local function sameTable(a, b)
	for key, value in a do
		assert(b[key] == value, "Table changed: " .. tostring(key))
	end
	for key, value in b do
		assert(a[key] == value, "Table added: " .. tostring(key))
	end
end
local function snapshot(place)
	local result = {}
	for _, item in place:GetDescendants() do
		local values = {}
		if item:IsA("BasePart") then
			for _, key in
				{
					"CFrame",
					"Size",
					"Material",
					"MaterialVariant",
					"Color",
					"Shape",
					"Anchored",
					"CanCollide",
					"CanTouch",
					"CanQuery",
					"CastShadow",
					"Transparency",
					"PivotOffset",
				}
			do
				local ok, value = pcall(function()
					return item[key]
				end)
				if ok then
					values[key] = value
				end
			end
		elseif item:IsA("Fire") then
			for _, key in { "Enabled", "Color", "SecondaryColor", "Heat", "Size", "TimeScale" } do
				values[key] = item[key]
			end
		elseif item:IsA("PointLight") then
			for _, key in { "Enabled", "Color", "Brightness", "Range", "Shadows" } do
				values[key] = item[key]
			end
		elseif item:IsA("Model") then
			values.PrimaryPart = item.PrimaryPart
			-- Where supported, prove the optional editor pivot is untouched.
			local ok, value = pcall(function()
				return item.WorldPivotData
			end)
			if ok then
				values.WorldPivotData = value
			end
		elseif item:IsA("LuaSourceContainer") then
			values.Source = item.Source
		elseif item:IsA("Lighting") then
			for _, key in
				{
					"Brightness",
					"ClockTime",
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
		end
		result[item] = {
			parent = item.Parent,
			name = item.Name,
			class = item.ClassName,
			attributes = item:GetAttributes(),
			tags = item:GetTags(),
			values = values,
		}
	end
	return result
end
local function frameMatches(a, components)
	local actual = { a:GetComponents() }
	for index = 1, 12 do
		assert(
			math.abs(actual[index] - components[index]) < 0.00001,
			"Frame differs from fixed manifest"
		)
	end
end
local function unchanged(place, before, approved)
	local count, expected = 0, 0
	for _, item in place:GetDescendants() do
		count += 1
		assert(before[item], "Instance added")
	end
	for item, state in before do
		expected += 1
		assert(
			item.Parent == state.parent
				and item.Name == state.name
				and item.ClassName == state.class,
			"Installer changed an instance's parent, name or class"
		)
		sameTable(state.attributes, item:GetAttributes())
		sameTable(state.tags, item:GetTags())
		for key, value in state.values do
			if key == "CFrame" and approved and approved[item] then
				frameMatches(item.CFrame, approved[item])
			else
				assert(
					item[key] == value,
					"Unapproved change: " .. item:GetFullName() .. "." .. key
				)
			end
		end
	end
	assert(count == expected, "Instance removed")
end
local place = setup()
local before = snapshot(place)
local ok, result = run(place)
assert(ok, result)
assert(
	result.changed == 28
		and not result.repeated
		and result.slots == 15
		and result.torchParts == 10
		and result.barrels == 3,
	"Installer returned unexpected counts"
)
local approved = {}
for _, entry in manifest.parts do
	local item = assert(resolve(place, entry.path))
	approved[item] = entry.after
	assert(entry.before[2] == entry.after[2], "Cluster Y changed")
	for index = 4, 12 do
		assert(entry.before[index] == entry.after[index], "Cluster rotation changed")
	end
end
unchanged(place, before, approved)
for _, cluster in manifest.clusters do
	local slot = assert(resolve(place, cluster.slot_path))
	local torch = assert(resolve(place, cluster.torch_path))
	assert(
		slot:GetAttribute("slot_id") == cluster.slot_id and slot:HasTag("corn_key_slot"),
		"Slot binding changed"
	)
	assert(torch:GetAttribute("torch_id") == "torch_" .. cluster.slot_id, "Torch binding changed")
	assert(
		math.abs(slot.CFrame.Position.X) >= 21
			and math.abs(slot.CFrame.Position.X - torch.Pole.CFrame.Position.X) < 0.00001
			and math.abs(torch.Pole.CFrame.Position.Z - slot.CFrame.Position.Z - 4) < 0.00001,
		"Torch and slot detached"
	)
end
assert(
	manifest.summary.min_road_gap >= 3
		and manifest.summary.min_cluster_separation >= 72
		and manifest.summary.min_props_gap >= 2.5
		and manifest.summary.min_spawn_gap >= 30,
	"Cluster clearance constraints failed"
)
for _, binding in manifest.barrel_bindings do
	local barrel = assert(resolve(place, binding.path))
	local slot = assert(resolve(place, "Workspace/CornMap/KeySlots/" .. binding.slot_id))
	assert(
		math.abs(barrel.CFrame.Position.X - slot.CFrame.Position.X - 2.8) < 0.00003
			and math.abs(barrel.CFrame.Position.Z - slot.CFrame.Position.Z) < 0.00001,
		"Legacy barrel did not preserve its slot association"
	)
end
local installed = snapshot(place)
ok, result = run(place)
assert(ok and result.changed == 0 and result.repeated, "Complete repeat was not a no-op")
unchanged(place, installed)
local rejected = 0
for _, kind in
	{
		"wrong-project",
		"wrong-scene",
		"running",
		"not-studio",
		"manual-slot",
		"manual-torch",
		"manual-barrel",
		"partial-slot",
		"partial-barrel",
		"size",
		"slot-id",
		"slot-tag",
		"barrel-tag",
		"barrel-color",
		"barrel-attribute",
		"extra-slot",
		"extra-torch-child",
		"barn-frame",
		"road-width",
		"spawn-frame",
		"missing-barrel",
		"duplicate-barrel",
		"torch-light",
		"torch-owner",
		"runtime-present",
	}
do
	local fixture = setup()
	local map = fixture:GetService("Workspace").CornMap
	local slot = map.KeySlots.solo_slot_02
	local torch = map.TorchMarkers.torch_solo_slot_02
	local barrel = assert(resolve(fixture, manifest.barrel_bindings[1].path))
	if kind == "wrong-project" then
		map:SetAttribute("corn_project_id", "foreign")
	end
	if kind == "wrong-scene" then
		local item = I.new("Folder")
		item.Name = "Asmr_Base"
		item.Parent = fixture:GetService("Workspace")
	end
	if kind == "manual-slot" then
		slot.CFrame += r.Vector3.new(0.1, 0, 0)
	end
	if kind == "manual-torch" then
		torch.Pole.CFrame += r.Vector3.new(0.1, 0, 0)
	end
	if kind == "manual-barrel" then
		barrel.CFrame += r.Vector3.new(0.1, 0, 0)
	end
	if kind == "partial-slot" then
		for _, entry in manifest.parts do
			if entry.path:match("/solo_slot_02$") then
				slot.CFrame = r.CFrame.new(table.unpack(entry.after))
			end
		end
	end
	if kind == "partial-barrel" then
		barrel.CFrame = r.CFrame.new(table.unpack(manifest.barrel_bindings[1].after))
	end
	if kind == "size" then
		slot.Size += r.Vector3.new(0.1, 0, 0)
	end
	if kind == "slot-id" then
		slot:SetAttribute("slot_id", "unknown")
	end
	if kind == "slot-tag" then
		slot:RemoveTag("corn_key_slot")
	end
	if kind == "barrel-tag" then
		barrel:RemoveTag("corn_barrel")
	end
	if kind == "barrel-color" then
		barrel.Color = r.Color3.new(0, 1, 0)
	end
	if kind == "barrel-attribute" then
		barrel:SetAttribute("AuthorNote", "manual")
	end
	if kind == "extra-slot" then
		local item = I.new("Part")
		item.Name = "AuthorSlot"
		item.Parent = map.KeySlots
	end
	if kind == "extra-torch-child" then
		local item = I.new("Folder")
		item.Name = "AuthorChild"
		item.Parent = torch
	end
	if kind == "barn-frame" then
		map.Props.HouseWest.SM_Bld_Barn_03.CFrame += r.Vector3.new(1, 0, 0)
	end
	if kind == "road-width" then
		map.Props.VillageRoad.RoadClearance.Size += r.Vector3.new(1, 0, 0)
	end
	if kind == "spawn-frame" then
		map.CornerSpawns:GetChildren()[1].CFrame += r.Vector3.new(1, 0, 0)
	end
	if kind == "missing-barrel" then
		barrel.Parent = nil
	end
	if kind == "duplicate-barrel" then
		local extra = barrel:Clone()
		extra.Parent = map.Props
	end
	if kind == "torch-light" then
		torch.Flame.TorchLight.Brightness = 2
	end
	if kind == "torch-owner" then
		torch:SetAttribute("CornTorchOwned", false)
	end
	if kind == "runtime-present" then
		local item = I.new("Folder")
		item.Name = "CornRoundRuntime"
		item.Parent = map
	end
	local previous = snapshot(fixture)
	ok, result = run(fixture, nil, kind == "running", kind ~= "not-studio")
	assert(not ok, "Accepted unsafe cluster input: " .. kind)
	unchanged(fixture, previous)
	rejected += 1
end
-- Three physically identical names must resolve by exact binding, independent
-- of GetChildren insertion order and the DOM's synthetic #2/#3 names.
local reordered = setup()
local props = reordered:GetService("Workspace").CornMap.Props
local last = assert(resolve(reordered, manifest.barrel_bindings[3].path))
last.Parent = nil
last.Parent = props
ok, result = run(reordered)
assert(ok and result.changed == 28, "Exact barrels depended on sibling order")
for _, binding in manifest.barrel_bindings do
	assert(matches(assert(resolve(reordered, binding.path)).CFrame, binding.after))
end
for _, at in { 1, 14, 28 } do
	local rollback = setup()
	local previous = snapshot(rollback)
	local injected, count = source:gsub(
		"%-%- CLUSTER_AFTER_WRITE",
		"if #changed==" .. at .. ' then error("Injected cluster write failure") end'
	)
	assert(count == 1, "Missing unique rollback injection point")
	ok, result = run(rollback, injected)
	assert(
		not ok and tostring(result):find("rolled back", 1, true),
		"Injected failure did not trigger rollback"
	)
	local restored = {}
	for index = 1, at do
		local entry = manifest.parts[index]
		restored[assert(resolve(rollback, entry.path))] = entry.before
	end
	unchanged(rollback, previous, restored)
end
assert(fs.readFile(path) == bytes, "Immutable cluster baseline changed")
print(
	"PASS: actual generated cluster installer 28 CFrames = 15 slots + 10 torch parts + 3 legacy barrels; complete before/repeat; "
		.. rejected
		.. " ownership/topology/partial/world-clearance refusals; order-independent duplicate-name barrel association; rollback at 1/14/28; all other world/Source/art/light/metadata exact; immutable baseline. Local Lune geometry only, no live physics/E/render claim."
)
