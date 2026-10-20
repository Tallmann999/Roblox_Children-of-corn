-- Production corn renderers with Lune geometry. Dynamic-mesh construction is a
-- deterministic peer-local adapter here; Studio verifies real EditableMesh/GPU.
local adapter = require("./scene-adapter")
local fs, r, I = adapter.fs, adapter.r, adapter.I
local CF, V3 = r.CFrame, r.Vector3
local function loadSource(path, env)
	local source = fs.readFile(path)
	if path == "src/shared/Game/CornLayout.luau" then
		source = source:gsub("item%.Position", "item.CFrame.Position")
	end
	local fn = assert(loadstring(source, path))
	setfenv(fn, setmetatable(env, { __index = getfenv() }))
	return fn()
end
local function child(parent, class, name)
	local item = I.new(class)
	item.Name, item.Parent = name, parent
	return item
end
local function node(name)
	return {
		Name = name,
		WaitForChild = function(_, nextName)
			return node(nextName)
		end,
	}
end
local Layout = loadSource(
	"src/shared/Game/CornLayout.luau",
	{ CFrame = CF, Vector3 = V3, Vector2 = r.Vector2 }
)
local function appearance(bad)
	local templates, calls = {}, 0
	local geometry = {
		CornTemplate = function(index, lod)
			calls += 1
			if bad == "failure" then
				error("Controlled geometry unavailable")
			end
			local key = "Corn_" .. string.char(64 + index) .. "_" .. lod
			local part = I.new("MeshPart")
			part.Name = key
			part.MeshId, part.TextureID = "dynamic://" .. key, "corn-leaf-material"
			part.Size = V3.new(2 + index * 0.1, 8, 2.1 + index * 0.1)
			part.CFrame, part.PivotOffset = CF.new(0.17, 4, -0.09), CF.identity
			part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
			part.DoubleSided, part.CastShadow = true, false
			part:SetAttribute(
				"HarvestGeometryOwner",
				if bad == "owner" then "foreign" else "harvest_warden_v1"
			)
			part:SetAttribute("HarvestAssetKey", key)
			part:SetAttribute("corn_project_id", "children_of_corn")
			part:SetAttribute("CornPlantTemplateOwned", true)
			part:SetAttribute("HarvestRootOffset", V3.new(0.17, 4, -0.09))
			templates[key] = part
			return part
		end,
	}
	local module = loadSource("src/shared/Game/CornAppearance.luau", {
		script = { Parent = node("Game") },
		require = function()
			return geometry
		end,
		CFrame = CF,
		Vector3 = V3,
		task = {
			wait = function()
				error("Unexpected concurrent fixture wait")
			end,
		},
	})
	return module, templates, function()
		return calls
	end
end
local Appearance, originals, buildCalls = appearance()
local localTemplates = Appearance.DetailedTemplates()
assert(Appearance.DetailedTemplates() == localTemplates and buildCalls() == 12)
assert(Appearance.DetailedHeight == 10)
for _, list in localTemplates do
	for _, template in list do
		assert(template.Size.Y == 10, "Every B variety/LOD must use taller render templates")
	end
end
for _, stride in { 1, 2, 3 } do
	local found = {}
	for col = -12, 12, stride do
		for row = -12, 12, stride do
			found[Appearance.Variety(col, row)] = true
		end
	end
	assert(
		found[1] and found[2] and found[3] and found[4],
		"Plant grid lost one of its four shapes"
	)
end
for _, bad in { "failure", "owner" } do
	local rejected = appearance(bad)
	assert(not pcall(rejected.DetailedTemplates), "Invalid geometry template was accepted")
