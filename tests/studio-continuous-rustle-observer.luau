-- Read-only production observer. Native input / diagnostic NPC staging are separate.
-- Only owned temporary report StringValues are created; no Sound/gameplay writes.
local Run = game:GetService("RunService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("SoundService")
local Http = game:GetService("HttpService")
local Gui = game:GetService("GuiService")
assert(Run:IsStudio() and Run:IsRunning() and Run:IsClient(), "Studio Play Client required")
local map = assert(workspace:FindFirstChild("CornMap"), "Children_of_corn map required")
assert(map:GetAttribute("corn_project_id") == "children_of_corn", "Wrong project")
local player = assert(Players.LocalPlayer, "Local player required")
local URI = "rbxassetid://138698164682825"
local PROJECT = "children_of_corn"
local MAX_ACTORS, MAX_HISTORY, MAX_EVENTS, MAX_SAMPLES = 11, 32, 4000, 13300
local DURATION, INTERVAL = 120, 0.1
local folder = assert(SS:FindFirstChild("CornPersonalAudio"), "Production audio folder required")
local ownLoop = assert(folder:FindFirstChild("CornLoop"), "Automatic personal loop required")
local function owned(sound, role)
	return sound
		and sound:IsA("Sound")
		and sound:GetAttribute("CornAudioOwned") == true
		and sound:GetAttribute("corn_project_id") == PROJECT
		and (role == "corn_rustle" or sound:GetAttribute("AudioVersion") == 1)
		and sound:GetAttribute("audio_role") == role
end
assert(
	owned(ownLoop, "cornloop") and ownLoop.SoundId == URI and ownLoop.Looped,
	"Expected selected continuous personal Sound"
)
local value = Instance.new("StringValue")
value.Name = "CornContinuousRustleObserver_" .. Http:GenerateGUID(false)
value:SetAttribute("corn_test_owned", true)
value:SetAttribute("Stage", "initial")
value:SetAttribute("Done", false)
value.Parent = RS
local began, actorCount, nextId = os.clock(), 0, 0
local entries, byRoot, summaries, connections, samples, events = {}, {}, {}, {}, {}, {}
local droppedSamples, droppedEvents, ignoredActors = 0, 0, 0
local snapshot
local remotes = RS:FindFirstChild("GameRemotes")
local remote = remotes and remotes:FindFirstChild("round_snapshot")
if remote and remote:IsA("RemoteEvent") then
	table.insert(
		connections,
		remote.OnClientEvent:Connect(function(current)
			snapshot = current
		end)
	)
end
local function stage()
	return string.sub(tostring(value:GetAttribute("Stage") or ""), 1, 80)
end
local function disconnect(list)
	for _, connection in list do
		connection:Disconnect()
	end
	table.clear(list)
end
local function soundState(sound)
	if not sound or not sound.Parent then
		return { present = false }
	end
	return {
		present = true,
		path = sound:GetFullName(),
		uri = sound.SoundId,
		cursor = sound.TimePosition,
		loaded = sound.IsLoaded,
		length = sound.TimeLength,
		playing = sound.IsPlaying,
		loudness = sound.PlaybackLoudness,
		speed = sound.PlaybackSpeed,
		volume = sound.Volume,
		looped = sound.Looped,
		min = sound.RollOffMinDistance,
		max = sound.RollOffMaxDistance,
		rolloff = sound.RollOffMode.Name,
	}
end
local function record(entry, scope, kind)
	local sound = if scope == "loop" then entry.loop else entry.source
	local state = soundState(sound)
	local counts = if scope == "loop"
		then entry.summary.loop_events
		else entry.summary.source_events
	counts[kind] = (counts[kind] or 0) + 1
	if scope == "loop" and state.present then
		if kind == "Paused" then
			entry.pausedCursor = state.cursor
		elseif kind == "Resumed" and entry.pausedCursor then
			entry.summary.max_resume_cursor_jump = math.max(
				entry.summary.max_resume_cursor_jump,
				math.abs(state.cursor - entry.pausedCursor)
			)
		end
	end
	if #events < MAX_EVENTS then
		table.insert(events, {
			at = os.clock() - began,
			stage = stage(),
			actor = entry.summary.id,
			scope = scope,
			kind = kind,
			cursor = state.cursor,
			speed = state.speed,
			uri = state.uri,
		})
	else
		droppedEvents += 1
	end
end
local function bindSound(entry, sound, scope)
	local key = if scope == "loop" then "loop" else "source"
	if entry[key] == sound then
		return
	end
	disconnect(entry[key .. "Connections"])
	entry[key] = sound
	if not sound then
		return
	end
	entry.summary[key .. "_bindings"] += 1
	entry.summary[key .. "_initial"] = entry.summary[key .. "_initial"] or soundState(sound)
	for _, kind in { "Played", "Paused", "Resumed", "DidLoop", "Stopped", "Ended", "Loaded" } do
		table.insert(
			entry[key .. "Connections"],
			sound[kind]:Connect(function()
				record(entry, scope, kind)
			end)
		)
	end
	table.insert(
		entry[key .. "Connections"],
		sound:GetPropertyChangedSignal("SoundId"):Connect(function()
			record(entry, scope, "URIChanged")
		end)
	)
end
local function refresh(entry)
	local root = entry.root
	local source = root and root.Parent and root:FindFirstChild("CornAudio_corn_rustle")
	bindSound(entry, if owned(source, "corn_rustle") then source else nil, "source")
	local loop
	if entry.summary.kind == "self" then
		loop = if owned(ownLoop, "cornloop") and ownLoop.Parent == folder then ownLoop else nil
	else
		local candidate = root and root.Parent and root:FindFirstChild("CornLocalRustle")
		loop = if owned(candidate, "corn_loop_local") then candidate else nil
	end
	bindSound(entry, loop, "loop")
end
local function entryFor(kind, role, root)
	if kind ~= "self" and byRoot[root] then
		return byRoot[root]
	end
	if actorCount >= MAX_ACTORS or #summaries >= MAX_HISTORY then
		ignoredActors += 1
		return nil
	end
	nextId += 1
	local summary = {
		id = role .. ":" .. nextId,
		kind = kind,
		role = role,
		at = os.clock() - began,
		loop_events = {},
		source_events = {},
		loop_bindings = 0,
		source_bindings = 0,
		samples = 0,
		active_samples = 0,
		playing_samples = 0,
		loaded_samples = 0,
		silent_source_playing_samples = 0,
		max_loudness = 0,
		max_paused_cursor_delta = 0,
		max_resume_cursor_jump = 0,
		max_local_loops_on_root = 0,
		max_legacy_voices_on_root = 0,
		root_changes = 0,
	}
	local entry = {
		summary = summary,
		root = root,
		loopConnections = {},
		sourceConnections = {},
		rootConnections = {},
	}
	table.insert(entries, entry)
	table.insert(summaries, summary)
	if kind ~= "self" then
		byRoot[root] = entry
	end
	actorCount += 1
	refresh(entry)
	return entry
end
local selfEntry = assert(entryFor("self", "self", nil), "Own observation entry required")
local function retire(entry)
	if entry.retired then
		return
	end
	entry.retired = true
	entry.summary.retired_at = os.clock() - began
	entry.summary.loop_final = soundState(entry.loop)
	entry.summary.source_final = soundState(entry.source)
	disconnect(entry.loopConnections)
	disconnect(entry.sourceConnections)
	disconnect(entry.rootConnections)
	byRoot[entry.root] = nil
	actorCount -= 1
end
local function resolve()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root ~= selfEntry.root then
		selfEntry.root = root
		selfEntry.previous = nil
		selfEntry.summary.root_changes += 1
	end
	local wanted = {}
	local count = 1
	for _, other in Players:GetPlayers() do
		if other ~= player and count < 8 then
			local otherRoot = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
			if otherRoot and otherRoot:IsA("BasePart") then
				wanted[otherRoot] = true
				entryFor("player", "player_" .. other.UserId, otherRoot)
				count += 1
			end
		end
	end
	local runtime = map:FindFirstChild("CornRoundRuntime")
	local indices = {}
	if runtime and runtime:GetAttribute("corn_project_id") == PROJECT then
		for _, model in runtime:GetChildren() do
			local index = model:GetAttribute("MonsterIndex")
			if
				model:IsA("Model")
				and model:GetAttribute("CornMonsterOwned") == true
				and model:GetAttribute("corn_project_id") == PROJECT
				and model:GetAttribute("MonsterRigVersion") == 1
				and type(index) == "number"
				and index % 1 == 0
				and index >= 1
				and index <= 3
				and not indices[index]
			then
				local npcRoot = model:FindFirstChild("Root")
				if npcRoot and npcRoot:IsA("BasePart") then
					indices[index], wanted[npcRoot] = true, true
					entryFor("npc", "npc" .. index, npcRoot)
				end
			end
		end
	end
	for _, entry in entries do
		if not entry.retired and entry ~= selfEntry and not wanted[entry.root] then
			retire(entry)
		end
	end
	for _, entry in entries do
		if not entry.retired then
			refresh(entry)
		end
	end
end
local function sample(entry, now)
	local root, loop, source = entry.root, entry.loop, entry.source
	local position = root and root.Parent and root.Position
	local current, silent = soundState(loop), soundState(source)
	local active = source and source.Parent and source:GetAttribute("AudioCornActive") == true
	local sourceSpeed = source and source.Parent and source:GetAttribute("AudioCornSpeed")
	local camera = workspace.CurrentCamera
	local row = {
		at = now - began,
		stage = stage(),
		actor = entry.summary.id,
		root_present = position ~= nil,
		x = position and position.X,
		y = position and position.Y,
		z = position and position.Z,
		distance = position and camera and (position - camera.CFrame.Position).Magnitude,
		loop_present = current.present,
		loaded = current.loaded,
		cursor = current.cursor,
		length = current.length,
		playing = current.playing,
		speed = current.speed,
		loudness = current.loudness,
		volume = current.volume,
		looped = current.looped,
		min = current.min,
		max = current.max,
		rolloff = current.rolloff,
		uri = current.uri,
		source_present = silent.present,
		source_uri = silent.uri,
		source_playing = silent.playing,
		source_volume = silent.volume,
		source_cursor = silent.cursor,
		corn_active = active,
		corn_speed = if type(sourceSpeed) == "number" then sourceSpeed else nil,
		phase = snapshot and snapshot.phase,
		sprint = snapshot and snapshot.is_sprinting,
		menu_open = Gui.MenuIsOpen,
		source_requested_playing = source and source.Parent and source:GetAttribute(
			"AudioRequestedPlaying"
		),
		hunt_state = root and root.Parent and root.Parent:GetAttribute("HuntState"),
	}
	local loops, legacy = 0, 0
	if root and root.Parent then
		for _, child in root:GetChildren() do
			if
				child:IsA("Sound")
				and child:GetAttribute("CornAudioOwned") == true
				and child:GetAttribute("corn_project_id") == PROJECT
			then
				if child:GetAttribute("audio_role") == "corn_loop_local" then
					loops += 1
				elseif child:GetAttribute("audio_role") == "corn_rustle_local" then
					legacy += 1
				end
			end
		end
	end
	row.spatial_loops, row.legacy_voices = loops, legacy
	local summary = entry.summary
	summary.samples += 1
	summary.active_samples += if active then 1 else 0
	summary.playing_samples += if current.playing then 1 else 0
	summary.loaded_samples += if current.loaded then 1 else 0
	summary.silent_source_playing_samples += if silent.playing then 1 else 0
	summary.max_loudness = math.max(summary.max_loudness, current.loudness or 0)
	summary.max_local_loops_on_root = math.max(summary.max_local_loops_on_root, loops)
	summary.max_legacy_voices_on_root = math.max(summary.max_legacy_voices_on_root, legacy)
	if
		entry.previous
		and current.present
		and entry.previous.loop_present
		and not current.playing
		and not entry.previous.playing
	then
		summary.max_paused_cursor_delta = math.max(
			summary.max_paused_cursor_delta,
			math.abs((current.cursor or 0) - (entry.previous.cursor or 0))
		)
	end
	entry.previous = row
	if #samples < MAX_SAMPLES then
		table.insert(samples, row)
	else
		droppedSamples += 1
	end
end
local function uiButtons()
	local hud = player.PlayerGui:FindFirstChild("CornMovementHud")
	local count = 0
	for _, item in if hud then hud:GetDescendants() else {} do
		if item:IsA("TextButton") and string.match(item.Text, "^Звук%s*[12]") then
			count += 1
		end
	end
	return count
end
local initialButtons = uiButtons()
local function chunks(rows, prefix)
	local names = {}
	for first = 1, #rows, 200 do
		local group = {}
		for index = first, math.min(first + 199, #rows) do
			table.insert(group, rows[index])
		end
		local child = Instance.new("StringValue")
		child.Name = prefix .. first
		child:SetAttribute("corn_test_owned", true)
		child.Value = Http:JSONEncode(group)
		assert(#child.Value < 190000, "Observer chunk exceeds safe StringValue limit")
		child.Parent = value
		table.insert(names, child.Name)
	end
	return names
end
value.Value = Http:JSONEncode({ done = false, duration = DURATION, sample_interval = INTERVAL })
task.spawn(function()
	local lastResolve, lastProgress = -math.huge, -math.huge
	local ok, problem = pcall(function()
		while
			value.Parent
			and value:GetAttribute("Stop") ~= true
			and os.clock() - began < DURATION
		do
			local now = os.clock()
			if now - lastResolve >= 0.25 then
				resolve()
				lastResolve = now
			end
			for _, entry in entries do
				if not entry.retired then
					sample(entry, now)
				end
			end
			if now - lastProgress >= 1 then
				value:SetAttribute("Elapsed", now - began)
				value:SetAttribute("Samples", #samples)
				value:SetAttribute("Actors", actorCount)
				lastProgress = now
			end
			task.wait(INTERVAL)
		end
	end)
	disconnect(connections)
	for _, entry in entries do
		if not entry.retired then
			entry.summary.loop_final = soundState(entry.loop)
			entry.summary.source_final = soundState(entry.source)
		end
		disconnect(entry.loopConnections)
		disconnect(entry.sourceConnections)
		disconnect(entry.rootConnections)
	end
	if not value.Parent then
		return
	end
	local report = {
		done = true,
		observer_ok = ok,
		error = if ok then nil else tostring(problem),
		duration = os.clock() - began,
		expected_uri = URI,
		actors = summaries,
		sample_count = #samples,
		event_count = #events,
		dropped_samples = droppedSamples,
		dropped_events = droppedEvents,
		ignored_actors = ignoredActors,
		initial_comparison_buttons = initialButtons,
		final_comparison_buttons = uiButtons(),
		sample_chunks = chunks(samples, "Samples"),
		event_chunks = chunks(events, "Events"),
		method = "Read-only actual production player/NPC loops and silent sources; operator native input and diagnostic motion recorded separately. No synthetic cues, Sound/gameplay writes, seek, preload or field scans.",
	}
	value.Value = Http:JSONEncode(report)
	assert(#value.Value < 190000, "Observer metadata exceeds safe StringValue limit")
	value:SetAttribute("Done", true)
end)
return {
	handle = value.Name,
	duration = DURATION,
	sample_interval = INTERVAL,
	stop_attribute = "Stop",
	stage_attribute = "Stage",
	done_attribute = "Done",
	maximum_actors = MAX_ACTORS,
}
