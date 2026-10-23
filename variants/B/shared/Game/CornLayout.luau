--!strict

local GreenBedLayout = require(script.Parent.GreenBedLayout)

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
	GreenBeds: boolean?,
	AuthoredCorn: any?,
}

local SLOT_RADIUS = 6
local BOX_PADDING = 1.5
-- The B grid keeps regular rows: 30% fewer plants per unit area, rather than
-- removing hashed individual cells and leaving irregular holes in each row.
local DETAILED_SPACING_SCALE = 1 / math.sqrt(2.6 * 0.7)
local TRAIL_EDGE_OUTSET = 0.05
local GREEN_TRAIL_EDGE_OUTSET = 0.15
local authoredCache = setmetatable({}, { __mode = "k" })

local function greenField(field: BasePart): boolean
	local map = field.Parent
	return field.Name == "FieldZone"
		and field.Size == Vector3.new(630, 10, 630)
		and map ~= nil
		and map:IsA("Model")
		and map.Name == "CornMap"
		and map:GetAttribute("corn_project_id") == "children_of_corn"
		and map:GetAttribute("HarvestArtVariant") == "B"
end

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
					if item.MeshId == "rbxassetid://104111861186519" then
						item.TextureID = "rbxassetid://137803536172445"
						item.Color = Color3.new(1, 1, 1)
						item:SetAttribute("CornGreenOriginal", true)
					end
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
	if greenField(field) then
		return field.CFrame:PointToWorldSpace(Vector3.new(column * spacing, -half.Y, row * spacing))
	end
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
	if greenField(field) then
		return GreenBedLayout.Position(CornLayout.BaseCellPosition(field, column, row))
	end
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
	return hash(column, row, 61) * math.pi * 2
end

function CornLayout.HeightFactor(column: number, row: number): number
	return 0.85 + hash(column, row, 97) * 0.3
end

function CornLayout.ApplyVariation(plant: Plant, column: number, row: number)
	if plant:GetAttribute("CornGreenOriginal") == true then
		-- All four green geometry templates start at height eight. Scale only Y;
		-- DetailedPivot subsequently uses their real root anchor and this Size.
		local factor = CornLayout.HeightFactor(column, row)
		assert(plant:IsA("BasePart"), "B green height variation requires a single static part")
		plant.Size = Vector3.new(plant.Size.X, plant.Size.Y * factor, plant.Size.Z)
		return
	end
	-- Preserve the legacy fallback path; A has its own canonical module.
	local sign = if hash(column, row, 79) < 0.5 then -1 else 1
	local factor = 1 + sign * (0.1 + hash(column, row, 97) * 0.05)
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
				or (item.Name == "CornAuthoring" and item:GetAttribute("BManualAuthoringVersion") == 1)
				or item:GetAttribute("BGreenBedsOwner") == "corn_B_green_beds_v1"
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

local function refreshAuthored(state)
	if not state.Dirty then
		return
	end
	local buckets = {}
	local count = 0
	for _, part in state.Source:GetDescendants() do
		if part:IsA("MeshPart") then
			local opacity = part:GetAttribute("BManualSourceTransparency")
			if type(opacity) ~= "number" then
				opacity = part.Transparency
			end
			local offset = part:GetAttribute("HarvestRootOffset")
			local templateSize = part:GetAttribute("CornGreenTemplateSize")
			if
				type(opacity) == "number"
				and finite(opacity)
				and opacity < 1
				and typeof(offset) == "Vector3"
				and typeof(templateSize) == "Vector3"
				and templateSize.X > 0
				and templateSize.Y > 0
				and templateSize.Z > 0
			then
				local size = part.Size
				local root = part.CFrame:PointToWorldSpace(
					-Vector3.new(
						offset.X * size.X / templateSize.X,
						offset.Y * size.Y / templateSize.Y,
						offset.Z * size.Z / templateSize.Z
					)
				)
				if finite(root.X) and finite(root.Z) then
					local key = math.floor(root.X / state.Width)
						.. ":"
						.. math.floor(root.Z / state.Width)
					if not buckets[key] then
						buckets[key] = {}
					end
					table.insert(buckets[key], root)
					count += 1
				end
			end
		end
	end
	state.Buckets, state.Count, state.Dirty = buckets, count, false
end

function CornLayout.AuthoringSource(map: Instance?): Folder?
	if
		not (
			map
			and map:IsA("Model")
			and map.Name == "CornMap"
			and map:GetAttribute("corn_project_id") == "children_of_corn"
			and map:GetAttribute("HarvestArtVariant") == "B"
			and map:GetAttribute("BManualAuthoringVersion") == 1
		)
	then
		return nil
	end
	local function ownedSource(folder)
		return folder
			and folder:IsA("Folder")
			and folder:GetAttribute("corn_project_id") == "children_of_corn"
			and folder:GetAttribute("BManualAuthoringVersion") == 1
	end
	local storage = game:GetService("ReplicatedStorage")
	local root = storage:FindFirstChild("BManualEditorSources")
	if ownedSource(root) then
		local source = root:FindFirstChild("CornAuthoring")
		if ownedSource(source) then
			return source
		end
	end
	local source = map:FindFirstChild("CornAuthoring")
	return if ownedSource(source) then source else nil
end

