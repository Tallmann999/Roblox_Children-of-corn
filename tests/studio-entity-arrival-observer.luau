-- Execute on the verified Children_of_corn Play CLIENT before opening the gate.
-- Read-only Sound observer: creates only an owned PlayerGui report StringValue.
-- Collect Done=true JSON (and named chunks, if any) before cleanup/Stop Play.
-- Client Played may precede replication; the separate server observer owns the
-- authoritative Play count. This records decoded playback/cursor/loudness.
local Run = game:GetService("RunService")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local Http = game:GetService("HttpService")
assert(Run:IsStudio() and Run:IsRunning() and Run:IsClient(), "Studio Play Client required")
local map = assert(workspace:FindFirstChild("CornMap"), "Children_of_corn map required")
assert(
	map:IsA("Model") and map:GetAttribute("corn_project_id") == "children_of_corn",
	"Wrong project"
)
local runtime = assert(map:FindFirstChild("CornRoundRuntime"), "Production round required")
assert(runtime:GetAttribute("corn_project_id") == "children_of_corn", "Foreign runtime")
assert(runtime:GetAttribute("GateOpen") ~= true, "Arm observer before opening the gate")
assert(
	not runtime:FindFirstChild("Monster2") and not runtime:FindFirstChild("Monster3"),
	"Reinforcements already exist"
)
local player = assert(Players.LocalPlayer, "LocalPlayer required")
local gui = assert(player:FindFirstChild("PlayerGui"), "PlayerGui required")
local PROJECT = "children_of_corn"
local INTERVAL, AFTER_FIRST, TOTAL_LIMIT = 0.03, 12, 60
local MAX_SOUNDS, MAX_PENDING, MAX_EVENTS, MAX_TRACES = 8, 128, 32, 24
local EXPECTED = {
	reinforcement_arrival_2 = {
		index = 2,
		key = "COC_Monster_01",
		uri = "rbxassetid://100872584572146",
		volume = 0.95,
	},
	reinforcement_arrival_3 = {
		index = 3,
		key = "COC_Monster_02",
		uri = "rbxassetid://92691373477671",
		volume = 0.95 * 0.998849,
	},
}
for _, item in runtime:GetDescendants() do
	if item:IsA("Sound") then
		assert(
			not EXPECTED[item:GetAttribute("audio_role")],
			"Arrival already present: arm before gate"
		)
	end
end
local reportValue = Instance.new("StringValue")
reportValue.Name = "CornEntityArrivalObserver_" .. Http:GenerateGUID(false)
reportValue:SetAttribute("corn_test_owned", true)
reportValue:SetAttribute("corn_project_id", PROJECT)
reportValue:SetAttribute("ObserverVersion", 1)
reportValue:SetAttribute("Armed", false)
reportValue:SetAttribute("Done", false)
reportValue:SetAttribute("Stop", false)
reportValue.Parent = gui
local began, firstArrival = os.clock(), nil
local entries, bySound, watched, connections = {}, {}, {}, {}
local watchedCount, droppedSounds = 0, 0
local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function number(value)
	return if finite(value) then value else 0
end
local function owned(item)
	return item ~= nil
		and item:GetAttribute("CornAudioOwned") == true
		and item:GetAttribute("corn_project_id") == PROJECT
end
local function snapshot(sound, expected)
	local ok, state = pcall(function()
		local root = sound.Parent
		local model = if root then root.Parent else nil
		local group = sound.SoundGroup
		local folder = if group then group.Parent else nil
		local rootBound = root ~= nil
			and root:IsA("BasePart")
			and root.Name == "Root"
			and model ~= nil
			and model:IsA("Model")
			and model.Name == "Monster" .. expected.index
			and model.Parent == runtime
			and model:GetAttribute("CornMonsterOwned") == true
			and model:GetAttribute("corn_project_id") == PROJECT
			and model:GetAttribute("MonsterRigVersion") == 1
			and model:GetAttribute("MonsterIndex") == expected.index
		local groupBound = group ~= nil
			and group:IsA("SoundGroup")
			and group.Name == "Effects"
			and owned(group)
			and group:GetAttribute("audio_role") == "group_Effects"
			and folder ~= nil
			and folder:IsA("Folder")
			and folder.Parent == SoundService
			and owned(folder)
			and folder:GetAttribute("audio_role") == "groups"
		local ownRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		return {
			present = root ~= nil,
			path = sound:GetFullName(),
			root_path = if root then root:GetFullName() else "",
			root_binding = rootBound,
			uri = sound.SoundId,
			key = tostring(sound:GetAttribute("AudioAssetKey") or ""),
			role = tostring(sound:GetAttribute("audio_role") or ""),
			owned = owned(sound),
			playing = sound.IsPlaying,
			loaded = sound.IsLoaded,
			time_position = number(sound.TimePosition),
			time_length = number(sound.TimeLength),
			loudness = number(sound.PlaybackLoudness),
			volume = number(sound.Volume),
			speed = number(sound.PlaybackSpeed),
			looped = sound.Looped,
			rolloff = sound.RollOffMode.Name,
			min_distance = number(sound.RollOffMinDistance),
			max_distance = number(sound.RollOffMaxDistance),
			group = if group then group:GetFullName() else "",
			group_binding = groupBound,
			group_volume = if group then number(group.Volume) else 0,
			listener_root_distance = if root
					and root:IsA("BasePart")
					and ownRoot
					and ownRoot:IsA("BasePart")
				then number((root.Position - ownRoot.Position).Magnitude)
				else -1,
		}
	end)
	return if ok then state else { present = false, read_error = tostring(state):sub(1, 500) }
