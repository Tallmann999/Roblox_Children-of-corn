-- Production world transaction on the exact saved scene, with a limited Lune mesh-template adapter.
-- This verifies layout/preservation/refusal, not EditableMesh rendering or Studio physics.
local adapter = require("./scene-adapter")
local fs, r, I = adapter.fs, adapter.r, adapter.I
local CF, V3 = r.CFrame, r.Vector3
local baseline = fs.readFile("place/Children_of_corn.rbxl")
local source = fs.readFile("src/server/Game/HarvestWorld.luau")
local neutral =
	require("@lune/serde").decode("json", fs.readFile("assets/harvest-warden/roblox-catalog.json"))
local PROJECT, OWNER = "children_of_corn", "harvest_warden_v1"
local calls = 0
local function setup(failAt, realCatalog)
	local place = r.deserializePlace(baseline)
	local map = place:GetService("Workspace").CornMap
	local module = I.new("ModuleScript")
	module.Name = "HarvestArtGeometry"
	module.Parent = place:GetService("ReplicatedStorage").GameShared.Game
	local function mesh(name, size, center, assetKey)
		local part = I.new("MeshPart")
		part.Name = name
		part.CFrame, part.Size = CF.new(center), size
		part.Transparency = 0
		part.TextureID = "rbxassetid://132154563588735"
		part:SetAttribute("HarvestMeshKey", assetKey .. ":" .. name)
		part:SetAttribute("corn_project_id", PROJECT)
		part:SetAttribute("HarvestGeometryOwner", OWNER)
		return part
	end
	local catalog = {}
	local geometry = {
		MeshInfo = function(key)
			return catalog[key]
		end,
		Apply = function(part, key)
			assert(part:IsA("MeshPart") and catalog[key], "Unknown local geometry binding")
		end,
		Template = function(key)
			calls += 1
			if failAt and calls == failAt then
				error("fixture budget exhausted")
			end
			local model = I.new("Model")
			model.Name = key
			if realCatalog then
				for _, meshKey in assert(neutral.assets[key]).meshes do
					local data = neutral.meshes[meshKey]
					local part =
						mesh(data.name, V3.new(unpack(data.size)), V3.new(unpack(data.center)), key)
					part:SetAttribute("HarvestMeshKey", meshKey)
					part.TextureID = data.textureId
					part.Material = r.Enum.Material[data.material]
					part.Color = r.Color3.new(unpack(data.color))
					catalog[meshKey] = data
					part.Parent = model
				end
			elseif key == "BarnDark_Open" then
				for _, name in
					{ "SM_Bld_Barn_03", "SM_Bld_Barn_03_Shutter_01", "SM_Bld_Barn_03_Shutter_02" }
				do
					local size = map.Props.HouseWest[name].Size
					-- Exercise two material primitives sharing one source mesh.
					for _, side in { -1, 1 } do
						local part = mesh(
							"HW_Dark_" .. name .. "_" .. side,
							V3.new(size.X / 2, size.Y, size.Z),
							V3.new(side * size.X / 4, 0, 0),
							key
						)
						catalog[part:GetAttribute("HarvestMeshKey")] =
							{ sourceName = "HW_Dark_" .. name }
						part.Parent = model
					end
				end
			else
				local part = mesh(
					key,
					if key:match("^Fence") then V3.new(12, 4, 0.5) else V3.new(1, 0.5, 1),
					V3.new(0, 0.25, 0),
					key
				)
				catalog[part:GetAttribute("HarvestMeshKey")] = { sourceName = key }
				part.Parent = model
			end
			return model
		end,
	}
	local fn = assert(loadstring(source, "HarvestWorld"))
	setfenv(
		fn,
		setmetatable({
			game = {
				GetService = function(_, name)
					return place:GetService(name)
				end,
			},
			require = function(required)
				return if required.Name == "MonsterPose" then { WardenScale = 1.3 } else geometry
			end,
			Instance = I,
			Vector3 = V3,
			CFrame = CF,
			Color3 = r.Color3,
			Enum = r.Enum,
		}, { __index = getfenv() })
	)
	return place, map, fn()
end

