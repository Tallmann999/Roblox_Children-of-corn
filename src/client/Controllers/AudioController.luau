--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local Shared = ReplicatedStorage:WaitForChild("GameShared"):WaitForChild("Game")
local Inventory = require(Shared:WaitForChild("Inventory"))
local Assets = require(Shared:WaitForChild("AudioAssets"))
local Rules = require(Shared:WaitForChild("AudioRules"))
local player = Players.LocalPlayer
local PROJECT = "children_of_corn"
local FOLDER_NAME = "CornPersonalAudio"
local RESOLVE_INTERVAL = 0.25
local PRELOAD_TIMEOUT = 8
local DEFAULT_FOOTSTEPS = "rbxasset://sounds/action_footsteps_plastic.mp3"
local FOOTSTEP_NAMES = { "Running", "Climbing" }
local definitions = {
	Background = { key = "COC_Background_02", category = "Music", looped = true },
	Hunt = { key = "COC_Hunt", category = "Music", looped = true },
	Energy = { key = "COC_Energy_Open", category = "Effects", looped = false },
	Trap = { key = "COC_Trap_Place", category = "Effects", looped = false },
}
local Controller = { Name = "AudioController", Order = 98 }

local function owned(instance: Instance?): boolean
	return instance ~= nil
		and instance:GetAttribute("CornAudioOwned") == true
		and instance:GetAttribute("corn_project_id") == PROJECT
		and instance:GetAttribute("AudioVersion") == 1
end

local function annotate(instance: Instance, role: string)
	instance:SetAttribute("CornAudioOwned", true)
	instance:SetAttribute("corn_project_id", PROJECT)
	instance:SetAttribute("AudioVersion", 1)
	instance:SetAttribute("audio_role", role)
end

function Controller:Init(_context: any)
	self._snapshot = nil
	self._roundId = -1
	self._useId = 0
	self._endedRound = nil
	self._folder = nil
	self._folderName = FOLDER_NAME
	self._groups = {}
	self._sounds = {}
	self._connections = {}
	self._monster = nil
	self._monsterRoot = nil
	self._monsters = {}
	self._resolveAt = 0
	self._capture = nil
	self._background = 0
	self._hunt = 0
	self._generation = 0
	self._preload = nil
	self._refused = nil
	self._started = false
	self._footstepPlayers = {}
	self._footstepPlayerCount = 0
	self._rustles = {}
	self._rustleCount = 0
	self._rustleResolveAt = 0
end

local function disconnect(entries: { RBXScriptConnection })
	for _, connection in entries do
		connection:Disconnect()
	end
	table.clear(entries)
end

local function serverRustle(sound: Instance?, root: BasePart): boolean
	if
		not (
			sound ~= nil
			and sound:IsA("Sound")
			and sound.Parent == root
			and sound.Name == "CornAudio_corn_rustle"
			and sound:GetAttribute("CornAudioOwned") == true
			and sound:GetAttribute("corn_project_id") == PROJECT
			and sound:GetAttribute("audio_role") == "corn_rustle"
		)
	then
		return false
	end
	for _, key in Rules.CornKeys do
		local asset = Assets.Get(key)
		if asset and asset.Id == (sound :: Sound).SoundId then
			return true
		end
	end
	return false
end

local function rustleCommit(source: Sound): any
	local value = source:GetAttribute("AudioRustleStart")
	if type(value) ~= "string" or #value > 80 then
		return nil
	end
	local rawId, key = string.match(value, "^([1-9]%d*):([%w_]+)$")
	local id = tonumber(rawId)
	if not id or id >= 9007199254740992 or id % 1 ~= 0 or not table.find(Rules.CornKeys, key) then
		return nil
	end
	local asset = Assets.Get(key)
	return if asset and string.match(asset.Id, "^rbxassetid://[1-9]%d*$")
		then { id = id, key = key, asset = asset }
		else nil
end

function Controller:_muteRustle(entry: any)
	if
		not entry.released
		and serverRustle(entry.source, entry.root)
		and entry.source.Volume ~= 0
	then
		entry.previousVolume = entry.source.Volume
		entry.source.Volume = 0
	end
end