end
local function matches(state, expected, role)
	return state.present == true
		and state.owned == true
		and state.role == role
		and state.key == expected.key
		and state.uri == expected.uri
		and state.root_binding == true
		and state.group_binding == true
		and state.looped == false
		and state.rolloff == "Linear"
		and state.min_distance == 20
		and state.max_distance == 1400
		and math.abs(state.volume - expected.volume) < 0.0001
		and math.abs(state.group_volume - 0.8) < 0.0001
end
local function trace(entry, state, kind, at)
	if #entry.traces >= MAX_TRACES then
		return
	end
	table.insert(entry.traces, {
		at = at,
		kind = kind,
		playing = state.playing,
		loaded = state.loaded,
		cursor = state.time_position,
		length = state.time_length,
		loudness = state.loudness,
	})
end
local function sample(entry, now)
	local state = snapshot(entry.sound, entry.expected)
	entry.latest = state
	entry.samples += 1
	if not state.present then
		return
	end
	entry.last_present = state
	entry.max_time_length = math.max(entry.max_time_length, state.time_length)
	entry.max_time_position = math.max(entry.max_time_position, state.time_position)
	entry.max_loudness = math.max(entry.max_loudness, state.loudness)
	if state.playing then
		entry.playing_samples += 1
	end
	if state.loudness > 0 then
		entry.positive_loudness_samples += 1
	end
	if entry.previous_cursor and state.time_position > entry.previous_cursor + 0.00001 then
		entry.cursor_advances += 1
		entry.max_forward_cursor_delta =
			math.max(entry.max_forward_cursor_delta, state.time_position - entry.previous_cursor)
	end
	entry.previous_cursor = state.time_position
	if matches(state, entry.expected, entry.role) then
		entry.matching_property_samples += 1
	elseif state.playing and now - entry.attached_at > 0.1 then
		entry.playing_property_mismatch_samples += 1
	end
	if now - entry.last_trace_at >= 0.25 or state.playing ~= entry.last_playing then
		trace(entry, state, "sample", now - began)
		entry.last_trace_at = now
	end
	entry.last_playing = state.playing
