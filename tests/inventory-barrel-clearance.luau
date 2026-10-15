-- Real saved barrel geometry + production item Sources in a bounded Lune adapter.
-- No engine physics, native E, renderer or scene serialization claim.
local adapter = require("./scene-adapter")
local serde = require("@lune/serde")
local fs, r, V3, CF = adapter.fs, adapter.r, adapter.V3, adapter.CF
local bytes = fs.readFile("place/Children_of_corn.before-resize-yellow-20261015.rbxl")
local place = r.deserializePlace(bytes)
local map = place:GetService("Workspace").CornMap
local modules = place:GetService("ServerScriptService").GameServer.Game
for _, name in { "InventoryWorld", "ItemModels" } do
	local source = fs.readFile("src/server/Game/" .. name .. ".luau")
	-- Lune omits Position defaults; emulate the engine CFrame/Position alias.
	if name == "InventoryWorld" then
		source = source
			:gsub("slot%.Position", "slot.CFrame.Position")
			:gsub("world%.Ground%.Position", "world.Ground.CFrame.Position")
	end
	modules[name].Source = source
end
local environment = setmetatable({
	game = place,
	workspace = place:GetService("Workspace"),
	Instance = r.Instance,
	CFrame = CF,
	Vector3 = V3,
	Vector2 = r.Vector2,
	Color3 = r.Color3,
	UDim2 = r.UDim2,
	Enum = r.Enum,
}, { __index = getfenv() })
local modelsFn = assert(loadstring(modules.ItemModels.Source))
setfenv(modelsFn, environment)
local Models = modelsFn()
environment.script = modules.InventoryWorld
environment.require = function(module)
	assert(module == modules.ItemModels, "Unexpected item dependency")
	return Models
