-- Actual network acceptance: initial two clients, two late joins, four starts,
-- carrier LeaveTest and surviving-team recovery. Diagnostic positions/prompt API,
-- elevated temporarily anchored players during client loading; not a blind round.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local STS = game:GetService("StudioTestService")
local Run = game:GetService("RunService")
local Http = game:GetService("HttpService")
assert(Run:IsStudio() and Run:IsServer(), "Studio test Server required")
local map = assert(workspace:FindFirstChild("CornMap"), "CornMap missing")
assert(map:GetAttribute("corn_project_id") == "children_of_corn", "Wrong project")
assert(not RS:FindFirstChild("CornMultiplayerTestProbe"), "Duplicate test probe")
local began, stage = os.clock(), "startup"
local COMMAND_TIMEOUT_SEC = 60
local probe = Instance.new("RemoteEvent")
probe.Name = "CornMultiplayerTestProbe"
probe:SetAttribute("corn_test_owned", true)
probe:SetAttribute("corn_project_id", "children_of_corn")
probe.Parent = RS
local snapshots, acknowledgements, pending, staged, known, traces = {}, {}, {}, {}, {}, {}
local clientReadiness = {}
local report = {
	checks = {},
	commands = {},
	starts = {},
	departures = {},
	prompt_staging = {},
	passed = false,
	mode = "Actual Studio server and real clients/gameplay remotes/custom prompt input; normal 3D rendering; diagnostic actor positions and temporary elevated anchors during joins; no physical E/native UI/visual/blind-round/FPS claim",
	trace_limit_per_recipient = 72,
	command_timeout_sec = COMMAND_TIMEOUT_SEC,
	action_delivery_audit = { rows = {}, dropped = 0, limit = 100, bindings = {} },
}
local auditConnections, auditedRemotes, estimatedBuckets = {}, {}, {}
local function rawValue(value)
	local kind = typeof(value)
	if kind == "string" then
		return value:sub(1, 120)
	end
	if kind == "boolean" then
		return value
	end
	if kind == "number" and value == value and math.abs(value) < math.huge then
		return value
	end
	return tostring(value):sub(1, 120)
end
local function watchActionRemote(remote)
	if
		auditedRemotes[remote]
		or not remote:IsA("RemoteEvent")
		or remote.Name ~= "request_round_action"
	then
		return
	end
	local folder = remote.Parent
	if not folder or folder.Name ~= "GameRemotes" or folder.Parent ~= RS then
		return
	end
	auditedRemotes[remote] = true
	table.insert(
		report.action_delivery_audit.bindings,
		{ at = os.clock() - began, path = remote:GetFullName() }
	)
	table.insert(
		auditConnections,
		remote.OnServerEvent:Connect(function(player, ...)
			local now, values = os.clock(), table.pack(...)
			local actionValue, modeValue = values[1], values[2]
			local bucket = estimatedBuckets[player] or { tokens = 2, at = now }
			local before = math.min(2, bucket.tokens + math.max(0, now - bucket.at) * 2)
			local charged = type(actionValue) == "string" and before >= 1
			bucket.tokens, bucket.at = if charged then before - 1 else before, now
			estimatedBuckets[player] = bucket
			local row = {
				at = now - began,
				stage = stage,
				user_id = player.UserId,
				player_name = player.Name,
				argument_count = values.n,
				action_type = typeof(actionValue),
				action_value = rawValue(actionValue),
				mode_type = typeof(modeValue),
				mode_value = rawValue(modeValue),
				estimated_tokens_before = before,
				estimated_tokens_after = bucket.tokens,
				estimated_request_fits = charged,
			}
			if #report.action_delivery_audit.rows < 100 then
				table.insert(report.action_delivery_audit.rows, row)
			else
				report.action_delivery_audit.dropped += 1
			end
		end)
	)
