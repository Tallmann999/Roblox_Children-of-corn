-- Production RoundAudio with deterministic Instances/decoding/playback adapters.
-- Explicit authoritative notification is tested separately from regular Step/sync.
-- These tests do not establish native decoding, audibility or listener mix.
local fs = require("@lune/fs")
local setup = assert(fs.readFile("tests/round-audio.luau"):match("^(.-)for id = 10, 1, %-1 do"))
setup = setup:gsub(
	"local Audio = load",
	[=[
local untrackedMake = make
make = function(class)
	local object = untrackedMake(class)
	if class == "Sound" then
		local meta = getmetatable(object)
		local setter = meta.__newindex
		meta.__newindex = function(self, key, value)
			if key == "SoundId" then self.values.UriWrites = (self.values.UriWrites or 0) + 1 end
			setter(self, key, value)
		end
	end
	return object
end
local Audio = load]=],
	1
)
local count
setup, count = setup:gsub(
	"Enum = roblox%.Enum,",
	[=[Enum = roblox.Enum,
	typeof = function(value)
		if type(value) == "table" and type(value.class) == "string" and value.values then return "Instance" end
		return typeof(value)
	end,]=],
	1
)
assert(count == 1, "RoundAudio adapter environment changed")
local cases = [=[
assets.Get = function(key)
	local definition = realAssets.Get(key)
	durations[key] = definition.Duration
	return definition
end
world.Runtime:SetAttribute("corn_project_id", "children_of_corn")
local owner = { UserId = 20 }
local humanoid, playerRoot = character(owner)
humanoid.WalkSpeed = 12
table.insert(players, owner)

local function hunt(index)
	local model = child("Model", if index == 1 then "Monster" else "Monster" .. index, world.Runtime)
	model:SetAttribute("CornMonsterOwned", true)
	model:SetAttribute("corn_project_id", "children_of_corn")
	model:SetAttribute("MonsterRigVersion", 1)
	model:SetAttribute("MonsterIndex", index)
	local root = child("Part", "Root", model)
	root.Position = roblox.Vector3.new(-60 + index * 20, 3, 30)
	model.PrimaryPart = root
	return { world = world, model = model, root = root, destroyed = false,
		state = "patrol", home = root.Position, balance = { monster_patrol_speed = 10 } }
end
local function scenario()
	local hunts = { hunt(1), hunt(2), hunt(3) }
	local audio = Audio.new(world, owner, hunts[1], rand)
	step(audio, 0, "active", "hard", hunts[1], hunts)
	return audio, hunts
end
local function roleSound(root, index)
	return root:FindFirstChild("CornAudio_reinforcement_arrival_" .. index)
end
local function pair(hunts) return { hunts[2], hunts[3] } end
local function finish(audio, hunts)
	audio:Destroy()
	for _, source in hunts do source.model:Destroy() end
end
local function cornSnapshot(audio)
	local result = {}
	for _, actor in audio.npcActors do
		local sound = actor.sound
		result[sound] = { id = sound.SoundId, writes = sound.UriWrites,
			plays = sound.PlayCount, stops = sound.StopCount, volume = sound.Volume }
	end
	return result
end
local function cornUnchanged(before)
	for sound, value in before do
		assert(sound.SoundId == value.id and sound.UriWrites == value.writes
			and sound.PlayCount == value.plays and sound.StopCount == value.stops and sound.Volume == value.volume,
			"Arrival changed the continuous rustle URI/playback metadata Sound")
	end
end

-- First binding and repeated synchronization never infer a spawn. Only one
-- successful authoritative pair notification emits the two independent cries.
do
	local audio, hunts = scenario()
	assert(not roleSound(hunts[2].root, 2) and not roleSound(hunts[3].root, 3))
	step(audio, 0.125, "active", "hard", hunts[3], hunts)
	step(audio, 0.25, "active", "hard", hunts[2], hunts)
	assert(not roleSound(hunts[2].root, 2) and not roleSound(hunts[3].root, 3),
		"Step/sync/lead binding inferred an old reinforcement appearance")
	local before = cornSnapshot(audio)
	local reentered, nested
	local basePlay = methods.Play
	function methods:Play()
		if self:GetAttribute("audio_role") == "reinforcement_arrival_2" and not reentered then
			reentered = true
			nested = audio:ReinforcementsSpawned(pair(hunts))
		end
		basePlay(self)
	end
	assert(audio:ReinforcementsSpawned(pair(hunts)) == 2)
	methods.Play = basePlay
	assert(reentered and nested == 0, "Both per-round appearance latches must commit before the first Play")
	local second, third = roleSound(hunts[2].root, 2), roleSound(hunts[3].root, 3)
	assert(second and third and second ~= third and second.Parent == hunts[2].root and third.Parent == hunts[3].root)
	for index, sound in { [2] = second, [3] = third } do
		local key = if index == 2 then "COC_Monster_01" else "COC_Monster_02"
		local definition = realAssets.Get(key)
		assert(sound:GetAttribute("AudioAssetKey") == key and sound.SoundId == definition.Id)
		assert(sound:GetAttribute("CornAudioOwned") == true and sound:GetAttribute("corn_project_id") == "children_of_corn")
		assert(sound:GetAttribute("AudioRequestedPlaying") == true and sound.PlayCount == 1 and sound.StopCount == 0)
		assert(not sound.Looped and sound.SoundGroup == audio.groups.Effects)
		assert(math.abs(sound.Volume - rules.Volume.Awakening * definition.Gain) < 0.00001)
		assert(sound.RollOffMode == roblox.Enum.RollOffMode.Linear and sound.RollOffMinDistance == 20 and sound.RollOffMaxDistance == 1400)
	end
	assert(second.SoundId ~= third.SoundId)
	assert(audio:ReinforcementsSpawned({ hunts[3], hunts[2] }) == 0)
	step(audio, 0.375, "active", "hard", hunts[3], hunts)
	step(audio, 0.5, "active", "hard", hunts[1], { hunts[1], hunts[3], hunts[2] })
	step(audio, 0.625, "active", "hard", hunts[1], { hunts[1] })
	step(audio, 0.75, "active", "hard", hunts[2], hunts)
	assert(audio:ReinforcementsSpawned(pair(hunts)) == 0 and second.PlayCount == 1 and third.PlayCount == 1)
	-- Compare the unchanged original roots before a deliberate binding removal.
	-- The alias handoffs above may destroy/recreate corn metadata on removal;
	-- none of those owned Sounds may ever play or acquire another URI.
	for sound, value in before do
		assert(sound.SoundId == value.id and sound.UriWrites == value.writes and sound.PlayCount == 0)
	end
	local stable = cornSnapshot(audio)
	step(audio, 4, "active", "hard", hunts[1], hunts)
	assert(not second.IsPlaying and not third.IsPlaying and second.StopCount == 0 and third.StopCount == 0,
		"Arrival tails must complete naturally; Step must not timer-Stop them")
	cornUnchanged(stable)
	local oldSecond = hunts[2]
	hunts[2] = hunt(2)
	assert(audio:ReinforcementsSpawned(pair(hunts)) == 0 and not roleSound(hunts[2].root, 2),
		"Replacement root replayed this round's index-2 appearance")
	oldSecond.model:Destroy()
	finish(audio, hunts)
end

-- An invalid/partial batch cannot cry for even its valid partner or consume its
-- latch. Repairing the batch produces exactly the original two appearances.
local invalidCount = 0
local function property(object, key, value)
	local old = object[key]
	object[key] = value
	return function() object[key] = old end
end
local function attribute(object, key, value)
	local old = object:GetAttribute(key)
	object:SetAttribute(key, value)
	return function() object:SetAttribute(key, old) end
end
for _, mutate in {
	function(h) return property(h, "destroyed", true) end,
	function(h) return property(h, "world", {}) end,
	function(h) return property(h, "root", false) end,
	function(h) return property(h, "model", "foreign") end,
	function(h) return property(h, "state", "stopped") end,
	function(h) return property(h, "state", "dormant") end,
	function(h) return property(h.model, "Parent", nil) end,
	function(h) return property(h.root, "Parent", world.Runtime) end,
	function(h) return property(h.model, "PrimaryPart", nil) end,
	function(h) return property(h.root, "Name", "ForeignRoot") end,
	function(h) return property(h.model, "Name", "ForeignMonster") end,
	function(h) return attribute(h.model, "CornMonsterOwned", false) end,
	function(h) return attribute(h.model, "corn_project_id", "other_game") end,
	function(h) return attribute(h.model, "MonsterRigVersion", 2) end,
	function(h) return attribute(h.model, "MonsterIndex", 4) end,
	function() return attribute(world.Runtime, "corn_project_id", "other_game") end,
	function() return property(world.Runtime, "Parent", workspace) end,
} do
	local audio, hunts = scenario()
	local undo = mutate(hunts[3])
	assert(audio:ReinforcementsSpawned(pair(hunts)) == 0)
	assert(not roleSound(hunts[2].root, 2), "Invalid partner caused a partial arrival")
	undo()
	assert(audio:ReinforcementsSpawned(pair(hunts)) == 2, "Invalid batch consumed the valid partner's latch")
	invalidCount += 1
	finish(audio, hunts)
end
for _, bad in { false, "reinforcements", {}, { 1, 2 } } do
	local audio, hunts = scenario()
	assert(audio:ReinforcementsSpawned(bad) == 0 and audio:ReinforcementsSpawned(nil) == 0)
	assert(audio:ReinforcementsSpawned({ hunts[2] }) == 0)
	assert(audio:ReinforcementsSpawned({ hunts[2], hunts[2] }) == 0)
	assert(audio:ReinforcementsSpawned({ hunts[2], hunts[3], hunts[1] }) == 0)
	assert(audio:ReinforcementsSpawned({ hunts[2], hunts[3], extra = hunts[1] }) == 0)
	local fourth = hunt(4)
	assert(audio:ReinforcementsSpawned({ hunts[2], fourth }) == 0)
	fourth.model:Destroy()
	assert(audio:ReinforcementsSpawned(pair(hunts)) == 2)
	invalidCount += 7
	finish(audio, hunts)
end

-- Capture cuts only the new owned one-shots immediately, even before the next
-- throttled actor poll. Revival and trap state changes never replay them.
do
	local audio, hunts = scenario()
	assert(audio:ReinforcementsSpawned(pair(hunts)) == 2)
	local second, third = roleSound(hunts[2].root, 2), roleSound(hunts[3].root, 3)
	local before = cornSnapshot(audio)
	step(audio, 0.001, "caught", "hard", hunts[1], hunts)
	assert(not second.IsPlaying and not third.IsPlaying and second.StopCount == 1 and third.StopCount == 1)
	step(audio, 0.002, "caught", "hard", hunts[1], hunts)
	step(audio, 1.25, "active", "hard", hunts[1], hunts)
	hunts[2].state = "trapped"
	step(audio, 1.5, "active", "hard", hunts[1], hunts)
	hunts[2].state = "patrol"
	assert(audio:ReinforcementsSpawned(pair(hunts)) == 0 and second.PlayCount == 1 and third.PlayCount == 1)
	cornUnchanged(before)
	finish(audio, hunts)
	assert(second.Destroyed and third.Destroyed and second.StopCount == 1 and third.StopCount == 1)
end
do
	local audio, hunts = scenario()
	step(audio, 0.001, "caught", "hard", hunts[1], hunts)
	-- The server has revived the owner and opened the gate before the next
	-- audio poll. Its explicit successful spawn notification is authoritative;
	-- the last observed caught Step must not suppress the current appearances.
	assert(audio:ReinforcementsSpawned(pair(hunts)) == 2)
	local second, third = roleSound(hunts[2].root, 2), roleSound(hunts[3].root, 3)
	assert(second.IsPlaying and third.IsPlaying and second.PlayCount == 1 and third.PlayCount == 1)
	step(audio, 1.25, "active", "hard", hunts[1], hunts)
	assert(audio:ReinforcementsSpawned(pair(hunts)) == 0 and second.StopCount == 0 and third.StopCount == 0,
		"A valid fast-revival gate appearance was suppressed or replayed")
	finish(audio, hunts)
end

-- Takeovers relinquish only the new Sound reference. Later caught/Destroy
-- must not Stop, relabel, overwrite, reparent or destroy the adopted Sound.
local foreignCount = 0
for _, mutate in {
	function(sound) sound:SetAttribute("CornAudioOwned", false) end,
	function(sound) sound:SetAttribute("corn_project_id", "other_game") end,
	function(sound) sound:SetAttribute("audio_role", "author_sound") end,
	function(sound) sound:SetAttribute("AudioAssetKey", "author_asset") end,
	function(sound) sound.IsPlaying = false; sound.SoundId = "rbxassetid://foreign" end,
	function(sound) sound.Name = "AuthorSound" end,
	function(sound) sound.Looped = true end,
	function(sound) sound.Parent = child("Folder", "AuthorAudio", workspace) end,
	function(sound) sound.SoundGroup = child("SoundGroup", "AuthorEffects", soundService) end,
	function(_, audio) audio.groups.Effects.Parent = child("Folder", "AuthorGroups", soundService) end,
	function(_, _, hunts) hunts[2].model:SetAttribute("CornMonsterOwned", false) end,
} do
	local audio, hunts = scenario()
	assert(audio:ReinforcementsSpawned(pair(hunts)) == 2)
	local sound = roleSound(hunts[2].root, 2)
	mutate(sound, audio, hunts)
	local before = { parent = sound.Parent, name = sound.Name, id = sound.SoundId,
		key = sound:GetAttribute("AudioAssetKey"), role = sound:GetAttribute("audio_role"),
		owned = sound:GetAttribute("CornAudioOwned"), project = sound:GetAttribute("corn_project_id"),
		group = sound.SoundGroup, volume = sound.Volume, looped = sound.Looped,
		stops = sound.StopCount, plays = sound.PlayCount, writes = sound.UriWrites,
		requested = sound:GetAttribute("AudioRequestedPlaying") }
	step(audio, 0.001, "caught", "hard", hunts[1], hunts)
	step(audio, 0.125, "active", "hard", hunts[1], hunts)
	assert(audio:ReinforcementsSpawned(pair(hunts)) == 0)
	audio:Destroy()
	assert(not sound.Destroyed and sound.Parent == before.parent and sound.Name == before.name
		and sound.SoundId == before.id and sound.SoundGroup == before.group and sound.Volume == before.volume
		and sound.Looped == before.looped and sound.StopCount == before.stops and sound.PlayCount == before.plays
		and sound.UriWrites == before.writes and sound:GetAttribute("AudioRequestedPlaying") == before.requested
		and sound:GetAttribute("AudioAssetKey") == before.key and sound:GetAttribute("audio_role") == before.role
		and sound:GetAttribute("CornAudioOwned") == before.owned and sound:GetAttribute("corn_project_id") == before.project,
		"New arrival lifecycle modified an adopted foreign Sound")
	foreignCount += 1
	for _, source in hunts do source.model:Destroy() end
	if sound.Parent then sound:Destroy() end
end

for _, phase in { "ready", "preparing", "escaped", "aborted", "caught_out" } do
	local audio, hunts = scenario()
	assert(audio:ReinforcementsSpawned(pair(hunts)) == 2)
	local second, third = roleSound(hunts[2].root, 2), roleSound(hunts[3].root, 3)
	local foreign = child("Folder", "AuthorChild", second)
	foreign:SetAttribute("author_marker", "preserve")
	step(audio, 0.001, phase, "hard", hunts[1], hunts)
	assert(audio.destroyed and second.Destroyed and third.Destroyed)
	assert(second.StopCount == 1 and third.StopCount == 1 and audio:ReinforcementsSpawned(pair(hunts)) == 0)
	assert(not foreign.Destroyed and foreign.Parent == hunts[2].root and foreign:GetAttribute("author_marker") == "preserve")
	finish(audio, hunts)
end

-- A new RoundAudio instance is the only appearance-latch reset.
do
	local audio, hunts = scenario()
	assert(audio:ReinforcementsSpawned(pair(hunts)) == 2)
	audio:Destroy()
	local fresh = Audio.new(world, owner, hunts[1], rand)
	assert(fresh:ReinforcementsSpawned(pair(hunts)) == 2)
	finish(fresh, hunts)
end
print("PASS production explicit reinforcement arrival audio: first sync/Step silent, exact pair validation (" .. tostring(invalidCount)
	.. " rejects), two independently bound Monster_01/02 one-shots, pre-Play/reentrant per-round latches, no replacement/rebind/lead/trap/revive replay, natural tails, immediate caught stop and terminal cleanup, " .. tostring(foreignCount)
	.. " foreign takeover guards, owned child preservation and unchanged continuous rustle URI/playback. Adapter only; native decoding/audibility separate.")
]=]
assert(loadstring(setup .. cases, "entity-arrival-audio-focused"))()
