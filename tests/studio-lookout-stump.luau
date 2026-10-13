-- Isolated real engine collision/raycast and pickup lifetime fixture.
-- Actual avatar jumps and E are checked separately in the working map.
local ItemWorld = require(game.ServerScriptService.GameServer.Game.InventoryWorld)
local Models = require(game.ServerScriptService.GameServer.Game.ItemModels)
local scratch = Instance.new("Model")
scratch.Name = "LookoutAcceptanceScratch"
scratch:SetAttribute("corn_test_owned", true)
scratch.Parent = workspace
local items
local checks = {}
local function part(name, size, position, parent, collision)
	local p = Instance.new("Part")
	p.Name, p.Size, p.Position = name, size, position
	p.Anchored = true
	p.CanCollide, p.CanQuery = collision == true, collision == true
	p.Parent = parent
	return p
end
local ground = part("Ground", Vector3.new(300, 2, 300), Vector3.new(0, 500, 0), scratch, true)
local runtime = Instance.new("Folder")
runtime.Name = "Runtime"
runtime.Parent = scratch
local slots = {}
for i = 1, 15 do
	slots[i] = part("Slot" .. i, Vector3.one, Vector3.new((i - 8) * 15, 501, 30), scratch, false)
end
local world = { Root = scratch, Runtime = runtime, Ground = ground, Slots = slots, Radius = 4 }
function world:IsOnPlayground(point)
	return math.abs(point.X) < 150 and math.abs(point.Z) < 150
end
local ok, problem = pcall(function()
	items = ItemWorld.new(world, Random.new(345), slots[1], function() end)
	local lookouts = items.folder.LookoutStumps
	assert(#lookouts:GetChildren() == 2, "Exactly two energy lookouts per round")
	local floor = ground.Position.Y + ground.Size.Y / 2
	local collisions = {}
	for _, lookout in lookouts:GetChildren() do
		assert(lookout:HasTag("corn_lookout_stump") and lookout:GetAttribute("LookoutVersion") == 1)
		assert(lookout:GetAttribute("corn_project_id") == "children_of_corn")
		local stump = lookout.Stump
		assert(stump == lookout.PrimaryPart and stump.Size.X == 8 and stump.Size.Y == 6)
		assert(math.abs(stump.Position.Y - 4 - floor) < 0.001, "Lookout sits on actual ground")
		for _, pair in { { stump, 8 }, { lookout.Step1, 2.5 }, { lookout.Step2, 5 } } do
			local body, height = pair[1], pair[2]
			assert(body.CanCollide and body.CanQuery and body.Anchored and not body.CanTouch)
			local hit = workspace:Raycast(body.Position + Vector3.new(0, 20, 0), Vector3.new(0, -25, 0))
			assert(hit and hit.Instance == body, "Actual collision surface must be raycastable")
			assert(math.abs(hit.Position.Y - floor - height) < 0.001)
			table.insert(collisions, { name = body.Name, top = hit.Position.Y - floor })
		end
		local bodyCount = 0
		for _, child in lookout:GetChildren() do
			assert(child:IsA("BasePart") and child.Anchored, "Bounded simple lookout geometry")
			bodyCount += 1
		end
		assert(bodyCount == 6)
	end
	checks.actual_collision_surfaces = collisions
	checks.two_grounded_lookouts_with_reachable_height_steps = true
	local character = Instance.new("Model")
	character.Name = "PlacementFixture"
	character.Parent = scratch
	local root = part("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(0, 504, -50), character, false)
	for _, lookout in lookouts:GetChildren() do
		for _, name in { "Step1", "Step2" } do
			local body = lookout[name]
			root.Position = body.Position + Vector3.new(0, body.Size.X / 2 + 3.2, 0)
			assert(not items:Place(root, character) and #items.traps == 0, "Trap placed through lookout wood")
		end
	end
	root.Position = Vector3.new(0, 504, -50)
	assert(items:Place(root, character) and #items.traps == 1, "Ordinary ground placement regressed")
	checks.traps_reject_wooden_steps_and_still_place_on_ground = true
	local energy, traps = 0, 0
	for _, pickup in items.pickups do
		if pickup.kind == "energy" then
			energy += 1
			assert(math.abs(pickup.anchor.Position.Y - floor - Models.StumpHeight - 0.68) < 0.001)
			local before = #lookouts:GetChildren()
			assert(items:Take(pickup))
			assert(not pickup.model.Parent and #lookouts:GetChildren() == before)
		elseif pickup.kind == "trap" then
			traps += 1
			assert(math.abs(pickup.anchor.Position.Y - floor - 0.22) < 0.001)
		end
	end
	assert(energy == 2 and traps == 2)
	checks.energy_on_top_traps_unchanged_lookout_survives_pickup = true
	items:Destroy()
	items = nil
	assert(#runtime:GetChildren() == 0)
	checks.terminal_inventory_geometry_cleanup = true
end)
if items then items:Destroy() end
scratch:Destroy()
assert(ok, tostring(problem))
checks.method = "Actual isolated engine collision raycasts and pickup ownership/lifetime; no live avatar relocation or ordinary climbing claim"
return game.HttpService:JSONEncode(checks)
