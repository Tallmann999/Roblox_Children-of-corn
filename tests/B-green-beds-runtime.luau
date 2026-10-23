-- Production CornLayout + complete 1406-part controller lifecycle through Lune.
-- No Studio, GPU, networking, physics, or sustained FPS acceptance is implied.
local adapter = require("./scene-adapter")
local fs, r, I = adapter.fs, adapter.r, adapter.I
local serde = require("@lune/serde")
local CF, V3 = r.CFrame, r.Vector3
local checks = 0
local function check(value, message)
	assert(value, message)
	checks += 1
end
local function loadSource(source, name, environment)
	local fn = assert(loadstring(source, name))
	setfenv(fn, setmetatable(environment, { __index = getfenv() }))
	return fn()
end
local function load(path, environment)
	return loadSource(fs.readFile(path), path, environment)
end
local http = {
	JSONDecode = function(_, text)
		return serde.decode("json", text)
	end,
}
local plan = load("variants/B/shared/Game/GreenBedLayout.luau", {
	game = {
		GetService = function(_, name)
			assert(name == "HttpService")
			return http
		end,
	},
	Vector3 = V3,
	CFrame = CF,
})
local place = r.deserializePlace(fs.readFile("place/Children_of_corn_B.rbxl"))
local map = place:GetService("Workspace"):FindFirstChild("CornMap")
local field = map:FindFirstChild("FieldZone")
local oldSource = place:GetService("ReplicatedStorage").GameShared.Game.CornLayout.Source
oldSource = oldSource:gsub("item%.Position", "item.CFrame.Position")
local oldLayout =
	loadSource(oldSource, "saved B CornLayout", { CFrame = CF, Vector3 = V3, Vector2 = r.Vector2 })
local baseline = oldLayout.ReadExclusions(map, field)
-- Lune and Studio stringify CFrames differently. This adapter substitutes only
-- the already independently read baseline signature; production Source is intact.
local planAdapter = setmetatable({ Signature = baseline.Signature }, { __index = plan })
local newLayout = loadSource(
	fs.readFile("variants/B/shared/Game/CornLayout.luau")
		:gsub("item%.Position", "item.CFrame.Position"),
	"new B CornLayout",
	{
		CFrame = CF,
		Vector3 = V3,
		Vector2 = r.Vector2,
		Color3 = r.Color3,
		script = { Parent = { GreenBedLayout = {} } },
		require = function()
			return planAdapter
		end,
		game = {
			GetService = function()
				return {
					IsClient = function()
						return false
					end,
				}
			end,
		},
	}
)
local exclusions = newLayout.ReadExclusions(map, field)
check(
	exclusions.GreenBeds and #exclusions.Boxes == 188 and #exclusions.Circles == 19,
	"Frozen B clearances did not integrate"
)
local spacing = newLayout.SpacingFor(field)
check(math.abs(spacing - 3 / math.sqrt(2.6)) < 1e-12, "B spacing changed")
local minColumn, maxColumn = newLayout.GetCellBounds(field)
check(minColumn == -169 and maxColumn == 169, "Existing B cell bounds changed")
for column = -169, 169, 7 do
	for row = -169, 169, 7 do
		local base = newLayout.BaseCellPosition(field, column, row)
		check(
			math.abs(base.X - column * spacing) < 0.00004
				and math.abs(base.Z - row * spacing) < 0.00004,
			"B root retains jitter or stagger"
		)
		local point = newLayout.CellPosition(field, column, row)
		check(point.X == base.X and point.Z == base.Z, "Soil projection moved a root")
		check(
			newLayout.TrailEdgePosition(point, exclusions) == point,
			"Old trail-edge projection remains"
		)
		if not plan.Contains(point) then
			check(newLayout.IsExcluded(point, exclusions), "Corn is allowed outside soil coverage")
		else
			check(
				math.abs(point.Y - plan.GetHeight(base)) < 0.000002,
				"Corn root height differs from soil"
			)
		end
	end
