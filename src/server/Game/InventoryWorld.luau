--!strict
local Workspace = game:GetService("Workspace")
local Models = require(script.Parent:WaitForChild("ItemModels"))
local InventoryWorld = {}
InventoryWorld.__index = InventoryWorld
function InventoryWorld.new(world: any, random: Random, keySlot: BasePart, onPickup: any): any
	local folder = Instance.new("Folder")
	folder.Name = "InventoryItems"
	folder:SetAttribute("corn_inventory_owned", true)
	folder:SetAttribute("corn_project_id", "children_of_corn")
	folder.Parent = world.Runtime
	local lookouts = Instance.new("Folder")
	lookouts.Name = "LookoutStumps"
	lookouts:SetAttribute("corn_inventory_owned", true)
	lookouts:SetAttribute("corn_project_id", "children_of_corn")
	lookouts.Parent = folder
	local self = setmetatable(
		{ world = world, folder = folder, pickups = {}, traps = {}, connections = {} },
		InventoryWorld
	)
	local slots = table.clone(world.Slots)
	for index = #slots, 2, -1 do
		local other = random:NextInteger(1, index)
		slots[index], slots[other] = slots[other], slots[index]
	end
	local used = 0
	for _, slot in slots do
		if slot == keySlot then
			continue
		end
		used += 1
		local kind = if used <= 2 then "energy" else "trap"
		local position = Vector3.new(
			slot.Position.X + 3.6,
			world.Ground.Position.Y + world.Ground.Size.Y / 2,
			slot.Position.Z
		)
		local frame = CFrame.new(
			position
				+ Vector3.new(0, if kind == "energy" then Models.StumpHeight + 0.68 else 0.22, 0)
		)
		local object, anchor
		if kind == "energy" then
			object, anchor = Models.Energy(frame)
		else
			object, anchor = Models.Trap(frame)
		end
		object.Name = "Pickup" .. used
		object:SetAttribute("item_kind", kind)
		object:SetAttribute("item_id", tostring(used))
		object:AddTag("corn_item_pickup")
		if kind == "energy" then
			local lookout = Instance.new("Model")
			lookout.Name = "Lookout" .. used
			lookout:SetAttribute("corn_inventory_owned", true)
			lookout:SetAttribute("corn_project_id", "children_of_corn")
			lookout:SetAttribute("LookoutVersion", 1)
			lookout:AddTag("corn_lookout_stump")
			lookout.PrimaryPart = Models.Stump(
				lookout,
				CFrame.new(position + Vector3.new(0, Models.StumpHeight / 2, 0))
			)
			lookout.Parent = lookouts
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "CornItemPrompt"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.ActionText = "Подобрать"
		prompt.ObjectText = if kind == "energy" then "Энергетик" else "Капкан"
		prompt.MaxActivationDistance = world.Radius
		prompt.RequiresLineOfSight = true
		prompt.Parent = anchor
		local entry = { model = object, anchor = anchor, prompt = prompt, kind = kind }
		table.insert(self.pickups, entry)
		table.insert(
			self.connections,
			prompt.Triggered:Connect(function(player)
				onPickup(player, entry)
			end)
		)
		object.Parent = folder
		if used == 4 then
			break
		end
	end
	return self
end
function InventoryWorld:SetEnabled(enabled: boolean)
	for _, entry in self.pickups do
		if entry.model.Parent then
			entry.prompt.Enabled = enabled
		end
	end
end
function InventoryWorld:Take(entry: any): boolean
	if not table.find(self.pickups, entry) or entry.model.Parent ~= self.folder then
		return false
	end
	entry.prompt.Enabled = false
	entry.model:Destroy()
	return true
end
function InventoryWorld:Place(root: BasePart, character: Model): boolean
	if #self.traps >= 2 then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- Runtime lookouts are real collision surfaces. Do not place through their
	-- wood; other owned items/NPC are noncollidable and are skipped by the ray.
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -9, 0), params)
	local props = self.world.Root:FindFirstChild("Props")
	local road = if props then props:FindFirstChild("VillageRoad") else nil
	if
		not hit
		or (hit.Instance ~= self.world.Ground and not (road and hit.Instance:IsDescendantOf(road)))
		or not self.world:IsOnPlayground(hit.Position)
	then
		return false
	end
	local object, anchor = Models.Trap(CFrame.new(hit.Position + Vector3.new(0, 0.15, 0)))
	object.Name = "PlacedTrap" .. (#self.traps + 1)
	object:AddTag("corn_placed_trap")
	object:SetAttribute("item_kind", "trap")
	object.Parent = self.folder
	table.insert(self.traps, { model = object, position = anchor.Position, spent = false })
	return true
end
function InventoryWorld:CheckTraps(hunt: any, from: Vector3?, now: number): boolean
	local at = hunt:GetPosition()
	if not at or hunt.state == "trapped" then
		return false
	end
	local start = from or at
	local segment = Vector3.new(at.X - start.X, 0, at.Z - start.Z)
	for _, trap in self.traps do
		if trap.spent then
			continue
		end
		local offset = Vector3.new(trap.position.X - start.X, 0, trap.position.Z - start.Z)
		local t = if segment.Magnitude > 0
			then math.clamp(offset:Dot(segment) / segment:Dot(segment), 0, 1)
			else 0
		local closest = start + (at - start) * t
		if
			Vector3.new(closest.X - trap.position.X, 0, closest.Z - trap.position.Z).Magnitude
				<= 2.3
			and math.abs(closest.Y - trap.position.Y) <= 5
			and hunt:Stun(now, 10)
		then
			trap.spent = true
			trap.model:SetAttribute("Triggered", true)
			local closed = Models.Trap(CFrame.new(trap.position), true)
			closed.Name = "SpentTrap"
			closed.Parent = self.folder
			trap.model:Destroy()
			task.delay(10, function()
				closed:Destroy()
			end)
			return true
		end
	end
	return false
end
function InventoryWorld:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	self.folder:Destroy()
	table.clear(self.pickups)
	table.clear(self.traps)
end
return InventoryWorld