end
local function bind(sound)
	if bySound[sound] then
		return
	end
	local role = sound:GetAttribute("audio_role")
	local expected = EXPECTED[role]
	if not expected then
		return
	end
	if #entries >= MAX_SOUNDS then
		droppedSounds += 1
		bySound[sound] = true
		return
	end
	local now = os.clock()
	firstArrival = firstArrival or now
	local initial = snapshot(sound, expected)
	local entry = {
		sound = sound,
		expected = expected,
		role = role,
		attached_at = now,
		initial = initial,
		initial_playing = initial.playing == true,
		initial_cursor = initial.time_position,
		events = { Played = 0, Ended = 0, Stopped = 0, Loaded = 0 },
		event_trace = {},
		traces = {},
		samples = 0,
		playing_samples = 0,
		positive_loudness_samples = 0,
		matching_property_samples = 0,
		playing_property_mismatch_samples = 0,
		cursor_advances = 0,
		max_forward_cursor_delta = 0,
		max_time_length = 0,
		max_time_position = 0,
		max_loudness = 0,
		last_trace_at = -math.huge,
	}
	bySound[sound] = entry
	table.insert(entries, entry)
	for _, kind in { "Played", "Ended", "Stopped", "Loaded" } do
		table.insert(
			connections,
			sound[kind]:Connect(function()
				entry.events[kind] += 1
				local state = snapshot(sound, expected)
				if #entry.event_trace < MAX_EVENTS then
					table.insert(entry.event_trace, {
						at = os.clock() - began,
						kind = kind,
						cursor = state.time_position,
						length = state.time_length,
					})
				end
				trace(entry, state, kind, os.clock() - began)
			end)
		)
	end
	sample(entry, now)
	reportValue:SetAttribute("ObservedSounds", #entries)
end
local function watch(item)
	if not item:IsA("Sound") or watched[item] then
		return
	end
	if watchedCount >= MAX_PENDING then
		droppedSounds += 1
		return
	end
	watched[item] = true
	watchedCount += 1
	-- Attribute replication may follow DescendantAdded. Never scan field plants
	-- every sample or write any Sound property to compensate for replication.
	table.insert(
		connections,
		item:GetAttributeChangedSignal("audio_role"):Connect(function()
			bind(item)
		end)
	)
	bind(item)
end
table.insert(connections, map.DescendantAdded:Connect(watch))
reportValue.Value = Http:JSONEncode({
	done = false,
	armed = true,
	sample_interval = INTERVAL,
	after_first = AFTER_FIRST,
	total_limit = TOTAL_LIMIT,
})
reportValue:SetAttribute("Armed", true)
task.spawn(function()
	local reason = "total_timeout"
	local ok, problem = pcall(function()
		local nextProgress = began
		while reportValue.Parent do
			local now = os.clock()
			if reportValue:GetAttribute("Stop") == true then
				reason = "requested_stop"
				break
			end
			if now - began >= TOTAL_LIMIT then
				break
			end
			if firstArrival and now - firstArrival >= AFTER_FIRST then
				reason = "after_first_complete"
				break
			end
			for _, entry in entries do
				sample(entry, now)
			end
			if now >= nextProgress then
				reportValue:SetAttribute("Elapsed", now - began)
				reportValue:SetAttribute("ObservedSounds", #entries)
				nextProgress = now + 0.5
			end
			task.wait(INTERVAL)
		end
	end)
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	if not reportValue.Parent then
		return
	end
	local rows, roleCounts = {}, { reinforcement_arrival_2 = 0, reinforcement_arrival_3 = 0 }
	local allPlayback = #entries == 2
	for _, entry in entries do
		local state = entry.last_present or entry.initial
		local started = entry.initial_playing
			or entry.events.Played > 0
			or entry.playing_samples > 0
		local playback = started
			and entry.max_time_length > 0
			and entry.cursor_advances > 0
			and entry.max_loudness > 0
		local properties = entry.matching_property_samples > 0
			and entry.playing_property_mismatch_samples == 0
		roleCounts[entry.role] += 1
		allPlayback = allPlayback and playback and properties
		table.insert(rows, {
			role = entry.role,
			expected = entry.expected,
			attached_at = entry.attached_at - began,
			initial = entry.initial,
			last_present = state,
			latest = entry.latest,
			initial_playing = entry.initial_playing,
			events = entry.events,
			event_trace = entry.event_trace,
			traces = entry.traces,
			samples = entry.samples,
			playing_samples = entry.playing_samples,
			positive_loudness_samples = entry.positive_loudness_samples,
			cursor_advances = entry.cursor_advances,
			max_forward_cursor_delta = entry.max_forward_cursor_delta,
			max_time_length = entry.max_time_length,
			max_time_position = entry.max_time_position,
			max_loudness = entry.max_loudness,
			matching_property_samples = entry.matching_property_samples,
			playing_property_mismatch_samples = entry.playing_property_mismatch_samples,
			decoded_playback_observed = playback,
			expected_properties_observed = properties,
		})
	end
	local report = {
		done = true,
		observer_ok = ok,
		error = if ok then nil else tostring(problem):sub(1, 1500),
		method = "Read-only production Client Sound replication/decoding/cursor/loudness; no Sound writes, synthetic cues or preload. Native gate input and server Play counts are separate evidence.",
		reason = reason,
		duration = os.clock() - began,
		first_arrival_at = if firstArrival then firstArrival - began else nil,
		after_first_observed = if firstArrival then os.clock() - firstArrival else 0,
		sample_interval = INTERVAL,
		sound_count = #entries,
		role_counts = roleCounts,
		dropped_sounds = droppedSounds,
		connections_disconnected = true,
		client_playback_accepted = ok
			and allPlayback
			and droppedSounds == 0
			and roleCounts.reinforcement_arrival_2 == 1
			and roleCounts.reinforcement_arrival_3 == 1,
		sounds = rows,
		chunks = {},
	}
	local encoded = Http:JSONEncode(report)
	if #encoded >= 180000 then
		report.sounds = nil
		for index, row in rows do
			local chunk = Instance.new("StringValue")
			chunk.Name = "Sound" .. index
			chunk:SetAttribute("corn_test_owned", true)
			chunk.Value = Http:JSONEncode(row)
			assert(#chunk.Value < 180000, "Observer sound chunk exceeds safe limit")
			chunk.Parent = reportValue
			table.insert(report.chunks, chunk.Name)
		end
		encoded = Http:JSONEncode(report)
	end
	assert(#encoded < 180000, "Observer report exceeds safe limit")
	reportValue.Value = encoded
	reportValue:SetAttribute("Elapsed", os.clock() - began)
	reportValue:SetAttribute("Armed", false)
	reportValue:SetAttribute("Done", true)
end)
return {
	handle = reportValue.Name,
	parent = "Players.LocalPlayer.PlayerGui",
	armed_attribute = "Armed",
	done_attribute = "Done",
	stop_attribute = "Stop",
	sample_interval = INTERVAL,
	after_first_seconds = AFTER_FIRST,
	total_limit_seconds = TOTAL_LIMIT,
	collect_before = "report cleanup or Stop Play",
}
