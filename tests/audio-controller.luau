-- Production client controller with deterministic Sound/Heartbeat/network-free adapters.
-- This checks transitions and ownership, not audio output or Roblox asset permissions.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local function load(path, env)
	local fn = assert(loadstring(fs.readFile(path), path))
	setfenv(fn, setmetatable(env, { __index = getfenv() }))
	return fn()
end
local Inventory = load("src/shared/Game/Inventory.luau", {})
local now, made, gameplayWrites, scans = 100, 0, 0, 0
local createdSoundsLoaded = false
local connections = {}
local function signal()
	local entries = {}
	return {
		Connect = function(_, fn)
			local connection = {
				Connected = true,
				Disconnect = function(self)
					self.Connected = false
				end,
			}
			table.insert(entries, { connection, fn })
			table.insert(connections, connection)
			return connection
		end,
		Fire = function(_, ...)
			for _, entry in entries do
				if entry[1].Connected then
					entry[2](...)
				end
			end
		end,
		Queue = function(_, ...)
			local callbacks, arguments = {}, table.pack(...)
			for _, entry in entries do
				if entry[1].Connected then
					table.insert(callbacks, entry[2])
				end
			end
			return function()
				for _, fn in callbacks do
					fn(table.unpack(arguments, 1, arguments.n))
				end
			end
		end,
	}
end
local methods = {}
local function make(class)
	made += 1
	return setmetatable({
		_class = class,
		_children = {},
		_attributes = {},
		_propertySignals = {},
		_values = {
			Name = class,
			Position = roblox.Vector3.new(),
			Health = 100,
			TimeLength = 0,
			TimePosition = 0,
			Volume = 1,
			IsPlaying = false,
			IsLoaded = createdSoundsLoaded,
			Ended = signal(),
			ChildAdded = signal(),
			ChildRemoved = signal(),
		},
		plays = 0,
		stops = 0,
	}, {
		__index = function(item, key)
			return methods[key] or item._values[key]
		end,
		__newindex = function(item, key, value)
			local previousValue = item._values[key]
			if key == "Parent" then
				local previous = item._values.Parent
				if previous then
					local index = table.find(previous._children, item)
					if index then
						table.remove(previous._children, index)
					end
				end
				if value then
					table.insert(value._children, item)
				end
			end
			if item._class == "Part" or item._class == "Camera" or item._class == "Humanoid" then
				gameplayWrites += 1
			end
			item._values[key] = value
			if key == "Parent" and previousValue ~= value then
				if previousValue then
					previousValue.ChildRemoved:Fire(item)
				end
				if value then
					value.ChildAdded:Fire(item)
				end
			end
			if previousValue ~= value and item._propertySignals[key] then
				item._propertySignals[key]:Fire()
			end
		end,
	})
end
function methods:IsA(class)
	return self._class == class or (class == "BasePart" and self._class == "Part")
end
function methods:GetPropertyChangedSignal(key)
	if not self._propertySignals[key] then
		self._propertySignals[key] = signal()
	end
	return self._propertySignals[key]
end
function methods:GetAttribute(key)
	return self._attributes[key]
end
function methods:SetAttribute(key, value)
	if self._class == "Part" or self._class == "Workspace" or self._class == "Model" then
		gameplayWrites += 1
	end
	self._attributes[key] = value
end
function methods:FindFirstChild(name)
	if self._class == "Workspace" then
		scans += 1
	end
	for _, child in self._children do
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
	for _, child in self._children do
		if child:IsA(class) then
			return child
		end
	end
	return nil
end
function methods:GetDescendants()
	local entries = {}
	for _, child in self._children do
		table.insert(entries, child)
		for _, nested in child:GetDescendants() do
			table.insert(entries, nested)
		end
	end
	return entries
end
function methods:Destroy()
	for _, child in table.clone(self._children) do
		child:Destroy()
	end
	self.Parent = nil
	self.Destroyed = true