local function snapshot(map)
	local result = {}
	for _, item in map:GetDescendants() do
		local entry = {
			parent = item.Parent,
			name = item.Name,
			class = item.ClassName,
			attrs = item:GetAttributes(),
		}
		if item:IsA("BasePart") then
			for _, key in
				{
					"CFrame",
					"Size",
					"Transparency",
					"CanCollide",
					"CanQuery",
					"CanTouch",
					"Color",
					"Material",
					"Anchored",
					"CastShadow",
				}
			do
				entry[key] = item[key]
			end
			if item:IsA("MeshPart") then
				entry.TextureContent, entry.MeshContent = item.TextureContent, item.MeshContent
			end
		end
		result[item] = entry
	end
	return result
end

local function preserved(before, allowTransparency)
	for item, row in before do
		assert(
			item.Parent == row.parent and item.Name == row.name and item.ClassName == row.class,
			"Original identity/topology changed"
		)
		local attrs = item:GetAttributes()
		for key, value in row.attrs do
			assert(attrs[key] == value, "Original attribute changed: " .. key)
		end
		for key in attrs do
			assert(row.attrs[key] ~= nil, "Original attribute added: " .. key)
		end
		if item:IsA("BasePart") then
			for key, value in row do
				if key ~= "parent" and key ~= "name" and key ~= "class" and key ~= "attrs" then
					if
						not (
							key == "Transparency"
							and allowTransparency
							and allowTransparency[item]
						)
					then
						assert(
							item[key] == value,
							"Original " .. item:GetFullName() .. "/" .. key .. " changed"
						)
					end
				end
			end
		end
	end
end

local _, map, module = setup()
local original = snapshot(map)
local oldAttrs = map:GetAttributes()
local legacy = module.Ensure()
assert(
	legacy.variant == "legacy" and not map:FindFirstChild("HarvestDecor"),
	"Legacy scene changed without installer opt-in"
)
preserved(original)
local reportA = module.Ensure("A")
assert(reportA.created == 1 and reportA.commonModels == 39, "Expected bounded common props")
original[map] = nil -- explicit opt-in adds only the agreed map variant attribute.
local homeAllowed = {}
for _, name in { "Head", "Arms", "Body" } do
	local part = map.Props.ScarecrowMarker[name]
	homeAllowed[part] = true
	assert(part.Transparency == 1, "Legacy home marker was not hidden")
end
preserved(original, homeAllowed)
assert(
	map.Props.ScarecrowMarker.Pole.Transparency
		== original[map.Props.ScarecrowMarker.Pole].Transparency,
	"Home pole changed"
)
for key, value in oldAttrs do
	assert(map:GetAttribute(key) == value)
end
local aRoot = map.HarvestDecor
assert(
	#aRoot.Common:GetChildren() == 39 and #aRoot.VariantB:GetChildren() == 20,
	"Unexpected decor model/part count"
)
for _, part in aRoot:GetDescendants() do
	if part:IsA("Texture") then
		assert(part.Transparency == 1, "B texture remains visible in A")
	end
	if part:IsA("BasePart") then
		assert(
			part.Anchored and not part.CanCollide and not part.CanQuery and not part.CanTouch,
			"Art affects collisions/LOS"
		)
		if part:IsDescendantOf(aRoot.VariantB) then
			assert(part.Transparency == 1)
		end
	end
end
assert(
	module.Ensure("A").changed == 0 and module.Ensure("A").created == 0,
	"Repeat A is not idempotent"
)
local allowed = table.clone(homeAllowed)
for _, house in { map.Props.HouseWest, map.Props.HouseEast, map.Props.HouseNorthWest } do
	for _, name in { "SM_Bld_Barn_03", "SM_Bld_Barn_03_Shutter_01", "SM_Bld_Barn_03_Shutter_02" } do
		allowed[house[name]] = true
	end
end
local b = module.Ensure("B")
assert(b.variant == "B" and b.created == 0 and aRoot == map.HarvestDecor, "B recreated owned art")
assert(
	aRoot.VariantB.GroundSurface.HarvestSurface.Transparency == 0
		and aRoot.VariantB.RoadSurface.HarvestSurface.Transparency == 0,
	"B textures not enabled"
)
preserved(original, allowed)
for part in allowed do
	assert(part.Transparency == 1, "B did not hide the red barn")
end
assert(module.Ensure("B").changed == 0, "Repeat B is not idempotent")
module.Ensure("A")
preserved(original, homeAllowed)
assert(module.Ensure("A").changed == 0, "B/A did not converge")

local rejected = 0
local function reject(mutate, after, seed)
	local _, testMap, api = setup()
	if seed then
		api.Ensure("A")
	end
	mutate(testMap)
	local before = snapshot(testMap)
	local ok = pcall(function()
		api.Ensure("B")
	end)
	assert(not ok, "Unsafe author state was accepted")
	before[testMap] = nil
	preserved(before)
	if after then
		after(testMap)
	end
	rejected += 1
