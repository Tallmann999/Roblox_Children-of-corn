--!strict
-- Additive art only. Authored transforms, collision, textures and Terrain stay intact.
local storage = game:GetService("ReplicatedStorage")
local world = game:GetService("Workspace")
local Geometry = require(
	storage:WaitForChild("GameShared"):WaitForChild("Game"):WaitForChild("HarvestArtGeometry")
)
local Pose =
	require(storage:WaitForChild("GameShared"):WaitForChild("Game"):WaitForChild("MonsterPose"))
local PROJECT = "children_of_corn"
local OWNER = "harvest_warden_v1"
local HOUSES = { "HouseWest", "HouseEast", "HouseNorthWest" }
local SOURCE_NAMES = { "SM_Bld_Barn_03", "SM_Bld_Barn_03_Shutter_01", "SM_Bld_Barn_03_Shutter_02" }
local HarvestWorld = {}

local function visibleBranch(branch: any, variant: string): boolean
	return branch == "Common" or branch == variant
end

local function owned(item: Instance)
	return item:GetAttribute("corn_project_id") == PROJECT
		and item:GetAttribute("HarvestGeometryOwner") == OWNER
end

local function stamp(item: Instance)
	item:SetAttribute("corn_project_id", PROJECT)
	item:SetAttribute("HarvestGeometryOwner", OWNER)
end

