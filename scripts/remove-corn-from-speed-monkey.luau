-- Run only in the EDIT-mode Command Bar of New_+1 speed monkey.
-- Checks every Corn source and object before removing any container.
local RunService = game:GetService("RunService")
assert(not RunService:IsRunning(), "Stop the play test first")
local workspace = game:GetService("Workspace")
local speedServer = game:GetService("ServerScriptService"):FindFirstChild("Server")
local progression = speedServer and speedServer:FindFirstChild("Progression")
local parameters = progression and progression:FindFirstChild("ProgressionParameters")
assert(workspace:FindFirstChild("Asmr_Base") and workspace:FindFirstChild("ASMR_Models")
    and parameters and parameters:IsA("ModuleScript")
    and string.find(parameters.Source, "Defines and validates SPEED progression", 1, true),
    "This is not the verified Speed Monkey scene; nothing removed")
local expected = {
{ path = { "ReplicatedStorage", "GameShared" }, nodes = {
{ path = "", class = "Folder" },
{ path = "Config", class = "Folder" },
{ path = "Config/GameConfig", class = "ModuleScript", source = [========[--!strict

local Balance = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("Balance"))

return {
	Environment = "DEV",
	Debug = true,
	Game = {
		Id = "children_of_corn",
		Name = "Дети кукурузы",
		Version = "0.1.0",
		SessionMode = "solo_local",
		SupportedDevice = "pc",
	},
	CoreLoop = Balance,
	Persistence = {
		Enabled = false,
		StoreName = "PlayerData_v1",
		SchemaVersion = 1,
	},
}
]========] },
{ path = "Core", class = "Folder" },
{ path = "Core/Logger", class = "ModuleScript", source = [========[--!strict

local Logger = {}
Logger.__index = Logger

function Logger.new(scope: string, debugEnabled: boolean?)
	return setmetatable({
		_scope = scope,
		_debug = debugEnabled == true,
	}, Logger)
end

function Logger:Info(...: any)
	print(string.format("[%s]", self._scope), ...)
end

function Logger:Warn(...: any)
	warn(string.format("[%s]", self._scope), ...)
end

function Logger:Debug(...: any)
	if self._debug then
		print(string.format("[%s][DEBUG]", self._scope), ...)
	end
end

return Logger
]========] },
{ path = "Game", class = "Folder" },
{ path = "Game/Balance", class = "ModuleScript", source = [========[--!strict

-- Baseline from docs/2026-10-09_core-loop_gd-spec.md, sections 11-12.
-- Map dimensions and visibility heights remain undefined until a Studio playtest.
return {
	target_round_min_sec = 420,
	target_round_max_sec = 600,
	hunt_start_delay_sec = 15,
	key_slot_count = 15,
	barrel_count = 3,
	max_catches = 2,
	stamina_capacity = 100,
	sprint_duration_sec = 4,
	stamina_refill_sec = 6,
	walk_speed = 12,
	sprint_speed = 18,
	monster_patrol_speed = 10,
	monster_chase_speed = 14,
	monster_detect_radius = 32,
	monster_lose_radius = 44,
	monster_lose_delay_sec = 1.5,
	monster_growl_radius = 72,
	monster_capture_radius = 3,
	capture_transition_sec = 1,
	respawn_protection_sec = 5,
	key_drop_adjust_radius = 6,
	interaction_radius = 4,
	escape_reward_diamonds = 10,
}
]========] },
{ path = "Game/RoundText", class = "ModuleScript", source = [========[--!strict

-- Keep player-facing strings in the GD namespace; this slice has no hunt/stamina UI.
return table.freeze({
	corn_loop_title = "Дети кукурузы",
	corn_loop_start = "Начать",
	corn_loop_loading = "Подготовка раунда…",
	corn_loop_objective_search = "Найди ключ от ворот и сбеги",
	corn_loop_objective_return = "Ключ найден. Вернись к воротам",
	corn_loop_objective_exit = "Ворота открыты — беги наружу",
	corn_loop_need_key = "Нужен ключ",
	corn_loop_result_escape = "Ты сбежал",
	corn_loop_result_aborted = "Раунд завершён",
	corn_loop_reward = "+{count} алмазов",
	corn_loop_test_balance = "Алмазы в этом тесте: {count}",
	corn_loop_round_time = "Время раунда: {time}",
	corn_loop_retry = "Ещё раз",
	corn_loop_menu = "В меню",
	corn_loop_leave = "Завершить раунд",
	corn_loop_setup_error = "Не удалось подготовить раунд. Попробуй снова",
	corn_loop_connection_error = "Не удалось подключить интерфейс. Перезапусти тест Studio",
})
]========] },
{ path = "Network", class = "Folder" },
{ path = "Network/EndpointNames", class = "ModuleScript", source = [========[--!strict

return {
	RequestRoundAction = "request_round_action",
	RoundSnapshot = "round_snapshot",
}
]========] }
} },
{ path = { "ServerScriptService", "GameServer" }, nodes = {
{ path = "", class = "Folder" },
{ path = "Bootstrap", class = "Script", source = [========[--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameShared = ReplicatedStorage:WaitForChild("GameShared")
local Config = require(GameShared:WaitForChild("Config"):WaitForChild("GameConfig"))
local Logger = require(GameShared:WaitForChild("Core"):WaitForChild("Logger"))
local log = Logger.new("ServerBootstrap", Config.Debug)

local servicesFolder = script.Parent:WaitForChild("Services")

type RuntimeModule = {
	Name: string?,
	Order: number?,
	Init: ((self: RuntimeModule, context: any) -> ())?,
	Start: ((self: RuntimeModule, context: any) -> ())?,
}

local loaded: { RuntimeModule } = {}
local byName: { [string]: RuntimeModule } = {}

for _, child in servicesFolder:GetChildren() do
	if child:IsA("ModuleScript") then
		local ok, result = pcall(require, child)
		if not ok then
			error(
				string.format(
					"Failed to require service %s: %s",
					child:GetFullName(),
					tostring(result)
				)
			)
		end
		if type(result) ~= "table" then
			error(string.format("Service %s must return a table", child:GetFullName()))
		end
		local module = result :: RuntimeModule
		local name = module.Name or child.Name
		if byName[name] then
			error(string.format("Duplicate service name: %s", name))
		end
		module.Name = name
		byName[name] = module
		table.insert(loaded, module)
	end
end

table.sort(loaded, function(a, b)
	return (a.Order or 100) < (b.Order or 100)
end)

local context = {
	Config = Config,
	Services = byName,
	Log = Logger.new("Server", Config.Debug),
}

for _, module in loaded do
	if module.Init then
		module:Init(context)
	end
end

for _, module in loaded do
	if module.Start then
		module:Start(context)
	end
end

log:Info(string.format("Started %d services", #loaded))
]========] },
{ path = "Game", class = "Folder" },
{ path = "Game/CornField", class = "ModuleScript", source = [========[--!strict

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")

local CornField = {}

-- Technical preview values only; final map geometry remains a playtest decision.
local HEIGHT = 8
local SPACING = 4.5
local CLEARING_RADIUS = 3

local function isClearing(position: Vector3, slots: { BasePart }): boolean
	for _, slot in slots do
		local delta = position - slot.Position
		if Vector2.new(delta.X, delta.Z).Magnitude <= CLEARING_RADIUS then
			return true
		end
	end
	return false
end

function CornField.Build(parent: Model, slots: { BasePart }, floorY: number): (boolean, number)
	local template = ServerStorage:FindFirstChild("CornPlantTemplate")
	if not template or (not template:IsA("Model") and not template:IsA("BasePart")) then
		warn(
			"[CornField] Import assets/corn/*_textured.fbx as ServerStorage/CornPlantTemplate; route test will run without corn"
		)
		return false, 0
	end
	for _, item in template:GetDescendants() do
		if item:IsA("LuaSourceContainer") then
			warn("[CornField] CornPlantTemplate must contain only art, not scripts")
			return false, 0
		end
	end
	local prepared = template:Clone()
	if not prepared then
		warn("[CornField] CornPlantTemplate is not Archivable")
		return false, 0
	end
	local initialSize = if prepared:IsA("Model")
		then select(2, prepared:GetBoundingBox())
		else (prepared :: BasePart).Size
	if initialSize.Y <= 0 then
		prepared:Destroy()
		warn("[CornField] CornPlantTemplate has no usable height")
		return false, 0
	end
	if prepared:IsA("Model") then
		prepared:ScaleTo(prepared:GetScale() * HEIGHT / initialSize.Y)
	else
		(prepared :: BasePart).Size *= HEIGHT / initialSize.Y
	end
	local allParts: { Instance } = prepared:GetDescendants()
	table.insert(allParts, prepared)
	for _, item in allParts do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = false
			item.CastShadow = false
		end
	end

	local plants = Instance.new("Folder")
	plants.Name = "CornPlants"
	plants.Parent = parent
	local random = Random.new(817)
	local count = 0
	for row = -10, 10 do
		for column = -12, 12 do
			local position = Vector3.new(column * SPACING, floorY, row * SPACING)
			if not isClearing(position, slots) then
				local clone = prepared:Clone()
				assert(clone, "Prepared corn clone is not Archivable")
				clone.Name = "Corn"
				local bounds, size: Vector3
				if clone:IsA("Model") then
					bounds, size = clone:GetBoundingBox()
				else
					local mesh = clone :: BasePart
					bounds, size = mesh.CFrame, mesh.Size
				end
				local pivotOffset = clone:GetPivot():ToObjectSpace(bounds)
				local target = CFrame.new(position + Vector3.new(0, size.Y / 2, 0))
					* CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
				clone:PivotTo(target * pivotOffset:Inverse())
				clone.Parent = plants
				count += 1
			end
		end
	end
	prepared:Destroy()

	local zone = Instance.new("Part")
	zone.Name = "CornFieldZone"
	zone.Size = Vector3.new(114, HEIGHT + 2, 96)
	zone.Position = Vector3.new(0, floorY + (HEIGHT + 2) / 2, 0)
	zone.Anchored = true
	zone.Transparency = 1
	zone.CanCollide = false
	zone.CanTouch = false
	zone.CanQuery = false
	zone.Parent = parent
	CollectionService:AddTag(zone, "corn_field_zone")
	return true, count
end

return CornField
]========] },
{ path = "Game/GreyboxWorld", class = "ModuleScript", source = [========[--!strict

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local CornField = require(script.Parent:WaitForChild("CornField"))

local GreyboxWorld = {}
GreyboxWorld.__index = GreyboxWorld

local FLOOR_Y = 80

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3
): Part
	local item = Instance.new("Part")
	item.Name = name
	item.Anchored = true
	item.Size = size
	item.Position = position
	item.Color = color
	item.TopSurface = Enum.SurfaceType.Smooth
	item.BottomSurface = Enum.SurfaceType.Smooth
	item.Parent = parent
	return item
end

local function prompt(
	parent: Instance,
	actionText: string,
	objectText: string,
	radius: number
): ProximityPrompt
	local item = Instance.new("ProximityPrompt")
	item.ActionText = actionText
	item.ObjectText = objectText
	item.KeyboardKeyCode = Enum.KeyCode.E
	item.MaxActivationDistance = radius
	item.RequiresLineOfSight = true
	item.HoldDuration = 0
	item.Enabled = false
	item.Parent = parent
	return item
end

function GreyboxWorld.new(radius: number, expectedSlots: number)
	-- Never adopt or destroy another model, even if it has the same name.
	assert(
		not Workspace:FindFirstChild("CornPrototypeRuntime"),
		"CornPrototypeRuntime already exists"
	)
	assert(expectedSlots == 15, "This temporary layout has exactly 15 slots")

	local root = Instance.new("Model")
	root.Name = "CornPrototypeRuntime"
	root:SetAttribute("RuntimePrototype", true)

	local self = setmetatable({
		Root = root,
		Radius = radius,
		Slots = {} :: { BasePart },
		Key = nil :: Part?,
		KeyPrompt = nil :: ProximityPrompt?,
	}, GreyboxWorld)

	local wallColor = Color3.fromRGB(51, 61, 52)
	part(
		root,
		"Ground",
		Vector3.new(160, 2, 160),
		Vector3.new(0, FLOOR_Y - 1, 0),
		Color3.fromRGB(91, 97, 70)
	)
	part(
		root,
		"WestBoundary",
		Vector3.new(2, 20, 122),
		Vector3.new(-60, FLOOR_Y + 10, 0),
		wallColor
	)
	part(root, "EastBoundary", Vector3.new(2, 20, 122), Vector3.new(60, FLOOR_Y + 10, 0), wallColor)
	part(
		root,
		"StartBoundary",
		Vector3.new(122, 20, 2),
		Vector3.new(0, FLOOR_Y + 10, -60),
		wallColor
	)
	part(
		root,
		"ExitBoundaryLeft",
		Vector3.new(54, 20, 2),
		Vector3.new(-33, FLOOR_Y + 10, 60),
		wallColor
	)
	part(
		root,
		"ExitBoundaryRight",
		Vector3.new(54, 20, 2),
		Vector3.new(33, FLOOR_Y + 10, 60),
		wallColor
	)
	part(root, "GateHeader", Vector3.new(12, 2, 2), Vector3.new(0, FLOOR_Y + 19, 60), wallColor)

	local spawn = part(
		root,
		"RoundSpawn",
		Vector3.new(6, 0.15, 6),
		Vector3.new(0, FLOOR_Y + 0.075, -50),
		Color3.fromRGB(158, 176, 150)
	)
	self.Spawn = spawn
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn:SetAttribute("spawn_id", "prototype_start")
	CollectionService:AddTag(spawn, "corn_spawn")
	self.SpawnCFrame =
		CFrame.lookAt(Vector3.new(0, FLOOR_Y + 3.5, -50), Vector3.new(0, FLOOR_Y + 3.5, 0))

	for row = 1, 5 do
		for column = 1, 3 do
			local slotId = string.format("prototype_slot_%02d", #self.Slots + 1)
			local slot = part(
				root,
				slotId,
				Vector3.new(6, 0.12, 6),
				Vector3.new((column - 2) * 36, FLOOR_Y + 0.06, (row - 3) * 18),
				Color3.fromRGB(119, 123, 87)
			)
			slot.CanCollide = false
			slot.CanQuery = false
			slot:SetAttribute("slot_id", slotId)
			CollectionService:AddTag(slot, "corn_key_slot")
			table.insert(self.Slots, slot)
		end
	end

	for _, index in { 3, 8, 13 } do
		local slot = self.Slots[index]
		local barrel = part(
			root,
			"LookoutBarrel",
			Vector3.new(4, 3.2, 3.2),
			Vector3.new(slot.Position.X + 3.5, FLOOR_Y + 2, slot.Position.Z),
			Color3.fromRGB(111, 78, 48)
		)
		barrel.Shape = Enum.PartType.Cylinder
		barrel.Material = Enum.Material.Wood
		barrel.CFrame *= CFrame.Angles(0, 0, math.pi / 2)
		CollectionService:AddTag(barrel, "corn_barrel")
	end
	local gateModel = Instance.new("Model")
	gateModel.Name = "EscapeGate"
	gateModel:SetAttribute("gate_id", "prototype_gate")
	gateModel.Parent = root
	CollectionService:AddTag(gateModel, "corn_gate")
	self.Gate = part(
		gateModel,
		"Door",
		Vector3.new(12, 18, 2),
		Vector3.new(0, FLOOR_Y + 9, 60),
		Color3.fromRGB(114, 75, 49)
	)
	self.Gate.CanTouch = false
	self.GateAnchor = part(
		gateModel,
		"InteractionAnchor",
		Vector3.new(0.1, 0.1, 0.1),
		Vector3.new(0, FLOOR_Y + 3, 58.7),
		Color3.new(1, 1, 1)
	)
	self.GateAnchor.Transparency = 1
	self.GateAnchor.CanCollide = false
	self.GateAnchor.CanTouch = false
	self.GateAnchor.CanQuery = false
	self.GatePrompt = prompt(self.GateAnchor, "Открыть", "Ворота", radius)

	self.Exit = part(
		root,
		"ExitZone",
		Vector3.new(12, 22, 8),
		Vector3.new(0, FLOOR_Y + 11, 68),
		Color3.fromRGB(133, 189, 141)
	)
	self.Exit.Transparency = 0.8
	self.Exit.CanCollide = false
	self.Exit.CanTouch = false
	self.Exit.CanQuery = false
	self.Exit:SetAttribute("gate_id", "prototype_gate")
	CollectionService:AddTag(self.Exit, "corn_exit")
	assert(#self.Slots == expectedSlots, "Key slot count mismatch")
	root.Parent = Workspace
	local cornReady, cornCount = CornField.Build(root, self.Slots, FLOOR_Y)
	root:SetAttribute("CornReady", cornReady)
	root:SetAttribute("CornCount", cornCount)
	return self
end

function GreyboxWorld:ClearKey()
	if self.Key then
		self.Key:Destroy()
	end
	self.Key = nil
	self.KeyPrompt = nil
end

function GreyboxWorld:SpawnKey(slot: BasePart): ProximityPrompt
	assert(slot:IsDescendantOf(self.Root), "Key slot must belong to runtime world")
	self:ClearKey()
	local key = part(
		self.Root,
		"GateKey",
		Vector3.new(1.5, 0.4, 3),
		slot.Position + Vector3.new(0, 0.45, 0),
		Color3.fromRGB(240, 198, 69)
	)
	key.Material = Enum.Material.Metal
	key.CanCollide = false
	key.CanTouch = false
	self.Key = key
	self.KeyPrompt = prompt(key, "Подобрать", "Ключ от ворот", self.Radius)
	return self.KeyPrompt
end

function GreyboxWorld:SetGateOpen(open: boolean)
	self.Gate.CanCollide = not open
	self.Gate.CanQuery = not open
	self.Gate.Transparency = if open then 1 else 0
	self.GatePrompt.Enabled = false
	self.Root:SetAttribute("GateOpen", open)
end

function GreyboxWorld:SetInteractionEnabled(enabled: boolean, gateOpen: boolean)
	self.GatePrompt.Enabled = enabled and not gateOpen
	if self.KeyPrompt then
		self.KeyPrompt.Enabled = enabled
	end
end

function GreyboxWorld:IsGateFront(position: Vector3): boolean
	return position.Z < self.Gate.Position.Z - self.Gate.Size.Z / 2
end

function GreyboxWorld:IsInExit(position: Vector3): boolean
	local point = self.Exit.CFrame:PointToObjectSpace(position)
	local halfSize = self.Exit.Size / 2
	return math.abs(point.X) <= halfSize.X
		and math.abs(point.Y) <= halfSize.Y
		and math.abs(point.Z) <= halfSize.Z
end

function GreyboxWorld:IsOnPlayground(position: Vector3): boolean
	return math.abs(position.X) <= 59
		and position.Z >= -59
		and position.Z <= 73
		and position.Y > FLOOR_Y - 3
		and position.Y < FLOOR_Y + 22
end

function GreyboxWorld:IsValid(): boolean
	if
		self.Root.Parent ~= Workspace
		or not self.Spawn:IsDescendantOf(self.Root)
		or not self.Gate:IsDescendantOf(self.Root)
		or not self.GateAnchor:IsDescendantOf(self.Root)
		or not self.GatePrompt:IsDescendantOf(self.GateAnchor)
		or not self.Exit:IsDescendantOf(self.Root)
		or #self.Slots ~= 15
	then
		return false
	end
	for _, slot in self.Slots do
		if not slot:IsDescendantOf(self.Root) then
			return false
		end
	end
	return true
end
function GreyboxWorld:Destroy()
	self.Root:Destroy()
end

return GreyboxWorld
]========] },
{ path = "Game/SoloRound", class = "ModuleScript", source = [========[--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameShared = ReplicatedStorage:WaitForChild("GameShared")
local Endpoints = require(GameShared:WaitForChild("Network"):WaitForChild("EndpointNames"))
local GreyboxWorld = require(script.Parent:WaitForChild("GreyboxWorld"))

local SoloRound = {}
SoloRound.__index = SoloRound

function SoloRound.new(context: any)
	return setmetatable({
		context = context,
		balance = context.Config.CoreLoop,
		action = context.Services.NetworkService:GetEvent(Endpoints.RequestRoundAction),
		snapshot = context.Services.NetworkService:GetEvent(Endpoints.RoundSnapshot),
		world = nil :: any,
		player = nil :: Player?,
		phase = "ready",
		epoch = 0,
		hasKey = false,
		gateOpen = false,
		diamonds = 0,
		reward = 0,
		startedAt = nil :: number?,
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
	self.snapshot:FireClient(player, {
		phase = self.phase,
		has_key = self.hasKey,
		gate_open = self.gateOpen,
		session_diamonds = self.diamonds,
		reward_diamonds = self.reward,
		elapsed_sec = if self.phase == "active" and self.startedAt
			then os.clock() - self.startedAt
			else self.elapsed,
		notice = self.notice,
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

function SoloRound:_controls(enabled: boolean)
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

function SoloRound:_moveToStart(character: Model)
	if not self.world then
		return
	end
	character:PivotTo(self.world.SpawnCFrame)
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

function SoloRound:_finish(phase: string, notice: string)
	if self.phase ~= "active" and self.phase ~= "preparing" then
		return
	end
	-- Fix the terminal state before rewarding or notifying any client.
	self.elapsed = if self.startedAt then os.clock() - self.startedAt else 0
	self.phase = phase
	self.epoch += 1
	self.notice = notice
	self.reward = if phase == "escaped" then self.balance.escape_reward_diamonds else 0
	self.diamonds += self.reward
	self.hasKey = false
	self:_clearKey()
	if self.world then
		self.world:SetInteractionEnabled(false, self.gateOpen)
	end
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
	self.notice = ""
	world:SetGateOpen(true)
	self:_send()
end

function SoloRound:_ensureWorld(): boolean
	if self.world then
		return self.world:IsValid()
	end
	local ok, result =
		pcall(GreyboxWorld.new, self.balance.interaction_radius, self.balance.key_slot_count)
	if not ok then
		self.context.Log:Warn("Cannot prepare prototype world:", result)
		return false
	end
	self.world = result
	table.insert(
		self.connections,
		self.world.GatePrompt.Triggered:Connect(function(player: Player)
			self:_openGate(player)
		end)
	)
	return true
end

function SoloRound:_startRound()
	if self.phase ~= "ready" and self.phase ~= "escaped" and self.phase ~= "aborted" then
		return
	end
	self.epoch += 1
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
		self:_finish("aborted", "corn_loop_setup_error")
		return
	end
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
			self.hasKey = true
			self.notice = ""
			self:_clearKey()
			self:_send()
		end)
		self.startedAt = os.clock()
		self.phase = "active"
		self.world:SetInteractionEnabled(true, false)
		self:_controls(true)
		self:_send()
		self.context.Log:Info("Solo round started")
	end)
end

function SoloRound:_menu()
	if self.phase ~= "escaped" and self.phase ~= "aborted" then
		return
	end
	self.epoch += 1
	self.phase = "ready"
	self.reward = 0
	self.elapsed = 0
	self.startedAt = nil
	self.notice = ""
	self.hasKey = false
	self.gateOpen = false
	self:_clearKey()
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

function SoloRound:_request(player: Player, action: any)
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
		or (action == "retry" and (self.phase == "escaped" or self.phase == "aborted"))
	then
		self:_startRound()
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
	if self.phase == "active" or (self.phase == "preparing" and self.roundCharacter ~= nil) then
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
	if self.gateOpen and self.world:IsInExit(root.Position) then
		self:_finish("escaped", "")
		return
	end
	if now - self.snapshotAt >= 1 then
		self.snapshotAt = now
		self:_send()
	end
end

function SoloRound:Start()
	self:_ensureWorld()
	table.insert(
		self.connections,
		self.action.OnServerEvent:Connect(function(player: Player, action: any)
			self:_request(player, action)
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
		RunService.Heartbeat:Connect(function()
			local now = os.clock()
			if now - self.pollAt >= 0.1 then
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
]========] },
{ path = "Services", class = "Folder" },
{ path = "Services/NetworkService", class = "ModuleScript", source = [========[--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkService = {
	Name = "NetworkService",
	Order = 10,
}

local root: Folder

function NetworkService:Init(_context: any)
	local existing = ReplicatedStorage:FindFirstChild("GameRemotes")
	if existing and not existing:IsA("Folder") then
		error("ReplicatedStorage.GameRemotes exists but is not a Folder")
	end
	if existing then
		root = existing
	else
		root = Instance.new("Folder")
		root.Name = "GameRemotes"
		root.Parent = ReplicatedStorage
	end
end

function NetworkService:GetEvent(name: string): RemoteEvent
	local existing = root:FindFirstChild(name)
	if existing then
		assert(existing:IsA("RemoteEvent"), string.format("%s is not a RemoteEvent", name))
		return existing
	end
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = root
	return event
end

function NetworkService:GetFunction(name: string): RemoteFunction
	local existing = root:FindFirstChild(name)
	if existing then
		assert(existing:IsA("RemoteFunction"), string.format("%s is not a RemoteFunction", name))
		return existing
	end
	local fn = Instance.new("RemoteFunction")
	fn.Name = name
	fn.Parent = root
	return fn
end

return NetworkService
]========] },
{ path = "Services/RoundService", class = "ModuleScript", source = [========[--!strict

local RunService = game:GetService("RunService")
local SoloRound = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("SoloRound"))

local RoundService = { Name = "RoundService", Order = 30 }
local runtime: any = nil

function RoundService:Init(context: any)
	if
		not RunService:IsStudio()
		or context.Config.Environment ~= "DEV"
		or context.Config.Game.SessionMode ~= "solo_local"
	then
		context.Log:Warn("Temporary solo prototype is available only in Studio DEV mode")
		return
	end
	runtime = SoloRound.new(context)
end

function RoundService:Start()
	if runtime then
		runtime:Start()
	end
end

return RoundService
]========] },
{ path = "Services/TagService", class = "ModuleScript", source = [========[--!strict

local CollectionService = game:GetService("CollectionService")

local TagService = {
	Name = "TagService",
	Order = 20,
}

local connections: { RBXScriptConnection } = {}

function TagService:Bind(tag: string, onAdded: (Instance) -> (), onRemoved: ((Instance) -> ())?)
	for _, instance in CollectionService:GetTagged(tag) do
		task.spawn(onAdded, instance)
	end

	table.insert(connections, CollectionService:GetInstanceAddedSignal(tag):Connect(onAdded))
	if onRemoved then
		table.insert(
			connections,
			CollectionService:GetInstanceRemovedSignal(tag):Connect(onRemoved)
		)
	end
end

function TagService:Destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

return TagService
]========] }
} },
{ path = { "StarterPlayer", "StarterPlayerScripts", "GameClient" }, nodes = {
{ path = "", class = "Folder" },
{ path = "Bootstrap", class = "LocalScript", source = [========[--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameShared = ReplicatedStorage:WaitForChild("GameShared")
local Config = require(GameShared:WaitForChild("Config"):WaitForChild("GameConfig"))
local Logger = require(GameShared:WaitForChild("Core"):WaitForChild("Logger"))
local log = Logger.new("ClientBootstrap", Config.Debug)

local controllersFolder = script.Parent:WaitForChild("Controllers")

type RuntimeModule = {
	Name: string?,
	Order: number?,
	Init: ((self: RuntimeModule, context: any) -> ())?,
	Start: ((self: RuntimeModule, context: any) -> ())?,
}

local loaded: { RuntimeModule } = {}
local byName: { [string]: RuntimeModule } = {}

for _, child in controllersFolder:GetChildren() do
	if child:IsA("ModuleScript") then
		local ok, result = pcall(require, child)
		if not ok then
			error(
				string.format(
					"Failed to require controller %s: %s",
					child:GetFullName(),
					tostring(result)
				)
			)
		end
		if type(result) ~= "table" then
			error(string.format("Controller %s must return a table", child:GetFullName()))
		end
		local module = result :: RuntimeModule
		local name = module.Name or child.Name
		if byName[name] then
			error(string.format("Duplicate controller name: %s", name))
		end
		module.Name = name
		byName[name] = module
		table.insert(loaded, module)
	end
end

table.sort(loaded, function(a, b)
	return (a.Order or 100) < (b.Order or 100)
end)

local context = {
	Config = Config,
	Controllers = byName,
	Log = Logger.new("Client", Config.Debug),
}

for _, module in loaded do
	if module.Init then
		module:Init(context)
	end
end

for _, module in loaded do
	if module.Start then
		module:Start(context)
	end
end

log:Info(string.format("Started %d controllers", #loaded))
]========] },
{ path = "Controllers", class = "Folder" },
{ path = "Controllers/RoundController", class = "ModuleScript", source = [========[--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameShared = ReplicatedStorage:WaitForChild("GameShared")
local EndpointNames = require(GameShared:WaitForChild("Network"):WaitForChild("EndpointNames"))
local RoundHud = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("RoundHud"))

type Snapshot = RoundHud.Snapshot

local RoundController = {
	Name = "RoundController",
	Order = 100,
	_snapshot = nil :: Snapshot?,
	_requestRemote = nil :: RemoteEvent?,
	_snapshotConnection = nil :: RBXScriptConnection?,
	_lastRequest = -math.huge,
	_hud = nil :: any,
}

local PHASES: { [string]: boolean } = {
	ready = true,
	preparing = true,
	active = true,
	escaped = true,
	aborted = true,
}
local ACTIONS: { [string]: boolean } = {
	start = true,
	retry = true,
	abort = true,
	menu = true,
}
local DEBOUNCE_SEC = 0.55
local REMOTE_WAIT_SEC = 10

local function nonnegativeNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value >= 0 and value < math.huge
end

local function validSnapshot(value: any): boolean
	return typeof(value) == "table"
		and typeof(value.phase) == "string"
		and PHASES[value.phase] == true
		and typeof(value.has_key) == "boolean"
		and typeof(value.gate_open) == "boolean"
		and nonnegativeNumber(value.session_diamonds)
		and nonnegativeNumber(value.reward_diamonds)
		and nonnegativeNumber(value.elapsed_sec)
		and typeof(value.notice) == "string"
end

local function getRemote(folder: Instance, name: string): RemoteEvent?
	local instance = folder:WaitForChild(name, REMOTE_WAIT_SEC)
	if not instance or not instance:IsA("RemoteEvent") then
		warn(
			string.format(
				"[RoundController] RemoteEvent %s is unavailable after %ds",
				name,
				REMOTE_WAIT_SEC
			)
		)
		return nil
	end
	return instance
end

function RoundController:Init(_context: any)
	self._snapshot = nil :: Snapshot?
	self._requestRemote = nil :: RemoteEvent?
	self._snapshotConnection = nil :: RBXScriptConnection?
	self._lastRequest = -math.huge
	self._hud = nil

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui", REMOTE_WAIT_SEC)
	if not playerGui or not playerGui:IsA("PlayerGui") then
		warn("[RoundController] PlayerGui is unavailable; the round interface was not created")
		return
	end
	self._hud = RoundHud.new(playerGui)
	self._hud:SetOnAction(function(action: string)
		self:_request(action)
	end)
end

function RoundController:_request(action: string)
	local remote = self._requestRemote
	local hud = self._hud
	if not remote or not hud or not self._snapshot or ACTIONS[action] ~= true then
		return
	end
	local now = os.clock()
	if now - self._lastRequest < DEBOUNCE_SEC then
		return
	end
	self._lastRequest = now
	hud:SetBusy(true)
	remote:FireServer(action)
	-- Only the server changes the view. A rejected request must not leave buttons stuck.
	task.delay(DEBOUNCE_SEC, function()
		if self._hud == hud then
			hud:SetBusy(false)
		end
	end)
end

function RoundController:Start(_context: any)
	local hud = self._hud
	if not hud then
		return
	end
	local folder = ReplicatedStorage:WaitForChild("GameRemotes", REMOTE_WAIT_SEC)
	if not folder or not folder:IsA("Folder") then
		warn("[RoundController] GameRemotes is unavailable; check RoundService startup in Output")
		hud:ShowUnavailable()
		return
	end
	local requestRemote = getRemote(folder, EndpointNames.RequestRoundAction)
	local snapshotRemote = getRemote(folder, EndpointNames.RoundSnapshot)
	if not requestRemote or not snapshotRemote then
		hud:ShowUnavailable()
		return
	end
	self._requestRemote = requestRemote
	self._snapshotConnection = snapshotRemote.OnClientEvent:Connect(function(payload: any)
		if not validSnapshot(payload) then
			warn("[RoundController] Ignored a malformed round_snapshot")
			return
		end
		self._snapshot = payload :: Snapshot
		hud:Render(payload :: Snapshot)
	end)

	-- Subscribe first: initial server messages may precede the client controller.
	requestRemote:FireServer("sync")
	task.delay(2, function()
		if self._hud == hud and self._snapshot == nil then
			requestRemote:FireServer("sync")
		end
	end)
	task.delay(REMOTE_WAIT_SEC, function()
		if self._hud == hud and self._snapshot == nil then
			warn("[RoundController] No valid initial round_snapshot; check RoundService Output")
			hud:ShowUnavailable()
		end
	end)
end

function RoundController:Destroy()
	if self._snapshotConnection then
		self._snapshotConnection:Disconnect()
		self._snapshotConnection = nil
	end
	if self._hud then
		self._hud:Destroy()
		self._hud = nil
	end
	self._requestRemote = nil
end

return RoundController
]========] },
{ path = "Game", class = "Folder" },
{ path = "Game/RoundHud", class = "ModuleScript", source = [========[--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RoundText: { [string]: string } = require(
	ReplicatedStorage:WaitForChild("GameShared"):WaitForChild("Game"):WaitForChild("RoundText")
)

export type Snapshot = {
	phase: string,
	has_key: boolean,
	gate_open: boolean,
	session_diamonds: number,
	reward_diamonds: number,
	elapsed_sec: number,
	notice: string,
}

local RoundHud = {}
RoundHud.__index = RoundHud

local PANEL_COLOR = Color3.fromRGB(27, 32, 28)
local TEXT_COLOR = Color3.fromRGB(239, 242, 233)
local MUTED_COLOR = Color3.fromRGB(190, 199, 186)
local BUTTON_COLOR = Color3.fromRGB(84, 109, 67)
local DISABLED_COLOR = Color3.fromRGB(63, 69, 61)

local function text(key: string, values: { [string]: string | number }?): string
	local template = RoundText[key] or ""
	return (
		string.gsub(template, "{([%w_]+)}", function(name)
			local value = if values then values[name] else nil
			return if value ~= nil then tostring(value) else "{" .. name .. "}"
		end)
	)
end

local function elapsedText(seconds: number): string
	local whole = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", math.floor(whole / 60), whole % 60)
end

local function label(
	parent: Instance,
	name: string,
	size: UDim2,
	position: UDim2,
	fontSize: number
): TextLabel
	local result = Instance.new("TextLabel")
	result.Name = name
	result.Size = size
	result.Position = position
	result.BackgroundTransparency = 1
	result.Font = Enum.Font.Gotham
	result.TextSize = fontSize
	result.TextColor3 = TEXT_COLOR
	result.TextWrapped = true
	result.TextXAlignment = Enum.TextXAlignment.Left
	result.TextYAlignment = Enum.TextYAlignment.Center
	result.Text = ""
	result.Parent = parent
	return result
end

local function button(
	parent: Instance,
	name: string,
	key: string,
	size: UDim2,
	position: UDim2
): TextButton
	local result = Instance.new("TextButton")
	result.Name = name
	result.Size = size
	result.Position = position
	result.BackgroundColor3 = BUTTON_COLOR
	result.BorderSizePixel = 0
	result.Font = Enum.Font.GothamMedium
	result.TextSize = 17
	result.TextColor3 = TEXT_COLOR
	result.Text = text(key)
	result.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = result
	return result
end

local function panel(parent: Instance, name: string, size: UDim2, position: UDim2): Frame
	local result = Instance.new("Frame")
	result.Name = name
	result.Size = size
	result.Position = position
	result.BackgroundColor3 = PANEL_COLOR
	result.BackgroundTransparency = 0.08
	result.BorderSizePixel = 0
	result.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = result
	return result
end

function RoundHud.new(playerGui: PlayerGui)
	local root = Instance.new("ScreenGui")
	root.Name = "CornRoundHud"
	root.ResetOnSpawn = false
	root.DisplayOrder = 10
	root.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	root.Parent = playerGui

	local card = panel(root, "RoundCard", UDim2.fromOffset(460, 320), UDim2.fromScale(0.5, 0.5))
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	local title = label(card, "Title", UDim2.new(1, -48, 0, 38), UDim2.fromOffset(24, 20), 27)
	title.Font = Enum.Font.GothamBold
	local message = label(card, "Message", UDim2.new(1, -48, 0, 52), UDim2.fromOffset(24, 68), 19)
	local resultTime =
		label(card, "Elapsed", UDim2.new(1, -48, 0, 26), UDim2.fromOffset(24, 124), 16)
	resultTime.TextColor3 = MUTED_COLOR
	local balance = label(card, "Balance", UDim2.new(1, -48, 0, 26), UDim2.fromOffset(24, 154), 16)
	balance.TextColor3 = MUTED_COLOR
	local notice = label(card, "Notice", UDim2.new(1, -48, 0, 46), UDim2.fromOffset(24, 186), 16)
	notice.TextColor3 = Color3.fromRGB(233, 209, 142)
	local start = button(
		card,
		"Start",
		"corn_loop_start",
		UDim2.new(1, -48, 0, 44),
		UDim2.fromOffset(24, 250)
	)
	local retry = button(
		card,
		"Retry",
		"corn_loop_retry",
		UDim2.new(0.5, -30, 0, 44),
		UDim2.fromOffset(24, 250)
	)
	local menu = button(
		card,
		"Menu",
		"corn_loop_menu",
		UDim2.new(0.5, -30, 0, 44),
		UDim2.new(0.5, 6, 0, 250)
	)
	local preparingLeave = button(
		card,
		"Leave",
		"corn_loop_leave",
		UDim2.new(1, -48, 0, 44),
		UDim2.fromOffset(24, 250)
	)

	local active = panel(root, "ActiveStatus", UDim2.new(0.64, 0, 0, 128), UDim2.fromOffset(20, 16))
	local activeConstraint = Instance.new("UISizeConstraint")
	activeConstraint.MaxSize = Vector2.new(690, 128)
	activeConstraint.Parent = active
	local objective =
		label(active, "Objective", UDim2.new(1, -32, 0, 32), UDim2.fromOffset(16, 8), 19)
	objective.Font = Enum.Font.GothamMedium
	local activeTime =
		label(active, "Elapsed", UDim2.new(1, -32, 0, 24), UDim2.fromOffset(16, 42), 15)
	activeTime.TextColor3 = MUTED_COLOR
	local activeBalance =
		label(active, "Balance", UDim2.new(1, -32, 0, 24), UDim2.fromOffset(16, 66), 15)
	activeBalance.TextColor3 = MUTED_COLOR
	local activeNotice =
		label(active, "Notice", UDim2.new(1, -32, 0, 24), UDim2.fromOffset(16, 94), 16)
	activeNotice.TextColor3 = notice.TextColor3
	local activeLeave = button(
		root,
		"LeaveRound",
		"corn_loop_leave",
		UDim2.fromOffset(185, 40),
		UDim2.new(1, -205, 0, 16)
	)

	local self = setmetatable({
		_root = root,
		_card = card,
		_title = title,
		_message = message,
		_time = resultTime,
		_balance = balance,
		_notice = notice,
		_active = active,
		_objective = objective,
		_activeTime = activeTime,
		_activeBalance = activeBalance,
		_activeNotice = activeNotice,
		_start = start,
		_retry = retry,
		_menu = menu,
		_preparingLeave = preparingLeave,
		_activeLeave = activeLeave,
		_buttons = { start, retry, menu, preparingLeave, activeLeave },
		_connections = {} :: { RBXScriptConnection },
		_snapshot = nil :: Snapshot?,
		_busy = false,
		_unavailable = false,
	}, RoundHud)
	self:_render()
	return self
end

function RoundHud:SetOnAction(callback: (string) -> ())
	local bindings = {
		{ button = self._start, action = "start" },
		{ button = self._retry, action = "retry" },
		{ button = self._menu, action = "menu" },
		{ button = self._preparingLeave, action = "abort" },
		{ button = self._activeLeave, action = "abort" },
	}
	for _, binding in bindings do
		table.insert(
			self._connections,
			binding.button.Activated:Connect(function()
				if not self._busy and not self._unavailable and self._snapshot ~= nil then
					callback(binding.action)
				end
			end)
		)
	end
end

function RoundHud:_render()
	local snapshot = self._snapshot
	local phase = if snapshot then snapshot.phase else "loading"
	local isActive = phase == "active"
	local isResult = phase == "escaped" or phase == "aborted"
	self._card.Visible = not isActive
	self._active.Visible = isActive
	self._activeLeave.Visible = isActive
	self._start.Visible = phase == "ready" or phase == "loading"
	self._retry.Visible = isResult
	self._menu.Visible = isResult
	self._preparingLeave.Visible = phase == "preparing"
	for _, control in self._buttons do
		local enabled = snapshot ~= nil and not self._busy and not self._unavailable
		control.Active = enabled
		control.AutoButtonColor = enabled
		control.BackgroundColor3 = if enabled then BUTTON_COLOR else DISABLED_COLOR
		control.TextTransparency = if enabled then 0 else 0.35
	end

	self._title.Text = text("corn_loop_title")
	self._time.Text = ""
	self._notice.Text = if snapshot then text(snapshot.notice) else ""
	self._balance.Visible = snapshot ~= nil
	self._balance.Text = text(
		"corn_loop_test_balance",
		{ count = if snapshot then snapshot.session_diamonds else 0 }
	)
	if self._unavailable then
		self._message.Text = text("corn_loop_connection_error")
	elseif phase == "loading" or phase == "preparing" then
		self._message.Text = text("corn_loop_loading")
	elseif phase == "ready" then
		self._message.Text = text("corn_loop_objective_search")
	elseif snapshot and isResult then
		self._title.Text = text(
			if phase == "escaped" then "corn_loop_result_escape" else "corn_loop_result_aborted"
		)
		self._message.Text = if phase == "escaped"
			then text("corn_loop_reward", { count = snapshot.reward_diamonds })
			else ""
		self._time.Text = text("corn_loop_round_time", { time = elapsedText(snapshot.elapsed_sec) })
	end

	if snapshot and isActive then
		local objectiveKey = if snapshot.gate_open
			then "corn_loop_objective_exit"
			elseif snapshot.has_key then "corn_loop_objective_return"
			else "corn_loop_objective_search"
		self._objective.Text = text(objectiveKey)
		self._activeTime.Text =
			text("corn_loop_round_time", { time = elapsedText(snapshot.elapsed_sec) })
		self._activeBalance.Text = self._balance.Text
		self._activeNotice.Text = text(snapshot.notice)
	end
end

function RoundHud:Render(snapshot: Snapshot)
	self._unavailable = false
	self._snapshot = snapshot
	self:_render()
end

function RoundHud:SetBusy(busy: boolean)
	self._busy = busy
	self:_render()
end

function RoundHud:ShowUnavailable()
	self._unavailable = true
	self:_render()
end

function RoundHud:Destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	self._root:Destroy()
end

return RoundHud
]========] }
} }
}
local function resolve(parent, path)
    local found = parent
    for _, segment in string.split(path, "/") do
        if segment ~= "" then
            found = found and found:FindFirstChild(segment)
        end
    end
    return found
end
local function normalized(source)
    return (string.gsub(source, "\r\n", "\n"))
end
local remove = {}
for _, entry in expected do
    local found = game
    for _, segment in entry.path do
        found = found and found:FindFirstChild(segment)
    end
    if found then
        assert(#found:GetDescendants() + 1 == #entry.nodes,
            "Unknown objects in " .. found:GetFullName() .. "; nothing removed")
        for _, node in entry.nodes do
            local item = resolve(found, node.path)
            assert(item and item.ClassName == node.class,
                "Unexpected object in " .. found:GetFullName() .. "; nothing removed")
            if node.source then
                assert(normalized(item.Source) == normalized(node.source),
                    "Source differs: " .. item:GetFullName() .. "; nothing removed")
            end
        end
        table.insert(remove, found)
    end
end
assert(#remove == 0 or #remove == 3, "Incomplete Corn integration; nothing removed")
local function assetUri(item, modernProperty, legacyProperty)
    local ok, value = pcall(function()
        return item[modernProperty].Uri
    end)
    if ok and type(value) == "string" then
        return value
    end
    local legacyOk, legacyValue = pcall(function()
        return item[legacyProperty]
    end)
    return if legacyOk then legacyValue else nil
end
local extras = {}
local runtime = workspace:FindFirstChild("CornPrototypeRuntime")
if runtime then
    assert(runtime:IsA("Model") and runtime:GetAttribute("RuntimePrototype") == true,
        "Unrecognized runtime model; nothing removed")
    table.insert(extras, runtime)
end
local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("GameRemotes")
if remotes then
    for _, remoteName in { "request_round_action", "round_snapshot" } do
        local remote = remotes:FindFirstChild(remoteName)
        if remote then
            assert(remote:IsA("RemoteEvent"), "Unexpected remote type; nothing removed")
            table.insert(extras, remote)
        end
    end
end
for _, templateName in { "CornPlantTemplate", "SM_Prop_Plant_Corn_01_L" } do
    local template = game:GetService("ServerStorage"):FindFirstChild(templateName)
    if template then
        local meshes = 0
        local items = template:GetDescendants()
        table.insert(items, template)
        for _, item in items do
            assert(not item:IsA("LuaSourceContainer"), "Art contains unknown code; nothing removed")
            if item:IsA("MeshPart") then
                assert(assetUri(item, "MeshContent", "MeshId") == "rbxassetid://104111861186519"
                    and assetUri(item, "TextureContent", "TextureID") == "rbxassetid://137803536172445",
                    "Unrecognized art asset; nothing removed")
                meshes += 1
            elseif item:IsA("BasePart") then
                error("Unrecognized part in corn art; nothing removed")
            end
        end
        assert(meshes == 1, "Unrecognized art hierarchy; nothing removed")
        table.insert(extras, template)
    end
end
local history = game:GetService("ChangeHistoryService")
history:SetWaypoint("Before removing ChildrenOfCorn")
for _, container in remove do
    container:Destroy()
end
for _, item in extras do
    item:Destroy()
end
if remotes and #remotes:GetChildren() == 0 then
    remotes:Destroy()
end
history:SetWaypoint("Removed ChildrenOfCorn from Speed Monkey")
print("ChildrenOfCorn cleanup: removed " .. #remove .. " verified containers; Speed Monkey retained")