end
local run = {
	IsStudio = function()
		return true
	end,
}
local function setup(variant, selectedAppearance)
	selectedAppearance = selectedAppearance or Appearance
	local world, storage = I.new("Workspace"), I.new("ReplicatedStorage")
	local shared = child(storage, "Folder", "GameShared")
	local modules = child(shared, "Folder", "Game")
	child(modules, "ModuleScript", "CornLayout")
	child(modules, "ModuleScript", "CornAppearance")
	local map = child(world, "Model", "CornMap")
	map:SetAttribute("corn_project_id", "children_of_corn")
	map:SetAttribute("HarvestArtVariant", variant)
	local field = child(map, "Part", "FieldZone")
	field.Size, field.CFrame = V3.new(630, 10, 630), CF.new(0, 5, 0)
	local saved = child(map, "Folder", "EditorFieldOverview")
	saved:SetAttribute("corn_project_id", "children_of_corn")
	saved:SetAttribute("CornEditorOverview", true)
	local original = child(saved, "MeshPart", "Original")
	original:SetAttribute("corn_project_id", "children_of_corn")
	original:SetAttribute("CornEditorOverview", true)
	original.LocalTransparencyModifier = 0.37
	local preview = child(map, "Folder", "EditorPreview")
	preview:SetAttribute("corn_project_id", "children_of_corn")
	preview:SetAttribute("CornEditorPreview", true)
	local props = child(map, "Folder", "Props")
	local house = child(props, "Part", "House")
	house.Size, house.CFrame = V3.new(10, 12, 16), CF.new(25, 6, 18)
	local slot = child(map, "Part", "Slot")
	slot.CFrame = CF.new(12, 0, 12)
	slot:AddTag("corn_key_slot")
	local art = child(storage, "Folder", "CornRuntimeArt")
	art:SetAttribute("corn_project_id", "children_of_corn")
	art:SetAttribute("CornRuntimeArtOwned", true)
	local template = child(art, "MeshPart", "CornPlantTemplate")
	template:SetAttribute("CornPlantTemplateOwned", true)
	template.Size, template.CFrame = V3.new(1.2, 8, 1.8), CF.new(0, 4, 0)
	template.MeshId, template.TextureID = Appearance.MeshId, Appearance.DryTextureId
	template.Anchored, template.CanCollide, template.CanTouch, template.CanQuery =
		true, false, false, false
	local services = {
		Workspace = {
			CurrentCamera = { CFrame = CF.new(0, 5.4, 0) },
			FindFirstChild = function(_, name)
				return world:FindFirstChild(name)
			end,
		},
		ReplicatedStorage = storage,
		RunService = run,
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
		warn = function() end,
		require = function(module)
			return if module.Name == "CornAppearance" then selectedAppearance else Layout
		end,
	}
	local Near = loadSource("src/client/Controllers/CornController.luau", env)
	local near = setmetatable({
		_chunks = {},
		_queue = {},
		_overviewParts = {},
		_overviewByChunk = {},
		_overviewDirty = {},
		_overviewConnections = {},
		_plantCount = 0,
		_inputEpoch = 0,
		_bindOverview = function() end,
		_restoreOverview = function() end,
		_updateOverview = function() end,
		_markOverviewChunk = function() end,
	}, { __index = Near })
	local Backdrop = loadSource("src/client/Controllers/CornBackdropController.luau", env)
	local backdrop = setmetatable({}, { __index = Backdrop })
	backdrop:Init({
		Config = { Environment = "DEV", Game = { SessionMode = "team_local" } },
		Controllers = {
			CornController = {
				UseBackdropReady = function()
					original.LocalTransparencyModifier = 0.37
					return true
				end,
			},
		},
	})
	backdrop._clock = function()
		return 0
	end
	local root = { Position = V3.new(0, 3.5, 0) }
	return near, backdrop, map, field, template, original, root, preview
end
local near, backdrop, map, field, oldTemplate, original, root, preview = setup("B")
local originalSize, originalFrame = oldTemplate.Size, oldTemplate.CFrame
assert(near:_resolveInputs() and near._detailed)
assert(preview.Parent == nil and original.LocalTransparencyModifier > 0.36)
near:_reconcile(root)
local function fillNear()
	local frames = 0
	while #near._queue > 0 do
		local before = near._plantCount
		near:_createBatch()
		assert(near._plantCount - before <= 18)
		frames += 1
		assert(frames < 1000, "Near renderer failed to settle")
	end
