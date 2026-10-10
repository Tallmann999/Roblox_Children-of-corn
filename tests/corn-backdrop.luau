-- Real controller methods + limited Lune geometry adapter. No Studio/render/FPS claim.
local adapter = require("./scene-adapter")
local fs, r, I = adapter.fs, adapter.r, adapter.I
local CF, V3 = r.CFrame, r.Vector3
local function loadSource(path, env)
	local source = fs.readFile(path)
	if path == "src/shared/Game/CornLayout.luau" then
		-- Lune lacks engine Position coupling for fixture Parts. Geometry remains exact.
		source = source:gsub("item%.Position", "item.CFrame.Position")
	end
	local fn = assert(loadstring(source, path))
	setfenv(fn, setmetatable(env, { __index = getfenv() }))
	return fn()
end
local Layout = loadSource(
	"src/shared/Game/CornLayout.luau",
	{ CFrame = CF, Vector3 = V3, Vector2 = r.Vector2 }
)
local function setup(bridge)
	local world = I.new("Workspace")
	local storage = I.new("ReplicatedStorage")
	local shared = I.new("Folder")
	shared.Name = "GameShared"
	shared.Parent = storage
	local gameFolder = I.new("Folder")
	gameFolder.Name = "Game"
	gameFolder.Parent = shared
	local module = I.new("ModuleScript")
	module.Name = "CornLayout"
	module.Parent = gameFolder
	local map = I.new("Model")
	map.Name = "CornMap"
	map:SetAttribute("corn_project_id", "children_of_corn")
	map.Parent = world
	local field = I.new("Part")
	field.Name = "FieldZone"
	field.Size = V3.new(120, 10, 120)
	field.CFrame = CF.new(40, 20, -80) * CF.Angles(0, math.rad(37), 0)
	field.Parent = map
	local overview = I.new("Folder")
	overview.Name = "EditorFieldOverview"
	overview:SetAttribute("CornEditorOverview", true)
	overview:SetAttribute("corn_project_id", "children_of_corn")
	overview.Parent = map
	local original = I.new("Part")
	original.Name = "Original"
	original:SetAttribute("CornEditorOverview", true)
	original:SetAttribute("corn_project_id", "children_of_corn")
	original.LocalTransparencyModifier = 0.37
	original.Parent = overview
	local slot = I.new("Part")
	slot.Name = "Slot"
	slot.CFrame = CF.new(field.CFrame.Position)
	slot:AddTag("corn_key_slot")
	slot.Parent = map
	local props = I.new("Folder")
	props.Name = "Props"
	props.Parent = map
	local house = I.new("Part")
	house.Name = "House"
	house.Size = V3.new(10, 12, 16)
	house.CFrame = field.CFrame * CF.new(25, 0, 18)
	house.Parent = props
	local art = I.new("Folder")
	art.Name = "CornRuntimeArt"
	art:SetAttribute("CornRuntimeArtOwned", true)
	art:SetAttribute("corn_project_id", "children_of_corn")
	art.Parent = storage
	local template = I.new("MeshPart")
	template.Name = "CornPlantTemplate"
	template.Size = V3.new(1.2, 8, 1.8)
	template.CFrame = CF.identity
	template:SetAttribute("CornPlantTemplateOwned", true)
	template.Parent = art
	local connections = { count = 0, disconnected = 0 }
	local run = {
		IsStudio = function()
			return true
		end,
		Heartbeat = {
			Connect = function(_, fn)
				connections.count += 1
				connections.callback = fn
				return {
					Disconnect = function()
						connections.disconnected += 1
					end,
				}
			end,
		},
	}
	local services = { Workspace = world, ReplicatedStorage = storage, RunService = run }
	local gameProxy = {
		GetService = function(_, name)
			return services[name]
		end,
	}
	local Controller = loadSource("src/client/Controllers/CornBackdropController.luau", {
		game = gameProxy,
		Instance = I,
		Enum = r.Enum,
		Vector3 = V3,
		require = function()
			return Layout
		end,
	})
	local renderer = if bridge == false
		then nil
		else {
			calls = 0,
			UseBackdropReady = function(self, folder)
				assert(folder.Parent == map and folder:GetAttribute("CornClientBackdropOwned"))
				self.calls += 1
				if original.Parent then
					original.LocalTransparencyModifier = 0.37
				end
				return true
			end,
		}
	local controller = setmetatable({}, { __index = Controller })
	controller:Init({
		Config = { Environment = "DEV", Game = { SessionMode = "solo_local" } },
		Controllers = { CornController = renderer },
	})
	controller._clock = function()
		return 0
	end
	return controller, map, field, template, original, slot, house, connections, renderer
end
local controller, map, field, template, original, slot, house, connections, renderer = setup()
local savedTemplateSize = template.Size
controller:Start()
controller:Start()
assert(connections.count == 1)
assert(controller:_resolveInputs())
local first = controller._folder
controller:_buildStep()
assert(controller._count == 18 and first:GetAttribute("LastFrameClones") == 18)
assert(
	math.abs(original.LocalTransparencyModifier - 0.37) < 1e-5
		and first:GetAttribute("Ready") == false
)
local frames = 1
while not controller._ready do
	controller:_buildStep()
	frames += 1
	assert(first:GetAttribute("LastFrameClones") <= 18 and frames < 200)
