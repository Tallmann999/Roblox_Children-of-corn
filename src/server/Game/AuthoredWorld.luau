--!strict
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local CornField = require(script.Parent:WaitForChild("CornField"))
local AuthoredWorld = {}
AuthoredWorld.__index = AuthoredWorld

local function namedPart(parent: Instance, name: string): BasePart
	local item = parent:FindFirstChild(name)
	assert(item and item:IsA("BasePart"), "Missing map part: " .. name)
	return item
end

local function hasTag(item: Instance, tag: string): boolean
	return CollectionService:HasTag(item, tag)
end

local function prompt(
	parent: Instance,
	name: string,
	action: string,
	object: string,
	radius: number
): ProximityPrompt
	assert(not parent:FindFirstChild(name), "Duplicate owned prompt: " .. name)
	local item = Instance.new("ProximityPrompt")
	item.Name = name
	item.ActionText = action
	item.ObjectText = object
	item.KeyboardKeyCode = Enum.KeyCode.E
	item.MaxActivationDistance = radius
	item.RequiresLineOfSight = true
	item.HoldDuration = 0
	item.Enabled = false
	item.Parent = parent
	return item
end

local function inBox(part: BasePart, position: Vector3): boolean
	local point = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(point.X) <= half.X
		and math.abs(point.Y) <= half.Y
		and math.abs(point.Z) <= half.Z
end

