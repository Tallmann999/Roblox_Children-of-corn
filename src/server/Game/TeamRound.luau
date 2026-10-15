--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Shared = ReplicatedStorage:WaitForChild("GameShared")
local Endpoints = require(Shared:WaitForChild("Network"):WaitForChild("EndpointNames"))
local Inventory = require(Shared:WaitForChild("Game"):WaitForChild("Inventory"))
local LightingModes = require(Shared.Game:WaitForChild("LightingModes"))
local AuthoredWorld = require(script.Parent:WaitForChild("AuthoredWorld"))
local Participant = require(script.Parent:WaitForChild("RoundParticipant"))
local InventoryWorld = require(script.Parent:WaitForChild("InventoryWorld"))
local MonsterHunt = require(script.Parent:WaitForChild("MonsterHunt"))
local RoundAudio = require(script.Parent:WaitForChild("RoundAudio"))
local MinimapState = require(script.Parent:WaitForChild("MinimapState"))

local TeamRound = {}
TeamRound.__index = TeamRound

function TeamRound.new(context: any): any
	local network = context.Services.NetworkService
	return setmetatable({
		context = context,
		balance = context.Config.CoreLoop,
		capacity = context.Config.Game.MaxPlayers,
		action = network:GetEvent(Endpoints.RequestRoundAction),
		snapshot = network:GetEvent(Endpoints.RoundSnapshot),
		sprintIntent = network:GetEvent(Endpoints.RequestSprintIntent),
		inventoryAction = network:GetEvent(Endpoints.RequestInventoryAction),
		members = {},
		order = {},
		connections = {},
		state = "waiting",
		roundId = 0,
		epoch = 0,
		world = nil,
		items = nil,
		hunt = nil,
		reinforcements = {},
		audio = nil,
		keyCarrier = nil,
		keySlot = nil,
		keyConnection = nil,
		gateOpen = false,
		evacuationActive = false,
		evacuationDeadline = nil,
		lightingMode = LightingModes.Default,
		lightingState = nil,
		startedAt = nil,
		huntAt = 0,
		pollAt = 0,
		snapshotAt = 0,
		random = Random.new(),
		ending = false,
	}, TeamRound)
end

function TeamRound:_admitted(): { any }
	local result = {}
	for _, member in self.order do
		if member.admitted and not member.destroyed then
			table.insert(result, member)
		end
	end
	return result
end

function TeamRound:_remaining(): number
	local count = 0
	for _, member in self.order do
		if
			member.inRound
			and member.joinedRound == self.roundId
			and (
				member.phase == "active"
				or member.phase == "caught"
				or member.phase == "preparing"
			)
		then
			count += 1
		end
	end
	return count
end

function TeamRound:Snapshot(member: any): any
	local admitted = self:_admitted()
	local ready = 0
	for _, entry in admitted do
		if entry.ready then
			ready += 1
		end
	end
	return {
		round_id = self.roundId,
		state = self.state,
		capacity = self.capacity,
		count = #admitted,
		ready_count = ready,
		remaining = self:_remaining(),
		ready = member.ready,
		can_start = member.admitted
			and not member.ready
			and (self.state == "waiting" or self.state == "finished"),
		key_state = if self.gateOpen
			then "opened"
			elseif self.keyCarrier then "carried"
			else "hidden",
		carrier_name = if self.keyCarrier
			then string.sub(self.keyCarrier.player.Name, 1, 50)
			else "",
	}
end

function TeamRound:Broadcast()
	for _, member in self.order do
		member:_send()
	end
end

function TeamRound:_hunts(): { any }
	local result = {}
	if self.hunt then
		table.insert(result, self.hunt)
	end
	for _, hunt in self.reinforcements do
		table.insert(result, hunt)
	end
	return result
end

function TeamRound:MonsterState(member: any): string
	for _, hunt in self:_hunts() do
		if
			not hunt.destroyed
			and hunt.state == "chase"
			and hunt.targetUserId == member.player.UserId
		then
			return "chase"
		end
	end
	local primary = self.hunt
	return if not primary
		then "stopped"
		elseif primary.state == "chase" then "patrol"
		else primary.state
end

