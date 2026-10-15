-- Verified Children_of_corn Studio CLIENT during Play. Real current controller,
-- author decoder and local Sound.Ended. Controlled server-commit inputs on an
-- isolated actor; no remote, live avatar/NPC/audio/camera or saved-world edits.
-- Async job returns a LOCAL ReplicatedStorage report handle, <=35 seconds.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
assert(
	RunService:IsStudio() and RunService:IsRunning() and RunService:IsClient(),
	"Studio Play Client required"
)
local player = assert(Players.LocalPlayer, "Client owner required")
local map = assert(workspace:FindFirstChild("CornMap"), "Verified CornMap required")
assert(map:GetAttribute("corn_project_id") == "children_of_corn", "Wrong project")
local playerRoot = assert(
	player.Character and player.Character:FindFirstChild("HumanoidRootPart"),
	"Living client character required"
)
local Module = require(player.PlayerScripts.GameClient.Controllers.AudioController)
local Assets = require(ReplicatedStorage.GameShared.Game.AudioAssets)
local Rules = require(ReplicatedStorage.GameShared.Game.AudioRules)
local guid = HttpService:GenerateGUID(false)
local result = Instance.new("StringValue")
result.Name = "CornRustleClientPlaybackReport_" .. guid
result:SetAttribute("corn_test_owned", true)
result.Parent = ReplicatedStorage
local began, deadline = os.clock(), os.clock() + 35
local report = {
	done = false,
	passed = false,
	status = "running",
	checks = {},
	assets = {},
	clips = {},
	events = {},
	fixture_id = guid,
	method = "Real current AudioController/author local Sound decoder and natural Ended; controlled accepted server metadata in an isolated client actor. No server-network timing, physical walking, human mix, multiplayer or ordinary-round claim.",
}
local controller, fixture, preloadThread, worker, watchdog, fixtureSource
local fixtureVoices = {}
local fixtureExpectedVolume = 0.38
local connections = {}
local ended, played, stopped = 0, 0, 0
local finished = false
local function publish()
	report.elapsed_sec = os.clock() - began
	result.Value = HttpService:JSONEncode(report)
end
local function finish(status, problem)
	if finished then
		return
	end
	finished = true
	for _, connection in connections do
		connection:Disconnect()
	end
	if preloadThread and coroutine.status(preloadThread) ~= "dead" then
		pcall(task.cancel, preloadThread)
	end
	local okController, problemController = pcall(function()
		if controller then
			controller:Destroy()
		end
	end)
	local gainRestored = not fixtureSource
		or math.abs(fixtureSource.Volume - fixtureExpectedVolume) < 0.00001
	report.cleanup_source_gain_restored = gainRestored
	local okFixture, problemFixture = pcall(function()
		if fixture then
			fixture:Destroy()
		end
	end)
	local voiceCleanup = true
	for _, sound in fixtureVoices do
		voiceCleanup = voiceCleanup and sound.Parent == nil
	end
	report.cleanup_local_voices = voiceCleanup
	report.cleanup_actor_count = if controller then controller._rustleCount else 0
	report.cleanup = okController
		and okFixture
		and voiceCleanup
		and gainRestored
		and (not controller or controller._rustleCount == 0)
		and (not fixture or fixture.Parent == nil)
	report.cleanup_problems = { tostring(problemController or ""), tostring(problemFixture or "") }
	report.done, report.status, report.problem = true, status, problem
	report.passed = status == "passed" and report.cleanup
	report.natural_ended_count, report.played_count, report.unexpected_stopped =
		ended, played, stopped
	publish()
	if watchdog and watchdog ~= coroutine.running() then
		pcall(task.cancel, watchdog)
	end
end
local function expect(condition, reason)
	assert(condition, reason or "Client rustle playback acceptance failed")
end
local function blocked(reason)
	error({ status = "blocked", reason = reason }, 0)
