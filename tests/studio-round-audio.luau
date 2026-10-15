-- Real engine geometry and Sounds; deterministic scheduler clock, isolated fixture.
-- AudioRequestedPlaying is intent only. Loaded/playback acceptance is a separate test.
local Audio = require(game.ServerScriptService.GameServer.Game.RoundAudio)
local Assets = require(game.ReplicatedStorage.GameShared.Game.AudioAssets)
local Rules = require(game.ReplicatedStorage.GameShared.Game.AudioRules)
local owner = assert(game.Players:GetPlayers()[1], "Play owner required")
local scratch = Instance.new("Model")
scratch.Name = "RoundAudioAcceptanceScratch"
scratch:SetAttribute("corn_project_id", "children_of_corn")
scratch.Parent = workspace
local audio
local checks = {}
local function part(name, size, frame, parent, collision)
	local item = Instance.new("Part")
	item.Name = name
	item.Size = size
	item.CFrame = frame
	item.Anchored = true
	item.CanCollide = collision == true
	item.CanQuery = collision == true
	item.Parent = parent or scratch
	return item
end
local rotation = CFrame.Angles(0, math.rad(37), 0)
local ground =
	part("Ground", Vector3.new(240, 2, 240), CFrame.new(0, 500, 0) * rotation, scratch, true)
local field =
	part("FieldZone", Vector3.new(240, 10, 240), CFrame.new(0, 506, 0) * rotation, scratch)
local runtime = Instance.new("Folder")
runtime.Name = "CornRoundRuntime"
runtime:SetAttribute("corn_project_id", "children_of_corn")
runtime.Parent = scratch
local props = Instance.new("Folder")
props.Name = "Props"
props.Parent = scratch
local zones = Instance.new("Folder")
zones.Name = "NoCornZones"
zones.Parent = scratch
local function at(x, z, height)
	return field.CFrame * CFrame.new(x, height or -2, z)
end
part("Road", Vector3.new(12, 1, 240), at(0, 0, -4.5), props, true)
part("BarnFootprint", Vector3.new(20, 12, 20), at(60, 60), zones)
local slot = part("Slot", Vector3.one, at(-60, 0), scratch)
slot:AddTag("corn_key_slot")
local torchFolder = Instance.new("Folder")
torchFolder.Name = "TorchMarkers"
torchFolder:SetAttribute("corn_project_id", "children_of_corn")
torchFolder:SetAttribute("CornTorchMarkersOwned", true)
torchFolder.Parent = scratch
local flames = {}
for index = 1, 27 do
	local torch = Instance.new("Model")
	torch.Name = "Torch" .. index
	torch:SetAttribute("corn_project_id", "children_of_corn")
	torch:SetAttribute("CornTorchOwned", true)
	torch:AddTag("corn_torch")
	torch.Parent = torchFolder
	flames[index] = part("Flame", Vector3.one, at(index - 14, -30, 10), torch)
end
local foreignTorch = Instance.new("Model")
foreignTorch.Name = "ForeignTorch"
foreignTorch.Parent = torchFolder
part("Flame", Vector3.one, at(0, 0), foreignTorch)
local foreignSound = Instance.new("Sound")
foreignSound.Name = "AuthorSound"
foreignSound.Volume = 0.37
foreignSound.Parent = flames[1]
local npcRoot = part("Root", Vector3.new(3, 6, 2), at(-90, 20), runtime)
local hunt = { root = npcRoot, state = "patrol", destroyed = false }
local world = { Root = scratch, Field = field, Ground = ground, Runtime = runtime }
local function requested(sound)
	return sound:GetAttribute("AudioRequestedPlaying") == true
end
local function voicesOn()
	local count = 0
	for _, sound in audio.voices do
		if requested(sound) then
			count += 1
		end
	end
	return count
end
local function cricketFormula(now)
	for _, entry in audio.crickets do
		assert(
			requested(entry.sound)
				== (
					now - audio.startedAt - entry.offset >= 0
					and (now - audio.startedAt - entry.offset) % 30 < 15
				),
			"Cricket 15/15 boundary"
		)
	end
