-- Version 3, prepared only: this revision has not been executed in native Studio.
-- Arm before the real gate transaction; collect owned report before Stop Play.
-- Read-only DescendantAdded observer. Deferred signals may attach after Play,
-- therefore observed Played events are incomplete and never an exact call count.
-- Earlier v1/v2 diagnostic failures do not invalidate separate client playback.
-- No loaded-module factory wrapping, Source/Sound/gameplay/remote writes.
local Run = game:GetService("RunService")
local Storage = game:GetService("ServerStorage")
local Http = game:GetService("HttpService")
assert(Run:IsStudio() and Run:IsServer() and Run:IsRunning(), "Studio Play Server required")
local map = assert(workspace:FindFirstChild("CornMap"), "CornMap missing")
assert(map:GetAttribute("corn_project_id") == "children_of_corn", "Wrong project")
local runtime = assert(map:FindFirstChild("CornRoundRuntime"), "Active runtime required")
assert(runtime:GetAttribute("GateOpen") ~= true, "Arm before gate opening")
assert(
	not runtime:FindFirstChild("Monster2") and not runtime:FindFirstChild("Monster3"),
	"Reinforcements already exist"
)
local roles = { reinforcement_arrival_2 = true, reinforcement_arrival_3 = true }
local report = Instance.new("StringValue")
report.Name = "CornEntityArrivalServerReport_" .. Http:GenerateGUID(false)
report:SetAttribute("corn_test_owned", true)
report:SetAttribute("corn_project_id", "children_of_corn")
report:SetAttribute("ObserverVersion", 3)
report:SetAttribute("Armed", false)
report:SetAttribute("Done", false)
report:SetAttribute("Stop", false)
report.Parent = Storage
local began, first = os.clock(), nil
local rows, bySound, watched, connections, errors = {}, {}, {}, {}, {}
local MAX_SOUNDS, MAX_PENDING = 8, 128
local pendingCount, droppedSounds = 0, 0
local function state(sound)
	return {
		path = sound:GetFullName(),
		uri = sound.SoundId,
		looped = sound.Looped,
		volume = sound.Volume,
		playing = sound.IsPlaying,
		requested = sound:GetAttribute("AudioRequestedPlaying") == true,
		loaded = sound.IsLoaded,
		mode = sound.RollOffMode.Name,
		range_min = sound.RollOffMinDistance,
		range_max = sound.RollOffMaxDistance,
		cursor = sound.TimePosition,
		length = sound.TimeLength,
	}
end
local function bind(sound)
	if bySound[sound] then
		return
	end
	local role = sound:GetAttribute("audio_role")
	if not roles[role] then
		return
	end
	if #rows >= MAX_SOUNDS then
		droppedSounds += 1
		bySound[sound] = true
		return
	end
	local initial = state(sound)
	local row = {
		role = role,
		initial = initial,
		initial_playing = initial.playing,
		initial_requested = initial.requested,
		attached_at = os.clock() - began,
		played = 0,
		ended = 0,
		stopped = 0,
		played_count_complete = false,
	}
	bySound[sound] = row
	table.insert(rows, row)
	first = first or os.clock()
	for _, event in { "Played", "Ended", "Stopped" } do
		table.insert(
			connections,
			sound[event]:Connect(function()
				local key = event:lower()
				row[key] += 1
				row[key .. "_at"] = os.clock() - began
				row[key .. "_state"] = state(sound)
				if event == "Stopped" and row.ended == 0 then
					row.stopped_before_end = true
				end
			end)
		)
	end
end
local function tryBind(sound)
	local ok, problem = pcall(bind, sound)
	if not ok and #errors < 8 then
		table.insert(errors, tostring(problem):sub(1, 1200))
	end
end
local function watch(item)
	if not item:IsA("Sound") or watched[item] then
		return
	end
	if pendingCount >= MAX_PENDING then
		droppedSounds += 1
		return
	end
	watched[item] = true
	pendingCount += 1
	table.insert(
		connections,
		item:GetAttributeChangedSignal("audio_role"):Connect(function()
			tryBind(item)
		end)
	)
	tryBind(item)
end
table.insert(connections, runtime.DescendantAdded:Connect(watch))
report.Value =
	Http:JSONEncode({ done = false, observer_version = 3, played_count_complete = false })
report:SetAttribute("Armed", true)
task.spawn(function()
	local reason = "total_timeout"
	local ok, problem = pcall(function()
		while report.Parent and os.clock() - began < 60 do
			if report:GetAttribute("Stop") == true then
				reason = "requested_stop"
				break
			end
			if first and os.clock() - first >= 12 then
				reason = "after_first_complete"
				break
			end
			task.wait(0.05)
		end
	end)
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	if not report.Parent then
		return
	end
	local roleCounts = { reinforcement_arrival_2 = 0, reinforcement_arrival_3 = 0 }
	local bothEnded = #rows == 2
	for _, row in rows do
		roleCounts[row.role] += 1
		bothEnded = bothEnded and row.ended > 0
	end
	report.Value = Http:JSONEncode({
		done = true,
		observer_version = 3,
		observer_ok = ok and #errors == 0,
		error = if ok then nil else tostring(problem):sub(1, 1200),
		errors = errors,
		rows = rows,
		role_counts = roleCounts,
		observed_two_arrivals_ended = bothEnded
			and roleCounts.reinforcement_arrival_2 == 1
			and roleCounts.reinforcement_arrival_3 == 1,
		elapsed = os.clock() - began,
		reason = reason,
		dropped_sounds = droppedSounds,
		connections_disconnected = true,
		played_count_complete = false,
		exact_play_count_accepted = false,
		scope = "Read-only server DescendantAdded and post-attachment events, initial IsPlaying/AudioRequestedPlaying, Ended/Stopped. Deferred attachment can miss Played; observed Played is a lower bound, never exact production Play count. Client observer separately owns decoding/cursor/loudness; deterministic unit instrumentation owns exact call counts. No module, Source, Sound or gameplay writes.",
	})
	report:SetAttribute("Armed", false)
	report:SetAttribute("Done", true)
end)
return {
	handle = report.Name,
	parent = "ServerStorage",
	armed = true,
	observer_version = 3,
	done_attribute = "Done",
	stop_attribute = "Stop",
	played_count_complete = false,
}
