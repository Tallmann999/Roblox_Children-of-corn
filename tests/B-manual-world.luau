-- Synthetic instances and production sources. No place is read or serialized;
-- this checks authoring bindings, not native rendering, physics or networking.
local adapter = require("./scene-adapter")
local fs, r, I = adapter.fs, adapter.r, adapter.I
local V3, CF = r.Vector3, r.CFrame
local checks = 0
local function check(condition, message)
	checks += 1
	assert(condition, message)
end
local function closeFrame(actual, expected)
	for index, value in { actual:GetComponents() } do
		check(
			math.abs(value - ({ expected:GetComponents() })[index]) < 0.0001,
			"Authored frame changed"
		)
	end
end
local function child(class, name, parent)
	local result = I.new(class)
	result.Name, result.Parent = name, parent
	return result
end
local project = "children_of_corn"
local owner = "harvest_warden_v1"
local world, storage = I.new("Workspace"), I.new("ReplicatedStorage")
local gameFolder = child("Folder", "Game", child("Folder", "GameShared", storage))
child("ModuleScript", "HarvestArtGeometry", gameFolder)
child("ModuleScript", "MonsterPose", gameFolder)
local map = child("Model", "CornMap", world)
map:SetAttribute("corn_project_id", project)
map:SetAttribute("HarvestArtVariant", "B")
map:SetAttribute("BManualAuthoringVersion", 1)
local props = child("Folder", "Props", map)
local ground = child("Part", "Ground", map)
ground.Size, ground.CFrame = V3.new(630, 2, 630), CF.new(0, -1, 0)
local field = child("Part", "FieldZone", map)
field.Size, field.CFrame = V3.new(630, 10, 630), CF.new(0, 5, 0)
local function stamp(item)
	item:SetAttribute("corn_project_id", project)
	item:SetAttribute("HarvestGeometryOwner", owner)
end
local art = child("Folder", "HarvestDecor", map)
stamp(art)
local home = child("Model", "ScarecrowMarker", props)
home:AddTag("corn_monster_home")
for _, name in { "Head", "Arms", "Body" } do
	child("Part", name, home)
end
local homeArt = child("Folder", "HarvestWardenHome", home)
stamp(homeArt)
local houses = {}
for _, name in { "HouseWest", "HouseEast", "HouseNorthWest" } do
	local house = child("Model", name, props)
	house:SetAttribute("corn_project_id", project)
	house:SetAttribute("CornFarmAssetOwned", true)
	house:SetAttribute("AssetKey", "SM_Bld_Barn_03")
	for index, meshName in
		{ "SM_Bld_Barn_03", "SM_Bld_Barn_03_Shutter_01", "SM_Bld_Barn_03_Shutter_02" }
	do
		local original = child("MeshPart", meshName, house)
		original:SetAttribute("CornFarmMeshOwned", true)
		original:SetAttribute("corn_project_id", project)
		original:SetAttribute("AssetKey", "SM_Bld_Barn_03")
		original:SetAttribute("MeshIndex", index)
		original.Transparency = 1
	end
	table.insert(houses, house)
end
local meshes = {}
for index, parent in { art, homeArt, houses[1], houses[2], houses[3] } do
	local mesh = child("MeshPart", "AuthoredVisual" .. index, parent)
	stamp(mesh)
	mesh:SetAttribute("HarvestMeshKey", "fixture/" .. index)
	mesh:SetAttribute("HarvestPlacedFrame", CF.identity)
	mesh:SetAttribute("HarvestSourceFrame", CF.identity)
	mesh.CFrame = CF.new(index * 17, index + 0.5, index * -11) * CF.Angles(0, index / 5, 0)
	mesh.Size = V3.new(index + 1, index + 2, index + 3)
	mesh.Transparency = index / 10
	mesh.Anchored, mesh.CanCollide, mesh.CanTouch, mesh.CanQuery = true, false, false, false
	table.insert(
		meshes,
		{ Part = mesh, Frame = mesh.CFrame, Size = mesh.Size, Transparency = mesh.Transparency }
	)
