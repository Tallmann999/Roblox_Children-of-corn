--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("GameShared"):WaitForChild("Game")
local Assets = require(Shared:WaitForChild("AudioAssets"))
local Rules = require(Shared:WaitForChild("AudioRules"))
local Layout = require(Shared:WaitForChild("CornLayout"))

local RoundAudio = {}
RoundAudio.__index = RoundAudio

local PROJECT = "children_of_corn"
local CORN_KEYS = Rules.CornKeys
local VOICE_KEYS = Rules.VoiceKeys

local function finite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function owned(item: Instance): boolean
	return item:GetAttribute("CornAudioOwned") == true
		and item:GetAttribute("corn_project_id") == PROJECT
end

local function annotate(item: Instance, role: string)
	item:SetAttribute("CornAudioOwned", true)
	item:SetAttribute("corn_project_id", PROJECT)
	item:SetAttribute("audio_role", role)
end

local function stop(sound: Sound)
	if sound:GetAttribute("AudioRequestedPlaying") ~= false then
		sound:SetAttribute("AudioRequestedPlaying", false)
		sound:Stop()
	end
end

local function request(sound: Sound, playing: boolean)
	if not playing then
		stop(sound)
	elseif sound:GetAttribute("AudioRequestedPlaying") ~= true then
		sound:SetAttribute("AudioRequestedPlaying", true)
		-- An empty ID is configuration awaiting import, not loaded audio.
		if sound.SoundId ~= "" then
			sound:Play()
		end
	end
end

-- Preserve an inserted foreign child even when its owned parent is removed.
local function destroyOwned(item: Instance)
	if not owned(item) then
		return
	end
	local safeParent = item.Parent
	while safeParent and owned(safeParent) do
		safeParent = safeParent.Parent
	end
	local descendants = item:GetDescendants()
	for _, child in descendants do
		if not owned(child) and child.Parent and owned(child.Parent) then
			child.Parent = safeParent
		end
	end
	item:Destroy()
end

function RoundAudio:_remember(item: Instance, role: string)
	annotate(item, role)
	table.insert(self.created, item)
	return item
end

function RoundAudio:_remove(item: Instance)
	if item:IsA("Sound") then
		stop(item)
	end
	destroyOwned(item)
	local index = table.find(self.created, item)
	if index then
		table.remove(self.created, index)
	end
end

function RoundAudio:_sound(
	parent: Instance,
	key: string,
	role: string,
	volume: number,
	category: string,
	range: any,
	looped: boolean
): Sound
	local definition = Assets.Get(key)
	local sound = Instance.new("Sound")
	sound.Name = "CornAudio_" .. role
	self:_remember(sound, role)
	sound:SetAttribute("AudioAssetKey", key)
	sound:SetAttribute("AudioRequestedPlaying", false)
	sound.SoundId = definition.Id
	sound.Volume = math.clamp(volume * definition.Gain, 0, 1)
	sound.Looped = looped
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = range.Min
	sound.RollOffMaxDistance = range.Max
	sound.SoundGroup = self.groups[category]
	sound.Parent = parent
	return sound
end

