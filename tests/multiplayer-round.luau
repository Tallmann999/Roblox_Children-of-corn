-- Production TeamRound + RoundParticipant + inherited SoloRound interaction helpers,
-- real Inventory/Stamina/MinimapState/InventoryWorld rules. World geometry, Roblox
-- signals/tasks, NPC decisions and sound rendering are deterministic adapters.
local fs = require("@lune/fs")
local process = require("@lune/process")
local r = require("@lune/roblox")

local function load(path, env, sourceOverride)
	local fn = assert(loadstring(sourceOverride or fs.readFile(path), path))
	setfenv(fn, setmetatable(env, { __index = getfenv() }))
	return fn()
end

local function fixture(count)
	local now, delayed, connections = 100, {}, {}
	local methods = {}
	local function signal()
		local listeners = {}
		return {
			Connect = function(_, callback)
				local connection = { Connected = true }
				function connection:Disconnect()
					self.Connected = false
				end
				table.insert(listeners, { connection, callback })
				table.insert(connections, connection)
				return connection
			end,
			Fire = function(_, ...)
				for _, entry in table.clone(listeners) do
					if entry[1].Connected then
						entry[2](...)
					end
				end
			end,
		}
	end
	local function make(class, name, parent)
		local object = setmetatable({
			class = class,
			values = {
				Name = name or class,
				CFrame = r.CFrame.identity,
				Size = r.Vector3.one,
				Health = 100,
				JumpPower = 50,
				JumpHeight = 7.2,
				AutoRotate = true,
				AssemblyLinearVelocity = r.Vector3.zero,
				AssemblyAngularVelocity = r.Vector3.zero,
				Enabled = true,
			},
			children = {},
			attributes = {},
			tags = {},
		}, {
			__index = function(self, key)
				if key == "Position" then
					return self.values.CFrame.Position
				end
				if methods[key] then
					return methods[key]
				end
				if self.values[key] ~= nil then
					return self.values[key]
				end
				for _, child in self.children do
					if child.Name == key then
						return child
					end
				end
				return nil
			end,
			__newindex = function(self, key, value)
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
					self.values.CFrame = r.CFrame.new(value)
					return
				end
				self.values[key] = value
			end,
		})
		if class == "ProximityPrompt" then
			object.Triggered = signal()
		end
		if class == "Humanoid" then
			object.Died = signal()
		end
		if class == "Player" then
			object.CharacterAdded, object.CharacterRemoving = signal(), signal()
		end
		object.Parent = parent
		return object
	end
	function methods:IsA(class)
		return self.class == class
			or class == "Instance"
			or (class == "BasePart" and (self.class == "Part" or self.class == "SpawnLocation"))
	end
	function methods:GetChildren()
		return table.clone(self.children)
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
		return self:FindFirstChild(name)
	end
	function methods:FindFirstChildOfClass(class)
		for _, child in self.children do
			if child:IsA(class) then
				return child
			end
		end
		return nil
	end
	function methods:IsDescendantOf(parent)
		local current = self.Parent
		while current do
			if current == parent then
				return true
			end
			current = current.Parent
		end
		return false
	end
	function methods:SetAttribute(name, value)
		self.attributes[name] = value
	end
	function methods:GetAttribute(name)
		return self.attributes[name]
	end
	function methods:GetAttributes()
		return table.clone(self.attributes)
	end
	function methods:AddTag(tag)
		self.tags[tag] = true
	end
	function methods:HasTag(tag)
		return self.tags[tag] == true
	end
	function methods:GetTags()
		local tags = {}
		for tag in self.tags do
			table.insert(tags, tag)
		end
		return tags
	end
	function methods:PivotTo(frame)
		self.pivots = (self.pivots or 0) + 1
		self.HumanoidRootPart.CFrame = frame
	end
	function methods:Destroy()
		for _, child in self:GetChildren() do
			child:Destroy()
		end
		self.Parent = nil
		self.Destroyed = true
	end
	local tasks = {}
	local nextWait
	function tasks.spawn(callback)
		table.insert(delayed, { at = now, callback = callback })
	end
	function tasks.delay(duration, callback)
		table.insert(delayed, { at = now + duration, callback = callback })
	end
	function tasks.wait(duration)
		now += duration or 0.01
		if nextWait then
			local callback = nextWait
			nextWait = nil
			callback()
		end
	end
	local function flush()
		while true do
			local selected
			for index, event in delayed do
				if event.at <= now then
					selected = index
					break
				end
			end
			if not selected then
				return
			end
			local event = table.remove(delayed, selected)
			event.callback()
		end
	end
	local players, storage, workspace, lighting =
		make("Players"), make("ReplicatedStorage"), make("Workspace"), make("Lighting")
	players.PlayerAdded, players.PlayerRemoving = signal(), signal()
	function players:GetPlayers()
		local result = {}
		for _, child in self.children do
			if child:IsA("Player") then
				table.insert(result, child)
			end
		end
		return result
	end
	lighting.ClockTime, lighting.Brightness = 9, 2
	lighting.Ambient, lighting.OutdoorAmbient =
		r.Color3.new(0.5, 0.4, 0.3), r.Color3.new(0.2, 0.3, 0.4)
	lighting.FogColor, lighting.FogStart, lighting.FogEnd = r.Color3.new(0.3, 0.2, 0.1), 10, 900
	local run = { Heartbeat = signal() }
	local shared = make("Folder", "GameShared", storage)
	local gameShared = make("Folder", "Game", shared)
	local networkShared = make("Folder", "Network", shared)
	local serverFolder = make("Folder", "Game")
	local modules = {}
	local function register(name, value, folder)
		modules[name] = value
		make("ModuleScript", name, folder or serverFolder)
		return value
	end
	local services = {
		Players = players,
		ReplicatedStorage = storage,
		RunService = run,
		Lighting = lighting,
		Workspace = workspace,
	}
	local function environment(name)
		return {
			game = {
				GetService = function(_, service)
					return assert(services[service], service)
				end,
			},
			script = serverFolder:FindFirstChild(name) or make("ModuleScript", name, serverFolder),
			require = function(node)
				return assert(modules[node.Name], node.Name)
			end,
			os = {
				clock = function()
					return now
				end,
			},
			task = tasks,
			Vector3 = r.Vector3,
			Vector2 = r.Vector2,
			CFrame = r.CFrame,
			Color3 = r.Color3,
			Enum = r.Enum,
			Instance = { new = make },
			Random = {
				new = function()
					return {
						NextInteger = function(_, lower)
							return lower
						end,
					}
				end,
			},
			RaycastParams = {
				new = function()
					return {}
				end,
			},
		}
	end
	register("EndpointNames", load("src/shared/Network/EndpointNames.luau", {}), networkShared)
	register("Inventory", load("src/shared/Game/Inventory.luau", {}), gameShared)
	register("Stamina", load("src/shared/Game/Stamina.luau", {}), gameShared)
	register(
		"LightingModes",
		load("src/shared/Game/LightingModes.luau", { Color3 = r.Color3, Instance = { new = make } }),
		gameShared
	)
	register(
		"MinimapGeometry",
		load("src/shared/Game/MinimapGeometry.luau", { Vector2 = r.Vector2, Vector3 = r.Vector3 }),
		gameShared
	)
	register("MinimapState", load("src/server/Game/MinimapState.luau", environment("MinimapState")))
	local map = make("Model", "CornMap", workspace)
	map:SetAttribute("corn_project_id", "children_of_corn")
	local world = {
		Root = map,
		Spawns = {},
		Slots = {},
		drops = 0,
		spawns = 0,
		clearCalls = 0,
		gateWrites = 0,
	}
	world.Runtime = make("Folder", "Runtime", map)
	world.Ground = make("Part", "Ground", map)
	world.Ground.Size = r.Vector3.new(630, 2, 630)
	world.Field = make("Part", "FieldZone", map)
	world.Field.Size = r.Vector3.new(630, 10, 630)
	for index, position in
		{
			r.Vector3.new(-288, 3, -288),
			r.Vector3.new(288, 3, -288),
			r.Vector3.new(-288, 3, 288),
			r.Vector3.new(288, 3, 288),
		}
	do
		local spawn = make("SpawnLocation", "Spawn" .. index, map)
		spawn.Position = position
		table.insert(world.Spawns, spawn)
	end
	for row = 1, 3 do
		for column = 1, 5 do
			local slot = make("Part", "Slot" .. tostring(#world.Slots + 1), map)
			slot.Position = r.Vector3.new((column - 3) * 125, 3, (row - 2) * 200)
			slot:AddTag("corn_key_slot")
			slot:SetAttribute("slot_id", slot.Name)
			table.insert(world.Slots, slot)
		end
	end
	world.GateAnchor = make("Part", "GateAnchor", map)
	world.GateAnchor.Position = r.Vector3.new(0, 3, 315)
	world.GatePrompt = make("ProximityPrompt", "GatePrompt", world.GateAnchor)
	function world:IsValid()
		return not self.invalid
	end
	function world:IsOnPlayground(position)
		return math.abs(position.X) <= 315 and math.abs(position.Z) <= 340
	end
	function world:IsInExit(position)
		return position.Z > 322
	end
	function world:IsGateFront(position)
		return position.Z <= 319
	end
	function world:SetGateOpen(open)
		self.open = open
		self.gateWrites += 1
	end
	function world:SetInteractionEnabled(enabled, gateOpen)
		if self.KeyPrompt then
			self.KeyPrompt.Enabled = enabled and not gateOpen
		end
		self.GatePrompt.Enabled = enabled and not gateOpen
	end
	function world:ClearKey()
		self.clearCalls += 1
		if self.Key then
			self.Key:Destroy()
		end
		self.Key, self.KeyPrompt = nil, nil
	end
	local function publishKey(position)
		world:ClearKey()
		world.Key = make("Part", "Key", world.Runtime)
		world.Key.Position = position
		world.KeyPrompt = make("ProximityPrompt", "KeyPrompt", world.Key)
		return world.KeyPrompt
	end
	function world:SpawnKey(slot)
		if self.failSpawn then
			return nil
		end
		self.spawns += 1
		return publishKey(slot.Position)
	end
	function world:DropKey(position, radius)
		assert(radius == 6)
		if self.failDrop then
			return nil
		end
		self.drops += 1
		return publishKey(position)
	end
	function workspace:Raycast(origin, direction)
		if direction.Y < -8 then
			return { Instance = world.Ground, Position = r.Vector3.new(origin.X, 1, origin.Z) }
		end
		return nil
	end
	register("AuthoredWorld", {
		new = function()
			return world
		end,
		IsSafeSpawn = function(root, spawn)
			return root == map and table.find(world.Spawns, spawn) ~= nil
		end,
		FindSafeSpawn = function()
			return world.Spawns[1]
		end,
		SpawnCFrame = function(spawn)
			return spawn.CFrame
		end,
	})
	local function item(frame)
		local model = make("Model")
		local anchor = make("Part", "Anchor", model)
		anchor.CFrame = frame
		return model, anchor
	end
	register("ItemModels", {
		Energy = item,
		Trap = item,
		StumpHeight = 2,
		Stump = function(parent, frame)
			local stump = make("Part", "Stump", parent)
			stump.CFrame = frame
			return stump
		end,
	})
	register(
		"InventoryWorld",
		load("src/server/Game/InventoryWorld.luau", environment("InventoryWorld"))
	)
	local hunts, audios = {}, {}
	local activeTeam, failHuntIndex
	register("MonsterHunt", {
		new = function(_world, balance, _startedAt, _targetUserId, options)
			local index = if options then options.index else 1
			if index == failHuntIndex then
				error("Fixture rejected reinforcement creation " .. tostring(index))
			end
			local hunt = {
				state = "patrol",
				index = index,
				baseDetection = balance.monster_detect_radius,
				detectRadius = balance.monster_detect_radius,
				position = if options then options.position else r.Vector3.zero,
				steps = {},
				destroyCalls = 0,
				captures = 0,
				ends = 0,
			}
			function hunt:GetPosition()
				return self.position
			end
			function hunt:SetDetectionMultiplier(value)
				self.multiplier = value
				self.detectRadius = self.baseDetection * value
			end
			function hunt:StepPlayers(dt, at, candidates)
				local ids = {}
				for _, candidate in candidates do
					table.insert(ids, candidate.userId)
				end
				table.insert(self.steps, { dt = dt, at = at, ids = ids })
				if self.nextCatch and self.state ~= "capturing" then
					for _, candidate in candidates do
						if candidate.userId == self.nextCatch and not candidate.protected then
							self.nextCatch = nil
							return candidate, false
						end
					end
				end
				return nil, false
			end
			function hunt:BeginCapture(position)
				self.state = "capturing"
				self.captures += 1
				return r.CFrame.new(position)
			end
			function hunt:EndCapture()
				self.state = "patrol"
				self.ends += 1
			end
			function hunt:Stun()
				return false
			end
			function hunt:Destroy()
				self.destroyed = true
				self.destroyCalls += 1
			end
			table.insert(hunts, hunt)
			return hunt
		end,
	})
	register("RoundAudio", {
		new = function()
			local audio = { steps = 0, destroyCalls = 0, arrivalCalls = 0, requestedCries = 0 }
			function audio:ReinforcementsSpawned(reinforcements)
				self.arrivalCalls += 1
				assert(
					activeTeam and activeTeam.state == "active" and activeTeam.gateOpen,
					"Arrival notification preceded the authoritative active gate transaction"
				)
				assert(
					activeTeam.evacuationActive and activeTeam.evacuationDeadline == now + 120,
					"Arrival notification preceded the shared evacuation deadline commit"
				)
				assert(
					reinforcements == activeTeam.reinforcements
						and #reinforcements == 2
						and #hunts == 3,
					"Arrival notification preceded both successful NPC creations"
				)
				for index, source in reinforcements do
					assert(
						source == hunts[index + 1]
							and source.index == index + 1
							and source.multiplier == 2
							and source.detectRadius == 96
							and not source.destroyed,
						"Arrival notification carried an incomplete or unconfigured reinforcement"
					)
				end
				self.notifiedPair = table.clone(reinforcements)
				if self.throwArrival then
					error("Fixture arrival decoder/service failure")
				end
				self.requestedCries += 2
				return 2
			end
			function audio:Step(_, phase, _, _, _, eligible)
				self.steps += 1
				self.phase = phase
				self.eligible = eligible
				self.eligibleAtStep = {}
				for _, player in players:GetPlayers() do
					self.eligibleAtStep[player.UserId] = eligible(player)
				end
			end
			function audio:Destroy()
				self.destroyCalls += 1
			end
			table.insert(audios, audio)
			return audio
		end,
	})
	register("SoloRound", load("src/server/Game/SoloRound.luau", environment("SoloRound")))
	register(
		"RoundParticipant",
		load(
			"src/server/Game/RoundParticipant.luau",
			environment("RoundParticipant"),
			-- Optional test-process-only archived Source for a negative regression
			-- replay. Normal runs execute the current production file unchanged.
			process.env.COC_MULTIPLAYER_PARTICIPANT_TEST_SOURCE
		)
	)
	local Team = load("src/server/Game/TeamRound.luau", environment("TeamRound"))
	local events, sent, warnings = {}, {}, {}
	for _, name in modules.EndpointNames do
		local event = { OnServerEvent = signal() }
		function event:FireClient(player, payload)
			table.insert(sent, { player = player, payload = payload })
		end
		events[name] = event
	end
	local context = {
		Config = { Game = { MaxPlayers = 4 }, CoreLoop = load("src/shared/Game/Balance.luau", {}) },
		Services = {
			NetworkService = {
				GetEvent = function(_, name)
					return assert(events[name], name)
				end,
			},
		},
		Log = {
			Warn = function(_, ...)
				table.insert(warnings, { ... })
			end,
			Info = function() end,
		},
	}
	local users = {}
	local function add(name)
		local player = make("Player", name or "Player" .. tostring(#users + 1), players)
		player.UserId = 1000 + #users + 1
		local character = make("Model", player.Name, workspace)
		local humanoid = make("Humanoid", "Humanoid", character)
		local root = make("Part", "HumanoidRootPart", character)
		root.Position = world.Spawns[(#users % 4) + 1].Position
		player.Character = character
		local user = { player = player, character = character, humanoid = humanoid, root = root }
		table.insert(users, user)
		return user
	end
	for _ = 1, count do
		add()
	end
	local team = Team.new(context)
	activeTeam = team
	team:Start()
	flush()
	local result = {
		team = team,
		world = world,
		users = users,
		modules = modules,
		hunts = hunts,
		audios = audios,
		sent = sent,
		warnings = warnings,
		connections = connections,
		lighting = lighting,
	}
	function result:now()
		return now
	end
	function result:failHuntSpawn(index)
		failHuntIndex = index
	end
	function result:onNextWait(callback)
		nextWait = callback
	end
	function result:respawn(index)
		local user = users[index]
		local old = user.character
		user.player.CharacterRemoving:Fire(old)
		old.Parent = nil
		local character = make("Model", user.player.Name .. "Respawn", workspace)
		local humanoid = make("Humanoid", "Humanoid", character)
		local root = make("Part", "HumanoidRootPart", character)
		root.Position = world.Spawns[index].Position
		user.character, user.humanoid, user.root = character, humanoid, root
		user.player.Character = character
		user.player.CharacterAdded:Fire(character)
		return old, character
	end
	function result:advance(seconds, heartbeat)
		now += seconds
		flush()
		if heartbeat then
			run.Heartbeat:Fire(seconds)
			flush()
		end
	end
	function result:flush()
		flush()
	end
	function result:member(index)
		return assert(team.members[users[index].player])
	end
	function result:request(index, action, mode)
		events[modules.EndpointNames.RequestRoundAction].OnServerEvent:Fire(
			users[index].player,
			action,
			mode
		)
	end
	function result:inventory(index, action, slot)
		events[modules.EndpointNames.RequestInventoryAction].OnServerEvent:Fire(
			users[index].player,
			action,
			slot
		)
	end
	function result:sprint(index, value)
		events[modules.EndpointNames.RequestSprintIntent].OnServerEvent:Fire(
			users[index].player,
			value
		)
	end
	function result:add(name)
		local user = add(name)
		players.PlayerAdded:Fire(user.player)
		flush()
		return user
	end
	function result:remove(index)
		local user = users[index]
		players.PlayerRemoving:Fire(user.player)
		user.player.Parent = nil
		flush()
	end
	function result:start()
		for index in users do
			self:request(index, "start", "hard")
		end
		flush()
		assert(team.state == "active", "Team did not enter active state")
	end
	function result:pickup(index)
		self:advance(0.3)
		assert(world.Key and world.KeyPrompt, "Shared key is not recoverable")
		users[index].root.Position = world.Key.Position
		world.KeyPrompt.Triggered:Fire(users[index].player)
		assert(team.keyCarrier == self:member(index), "Shared key pickup failed")
	end
	function result:gate(index)
		self:advance(0.3)
		users[index].root.Position = world.GateAnchor.Position
		world.GatePrompt.Triggered:Fire(users[index].player)
		assert(team.gateOpen and team.evacuationActive, "Shared gate did not open")
	end
	return result
end

local function countKind(member, kind)
	local count = 0
	for _, value in member.inventory.slots do
		if value == kind then
			count += 1
		end
	end
	return count
end

-- Two players, server readiness, prompt contention, independent rate buckets,
-- same item consumption, owner-only sprint, and one shared evacuation deadline.
-- Preparation must wait for a new healthy character after a prior-round death.
-- Neither old-corpse removal nor a delayed old Died event belongs to the newly
-- reset round. Fresh active/caught events still finish that current attempt.
do
	local failures = {}
	for _, oldEvent in { "CharacterRemoving", "Died" } do
		for _, freshPhase in { "active", "caught" } do
			for _, freshEvent in { "CharacterRemoving", "Died" } do
				local label = oldEvent .. " -> " .. freshPhase .. "/" .. freshEvent
				local ok, problem = pcall(function()
					local f = fixture(2)
					f:start()
					local a, b = f:member(1), f:member(2)
					local corpse, oldHumanoid = f.users[1].character, f.users[1].humanoid
					oldHumanoid.Health = 0
					oldHumanoid.Died:Fire()
					f:request(2, "abort")
					assert(f.team.state == "finished" and a.phase == "aborted")
					local previousRound = f.team.roundId
					f:advance(1)
					f:request(1, "retry", "hard")
					local replaced = false
					f:onNextWait(function()
						assert(
							a.phase == "preparing"
								and a.roundCharacter == nil
								and a.boundCharacter == corpse,
							"Fixture did not reach the production corpse preparation wait"
						)
						if oldEvent == "Died" then
							oldHumanoid.Died:Fire()
							assert(
								a.phase == "preparing",
								"Delayed previous Died aborted preparation before CharacterRemoving"
							)
						end
						f:respawn(1)
						replaced = true
					end)
					f:request(2, "retry", "hard")
					f:flush()
					assert(
						replaced
							and f.team.roundId == previousRound + 1
							and f.team.state == "active"
					)
					assert(
						a.phase == "active" and b.phase == "active",
						"Previous corpse event aborted the new round: A="
							.. a.phase
							.. ", B="
							.. b.phase
					)
					assert(
						a.roundCharacter == f.users[1].character
							and a.boundCharacter == f.users[1].character
							and f.users[1].character ~= corpse
							and f.users[1].humanoid.Health > 0
							and #a.minimap.deaths == 0,
						"The new healthy character was not committed cleanly"
					)
					oldHumanoid.Died:Fire()
					assert(
						a.phase == "active",
						"Old disconnected Died listener finished the current character"
					)
					f:pickup(1)
					if freshPhase == "caught" then
						f.team.hunt.nextCatch = f.users[1].player.UserId
						f:advance(0.3, true)
						assert(a.phase == "caught" and f.world.Key and not a.hasKey)
					end
					if freshEvent == "Died" then
						f.users[1].humanoid.Health = 0
						f.users[1].humanoid.Died:Fire()
					else
						f.users[1].player.CharacterRemoving:Fire(f.users[1].character)
					end
					assert(
						a.phase == "aborted"
							and b.phase == "active"
							and f.team.state == "active"
							and f.world.Key
							and not a.hasKey
							and not f.team.keyCarrier,
						"Current active/caught death or removal did not finish and recover the shared key"
					)
				end)
				if not ok then
					table.insert(failures, label .. ": " .. tostring(problem))
					print("FAIL corpse retry regression " .. failures[#failures])
				end
			end
		end
	end
	assert(#failures == 0, "Corpse retry regression failures: " .. tostring(#failures))
end

do
	local f = fixture(2)
	local team, a, b = f.team, f:member(1), f:member(2)
	f:request(1, "start", "hard")
	assert(team.state == "waiting" and a.ready and not b.ready and team.roundId == 0)
	f:request(2, "start", "easy")
	assert(team.state == "waiting" and not b.ready)
	f:advance(0.6)
	f:request(2, "start", "hard")
	assert(team.state == "preparing")
	f:flush()
	assert(team.state == "active" and team.roundId == 1 and not a.ready and not b.ready)
	assert(
		a.selectedSpawn ~= b.selectedSpawn and a.inventory ~= b.inventory and a.stamina ~= b.stamina
	)
	assert(a.minimap ~= b.minimap and a.items == b.items and #team:_hunts() == 1)
	assert(#team.items.pickups == 4, "The team must share two energy and two trap pickups")
	local keyPrompt = f.world.KeyPrompt
	f.users[1].root.Position, f.users[2].root.Position = f.world.Key.Position, f.world.Key.Position
	keyPrompt.Triggered:Fire(f.users[1].player)
	keyPrompt.Triggered:Fire(f.users[2].player)
	assert(team.keyCarrier == a and a.hasKey and not b.hasKey and not f.world.Key)
	assert(
		countKind(a, "key") + countKind(b, "key") == 1,
		"Shared key contention duplicated the key"
	)
	f:advance(0.3)
	local entry = team.items.pickups[1]
	f.users[1].root.Position, f.users[2].root.Position =
		entry.anchor.Position, entry.anchor.Position
	entry.prompt.Triggered:Fire(f.users[1].player)
	entry.prompt.Triggered:Fire(f.users[2].player)
	assert(not entry.model.Parent and not entry.prompt.Enabled)
	assert(
		countKind(a, entry.kind) + countKind(b, entry.kind) == 1,
		"Same-item contention duplicated inventory"
	)
	f:advance(1)
	local before = #f.sent
	for _ = 1, 20 do
		f:request(1, "sync")
	end
	assert(#f.sent - before == 2, "Round-action burst exceeded two tokens")
	f:request(2, "sync")
	assert(#f.sent - before == 3, "A request burst consumed B's rate bucket")
	f:advance(0.5)
	f:request(1, "sync")
	assert(#f.sent - before == 4, "Round request bucket did not refill")
	before = #f.sent
	for _ = 1, 20 do
		f:inventory(1, "select", 2)
	end
	assert(#f.sent - before == 10, "Inventory request burst was not bounded")
	f:inventory(2, "select", 3)
	assert(b.inventory.selected == 3 and #f.sent - before == 11)
	f:sprint(1, "true")
	assert(not a.stamina.intent and not b.stamina.intent)
	for _ = 1, 14 do
		f:sprint(1, true)
		f:sprint(1, false)
	end
	f:sprint(1, true)
	assert(not a.stamina.intent, "Sprint request burst was not bounded")
	f:sprint(2, true)
	assert(b.stamina.intent, "Sprint rate bucket leaked across players")
	f:sprint(2, false)
	f:advance(1)
	local energy = assert(table.find(a.inventory.slots, "energy"))
	f:inventory(1, "select", energy)
	f:inventory(1, "use", energy)
	assert(
		a.inventory.useId == 1
			and b.inventory.useId == 0
			and a.inventory.energyUntil == f:now() + 30
	)
	a:_movement(0.1)
	b:_movement(0.1)
	assert(f.users[1].humanoid.WalkSpeed == 24 and f.users[2].humanoid.WalkSpeed == 12)
	f.users[2].root.Position = f.world.GateAnchor.Position
	f.world.GatePrompt.Triggered:Fire(f.users[2].player)
	assert(not team.gateOpen and b.notice == "corn_loop_need_key")
	f:gate(1)
	local deadline, primary = team.evacuationDeadline, team.hunt
	assert(deadline == f:now() + 120 and #team:_hunts() == 3)
	for _, hunt in team:_hunts() do
		assert(hunt.multiplier == 2 and hunt.detectRadius == 96)
	end
	assert(team.audio.arrivalCalls == 1 and team.audio.requestedCries == 2)
	assert(not a.hasKey and not b.hasKey and not team.keyCarrier and countKind(a, "key") == 0)
	for _ = 1, 5 do
		f.world.GatePrompt.Triggered:Fire(f.users[1].player)
		team:_openGate(f.users[2].player)
	end
	assert(
		team.evacuationDeadline == deadline and team.hunt == primary and #f.hunts == 3,
		"Repeated gate interaction reset the deadline or added hunters"
	)
	assert(
		team.audio.arrivalCalls == 1 and team.audio.requestedCries == 2,
		"Repeated gate interaction replayed the successful reinforcement notification"
	)
	assert(#f.warnings == 0, "Successful gate emitted an audio integration warning")
	local snapshot = team:Snapshot(b)
	assert(snapshot.key_state == "opened" and snapshot.remaining == 2 and snapshot.count == 2)
	for key in snapshot do
		assert(
			({
				round_id = true,
				state = true,
				capacity = true,
				count = true,
				ready_count = true,
				remaining = true,
				ready = true,
				can_start = true,
				key_state = true,
				carrier_name = true,
			})[key],
			"Shared snapshot leaked an unapproved marker or coordinate"
		)
	end
end

-- The supported range includes a single ready participant and three players;
-- each retains personal attempts/reward while using the same one-shot gate.
for _, participantCount in { 1, 3 } do
	local f = fixture(participantCount)
	f:start()
	assert(
		f.team:Snapshot(f:member(1)).count == participantCount
			and f.team:_remaining() == participantCount
			and #f.team:_hunts() == 1
	)
	for index = 1, participantCount do
		assert(f:member(index).catches == 0 and f:member(index).diamonds == 0)
	end
	f:pickup(1)
	f:gate(1)
	assert(f.team.audio.arrivalCalls == 1 and f.team.audio.requestedCries == 2 and #f.warnings == 0)
	f.users[1].root.Position = r.Vector3.new(0, 3, 326)
	f:advance(0.3, true)
	assert(f:member(1).phase == "escaped" and f:member(1).diamonds == 20)
	if participantCount == 1 then
		assert(f.team.state == "finished" and not f.team.audio)
	else
		assert(f.team.state == "active" and f.team:_remaining() == participantCount - 1)
		assert(f:member(2).phase == "active" and f:member(2).diamonds == 0)
	end
end

-- A failed second reinforcement never notifies audio for the partial pair.
-- The existing setup-failure transaction completes every actor and cleans up.
do
	local f = fixture(2)
	f:start()
	f:pickup(1)
	local audio = f.team.audio
	f:failHuntSpawn(3)
	f:advance(0.3)
	f.users[1].root.Position = f.world.GateAnchor.Position
	f.world.GatePrompt.Triggered:Fire(f.users[1].player)
	assert(
		audio.arrivalCalls == 0 and audio.requestedCries == 0,
		"A partial reinforcement spawn emitted an arrival notification"
	)
	assert(#f.hunts == 2 and f.hunts[1].destroyed and f.hunts[2].destroyed)
	assert(f.team.state == "finished" and not f.team.audio and not f.team.evacuationDeadline)
	assert(
		f:member(1).phase == "aborted"
			and f:member(2).phase == "aborted"
			and audio.destroyCalls == 1
	)
	assert(#f.warnings == 1 and f.warnings[1][1] == "Cannot prepare team evacuation:")
end

-- Audio is presentation: a failed notification cannot roll back an otherwise
-- committed shared gate or prevent either live participant from continuing.
do
	local f = fixture(2)
	f:start()
	f:pickup(1)
	local audio = f.team.audio
	audio.throwArrival = true
	f:gate(1)
	local deadline = f.team.evacuationDeadline
	assert(
		f.team.state == "active"
			and f.team.gateOpen
			and f.team.evacuationActive
			and deadline == f:now() + 120
			and #f.team:_hunts() == 3
	)
	assert(f:member(1).phase == "active" and f:member(2).phase == "active")
	assert(audio.arrivalCalls == 1 and audio.requestedCries == 0 and audio.destroyCalls == 0)
	assert(
		#f.warnings == 1 and f.warnings[1][1] == "Cannot play team reinforcement arrival voices:"
	)
	f:advance(0.3, true)
	f.world.GatePrompt.Triggered:Fire(f.users[1].player)
	assert(
		audio.arrivalCalls == 1 and f.team.evacuationDeadline == deadline,
		"A failed audio presentation caused gameplay to replay the gate notification"
	)
	f.users[1].root.Position = r.Vector3.new(0, 3, 326)
	f:advance(0.3, true)
	assert(
		f:member(1).phase == "escaped"
			and f:member(1).diamonds == 20
			and f:member(2).phase == "active"
			and f.team.state == "active"
	)
end

-- One escape pays once and does not finish the other participant's hunt, world
-- or deadline. Terminal menu/retry/start cannot reset a running teammate.
do
	local f = fixture(2)
	f:start()
	f:pickup(1)
	f:gate(1)
	local team, a, b = f.team, f:member(1), f:member(2)
	local deadline, primary, items, audio, roundId =
		team.evacuationDeadline, team.hunt, team.items, team.audio, team.roundId
	f.users[1].root.Position, f.users[2].root.Position =
		r.Vector3.new(0, 3, 326), r.Vector3.new(25, 3, 0)
	f:advance(0.3, true)
	assert(a.phase == "escaped" and a.reward == 20 and a.diamonds == 20 and b.phase == "active")
	assert(
		team.state == "active"
			and team:_remaining() == 1
			and team.hunt == primary
			and team.items == items
			and team.audio == audio
	)
	assert(team.evacuationDeadline == deadline and not primary.destroyed)
	a:_finish("escaped", "")
	f:advance(0.3, true)
	assert(a.diamonds == 20 and b.diamonds == 0 and #primary.steps >= 2)
	assert(table.find(primary.steps[#primary.steps].ids, f.users[2].player.UserId))
	assert(not table.find(primary.steps[#primary.steps].ids, f.users[1].player.UserId))
	assert(audio.eligible(f.users[2].player) and not audio.eligible(f.users[1].player))
	f:advance(1)
	f:request(1, "retry", "hard")
	assert(not a.ready and team.roundId == roundId and b.phase == "active")
	f:request(1, "menu")
	assert(a.phase == "ready" and not a.inRound and team.state == "active" and b.phase == "active")
	f:advance(0.6)
	f:request(1, "start", "hard")
	assert(not a.ready and team.hunt == primary and team.evacuationDeadline == deadline)
	f:advance(deadline - f:now() + 0.01, true)
	assert(b.phase == "caught_out" and b.notice == "corn_evacuation_expired" and b.diamonds == 0)
	assert(team.state == "finished" and not team.hunt and not team.items and not team.audio)
	for _, hunt in f.hunts do
		assert(hunt.destroyed and hunt.destroyCalls == 1)
	end
	assert(items.folder.Destroyed and audio.destroyCalls == 1 and not team.evacuationDeadline)
	assert(
		f.lighting.ClockTime == 9 and f.lighting.Brightness == 2 and f.lighting.FogEnd == 900,
		"Last terminal result did not restore the saved lighting baseline"
	)
	f:advance(1)
	f:request(1, "start", "hard")
	assert(team.state == "finished" and a.ready)
	f:request(2, "retry", "hard")
	f:flush()
	assert(
		team.roundId == roundId + 1
			and team.state == "active"
			and a.diamonds == 20
			and b.diamonds == 0
	)
end

-- The shared evacuation clock continues through an individual capture/revival.
do
	local f = fixture(2)
	f:start()
	f:pickup(1)
	f:gate(1)
	local team, a, b = f.team, f:member(1), f:member(2)
	local primary, deadline, items, audio, epoch =
		team.hunt, team.evacuationDeadline, team.items, team.audio, team.epoch
	f.users[2].root.Position = r.Vector3.new(25, 3, 0)
	primary.nextCatch = f.users[1].player.UserId
	f:advance(0.3, true)
	assert(a.phase == "caught" and b.phase == "active" and team.evacuationDeadline == deadline)
	assert(
		audio.phase == "active"
			and audio.eligibleAtStep[f.users[2].player.UserId] == true
			and audio.eligibleAtStep[f.users[1].player.UserId] == false
			and audio.destroyCalls == 0,
		"A personal capture paused shared audio or retained that player's corn movement"
	)
	local caughtRemaining = deadline - f:now()
	f:advance(1.01, true)
	f:request(1, "revive")
	assert(a.phase == "active" and team.evacuationActive and team.evacuationDeadline == deadline)
	assert(deadline - f:now() < caughtRemaining and team.epoch == epoch and #team:_hunts() == 3)
	assert(
		team.hunt == primary and team.items == items and team.audio == audio and b.phase == "active"
	)
	for _, hunt in team:_hunts() do
		assert(not hunt.destroyed)
	end
end

-- First capture drops a recoverable key, preserves consumables and visited
-- history; revival resets only that actor. Second capture also drops the key.
do
	local f = fixture(2)
	f:start()
	f:pickup(1)
	local team, a, b = f.team, f:member(1), f:member(2)
	local primary, items, epoch, roundId = team.hunt, team.items, team.epoch, team.roundId
	f.modules.Inventory.Add(a.inventory, "energy")
	a.inventory.energyUntil = f:now() + 30
	a.minimap:_visit("clearing:known", "clearing", r.Vector3.zero)
	primary.nextCatch = f.users[1].player.UserId
	f:advance(0.3, true)
	assert(a.phase == "caught" and a.catches == 1 and b.phase == "active")
	assert(not a.hasKey and not team.keyCarrier and f.world.Key and f.world.drops == 1)
	assert(countKind(a, "energy") == 1 and a.inventory.energyUntil == 0)
	local visited = #a.minimap.visited
	f:request(1, "revive")
	assert(a.phase == "caught", "Revival bypassed the server capture timer")
	f:advance(1.01)
	assert(a.captureUntil == 0 and primary.ends == 1)
	f:request(1, "revive")
	assert(a.phase == "active" and a.catches == 1 and a.protectedUntil == f:now() + 5)
	assert(
		team.hunt == primary
			and team.items == items
			and team.epoch == epoch
			and team.roundId == roundId
	)
	assert(b.phase == "active" and #a.minimap.visited == visited and #a.minimap.deaths == 1)
	f:pickup(1)
	f:advance(5.1)
	primary.nextCatch = f.users[1].player.UserId
	f:advance(0.3, true)
	assert(a.phase == "caught" and a.catches == 2 and f.world.Key and f.world.drops == 2)
	f:advance(1.01)
	assert(
		a.phase == "caught_out"
			and team.state == "active"
			and b.phase == "active"
			and not primary.destroyed
	)
	f:request(1, "revive")
	assert(a.phase == "caught_out", "Second capture accepted same-round revival")
	f:pickup(2)
	assert(team.keyCarrier == b and countKind(a, "key") == 0 and countKind(b, "key") == 1)
end

-- A failed nearby drop falls back to the original key slot. If both engine
-- placements fail, the coordinator completes every actor instead of stranding
-- an active teammate in a keyless shared round.
do
	local f = fixture(2)
	f:start()
	f:pickup(1)
	f.world.failDrop, f.world.failSpawn = true, true
	f:request(1, "abort")
	assert(
		f.team.state == "finished"
			and f:member(1).phase == "aborted"
			and f:member(2).phase == "aborted"
	)
	assert(not f.team.keyCarrier and not f.world.Key and not f.team.items and not f.team.hunt)
	assert(f:member(2).notice == "corn_hunt_drop_error")
end

-- Died/CharacterRemoving/disconnect and explicit abort recover the shared key
-- without ending the remaining player's round. Died must work at Health zero.
for _, reason in { "death", "characterRemoving", "disconnect", "abort", "dropFallback" } do
	local f = fixture(2)
	f:start()
	f:pickup(1)
	local team, a, b = f.team, f:member(1), f:member(2)
	local primary, items = team.hunt, team.items
	local position = f.users[1].root.Position
	if reason == "death" then
		f.users[1].humanoid.Health = 0
		f.users[1].humanoid.Died:Fire()
		assert(
			a.phase == "aborted"
				and #a.minimap.deaths == 1
				and f.world.drops == 1
				and f.world.Key.Position == position,
			"Health-zero death must recover the key from the retained round-character root"
		)
	elseif reason == "characterRemoving" then
		f.users[1].player.CharacterRemoving:Fire(f.users[1].character)
		assert(a.phase == "aborted" and #a.minimap.deaths == 1 and f.world.drops == 1)
	elseif reason == "disconnect" then
		local characterConnection, deathConnection = a.characterConnection, a.deathConnection
		f:remove(1)
		assert(a.destroyed and not characterConnection.Connected and not deathConnection.Connected)
		assert(
			not team.members[f.users[1].player]
				and #team.order == 1
				and f.world.Key.Position == position
		)
	else
		if reason == "dropFallback" then
			f.world.failDrop = true
		end
		f:request(1, "abort")
		assert(a.phase == "aborted")
		if reason == "dropFallback" then
			assert(f.world.spawns == 2)
		end
	end
	assert(
		team.state == "active"
			and b.phase == "active"
			and team.hunt == primary
			and team.items == items
	)
	assert(f.world.Key and not team.keyCarrier and not a.hasKey and countKind(a, "key") == 0)
	f:pickup(2)
	assert(team.keyCarrier == b)
	if reason == "disconnect" then
		f:remove(2)
		assert(
			team.state == "waiting"
				and #team.order == 0
				and not team.hunt
				and not team.items
				and not f.world.Key
		)
		assert(not team.gateOpen and f.world.open == false and primary.destroyed)
	else
		f:request(2, "abort")
		assert(
			team.state == "finished" and team:_remaining() == 0 and not team.hunt and not team.items
		)
		assert(primary.destroyed and items.folder.Destroyed and not f.world.Key)
	end
	assert(#f.warnings == 0, "Unexpected setup failure in " .. reason)
end

-- An admitted late join waits for the next common round; the fifth connection
-- remains outside capacity. Once all previous actors finish, four ready actors
-- start together at distinct authored corners. Queue admission never restarts it.
do
	local f = fixture(2)
	f:start()
	local team, roundId, primary = f.team, f.team.roundId, f.team.hunt
	f:add("Late C")
	f:add("Late D")
	f:add("Queued E")
	local c, d, e = f:member(3), f:member(4), f:member(5)
	assert(c.admitted and d.admitted and not e.admitted)
	assert(c.phase == "ready" and not c.inRound and f.users[3].humanoid.WalkSpeed == 0)
	local snapshot = team:Snapshot(c)
	assert(snapshot.count == 4 and snapshot.remaining == 2 and not snapshot.can_start)
	f:request(3, "start", "hard")
	f:request(5, "start", "hard")
	assert(not c.ready and not e.ready and team.roundId == roundId and team.hunt == primary)
	f:request(1, "abort")
	f:request(2, "abort")
	assert(team.state == "finished")
	f:advance(1)
	f:request(1, "retry", "hard")
	f:request(2, "retry", "hard")
	f:request(3, "start", "hard")
	assert(team.state == "finished" and not d.ready)
	f:request(4, "start", "hard")
	f:flush()
	assert(team.state == "active" and team.roundId == roundId + 1 and team:_remaining() == 4)
	local starts = {}
	for index = 1, 4 do
		local member = f:member(index)
		assert(member.phase == "active" and not starts[member.selectedSpawn])
		starts[member.selectedSpawn] = true
	end
	assert(e.phase == "ready" and not e.inRound)
	local current = team.hunt
	f:remove(4)
	assert(e.admitted and not e.inRound and not team:Snapshot(e).can_start)
	assert(team.hunt == current and team:_remaining() == 3)
end

print(
	"PASS production shared-key TeamRound/RoundParticipant: supported1-4 participants, two-player readiness, key/item contention, shared gate/120-second deadline/three NPCs at96, one post-commit reinforcement notification/no replay, failed second spawn silent and throwing audio keeps gameplay active; first/second capture/personal revival/shared audio continuity, Health-zero death/character removal/disconnect/abort/fallback key recovery, one escape +20 once while teammate continues, terminal retry/menu isolation, per-player round/inventory/sprint limits, late-join/capacity/four distinct starts and all-terminal/empty cleanup. Deterministic engine/world/hunt/audio adapters; no Studio network, NPC decision or visual/FPS acceptance claim."
)
