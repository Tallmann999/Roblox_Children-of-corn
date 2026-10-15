-- Verified Children_of_corn Studio Play / SERVER only. No native-input acceptance.
-- Actual SoloRound/AuthoredWorld/MonsterHunt methods, real engine geometry/clocks.
-- Fixture boundaries: fake NetworkService sink, an owned character lookup and
-- owned-character spawn movement. No live Player.Character/Root/Lighting writes.
-- Deadlines are first checked at the real120sec setting, then explicitly expired
-- by this server fixture; this is not a120sec endurance or blind-round test.
local RunService = game:GetService("RunService")
assert(
	RunService:IsStudio() and RunService:IsRunning() and RunService:IsServer(),
	"Studio Play Server required"
)
local actualMap = assert(workspace:FindFirstChild("CornMap"), "Children_of_corn map missing")
assert(actualMap:GetAttribute("corn_project_id") == "children_of_corn", "Wrong Studio target")
local Players = game:GetService("Players")
local owner = assert(Players:GetPlayers()[1], "Real Play owner required")
local Modules = game.ServerScriptService.GameServer.Game
local Solo = require(Modules.SoloRound)
local Hunt = require(Modules.MonsterHunt)
local AuthoredWorld = require(Modules.AuthoredWorld)
local Shared = game.ReplicatedStorage.GameShared.Game
local Inventory = require(Shared.Inventory)
local Balance = require(Shared.Balance)
local HttpService = game:GetService("HttpService")
local scratch, rounds = nil, {}
local checks, snapshots = {}, {}
local began = os.clock()
local function expect(value, message)
	return assert(value, message or "Finale engine fixture assertion failed")
end
local function part(name, size, position, parent, collidable)
	local item = Instance.new("Part")
	item.Name, item.Size, item.Position = name, size, position
	item.Anchored, item.CanCollide, item.CanQuery, item.CanTouch =
		true, collidable == true, collidable == true, false
	item.Parent = parent
	return item