function Controller:_releaseRustle(root: BasePart)
	local entry = self._rustles[root]
	if not entry or entry.released then
		return
	end
	entry.released = true
	disconnect(entry.connections)
	for _, voice in entry.voices do
		local sound = voice.sound
		if owned(sound) and sound.Parent == root then
			-- Preserve a foreign child inserted under either owned local player.
			for _, child in sound:GetChildren() do
				if not owned(child) then
					child.Parent = root
				end
			end
			sound:Destroy()
		end
	end
	if
		entry.previousVolume ~= nil
		and serverRustle(entry.source, root)
		and entry.source.Volume == 0
	then
		local recognizedId = false
		for _, key in Rules.CornKeys do
			local asset = Assets.Get(key)
			if asset and asset.Id == entry.source.SoundId then
				recognizedId = true
				break
			end
		end
		if recognizedId then
			entry.source.Volume = entry.previousVolume
		end
	end
	self._rustles[root] = nil
	self._rustleCount -= 1
end

function Controller:_clearRustles()
	for root in self._rustles do
		self:_releaseRustle(root)
	end
	self._rustleResolveAt = 0
end

local function rustleVoicesOwned(entry: any): boolean
	for _, voice in entry.voices do
		if not owned(voice.sound) or voice.sound.Parent ~= entry.root then
			return false
		end
	end
	return true
end

function Controller:_tryRustle(entry: any, now: number)
	if entry.released or not entry.pending or now < entry.retryAt then
		return
	end
	if not rustleVoicesOwned(entry) or not serverRustle(entry.source, entry.root) then
		return
	end
	for _, voice in entry.voices do
		if not voice.active and not voice.deferStart then
			local sound, clip = voice.sound, entry.pending
			entry.pending, voice.current = nil, clip
			voice.active, voice.started = true, false
			voice.loadDeadline = now + PRELOAD_TIMEOUT
			sound.SoundId = clip.asset.Id
			sound.Volume = math.clamp(Rules.Volume.Rustle * clip.asset.Gain, 0, 1)
			sound:SetAttribute("AudioRustleId", clip.id)
			sound:SetAttribute("AudioAssetKey", clip.key)
			sound:Play()
			return
		end
	end
end

function Controller:_acceptRustle(entry: any, initial: boolean)
	if entry.released or not serverRustle(entry.source, entry.root) then
		return
	end
	local clip = rustleCommit(entry.source)
	if not clip or clip.id <= entry.lastId then
		return
	end
	entry.lastId = clip.id
	if initial and entry.source:GetAttribute("AudioRequestedPlaying") ~= true then
		return
	end
	entry.pending = clip -- Latest only: at most one future clip per actor.
	self:_tryRustle(entry, os.clock())
end

function Controller:_bindRustle(root: BasePart, source: Sound): any
	local old = self._rustles[root]
	if old and (old.released or old.source == source) then
		return old
	end
	if old then
		self:_releaseRustle(root)
	end
	if
		self._rustleCount >= Rules.ActorLimit + 3
		or not serverRustle(source, root)
		or not owned(self._groups.Effects)
	then
		return nil
	end
	local group = source.SoundGroup
	if
		not group
		or group:GetAttribute("CornAudioOwned") ~= true
		or group:GetAttribute("corn_project_id") ~= PROJECT
	then
		group = self._groups.Effects
	end
	local function voiceSound(index: number): Sound
		local sound = Instance.new("Sound")
		sound.Name = if index == 1 then "CornLocalRustle" else "CornLocalRustle" .. index
		annotate(sound, "corn_rustle_local")
		sound.Looped = false
		sound.PlaybackSpeed = 1
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = Rules.Ranges.Rustle.Min
		sound.RollOffMaxDistance = Rules.Ranges.Rustle.Max
		sound.SoundGroup = group
		return sound
	end
	local entry = {
		root = root,
		source = source,
		sound = voiceSound(1),
		connections = {},
		lastId = 0,
		active = false,
		started = false,
		released = false,
		retryAt = 0,
	}
	entry.voices = { entry }
	for index = 2, Rules.RustleVoices do
		table.insert(entry.voices, {
			sound = voiceSound(index),
			active = false,
			started = false,
		})
	end
	self._rustles[root] = entry
	self._rustleCount += 1
	for _, voice in entry.voices do
		-- Register the full fixed pool before Root.ChildAdded can reenter
		-- the existing footsteps/rustle binder for either local Sound.
		voice.sound.Parent = root
		table.insert(
			entry.connections,
			voice.sound.Ended:Connect(function()
				if entry.released or self._rustles[root] ~= entry then
					return
				end
				voice.active, voice.started, voice.current = false, false, nil
				-- A completed voice is reused on the next heartbeat, after every
				-- Ended listener has observed its URI and natural completion.
				voice.deferStart = true
			end)
		)
	end
	table.insert(
		entry.connections,
		source:GetAttributeChangedSignal("AudioRustleStart"):Connect(function()
			self:_acceptRustle(entry, false)
		end)
	)
	table.insert(
		entry.connections,
		source:GetPropertyChangedSignal("Volume"):Connect(function()
			self:_muteRustle(entry)
		end)
	)
	self:_muteRustle(entry)
	self:_acceptRustle(entry, true)
	return entry