end
publish()
watchdog = task.delay(35, function()
	finish("blocked", "35-second watchdog expired; incomplete playback not accepted")
	if worker and coroutine.status(worker) ~= "dead" then
		pcall(task.cancel, worker)
	end
end)
worker = task.spawn(function()
	local ok, failure = xpcall(function()
		fixture = Instance.new("Model")
		fixture.Name = "CornRustleClientPlaybackScratch_" .. guid
		fixture:SetAttribute("corn_test_owned", true)
		fixture.Parent = workspace
		local root = Instance.new("Part")
		root.Name, root.Size = "HumanoidRootPart", Vector3.one
		root.Anchored, root.Transparency, root.CanCollide, root.CanQuery, root.CanTouch =
			true, 1, false, false, false
		root.Position = playerRoot.Position + Vector3.new(5, 0, 0)
		root.Parent = fixture
		local humanoid = Instance.new("Humanoid")
		humanoid.RequiresNeck = false
		humanoid.Parent = fixture
		local preloadSounds, failures, preloadDone, preloadProblem = {}, {}, false, nil
		for _, key in Rules.CornKeys do
			local sound = Instance.new("Sound")
			sound.SoundId, sound.Volume = Assets.Get(key).Id, 0
			sound.Parent = fixture
			preloadSounds[key] = sound
		end
		preloadThread = task.spawn(function()
			local preloadOk, preloadError = pcall(function()
				local sounds = {}
				for _, sound in preloadSounds do
					table.insert(sounds, sound)
				end
				ContentProvider:PreloadAsync(sounds, function(uri, status)
					if status ~= Enum.AssetFetchStatus.Success then
						failures[uri] = tostring(status)
					end
				end)
			end)
			preloadDone = true
			if not preloadOk then
				preloadProblem = tostring(preloadError)
			end
		end)
		local loadDeadline = os.clock() + 8
		while not preloadDone and os.clock() < loadDeadline do
			task.wait(0.05)
		end
		local loaded = 0
		for _, key in Rules.CornKeys do
			local sound = preloadSounds[key]
			report.assets[key] =
				{ id = sound.SoundId, loaded = sound.IsLoaded, length = sound.TimeLength }
			if sound.IsLoaded and sound.TimeLength > 0 then
				loaded += 1
			end
		end
		report.preload = {
			done = preloadDone,
			loaded_count = loaded,
			failures = failures,
			problem = preloadProblem,
		}
		publish()
		if not preloadDone or preloadProblem or next(failures) or loaded ~= 6 then
			blocked("Six actual author corn decoders unavailable; see preload/assets")
		end
		for _, sound in preloadSounds do
			sound:Destroy()
		end
		controller = setmetatable({}, { __index = Module })
		controller:Init({})
		controller._folderName = "CornPersonalRustleFixture_" .. guid
		expect(controller:_build(), "Owned fixture Effects group required")
		controller._snapshot = { phase = "active" }
		controller._footstepPlayers[{}] = {
			root = root,
			character = fixture,
			connections = {},
			rootConnections = {},
			characterConnections = {},
			sounds = {},
		}
		controller._resolveMonster = function(self)
			self._monster, self._monsterRoot = nil, nil
			self._monsters = {}
		end
		local source = Instance.new("Sound")
		fixtureSource = source
		source.Name, source.SoundId, source.Volume =
			"CornAudio_corn_rustle", Assets.Get("COC_Corn_13").Id, 0.38
		source:SetAttribute("CornAudioOwned", true)
		source:SetAttribute("corn_project_id", "children_of_corn")
		source:SetAttribute("audio_role", "corn_rustle")
		source:SetAttribute("AudioRustleId", 0)
		source:SetAttribute("AudioRustleStart", "")
		source:SetAttribute("AudioRequestedPlaying", false)
		source.Parent = root
		controller:_refreshRustle(root)
		local entry = assert(controller._rustles[root], "Fixture actor must bind")
		expect(#entry.voices == 2 and entry.voices[1] == entry, "Exactly two local voices required")
		local trackers = {}
		local violation, stage = nil, "initial"
		local maximumActive, maximumPending, seq = 0, 0, 0
		local function event(kind, tracker)
			local sound = tracker.sound
			if #report.events < 200 then
				table.insert(report.events, {
					event = kind,
					voice = tracker.index,
					at = os.clock() - began,
					stage = stage,
					id = sound.SoundId,
					sequence = sound:GetAttribute("AudioRustleId"),
					key = sound:GetAttribute("AudioAssetKey"),
					position = sound.TimePosition,
				})
			end
		end
		for index, voice in entry.voices do
			local sound = voice.sound
			fixtureVoices[index] = sound
			expect(
				sound.Name == (if index == 1 then "CornLocalRustle" else "CornLocalRustle2"),
				"Fixed voice names required"
			)
			local tracker = { index = index, sound = sound, played = 0, ended = 0 }
			trackers[index] = tracker
			table.insert(
				connections,
				sound.Played:Connect(function()
					local previous = tracker.current
					if previous and not previous.ended_at then
						violation = "Play replaced this voice before its own natural Ended"
					end
					played += 1
					tracker.played += 1
					tracker.current = {
						voice = index,
						id = sound.SoundId,
						sequence = sound:GetAttribute("AudioRustleId"),
						key = sound:GetAttribute("AudioAssetKey"),
						started_at = os.clock() - began,
						length = sound.TimeLength,
						max_position = 0,
						max_loudness = 0,
						stage = stage,
					}
					table.insert(report.clips, tracker.current)
					event("Played", tracker)
				end)
			)
			table.insert(
				connections,
				sound.Ended:Connect(function()
					local current = tracker.current
					if not current or current.ended_at then
						violation = "Ended without one current clip on this voice"
					else
						if sound.TimeLength > 0 then
							current.length = sound.TimeLength
						end
						current.ended_at = os.clock() - began
						current.elapsed_sec = current.ended_at - current.started_at
						if current.id ~= sound.SoundId then
							violation = "Voice URI replaced before its own natural Ended"
						end
					end
					ended += 1
					tracker.ended += 1
					event("Ended", tracker)
				end)
			)
			table.insert(
				connections,
				sound.Stopped:Connect(function()
					stopped += 1
					violation = "Stopped during full-tail acceptance"
					event("Stopped", tracker)
				end)
			)
			table.insert(
				connections,
				sound:GetPropertyChangedSignal("SoundId"):Connect(function()
					if tracker.current and not tracker.current.ended_at then
						violation = "URI changed while this voice had no natural Ended"
					end
					event("SoundId", tracker)
				end)
			)
		end
		local function commit(key)
			seq += 1
			source.SoundId = Assets.Get(key).Id
			fixtureExpectedVolume = math.clamp(Rules.Volume.Rustle * Assets.Get(key).Gain, 0, 1)
			source.Volume = fixtureExpectedVolume
			source:SetAttribute("AudioRequestedPlaying", true)
			source:SetAttribute("AudioRustleId", seq)
			source:SetAttribute("AudioRustleStart", tostring(seq) .. ":" .. key)
			return seq
		end
		local followAt = 0
		local function pump(seconds)
			local untilWall = os.clock() + seconds
			repeat
				expect(not finished and os.clock() < deadline, "Fixture deadline")
				expect(not violation, violation)
				if os.clock() >= followAt then
					followAt = os.clock() + 0.1
					local character = player.Character
					local listenerRoot = character and character:FindFirstChild("HumanoidRootPart")
					if listenerRoot and listenerRoot:IsA("BasePart") then
						-- Only the owned, non-interactive scratch emitter follows.
						-- Parallel native walking must not turn distance mute into
						-- a false decoder/loudness failure after leaving this point.
						root.Position = listenerRoot.Position + Vector3.new(5, 0, 0)
					end
				end
				controller:_stepRustles(os.clock())
				local active = 0
				for _, tracker in trackers do
					local sound, current = tracker.sound, tracker.current
					if sound.IsPlaying then
						active += 1
					end
					if current and not current.ended_at then
						expect(current.id == sound.SoundId, "Active URI changed")
						if sound.TimeLength > 0 then
							current.length = sound.TimeLength
						end
						if
							sound.IsPlaying
							and sound.TimePosition > 0
							and not current.decoded_started_at
						then
							current.decoded_started_at = os.clock() - began
						end
						current.max_position = math.max(current.max_position, sound.TimePosition)
						current.max_loudness =
							math.max(current.max_loudness, sound.PlaybackLoudness)
					end
				end
				maximumActive = math.max(maximumActive, active)
				maximumPending = math.max(maximumPending, if entry.pending then 1 else 0)
				expect(active <= 2 and #entry.voices == 2, "Unbounded voice allocation")
				task.wait(math.min(0.02, math.max(0.001, untilWall - os.clock())))
			until os.clock() >= untilWall
		end
		local function waitFor(predicate)
			local untilWall = math.min(deadline, os.clock() + 5)
			while not predicate() and os.clock() < untilWall do
				pump(0.015)
			end
			if not predicate() then
				for _, tracker in trackers do
					if not tracker.sound.IsLoaded then
						blocked("Selected local author Sound never decoded")
					end
				end
			end
			expect(predicate(), "Real client Played/Ended was not observed")
		end
		local function idle()
			return not entry.voices[1].active and not entry.voices[2].active and not entry.pending
		end
		stage = "short_step_stop_tail"
		commit("COC_Corn_13")
		waitFor(function()
			return played == 1
		end)
		pump(0.15)
		source:SetAttribute("AudioRequestedPlaying", false)
		pump(0.2)
		expect(
			trackers[1].sound.IsPlaying and not trackers[1].current.ended_at,
			"Stopped intent must retain the actual short-step tail"
		)
		waitFor(function()
			return ended == 1 and idle()
		end)
		report.checks.short_step_stop_naturally_ended = true

		stage = "two_overlap_and_newest_pending"
		local beforeOverlap = played
		commit("COC_Corn_13")
		waitFor(function()
			return played == beforeOverlap + 1
		end)
		local firstClip = trackers[1].current
		pump(0.15)
		commit("COC_Corn_11")
		waitFor(function()
			return played == beforeOverlap + 2
		end)
		local secondClip = trackers[2].current
		waitFor(function()
			return trackers[1].sound.IsPlaying
				and trackers[2].sound.IsPlaying
				and trackers[1].sound.TimePosition > 0
				and trackers[2].sound.TimePosition > 0
		end)
		pump(0.001)
		expect(
			not firstClip.ended_at
				and not secondClip.ended_at
				and entry.voices[1].active
				and entry.voices[2].active,
			"Two real onsets must overlap before either natural Ended"
		)
		report.first_overlap = {
			first_voice = firstClip.voice,
			second_voice = secondClip.voice,
			onset_gap_sec = secondClip.started_at - firstClip.started_at,
			decoded_onset_gap_sec = secondClip.decoded_started_at - firstClip.decoded_started_at,
			first_length = firstClip.length,
			second_length = secondClip.length,
		}
		local newest
		for _, key in { "COC_Corn_02", "COC_Corn_18", "COC_Corn_20" } do
			newest = commit(key)
			-- Real Instance signal dispatch may be deferred. Observe every
			-- accepted pending replacement rather than assuming sync callbacks.
			waitFor(function()
				return entry.lastId == newest
			end)
			expect(
				entry.pending and entry.pending.id == newest and entry.pending.key == key,
				"Two busy voices must keep exactly newest pending"
			)
		end
		pump(0.1)
		expect(
			played == beforeOverlap + 2 and not firstClip.ended_at and not secondClip.ended_at,
			"Pending overload replaced an unfinished voice"
		)
		waitFor(function()
			return played == beforeOverlap + 3
		end)
		local newestClip = report.clips[#report.clips]
		expect(
			newestClip.sequence == newest and newestClip.key == "COC_Corn_20",
			"Superseded pending history was played"
		)
		local reused = if newestClip.voice == 1 then firstClip else secondClip
		expect(
			reused.ended_at and newestClip.started_at >= reused.ended_at,
			"Voice reuse must follow that voice's own Ended"
		)
		waitFor(function()
			return idle() and ended == played
		end)
		pump(0.1)
		expect(
			played == beforeOverlap + 3 and stopped == 0,
			"Overload retained hidden queue history"
		)
		report.checks.two_real_onsets_before_first_end = true
		report.checks.newest_pending_only_after_own_ended = true

		-- Exact 120 logical polls at 10 Hz. These are controlled accepted commits,
		-- not an assertion of server movement/ground/corn eligibility or network timing.
		stage = "twelve_second_ten_hz_cadence"
		local routeKeys = { "COC_Corn_10", "COC_Corn_02" }
		local function scheduledCount(previous)
			local count, nextAt = 0, 0
			for tick = 1, 120 do
				local now = tick / 10
				if now >= nextAt then
					local key = routeKeys[count % #routeKeys + 1]
					count += 1
					local duration = Assets.Get(key).Duration
					local interval = if previous
						then math.max(0.45, duration)
						else math.max(0.225, duration / 2)
					local anchor = if not previous and count > 1
						then math.max(nextAt, now - 0.1)
						else now
					nextAt = anchor + interval
				end
			end
			return count
		end
		local routeBegan, routeFirstClip, routeCount, nextAt = os.clock(), #report.clips + 1, 0, 0
		local firstRouteSequence, maximumPollLateness, acceptedCues = seq, 0, 0
		local cueTimes = {}
		for tick = 1, 120 do
			local tickAt = routeBegan + tick / 10
			if os.clock() < tickAt then
				pump(tickAt - os.clock())
			end
			local now = os.clock() - routeBegan
			maximumPollLateness = math.max(maximumPollLateness, now - tick / 10)
			if now >= nextAt then
				local key = routeKeys[routeCount % #routeKeys + 1]
				local anchor = if routeCount > 0 then math.max(nextAt, now - 0.1) else now
				routeCount += 1
				local cue = commit(key)
				waitFor(function()
					return entry.lastId == cue
				end)
				acceptedCues += 1
				table.insert(cueTimes, now)
				nextAt = anchor + math.max(Rules.RustleInterval, Assets.Get(key).Duration / 2)
			end
		end
		source:SetAttribute("AudioRequestedPlaying", false)
		report.route = {
			logical_polls = 120,
			poll_hz = 10,
			wall_sec = os.clock() - routeBegan,
			committed_cues = routeCount,
			accepted_cues = acceptedCues,
			accepted_sequence_advance = entry.lastId - firstRouteSequence,
			cue_times_sec = cueTimes,
			maximum_poll_lateness_sec = maximumPollLateness,
			method = "Real elapsed 10 Hz polls; nextDeadline=max(previousDeadline,now-0.1)+max(0.225,duration/2); no burst catch-up",
			expected_cues = scheduledCount(false),
			expected_previous_formula = scheduledCount(true),
		}
		expect(
			report.route.accepted_cues == report.route.expected_cues
				and routeCount == report.route.accepted_cues
				and routeCount > report.route.expected_previous_formula,
			"Controlled twelve-second cadence did not exceed prior formula"
		)
		waitFor(function()
			return idle() and ended == played
		end)
		local routeStarts, routeGaps, lastAt = { 0, 0 }, {}, nil
		for index = routeFirstClip, #report.clips do
			local clip = report.clips[index]
			routeStarts[clip.voice] += 1
			if lastAt then
				table.insert(routeGaps, clip.started_at - lastAt)
			end
			lastAt = clip.started_at
		end
		report.route.onsets_by_voice, report.route.onset_gaps_sec = routeStarts, routeGaps
		report.route.local_started = routeStarts[1] + routeStarts[2]
		report.route.local_ended = 0
		for index = routeFirstClip, #report.clips do
			if report.clips[index].ended_at then
				report.route.local_ended += 1
			end
		end
		report.route.accepted_rate_ratio = routeCount / report.route.expected_previous_formula
		expect(
			report.route.expected_previous_formula == 18 and report.route.expected_cues == 36,
			"Alternating 0.44/0.89-second route formula drifted"
		)
		expect(
			report.route.local_ended == report.route.local_started
				and report.route.local_started <= report.route.accepted_cues,
			"Route left a started tail incomplete"
		)
		expect(
			routeStarts[1] > 0 and routeStarts[2] > 0,
			"Cadence must exercise both actual voices"
		)
		report.checks.twelve_second_10hz_controlled_cadence = true
		for _, clip in report.clips do
			expect(
				clip.ended_at and clip.length > 0 and clip.elapsed_sec >= clip.length - 0.18,
				"Every started clip requires its full decoded duration and natural Ended"
			)
			expect(
				clip.max_position >= clip.length * 0.9 - 0.05,
				"TimePosition must traverse actual client clip"
			)
			expect(clip.max_loudness > 0, "Actual client PlaybackLoudness must be nonzero")
		end
		report.checks.every_clip_real_ended_position_loudness_no_stop = true
		report.checks.two_local_sounds_per_actor = root:FindFirstChild("CornLocalRustle")
				== trackers[1].sound
			and root:FindFirstChild("CornLocalRustle2") == trackers[2].sound
			and controller._rustleCount == 1
		report.maximum_active_voices, report.maximum_pending = maximumActive, maximumPending
		report.voices = {}
		for index, tracker in trackers do
			report.voices[index] = {
				name = tracker.sound.Name,
				played = tracker.played,
				natural_ended = tracker.ended,
			}
		end
		expect(
			report.checks.two_local_sounds_per_actor and maximumActive == 2 and maximumPending == 1
		)
	end, function(problem)
		return if type(problem) == "table"
			then problem
			else {
				status = "failed",
				reason = tostring(problem),
				traceback = debug.traceback(),
			}
	end)
	if ok then
		finish("passed")
	else
		report.traceback = failure.traceback
		finish(failure.status or "failed", failure.reason)
	end
end)
return HttpService:JSONEncode({
	started = true,
	report_name = result.Name,
	report_parent = "ReplicatedStorage (CLIENT-local)",
	fixture_id = guid,
	max_seconds = 35,
})
