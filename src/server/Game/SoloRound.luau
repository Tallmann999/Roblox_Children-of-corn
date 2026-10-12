--!strict

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameShared = ReplicatedStorage:WaitForChild("GameShared")
local Endpoints = require(GameShared:WaitForChild("Network"):WaitForChild("EndpointNames"))
local AuthoredWorld = require(script.Parent:WaitForChild("AuthoredWorld"))
local MonsterHunt = require(script.Parent:WaitForChild("MonsterHunt"))
local MinimapState = require(script.Parent:WaitForChild("MinimapState"))
local Stamina = require(GameShared:WaitForChild("Game"):WaitForChild("Stamina"))
local Inventory = require(GameShared:WaitForChild("Game"):WaitForChild("Inventory"))
local InventoryWorld = require(script.Parent:WaitForChild("InventoryWorld"))

local LightingModes = require(GameShared:WaitForChild("Game"):WaitForChild("LightingModes"))

local SoloRound = {}
SoloRound.__index = SoloRound

function SoloRound.new(context: any)
	return setmetatable({
		context = context,
		balance = context.Config.CoreLoop,
		action = context.Services.NetworkService:GetEvent(Endpoints.RequestRoundAction),
		snapshot = context.Services.NetworkService:GetEvent(Endpoints.RoundSnapshot),
		sprintIntent = context.Services.NetworkService:GetEvent(Endpoints.RequestSprintIntent),
		inventoryAction = context.Services.NetworkService:GetEvent(
			Endpoints.RequestInventoryAction
		),
		inventory = Inventory.new(os.clock()),
		items = nil :: any,
		stamina = Stamina.new(context.Config.CoreLoop.stamina_capacity, os.clock()),
		minimap = MinimapState.new(),
		world = nil :: any,
		selectedSpawn = nil :: BasePart?,
		player = nil :: Player?,
		phase = "ready",
		lightingMode = LightingModes.Default,
		lightingState = nil :: any,
		epoch = 0,
		hasKey = false,
		gateOpen = false,
		diamonds = 0,
		reward = 0,
		startedAt = nil :: number?,
		hunt = nil :: any,
		catches = 0,
		captureFrame = CFrame.identity,
		captureUntil = 0,
		protectedUntil = 0,
		huntAt = 0,
		elapsed = 0,
		notice = "",
		random = Random.new(),
		connections = {} :: { RBXScriptConnection },
		characterConnection = nil :: RBXScriptConnection?,
		characterRemovingConnection = nil :: RBXScriptConnection?,
		deathConnection = nil :: RBXScriptConnection?,
		keyConnection = nil :: RBXScriptConnection?,
		roundCharacter = nil :: Model?,
		boundCharacter = nil :: Model?,
		controlledCharacter = nil :: Model?,
		jumpPower = 50,
		jumpHeight = 7.2,
		autoRotate = true,
		requestTokens = 2,
		requestAt = os.clock(),
		interactionAt = -math.huge,
		pollAt = 0,
		snapshotAt = 0,
	}, SoloRound)
end

function SoloRound:_send()
	local player = self.player
	if not player or player.Parent ~= Players then
		return
	end
	local facing = if self.selectedSpawn
		then self.selectedSpawn.CFrame.LookVector
		else Vector3.new(0, 0, -1)
	local horizontal = Vector3.new(facing.X, 0, facing.Z)
	local startLook = if horizontal.Magnitude > 0 then horizontal.Unit else Vector3.new(0, 0, -1)
	self.snapshot:FireClient(player, {
		phase = self.phase,
		lighting_mode = self.lightingMode,
		minimap = self.minimap:Snapshot(),
		inventory = Inventory.Snapshot(self.inventory, os.clock()),
		has_key = self.hasKey,
		gate_open = self.gateOpen,
		session_diamonds = self.diamonds,
		reward_diamonds = self.reward,
		elapsed_sec = if self.phase == "active" and self.startedAt
			then os.clock() - self.startedAt
			else self.elapsed,
		notice = self.notice,
		stamina = self.stamina.value,
		stamina_capacity = self.balance.stamina_capacity,
		is_sprinting = self.stamina.sprinting,
		sprint_exhausted = self.stamina.exhausted,
		start_look = startLook,
		catches_remaining = math.max(0, self.balance.max_catches - self.catches),
		capture = {
			id = self.catches,
			remaining = math.clamp(self.captureUntil - os.clock(), 0, 1),
			frame = self.captureFrame,
		},
		monster_state = if self.hunt then self.hunt.state else "stopped",
		protection_sec = math.max(0, self.protectedUntil - os.clock()),
	})
