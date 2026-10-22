-- Production layout/renderer/index methods with real Lune geometry.
-- No native rendering, shadows or sustained FPS acceptance is implied.
local adapter = require("./scene-adapter")
local fs, r, I = adapter.fs, adapter.r, adapter.I
local CF, V3 = r.CFrame, r.Vector3
local assertions = 0
local function check(condition, message)
	assert(condition, message)
	assertions += 1
end
local function load(path, env)
	local fn = assert(loadstring(fs.readFile(path), path))
	setfenv(fn, setmetatable(env, { __index = getfenv() }))
	return fn()
end
local Layout =
	load("src/shared/Game/CornLayout.luau", { CFrame = CF, Vector3 = V3, Vector2 = r.Vector2 })
local Appearance = load("src/shared/Game/CornAppearance.luau", { CFrame = CF, Vector3 = V3 })
local function child(parent, class, name)
	local p = I.new(class)
	p.Name, p.Parent = name, parent
	return p
end
local world = I.new("Workspace")
local map = child(world, "Model", "CornMap")
map:SetAttribute("corn_project_id", "children_of_corn")
local field = child(map, "Part", "FieldZone")
field.Size, field.CFrame = V3.new(630, 10, 630), CF.new(0, 5, 0)
local originalSpacing = 3 / math.sqrt(1.3)
local spacing = 3 * (1 / math.sqrt(2.6))
check(math.abs((originalSpacing / spacing) ^ 2 - 2) < 1e-12, "B density did not double")
check(
	math.abs(spacing / originalSpacing - 1 / math.sqrt(2)) < 1e-12,
	"B distances did not shrink uniformly"
)
local aPositions = {}
map:SetAttribute("HarvestArtVariant", "A")
check(Layout.SpacingFor(field) == 3, "A spacing changed")
for c = -30, 30 do
	for row = -30, 30 do
		aPositions[c .. ":" .. row] = Layout.CellPosition(field, c, row)
	end
end
local amin, amax = Layout.GetCellBounds(field)
check((amax - amin + 1) ^ 2 == 44521, "A full grid changed")
map:SetAttribute("HarvestArtVariant", "B")
check(Layout.SpacingFor(field) == spacing, "B spacing not selected")
local bmin, bmax = Layout.GetCellBounds(field)
check((bmax - bmin + 1) ^ 2 == 114921, "B full grid count incorrect")
for c = -30, 30 do
	for row = -30, 30 do
		local point = Layout.CellPosition(field, c, row)
		check(
			(point - aPositions[c .. ":" .. row] * (spacing / 3)).Magnitude < 0.00004,
			"Density applies unevenly across field"
		)
		check(point == Layout.CellPosition(field, c, row), "B cell placement is nondeterministic")
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
	check(Layout.SpacingFor(field) == 3, "Foreign map receives B density")
	map.Name, field.Name, field.Parent = "CornMap", "FieldZone", map
	map:SetAttribute("corn_project_id", "children_of_corn")
end
check(
	Appearance.DetailedNearChunkLimit == 8 and Appearance.DetailedNearPlantLimit == 1152,
	"Highest LOD did not scale with density"
)
check(
	Appearance.DetailedNearChunkLimit * 144 == Appearance.DetailedNearPlantLimit,
	"Detailed LOD limit is inconsistent"
)
local storage = I.new("ReplicatedStorage")
local shared = child(storage, "Folder", "GameShared")
local modules = child(shared, "Folder", "Game")
child(modules, "ModuleScript", "CornLayout")
child(modules, "ModuleScript", "CornAppearance")
local art = child(storage, "Folder", "CornRuntimeArt")
art:SetAttribute("CornRuntimeArtOwned", true)
art:SetAttribute("corn_project_id", "children_of_corn")
local template = child(art, "MeshPart", "CornPlantTemplate")
template.Size, template.CFrame, template.PivotOffset =
	V3.new(2, 10, 2), CF.new(0, 5, 0), CF.identity
template:SetAttribute("CornPlantTemplateOwned", true)
template:SetAttribute("HarvestRootOffset", V3.new(0, 4, 0))
local appearance = table.clone(Appearance)
appearance.DetailedTemplates = function()
	return {
		Near = { template, template, template, template },
		Mid = { template, template, template, template },
		Far = { template, template, template, template },
	}