end
local ok, problem = pcall(function()
	audio = Audio.new(world, owner, hunt, Random.new(1187))
	assert(#audio.crickets == 5 and #audio.fires == 27 and #audio.voices == 3)
	for _, entry in audio.crickets do
		local emitter = entry.sound.Parent
		assert(emitter:IsA("BasePart") and emitter:HasTag("corn_audio_emitter"))
		assert(
			emitter.Anchored
				and emitter.Transparency == 1
				and not emitter.CanCollide
				and not emitter.CanTouch
				and not emitter.CanQuery
				and not emitter.CastShadow
		)
		assert(entry.sound.RollOffMaxDistance == Rules.Ranges.Crickets.Max)
	end
	for _, sound in audio.fires do
		assert(sound.Parent.Name == "Flame" and sound.Volume <= 1)
		assert(sound.RollOffMaxDistance == Rules.Ranges.Fire.Max)
	end
	assert(math.abs(audio.groups.Ambience.Volume - Rules.Mix.Master * Rules.Mix.Ambience) < 0.0001)
	checks.five_nonphysical_emitters_and_twenty_seven_owned_torches = true
	for _, now in { 0, 14.999, 15, 29.999, 30, 45, 60 } do
		audio:Step(now, "active", "easy", hunt)
		cricketFormula(now)
		for _, sound in audio.fires do
			assert(not requested(sound))
		end
	end
	assert(foreignSound.Parent == flames[1] and math.abs(foreignSound.Volume - 0.37) < 0.0001)
	assert(#foreignTorch.Flame:GetChildren() == 0)
	checks.exact_cricket_schedule_and_easy_silent_foreign_preserved = true
	audio:Step(61, "active", "hard", hunt)
	for _, sound in audio.fires do
		assert(requested(sound))
	end
	-- A full three-voice bag, safe intervals, and no boundary repeat.
	hunt.state = "chase"
	audio:Step(62, "active", "hard", hunt)
	assert(math.abs(audio.voiceAt - 62 - Rules.FirstVoiceDelay) < 0.0001 and voicesOn() == 0)
	local bag = {}
	local previous
	for index = 1, 4 do
		local now = audio.voiceAt
		audio:Step(now, "active", "hard", hunt)
		assert(voicesOn() == 1 and audio.voiceLast ~= previous)
		if index <= 3 then
			assert(not bag[audio.voiceLast])
			bag[audio.voiceLast] = true
		end
		previous = audio.voiceLast
		local pause = audio.voiceAt - audio.voiceUntil
		assert(pause >= Rules.VoiceMin and pause <= Rules.VoiceMax)
		audio:Step(audio.voiceUntil + 0.001, "active", "hard", hunt)
		assert(voicesOn() == 0)
	end
	checks.voice_shuffle_no_overlap_and_bounded_random_intervals = true
	local now = audio.voiceAt
	audio:Step(now, "active", "hard", hunt)
	assert(voicesOn() == 1)
	hunt.state = "trapped"
	audio:Step(now + 0.001, "active", "hard", hunt)
	assert(
		voicesOn() == 0 and not requested(audio.npc.sound),
		"Trap stops voices immediately and does not start stationary corn"
	)
	hunt.state = "patrol"
	-- Empty NPC ID isolates deterministic scheduling from actual async loading.
	-- Real decoded corn completion is tested separately with playback observations.
	audio.npc.sound.SoundId = ""
	-- Real rotated map geometry: stationary/teleport/air/outside/road/barn/slot.
	local cursor = now + 2
	local function step(x, z, height)
		cursor += 0.11
		npcRoot.CFrame = at(x, z, height)
		audio:Step(cursor, "active", "medium", hunt)
		-- Each selection restores the deliberate empty-ID intent fixture.
		audio.npc.sound.SoundId = ""
	end
	local function finishTail(phase)
		cursor = math.max(cursor + 0.11, audio.npc.untilAt + 0.11, audio.npc.nextAt + 0.11)
		audio:Step(cursor, phase or "active", "medium", hunt)
		assert(not requested(audio.npc.sound), "Finished stationary tail has no new request")
	end
	step(-90, 20)
	step(-89, 20)
	assert(requested(audio.npc.sound), "Moving NPC in corn rustles")
	local originalKey = audio.npc.sound:GetAttribute("AudioAssetKey")
	step(-89, 20)
	assert(requested(audio.npc.sound), "Stationary NPC preserves the started tail")
	step(-88, 20)
	assert(
		requested(audio.npc.sound) and audio.npc.sound:GetAttribute("AudioAssetKey") == originalKey,
		"Resuming before completion does not replace the clip"
	)
	finishTail()
	step(70, -80)
	assert(not requested(audio.npc.sound), "Teleport silent")
	step(0, 20)
	step(0, 21)
	assert(not requested(audio.npc.sound), "Road excluded")
	step(60, 60)
	step(61, 60)
	assert(not requested(audio.npc.sound), "Barn excluded")
	step(-60, 0)
	step(-59, 0)
	assert(not requested(audio.npc.sound), "Key clearing excluded")
	step(140, 0)
	step(141, 0)
	assert(not requested(audio.npc.sound), "Outside field silent")
	step(-90, 20, 10)
	step(-89, 20, 10)
	assert(not requested(audio.npc.sound), "Airborne NPC silent")
	step(-90, 20)
	step(-89, 20)
	assert(requested(audio.npc.sound))
	-- Each actor keeps one Sound; continuous walking waits for full intent duration.
	local rustleSound = audio.npc.sound
	local walkX = -89
	for index = 1, 12 do
		local previousKey = audio.npc.sound:GetAttribute("AudioAssetKey")
		local expectedInterval = math.max(Rules.RustleInterval, Assets.Get(previousKey).Duration)
		assert(math.abs(audio.npc.nextAt - cursor - expectedInterval) < 0.00001)
		local due = audio.npc.nextAt
		while cursor + 0.11 < due do
			walkX += 0.5
			step(walkX, 20)
			assert(audio.npc.sound:GetAttribute("AudioAssetKey") == previousKey)
		end
		walkX += 0.5
		step(walkX, 20)
		assert(
			requested(audio.npc.sound)
				and audio.npc.sound:GetAttribute("AudioAssetKey") ~= previousKey
				and audio.npc.sound == rustleSound
		)
	end
	checks.moving_actor_one_sound_full_duration_and_no_early_replacement_intent = true
	local originalExclusions = audio.exclusions
	part("LateExclusion", Vector3.new(20, 10, 20), at(-90, 20), zones)
	assert(
		audio.exclusions == originalExclusions and audio:_inCorn(at(-89, 20).Position),
		"Exclusions cached once"
	)
	checks.actual_movement_rotated_field_road_clearings_air_and_cached_exclusions = true
	audio:Step(cursor + 0.001, "caught", "hard", hunt)
	assert(
		requested(audio.npc.sound) and voicesOn() == 0,
		"Capture preserves the current corn tail"
	)
	for _, sound in audio.fires do
		assert(requested(sound))
	end
	cricketFormula(cursor + 0.001)
	hunt.state = "trapped"
	cursor += 0.11
	audio:Step(cursor, "active", "hard", hunt)
	assert(requested(audio.npc.sound), "Trap preserves the current corn tail")
	finishTail("caught")
	step(walkX + 0.5, 20)
	assert(not requested(audio.npc.sound), "Trapped NPC cannot start another rustle")
	hunt.state = "patrol"
	checks.capture_trap_preserve_tail_and_suppress_new_rustle_intent = true
	local oldNpcSound = audio.npc.sound
	local oldVoice = audio.voices[1]
	local replacementRoot = part("ReplacementRoot", Vector3.new(3, 6, 2), at(-90, 20), runtime)
	local replacement = { root = replacementRoot, state = "patrol", destroyed = false }
	audio:Step(cursor + 1, "active", "hard", replacement)
	assert(
		oldNpcSound.Parent == nil and oldVoice.Parent == nil and audio.npc.root == replacementRoot
	)
	assert(#audio.voices == 3)
	checks.replacement_actor_removes_old_emitters = true
	local inserted = Instance.new("Folder")
	inserted.Name = "ForeignInsertedIntoAudio"
	inserted.Parent = audio.crickets[1].sound.Parent
	local saved = {}
	for _, item in audio.created do
		table.insert(saved, item)
	end
	audio:Step(cursor + 2, "escaped", "hard", replacement)
	assert(audio.destroyed and inserted.Parent == runtime and foreignSound.Parent == flames[1])
	for _, item in saved do
		assert(item.Parent == nil, "Owned runtime object remained after terminal")
	end
	audio:Stop()
	audio:Destroy()
	audio:Step(cursor + 3, "active", "hard", replacement)
	assert(#audio.created == 0 and #audio.crickets == 0 and #audio.voices == 0)
	checks.terminal_idempotent_cleanup_and_foreign_child_preserved = true
	local ids = {}
	for _, key in
		{
			"COC_Crickets_15s",
			"COC_Fire",
			"COC_Monster_01",
			"COC_Monster_02",
			"COC_Monster_03",
			"COC_Corn_02",
		}
	do
		ids[key] = Assets.Get(key).Id
	end
	checks.configured_ids = ids
	checks.method =
		"Actual engine Parts/Sounds/groups with controlled logical Step clocks; NPC corn SoundId deliberately empty after each selection. Corn intent attributes exercise complete-duration scheduling and suppression, not decoded/audible playback, IsLoaded, human mix, or multiplayer acceptance. No live character relocation."
end)
if audio then
	audio:Destroy()
end
scratch:Destroy()
assert(ok, problem)
return checks