function TeamRound:_ensureWorld(): boolean
	if self.world then
		return self.world:IsValid()
	end
	local ok, world =
		pcall(AuthoredWorld.new, self.balance.interaction_radius, self.balance.key_slot_count)
	if not ok then
		self.context.Log:Warn("Cannot bind multiplayer CornMap:", world)
		return false
	end
	self.world = world
	table.insert(
		self.connections,
		world.GatePrompt.Triggered:Connect(function(player: Player)
			self:_openGate(player)
		end)
	)
	return true
end

function TeamRound:_clearKey()
	if self.keyConnection then
		self.keyConnection:Disconnect()
		self.keyConnection = nil
	end
	if self.world then
		self.world:ClearKey()
	end
end

function TeamRound:_bindKey(prompt: ProximityPrompt)
	if self.keyConnection then
		self.keyConnection:Disconnect()
	end
	local epoch = self.epoch
	self.keyConnection = prompt.Triggered:Connect(function(player: Player)
		local member = self.members[player]
		local key = self.world.Key
		if
			self.epoch ~= epoch
			or self.state ~= "active"
			or self.keyCarrier
			or self.gateOpen
			or not key
			or prompt ~= self.world.KeyPrompt
		then
			return
		end
		if
			self:ExpireEvacuation(os.clock())
			or not member
			or not member:_canInteract(player, key, prompt)
		then
			return
		end
		if not Inventory.Add(member.inventory, "key") then
			member.notice = "corn_inventory_full"
			member:_send()
			return
		end
		self.keyCarrier = member
		member.hasKey = true
		member.notice = ""
		self:_clearKey()
		self:Broadcast()
	end)
end

function TeamRound:DropKey(member: any, position: Vector3?)
	if self.keyCarrier ~= member then
		return
	end
	self.keyCarrier = nil
	member.hasKey = false
	Inventory.Remove(member.inventory, "key")
	if self.gateOpen or not self.world or self.state ~= "active" then
		return
	end
	local prompt = if position
		then self.world:DropKey(position, self.balance.key_drop_adjust_radius)
		else nil
	if not prompt and self.keySlot then
		prompt = self.world:SpawnKey(self.keySlot)
	end
	if prompt then
		self:_bindKey(prompt)
		self.world:SetInteractionEnabled(true, false)
	else
		self:_abortAll("corn_hunt_drop_error")
	end
end

function TeamRound:_cleanup(state: string)
	self.epoch += 1
	self:_clearKey()
	self.keyCarrier = nil
	if self.items then
		self.items:Destroy()
		self.items = nil
	end
	for _, member in self.order do
		member.items = nil
	end
	if self.audio then
		self.audio:Destroy()
		self.audio = nil
	end
	for _, hunt in self:_hunts() do
		hunt:Destroy()
	end
	self.hunt = nil
	table.clear(self.reinforcements)
	self.evacuationActive = false
	self.evacuationDeadline = nil
	if self.world then
		self.world:SetInteractionEnabled(false, self.gateOpen)
	end
	if self.lightingState then
		LightingModes.Restore(Lighting, self.lightingState)
		self.lightingState = nil
	end
	self.state = state
end

function TeamRound:CompleteIfDone()
	if
		not self.ending
		and (self.state == "active" or self.state == "preparing")
		and self:_remaining() == 0
	then
		self:_cleanup("finished")
	end
end

function TeamRound:_abortAll(notice: string)
	if self.ending then
		return
	end
	self.ending = true
	for _, member in self.order do
		if member.inRound then
			member:_finish("aborted", notice)
		end
	end
	self.ending = false
	self:_cleanup("finished")
	self:Broadcast()
end

function TeamRound:ExpireEvacuation(now: number): boolean
	if self.state ~= "active" or not self.evacuationDeadline or now < self.evacuationDeadline then
		return false
	end
	self.ending = true
	for _, member in self.order do
		if member.inRound and (member.phase == "active" or member.phase == "caught") then
			member:_finish("caught_out", "corn_evacuation_expired")
		end
	end
	self.ending = false
	self:_cleanup("finished")
	self:Broadcast()
	return true
end

