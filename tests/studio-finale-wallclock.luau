-- Verified Children_of_corn Studio Play SERVER. Starts an async <=125sec fixture.
-- Poll the returned ReplicatedStorage StringValue until done=true; retain JSON,
-- then remove that owned report. This test waits REAL120sec, without changing
-- Balance, os.clock, the server deadline, or any gate/poll/capture implementation.
-- Only fixture boundaries: NetworkService sink and owned-character lookup/spawn.
local RunService = game:GetService("RunService")
assert(
	RunService:IsStudio() and RunService:IsRunning() and RunService:IsServer(),
	"Studio Play Server required"
)
local actualMap = assert(workspace:FindFirstChild("CornMap"), "Children_of_corn map missing")
assert(actualMap:GetAttribute("corn_project_id") == "children_of_corn", "Wrong target")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local owner = assert(Players:GetPlayers()[1], "Real Play owner required")
local Modules = game.ServerScriptService.GameServer.Game
local Solo = require(Modules.SoloRound)
local Hunt = require(Modules.MonsterHunt)
local AuthoredWorld = require(Modules.AuthoredWorld)
local Shared = game.ReplicatedStorage.GameShared.Game
local Inventory = require(Shared.Inventory)
local Balance = require(Shared.Balance)
assert(Balance.evacuation_duration_sec == 120, "Actual120sec configuration required")
local id = HttpService:GenerateGUID(false)
local reportValue = Instance.new("StringValue")
reportValue.Name = "CornFinaleWallclockReport_" .. id
reportValue:SetAttribute("corn_test_owned", true)
reportValue:SetAttribute("corn_project_id", "children_of_corn")
reportValue:SetAttribute("FixtureId", id)
reportValue.Parent = ReplicatedStorage
local began, finished = os.clock(), false
local scratch, round, lastSnapshot, workerThread, watchdogThread
local report = {
	fixture_version = 1,
	fixture_id = id,
	done = false,
	passed = false,
	status = "running",
	stage = "setup",
	snapshot_count = 0,
	checks = {},
	checkpoints = {},
	method = "Actual production SoloRound/AuthoredWorld/MonsterHunt, real engine Parts/Humanoid and wall clock. Real key-gate transaction spawns3NPC then actual first capture byNPC2 is held untouched until120sec expiration. No fast-forward, live character/Lighting/native input/audio/FPS claims.",
}
local function publish()
	report.elapsed_sec = os.clock() - began
	reportValue.Value = HttpService:JSONEncode(report)
end
local function expect(value, reason)
	return assert(value, reason or "Finale wallclock assertion failed")
end
local function part(name, size, position, parent, collidable)
	local item = Instance.new("Part")
	item.Name, item.Size, item.Position = name, size, position
	item.Anchored, item.CanCollide, item.CanQuery, item.CanTouch =
		true, collidable == true, collidable == true, false
	item.Parent = parent
	return item
end
local function cleanup()
	local failures = {}
	if round then
		local cleaned, failure = pcall(function()
			round.epoch += 1
			round.phase = "aborted"
			round:_stopHunt()
			round:_clearInventory()
			round:_clearKey()
			for _, connection in round.connections do
				connection:Disconnect()
			end
		end)
		if not cleaned then
			table.insert(failures, tostring(failure))
		end
	end
	if scratch then
		local cleaned, failure = pcall(function()
			scratch:Destroy()
		end)
		if not cleaned then
			table.insert(failures, tostring(failure))
		end
	end
	report.cleanup =
		{ scratch_removed = scratch == nil or scratch.Parent == nil, failures = failures }
	return #failures == 0
end
local function finish(passed, failure)
	if finished then
		return
	end
	finished = true
	local current = coroutine.running()
	for _, thread in { workerThread, watchdogThread } do
		if thread and thread ~= current and coroutine.status(thread) ~= "dead" then
			pcall(task.cancel, thread)
		end
	end
	report.done = true
	report.passed = cleanup() and passed
	report.status = if report.passed then "PASS" else "FAIL"
	report.stage = "complete"
	if failure then
		report.error = tostring(failure)
	end
	publish()
