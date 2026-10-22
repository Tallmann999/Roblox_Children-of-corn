--!strict

local CornLayout = {
	Height = 8,
	Spacing = 3,
	Seed = 817,
	ChunkCells = 12,
	RenderRadius = 150,
	ElevatedRadius = 200,
	DenseRadius = 60,
	MediumRadius = 130,
}

export type Plant = Model | BasePart
export type Box = { Frame: CFrame, HalfSize: Vector2 }
export type Circle = { Center: Vector3, Radius: number }
export type TrailEdge = {
	CenterX: number,
	CenterZ: number,
	HalfWidth: number,
	HalfLength: number,
	AlongX: boolean,
	Key: string,
}
export type Exclusions = {
	Boxes: { Box },
	Circles: { Circle },
	Signature: string,
	TrailEdges: { TrailEdge }?,
	TrailEdgeMaxShift: number?,
}

local SLOT_RADIUS = 6
local BOX_PADDING = 1.5
local DETAILED_SPACING_SCALE = 1 / math.sqrt(2.6)
local TRAIL_EDGE_OUTSET = 0.05

local function finite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

function CornLayout.Bounds(plant: Plant): (CFrame, Vector3)
	if plant:IsA("Model") then
		return plant:GetBoundingBox()
	end
	return plant.CFrame, plant.Size
end

function CornLayout.PrepareTemplate(source: Instance, height: number?): (Plant?, string?)
	if not source:IsA("Model") and not source:IsA("BasePart") then
		return nil, "Corn source must be a Model or BasePart"
	end
	local targetHeight = height or CornLayout.Height
	if not finite(targetHeight) or targetHeight <= 0 then
		return nil, "Corn height must be positive and finite"
	end
	local items = source:GetDescendants()
	table.insert(items, source)
	local partCount = 0
	for _, item in items do
		if item:IsA("LuaSourceContainer") then
			return nil, "Corn source contains code"
		end
		if
			item:IsA("Sound")
			or item:IsA("ParticleEmitter")
			or item:IsA("Beam")
			or item:IsA("Trail")
			or item:IsA("ProximityPrompt")
			or item:IsA("ClickDetector")
			or item:IsA("RemoteEvent")
			or item:IsA("RemoteFunction")
		then
			return nil, "Corn source must contain only static art"
		end
		if not item.Archivable then
			return nil, "Corn source has non-Archivable contents"
		end
		if item:IsA("BasePart") then
			partCount += 1
		end
	end
	if partCount == 0 then
		return nil, "Corn source has no BaseParts"
	end

	local prepared = source:Clone() :: Plant?
	if not prepared then
		return nil, "Corn source could not be cloned"
	end
	local ok, problem = pcall(function()
		local _, size = CornLayout.Bounds(prepared :: Plant)
		if not finite(size.Y) or size.Y <= 0 then
			error("Corn source has no usable height")
		end
		local ratio = targetHeight / size.Y
		if prepared:IsA("Model") then
			prepared:ScaleTo(prepared:GetScale() * ratio)
		else
			prepared.Size *= ratio
			for _, item in prepared:GetChildren() do
				if item:IsA("SpecialMesh") then
					item.Scale *= ratio
				end
			end
		end
		-- The imported plant has one mesh plus import poses/animation metadata.
		-- Keep only that normalized mesh on decorative copies; the source is untouched.
		if prepared:IsA("Model") and partCount == 1 then
			local mesh = prepared:FindFirstChildWhichIsA("MeshPart", true)
			if mesh and mesh:IsA("MeshPart") then
				mesh.Parent = nil
				prepared:Destroy()
				prepared = mesh
			end
		end
		for _, item in prepared:GetDescendants() do
			if
				item:IsA("AnimationController")
				or (item:IsA("Folder") and item.Name == "InitialPoses")
			then
				item:Destroy()
			end
		end
		local clones = prepared:GetDescendants()
		table.insert(clones, prepared)
		for _, item in clones do
			-- Art tags must not become gameplay bindings on every decorative clone.
			for _, tag in item:GetTags() do
				item:RemoveTag(tag)
			end
			if item:IsA("BasePart") then
				item.Anchored = true
				item.CanCollide = false
				item.CanTouch = false
				item.CanQuery = false
				item.CastShadow = false
				if item:IsA("MeshPart") then
					item.DoubleSided = true
				end
			end
		end
		prepared:PivotTo(CornLayout.PivotForPlant(prepared, Vector3.zero, 0))
	end)
	if not ok then
		prepared:Destroy()
		return nil, tostring(problem)
	end
	return prepared, nil