end
local ok, problem = xpcall(function()
	scratch = Instance.new("Model")
	scratch.Name = "FinaleAcceptance_" .. HttpService:GenerateGUID(false)
	scratch:SetAttribute("corn_test_owned", true)
	scratch:SetAttribute("corn_project_id", "children_of_corn")
	scratch.Parent = workspace
	local y = actualMap.Ground.Position.Y + 500
	local ground = part("Ground", Vector3.new(840, 2, 840), Vector3.new(0, y, 0), scratch, true)
	local runtime = Instance.new("Folder")
	runtime.Name = "CornRoundRuntime"
	runtime:SetAttribute("corn_project_id", "children_of_corn")
	runtime.Parent = scratch
	local props = Instance.new("Folder")
	props.Name, props.Parent = "Props", scratch
	local home = Instance.new("Model")
	home.Name, home.Parent = "Home", props
	part("Body", Vector3.one, Vector3.new(-250, y + 4, -250), home, false)
	local bounds =
		part("PlayBounds", Vector3.new(840, 80, 840), Vector3.new(0, y + 20, 0), scratch, false)
	local field =
		part("FieldZone", Vector3.new(840, 1, 840), Vector3.new(0, y + 1, 0), scratch, false)
	local spawn =
		part("RoundSpawn", Vector3.new(6, 1, 6), Vector3.new(-350, y + 1, -350), scratch, false)
	spawn:AddTag("corn_spawn")
	spawn:SetAttribute("spawn_id", "finale_fixture")
	local slots = {}
	for index = 1, 15 do
		local slot = part(
			"Slot" .. string.format("%02d", index),
			Vector3.one,
			Vector3.new((index - 1) % 5 * 80 - 160, y + 1, math.floor((index - 1) / 5) * 80 - 160),
			scratch,
			false
		)
		slot:AddTag("corn_key_slot")
		slot:SetAttribute("slot_id", tostring(index))
		table.insert(slots, slot)
	end
	local gateModel = Instance.new("Model")
	gateModel.Name, gateModel.Parent = "Gate", scratch
	gateModel:SetAttribute("gate_id", "finale_fixture")
	local gate = part("Door", Vector3.new(12, 12, 2), Vector3.new(0, y + 7, 200), gateModel, true)
	local anchor =
		part("InteractionAnchor", Vector3.one, Vector3.new(0, y + 4, 198), gateModel, false)
	local exit =
		part("ExitZone", Vector3.new(10, 10, 10), Vector3.new(0, y + 4, 207), gateModel, false)
	exit:SetAttribute("gate_id", "finale_fixture")
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name, prompt.Parent = "CornGatePrompt", anchor
	local world = setmetatable({
		Root = scratch,
		Runtime = runtime,
		Ground = ground,
		Field = field,
		Bounds = bounds,
		Spawn = spawn,
		Spawns = { spawn },
		Slots = slots,
		Home = home,
		Radius = 4,
		GateModel = gateModel,
		Gate = gate,
		GateAnchor = anchor,
		GatePrompt = prompt,
		Exit = exit,
		ClosedTransparency = gate.Transparency,
		ClosedCollision = gate.CanCollide,
		ClosedQuery = gate.CanQuery,
	}, { __index = AuthoredWorld })
	expect(world:IsValid(), "Actual AuthoredWorld rejected fixture schema")
	local character = Instance.new("Model")
	character.Name, character.Parent = "OwnedCharacterFixture", scratch
	local root =
		part("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(0, y + 4, 196), character, false)
	character.PrimaryPart = root
	local humanoid = Instance.new("Humanoid")
	humanoid.RequiresNeck, humanoid.Parent = false, character
	local front = root.CFrame
	local event = {
		FireClient = function(_, target, snapshot)
			expect(target == owner, "Snapshot targeted a different player")
			expect(
				type(snapshot.evacuation) == "table" and snapshot.evacuation.duration == 120,
				"Missing authoritative evacuation snapshot"
			)
			expect(snapshot.evacuation.remaining >= 0 and snapshot.evacuation.remaining <= 120)
			table.insert(snapshots, snapshot)
		end,
	}
	local context = {
		Config = { CoreLoop = Balance },
		Services = { NetworkService = {
			GetEvent = function()
				return event
			end,
		} },
		Log = { Info = function() end, Warn = function() end },
	}
	local function request(round, player, action, mode)
		round.requestTokens, round.requestAt = 2, os.clock()
		round:_request(player, action, mode)
	end
	local function newRound(mode)
		for _, previous in rounds do
			previous.epoch += 1
			previous.phase = "aborted"
			previous:_stopHunt()
			previous:_clearInventory()
		end
		world:ClearKey()
		world:SetGateOpen(false)
		world:SetInteractionEnabled(true, false)
		root.CFrame, humanoid.Health = front, 100
		local round = Solo.new(context)
		table.insert(rounds, round)
		round.world, round.player, round.roundCharacter = world, owner, character
		round.selectedSpawn, round.phase, round.lightingMode = spawn, "active", mode
		round.startedAt, round.huntAt = os.clock() - 30, os.clock()
		round.minimap:ResetHistory()
		-- Only substitute the character/account boundary; tested gameplay methods
		-- keep their real implementations and real Humanoid/Parts.
		round._livingCharacter = function()
			if character.Parent and humanoid.Health > 0 then
				return character, humanoid, root
			end
			return nil, nil, nil
		end
		round._moveToStart = function(_, target)
			expect(target == character, "Fixture tried to move a live character")
			target:PivotTo(AuthoredWorld.SpawnCFrame(spawn))
		end
		round.hunt = Hunt.new(world, Balance, round.startedAt, owner.UserId)
		round.hunt:Step(0, os.clock(), root, true)
		round:_controls(true)
		return round
	end
	local function key(round)
		expect(Inventory.Add(round.inventory, "key"), "Fixture key allocation failed")
		round.hasKey = true
	end
	local function open(round)
		root.CFrame = front
		key(round)
		round.interactionAt = -math.huge
		local before = os.clock()
		round:_openGate(owner)
		expect(round.gateOpen and round.evacuationActive, "Valid server gate transaction failed")
		expect(
			round.evacuationDeadline >= before + 120
				and round.evacuationDeadline <= os.clock() + 120,
			"Gate did not establish the real120sec deadline"
		)
		expect(
			not round.hasKey and not table.find(round.inventory.slots, "key"),
			"Key was not consumed"
		)
		expect(
			not gate.CanCollide
				and not gate.CanQuery
				and gate.Transparency == 1
				and not prompt.Enabled
		)
		expect(runtime:GetAttribute("GateOpen") == true)
		local hunts = round:_hunts()
		expect(#hunts == 3 and #round.reinforcements == 2, "Expected exactly three hunters")
		for index, hunt in hunts do
			expect(hunt.model.Name == (if index == 1 then "Monster" else "Monster" .. index))
			expect(
				hunt.model:GetAttribute("MonsterIndex") == index
					and #hunt.visuals == 9
					and #hunt.model:GetChildren() == 10
					and hunt.detectRadius == 32
			)
			expect(
				hunt.model:GetAttribute("CornMonsterOwned") == true
					and hunt.model:GetAttribute("corn_project_id") == "children_of_corn"
					and hunt.model:GetAttribute("MonsterRigVersion") == 1
			)
			if index > 1 then
				expect(
					hunt.state == "patrol" and hunt.firstChaseUsed and not hunt.firstChaseUntil,
					"Reinforcement repeated awakening/first special chase"
				)
				for _, visual in hunt.visuals do
					expect(visual.Transparency == 0)
				end
			end
		end
		return hunts, round.evacuationDeadline
	end
	local function cleared(round)
		expect(
			not round.evacuationActive
				and round.evacuationDeadline == nil
				and round.hunt == nil
				and #round.reinforcements == 0
				and round.audio == nil,
			"Terminal/menu leaked finale state"
		)
		for index = 1, 3 do
			expect(
				not runtime:FindFirstChild(if index == 1 then "Monster" else "Monster" .. index),
				"Hunter leaked"
			)
		end
	end
	local function capture(round, index)
		local hunts, now = round:_hunts(), os.clock()
		root.CFrame = front
		round.protectedUntil, round.huntAt = 0, now
		for candidate, hunt in hunts do
			hunt.model:PivotTo(
				CFrame.new(
					root.Position
						+ Vector3.new(if candidate == index then 2 else 100 + candidate * 10, 0, 0)
				)
			)
			hunt:_state("chase", now - 2.1)
			hunt.chaseStartedAt = now - 2.1
			hunt.firstChaseUntil = nil
		end
		round:_poll(now)
		expect(
			round.phase == "caught" and round.catches == 1,
			"Actual Hunt.Step did not commit exactly one catch"
		)
		expect(round.captureFrame == hunts[index].root.CFrame, "Capture frame used another NPC")
		for _, hunt in hunts do
			expect(hunt.state == "capturing")
		end
		expect(humanoid.WalkSpeed == 0 and round.captureUntil > now)
		return hunts
	end

	local round = newRound("medium")
	local initialEpoch = round.epoch
	request(round, {}, "abort")
	request(round, owner, { action = "escaped", reward = 999, duration = 999 })
	for _, action in
		{ "escaped", "escape", "reward", "openGate", "evacuation", "revive", "retry", "start" }
	do
		request(round, owner, action, "hard")
	end
	expect(
		round.phase == "active"
			and round.epoch == initialEpoch
			and round.reward == 0
			and round.diamonds == 0
			and not round.evacuationActive
			and round.hunt ~= nil,
		"Client request forged finale/award/phase"
	)
	round.requestTokens, round.requestAt = 0, os.clock()
	round:_request(owner, "abort")
	expect(round.phase == "active", "Token bucket did not reject request")
	round.interactionAt = -math.huge
	round:_openGate({})
	expect(not round.gateOpen)
	expect(Inventory.Add(round.inventory, "key"))
	round.interactionAt = -math.huge
	round:_openGate(owner)
	expect(
		not round.gateOpen and not round.evacuationActive,
		"Inventory alone bypassed authoritative hasKey"
	)
	Inventory.Remove(round.inventory, "key")
	key(round)
	for _, position in { Vector3.new(0, y + 4, 190), Vector3.new(0, y + 4, 202) } do
		root.Position, round.interactionAt = position, -math.huge
		round:_openGate(owner)
		expect(
			not round.gateOpen and not round.evacuationActive,
			"Far/behind gate request accepted"
		)
	end
	root.CFrame = front
	local wall =
		part("InteractionWall", Vector3.new(6, 6, 0.5), Vector3.new(0, y + 4, 197), scratch, true)
	round.interactionAt = -math.huge
	round:_openGate(owner)
	expect(not round.gateOpen, "Gate LOS wall was ignored")
	wall:Destroy()
	prompt.Enabled, round.interactionAt = false, -math.huge
	round:_openGate(owner)
	expect(not round.gateOpen, "Disabled prompt opened gate")
	prompt.Enabled = true
	Inventory.Remove(round.inventory, "key")
	round.hasKey = false
	local hunts, deadline = open(round)
	expect(not hunts[1].firstChaseUsed, "Opening gate consumed primary first detection")
	round.interactionAt = -math.huge
	round:_openGate(owner)
	round:_startEvacuation(os.clock() + 10, root)
	expect(
		round.evacuationDeadline == deadline
			and #round:_hunts() == 3
			and round.reinforcements[1] == hunts[2]
			and round.reinforcements[2] == hunts[3],
		"Repeated gate extended/spawned finale"
	)
	checks.gate_actual_key_distance_front_los_prompt_owner_once120_three_rigs = true
	checks.client_request_owner_type_phase_unknown_action_and_token_guards = true
	for _, hunt in hunts do
		hunt.model:PivotTo(CFrame.new(root.Position + Vector3.new(31, 0, 0)))
		hunt:Step(0, os.clock(), root, false)
		expect(hunt.state == "chase", "Actual LOS detection did not extend16to32")
		hunt:ResetHome()
		hunt.model:PivotTo(CFrame.new(root.Position + Vector3.new(33, 0, 0)))
		hunt:Step(0, os.clock(), root, false)
		expect(hunt.state == "patrol", "Detection extended beyond32")
		hunt:ResetHome()
	end
	expect(Balance.monster_lose_radius == 42 and Balance.monster_lose_delay_sec == 1.25)
	checks.all_three_actual_los_detection31_yes33_no_loss42_unchanged = true
	capture(round, 2)
	local snapshotBefore = snapshots[#snapshots].evacuation.remaining
	request(round, owner, "revive")
	request(round, owner, "menu")
	expect(
		round.phase == "caught" and round.captureUntil > 0,
		"Capture windup choice accepted early"
	)
	task.wait(1.08)
	round:_poll(os.clock())
	expect(
		round.phase == "caught" and round.captureUntil == 0 and round.evacuationDeadline == deadline,
		"First catch did not hold with original deadline"
	)
	expect(
		snapshots[#snapshots].evacuation.remaining < snapshotBefore - 1,
		"Evacuation countdown paused during capture/choice hold"
	)
	request(round, {}, "revive")
	expect(round.phase == "caught", "Foreign owner revived")
	request(round, owner, "revive")
	expect(
		round.phase == "active"
			and round.evacuationDeadline == deadline
			and round.evacuationActive
			and round.protectedUntil > os.clock(),
		"Revive reset/paused finale"
	)
	for _, hunt in hunts do
		expect(
			hunt.state == "patrol" and (hunt.root.Position - hunt.home).Magnitude < 0.001,
			"Revive failed ResetHome for all three"
		)
	end
	checks.actual_captor2_frame_one_capture_hold_real1sec_and_revive_all_deadline_continues = true
	root.Position = exit.Position
	hunts[2].model:PivotTo(CFrame.new(root.Position + Vector3.new(2, 0, 0)))
	hunts[2]:_state("chase", os.clock() - 2.1)
	hunts[2].chaseStartedAt = os.clock() - 2.1
	round.evacuationDeadline = os.clock() - 0.01
	local captures = round.catches
	round:_poll(os.clock())
	expect(
		round.phase == "caught_out"
			and round.notice == "corn_evacuation_expired"
			and round.catches == captures
			and round.reward == 0
			and round.diamonds == 0,
		"Deadline did not beat exit/capture and refuse reward"
	)
	cleared(round)
	checks.active_timeout_precedes_physical_exit_and_no_reward_cleanup = true

	for mode, expected in { easy = 5, medium = 10, hard = 20 } do
		local win = newRound(mode)
		root.Position = exit.Position
		win.protectedUntil = math.huge
		win:_poll(os.clock())
		expect(
			win.phase == "active" and win.reward == 0 and win.diamonds == 0,
			"Closed exit awarded victory"
		)
		open(win)
		request(win, owner, "escaped", expected)
		expect(win.phase == "active" and win.reward == 0, "Client declared victory")
		root.Position = exit.Position
		win:_poll(os.clock())
		expect(
			win.phase == "escaped" and win.reward == expected and win.diamonds == expected,
			"Wrong per-mode escape reward"
		)
		win:_poll(os.clock())
		win:_finish("escaped", "duplicate")
		expect(win.diamonds == expected, "Escape reward duplicated")
		cleared(win)
		request(win, owner, "retry", "unknown")
		expect(
			win.phase == "escaped" and win.evacuationDeadline == nil,
			"Malformed retry started round"
		)
		request(win, owner, "menu")
		expect(win.phase == "ready" and win.diamonds == expected and not win.gateOpen)
		cleared(win)
		checks["physical_exit_reward_" .. mode .. "_" .. expected .. "_once_menu_cleanup"] = true
	end
	local held = newRound("hard")
	open(held)
	capture(held, 3)
	task.wait(1.08)
	held:_poll(os.clock())
	expect(held.phase == "caught" and held.captureUntil == 0)
	held.evacuationDeadline = os.clock() - 0.01
	request(held, owner, "revive")
	expect(
		held.phase == "caught_out" and held.notice == "corn_evacuation_expired" and held.reward == 0,
		"Held revive bypassed expired deadline"
	)
	cleared(held)
	checks.captor3_hold_timeout_on_revive_no_reward = true
	local film = newRound("easy")
	open(film)
	capture(film, 2)
	film.evacuationDeadline = os.clock() - 0.01
	film:_poll(os.clock())
	expect(
		film.phase == "caught_out" and film.captureUntil == 0 and film.reward == 0,
		"Timer paused during active capture film"
	)
	local terminalEpoch = film.epoch
	task.wait(1.08)
	expect(
		film.phase == "caught_out" and film.epoch == terminalEpoch,
		"Stale capture callback revived timed-out round"
	)
	cleared(film)
	checks.capture_film_timeout_and_delayed_callback_epoch_cleanup = true
	local leave = newRound("medium")
	open(leave)
	leave:_removePlayer(owner)
	expect(leave.player == nil and leave.phase == "ready" and not leave.gateOpen)
	cleared(leave)
	checks.owner_removal_clears_deadline_all_npcs_inventory_and_gate = true
	expect(os.clock() - began < 25, "Fixture exceeded its bounded execution budget")
end, debug.traceback)

-- Cleanup must also run for a failed assertion and invalidate pending capture tasks.
for _, round in rounds do
	pcall(function()
		round.epoch += 1
		round.phase = "aborted"
		round:_stopHunt()
		round:_clearInventory()
		round:_clearKey()
		for _, connection in round.connections do
			connection:Disconnect()
		end
	end)
end
if scratch then
	scratch:Destroy()
end
if not ok then
	error(problem, 0)
end
return {
	status = "PASS",
	checks = checks,
	snapshot_count = #snapshots,
	elapsed_sec = os.clock() - began,
	method = "actual engine Parts/Humanoid/LOS + required production SoloRound/AuthoredWorld/MonsterHunt; isolated character/network boundary; explicit deadline fast-forward; no native input/audio/FPS/endurance claim",
	cleanup = "owned scratch destroyed; pending callbacks invalidated; live character/Lighting untouched",
}