end
local services = {
	Workspace = world,
	ReplicatedStorage = storage,
	RunService = {
		IsStudio = function()
			return true
		end,
	},
	Players = { LocalPlayer = {} },
}
local env = {
	game = {
		GetService = function(_, name)
			return services[name]
		end,
	},
	CFrame = CF,
	Vector3 = V3,
	Instance = I,
	Enum = r.Enum,
	os = {
		clock = function()
			return 0
		end,
	},
	warn = function() end,
	require = function(module)
		return if module.Name == "CornAppearance" then appearance else Layout
	end,
}
local Near = load("src/client/Controllers/CornController.luau", env)
local Far = load("src/client/Controllers/CornBackdropController.luau", env)
local Wind = load("src/client/Controllers/CornWindController.luau", env)
local function count(t)
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end
local function nearController(variant)
	map:SetAttribute("HarvestArtVariant", variant)
	local group = child(map, "Folder", "CornClientPlants")
	group:SetAttribute("CornClientRendererOwned", true)
	group:SetAttribute("corn_project_id", "children_of_corn")
	return setmetatable({
		_map = map,
		_field = field,
		_folder = group,
		_template = template,
		_chunks = {},
		_plantCount = 0,
		_detailed = variant == "B",
		_appearance = appearance,
		_detailedTemplates = appearance.DetailedTemplates(),
		_resolveInputs = function()
			return true
		end,
		_bindOverview = function() end,
		_elevatedView = function()
			return true
		end,
		_updateOverview = function() end,
		_markOverviewChunk = function() end,
	}, { __index = Near })
end
for _, variant in { "A", "B" } do
	local near = nearController(variant)
	near:_reconcile({ Position = V3.new(0, 3, 0) })
	check(
		(if variant == "B" then count(near._chunks) == 200 else count(near._chunks) <= 100),
		"Chunk cap changed or cuts dense B coverage"
	)
	local detailedChunks = 0
	for _, chunk in near._chunks do
		check(
			chunk.Folder:GetAttribute("DetailStride")
				== chunk.Lod * (if variant == "B" then spacing else 3),
			"Near stride mismatches layout"
		)
		if chunk.ArtLod == 1 then
			detailedChunks += 1
		end
	end
	if variant == "B" then
		check(detailedChunks == 8, "B highest LOD stops before eight nearest chunks")
	end
	near._folder:Destroy()
end
local function clonedPart(clones)
	local values = {
		Size = V3.new(2, 10, 2),
		CFrame = CF.new(0, 5, 0),
		PivotOffset = CF.identity,
		CastShadow = false,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		attrs = { HarvestRootOffset = V3.new(0, 4, 0) },
	}
	local methods = {
		IsA = function(_, class)
			return class == "BasePart" or class == "MeshPart"
		end,
		GetDescendants = function()
			return {}
		end,
		SetAttribute = function(_, name, value)
			values.attrs[name] = value
		end,
		GetAttribute = function(_, name)
			return values.attrs[name]
		end,
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
				check(values.CastShadow, "B clone published without shadows")
				check(
					not values.CanCollide and not values.CanTouch and not values.CanQuery,
					"B clone became collidable"
				)
			end
			values[key] = value
		end,
	})
	table.insert(clones, object)
	return object
end
local function sourceProxy()
	local clones = {}
	return {
		Clone = function()
			return clonedPart(clones)
		end,
	}, clones
end
local function capBatch(variant, initial)
	local near = nearController(variant)
	local source, clones = sourceProxy()
	near._template = source
	near._detailedTemplates = {
		Near = { source, source, source, source },
		Mid = { source, source, source, source },
		Far = { source, source, source, source },
	}
	near._plantCount = initial
	near._exclusions = { Boxes = {}, Circles = {} }
	near._queue = {
		{
			Alive = true,
			Lod = 3,
			ArtLod = 3,
			Column = 0,
			Row = 0,
			MinColumn = 0,
			MaxColumn = 10000,
			MaxRow = 1,
			Count = 0,
			Folder = {},
		},
	}
	-- A part's old shadow flag is allowed to remain false; this helper tests caps.
	if variant == "A" then
		local a = I.new("MeshPart")
		a.Size = V3.new(2, 8, 2)
		a.CFrame = CF.new(0, 4, 0)
		a.PivotOffset = CF.identity
		near._template = {
			Clone = function()
				table.insert(clones, true)
				return a:Clone()
			end,
		}
	end
	near:_createBatch()
	near._folder:Destroy()
	return near._plantCount, #clones
