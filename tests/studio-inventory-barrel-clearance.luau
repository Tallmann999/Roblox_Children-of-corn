-- Isolated actual-engine collision/LOS test; live native E remains separate.
local ItemWorld = require(game.ServerScriptService.GameServer.Game.InventoryWorld)
local map = assert(workspace:FindFirstChild("CornMap"), "Children_of_corn map required")
assert(
	map:GetAttribute("corn_project_id") == "children_of_corn" and map.FieldZone.Size.X == 630,
	"Resized Children_of_corn required"
)
local scratch = Instance.new("Model")
scratch.Name = "InventoryBarrelAcceptanceScratch"
scratch:SetAttribute("corn_test_owned", true)
scratch.Parent = workspace
local items
local results = {}
local function part(name, size, frame, parent, collision)
	local object = Instance.new("Part")
	object.Name, object.Size, object.CFrame = name, size, frame
	object.Anchored, object.CanCollide, object.CanQuery = true, collision, collision
	object.Parent = parent
	return object
end
local ground = part("Ground", Vector3.new(630, 2, 630), CFrame.new(0, 500, 0), scratch, true)
local runtime = Instance.new("Folder")
runtime.Name, runtime.Parent = "Runtime", scratch
local sourceSlots = map.KeySlots:GetChildren()
table.sort(sourceSlots, function(a, b)
	return a:GetAttribute("slot_id") < b:GetAttribute("slot_id")
end)
assert(#sourceSlots == 15, "Expected fifteen actual key slots")
local slots = {}
for index, source in sourceSlots do
	slots[index] = part(
		source.Name,
		source.Size,
		CFrame.new(source.Position.X, 501, source.Position.Z),
		scratch,
		false
	)
end
local world = { Root = scratch, Runtime = runtime, Ground = ground, Radius = 4 }
local random = {
	NextInteger = function(_, _, high)
		return high
	end,
}
local ok, problem = pcall(function()
	for _, index in { 3, 8, 13 } do
		local sourceBarrel
		for _, candidate in map.Props:GetChildren() do
			if candidate:IsA("BasePart") and candidate:HasTag("corn_barrel") then
				local relative = candidate.Position - sourceSlots[index].Position
				if (relative - Vector3.new(2.8, 1.94, 0)).Magnitude < 0.002 then
					assert(not sourceBarrel, "Ambiguous original barrel")
					sourceBarrel = candidate
				end
			end
		end
		local barrel = assert(sourceBarrel, "Actual legacy barrel missing"):Clone()
		barrel.Name = "LegacyBarrel" .. index
		local originalFloor = map.Ground.Position.Y + map.Ground.Size.Y / 2
		barrel.CFrame = CFrame.new(0, 501 - originalFloor, 0) * barrel.CFrame
		barrel.Parent = scratch
		assert(
			barrel.Shape == Enum.PartType.Cylinder and barrel.CanCollide and barrel.CanQuery,
			"Legacy cylinder must retain actual collision/query"
		)
		local key = slots[(index + 3) % #slots + 1]
		world.Slots = {
			key,
			slots[index % #slots + 1],
			slots[(index + 1) % #slots + 1],
			slots[index],
			slots[(index + 2) % #slots + 1],
		}
		for _, slot in slots do
			if not table.find(world.Slots, slot) then
				table.insert(world.Slots, slot)
			end
		end
		items = ItemWorld.new(world, random, key, function() end)
		assert(
			#items.pickups == 4 and #items.folder.LookoutStumps:GetChildren() == 2,
			"Pickup/lookout counts changed"
		)
		local counts = { energy = 0, trap = 0 }
		for _, pickup in items.pickups do
			counts[pickup.kind] += 1
		end
		assert(counts.energy == 2 and counts.trap == 2, "Two-energy/two-trap rule changed")
		local trap = items.pickups[3]
		assert(
			trap.kind == "trap"
				and math.abs(trap.anchor.Position.X - slots[index].Position.X + 3.6) < 0.001,
			"Trap lost selected legacy-slot binding"
		)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { barrel }
		params.RespectCanCollide = true
		local oldAnchor =
			Vector3.new(slots[index].Position.X + 3.6, 501.22, slots[index].Position.Z)
		local oldEye = oldAnchor + Vector3.new(0, 5, 2)
		local oldHit = workspace:Raycast(oldEye, oldAnchor - oldEye, params)
		assert(
			oldHit and oldHit.Instance == barrel,
			"Former trap LOS must actually hit legacy cylinder"
		)
		local newEye = trap.anchor.Position + Vector3.new(0, 5, 2)
		assert(
			not workspace:Raycast(newEye, trap.anchor.Position - newEye, params),
			"New trap still blocked by legacy cylinder"
		)
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Include
		overlap.FilterDescendantsInstances = { barrel }
		overlap.RespectCanCollide = true
		local checked = 0
		for _, object in trap.model:GetChildren() do
			if object:IsA("BasePart") then
				assert(
					#workspace:GetPartBoundsInBox(object.CFrame, object.Size, overlap) == 0,
					"New trap part intersects actual collidable barrel"
				)
				checked += 1
			end
		end
		table.insert(results, {
			slot_id = sourceSlots[index]:GetAttribute("slot_id"),
			old_ray_blocked = true,
			new_ray_clear = true,
			new_barrel_overlaps = 0,
			trap_parts_checked = checked,
			energy = counts.energy,
			traps = counts.trap,
		})
		items:Destroy()
		items = nil
		barrel:Destroy()
		assert(#runtime:GetChildren() == 0, "Item runtime cleanup incomplete")
	end
end)
if items then
	items:Destroy()
end
scratch:Destroy()
assert(ok, tostring(problem))
assert(#results == 3, "Incomplete actual legacy barrel coverage")
return game.HttpService:JSONEncode({
	passed = true,
	cases = results,
	cleanup = workspace:FindFirstChild("InventoryBarrelAcceptanceScratch") == nil,
	scope = "Actual production ItemWorld, cloned authored cylinders, engine raycasts and overlap queries in isolated elevated scratch; live native E separately",
})