end

function SoloRound:_livingCharacter(): (Model?, Humanoid?, BasePart?)
	local player = self.player
	local character = if player then player.Character else nil
	if not character or not character.Parent then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

function SoloRound:_recordCharacterDeath(character: Model?)
	if
		not character
		or character ~= self.roundCharacter
		or (self.phase ~= "active" and self.phase ~= "caught")
	then
		return
	end
	-- Died runs after Health reaches zero, so _livingCharacter cannot supply this root.
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		self.minimap:RecordDeath(character, root.Position)
	end
end

function SoloRound:_controls(enabled: boolean)
	if not enabled then
		Stamina.Request(self.stamina, false, os.clock(), false)
	end
	local character, humanoid = self:_livingCharacter()
	if not character or not humanoid then
		return
	end
	if self.controlledCharacter ~= character then
		self.controlledCharacter = character
		self.jumpPower = humanoid.JumpPower
		self.jumpHeight = humanoid.JumpHeight
		self.autoRotate = humanoid.AutoRotate
	end
	humanoid.WalkSpeed = if enabled then self.balance.walk_speed else 0
	humanoid.JumpPower = if enabled then self.jumpPower else 0
	humanoid.JumpHeight = if enabled then self.jumpHeight else 0
	humanoid.AutoRotate = enabled and self.autoRotate
end

function SoloRound:_fallbackSpawn(): BasePart?
	local map = Workspace:FindFirstChild("CornMap")
	if
		not map
		or not map:IsA("Model")
		or map:GetAttribute("corn_project_id") ~= "children_of_corn"
	then
		return nil
	end
	local ok, result = pcall(AuthoredWorld.FindSafeSpawn, map)
	if not ok then
		self.context.Log:Warn("Cannot find a safe CornMap spawn:", result)
		return nil
	end
	return result
end

function SoloRound:_setRespawnLocation()
	local player = self.player
	if not player then
		return
	end
	local spawn = self.selectedSpawn
	player.RespawnLocation = if spawn
			and spawn:IsA("SpawnLocation")
			and spawn:IsDescendantOf(Workspace)
		then spawn
		else nil
end

