-- Verified Children_of_corn Studio Play / SERVER only. No native-input acceptance.
-- Actual SoloRound/AuthoredWorld/MonsterHunt methods, real engine geometry/clocks.
-- Fixture boundaries: fake NetworkService sink, an owned character lookup and
-- owned-character spawn movement. No live Player.Character/Root/Lighting writes.
-- Invalid start/retry paths use the real _request/_startRound without overrides.
-- The valid round is staged active: native Start is a separate acceptance test.
-- No endurance/native-input/audio/GPU claim is made by this isolated fixture.
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
local LightingModes = require(Shared.LightingModes)
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local scratch, rounds = nil, {}
local checks, snapshots = {}, {}
local began = os.clock()
local function expect(value, message)
	return assert(value, message or "Night-round engine fixture assertion failed")
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
	scratch.Name = "NightRoundAcceptance_" .. HttpService:GenerateGUID(false)
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
	local function properties()
		local result = {}
		for _, item in scratch:GetDescendants() do
			local values = {
				parent = item.Parent,
				name = item.Name,
				class = item.ClassName,
				attrs = item:GetAttributes(),
				tags = item:GetTags(),
			}
			if item:IsA("BasePart") then
				values.frame, values.size = item.CFrame, item.Size
				values.transparency = item.Transparency
				values.collide, values.query = item.CanCollide, item.CanQuery
			elseif item:IsA("ProximityPrompt") then
				values.enabled = item.Enabled
			elseif item:IsA("Humanoid") then
				values.health, values.walkSpeed = item.Health, item.WalkSpeed
				values.jumpPower, values.jumpHeight, values.autoRotate =
					item.JumpPower, item.JumpHeight, item.AutoRotate
			end
			result[item] = values
		end
		return result
	end
	local function equal(a, b)
		if type(a) ~= "table" or type(b) ~= "table" then
			return a == b
		end
		for entryKey, value in a do
			if not equal(value, b[entryKey]) then
				return false
			end
		end
		for entryKey, value in b do
			if not equal(a[entryKey], value) then
				return false
			end
		end
		return true
	end
	local function guardedState(round)
		return {
			phase = round.phase,
			epoch = round.epoch,
			mode = round.lightingMode,
			startedAt = round.startedAt,
			elapsed = round.elapsed,
			reward = round.reward,
			diamonds = round.diamonds,
			hasKey = round.hasKey,
			gateOpen = round.gateOpen,
			deadline = round.evacuationDeadline,
			evacuation = round.evacuationActive,
			hunt = round.hunt,
			companions = table.clone(round.reinforcements),
			inventory = Inventory.Snapshot(round.inventory, os.clock()),
			character = round.roundCharacter,
			controlledCharacter = round.controlledCharacter,
			selectedSpawn = round.selectedSpawn,
			lightingState = round.lightingState,
			catches = round.catches,
			captureUntil = round.captureUntil,
			notice = round.notice,
			world = properties(),
			lighting = LightingModes.Capture(Lighting),
			snapshots = #snapshots,
		}
	end
	-- Contract checks precede all round staging and cannot pass an old installed
	-- three-mode provider accidentally. No valid _startRound runs in this fixture.
	expect(
		LightingModes.Default == "hard"
			and #LightingModes.Order == 1
			and LightingModes.Order[1] == "hard"
	)
	expect(
		LightingModes.IsValid("hard")
			and not LightingModes.IsValid("easy")
			and not LightingModes.IsValid("medium")
			and not LightingModes.IsValid(nil)
			and not LightingModes.IsValid("unknown")
	)
	expect(LightingModes.Profiles.easy == nil and LightingModes.Profiles.medium == nil)
	expect(
		LightingModes.Profiles.hard.ClockTime == 20.5
			and LightingModes.Profiles.hard.Torches == true
	)
	expect(
		Balance.escape_reward_diamonds == 20
			and Balance.escape_rewards.hard == 20
			and Balance.escape_rewards.easy == nil
			and Balance.escape_rewards.medium == nil
	)
	local invalidModes = {
		{ name = "easy", value = "easy" },
		{ name = "medium", value = "medium" },
		{ name = "nil" },
		{ name = "unknown", value = "unknown" },
	}
	local guards = Solo.new(context)
	table.insert(rounds, guards)
	guards.world, guards.player, guards.roundCharacter = world, owner, character
	guards.selectedSpawn = spawn
	guards._livingCharacter = function()
		return character, humanoid, root
	end
	guards._moveToStart = function(_, target)
		expect(target == character, "Fixture tried to move a live character")
		target:PivotTo(AuthoredWorld.SpawnCFrame(spawn))
	end
	expect(guards.phase == "ready" and guards.lightingMode == "hard")
	expect(rawget(guards, "_request") == nil and rawget(guards, "_startRound") == nil)
	local invalidCount = 0
	for _, mode in invalidModes do
		local previous = guardedState(guards)
		request(guards, owner, "start", mode.value)
		expect(
			equal(previous, guardedState(guards)),
			"Invalid ready/start changed round/world/Lighting: " .. mode.name
		)
		guards:_startRound(mode.value)
		expect(
			equal(previous, guardedState(guards)),
			"Direct invalid _startRound changed state: " .. mode.name
		)
		invalidCount += 2
	end
	for _, phase in { "escaped", "aborted", "caught_out" } do
		guards.phase = phase
		for _, mode in invalidModes do
			local previous = guardedState(guards)
			request(guards, owner, "retry", mode.value)
			expect(
				equal(previous, guardedState(guards)),
				"Invalid terminal/retry changed round/world/Lighting: " .. phase .. "/" .. mode.name
			)
			invalidCount += 1
		end
	end
	checks.hard_only_provider_default_order_profile_reward_contract = true
	checks.actual_invalid_start_retry_no_world_lighting_or_round_mutations = invalidCount
	local win = newRound("hard")
	root.Position, win.protectedUntil = exit.Position, math.huge
	win:_poll(os.clock())
	expect(
		win.phase == "active" and win.reward == 0 and win.diamonds == 0,
		"Closed exit awarded victory"
	)
	local hunts, deadline = open(win)
	expect(not hunts[1].firstChaseUsed and #hunts == 3)
	win.interactionAt = -math.huge
	win:_openGate(owner)
	expect(
		win.evacuationDeadline == deadline and #win:_hunts() == 3,
		"Repeated gate reset the deadline/companions"
	)
	for _, hunt in hunts do
		hunt.model:PivotTo(CFrame.new(root.Position + Vector3.new(31, 0, 0)))
		hunt:Step(0, os.clock(), root, false)
		expect(hunt.state == "chase", "Actual32stud detection missed31")
		hunt:ResetHome()
		hunt.model:PivotTo(CFrame.new(root.Position + Vector3.new(33, 0, 0)))
		hunt:Step(0, os.clock(), root, false)
		expect(hunt.state == "patrol", "Actual32stud detection accepted33")
		hunt:ResetHome()
	end
	checks.actual_key_gate120_once_three_owned_rigs_detection31_yes33_no = true
	request(win, owner, "escaped", 999)
	expect(
		win.phase == "active" and win.reward == 0 and win.diamonds == 0,
		"Client forged victory/reward"
	)
	root.Position = exit.Position
	win:_poll(os.clock())
	expect(
		win.phase == "escaped" and win.reward == 20 and win.diamonds == 20,
		"Hard physical exit did not award20"
	)
	win:_poll(os.clock())
	win:_finish("escaped", "duplicate")
	expect(win.reward == 20 and win.diamonds == 20, "Escape reward duplicated")
	cleared(win)
	request(win, owner, "menu")
	expect(
		win.phase == "ready"
			and win.lightingMode == "hard"
			and win.diamonds == 20
			and not win.gateOpen
	)
	cleared(win)
	expect(
		not runtime:GetAttribute("GateOpen")
			and gate.CanCollide
			and gate.CanQuery
			and gate.Transparency == world.ClosedTransparency
	)
	checks.actual_physical_exit_reward20_once_and_menu_cleanup = true
	expect(os.clock() - began < 15, "Night fixture exceeded bounded budget")
end, debug.traceback)

for _, round in rounds do
	pcall(function()
		round.epoch += 1
		round.phase = "aborted"
		round:_stopHunt()
		round:_clearInventory()
		round:_clearKey()
		-- Normally nil: restore only a regression's actual _startRound capture.
		round:_restoreLighting()
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
	method = "actual SoloRound _request/_startRound invalid guards + actual key/gate/Hunt32/physical exit methods; staged active hard round and isolated owned character/network boundary; no native-input/start/GPU/audio/endurance claim",
	cleanup = "owned scratch destroyed, hunter callbacks invalidated; live character untouched, normal passing path never applies Lighting",
}