function RoundAudio.new(world: any, ownerPlayer: Player, hunt: any, random: Random?)
	assert(world.Root and world.Root:IsA("Model"), "Round audio requires a bound map")
	assert(world.Field and world.Field:IsA("BasePart"), "Round audio requires Field")
	assert(world.Runtime and world.Ground, "Round audio requires runtime and Ground")
	local self = setmetatable({
		world = world,
		ownerPlayer = ownerPlayer,
		random = random or Random.new(),
		created = {} :: { Instance },
		groups = {} :: { [string]: SoundGroup },
		crickets = {},
		fires = {} :: { Sound },
		actors = {} :: { [Player]: any },
		npc = nil :: any,
		voices = {} :: { Sound },
		voiceBag = {} :: { number },
		voiceLast = 0,
		voiceUntil = 0,
		voiceAt = 0,
		chasing = false,
		wakeObservedDormant = hunt and hunt.state == "dormant",
		wakePlayed = false,
		wakeUntil = 0,
		startedAt = nil :: number?,
		pollAt = -math.huge,
		destroyed = false,
		exclusions = Layout.ReadExclusions(world.Root, world.Field),
	}, RoundAudio)
	local id = HttpService:GenerateGUID(false)
	local folder = Instance.new("Folder")
	folder.Name = "CornRoundAudio_" .. id
	self:_remember(folder, "runtime")
	folder.Parent = world.Runtime
	self.folder = folder
	local wakeAnchor = Instance.new("Part")
	wakeAnchor.Name = "AwakeningEmitter"
	self:_remember(wakeAnchor, "awakening_emitter")
	wakeAnchor:AddTag("corn_audio_emitter")
	wakeAnchor.Size = Vector3.one
	wakeAnchor.Transparency = 1
	wakeAnchor.Anchored = true
	wakeAnchor.CanCollide = false
	wakeAnchor.CanTouch = false
	wakeAnchor.CanQuery = false
	wakeAnchor.CastShadow = false
	wakeAnchor.Position = if hunt and hunt.home then hunt.home else world.Field.Position
	wakeAnchor.Parent = folder
	local groupsFolder = Instance.new("Folder")
	groupsFolder.Name = "CornRoundAudio_" .. id
	self:_remember(groupsFolder, "groups")
	groupsFolder.Parent = SoundService
	for _, category in { "Music", "Ambience", "Effects" } do
		local group = Instance.new("SoundGroup")
		group.Name = category
		self:_remember(group, "group_" .. category)
		group.Volume = math.clamp(Rules.Mix.Master * Rules.Mix[category], 0, 1)
		group.Parent = groupsFolder
		self.groups[category] = group
	end
	self.wakeSound = self:_sound(
		wakeAnchor,
		"COC_Monster_03",
		"awakening",
		Rules.Volume.Awakening,
		"Effects",
		Rules.Ranges.Awakening,
		false
	)
	self.wakeSound.RollOffMode = Enum.RollOffMode.Linear
	local half = world.Field.Size / 2
	for index, offset in
		{
			Vector2.new(-0.62, -0.62),
			Vector2.new(0.62, -0.62),
			Vector2.new(0, 0),
			Vector2.new(-0.62, 0.62),
			Vector2.new(0.62, 0.62),
		}
	do
		local anchor = Instance.new("Part")
		anchor.Name = "Crickets" .. index
		self:_remember(anchor, "crickets_emitter")
		anchor:AddTag("corn_audio_emitter")
		anchor.Size = Vector3.one
		anchor.Transparency = 1
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanTouch = false
		anchor.CanQuery = false
		anchor.CastShadow = false
		anchor.Position = world.Field.CFrame:PointToWorldSpace(
			Vector3.new(offset.X * half.X, -half.Y + 1, offset.Y * half.Z)
		)
		anchor.Parent = folder
		local sound = self:_sound(
			anchor,
			"COC_Crickets_15s",
			"crickets",
			Rules.Volume.Crickets,
			"Ambience",
			Rules.Ranges.Crickets,
			true
		)
		table.insert(self.crickets, { sound = sound, offset = (index - 1) * Rules.Cycle / 5 })
	end
	local markers = world.Root:FindFirstChild("TorchMarkers")
	if
		markers
		and markers:GetAttribute("CornTorchMarkersOwned") == true
		and markers:GetAttribute("corn_project_id") == PROJECT
	then
		for _, torch in markers:GetChildren() do
			if
				torch:IsA("Model")
				and torch:GetAttribute("CornTorchOwned") == true
				and torch:GetAttribute("corn_project_id") == PROJECT
				and torch:HasTag("corn_torch")
			then
				local flame = torch:FindFirstChild("Flame")
				if flame and flame:IsA("BasePart") then
					table.insert(
						self.fires,
						self:_sound(
							flame,
							"COC_Fire",
							"fire",
							Rules.Volume.Fire,
							"Ambience",
							Rules.Ranges.Fire,
							true
						)
					)
				end
			end
		end
	end
	self:_setHunt(hunt)
	return self
end

function RoundAudio:_setHunt(hunt: any)
	if not self.wakePlayed and hunt and hunt.state == "dormant" then
		self.wakeObservedDormant = true
	end
	local root = if hunt and not hunt.destroyed then hunt.root else nil
	if root and not root.Parent then
		root = nil
	end
	if self.npc and self.npc.root == root then
		return
	end
	if self.npc then
		self:_remove(self.npc.sound)
	end
	for _, sound in self.voices do
		self:_remove(sound)
	end
	self.voices = {}
	self.npc = nil
	self.chasing = false
	if root and root:IsA("BasePart") and root.Parent then
		self.npc = self:_actor(root)
		for index, key in VOICE_KEYS do
			self.voices[index] = self:_sound(
				root,
				key,
				"monster_voice_" .. index,
				Rules.Volume.Monster,
				"Effects",
				Rules.Ranges.Monster,
				false
			)
		end
	end
