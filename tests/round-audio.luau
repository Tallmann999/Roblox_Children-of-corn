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
local function make(class)
	return setmetatable({
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
			Health = 100,
			HipHeight = 2,
			RigType = roblox.Enum.HumanoidRigType.R15,
			FloorMaterial = roblox.Enum.Material.Grass,
			PlayCount = 0,
			StopCount = 0,
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
				assert(not self.values.IsPlaying, "Stop the previous clip before replacing SoundId")
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
	self.IsPlaying = true
end
function methods:Stop()
	self.StopCount += 1
	self.IsPlaying = false
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
audio:Step(0, "active", "hard", nil)
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
audio:Step(0.11, "active", "hard", nil)
for _, actor in audio.actors do
	assert(actor.sound:GetAttribute("AudioRequestedPlaying") == true)
end
assert(rayCount == 16 and reads == 1)
local ownerActor = audio.actors[owner]
audio:Step(0.111, "caught", "hard", nil)
assert(
	ownerActor.sound:GetAttribute("AudioRequestedPlaying") == false,
	"Capture stops immediately, even between10Hz polls"
)
for player, actor in audio.actors do
	if player ~= owner then
		assert(actor.sound:GetAttribute("AudioRequestedPlaying") == true)
	end
end
for _, actor in audio.actors do
	actor.root.Position += roblox.Vector3.xAxis
end
audio:Step(0.22, "caught", "hard", nil)
assert(ownerActor.sound:GetAttribute("AudioRequestedPlaying") == false)
local rejected = audio.actors[players[10]]
local human = players[10].Character:FindFirstChildOfClass("Humanoid")
human.FloorMaterial = roblox.Enum.Material.Air
rejected.root.Position += roblox.Vector3.xAxis
audio:Step(0.33, "active", "hard", nil)
assert(rejected.sound:GetAttribute("AudioRequestedPlaying") == false, "Airborne player silent")
human.FloorMaterial = roblox.Enum.Material.Grass
groundHit = false
rejected.root.Position += roblox.Vector3.xAxis
audio:Step(0.44, "active", "hard", nil)
assert(rejected.sound:GetAttribute("AudioRequestedPlaying") == false, "Server ground ray required")
groundHit = true
local oldSound = rejected.sound
human.Health = 0
audio:Step(0.55, "active", "hard", nil)
assert(not audio.actors[players[10]] and oldSound.Destroyed)
character(players[10])
audio:Step(0.66, "active", "hard", nil)
local replaced = audio.actors[players[10]]
assert(
	replaced
		and replaced.sound ~= oldSound
		and replaced.sound:GetAttribute("AudioRequestedPlaying") == false
)
local knownSound = replaced.sound
character(players[10])
audio:Step(0.77, "active", "hard", nil)
assert(knownSound.Destroyed and audio.actors[players[10]].sound ~= knownSound)
for _, actor in audio.actors do
	actor.root.Position += roblox.Vector3.new(80, 0, 0)
end
audio:Step(0.88, "active", "hard", nil)
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
audio:Step(1, "active", "hard", nil)
audio:Destroy()
assert(#audio.created == 0 and actorCount() == 0 and reads == 1)
local npcRoot = child("Part", "MonsterRoot", world.Runtime)
npcRoot.Position = roblox.Vector3.new(-80, 3, 20)
local hunt = { root = npcRoot, state = "chase", destroyed = false }
local cue = Audio.new(world, owner, hunt, rand)
cue:Step(0, "active", "hard", hunt)
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
cue:Step(0.29, "active", "hard", hunt)
assert(requestedVoices() == 0)
cue:Step(0.4, "active", "hard", hunt)
assert(requestedVoices() == 1, "A short chase receives its discovery cue at0.4sec")
local gap = cue.voiceAt - cue.voiceUntil
assert(gap >= rules.VoiceMin and gap <= rules.VoiceMax, "Subsequent silence remains4..7.5sec")
hunt.state = "patrol"
cue:Step(0.401, "active", "hard", hunt)
assert(requestedVoices() == 0, "Losing chase silences initial roar immediately")
-- Use fake nonempty IDs only inside this adapter, to observe restarts/stop ordering.
fixtureId = "rbxassetid://1"
local cursor = 1
npcRoot.Position = roblox.Vector3.new(-80, 3, 20)
cue:_stepActor(cue.npc, cursor, true)
for index = 1, 14 do
	local oldKey = cue.npc.sound:GetAttribute("AudioAssetKey")
	local due = cue.npc.nextAt
	if index == 1 then
		due = cursor + 0.11
	end
	local oldPlayCount = cue.npc.sound.PlayCount
	npcRoot.Position += roblox.Vector3.xAxis
	cue:_stepActor(cue.npc, due, true)
	assert(cue.npc.sound.PlayCount == oldPlayCount + 1, "Moving actor restarts on cadence")
	local key = cue.npc.sound:GetAttribute("AudioAssetKey")
	if index > 1 then
		assert(key ~= oldKey, "Corn clip must not repeat consecutively")
	end
	local interval = math.min(rules.RustleInterval, realAssets.Get(key).Duration)
	assert(
		math.abs(cue.npc.nextAt - due - interval) < 0.000001,
		"No added gap after min(.45,duration)"
	)
	cursor = due
end
assert(cue.npc.sound.StopCount >= 13, "Long rustles are explicitly stopped before replacement")
cue:Destroy()
local awakeningHunt =
	{ root = npcRoot, home = npcRoot.Position, state = "dormant", destroyed = false }
local wake = Audio.new(world, owner, awakeningHunt, rand)
wake:Step(0, "active", "hard", awakeningHunt)
assert(not wake.wakePlayed and wake.wakeSound.PlayCount == 0)
awakeningHunt.state = "chase"
wake:Step(20, "active", "hard", awakeningHunt)
assert(
	wake.wakePlayed
		and wake.wakeSound.PlayCount == 1
		and wake.wakeSound.RollOffMode == roblox.Enum.RollOffMode.Linear
)
local home = wake.wakeSound.Parent.Position
npcRoot.Position += roblox.Vector3.new(40, 0, 0)
wake:Step(20.5, "active", "hard", awakeningHunt)
assert(wake.wakeSound.Parent.Position == home, "Awakening direction must stay at original home")
for _, sound in wake.voices do
	assert(sound.PlayCount == 0, "Regular voices overlapped awakening scream")
end
wake:Step(wake.wakeUntil + 0.01, "active", "hard", awakeningHunt)
assert(wake.wakeSound.PlayCount == 1 and not wake.wakeSound.IsPlaying)
awakeningHunt.state = "dormant"
wake:Step(30, "active", "hard", awakeningHunt)
awakeningHunt.state = "patrol"
wake:Step(31, "active", "hard", awakeningHunt)
assert(wake.wakeSound.PlayCount == 1, "One awakening per round, including home reset")
wake:Destroy()
awakeningHunt.state = "dormant"
wake = Audio.new(world, owner, awakeningHunt, rand)
wake:Step(0, "active", "hard", awakeningHunt)
awakeningHunt.state = "patrol"
wake:Step(20, "active", "hard", awakeningHunt)
wake:Step(20.01, "caught", "hard", awakeningHunt)
assert(
	not wake.wakeSound.IsPlaying and wake.wakeSound.PlayCount == 1,
	"Capture immediately cuts awakening"
)
local ownedScream = wake.wakeSound
local ownedAnchor = ownedScream.Parent
wake:Destroy()
assert(ownedScream.Destroyed and ownedAnchor.Destroyed)
print(
	"PASS: eight-player cap/owner priority, server motion/alive/ground guards, captured-owner silence, replacement/death removal, empty-ID no-Play and strict owned cleanup. Adapter test only; no engine or audible claim."
)