end
local green = I.new("MeshPart")
green.Size = V3.new(3, 8, 3)
green:SetAttribute("CornGreenOriginal", true)
newLayout.ApplyVariation(green, 17, 13)
check(green.Size == V3.new(3, 8, 3), "Green source corn height varied")

local function child(parent, class, name)
	local object = I.new(class)
	object.Name, object.Parent = name, parent
	return object
end
local runtime = child(map, "Folder", "CornRoundRuntime")
runtime:SetAttribute("corn_project_id", "children_of_corn")
local key = child(runtime, "Part", "GateKey")
key:AddTag("corn_no_corn_zone")
local ownedBeds = child(map, "Folder", "CornClientGreenBeds")
ownedBeds:SetAttribute("corn_project_id", "children_of_corn")
ownedBeds:SetAttribute("BGreenBedsOwner", "corn_B_green_beds_v1")
local ownedPart = child(ownedBeds, "MeshPart", "OwnedBed")
ownedPart:AddTag("corn_no_corn_zone")
local door = map.EscapeGate:FindFirstChild("Door", true)
local previousDoor = { door.Transparency, door.CanCollide, door.CanQuery }
door.Transparency, door.CanCollide, door.CanQuery = 1, false, false
local runtimeExclusions = newLayout.ReadExclusions(map, field)
check(
	runtimeExclusions.Signature == exclusions.Signature,
	"Ordinary gate/runtime/owned decoration altered the clearance signature"
)
door.Transparency, door.CanCollide, door.CanQuery = unpack(previousDoor)
ownedBeds:Destroy()
runtime:Destroy()
local clearing = map.NoCornZones:FindFirstChildWhichIsA("BasePart", true)
local originalFrame = clearing.CFrame
clearing.CFrame *= CF.new(0.125, 0, 0)
check(not pcall(newLayout.ReadExclusions, map, field), "Manual clearance movement was accepted")
clearing.CFrame = originalFrame
map:SetAttribute("HarvestArtVariant", "A")
local foreign = newLayout.ReadExclusions(map, field)
check(not foreign.GreenBeds and newLayout.SpacingFor(field) == 3, "A received B green beds")
for column = -8, 8 do
	for row = -8, 8 do
		check(
			newLayout.CellPosition(field, column, row) == oldLayout.CellPosition(field, column, row),
			"Foreign/A fallback positions changed"
		)
	end
end
map:SetAttribute("HarvestArtVariant", "B")

local nativeInputs = serde.decode(
	"json",
	fs.readFile(".artifacts/playtests/2026-10-22-B-green-beds/native-inputs.json")
)
local expected = { Boxes = {}, Circles = {} }
local expectedField = {
	Size = V3.new(unpack(nativeInputs.fieldSize)),
	CFrame = CF.new(unpack(nativeInputs.fieldFrame)),
}
for index = #nativeInputs.boxes, 1, -1 do
	local row = nativeInputs.boxes[index]
	table.insert(
		expected.Boxes,
		{ Frame = CF.new(unpack(row.frame)), HalfSize = r.Vector2.new(unpack(row.half)) }
	)
end
for index = #nativeInputs.circles, 1, -1 do
	local row = nativeInputs.circles[index]
	table.insert(expected.Circles, { Center = V3.new(unpack(row.center)), Radius = row.radius })
end
check(
	plan.MatchesExclusions(expected, expectedField),
	"Reordered frozen clearance multiset refused"
)
local networkFrame = expected.Boxes[1].Frame
expected.Boxes[1].Frame += V3.new(0.00005, 0.00003, -0.00005)
check(plan.MatchesExclusions(expected, expectedField), "Normal client rounding refused")
expected.Boxes[1].Frame = networkFrame + V3.new(0.01, 0, 0)
check(
	not plan.MatchesExclusions(expected, expectedField),
	"Manual clearance movement accepted by client"
)
expected.Boxes[1].Frame = networkFrame
local firstCircle = expected.Circles[1].Radius
expected.Circles[1].Radius += 0.01
check(
	not plan.MatchesExclusions(expected, expectedField),
	"Changed circle radius accepted by client"
)
expected.Circles[1].Radius = firstCircle
table.remove(expected.Boxes)
check(not plan.MatchesExclusions(expected, expectedField), "Missing clearance accepted by client")