end
local function validateNear()
	local total, detailed, shapes = 0, 0, {}
	local exclusions = Layout.ReadExclusions(map, field)
	for _, chunk in near._chunks do
		for _, plant in chunk.Folder:GetChildren() do
			total += 1
			local key = plant:GetAttribute("HarvestAssetKey")
			assert(key and key:match("^Corn_[ABCD]_"), "Legacy/unknown plant entered B renderer")
			shapes[key:match("^Corn_([ABCD])_")] = true
			if key:match("_Near$") then
				detailed += 1
			end
			local offset = plant:GetAttribute("HarvestRootOffset")
			local scale = plant.Size.Y / 8
			local ground = (plant.CFrame * CF.new(-offset.X, -offset.Y * scale, -offset.Z)).Position
			local localGround = field.CFrame:PointToObjectSpace(ground)
			local col, row = math.round(localGround.X / 3), math.round(localGround.Z / 3)
			assert(
				(ground - Layout.CellPosition(field, col, row)).Magnitude < 0.0001,
				"Detailed stem root drifted off canonical cell"
			)
			assert(
				not Layout.IsExcluded(ground, exclusions),
				"Detailed corn entered gameplay clearing"
			)
			assert(
				plant.Anchored
					and not plant.CanCollide
					and not plant.CanTouch
					and not plant.CanQuery
			)
			assert(plant.Size.Y > 8.4 and plant.Size.Y < 11.6)
		end
	end
	assert(total == near._plantCount and total <= 4032 and total > 600)
	assert(detailed > 0 and detailed <= 576, "Near geometry budget exceeded")
	assert(shapes.A and shapes.B and shapes.C and shapes.D)
end
fillNear()
validateNear()
root.Position = V3.new(70, 3.5, -55)
near:_reconcile(root)
fillNear()
validateNear()
assert(
	oldTemplate.Size == originalSize
		and oldTemplate.CFrame == originalFrame
		and oldTemplate.TextureID == Appearance.DryTextureId
)
assert(buildCalls() == 12, "Canonical geometry rebuilt for each plant/chunk")
print(
	"PASS: B four stable varieties, rooted curved meshes, exact gameplay exclusions/height/density, streaming18/batch and Near576 cap"
)
assert(backdrop:_resolveInputs() and backdrop._detailed)
local farFolder = backdrop._folder
backdrop:_buildStep()
assert(
	backdrop._count == 18
		and original.LocalTransparencyModifier > 0.36
		and farFolder:GetAttribute("Ready") == false
)
local frames = 0
while not backdrop._ready do
	backdrop:_buildStep()
	frames += 1
	assert(frames < 1000 and farFolder:GetAttribute("LastFrameClones") <= 18)
end
assert(original.LocalTransparencyModifier == 1)
local shapes = {}
for _, plant in farFolder:GetChildren() do
	local col, row = plant.Name:match("^Far_(%-?%d+)_(%-?%d+)$")
	col, row = tonumber(col), tonumber(row)
	local key = Appearance.DetailedKey(Appearance.Variety(col, row), "Far")
	assert(plant:GetAttribute("HarvestAssetKey") == key, "Backdrop used wrong shape/LOD")
	shapes[key] = true
	local offset = plant:GetAttribute("HarvestRootOffset")
	local ground = (plant.CFrame * CF.new(-offset.X, -offset.Y * plant.Size.Y / 8, -offset.Z)).Position
	assert((ground - Layout.CellPosition(field, col, row)).Magnitude < 0.0001)
end
local count = 0
for _ in shapes do
	count += 1
