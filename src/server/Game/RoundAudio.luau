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
local LOOP_KEY = "COC_Corn_Continuous_02"
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

function RoundAudio:_stepCricket(entry: any, now: number)
	local sound = entry.sound
	local elapsed = now - self.startedAt - entry.offset
	local inSlot = Rules.CricketIsOn(now, self.startedAt, entry.offset)
	if sound:GetAttribute("AudioRequestedPlaying") ~= inSlot then
		sound:SetAttribute("AudioRequestedPlaying", inSlot)
	end
	if elapsed < 0 then
		sound.Volume = 0
		return
	end
	local cycle = math.floor(elapsed / Rules.Cycle)
	local slotAt = self.startedAt + entry.offset + cycle * Rules.Cycle
	if cycle ~= entry.cycle then
		-- A stalled/unavailable request stayed silent. Cancel only that
		-- never-decoded attempt before considering a later scheduled slot.
		if entry.requestedAt and not entry.playBeganAt and not entry.abandoned then
			if not sound.IsLoaded and sound.TimePosition == 0 then
				sound:Stop()
			end
		end
		entry.cycle = cycle
		entry.requestedAt, entry.playBeganAt = nil, nil
		entry.abandoned = false
		-- One attempt per slot; no replay of missed slots after a stall.
		if
			inSlot
			and now - slotAt <= Rules.CricketStartWindow
			and sound.SoundId ~= ""
			and not sound.IsPlaying
		then
			sound.Volume = 0
			sound.TimePosition = 0
			entry.requestedAt = now
			entry.startDeadline = slotAt + Rules.CricketStartWindow
			sound:Play()
		end
	end
	if entry.requestedAt and not entry.playBeganAt and not entry.abandoned then
		local progressed = finite(sound.TimePosition) and sound.TimePosition > 0
		if now <= entry.startDeadline and ((sound.IsLoaded and sound.IsPlaying) or progressed) then
			-- Fade from the first observed decode/playback, never jump to the
			-- historical gain of a partially elapsed slot after cold loading.
			entry.playBeganAt = now
		elseif now >= entry.startDeadline then
			entry.abandoned = true
			if not sound.IsLoaded and not progressed then
				sound:Stop()
			end
		end
	end
	local alpha = 0
	if inSlot and entry.playBeganAt and not entry.abandoned and sound.IsPlaying then
		local played = math.max(0, now - entry.playBeganAt)
		local length = entry.duration
		if finite(sound.TimeLength) and sound.TimeLength > 0 then
			length = math.min(length, sound.TimeLength)
		end
		local progress = if finite(sound.TimePosition)
			then math.max(played, sound.TimePosition)
			else played
		alpha = Rules.CricketEnvelope(played, slotAt + Rules.CricketOn - now, length - progress)
	end
	-- Normal off is silence followed by natural Ended, never a timer Stop.
	sound.Volume = entry.gain * alpha
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
		npcActors = {} :: { [BasePart]: any },
		primaryHunt = nil :: any,
		leadHunt = nil :: any,
		voiceRoot = nil :: BasePart?,
		voices = {} :: { Sound },
		voiceBag = {} :: { number },
		voiceLast = 0,
		voiceUntil = 0,
		voiceAt = 0,
		chasing = false,
		wakeObservedDormant = hunt and hunt.state == "dormant",
		wakePlayed = false,
		wakePrimaryRoot = nil :: BasePart?,
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
			false
		)
		local gain = sound.Volume
		sound.Volume = 0
		table.insert(self.crickets, {
			sound = sound,
			offset = (index - 1) * Rules.Cycle / 5,
			gain = gain,
			duration = math.max(0.1, Assets.Get("COC_Crickets_15s").Duration),
			cycle = -1,
			requestedAt = nil,
			playBeganAt = nil,
			abandoned = false,
		})
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