local assetMetadata = {}
for _, asset in serde.decode("json", fs.readFile("scene-c/data/manifest.json")).assets do
	assetMetadata[asset.key] = asset
end
-- Lune Vector3 arithmetic retains doubles whereas its Instance Size setter
-- serializes float32. Studio Vector3 itself is float32. Normalize only this
-- fixture's expected Size through that setter so exact native checks are tested.
local controllerPlan = table.clone(plan)
controllerPlan.SoilTiles = {}
local sizeAdapter = I.new("Part")
for _, tile in plan.SoilTiles do
	local value = table.clone(tile)
	sizeAdapter.Size, sizeAdapter.CFrame = tile.Size, tile.Frame
	value.Size = sizeAdapter.Size
	value.Frame = sizeAdapter.CFrame
	table.insert(controllerPlan.SoilTiles, value)
end
sizeAdapter:Destroy()

local function controllerFixture(options)
	options = options or {}
	local world, storage = I.new("Workspace"), I.new("ReplicatedStorage")
	local modules = child(child(storage, "Folder", "GameShared"), "Folder", "Game")
	child(modules, "ModuleScript", "GreenBedLayout")
	child(modules, "ModuleScript", "GreenBedGeometry")
	local localMap = child(world, "Model", "CornMap")
	localMap:SetAttribute("corn_project_id", "children_of_corn")
	localMap:SetAttribute("HarvestArtVariant", options.variant or "B")
	local localField = child(localMap, "Part", "FieldZone")
	localField.Size, localField.CFrame = V3.new(630, 10, 630), CF.new(0, 19.399986267089844, 0)
	local preview = child(localMap, "Folder", "GreenBedEditor")
	preview:SetAttribute("BGreenBedsOwner", "corn_B_green_beds_v1")
	preview:SetAttribute("corn_project_id", "children_of_corn")
	local previewParts = {}
	for index, tile in controllerPlan.SoilTiles do
		local metadata = assetMetadata[tile.Key]
		local part =
			child(preview, "MeshPart", metadata.name .. "_" .. string.format("%04d", index))
		part:SetAttribute("BGreenBedsOwner", "corn_B_green_beds_v1")
		part:SetAttribute("BGreenBedGeometryOwned", true)
		part:SetAttribute("BGreenBedGeometryKey", tile.Key)
		part:SetAttribute("BGreenBedSourceSHA256", metadata.source_sha256)
		part:SetAttribute("BGreenBedSourceTriangles", metadata.triangles)
		part:SetAttribute("BGreenBedTile", index)
		part.CFrame, part.Size, part.PivotOffset = tile.Frame, tile.Size, CF.identity
		part.Color, part.Material, part.TextureID =
			r.Color3.new(1, 1, 1), r.Enum.Material.Plastic, "rbxassetid://95855894892409"
		part.Transparency, part.Reflectance, part.Anchored = 0, 0, true
		part.CanCollide, part.CanTouch, part.CanQuery = false, false, false
		part.CastShadow, part.DoubleSided = true, true
		part.LocalTransparencyModifier = (index % 3) * 0.1
		previewParts[index] = part
	end
	if options.foreignPreview then
		child(previewParts[1], "Attachment", "Manual")
	end
	if options.mutatePreview then
		options.mutatePreview(previewParts[1], preview)
	end
	local state = {
		queue = {},
		builds = 0,
		clones = 0,
		clock = 0,
		connected = 0,
		disconnected = 0,
		warnings = {},
	}
	local run = {
		IsStudio = function()
			return options.studio ~= false
		end,
		IsClient = function()
			return options.client ~= false
		end,
		Heartbeat = {
			Connect = function(_, callback)
				state.callback, state.connected = callback, state.connected + 1
				return {
					Disconnect = function()
						state.disconnected += 1
					end,
				}
			end,
		},
	}
	local geometry = {
		BuildTemplates = function()
			state.builds += 1
			if options.failBuild then
				error("Expected preparation failure")
			end
		end,
		Clone = function(asset, frame)
			state.clones += 1
			state.clock += options.cloneCost or 0.00001
			local part = I.new("MeshPart")
			part.Name, part.CFrame = asset, frame
			part:SetAttribute("BGreenBedsOwner", "corn_B_green_beds_v1")
			return part
		end,
	}
	local controller = load("variants/B/client/Controllers/GreenBedController.luau", {
		game = {
			GetService = function(_, name)
				return if name == "RunService" then run else storage
			end,
		},
		workspace = world,
		Instance = I,
		Vector3 = V3,
		CFrame = CF,
		Color3 = r.Color3,
		Enum = r.Enum,
		require = function(module)
			return if module.Name == "GreenBedLayout" then controllerPlan else geometry
		end,
		task = {
			spawn = function(callback)
				table.insert(state.queue, callback)
			end,
		},
		os = {
			clock = function()
				return state.clock
			end,
		},
		warn = function(message)
			table.insert(state.warnings, message)
		end,
	})
	controller:Init({ Config = { Environment = options.environment or "DEV" } })
	controller:Start()
	local function flush()
		local pending = state.queue
		state.queue = {}
		for _, callback in pending do
			callback()
		end
	end
	local function tick(delta)
		if state.callback then
			state.callback(delta or 0.016)
		end
		flush()
	end
	return controller, state, localMap, previewParts, tick, flush
