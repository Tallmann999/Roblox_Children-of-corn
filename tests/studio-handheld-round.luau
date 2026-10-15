-- Real engine geometry and server methods; isolated owner fixture, no forging live pickups.
local Modules = game.ServerScriptService.GameServer.Game
local Solo = require(Modules.SoloRound)
local ItemWorld = require(Modules.InventoryWorld)
local Inventory = require(game.ReplicatedStorage.GameShared.Game.Inventory)
local Capture = require(game.ReplicatedStorage.GameShared.Game.CapturePresentation)
local Balance = require(game.ReplicatedStorage.GameShared.Game.Balance)
local Hunt = require(Modules.MonsterHunt)
local owner = game.Players:GetPlayers()[1]
assert(owner, "Play owner required")
local scratch = Instance.new("Model")
scratch.Name = "HandheldAcceptanceScratch"
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
local sent = {}
round._send = function(self)
	local shot = {
		id = self.catches,
		remaining = math.clamp(self.captureUntil - os.clock(), 0, 1),
		frame = self.captureFrame,
	}
	assert(Capture.IsValidSnapshot(shot))
	table.insert(sent, { phase = self.phase, capture = shot })
end
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
	assert(
		round.inventory.slots[1] == "energy"
			and round.inventory.useId == 0
			and round.inventory.useKind == "none"
	)
	round:_inventoryRequest(owner, "use", 2)
	assert(round.inventory.slots[2] == "trap" and round.inventory.useId == 0)
	round:_inventoryRequest(owner, "select", 6)
	assert(round.inventory.selected == 1)
	round:_inventoryRequest(owner, "use", 1)
	assert(
		round.inventory.slots[1] == "empty"
			and round.inventory.useId == 1
			and round.inventory.useKind == "energy"
	)
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
	assert(
		round.inventory.slots[3] == "key"
			and round.inventory.useId == 1
			and round.inventory.useKind == "energy"
	)
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
	assert(
		round.inventory.slots[2] == "trap"
			and #round.items.traps == 0
			and round.inventory.useId == 1
	)
	wall:Destroy()
	round.interactionAt = -math.huge
	round:_inventoryRequest(owner, "use", 2)
	assert(
		round.inventory.slots[2] == "empty"
			and #round.items.traps == 1
			and round.inventory.useId == 2
			and round.inventory.useKind == "trap"
	)
	checks.accepted_use_counter_only_committed_energy_and_trap = true
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
	local moves = 0
	round._moveToStart = function()
		moves += 1
	end
	round:_request({}, "revive", nil)
	round:_request(owner, "revive", nil)
	assert(round.phase == "caught" and moves == 0, "Foreign and early revival refused")
	task.wait(1.1)
	assert(
		round.phase == "caught"
			and round.captureUntil == 0
			and round.catches == 1
			and humanoid.WalkSpeed == 0
			and moves == 0
	)
	local elapsedBefore = round.elapsed
	local roundId = round.minimap:Snapshot().round_id
	round:_request(owner, "revive", nil)
	assert(
		round.phase == "active"
			and moves == 1
			and round.catches == 1
			and round.elapsed == elapsedBefore
			and round.minimap:Snapshot().round_id == roundId
	)
	assert(
		round.protectedUntil > os.clock()
			and round.hunt.state == "patrol"
			and world.KeyPrompt.Parent ~= nil
	)
	round:_request(owner, "revive", nil)
	assert(moves == 1, "Duplicate revival cannot move again")
	checks.first_catch_waits_for_owner_revive_preserves_round_key_consumables_and_time = true
	assert(sent[#sent].capture.remaining == 0 and sent[#sent].capture.id == 1)
	round:_caught(root)
	assert(
		round.phase == "caught"
			and round.catches == 2
			and round.hunt.state == "capturing"
			and humanoid.WalkSpeed == 0
	)
	local still = round.hunt.root.CFrame
	assert(
		not round.hunt:Step(0.25, os.clock() + 5, root, false)
			and round.hunt.root.CFrame == still
			and not round.hunt:CanCapture(root)
	)
	assert(
		sent[#sent].capture.id == 2
			and sent[#sent].capture.remaining > 0
			and sent[#sent].phase == "caught"
	)
	task.wait(1.1)
	assert(round.phase == "caught_out" and round.reward == 0 and round.captureUntil == 0)
	checks.second_capture_delayed_defeat_and_no_root_motion = true
	-- Abort invalidates the scheduled capture return, even while an NPC is frozen.
	round.phase = "active"
	round.catches = 0
	round.hunt = Hunt.new(world, Balance, os.clock() - 20)
	round:_caught(root)
	round:_finish("aborted", "")
	local epoch = round.epoch
	task.wait(1.1)
	assert(
		round.phase == "aborted"
			and round.epoch == epoch
			and round.hunt == nil
			and round.captureUntil == 0
	)
	checks.abort_epoch_cancels_delayed_transition = true
	assert(round.phase == "aborted")
	assert(
		not runtime:FindFirstChild("InventoryItems")
			and not table.find(round.inventory.slots, "energy")
	)
	checks.cleanup = true
	-- The first post-cinematic Exit choice must leave the held round, not hang.
	round.phase = "active"
	round.catches = 0
	round.hunt = Hunt.new(world, Balance, os.clock() - 20)
	round:_caught(root)
	round.requestTokens = 2
	round:_request(owner, "menu", nil)
	assert(round.phase == "caught" and round.hunt ~= nil, "Early capture menu refused")
	task.wait(1.1)
	local menuEpoch = round.epoch
	round:_request(owner, "menu", nil)
	assert(
		round.phase == "ready"
			and round.hunt == nil
			and round.audio == nil
			and round.epoch > menuEpoch
	)
	assert(round.elapsed == 0 and round.startedAt == nil and not round.gateOpen)
	checks.first_capture_menu_clears_held_hunt_and_returns_mode_selection = true
	if not hunt.destroyed then
		hunt:Destroy()
	end
end)
scratch:Destroy()
assert(ok, problem)
assert(moreOk, moreProblem)
checks.method =
	"Actual engine Parts/raycast/server clocks, isolated SoloRound/MonsterHunt; both1secondcaptures,finaldefeat,abortepoch; handheldclientvisualacceptedusage separately"
return checks
