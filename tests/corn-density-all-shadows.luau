-- Production methods with real Lune geometry and publication-aware clone proxies.
-- Native Studio checks still cover rendering, EditableMesh and runtime timing.
local adapter = require("./scene-adapter")
local fs, r, I = adapter.fs, adapter.r, adapter.I
local CF, V3 = r.CFrame, r.Vector3
local assertions = 0
local function check(condition, message)
	assert(condition, message)
	assertions += 1
end
local function loadSource(path, env)
	local source = fs.readFile(path)
	if path == "src/client/Controllers/CornShadowController.luau" then
		-- Lune fixture parts have no coupled Position getter.
		source = source
			:gsub("part%.Position", "part.CFrame.Position")
			:gsub("root%.Position", "root.CFrame.Position")
	end
	local fn = assert(loadstring(source, path))
	setfenv(fn, setmetatable(env, { __index = getfenv() }))
	return fn()
end
local Layout = loadSource("src/shared/Game/CornLayout.luau", {
	CFrame = CF,
	Vector3 = V3,
	Vector2 = r.Vector2,
})
local function child(parent, class, name)
	local item = I.new(class)
	item.Name, item.Parent = name, parent
	return item
end
local world = I.new("Workspace")
local map = child(world, "Model", "CornMap")
map:SetAttribute("corn_project_id", "children_of_corn")
local ground = child(map, "Part", "Ground")
ground.Size, ground.CFrame = V3.new(630, 2, 630), CF.new(0, -1, 0)
local field = child(map, "Part", "FieldZone")
field.Size, field.CFrame = V3.new(630, 10, 630), CF.new(0, 5, 0)
local spacing = 3 / math.sqrt(1.3)
for _, variant in { "A", "B" } do
	map:SetAttribute("HarvestArtVariant", variant)
	check(
		Layout.SpacingFor(field) == (if variant == "B" then spacing else 3),
		"Variant spacing changed"
	)
end
check(math.abs((3 / spacing) ^ 2 - 1.3) < 1e-12, "Density factor is not thirty percent")
map:SetAttribute("HarvestArtVariant", "A")
local aMin, aMax, aRowMin, aRowMax = Layout.GetCellBounds(field)
local aCount = (aMax - aMin + 1) * (aRowMax - aRowMin + 1)
local aPositions = {}
for column = -20, 20 do
	for row = -20, 20 do
		local hashX = (column * 92837111 + row * 689287499 + 817) % 104729
		local hashZ = (column * 19349663 + row * 83492791 + 817) % 104729
		local stagger = if row % 2 == 0 then -0.45 else 0.45
		local expected = V3.new(
			column * 3 + stagger + (hashX / 104729 - 0.5) * 0.36,
			0,
			row * 3 + (hashZ / 104729 - 0.5) * 0.36
		)
		check(
			(Layout.BaseCellPosition(field, column, row) - expected).Magnitude < 0.00001,
			"A cell layout changed"
		)
		aPositions[column .. ":" .. row] = Layout.CellPosition(field, column, row)
	end
end
map:SetAttribute("HarvestArtVariant", "B")
local bMin, bMax, bRowMin, bRowMax = Layout.GetCellBounds(field)
local bCount = (bMax - bMin + 1) * (bRowMax - bRowMin + 1)
check(aCount == 44521 and bCount == 57121, "Whole-field candidate grid count changed")
check(
	bCount > aCount * 1.28 and bCount < aCount * 1.32,
	"Finite field grid did not gain expected density"
)
for column = -20, 20 do
	for row = -20, 20 do
		local point = Layout.CellPosition(field, column, row)
		local original = aPositions[column .. ":" .. row]
		check(
			(point - original * (spacing / 3)).Magnitude < 0.00002,
			"B positions do not use the same denser grid"
		)
		check(point == Layout.CellPosition(field, column, row), "Density introduced nondeterminism")
	end
end
for _, mutation in
	{
		function()
			map:SetAttribute("corn_project_id", "foreign")
		end,
		function()
			map.Name = "OtherMap"
		end,
		function()
			field.Name = "OtherField"
		end,
		function()
			field.Parent = nil
		end,
	}