function SoloRound:_chooseSpawn()
	if self.world and self.world:IsValid() then
		self.selectedSpawn = self.world:SelectSpawn(self.random:NextInteger(1, #self.world.Spawns))
	else
		self.selectedSpawn = self:_fallbackSpawn()
	end
	self:_setRespawnLocation()
end

function SoloRound:_moveToStart(character: Model)
	local spawn = self.selectedSpawn
	local map = Workspace:FindFirstChild("CornMap")
	if
		not spawn
		or not map
		or not map:IsA("Model")
		or not AuthoredWorld.IsSafeSpawn(map, spawn)
	then
		spawn = self:_fallbackSpawn()
		self.selectedSpawn = spawn
	end
	if not spawn then
		self.context.Log:Warn("No valid CornMap start; install or repair CornerSpawns")
		return
	end
	self:_setRespawnLocation()
	character:PivotTo(AuthoredWorld.SpawnCFrame(spawn))
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
end

function SoloRound:_clearKey()
	if self.keyConnection then
		self.keyConnection:Disconnect()
		self.keyConnection = nil
	end
	if self.world then
		self.world:ClearKey()
	end
end

function SoloRound:_clearInventory()
	if self.items then
		self.items:Destroy()
		self.items = nil
	end
	self.inventory = Inventory.new(os.clock())
end

function SoloRound:_promptNearby(
	root: BasePart,
	character: Model,
	item: BasePart?,
	itemPrompt: ProximityPrompt?
): boolean
	if not item or not itemPrompt or not itemPrompt.Enabled then
		return false
	end
	local direction = item.Position - root.Position
	if direction.Magnitude > self.balance.interaction_radius then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	local hit = Workspace:Raycast(root.Position, direction, params)
	return not hit or hit.Instance == item
end

function SoloRound:_inventoryRequest(player: Player, action: any, slot: any)
	if player ~= self.player or self.phase ~= "active" then
		return
	end
	local character, _, root = self:_livingCharacter()
	if not character or character ~= self.roundCharacter or not root then
		return
	end
	local now = os.clock()
	if not Inventory.Request(self.inventory, action, slot, now) then
		return
	end
	if action == "select" then
		self:_send()
		return
	end
	if not self.world or not self.world:IsValid() or now - self.interactionAt < 0.35 then
		return
	end
	if
		self:_promptNearby(root, character, self.world.Key, self.world.KeyPrompt)
		or self:_promptNearby(root, character, self.world.GateAnchor, self.world.GatePrompt)
	then
		return
	end
	if self.items then
		for _, entry in self.items.pickups do
			if
				entry.model.Parent
				and self:_promptNearby(root, character, entry.anchor, entry.prompt)
			then
				return
			end
		end
	end
	local kind = self.inventory.slots[slot]
	if kind == "energy" then
		self.inventory.energyUntil = now + Inventory.EnergyDuration
	elseif kind == "trap" then
		if not self.items or not self.items:Place(root, character) then
			return
		end
	else
		return
	end
	self.inventory.slots[slot] = "empty"
	self.inventory.useId += 1
	self.inventory.useKind = kind
	self.interactionAt = now
	self.notice = ""
	self:_send()
end

function SoloRound:_finish(phase: string, notice: string)
	if self.phase ~= "active" and self.phase ~= "preparing" and self.phase ~= "caught" then
		return
	end
	-- Fix the terminal state before rewarding or notifying any client.
	self.elapsed = if self.startedAt then os.clock() - self.startedAt else 0
	self.phase = phase
	self.captureUntil = 0
	self.epoch += 1
	self.notice = notice
	self.reward = if phase == "escaped" then self.balance.escape_reward_diamonds else 0
	self.diamonds += self.reward
	self.hasKey = false
	self:_clearInventory()
	self:_clearKey()
	if self.world then
		self.world:SetInteractionEnabled(false, self.gateOpen)
	end
	self:_stopHunt()
	self:_controls(false)
	self:_send()
	self.context.Log:Info("Round finished:", phase, "reward:", self.reward)
end

function SoloRound:_canInteract(
	player: Player,
	item: BasePart,
	itemPrompt: ProximityPrompt
): boolean
	if player ~= self.player or self.phase ~= "active" or not itemPrompt.Enabled then
		return false
	end
	local now = os.clock()
	if now - self.interactionAt < 0.25 then
		return false
	end
	self.interactionAt = now
	local character, _, root = self:_livingCharacter()
	if not character or character ~= self.roundCharacter or not root then
		return false
	end
	if not self.world or not item:IsDescendantOf(self.world.Root) then
		return false
	end
	local direction = item.Position - root.Position
	if direction.Magnitude > self.balance.interaction_radius then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	local hit = Workspace:Raycast(root.Position, direction, params)
	return not hit or hit.Instance == item
end

function SoloRound:_openGate(player: Player)
	local world = self.world
	if
		not world
		or self.gateOpen
		or not self:_canInteract(player, world.GateAnchor, world.GatePrompt)
	then
		return
	end
	local _, _, root = self:_livingCharacter()
	if not root or not world:IsGateFront(root.Position) then
		return
	end
	if not self.hasKey then
		self.notice = "corn_loop_need_key"
		self:_send()
		return
	end
	self.hasKey = false
	self.gateOpen = true
	Inventory.Remove(self.inventory, "key")
	self.notice = ""
	world:SetGateOpen(true)
	self:_send()
end

function SoloRound:_ensureWorld(): boolean
	if self.world then
		return self.world:IsValid()
	end
	local ok, result =
		pcall(AuthoredWorld.new, self.balance.interaction_radius, self.balance.key_slot_count)
	if not ok then
		self.context.Log:Warn("Cannot bind editable CornMap:", result)
		return false
	end
	self.world = result
	if self.selectedSpawn and table.find(self.world.Spawns, self.selectedSpawn) then
		self.world.Spawn = self.selectedSpawn
	end
	table.insert(
		self.connections,
		self.world.GatePrompt.Triggered:Connect(function(player: Player)
			self:_openGate(player)
		end)
	)
	return true
end

function SoloRound:_stopHunt()
	if self.hunt then
		self.hunt:Destroy()
		self.hunt = nil
	end
end

function SoloRound:_bindKey(keyPrompt: ProximityPrompt)
	if self.keyConnection then
		self.keyConnection:Disconnect()
	end
	local epoch = self.epoch
	self.keyConnection = keyPrompt.Triggered:Connect(function(player: Player)
		local key = self.world.Key
		if
			self.epoch ~= epoch
			or self.hasKey
			or self.gateOpen
			or not key
			or keyPrompt ~= self.world.KeyPrompt
		then
			return
		end
		if not self:_canInteract(player, key, keyPrompt) then
			return
		end
		if not Inventory.Add(self.inventory, "key") then
			self.notice = "corn_inventory_full"
			self:_send()
			return
		end
		self.hasKey = true
		self.notice = ""
		self:_clearKey()
		self:_send()
	end)
end

function SoloRound:_caught(root: BasePart)
	if self.phase ~= "active" then
		return
	end
	self.minimap:RecordCaught(root.Position)
	self.catches += 1
	self.captureFrame = self.hunt:BeginCapture(root.Position)
	self.captureUntil = os.clock() + self.balance.capture_transition_sec
	self.elapsed = if self.startedAt then os.clock() - self.startedAt else 0
	self.phase = "caught"
	self.inventory.energyUntil = 0
	if self.items then
		self.items:SetEnabled(false)
	end
	local finalCatch = self.catches >= self.balance.max_catches
	self.notice = if finalCatch
		then "corn_hunt_defeat_notice"
		elseif self.hasKey then "corn_hunt_key_dropped"
		else "corn_hunt_first_catch"
	local epoch = self.epoch
	if self.hasKey and not finalCatch then
		self.hasKey = false
		Inventory.Remove(self.inventory, "key")
		local prompt = self.world:DropKey(root.Position, self.balance.key_drop_adjust_radius)
		if not prompt then
			self:_finish("aborted", "corn_hunt_drop_error")
			return
		end
		self:_bindKey(prompt)
	end
	self.world:SetInteractionEnabled(false, self.gateOpen)
	self:_controls(false)
	self:_send()
	task.delay(self.balance.capture_transition_sec, function()
		if self.epoch ~= epoch or self.phase ~= "caught" then
			return
		end
		local character = self:_livingCharacter()
		if not character or character ~= self.roundCharacter then
			self:_finish("aborted", "corn_loop_result_aborted")
			return
		end
		if finalCatch then
			self:_finish("caught_out", "corn_hunt_defeat_notice")
			return
		end
		self.captureUntil = 0
		self:_moveToStart(character)
		self.stamina = Stamina.new(self.balance.stamina_capacity, os.clock())
		self.protectedUntil = os.clock() + self.balance.respawn_protection_sec
		self.hunt:ResetHome()
		self.huntAt = os.clock()
		self.phase = "active"
		if self.items then
			self.items:SetEnabled(true)
		end
		self.world:SetInteractionEnabled(true, self.gateOpen)
		self:_controls(true)
		self:_send()
	end)
end

function SoloRound:_restoreLighting()
	if self.lightingState then
		LightingModes.Restore(Lighting, self.lightingState)
		self.lightingState = nil
	end
end

function SoloRound:_startRound(mode: string)
	if
		self.phase ~= "ready"
		and self.phase ~= "escaped"
		and self.phase ~= "aborted"
		and self.phase ~= "caught_out"
	then
		return
	end
	if not LightingModes.IsValid(mode) then
		return
	end
	self.minimap:ResetHistory()
	self.lightingMode = mode
	if not self.lightingState then
		self.lightingState = LightingModes.Capture(Lighting)
	end
	LightingModes.Apply(Lighting, mode)
	self.epoch += 1
	self.stamina = Stamina.new(self.balance.stamina_capacity, os.clock())
	self:_stopHunt()
	self:_clearInventory()
	self.catches = 0
	self.captureFrame = CFrame.identity
	self.captureUntil = 0
	self.protectedUntil = 0
	local epoch = self.epoch
	self.phase = "preparing"
	self.startedAt = nil
	self.elapsed = 0
	self.reward = 0
	self.notice = ""
	self.hasKey = false
	self.gateOpen = false
	self.roundCharacter = nil
	self:_clearKey()
	self:_controls(false)
	self:_send()
	if not self:_ensureWorld() then
		self:_chooseSpawn()
		local character = self:_livingCharacter()
		if character then
			self:_moveToStart(character)
		end
		self:_finish("aborted", "corn_loop_setup_error")
		return
	end
	self:_chooseSpawn()
	self.world:SetGateOpen(false)
	self.world:SetInteractionEnabled(false, false)

	task.spawn(function()
		local deadline = os.clock() + 10
		local character: Model? = nil
		while
			self.epoch == epoch
			and self.phase == "preparing"
			and self.player
			and self.player.Parent == Players
		do
			character = self:_livingCharacter()
			if character or os.clock() >= deadline then
				break
			end
			task.wait(0.1)
		end
		if self.epoch ~= epoch or self.phase ~= "preparing" then
			return
		end
		if not character then
			self:_finish("aborted", "corn_loop_setup_error")
			return
		end
		if not self.world or not self.world:IsValid() then
			self:_finish("aborted", "corn_loop_setup_error")
			return
		end
		self:_moveToStart(character)
		self.roundCharacter = character
		local slot = self.world.Slots[self.random:NextInteger(1, #self.world.Slots)]
		local keyPrompt = self.world:SpawnKey(slot)
		self:_bindKey(keyPrompt)
		self.items = InventoryWorld.new(self.world, self.random, slot, function(player, entry)
			if
				self.epoch ~= epoch
				or not self.items
				or entry.model.Parent ~= self.items.folder
				or not self:_canInteract(player, entry.anchor, entry.prompt)
			then
				return
			end
			if not Inventory.Add(self.inventory, entry.kind) then
				self.notice = "corn_inventory_full"
				self:_send()
				return
			end
			assert(self.items:Take(entry), "Pickup invalidated during server transaction")
			self.notice = ""
			self:_send()
		end)
		self.startedAt = os.clock()
		local ok, hunt = pcall(MonsterHunt.new, self.world, self.balance, self.startedAt)
		if not ok then
			self.context.Log:Warn("Cannot start hunt:", hunt)
			self:_finish("aborted", "corn_loop_setup_error")
			return
		end
		self.hunt = hunt
		self.huntAt = self.startedAt
		self.phase = "active"
		self.world:SetInteractionEnabled(true, false)
		self:_controls(true)
		self:_send()
		self.context.Log:Info("Solo round started")
	end)
end

function SoloRound:_menu()
	if self.phase ~= "escaped" and self.phase ~= "aborted" and self.phase ~= "caught_out" then
		return
	end
	self.epoch += 1
	self.phase = "ready"
	self:_restoreLighting()
	self.reward = 0
	self.elapsed = 0
	self.startedAt = nil
	self.notice = ""
	self.hasKey = false
	self.gateOpen = false
	self:_clearKey()
	self:_clearInventory()
	if self.world then
		self.world:SetGateOpen(false)
		self.world:SetInteractionEnabled(false, false)
	end
	local character = self:_livingCharacter()
	if character then
		self:_moveToStart(character)
	end
	self:_controls(false)
	self:_send()
end

function SoloRound:_request(player: Player, action: any, mode: any)
	if player ~= self.player then
		return
	end
	local now = os.clock()
	self.requestTokens = math.min(2, self.requestTokens + (now - self.requestAt) * 2)
	self.requestAt = now
	if self.requestTokens < 1 then
		return
	end
	self.requestTokens -= 1
	if type(action) ~= "string" then
		return
	end
	if action == "sync" then
		self:_send()
	elseif
		(action == "start" and self.phase == "ready")
		or (
			action == "retry"
			and (self.phase == "escaped" or self.phase == "aborted" or self.phase == "caught_out")
		)
	then
		if LightingModes.IsValid(mode) then
			self:_startRound(mode)
		end
	elseif action == "abort" then
		self:_finish("aborted", "corn_loop_result_aborted")
	elseif action == "menu" then
		self:_menu()
	end
end

function SoloRound:_bindCharacter(character: Model)
	if character == self.boundCharacter then
		return
	end
	self.boundCharacter = character
	if self.deathConnection then
		self.deathConnection:Disconnect()
		self.deathConnection = nil
	end
	if
		self.phase == "active"
		or self.phase == "caught"
		or (self.phase == "preparing" and self.roundCharacter ~= nil)
	then
		self:_recordCharacterDeath(self.roundCharacter)
		self:_finish("aborted", "corn_loop_result_aborted")
	end
	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 10)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		local player = self.player
		if not player or player.Character ~= character or self.boundCharacter ~= character then
			return
		end
		if not humanoid or not humanoid:IsA("Humanoid") or not root or not root:IsA("BasePart") then
			self:_finish("aborted", "corn_loop_setup_error")
			return
		end
		self.deathConnection = humanoid.Died:Connect(function()
			if self.player and self.player.Character == character then
				self:_recordCharacterDeath(character)
				self:_finish("aborted", "corn_loop_result_aborted")
			end
		end)
		if self.phase ~= "active" and self.phase ~= "preparing" then
			self:_moveToStart(character)
		end
		self:_controls(self.phase == "active" and self.roundCharacter == character)
		self:_send()
	end)
end

function SoloRound:_addPlayer(player: Player)
	if self.player then
		return -- One owner, no multiplayer matchmaking in this prototype.
	end
	self.player = player
	self:_setRespawnLocation()
	self.requestTokens = 2
	self.requestAt = os.clock()
	self.characterConnection = player.CharacterAdded:Connect(function(character: Model)
		self:_bindCharacter(character)
	end)
	self.characterRemovingConnection = player.CharacterRemoving:Connect(function(character: Model)
		if
			player == self.player
			and (character == self.boundCharacter or character == player.Character)
		then
			self:_recordCharacterDeath(character)
			self:_finish("aborted", "corn_loop_result_aborted")
		end
	end)
	if player.Character then
		self:_bindCharacter(player.Character)
	end
	self:_send()
end

function SoloRound:_removePlayer(player: Player)
	if player ~= self.player then
		return
	end
	self.epoch += 1
	self:_clearKey()
	self:_clearInventory()
	if self.characterConnection then
		self.characterConnection:Disconnect()
		self.characterConnection = nil
	end
	if self.deathConnection then
		self.deathConnection:Disconnect()
		self.deathConnection = nil
	end
	if self.characterRemovingConnection then
		self.characterRemovingConnection:Disconnect()
		self.characterRemovingConnection = nil
	end
	self.player = nil
	self.minimap:ClearHistory()
	self:_restoreLighting()
	self.lightingMode = LightingModes.Default
	self:_stopHunt()
	self.catches = 0
	self.captureUntil = 0
	self.captureFrame = CFrame.identity
	self.protectedUntil = 0
	self.stamina = Stamina.new(self.balance.stamina_capacity, os.clock())
	self.phase = "ready"
	self.hasKey = false
	self.gateOpen = false
	self.diamonds = 0
	self.reward = 0
	self.startedAt = nil
	self.elapsed = 0
	self.notice = ""
	self.roundCharacter = nil
	self.boundCharacter = nil
	self.controlledCharacter = nil
	if self.world then
		self.world:SetGateOpen(false)
		self.world:SetInteractionEnabled(false, false)
	end
end

function SoloRound:_poll(now: number)
	if self.phase ~= "active" then
		return
	end
	local character, _, root = self:_livingCharacter()
	if not character or character ~= self.roundCharacter or not root then
		local roundCharacter = self.roundCharacter
		local humanoid = if roundCharacter
			then roundCharacter:FindFirstChildOfClass("Humanoid")
			else nil
		if humanoid and humanoid.Health <= 0 then
			self:_recordCharacterDeath(roundCharacter)
		end
		self:_finish("aborted", "corn_loop_result_aborted")
		return
	end
	if
		not self.world
		or not self.world:IsValid()
		or not self.world:IsOnPlayground(root.Position)
	then
		self:_finish("aborted", "corn_loop_setup_error")
		return
	end
	-- A visit and capture in the same tick both belong to this pre-teleport position.
	self.minimap:Poll(self.world, root.Position)
	if self.hunt then
		local previous = self.hunt:GetPosition()
		if self.items then
			self.items:CheckTraps(self.hunt, previous, now)
		end
		local caught, awakened =
			self.hunt:Step(now - self.huntAt, now, root, now < self.protectedUntil)
		self.huntAt = now
		if self.items and self.items:CheckTraps(self.hunt, previous, now) then
			caught = false
		end
		if awakened then
			self.notice = "corn_hunt_awakened"
		end
		if caught then
			self:_caught(root)
			return
		end
	end
	if self.gateOpen and self.world:IsInExit(root.Position) then
		self:_finish("escaped", "")
		return
	end
	if now - self.snapshotAt >= 0.25 then
		self.snapshotAt = now
		self:_send()
	end
end

function SoloRound:_sprintRequest(player: Player, value: any)
	if player ~= self.player then
		return
	end
	local character = self:_livingCharacter()
	Stamina.Request(
		self.stamina,
		value,
		os.clock(),
		self.phase == "active" and character ~= nil and character == self.roundCharacter
	)
end

function SoloRound:_movement(dt: number)
	local character, humanoid, root = self:_livingCharacter()
	local active = self.phase == "active" and character ~= nil and character == self.roundCharacter
	local velocity = if root then root.AssemblyLinearVelocity else Vector3.zero
	local moving = Vector3.new(velocity.X, 0, velocity.Z).Magnitude > 0.5
	Stamina.Step(self.stamina, dt, moving, active, self.balance)
	if humanoid then
		humanoid.WalkSpeed = if not active
			then 0
			elseif self.stamina.sprinting then self.balance.sprint_speed * Inventory.Multiplier(
				self.inventory,
				os.clock()
			)
			else self.balance.walk_speed * Inventory.Multiplier(self.inventory, os.clock())
		humanoid:SetAttribute(
			"corn_energy_remaining",
			Inventory.Snapshot(self.inventory, os.clock()).energy_remaining
		)
		humanoid:SetAttribute("corn_stamina", self.stamina.value)
		humanoid:SetAttribute("corn_sprinting", self.stamina.sprinting)
		humanoid:SetAttribute("corn_sprint_exhausted", self.stamina.exhausted)
	end
end

function SoloRound:Start()
	self:_ensureWorld()
	self:_chooseSpawn()
	table.insert(
		self.connections,
		self.inventoryAction.OnServerEvent:Connect(function(player: Player, action: any, slot: any)
			self:_inventoryRequest(player, action, slot)
		end)
	)
	table.insert(
		self.connections,
		self.sprintIntent.OnServerEvent:Connect(function(player: Player, value: any)
			self:_sprintRequest(player, value)
		end)
	)
	table.insert(
		self.connections,
		self.action.OnServerEvent:Connect(function(player: Player, action: any, mode: any)
			self:_request(player, action, mode)
		end)
	)
	table.insert(
		self.connections,
		Players.PlayerAdded:Connect(function(player: Player)
			self:_addPlayer(player)
		end)
	)
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player: Player)
			self:_removePlayer(player)
		end)
	)
	table.insert(
		self.connections,
		RunService.Heartbeat:Connect(function(dt: number)
			self:_movement(dt)
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

return SoloRound