end
-- Observe the actual RemoteEvent as soon as NetworkService publishes it.
-- This listener neither forwards requests nor reads/mutates production buckets.
table.insert(auditConnections, RS.DescendantAdded:Connect(watchActionRemote))
local initialRemotes = RS:FindFirstChild("GameRemotes")
if initialRemotes then
	for _, remote in initialRemotes:GetChildren() do
		watchActionRemote(remote)
	end
end
report.action_delivery_audit.rate_estimate_scope =
	"Approximate 2-token/cap2/refill2-per-second model from observed string requests only; not production bucket introspection or proof of server acceptance. Raw delivery times/types/values are direct OnServerEvent observations."
local function waitFor(predicate, message, timeout)
	local deadline = os.clock() + (timeout or 20)
	repeat
		if predicate() then
			return
		end
		task.wait(0.1)
	until os.clock() >= deadline
	error("Timeout [" .. stage .. "]: " .. message)
end
local function check(value, name)
	assert(value, name)
	table.insert(report.checks, { at = os.clock() - began, stage = stage, name = name })
	print("[MultiplayerTest] PASS " .. name)
end
local function register(player)
	known[player] = known[player]
		or { user_id = player.UserId, name = player.Name, joined_at = os.clock() - began }
	traces[player] = traces[player]
		or { rows = {}, dropped = 0, signature = "", last_at = -math.huge }
end
for _, player in Players:GetPlayers() do
	register(player)