end

function CornLayout.PivotForPlant(plant: Plant, groundPosition: Vector3, yaw: number): CFrame
	local bounds, size = CornLayout.Bounds(plant)
	local boundsFromPivot = plant:GetPivot():ToObjectSpace(bounds)
	return CFrame.new(groundPosition + Vector3.new(0, size.Y / 2, 0))
		* CFrame.Angles(0, yaw, 0)
		* boundsFromPivot:Inverse()
end

function CornLayout.SpacingFor(field: BasePart): number
	local map = field.Parent
	if
		field.Name == "FieldZone"
		and map
		and map:IsA("Model")
		and map.Name == "CornMap"
		and map:GetAttribute("corn_project_id") == "children_of_corn"
		and map:GetAttribute("HarvestArtVariant") == "B"
	then
		return CornLayout.Spacing * DETAILED_SPACING_SCALE
	end
	return CornLayout.Spacing
end

function CornLayout.GetCellBounds(field: BasePart): (number, number, number, number)
	local half = field.Size / 2
	local spacing = CornLayout.SpacingFor(field)
	return math.ceil(-half.X / spacing),
		math.floor(half.X / spacing),
		math.ceil(-half.Z / spacing),
		math.floor(half.Z / spacing)
end

function CornLayout.BaseCellPosition(field: BasePart, column: number, row: number): Vector3
	local half = field.Size / 2
	local spacing = CornLayout.SpacingFor(field)
	local hashX = (column * 92837111 + row * 689287499 + CornLayout.Seed) % 104729
	local hashZ = (column * 19349663 + row * 83492791 + CornLayout.Seed) % 104729
	local stagger = if row % 2 == 0 then -spacing * 0.15 else spacing * 0.15
	local x = column * spacing + stagger + (hashX / 104729 - 0.5) * spacing * 0.12
	local z = row * spacing + (hashZ / 104729 - 0.5) * spacing * 0.12
	return field.CFrame:PointToWorldSpace(
		Vector3.new(math.clamp(x, -half.X, half.X), -half.Y, math.clamp(z, -half.Z, half.Z))
	)
end

local function hash(column: number, row: number, salt: number): number
	return ((column * 73856093 + row * 19349663 + CornLayout.Seed * salt) % 104729) / 104729
end

function CornLayout.CellPosition(field: BasePart, column: number, row: number): Vector3
	local point = field.CFrame:PointToObjectSpace(CornLayout.BaseCellPosition(field, column, row))
	local half = field.Size / 2
	local spacing = CornLayout.SpacingFor(field)
	return field.CFrame:PointToWorldSpace(
		Vector3.new(
			math.clamp(point.X + (hash(column, row, 17) * 2 - 1) * spacing * 0.1, -half.X, half.X),
			point.Y,
			math.clamp(point.Z + (hash(column, row, 31) * 2 - 1) * spacing * 0.1, -half.Z, half.Z)
		)
	)
end

function CornLayout.CellYaw(column: number, row: number): number
	local sign = if hash(column, row, 47) < 0.5 then -1 else 1
	return math.rad(10 + hash(column, row, 61) * 20) * sign
end

function CornLayout.HeightFactor(column: number, row: number): number
	local sign = if hash(column, row, 79) < 0.5 then -1 else 1
	return 1 + sign * (0.1 + hash(column, row, 97) * 0.05)
end