end
local itemsFn = assert(loadstring(modules.InventoryWorld.Source))
setfenv(itemsFn, environment)
local ItemWorld = itemsFn()
local slots = map.KeySlots:GetChildren()
table.sort(slots, function(a, b)
	return a:GetAttribute("slot_id") < b:GetAttribute("slot_id")
end)
assert(#slots == 15, "Expected fifteen saved key slots")
local barrels = {}
for _, index in { 3, 8, 13 } do
	for _, object in map.Props:GetChildren() do
		if object:IsA("BasePart") and object:HasTag("corn_barrel") then
			local delta = object.CFrame.Position - slots[index].CFrame.Position
			if (delta - V3.new(2.8, 1.94, 0)).Magnitude < 0.001 then
				assert(not barrels[index], "Ambiguous legacy barrel")
				barrels[index] = object
			end
		end
	end
	local barrel = assert(barrels[index], "Saved legacy barrel missing")
	assert(
		barrel.Shape == r.Enum.PartType.Cylinder and barrel.CanCollide and barrel.CanQuery,
		"Saved barrel must remain a collidable cylinder"
	)
end
local runtime = r.Instance.new("Folder")
runtime.Name = "BarrelClearanceTestRuntime"
runtime.Parent = map
local world = { Root = map, Runtime = runtime, Ground = map.Ground, Radius = 4 }
local floor = map.Ground.CFrame.Position.Y + map.Ground.Size.Y / 2
local random = {
	NextInteger = function(_, _, high)
		return high
	end,
}
local checkedRounds, oldInside, visibleParts, minBarrelGap = 0, 0, 0, math.huge
local function cylinderContains(barrel, point)
	local localPoint = barrel.CFrame:PointToObjectSpace(point)
	return math.abs(localPoint.X) < barrel.Size.X / 2
		and localPoint.Y * localPoint.Y / (barrel.Size.Y * barrel.Size.Y / 4)
				+ localPoint.Z * localPoint.Z / (barrel.Size.Z * barrel.Size.Z / 4)
			< 1
end
local function indexAfter(index, amount)
	return (index + amount - 1) % #slots + 1
end
local function runVariant()
	for index, target in slots do
		local key = slots[indexAfter(index, 4)]
		world.Slots = {
			key,
			slots[indexAfter(index, 1)],
			slots[indexAfter(index, 2)],
			target,
			slots[indexAfter(index, 3)],
		}
		for _, slot in slots do
			if not table.find(world.Slots, slot) then
				table.insert(world.Slots, slot)
			end
		end
		local items = ItemWorld.new(world, random, key, function() end)
		assert(
			#items.pickups == 4 and #items.folder.LookoutStumps:GetChildren() == 2,
			"Pickup/lookout counts changed"
		)
		local counts, used = { energy = 0, trap = 0 }, {}
		for _, pickup in items.pickups do
			counts[pickup.kind] += 1
			local offset = if pickup.kind == "energy" then 3.6 else -3.6
			local center = pickup.anchor.CFrame.Position - V3.new(offset, 0, 0)
			local source
			for _, slot in slots do
				if
					V3.new(center.X - slot.CFrame.Position.X, 0, center.Z - slot.CFrame.Position.Z).Magnitude
					< 0.001
				then
					source = slot
				end
			end
			assert(
				source and source ~= key and not used[source],
				"Pickup must retain distinct nonkey slot binding"
			)
			used[source] = true
			assert(
				pickup.prompt.MaxActivationDistance == 4 and pickup.prompt.RequiresLineOfSight,
				"Pickup range/LOS changed"
			)
			assert(
				pickup.prompt.KeyboardKeyCode == r.Enum.KeyCode.E
					and pickup.model:HasTag("corn_item_pickup"),
				"Pickup input/tag binding changed"
			)
		end
		assert(counts.energy == 2 and counts.trap == 2, "Two-energy/two-trap rule changed")
		local trap = items.pickups[3]
		assert(
			trap.kind == "trap" and math.abs(trap.anchor.CFrame.Position.Y - floor - 0.22) < 0.001,
			"Ground trap height changed"
		)
		assert(
			(trap.anchor.CFrame.Position - V3.new(
				target.CFrame.Position.X - 3.6,
				floor + 0.22,
				target.CFrame.Position.Z
			)).Magnitude < 0.001,
			"Trap lost its selected-slot binding"
		)
		local barrel = barrels[index]
		if barrel then
			assert(
				cylinderContains(
					barrel,
					V3.new(target.CFrame.Position.X + 3.6, floor + 0.22, target.CFrame.Position.Z)
				),
				"Regression geometry must prove former pickup inside wood"
			)
			assert(
				not cylinderContains(barrel, trap.anchor.CFrame.Position),
				"New trap still inside legacy wood"
			)
			oldInside += 1
		end
		for _, part in trap.model:GetChildren() do
			if part:IsA("BasePart") then
				for _, x in { -1, 1 } do
					for _, y in { -1, 1 } do
						for _, z in { -1, 1 } do
							local point =
								part.CFrame:PointToWorldSpace(part.Size * V3.new(x, y, z) / 2)
							local relative = point - target.CFrame.Position
							assert(
								relative.X >= -5 and relative.X <= 6.6 and math.abs(relative.Z) <= 3,
								"Trap outside approved cluster footprint"
							)
							assert(
								relative.X * relative.X + relative.Z * relative.Z <= 36,
								"Trap outside corn clearing"
							)
							if barrel then
								local barrelLeft = barrel.CFrame.Position.X - barrel.Size.Y / 2
								local gap = barrelLeft - point.X
								assert(
									gap > 0,
									"Trap geometry intersects legacy cylinder X interval"
								)
								minBarrelGap = math.min(minBarrelGap, gap)
							end
						end
					end
				end
				visibleParts += 1
			end
		end
		items:Destroy()
		assert(#runtime:GetChildren() == 0, "Item runtime cleanup incomplete")
		checkedRounds += 1
	end
end
runVariant()
local layout = serde.decode("json", fs.readFile("scripts/resize-layout.json"))
for index, slot in slots do
	local row = layout.slots[index]
	assert(row.slot_id == slot:GetAttribute("slot_id"), "Resize slot ordering mismatch")
	local target = V3.new(table.unpack(row.center))
	local delta = target - slot.CFrame.Position
	if barrels[index] then
		barrels[index].CFrame = CF.new(delta) * barrels[index].CFrame
	end
	slot.CFrame = CF.new(target) * slot.CFrame.Rotation
end
runVariant()
runtime:Destroy()
assert(
	checkedRounds == 30 and oldInside == 6 and minBarrelGap > 3,
	"Incomplete before/after legacy regression coverage"
)
assert(
	fs.readFile("place/Children_of_corn.before-resize-yellow-20261015.rbxl") == bytes,
	"Immutable scene bytes changed during adapter fixture"
)
print(serde.encode("json", {
	passed = true,
	actual_saved_legacy_cylinders = 3,
	before_and_after_resize_rounds = checkedRounds,
	proved_former_inside_barrel_cases = oldInside,
	checked_trap_parts = visibleParts,
	minimum_trap_to_barrel_x_gap = minBarrelGap,
	all15_slot_bindings_preserved = true,
	counts_and_key_exclusion_preserved = true,
	scope = "Production InventoryWorld/ItemModels and actual saved cylinder geometry in bounded Lune adapter; analytical separation/footprint, no engine raycast/native E/scene write claim",
}))
