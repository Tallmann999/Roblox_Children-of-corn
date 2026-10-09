--!strict
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local Layout = require(
	ReplicatedStorage:WaitForChild("GameShared"):WaitForChild("Game"):WaitForChild("CornLayout")
)
local MapAuthoring = {}

local function guard()
	assert(
		RunService:IsStudio() and not RunService:IsRunning(),
		"Use the Command Bar in Studio Edit mode"
	)
	assert(
		not Workspace:FindFirstChild("Asmr_Base") and not Workspace:FindFirstChild("ASMR_Models"),
		"Speed Monkey scene detected; Corn installation refused"
	)
	local config = ReplicatedStorage:FindFirstChild("GameShared")
	config = config and config:FindFirstChild("Config")
	local module = config and config:FindFirstChild("GameConfig")
	assert(
		module
			and module:IsA("ModuleScript")
			and string.find(module.Source, 'Id = "children_of_corn"', 1, true),
		"Open the Children_of_corn project"
	)
end

local function artSource(): Instance
	local first = ServerStorage:FindFirstChild("CornPlantTemplate")
	local imported = ServerStorage:FindFirstChild("SM_Prop_Plant_Corn_01_L")
	assert(not (first and imported), "Keep one unambiguous corn source in ServerStorage")
	local source = first or imported
	assert(source, "Imported corn asset missing from ServerStorage")
	return source
end

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

local function zone(parent: Instance, name: string, size: Vector3, position: Vector3): Part
	local item = part(parent, name, size, position, Color3.fromRGB(123, 175, 113))
	item.Transparency = 1
	item.CanCollide = false
	item.CanTouch = false
	item.CanQuery = false
	return item
end

local function noCorn(parent: Instance, name: string, size: Vector3, position: Vector3): Part
	local item = zone(parent, name, size, position)
	CollectionService:AddTag(item, "corn_no_corn_zone")
	return item
end

local function house(parent: Instance, name: string, origin: Vector3)
	local root = Instance.new("Model")
	root.Name = name
	root.Parent = parent
	local walls = part(
		root,
		"Body",
		Vector3.new(20, 12, 24),
		origin + Vector3.new(0, 6, 0),
		Color3.fromRGB(95, 84, 62)
	)
	walls.Material = Enum.Material.WoodPlanks
	local door = part(
		root,
		"DecorativeDoor",
		Vector3.new(4, 7, 0.25),
		origin + Vector3.new(0, 3.5, -12.1),
		Color3.fromRGB(58, 45, 33)
	)
	door.Material = Enum.Material.Wood
	for _, side in { -1, 1 } do
		local roof = part(
			root,
			"Roof",
			Vector3.new(12, 1, 26),
			origin + Vector3.new(side * 5, 14, 0),
			Color3.fromRGB(54, 57, 49)
		)
		roof.CFrame *= CFrame.Angles(0, 0, -side * math.pi / 8)
		roof.Material = Enum.Material.Slate
	end
end

