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
end

local function disconnect(entries: { RBXScriptConnection })
	for _, connection in entries do
		connection:Disconnect()
	end
	table.clear(entries)
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
	self._monster, self._monsterRoot = nil, nil
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
	local map = workspace:FindFirstChild("CornMap")
	local runtime = if map and map:GetAttribute("corn_project_id") == PROJECT
		then map:FindFirstChild("CornRoundRuntime")
		else nil
	local monster = if runtime and runtime:GetAttribute("corn_project_id") == PROJECT
		then runtime:FindFirstChild("Monster")
		else nil
	local root = if monster then monster:FindFirstChild("Root") else nil
	if
		monster
		and monster:IsA("Model")
		and monster:GetAttribute("CornMonsterOwned") == true
		and monster:GetAttribute("corn_project_id") == PROJECT
		and monster:GetAttribute("MonsterRigVersion") == 1
		and root
		and root:IsA("BasePart")
	then
		self._monster, self._monsterRoot = monster, root
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
	local monster, enemy = self._monster, self._monsterRoot
	if
		not monster
		or not enemy
		or enemy.Parent ~= monster
		or not monster.Parent
		or monster:GetAttribute("CornMonsterOwned") ~= true
		or monster:GetAttribute("corn_project_id") ~= PROJECT
		or monster:GetAttribute("MonsterRigVersion") ~= 1
		or monster:GetAttribute("ChaseTargetUserId") ~= player.UserId
	then
		return 0
	end
	local distance = (enemy.Position - root.Position).Magnitude
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
		self:_stopAll()
		self._monster, self._monsterRoot = nil, nil
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
