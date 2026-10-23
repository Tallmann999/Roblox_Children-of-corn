-- Production controller through a limited Lune adapter; no GPU/FPS claim.
local adapter = require("./scene-adapter")
local fs, r, I = adapter.fs, adapter.r, adapter.I
local CF, V3 = r.CFrame, r.Vector3
-- Lune has no Instance replication signals; event cleanup is modeled here.
for _, name in { "DescendantAdded", "DescendantRemoving" } do
	r.implementProperty("Instance", name, function()
		return {
			Connect = function()
				return { Disconnect = function() end }
			end,
		}
	end)
end
local checks = 0
local function check(value, reason)
	assert(value, reason)
	checks += 1
end
local function child(parent, class, name)
	local item = I.new(class)
	item.Name, item.Parent = name, parent
	return item
end
local function load(path, environment)
	local fn = assert(loadstring(fs.readFile(path), path))
	setfenv(fn, setmetatable(environment, { __index = getfenv() }))
	return fn()
end
local function fixture(options)
	options = options or {}
	local world, storage = I.new("Workspace"), I.new("ReplicatedStorage")
	local modules = child(child(storage, "Folder", "GameShared"), "Folder", "Game")
	child(modules, "ModuleScript", "CornLayout")
	child(modules, "ModuleScript", "CornAppearance")
	local map = child(world, "Model", "CornMap")
	map:SetAttribute("corn_project_id", "children_of_corn")
	map:SetAttribute("HarvestArtVariant", options.variant or "B")
	map:SetAttribute("BManualAuthoringVersion", 1)
	local field = child(map, "Part", "FieldZone")
	field.Size, field.CFrame = V3.new(630, 10, 630), CF.identity
	local source = child(map, "Folder", "CornAuthoring")
	source:SetAttribute("corn_project_id", "children_of_corn")
	source:SetAttribute("BManualAuthoringVersion", 1)
	source:SetAttribute("BManualServerReady", true)
	if options.replicatedSource then
		local placeholder = source:Clone()
		placeholder:SetAttribute("BManualServerReady", nil)
		placeholder.Parent = map
		local archive = child(storage, "Folder", "BManualEditorSources")
		archive:SetAttribute("corn_project_id", "children_of_corn")
		archive:SetAttribute("BManualAuthoringVersion", 1)
		source.Parent = archive
	end
	local group = child(source, "Model", "Chunk_0_0")
	local function plant(column, row, position)
		local item = child(group, "MeshPart", "Plant")
		item.Size = V3.new(3, 6.8 + (column + row + 20) % 13 * 0.2, 3)
		item.CFrame = CF.new(position or V3.new(column * 3, 4, row * 3))
			* CF.Angles(0.04, column * 0.4, -0.025)
		item.Anchored = true
		item.CanCollide, item.CanTouch, item.CanQuery = false, false, false
		item:SetAttribute("CornGreenVariety", (column + row + 100) % 4 + 1)
		item:SetAttribute("HarvestRootOffset", V3.new(0.2, 4, -0.15))
		item:SetAttribute("CornGreenTemplateSize", V3.new(3, 8, 3))
		item:SetAttribute("CornAuthorColumn", column)
		item:SetAttribute("CornAuthorRow", row)
		if not options.replicatedSource then
			item:SetAttribute("BManualSourceTransparency", 0.15)
		end
		item.Transparency = if options.replicatedSource then 0.15 else 1
		item.LocalTransparencyModifier = 0.2
		return item
	end
	local parts = {}
	for column = -5, 5 do
		for row = -3, 3 do
			table.insert(parts, plant(column, row))
		end
	end
	local moved = parts[1]
	moved.CFrame = CF.new(210, 4, 0) * moved.CFrame.Rotation
	local duplicate = parts[2]:Clone()
	duplicate.Parent = group
	duplicate.CFrame += V3.new(1, 0, 1)
	local removed = table.remove(parts)
	removed:Destroy()
	local hidden = plant(30, 0)
	hidden:SetAttribute("BManualSourceTransparency", 1)
	hidden.Transparency = 1
	local root = child(child(world, "Model", "Character"), "Part", "HumanoidRootPart")
	root.CFrame = CF.identity
	local state = { pending = {}, warnings = {}, disconnects = 0, clock = 0, timeCost = 0 }
	local run = {
		IsStudio = function()
			return options.studio ~= false
		end,
		Heartbeat = {
			Connect = function(_, callback)
				state.callback = callback
				return {
					Disconnect = function()
						state.disconnects += 1
					end,
				}
			end,
		},
	}
	local templates = { Near = {}, Mid = {}, Far = {} }
	for lod, variants in templates do
		for variety = 1, 4 do
			local item = I.new("MeshPart")
			item.Name, item.Size = lod .. variety, V3.new(3, 8, 3)
			item:SetAttribute("CornGreenVariety", variety)
			item:SetAttribute("CornGreenOriginal", true)
			item:SetAttribute("CornPlantTemplateOwned", true)
			item:SetAttribute("HarvestRootOffset", V3.new(0.2, 4, -0.15))
			item:SetAttribute("CornGreenTemplateSize", V3.new(3, 8, 3))
			item.Anchored = true
			item.CanCollide, item.CanTouch, item.CanQuery = false, false, false
			variants[variety] = item
		end
	end
	local layout = {
		ChunkCells = 12,
		SpacingFor = function()
			return 3
		end,
		ReadExclusions = function()
			error("Frozen exclusion path entered")
		end,
	}
	local sourceLayout = load("variants/B/shared/Game/CornLayout.luau", {
		game = {
			GetService = function()
				return storage
			end,
		},
		script = { Parent = { GreenBedLayout = {} } },
		require = function()
			return {}
		end,
		CFrame = CF,
		Vector3 = V3,
		Vector2 = r.Vector2,
	})
	layout.AuthoringSource = sourceLayout.AuthoringSource
	local appearance = {
		DetailedTemplates = function()
			if options.failTemplates then
				error("Fixture template failure")
			end
			return templates
		end,
	}
	local environment = {
		game = {
			GetService = function(_, name)
				return ({
					Workspace = world,
					ReplicatedStorage = storage,
					RunService = run,
					Players = { LocalPlayer = { Character = root.Parent } },
				})[name]
			end,
		},
		Instance = I,
		Vector3 = V3,
		CFrame = CF,
		require = function(module)
			return if module.Name == "CornLayout" then layout else appearance
		end,
		task = {
			spawn = function(callback)
				table.insert(state.pending, callback)
			end,
		},
		warn = function(message)
			table.insert(state.warnings, message)
		end,
		os = {
			clock = function()
				state.clock += state.timeCost
				return state.clock
			end,
		},
	}
	local prototype =
		load("variants/B/client/Controllers/AuthoringCornController.luau", environment)
	local controller = setmetatable({}, { __index = prototype })
	local context = {
		Config = { Environment = "DEV", Game = { SessionMode = "solo_local" } },
		Controllers = {},
	}
	controller:Init(context)
	controller:Start()
	local function tick(delta)
		if state.callback then
			state.callback(delta or 0.016)
		end
		local callbacks = state.pending
		state.pending = {}
		for _, callback in callbacks do
			callback()
		end
	end
	return controller,
		state,
		map,
		source,
		parts,
		moved,
		duplicate,
		root,
		tick,
		plant,
		environment,
		context