end
local addedConnection = Players.PlayerAdded:Connect(register)
local removedConnection = Players.PlayerRemoving:Connect(function(player)
	register(player)
	known[player].removed_at = os.clock() - began
	table.insert(
		report.departures,
		{ at = os.clock() - began, user_id = player.UserId, stage = stage }
	)
end)
local probeConnection = probe.OnServerEvent:Connect(function(player, kind, value)
	if player.Parent ~= Players or not known[player] then
		return
	end
	if
		kind == "ready"
		and type(value) == "table"
		and value.command_handler_connected == true
		and value.rendering_mode == "normal"
	then
		clientReadiness[player] = {
			ready = true,
			at = os.clock() - began,
			command_handler_connected = true,
			rendering_mode = "normal",
		}
	elseif kind == "snapshot" and type(value) == "table" and value.user_id == player.UserId then
		snapshots[player] = value
		local team = value.team or {}
		local signature = table.concat({
			tostring(value.phase),
			tostring(team.round_id),
			tostring(team.state),
			tostring(team.ready),
			tostring(team.count),
			tostring(team.remaining),
			tostring(value.has_key),
			tostring(value.diamonds),
			tostring(value.reward),
			tostring(value.catches_remaining),
		}, ":")
		local log, at = traces[player], os.clock() - began
		if signature ~= log.signature or at - log.last_at >= 1 then
			local row = {
				at = at,
				stage = stage,
				phase = value.phase,
				round_id = team.round_id,
				team_state = team.state,
				count = team.count,
				remaining = team.remaining,
				ready = team.ready,
				has_key = value.has_key,
				diamonds = value.diamonds,
				reward = value.reward,
				catches = value.catches_remaining,
				evacuation = value.evacuation and value.evacuation.remaining,
				hud = value.hud,
			}
			if #log.rows < 72 then
				table.insert(log.rows, row)
			else
				log.rows[#log.rows] = row
				log.dropped += 1
			end
			log.signature, log.last_at = signature, at
		end
	elseif kind == "ack" and type(value) == "table" and pending[value.id] == player then
		acknowledgements[value.id] = value
	end
end)
local serial = 0
local function command(player, kind, argument)
	serial += 1
	local id = serial
	pending[id] = player
	probe:FireClient(player, id, kind, argument)
	waitFor(function()
		return acknowledgements[id] ~= nil or (kind == "leave" and player.Parent ~= Players)
	end, "client command " .. kind, COMMAND_TIMEOUT_SEC)
	local ack = acknowledgements[id]
		or {
			ok = kind == "leave" and player.Parent ~= Players,
			details = { disconnected_before_ack_arrival = true },
		}
	table.insert(report.commands, {
		at = os.clock() - began,
		stage = stage,
		user_id = player.UserId,
		kind = kind,
		action = type(argument) == "table" and argument.action or nil,
		ok = ack.ok,
		details = ack.details,
	})
	assert(ack.ok, tostring(ack.failure))
	pending[id] = nil
	if kind == "leave" then
		waitFor(function()
			return player.Parent ~= Players and known[player].removed_at ~= nil
		end, "actual client PlayerRemoving", 30)
	else
		task.wait(0.65)
	end
end
local function action(player, value)
	command(
		player,
		"action",
		{ action = value, mode = if value == "start" or value == "retry" then "hard" else nil }
	)
end
local function root(player)
	return assert(
		player.Character and player.Character:FindFirstChild("HumanoidRootPart"),
		"Character Root missing for " .. player.Name
	)
end
local function move(player, position)
	player.Character:PivotTo(CFrame.new(position))
	root(player).AssemblyLinearVelocity = Vector3.zero
	task.wait(0.35)
end
local function find(name)
	return map:FindFirstChild(name, true)
end
local function prompt(player, target)
	move(player, target.Parent.Position + Vector3.new(0, 2.4, -1.5))
	local from, to = root(player).Position, target.Parent.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	params.RespectCanCollide = true
	local hit = workspace:Raycast(from, to - from, params)
	table.insert(report.prompt_staging, {
		at = os.clock() - began,
		stage = stage,
		user_id = player.UserId,
		prompt = target.Name,
		distance = (to - from).Magnitude,
		hit = if hit then hit.Instance:GetFullName() else "",
		clear_line = not hit or hit.Instance == target.Parent,
	})
	local path, item = {}, target
	while item ~= game do
		table.insert(path, 1, item.Name)
		item = assert(item.Parent, "Detached prompt")
	end
	command(player, "prompt", { path = path })
end
local function park(player)
	local item = root(player)
	if staged[player] then
		return
	end
	staged[player] = { root = item, frame = item.CFrame, anchored = item.Anchored }
	local at = item.Position + Vector3.new(0, 12, 0)
	local bounds = assert(map:FindFirstChild("PlayBounds"))
	local relative = bounds.CFrame:PointToObjectSpace(at)
	assert(math.abs(relative.Y) < bounds.Size.Y / 2, "Diagnostic safe-height outside bounds")
	item.Anchored = true
	item.CFrame = CFrame.new(at) * item.CFrame.Rotation
	item.AssemblyLinearVelocity = Vector3.zero
end
local function unpark(player)
	local saved = staged[player]
	if not saved then
		return
	end
	if saved.root.Parent then
		saved.root.CFrame = saved.frame
		if saved.root.Anchored == true then
			saved.root.Anchored = saved.anchored
		end
		saved.root.AssemblyLinearVelocity = Vector3.zero
	end
	staged[player] = nil
end
local function recordStarts(players, name)
	local rows = {}
	for index, player in players do
		local at = root(player).Position
		for other = 1, index - 1 do
			check(
				(at - root(players[other]).Position).Magnitude > 200,
				name .. " distinct corner pair " .. other .. "/" .. index
			)
		end
		table.insert(rows, { user_id = player.UserId, x = at.X, y = at.Y, z = at.Z })
	end
	table.insert(report.starts, { stage = name, players = rows })
end
local function openGate(player)
	local gate = assert(find("CornGatePrompt"), "Gate prompt missing")
	local door = assert(gate.Parent.Parent:FindFirstChild("Door"))
	local anchor = door.CFrame:PointToObjectSpace(gate.Parent.Position)
	move(
		player,
		gate.Parent.Position
			+ door.CFrame.LookVector * (if anchor.Z < 0 then 1.5 else -1.5)
			+ Vector3.new(0, 2, 0)
	)
	local path, item = {}, gate
	while item ~= game do
		table.insert(path, 1, item.Name)
		item = assert(item.Parent, "Detached gate")
	end
	command(player, "prompt", { path = path })
end
local ok, failure = xpcall(function()
	waitFor(function()
		return #Players:GetPlayers() == 2
	end, "two actual Players", 120)
	local players = Players:GetPlayers()
	table.sort(players, function(a, b)
		return a.UserId < b.UserId
	end)
	local a, b = players[1], players[2]
	waitFor(function()
		return clientReadiness[a]
			and clientReadiness[b]
			and clientReadiness[a].ready
			and clientReadiness[b].ready
			and snapshots[a]
			and snapshots[b]
			and snapshots[a].hud
			and snapshots[b].hud
			and snapshots[a].team.count == 2
			and snapshots[b].team.count == 2
	end, "both HUDs observe both connected players", 120)
	check(
		a.UserId ~= b.UserId and snapshots[a].team.count == 2 and snapshots[b].team.count == 2,
		"two real recipients receive personal team snapshots"
	)
	stage = "initial_startup_settle"
	local settlingAt = os.clock()
	report.startup_settling = { requested_seconds = 1.2, began_at = settlingAt - began }
	task.wait(1.2)
	report.startup_settling.actual_seconds = os.clock() - settlingAt
	report.startup_settling.ended_at = os.clock() - began
	stage = "round1_ready"
	action(a, "start")
	waitFor(function()
		return snapshots[a].team.ready
	end, "first ready")
	check(
		snapshots[a].phase == "ready" and snapshots[b].phase == "ready",
		"one ready cannot start teammate"
	)
	action(b, "start")
	waitFor(function()
		return snapshots[a].phase == "active" and snapshots[b].phase == "active"
	end, "common round active", 40)
	local roundId = snapshots[a].team.round_id
	check(roundId == snapshots[b].team.round_id, "shared first round ID")
	recordStarts({ a, b }, "two-player starts")
	stage = "round1_key_gate_exit"
	prompt(a, assert(find("CornKeyPrompt")))
	waitFor(function()
		return snapshots[a].has_key and snapshots[b].team.key_state == "carried"
	end, "shared key pickup")
	check(
		not snapshots[b].has_key and not find("CornKeyPrompt"),
		"one carrier and no duplicated key"
	)
	openGate(a)
	waitFor(function()
		return snapshots[a].gate_open and snapshots[b].gate_open
	end, "shared gate")
	check(
		snapshots[a].evacuation.active
			and snapshots[b].evacuation.active
			and find("Monster2")
			and find("Monster3"),
		"shared deadline and three hunters"
	)
	local exit = assert(find("ExitZone"))
	move(a, Vector3.new(exit.Position.X, root(a).Position.Y, exit.Position.Z))
	waitFor(function()
		return snapshots[a].phase == "escaped"
	end, "A escape")
	check(
		snapshots[a].diamonds == 20
			and snapshots[a].reward == 20
			and snapshots[b].phase == "active"
			and find("Monster"),
		"A rewarded once while B continues"
	)
	local remaining = snapshots[b].evacuation.remaining
	action(a, "retry")
	check(
		snapshots[a].phase == "escaped"
			and snapshots[a].diamonds == 20
			and snapshots[b].team.round_id == roundId
			and snapshots[b].evacuation.remaining <= remaining,
		"personal retry cannot reset team or duplicate reward"
	)
	move(b, Vector3.new(exit.Position.X + 2, root(b).Position.Y, exit.Position.Z))
	waitFor(function()
		return snapshots[b].phase == "escaped" and snapshots[b].team.state == "finished"
	end, "B escape finishes team")
	check(
		snapshots[b].diamonds == 20 and not find("Monster") and not find("Monster2"),
		"last result cleans hunters"
	)
	stage = "round2_capture_revive"
	action(a, "retry")
	action(b, "retry")
	waitFor(function()
		return snapshots[a].phase == "active"
			and snapshots[b].phase == "active"
			and snapshots[a].team.round_id == roundId + 1
	end, "second round")
	prompt(a, assert(find("CornKeyPrompt")))
	waitFor(function()
		return snapshots[a].has_key
	end, "second key pickup")
	park(a)
	park(b)
	local monster = assert(find("Monster"))
	waitFor(function()
		return monster:GetAttribute("HuntState") ~= "dormant"
	end, "hunt awakens", 30)
	unpark(a)
	monster:PivotTo(CFrame.new(root(a).Position + Vector3.new(0, 0, 2)))
	waitFor(function()
		return snapshots[a].phase == "caught"
	end, "real first capture", 10)
	check(
		snapshots[b].phase == "active"
			and root(b).Parent.Humanoid.WalkSpeed == 12
			and find("CornKeyPrompt"),
		"capture drops key and preserves teammate active state/WalkSpeed12 during diagnostic anchoring"
	)
	waitFor(function()
		return snapshots[a].capture_remaining == 0
	end, "capture transition ends")
	local npcAt = monster.PrimaryPart.Position
	action(a, "revive")
	waitFor(function()
		return snapshots[a].phase == "active"
	end, "personal revive")
	check(
		snapshots[a].catches_remaining == 1
			and snapshots[b].catches_remaining == 2
			and (monster.PrimaryPart.Position - npcAt).Magnitude < 30,
		"revive leaves teammate attempts and NPC location intact"
	)
	park(a)
	stage = "late_join_two_clients"
	STS:AddPlayers(1)
	waitFor(function()
		return #Players:GetPlayers() == 3
	end, "third actual client", 120)
	local third
	for _, player in Players:GetPlayers() do
		if player ~= a and player ~= b then
			assert(third == nil, "Expected exactly one third client")
			third = player
		end
	end
	assert(third, "Third client missing")
	waitFor(function()
		return clientReadiness[third]
			and clientReadiness[third].ready
			and snapshots[third]
			and snapshots[third].hud
			and snapshots[third].team.count == 3
			and snapshots[third].team.remaining == 2
			and snapshots[third].team.round_id == roundId + 1
	end, "third client handler and HUD observe the current three-player roster", 120)
	STS:AddPlayers(1)
	waitFor(function()
		return #Players:GetPlayers() == 4
	end, "fourth actual client", 120)
	local late = {}
	for _, player in Players:GetPlayers() do
		if player ~= a and player ~= b then
			table.insert(late, player)
		end
	end
	table.sort(late, function(left, right)
		return left.UserId < right.UserId
	end)
	local c, d = late[1], late[2]
	waitFor(function()
		return clientReadiness[c]
			and clientReadiness[d]
			and clientReadiness[c].ready
			and clientReadiness[d].ready
			and snapshots[c]
			and snapshots[d]
			and snapshots[c].hud
			and snapshots[d].hud
			and snapshots[c].team.count == 4
			and snapshots[d].team.count == 4
			and snapshots[c].team.remaining == 2
			and snapshots[d].team.remaining == 2
			and snapshots[c].team.round_id == roundId + 1
			and snapshots[d].team.round_id == roundId + 1
	end, "both late HUDs observe all four connected players", 120)
	check(
		snapshots[c].phase == "ready"
			and snapshots[d].phase == "ready"
			and not snapshots[c].team.can_start
			and not snapshots[d].team.can_start
			and snapshots[c].team.remaining == 2
			and snapshots[d].team.remaining == 2,
		"late clients three and four wait outside current roster"
	)
	-- The production controller and probe both sync at startup; refill before
	-- testing admission so a rate rejection cannot stand in for the late-join guard.
	local lateSettlingAt = os.clock()
	report.late_startup_settling = { requested_seconds = 1.2, began_at = lateSettlingAt - began }
	task.wait(1.2)
	report.late_startup_settling.actual_seconds = os.clock() - lateSettlingAt
	report.late_startup_settling.ended_at = os.clock() - began
	action(c, "start")
	action(d, "start")
	check(
		not snapshots[c].team.ready and not snapshots[d].team.ready,
		"late joins cannot inject themselves into active team"
	)
	stage = "round2_abort_death"
	unpark(b)
	prompt(b, assert(find("CornKeyPrompt")))
	waitFor(function()
		return snapshots[b].has_key
	end, "B recovers first-catch key")
	action(b, "abort")
	waitFor(function()
		return snapshots[b].phase == "aborted" and find("CornKeyPrompt")
	end, "carrier abort key drop")
	check(
		snapshots[a].phase == "active"
			and snapshots[c].phase == "ready"
			and snapshots[d].phase == "ready",
		"carrier abort preserves active teammate and late queue"
	)
	-- The aborted avatar remains in the world. Clear the previous carrier from
	-- the next actor's diagnostic approach; production LOS still applies.
	local dropped = assert(find("CornKeyPrompt"))
	local approach = dropped.Parent.Position + Vector3.new(0, 2.4, -1.5)
	local approachParams = RaycastParams.new()
	approachParams.FilterType = Enum.RaycastFilterType.Exclude
	approachParams.FilterDescendantsInstances = { a.Character }
	approachParams.RespectCanCollide = true
	local approachHit =
		workspace:Raycast(approach, dropped.Parent.Position - approach, approachParams)
	report.aborted_avatar_approach = {
		scope = "Prospective diagnostic approach before moving the aborted avatar; not an actual failed pickup",
		hit = if approachHit then approachHit.Instance:GetFullName() else "",
		previous_carrier_occludes = approachHit ~= nil
			and approachHit.Instance:IsDescendantOf(b.Character),
	}
	move(b, root(b).Position + Vector3.new(10, 0, 0))
	unpark(a)
	prompt(a, assert(find("CornKeyPrompt")))
	waitFor(function()
		return snapshots[a].has_key
	end, "A recovers aborted carrier key")
	root(a).Parent.Humanoid.Health = 0
	waitFor(function()
		return snapshots[a].phase == "aborted" and snapshots[a].team.state == "finished"
	end, "last participant death")
	check(
		snapshots[a].diamonds == 20 and snapshots[b].diamonds == 20 and not find("CornKeyPrompt"),
		"death adds no reward and final result cleans key"
	)
	stage = "round3_four_ready"
	waitFor(function()
		return a.Character
			and a.Character:FindFirstChildOfClass("Humanoid")
			and a.Character.Humanoid.Health > 0
			and a.Character:FindFirstChild("HumanoidRootPart")
	end, "A respawns", 30)
	action(a, "retry")
	action(b, "retry")
	action(c, "start")
	waitFor(function()
		for _, player in { a, b, c, d } do
			local team = snapshots[player].team
			if
				team.ready_count ~= 3
				or team.state ~= "finished"
				or team.round_id ~= roundId + 1
			then
				return false
			end
		end
		return true
	end, "all four recipients observe three ready in the finished round")
	check(
		snapshots[a].team.ready
			and snapshots[b].team.ready
			and snapshots[c].team.ready
			and not snapshots[d].team.ready,
		"three ready cannot start fourth participant"
	)
	action(d, "start")
	waitFor(function()
		return snapshots[a].phase == "active"
			and snapshots[b].phase == "active"
			and snapshots[c].phase == "active"
			and snapshots[d].phase == "active"
	end, "all four active", 40)
	check(
		snapshots[a].team.round_id == roundId + 2
			and snapshots[d].team.round_id == roundId + 2
			and snapshots[a].team.remaining == 4,
		"new common round includes all four"
	)
	recordStarts({ a, b, c, d }, "four-player starts")
	stage = "round3_carrier_disconnect"
	park(b)
	park(c)
	park(d)
	prompt(a, assert(find("CornKeyPrompt")))
	waitFor(function()
		return snapshots[a].has_key
	end, "disconnect carrier takes key")
	command(a, "leave")
	waitFor(function()
		for _, player in { b, c, d } do
			local team = snapshots[player].team
			if team.count ~= 3 or team.remaining ~= 3 or team.round_id ~= roundId + 2 then
				return false
			end
		end
		return find("CornKeyPrompt") ~= nil
	end, "disconnected carrier key recovered for remaining three")
	check(
		snapshots[b].phase == "active"
			and snapshots[c].phase == "active"
			and snapshots[d].phase == "active"
			and find("Monster"),
		"actual disconnect preserves three active participants and hunt"
	)
	local keys = 0
	for _, item in map:GetDescendants() do
		if item:IsA("ProximityPrompt") and item.Name == "CornKeyPrompt" then
			keys += 1
		end
	end
	check(keys == 1, "disconnect restores exactly one world key")
	unpark(b)
	prompt(b, assert(find("CornKeyPrompt")))
	waitFor(function()
		return snapshots[b].has_key and snapshots[c].team.key_state == "carried"
	end, "survivor picks up disconnect key")
	stage = "round3_survivor_gate_exit"
	openGate(b)
	waitFor(function()
		return snapshots[b].gate_open and snapshots[c].gate_open and snapshots[d].gate_open
	end, "survivors share open gate")
	local arrivals = {}
	for index = 1, 3 do
		local npc = assert(find(if index == 1 then "Monster" else "Monster" .. index))
		check(npc:GetAttribute("DetectionRadius") == 96, "retained detection96 NPC" .. index)
		if index > 1 then
			local sound = assert(
				npc.Root:FindFirstChild("CornAudio_reinforcement_arrival_" .. index),
				"Retained arrival cry missing"
			)
			table.insert(arrivals, {
				index = index,
				uri = sound.SoundId,
				mode = sound.RollOffMode.Name,
				min = sound.RollOffMinDistance,
				max = sound.RollOffMaxDistance,
				looped = sound.Looped,
			})
		end
	end
	report.retained_arrivals = arrivals
	move(b, Vector3.new(exit.Position.X, root(b).Position.Y, exit.Position.Z))
	waitFor(function()
		if snapshots[b].phase ~= "escaped" then
			return false
		end
		for _, player in { b, c, d } do
			local team = snapshots[player].team
			if team.remaining ~= 2 or team.round_id ~= roundId + 2 then
				return false
			end
		end
		return true
	end, "all survivors observe the escape with two participants remaining")
	check(
		snapshots[b].diamonds == 40
			and snapshots[b].reward == 20
			and snapshots[c].phase == "active"
			and snapshots[d].phase == "active",
		"survivor rewarded once while other two continue"
	)
	action(c, "abort")
	action(d, "abort")
	waitFor(function()
		for _, player in { b, c, d } do
			local team = snapshots[player].team
			if team.state ~= "finished" or team.round_id ~= roundId + 2 then
				return false
			end
		end
		return snapshots[c].phase == "aborted"
			and snapshots[d].phase == "aborted"
			and not find("Monster")
	end, "all survivors observe final aborts and round cleanup")
	check(
		snapshots[c].diamonds == 0 and snapshots[d].diamonds == 0,
		"late participants receive no unearned reward"
	)
	report.passed = true
end, debug.traceback)
if not ok then
	report.error = failure
end
for player in staged do
	unpark(player)
end
report.recipients = {}
for player, metadata in known do
	table.insert(report.recipients, {
		identity = metadata,
		connected = player.Parent == Players,
		client_readiness = clientReadiness[player],
		last_snapshot = snapshots[player],
		trace = traces[player] and traces[player].rows,
		dropped_trace_rows = traces[player] and traces[player].dropped,
	})
end
table.sort(report.recipients, function(a, b)
	return a.identity.user_id < b.identity.user_id
end)
report.duration_sec = os.clock() - began
report.final_stage = stage
report.staging_restored = next(staged) == nil
probeConnection:Disconnect()
addedConnection:Disconnect()
removedConnection:Disconnect()
for _, connection in auditConnections do
	connection:Disconnect()
end
report.action_delivery_audit.connections_disconnected = true
print("[MultiplayerTest] " .. Http:JSONEncode(report))
task.wait(1)
STS:EndTest(report)