end

function RoundAudio:_actor(root: BasePart): any
	return {
		root = root,
		sound = self:_sound(
			root,
			CORN_KEYS[1],
			"corn_rustle",
			Rules.Volume.Rustle,
			"Effects",
			Rules.Ranges.Rustle,
			false
		),
		lastPosition = nil,
		lastAt = nil,
		lastClip = 0,
		untilAt = 0,
		nextAt = 0,
	}
end

function RoundAudio:_inCorn(point: Vector3): boolean
	local field = self.world.Field
	local at = field.CFrame:PointToObjectSpace(point)
	local half = field.Size / 2
	return math.abs(at.X) <= half.X
		and math.abs(at.Z) <= half.Z
		and not Layout.IsExcluded(point, self.exclusions)
end

function RoundAudio:_stepActor(actor: any, now: number, eligible: boolean)
	local root = actor.root
	local point = root.Position
	local before = actor.lastPosition
	local beforeAt = actor.lastAt
	actor.lastPosition = point
	actor.lastAt = now
	local dt = if beforeAt then now - beforeAt else 0
	local delta = if before then point - before else Vector3.zero
	local distance = Vector3.new(delta.X, 0, delta.Z).Magnitude
	-- Clear discontinuities instead of turning spawn/teleport into a loud footstep.
	local moving = dt > 0
		and dt <= 1
		and distance >= 0.05
		and distance <= 12
		and distance / dt <= 45
		and math.abs(delta.Y) < 4
	if not eligible or not moving or not self:_inCorn(point) then
		stop(actor.sound)
		actor.untilAt = 0
		actor.nextAt = now
		return
	end
	if now >= actor.untilAt then
		stop(actor.sound)
	end
	if now < actor.nextAt then
		return
	end
	local index = self.random:NextInteger(1, #CORN_KEYS - 1)
	if index >= actor.lastClip then
		index += 1
	end
	if index > #CORN_KEYS then
		index = 1
	end
	actor.lastClip = index
	local definition = Assets.Get(CORN_KEYS[index])
	-- The cadence can cut a long clip short. Stop before replacing its URI,
	-- so one actor never layers an old rustle under the next one.
	stop(actor.sound)
	actor.sound.SoundId = definition.Id
	actor.sound:SetAttribute("AudioAssetKey", CORN_KEYS[index])
	actor.sound.Volume = math.clamp(Rules.Volume.Rustle * definition.Gain, 0, 1)
	local duration = math.max(0.1, definition.Duration)
	actor.untilAt = now + duration
	actor.nextAt = now + math.min(Rules.RustleInterval, duration)
	request(actor.sound, true)
end

function RoundAudio:_grounded(character: Model, humanoid: Humanoid, root: BasePart): boolean
	if humanoid.Health <= 0 or humanoid.FloorMaterial == Enum.Material.Air then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	local legHeight = 0
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		local leg = character:FindFirstChild("Left Leg")
		if leg and leg:IsA("BasePart") then
			legHeight = leg.Size.Y
		end
	end
	local length = math.max(3, legHeight + humanoid.HipHeight + root.Size.Y / 2 + 2)
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -length, 0), params)
	return hit ~= nil and hit.Instance == self.world.Ground
end

function RoundAudio:_players(now: number, phase: string)
	local players = Players:GetPlayers()
	table.sort(players, function(a, b)
		if a == b then
			return false
		elseif a == self.ownerPlayer then
			return true
		elseif b == self.ownerPlayer then
			return false
		end
		return a.UserId < b.UserId
	end)
	local alive: { [Player]: boolean } = {}
	for index, player in players do
		if index > Rules.ActorLimit then
			break
		end
		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if
			not character
			or not humanoid
			or not root
			or not root:IsA("BasePart")
			or humanoid.Health <= 0
		then
			continue
		end
		alive[player] = true
		local actor = self.actors[player]
		if actor and actor.root ~= root then
			self:_remove(actor.sound)
			actor = nil
		end
		if not actor then
			actor = self:_actor(root)
			self.actors[player] = actor
		end
		self:_stepActor(
			actor,
			now,
			(phase == "active" or player ~= self.ownerPlayer)
				and self:_grounded(character, humanoid, root)
		)
	end
	for player, actor in self.actors do
		if not alive[player] then
			self:_remove(actor.sound)
			self.actors[player] = nil
		end
	end
