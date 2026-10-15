-- Run only on the verified Children_of_corn Studio Server during Play.
-- This starts an asynchronous, <=40-second REAL decoder/playback fixture.
-- Read the returned ReplicatedStorage StringValue until done=true, then retain
-- its JSON as evidence and remove that report value. No Play intent fake PASS.
-- Client TimePosition/Loudness and human audibility need a separate observer.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local HttpService = game:GetService("HttpService")
assert(
	RunService:IsStudio() and RunService:IsRunning() and RunService:IsServer(),
	"Studio Play Server required"
)
local map = assert(workspace:FindFirstChild("CornMap"), "Verified CornMap required")
assert(map:GetAttribute("corn_project_id") == "children_of_corn", "Wrong project")
local owner = assert(game:GetService("Players"):GetPlayers()[1], "Play owner required")
local character = assert(owner.Character, "Live character required")
local ownerRoot =
	assert(character:FindFirstChild("HumanoidRootPart"), "Live character root required")
assert(ownerRoot:IsA("BasePart"), "Character root must be a BasePart")

local id = HttpService:GenerateGUID(false)
local reportValue = Instance.new("StringValue")
reportValue.Name = "CornRustlePlaybackReport_" .. id
reportValue:SetAttribute("corn_test_owned", true)
reportValue:SetAttribute("FixtureId", id)
reportValue.Parent = ReplicatedStorage
local began = os.clock()
local deadline = began + 40
local report = {
	fixture_version = 1,
	fixture_id = id,
	done = false,
	passed = false,
	status = "running",
	checks = {},
	assets = {},
	scenarios = {},
	traces = {},
	method = "Actual server RoundAudio and author Sounds, wall clocks, natural Ended/Played/Stopped/URI traces. Synthetic anchored motion in an isolated world near the live player; no character, gameplay, Source or saved-world edits. Server playback only; no client/human audibility, physical walking, mix or multiplayer claim.",
}
local scratch, audio, preloadThread, workerThread, watchdogThread
local monitors = {}
local finished = false
local function publish()
	report.elapsed_sec = os.clock() - began
	reportValue.Value = HttpService:JSONEncode(report)
end
local function cleanup()
	for _, monitor in monitors do
		for _, connection in monitor.connections do
			connection:Disconnect()
		end
	end
	if preloadThread and coroutine.status(preloadThread) ~= "dead" then
		pcall(task.cancel, preloadThread)
	end
	local cleanupProblems = {}
	local created = {}
	if audio then
		for _, item in audio.created do
			table.insert(created, item)
		end
		local audioOk, audioProblem = pcall(function()
			audio:Destroy()
		end)
		if not audioOk then
			table.insert(cleanupProblems, tostring(audioProblem))
			-- All these instances belong to this isolated fixture. Continue
			-- cleanup even if one production Destroy operation failed.
			for _, item in created do
				pcall(function()
					item:Destroy()
				end)
			end
		end
	elseif scratch then
		-- A partially failed constructor can already have made its external
		-- SoundService group folder. Match only the unique name in OUR runtime.
		local runtime = scratch:FindFirstChild("CornRoundRuntime")
		if runtime then
			for _, item in runtime:GetChildren() do
				if
					item:GetAttribute("audio_role") == "runtime"
					and item:GetAttribute("CornAudioOwned") == true
				then
					local groups = game:GetService("SoundService"):FindFirstChild(item.Name)
					if groups and groups:GetAttribute("CornAudioOwned") == true then
						table.insert(created, groups)
						pcall(function()
							groups:Destroy()
						end)
					end
				end
			end
		end
	end
	if scratch then
		local scratchOk, scratchProblem = pcall(function()
			scratch:Destroy()
		end)
		if not scratchOk then
			table.insert(cleanupProblems, tostring(scratchProblem))
		end
	end
	local remaining = false
	for _, item in created do
		if item.Parent ~= nil then
			remaining = true
		end
	end
	report.cleanup = #cleanupProblems == 0
		and not remaining
		and (not scratch or scratch.Parent == nil)
	report.cleanup_problems = cleanupProblems
