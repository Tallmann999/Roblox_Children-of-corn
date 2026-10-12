--!strict
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local CornField = require(script.Parent:WaitForChild("CornField"))
local ItemModels = require(script.Parent:WaitForChild("ItemModels"))
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

local function validateSpawn(root: Model, spawn: BasePart, bounds: BasePart)
	assert(spawn:IsDescendantOf(root), "Spawn must belong to CornMap")
	assert(hasTag(spawn, "corn_spawn"), "Missing corn_spawn tag: " .. spawn.Name)
	local id = spawn:GetAttribute("spawn_id")
	assert(type(id) == "string" and id ~= "", "Spawn id must be a nonempty string: " .. spawn.Name)
	assert(spawn.Anchored, "Spawn must be Anchored: " .. spawn.Name)
	assert(
		spawn.CFrame.UpVector:Dot(Vector3.yAxis) > 0.999,
		"Spawn must remain horizontal: " .. spawn.Name
	)
	if spawn:IsA("SpawnLocation") then
		assert(
			spawn.Enabled and spawn.Neutral,
			"Corner spawn must be enabled and neutral: " .. spawn.Name
		)
	end
	local position = (spawn.CFrame * CFrame.new(0, spawn.Size.Y / 2 + 3.5, 0)).Position
	assert(inBox(bounds, position), "Spawn is outside PlayBounds: " .. spawn.Name)
end

function AuthoredWorld.IsSafeSpawn(root: Model, spawn: BasePart): boolean
	local bounds = root:FindFirstChild("PlayBounds")
	return bounds ~= nil and bounds:IsA("BasePart") and pcall(validateSpawn, root, spawn, bounds)
end

function AuthoredWorld.ReadSpawns(root: Model): { BasePart }
	local bounds = namedPart(root, "PlayBounds")
	local corners = root:FindFirstChild("CornerSpawns")
	local spawns: { BasePart } = {}
	if corners then
		assert(
			corners:IsA("Folder")
				and corners:GetAttribute("CornCornerSpawnsOwned") == true
				and corners:GetAttribute("corn_project_id") == "children_of_corn",
			"Unrecognized CornerSpawns"
		)
		local seen: { [string]: boolean } = {}
		for _, item in corners:GetChildren() do
			assert(item:IsA("SpawnLocation"), "CornerSpawns must contain only SpawnLocations")
			validateSpawn(root, item, bounds)
			local id = item:GetAttribute("spawn_id") :: string
			assert(not seen[id], "Corner spawn ids must be unique")
			seen[id] = true
			table.insert(spawns, item)
		end
		assert(#spawns == 4, "CornMap must have four corner spawns")
		table.sort(spawns, function(a, b)
			return tostring(a:GetAttribute("spawn_id")) < tostring(b:GetAttribute("spawn_id"))
		end)
	else
		local legacy = namedPart(root, "RoundSpawn")
		validateSpawn(root, legacy, bounds)
		table.insert(spawns, legacy)
	end
	return spawns
end

-- A broken gate or slot must not leave the menu character underneath the map.
function AuthoredWorld.FindSafeSpawn(root: Model): BasePart?
	local bounds = root:FindFirstChild("PlayBounds")
	if not bounds or not bounds:IsA("BasePart") then
		return nil
	end
	local candidates: { BasePart } = {}
	local corners = root:FindFirstChild("CornerSpawns")
	if
		corners
		and corners:IsA("Folder")
		and corners:GetAttribute("CornCornerSpawnsOwned") == true
		and corners:GetAttribute("corn_project_id") == "children_of_corn"
	then
		for _, item in corners:GetChildren() do
			if item:IsA("SpawnLocation") and pcall(validateSpawn, root, item, bounds) then
				table.insert(candidates, item)
			end
		end
	end
	table.sort(candidates, function(a, b)
		return tostring(a:GetAttribute("spawn_id")) < tostring(b:GetAttribute("spawn_id"))
	end)
	if candidates[1] then
		return candidates[1]
	end
	local legacy = root:FindFirstChild("RoundSpawn")
	if legacy and legacy:IsA("BasePart") and pcall(validateSpawn, root, legacy, bounds) then
		return legacy
	end
	return nil
end

function AuthoredWorld.SpawnCFrame(spawn: BasePart): CFrame
	return spawn.CFrame * CFrame.new(0, spawn.Size.Y / 2 + 3.5, 0)
end

function AuthoredWorld.new(radius: number, expectedSlots: number)
	local root = Workspace:FindFirstChild("CornMap")
	assert(
		root and root:IsA("Model") and root:GetAttribute("corn_project_id") == "children_of_corn",
		"Install the editable CornMap in Children_of_corn before Test"
	)
	local spawns = AuthoredWorld.ReadSpawns(root)
	local field = namedPart(root, "FieldZone")
	local ground = namedPart(root, "Ground")
	local home = root.Props:FindFirstChild("ScarecrowMarker")
	assert(home and home:IsA("Model") and home:HasTag("corn_monster_home"), "Monster home missing")
	local bounds = namedPart(root, "PlayBounds")
	local gateModel = root:FindFirstChild("EscapeGate")
	assert(
		gateModel and gateModel:IsA("Model") and hasTag(gateModel, "corn_gate"),
		"Missing tagged EscapeGate"
	)
	local gate = namedPart(gateModel, "Door")
	local anchor = namedPart(gateModel, "InteractionAnchor")
	local exit = namedPart(gateModel, "ExitZone")
	assert(hasTag(exit, "corn_exit"), "Missing corn_exit tag")
	local gateId = gateModel:GetAttribute("gate_id")
	assert(type(gateId) == "string" and gateId ~= "", "Gate id must be a nonempty string")
	assert(exit:GetAttribute("gate_id") == gateId, "Gate/exit identity mismatch")
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
		Spawns = spawns,
		Spawn = spawns[1],
		Field = field,
		Ground = ground,
		Home = home,
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
		KeyModel = nil :: Model?,
		KeyPrompt = nil :: ProximityPrompt?,
	}, AuthoredWorld)
	return self