end
assert(count == 4 and backdrop._count <= 20000 and buildCalls() == 12)
assert(backdrop:_resolveInputs() and backdrop._folder == farFolder)
map:SetAttribute("HarvestArtVariant", "A")
assert(backdrop:_resolveInputs() and not backdrop._detailed and farFolder.Parent == nil)
assert(math.abs(original.LocalTransparencyModifier - 0.37) < 0.0001)
assert(near:_resolveInputs() and not near._detailed)
near:_reconcile(root)
fillNear()
for _, chunk in near._chunks do
	for _, plant in chunk.Folder:GetChildren() do
		assert(plant.MeshId == Appearance.MeshId and plant:GetAttribute("HarvestAssetKey") == nil)
	end
end
backdrop:Destroy()
near:Destroy()
assert(
	map:FindFirstChild("CornClientPlants") == nil
		and math.abs(original.LocalTransparencyModifier - 0.37) < 0.0001
)
print(
	"PASS: B Far-only whole field, inherited four-variety placements, Ready handoff/reuse, B-to-A restoration and cleanup"
)
local brokenAppearance = appearance("failure")
local brokenNear, brokenBackdrop, brokenMap, _, _, brokenOriginal, _, brokenPreview =
	setup("B", brokenAppearance)
assert(not brokenNear:_resolveInputs() and not brokenBackdrop:_resolveInputs())
assert(brokenNear._folder == nil and brokenBackdrop._folder == nil)
assert(
	brokenPreview.Parent == brokenMap
		and math.abs(brokenOriginal.LocalTransparencyModifier - 0.37) < 0.0001
)
local partialNear, partialBackdrop, partialMap, partialField, _, partialOriginal = setup("B")
assert(partialBackdrop:_resolveInputs())
partialBackdrop:_buildStep()
partialField.CFrame *= CF.new(1, 0, 0)
partialBackdrop:_buildStep()
assert(
	partialBackdrop._folder == nil
		and math.abs(partialOriginal.LocalTransparencyModifier - 0.37) < 0.0001
)
partialMap:SetAttribute("HarvestArtVariant", "A")
assert(partialNear:_resolveInputs() and not partialNear._detailed)
partialNear:Destroy()
partialBackdrop:Destroy()
print(
	"PASS: failed detailed startup preserves authored preview/overview; interrupted streaming cancels before publication"
)
local delayed = setmetatable({
	DetailedTemplates = function()
		coroutine.yield("building")
		return localTemplates
	end,
}, { __index = Appearance })
for _, kind in { "near", "backdrop" } do
	local pendingNear, pendingBackdrop, pendingMap, _, _, pendingOriginal, _, pendingPreview =
		setup("B", delayed)
	local pending = if kind == "near" then pendingNear else pendingBackdrop
	local thread = coroutine.create(function()
		return pending:_resolveInputs()
	end)
	local ok, status = coroutine.resume(thread)
	assert(ok and status == "building")
	assert(not pending:_resolveInputs(), "Reentrant template preparation was accepted")
	pending:Destroy()
	ok, status = coroutine.resume(thread)
	assert(ok and status == false and coroutine.status(thread) == "dead")
	assert(pending._folder == nil and pendingPreview.Parent == pendingMap)
	assert(math.abs(pendingOriginal.LocalTransparencyModifier - 0.37) < 0.0001)
	pendingNear:Destroy()
	pendingBackdrop:Destroy()
end
print(
	"PASS: late async template completion cannot recreate a destroyed renderer or remove saved fallback"
)
for _, part in originals do
	assert(
		math.abs(part.Size.Y - 8) < 0.00001
			and (part.CFrame.Position - V3.new(0.17, 4, -0.09)).Magnitude < 0.00001
			and part.Parent == nil,
		part.Name
			.. " "
			.. tostring(part.Size)
			.. " "
			.. tostring(part.CFrame)
			.. " parent="
			.. tostring(part.Parent)
	)
end