do
	mutation()
	check(Layout.SpacingFor(field) == 3, "Foreign geometry received the B density")
	map.Name, field.Name, field.Parent = "CornMap", "FieldZone", map
	map:SetAttribute("corn_project_id", "children_of_corn")
end
local masks = child(map, "Folder", "NoCornZones")
local mask = child(masks, "Part", "Trail")
mask.Size, mask.CFrame = V3.new(4, 0.08, 30), CF.identity
local exclusion = Layout.ReadExclusions(map, field)
check(Layout.IsExcluded(V3.new(3.49, 0, 0), exclusion), "Leaf clearance padding shrank")
check(not Layout.IsExcluded(V3.new(3.51, 0, 0), exclusion), "Trail padding was widened")
masks:Destroy()

local storage = I.new("ReplicatedStorage")
local shared = child(storage, "Folder", "GameShared")
local modules = child(shared, "Folder", "Game")
child(modules, "ModuleScript", "CornLayout")
child(modules, "ModuleScript", "CornAppearance")
local art = child(storage, "Folder", "CornRuntimeArt")
art:SetAttribute("CornRuntimeArtOwned", true)
art:SetAttribute("corn_project_id", "children_of_corn")
local template = child(art, "MeshPart", "CornPlantTemplate")
template:SetAttribute("CornPlantTemplateOwned", true)
template.Size, template.CFrame, template.PivotOffset = V3.new(1, 8, 1), CF.new(0, 4, 0), CF.identity
local appearance = {
	DetailedNearChunkLimit = 4,
	DetailedNearPlantLimit = 576,
	DetailedTemplates = function()
		return { Near = { template }, Mid = { template }, Far = { template } }
	end,
}
local connections, disconnections = 0, 0
local run = {
	IsStudio = function()
		return true
	end,
	Heartbeat = {
		Connect = function()
			connections += 1
			return {
				Disconnect = function()
					disconnections += 1
				end,
			}
		end,
	},
}
local character = child(nil, "Model", "Character")
local humanoid = child(character, "Humanoid", "Humanoid")
humanoid.Health = 100
local root = child(character, "Part", "HumanoidRootPart")
root.CFrame = CF.new(0, 3, 0)
local services = {
	Workspace = world,
	ReplicatedStorage = storage,
	RunService = run,
	Players = { LocalPlayer = { Character = character } },
}
local env = {
	game = {
		GetService = function(_, name)
			return services[name]
		end,
	},
	Instance = I,
	CFrame = CF,
	Vector3 = V3,
	Enum = r.Enum,
	os = {
		clock = function()
			return 0
		end,
	},
	require = function(module)
		return if module.Name == "CornAppearance" then appearance else Layout
	end,
}
local Near = loadSource("src/client/Controllers/CornController.luau", env)
local Backdrop = loadSource("src/client/Controllers/CornBackdropController.luau", env)
local Shadow = loadSource("src/client/Controllers/CornShadowController.luau", env)
for _, variant in { "A", "B" } do
	map:SetAttribute("HarvestArtVariant", variant)
	local expectedSpacing = if variant == "B" then spacing else 3
	local group = child(map, "Folder", "CornClientPlants")
	group:SetAttribute("CornClientRendererOwned", true)
	group:SetAttribute("corn_project_id", "children_of_corn")
	local near = setmetatable({
		_map = map,
		_field = field,
		_folder = group,
		_chunks = {},
		_plantCount = 0,
		_detailed = variant == "B",
		_appearance = appearance,
		_resolveInputs = function()
			return true
		end,
		_bindOverview = function() end,
		_elevatedView = function()
			return false
		end,
		_updateOverview = function() end,
		_markOverviewChunk = function() end,
	}, { __index = Near })
	near:_reconcile({ Position = V3.new(0, 3, 0) })
	check(near._chunks["0:0"] ~= nil, "Renderer lost the root chunk")
	for _, chunk in near._chunks do
		check(
			chunk.Folder:GetAttribute("DetailStride") == chunk.Lod * expectedSpacing,
			"Chunk stride does not match density"
		)
	end
	group:Destroy()
	local far = setmetatable({}, { __index = Backdrop })
	far:Init({
		Config = { Environment = "DEV", Game = { SessionMode = "team_local" } },
		Controllers = {
			CornController = {
				UseBackdropReady = function()
					return true
				end,
			},
		},
	})
	check(far:_resolveInputs(), "Backdrop could not bind the density grid")
	check(
		far._folder:GetAttribute("DetailStride") == 2 * expectedSpacing,
		"Backdrop stride does not match density"
	)
	check(
		far._minColumn % 2 == 0 and far._maxColumn % 2 == 0,
		"Backdrop grid lost its even-cell alignment"
	)
	far:Destroy()
