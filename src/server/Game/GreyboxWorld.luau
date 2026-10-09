--!strict

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