end

function Controller:_refreshRustle(root: BasePart?)
	if not root then
		return
	end
	local source = root:FindFirstChild("CornAudio_corn_rustle")
	local current = self._rustles[root]
	if current and current.released then
		return
	end
	if not serverRustle(source, root) then
		self:_releaseRustle(root)
	elseif
		self._snapshot and (self._snapshot.phase == "active" or self._snapshot.phase == "caught")
	then
		self:_bindRustle(root, source :: Sound)
	end
end

function Controller:_stepRustles(now: number)
	local snapshot = self._snapshot
	if
		not snapshot
		or (snapshot.phase ~= "active" and snapshot.phase ~= "caught")
		or not self:_livingRoot()
	then
		self:_clearRustles()
		return
	end
	if now >= self._rustleResolveAt then
		self._rustleResolveAt = now + RESOLVE_INTERVAL
		local allowed = {}
		for _, state in self._footstepPlayers do
			local humanoid = if state.character
				then state.character:FindFirstChildOfClass("Humanoid")
				else nil
			if
				state.root
				and state.root.Parent == state.character
				and humanoid
				and humanoid.Health > 0
			then
				allowed[state.root] = true
				self:_refreshRustle(state.root)
			end
		end
		self:_resolveMonster(now)
		for _, actor in self._monsters do
			allowed[actor.root] = true
			self:_refreshRustle(actor.root)
		end
		for root in self._rustles do
			if not allowed[root] then
				self:_releaseRustle(root)
			end
		end
	end
	for root, entry in self._rustles do
		if
			not root.Parent
			or not serverRustle(entry.source, root)
			or not rustleVoicesOwned(entry)
		then
			self:_releaseRustle(root)
		else
			for _, voice in entry.voices do
				voice.deferStart = false
				local sound = voice.sound
				if voice.active then
					voice.started = voice.started
						or sound.TimePosition > 0
						or (sound.IsLoaded and sound.IsPlaying)
					if not voice.started and now >= voice.loadDeadline then
						-- Retry only the newest unplayed request; a newer accepted
						-- cue on either voice must never revive an old failed clip.
						sound:Stop()
						if not entry.pending and voice.current.id == entry.lastId then
							entry.pending = voice.current
						end
						voice.current, voice.active = nil, false
						entry.retryAt = now + 0.5
					end
				end
			end
			self:_tryRustle(entry, now)
		end
	end
end

local function defaultFootstep(entry: any): boolean
	return entry.sound.Parent == entry.root
		and entry.root.Parent == entry.character
		and entry.root.Name == "HumanoidRootPart"
		and entry.sound.Name == entry.name
		and entry.sound.SoundId == DEFAULT_FOOTSTEPS
end

function Controller:_muteFootstep(entry: any)
	if not entry.released and defaultFootstep(entry) then
		if entry.previous == nil then
			entry.previous = entry.sound.Volume
		end
		if entry.sound.Volume ~= 0 then
			entry.sound.Volume = 0
		end
	end
end

function Controller:_releaseFootstep(entry: any)
	entry.released = true
	disconnect(entry.connections)
	if entry.previous ~= nil and defaultFootstep(entry) and entry.sound.Volume == 0 then
		entry.sound.Volume = entry.previous
	end
end

