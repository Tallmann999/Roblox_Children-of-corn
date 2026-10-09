--!strict

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
