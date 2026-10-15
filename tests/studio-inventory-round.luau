-- Real engine geometry and server methods; isolated owner fixture, no forging live pickups.
local Modules = game.ServerScriptService.GameServer.Game
local Solo = require(Modules.SoloRound)
local ItemWorld = require(Modules.InventoryWorld)
local Inventory = require(game.ReplicatedStorage.GameShared.Game.Inventory)
local Balance = require(game.ReplicatedStorage.GameShared.Game.Balance)
local Hunt = require(Modules.MonsterHunt)
local owner = game.Players:GetPlayers()[1]
assert(owner, "Play owner required")
local scratch = Instance.new("Model")
scratch.Name = "InventoryAcceptanceScratch"
scratch.Parent = workspace
local function part(name, size, position, parent, collision)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Position = position
	p.Anchored = true
	p.CanCollide = collision == true
	p.CanQuery = collision == true
	p.Parent = parent or scratch
	return p
end
local ground = part("Ground", Vector3.new(300, 2, 300), Vector3.new(0, 500, 0), scratch, true)
local runtime = Instance.new("Folder")
runtime.Name = "Runtime"
runtime.Parent = scratch
local props = Instance.new("Folder")
props.Name = "Props"
props.Parent = scratch
local home = Instance.new("Model")
home.Name = "Home"
home.Parent = props
part("Body", Vector3.new(1, 1, 1), Vector3.new(0, 504, 0), home, false)
local slots = {}
for i = 1, 15 do
	slots[i] = part("Slot" .. i, Vector3.one, Vector3.new((i - 8) * 12, 501, 30), scratch, false)