end
local function cloneProxy(expected, initial)
	local childPart = {
		CastShadow = initial,
		SetAttribute = function() end,
		IsA = function(_, class)
			return class == "BasePart" or class == "Part"
		end,
	}
	local values = {
		CastShadow = initial,
		Size = V3.new(1, 10, 1),
		CFrame = CF.new(0, 5, 0),
		PivotOffset = CF.identity,
	}
	local methods = {
		IsA = function(_, class)
			return class == "BasePart" or class == "MeshPart"
		end,
		GetDescendants = function()
			return { childPart }
		end,
		SetAttribute = function() end,
		GetPivot = function()
			return values.CFrame
		end,
		PivotTo = function(_, frame)
			values.CFrame = frame
		end,
	}
	local object = setmetatable({}, {
		__index = function(_, key)
			return methods[key] or values[key]
		end,
		__newindex = function(_, key, value)
			if key == "Parent" then
				check(values.CastShadow == expected, "Plant published with the wrong shadow flag")
				if expected then
					check(childPart.CastShadow, "A child part was published without shadows")
				end
				values.published = true
			end
			values[key] = value
		end,
	})
	return object, values, childPart
end
local function cloneSource(expected, initial)
	local clones = {}
	return {
		Clone = function()
			local object, values, leaf = cloneProxy(expected, initial)
			table.insert(clones, { object = object, values = values, leaf = leaf })
			return object
		end,
	},
		clones
end
for _, variant in { "A", "B" } do
	map:SetAttribute("HarvestArtVariant", variant)
	for _, lod in { 1, 2, 3 } do
		local detailed = variant == "B"
		local source, clones = cloneSource(detailed, false)
		local chunk = {
			Alive = true,
			Lod = lod,
			ArtLod = lod,
			Column = 0,
			Row = 0,
			MinColumn = 0,
			MaxColumn = 0,
			MaxRow = 0,
			Count = 0,
			Folder = {},
		}
		local near = setmetatable({
			_field = field,
			_template = source,
			_detailed = detailed,
			_detailedTemplates = { Near = { source }, Mid = { source }, Far = { source } },
			_appearance = {
				Variety = function()
					return 1
				end,
				DetailedPivot = function(plant, point, yaw)
					return Layout.PivotForPlant(plant, point, yaw)
				end,
			},
			_exclusions = { Boxes = {}, Circles = {} },
			_queue = { chunk },
			_plantCount = 0,
			_markOverviewChunk = function() end,
			_updateOverview = function() end,
		}, { __index = Near })
		near:_createBatch()
		check(
			#clones == 1 and clones[1].values.published and near._plantCount == 1,
			"Near clone did not publish exactly once"
		)
	end
	local source, clones = cloneSource(variant == "B", false)
	local group = child(map, "Folder", "CornClientBackdrop")
	group:SetAttribute("CornClientBackdropOwned", true)
	group:SetAttribute("corn_project_id", "children_of_corn")
	local far = setmetatable({
		_folder = group,
		_map = map,
		_field = field,
		_template = source,
		_detailed = variant == "B",
		_detailedTemplates = { Far = { source } },
		_appearance = {
			Variety = function()
				return 1
			end,
			DetailedPivot = function(plant, point, yaw)
				return Layout.PivotForPlant(plant, point, yaw)
			end,
		},
		_exclusions = { Boxes = {}, Circles = {} },
		_fieldFrame = field.CFrame,
		_fieldSize = field.Size,
		_minColumn = 0,
		_maxColumn = 0,
		_column = 0,
		_row = 0,
		_maxRow = 0,
		_epoch = 0,
		_count = 0,
		_fieldYaw = 0,
		_clock = function()
			return 0
		end,
		_publish = function()
			return true
		end,
	}, { __index = Backdrop })
	far:_buildStep()
	check(
		#clones == 1 and clones[1].values.published and far._count == 1,
		"Far clone did not publish exactly once"
	)
	group:Destroy()