end
function methods:Play()
	assert(self._class == "Sound")
	self.plays += 1
	self.IsPlaying = true
end
function methods:Stop()
	assert(self._class == "Sound")
	self.stops += 1
	self.IsPlaying = false
	self.TimePosition = 0
end
local storage, world, audio = make("ReplicatedStorage"), make("Workspace"), make("SoundService")
local folder, games = make("Folder"), make("Folder")
folder.Name, folder.Parent = "GameShared", storage
games.Name, games.Parent = "Game", folder
for _, name in { "Inventory", "AudioAssets", "AudioRules" } do
	local node = make("ModuleScript")
	node.Name, node.Parent = name, games
end
local hero, humanoid, root = make("Model"), make("Humanoid"), make("Part")
humanoid.Parent, root.Parent = hero, hero
root.Name = "HumanoidRootPart"
local map, runtime, monster, enemy = make("Folder"), make("Folder"), make("Model"), make("Part")
map.Name, map.Parent = "CornMap", world
runtime.Name, runtime.Parent = "CornRoundRuntime", map
monster.Name, monster.Parent = "Monster", runtime
enemy.Name, enemy.Parent = "Root", monster
for _, object in { map, runtime, monster } do
	object:SetAttribute("corn_project_id", "children_of_corn")
end
monster:SetAttribute("CornMonsterOwned", true)
monster:SetAttribute("MonsterRigVersion", 1)
monster:SetAttribute("MonsterIndex", 1)
monster:SetAttribute("HuntState", "chase")
monster:SetAttribute("ChaseTargetUserId", 20)
enemy.Position = roblox.Vector3.new(0, 0, 10)
local player =
	{ UserId = 20, Character = hero, CharacterAdded = signal(), CharacterRemoving = signal() }
local gui = { MenuIsOpen = false, MenuOpened = signal() }
local heartbeat = signal()
local delays, tasks, warnings, preloadMode = {}, {}, {}, "success"
local assetList = {
	COC_Background_02 = { Id = "rbxassetid://11", Gain = 0.9, Duration = 160 },
	COC_Hunt = { Id = "rbxassetid://12", Gain = 1, Duration = 90 },
	COC_Energy_Open = { Id = "rbxassetid://13", Gain = 1, Duration = 1.33 },
	COC_Trap_Place = { Id = "rbxassetid://14", Gain = 1, Duration = 0.57 },
}
for index = 1, 11 do
	assetList["SpatialClip" .. index] =
		{ Id = "rbxassetid://" .. tostring(14 + index), Gain = 1, Duration = 0.44 }
