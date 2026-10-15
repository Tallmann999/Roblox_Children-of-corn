-- Actual server module with deterministic Instances/service adapters.
-- Covers bounded server actor authority and cleanup; no engine/audible claim.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local function load(path, env)
	local fn = assert(loadstring(fs.readFile(path), path))
	setfenv(fn, setmetatable(env, { __index = getfenv() }))
	return fn()
end
local methods = {}
local virtualNow = 0
local sounds = {}
local durations = {}
local function make(class)
	local item = setmetatable({
		class = class,
		children = {},
		attributes = {},
		tags = {},
		values = {
			Name = class,
			CFrame = roblox.CFrame.identity,
			Size = roblox.Vector3.one,
			SoundId = "",
			TimeLength = 0,
			TimePosition = 0,
			Health = 100,
			HipHeight = 2,
			RigType = roblox.Enum.HumanoidRigType.R15,
			FloorMaterial = roblox.Enum.Material.Grass,
			PlayCount = 0,
			StopCount = 0,
			IsLoaded = false,
			IsPlaying = false,
			AdapterLoadDelay = 0,
			AdapterDuration = 0,
		},
	}, {
		__index = function(self, key)
			if key == "Position" then
				return self.values.CFrame.Position
			end
			return methods[key] or self.values[key]
		end,
		__newindex = function(self, key, value)
			if self.class == "Sound" and key == "SoundId" then
				assert(
					not self.values.IsPlaying and not self.values.PendingPlayback,
					"A playing or pending clip must finish before replacing SoundId"
				)
				self.values.IsLoaded = value ~= "" and self.values.AdapterLoadDelay == 0
			end
			if key == "Parent" then
				local previous = self.values.Parent
				if previous then
					local index = table.find(previous.children, self)
					if index then
						table.remove(previous.children, index)
					end
				end
				if value then
					table.insert(value.children, self)
				end
			elseif key == "Position" then
				self.values.CFrame = roblox.CFrame.new(value)
				return
			end
			self.values[key] = value
		end,
	})
	if class == "Sound" then
		table.insert(sounds, item)
	end
	return item
end
-- This adapter models decoding and natural completion separately from Step's clock.
-- Fake IDs are never sent to Studio and do not establish audible playback.
local function advance(now)
	virtualNow = now
	for _, sound in sounds do
		if not sound.Destroyed then
			if sound.PendingPlayback and now >= sound.LoadAt then
				sound.IsLoaded = true
				sound.IsPlaying = true
				sound.PendingPlayback = false
				sound.TimeLength = sound.PlaybackDuration
			end
			if sound.IsPlaying then
				local elapsed = math.max(0, now - sound.LoadAt)
				sound.TimePosition = if sound.Looped
					then elapsed % sound.PlaybackDuration
					else math.min(elapsed, sound.PlaybackDuration)
			end
			if sound.IsPlaying and not sound.Looped and now >= sound.FinishAt then
				sound.IsPlaying = false
			end
		end
	end
end
local function step(audio, now, phase, mode, hunt, hunts)
	advance(now)
	audio:Step(now, phase, mode, hunt, hunts)
end
function methods:IsA(class)
	return self.class == class or (class == "BasePart" and self.class == "Part")
end
function methods:SetAttribute(key, value)
	self.attributes[key] = value
end
function methods:GetAttribute(key)
	return self.attributes[key]
end
function methods:AddTag(tag)
	self.tags[tag] = true
end
function methods:HasTag(tag)
	return self.tags[tag] == true
end
function methods:GetChildren()
	return table.clone(self.children)
end
function methods:GetDescendants()
	local result = {}
	for _, child in self.children do
		table.insert(result, child)
		for _, descendant in child:GetDescendants() do
			table.insert(result, descendant)
		end
	end
	return result
end
function methods:FindFirstChild(name)
	for _, child in self.children do
		if child.Name == name then
			return child
		end
	end
	return nil
end
function methods:WaitForChild(name)
	return assert(self:FindFirstChild(name), name)
end
function methods:FindFirstChildOfClass(class)
	for _, child in self.children do
		if child:IsA(class) then
			return child
		end
	end
	return nil
end
function methods:GetFullName()
	return self.Name
end
function methods:Play()
	self.PlayCount += 1
	self.LoadAt = virtualNow + (if self.IsLoaded then 0 else self.AdapterLoadDelay)
	self.PendingPlayback = not self.IsLoaded
	self.IsPlaying = self.IsLoaded
	local duration = if self.AdapterDuration > 0
		then self.AdapterDuration
		else durations[self:GetAttribute("AudioAssetKey")] or 0.1
	self.TimeLength = if self.IsLoaded then duration else 0
	self.TimePosition = 0
	self.PlaybackDuration = duration
	self.FinishAt = self.LoadAt + duration
end
function methods:Stop()
	self.StopCount += 1
	self.IsPlaying = false
	self.PendingPlayback = false
	self.TimePosition = 0
end
function methods:Destroy()
	for _, child in self:GetChildren() do
		child:Destroy()
	end
	self.Parent = nil
	self.Destroyed = true
end
local function child(class, name, parent)
	local item = make(class)
	item.Name = name
	item.Parent = parent
	return item