local function seal(root: Instance)
	for _, item in { root, table.unpack(root:GetDescendants()) } do
		item:SetAttribute("HarvestExpectedChildren", #item:GetChildren())
		item:SetAttribute("HarvestExpectedName", item.Name)
	end
end

local function equal(a: any, b: any): boolean
	if typeof(a) == "CFrame" and typeof(b) == "CFrame" then
		local left, right = { a:GetComponents() }, { b:GetComponents() }
		for index, value in left do
			if math.abs(value - right[index]) > 0.0001 then
				return false
			end
		end
		return true
	elseif typeof(a) == "Vector3" and typeof(b) == "Vector3" then
		return (a - b).Magnitude < 0.0001
	end
	return a == b
end

local function mapBinding(): (Model, Folder, BasePart, BasePart)
	local map = world:FindFirstChild("CornMap")
	assert(
		map
			and map:IsA("Model")
			and map:GetAttribute("corn_project_id") == PROJECT
			and not world:FindFirstChild("Asmr_Base")
			and not world:FindFirstChild("ASMR_Models"),
		"Harvest art requires the Children_of_corn map"
	)
	local props, ground, field =
		map:FindFirstChild("Props"), map:FindFirstChild("Ground"), map:FindFirstChild("FieldZone")
	assert(
		props
			and props:IsA("Folder")
			and ground
			and ground:IsA("BasePart")
			and field
			and field:IsA("BasePart"),
		"Harvest map bindings missing"
	)
	assert(
		ground.Size == Vector3.new(630, 2, 630) and field.Size == Vector3.new(630, 10, 630),
		"Harvest art requires the accepted 630 field"
	)
	assert(
		ground.CFrame.UpVector:Dot(Vector3.yAxis) > 0.9999,
		"Harvest ground must remain horizontal"
	)
	return map, props, ground, field
end

local function barnSources(props: Folder): { any }
	local result = {}
	for _, houseName in HOUSES do
		local house = props:FindFirstChild(houseName)
		assert(
			house
				and house:IsA("Model")
				and house:GetAttribute("CornFarmAssetOwned") == true
				and house:GetAttribute("corn_project_id") == PROJECT
				and house:GetAttribute("AssetKey") == "SM_Bld_Barn_03",
			"Unknown original barn: " .. houseName
		)
		for index, name in SOURCE_NAMES do
			local part = house:FindFirstChild(name)
			assert(
				part
					and part:IsA("MeshPart")
					and part:GetAttribute("CornFarmMeshOwned") == true
					and part:GetAttribute("corn_project_id") == PROJECT
					and part:GetAttribute("AssetKey") == "SM_Bld_Barn_03"
					and part:GetAttribute("MeshIndex") == index,
				"Unknown original barn mesh: " .. name
			)
			table.insert(result, {
				Part = part,
				House = houseName,
				Name = name,
				Frame = part.CFrame,
				Size = part.Size,
			})
		end
	end
	return result
end

local function sourceFor(props: Folder, item: Instance): MeshPart
	local house = props:FindFirstChild(item:GetAttribute("HarvestSourceHouse"))
	local source = house and house:FindFirstChild(item:GetAttribute("HarvestSourceName"))
	assert(
		source
			and source:IsA("MeshPart")
			and source:GetAttribute("CornFarmMeshOwned") == true
			and source:GetAttribute("corn_project_id") == PROJECT
			and equal(source.CFrame, item:GetAttribute("HarvestSourceFrame"))
			and equal(source.Size, item:GetAttribute("HarvestSourceSize")),
		"Harvest original barn binding changed; author work preserved"
	)
	return source
end

local function freezePart(part: BasePart, branch: string)
	stamp(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part:SetAttribute("HarvestBranch", branch)
	part:SetAttribute("HarvestPlacedFrame", part.CFrame)
	part:SetAttribute("HarvestPlacedSize", part.Size)
	part:SetAttribute("HarvestVisibleTransparency", part.Transparency)
	part:SetAttribute("HarvestTexture", if part:IsA("MeshPart") then part.TextureID else "")
	part:SetAttribute("HarvestColor", part.Color)
	part:SetAttribute("HarvestMaterial", part.Material.Name)
	part:SetAttribute("HarvestCastShadow", part.CastShadow)
end

local function validateDecor(root: Instance, props: Folder, variant: string)
	assert(
		root:IsA("Folder") and owned(root) and root:GetAttribute("HarvestWorldVersion") == 1,
		"Foreign HarvestDecor preserved"
	)
	assert(
		root:GetAttribute("HarvestAppliedVariant") == variant,
		"Harvest variant metadata differs"
	)
	assert(
		#root:GetChildren() == root:GetAttribute("HarvestExpectedChildren")
			and root.Name == root:GetAttribute("HarvestExpectedName"),
		"Harvest root topology edit preserved"
	)
	for _, item in root:GetDescendants() do
		assert(owned(item), "Foreign child inside HarvestDecor preserved: " .. item:GetFullName())
		assert(
			#item:GetChildren() == item:GetAttribute("HarvestExpectedChildren")
				and item.Name == item:GetAttribute("HarvestExpectedName"),
			"Harvest decor topology edit preserved"
		)
		if item:IsA("BasePart") then
			local visible = item:GetAttribute("HarvestVisibleTransparency")
			local expected = if visibleBranch(item:GetAttribute("HarvestBranch"), variant)
				then visible
				else 1
			assert(
				equal(item.CFrame, item:GetAttribute("HarvestPlacedFrame"))
					and equal(item.Size, item:GetAttribute("HarvestPlacedSize"))
					and item.Transparency == expected
					and item.Anchored
					and not item.CanCollide
					and not item.CanTouch
					and not item.CanQuery
					and item.Color == item:GetAttribute("HarvestColor")
					and item.Material.Name == item:GetAttribute("HarvestMaterial")
					and item.CastShadow == item:GetAttribute("HarvestCastShadow"),
				"Harvest authored decor edit preserved: " .. item:GetFullName()
			)
			if item:IsA("MeshPart") then
				assert(
					type(item:GetAttribute("HarvestMeshKey")) == "string"
						and item.TextureID == item:GetAttribute("HarvestTexture"),
					"Harvest mesh/texture edit preserved"
				)
			end
			if item:GetAttribute("HarvestSourceName") then
				local source = sourceFor(props, item)
				assert(
					source.Transparency
						== (
							if variant == "B"
								then 1
								else item:GetAttribute("HarvestSourceTransparency")
						),
					"Harvest barn appearance edit preserved"
				)
			end
		elseif item:IsA("Texture") then
			local expected = if visibleBranch(item:GetAttribute("HarvestBranch"), variant)
				then item:GetAttribute("HarvestVisibleTransparency")
				else 1
			assert(
				item.Texture == item:GetAttribute("HarvestTexture")
					and item.Transparency == expected
					and item.Face == Enum.NormalId.Top
					and item.StudsPerTileU == item:GetAttribute("HarvestTileSize")
					and item.StudsPerTileV == item:GetAttribute("HarvestTileSize"),
				"Harvest ground texture edit preserved"
			)
		else
			assert(
				item:IsA("Model") or item:IsA("Folder"),
				"Foreign HarvestDecor instance preserved"
			)
		end
	end
end

local function cloneAsset(
	assetKey: string,
	name: string,
	frame: CFrame,
	parent: Instance,
	branch: string,
	scale: number?
): Model
	local template = Geometry.Template(assetKey)
	assert(template and template:IsA("Model"), "Harvest model template required: " .. assetKey)
	local model = template:Clone()
	model.Name = name
	stamp(model)
	model:SetAttribute("HarvestAssetKey", assetKey)
	-- Template parts carry baked global-to-asset centers; no importer pivot assumption.
	for _, part in model:GetDescendants() do
		assert(part:IsA("MeshPart"), "Harvest template contains unexpected hierarchy")
		part.CFrame = frame * CFrame.new(part.CFrame.Position * (scale or 1)) * part.CFrame.Rotation
		part.Size *= scale or 1
		freezePart(part, branch)
	end
	model.Parent = parent
	return model
end

local function homeBinding(props: Folder): (Model, { BasePart })
	local home = props:FindFirstChild("ScarecrowMarker")
	assert(
		home and home:IsA("Model") and home:HasTag("corn_monster_home"),
		"Harvest monster home binding missing"
	)
	local parts = {}
	for _, name in { "Head", "Arms", "Body" } do
		local part = home:FindFirstChild(name)
		assert(part and part.ClassName == "Part", "Unknown original home marker part: " .. name)
		table.insert(parts, part :: BasePart)
	end
	return home, parts
end

local function prepareHome(props: Folder, ground: BasePart): (Folder, boolean, { BasePart })
	local home, originals = homeBinding(props)
	local old = home:FindFirstChild("HarvestWardenHome")
	if old then
		assert(old:IsA("Folder") and #old:GetChildren() == 2, "Foreign HarvestWardenHome preserved")
		local variant = old:GetAttribute("HarvestAppliedVariant")
		validateDecor(old, props, variant)
		assert(
			old:FindFirstChild("Classic") and old:FindFirstChild("Detailed"),
			"Incomplete home visual variants"
		)
		for _, part in originals do
			assert(
				part.Transparency == 1
					and equal(part.CFrame, old:GetAttribute(part.Name .. "SourceFrame"))
					and equal(part.Size, old:GetAttribute(part.Name .. "SourceSize")),
				"Original home marker edit preserved"
			)
		end
		return old :: Folder, false, originals
	end
	local root = Instance.new("Folder")
	root.Name = "HarvestWardenHome"
	stamp(root)
	root:SetAttribute("HarvestWorldVersion", 1)
	local head = originals[1]
	local frame = CFrame.new(
		head.CFrame.Position.X,
		ground.CFrame.Position.Y + ground.Size.Y / 2,
		head.CFrame.Position.Z
	) * CFrame.Angles(0, math.pi, 0)
	local ok, problem = pcall(function()
		for _, part in originals do
			assert(part.Transparency == 0, "Original home marker appearance differs")
			root:SetAttribute(part.Name .. "SourceFrame", part.CFrame)
			root:SetAttribute(part.Name .. "SourceSize", part.Size)
			root:SetAttribute(part.Name .. "SourceTransparency", part.Transparency)
		end
		cloneAsset("WardenClassic", "Classic", frame, root, "A", Pose.WardenScale)
		cloneAsset("WardenDetailed", "Detailed", frame, root, "B", Pose.WardenScale)
		seal(root)
	end)
	if not ok then
		root:Destroy()
		error("Harvest home preparation failed: " .. tostring(problem))
	end
	return root, true, originals
end

local function safePlacement(map: Model, frame: CFrame, radius: number)
	for _, folderName in { "KeySlots", "CornerSpawns" } do
		local folder = assert(map:FindFirstChild(folderName), "Harvest clearance folder missing")
		for _, part in folder:GetChildren() do
			if part:IsA("BasePart") then
				local delta = part.CFrame.Position - frame.Position
				assert(
					Vector3.new(delta.X, 0, delta.Z).Magnitude > radius + 10,
					"Harvest decor would cover a slot or start"
				)
			end
		end
	end
	local gate = assert(map:FindFirstChild("EscapeGate"), "Harvest gate missing")
	local anchor = gate:FindFirstChild("InteractionAnchor")
	assert(anchor and anchor:IsA("BasePart"), "Harvest gate interaction anchor missing")
	local delta = anchor.CFrame.Position - frame.Position
	assert(
		Vector3.new(delta.X, 0, delta.Z).Magnitude > radius + 18,
		"Harvest decor would cover gate/exit"
	)
end

local function groundTexture(assetKey: string): string
	local template = Geometry.Template(assetKey)
	local part = if template:IsA("MeshPart")
		then template
		else template:FindFirstChildWhichIsA("MeshPart", true)
	assert(part and part.TextureID ~= "", "Harvest ground texture not uploaded")
	return part.TextureID
end

local function layoutBinding(root: Instance, props: Folder, ground: BasePart)
	local roadFolder = props:FindFirstChild("VillageRoad")
	local road = roadFolder and roadFolder:FindFirstChild("RoadSurface")
	assert(
		road and road:IsA("BasePart") and road:GetAttribute("CornRoadExitOwned") == true,
		"Original road binding missing"
	)
	assert(
		equal(ground.CFrame, root:GetAttribute("HarvestGroundFrame"))
			and equal(ground.Size, root:GetAttribute("HarvestGroundSize"))
			and equal(road.CFrame, root:GetAttribute("HarvestRoadFrame"))
			and equal(road.Size, root:GetAttribute("HarvestRoadSize")),
		"Author ground or road changed; Harvest overlay preserved"
	)
end

local function plane(
	parent: Folder,
	name: string,
	frame: CFrame,
	size: Vector3,
	textureId: string,
	tile: number
)
	local part = Instance.new("Part")
	part.Name = name
	part.CFrame = frame
	part.Size = size
	part.Color = Color3.fromRGB(104, 86, 66)
	part.Material = Enum.Material.Ground
	part.CastShadow = false
	freezePart(part, "B")
	local texture = Instance.new("Texture")
	texture.Name = "HarvestSurface"
	stamp(texture)
	texture.Face = Enum.NormalId.Top
	texture.Texture = textureId
	texture.StudsPerTileU = tile
	texture.StudsPerTileV = tile
	texture:SetAttribute("HarvestTexture", textureId)
	texture:SetAttribute("HarvestTileSize", tile)
	texture:SetAttribute("HarvestBranch", "B")
	texture:SetAttribute("HarvestVisibleTransparency", texture.Transparency)
	texture.Parent = part
	part.Parent = parent
end

local function build(map: Model, props: Folder, ground: BasePart, sources: { any }): Folder
	local root = Instance.new("Folder")
	root.Name = "HarvestDecor"
	stamp(root)
	root:SetAttribute("HarvestWorldVersion", 1)
	root:SetAttribute("HarvestGroundFrame", ground.CFrame)
	root:SetAttribute("HarvestGroundSize", ground.Size)
	local common, detailed = Instance.new("Folder"), Instance.new("Folder")
	common.Name, detailed.Name = "Common", "VariantB"
	stamp(common)
	stamp(detailed)
	common.Parent, detailed.Parent = root, root
	local ok, problem = pcall(function()
		local floorY = ground.CFrame.Position.Y + ground.Size.Y / 2
		local count = 0
		local function decor(key: string, name: string, frame: CFrame, radius: number)
			safePlacement(map, frame, radius)
			cloneAsset(key, name, frame, common, "Common")
			count += 1
		end
		for houseIndex, houseName in HOUSES do
			local shell =
				assert(props:FindFirstChild(houseName)):FindFirstChild("SM_Bld_Barn_03") :: MeshPart
			local frame = CFrame.new(shell.CFrame.Position.X, floorY, shell.CFrame.Position.Z)
				* shell.CFrame.Rotation
			for _, side in { -1, 1 } do
				for index, x in { -6, 6 } do
					local key = "Fence_0"
						.. tostring((houseIndex + index + (if side == 1 then 1 else 0)) % 3 + 1)
					decor(
						key,
						houseName .. "_Fence_" .. tostring(side) .. "_" .. tostring(index),
						frame * CFrame.new(x, 0, side * 12.5),
						6.5
					)
				end
			end
			for index = 1, 5 do
				local x = -15 - index % 2 * 1.8
				local z = (index - 3) * 3.3
				decor(
					"Rock_0" .. index,
					houseName .. "_Rock_" .. index,
					frame * CFrame.new(x, 0, z) * CFrame.Angles(0, index * 1.73, 0),
					1.1
				)
			end
		end
		for _, side in { -1, 1 } do
			for index, z in { -240, -140, -60, 60, 140, 240 } do
				decor(
					"Fence_0" .. tostring(index % 3 + 1),
					"RoadFence_" .. side .. "_" .. index,
					CFrame.new(side * 11.5, floorY, z) * CFrame.Angles(0, math.pi / 2, 0),
					6.5
				)
			end
		end
		root:SetAttribute("HarvestCommonModels", count)
		local barn = Geometry.Template("BarnDark_Open")
		assert(barn:IsA("Model"), "Harvest dark barn template required")
		for _, source in sources do
			assert(source.Part.Transparency == 0, "Original barn transparency has author changes")
			local selected = {}
			local low, high =
				Vector3.new(math.huge, math.huge, math.huge),
				Vector3.new(-math.huge, -math.huge, -math.huge)
			for _, part in barn:GetChildren() do
				assert(
					part:IsA("MeshPart"),
					"Harvest barn template must contain mesh primitives only"
				)
				local info = Geometry.MeshInfo(part:GetAttribute("HarvestMeshKey"))
				local name = info.sourceName:gsub("^HW_Dark_", ""):gsub("_Export$", "")
				if name == source.Name then
					table.insert(selected, part)
					local center, half = part.CFrame.Position, part.Size / 2
					low = Vector3.new(
						math.min(low.X, center.X - half.X),
						math.min(low.Y, center.Y - half.Y),
						math.min(low.Z, center.Z - half.Z)
					)
					high = Vector3.new(
						math.max(high.X, center.X + half.X),
						math.max(high.Y, center.Y + half.Y),
						math.max(high.Z, center.Z + half.Z)
					)
				end
			end
			assert(#selected > 0, "Dark barn source correspondence missing: " .. source.Name)
			local center, size = (low + high) / 2, high - low
			local ratio = source.Size / size
			assert(
				math.abs(ratio.X - 1) < 0.005
					and math.abs(ratio.Y - 1) < 0.005
					and math.abs(ratio.Z - 1) < 0.005,
				"Dark barn dimensions differ from original"
			)
			for index, part in selected do
				local copy = part:Clone()
				copy.Name = source.House .. "_" .. source.Name .. "_" .. index
				copy.CFrame = source.Frame * CFrame.new((part.CFrame.Position - center) * ratio)
				copy.Size = part.Size * ratio
				freezePart(copy, "B")
				copy:SetAttribute("HarvestSourceHouse", source.House)
				copy:SetAttribute("HarvestSourceName", source.Name)
				copy:SetAttribute("HarvestSourceFrame", source.Frame)
				copy:SetAttribute("HarvestSourceSize", source.Size)
				copy:SetAttribute("HarvestSourceTransparency", source.Part.Transparency)
				copy.Parent = detailed
			end
		end
		plane(
			detailed,
			"GroundSurface",
			ground.CFrame * CFrame.new(0, ground.Size.Y / 2 + 0.015, 0),
			Vector3.new(ground.Size.X, 0.02, ground.Size.Z),
			groundTexture("Ground_Tile_8"),
			8
		)
		local road = assert(props:FindFirstChild("VillageRoad")):FindFirstChild("RoadSurface")
		assert(
			road and road:IsA("BasePart") and road:GetAttribute("CornRoadExitOwned") == true,
			"Original road binding missing"
		)
		root:SetAttribute("HarvestRoadFrame", road.CFrame)
		root:SetAttribute("HarvestRoadSize", road.Size)
		plane(
			detailed,
			"RoadSurface",
			road.CFrame * CFrame.new(0, road.Size.Y / 2 + 0.035, 0),
			Vector3.new(road.Size.X, 0.02, road.Size.Z),
			groundTexture("Path_Tile_8"),
			8
		)
		seal(root)
	end)
	if not ok then
		root:Destroy()
		error("Harvest decor preparation failed; original world unchanged: " .. tostring(problem))
	end
	return root
end

-- In manual B the saved scene owns placement and appearance. Geometry remains
-- peer-local, so restore its mesh data without replaying the original layout or
-- comparing transforms with the old installation snapshot.
local function ensureManual(map: Model): any
	local currentMap, props = mapBinding()
	assert(
		currentMap == map and map:GetAttribute("HarvestArtVariant") == "B",
		"Manual Harvest authoring requires the accepted B map"
	)
	barnSources(props)
	local marker = homeBinding(props)
	local root = map:FindFirstChild("HarvestDecor")
	local home = marker:FindFirstChild("HarvestWardenHome")
	assert(
		root and root:IsA("Folder") and owned(root) and home and home:IsA("Folder") and owned(home),
		"Manual Harvest roots missing or foreign"
	)
	local targets = {}
	local parts = 0
	for _, item in map:GetDescendants() do
		if item:GetAttribute("HarvestGeometryOwner") ~= OWNER then
			continue
		end
		assert(owned(item), "Foreign manual Harvest metadata preserved")
		assert(
			item:IsA("Folder") or item:IsA("Model") or item:IsA("BasePart") or item:IsA("Texture"),
			"Unsupported manual Harvest instance preserved: " .. item:GetFullName()
		)
		if item:IsA("BasePart") then
			assert(
				(item.ClassName == "Part" or item:IsA("MeshPart"))
					and item.Anchored
					and not item.CanCollide
					and not item.CanTouch
					and not item.CanQuery,
				"Manual Harvest art must remain anchored decoration"
			)
			parts += 1
			if item:IsA("MeshPart") then
				local key = item:GetAttribute("HarvestMeshKey")
				assert(
					type(key) == "string" and Geometry.MeshInfo(key),
					"Manual Harvest mesh key missing"
				)
				table.insert(targets, { Part = item, Key = key })
			end
		end
	end
	assert(#targets > 0, "Manual Harvest visual meshes missing")
	for _, target in targets do
		assert(
			map.Parent == world
				and target.Part:IsDescendantOf(map)
				and owned(target.Part)
				and map:GetAttribute("BManualAuthoringVersion") == 1
				and map:GetAttribute("HarvestArtVariant") == "B",
			"Manual Harvest binding changed during restoration"
		)
		Geometry.Apply(target.Part, target.Key)
	end
	return {
		variant = "B",
		created = 0,
		changed = 0,
		parts = parts,
		commonModels = root:GetAttribute("HarvestCommonModels") or 0,
	}
end

function HarvestWorld.Ensure(requested: string?): any
	local candidate = world:FindFirstChild("CornMap")
	if
		candidate
		and candidate:IsA("Model")
		and candidate:GetAttribute("BManualAuthoringVersion") == 1
	then
		assert(requested == nil or requested == "B", "Manual B cannot switch art variants")
		return ensureManual(candidate)
	end
	local declared = candidate and candidate:GetAttribute("HarvestArtVariant")
	assert(
		declared == nil or declared == "A" or declared == "B",
		"Unknown authored Harvest variant preserved"
	)
	if
		requested == nil and (not candidate or candidate:GetAttribute("HarvestArtVariant") == nil)
	then
		return { variant = "legacy", created = 0, changed = 0, parts = 0, commonModels = 0 }
	end
	local map, props, ground = mapBinding()
	local variant = requested or map:GetAttribute("HarvestArtVariant")
	if variant == nil then
		return { variant = "legacy", created = 0, changed = 0, parts = 0, commonModels = 0 }
	end
	assert(variant == "A" or variant == "B", "Harvest variant must be A or B")
	local sources = barnSources(props)
	local root = map:FindFirstChild("HarvestDecor")
	local created = root == nil
	local previous = if root then root:GetAttribute("HarvestAppliedVariant") else "A"
	local marker = homeBinding(props)
	assert(
		(root ~= nil) == (marker:FindFirstChild("HarvestWardenHome") ~= nil),
		"Partial Harvest world roots preserved for review"
	)
	if root then
		assert(previous == "A" or previous == "B", "Unknown applied Harvest variant")
		validateDecor(root, props, previous)
		layoutBinding(root, props, ground)
	end
	local homeRoot, homeCreated, homeParts
	local prepared, preparationProblem = pcall(function()
		if not root then
			root = build(map, props, ground, sources)
		end
		layoutBinding(root, props, ground)
		homeRoot, homeCreated, homeParts = prepareHome(props, ground)
		assert(
			homeCreated or homeRoot:GetAttribute("HarvestAppliedVariant") == previous,
			"Harvest home/world variants differ"
		)
		for _, visualRoot in { root, homeRoot } do
			for _, part in visualRoot:GetDescendants() do
				if part:IsA("MeshPart") then
					Geometry.Apply(part, part:GetAttribute("HarvestMeshKey"))
				end
			end
		end
		local currentMap, currentProps, currentGround = mapBinding()
		assert(
			currentMap == map and currentProps == props and currentGround == ground,
			"Harvest world bindings changed during geometry restoration"
		)
		if not created then
			validateDecor(root, props, previous)
			validateDecor(homeRoot, props, previous)
			layoutBinding(root, props, ground)
			for _, part in homeParts do
				assert(
					part.Transparency == 1
						and equal(part.CFrame, homeRoot:GetAttribute(part.Name .. "SourceFrame"))
						and equal(part.Size, homeRoot:GetAttribute(part.Name .. "SourceSize")),
					"Author home changed during local geometry restoration"
				)
			end
			return
		end
		-- EditableMesh allocation yields. Recheck every author binding before publication.
		assert(
			map.Parent == world and not map:FindFirstChild("HarvestDecor"),
			"Harvest root changed while preparing"
		)
		for _, source in sources do
			assert(
				source.Part.Parent == props:FindFirstChild(source.House)
					and equal(source.Part.CFrame, source.Frame)
					and equal(source.Part.Size, source.Size)
					and source.Part.Transparency == 0,
				"Author barn changed during Harvest preparation"
			)
		end
		for _, part in homeParts do
			assert(
				part.Parent == marker
					and part.Transparency == 0
					and equal(part.CFrame, homeRoot:GetAttribute(part.Name .. "SourceFrame"))
					and equal(part.Size, homeRoot:GetAttribute(part.Name .. "SourceSize")),
				"Author home changed during Harvest preparation"
			)
		end
	end)
	if not prepared then
		if created and root then
			root:Destroy()
		end
		if homeCreated and homeRoot then
			homeRoot:Destroy()
		end
		error(
			"Harvest preparation refused; original world unchanged: "
				.. tostring(preparationProblem)
		)
	end
	local changed, parts, journal = 0, 0, {}
	local function set(part: any, value: number)
		if part.Transparency ~= value then
			table.insert(journal, { Part = part, Value = part.Transparency })
			part.Transparency = value
			changed += 1
		end
	end
	local ok, problem = pcall(function()
		for _, visualRoot in { root, homeRoot } do
			for _, item in visualRoot:GetDescendants() do
				if item:IsA("BasePart") then
					parts += 1
					set(
						item,
						if visibleBranch(item:GetAttribute("HarvestBranch"), variant)
							then item:GetAttribute("HarvestVisibleTransparency")
							else 1
					)
					if item:GetAttribute("HarvestSourceName") then
						set(
							sourceFor(props, item),
							if variant == "B"
								then 1
								else item:GetAttribute("HarvestSourceTransparency")
						)
					end
				elseif item:IsA("Texture") then
					set(
						item,
						if visibleBranch(item:GetAttribute("HarvestBranch"), variant)
							then item:GetAttribute("HarvestVisibleTransparency")
							else 1
					)
				end
			end
		end
		for _, part in homeParts do
			set(part, 1)
		end
		root:SetAttribute("HarvestAppliedVariant", variant)
		homeRoot:SetAttribute("HarvestAppliedVariant", variant)
		if created then
			root.Parent = map
			homeRoot.Parent = marker
		end
		map:SetAttribute("HarvestArtVariant", variant)
	end)
	if not ok then
		for index = #journal, 1, -1 do
			journal[index].Part.Transparency = journal[index].Value
		end
		if created then
			root:Destroy()
			homeRoot:Destroy()
		else
			root:SetAttribute("HarvestAppliedVariant", previous)
			homeRoot:SetAttribute("HarvestAppliedVariant", previous)
		end
		error("Harvest appearance transaction rolled back: " .. tostring(problem))
	end
	return {
		variant = variant,
		created = if created then 1 else 0,
		changed = changed,
		parts = parts,
		commonModels = root:GetAttribute("HarvestCommonModels"),
	}
end

return HarvestWorld