function Controller:_refreshFootsteps(state: any)
	local root = state.root
	for _, name in FOOTSTEP_NAMES do
		local candidate = if root then root:FindFirstChild(name) else nil
		if candidate and not candidate:IsA("Sound") then
			candidate = nil
		end
		local old = state.sounds[name]
		if old and old.sound ~= candidate then
			self:_releaseFootstep(old)
			state.sounds[name] = nil
		end
		if candidate and not state.sounds[name] then
			local entry = {
				sound = candidate,
				root = root,
				character = state.character,
				name = name,
				released = false,
				connections = {},
			}
			state.sounds[name] = entry
			for _, property in { "SoundId", "Volume" } do
				table.insert(
					entry.connections,
					candidate:GetPropertyChangedSignal(property):Connect(function()
						self:_muteFootstep(entry)
					end)
				)
			end
			table.insert(
				entry.connections,
				candidate:GetPropertyChangedSignal("Name"):Connect(function()
					self:_refreshFootsteps(state)
				end)
			)
		end
		if state.sounds[name] then
			self:_muteFootstep(state.sounds[name])
		end
	end
	self:_refreshRustle(root)
end

function Controller:_bindFootstepRoot(state: any)
	local candidate = if state.character
		then state.character:FindFirstChild("HumanoidRootPart")
		else nil
	if candidate and not candidate:IsA("BasePart") then
		candidate = nil
	end
	if candidate == state.root then
		return
	end
	disconnect(state.rootConnections)
	if state.root then
		self:_releaseRustle(state.root)
	end
	for _, entry in state.sounds do
		self:_releaseFootstep(entry)
	end
	table.clear(state.sounds)
	state.root = candidate
	if candidate then
		for _, event in { candidate.ChildAdded, candidate.ChildRemoved } do
			table.insert(
				state.rootConnections,
				event:Connect(function()
					self:_refreshFootsteps(state)
				end)
			)
		end
		table.insert(
			state.rootConnections,
			candidate:GetPropertyChangedSignal("Name"):Connect(function()
				self:_bindFootstepRoot(state)
			end)
		)
		self:_refreshFootsteps(state)
	end
end

function Controller:_bindFootstepCharacter(state: any, character: Model?)
	if state.root then
		self:_releaseRustle(state.root)
	end
	disconnect(state.characterConnections)
	disconnect(state.rootConnections)
	for _, entry in state.sounds do
		self:_releaseFootstep(entry)
	end
	table.clear(state.sounds)
	state.character, state.root = character, nil
	if character then
		for _, event in { character.ChildAdded, character.ChildRemoved } do
			table.insert(
				state.characterConnections,
				event:Connect(function()
					self:_bindFootstepRoot(state)
				end)
			)
		end
		self:_bindFootstepRoot(state)
	end
end

function Controller:_watchFootstepPlayer(target: Player)
	if self._footstepPlayers[target] or self._footstepPlayerCount >= 8 then
		return
	end
	local state = { connections = {}, characterConnections = {}, rootConnections = {}, sounds = {} }
	self._footstepPlayers[target] = state
	self._footstepPlayerCount += 1
	table.insert(
		state.connections,
		target.CharacterAdded:Connect(function(character: Model)
			if self._footstepPlayers[target] ~= state then
				return
			end
			if target == player then
				self:Clear("character changed")
			end
			self:_bindFootstepCharacter(state, character)
		end)
	)
	table.insert(
		state.connections,
		target.CharacterRemoving:Connect(function(character: Model)
			if self._footstepPlayers[target] ~= state then
				return
			end
			if target == player then
				self:Clear("character changed")
			end
			if state.character == character then
				self:_bindFootstepCharacter(state, nil)
			end
		end)
	)
	self:_bindFootstepCharacter(state, target.Character)
end

function Controller:_releaseFootstepPlayer(target: Player)
	local state = self._footstepPlayers[target]
	if state then
		disconnect(state.connections)
		self:_bindFootstepCharacter(state, nil)
		self._footstepPlayers[target] = nil
		self._footstepPlayerCount -= 1
	end
end

function Controller:_startFootsteps()
	for _, target in Players:GetPlayers() do
		self:_watchFootstepPlayer(target)
	end
	table.insert(
		self._connections,
		Players.PlayerAdded:Connect(function(target: Player)
			if self._started then
				self:_watchFootstepPlayer(target)
			end
		end)
	)
	table.insert(
		self._connections,
		Players.PlayerRemoving:Connect(function(target: Player)
			self:_releaseFootstepPlayer(target)
		end)
	)