end
local foreign = child("MeshPart", "ForeignArt", houses[1])
local calls = 0
local geometry = {
	MeshInfo = function(key)
		return key:match("^fixture/") and {}
	end,
	Apply = function(part, key)
		check(
			part ~= foreign and key == part:GetAttribute("HarvestMeshKey"),
			"Foreign art restored"
		)
		calls += 1
	end,
}
local gameProxy = {
	GetService = function(_, name)
		return if name == "Workspace"
			then world
			elseif name == "ReplicatedStorage" then storage
			else nil
	end,
}
local function module(path, extra)
	local env = setmetatable({
		game = gameProxy,
		Instance = I,
		Vector3 = V3,
		Vector2 = r.Vector2,
		CFrame = CF,
		Color3 = r.Color3,
		UDim2 = r.UDim2,
		Enum = r.Enum,
		require = function(required)
			return if required.Name == "MonsterPose" then {} else geometry
		end,
	}, { __index = getfenv() })
	for key, value in extra or {} do
		env[key] = value
	end
	local source = fs.readFile(path)
	if path:match("InventoryWorld.luau$") then
		-- Lune lacks the inherited engine Position property alias.
		source = source
			:gsub("slot%.Position", "slot.CFrame.Position")
			:gsub("world%.Ground%.Position", "world.Ground.CFrame.Position")
	end
	local fn = assert(loadstring(source, path))
	setfenv(fn, env)
	return fn()
end
local harvest = module("variants/B/server/Game/HarvestWorld.luau")
local result = harvest.Ensure()
check(calls == 5 and result.parts == 5 and result.changed == 0, "Moved art not restored once")
for _, saved in meshes do
	closeFrame(saved.Part.CFrame, saved.Frame)
	check(
		saved.Part.Size == saved.Size and saved.Part.Transparency == saved.Transparency,
		"Authored appearance changed"
	)
end
check(not pcall(harvest.Ensure, "A"), "Manual B switched variant")
local bad = child("WedgePart", "UnsupportedOwnedShape", art)
stamp(bad)
bad.Anchored, bad.CanCollide, bad.CanTouch, bad.CanQuery = true, false, false, false
local before = calls
check(
	not pcall(harvest.Ensure) and calls == before,
	"Unsupported owned class was not refused before apply"
)
bad:Destroy()
meshes[3].Part:SetAttribute("corn_project_id", "foreign")
check(not pcall(harvest.Ensure) and calls == before, "Foreign owned metadata accepted")
meshes[3].Part:SetAttribute("corn_project_id", project)

local slots = child("Folder", "KeySlots", map)
local runtime = child("Folder", "CornRoundRuntime", map)
local state = {
	Root = map,
	Runtime = runtime,
	Ground = ground,
	Slots = {},
	Radius = 12,
	IsOnPlayground = function(_, position)
		return math.abs(position.X) < 315 and math.abs(position.Z) < 315
	end,
}
local sites = {}
for index = 1, 15 do
	local site = child("Model", "Site" .. index, slots)
	local slot = child("Part", "solo_slot_" .. index, site)
	slot.CFrame, slot.Size = CF.new(index * 10 - 80, 0.06, 0), V3.new(6, 0.12, 6)
	site.PrimaryPart = slot
	local points = {}
	for _, kind in { "energy", "trap" } do
		local point = child("Part", if kind == "energy" then "EnergyPoint" else "TrapPoint", site)
		point:SetAttribute("corn_project_id", project)
		point:SetAttribute("BAuthoringHelper", true)
		point:SetAttribute("BAuthoringPoint", kind)
		point.Anchored = true
		point.CFrame = slot.CFrame
			* CF.new(
				if kind == "energy" then 3.6 else -3.6,
				if kind == "energy" then 8.62 else 0.16,
				0
			)
		points[kind] = point
	end
	site:PivotTo(CF.new(index * 10 - 80, 0.06, index * 3) * CF.Angles(0, math.pi / 2, 0))
	sites[index] = { Site = site, Points = points }
	table.insert(state.Slots, slot)
