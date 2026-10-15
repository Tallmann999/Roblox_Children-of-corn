-- Temporary actual network acceptance. Diagnostic positions, not a blind round.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioTestService = game:GetService("StudioTestService")
local RunService = game:GetService("RunService")
assert(RunService:IsStudio())
local probe = Instance.new("RemoteEvent")
probe.Name = "CornMultiplayerTestProbe"
probe.Parent = ReplicatedStorage
local snapshots, acknowledgements = {}, {}
local report = { checks = {}, mode = "actual Studio clients; real remotes and engine prompt input; diagnostic positions", passed = false }
probe.OnServerEvent:Connect(function(player, kind, value)
	if kind == "snapshot" then
		snapshots[player] = value
	elseif kind == "ack" then
		acknowledgements[value.id] = value
	end
end)
local function waitFor(predicate, message, timeout)
	local deadline = os.clock() + (timeout or 20)
	repeat
		if predicate() then
			return
		end
		task.wait(0.1)
	until os.clock() >= deadline
	error("Timeout: " .. message)
end
local function check(value, name)
	assert(value, name)
	table.insert(report.checks, name)
	print("[MultiplayerTest] PASS " .. name)
end
local serial = 0
local function command(player, kind, argument)
	serial += 1
	local id = serial
	probe:FireClient(player, id, kind, argument)
	waitFor(function() return acknowledgements[id] ~= nil end, "client command " .. kind)
	assert(acknowledgements[id].ok, acknowledgements[id].failure)
	task.wait(0.65)
end
local function action(player, value)
	command(player, "action", { action = value, mode = if value == "start" or value == "retry" then "hard" else nil })
end
local function root(player)
	return assert(player.Character and player.Character:FindFirstChild("HumanoidRootPart"))
end
local function move(player, position)
	player.Character:PivotTo(CFrame.new(position))
	root(player).AssemblyLinearVelocity = Vector3.zero
	task.wait(0.35)
end
local function prompt(player, target)
	move(player, target.Parent.Position + Vector3.new(0, 2.4, -1.5))
	command(player, "prompt", target)
end
local function find(name)
	return workspace.CornMap:FindFirstChild(name, true)
end
local function summary(player)
	local snapshot = snapshots[player]
	return snapshot and { user_id = player.UserId, phase = snapshot.phase, team = snapshot.team, diamonds = snapshot.diamonds, has_key = snapshot.has_key, catches_remaining = snapshot.catches_remaining }