function TeamRound:_startEvacuation(now: number, root: BasePart): boolean
	if self.evacuationActive then
		return true
	end
	if not self.hunt or self.hunt.destroyed then
		return false
	end
	local slots = table.clone(self.world.Slots)
	table.sort(slots, function(a, b)
		local da, db =
			(a.Position - root.Position).Magnitude, (b.Position - root.Position).Magnitude
		return if math.abs(da - db) < 0.01 then a.Name < b.Name else da < db
	end)
	local chosen = {}
	for _, slot in slots do
		local safe = true
		for _, member in self.order do
			local _, _, other = member:_livingCharacter()
			if
				member.phase == "active"
				and other
				and (slot.Position - other.Position).Magnitude < 48
			then
				safe = false
				break
			end
		end
		if not safe or (chosen[1] and (slot.Position - chosen[1].Position).Magnitude < 72) then
			continue
		end
		table.insert(chosen, slot)
		if #chosen == 2 then
			break
		end
	end
	if #chosen ~= 2 then
		return false
	end
	local ok, problem = pcall(function()
		self.hunt:SetDetectionMultiplier(2)
		for index, slot in chosen do
			local hunt = MonsterHunt.new(
				self.world,
				self.balance,
				now,
				nil,
				{ index = index + 1, position = slot.Position, immediate = true }
			)
			table.insert(self.reinforcements, hunt)
			hunt:SetDetectionMultiplier(2)
		end
	end)
	if not ok then
		self.context.Log:Warn("Cannot prepare team evacuation:", problem)
		return false
	end
	self.evacuationActive = true
	self.evacuationDeadline = now + self.balance.evacuation_duration_sec
	if self.audio then
		local audioOk, audioProblem =
			pcall(self.audio.ReinforcementsSpawned, self.audio, self.reinforcements)
		if not audioOk then
			self.context.Log:Warn("Cannot play team reinforcement arrival voices:", audioProblem)
		end
	end
	return true
end

function TeamRound:_openGate(player: Player)
	local member = self.members[player]
	local world = self.world
	if
		not member
		or not world
		or self.gateOpen
		or self.state ~= "active"
		or not member:_canInteract(player, world.GateAnchor, world.GatePrompt)
	then
		return
	end
	local _, _, root = member:_livingCharacter()
	if not root or not world:IsGateFront(root.Position) then
		return
	end
	if self.keyCarrier ~= member or not member.hasKey then
		member.notice = "corn_loop_need_key"
		member:_send()
		return
	end
	self.gateOpen = true
	self.keyCarrier = nil
	member.hasKey = false
	Inventory.Remove(member.inventory, "key")
	world:SetGateOpen(true)
	world:SetInteractionEnabled(true, true)
	if not self:_startEvacuation(os.clock(), root) then
		self:_abortAll("corn_loop_setup_error")
		return
	end
	for _, entry in self.order do
		if entry.phase == "active" then
			entry.notice = "corn_evacuation_started"
		end
	end
	self:Broadcast()
end