end
reject(function(m)
	local f = I.new("Folder")
	f.Name = "HarvestDecor"
	f.Parent = m
end)
reject(function(m)
	local f = I.new("Folder")
	f.Name = "ForeignArt"
	f.Parent = m.HarvestDecor.Common
end, nil, true)
reject(function(m)
	m.Props.HouseWest.SM_Bld_Barn_03.CFrame *= CF.new(1, 0, 0)
end, nil, true)
reject(function(m)
	m.Props.HouseWest.SM_Bld_Barn_03.Transparency = 0.42
end, nil, true)
reject(function(m)
	m.HarvestDecor.Common:GetChildren()[1]:GetChildren()[1].CanQuery = true
end, nil, true)
reject(function(m)
	m.HarvestDecor.Common:GetChildren()[1]:GetChildren()[1].CFrame *= CF.new(0, 0, 1)
end, nil, true)
reject(function(m)
	m.HarvestDecor.Common:GetChildren()[1]:GetChildren()[1]:Destroy()
end, nil, true)
reject(function(m)
	m.HarvestDecor.Common:GetChildren()[1].Name = "AuthorRenamedFence"
end, nil, true)
reject(function(m)
	m.HarvestDecor.VariantB.GroundSurface.HarvestSurface.Texture = "rbxassetid://1"
end, nil, true)
reject(function(m)
	m.KeySlots.solo_slot_01.CFrame = CF.new(-11.5, 14.4, -240)
end, function(m)
	assert(not m:FindFirstChild("HarvestDecor"))
end)
reject(function(m)
	m.Ground.Size = V3.new(640, 2, 630)
end)
reject(function(m)
	m:SetAttribute("HarvestArtVariant", "unknown")
end)
reject(function(m)
	m.Props.HouseEast.SM_Bld_Barn_03:SetAttribute("CornFarmMeshOwned", false)
end)
reject(function(m)
	m.Props.VillageRoad.RoadSurface.CFrame *= CF.new(1, 0, 0)
end, nil, true)
reject(function(m)
	m.Props.ScarecrowMarker.Head.Transparency = 0.3
end, nil, true)
reject(function(m)
	m.Props.ScarecrowMarker.HarvestWardenHome.Detailed:GetChildren()[1].Color =
		r.Color3.new(1, 1, 1)
end, nil, true)
local _, failedMap, failing = setup(calls + 6)
local failedBefore = snapshot(failedMap)
assert(
	not pcall(function()
			failing.Ensure("A")
		end) and not failedMap:FindFirstChild("HarvestDecor"),
	"Failed geometry preparation published partial art"
)
preserved(failedBefore)
local _, actualMap, actualModule = setup(nil, true)
local actualOriginal = snapshot(actualMap)
actualOriginal[actualMap] = nil
actualModule.Ensure("B")
local actualAllowed = {}
for _, name in { "Head", "Arms", "Body" } do
	actualAllowed[actualMap.Props.ScarecrowMarker[name]] = true
end
for _, house in
	{ actualMap.Props.HouseWest, actualMap.Props.HouseEast, actualMap.Props.HouseNorthWest }
do
	for _, name in { "SM_Bld_Barn_03", "SM_Bld_Barn_03_Shutter_01", "SM_Bld_Barn_03_Shutter_02" } do
		actualAllowed[house[name]] = true
	end
end
preserved(actualOriginal, actualAllowed)
assert(
	#actualMap.HarvestDecor.VariantB:GetChildren() == 14,
	"Actual four-primitive barn count differs"
)
assert(actualModule.Ensure("B").changed == 0, "Actual export repeat differs")
actualModule.Ensure("A")
for _, house in
	{ actualMap.Props.HouseWest, actualMap.Props.HouseEast, actualMap.Props.HouseNorthWest }
do
	for _, name in { "SM_Bld_Barn_03", "SM_Bld_Barn_03_Shutter_01", "SM_Bld_Barn_03_Shutter_02" } do
		actualAllowed[house[name]] = nil
	end
end
preserved(actualOriginal, actualAllowed)
print(
	"PASS harvest-world: saved-world preservation, 39 common props, material primitives, A/B/A, repeat, legacy opt-in, "
		.. rejected
		.. " unsafe states and allocation rollback"
)
