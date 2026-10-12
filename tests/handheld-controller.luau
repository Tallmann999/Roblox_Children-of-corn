-- Actual HandheldController methods with deterministic camera/Instances/signals.
-- No engine/network/pixel claim. Geometry/poses are shared with the real controller.
local fs = require("@lune/fs")
local r = require("@lune/roblox")
local function load(path, env)
	local fn = assert(loadstring(fs.readFile(path), path))
	setfenv(fn, setmetatable(env, { __index = getfenv() }))
	return fn()
end
local Inventory = load("src/shared/Game/Inventory.luau", {})
local Presentation = load(
	"src/shared/Game/HandheldPresentation.luau",
	{ CFrame = r.CFrame, Vector3 = r.Vector3, Color3 = r.Color3, Enum = r.Enum }
)
local function signal()
	local entries = {}
	return {
		Connect = function(_, fn)
			local connection = {
				Connected = true,
				Disconnect = function(self)
					self.Connected = false
				end,
			}
			table.insert(entries, { connection, fn })
			return connection
		end,
		Fire = function(_, ...)
			for _, entry in entries do
				if entry[1].Connected then
					entry[2](...)
				end
			end
		end,
	}
end
local methods = {}
local made, cameraWrites, rootWrites = 0, 0, 0
local function make(class)
	made += 1
	return setmetatable({
		_class = class,
		_children = {},
		_attributes = {},
		_values = {
			Name = class,
			CFrame = r.CFrame.identity,
			Color = r.Color3.fromRGB(173, 114, 67),
			CameraType = r.Enum.CameraType.Custom,
			ViewportSize = r.Vector2.new(1400, 800),
			Health = 100,
			FieldOfView = 70,
		},
	}, {
		__index = function(item, key)
			local value = methods[key] or item._values[key]
			if value ~= nil then
				return value
			end
			for _, child in item._children do
				if child.Name == key then
					return child
				end
			end
			return nil
		end,
		__newindex = function(item, key, value)
			if key == "Parent" then
				local previous = item._values.Parent
				if previous then
					local index = table.find(previous._children, item)
					if index then
						table.remove(previous._children, index)
					end
				end
				if value then
					table.insert(value._children, item)
				end
			end
			if
				item._class == "Camera"
				and (
					key == "CFrame"
					or key == "CameraType"
					or key == "CameraSubject"
					or key == "FieldOfView"
				)
			then
				cameraWrites += 1
			end
			if
				item._values.Name == "HumanoidRootPart"
				and (key == "CFrame" or key == "Position" or key == "AssemblyLinearVelocity")
			then
				rootWrites += 1
			end
			item._values[key] = value
		end,
	})
end
function methods:IsA(class)
	return self._class == class or (class == "BasePart" and self._class == "Part")
end
function methods:SetAttribute(name, value)
	self._attributes[name] = value
end
function methods:GetAttribute(name)
	return self._attributes[name]
end
function methods:GetChildren()
	return table.clone(self._children)
end
function methods:FindFirstChild(name)
	for _, child in self._children do
		if child.Name == name then
			return child
		end
	end
	return nil
end
function methods:WaitForChild(name)
	return assert(self:FindFirstChild(name), name)
end
function methods:FindFirstChildOfClass(class)
	for _, child in self._children do
		if child:IsA(class) then
			return child
		end
	end
	return nil
end
function methods:Destroy()
	for _, child in self:GetChildren() do
		child:Destroy()
	end
	self.Parent = nil
	self.Destroyed = true
end
function methods:Clone()
	local copy = make(self._class)
	for name, value in self._values do
		if name ~= "Parent" then
			copy._values[name] = value
		end
	end
	return copy
end
function methods:GetDescendants()
	local items = {}
	for _, child in self:GetChildren() do
		table.insert(items, child)
		for _, nested in child:GetDescendants() do
			table.insert(items, nested)
		end
	end
	return items
end
function methods:PivotTo(frame)
	assert(self:IsA("Model") and self.PrimaryPart, "Expected owned whole-model pivot")
	self._pivotCalls = (self._pivotCalls or 0) + 1
	local delta = frame * self.PrimaryPart.CFrame:Inverse()
	for _, child in self:GetChildren() do
		child.CFrame = delta * child.CFrame
	end
end
local world, storage = make("Workspace"), make("ReplicatedStorage")
local shared = make("Folder")
shared.Name = "GameShared"
shared.Parent = storage
local games = make("Folder")
games.Name = "Game"
games.Parent = shared
for _, name in { "Inventory", "HandheldPresentation" } do
	local node = make("ModuleScript")
	node.Name = name
	node.Parent = games