function CornLayout.ApplyVariation(plant: Plant, column: number, row: number)
	local factor = CornLayout.HeightFactor(column, row)
	if plant:IsA("BasePart") then
		plant.Size = Vector3.new(plant.Size.X, plant.Size.Y * factor, plant.Size.Z)
	else
		plant:ScaleTo(plant:GetScale() * factor)
	end
end

local function footprint(frame: CFrame, size: Vector3, padding: number): Box
	local look = frame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local flat = CFrame.new(frame.Position) * CFrame.Angles(0, yaw, 0)
	local half = size / 2
	local right = flat.RightVector
	local forward = flat.LookVector
	local width = math.abs(right:Dot(frame.RightVector)) * half.X
		+ math.abs(right:Dot(frame.UpVector)) * half.Y
		+ math.abs(right:Dot(frame.LookVector)) * half.Z
	local depth = math.abs(forward:Dot(frame.RightVector)) * half.X
		+ math.abs(forward:Dot(frame.UpVector)) * half.Y
		+ math.abs(forward:Dot(frame.LookVector)) * half.Z
	return { Frame = flat, HalfSize = Vector2.new(width + padding, depth + padding) }
end

local function authorDescendants(map: Model): { Instance }
	local result: { Instance } = {}
	local stack = map:GetChildren()
	while #stack > 0 do
		local item = table.remove(stack)
		local owned = item:GetAttribute("corn_project_id") == "children_of_corn"
		local decoration = owned
			and (
				(item.Name == "EditorPreview" and item:GetAttribute("CornEditorPreview") == true)
				or (item.Name == "EditorFieldOverview" and item:GetAttribute("CornEditorOverview") == true)
				or (item.Name == "CornClientPlants" and item:GetAttribute("CornClientRendererOwned") == true)
				or (item.Name == "CornClientBackdrop" and item:GetAttribute(
					"CornClientBackdropOwned"
				) == true)
				or item.Name == "CornRoundRuntime"
			)
		if decoration then
			continue
		end
		table.insert(result, item)
		for _, child in item:GetChildren() do
			table.insert(stack, child)
		end
	end
	return result
end
function CornLayout.ReadExclusions(map: Model, field: BasePart): Exclusions
	local boxes: { Box } = {}
	local circles: { Circle } = {}
	local trailEdges: { TrailEdge } = {}
	local signatures: { string } = { tostring(field.CFrame) .. "/" .. tostring(field.Size) }
	local included: { [Instance]: boolean } = {}
	local detailed = CornLayout.SpacingFor(field) ~= CornLayout.Spacing
	local noCorn = map:FindFirstChild("NoCornZones")
	local maze = if noCorn then noCorn:FindFirstChild("Maze02Masks") else nil
	local function ownedTrail(part: BasePart): boolean
		local index = tonumber(part.Name:match("^trail_(%d%d%d)$"))
		return detailed
			and map == field.Parent
			and maze ~= nil
			and maze:IsA("Folder")
			and maze:GetAttribute("corn_project_id") == "children_of_corn"
			and maze:GetAttribute("CornMazeOwner") == "corn_maze02_v1"
			and part.Parent == maze
			and part:GetAttribute("corn_project_id") == "children_of_corn"
			and part:GetAttribute("CornMazeOwner") == "corn_maze02_v1"
			and index ~= nil
			and index >= 1
			and index <= 100
			and math.abs(part.Size.Y - 0.08) < 0.001
			and math.min(part.Size.X, part.Size.Z) == 4
			and math.max(part.Size.X, part.Size.Z) >= 30
			and part.CFrame.Rotation == CFrame.identity
	end
	local function addBox(part: BasePart, padding: number)
		if included[part] then
			return
		end
		included[part] = true
		local trail = ownedTrail(part)
		if trail then
			-- The visible four-stud path is the root clearance. Fixed props keep
			-- their existing safety margin; leaves may reach over the path edge.
			padding = 0
		end
		local box = footprint(part.CFrame, part.Size, padding)
		table.insert(boxes, box)
		if trail then
			local center = part.CFrame.Position
			table.insert(trailEdges, {
				CenterX = center.X,
				CenterZ = center.Z,
				HalfWidth = math.min(part.Size.X, part.Size.Z) / 2,
				HalfLength = math.max(part.Size.X, part.Size.Z) / 2,
				AlongX = part.Size.X > part.Size.Z,
				Key = part.Name,
			})
		end
		table.insert(
			signatures,
			part:GetFullName()
				.. "/box/"
				.. tostring(part.CFrame)
				.. "/"
				.. tostring(part.Size)
				.. "/"
				.. padding
		)
	end
	for _, folderName in { "NoCornZones", "Props" } do
		local folder = map:FindFirstChild(folderName)
		if folder then
			for _, item in folder:GetDescendants() do
				if item:IsA("BasePart") then
					addBox(item, BOX_PADDING)
				end
			end
		end
	end
	for _, item in authorDescendants(map) do
		if item:IsA("BasePart") then
			if item:HasTag("corn_no_corn_zone") then
				addBox(item, BOX_PADDING)
			end
			if item:HasTag("corn_key_slot") then
				table.insert(circles, { Center = item.Position, Radius = SLOT_RADIUS })
				table.insert(signatures, item:GetFullName() .. "/slot/" .. tostring(item.Position))
			elseif item:HasTag("corn_spawn") then
				addBox(item, 4)
				table.insert(circles, { Center = item.Position, Radius = 10 })
				table.insert(signatures, item:GetFullName() .. "/spawn/" .. tostring(item.Position))
			end
		end
	end
	local gate = map:FindFirstChild("EscapeGate")
	if gate then
		local door = gate:FindFirstChild("Door", true)
		if door and door:IsA("BasePart") then
			addBox(door, 6)
		end
	end
	table.sort(signatures)
	table.sort(trailEdges, function(a, b)
		return a.Key < b.Key
	end)
	return {
		Boxes = boxes,
		Circles = circles,
		Signature = table.concat(signatures, "|"),
		TrailEdges = trailEdges,
		TrailEdgeMaxShift = CornLayout.SpacingFor(field),
	}
