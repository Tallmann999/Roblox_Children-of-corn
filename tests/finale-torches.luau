-- Immutable saved bytes, actual generated installer in a bounded Lune adapter.
-- No scene writes/reserialization, live Studio/physics or GPU claim.
local adapter = require("./scene-adapter")
local fs, r, I = adapter.fs, adapter.r, adapter.I
local serde = require("@lune/serde")
local path = "place/Children_of_corn.before-finale-20261015.rbxl"
local bytes = fs.readFile(path)
local source = fs.readFile("scripts/install-finale-torches.luau")
local manifest = serde.decode("json", fs.readFile("scripts/finale-torch-layout.json"))
assert(#bytes == 1015691 and #manifest.parts == 54 and #manifest.models == 27)
assert(manifest.version == 2 and #manifest.barn_bindings == 3)
assert(
	manifest.baseline.sha256 == "9082169a7da5fed15cd962611777285213fce99f23de82f83e0f361a683ecf16"
)
assert(not source:find(":PivotTo", 1, true) and not source:find(".WorldPivot=", 1, true))
local function resolve(place, nodePath)
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
	-- Lune model GetPivot ignores saved OptionalCoordinateFrame; bridge only
	-- that getter to its exact native saved pivot property in this fixture.
	local fixtureSource = (code or source):gsub("barn:GetPivot%(%)", "barn.WorldPivotData")
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
				and item.ClassName == state.class
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
assert(result.changed == 54 and result.models == 27 and not result.repeated)
local approved = {}
for _, entry in manifest.parts do
	local part = assert(resolve(place, entry.path))
	approved[part] = entry.after
	assert(entry.before[2] == entry.after[2], "Y changed")
	for index = 4, 12 do
		assert(entry.before[index] == entry.after[index], "Rotation changed")
	end
	if entry.torch_id:find("torch_House", 1, true) then
		local house = entry.torch_id:gsub("^torch_", ""):gsub("%-?1$", "")
		local binding
		for _, barn in manifest.barn_bindings do
			if barn.path:match("/([^/]+)$") == house then
				binding = barn
			end
		end
		assert(binding, "Missing fixed Barn binding")
		assert(math.abs(math.abs(entry.after[1] - binding.pivot[1]) - 6) < 0.00001)
		assert(math.abs(entry.after[3] - binding.pivot[3] + 11.75) < 0.00001)
	end
end
unchanged(place, before, approved)
local installed = snapshot(place)
ok, result = run(place)
assert(ok and result.changed == 0 and result.repeated)
unchanged(place, installed)
local firstPath = manifest.parts[1].path
local modelPath = firstPath:match("^(.*)/[^/]+$")
local rejected = 0
for _, kind in
	{
		"wrong-project",
		"wrong-scene",
		"running",
		"not-studio",
		"manual-frame",
		"partial-one-part",
		"partial-one-model",
		"size",
		"shape",
		"material",
		"color",
		"collision",
		"brightness",
		"fire-size",
		"fire-heat",
		"extra-child",
		"missing-model",
		"model-class",
		"owner",
		"extra-attribute",
		"tag",
		"missing-tag",
		"primary-part",
		"barn-pivot",
		"barn-body-frame",
		"barn-body-size",
		"barn-owner",
		"barn-child",
		"superseded-scatter",
	}
do
	local fixture = setup()
	local part = resolve(fixture, firstPath)
	local model = resolve(fixture, modelPath)
	local markers = fixture:GetService("Workspace").CornMap.TorchMarkers
	local barn = fixture:GetService("Workspace").CornMap.Props.HouseWest
	if kind == "wrong-project" then
		fixture:GetService("Workspace").CornMap:SetAttribute("corn_project_id", "other")
	end
	if kind == "wrong-scene" then
		local other = I.new("Folder")
		other.Name = "Asmr_Base"
		other.Parent = fixture:GetService("Workspace")
	end
	if kind == "manual-frame" then
		part.CFrame += r.Vector3.new(0.123, 0, 0)
	end
	if kind == "partial-one-part" then
		part.CFrame = r.CFrame.new(table.unpack(manifest.parts[1].after))
	end
	if kind == "partial-one-model" then
		for _, entry in manifest.parts do
			if entry.path:match("^(.*)/[^/]+$") == modelPath then
				resolve(fixture, entry.path).CFrame = r.CFrame.new(table.unpack(entry.after))
			end
		end
	end
	if kind == "size" then
		part.Size += r.Vector3.new(0.1, 0, 0)
	end
	if kind == "shape" then
		part.Shape = r.Enum.PartType.Ball
	end
	if kind == "material" then
		part.Material = r.Enum.Material.Glass
	end
	if kind == "color" then
		part.Color = r.Color3.new(0, 1, 0)
	end
	if kind == "collision" then
		part.CanCollide = true
	end
	if kind == "brightness" then
		model.Flame.TorchLight.Brightness = 2
	end
	if kind == "fire-size" then
		model.Flame.TorchFire.Size = 9
	end
	if kind == "fire-heat" then
		model.Flame.TorchFire.Heat = 7
	end
	if kind == "extra-child" then
		local child = I.new("Folder")
		child.Name = "AuthorChild"
		child.Parent = model
	end
	if kind == "missing-model" then
		model.Parent = nil
	end
	if kind == "model-class" then
		model.Parent = nil
		local other = I.new("Folder")
		other.Name = model.Name
		other.Parent = markers
	end
	if kind == "owner" then
		model:SetAttribute("CornTorchOwned", false)
	end
	if kind == "extra-attribute" then
		part:SetAttribute("AuthorNote", "manual")
	end
	if kind == "tag" then
		model:AddTag("author_tag")
	end
	if kind == "missing-tag" then
		model:RemoveTag("corn_torch")
	end
	if kind == "primary-part" then
		model.PrimaryPart = model.Flame
	end
	if kind == "barn-pivot" then
		barn.WorldPivotData += r.Vector3.new(1, 0, 0)
	end
	if kind == "barn-body-frame" then
		barn.SM_Bld_Barn_03.CFrame += r.Vector3.new(1, 0, 0)
	end
	if kind == "barn-body-size" then
		barn.SM_Bld_Barn_03.Size += r.Vector3.new(1, 0, 0)
	end
	if kind == "barn-owner" then
		barn:SetAttribute("CornFarmAssetOwned", false)
	end
	if kind == "barn-child" then
		local child = I.new("Folder")
		child.Name = "AuthorChild"
		child.Parent = barn
	end
	if kind == "superseded-scatter" then
		local deltas = {
			torch_HouseWest1 = { 6, -10 },
			["torch_HouseWest-1"] = { -10, -6 },
			torch_HouseEast1 = { 9, -10 },
			["torch_HouseEast-1"] = { -11, -6 },
			torch_HouseNorthWest1 = { 8, -11 },
			["torch_HouseNorthWest-1"] = { -12, -5 },
		}
		for _, entry in manifest.parts do
			local frame = r.CFrame.new(table.unpack(entry.after))
			local delta = deltas[entry.torch_id]
			if delta then
				frame = r.CFrame.new(table.unpack(entry.before))
					+ r.Vector3.new(delta[1], 0, delta[2])
			end
			resolve(fixture, entry.path).CFrame = frame
		end
	end
	local previous = snapshot(fixture)
	ok, result = run(fixture, nil, kind == "running", kind ~= "not-studio")
	assert(not ok, "Accepted unsafe torch input: " .. kind)
	unchanged(fixture, previous)
	rejected += 1
end
local rollback = setup()
local rollbackBefore = snapshot(rollback)
local injected, count =
	source:gsub("%-%- FINALE_TORCH_AFTER_WRITE", 'error("Injected torch write failure")')
assert(count == 1)
ok, result = run(rollback, injected)
assert(not ok and tostring(result):find("rolled back", 1, true))
-- Lune reconstructs the assigned-and-restored CFrame through f32 bounds;
-- accept less than 1e-5 only on this deliberately written rollback Part.
unchanged(rollback, rollbackBefore, {
	[assert(resolve(rollback, firstPath))] = manifest.parts[1].before,
})
assert(fs.readFile(path) == bytes, "Immutable engine baseline bytes changed")
print(
	"PASS: fixed54-part translation/27models, exact before/repeat, "
		.. rejected
		.. " unknown/partial/topology/props refusals, injected rollback, world/Source/art/light preservation and immutable byte proof. Lune adapter only; live clearance/GPU not claimed."
)