end

local controller, state, map, source, parts, moved, duplicate, root, tick, plant, environment, context =
	fixture()
tick(0.1)
check(not controller._ready, "Published before initial quiet replication window")
tick(0.8)
for _ = 1, 200 do
	tick()
end
check(
	controller._ready and #controller._records == 77,
	"Deleted/hidden/duplicated source records differ: "
		.. #controller._records
		.. "/"
		.. table.concat(state.warnings, " | ")
)
check(
	controller._nearCount <= 8064 and controller._farFolder:GetAttribute("Ready"),
	"Bounded layers not ready"
)
check(#state.warnings == 0, "Unexpected authoring warning")
local movedRecord, copiedRecord
for _, record in controller._records do
	check(
		record.Source ~= nil
			and record.Frame == record.Source.CFrame
			and record.Size == record.Source.Size,
		"Author frame/size was regenerated"
	)
	if record.Source == moved then
		movedRecord = record
	end
	if record.Source == duplicate then
		copiedRecord = record
	end
	local copy = controller._nearByRecord[record]
	if copy then
		check(
			copy.CFrame == record.Frame
				and copy.Size == record.Size
				and math.abs(copy.Transparency - 0.15) < 1e-6,
			"Authored pose/height/opacity was not copied exactly"
		)
		check(
			copy.CastShadow and copy.Anchored and not copy.CanCollide and not copy.CanQuery,
			"Authored runtime physics/shadows changed"
		)
	end
end
check(movedRecord and copiedRecord, "Copied inherited IDs were refused")
check(not controller._nearByRecord[movedRecord], "Moved plant still indexed at old grid position")
root.CFrame = CF.new(210, 4, 0)
for _ = 1, 20 do
	tick(0.1)
end
check(
	controller._nearByRecord[movedRecord] ~= nil,
	"Moved plant missing from actual destination chunk"
)
for _, record in controller._far do
	if controller._nearByRecord[record] then
		check(record.FarPart.LocalTransparencyModifier == 1, "Near/far duplicate remains visible")
	end
end
-- Lune's Instance signals are not a real replication driver; invoke the same
-- debounced dirty state after adding a late server-replicated plant.
local late = plant(80, 2, V3.new(215, 4, 1))
controller._dirty, controller._quiet, controller._settleAge = true, 0, 0
tick(0.2)
check(#controller._records == 77, "Late change bypassed debounce")
tick(0.6)
for _ = 1, 200 do
	tick()
end
check(#controller._records == 78, "Late replicated source was dropped")
local lateFound = false
for _, record in controller._records do
	if record.Source == late then
		lateFound = true
	end
end
check(lateFound, "Late addition did not rebuild actual records")
state.timeCost = 0.0004
controller._farIndex = 1
controller:_buildBatch()
check(
	controller._farFolder:GetAttribute("LastFrameClones") < 18,
	"Time budget failed to stop expensive clones"
)
state.timeCost = 0
local folder = controller._nearFolder
controller:Destroy()
check(folder.Parent == nil and state.disconnects == 1, "Destroy did not clean owned runtime")
check(
	math.abs(parts[1].Transparency - 0.15) < 1e-6,
	"Server-hidden source fallback was not restored"
)
check(
	math.abs(parts[1].LocalTransparencyModifier - 0.2) < 1e-6,
	"Source author visibility was not restored"
)

local failed, failedState, _, _, failedParts, _, _, _, failedTick =
	fixture({ failTemplates = true })
failedTick(1)
check(
	failed._nearFolder == nil and #failedState.warnings == 1,
	"Preparation failure did not preserve source"
)
check(
	math.abs(failedParts[1].Transparency - 0.15) < 1e-6,
	"Preparation failure left author source hidden"
)
failed:Destroy()
local foreign, foreignState, foreignMap, _, _, _, _, _, foreignTick = fixture()
local foreignFolder = child(foreignMap, "Folder", "CornClientPlants")
foreignTick(1)
check(
	foreignFolder.Parent == foreignMap and #foreignState.warnings == 1,
	"Foreign name collision was replaced"
)
foreign:Destroy()
local guarded, _, _, _, guardedParts, _, _, _, guardedTick = fixture()
guardedTick(1)
guardedTick(1)
guardedParts[1].Transparency = 0.61
guardedParts[1].LocalTransparencyModifier = 0.47
guarded:Destroy()
check(
	math.abs(guardedParts[1].Transparency - 0.61) < 1e-6
		and math.abs(guardedParts[1].LocalTransparencyModifier - 0.47) < 1e-6,
	"Cleanup overwrote a later foreign visibility write"
)
local inactive, inactiveState, _, _, _, _, _, _, inactiveTick = fixture({ variant = "A" })
inactiveTick(1)
check(
	inactive._nearFolder == nil and #inactiveState.warnings == 0,
	"Authoring controller affected A"
)
inactive:Destroy()

local oldNear = load("variants/B/client/Controllers/CornController.luau", environment)
oldNear:Init(context)
check(
	oldNear:_resolveInputs() == false and oldNear._map == map,
	"Legacy near grid did not opt out while retaining torch map"
)
oldNear:Destroy()
local oldFar = load("variants/B/client/Controllers/CornBackdropController.luau", environment)
oldFar:Init(context)
check(oldFar:_resolveInputs() == false and oldFar._folder == nil, "Legacy far grid did not opt out")
oldFar:Destroy()
print(
	"PASS: "
		.. checks
		.. " authored records/actual-root chunks/delete/duplicate/hidden opacity/late replication/budgets/cleanup/legacy opt-out checks"
)

local archived, archivedState, archivedMap, archivedSource, archivedParts, _, _, _, archivedTick =
	fixture({ replicatedSource = true })
archivedTick(1)
archivedTick(1)
for _ = 1, 200 do
	archivedTick()
end
check(
	archived._ready and archived._source == archivedSource and #archived._records == 77,
	"ReplicatedStorage source did not take priority over empty Workspace placeholder"
)
check(
	archivedSource:IsDescendantOf(archivedSource.Parent.Parent)
		and archivedMap.CornAuthoring ~= archivedSource,
	"Author source archive fixture is invalid"
)
check(next(archived._hidden) == nil, "Archived 70k source path performed per-plant LTM writes")
check(
	archivedParts[1]:GetAttribute("BManualSourceTransparency") == nil
		and math.abs(archivedParts[1].Transparency - 0.15) < 1e-6
		and math.abs(archivedParts[1].LocalTransparencyModifier - 0.2) < 1e-6,
	"Archived source properties were rewritten"
)
archived:Destroy()
check(
	#archivedState.warnings == 0 and math.abs(archivedParts[1].Transparency - 0.15) < 1e-6,
	"Archived cleanup changed source opacity"
)
print("PASS: archived source priority and no per-plant visibility/attribute writes")