end

function Controller:_soundValid(entry: any): boolean
	return entry ~= nil
		and owned(self._folder)
		and self._folder.Parent == SoundService
		and owned(entry.sound)
		and entry.sound.Parent == self._folder
		and owned(entry.group)
		and entry.group.Parent == self._folder
		and entry.sound.SoundGroup == entry.group
end

function Controller:_stop(entry: any)
	if self:_soundValid(entry) then
		entry.sound:Stop()
		entry.sound.Volume = 0
	end
	if entry then
		entry.playing = false
		entry.deadline = nil
	end
end

function Controller:_stopAll()
	self._background, self._hunt = 0, 0
	for _, entry in self._sounds do
		self:_stop(entry)
	end
end

function Controller:Clear(_reason: string?)
	self._snapshot = nil
	self:_clearRustles()
	self._monster, self._monsterRoot = nil, nil
	self._monsters = {}
	self._resolveAt = 0
	self:_stopAll()
end

function Controller:_build(): boolean
	if self._folder then
		return owned(self._folder) and self._folder.Parent == SoundService
	end
	local existing = SoundService:FindFirstChild(self._folderName)
	if existing then
		if self._refused ~= existing then
			self._refused = existing
			warn("[AudioController] Existing personal audio folder preserved; ownership refused")
		end
		return false
	end
	local folder = Instance.new("Folder")
	folder.Name = self._folderName
	annotate(folder, "personal")
	self._folder = folder
	for _, category in { "Music", "Effects" } do
		local group = Instance.new("SoundGroup")
		group.Name = category
		group.Volume = math.clamp(Rules.Mix.Master * Rules.Mix[category], 0, 1)
		annotate(group, string.lower(category))
		group.Parent = folder
		self._groups[category] = group
	end
	for role, definition in definitions do
		local asset = Assets.Get(definition.key)
		if
			asset
			and type(asset.Id) == "string"
			and string.match(asset.Id, "^rbxassetid://[1-9]%d*$")
		then
			local sound = Instance.new("Sound")
			sound.Name = role
			sound.SoundId = asset.Id
			sound.Volume = 0
			sound.Looped = definition.looped
			sound.SoundGroup = self._groups[definition.category]
			annotate(sound, string.lower(role))
			sound.Parent = folder
			local entry = {
				sound = sound,
				group = sound.SoundGroup,
				gain = math.clamp(asset.Gain * Rules.Volume[role], 0, 1),
				duration = asset.Duration,
				playing = false,
				failed = false,
			}
			self._sounds[role] = entry
			if not definition.looped then
				table.insert(
					self._connections,
					sound.Ended:Connect(function()
						self:_stop(entry)
					end)
				)
			end
		end
	end
	folder.Parent = SoundService
	return true
end

function Controller:_preloadAssets()
	local ids = {}
	local seen = {}
	local byId = {}
	for _, entry in self._sounds do
		byId[entry.sound.SoundId] = entry
	end
	-- Prime short spatial clips too; their server playback can end before a cold fetch.
	for _, asset in Assets.List() do
		local id = asset.Id
		if
			type(id) == "string"
			and string.match(id, "^rbxassetid://[1-9]%d*$")
			and not seen[id]
		then
			seen[id] = true
			table.insert(ids, id)
			if #ids >= 15 then
				break
			end
		end
	end
	if #ids == 0 then
		return
	end
	local generation = self._generation
	local pending = { thread = nil, active = true }
	self._preload = pending
	pending.thread = task.spawn(function()
		local ok, message = pcall(function()
			ContentProvider:PreloadAsync(ids, function(id: string, status: Enum.AssetFetchStatus)
				local entry = byId[id]
				if self._generation == generation and status ~= Enum.AssetFetchStatus.Success then
					if entry then
						-- A transient preload failure may arrive after the Sound itself loaded.
						entry.failed = not entry.sound.IsLoaded
						if not entry.failed then
							return
						end
						self:_stop(entry)
					end
					warn("[AudioController] Audio asset unavailable: " .. id)
				end
			end)
		end)
		if self._generation == generation then
			pending.active = false
			self._preload = nil
			if not ok then
				warn("[AudioController] Audio preload failed: " .. tostring(message))
			end
		end
	end)
	task.delay(PRELOAD_TIMEOUT, function()
		if self._generation == generation and self._preload == pending and pending.active then
			if pending.thread then
				pcall(task.cancel, pending.thread)
			end
			pending.active = false
			self._preload = nil
			warn("[AudioController] Audio preload timed out; gameplay continues")
		end
	end)