end

local folder = child(map, "Folder", "CornClientPlants")
folder:SetAttribute("CornClientRendererOwned", true)
folder:SetAttribute("corn_project_id", "children_of_corn")
local chunk = child(folder, "Folder", "Chunk_0:0")
local plant = child(chunk, "MeshPart", "Corn")
plant:SetAttribute("CornPlantTemplateOwned", true)
plant.Size, plant.CFrame = V3.new(2, 8, 2), CF.new(2, 4, 0)
plant.Anchored, plant.CanCollide, plant.CanTouch, plant.CanQuery = true, false, false, false
plant.CastShadow = false
plant.LocalTransparencyModifier = 0
plant.MeshId, plant.TextureID = "fixture-mesh", "fixture-texture"
local renderer = {
	_enabled = true,
	_map = map,
	_field = field,
	_folder = folder,
	_chunks = { ["0:0"] = { Alive = true, Lod = 1, Folder = chunk } },
}
local function shadowController()
	local controller = setmetatable({}, { __index = Shadow })
	controller:Init({
		Config = { Environment = "DEV", Game = { SessionMode = "team_local" } },
		Controllers = { CornController = renderer, CornWindController = { _layers = {} } },
	})
	return controller
end
map:SetAttribute("HarvestArtVariant", "B")
local bShadow = shadowController()
bShadow:Start({})
check(not bShadow._enabled and connections == 0, "B bounded controller connected")
check(bShadow:_binding() == nil, "B binding accepted the old thirty-six-stud chunks")
bShadow:_reconcile()
check(not plant.CastShadow and bShadow._lastScanned == 0, "B bounded controller changed corn")
bShadow:Destroy()
map:SetAttribute("HarvestArtVariant", "A")
local aShadow = shadowController()
aShadow:Start({})
check(aShadow._enabled and connections == 1, "A controller no longer starts")
aShadow:_reconcile()
check(plant.CastShadow and aShadow._lastWrites == 1, "A foreground casting behavior changed")
root.CFrame = CF.new(100, 3, 0)
aShadow:_reconcile()
check(not plant.CastShadow, "A movement did not restore its own shadow")
root.CFrame = CF.new(0, 3, 0)
aShadow:_reconcile()
check(plant.CastShadow, "A returning player did not reacquire shadow")
aShadow:Destroy()
check(not plant.CastShadow and disconnections == 1, "A cleanup changed")
local bounded = shadowController()
local extra = {}
for column = -9, 9 do
	for row = -9, 9 do
		local copy = plant:Clone()
		copy.CFrame, copy.Parent = CF.new(column, 4, row), chunk
		table.insert(extra, copy)
	end
end
local existing = plant:Clone()
existing.CastShadow, existing.Parent = true, chunk
bounded:_reconcile()
local selected = 0
for _ in bounded._active do
	selected += 1
end
check(selected == 256 and bounded._lastScanned <= 1296, "A caster or scan budget changed")
check(bounded._active[existing] == nil and existing.CastShadow, "A claimed a pre-existing caster")
local selectedPart = next(bounded._active)
selectedPart.Size = V3.new(3, 8, 2)
bounded:_reconcile()
check(bounded._retired[selectedPart] and selectedPart.CastShadow, "A overwrote a foreign edit")
bounded:Destroy()
check(selectedPart.CastShadow and existing.CastShadow, "A cleanup reset foreign casters")
for _, copy in extra do
	if copy ~= selectedPart then
		check(not copy.CastShadow, "A cleanup leaked an owned caster")
	end
end
print(
	string.format(
		"corn-density-all-shadows PASS (%d assertions; A %d / B %d candidate cells)",
		assertions,
		aCount,
		bCount
	)
)