function AuthoredWorld.new(radius: number, expectedSlots: number)
	local root = Workspace:FindFirstChild("CornMap")
	assert(
		root and root:IsA("Model") and root:GetAttribute("corn_project_id") == "children_of_corn",
		"Install the editable CornMap in Children_of_corn before Test"
	)
	local spawn = namedPart(root, "RoundSpawn")
	local field = namedPart(root, "FieldZone")
	local bounds = namedPart(root, "PlayBounds")
	local gateModel = root:FindFirstChild("EscapeGate")
	assert(
		gateModel and gateModel:IsA("Model") and hasTag(gateModel, "corn_gate"),
		"Missing tagged EscapeGate"
	)
	local gate = namedPart(gateModel, "Door")
	local anchor = namedPart(gateModel, "InteractionAnchor")
	local exit = namedPart(gateModel, "ExitZone")
	assert(hasTag(spawn, "corn_spawn") and hasTag(exit, "corn_exit"), "Missing spawn/exit tags")
	assert(
		exit:GetAttribute("gate_id") == gateModel:GetAttribute("gate_id"),
		"Gate/exit identity mismatch"
	)
	local slots: { BasePart } = {}
	local seen: { [string]: boolean } = {}
	for _, item in root:GetDescendants() do
		if item:IsA("BasePart") and hasTag(item, "corn_key_slot") then
			local id = item:GetAttribute("slot_id")
			assert(
				type(id) == "string" and id ~= "" and not seen[id],
				"Key slot ids must be unique strings"
			)
			seen[id] = true
			table.insert(slots, item)
		end
	end
	assert(#slots == expectedSlots, "CornMap must have " .. tostring(expectedSlots) .. " key slots")
	table.sort(slots, function(a, b)
		return tostring(a:GetAttribute("slot_id")) < tostring(b:GetAttribute("slot_id"))
	end)
	assert(not root:FindFirstChild("CornRoundRuntime"), "CornRoundRuntime already exists")
	assert(not anchor:FindFirstChild("CornGatePrompt"), "CornGatePrompt already exists")
	assert(gate.CanCollide, "Closed Door must have CanCollide enabled")
	local artOk, artReady = pcall(CornField.Prepare)
	if not artOk or not artReady then
		warn("[AuthoredWorld] Corn art unavailable:", artReady)
	end
	local runtime = Instance.new("Folder")
	runtime.Name = "CornRoundRuntime"
	runtime:SetAttribute("corn_project_id", "children_of_corn")
	runtime.Parent = root
	local gatePrompt = prompt(anchor, "CornGatePrompt", "Открыть", "Ворота", radius)
	local self = setmetatable({
		Root = root,
		Radius = radius,
		Slots = slots,
		Spawn = spawn,
		Field = field,
		Bounds = bounds,
		GateModel = gateModel,
		Gate = gate,
		GateAnchor = anchor,
		Exit = exit,
		Runtime = runtime,
		GatePrompt = gatePrompt,
		ClosedTransparency = gate.Transparency,
		ClosedCollision = gate.CanCollide,
		ClosedQuery = gate.CanQuery,
		Key = nil :: Part?,
		KeyPrompt = nil :: ProximityPrompt?,
	}, AuthoredWorld)
	return self
end

function AuthoredWorld:GetSpawnCFrame(): CFrame
	return self.Spawn.CFrame * CFrame.new(0, self.Spawn.Size.Y / 2 + 3.5, 0)
end

function AuthoredWorld:ClearKey()
	if self.Key then
		self.Key:Destroy()
	end
	self.Key = nil
	self.KeyPrompt = nil
end

function AuthoredWorld:SpawnKey(slot: BasePart): ProximityPrompt
	assert(slot:IsDescendantOf(self.Root), "Key slot must belong to CornMap")
	self:ClearKey()
	local key = Instance.new("Part")
	key.Name = "GateKey"
	key.Size = Vector3.new(1.5, 0.4, 3)
	key.CFrame = slot.CFrame * CFrame.new(0, slot.Size.Y / 2 + 0.3, 0)
	key.Anchored = true
	key.Color = Color3.fromRGB(240, 198, 69)
	key.Material = Enum.Material.Metal
	key.CanCollide = false
	key.CanTouch = false
	key.Parent = self.Runtime
	self.Key = key
	self.KeyPrompt =
		prompt(key, "CornKeyPrompt", "Подобрать", "Ключ от ворот", self.Radius)
	return self.KeyPrompt
end

function AuthoredWorld:SetGateOpen(open: boolean)
	self.Gate.CanCollide = if open then false else self.ClosedCollision
	self.Gate.CanQuery = if open then false else self.ClosedQuery
	self.Gate.Transparency = if open then 1 else self.ClosedTransparency
	self.GatePrompt.Enabled = false
	self.Runtime:SetAttribute("GateOpen", open)
end

function AuthoredWorld:SetInteractionEnabled(enabled: boolean, gateOpen: boolean)
	self.GatePrompt.Enabled = enabled and not gateOpen
	if self.KeyPrompt then
		self.KeyPrompt.Enabled = enabled
	end
end

function AuthoredWorld:IsGateFront(position: Vector3): boolean
	local anchor = self.Gate.CFrame:PointToObjectSpace(self.GateAnchor.Position)
	local point = self.Gate.CFrame:PointToObjectSpace(position)
	local frontSign = if anchor.Z < 0 then -1 else 1
	return point.Z * frontSign > self.Gate.Size.Z / 2
end

function AuthoredWorld:IsInExit(position: Vector3): boolean
	return inBox(self.Exit, position)
end

function AuthoredWorld:IsOnPlayground(position: Vector3): boolean
	return inBox(self.Bounds, position)
end

function AuthoredWorld:IsValid(): boolean
	if
		self.Root.Parent ~= Workspace
		or not self.Runtime:IsDescendantOf(self.Root)
		or not self.Spawn:IsDescendantOf(self.Root)
		or not self.Field:IsDescendantOf(self.Root)
		or not self.Bounds:IsDescendantOf(self.Root)
		or not self.Gate:IsDescendantOf(self.Root)
		or not self.GateAnchor:IsDescendantOf(self.Root)
		or not self.Exit:IsDescendantOf(self.Root)
		or not self.GatePrompt:IsDescendantOf(self.GateAnchor)
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

return AuthoredWorld