end

local controller, state, localMap, previewParts, tick = controllerFixture()
tick(1)
for index, part in previewParts do
	check(
		math.abs(part.LocalTransparencyModifier - (index % 3) * 0.1) < 0.00001,
		"Preview hidden before readiness"
	)
end
local frames = 0
while not controller._ready and frames < 300 do
	tick()
	frames += 1
	if controller._folder then
		check(controller._folder:GetAttribute("LastFrameClones") <= 8, "Clone budget exceeded")
	end
end
check(
	controller._ready and state.clones == #plan.SoilTiles and state.builds == 1,
	"Complete plan did not publish: "
		.. serde.encode(
			"json",
			{ warnings = state.warnings, clones = state.clones, builds = state.builds }
		)
)
check(#controller._folder:GetChildren() == 1406, "Published soil part count differs")
for index, part in previewParts do
	check(part.LocalTransparencyModifier == 1, "Saved preview remains visible")
end
local generated = controller._folder
controller:Destroy()
check(
	generated.Parent == nil and state.disconnected == 1,
	"Destroy did not remove owned runtime/disconnect"
)
for index, part in previewParts do
	check(
		math.abs(part.LocalTransparencyModifier - (index % 3) * 0.1) < 0.00001,
		"Preview LTM was not restored"
	)
end

local slow, slowState, _, _, slowTick = controllerFixture({ cloneCost = 0.001 })
slowTick(1)
slowTick()
check(slowState.clones <= 2, "Time budget did not limit expensive clones")
slow:Destroy()
local failed, failState, _, failPreview, failTick = controllerFixture({ failBuild = true })
failTick(1)
failTick(1)
check(
	failed._folder == nil and failState.clones == 0 and failState.builds == 1,
	"Preparation failure retried/damaged preview"
)
for index, part in failPreview do
	check(
		math.abs(part.LocalTransparencyModifier - (index % 3) * 0.1) < 0.00001,
		"Failure hid the saved preview"
	)
end
failed:Destroy()
local bad, badState, _, badPreview, badTick = controllerFixture({ foreignPreview = true })
badTick(1)
for _ = 1, 200 do
	badTick()
end
check(bad._folder == nil and #badState.warnings == 1, "Foreign preview was accepted")
check(badPreview[1]:FindFirstChild("Manual") ~= nil, "Foreign preview child deleted")
bad:Destroy()
local manualRefusals = {
	function(part)
		part.CFrame += V3.new(0.01, 0, 0)
	end,
	function(part)
		part.Size += V3.new(0.01, 0, 0)
	end,
	function(part)
		part.TextureID = "rbxassetid://123"
	end,
	function(part)
		part.Color = r.Color3.new(0.9, 1, 1)
	end,
	function(part)
		part.Material = r.Enum.Material.Neon
	end,
	function(part)
		part.CanCollide = true
	end,
	function(part)
		part.CastShadow = false
	end,
	function(part)
		part.DoubleSided = false
	end,
	function(part)
		part:SetAttribute("ManualAuthorAttribute", true)
	end,
	function(part)
		part:AddTag("ManualAuthorTag")
	end,
	function(part)
		part.Name = "ManualAuthorName"
	end,
	function(part)
		part:SetAttribute("BGreenBedTile", 2)
	end,
	function(part)
		part.PivotOffset = CF.new(0.01, 0, 0)
	end,
	function(_, preview)
		preview:SetAttribute("ManualAuthorAttribute", true)
	end,
}
for case, mutate in manualRefusals do
	local guarded, guardedState, _, guardedPreview, guardedTick =
		controllerFixture({ mutatePreview = mutate })
	guardedTick(1)
	for _ = 1, 180 do
		guardedTick()
	end
	check(
		guarded._folder == nil and #guardedState.warnings == 1,
		"Manual editor change accepted: " .. case
	)
	check(
		guardedPreview[1].Parent ~= nil
			and math.abs(guardedPreview[1].LocalTransparencyModifier - 0.1) < 0.00001,
		"Manual editor change overwritten or hidden: " .. case
	)
	guarded:Destroy()
end
local rounded, _, _, roundedPreview, roundedTick = controllerFixture({
	mutatePreview = function(part)
		part.CFrame += V3.new(0.00005, 0, 0)
	end,
})
roundedTick(1)
for _ = 1, 180 do
	roundedTick()
end
check(
	rounded._ready and roundedPreview[1].LocalTransparencyModifier == 1,
	"Client CFrame rounding was refused"
)
rounded:Destroy()
local exact, exactState, _, exactPreview, exactTick = controllerFixture({
	client = false,
	mutatePreview = function(part)
		part.CFrame += V3.new(0.00005, 0, 0)
	end,
})
exactTick(1)
for _ = 1, 180 do
	exactTick()
end
check(
	exact._folder == nil
		and #exactState.warnings == 1
		and math.abs(exactPreview[1].LocalTransparencyModifier - 0.1) < 0.00001,
	"Edit/server editor check used client frame tolerance"
)
exact:Destroy()
local canceled, cancelState, _, _, _, cancelFlush = controllerFixture()
canceled._poll = 1
canceled:_step(1)
canceled:Destroy()
cancelFlush()
check(canceled._folder == nil and cancelState.clones == 0, "Canceled async build published")
local inert, inertState = controllerFixture({ variant = "A" })
inertState.callback(1)
check(inert._folder == nil and inertState.clones == 0, "Controller changed A")
inert:Destroy()
local disabled, disabledState = controllerFixture({ studio = false })
check(
	disabledState.connected == 0 and disabledState.builds == 0,
	"Controller enabled outside Studio"
)
disabled:Destroy()

print(serde.encode("json", {
	pass = true,
	checks = checks,
	completeSoilParts = 1406,
	buildFrames = frames,
	manualEditorRefusals = #manualRefusals,
	nativeMutation = false,
	networkAcceptance = false,
	GPUAcceptance = false,
}))