end

function AuthoredWorld:SelectSpawn(index: number): BasePart
	assert(index % 1 == 0 and index >= 1 and index <= #self.Spawns, "Invalid spawn index")
	local spawn = self.Spawns[index]
	validateSpawn(self.Root, spawn, self.Bounds)
	self.Spawn = spawn
	return spawn
end

function AuthoredWorld:GetSpawnCFrame(): CFrame
	validateSpawn(self.Root, self.Spawn, self.Bounds)
	return AuthoredWorld.SpawnCFrame(self.Spawn)
end

function AuthoredWorld:ClearKey()
	if self.KeyModel then
		self.KeyModel:Destroy()
	elseif self.Key then
		self.Key:Destroy()
	end
	self.Key = nil
	self.KeyModel = nil
	self.KeyPrompt = nil
end

function AuthoredWorld:SpawnKeyAt(frame: CFrame): ProximityPrompt
	self:ClearKey()
	local object, key = ItemModels.Key(frame)
	key.Name = "GateKey"
	object.Parent = self.Runtime
	self.KeyModel = object
	self.Key = key
	self.KeyPrompt =
		prompt(key, "CornKeyPrompt", "Подобрать", "Ключ от ворот", self.Radius)
	return self.KeyPrompt
end

function AuthoredWorld:SpawnKey(slot: BasePart): ProximityPrompt
	assert(slot:IsDescendantOf(self.Root), "Key slot must belong to CornMap")
	return self:SpawnKeyAt(slot.CFrame * CFrame.new(0, slot.Size.Y / 2 + 0.3, 0))
end

function AuthoredWorld:DropKey(position: Vector3, radius: number): ProximityPrompt?
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Exclude
	ray.FilterDescendantsInstances = { self.Runtime }
	ray.RespectCanCollide = true
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { self.Root.Props, self.Root.Boundaries, self.Gate }
	overlap.RespectCanCollide = true
	for ring = 0, radius do
		for angle = 0, if ring == 0 then 0 else 7 do
			local offset = Vector3.new(
				math.cos(angle * math.pi / 4),
				0,
				math.sin(angle * math.pi / 4)
			) * ring
			local at = position + offset
			local hit = workspace:Raycast(at + Vector3.new(0, 10, 0), Vector3.new(0, -40, 0), ray)
			if
				hit and (hit.Instance == self.Ground or hit.Instance == self.GateModel.ExitGround)
			then
				local place = hit.Position + Vector3.new(0, 0.5, 0)
				local obstacles = workspace:GetPartBoundsInBox(
					CFrame.new(place + Vector3.new(0, 1, 0)),
					Vector3.new(3, 2, 3),
					overlap
				)
				if #obstacles == 0 and self:IsOnPlayground(place) then
					return self:SpawnKeyAt(CFrame.new(place))
				end
			end
		end
	end
	return nil
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
	local spawnIds: { [string]: boolean } = {}
	for _, spawn in self.Spawns do
		if not pcall(validateSpawn, self.Root, spawn, self.Bounds) then
			return false
		end
		local id = spawn:GetAttribute("spawn_id") :: string
		if spawnIds[id] then
			return false
		end
		spawnIds[id] = true
	end
	local gateId = self.GateModel:GetAttribute("gate_id")
	if type(gateId) ~= "string" or gateId == "" or gateId ~= self.Exit:GetAttribute("gate_id") then
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