end
local rs = make("ReplicatedStorage")
local shared = child("Folder", "Game", child("Folder", "GameShared", rs))
local assetsNode = child("ModuleScript", "AudioAssets", shared)
local rulesNode = child("ModuleScript", "AudioRules", shared)
local layoutNode = child("ModuleScript", "CornLayout", shared)
local realAssets = load("src/shared/Game/AudioAssets.luau", {})
local fixtureId = ""
local assets = {
	Get = function(key)
		local asset = realAssets.Get(key)
		durations[key] = asset.Duration
		return { Id = fixtureId, Gain = asset.Gain, Duration = asset.Duration }
	end,
}
local rules = load("src/shared/Game/AudioRules.luau", {})
local layout = load("src/shared/Game/CornLayout.luau", {
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = roblox.CFrame,
})
local reads = 0
local realRead = layout.ReadExclusions
layout.ReadExclusions = function(...)
	reads += 1
	return realRead(...)
end
local modules = { [assetsNode] = assets, [rulesNode] = rules, [layoutNode] = layout }
local workspace = make("Workspace")
local soundService = make("SoundService")
local players = {}
local playersService = {
	GetPlayers = function()
		return table.clone(players)
	end,
}
local services = {
	ReplicatedStorage = rs,
	Players = playersService,
	SoundService = soundService,
	HttpService = {
		GenerateGUID = function()
			return "fixture-guid"
		end,
	},
}
local world = {
	Root = child("Model", "CornMap", workspace),
}
world.Runtime = child("Folder", "CornRoundRuntime", world.Root)
world.Field = child("Part", "Field", world.Root)
world.Field.Size = roblox.Vector3.new(240, 10, 240)
world.Field.Position = roblox.Vector3.new(0, 5, 0)
world.Ground = child("Part", "Ground", world.Root)
world.Ground.Size = roblox.Vector3.new(240, 2, 240)
world.Ground.Position = roblox.Vector3.new(0, -1, 0)
local rayCount = 0
local groundHit = true
local rayLength = 0
function workspace:Raycast(origin, direction, params)
	rayCount += 1
	rayLength = direction.Magnitude
	assert(#params.FilterDescendantsInstances == 1)
	return if groundHit and rayLength >= origin.Y then { Instance = world.Ground } else nil
end
local nextInteger = 0
local rand = {
	NextInteger = function(_, low, high)
		nextInteger += 1
		return low + nextInteger % (high - low + 1)
	end,
	NextNumber = function(_, low, high)
		return (low + high) / 2
	end,
}
local Audio = load("src/server/Game/RoundAudio.luau", {
	game = {
		GetService = function(_, key)
			return assert(services[key], key)
		end,
	},
	workspace = workspace,
	require = function(node)
		return assert(modules[node])
	end,
	Instance = { new = make },
	Vector2 = roblox.Vector2,
	Vector3 = roblox.Vector3,
	Enum = roblox.Enum,
	Random = {
		new = function()
			return rand
		end,
	},
	RaycastParams = {
		new = function()
			return {}
		end,
	},
})
local function character(player)
	local model = child("Model", "Character" .. player.UserId, workspace)
	local humanoid = child("Humanoid", "Humanoid", model)
	local root = child("Part", "HumanoidRootPart", model)
	root.Size = roblox.Vector3.new(2, 2, 1)
	root.Position = roblox.Vector3.new(-80, 3, 20)
	player.Character = model
	return humanoid, root
end
for id = 10, 1, -1 do
	local player = { UserId = id }
	character(player)
	table.insert(players, player)
end
local owner = players[2] -- ID9 must be admitted before the seven lowest IDs.
local audio = Audio.new(world, owner, nil, rand)
step(audio, 0, "active", "hard", nil)
local function actorCount()
	local count = 0
	for _ in audio.actors do
		count += 1
	end
	return count
end
assert(actorCount() == 8 and audio.actors[owner] and not audio.actors[players[1]])
assert(reads == 1 and rayCount == 8)
local ownerHumanoid = owner.Character:FindFirstChildOfClass("Humanoid")
local ownerRoot = audio.actors[owner].root
ownerHumanoid.RigType = roblox.Enum.HumanoidRigType.R6
ownerHumanoid.HipHeight = 0
local leg = child("Part", "Left Leg", owner.Character)
leg.Size = roblox.Vector3.new(1, 2, 1)
ownerRoot.Position = roblox.Vector3.new(-80, 3.2, 20)
assert(
	audio:_grounded(owner.Character, ownerHumanoid, ownerRoot) and rayLength == 5,
	"R6 legs extend the ground ray"
)
ownerHumanoid.RigType = roblox.Enum.HumanoidRigType.R15
ownerHumanoid.HipHeight = 2
leg:Destroy()
rayCount = 8 -- The preceding direct grounded check is independent of actor poll counts.
for player, actor in audio.actors do
	actor.root.Position += roblox.Vector3.xAxis
end
step(audio, 0.11, "active", "hard", nil)
for _, actor in audio.actors do
	assert(actor.sound:GetAttribute("AudioRequestedPlaying") == true)
end
assert(rayCount == 16 and reads == 1)
local ownerActor = audio.actors[owner]
step(audio, 0.111, "caught", "hard", nil)
assert(
	ownerActor.sound:GetAttribute("AudioRequestedPlaying") == true,
	"Capture preserves the current corn tail, even between10Hz polls"
)
for player, actor in audio.actors do
	if player ~= owner then
		assert(actor.sound:GetAttribute("AudioRequestedPlaying") == true)
	end
end
for _, actor in audio.actors do
	actor.root.Position += roblox.Vector3.xAxis
end
step(audio, 0.22, "caught", "hard", nil)
assert(ownerActor.sound:GetAttribute("AudioRequestedPlaying") == true)
step(audio, 2.3, "caught", "hard", nil)
for _, actor in audio.actors do
	assert(actor.sound:GetAttribute("AudioRequestedPlaying") == false)
	assert(actor.sound.StopCount == 0, "Natural empty-ID intent completion must not Stop")
end
local rejected = audio.actors[players[10]]
local human = players[10].Character:FindFirstChildOfClass("Humanoid")
human.FloorMaterial = roblox.Enum.Material.Air
rejected.root.Position += roblox.Vector3.xAxis
step(audio, 2.41, "active", "hard", nil)
assert(rejected.sound:GetAttribute("AudioRequestedPlaying") == false, "Airborne player silent")
human.FloorMaterial = roblox.Enum.Material.Grass
groundHit = false
rejected.root.Position += roblox.Vector3.xAxis
step(audio, 2.52, "active", "hard", nil)
assert(rejected.sound:GetAttribute("AudioRequestedPlaying") == false, "Server ground ray required")
groundHit = true
local oldSound = rejected.sound
human.Health = 0
step(audio, 2.63, "active", "hard", nil)
assert(not audio.actors[players[10]] and oldSound.Destroyed)
character(players[10])
step(audio, 2.74, "active", "hard", nil)
local replaced = audio.actors[players[10]]
assert(
	replaced
		and replaced.sound ~= oldSound
		and replaced.sound:GetAttribute("AudioRequestedPlaying") == false
)
local knownSound = replaced.sound
character(players[10])
step(audio, 2.85, "active", "hard", nil)
assert(knownSound.Destroyed and audio.actors[players[10]].sound ~= knownSound)
for _, actor in audio.actors do
	actor.root.Position += roblox.Vector3.new(80, 0, 0)
end
step(audio, 2.96, "active", "hard", nil)
for _, actor in audio.actors do
	assert(actor.sound:GetAttribute("AudioRequestedPlaying") == false, "Teleport silent")
end
local created = table.clone(audio.created)
for _, item in created do
	if item:IsA("Sound") then
		assert(item.PlayCount == 0, "Empty ID must never be Play-ed")
	end
end
local foreign = child("Folder", "ForeignWithinOwnedGroup", audio.groups.Effects)
audio:Stop()
assert(audio.destroyed and foreign.Parent == soundService)
for _, item in created do
	assert(item.Destroyed and item.Parent == nil)
end
step(audio, 3.1, "active", "hard", nil)
audio:Destroy()
assert(#audio.created == 0 and actorCount() == 0 and reads == 1)
local npcRoot = child("Part", "MonsterRoot", world.Runtime)
npcRoot.Position = roblox.Vector3.new(-80, 3, 20)
local hunt = { root = npcRoot, state = "chase", destroyed = false }
local cue = Audio.new(world, owner, hunt, rand)
step(cue, 0, "active", "hard", hunt)
assert(cue.voiceAt == 0.4, "Initial discovery cue delay")
local function requestedVoices()
	local count = 0
	for _, sound in cue.voices do
		if sound:GetAttribute("AudioRequestedPlaying") == true then
			count += 1
		end
	end
	return count
end
step(cue, 0.29, "active", "hard", hunt)
assert(requestedVoices() == 0)
step(cue, 0.4, "active", "hard", hunt)
assert(requestedVoices() == 1, "A short chase receives its discovery cue at0.4sec")
local gap = cue.voiceAt - cue.voiceUntil
assert(gap >= rules.VoiceMin and gap <= rules.VoiceMax, "Subsequent silence remains4..7.5sec")
hunt.state = "patrol"
step(cue, 0.401, "active", "hard", hunt)
assert(requestedVoices() == 0, "Losing chase silences initial roar immediately")
-- Fake loaded IDs exercise complete one-shots without any actual audio claim.
fixtureId = "rbxassetid://1"
local cursor = 1
npcRoot.Position = roblox.Vector3.new(-80, 3, 20)
local actor = cue.npc
local function actorStep(now, displacement, eligible)
	advance(now)
	if displacement then
		npcRoot.Position += displacement
	end
	cue:_stepActor(actor, now, eligible ~= false)
	cursor = now
end
actorStep(cursor)
actorStep(cursor + 0.11, roblox.Vector3.new(0.06, 0, 0))
local firstSound = actor.sound
local firstKey = firstSound:GetAttribute("AudioAssetKey")
assert(firstSound.PlayCount == 1 and firstSound.IsPlaying)
actorStep(cursor + 0.11)
assert(firstSound.PlayCount == 1 and firstSound.IsPlaying, "A tiny step's tail survives stopping")
actorStep(cursor + 0.11, roblox.Vector3.xAxis)
assert(
	firstSound.PlayCount == 1 and firstSound:GetAttribute("AudioAssetKey") == firstKey,
	"Resuming movement must not replace the unfinished clip"
)
local cuesDuringPlayback = 0
for _ = 1, 14 do
	local oldCommit = firstSound:GetAttribute("AudioRustleStart")
	local oldKey = oldCommit:match(":(.+)$")
	local oldId, oldCount = actor.rustleId, firstSound.PlayCount
	local oldUri, oldUntil = firstSound.SoundId, actor.untilAt
	local previousDeadline = actor.nextAt
	local continuous = actor.cueContinuous
	local due = previousDeadline + 0.001
	while cursor + 0.1 < due do
		actorStep(cursor + 0.1, roblox.Vector3.xAxis)
		assert(actor.rustleId == oldId, "Cue arrived before its bounded cadence")
	end
	actorStep(due, roblox.Vector3.xAxis)
	assert(actor.rustleId == oldId + 1 and actor.sound == firstSound, "Expected one validated cue")
	local key = firstSound:GetAttribute("AudioRustleStart"):match(":(.+)$")
	assert(key ~= oldKey, "Corn cue must not repeat consecutively")
	assert(
		math.abs(
			actor.nextAt
				- (if continuous then previousDeadline else due)
				- math.max(rules.RustleInterval, realAssets.Get(key).Duration / rules.RustleVoices)
		) < 0.000001,
		"Cue cadence must be half the previous max(.45, duration)"
	)
	if due < oldUntil then
		cuesDuringPlayback += 1
		assert(
			firstSound.PlayCount == oldCount and firstSound.SoundId == oldUri,
			"A cue during the previous server clip rewrote playback"
		)
	end
end
assert(cuesDuringPlayback >= 3, "Continuous movement did not receive more frequent cues")
assert(firstSound.StopCount == 0, "Natural corn completion never calls Stop")

-- A decoded clip longer than manifest metadata also keeps its full tail.
npcRoot.Position = roblox.Vector3.new(-80, 3, 20)
actor = cue:_actor(npcRoot)
actor.sound.AdapterDuration = 4
actorStep(30)
actorStep(30.11, roblox.Vector3.xAxis)
local longSound = actor.sound
local longKey = longSound:GetAttribute("AudioAssetKey")
local nominalEnd = actor.untilAt
local cueBeforeLongTail = actor.rustleId
while cursor + 0.1 < longSound.FinishAt do
	actorStep(cursor + 0.1, roblox.Vector3.xAxis)
	assert(longSound.PlayCount == 1 and longSound:GetAttribute("AudioAssetKey") == longKey)
end
assert(
	cursor > nominalEnd and longSound.IsPlaying and actor.rustleId > cueBeforeLongTail + 2,
	"Longer server decode must retain its full tail while publishing validated cues"
)
actorStep(longSound.FinishAt + 0.001)
assert(not longSound.IsPlaying and not longSound:GetAttribute("AudioRequestedPlaying"))
assert(longSound.PlayCount == 1 and longSound.StopCount == 0)

-- Late loading cannot be replaced at nominal expiry; playback completes after decode.
npcRoot.Position = roblox.Vector3.new(-80, 3, 20)
actor = cue:_actor(npcRoot)
actor.sound.AdapterLoadDelay = 3
actor.sound.AdapterDuration = 2.5
actorStep(40)
actorStep(40.11, roblox.Vector3.xAxis)
local lateSound = actor.sound
local lateKey = lateSound:GetAttribute("AudioAssetKey")
while cursor + 0.1 < lateSound.FinishAt do
	actorStep(cursor + 0.1, roblox.Vector3.xAxis)
	assert(lateSound.PlayCount == 1 and lateSound:GetAttribute("AudioAssetKey") == lateKey)
	assert(lateSound:GetAttribute("AudioRequestedPlaying"))
end
assert(lateSound.IsLoaded and lateSound.IsPlaying and cursor > actor.untilAt)
actorStep(lateSound.FinishAt + 0.001)
assert(lateSound.PlayCount == 1 and lateSound.StopCount == 0 and not lateSound.IsPlaying)

-- Never-decoding IDs recover after the load deadline; a clip that actually
-- progressed may not be cut merely because IsLoaded became unreliable.
npcRoot.Position = roblox.Vector3.new(-80, 3, 20)
actor = cue:_actor(npcRoot)
actor.sound.AdapterLoadDelay = 1000
actorStep(47)
actorStep(47.11, roblox.Vector3.xAxis)
local missingSound = actor.sound
local missingKey = missingSound:GetAttribute("AudioAssetKey")
assert(not missingSound.IsLoaded and missingSound.PendingPlayback)
actorStep(actor.loadDeadline - 0.01)
assert(missingSound.PlayCount == 1 and missingSound.StopCount == 0)
missingSound.TimePosition = 0.25
actorStep(actor.loadDeadline + 0.11)
assert(missingSound.PlayCount == 1 and missingSound.StopCount == 0)
missingSound.TimePosition = 0
actorStep(cursor + 0.11, roblox.Vector3.xAxis)
assert(
	missingSound.PlayCount == 2
		and missingSound.StopCount == 1
		and missingSound:GetAttribute("AudioAssetKey") ~= missingKey,
	"An unplayed failed request recovers after timeout without cutting played audio"
)

-- Movement eligibility suppresses new starts; it never cuts a started tail.
npcRoot.Position = roblox.Vector3.new(-80, 3, 20)
actor = cue:_actor(npcRoot)
actorStep(50)
actorStep(50.11, roblox.Vector3.xAxis)
local guardedSound = actor.sound
local guardedCue = actor.rustleId
actorStep(50.22, roblox.Vector3.xAxis, false)
assert(guardedSound.IsPlaying and guardedSound.PlayCount == 1 and guardedSound.StopCount == 0)
actorStep(50.33, roblox.Vector3.new(80, 0, 0))
assert(guardedSound.IsPlaying and guardedSound.PlayCount == 1, "Teleport preserves existing tail")
actorStep(math.max(actor.untilAt, actor.nextAt) + 0.001, nil, false)
assert(not guardedSound:GetAttribute("AudioRequestedPlaying"))
actorStep(cursor + 0.11, roblox.Vector3.xAxis, false)
assert(guardedSound.PlayCount == 1, "Ineligible actor cannot start another clip")
assert(
	actor.rustleId == guardedCue,
	"Ineligible/teleported/stationary actor emitted a metadata cue"
)

-- The production Step path preserves NPC tails through trapped and caught.
local tailHunt = { root = npcRoot, state = "patrol", destroyed = false }
local tail = Audio.new(world, owner, tailHunt, rand)
npcRoot.Position = roblox.Vector3.new(-80, 3, 20)
step(tail, 60, "active", "hard", tailHunt)
npcRoot.Position += roblox.Vector3.xAxis
step(tail, 60.11, "active", "hard", tailHunt)
local npcSound = tail.npc.sound
local npcCue = tail.npc.rustleId
assert(npcSound.PlayCount == 1 and npcSound.IsPlaying)
tailHunt.state = "trapped"
step(tail, 60.12, "active", "hard", tailHunt)
step(tail, 60.23, "active", "hard", tailHunt)
assert(npcSound.IsPlaying and npcSound.StopCount == 0, "Trap preserves rustle tail")
step(tail, 60.34, "caught", "hard", tailHunt)
assert(npcSound.IsPlaying and npcSound.StopCount == 0, "Capture preserves rustle tail")
step(tail, npcSound.FinishAt + 0.11, "caught", "hard", tailHunt)
assert(npcSound.PlayCount == 1 and not npcSound:GetAttribute("AudioRequestedPlaying"))
assert(tail.npc.rustleId == npcCue, "Trapped/caught NPC emitted a metadata cue")
tailHunt.state = "patrol"
step(tail, npcSound.FinishAt + 0.22, "active", "hard", tailHunt)
assert(npcSound.PlayCount == 1, "Stationary post-catch actor cannot replay")
npcRoot.Position += roblox.Vector3.xAxis
step(tail, npcSound.FinishAt + 0.33, "active", "hard", tailHunt)
assert(npcSound.PlayCount == 2 and npcSound.IsPlaying)
step(tail, virtualNow + 0.001, "escaped", "hard", tailHunt)
assert(tail.destroyed and npcSound.Destroyed and not npcSound.IsPlaying)
local death = Audio.new(world, owner, nil, rand)
step(death, 70, "active", "hard", nil)
ownerRoot.Position += roblox.Vector3.xAxis
step(death, 70.11, "active", "hard", nil)
local dyingSound = death.actors[owner].sound
assert(dyingSound.IsPlaying)
ownerHumanoid.Health = 0
step(death, 70.22, "active", "hard", nil)
assert(not death.actors[owner] and dyingSound.Destroyed and not dyingSound.IsPlaying)
ownerHumanoid.Health = 100
death:Destroy()
cue:Destroy()
local awakeningHunt =
	{ root = npcRoot, home = npcRoot.Position, state = "dormant", destroyed = false }
local wake = Audio.new(world, owner, awakeningHunt, rand)
step(wake, 0, "active", "hard", awakeningHunt)
assert(not wake.wakePlayed and wake.wakeSound.PlayCount == 0)
awakeningHunt.state = "chase"
step(wake, 20, "active", "hard", awakeningHunt)
assert(
	wake.wakePlayed
		and wake.wakeSound.PlayCount == 1
		and wake.wakeSound.RollOffMode == roblox.Enum.RollOffMode.Linear
)
local home = wake.wakeSound.Parent.Position
npcRoot.Position += roblox.Vector3.new(40, 0, 0)
step(wake, 20.5, "active", "hard", awakeningHunt)
assert(wake.wakeSound.Parent.Position == home, "Awakening direction must stay at original home")
for _, sound in wake.voices do
	assert(sound.PlayCount == 0, "Regular voices overlapped awakening scream")
end
step(wake, wake.wakeUntil + 0.01, "active", "hard", awakeningHunt)
assert(wake.wakeSound.PlayCount == 1 and not wake.wakeSound.IsPlaying)
awakeningHunt.state = "dormant"
step(wake, 30, "active", "hard", awakeningHunt)
awakeningHunt.state = "patrol"
step(wake, 31, "active", "hard", awakeningHunt)
assert(wake.wakeSound.PlayCount == 1, "One awakening per round, including home reset")
wake:Destroy()
awakeningHunt.state = "dormant"
wake = Audio.new(world, owner, awakeningHunt, rand)
step(wake, 0, "active", "hard", awakeningHunt)
awakeningHunt.state = "patrol"
step(wake, 20, "active", "hard", awakeningHunt)
step(wake, 20.01, "caught", "hard", awakeningHunt)
assert(
	not wake.wakeSound.IsPlaying and wake.wakeSound.PlayCount == 1,
	"Capture immediately cuts awakening"
)
local ownedScream = wake.wakeSound
local ownedAnchor = ownedScream.Parent
wake:Destroy()
assert(ownedScream.Destroyed and ownedAnchor.Destroyed)

-- Actual RoundAudio Step/envelope logic, virtual natural audio completion.
-- No decoded asset/network/listener claim is inferred from this adapter.
local function cricketAudio()
	local ambient = Audio.new(world, owner, nil, rand)
	assert(#ambient.crickets == 5)
	for index, entry in ambient.crickets do
		assert(entry.offset == (index - 1) * 6 and entry.sound.Looped == false)
		assert(
			entry.sound.Volume == 0 and entry.sound.RollOffMaxDistance == rules.Ranges.Crickets.Max
		)
	end
	return ambient, ambient.crickets[1]
end
local function gain(entry, alpha)
	assert(math.abs(entry.sound.Volume - entry.gain * alpha) < 0.000001, "Wrong cricket envelope")
end
local ambient, cricket = cricketAudio()
for _, sample in
	{
		{ 0, 0 },
		{ 0.25, 0.25 },
		{ 0.5, 0.5 },
		{ 1, 1 },
		{ 7, 1 },
		{ 14, 1 },
		{ 14.5, 0.5 },
		{ 14.9, 0.1 },
		{ 15, 0 },
		{ 15.03, 0 },
		{ 29.99, 0 },
	}
do
	step(ambient, sample[1], "active", "hard", nil)
	gain(cricket, sample[2])
	assert(cricket.sound.PlayCount == 1 and cricket.sound.StopCount == 0)
end
assert(not cricket.sound.IsPlaying and not cricket.sound:GetAttribute("AudioRequestedPlaying"))
step(ambient, 30, "active", "hard", nil)
assert(cricket.sound.PlayCount == 2 and cricket.sound.StopCount == 0)
gain(cricket, 0)
step(ambient, 30.5, "caught", "hard", nil)
gain(cricket, 0.5)
step(ambient, 31, "caught", "hard", nil)
gain(cricket, 1)
step(ambient, 31.1, "escaped", "hard", nil)
assert(ambient.destroyed and cricket.sound.Destroyed and cricket.sound.StopCount == 1)

local short, shortCricket = cricketAudio()
shortCricket.sound.AdapterDuration = 2
for _, sample in
	{
		{ 100, 0 },
		{ 100.5, 0.5 },
		{ 101, 1 },
		{ 101.5, 0.5 },
		{ 101.99, 0.01 },
		{ 102, 0 },
		{ 110, 0 },
	}
do
	step(short, sample[1], "active", "easy", nil)
	gain(shortCricket, sample[2])
	assert(shortCricket.sound.PlayCount == 1 and shortCricket.sound.StopCount == 0)
end
short:Destroy()

local cold, coldCricket = cricketAudio()
coldCricket.sound.IsLoaded = false
coldCricket.sound.AdapterLoadDelay = 0.4
for _, sample in
	{
		{ 200, 0 },
		{ 200.25, 0 },
		{ 200.4, 0 },
		{ 200.9, 0.5 },
		{ 201.4, 1 },
		{ 214.5, 0.5 },
		{ 215, 0 },
		{ 215.5, 0 },
	}
do
	step(cold, sample[1], "active", "medium", nil)
	gain(coldCricket, sample[2])
	assert(coldCricket.sound.PlayCount == 1 and coldCricket.sound.StopCount == 0)
end
assert(not coldCricket.sound.IsPlaying)
cold:Destroy()

local unavailable, missingCricket = cricketAudio()
missingCricket.sound.IsLoaded = false
missingCricket.sound.AdapterLoadDelay = 3
step(unavailable, 300, "active", "hard", nil)
step(unavailable, 300.5, "active", "hard", nil)
gain(missingCricket, 0)
assert(missingCricket.sound.PlayCount == 1 and missingCricket.sound.StopCount == 0)
step(unavailable, 301, "active", "hard", nil)
assert(missingCricket.sound.StopCount == 1 and not missingCricket.sound.PendingPlayback)
missingCricket.sound.IsLoaded = true -- Later background decode may finish, without replaying history.
for _, now in { 303, 310, 315, 329.99 } do
	step(unavailable, now, "active", "hard", nil)
	gain(missingCricket, 0)
	assert(missingCricket.sound.PlayCount == 1 and missingCricket.sound.StopCount == 1)
end
step(unavailable, 330, "active", "hard", nil)
assert(missingCricket.sound.PlayCount == 2 and missingCricket.sound.StopCount == 1)
gain(missingCricket, 0)
step(unavailable, 331, "active", "hard", nil)
gain(missingCricket, 1)
unavailable:Destroy()

local stalled, skippedCricket = cricketAudio()
step(stalled, 400, "active", "hard", nil)
step(stalled, 432, "active", "hard", nil)
step(stalled, 432.5, "active", "hard", nil)
step(stalled, 450, "active", "hard", nil)
assert(skippedCricket.sound.PlayCount == 1 and skippedCricket.sound.StopCount == 0)
step(stalled, 460, "active", "hard", nil)
assert(skippedCricket.sound.PlayCount == 2)
stalled:Destroy()

-- A decode observed only after the deadline remains silent. If it has already
-- begun naturally during a long Step stall, do not cut it or play it again.
local late, lateCricket = cricketAudio()
lateCricket.sound.IsLoaded = false
lateCricket.sound.AdapterLoadDelay = 3
step(late, 500, "active", "hard", nil)
step(late, 503, "active", "hard", nil)
step(late, 503.5, "active", "hard", nil)
gain(lateCricket, 0)
assert(
	lateCricket.sound.IsPlaying
		and lateCricket.sound.PlayCount == 1
		and lateCricket.sound.StopCount == 0
)
step(late, 518.1, "active", "hard", nil)
assert(not lateCricket.sound.IsPlaying and lateCricket.sound.StopCount == 0)
step(late, 530, "active", "hard", nil)
assert(lateCricket.sound.PlayCount == 2)
late:Destroy()

-- Three authoritative NPC sources retain independent corn actor identities.
-- Only the selected threat owns the one three-Sound voice bundle.
local roots, hunts = {}, {}
for index = 1, 5 do
	local root = child("Part", "AudioMonsterRoot" .. index, world.Runtime)
	root.Position = roblox.Vector3.new(-80 + index * 4, 3, 30)
	roots[index] = root
	hunts[index] = { root = root, home = root.Position, state = "patrol", destroyed = false }
end
hunts[1].state, hunts[2].state = "dormant", "chase"
local group = Audio.new(world, owner, hunts[2], rand) -- Group binding corrects an initial selected extra.
local function npcCount()
	local count = 0
	for _ in group.npcActors do
		count += 1
	end
	return count
end
local function voiceCount()
	local count = 0
	for _, item in group.created do
		if item:IsA("Sound") and item:GetAttribute("audio_role"):match("^monster_voice_") then
			count += 1
		end
	end
	return count
end
step(group, 600, "active", "hard", hunts[2], hunts)
assert(npcCount() == 3 and group.npc == group.npcActors[roots[2]] and voiceCount() == 3)
assert(group.primaryHunt == hunts[1] and not group.wakePlayed and group.wakeSound.PlayCount == 0)
local primaryActor, secondActor, thirdActor =
	group.npcActors[roots[1]], group.npcActors[roots[2]], group.npcActors[roots[3]]
for index = 1, 3 do
	roots[index].Position += roblox.Vector3.xAxis
end
step(group, 600.11, "active", "hard", hunts[2], hunts)
assert(primaryActor.sound.PlayCount == 0, "Dormant primary cannot rustle")
assert(secondActor.sound.PlayCount == 1 and thirdActor.sound.PlayCount == 1)
assert(secondActor.sound.IsPlaying and thirdActor.sound.IsPlaying)
step(group, 600.4, "active", "hard", hunts[2], hunts)
local oldVoices = table.clone(group.voices)
local playingVoice = false
for _, sound in oldVoices do
	playingVoice = playingVoice or sound.IsPlaying
end
assert(playingVoice and group.wakeSound.PlayCount == 0, "Extra NPC chase woke the primary emitter")
step(group, 600.401, "active", "hard", hunts[3], hunts)
assert(group.npc == thirdActor and voiceCount() == 3)
assert(group.npcActors[roots[2]] == secondActor and group.npcActors[roots[3]] == thirdActor)
assert(secondActor.sound.IsPlaying and thirdActor.sound.IsPlaying)
assert(secondActor.sound.StopCount == 0 and thirdActor.sound.StopCount == 0)
for _, sound in oldVoices do
	assert(sound.Destroyed and not sound.IsPlaying)
end
for _, sound in group.voices do
	assert(sound.Parent == roots[3])
end
hunts[2].state, hunts[3].state = "capturing", "capturing"
step(group, 600.402, "caught", "hard", hunts[1], hunts)
assert(npcCount() == 3 and group.npc == primaryActor and voiceCount() == 3)
assert(secondActor.sound.IsPlaying and thirdActor.sound.IsPlaying)
assert(secondActor.sound.StopCount == 0 and thirdActor.sound.StopCount == 0)
step(group, 603, "caught", "hard", hunts[1], hunts)
assert(secondActor.sound.PlayCount == 1 and thirdActor.sound.PlayCount == 1)
assert(not secondActor.sound.IsPlaying and not thirdActor.sound.IsPlaying)
assert(secondActor.sound.StopCount == 0 and thirdActor.sound.StopCount == 0)

hunts[1].state, hunts[2].state, hunts[3].state = "patrol", "patrol", "trapped"
for index = 1, 3 do
	roots[index].Position += roblox.Vector3.xAxis
end
step(group, 603.11, "active", "hard", hunts[2], hunts)
assert(group.wakePlayed and group.wakeSound.PlayCount == 1)
assert(
	group.wakeSound.Parent.Position == hunts[1].home,
	"Awakening anchor followed selected extra NPC"
)
assert(
	primaryActor.sound.PlayCount == 1
		and secondActor.sound.PlayCount == 2
		and thirdActor.sound.PlayCount == 1,
	"NPC eligibility was taken from the lead instead of its own hunt"
)

hunts[2].destroyed = true
roots[2].Parent = nil
step(group, 603.12, "active", "hard", hunts[1], hunts)
assert(npcCount() == 2 and group.npcActors[roots[2]] == nil and secondActor.sound.Destroyed)
assert(
	not secondActor.sound.IsPlaying
		and not primaryActor.sound.Destroyed
		and not thirdActor.sound.Destroyed
)
assert(group.npcActors[roots[1]] == primaryActor and group.npcActors[roots[3]] == thirdActor)
step(group, 603.13, "active", "hard", hunts[4], { hunts[1], hunts[3], hunts[4], hunts[5] })
assert(npcCount() == 3 and group.npcActors[roots[5]] == nil and group.npc.root == roots[4])
assert(voiceCount() == 3 and #group.voices == 3 and group.wakeSound.PlayCount == 1)
local remainingNpcSounds = {}
for _, actor in group.npcActors do
	table.insert(remainingNpcSounds, actor.sound)
end
step(group, 603.14, "escaped", "hard", hunts[4], { hunts[1], hunts[3], hunts[4] })
assert(group.destroyed and group.npc == nil and next(group.npcActors) == nil and #group.voices == 0)
for _, sound in remainingNpcSounds do
	assert(sound.Destroyed)
end

-- The same deterministic 12-second route at the unchanged 10 Hz has a
-- quantized cadence; it must not be described as exactly 2x in real time.
local cadence = Audio.new(world, owner, nil, {
	NextInteger = function()
		return 1
	end,
	NextNumber = function(_, low, high)
		return (low + high) / 2
	end,
})
local cadenceActor = cadence:_actor(npcRoot)
local function expectedCues(factor)
	local nextAt, count = 0, 0
	for tick = 1, 120 do
		local now = 1000 + tick / 10
		if now >= nextAt then
			count += 1
			local key = if count % 2 == 1 then "COC_Corn_10" else "COC_Corn_02"
			local anchor = if factor == 2 and count > 1 then math.max(nextAt, now - 0.1) else now
			nextAt = anchor + math.max(0.45, realAssets.Get(key).Duration) / factor
		end
	end
	return count
end
local onsetTimes = {}
for tick = 0, 120 do
	local now = 1000 + tick / 10
	advance(now)
	npcRoot.Position += roblox.Vector3.new(0.6, 0, 0)
	local before = cadenceActor.rustleId
	cadence:_stepActor(cadenceActor, now, true)
	if cadenceActor.rustleId > before then
		table.insert(onsetTimes, now)
	end
end
local previousCount, expectedCount = expectedCues(1), expectedCues(2)
assert(
	cadenceActor.rustleId == expectedCount,
	"Actual production cue count differs from 10 Hz half schedule"
)
assert(
	expectedCount >= previousCount * 1.9 and expectedCount <= previousCount * 2.05,
	"Bounded carry did not retain the doubled continuous cadence"
)
assert(
	cadenceActor.sound.StopCount == 0 and cadenceActor.sound.PlayCount < expectedCount,
	"Faster cues must not restart the server player"
)
local idAtStop = cadenceActor.rustleId
advance(1015)
cadence:_stepActor(cadenceActor, 1015, true)
assert(cadenceActor.rustleId == idAtStop, "Stopped route emitted a new cue")
advance(1015.1)
npcRoot.Position += roblox.Vector3.new(0.6, 0, 0)
cadence:_stepActor(cadenceActor, 1015.1, true)
assert(
	cadenceActor.rustleId == idAtStop + 1 and cadenceActor.nextAt >= 1015.1 + rules.RustleInterval,
	"Resuming after a pause reused historical cadence carry"
)
advance(1015.2)
npcRoot.Position += roblox.Vector3.new(0.6, 0, 0)
cadence:_stepActor(cadenceActor, 1015.2, true)
assert(cadenceActor.rustleId == idAtStop + 1, "Resume produced a catch-up burst")
cadence:Destroy()
print(
	string.format(
		"PASS: same 12-second 10 Hz route old=%d / current=%d cues (%.3fx); no server Stop/restart for busy cues",
		previousCount,
		expectedCount,
		expectedCount / previousCount
	)
)
print(
	"PASS: doubled metadata cue cadence during intact server playback; actor authority/full corn tails/legacy voices; three stable NPC corn sources across lead/caught, own-state eligibility, one voice bundle, primary-only awakening, bounded/gone/terminal cleanup; five nonlooped cricket start/end fades, natural off, cold/stalled/late recovery. Adapter test only; no engine or audible claim."
)