end
local function finish(status, problem)
	if finished then
		return
	end
	finished = true
	cleanup()
	report.status = status
	report.problem = problem
	report.done = true
	report.passed = status == "passed" and report.cleanup == true
	report.report_value_retained = true
	publish()
	if watchdogThread and watchdogThread ~= coroutine.running() then
		pcall(task.cancel, watchdogThread)
	end
end
local function blocked(reason)
	error({ kind = "blocked", reason = reason }, 0)
end
local function checkDeadline()
	if finished or os.clock() >= deadline then
		blocked("40-second fixture deadline; no completed playback acceptance")
	end
end
local function expect(condition, reason)
	assert(condition, reason)
end
publish()
watchdogThread = task.delay(40, function()
	finish("blocked", "40-second watchdog expired; incomplete playback was not accepted")
	if workerThread and coroutine.status(workerThread) ~= "dead" then
		pcall(task.cancel, workerThread)
	end
end)

workerThread = task.spawn(function()
	local ok, problem = xpcall(function()
		local Audio = require(game.ServerScriptService.GameServer.Game.RoundAudio)
		local Assets = require(ReplicatedStorage.GameShared.Game.AudioAssets)
		local Rules = require(ReplicatedStorage.GameShared.Game.AudioRules)
		expect(#Rules.CornKeys == 6, "Expected six current author corn clips")
		local center = ownerRoot.Position + Vector3.new(10, 0, 5)
		scratch = Instance.new("Model")
		scratch.Name = "CornRustlePlaybackScratch_" .. id
		scratch.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		scratch:SetAttribute("corn_test_owned", true)
		scratch:SetAttribute("corn_project_id", "children_of_corn")
		scratch:SetAttribute("FixtureId", id)
		scratch.Parent = workspace
		report.scratch_name = scratch.Name
		report.listener_distance_at_creation = (center - ownerRoot.Position).Magnitude
		reportValue:SetAttribute("ScratchName", scratch.Name)
		local function part(name, size, position)
			local item = Instance.new("Part")
			item.Name = name
			item.Size = size
			item.Position = position
			item.Anchored = true
			item.Transparency = 1
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
			item.CastShadow = false
			item.Parent = scratch
			return item
		end
		local ground = part("Ground", Vector3.new(120, 2, 120), center - Vector3.new(0, 4, 0))
		local field = part("FieldZone", Vector3.new(120, 10, 120), center + Vector3.new(0, 2, 0))
		local runtime = Instance.new("Folder")
		runtime.Name = "CornRoundRuntime"
		runtime.Parent = scratch
		local preloads = Instance.new("Folder")
		preloads.Name = "MutedAuthorPreloads"
		preloads.Parent = scratch
		local decodeSounds, failures = {}, {}
		for _, key in Rules.CornKeys do
			local definition = Assets.Get(key)
			expect(
				string.match(definition.Id, "^rbxassetid://%d+$") ~= nil,
				"Missing author corn ID: " .. key
			)
			local sound = Instance.new("Sound")
			sound.Name = key
			sound.SoundId = definition.Id
			sound.Volume = 0
			sound.Parent = preloads
			decodeSounds[key] = sound
		end
		local preloadDone, preloadError = false, nil
		preloadThread = task.spawn(function()
			local preloadOk, preloadProblem = pcall(function()
				local items = {}
				for _, sound in decodeSounds do
					table.insert(items, sound)
				end
				ContentProvider:PreloadAsync(items, function(uri, status)
					if status ~= Enum.AssetFetchStatus.Success then
						failures[uri] = tostring(status)
					end
				end)
			end)
			preloadDone = true
			if not preloadOk then
				preloadError = tostring(preloadProblem)
			end
		end)
		local loadDeadline = math.min(deadline, os.clock() + 8)
		while not preloadDone and os.clock() < loadDeadline do
			checkDeadline()
			task.wait(0.05)
		end
		local missing = {}
		for _, key in Rules.CornKeys do
			local sound = decodeSounds[key]
			report.assets[key] = {
				id = sound.SoundId,
				loaded = sound.IsLoaded,
				length = sound.TimeLength,
				manifest_duration = Assets.Get(key).Duration,
			}
			if not sound.IsLoaded or sound.TimeLength <= 0 then
				table.insert(missing, key)
			end
		end
		report.preload =
			{ done = preloadDone, error = preloadError, failures = failures, missing = missing }
		publish()
		if not preloadDone or preloadError or next(failures) or #missing > 0 then
			blocked(
				"Author corn preload/decoder unavailable; see preload/assets, not a playback PASS"
			)
		end
		report.checks.all_six_author_corn_assets_decoded = true
		preloads:Destroy()
		local npcRoot =
			part("NpcMotionEmitter", Vector3.new(3, 6, 2), center + Vector3.new(0, 0, 2))
		local stepRoot = part("StepMotionEmitter", Vector3.one, center - Vector3.new(0, 0, 2))
		local hunt = { root = npcRoot, state = "patrol", destroyed = false }
		local world = { Root = scratch, Field = field, Ground = ground, Runtime = runtime }
		audio = Audio.new(world, owner, hunt, Random.new(1187))
		-- Fixture-instance isolation only: integrated Step still runs the real
		-- NPC eligibility/state logic, without binding Sounds to live avatars.
		audio._players = function() end
		audio.groups.Ambience.Volume = 0
		audio.wakeSound.Volume = 0
		for _, sound in audio.voices do
			sound.Volume = 0
		end
		local stepActor = audio:_actor(stepRoot)
		local phase, stage = "active", "initial"
		local function now()
			return os.clock() - began
		end
		local function monitorSound(sound, label)
			local monitor = {
				sound = sound,
				plays = 0,
				ends = 0,
				stops = 0,
				uri_changes = 0,
				clips = {},
				events = {},
				violations = {},
				connections = {},
				allow_stop = false,
			}
			local function event(kind)
				if #monitor.events < 96 then
					table.insert(monitor.events, {
						kind = kind,
						at = now(),
						stage = stage,
						id = sound.SoundId,
						key = sound:GetAttribute("AudioAssetKey"),
						position = sound.TimePosition,
						loaded = sound.IsLoaded,
						length = sound.TimeLength,
						playing = sound.IsPlaying,
						requested = sound:GetAttribute("AudioRequestedPlaying"),
					})
				end
			end
			local function violation(reason)
				if #monitor.violations < 12 then
					table.insert(monitor.violations, reason)
				end
			end
			table.insert(
				monitor.connections,
				sound.Played:Connect(function()
					local previous = monitor.clips[#monitor.clips]
					if previous and not previous.ended_at then
						violation("New Play before previous natural Ended")
					end
					monitor.plays += 1
					table.insert(monitor.clips, {
						id = sound.SoundId,
						key = sound:GetAttribute("AudioAssetKey"),
						started_at = now(),
						length = sound.TimeLength,
						max_position = 0,
						stage = stage,
					})
					event("Played")
				end)
			)
			table.insert(
				monitor.connections,
				sound.Ended:Connect(function()
					local clip = monitor.clips[#monitor.clips]
					if not clip or clip.ended_at then
						violation("Ended without one active clip")
					else
						clip.ended_at = now()
						clip.elapsed_sec = clip.ended_at - clip.started_at
						if clip.id ~= sound.SoundId then
							violation("URI changed before Ended")
						end
						if clip.length <= 0 or clip.elapsed_sec < clip.length - 0.15 then
							violation("Natural Ended occurred before decoded duration")
						end
					end
					monitor.ends += 1
					event("Ended")
				end)
			)
			table.insert(
				monitor.connections,
				sound.Stopped:Connect(function()
					monitor.stops += 1
					if not monitor.allow_stop then
						violation("Stopped during a natural-tail scenario")
					end
					event("Stopped")
				end)
			)
			table.insert(
				monitor.connections,
				sound:GetPropertyChangedSignal("SoundId"):Connect(function()
					monitor.uri_changes += 1
					local clip = monitor.clips[#monitor.clips]
					if clip and not clip.ended_at and clip.id ~= sound.SoundId then
						violation("SoundId replaced before natural Ended")
					end
					event("SoundId")
				end)
			)
			-- The JSON report deliberately excludes runtime Instances/connections.
			report.traces[label] = {
				clips = monitor.clips,
				events = monitor.events,
				violations = monitor.violations,
			}
			table.insert(monitors, monitor)
			return monitor
		end
		local stepMonitor = monitorSound(stepActor.sound, "step_actor")
		local npcMonitor = monitorSound(audio.npc.sound, "npc_actor")
		local function sample()
			for _, monitor in monitors do
				local clip = monitor.clips[#monitor.clips]
				if clip and not clip.ended_at then
					clip.max_position = math.max(clip.max_position, monitor.sound.TimePosition)
				end
				expect(#monitor.violations == 0, table.concat(monitor.violations, "; "))
			end
		end
		local tickAt = 0
		local function pump(seconds, driver, move)
			local untilWall = os.clock() + seconds
			while os.clock() < untilWall do
				checkDeadline()
				if now() >= tickAt then
					tickAt = now() + 0.105
					if move then
						move()
					end
					driver()
				end
				sample()
				task.wait(0.02)
			end
			sample()
		end
		local function waitFor(predicate, timeout, driver, move)
			local untilWall = math.min(deadline, os.clock() + timeout)
			while not predicate() and os.clock() < untilWall do
				pump(0.025, driver, move)
			end
			if not predicate() then
				for _, monitor in monitors do
					if monitor.sound.SoundId ~= "" and not monitor.sound.IsLoaded then
						blocked("Selected real clip failed to load during playback")
					end
				end
				error("Timed out waiting for actual Played/Ended, not accepted as playback", 0)
			end
		end
		local stepEligible = true
		local function stepDriver()
			audio:_stepActor(stepActor, now(), stepEligible)
		end
		local function npcDriver()
			audio:Step(now(), phase, "easy", hunt)
		end
		-- Real Random, chosen deterministically to start the author's long clip.
		-- No Sound state or decoder duration is forged by the harness.
		local longIndex = assert(table.find(Rules.CornKeys, "COC_Corn_13"))
		local longSeed
		for seed = 1, 100 do
			if Random.new(seed):NextInteger(1, #Rules.CornKeys - 1) + 1 == longIndex then
				longSeed = seed
				break
			end
		end
		expect(longSeed ~= nil, "Could not select a deterministic real Random seed")
		local function beginClip(actor, monitor, driver)
			expect(
				not actor.sound.IsPlaying,
				"Previous clip must naturally finish before next scenario"
			)
			actor.lastClip = 0
			audio.random = Random.new(longSeed)
			pump(0.15, driver)
			local playsBefore = monitor.plays
			actor.root.Position += Vector3.new(0.6, 0, 0)
			waitFor(function()
				return monitor.plays == playsBefore + 1
			end, 1, driver)
			local clip = monitor.clips[#monitor.clips]
			expect(clip.key == "COC_Corn_13", "Expected real author long clip")
			if not actor.sound.IsLoaded or clip.length <= 0 then
				blocked("Selected author clip did not actually decode at Play")
			end
			expect(
				actor.sound.Looped == false and actor.sound.PlaybackSpeed == 1,
				"Natural unmodified one-shot required"
			)
			local duration = Assets.Get(clip.key).Duration
			expect(
				math.abs(
					actor.nextAt
						- (actor.untilAt - duration)
						- math.max(Rules.RustleInterval, duration / Rules.RustleVoices)
				) < 0.0001,
				"Half-duration metadata cadence with intact server player"
			)
			return clip, monitor.plays, monitor.uri_changes
		end
		local function finishTail(actor, monitor, clip, driver, move)
			waitFor(function()
				return clip.ended_at ~= nil
			end, math.max(clip.length, Assets.Get(clip.key).Duration) + 1.5, driver, move)
			expect(
				clip.max_position >= math.max(0.1, clip.length * 0.7),
				"TimePosition must advance through most of the real clip"
			)
			pump(0.25, driver, move)
			expect(
				not actor.sound.IsPlaying
					and actor.sound:GetAttribute("AudioRequestedPlaying") == false,
				"Natural tail settles without Stop"
			)
			expect(monitor.stops == 0, "No Stop in tail scenarios")
		end
		local function checkpoint(name, data)
			report.checks[name] = true
			report.scenarios[name] = data
			publish()
		end

		stage = "short_step_then_stop"
		local clip, plays, changes = beginClip(stepActor, stepMonitor, stepDriver)
		pump(0.18, stepDriver)
		expect(
			not clip.ended_at and stepActor.sound.IsPlaying,
			"Short step followed by stop must retain playing tail"
		)
		finishTail(stepActor, stepMonitor, clip, stepDriver)
		expect(
			stepMonitor.plays == plays and stepMonitor.uri_changes == changes,
			"Stop must not replay/replace clip"
		)
		checkpoint(stage, { natural_ended = true, plays = 1, stopped = 0 })

		stage = "resume_before_clip_end"
		clip, plays, changes = beginClip(stepActor, stepMonitor, stepDriver)
		pump(0.18, stepDriver)
		stepRoot.Position += Vector3.new(0.6, 0, 0)
		pump(0.25, stepDriver)
		expect(
			not clip.ended_at and stepActor.sound.IsPlaying,
			"Resume precondition: old real clip still plays"
		)
		expect(
			stepMonitor.plays == plays and stepMonitor.uri_changes == changes,
			"Resume must not cut or replace clip"
		)
		finishTail(stepActor, stepMonitor, clip, stepDriver)
		expect(stepMonitor.plays == plays, "One short resumed step must not queue another clip")
		checkpoint(stage, { natural_ended = true, same_clip_through_resume = true, stopped = 0 })

		stage = "continuous_motion_starts_only_after_ended"
		clip, plays = beginClip(stepActor, stepMonitor, stepDriver)
		local function movingStep()
			stepRoot.Position += Vector3.new(0.2, 0, 0)
		end
		local firstCue = stepActor.rustleId
		local firstUri = stepActor.sound.SoundId
		waitFor(function()
			return stepActor.rustleId > firstCue
		end, 1.7, stepDriver, movingStep)
		expect(
			not clip.ended_at and stepMonitor.plays == plays and stepActor.sound.SoundId == firstUri,
			"More frequent validated cue must arrive before the first Ended without rewriting server playback"
		)
		report.checks.half_cadence_cue_before_first_natural_end = true
		waitFor(function()
			return stepMonitor.plays >= plays + 2
		end, 7, stepDriver, movingStep)
		local last = stepMonitor.clips[#stepMonitor.clips]
		finishTail(stepActor, stepMonitor, last, stepDriver)
		expect(
			stepMonitor.plays == plays + 2,
			"Stopping continuous movement must not leave queued starts"
		)
		checkpoint(
			stage,
			{ consecutive_clips = 3, each_previous_naturally_ended = true, stopped = 0 }
		)

		local function npcTail(name, becomeIneligible, reset)
			stage = name
			phase, hunt.state = "active", "patrol"
			npcRoot.Position = Vector3.new(npcRoot.Position.X, center.Y, npcRoot.Position.Z)
			local npcClip, npcPlays, npcChanges = beginClip(audio.npc, npcMonitor, npcDriver)
			pump(0.18, npcDriver)
			becomeIneligible()
			local function movingNpc()
				npcRoot.Position += Vector3.new(0.2, 0, 0)
			end
			pump(0.22, npcDriver, movingNpc)
			expect(
				not npcClip.ended_at and audio.npc.sound.IsPlaying,
				"Ineligible NPC must keep its already-playing tail"
			)
			expect(
				npcMonitor.plays == npcPlays and npcMonitor.uri_changes == npcChanges,
				"Ineligibility must not replace current clip"
			)
			finishTail(audio.npc, npcMonitor, npcClip, npcDriver, movingNpc)
			expect(
				npcMonitor.plays == npcPlays,
				"Ineligible moving NPC must not start another clip"
			)
			checkpoint(
				name,
				{ natural_ended = true, no_new_start_while_ineligible = true, stopped = 0 }
			)
			reset()
		end
		npcTail("npc_airborne_ineligible_tail", function()
			npcRoot.Position += Vector3.new(0, 5, 0)
		end, function()
			npcRoot.Position -= Vector3.new(0, 5, 0)
		end)
		npcTail("npc_trapped_tail", function()
			hunt.state = "trapped"
		end, function()
			hunt.state = "patrol"
		end)
		npcTail("npc_caught_tail", function()
			phase, hunt.state = "caught", "capturing"
		end, function()
			phase, hunt.state = "active", "patrol"
		end)
		expect(
			#stepRoot:GetChildren() == 1 and stepRoot:GetChildren()[1] == stepActor.sound,
			"Step actor retains exactly one Sound"
		)
		local npcCornSounds = 0
		for _, child in npcRoot:GetChildren() do
			if child:IsA("Sound") and child:GetAttribute("audio_role") == "corn_rustle" then
				npcCornSounds += 1
			end
		end
		expect(npcCornSounds == 1, "NPC retains exactly one corn Sound")
		report.checks.one_sound_per_actor = true
		report.server_natural_ended_count = stepMonitor.ends + npcMonitor.ends
		report.server_clip_starts_before_terminal = stepMonitor.plays + npcMonitor.plays
		expect(
			stepMonitor.ends >= 5 and npcMonitor.ends >= 3,
			"At least eight real natural Ended events are required"
		)
		expect(
			stepMonitor.plays == stepMonitor.ends and npcMonitor.plays == npcMonitor.ends,
			"Every pre-terminal actual clip start must have a matching natural Ended"
		)
		report.checks.every_preterminal_start_has_natural_ended = true
		stage = "terminal_cleanup_exception"
		beginClip(audio.npc, npcMonitor, npcDriver)
		pump(0.12, npcDriver)
		expect(audio.npc.sound.IsPlaying, "Terminal cleanup exception starts with actual playback")
		for _, monitor in monitors do
			monitor.allow_stop = true
		end
		audio:Step(now(), "escaped", "easy", hunt)
		task.wait(0.05)
		expect(
			audio.destroyed and #audio.created == 0 and npcMonitor.sound.Parent == nil,
			"Terminal must remove all owned audio immediately"
		)
		report.checks.terminal_cleanup_exception = true
		report.scenarios.terminal_cleanup_exception =
			{ cleanup_allowed_to_interrupt = true, audio_removed = true }
		report.checks.zero_unexpected_stops_or_mid_clip_uri_replacements = true
		report.client_playback_accepted = false
		report.human_audibility_accepted = false
	end, function(failure)
		if type(failure) == "table" and failure.kind then
			return failure
		end
		return { kind = "failed", reason = tostring(failure), traceback = debug.traceback() }
	end)
	if ok then
		finish("passed")
	else
		report.failure_traceback = problem.traceback
		finish(problem.kind or "failed", problem.reason or tostring(problem))
	end
end)

return HttpService:JSONEncode({
	started = true,
	fixture_id = id,
	report_name = reportValue.Name,
	report_parent = "ReplicatedStorage",
	max_seconds = 40,
	read = "JSONDecode(game.ReplicatedStorage[report_name].Value); await done=true, retain JSON, then Destroy only this report StringValue",
})