function TeamRound:_startRound()
	if self.state ~= "waiting" and self.state ~= "finished" then
		return
	end
	if not self:_ensureWorld() then
		for _, member in self.order do
			member.ready = false
			member.notice = "corn_loop_setup_error"
		end
		self:Broadcast()
		return
	end
	self:_cleanup("preparing")
	self.roundId += 1
	self.gateOpen = false
	self.startedAt = nil
	self.world:SetGateOpen(false)
	local starts = table.clone(self.world.Spawns)
	for index = #starts, 2, -1 do
		local other = self.random:NextInteger(1, index)
		starts[index], starts[other] = starts[other], starts[index]
	end
	local roster = self:_admitted()
	for index, member in roster do
		member:Reset(starts[index])
	end
	self.lightingState = LightingModes.Capture(Lighting)
	LightingModes.Apply(Lighting, self.lightingMode)
	self:Broadcast()
	local epoch = self.epoch
	task.spawn(function()
		local deadline = os.clock() + 10
		while self.epoch == epoch and self.state == "preparing" do
			local waiting = false
			for _, member in roster do
				if
					not member.destroyed
					and member.phase == "preparing"
					and not member:_livingCharacter()
				then
					waiting = true
				end
			end
			if not waiting or os.clock() >= deadline then
				break
			end
			task.wait(0.1)
		end
		if self.epoch ~= epoch or self.state ~= "preparing" then
			return
		end
		for _, member in roster do
			if member.destroyed or member.phase ~= "preparing" then
				continue
			end
			local character = member:_livingCharacter()
			if not character then
				member:_finish("aborted", "corn_loop_setup_error")
			else
				member:_moveToStart(character)
				member.roundCharacter = character
			end
		end
		if self.epoch ~= epoch or self.state ~= "preparing" then
			return
		end
		local ok, problem = pcall(function()
			assert(self.world:IsValid(), "CornMap changed during preparation")
			self.keySlot = self.world.Slots[self.random:NextInteger(1, #self.world.Slots)]
			self:_bindKey(self.world:SpawnKey(self.keySlot))
			self.items = InventoryWorld.new(
				self.world,
				self.random,
				self.keySlot,
				function(player, entry)
					local member = self.members[player]
					if
						self.epoch ~= epoch
						or self.state ~= "active"
						or not member
						or not self.items
						or entry.model.Parent ~= self.items.folder
						or not member:_canInteract(player, entry.anchor, entry.prompt)
					then
						return
					end
					if not Inventory.Add(member.inventory, entry.kind) then
						member.notice = "corn_inventory_full"
						member:_send()
						return
					end
					assert(self.items:Take(entry), "Pickup invalidated during server transaction")
					member.notice = ""
					member:_send()
				end
			)
			self.startedAt = os.clock()
			self.hunt = MonsterHunt.new(self.world, self.balance, self.startedAt)
			self.audio = RoundAudio.new(self.world, roster[1].player, self.hunt, self.random)
		end)
		if not ok then
			self.context.Log:Warn("Cannot start team round:", problem)
			self:_abortAll("corn_loop_setup_error")
			return
		end
		self.huntAt = self.startedAt
		self.state = "active"
		for _, member in roster do
			if not member.destroyed and member.phase == "preparing" then
				member.items = self.items
				member.phase = "active"
				member:_controls(true)
			end
		end
		self.world:SetInteractionEnabled(true, false)
		self:Broadcast()
	end)
end

function TeamRound:_maybeStart()
	if self.state ~= "waiting" and self.state ~= "finished" then
		return
	end
	local admitted = self:_admitted()
	if #admitted == 0 then
		return
	end
	for _, member in admitted do
		if not member.ready then
			return
		end
	end
	self:_startRound()
end

function TeamRound:_request(player: Player, action: any, mode: any)
	local member = self.members[player]
	if not member or type(action) ~= "string" then
		return
	end
	local now = os.clock()
	member.requestTokens = math.min(2, member.requestTokens + (now - member.requestAt) * 2)
	member.requestAt = now
	if member.requestTokens < 1 then
		return
	end
	member.requestTokens -= 1
	self:ExpireEvacuation(now)
	if action == "sync" then
		member:_send()
	elseif action == "revive" then
		member:_revive()
	elseif action == "menu" then
		member:_menu()
	elseif action == "abort" then
		member:_finish("aborted", "corn_loop_result_aborted")
	elseif
		(action == "start" and member.phase == "ready")
		or (
			action == "retry"
			and (
				member.phase == "escaped"
				or member.phase == "aborted"
				or member.phase == "caught_out"
			)
		)
	then
		if
			member.admitted
			and (self.state == "waiting" or self.state == "finished")
			and LightingModes.IsValid(mode)
		then
			member.ready = true
			self:Broadcast()
			self:_maybeStart()
		end
	end
end

function TeamRound:_admit()
	local count = 0
	local used = {}
	for _, member in self.order do
		if count >= self.capacity then
			member.admitted = false
			continue
		end
		count += 1
		member.admitted = true
		member.world = self.world
		if self.world then
			if not member.selectedSpawn or used[member.selectedSpawn] then
				for _, spawn in self.world.Spawns do
					if not used[spawn] then
						member.selectedSpawn = spawn
						break
					end
				end
			end
			used[member.selectedSpawn] = true
			member:_setRespawnLocation()
		end
	end
end

function TeamRound:_addPlayer(player: Player)
	if self.members[player] then
		return
	end
	local member = Participant.new(self, player)
	self.members[player] = member
	table.insert(self.order, member)
	self:_admit()
	member:Bind()
	self:Broadcast()
end

function TeamRound:_removePlayer(player: Player)
	local member = self.members[player]
	if not member then
		return
	end
	local _, _, root = member:_livingCharacter()
	self:DropKey(member, if root then root.Position else nil)
	member:Destroy()
	self.members[player] = nil
	table.remove(self.order, table.find(self.order, member))
	self:_admit()
	self:CompleteIfDone()
	if #self.order == 0 then
		self:_cleanup("waiting")
		self.gateOpen = false
		if self.world then
			self.world:SetGateOpen(false)
		end
	end
	self:Broadcast()
	self:_maybeStart()
end

function TeamRound:_poll(now: number)
	if self:ExpireEvacuation(now) or self.state ~= "active" then
		return
	end
	if not self.world or not self.world:IsValid() then
		self:_abortAll("corn_loop_setup_error")
		return
	end
	local candidates = {}
	for _, member in self.order do
		if member.phase ~= "active" or not member.inRound then
			continue
		end
		local character, _, root = member:_livingCharacter()
		if not character or character ~= member.roundCharacter or not root then
			member:_recordCharacterDeath(member.roundCharacter)
			member:_finish("aborted", "corn_loop_result_aborted")
		elseif not self.world:IsOnPlayground(root.Position) then
			member:_finish("aborted", "corn_loop_setup_error")
		else
			member.minimap:Poll(self.world, root.Position)
			table.insert(candidates, {
				userId = member.player.UserId,
				root = root,
				protected = now < member.protectedUntil,
				member = member,
			})
		end
	end
	if self.state ~= "active" then
		return
	end
	for _, hunt in self:_hunts() do
		local previous = hunt:GetPosition()
		self.items:CheckTraps(hunt, previous, now)
		local caught, awakened = hunt:StepPlayers(now - self.huntAt, now, candidates)
		if self.items:CheckTraps(hunt, previous, now) then
			caught = nil
		end
		if awakened then
			for _, member in self.order do
				if member.phase == "active" then
					member.notice = "corn_hunt_awakened"
				end
			end
		end
		if caught and caught.member.phase == "active" then
			caught.member:_caught(caught.root, hunt)
			for index = #candidates, 1, -1 do
				if candidates[index].member == caught.member then
					table.remove(candidates, index)
				end
			end
		end
	end
	self.huntAt = now
	if self.audio then
		local lead = self.hunt
		for _, hunt in self:_hunts() do
			if hunt.state == "chase" then
				lead = hunt
				break
			end
		end
		self.audio:Step(now, "active", self.lightingMode, lead, self:_hunts(), function(player)
			local member = self.members[player]
			return member ~= nil
				and member.inRound
				and member.phase == "active"
				and member.roundCharacter == player.Character
		end)
	end
	for _, candidate in candidates do
		if
			self.gateOpen
			and candidate.member.phase == "active"
			and self.world:IsInExit(candidate.root.Position)
		then
			candidate.member:_finish("escaped", "")
		end
	end
	if now - self.snapshotAt >= 0.25 then
		self.snapshotAt = now
		self:Broadcast()
	end
end

function TeamRound:Start()
	assert(self.capacity == 4, "First multiplayer version requires four authored starts")
	self:_ensureWorld()
	table.insert(
		self.connections,
		self.action.OnServerEvent:Connect(function(player, action, mode)
			self:_request(player, action, mode)
		end)
	)
	table.insert(
		self.connections,
		self.inventoryAction.OnServerEvent:Connect(function(player, action, slot)
			local member = self.members[player]
			if member and not self:ExpireEvacuation(os.clock()) then
				member:_inventoryRequest(player, action, slot)
			end
		end)
	)
	table.insert(
		self.connections,
		self.sprintIntent.OnServerEvent:Connect(function(player, value)
			local member = self.members[player]
			if member and not self:ExpireEvacuation(os.clock()) then
				member:_sprintRequest(player, value)
			end
		end)
	)
	table.insert(
		self.connections,
		Players.PlayerAdded:Connect(function(player)
			self:_addPlayer(player)
		end)
	)
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			self:_removePlayer(player)
		end)
	)
	table.insert(
		self.connections,
		RunService.Heartbeat:Connect(function(dt)
			for _, member in self.order do
				member:_movement(dt)
			end
			local now = os.clock()
			if now - self.pollAt >= MinimapState.PollInterval then
				self.pollAt = now
				self:_poll(now)
			end
		end)
	)
	for _, player in Players:GetPlayers() do
		self:_addPlayer(player)
	end
end

return TeamRound