end
local ok, failure = xpcall(function()
	waitFor(function() return #Players:GetPlayers() == 2 end, "two actual Players", 120)
	local players = Players:GetPlayers()
	table.sort(players, function(a, b) return a.UserId < b.UserId end)
	local a, b = players[1], players[2]
	waitFor(function() return snapshots[a] and snapshots[b] and snapshots[a].hud and snapshots[b].hud end, "both HUDs and snapshots", 120)
	check(a.UserId ~= b.UserId and snapshots[a].team.count == 2 and snapshots[b].team.count == 2, "two recipients receive team snapshots")
	action(a, "start")
	waitFor(function() return snapshots[a].team.ready end, "first ready")
	check(snapshots[a].phase == "ready" and snapshots[b].phase == "ready", "one ready cannot start teammate")
	action(b, "start")
	waitFor(function() return snapshots[a].phase == "active" and snapshots[b].phase == "active" end, "common round active", 40)
	local roundId = snapshots[a].team.round_id
	check(roundId == snapshots[b].team.round_id and (root(a).Position - root(b).Position).Magnitude > 200, "one round with distinct corner starts")
	local key = assert(find("CornKeyPrompt"))
	prompt(a, key)
	waitFor(function() return snapshots[a].has_key and snapshots[b].team.key_state == "carried" end, "shared key picked up")
	check(not snapshots[b].has_key and not find("CornKeyPrompt"), "one carrier and no duplicate world key")
	local gate = assert(find("CornGatePrompt"))
	-- Gate-front side is determined from its existing prompt anchor.
	local gatePart = assert(gate.Parent.Parent:FindFirstChild("Door"))
	local localAnchor = gatePart.CFrame:PointToObjectSpace(gate.Parent.Position)
	move(a, gate.Parent.Position + gatePart.CFrame.LookVector * (if localAnchor.Z < 0 then 1.5 else -1.5) + Vector3.new(0, 2, 0))
	command(a, "prompt", gate)
	waitFor(function() return snapshots[a].gate_open and snapshots[b].gate_open end, "shared gate open")
	check(snapshots[a].evacuation.active and snapshots[b].evacuation.active and find("Monster2") and find("Monster3"), "one shared deadline and three hunters")
	local exit = assert(find("ExitZone"))
	move(a, Vector3.new(exit.Position.X, root(a).Position.Y, exit.Position.Z))
	waitFor(function() return snapshots[a].phase == "escaped" end, "A escape")
	check(snapshots[a].diamonds == 20 and snapshots[a].reward == 20 and snapshots[b].phase == "active" and find("Monster"), "A rewarded once while B and hunters continue")
	local timeBefore = snapshots[b].evacuation.remaining
	action(a, "retry")
	check(snapshots[a].phase == "escaped" and snapshots[a].diamonds == 20 and snapshots[b].team.round_id == roundId and snapshots[b].evacuation.remaining <= timeBefore, "personal retry cannot reset active team or duplicate reward")
	move(b, Vector3.new(exit.Position.X + 2, root(b).Position.Y, exit.Position.Z))
	waitFor(function() return snapshots[b].phase == "escaped" and snapshots[b].team.state == "finished" end, "B escape finishes team")
	check(snapshots[b].diamonds == 20 and not find("Monster") and not find("Monster2"), "last result cleans shared hunters")
	action(a, "retry")
	action(b, "retry")
	waitFor(function() return snapshots[a].phase == "active" and snapshots[a].team.round_id == roundId + 1 and snapshots[b].phase == "active" end, "second common round")
	prompt(a, assert(find("CornKeyPrompt")))
	waitFor(function() return snapshots[a].has_key end, "second key pickup")
	local monster = assert(find("Monster"))
	waitFor(function() return monster:GetAttribute("HuntState") ~= "dormant" end, "real hunt awakens", 30)
	local at = root(a).Position
	monster:PivotTo(CFrame.new(at + Vector3.new(0, 0, 2)))
	waitFor(function() return snapshots[a].phase == "caught" end, "real first capture", 10)
	check(snapshots[b].phase == "active" and root(b).Parent.Humanoid.WalkSpeed == 12 and find("CornKeyPrompt"), "A capture drops key while B remains playable")
	waitFor(function() return snapshots[a].capture_remaining == 0 end, "capture presentation ends")
	local npcAt = monster.PrimaryPart.Position
	action(a, "revive")
	waitFor(function() return snapshots[a].phase == "active" end, "personal revive")
	check(snapshots[a].catches_remaining == 1 and snapshots[b].catches_remaining == 2 and (monster.PrimaryPart.Position - npcAt).Magnitude < 30, "revive leaves teammate attempts and NPC location intact")
	-- A late actual client must receive a deliberate waiting state.
	StudioTestService:AddPlayers(1)
	waitFor(function() return #Players:GetPlayers() == 3 end, "late client joins", 60)
	local c
	for _, player in Players:GetPlayers() do if player ~= a and player ~= b then c = player end end
	waitFor(function() return snapshots[c] and snapshots[c].hud end, "late client snapshot/HUD", 120)
	check(snapshots[c].phase == "ready" and not snapshots[c].team.can_start and snapshots[c].team.remaining == 2, "late client waits for next round")
	action(c, "start")
	check(snapshots[c].phase == "ready" and not snapshots[c].team.ready, "late join cannot inject itself into active round")
	prompt(b, assert(find("CornKeyPrompt")))
	waitFor(function() return snapshots[b].has_key end, "B takes recovered key")
	action(b, "abort")
	waitFor(function() return snapshots[b].phase == "aborted" and find("CornKeyPrompt") end, "carrier abort drops key")
	check(snapshots[a].phase == "active" and snapshots[c].phase == "ready", "carrier abort preserves active teammate and waiting client")
	prompt(a, assert(find("CornKeyPrompt")))
	waitFor(function() return snapshots[a].has_key end, "A recovers carrier-abort key")
	root(a).Parent.Humanoid.Health = 0
	waitFor(function() return snapshots[a].phase == "aborted" and snapshots[a].team.state == "finished" end, "death ends final participant")
	check(snapshots[a].diamonds == 20 and snapshots[b].diamonds == 20 and not find("CornKeyPrompt"), "death gives no duplicate reward and last result cleans key")
	report.recipients = { summary(a), summary(b), summary(c) }
	report.passed = true
end, debug.traceback)
if not ok then report.error = failure end
report.duration_sec = os.clock()
print("[MultiplayerTest] " .. game:GetService("HttpService"):JSONEncode(report))
task.wait(1)
StudioTestService:EndTest(report)