function MapAuthoring.EnsureCornerSpawns(map: Model): Folder
	guard()
	assert(
		map.Parent == Workspace and map:GetAttribute("corn_project_id") == "children_of_corn",
		"Corner spawns require the correct editable CornMap"
	)
	local field = map:FindFirstChild("FieldZone")
	local bounds = map:FindFirstChild("PlayBounds")
	assert(
		field and field:IsA("BasePart") and bounds and bounds:IsA("BasePart"),
		"FieldZone/PlayBounds missing"
	)
	assert(field.CFrame.UpVector:Dot(Vector3.yAxis) > 0.999, "FieldZone must remain horizontal")
	assert(field.Size.X > 100 and field.Size.Z > 100, "FieldZone is too small for corner starts")
	local entries = {
		{ Name = "SW", Id = "solo_corner_sw", X = -1, Z = -1 },
		{ Name = "SE", Id = "solo_corner_se", X = 1, Z = -1 },
		{ Name = "NW", Id = "solo_corner_nw", X = -1, Z = 1 },
		{ Name = "NE", Id = "solo_corner_ne", X = 1, Z = 1 },
	}
	local old = map:FindFirstChild("CornerSpawns")
	if old then
		assert(
			old:IsA("Folder")
				and old:GetAttribute("CornCornerSpawnsOwned") == true
				and old:GetAttribute("corn_project_id") == "children_of_corn",
			"Unrecognized CornerSpawns; not replaced"
		)
		assert(#old:GetChildren() == 4, "CornerSpawns must contain exactly four owned starts")
		for _, entry in entries do
			local item = old:FindFirstChild(entry.Name)
			assert(
				item
					and item:IsA("SpawnLocation")
					and item:GetAttribute("spawn_id") == entry.Id
					and item:GetAttribute("CornCornerSpawnOwned") == true
					and item:GetAttribute("corn_project_id") == "children_of_corn"
					and CollectionService:HasTag(item, "corn_spawn")
					and item.Enabled
					and item.Neutral,
				"Unknown or invalid corner start: " .. entry.Name
			)
			local position = bounds.CFrame:PointToObjectSpace(
				(item.CFrame * CFrame.new(0, item.Size.Y / 2 + 3.5, 0)).Position
			)
			local half = bounds.Size / 2
			assert(
				math.abs(position.X) <= half.X
					and math.abs(position.Y) <= half.Y
					and math.abs(position.Z) <= half.Z
					and item.Anchored
					and item.CFrame.UpVector:Dot(Vector3.yAxis) > 0.999,
				"Corner start is unsafe: " .. entry.Name
			)
		end
		return old
	end
	local folder = Instance.new("Folder")
	folder.Name = "CornerSpawns"
	folder:SetAttribute("CornCornerSpawnsOwned", true)
	folder:SetAttribute("corn_project_id", "children_of_corn")
	local ok, problem = pcall(function()
		for _, entry in entries do
			local localPosition = Vector3.new(
				entry.X * (field.Size.X / 2 - 50),
				-field.Size.Y / 2 + 0.075,
				entry.Z * (field.Size.Z / 2 - 50)
			)
			local position = field.CFrame:PointToWorldSpace(localPosition)
			local center = Vector3.new(field.Position.X, position.Y, field.Position.Z)
			local item = Instance.new("SpawnLocation")
			item.Parent = folder
			item.Name = entry.Name
			item.Size = Vector3.new(6, 0.15, 6)
			item.CFrame = CFrame.lookAt(position, center)
			item.Anchored = true
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = false
			item.Neutral = true
			item.Enabled = true
			item.AllowTeamChangeOnTouch = false
			item.Duration = 0
			item.Color = Color3.fromRGB(158, 176, 150)
			item:SetAttribute("spawn_id", entry.Id)
			item:SetAttribute("CornCornerSpawnOwned", true)
			item:SetAttribute("corn_project_id", "children_of_corn")
			CollectionService:AddTag(item, "corn_spawn")
			local candidate = bounds.CFrame:PointToObjectSpace(
				(item.CFrame * CFrame.new(0, item.Size.Y / 2 + 3.5, 0)).Position
			)
			local half = bounds.Size / 2
			assert(
				math.abs(candidate.X) <= half.X
					and math.abs(candidate.Y) <= half.Y
					and math.abs(candidate.Z) <= half.Z,
				"Corner start is outside PlayBounds"
			)
			item.Parent = folder
		end
	end)
	if not ok then
		folder:Destroy()
		error(tostring(problem))
	end
	folder.Parent = map
	return folder
end

function MapAuthoring.Preview(map: Model, center: Vector3, radius: number?): number
	guard()
	local field = map:FindFirstChild("FieldZone")
	assert(field and field:IsA("BasePart"), "CornMap FieldZone missing")
	local old = map:FindFirstChild("EditorPreview")
	assert(
		not old
			or (
				old:IsA("Folder")
				and old:GetAttribute("CornEditorPreview") == true
				and old:GetAttribute("corn_project_id") == "children_of_corn"
			),
		"Unrecognized EditorPreview; not replaced"
	)
	local prepared, problem = Layout.PrepareTemplate(artSource())
	assert(prepared, problem or "Cannot prepare corn preview")
	local folder = Instance.new("Folder")
	folder.Name = "EditorPreview"
	folder:SetAttribute("CornEditorPreview", true)
	folder:SetAttribute("corn_project_id", "children_of_corn")
	local distance = math.clamp(radius or 55, 10, 85)
	local localCenter = field.CFrame:PointToObjectSpace(center)
	local minColumn, maxColumn, minRow, maxRow = Layout.GetCellBounds(field)
	minColumn = math.max(minColumn, math.ceil((localCenter.X - distance) / Layout.Spacing))
	maxColumn = math.min(maxColumn, math.floor((localCenter.X + distance) / Layout.Spacing))
	minRow = math.max(minRow, math.ceil((localCenter.Z - distance) / Layout.Spacing))
	maxRow = math.min(maxRow, math.floor((localCenter.Z + distance) / Layout.Spacing))
	local exclusions = Layout.ReadExclusions(map, field)
	local _, fieldYaw = field.CFrame:ToOrientation()
	local count = 0
	local ok, err = pcall(function()
		for row = minRow, maxRow do
			for column = minColumn, maxColumn do
				local position = Layout.CellPosition(field, column, row)
				local delta = position - center
				if
					Vector2.new(delta.X, delta.Z).Magnitude <= distance
					and not Layout.IsExcluded(position, exclusions)
				then
					local clone = prepared:Clone()
					assert(clone, "Corn clone is not Archivable")
					clone.Name = "Corn"
					clone:PivotTo(
						Layout.PivotForPlant(
							prepared,
							position,
							Layout.CellYaw(column, row) + fieldYaw
						)
					)
					clone.Parent = folder
					count += 1
				end
			end
		end
	end)
	prepared:Destroy()
	if not ok then
		folder:Destroy()
		error(tostring(err))
	end
	if old then
		old:Destroy()
	end
	folder.Parent = map
	folder:SetAttribute("PlantCount", count)
	return count
end

-- Whole-map coarse corn for authoring and distant view; fine plants stay local.
function MapAuthoring.RebuildOverview(map: Model): number
	guard()
	assert(
		map.Parent == Workspace and map:GetAttribute("corn_project_id") == "children_of_corn",
		"CornMap missing"
	)
	local field = map:FindFirstChild("FieldZone")
	assert(field and field:IsA("BasePart"), "FieldZone missing")
	assert(field.CFrame.UpVector:Dot(Vector3.yAxis) > 0.9999, "FieldZone must stay horizontal")
	local old = map:FindFirstChild("EditorFieldOverview")
	if old then
		assert(
			old:IsA("Folder")
				and old:GetAttribute("CornEditorOverview") == true
				and old:GetAttribute("corn_project_id") == "children_of_corn",
			"Unrecognized overview; retained"
		)
		for _, item in old:GetChildren() do
			assert(
				item:IsA("BasePart")
					and item:GetAttribute("CornEditorOverview") == true
					and item:GetAttribute("corn_project_id") == "children_of_corn",
				"Overview contains manual objects; retained"
			)
		end
	end
	local prepared, problem = Layout.PrepareTemplate(artSource())
	assert(prepared, problem or "Cannot prepare overview art")
	assert(prepared:IsA("MeshPart"), "Whole-field overview requires the imported single-mesh corn")
	local stride = 16
	-- Preserve plant proportions. This sparse layer is an approximate field overview,
	-- while EditorPreview and the client renderer provide dense, life-size plants.
	local _, preparedSize = Layout.Bounds(prepared)
	local half = preparedSize / 2
	local folder = Instance.new("Folder")
	folder.Name = "EditorFieldOverview"
	folder:SetAttribute("CornEditorOverview", true)
	folder:SetAttribute("corn_project_id", "children_of_corn")
	folder:SetAttribute("OverviewSpacing", stride)
	folder:SetAttribute("OverviewApproximation", true)
	folder:SetAttribute("OverviewPlantScale", 1)
	local exclusions = Layout.ReadExclusions(map, field)
	local _, yaw = field.CFrame:ToOrientation()
	local count = 0
	local ok, err = pcall(function()
		for row = math.ceil(-field.Size.Z / 2 / stride), math.floor(field.Size.Z / 2 / stride) do
			for column = math.ceil(-field.Size.X / 2 / stride), math.floor(field.Size.X / 2 / stride) do
				local ground = field.CFrame:PointToWorldSpace(
					Vector3.new(column * stride, -field.Size.Y / 2, row * stride)
				)
				local excluded = false
				for _, x in { -1, 0, 1 } do
					for _, z in { -1, 0, 1 } do
						local sample = ground
							+ field.CFrame:VectorToWorldSpace(
								Vector3.new(x * half.X, 0, z * half.Z)
							)
						if Layout.IsExcluded(sample, exclusions) then
							excluded = true
							break
						end
					end
					if excluded then
						break
					end
				end
				if excluded then
					continue
				end
				local clone = prepared:Clone()
				assert(clone, "Overview clone failed")
				clone.Name = "DistantCorn"
				clone:SetAttribute("CornEditorOverview", true)
				clone:SetAttribute("corn_project_id", "children_of_corn")
				clone:PivotTo(Layout.PivotForPlant(prepared, ground, yaw))
				clone.Parent = folder
				count += 1
				if count % 128 == 0 then
					task.wait()
				end
			end
		end
	end)
	prepared:Destroy()
	if not ok then
		folder:Destroy()
		error(tostring(err))
	end
	if old then
		old:Destroy()
	end
	folder:SetAttribute("PlantCount", count)
	folder.Parent = map
	print(
		"CornMap whole-field overview:",
		count,
		"upright sparse overview meshes; fine corn uses 3-stud spacing"
	)
	return count
end

function MapAuthoring.PreviewAtSelection(): number
	guard()
	local map = Workspace:FindFirstChild("CornMap")
	assert(
		map and map:IsA("Model") and map:GetAttribute("corn_project_id") == "children_of_corn",
		"CornMap missing"
	)
	local spawn: Instance? = map:FindFirstChild("RoundSpawn")
	if not spawn then
		local corners = map:FindFirstChild("CornerSpawns")
		spawn = corners and corners:FindFirstChild("SW")
	end
	assert(spawn and spawn:IsA("BasePart"), "CornMap has no preview start")
	local center = spawn.Position
	local selected = Selection:Get()[1]
	if selected and (selected:IsA("Model") or selected:IsA("BasePart")) then
		center = selected:GetPivot().Position
	end
	local count = MapAuthoring.Preview(map, center)
	print("CornMap editor preview:", count, "plants near selection")
	return count
end

function MapAuthoring.Install(): Model
	guard()
	assert(not Workspace:FindFirstChild("CornMap"), "CornMap already exists; manual edits retained")
	local testClone, problem = Layout.PrepareTemplate(artSource())
	assert(testClone, problem or "Corn art preparation failed")
	testClone:Destroy()
	local root = Instance.new("Model")
	root.Name = "CornMap"
	root:SetAttribute("corn_project_id", "children_of_corn")
	root:SetAttribute("map_version", 1)
	local ok, err = pcall(function()
		local ground = part(
			root,
			"Ground",
			Vector3.new(1200, 2, 1200),
			Vector3.new(0, 79, 0),
			Color3.fromRGB(91, 97, 70)
		)
		ground.Material = Enum.Material.Ground
		local field = zone(root, "FieldZone", Vector3.new(1200, 10, 1200), Vector3.new(0, 85, 0))
		CollectionService:AddTag(field, "corn_field_zone")
		local bounds = zone(root, "PlayBounds", Vector3.new(1200, 50, 1240), Vector3.new(0, 100, 0))
		CollectionService:AddTag(bounds, "corn_play_bounds")
		local zones = Instance.new("Folder")
		zones.Name = "NoCornZones"
		zones.Parent = root
		local props = Instance.new("Folder")
		props.Name = "Props"
		props.Parent = root
		local slots = Instance.new("Folder")
		slots.Name = "KeySlots"
		slots.Parent = root
		local boundaries = Instance.new("Folder")
		boundaries.Name = "Boundaries"
		boundaries.Parent = root
		local wall = Color3.fromRGB(51, 61, 52)
		part(boundaries, "West", Vector3.new(2, 20, 1204), Vector3.new(-601, 90, 0), wall)
		part(boundaries, "East", Vector3.new(2, 20, 1204), Vector3.new(601, 90, 0), wall)
		part(boundaries, "South", Vector3.new(1200, 20, 2), Vector3.new(0, 90, -601), wall)
		part(boundaries, "NorthLeft", Vector3.new(594, 20, 2), Vector3.new(-303, 90, 601), wall)
		part(boundaries, "NorthRight", Vector3.new(594, 20, 2), Vector3.new(303, 90, 601), wall)
		local spawn = part(
			root,
			"RoundSpawn",
			Vector3.new(6, 0.15, 6),
			Vector3.new(0, 80.075, -500),
			Color3.fromRGB(158, 176, 150)
		)
		spawn.CFrame *= CFrame.Angles(0, math.pi, 0)
		spawn.CanCollide = false
		spawn.CanTouch = false
		spawn.CanQuery = false
		spawn:SetAttribute("spawn_id", "solo_start")
		CollectionService:AddTag(spawn, "corn_spawn")
		noCorn(zones, "StartClearing", Vector3.new(20, 10, 20), Vector3.new(0, 85, -500))
		local allSlots: { Part } = {}
		for row = 1, 5 do
			for column = 1, 3 do
				local id = string.format("solo_slot_%02d", #allSlots + 1)
				local slot = part(
					slots,
					id,
					Vector3.new(6, 0.12, 6),
					Vector3.new((column - 2) * 360, 80.06, (row - 3) * 180),
					Color3.fromRGB(119, 123, 87)
				)
				slot.CanCollide = false
				slot.CanTouch = false
				slot.CanQuery = false
				slot:SetAttribute("slot_id", id)
				CollectionService:AddTag(slot, "corn_key_slot")
				table.insert(allSlots, slot)
			end
		end
		for _, index in { 3, 8, 13 } do
			local barrel = part(
				props,
				"LookoutBarrel",
				Vector3.new(4, 3.2, 3.2),
				allSlots[index].Position + Vector3.new(4, 1.94, 0),
				Color3.fromRGB(111, 78, 48)
			)
			barrel.CFrame *= CFrame.Angles(0, 0, math.pi / 2)
			barrel.Shape = Enum.PartType.Cylinder
			barrel.Material = Enum.Material.Wood
			CollectionService:AddTag(barrel, "corn_barrel")
		end
		house(props, "HouseWest", Vector3.new(-180, 80, -190))
		house(props, "HouseEast", Vector3.new(210, 80, 120))
		house(props, "HouseNorthWest", Vector3.new(-420, 80, 240))
		local scarecrow = Instance.new("Model")
		scarecrow.Name = "ScarecrowMarker"
		scarecrow:SetAttribute("role", "visual_scarecrow_placeholder")
		scarecrow.Parent = props
		part(
			scarecrow,
			"Pole",
			Vector3.new(0.8, 20, 0.8),
			Vector3.new(12, 90, 12),
			Color3.fromRGB(77, 60, 42)
		)
		part(
			scarecrow,
			"Body",
			Vector3.new(4, 8, 2),
			Vector3.new(12, 94, 12),
			Color3.fromRGB(35, 39, 30)
		)
		part(
			scarecrow,
			"Arms",
			Vector3.new(14, 1, 1),
			Vector3.new(12, 97, 12),
			Color3.fromRGB(35, 39, 30)
		)
		part(
			scarecrow,
			"Head",
			Vector3.new(2.5, 2.5, 2.5),
			Vector3.new(12, 99.5, 12),
			Color3.fromRGB(89, 83, 54)
		)
		local gate = Instance.new("Model")
		gate.Name = "EscapeGate"
		gate:SetAttribute("gate_id", "solo_gate")
		gate.Parent = root
		CollectionService:AddTag(gate, "corn_gate")
		part(
			gate,
			"Door",
			Vector3.new(12, 18, 2),
			Vector3.new(0, 89, 601),
			Color3.fromRGB(114, 75, 49)
		).CanTouch =
			false
		zone(gate, "InteractionAnchor", Vector3.new(0.1, 0.1, 0.1), Vector3.new(0, 83, 599.7))
		local exit = zone(gate, "ExitZone", Vector3.new(12, 22, 8), Vector3.new(0, 91, 610))
		exit:SetAttribute("gate_id", "solo_gate")
		CollectionService:AddTag(exit, "corn_exit")
		noCorn(gate, "ApproachClearance", Vector3.new(20, 10, 28), Vector3.new(0, 85, 600))
		part(gate, "Header", Vector3.new(12, 2, 2), Vector3.new(0, 99, 601), wall)
		local apron = part(
			gate,
			"ExitGround",
			Vector3.new(20, 2, 20),
			Vector3.new(0, 79, 610),
			Color3.fromRGB(91, 97, 70)
		)
		apron.Material = Enum.Material.Ground
		gate.PrimaryPart = gate.Door :: BasePart
		root.Parent = Workspace
		MapAuthoring.EnsureCornerSpawns(root)
		MapAuthoring.RebuildOverview(root)
		local count = MapAuthoring.Preview(root, spawn.Position)
		root:SetAttribute("EditorCornCount", count)
		Selection:Set({ spawn })
	end)
	if not ok then
		root:Destroy()
		error(tostring(err))
	end
	print(
		"CornMap installed: 1200 x 1200 studs, 15 key slots, gate, 3 barrels, 3 decorative houses"
	)
	return root
end
return MapAuthoring