end
assetList.Duplicate = { Id = "rbxassetid://11", Gain = 1, Duration = 1 }
assetList.Empty = { Id = "", Gain = 1, Duration = 1 }
assetList.Invalid = { Id = "rbxassetid://0", Gain = 1, Duration = 1 }
local preloadRequests = {}
local Rules = load("src/shared/Game/AudioRules.luau", {})
local services = {
	Players = {
		LocalPlayer = player,
		PlayerAdded = signal(),
		PlayerRemoving = signal(),
		GetPlayers = function()
			return { player }
		end,
	},
	ReplicatedStorage = storage,
	SoundService = audio,
	RunService = { Heartbeat = heartbeat },
	GuiService = gui,
	ContentProvider = {
		PreloadAsync = function(_, ids, fn)
			assert(#ids == 15, "Preload did not cover all 15 unique valid clips")
			local seen = {}
			for _, id in ids do
				assert(
					type(id) == "string"
						and string.match(id, "^rbxassetid://[1-9]%d*$")
						and not seen[id]
				)
				seen[id] = true
			end
			for _, asset in assetList do
				if string.match(asset.Id, "^rbxassetid://[1-9]%d*$") then
					assert(seen[asset.Id], "Valid spatial clip omitted from client preload")
				end
			end
			table.insert(preloadRequests, table.clone(ids))
			if preloadMode == "hang" then
				coroutine.yield()
				return
			end
			for _, id in ids do
				fn(
					id,
					if preloadMode == "failure"
						then roblox.Enum.AssetFetchStatus.Failure
						else roblox.Enum.AssetFetchStatus.Success
				)
			end
		end,
	},
}
local module = load("src/client/Controllers/AudioController.luau", {
	game = {
		GetService = function(_, name)
			return assert(services[name], name)
		end,
	},
	workspace = world,
	Instance = { new = make },
	Enum = roblox.Enum,
	os = {
		clock = function()
			return now
		end,
	},
	task = {
		spawn = function(fn)
			local thread = coroutine.create(fn)
			table.insert(tasks, thread)
			assert(coroutine.resume(thread))
			return thread
		end,
		delay = function(duration, fn)
			table.insert(delays, { at = now + duration, fn = fn })
		end,
		cancel = function(thread)
			if coroutine.status(thread) ~= "dead" then
				coroutine.close(thread)
			end
		end,
	},
	require = function(node)
		return if node.Name == "Inventory"
			then Inventory
			elseif node.Name == "AudioRules" then Rules
			else {
				Get = function(key)
					return assetList[key]
				end,
				List = function()
					return assetList
				end,
			}
	end,
	warn = function(value)
		table.insert(warnings, value)
	end,
})
local capture = { _state = { active = false } }
local context = { Controllers = { CaptureController = capture } }
local function new()
	local object = setmetatable({}, { __index = module })
	object:Init({})
	object:Start(context)
	return object
end
local function snapshot(roundId, useId, kind, phase, state)
	return {
		minimap = { round_id = roundId },
		phase = phase or "active",
		monster_state = state or "patrol",
		inventory = {
			slots = { "empty", "empty", "empty", "empty", "empty" },
			selected = 1,
			energy_remaining = 0,
			use = { id = useId, kind = kind },
		},
	}
end
local function show(object, roundId, useId, kind, phase, state)
	object:SetSnapshot(snapshot(roundId, useId, kind, phase, state))
end
local function advance(object, dt)
	now += dt
	for _, delayed in delays do
		if not delayed.fired and delayed.at <= now then
			delayed.fired = true
			delayed.fn()
		end
	end
	object:_step(dt, now)
end
gameplayWrites, scans = 0, 0
local FOOTSTEPS = "rbxasset://sounds/action_footsteps_plastic.mp3"
local function footstep(name, id, volume, parent)
	local sound = make("Sound")
	sound.Name, sound.SoundId, sound.Volume = name, id, volume
	sound.Parent = parent
	return sound
end
local running = footstep("Running", FOOTSTEPS, 0.65, root)
local jumping = footstep("Jumping", "rbxasset://sounds/action_jump.mp3", 0.4, root)
local death = footstep("Died", "rbxasset://sounds/uuhhh.mp3", 0.3, root)
local rustle = footstep("CornRustle", "rbxassetid://99", 0.25, root)
local object = new()
assert(
	running.Volume == 0 and jumping.Volume == 0.4 and death.Volume == 0.3 and rustle.Volume == 0.25,
	"Existing default mute affected jump/death/corn"
)
local climbing = footstep("Climbing", "rbxassetid://88", 0.42, root)
assert(climbing.Volume == 0.42, "Custom Climbing asset was muted")
climbing.SoundId = FOOTSTEPS
assert(climbing.Volume == 0, "Late default SoundId was not muted")
running.Volume = 0.8
assert(running.Volume == 0, "Default volume rewrite escaped mute")
local duplicate = footstep("Running", FOOTSTEPS, 0.61, root)
assert(duplicate.Volume == 0.61, "Unknown duplicate default-named Sound was modified")
local ownFootsteps = object._footstepPlayers[player]
assert(
	ownFootsteps
		and ownFootsteps.sounds.Running.sound == running
		and ownFootsteps.sounds.Climbing.sound == climbing
)
local other = { UserId = 21, CharacterAdded = signal(), CharacterRemoving = signal() }
services.Players.PlayerAdded:Fire(other)
local otherCharacter = make("Model")
other.Character = otherCharacter
other.CharacterAdded:Fire(otherCharacter)
local otherRoot = make("Part")
-- Fixture setup of a new Root is not a controller gameplay write.
local previousWrites = gameplayWrites
otherRoot.Name, otherRoot.Parent = "HumanoidRootPart", otherCharacter
gameplayWrites = previousWrites
local otherRunning = footstep("Running", FOOTSTEPS, 0.55, otherRoot)
assert(
	otherRunning.Volume == 0 and object._footstepPlayerCount == 2,
	"New player/late Root/Sound lifecycle missed default"
)
other.CharacterRemoving:Fire(otherCharacter)
assert(otherRunning.Volume == 0.55, "Character removal did not restore default volume")
local secondOther = make("Model")
local secondRoot = make("Part")
previousWrites = gameplayWrites
secondRoot.Name, secondRoot.Parent = "HumanoidRootPart", secondOther
gameplayWrites = previousWrites
local secondRunning = footstep("Running", FOOTSTEPS, 0.65, secondRoot)
other.Character = secondOther
other.CharacterAdded:Fire(secondOther)
assert(secondRunning.Volume == 0, "Respawn default Sound was not muted")
secondRunning.SoundId, secondRunning.Volume = "rbxassetid://77", 0.19
services.Players.PlayerRemoving:Fire(other)
assert(
	secondRunning.Volume == 0.19 and object._footstepPlayerCount == 1,
	"Changed foreign identity was restored or player binding leaked"
)
local overflow = {}
for index = 1, 9 do
	local target = { UserId = 30 + index, CharacterAdded = signal(), CharacterRemoving = signal() }
	table.insert(overflow, target)
	services.Players.PlayerAdded:Fire(target)
end
assert(
	object._footstepPlayerCount == 8
		and object._footstepPlayers[overflow[7]]
		and not object._footstepPlayers[overflow[8]],
	"Footstep lifecycle exceeded 8 player bindings"
)
for _, target in overflow do
	services.Players.PlayerRemoving:Fire(target)
end
assert(object._footstepPlayerCount == 1, "Player overflow/removal leaked lifecycle state")
assert(object.Order == 98 and #object._folder:GetDescendants() == 6)
assert(
	#preloadRequests == 1 and #preloadRequests[1] == 15,
	"Spatial preload not scheduled asynchronously at startup"
)
assert(object._preload == nil, "Synchronous cached preload left a false pending timeout")
local background, hunt, energy, trap =
	object._sounds.Background.sound,
	object._sounds.Hunt.sound,
	object._sounds.Energy.sound,
	object._sounds.Trap.sound
show(object, 1, 4, "energy")
assert(energy.plays == 0 and trap.plays == 0, "Initial sync replayed past use")
advance(object, 0.4)
assert(background.IsPlaying and background.Volume > 0 and background.Volume < 0.12)
advance(object, 0.4)
assert(math.abs(background.Volume - 0.108) < 1e-8 and background.plays == 1)
show(object, 1, 4, "energy", "active", "chase")
advance(object, 0.14)
assert(hunt.IsPlaying and math.abs(hunt.Volume - 0.034) < 1e-8, "Chase did not start quietly")
advance(object, 1.4)
assert(hunt.Volume > 0.2 and hunt.Volume <= 0.34 and hunt.plays == 1)
-- Fixed names/indexes; personal intensity follows the nearest actual chasing target.
local function extraMonster(index, distance)
	local previousWrites = gameplayWrites
	local model, targetRoot = make("Model"), make("Part")
	model.Name, model.Parent = "Monster" .. index, runtime
	for name, value in
		{
			corn_project_id = "children_of_corn",
			CornMonsterOwned = true,
			MonsterRigVersion = 1,
			MonsterIndex = index,
			HuntState = "chase",
			ChaseTargetUserId = 20,
		}
	do
		model:SetAttribute(name, value)
	end
	targetRoot.Name, targetRoot.Parent = "Root", model
	targetRoot._values.Position = roblox.Vector3.new(0, 0, distance)
	gameplayWrites = previousWrites
	return model, targetRoot
end
local secondMonster, secondEnemy = extraMonster(2, 5)
local thirdMonster, thirdEnemy = extraMonster(3, 2)
local fourthMonster = extraMonster(4, 1)
object._resolveAt = 0
assert(object:_huntGoal(root, now) == Rules.ChaseIntensity(2) and object._monster == thirdMonster)
assert(#object._monsters == 3, "Audio resolver accepted fourth NPC")
thirdMonster._attributes.HuntState = "patrol"
assert(
	object:_huntGoal(root, now) == Rules.ChaseIntensity(5) and object._monster == secondMonster,
	"Nearest nonchasing NPC masked an actual chaser"
)
thirdMonster._attributes.HuntState = "chase"
thirdMonster._attributes.corn_project_id = "foreign"
secondMonster._attributes.ChaseTargetUserId = 99
assert(
	object:_huntGoal(root, now) == Rules.ChaseIntensity(10) and object._monster == monster,
	"Foreign or other-target NPC affected personal Hunt"
)
secondMonster._attributes.ChaseTargetUserId = 20
secondMonster._attributes.MonsterIndex = 3
assert(object:_huntGoal(root, now) == Rules.ChaseIntensity(10), "Wrong MonsterIndex accepted")
local fixtureCleanupWrites = gameplayWrites
secondMonster:Destroy()
thirdMonster:Destroy()
fourthMonster:Destroy()
gameplayWrites = fixtureCleanupWrites
object._resolveAt = 0
object:_resolveMonster(now)
monster._attributes.ChaseTargetUserId = 99
local previous = hunt.Volume
advance(object, 0.25)
assert(
	hunt.IsPlaying and hunt.Volume < previous and hunt.Volume > 0,
	"Other target should fade out personal chase"
)
advance(object, 2.5)
assert(not hunt.IsPlaying and hunt.Volume == 0, "Personal chase did not stop at fade zero")
monster._attributes.ChaseTargetUserId = 20
enemy._values.Position = roblox.Vector3.new(0, 0, 100)
advance(object, 2)
assert(not hunt.IsPlaying, "Far-away target kept chase music")
enemy._values.Position = roblox.Vector3.new(0, 0, 10)
advance(object, 0.3)
assert(hunt.IsPlaying)
show(object, 1, 5, "energy", "active", "chase")
assert(energy.IsPlaying and energy.plays == 1 and math.abs(energy.Volume - 0.55) < 1e-8)
local deadline = object._sounds.Energy.deadline
show(object, 1, 5, "energy", "active", "chase")
show(object, 1, 4, "energy", "active", "chase")
assert(
	energy.plays == 1 and object._sounds.Energy.deadline == deadline,
	"Duplicate/out-of-order replayed use"
)
advance(object, 1.9)
assert(not energy.IsPlaying and object._sounds.Energy.deadline == nil)
show(object, 1, 6, "trap", "active", "chase")
assert(trap.plays == 1 and trap.IsPlaying)
trap.Ended:Fire()
assert(not trap.IsPlaying and object._sounds.Trap.deadline == nil)
show(object, 1, 7, "energy", "active", "chase")
show(object, 1, 7, "energy", "caught", "capturing")
assert(
	not hunt.IsPlaying and not energy.IsPlaying and background.IsPlaying,
	"Caught did not stop hunt/use immediately"
)
show(object, 1, 7, "energy", "active", "chase")
advance(object, 0.3)
capture._state.active = true
advance(object, 0.1)
assert(not hunt.IsPlaying and background.IsPlaying)
capture._state.active = false
show(object, 1, 8, "trap", "active", "chase")
gui.MenuIsOpen = true
gui.MenuOpened:Fire()
assert(not background.IsPlaying and not hunt.IsPlaying and not trap.IsPlaying)
show(object, 1, 9, "energy", "active", "chase")
gui.MenuIsOpen = false
advance(object, 0.5)
assert(
	background.IsPlaying and energy.plays == 2,
	"Resume replayed the use received while menu open"
)
show(object, 1, 0, "none", "escaped", "stopped")
show(object, 1, 9, "energy", "active", "chase")
advance(object, 0.5)
assert(not background.IsPlaying and not hunt.IsPlaying, "Old active revived terminal round")
show(object, 2, 0, "none")
advance(object, 0.5)
assert(background.IsPlaying and energy.plays == 2)
show(object, 2, 1, "energy")
humanoid._values.Health = 0
advance(object, 0.1)
assert(not background.IsPlaying and not energy.IsPlaying)
humanoid._values.Health = 100
player.CharacterRemoving:Fire(hero)
assert(
	running.Volume == 0.65 and climbing.Volume == 0.42,
	"Local reset did not restore original default volumes"
)
advance(object, 1)
assert(
	not background.IsPlaying and object._snapshot == nil,
	"Character removal kept stale snapshot"
)
player.CharacterAdded:Fire(hero)
assert(running.Volume == 0 and climbing.Volume == 0, "Local respawn did not remute exact defaults")
show(object, 3, 3, "trap")
assert(trap.plays == 2, "Respawn/retry sync replayed history")
show(object, 3, 4, "trap")
object:SetSnapshot({ inventory = {} })
assert(not trap.IsPlaying and object._snapshot == nil)
show(object, 4, 0, "none", "active", "chase")
local beforeScans, allocations = scans, made
for _ = 1, 120 do
	advance(object, 1 / 60)
end
assert(scans - beforeScans <= 8 and made == allocations, "Controller scans/reallocates unboundedly")
assert(object._groups.Music.Volume == 0.8 and object._groups.Effects.Volume == 0.8)
for _, entry in object._sounds do
	assert(entry.sound.Volume <= 1 and entry.group.Parent == object._folder)
end
local ownFolder = object._folder
local releasedRunningEntry = object._footstepPlayers[player].sounds.Running
local queuedCharacter = player.CharacterAdded:Queue(hero)
local queuedPlayer = services.Players.PlayerAdded:Queue({
	UserId = 89,
	CharacterAdded = signal(),
	CharacterRemoving = signal(),
})
object:Destroy()
queuedCharacter()
queuedPlayer()
object:_muteFootstep(releasedRunningEntry)
assert(
	running.Volume == 0.65
		and next(object._footstepPlayers) == nil
		and object._footstepPlayerCount == 0,
	"Queued callbacks after disconnect remuted restored sounds or created ghost player bindings"
)
assert(
	running.Volume == 0.65
		and climbing.Volume == 0.42
		and jumping.Volume == 0.4
		and death.Volume == 0.3
		and rustle.Volume == 0.25
		and duplicate.Volume == 0.61,
	"Default mute cleanup failed guarded restoration or changed unrelated sounds"
)
assert(
	next(object._footstepPlayers) == nil and object._footstepPlayerCount == 0,
	"Footstep player state leaked"
)
assert(ownFolder.Destroyed and not audio:FindFirstChild("CornPersonalAudio"))
for _, connection in connections do
	assert(not connection.Connected, "Audio connection leaked")
end
assert(gameplayWrites == 0, "Personal audio changed character/camera/world/gameplay state")
local unknown = make("Folder")
unknown.Name, unknown.Parent = "CornPersonalAudio", audio
local refused = new()
show(refused, 1, 0, "none")
advance(refused, 2)
refused:Destroy()
assert(unknown.Parent == audio and not unknown.Destroyed and not refused._folder)
unknown:Destroy()
local altered = new()
local alteredFolder = altered._folder
local foreign = make("Sound")
foreign.Name, foreign.Parent = "AuthorSound", alteredFolder
altered:Destroy()
assert(
	alteredFolder.Parent == audio and foreign.Parent == alteredFolder and not foreign.Destroyed,
	"Foreign descendant was destroyed"
)
alteredFolder:Destroy()
preloadMode = "failure"
local failed = new()
show(failed, 1, 0, "none", "active", "chase")
advance(failed, 2)
show(failed, 1, 1, "energy")
for _, entry in failed._sounds do
	assert(entry.failed and not entry.sound.IsPlaying)
end
local failedBackground, failedHunt, failedEnergy, failedTrap =
	failed._sounds.Background, failed._sounds.Hunt, failed._sounds.Energy, failed._sounds.Trap
failedBackground.sound._values.IsLoaded, failedHunt.sound._values.IsLoaded = true, true
show(failed, 1, 1, "energy", "active", "chase")
advance(failed, 0.2)
assert(
	failedBackground.sound.IsPlaying
		and failedHunt.sound.IsPlaying
		and not failedBackground.failed
		and not failedHunt.failed,
	"Later-loaded music did not recover from transient preload failure"
)
failedEnergy.sound._values.IsLoaded = true
show(failed, 1, 1, "energy", "active", "chase")
assert(
	not failedEnergy.sound.IsPlaying and failedEnergy.sound.plays == 0,
	"Loaded effect replayed historical accepted use"
)
show(failed, 1, 2, "energy", "active", "chase")
assert(
	failedEnergy.sound.IsPlaying and failedEnergy.sound.plays == 1 and not failedEnergy.failed,
	"New accepted energy did not recover loaded asset"
)
failedTrap.sound._values.IsLoaded = true
show(failed, 1, 3, "trap")
assert(
	failedTrap.sound.IsPlaying and failedTrap.sound.plays == 1 and not failedTrap.failed,
	"New accepted trap did not recover loaded asset"
)
failed:Destroy()
createdSoundsLoaded = true
local staleFailure = new()
for _, entry in staleFailure._sounds do
	assert(not entry.failed, "Stale preload failure suppressed an already loaded Sound")
end
show(staleFailure, 1, 0, "none", "active", "chase")
advance(staleFailure, 0.2)
show(staleFailure, 1, 1, "energy", "active", "chase")
assert(
	staleFailure._sounds.Background.sound.IsPlaying
		and staleFailure._sounds.Hunt.sound.IsPlaying
		and staleFailure._sounds.Energy.sound.IsPlaying
)
staleFailure:Destroy()
createdSoundsLoaded = false
preloadMode = "hang"
local hanging = new()
assert(hanging._preload and hanging._preload.active)
advance(hanging, 8.1)
assert(
	hanging._preload == nil and coroutine.status(tasks[#tasks]) == "dead",
	"Preload timeout did not cancel stalled task"
)
hanging:Destroy()
for _, asset in assetList do
	asset.Id = ""
end
local requestCount = #preloadRequests
local empty = new()
assert(#preloadRequests == requestCount, "Empty manifest scheduled a useless preload")
assert(
	next(empty._sounds) == nil and empty._preload == nil and #empty._folder:GetDescendants() == 2
)
show(empty, 1, 0, "none", "active", "chase")
advance(empty, 5)
empty:Destroy()
print(
	"PASS: three fixed indexed NPCs/nearest actual own-target/foreign+fourth guards; background/own-target-only quiet hunt fades and distance mute; authoritative use first-sync/duplicate/stale/terminal/retry guards; caught/menu/death/reset stop; exact default Running/Climbing existing/late-ID/new-player/late-Root/respawn mute, volume rewrites, unknown duplicates/custom IDs and jump/death/corn preservation, guarded restoration; bounded resolver/all15unique-valid-clips asynchronous preload/missing-ID/failure/8s timeout; transient failure later-loaded recovery without effect history replay/stale failure after loaded; category groups/ownership/foreign preservation; zero gameplay/world/camera writes and cleanup"
)
