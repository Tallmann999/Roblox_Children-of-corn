-- Actual capture timing/controller methods with deterministic camera/Instance signals.
-- No engine rendering/physics or real-catch claim; Studio fixture covers actual objects.
local fs = require("@lune/fs")
local r = require("@lune/roblox")
local function datatype(value)
	if type(value) == "userdata" and pcall(function()
		return value:GetComponents()
	end) then
		return "CFrame"
	end
	if type(value) == "userdata" and pcall(function()
		return value.Magnitude
	end) then
		return "Vector3"
	end
	return typeof(value)
end
local function load(path, env)
	local fn = assert(loadstring(fs.readFile(path), path))
	setfenv(fn, setmetatable(env, { __index = getfenv() }))
	return fn()
end
local Capture =
	load("src/shared/Game/CapturePresentation.luau", { CFrame = r.CFrame, typeof = datatype })
local Pose = load(
	"src/shared/Game/MonsterPose.luau",
	{ CFrame = r.CFrame, Vector3 = r.Vector3, Color3 = r.Color3, Enum = r.Enum }
)
local empty = { id = 0, remaining = 0, frame = r.CFrame.identity }
local value = {
	id = 1,
	remaining = 1,
	frame = r.CFrame.new(10, 17, 10) * r.CFrame.Angles(0, math.rad(30), 0),
}
assert(Capture.IsValidSnapshot(empty) and Capture.IsValidSnapshot(value))
for _, bad in
	{
		{ id = -1, remaining = 1 },
		{ id = 0, remaining = 1 },
		{ id = 3, remaining = 0 },
		{ id = 0.5, remaining = 0 },
		{ id = 1, remaining = -0.1 },
		{ id = 1, remaining = 1.01 },
		{ id = 1, remaining = math.huge },
		{ id = 1, remaining = 0 / 0 },
	}
do
	bad.frame = r.CFrame.identity
	assert(not Capture.IsValidSnapshot(bad), "Malformed capture accepted")
