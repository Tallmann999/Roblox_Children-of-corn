--!strict
local ItemModels = {}
local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	frame: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local item = Instance.new("Part")
	item.Name = name
	item.Size = size
	item.CFrame = frame
	item.Color = color
	item.Material = material or Enum.Material.Metal
	item.Anchored = true
	item.CanCollide = false
	item.CanTouch = false
	item.CanQuery = false
	item.Parent = parent
	return item
end
local function model(name: string): (Model, Part)
	local object = Instance.new("Model")
	object.Name = name
	object:SetAttribute("corn_inventory_owned", true)
	object:SetAttribute("corn_project_id", "children_of_corn")
	local anchor =
		part(object, "Anchor", Vector3.new(0.1, 0.1, 0.1), CFrame.identity, Color3.new(1, 1, 1))
	anchor.Transparency = 1
	object.PrimaryPart = anchor
	return object, anchor
end
function ItemModels.Key(frame: CFrame): (Model, Part)
	local object, anchor = model("GateKeyModel")
	local gold = Color3.fromRGB(235, 192, 60)
	anchor.CFrame = frame
	for index = 1, 12 do
		local angle = index * math.pi / 6
		part(
			object,
			"Ring" .. index,
			Vector3.new(0.26, 0.15, 0.42),
			frame
				* CFrame.new(math.cos(angle) * 0.65, 0, -1 + math.sin(angle) * 0.65)
				* CFrame.Angles(0, -angle, 0),
			gold
		)
	end
	part(object, "Shaft", Vector3.new(0.23, 0.17, 1.95), frame * CFrame.new(0, 0, 0.58), gold)
	for index = 1, 2 do
		part(
			object,
			"Tooth" .. index,
			Vector3.new(0.58, 0.17, 0.22),
			frame * CFrame.new(0.2, 0, 0.75 + index * 0.36),
			gold
		)
	end
	return object, anchor
end
function ItemModels.Energy(frame: CFrame): (Model, Part)
	local object, anchor = model("EnergyCan")
	anchor.CFrame = frame
	local body = part(
		object,
		"Can",
		Vector3.new(1.25, 0.72, 0.72),
		frame * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(38, 116, 65)
	)
	body.Shape = Enum.PartType.Cylinder
	for _, offset in { -0.62, 0.62 } do
		local lid = part(
			object,
			"Lid",
			Vector3.new(0.07, 0.74, 0.74),
			frame * CFrame.new(0, offset, 0) * CFrame.Angles(0, 0, math.pi / 2),
			Color3.fromRGB(180, 192, 185)
		)
		lid.Shape = Enum.PartType.Cylinder
	end
	local label = Instance.new("SurfaceGui")
	label.Face = Enum.NormalId.Front
	label.CanvasSize = Vector2.new(256, 256)
	label.Parent = body
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Text = "⚡"
	text.TextColor3 = Color3.fromRGB(240, 255, 133)
	text.TextScaled = true
	text.Parent = label
	return object, anchor
end
function ItemModels.Trap(frame: CFrame, closed: boolean?): (Model, Part)
	local object, anchor = model("BearTrap")
	anchor.CFrame = frame
	local steel = Color3.fromRGB(91, 100, 99)
	local base = part(
		object,
		"Plate",
		Vector3.new(0.16, 2.2, 2.2),
		frame * CFrame.Angles(0, 0, math.pi / 2),
		steel
	)
	base.Shape = Enum.PartType.Cylinder
	for side = -1, 1, 2 do
		local jaw = frame * CFrame.new(side * 0.95, 0.18, 0)
		if closed then
			jaw = jaw * CFrame.Angles(0, 0, side * math.rad(65))
		end
		part(object, "Jaw", Vector3.new(0.18, 0.2, 2.15), jaw, steel)
		for tooth = -2, 2 do
			part(
				object,
				"Tooth",
				Vector3.new(0.16, 0.32, 0.18),
				jaw * CFrame.new(0, 0.2, tooth * 0.4),
				Color3.fromRGB(163, 170, 164)
			)
		end
	end
	part(
		object,
		"Trigger",
		Vector3.new(0.65, 0.13, 0.65),
		frame * CFrame.new(0, 0.15, 0),
		Color3.fromRGB(154, 118, 62)
	)
	return object, anchor
end
function ItemModels.Stump(parent: Instance, frame: CFrame): Part
	local stump = part(
		parent,
		"Stump",
		Vector3.new(2.4, 3, 3),
		frame * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(94, 70, 43),
		Enum.Material.Wood
	)
	stump.Shape = Enum.PartType.Cylinder
	stump.CanCollide = true
	stump.CanQuery = true
	local top = part(
		parent,
		"CutWood",
		Vector3.new(0.12, 2.85, 2.85),
		frame * CFrame.new(0, 1.21, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(171, 143, 95),
		Enum.Material.Wood
	)
	top.Shape = Enum.PartType.Cylinder
	return stump
end
return ItemModels