end
local itemModels = module("src/server/Game/ItemModels.luau")
local scriptRoot = child("Folder", "Game", nil)
local itemModule = child("ModuleScript", "ItemModels", scriptRoot)
local inventoryModule = child("ModuleScript", "InventoryWorld", scriptRoot)
local inventory = module("variants/B/server/Game/InventoryWorld.luau", {
	script = inventoryModule,
	require = function(required)
		check(required == itemModule, "Unexpected inventory dependency")
		return itemModels
	end,
})
local random = {
	NextInteger = function(_, _, high)
		return high
	end,
}
local owned = inventory.new(state, random, state.Slots[15], function() end)
check(
	#owned.pickups == 4 and #owned.folder.LookoutStumps:GetChildren() == 2,
	"Random item/stump counts changed"
)
for index, entry in owned.pickups do
	local kind = if index <= 2 then "energy" else "trap"
	check(entry.kind == kind, "Random item kinds changed")
	closeFrame(entry.anchor.CFrame, sites[index].Points[kind].CFrame)
	if kind == "energy" then
		local stump = owned.folder.LookoutStumps:FindFirstChild("Lookout" .. index).PrimaryPart
		closeFrame(
			stump.CFrame,
			sites[index].Points.energy.CFrame * CF.new(0, -4.68, 0) * CF.Angles(0, 0, math.pi / 2)
		)
	end
end
owned:Destroy()
check(#runtime:GetChildren() == 0, "Inventory cleanup left authored/runtime objects")
sites[15].Points.energy.Name = "MissingEnergyPoint"
check(
	not pcall(inventory.new, state, random, state.Slots[15], function() end),
	"Incomplete unselected site accepted"
)
check(#runtime:GetChildren() == 0, "Incomplete sites left partial runtime items")
sites[15].Points.energy.Name = "EnergyPoint"
map:SetAttribute("BManualAuthoringVersion", nil)
local legacy = inventory.new(state, random, state.Slots[15], function() end)
check(
	#legacy.pickups == 4 and #legacy.folder.LookoutStumps:GetChildren() == 2,
	"Legacy counts changed"
)
for index, entry in legacy.pickups do
	local slot = state.Slots[index]
	local energy = index <= 2
	local expected = CF.new(
		slot.CFrame.Position.X + (if energy then 3.6 else -3.6),
		if energy then 8.68 else 0.22,
		slot.CFrame.Position.Z
	)
	closeFrame(entry.anchor.CFrame, expected)
end
legacy:Destroy()
map:SetAttribute("BManualAuthoringVersion", 1)

local pending = {}
local connected, disconnected = 0, 0
local function event()
	return {
		Connect = function()
			connected += 1
			return {
				Disconnect = function()
					disconnected += 1
				end,
			}
		end,
	}
end
r.implementMethod("Instance", "GetAttributeChangedSignal", event)
r.implementMethod("Instance", "GetPropertyChangedSignal", event)
local controller = module("variants/B/client/Controllers/HarvestGeometryController.luau", {
	game = {
		GetService = function(_, name)
			return if name == "RunService"
				then {
					IsStudio = function()
						return true
					end,
				}
				else gameProxy:GetService(name)
		end,
	},
	task = {
		defer = function(callback)
			table.insert(pending, callback)
		end,
	},
	warn = function() end,
})
controller:Init({ Config = { Environment = "DEV", Game = { SessionMode = "team_local" } } })
controller._map = map
before = calls
controller:_ensure()
check(calls == before + 5 and controller._lastError == nil, "Client missed moved house/home art")
check(controller._parts[foreign] ~= nil, "Late ownership metadata is not watched inside a house")
local late = child("MeshPart", "LateReplicatedOverlay", houses[1])
stamp(late)
controller:_ensure()
check(
	controller._lastError == nil and controller._parts[late] ~= nil,
	"Client rejected pending metadata"
)
late:SetAttribute("HarvestMeshKey", "fixture/6")
before = calls
controller:_ensure()
check(calls == before + 6 and controller._lastError == nil, "Client did not restore late metadata")
meshes[1].Part:SetAttribute("corn_project_id", "foreign")
before = calls
controller:_ensure()
check(calls == before and controller._lastError ~= nil, "Client accepted foreign metadata")
meshes[1].Part:SetAttribute("corn_project_id", project)
controller:Destroy()
check(connected > 0 and connected == disconnected, "Client watchers leaked on destroy")
print(
	"PASS B manual world: "
		.. checks
		.. " binding/move/rotation/appearance/count/refusal/cleanup checks"
)