end

function CornLayout.IsExcluded(position: Vector3, exclusions: Exclusions): boolean
	for _, circle in exclusions.Circles do
		local delta = position - circle.Center
		if delta.X * delta.X + delta.Z * delta.Z <= circle.Radius * circle.Radius then
			return true
		end
	end
	for _, box in exclusions.Boxes do
		local localPosition = box.Frame:PointToObjectSpace(position)
		if
			math.abs(localPosition.X) <= box.HalfSize.X
			and math.abs(localPosition.Z) <= box.HalfSize.Y
		then
			return true
		end
	end
	return false
end

function CornLayout.TrailEdgePosition(position: Vector3, exclusions: Exclusions): Vector3
	local edges = exclusions.TrailEdges
	local reach = exclusions.TrailEdgeMaxShift
	if not edges or #edges == 0 or not reach then
		return position
	end
	local bestGap = math.huge
	local x, z = position.X, position.Z
	local candidateX, candidateZ = x, z
	local found = false
	for _, edge in edges do
		local dx, dz = x - edge.CenterX, z - edge.CenterZ
		local across = if edge.AlongX then dz else dx
		local along = if edge.AlongX then dx else dz
		local gap = math.abs(across) - edge.HalfWidth
		if
			gap >= 0
			and gap <= reach
			and gap < bestGap
			and math.abs(along) <= edge.HalfLength - 1
		then
			bestGap = gap
			local target = (if across < 0 then -1 else 1) * (edge.HalfWidth + TRAIL_EDGE_OUTSET)
			candidateX = if edge.AlongX then x else edge.CenterX + target
			candidateZ = if edge.AlongX then edge.CenterZ + target else z
			found = true
		end
	end
	-- Reuse existing cells, variants and render budgets. Both the original and
	-- projected root must pass every clearance, including crossing paths.
	local candidate = if found then Vector3.new(candidateX, position.Y, candidateZ) else nil
	if
		candidate
		and not CornLayout.IsExcluded(position, exclusions)
		and not CornLayout.IsExcluded(candidate, exclusions)
	then
		return candidate
	end
	return position
end

return CornLayout