end
assert(first:GetAttribute("Ready") and controller._count <= 20000)
assert(original.LocalTransparencyModifier == 1 and renderer.calls == 1)
local exclusions = Layout.ReadExclusions(map, field)
for _, plant in first:GetChildren() do
	local bounds, size = Layout.Bounds(plant)
	local bottom = bounds.Position - V3.new(0, size.Y / 2, 0)
	assert(not Layout.IsExcluded(bottom, exclusions), "Corn entered clearing/house exclusion")
	assert(
		math.abs(size.X - template.Size.X) < 1e-5 and math.abs(size.Z - template.Size.Z) < 1e-5,
		"Far plant stretched X/Z"
	)
	assert(size.Y > 6.7 and size.Y < 9.3, "Normal height variation missing")
	assert(plant.CastShadow == false and plant.RenderFidelity == template.RenderFidelity)
	assert(plant.Anchored and not plant.CanCollide and not plant.CanTouch and not plant.CanQuery)
end
for _ = 1, 3 do
	assert(controller:_resolveInputs() and controller._folder == first)
end
assert(template.Size == savedTemplateSize, "Original prepared art changed")
local epoch = controller._epoch
house.CFrame *= CF.new(1, 0, 0)
assert(controller:_resolveInputs())
assert(controller._epoch > epoch and controller._folder ~= first and first.Parent == nil)
assert(math.abs(original.LocalTransparencyModifier - 0.37) < 1e-5)
controller._clock = (function()
	local value = 0
	return function()
		value += 0.0004
		return value
	end
end)()
controller:_buildStep()
assert(
	controller._count > 0 and controller._count < 18,
	"Time budget failed to stop the clone loop"
)
assert(controller._folder:GetAttribute("LastFrameSeconds") <= 0.0024 + 1e-7)
local before = controller._epoch
field.CFrame *= CF.new(1, 0, 0)
controller:_buildStep()
assert(
	controller._folder == nil
		and controller._epoch > before
		and math.abs(original.LocalTransparencyModifier - 0.37) < 1e-5
)
controller:Destroy()
assert(connections.disconnected == 1)
print(
	"PASS: clone18/time2ms budget, exact source aspect/height, exclusions, handoff, same-session reuse, input cancellation and connection cleanup"
)
local capped, _, bigField, _, saved = setup()
bigField.Size = V3.new(960, 10, 960)
assert(
	not capped:_resolveInputs()
		and capped._folder == nil
		and math.abs(saved.LocalTransparencyModifier - 0.37) < 1e-5
)
capped:Destroy()
local collision, collisionMap, _, _, collisionSaved = setup()
local foreign = I.new("Folder")
foreign.Name = "CornClientBackdrop"
foreign.Parent = collisionMap
local foreignPart = I.new("Part")
foreignPart.Parent = foreign
assert(not collision:_resolveInputs())
collision:Destroy()
assert(
	foreign.Parent == collisionMap
		and foreignPart.Parent == foreign
		and math.abs(collisionSaved.LocalTransparencyModifier - 0.37) < 1e-5
)
local noBridge, _, _, _, noBridgeSaved = setup(false)
assert(
	not noBridge:_resolveInputs()
		and noBridge._folder == nil
		and math.abs(noBridgeSaved.LocalTransparencyModifier - 0.37) < 1e-5
)
noBridge:Destroy()
local mixed, mixedMap, _, _, mixedSaved = setup()
assert(mixed:_resolveInputs())
while not mixed._ready do
	mixed:_buildStep()
end
local mixedFolder = mixed._folder
local injected = I.new("Part")
injected.Parent = mixedFolder
mixed:Destroy()
assert(
	mixedFolder.Parent == mixedMap
		and injected.Parent == mixedFolder
		and math.abs(mixedSaved.LocalTransparencyModifier - 0.37) < 1e-5
)
assert(mixedFolder:GetAttribute("Ready") == false)
print(
	"PASS: oversized-grid fallback, unknown name/content preservation, unavailable bridge and exact author LTM restoration"
)

local modelGuard, modelMap, _, preparedPart, modelSaved = setup()
assert(modelGuard:_resolveInputs())
while not modelGuard._ready do
	modelGuard:_buildStep()
end
local oldBackdrop = modelGuard._folder
assert(modelSaved.LocalTransparencyModifier == 1)
local art = preparedPart.Parent
local wrapped = I.new("Model")
wrapped.Name = "CornPlantTemplate"
wrapped:SetAttribute("CornPlantTemplateOwned", true)
preparedPart.Parent = wrapped
wrapped.Parent = art
assert(not modelGuard:_resolveInputs())
assert(modelGuard._folder == nil and oldBackdrop.Parent == nil)
assert(math.abs(modelSaved.LocalTransparencyModifier - 0.37) < 1e-5)
assert(
	wrapped.Parent == art
		and preparedPart.Parent == wrapped
		and modelMap.EditorFieldOverview.Parent == modelMap
)
modelGuard:Destroy()
print(
	"PASS: unsupported Model template refuses backdrop publication and restores exact authored overview visibility"
)