local function authoredExclusions(map, field)
	local source = CornLayout.AuthoringSource(map)
	if
		not (
			greenField(field)
			and map:GetAttribute("BManualAuthoringVersion") == 1
			and source
			and source:IsA("Folder")
			and source:GetAttribute("corn_project_id") == "children_of_corn"
			and source:GetAttribute("BManualAuthoringVersion") == 1
		)
	then
		return nil
	end
	local state = authoredCache[map]
	if
		not state
		or state.Source ~= source
		or state.Frame ~= field.CFrame
		or state.Size ~= field.Size
	then
		if state then
			for _, connection in state.Connections do
				connection:Disconnect()
			end
		end
		local radius = CornLayout.SpacingFor(field) * 0.72
		state = {
			Map = map,
			Source = source,
			Frame = field.CFrame,
			Size = field.Size,
			Radius = radius,
			Width = radius * 2 + 0.01,
			Buckets = {},
			Dirty = true,
			Connections = {},
		}
		local function invalidate()
			state.Dirty = true
		end
		state.Connections = {
			source.DescendantAdded:Connect(invalidate),
			source.DescendantRemoving:Connect(invalidate),
		}
		authoredCache[map] = state
	end
	refreshAuthored(state)
	return {
		Boxes = {},
		Circles = {},
		TrailEdges = {},
		AuthoredCorn = state,
		Signature = "B-manual-authoring-v1/" .. tostring(field.CFrame) .. "/" .. tostring(
			field.Size
		),
	}
end

function CornLayout.ReadExclusions(map: Model, field: BasePart): Exclusions
	local authored = authoredExclusions(map, field)
	if authored then
		return authored
	end
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
	local signature = table.concat(signatures, "|")
	local green = greenField(field)
	if green then
		local matches = signature == GreenBedLayout.Signature
		if not matches and game:GetService("RunService"):IsClient() then
			matches = GreenBedLayout.MatchesExclusions({ Boxes = boxes, Circles = circles }, field)
		end
		assert(matches, "B clearances changed; regenerate the guarded green-bed plan")
		-- A stable accepted signature keeps normal network rounding from causing
		-- repeated renderer rebuilds. Exact Edit/server checks remain above.
		signature = GreenBedLayout.Signature
			.. "|green-beds-v2-density70/"
			.. GreenBedLayout.InputSHA256
	end
	return {
		Boxes = boxes,
		Circles = circles,
		Signature = signature,
		TrailEdges = trailEdges,
		TrailEdgeMaxShift = CornLayout.SpacingFor(field),
		GreenBeds = green,
	}
end

function CornLayout.IsExcluded(position: Vector3, exclusions: Exclusions): boolean
	local authored = exclusions.AuthoredCorn
	if authored then
		if
			CornLayout.AuthoringSource(authored.Map) ~= authored.Source
			or authored.Source:GetAttribute("BManualAuthoringVersion") ~= 1
			or authored.Source:GetAttribute("corn_project_id") ~= "children_of_corn"
		then
			return true
		end
		refreshAuthored(authored)
		local point = authored.Frame:PointToObjectSpace(position)
		if math.abs(point.X) > authored.Size.X / 2 or math.abs(point.Z) > authored.Size.Z / 2 then
			return true
		end
		local radius, width = authored.Radius, authored.Width
		-- Width exceeds the diameter: each query visits at most four buckets.
		for x = math.floor((position.X - radius) / width), math.floor((position.X + radius) / width) do
			for z = math.floor((position.Z - radius) / width), math.floor((position.Z + radius) / width) do
				for _, root in authored.Buckets[x .. ":" .. z] or {} do
					local dx, dz = position.X - root.X, position.Z - root.Z
					if dx * dx + dz * dz <= radius * radius then
						return false
					end
				end
			end
		end
		return true
	end
	if exclusions.GreenBeds and not GreenBedLayout.Contains(position) then
		return true
	end
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
	local outset = if exclusions.GreenBeds then GREEN_TRAIL_EDGE_OUTSET else TRAIL_EDGE_OUTSET
	for _, edge in edges do
		local dx, dz = x - edge.CenterX, z - edge.CenterZ
		local across = if edge.AlongX then dz else dx
		local along = if edge.AlongX then dx else dz
		local gap = math.abs(across) - edge.HalfWidth
		if
			gap >= (if exclusions.GreenBeds then outset else 0)
			and gap <= reach
			and gap < bestGap
			and math.abs(along) <= edge.HalfLength - 1
		then
			bestGap = gap
			local target = (if across < 0 then -1 else 1) * (edge.HalfWidth + outset)
			candidateX = if edge.AlongX then x else edge.CenterX + target
			candidateZ = if edge.AlongX then edge.CenterZ + target else z
			found = true
		end
	end
	-- Reuse existing cells, variants and render budgets. Both the original and
	-- projected root must pass every clearance, including crossing paths.
	local candidate = if found then Vector3.new(candidateX, position.Y, candidateZ) else nil
	if candidate and exclusions.GreenBeds then
		local height = GreenBedLayout.GetHeight(candidate)
		if not height then
			-- Rounded FBX skirts do not fill their bounding rectangles. Retain
			-- the closest real bed surface along this bounded, path-safe segment;
			-- never invent soil heights or add an extra plant at the trail edge.
			local valid, invalid = 0, 1
			local base = position
			local delta = candidate - base
			for _ = 1, 8 do
				local amount = (valid + invalid) / 2
				local sample = base + delta * amount
				local sampledHeight = GreenBedLayout.GetHeight(sample)
				if sampledHeight then
					valid, height = amount, sampledHeight
				else
					invalid = amount
				end
			end
			if valid == 0 then
				return position
			end
			candidate = base + delta * valid
		end
		assert(height, "Projected B corn root requires a real bed surface")
		candidate = Vector3.new(candidate.X, height, candidate.Z)
	end
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
