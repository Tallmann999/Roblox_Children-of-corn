-- Verified Children_of_corn Studio SERVER during Play. Returns immediately;
-- poll the report StringValue until done=true (at most 20 seconds).
-- Five original stagger offsets are checked, then aligned ONLY in this isolated
-- fixture to observe all five real decoders/fades/natural ends in one slot.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local ContentProvider = game:GetService("ContentProvider")
local LogService = game:GetService("LogService")
assert(
	RunService:IsStudio() and RunService:IsRunning() and RunService:IsServer(),
	"Studio Play Server required"
)
local map = assert(workspace:FindFirstChild("CornMap"), "Verified CornMap required")
assert(map:GetAttribute("corn_project_id") == "children_of_corn", "Wrong project")
local Audio = require(game.ServerScriptService.GameServer.Game.RoundAudio)
local Shared = ReplicatedStorage.GameShared.Game
local Assets = require(Shared.AudioAssets)
local Rules = require(Shared.AudioRules)
local definition = Assets.Get("COC_Crickets_15s")
assert(string.match(definition.Id, "^rbxassetid://%d+$"), "Author cricket asset ID required")
local assetNumber = string.match(definition.Id, "%d+")
local guid = HttpService:GenerateGUID(false)
local result = Instance.new("StringValue")
result.Name = "CornCricketFadesReport_" .. guid
result:SetAttribute("corn_test_owned", true)
result:SetAttribute("FixtureId", guid)
result.Parent = ReplicatedStorage
local began = os.clock()
local report = {
	fixture_version = 1,
	fixture_id = guid,
	done = false,
	passed = false,
	status = "running",
	asset_id = definition.Id,
	manifest_duration = definition.Duration,
	checks = {},
	crickets = {},
	asset_messages = {},
	method = "Five actual isolated production RoundAudio Sounds; wall-clock Step at approximately 10Hz, real IsLoaded/TimeLength/TimePosition/Volume and Played/Ended/Stopped events. No preload or forged playback state. Original 0/6/12/18/24 offsets checked, then only fixture offsets aligned to zero for one bounded slot. Server decoder/presentation evidence; no client/human audibility, mix, ordinary round or multiplayer claim.",
}
local scratch, audio, worker, watchdog
local connections, monitors = {}, {}
local finished = false
local function publish()
	report.elapsed_sec = os.clock() - began
	result.Value = HttpService:JSONEncode(report)
end
local function fetchStatus()
	local ok, status = pcall(function()
		return ContentProvider:GetAssetFetchStatus(definition.Id)
	end)
	return if ok then tostring(status) else "unavailable: " .. tostring(status)
end
local function finish(status, problem)
	if finished then
		return
	end
	finished = true
	-- Disconnect playback observations before permitted terminal cleanup.
	for _, connection in connections do
		connection:Disconnect()
	end
	local created = {}
	if audio then
		for _, item in audio.created do
			table.insert(created, item)
		end
	end
	local cleanupProblems = {}
	if audio then
		local ok, failure = pcall(function()
			audio:Destroy()
		end)
		if not ok then
			table.insert(cleanupProblems, tostring(failure))
		end
	end
	-- All references here belong to this fixture, including external groups.
	for _, item in created do
		if item.Parent then
			local ok, failure = pcall(function()
				item:Destroy()
			end)
			if not ok then
				table.insert(cleanupProblems, tostring(failure))
			end
		end
	end
	if scratch then
		-- Cover a partially failed constructor's external SoundService folder.
		local runtime = scratch:FindFirstChild("CornRoundRuntime")
		if runtime then
			for _, item in runtime:GetChildren() do
				if item:GetAttribute("audio_role") == "runtime" then
					local groups = game:GetService("SoundService"):FindFirstChild(item.Name)
					if
						groups
						and groups:GetAttribute("CornAudioOwned") == true
						and groups:GetAttribute("corn_project_id") == "children_of_corn"
					then
						groups:Destroy()
					end
				end
			end
		end
		scratch:Destroy()
	end
	local remaining = false
	for _, item in created do
		remaining = remaining or item.Parent ~= nil
	end
	report.cleanup = #cleanupProblems == 0
		and not remaining
		and (not scratch or scratch.Parent == nil)
	report.cleanup_problems = cleanupProblems
	report.fetch_status = fetchStatus()
	report.done, report.status, report.problem = true, status, problem
	report.passed = status == "passed" and report.cleanup
	publish()
	print("CRICKET_FADES " .. status .. " " .. result.Name)
	if watchdog and watchdog ~= coroutine.running() then
		pcall(task.cancel, watchdog)
	end
end
local function blocked(reason)
	error({ status = "blocked", reason = reason }, 0)