end
check(capBatch("A", 4032) == 4032, "A renderer cap changed")
local bcount, bcreated = capBatch("B", 4032)
check(bcount == 4050 and bcreated == 18, "B still stops at old A cap or clone budget changed")
check(capBatch("B", 8063) == 8064, "B cap allows more than 8064 plants")
check(capBatch("B", 8064) == 8064, "B capped renderer continues creating")
-- Real full-grid candidate preflight must allow all B sectors, then real build
-- method must reach the final row rather than silently stop at an old cap.
map:SetAttribute("HarvestArtVariant", "B")
local far = setmetatable({}, { __index = Far })
far:Init({
	Config = { Environment = "DEV", Game = { SessionMode = "team_local" } },
	Controllers = { CornController = {
		UseBackdropReady = function()
			return true
		end,
	} },
})
check(far:_resolveInputs(), "B full grid rejected by backdrop preflight")
check(far._folder:GetAttribute("MaxPlants") == 30000, "B Far cap metadata is stale")
check(far._folder:GetAttribute("DetailStride") == spacing * 2, "B Far stride mismatches Near")
local source, clones = sourceProxy()
far._detailedTemplates = { Far = { source, source, source, source } }
far._exclusions = { Boxes = {}, Circles = {} }
far._clock = function()
	return 0
end
local published = false
far._publish = function(self)
	published = true
	self._ready = true
	return true
end
for _ = 1, 2000 do
	if far._ready then
		break
	end
	far:_buildStep()
end
check(
	published and far._count == 28561 and #clones == 28561,
	"B Far did not cover the full 169x169 even-cell grid"
)
check(far._row > far._maxRow, "B Far publishes before reaching last field row")
for _, i in { 1, 10000, 20001, 28561 } do
	local p = clones[i]
	local c, row = p.Name:match("Far_(%-?%d+)_(%-?%d+)")
	local point = Layout.CellPosition(field, tonumber(c), tonumber(row))
	local expected = appearance.DetailedPivot(p, point, Layout.CellYaw(tonumber(c), tonumber(row)))
	check(p.CFrame == expected, "Far positioning differs from the shared Near placement")
end
far:Destroy()
map:SetAttribute("HarvestArtVariant", "A")
local aFar = setmetatable({}, { __index = Far })
aFar:Init({
	Config = { Environment = "DEV", Game = { SessionMode = "team_local" } },
	Controllers = { CornController = {
		UseBackdropReady = function()
			return true
		end,
	} },
})
check(
	aFar:_resolveInputs() and aFar._folder:GetAttribute("MaxPlants") == 20000,
	"A Far cap changed"
)
aFar:Destroy()
-- Index caps permit the additional B objects without increasing the wind's
-- actor, scan, per-frame index or animated Part limits.
for _, variant in { "A", "B" } do
	for _, kind in { "near", "far" } do
		map:SetAttribute("HarvestArtVariant", variant)
		local name = if kind == "near" then "CornClientPlants" else "CornClientBackdrop"
		local layerFolder = child(map, "Folder", name)
		layerFolder:SetAttribute(
			if kind == "near" then "CornClientRendererOwned" else "CornClientBackdropOwned",
			true
		)
		layerFolder:SetAttribute("corn_project_id", "children_of_corn")
		layerFolder:SetAttribute("CornEditorOverview", true)
		local parent = if kind == "near"
			then child(layerFolder, "Folder", "Chunk_0:0")
			else layerFolder
		local p = child(parent, "MeshPart", if kind == "near" then "Corn" else "Far_0_0")
		p:SetAttribute("CornPlantTemplateOwned", true)
		p:SetAttribute("CornClientBackdropOwned", true)
		p:SetAttribute("corn_project_id", "children_of_corn")
		p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
		p.Size, p.CFrame = V3.new(2, 10, 2), CF.new(0, 5, 0)
		local limit = if kind == "near"
			then (if variant == "B" then 8192 else 4096)
			else (if variant == "B" then 30000 else 20000)
		local layer = {
			Kind = kind,
			Folder = layerFolder,
			Count = limit - 1,
			Entries = {},
			Buckets = {},
			Groups = { [parent] = { Entries = {} } },
		}
		local wind = setmetatable(
			{ _map = map, _layers = { [kind] = layer }, _active = {} },
			{ __index = Wind }
		)
		wind:_register({ Layer = layer, Plant = p, Parent = parent })
		check(
			layer.Count == limit and layer.Entries[p] ~= nil,
			"Wind did not index final allowed " .. variant .. " " .. kind .. " plant"
		)
		local overflow = p:Clone()
		overflow.Parent = parent
		wind:_register({ Layer = layer, Plant = overflow, Parent = parent })
		check(
			layer.Count == limit and layer.Entries[overflow] == nil,
			"Wind exceeded " .. variant .. " " .. kind .. " cap"
		)
		layerFolder:Destroy()
	end
end
print(
	string.format(
		"corn-double-density PASS (%d assertions; B28561fullFar/8064near/200chunks; A retained)",
		assertions
	)
)