end
local character = Instance.new("Model")
character.Name = "OwnerFixture"
character.Parent = scratch
local humanoid = Instance.new("Humanoid")
humanoid.Parent = character
local root =
	part("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(40, 504, 0), character, false)
local world =
	{ Root = scratch, Runtime = runtime, Ground = ground, Slots = slots, Radius = 4, Home = home }
function world:IsValid()
	return true
end
function world:IsOnPlayground(point)
	return math.abs(point.X) < 150 and math.abs(point.Z) < 150
end
function world:SetInteractionEnabled() end
function world:IsGateFront()
	return true
end
function world:SetGateOpen()
	self.GatePrompt.Enabled = false
end
local gate = part("GateAnchor", Vector3.one, Vector3.new(100, 504, 0), scratch, false)
local gatePrompt = Instance.new("ProximityPrompt")
gatePrompt.Enabled = true
gatePrompt.Parent = gate
world.GateAnchor = gate
world.GatePrompt = gatePrompt
local context = {
	Config = { CoreLoop = Balance },
	Services = { NetworkService = {
		GetEvent = function()
			return {}
		end,
	} },
	Log = { Info = function() end, Warn = function() end },
}
local round = Solo.new(context)
round.world = world
round.player = owner
round.phase = "active"
round.roundCharacter = character
round._livingCharacter = function()
	return character, humanoid, root
end
round._send = function() end
round._moveToStart = function() end
round._clearKey = function() end
local checks = {}
local ok, problem = pcall(function()
	local rand = Random.new(345)
	round.items = ItemWorld.new(world, rand, slots[1], function() end)
	local kinds = { energy = 0, trap = 0 }
	local positions = {}
	for _, entry in round.items.pickups do
		kinds[entry.kind] += 1
		local pos = tostring(entry.anchor.Position)
		assert(not positions[pos])
		positions[pos] = true
		assert(entry.model:HasTag("corn_item_pickup"))
	end
	assert(kinds.energy == 2 and kinds.trap == 2 and #round.items.pickups == 4)
	checks.four_distinct_pickups_and_two_stumps = true
	assert(Inventory.Add(round.inventory, "energy"))
	assert(Inventory.Add(round.inventory, "trap"))
	assert(Inventory.Add(round.inventory, "key"))
	round:_inventoryRequest({}, "use", 1)
	assert(round.inventory.slots[1] == "energy")
	round:_inventoryRequest(owner, "use", 2)
	assert(round.inventory.slots[2] == "trap")
	round:_inventoryRequest(owner, "select", 6)
	assert(round.inventory.selected == 1)
	round:_inventoryRequest(owner, "use", 1)
	assert(round.inventory.slots[1] == "empty")
	round:_movement(0.1)
	assert(humanoid.WalkSpeed == 24)
	round.stamina.sprinting = true
	root.AssemblyLinearVelocity = Vector3.new(12, 0, 0)
	round.stamina.intent = true
	round:_movement(0.1)
	assert(humanoid.WalkSpeed == 36)
	round.inventory.energyUntil = os.clock() - 0.001
	round:_movement(0.1)
	assert(humanoid.WalkSpeed == 18)
	checks.owner_slot_guards_and_server_24_36_speed_expiry = true
	round.inventory.selected = 3
	round.interactionAt = -math.huge
	round:_inventoryRequest(owner, "use", 3)
	assert(round.inventory.slots[3] == "key")
	root.Position = gate.Position
	round:_openGate(owner)
	assert(not round.gateOpen, "Inventory key alone cannot bypass authoritative hasKey")
end)
local moreOk, moreProblem = pcall(function()
	round.hasKey = true
	round.interactionAt = -math.huge
	round:_openGate(owner)
	assert(round.gateOpen and not table.find(round.inventory.slots, "key"))
	checks.key_gate_consumption = true
	root.Position = Vector3.new(40, 504, 0)
	round.interactionAt = -math.huge
	round.inventory.selected = 2
	local wall = part("Wall", Vector3.new(6, 1, 6), Vector3.new(40, 502.5, 0), scratch, true)
	round:_inventoryRequest(owner, "use", 2)
	assert(round.inventory.slots[2] == "trap" and #round.items.traps == 0)
	wall:Destroy()
	round.interactionAt = -math.huge
	round:_inventoryRequest(owner, "use", 2)
	assert(round.inventory.slots[2] == "empty" and #round.items.traps == 1)
	local trap = round.items.traps[1]
	assert(not trap.spent)
	-- A player crossing cannot trigger: only CheckTraps(monster) owns the transition.
	root.Position = trap.position + Vector3.new(0, 3, 0)
	task.wait(0.05)
	assert(not trap.spent)
	local hunt = Hunt.new(world, Balance, os.clock() - 20)
	round.hunt = hunt
	hunt:_state("patrol")
	hunt.model:PivotTo(CFrame.new(trap.position + Vector3.new(5, 3, 0)))
	local from = trap.position + Vector3.new(-5, 3, 0)
	assert(
		round.items:CheckTraps(hunt, from, os.clock()) and hunt.state == "trapped" and trap.spent
	)
	assert(not round.items:CheckTraps(hunt, from, os.clock()))
	checks.floor_rejection_place_player_safe_swept_monster_only = true
	local energy = round.items.pickups[1]
	root.Position = energy.anchor.Position + Vector3.new(0, 0, -2)
	assert(Inventory.Add(round.inventory, "energy"))
	round.inventory.selected = 1
	round.interactionAt = -math.huge
	round:_inventoryRequest(owner, "use", 1)
	assert(round.inventory.slots[1] == "energy", "E world prompt priority")
	assert(round:_canInteract(owner, energy.anchor, energy.prompt))
	assert(round.items:Take(energy) and not round.items:Take(energy))
	checks.prompt_priority_and_one_time_take = true
	round.inventory = Inventory.new(os.clock())
	Inventory.Add(round.inventory, "key")
	Inventory.Add(round.inventory, "energy")
	Inventory.Add(round.inventory, "trap")
	round.inventory.energyUntil = os.clock() + 30
	round.hasKey = true
	round.gateOpen = false
	round.catches = 0
	world.DropKey = function()
		local key = part("DroppedKey", Vector3.one, root.Position, runtime, false)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Parent = key
		world.Key = key
		world.KeyPrompt = prompt
		return prompt
	end
	round:_caught(root)
	assert(
		round.phase == "caught"
			and not round.hasKey
			and not table.find(round.inventory.slots, "key")
			and table.find(round.inventory.slots, "energy")
			and table.find(round.inventory.slots, "trap")
			and round.inventory.energyUntil == 0
	)
	task.wait(1.1)
	assert(round.phase == "caught" and round.captureUntil == 0 and round.catches == 1)
	round:_request(owner, "revive", nil)
	assert(round.phase == "active")
	checks.first_catch_preserves_consumables_drops_key_clears_buff = true
	round:_finish("aborted", "")
	assert(round.phase == "aborted")
	assert(
		not runtime:FindFirstChild("InventoryItems")
			and not table.find(round.inventory.slots, "energy")
	)
	checks.cleanup = true
	if not hunt.destroyed then
		hunt:Destroy()
	end
end)
scratch:Destroy()
assert(ok, problem)
assert(moreOk, moreProblem)
checks.method =
	"Actual engine Parts/raycast and isolated authoritative SoloRound/InventoryWorld/MonsterHunt; live E separately"
return checks