end

function RoundAudio:_voice(now: number)
	if now < self.wakeUntil then
		return
	end
	if now >= self.voiceUntil then
		for _, sound in self.voices do
			stop(sound)
		end
	end
	if now < self.voiceAt or #self.voices ~= 3 then
		return
	end
	if #self.voiceBag == 0 then
		self.voiceBag = { 1, 2, 3 }
		for index = #self.voiceBag, 2, -1 do
			local other = self.random:NextInteger(1, index)
			self.voiceBag[index], self.voiceBag[other] = self.voiceBag[other], self.voiceBag[index]
		end
		if self.voiceBag[1] == self.voiceLast then
			self.voiceBag[1], self.voiceBag[2] = self.voiceBag[2], self.voiceBag[1]
		end
	end
	local index = table.remove(self.voiceBag, 1)
	self.voiceLast = index
	local sound = self.voices[index]
	local definition = Assets.Get(VOICE_KEYS[index])
	self.voiceUntil = now + math.max(0.1, definition.Duration, sound.TimeLength)
	self.voiceAt = self.voiceUntil + self.random:NextNumber(Rules.VoiceMin, Rules.VoiceMax)
	request(sound, true)
end

function RoundAudio:Step(now: number, phase: string, mode: string, hunt: any)
	if self.destroyed or not finite(now) then
		return
	end
	if phase ~= "active" and phase ~= "caught" then
		self:Destroy()
		return
	end
	if not self.startedAt then
		self.startedAt = now
	end
	self:_setHunt(hunt)
	if phase == "caught" then
		stop(self.wakeSound)
		self.wakeUntil = 0
	elseif
		not self.wakePlayed
		and self.wakeObservedDormant
		and hunt
		and not hunt.destroyed
		and hunt.state ~= "dormant"
		and hunt.state ~= "stopped"
	then
		self.wakePlayed = true
		self.wakeUntil = now
			+ math.max(Assets.Get("COC_Monster_03").Duration, self.wakeSound.TimeLength)
		for _, sound in self.voices do
			stop(sound)
		end
		request(self.wakeSound, true)
	elseif self.wakePlayed and now >= self.wakeUntil then
		stop(self.wakeSound)
	end
	for _, entry in self.crickets do
		request(entry.sound, Rules.CricketIsOn(now, self.startedAt, entry.offset))
	end
	for _, sound in self.fires do
		request(sound, mode == "medium" or mode == "hard")
	end
	local chasing = phase == "active" and hunt and not hunt.destroyed and hunt.state == "chase"
	if not chasing then
		for _, sound in self.voices do
			stop(sound)
		end
	elseif not self.chasing then
		self.voiceAt = now + Rules.FirstVoiceDelay
		self.voiceUntil = now
	end
	self.chasing = chasing == true
	if phase == "caught" then
		local owner = self.actors[self.ownerPlayer]
		if owner then
			stop(owner.sound)
		end
	end
	if
		self.npc
		and (phase ~= "active" or not hunt or (hunt.state ~= "patrol" and hunt.state ~= "chase"))
	then
		stop(self.npc.sound)
	end
	if now < self.pollAt then
		return
	end
	self.pollAt = now + 0.1
	if self.chasing then
		self:_voice(now)
	end
	if self.npc then
		local floor = self.world.Ground.Position.Y + self.world.Ground.Size.Y / 2
		self:_stepActor(
			self.npc,
			now,
			phase == "active"
				and hunt
				and (hunt.state == "patrol" or hunt.state == "chase")
				and math.abs(self.npc.root.Position.Y - floor - 3) <= 3
		)
	end
	self:_players(now, phase)
end

function RoundAudio:Destroy()
	if self.destroyed then
		return
	end
	self.destroyed = true
	for index = #self.created, 1, -1 do
		local item = self.created[index]
		if item:IsA("Sound") then
			stop(item)
		end
		destroyOwned(item)
	end
	self.created = {}
	self.actors = {}
	self.voices = {}
	self.fires = {}
	self.crickets = {}
	self.npc = nil
end

RoundAudio.Stop = RoundAudio.Destroy

return RoundAudio