end

function Controller:_livingRoot(): BasePart?
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then root else nil
end

function Controller:_resolveMonster(now: number)
	if now < self._resolveAt then
		return
	end
	self._resolveAt = now + RESOLVE_INTERVAL
	self._monster, self._monsterRoot = nil, nil
	self._monsters = {}
	local map = workspace:FindFirstChild("CornMap")
	local runtime = if map and map:GetAttribute("corn_project_id") == PROJECT
		then map:FindFirstChild("CornRoundRuntime")
		else nil
	if
		not runtime
		or not runtime:IsA("Folder")
		or runtime:GetAttribute("corn_project_id") ~= PROJECT
	then
		return
	end
	for index = 1, 3 do
		local name = if index == 1 then "Monster" else "Monster" .. index
		local monster = runtime:FindFirstChild(name)
		local root = if monster then monster:FindFirstChild("Root") else nil
		if
			monster
			and monster:IsA("Model")
			and monster:GetAttribute("CornMonsterOwned") == true
			and monster:GetAttribute("corn_project_id") == PROJECT
			and monster:GetAttribute("MonsterRigVersion") == 1
			and monster:GetAttribute("MonsterIndex") == index
			and root
			and root:IsA("BasePart")
		then
			table.insert(
				self._monsters,
				{ model = monster, root = root, runtime = runtime, index = index }
			)
			if index == 1 then
				self._monster, self._monsterRoot = monster, root
			end
		end
	end
end

function Controller:_huntGoal(root: BasePart, now: number): number
	local snapshot = self._snapshot
	if
		not snapshot
		or snapshot.phase ~= "active"
		or snapshot.monster_state ~= "chase"
		or (self._capture and self._capture._state.active)
	then
		return 0
	end
	self:_resolveMonster(now)
	local nearest, distance = nil, math.huge
	for _, actor in self._monsters do
		local monster, enemy = actor.model, actor.root
		if
			enemy.Parent == monster
			and monster.Parent == actor.runtime
			and actor.runtime.Parent ~= nil
			and actor.runtime:GetAttribute("corn_project_id") == PROJECT
			and monster.Name == (if actor.index == 1 then "Monster" else "Monster" .. actor.index)
			and monster:GetAttribute("MonsterIndex") == actor.index
			and monster:GetAttribute("CornMonsterOwned") == true
			and monster:GetAttribute("corn_project_id") == PROJECT
			and monster:GetAttribute("MonsterRigVersion") == 1
			and monster:GetAttribute("HuntState") == "chase"
			and monster:GetAttribute("ChaseTargetUserId") == player.UserId
		then
			local candidate = (enemy.Position - root.Position).Magnitude
			if candidate < distance then
				nearest, distance = actor, candidate
			end
		end
	end
	if nearest then
		self._monster, self._monsterRoot = nearest.model, nearest.root
	end
	return if distance <= (Rules.HuntMaxDistance or 60) then Rules.ChaseIntensity(distance) else 0
end

function Controller:_canPlay(entry: any): boolean
	if not self:_soundValid(entry) then
		return false
	end
	if entry.failed and entry.sound.IsLoaded then
		entry.failed = false
	end
	return not entry.failed
end

function Controller:_music(role: string, alpha: number)
	local entry = self._sounds[role]
	if not self:_canPlay(entry) then
		return
	end
	if alpha <= 0 then
		if entry.playing then
			self:_stop(entry)
		end
		return
	end
	entry.sound.Volume = entry.gain * alpha
	if not entry.playing then
		entry.playing = true
		entry.sound:Play()
	end
end

function Controller:_playEffect(kind: string, now: number)
	local entry = self._sounds[if kind == "energy" then "Energy" else "Trap"]
	if not self:_canPlay(entry) then
		return
	end
	self:_stop(entry)
	entry.sound.Volume = entry.gain
	entry.playing = true
	entry.deadline = now + math.max(entry.duration, entry.sound.TimeLength) + 0.5
	entry.sound:Play()
