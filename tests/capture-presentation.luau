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
local headMotion = 0
local previousShake = Capture.HeadShake(0)
for index = 0, 100 do
	local elapsed = index / 100
	local shake = Capture.HeadShake(elapsed)
	local cameraShake = Capture.CameraShake(elapsed)
	for _, frame in { shake, cameraShake } do
		for _, component in { frame:GetComponents() } do
			assert(component == component and math.abs(component) < 2)
		end
	end
	local _, headAngle = shake:ToAxisAngle()
	local _, cameraAngle = cameraShake:ToAxisAngle()
	assert(headAngle < math.rad(28), "Head motion escaped its visual bound")
	assert(cameraAngle < math.rad(1.1) and cameraShake.Position.Magnitude < 0.035)
	headMotion += (shake.LookVector - previousShake.LookVector).Magnitude
	previousShake = shake
	assert(Capture.MouthOpen(elapsed) >= 0.3 and Capture.MouthOpen(elapsed) <= 1)
	assert(Capture.PaintOpacity(elapsed) >= 0 and Capture.PaintOpacity(elapsed) <= 0.88)
end
assert(headMotion > 5, "Head did not shake rapidly during the single-second capture")
assert(Capture.MouthOpen(0) == 0.3 and Capture.MouthOpen(0.3) == 1)
assert(Capture.PaintOpacity(0.4) == 0 and Capture.PaintOpacity(0.6) > 0.8)
assert(Capture.PaintOpacity(1) < 0.000001 and #Capture.PaintDrops == 21)
assert(Capture.HeadShake(0 / 0) == r.CFrame.identity)
print(
	"PASS: capture identity/deadline plus bounded rapid head shake, mild camera motion, opening mouth and timed paint"
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
function methods:GetDescendants()
	local result = {}
	for _, child in self._children do
		table.insert(result, child)
		for _, descendant in child:GetDescendants() do
			table.insert(result, descendant)
		end
	end
	return result
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
local playerGui = make("PlayerGui")
local player = {
	CharacterAdded = signal(),
	CharacterRemoving = signal(),
	FindFirstChildOfClass = function(_, class)
		return if class == "PlayerGui" then playerGui else nil
	end,
}
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
monster:SetAttribute("MonsterIndex", 1)
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
local function extraRig(index)
	local model = make("Model")
	model.Name = "Monster" .. index
	model:SetAttribute("CornMonsterOwned", true)
	model:SetAttribute("corn_project_id", "children_of_corn")
	model:SetAttribute("MonsterRigVersion", 1)
	model:SetAttribute("MonsterIndex", index)
	model.Parent = runtime
	local root = make("Part")
	root.Name, root.Parent = "Root", model
	local parts = {}
	for _, definition in Pose.Parts do
		local part = make("Part")
		part.Name, part.Size, part.Parent = definition.Name, definition.Size, model
		part.LocalTransparencyModifier = index / 10
		parts[part.Name] = part
	end
	return model, root, parts
end
local secondMonster, secondRoot, secondParts = extraRig(2)
local thirdMonster, thirdRoot, thirdParts = extraRig(3)
local fourthMonster, fourthRoot, fourthParts = extraRig(4)
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
	Vector2 = r.Vector2,
	UDim2 = r.UDim2,
	UDim = r.UDim,
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
			and not playerGui:FindFirstChild("CornCapturePaint")
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
assert(#controller._visual:GetChildren() == 13 and #controller._hiddenServer == 27)
assert(#controller._paint:GetChildren() == 21 and #controller._paintDrops == 21)
local paintGui = controller._paint
for _, drop in controller._paintDrops do
	assert(not drop.Active and not drop.Selectable and drop.BackgroundTransparency == 1)
end
for _, part in controller._mouthParts do
	assert(part.Anchored and not part.CanCollide and not part.CanQuery and not part.CanTouch)
end
assert(invisibleRoot.LocalTransparencyModifier == 0, "Root was hidden")
assert(
	secondRoot.LocalTransparencyModifier == 0
		and thirdRoot.LocalTransparencyModifier == 0
		and fourthRoot.LocalTransparencyModifier == 0,
	"Additional authoritative Root hidden"
)
for _, parts in { secondParts, thirdParts } do
	for _, part in parts do
		assert(part.LocalTransparencyModifier == 1, "Additional rig not hidden")
	end
end
for _, part in fourthParts do
	assert(part.LocalTransparencyModifier == 0.4, "Fourth rig changed")
end

for _, part in originalParts do
	assert(part.LocalTransparencyModifier == 1)
end
now = 10.537
controller:_step(now)
local pose = Pose.Get("capturing", now - 10, false)
local expectedHead = value.frame * r.CFrame.new(0, 4, 0) * pose.Head * Capture.HeadShake(now - 10)
assert((controller._parts.Head.Position - expectedHead.Position).Magnitude < 0.00001)
assert((controller._parts.Head.CFrame.LookVector - expectedHead.LookVector).Magnitude < 0.00001)
for _, name in { "Hat", "LeftEye", "RightEye" } do
	local relative = controller._parts.Head.CFrame:Inverse() * controller._parts[name].CFrame
	local expected = pose.Head:Inverse() * pose[name]
	assert(
		(relative.Position - expected.Position).Magnitude < 0.00001,
		"Head detail left its shaking group"
	)
end
local mouth = controller._mouthParts.OpenMouth
assert(math.abs(mouth.Size.Y - 1.3) < 0.00001 and math.abs(mouth.Size.X - 1.85) < 0.00001)
assert((controller._parts.Head.CFrame:Inverse() * mouth.CFrame).Position.Z < -1.3)
assert(math.abs(controller._mouthParts.LowerJaw.Size.Y - 0.3) < 0.00001)
for _, drop in controller._paintDrops do
	assert(drop.BackgroundTransparency < 0.2, "Paint never appeared")
end
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
assert(paintGui.Destroyed and mouth.Destroyed, "Owned paint/mouth leaked after deadline")
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
for _, parts in { secondParts, thirdParts } do
	for _, part in parts do
		assert(
			part.LocalTransparencyModifier == (if parts == secondParts then 0.2 else 0.3),
			"Extra rig restore failed"
		)
	end
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
local foreignPaint = make("ScreenGui")
foreignPaint.Name = "CornCapturePaint"
foreignPaint.Parent = playerGui
now = 15.8
controller:SetSnapshot(snapshot(4, 2, 1))
assert(
	controller._state.active and controller._paint == nil,
	"Foreign paint should not block camera presentation"
)
controller:Cancel("foreign paint fixture")
assert(
	foreignPaint.Parent == playerGui and not foreignPaint.Destroyed,
	"Foreign overlay overwritten"
)
foreignPaint:Destroy()
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
now = 18
controller:SetSnapshot(snapshot(6, 1, 1))
local inserted = make("TextLabel")
inserted.Name = "AuthorGuiChild"
inserted.Parent = controller._paintDrops[1]
controller:Cancel("foreign child fixture")
clean()
assert(
	inserted.Parent == playerGui and not inserted.Destroyed,
	"Foreign insertion was deleted with paint"
)
inserted:Destroy()
now = 19
controller:SetSnapshot(snapshot(6, 2, 1))
local changedPaint = controller._paint
changedPaint:SetAttribute("CornCaptureOwned", false)
local transparency = controller._paintDrops[1].BackgroundTransparency
controller:_step(now + 0.6)
assert(
	controller._paintDrops[1].BackgroundTransparency == transparency,
	"Changed overlay still animated"
)
controller:Cancel("changed overlay fixture")
assert(changedPaint.Parent == playerGui and not changedPaint.Destroyed)
assert(not controller._bound and not movement.capture and not hud.capture)
changedPaint:Destroy()
clean()
-- A changed index/project must neither hide nor restore foreign visual state.
secondMonster:SetAttribute("MonsterIndex", 3)
thirdMonster:SetAttribute("corn_project_id", "foreign")
controller:_hideServerRig()
assert(#controller._hiddenServer == 9, "Foreign/index mismatch hid extra rigs")
for _, part in secondParts do
	assert(part.LocalTransparencyModifier == 0.2)
end
for _, part in thirdParts do
	assert(part.LocalTransparencyModifier == 0.3)
end
controller:_restoreServerRig()
secondMonster:SetAttribute("MonsterIndex", 2)
thirdMonster:SetAttribute("corn_project_id", "children_of_corn")
controller:_hideServerRig()
secondMonster:SetAttribute("CornMonsterOwned", false)
secondParts.Head.LocalTransparencyModifier = 0.71
thirdParts.Head.LocalTransparencyModifier = 0.61
controller:_restoreServerRig()
assert(
	secondParts.Head.LocalTransparencyModifier == 0.71
		and thirdParts.Head.LocalTransparencyModifier == 0.61,
	"Guarded restore replaced changed ownership/manual LTM"
)
local connections = table.clone(controller._connections)
controller:Destroy()
for _, connection in connections do
	assert(not connection.Connected, "Capture listener leaked")
end
assert(#controller._connections == 0 and controller._deathConnection == nil)
print(
	"PASS: actual controller13-part open-mouth/head-group and21-drop noninteractive paint, camera/FOV ownership, deadline/new spawn/three indexed server rigs/27visual LTM/0Root +fourth/foreign/index guards, menu/death/respawn/replacement/foreign visual+GUI cleanup"
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