end
publish()
watchdogThread = task.delay(125, function()
	finish(false, "125sec watchdog expired before real wallclock acceptance")
end)
workerThread = task.spawn(function()
	local ok, failure = xpcall(function()
		scratch = Instance.new("Model")
		scratch.Name = "FinaleWallclock_" .. HttpService:GenerateGUID(false)
		scratch:SetAttribute("corn_test_owned", true)
		scratch:SetAttribute("corn_project_id", "children_of_corn")
		scratch.Parent = workspace
		local y = actualMap.Ground.Position.Y + 700
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
				Vector3.new(
					(index - 1) % 5 * 80 - 160,
					y + 1,
					math.floor((index - 1) / 5) * 80 - 160
				),
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
		local gate =
			part("Door", Vector3.new(12, 12, 2), Vector3.new(0, y + 7, 200), gateModel, true)
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
		local root = part(
			"HumanoidRootPart",
			Vector3.new(2, 2, 1),
			Vector3.new(0, y + 4, 196),
			character,
			false
		)
		character.PrimaryPart = root
		local humanoid = Instance.new("Humanoid")
		humanoid.RequiresNeck, humanoid.Parent = false, character
		local event = {
			FireClient = function(_, target, snapshot)
				expect(target == owner, "Snapshot targeted a different player")
				expect(
					type(snapshot.evacuation) == "table" and snapshot.evacuation.duration == 120,
					"Missing authoritative evacuation snapshot"
				)
				expect(snapshot.evacuation.remaining >= 0 and snapshot.evacuation.remaining <= 120)
				lastSnapshot = snapshot
				report.snapshot_count += 1
			end,
		}
		local context = {
			Config = { CoreLoop = Balance },
			Services = {
				NetworkService = {
					GetEvent = function()
						return event
					end,
				},
			},
			Log = { Info = function() end, Warn = function() end },
		}

		round = Solo.new(context)
		round.world, round.player, round.roundCharacter = world, owner, character
		round.selectedSpawn, round.phase, round.lightingMode = spawn, "active", "medium"
		round.startedAt, round.huntAt = os.clock() - 30, os.clock()
		round.minimap:ResetHistory()
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
		world:SetInteractionEnabled(true, false)
		expect(Inventory.Add(round.inventory, "key"))
		round.hasKey = true
		round.interactionAt = -math.huge
		local before = os.clock()
		round:_openGate(owner)
		expect(
			round.gateOpen and round.evacuationActive and round.evacuationDeadline,
			"Real validated key-gate transaction did not start finale"
		)
		local deadline = round.evacuationDeadline
		local openedAt = deadline - 120
		expect(
			openedAt >= before and openedAt <= os.clock(),
			"Deadline does not use actual server clock+120"
		)
		expect(
			not round.hasKey and not table.find(round.inventory.slots, "key"),
			"Gate key not consumed"
		)
		local hunts = round:_hunts()
		expect(#hunts == 3 and #round.reinforcements == 2, "Actual gate failed3NPC construction")
		for index, hunt in hunts do
			expect(hunt.model:GetAttribute("MonsterIndex") == index and hunt.detectRadius == 32)
			expect(hunt.model.Parent == runtime)
		end
		report.checks.actual_gate_key_once120_and_three_npcs = true
		report.opened_at_clock, report.deadline_clock = openedAt, deadline
		hunts[2].model:PivotTo(CFrame.new(root.Position + Vector3.new(2, 0, 0)))
		round:_caught(root, hunts[2])
		expect(round.phase == "caught" and round.catches == 1 and round.captureUntil > os.clock())
		expect(
			round.captureFrame == hunts[2].root.CFrame,
			"Actual extraNPC captor frame not preserved"
		)
		for _, hunt in hunts do
			expect(hunt.state == "capturing")
		end
		report.checks.first_capture_by_extra_npc = true
		report.stage = "held_capture_until_real120sec"
		publish()
		local held, sixty, checkpoint = false, false, 1
		local checkpoints = { 1.05, 30, 60, 90, 119 }
		local previousRemaining = 120
		while round.phase == "caught" do
			local now = os.clock()
			expect(now - began < 124.5, "Wallclock loop exceeded bounded lifetime")
			expect(
				round.evacuationDeadline == deadline and round.evacuationActive,
				"Held capture changed or paused the server deadline"
			)
			round:_poll(now)
			if round.phase ~= "caught" then
				break
			end
			expect(now < deadline, "Expired held round did not terminate")
			if round.captureUntil == 0 then
				held = true
			end
			if checkpoint <= #checkpoints and now - openedAt >= checkpoints[checkpoint] then
				round:_send()
				expect(
					lastSnapshot
						and lastSnapshot.phase == "caught"
						and lastSnapshot.evacuation.active
				)
				local remaining = lastSnapshot.evacuation.remaining
				expect(
					remaining <= previousRemaining
						and math.abs(remaining - (deadline - os.clock())) < 0.2,
					"Snapshot countdown reset, froze or diverged from wall clock"
				)
				previousRemaining = remaining
				table.insert(report.checkpoints, {
					elapsed_from_gate = now - openedAt,
					phase = round.phase,
					remaining = remaining,
					capture_remaining = lastSnapshot.capture.remaining,
					npc_count = #round:_hunts(),
				})
				if checkpoints[checkpoint] == 60 then
					expect(
						held and round.captureUntil == 0 and remaining >= 57.5 and remaining <= 60.2,
						"At~60sec the held choice had zero/reset/frozen timer"
					)
					sixty = true
				end
				checkpoint += 1
				publish()
			end
			task.wait(0.1)
		end
		local expiredElapsed = os.clock() - openedAt
		expect(
			held and sixty and #report.checkpoints == #checkpoints,
			"Did not observe real first-capture hold/60sec/countdown checkpoints"
		)
		expect(
			expiredElapsed >= 119.8 and expiredElapsed <= 122.5,
			"Actual expiration outside119.8..122.5sec wallclock acceptance"
		)
		expect(
			round.phase == "caught_out"
				and round.notice == "corn_evacuation_expired"
				and round.reward == 0
				and round.diamonds == 0
				and round.catches == 1,
			"Held real120sec expiration did not lose once without reward"
		)
		expect(
			not round.evacuationActive
				and round.evacuationDeadline == nil
				and round.captureUntil == 0
		)
		expect(round.hunt == nil and #round.reinforcements == 0 and round.audio == nil)
		for _, hunt in hunts do
			expect(hunt.destroyed and hunt.model.Parent == nil, "Expired hunter survived")
		end
		expect(
			lastSnapshot.phase == "caught_out"
				and not lastSnapshot.evacuation.active
				and lastSnapshot.evacuation.remaining == 0
				and lastSnapshot.reward_diamonds == 0,
			"Terminal authoritative snapshot retained timer/reward"
		)
		report.checks.real_first_capture_callback_then_held_without_choices = true
		report.checks.real_sixty_second_countdown_no_reset_or_pause = true
		report.checks.real120sec_expiration_caught_out_no_reward = true
		report.checks.npcs_destroyed_and_deadline_cleared = true
		report.gate_to_expiration_sec = expiredElapsed
		report.terminal_phase, report.terminal_notice = round.phase, round.notice
		report.terminal_reward, report.final_catches = round.reward, round.catches
	end, debug.traceback)
	finish(ok, if ok then nil else failure)
end)
return {
	started = true,
	report_path = reportValue:GetFullName(),
	report_name = reportValue.Name,
	fixture_id = id,
	timeout_sec = 125,
	real_duration_sec = 120,
}