end

function Controller:_step(dt: number, now: number)
	self:_stepRustles(now)
	local snapshot = self._snapshot
	local root = self:_livingRoot()
	if
		not snapshot
		or not root
		or GuiService.MenuIsOpen
		or (snapshot.phase ~= "active" and snapshot.phase ~= "caught")
	then
		self:_stopAll()
		return
	end
	self._background = Rules.Fade(self._background, 1, dt, Rules.BackgroundFade)
	self:_music("Background", self._background)
	if snapshot.phase == "caught" or (self._capture and self._capture._state.active) then
		self._hunt = 0
		self:_stop(self._sounds.Hunt)
		self:_stop(self._sounds.Energy)
		self:_stop(self._sounds.Trap)
	else
		local goal = self:_huntGoal(root, now)
		self._hunt = Rules.Fade(
			self._hunt,
			goal,
			dt,
			if goal > self._hunt then Rules.HuntFadeIn else Rules.HuntFadeOut
		)
		self:_music("Hunt", self._hunt)
		for _, role in { "Energy", "Trap" } do
			local entry = self._sounds[role]
			if entry and entry.deadline and now >= entry.deadline then
				self:_stop(entry)
			end
		end
	end
end

function Controller:SetSnapshot(snapshot: any)
	if
		type(snapshot) ~= "table"
		or type(snapshot.minimap) ~= "table"
		or not Inventory.IsValidSnapshot(snapshot.inventory)
	then
		self:Clear("malformed snapshot")
		return
	end
	local roundId = snapshot.minimap.round_id
	local use = snapshot.inventory.use
	if
		type(roundId) ~= "number"
		or roundId < 0
		or roundId >= math.huge
		or roundId % 1 ~= 0
		or roundId < self._roundId
	then
		return
	end
	if
		roundId == self._roundId
		and snapshot.phase == "active"
		and (use.id < self._useId or self._endedRound == roundId)
	then
		return
	end
	local first = roundId ~= self._roundId
	if first then
		self:_clearRustles()
		self:_stopAll()
		self._monster, self._monsterRoot = nil, nil
		self._monsters = {}
		self._resolveAt = 0
		self._roundId, self._useId = roundId, use.id
		self._endedRound = nil
	end
	self._snapshot = snapshot
	if
		snapshot.phase == "escaped"
		or snapshot.phase == "aborted"
		or snapshot.phase == "caught_out"
	then
		self._endedRound = roundId
	end
	if not first and use.id > self._useId then
		self._useId = use.id
		if
			snapshot.phase == "active"
			and self:_livingRoot()
			and not GuiService.MenuIsOpen
			and not (self._capture and self._capture._state.active)
			and (use.kind == "energy" or use.kind == "trap")
		then
			self:_playEffect(use.kind, os.clock())
		end
	end
	self:_step(0, os.clock())
end

function Controller:Start(context: any)
	if self._started then
		return
	end
	self._started = true
	self._capture = context.Controllers.CaptureController
	self:_startFootsteps()
	if not self:_build() then
		return
	end
	self:_preloadAssets()
	table.insert(
		self._connections,
		RunService.Heartbeat:Connect(function(dt: number)
			self:_step(dt, os.clock())
		end)
	)
	table.insert(
		self._connections,
		GuiService.MenuOpened:Connect(function()
			self:_stopAll()
		end)
	)
end

function Controller:Destroy()
	self:Clear("destroy")
	for target in self._footstepPlayers do
		self:_releaseFootstepPlayer(target)
	end
	self._generation += 1
	if self._preload then
		if self._preload.thread then
			pcall(task.cancel, self._preload.thread)
		end
		self._preload = nil
	end
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	local folder = self._folder
	if folder and owned(folder) then
		-- A manually changed descendant must survive along with its parent folder.
		local allOwned = true
		for _, child in folder:GetDescendants() do
			if not owned(child) then
				allOwned = false
				break
			end
		end
		if allOwned then
			folder:Destroy()
		else
			warn("[AudioController] Changed personal audio children preserved")
		end
	elseif folder then
		warn("[AudioController] Changed personal audio folder preserved")
	end
	self._folder, self._capture, self._refused = nil, nil, nil
	table.clear(self._sounds)
	table.clear(self._groups)
	self._started = false
end

return Controller