end
local player = {
	CharacterAdded = signal(),
	CharacterRemoving = signal(),
	CameraMode = r.Enum.CameraMode.LockFirstPerson,
}
local function character()
	local model = make("Model")
	local humanoid = make("Humanoid")
	humanoid.Parent = model
	local root = make("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = model
	local left, right = make("Part"), make("Part")
	left.Name, right.Name = "LeftHand", "RightHand"
	left.Color, right.Color = r.Color3.fromRGB(55, 115, 165), r.Color3.fromRGB(165, 85, 55)
	left.Parent, right.Parent = model, model
	return model, humanoid
end
local hero, humanoid = character()
player.Character = hero
local camera = make("Camera")
camera.CameraSubject = humanoid
camera.Parent = world
world.CurrentCamera = camera
cameraWrites, rootWrites = 0, 0
local now, pending, bindings = 100, {}, {}
local gui = { MenuIsOpen = false, MenuOpened = signal() }
local run = {
	BindToRenderStep = function(_, name, priority, fn)
		assert(priority == r.Enum.RenderPriority.Camera.Value + 2)
		assert(not bindings[name])
		bindings[name] = fn
	end,
	UnbindFromRenderStep = function(_, name)
		bindings[name] = nil
	end,
}
local services = {
	Players = { LocalPlayer = player },
	ReplicatedStorage = storage,
	RunService = run,
	GuiService = gui,
}
local module = load("src/client/Controllers/HandheldController.luau", {
	game = {
		GetService = function(_, name)
			return assert(services[name], name)
		end,
	},
	workspace = world,
	Instance = { new = make },
	CFrame = r.CFrame,
	Vector3 = r.Vector3,
	Vector2 = r.Vector2,
	UDim2 = r.UDim2,
	UDim = r.UDim,
	Color3 = r.Color3,
	Enum = r.Enum,
	os = {
		clock = function()
			return now
		end,
	},
	task = {
		delay = function(duration, fn)
			table.insert(pending, { at = now + duration, fn = fn })
		end,
	},
	require = function(node)
		return if node.Name == "Inventory" then Inventory else Presentation
	end,
	warn = function() end,
})
local controller = setmetatable({}, { __index = module })
local minimap, capture = { _expanded = false }, { _state = { active = false } }
controller:Init({})
controller:Start({ Controllers = { MinimapController = minimap, CaptureController = capture } })
local function snapshot(roundId, useId, useKind, selected, selectedKind, phase)
	local slots = { "empty", "empty", "empty", "empty", "empty" }
	slots[selected] = selectedKind
	return {
		minimap = { round_id = roundId },
		phase = phase or "active",
		inventory = {
			slots = slots,
			selected = selected,
			energy_remaining = 0,
			use = { id = useId, kind = useKind },
		},
	}
end
local function show(roundId, useId, useKind, selected, kind, phase)
	controller:SetSnapshot(snapshot(roundId, useId, useKind, selected, kind, phase))
end
local function advance(time)
	now = time
	for _, event in pending do
		if not event.fired and event.at <= now then
			event.fired = true
			event.fn()
		end
	end
end
show(1, 4, "energy", 1, "key")
assert(
	controller._visual and controller._kind == "key" and not controller._gesture,
	"Initial sync replayed old use"
)
assert(#controller._visual:GetChildren() <= 24 and controller._visual.Parent == camera)
assert(
	controller._visual.RightHand.Color == hero:FindFirstChild("RightHand").Color
		and controller._visual.LeftHand.Color == hero:FindFirstChild("LeftHand").Color
)
for _, part in controller._visual:GetChildren() do
	assert(
		part.Anchored
			and not part.CanCollide
			and not part.CanTouch
			and not part.CanQuery
			and not part.CastShadow
	)
end
local unchanged, allocations = controller._visual, made
for _ = 1, 20 do
	controller:_step(now)
end
assert(
	controller._visual == unchanged and made == allocations and unchanged._pivotCalls == 21,
	"Held geometry rebuilt or multiple pivots per frame"
)
show(1, 4, "energy", 2, "energy")
local can = controller._visual
local label = can.Can.EnergyLabel
assert(
	label.Parent == can.Can
		and label.Face == r.Enum.NormalId.Back
		and label.CanvasSize == r.Vector2.new(256, 256),
	"Can label does not face camera or has unbounded canvas"
)
assert(
	not label.AlwaysOnTop
		and not label.Active
		and label.LightInfluence == 0
		and label.Paper.Rotation == 90
		and label.Paper.Logo.Text == "+"
		and label.Paper:FindFirstChild("Name").Text == "ENERGY",
	"Can label has unsafe GUI settings or missing readable branding"
)
for _, child in can:GetDescendants() do
	assert(
		not child:IsA("PointLight") and not child:IsA("Attachment"),
		"Held model still has lighting"
	)
end
assert(controller._kind == "energy" and #can:GetChildren() == 6 and not controller._gesture)
show(1, 5, "energy", 2, "empty")
assert(controller._gesture and controller._gesture.kind == "energy" and controller._visual == can)
local deadline = controller._gesture.deadline
now = 100.3
show(1, 5, "energy", 2, "empty")
assert(
	controller._gesture.deadline == deadline and controller._visual == can,
	"Duplicate use extended/rebuilt gesture"
)
show(1, 4, "energy", 2, "trap")
assert(
	controller._gesture.deadline == deadline and controller._kind == "energy",
	"Out-of-order use changed presentation"
)
advance(100.91)
assert(
	not controller._gesture and not controller._visual,
	"Consumed empty slot still held after0.9s"
)
assert(label.Destroyed and label.Parent == nil, "Can label survived its owned model")
now = 101
show(1, 5, "energy", 3, "trap")
local trap = controller._visual
assert(controller._kind == "trap" and #trap:GetChildren() == 17)
show(1, 6, "trap", 3, "empty")
assert(
	controller._gesture and controller._gesture.deadline == 101.55 and controller._visual == trap
)
now = 101.2
show(1, 6, "trap", 1, "key")
assert(
	not controller._gesture and controller._kind == "key",
	"Switch selection did not interrupt gesture"
)
advance(101.6)
assert(controller._kind == "key", "Cancelled old timer removed current selected item")
show(1, 0, "none", 1, "empty", "escaped")
assert(
	not controller._visual and not controller._gesture,
	"Terminal inventory reset useid0 was incorrectly ignored"
)
show(1, 6, "trap", 1, "key")
assert(not controller._visual, "Old active snapshot revived ended round")
show(2, 0, "none", 1, "energy")
assert(controller._kind == "energy" and not controller._gesture)
show(2, 1, "energy", 1, "empty")
for _, reason in
	{ "map", "capture", "owner", "menu", "dead", "type", "subject", "thirdperson", "caught" }
do
	if reason == "map" then
		minimap._expanded = true
	elseif reason == "capture" then
		capture._state.active = true
	elseif reason == "owner" then
		camera:SetAttribute("CornCaptureCameraOwner", "capture")
	elseif reason == "menu" then
		gui.MenuIsOpen = true
		gui.MenuOpened:Fire()
	elseif reason == "dead" then
		humanoid.Health = 0
	elseif reason == "type" then
		camera._values.CameraType = r.Enum.CameraType.Scriptable
	elseif reason == "subject" then
		camera._values.CameraSubject = nil
	elseif reason == "thirdperson" then
		player.CameraMode = r.Enum.CameraMode.Classic
	else
		show(2, 1, "energy", 1, "key", "caught")
	end
	controller:_step(now)
	assert(
		not controller._visual and not controller._gesture,
		"Visibility/cancel guard failed: " .. reason
	)
	minimap._expanded, capture._state.active, gui.MenuIsOpen, humanoid.Health =
		false, false, false, 100
	camera:SetAttribute("CornCaptureCameraOwner", nil)
	camera._values.CameraType, camera._values.CameraSubject, player.CameraMode =
		r.Enum.CameraType.Custom, humanoid, r.Enum.CameraMode.LockFirstPerson
	show(2, 1, "energy", 1, "energy")
end
local oldVisual = controller._visual
local replacement = make("Camera")
replacement._values.CameraSubject = humanoid
replacement.Parent = world
world.CurrentCamera = replacement
controller:_step(now)
assert(
	oldVisual.Destroyed and not controller._visual,
	"Camera replacement did not clean old owned model"
)
controller:_step(now)
assert(
	controller._visual and controller._visual.Parent == replacement,
	"Eligible replacement camera did not use latest selection"
)
controller:Clear("fixture")
local foreign = make("Model")
foreign.Name = "CornHandheld"
foreign.Parent = replacement
show(3, 0, "none", 1, "key")
assert(
	not controller._visual and foreign.Parent == replacement and not foreign.Destroyed,
	"Foreign held model changed"
)
foreign:Destroy()
controller:_step(now)
assert(controller._visual)
local old = controller._visual
player.CharacterRemoving:Fire(hero)
assert(old.Destroyed and controller._snapshot == nil and not controller._visual)
local nextHero, nextHumanoid = character()
player.Character, humanoid, hero = nextHero, nextHumanoid, nextHero
replacement._values.CameraSubject = nextHumanoid
player.CharacterAdded:Fire(nextHero)
controller:_step(now)
assert(not controller._visual, "Respawn reused stale inventory snapshot")
show(4, 3, "trap", 2, "energy")
assert(
	controller._visual
		and not controller._gesture
		and controller._visual.RightHand.Color == nextHero:FindFirstChild("RightHand").Color
)
controller:SetSnapshot({ inventory = { slots = {} } })
assert(not controller._visual and controller._snapshot == nil)
local connections = table.clone(controller._connections)
controller:Destroy()
for _, connection in connections do
	assert(not connection.Connected, "Handheld connection leaked")
end
assert(next(bindings) == nil and #controller._connections == 0)
assert(cameraWrites == 0 and rootWrites == 0, "Presentation wrote camera or gameplay Root")
print(
	"PASS: authoritative selected geometry/initial-sync skip, avatar skin/safe flags/<=24parts, no rebuild and onePivot/frame, acceptedenergy/trap consumption/deadlines, duplicate/out-of-order IDs, selection/terminal/retry/death/capture/menu/map/foreigncamera/replacement/reset guards, foreign model preservation,0camera/Rootwrites and cleanup"
)