end
table.insert(
	connections,
	LogService.MessageOut:Connect(function(message, kind)
		if string.find(message, assetNumber, 1, true) and #report.asset_messages < 8 then
			table.insert(report.asset_messages, { message = message, kind = tostring(kind) })
		end
	end)
)
publish()
watchdog = task.delay(20, function()
	finish("blocked", "20-second watchdog: incomplete decoder/fade/natural-End observation")
	if worker and coroutine.status(worker) ~= "dead" then
		pcall(task.cancel, worker)
	end
end)
worker = task.spawn(function()
	local ok, failure = xpcall(function()
		scratch = Instance.new("Model")
		scratch.Name = "CornCricketFadesScratch_" .. guid
		scratch:SetAttribute("corn_test_owned", true)
		scratch:SetAttribute("corn_project_id", "children_of_corn")
		scratch.Parent = workspace
		local function part(name, size, position, collide)
			local item = Instance.new("Part")
			item.Name, item.Size, item.Position = name, size, position
			item.Anchored, item.Transparency = true, 1
			item.CanCollide, item.CanQuery, item.CanTouch = collide == true, collide == true, false
			item.CastShadow = false
			item.Parent = scratch
			return item
		end
		local ground = part("Ground", Vector3.new(240, 2, 240), Vector3.new(0, 500, 0), true)
		local field = part("FieldZone", Vector3.new(240, 10, 240), Vector3.new(0, 506, 0))
		local runtime = Instance.new("Folder")
		runtime.Name, runtime.Parent = "CornRoundRuntime", scratch
		audio = Audio.new(
			{ Root = scratch, Field = field, Ground = ground, Runtime = runtime },
			nil,
			nil
		)
		-- Keep the production Step, cricket implementation, groups and Sounds;
		-- only this instance's unrelated live-avatar discovery is isolated.
		audio._players = function() end
		assert(
			#audio.crickets == 5 and #audio.fires == 0 and #audio.voices == 0,
			"Expected five isolated crickets without torches or monsters"
		)
		local emitters = {}
		for index, entry in audio.crickets do
			local sound, emitter = entry.sound, entry.sound.Parent
			assert(entry.offset == (index - 1) * 6, "Original stagger offsets changed")
			assert(
				emitter:IsA("BasePart") and emitter:HasTag("corn_audio_emitter"),
				"Owned spatial emitter required"
			)
			assert(
				not emitters[emitter] and emitter:IsDescendantOf(runtime),
				"Distinct spatial emitters"
			)
			emitters[emitter] = true
			assert(
				sound.SoundId == definition.Id and not sound.Looped and sound.PlaybackSpeed == 1,
				"Unmodified nonlooped author cricket required"
			)
			assert(
				sound.Volume == 0 and sound.RollOffMaxDistance == Rules.Ranges.Crickets.Max,
				"Silent startup and production spatial range required"
			)
			assert(
				sound.SoundGroup == audio.groups.Ambience and audio.groups.Ambience.Volume > 0,
				"Production Ambience group must have nonzero gain"
			)
			local trace = {
				index = index,
				original_offset = entry.offset,
				gain = entry.gain,
				loaded_before_play = sound.IsLoaded,
				played = 0,
				ended = 0,
				stopped = 0,
				uri_changes = 0,
				max_position = 0,
				max_volume = 0,
				samples = {}, -- {wall seconds, TimePosition, Volume, IsPlaying}
			}
			table.insert(report.crickets, trace)
			table.insert(monitors, { sound = sound, trace = trace })
			local function time()
				return os.clock() - began
			end
			table.insert(
				connections,
				sound.Played:Connect(function()
					trace.played += 1
					trace.played_at = time()
					trace.start_volume = sound.Volume
				end)
			)
			table.insert(
				connections,
				sound.Ended:Connect(function()
					trace.ended += 1
					trace.ended_at = time()
				end)
			)
			table.insert(
				connections,
				sound.Stopped:Connect(function()
					trace.stopped += 1
				end)
			)
			table.insert(
				connections,
				sound:GetPropertyChangedSignal("SoundId"):Connect(function()
					trace.uri_changes += 1
				end)
			)
			entry.offset = 0
		end
		report.checks.five_distinct_spatial_nonlooped_sounds_original_offsets_and_nonzero_group =
			true
		local slotStarted = os.clock()
		audio.startedAt = slotStarted
		report.slot_started_at = slotStarted - began
		local nextPublish = 0
		while os.clock() - slotStarted < 17 do
			local now = os.clock()
			local elapsed = now - slotStarted
			audio:Step(now, "caught", "easy", nil)
			for _, monitor in monitors do
				local sound, trace = monitor.sound, monitor.trace
				local volume, position = sound.Volume, sound.TimePosition
				trace.loaded, trace.length = sound.IsLoaded, sound.TimeLength
				trace.max_position = math.max(trace.max_position, position)
				trace.max_volume = math.max(trace.max_volume, volume)
				trace.final_playing = sound.IsPlaying
				trace.final_volume = volume
				table.insert(trace.samples, { now - began, position, volume, sound.IsPlaying })
				assert(volume >= 0 and volume <= trace.gain + 0.00001, "Cricket gain bounds")
				if
					sound.IsLoaded
					and sound.IsPlaying
					and position > 0
					and not trace.progress_at
				then
					trace.progress_at, trace.first_progress_volume = now - began, volume
				end
				local ratio = volume / trace.gain
				if elapsed < 3 and sound.IsPlaying and position > 0 then
					if ratio > 0 and ratio <= 0.4 and not trace.rise_low_at then
						trace.rise_low_at = now - began
					elseif ratio > 0.4 and ratio < 0.85 and not trace.rise_mid_at then
						trace.rise_mid_at = now - began
					elseif ratio >= 0.9 and not trace.rise_high_at then
						trace.rise_high_at = now - began
					end
				end
				if elapsed > 12 and elapsed < 14 and ratio >= 0.9 then
					trace.late_plateau = true
				end
				if elapsed >= 13 and sound.IsPlaying and ratio > 0.15 and ratio < 0.8 then
					trace.fall_mid_at = trace.fall_mid_at or now - began
				end
				if trace.fall_mid_at and ratio <= 0.15 then
					trace.fall_low_at = trace.fall_low_at or now - began
				end
				if elapsed >= 15 then
					assert(volume == 0, "Normal off must remain silent")
					assert(sound:GetAttribute("AudioRequestedPlaying") == false, "Off intent")
					trace.off_observed = true
				end
			end
			if elapsed >= nextPublish then
				nextPublish = elapsed + 1
				publish()
			end
			task.wait(0.1)
		end
		local unavailable = {}
		for _, monitor in monitors do
			local sound, trace = monitor.sound, monitor.trace
			trace.loaded, trace.length = sound.IsLoaded, sound.TimeLength
			if not trace.loaded or trace.length <= 0 then
				table.insert(unavailable, trace.index)
			end
		end
		if #unavailable > 0 then
			report.unavailable_emitters = unavailable
			blocked(
				"Author cricket decoder unavailable: "
					.. definition.Id
					.. "; see asset_messages/fetch_status and individual IsLoaded/length. No playback acceptance."
			)
		end
		report.checks.all_five_real_decoders_loaded = true
		for _, monitor in monitors do
			local trace = monitor.trace
			if not trace.progress_at then
				blocked(
					"Cricket "
						.. trace.index
						.. " decoded but no actual TimePosition progress in the bounded start slot"
				)
			end
			if
				not trace.rise_high_at
				and trace.progress_at > report.slot_started_at + Rules.CricketStartWindow + 0.15
			then
				blocked(
					"Cricket "
						.. trace.index
						.. " first actual decoder progress arrived after the bounded startup window; no fade/playback acceptance."
				)
			end
			assert(
				trace.played == 1 and trace.start_volume == 0,
				"Exactly one silent production Play"
			)
			assert(
				trace.stopped == 0 and trace.uri_changes == 0,
				"No ordinary Stop or URI replacement"
			)
			assert(
				trace.rise_low_at and trace.rise_mid_at and trace.rise_high_at,
				"Observed low/mid/full fade-in"
			)
			assert(
				trace.rise_low_at < trace.rise_mid_at and trace.rise_mid_at < trace.rise_high_at,
				"Fade-in order"
			)
			assert(
				trace.late_plateau and trace.fall_mid_at and trace.fall_low_at,
				"Observed plateau/mid/low fade-out"
			)
			assert(
				trace.fall_mid_at < trace.fall_low_at and trace.fall_low_at > trace.rise_high_at,
				"Fade-out order"
			)
			assert(trace.ended == 1 and trace.ended_at, "Exactly one natural Ended")
			assert(
				trace.ended_at - trace.played_at >= trace.length - 0.3,
				"Decoded clip was not shortened"
			)
			assert(trace.max_position >= trace.length * 0.85, "Real position traversed the clip")
			assert(
				trace.off_observed and not trace.final_playing and trace.final_volume == 0,
				"Quiet off after natural completion"
			)
		end
		report.checks.five_actual_fade_ins_and_fade_outs = true
		report.checks.five_natural_ends_no_ordinary_stops_no_replays_no_uri_changes = true
	end, function(problem)
		return if type(problem) == "table" then problem else debug.traceback(tostring(problem), 2)
	end)
	if ok then
		finish("passed")
	elseif type(failure) == "table" then
		finish(failure.status, failure.reason)
	else
		finish("failed", failure)
	end
end)
return {
	status = "started",
	report_name = result.Name,
	fixture_id = guid,
	deadline_seconds = 20,
	read = "Poll ReplicatedStorage[report_name].Value JSON until done=true; retain evidence, then remove this report value.",
}