function RoundAudio:_setHunt(hunt: any, hunts: { any }?)
	local desired = {} :: { [BasePart]: any }
	self.primaryHunt = nil
	-- Exactly three authoritative sources, without a Workspace/field scan.
	for index = 1, 3 do
		local source = if hunts then hunts[index] else (if index == 1 then hunt else nil)
		local root = if source and not source.destroyed then source.root else nil
		if root and root:IsA("BasePart") and root.Parent and not desired[root] then
			desired[root] = source
			if index == 1 then
				self.primaryHunt = source
			end
		end
	end
	if not self.wakePlayed then
		local primary = self.primaryHunt
		local root = if primary then primary.root else nil
		if self.wakePrimaryRoot ~= root then
			self.wakePrimaryRoot = root
			self.wakeObservedDormant = primary ~= nil and primary.state == "dormant"
			if primary then
				self.wakeSound.Parent.Position = primary.home or self.world.Field.Position
			end
		elseif primary and primary.state == "dormant" then
			self.wakeObservedDormant = true
		end
	end
	-- Remove only vanished NPCs before adding replacements; the live corn pool
	-- stays bounded at three and lead handoffs never cut another NPC's tail.
	for root, actor in self.npcActors do
		if not desired[root] then
			self:_remove(actor.sound)
			self.npcActors[root] = nil
		end
	end
	for root, source in desired do
		local actor = self.npcActors[root]
		if not actor then
			actor = self:_actor(root)
			self.npcActors[root] = actor
		end
		actor.hunt = source
	end
	local leadRoot = if hunt and not hunt.destroyed then hunt.root else nil
	local selected = if leadRoot then self.npcActors[leadRoot] else nil
	if not selected and self.primaryHunt then
		selected = self.npcActors[self.primaryHunt.root]
	end
	self.npc = selected -- Legacy alias for the selected voice/threat source.
	self.leadHunt = if selected then selected.hunt else nil
	local root = if selected then selected.root else nil
	if self.voiceRoot == root then
		return
	end
	for _, sound in self.voices do
		self:_remove(sound)
	end
	self.voices = {}
	self.voiceRoot = root
	self.voiceBag = {}
	self.voiceLast, self.voiceUntil, self.voiceAt = 0, 0, 0
	self.chasing = false
	if root then
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
	-- This silent Sound is a replicated, owned movement binding only.
	local sound =
		self:_sound(root, LOOP_KEY, "corn_rustle", 0, "Effects", Rules.Ranges.Rustle, true)
	sound:SetAttribute("AudioCornActive", false)
	sound:SetAttribute("AudioCornSpeed", 1)
	return { root = root, sound = sound, lastPosition = nil, lastAt = nil, playbackSpeed = 1 }
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
	local root, sound = actor.root, actor.sound
	local point, before, beforeAt = root.Position, actor.lastPosition, actor.lastAt
	actor.lastPosition, actor.lastAt = point, now
	local dt = if beforeAt then now - beforeAt else 0
	local delta = if before then point - before else Vector3.zero
	local distance = Vector3.new(delta.X, 0, delta.Z).Magnitude
	local moving = dt > 0
		and dt <= 1
		and distance >= 0.05
		and distance <= 12
		and distance / dt <= 45
		and math.abs(delta.Y) < 4
	local active = eligible == true and moving and self:_inCorn(point)
	local speed = 1
	if active then
		local stableRatio = actor.playerSpeed
		local hunt = actor.hunt
		if not stableRatio and hunt then
			local huntSpeed
			local character = self.ownerPlayer.Character
			local playerRoot = if character
				then character:FindFirstChild("HumanoidRootPart")
				else nil
			if hunt.state == "chase" and playerRoot and type(hunt._chaseSpeed) == "function" then
				local ok, value = pcall(hunt._chaseSpeed, hunt, playerRoot, now)
				if ok then
					huntSpeed = value
				end
			elseif hunt.state == "patrol" and type(hunt.balance) == "table" then
				huntSpeed = hunt.balance.monster_patrol_speed
			end
			if type(huntSpeed) == "number" and finite(huntSpeed) and huntSpeed > 0 then
				stableRatio = huntSpeed / 10
			end
		end
		local ratio = stableRatio or distance / dt / 10
		ratio = math.floor(math.clamp(ratio, 1, 2) * 10 + 0.5) / 10
		-- NPC waypoint/physics noise must not modulate pitch every poll.
		speed = if stableRatio or math.abs(ratio - actor.playbackSpeed) >= 0.15
			then ratio
			else actor.playbackSpeed
	end
	actor.playbackSpeed = speed
	if sound:GetAttribute("AudioCornSpeed") ~= speed then
		sound:SetAttribute("AudioCornSpeed", speed)
	end
	if sound:GetAttribute("AudioCornActive") ~= active then
		sound:SetAttribute("AudioCornActive", active)
	end
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
		actor.playerSpeed = if finite(humanoid.WalkSpeed)
			then math.clamp(humanoid.WalkSpeed / 12, 1, 2)
			else 1
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

function RoundAudio:Step(now: number, phase: string, mode: string, hunt: any, hunts: { any }?)
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
	self:_setHunt(hunt, hunts)
	local primary = self.primaryHunt
	if phase == "caught" then
		stop(self.wakeSound)
		self.wakeUntil = 0
	elseif
		not self.wakePlayed
		and self.wakeObservedDormant
		and primary
		and not primary.destroyed
		and primary.state ~= "dormant"
		and primary.state ~= "stopped"
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
		self:_stepCricket(entry, now)
	end
	for _, sound in self.fires do
		request(sound, mode == "medium" or mode == "hard")
	end
	local lead = self.leadHunt
	local chasing = phase == "active" and lead and not lead.destroyed and lead.state == "chase"
	if not chasing then
		for _, sound in self.voices do
			stop(sound)
		end
	elseif not self.chasing then
		self.voiceAt = now + Rules.FirstVoiceDelay
		self.voiceUntil = now
	end
	self.chasing = chasing == true
	if now < self.pollAt then
		return
	end
	self.pollAt = now + 0.1
	if self.chasing then
		self:_voice(now)
	end
	for _, actor in self.npcActors do
		local source = actor.hunt
		local floor = self.world.Ground.Position.Y + self.world.Ground.Size.Y / 2
		self:_stepActor(
			actor,
			now,
			phase == "active"
				and source
				and (source.state == "patrol" or source.state == "chase")
				and math.abs(actor.root.Position.Y - floor - 3) <= 3
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
	self.npcActors = {}
	self.primaryHunt, self.leadHunt, self.voiceRoot = nil, nil, nil
	self.wakePrimaryRoot = nil
end

RoundAudio.Stop = RoundAudio.Destroy

return RoundAudio