end
assert(not Capture.IsValidSnapshot({ id = 1, remaining = 1, frame = "untrusted" }))
local state = Capture.NewState()
assert(Capture.Observe(state, 1, value, "caught", 100) == "begin" and state.deadline == 101)
assert(
	Capture.Observe(state, 1, value, "caught", 100.9) == "keep" and state.deadline == 101,
	"Duplicate extends capture"
)
assert(Capture.Progress(state, 100) == 0 and Capture.Progress(state, 100.7) > 0.999)
assert(Capture.Observe(state, 1, value, "caught", 101) == "cancel")
assert(
	Capture.Observe(state, 1, value, "caught", 101.1) == "none",
	"Capture replayed after deadline"
)
assert(Capture.Observe(state, 2, value, "caught", 102) == "begin")
assert(Capture.Observe(state, 3, empty, "preparing", 102.2) == "cancel" and state.roundId == 3)
assert(
	Capture.Observe(state, 2, value, "caught", 102.3) == "none" and state.roundId == 3,
	"Stale round rewound identity"
)
assert(Capture.Observe(state, 3, value, "caught", 103) == "begin")
local short = table.clone(value)
short.remaining = 0.1
assert(Capture.Observe(state, 3, short, "caught", 103.2) == "keep" and state.deadline <= 103.31)
assert(Capture.Observe(state, 3, nil, "caught", 103.21) == "cancel")
assert(
	Capture.Observe(state, 3, value, "caught", 103.3) == "none",
	"Malformed cancellation allowed replay"
)
print(
	"PASS: capture schema/finite frames, round+id dedup, late snapshots, shortening-only deadline, stale round/malformed cancellation and bounded progress"
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
local function make(class)
	return setmetatable({
		_class = class,
		_children = {},
		_attributes = {},
		_values = {
			Name = class,
			CFrame = r.CFrame.identity,
			Focus = r.CFrame.identity,
			Size = r.Vector3.one,
			Health = 100,
			Died = signal(),
			LocalTransparencyModifier = 0,
			FieldOfView = 85,
			CameraType = r.Enum.CameraType.Custom,
		},
	}, {
		__index = function(item, key)
			if key == "Position" then
				return item._values.CFrame.Position
			end
			return methods[key] or item._values[key]
		end,
		__newindex = function(item, key, value)
			if key == "Parent" then
				local old = item._values.Parent
				if old then
					local index = table.find(old._children, item)
					if index then
						table.remove(old._children, index)
					end
				end
				if value then
					table.insert(value._children, item)
				end
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
local world, storage = make("Workspace"), make("ReplicatedStorage")
local shared = make("Folder")
shared.Name = "GameShared"
shared.Parent = storage
local games = make("Folder")
games.Name = "Game"
games.Parent = shared
for _, name in { "CapturePresentation", "MonsterPose", "RoundText" } do
	local item = make("ModuleScript")
	item.Name = name
	item.Parent = games
end
local network = make("Folder")
network.Name = "Network"
network.Parent = shared
local endpoint = make("ModuleScript")
endpoint.Name = "EndpointNames"
endpoint.Parent = network
local player = { CharacterAdded = signal(), CharacterRemoving = signal() }
local function character(position)
	local model = make("Model")
	model.Parent = world
	local humanoid = make("Humanoid")
	humanoid.Parent = model
	local root = make("Part")
	root.Name = "HumanoidRootPart"
	root.CFrame = r.CFrame.new(position)
	root.Parent = model
	return model, humanoid, root
end
local hero, humanoid, heroRoot = character(r.Vector3.new(1, 17, 1))
player.Character = hero
local camera = make("Camera")
camera.CFrame = r.CFrame.new(1, 20, 1)
camera.CameraSubject = humanoid
camera.Parent = world
world.CurrentCamera = camera
local map = make("Model")
map.Name = "CornMap"
map:SetAttribute("corn_project_id", "children_of_corn")
map.Parent = world
local runtime = make("Folder")
runtime.Name = "CornRoundRuntime"
runtime:SetAttribute("corn_project_id", "children_of_corn")
runtime.Parent = map
local monster = make("Model")
monster.Name = "Monster"
monster:SetAttribute("CornMonsterOwned", true)
monster:SetAttribute("corn_project_id", "children_of_corn")
monster:SetAttribute("MonsterRigVersion", 1)
monster.Parent = runtime
local invisibleRoot = make("Part")
invisibleRoot.Name = "Root"
invisibleRoot.Parent = monster
local originalParts = {}
for _, definition in Pose.Parts do
	local part = make("Part")
	part.Name = definition.Name
	part.Size = definition.Size
	part.Parent = monster
	part.LocalTransparencyModifier = 0.2
	originalParts[part.Name] = part
end
local now, delays, bindings, guid = 10, {}, {}, 0
local guiService = { MenuIsOpen = false, MenuOpened = signal() }
local run = {
	BindToRenderStep = function(_, name, priority, fn)
		assert(priority == r.Enum.RenderPriority.Camera.Value + 1)
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
	GuiService = guiService,
	HttpService = {
		GenerateGUID = function()
			guid += 1
			return tostring(guid)
		end,
	},
	ContextActionService = {},
	UserInputService = {},
}
local env = {
	game = {
		GetService = function(_, name)
			return assert(services[name], name)
		end,
	},
	workspace = world,
	Instance = { new = make },
	CFrame = r.CFrame,
	Vector3 = r.Vector3,
	Color3 = r.Color3,
	Enum = r.Enum,
	typeof = datatype,
	os = {
		clock = function()
			return now
		end,
	},
	task = {
		delay = function(duration, fn)
			table.insert(delays, { at = now + duration, fn = fn })
		end,
	},
	require = function(item)
		return if item.Name == "CapturePresentation"
			then Capture
			elseif item.Name == "MonsterPose" then Pose
			else {}
	end,
	warn = function() end,
}
local Module = load("src/client/Controllers/CaptureController.luau", env)
local controller = setmetatable({}, { __index = Module })
local movement = {
	SetCaptureActive = function(self, value)
		self.capture = value
	end,
}
local minimap = {
	_expanded = true,
	SetExpanded = function(self, value)
		self._expanded = value
	end,
}
local hud = {
	SetCaptureActive = function(self, value)
		self.capture = value
	end,
}
controller:Init({})
controller:Start({
	Controllers = {
		MovementController = movement,
		MinimapController = minimap,
		RoundController = { _hud = hud },
	},
})
local function snapshot(roundId, id, remaining, phase)
	return {
		minimap = { round_id = roundId },
		capture = { id = id, remaining = remaining, frame = value.frame },
		phase = phase or "caught",
		start_look = r.Vector3.new(0, 0, -1),
	}
end
local function advance(time)
	now = time
	for _, event in delays do
		if not event.fired and event.at <= now then
			event.fired = true
			event.fn()
		end
	end
end
local function clean()
	assert(
		not controller._state.active
			and not controller._bound
			and not world:FindFirstChild("CornCaptureVisual")
	)
	assert(not movement.capture and not hud.capture and next(bindings) == nil)
end
controller:SetSnapshot(snapshot(1, 1, 1))
assert(controller._bound and movement.capture and hud.capture and not minimap._expanded)
assert(camera.CameraType == r.Enum.CameraType.Scriptable and camera.FieldOfView == 70)
assert(controller._state.frame == value.frame, "Presentation changed authoritative capture frame")
assert(
	controller._parts.Head.CFrame
		== value.frame * r.CFrame.new(0, 4, 0) * Pose.Get("capturing", 0, false).Head,
	"Capture visual was not lifted exactly four local studs"
)
assert(#controller._visual:GetChildren() == 9 and #controller._hiddenServer == 9)
assert(invisibleRoot.LocalTransparencyModifier == 0, "Root was hidden")
for _, part in originalParts do
	assert(part.LocalTransparencyModifier == 1)
end
now = 10.5
controller:_step(now)
assert(
	controller._parts.Head.CFrame
		== value.frame * r.CFrame.new(0, 4, 0) * Pose.Get("capturing", 0.5, false).Head,
	"Animated capture lost presentation offset"
)
assert(camera.FieldOfView < 70 and camera.FieldOfView > 62)
minimap._expanded = true
controller:_step(now)
assert(not minimap._expanded)
now = 10.9
controller:SetSnapshot(snapshot(1, 1, 1))
assert(controller._state.deadline == 11)
heroRoot.CFrame = r.CFrame.new(-100, 17, -100)
advance(11)
clean()
assert(
	camera.FieldOfView == 85
		and camera.CameraType == r.Enum.CameraType.Custom
		and camera:GetAttribute("CornCaptureCameraOwner") == nil
)
assert(
	(camera.CFrame.Position - heroRoot.Position).Magnitude < 2,
	"Camera restored old catch location"
)
for _, part in originalParts do
	assert(part.LocalTransparencyModifier == 0.2)
end
controller:SetSnapshot(snapshot(1, 1, 1))
clean()
now = 12
controller:SetSnapshot(snapshot(1, 2, 1))
assert(controller._state.active, "Second catch not presented")
originalParts.Head.LocalTransparencyModifier = 0.4
controller:SetSnapshot(nil)
clean()
assert(originalParts.Head.LocalTransparencyModifier == 0.4, "Manual modifier overwritten")
now = 13
controller:SetSnapshot(snapshot(2, 1, 1))
guiService.MenuIsOpen = true
guiService.MenuOpened:Fire()
clean()
guiService.MenuIsOpen = false
controller:SetSnapshot(snapshot(2, 1, 1))
clean()
now = 14
controller:SetSnapshot(snapshot(2, 2, 1))
local replacement = make("Camera")
replacement.FieldOfView = 93
replacement.Parent = world
world.CurrentCamera = replacement
controller:_step(now + 0.1)
clean()
assert(
	replacement.FieldOfView == 93 and replacement.CameraType == r.Enum.CameraType.Custom,
	"Replacement camera altered"
)
world.CurrentCamera = camera
now = 15
controller:SetSnapshot(snapshot(3, 1, 1))
camera:SetAttribute("CornCaptureCameraOwner", "foreign")
camera.FieldOfView = 44
controller:Cancel("external ownership")
clean()
assert(
	camera.FieldOfView == 44 and camera:GetAttribute("CornCaptureCameraOwner") == "foreign",
	"External camera owner overwritten"
)
camera:SetAttribute("CornCaptureCameraOwner", nil)
camera.CameraType = r.Enum.CameraType.Custom
camera.FieldOfView = 85
now = 15.1
controller:SetSnapshot(snapshot(3, 2, 1))
camera.CameraType = r.Enum.CameraType.Fixed
camera.FieldOfView = 48
controller:_step(now + 0.1)
clean()
assert(
	camera.CameraType == r.Enum.CameraType.Fixed
		and camera.FieldOfView == 48
		and camera:GetAttribute("CornCaptureCameraOwner") == nil,
	"External type change overwritten or own token leaked"
)
camera.CameraType = r.Enum.CameraType.Custom
camera.FieldOfView = 85
local foreign = make("Model")
foreign.Name = "CornCaptureVisual"
foreign.Parent = world
controller:SetSnapshot(snapshot(4, 1, 1))
assert(
	not controller._state.active and foreign.Parent == world and not foreign.Destroyed,
	"Foreign visual changed"
)
foreign:Destroy()
now = 16
controller:SetSnapshot(snapshot(5, 1, 1))
humanoid.Health = 0
humanoid.Died:Fire()
clean()
humanoid.Health = 100
now = 17
controller:SetSnapshot(snapshot(5, 2, 1))
local newHero, newHumanoid, newRoot = character(r.Vector3.new(200, 17, 200))
player.Character = newHero
player.CharacterAdded:Fire(newHero)
clean()
assert(
	camera.CameraSubject == newHumanoid
		and (camera.CFrame.Position - newRoot.Position).Magnitude < 2,
	"Respawn camera uses old character"
)
local connections = table.clone(controller._connections)
controller:Destroy()
for _, connection in connections do
	assert(not connection.Connected, "Capture listener leaked")
end
assert(#controller._connections == 0 and controller._deathConnection == nil)
print(
	"PASS: actual controller9-part visual/face light, camera/FOV/Camera+1 ownership, no duplicate extension, wall-clock cleanup, new spawn restoration, server9-part LTM guard, menu/death/respawn/camera replacement/foreign visual and cleanup"
)

local Movement = load("src/client/Controllers/MovementController.luau", env)
local release = 0
local move = setmetatable({
	_captureActive = false,
	_active = true,
	_cursorOpen = true,
	_mapOpen = true,
	_shifts = { shift = true },
	_intentValue = true,
	_remote = {
		FireServer = function(_, value)
			assert(value == false)
			release += 1
		end,
	},
	_gui = {},
	_staminaPanel = {},
	_cursorGuard = {},
	_roundLeave = {},
	_snapshot = nil,
}, { __index = Movement })
move:SetCaptureActive(true)
assert(
	release == 1
		and not move._mapOpen
		and not move._cursorOpen
		and not move._gui.Enabled
		and not move._roundLeave.Modal
)
move:SetMapOpen(true)
assert(not move._mapOpen)
local previousFrame = camera.CFrame
move:_camera()
assert(camera.CFrame == previousFrame, "Movement altered capture camera")
print(
	"PASS: actual Movement capture guard releases sprint/cursor/map, suppresses stamina/modal UI and camera reset"
)
