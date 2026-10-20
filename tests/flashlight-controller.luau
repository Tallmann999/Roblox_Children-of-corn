-- Execute actual production controller with the established Instance/signal
-- adapter. This is deterministic lifecycle coverage, not native rendering.
local fs = require("@lune/fs")
local base = fs.readFile("tests/handheld-controller.luau")
local boundary = assert(
	base:find('local module = load("src/client/Controllers/HandheldController.luau"', 1, true)
)
local setup = base:sub(1, boundary - 1)
local checks = [==[
local Flashlight = load("src/shared/Game/FlashlightPresentation.luau", {
	CFrame = r.CFrame, Vector3 = r.Vector3, Vector2 = r.Vector2,
	Color3 = r.Color3, Enum = r.Enum,
	NumberSequence = r.NumberSequence, NumberSequenceKeypoint = r.NumberSequenceKeypoint,
	ColorSequence = r.ColorSequence,
})
function methods:GetAttributes() return table.clone(self._attributes) end
function methods:GetTags() return table.clone(self._tags or {}) end
local originalMake = make
local created, allocation, failAt = {}, 0, nil
make = function(class)
	allocation += 1
	if allocation == failAt then error("expected allocation failure") end
	local item = originalMake(class)
	item._values.ClassName = class
	local meta = getmetatable(item)
	local originalWrite = meta.__newindex
	meta.__newindex = function(object, key, value)
		if ((class == "SpotLight" or class == "PointLight") and key == "Brightness") or (class == "Beam" and (key == "Width0" or key == "Width1")) then
			local bytes = buffer.create(4)
			buffer.writef32(bytes, 0, value)
			value = buffer.readf32(bytes, 0)
		end
		return originalWrite(object, key, value)
	end
	table.insert(created, item)
	return item
end
local map = make("Model")
map.Name, map.Parent = "CornMap", world
map:SetAttribute("corn_project_id", "children_of_corn")
map:SetAttribute("HarvestArtVariant", "A")
local data = make("ModuleScript")
data.Name, data.Parent = "FlashlightPresentation", games
local root = hero:FindFirstChild("HumanoidRootPart")
root.Position, root.AssemblyLinearVelocity = r.Vector3.new(0, 20, 0), r.Vector3.zero
humanoid.FloorMaterial = r.Enum.Material.Grass
rootWrites = 0
local rayCount = 0
function world:Raycast() rayCount += 1; error("Surface-light lamp must not cast decorative rays") end
local input = { WindowFocusReleased = signal(), WindowFocused = signal(), focused = nil }
function input:GetFocusedTextBox() return self.focused end
local actions = {}
local cas = {}
function cas:BindActionAtPriority(name, fn, touch, priority, key)
	assert(name == "CornFlashlightToggle" and priority == 3000 and not touch and key == r.Enum.UserInputType.MouseButton1)
	assert(not actions[name])
	actions[name] = fn
end
function cas:UnbindAction(name) actions[name] = nil end
local priorities = {}
function run:BindToRenderStep(name, priority, fn)
	assert(not bindings[name])
	assert(priority == r.Enum.RenderPriority.Camera.Value - 1 or priority == r.Enum.RenderPriority.Camera.Value + 1)
	bindings[name], priorities[name] = fn, priority
end
function run:UnbindFromRenderStep(name) bindings[name], priorities[name] = nil, nil end
services.UserInputService, services.ContextActionService = input, cas
local module = load("src/client/Controllers/FlashlightController.luau", {
	game = { GetService = function(_, name) return assert(services[name], name) end },
	workspace = world, Instance = {new = function(class) return make(class) end},
	CFrame = r.CFrame, Vector3 = r.Vector3, Vector2 = r.Vector2,
	Color3 = r.Color3, Enum = r.Enum,
	RaycastParams = {new = function() return {} end},
	typeof = function(value)
		return typeof(value)
	end,
	script = {Parent={Parent={WaitForChild=function(_,name) assert(name=="Game");return {WaitForChild=function(_,n)assert(n=="FlashlightTuning");return {Name=n}end}end}}},
 require = function(node) if node.Name=="FlashlightPresentation" then return Flashlight end;assert(node.Name=="FlashlightTuning");return {new=function()error("Unexpected Studio UI in adapter")end}end,
	warn = function() end,
})
local controller = setmetatable({}, {__index = module})
local movement = {_cursorOpen = false, _mapOpen = false}
local minimap, capture = {_expanded = false}, {_state = {active = false}}
controller:Init({})
controller:Start({Controllers = {MovementController = movement, MinimapController = minimap, CaptureController = capture}})
local function show(id, phase)
	controller:SetSnapshot({minimap = {round_id = id}, phase = phase or "active"})
end
local function render(dt, normalFrame)
	if bindings.CornFlashlightCameraBase then bindings.CornFlashlightCameraBase(dt) end
	if normalFrame then camera.CFrame = normalFrame end
	if bindings.CornFlashlightPresentation then bindings.CornFlashlightPresentation(dt) end
end
local function f(state)
	return actions.CornFlashlightToggle(nil, state or r.Enum.UserInputState.Begin)
end
local function lightsEnabled(expected)
	assert(controller._visual and #controller._lights == 3)
	for _, record in controller._lights do assert(record.item.Enabled == expected) end
	for _, item in controller._visual:GetDescendants() do assert(not item:IsA("Beam"), "Rejected air tunnel returned") end
end
local function noVisual()
	assert(not controller._visual and not camera:FindFirstChild("CornPersonalFlashlight"))
end
local function exactRestore(expected)
	controller:_unapplyCamera()
	assert(camera.CFrame == expected, "Camera did not restore the exact unmodified base")
end
assert(f() == r.Enum.ContextActionResult.Pass and not next(bindings))
show(1)
assert(controller._visual and controller._on and controller._bound)
assert(#controller._parts == #Flashlight.Definitions() and #controller._parts <= 11)
assert(priorities.CornFlashlightCameraBase == r.Enum.RenderPriority.Camera.Value - 1)
assert(priorities.CornFlashlightPresentation == r.Enum.RenderPriority.Camera.Value + 1)
lightsEnabled(true)
assert(controller._lights[2].item.Brightness ~= 15.08, "Mock must model native float32 property readback")
local handFill = controller._lights[3].item
assert(handFill.ClassName == "SpotLight" and handFill.Name == "HandFill")
assert(handFill.Parent.Name == "HandFillAim" and handFill.Range == 1.5 and handFill.Angle == 75 and not handFill.Shadows)
assert(handFill.Brightness ~= .08 and math.abs(handFill.Brightness-.08) < 1e-7)
assert(controller:_visualOwned(), "Rounded engine light properties must remain owned")
assert(controller._lights[1].item.Angle == 26 and controller._lights[2].item.Angle == 54)
assert(rayCount == 0, "Snapshot refresh cast outside a render step")
for _, item in controller._visual:GetDescendants() do assert(not item:IsA("PointLight"), "Spherical hand-fill survived") end
for _, record in controller._parts do
	local part = record.item
	assert(part.Anchored and not part.CanCollide and not part.CanTouch and not part.CanQuery and not part.CastShadow)
	if part.Name == "LeftPalm" or part.Name == "LeftThumb" then
		assert(part.Color == hero:FindFirstChild("LeftHand").Color)
	end
end
assert(f() == r.Enum.ContextActionResult.Sink)
lightsEnabled(false)
show(1)
lightsEnabled(false)
assert(f(r.Enum.UserInputState.End) == r.Enum.ContextActionResult.Pass and not controller._on)
assert(f() == r.Enum.ContextActionResult.Sink)
lightsEnabled(true)
assert(rayCount == 0, "Mouse toggles must not multiply per-frame raycasts")

-- The same exact lens attachment emits the bright circular core and weak spill.
local main, fill = controller._lights[1].item, controller._lights[2].item
assert(main.Parent == fill.Parent and main.Parent.Name == "LensAim")
assert(main.Parent.Parent.Name == "Lens")
assert(main.Face == r.Enum.NormalId.Front and fill.Face == main.Face)
assert(main.Range == 24 and math.abs(main.Brightness-22.62)<1e-5 and not main.Shadows)
assert(fill.Range == 24 and math.abs(fill.Brightness-15.08)<1e-5 and not fill.Shadows)
render(1/60)
assert(rayCount == 0 and controller:_visualOwned())
local emitter = main.Parent.Parent
local axis = emitter.CFrame * main.Parent.CFrame
assert(axis.LookVector:Dot(emitter.CFrame.RightVector) > .9999)
assert((axis.Position-emitter.CFrame:PointToWorldSpace(r.Vector3.new(emitter.Size.X/2,0,0))).Magnitude < 1e-5)
assert(main.Angle < fill.Angle and main.Brightness > fill.Brightness)
assert(f(r.Enum.UserInputState.Change) == r.Enum.ContextActionResult.Pass and controller._on)

-- Repeated render updates use the default camera frame as their base: no
-- accumulating inverse and no modification of avatar/gameplay properties.
local normal = r.CFrame.new(10, 22, 4) * r.CFrame.Angles(.1, .4, 0)
root._values.AssemblyLinearVelocity = r.Vector3.new(12, 0, 0)
for _ = 1, 120 do
	render(1/60, normal)
	assert((camera.CFrame.Position-normal.Position).Magnitude < .08)
	assert(controller._effect and controller._effect.base == normal)
end
local rendered = camera.CFrame
assert(rendered ~= normal)
exactRestore(normal)
render(1/60, normal)
local foreignFrame = r.CFrame.new(50, 33, -10) * r.CFrame.Angles(.5, -.2, 0)
camera.CFrame = foreignFrame
controller:_unapplyCamera()
assert(camera.CFrame == foreignFrame, "A newer mouse-look frame was overwritten")
render(1/60, normal)
camera:SetAttribute("CornCaptureCameraOwner", "foreign capture token")
local captured = camera.CFrame
controller:Clear("capture begins")
assert(camera.CFrame == captured, "Capture ownership must prevent camera restoration")
noVisual()
assert(not next(bindings))
camera:SetAttribute("CornCaptureCameraOwner", nil)
camera.CFrame = normal
show(1)

-- Free cursor, expanded map, menu, focused textbox and window blur all
-- suppress body/light/bob and pass LMB without changing the remembered toggle.
for _, condition in {"cursor", "map", "movementMap", "menu", "textbox", "capture", "blur"} do
	if condition == "cursor" then movement._cursorOpen = true
	elseif condition == "map" then minimap._expanded = true
	elseif condition == "movementMap" then movement._mapOpen = true
	elseif condition == "menu" then gui.MenuIsOpen = true; gui.MenuOpened:Fire()
	elseif condition == "textbox" then input.focused = {}
	elseif condition == "capture" then capture._state.active = true
	else input.WindowFocusReleased:Fire() end
	render(1/60, normal)
	noVisual()
	assert(camera.CFrame == normal and f() == r.Enum.ContextActionResult.Pass and controller._on)
	movement._cursorOpen, movement._mapOpen, minimap._expanded = false, false, false
	gui.MenuIsOpen, input.focused, capture._state.active = false, nil, false
	input.WindowFocused:Fire()
	render(1/60, normal)
	lightsEnabled(true)
end

-- Death, rig replacement, camera replacement and terminal snapshots clean
-- exact owned nodes; the new camera still receives the default user frame.
local previousModel = controller._visual
humanoid.Health = 0
render(1/60, normal)
noVisual()
assert(previousModel.Destroyed)
humanoid.Health = 100
show(1)
local previousCamera = camera
local replacement = make("Camera")
replacement.CameraSubject, replacement.Parent, replacement.CFrame = humanoid, world, normal
world.CurrentCamera = replacement
controller:_step(1/60)
assert(not previousCamera:FindFirstChild("CornPersonalFlashlight") and controller._visual.Parent == replacement)
camera = replacement
player.CharacterRemoving:Fire(hero)
noVisual()
assert(not next(bindings))
show(1)
show(1,"caught")
noVisual()
assert(not next(bindings))
show(1)
assert(controller._visual)
f()
show(1,"escaped")
noVisual()
assert(not next(bindings))
show(1)
noVisual()
show(2)
lightsEnabled(true)
show(1,"aborted")
assert(controller._roundId == 2 and controller._visual, "Stale snapshots changed current round")
map:SetAttribute("HarvestArtVariant", "B")
show(2)
lightsEnabled(true)
map:SetAttribute("HarvestArtVariant", "foreign")
show(2)
noVisual()
assert(not next(bindings) and f() == r.Enum.ContextActionResult.Pass)
map:SetAttribute("HarvestArtVariant", "A")
show(2)

-- An unknown same-name model is never adopted/deleted. A foreign child
-- inserted into our own subtree survives; only our exact known lights quench.
local compromised = controller._visual
local foreign = make("Folder")
foreign.Name, foreign.Parent = "AuthorChild", compromised
local ownedLights = table.clone(controller._lights)
render(1/60, normal)
assert(not controller._visual and not compromised.Destroyed and foreign.Parent == compromised)
for _, record in ownedLights do assert(not record.item.Enabled) end
show(2)
assert(not controller._visual and compromised.Parent == camera)
compromised:Destroy() -- Test author, not controller, removes the changed model.
local impostor = make("Model")
impostor.Name, impostor.Parent = "CornPersonalFlashlight", camera
show(2)
assert(not controller._visual and not impostor.Destroyed)
impostor:Destroy()
show(2)
local edited = controller._visual
controller._parts[1].item.Size += r.Vector3.new(.1,0,0)
controller:Clear("author edit")
assert(not edited.Destroyed and edited.Parent == camera)
edited:Destroy()
show(2)
local retagged = controller._visual
retagged:SetAttribute("corn_project_id", "another project")
controller:Clear("foreign ownership")
assert(not retagged.Destroyed and retagged:GetAttribute("corn_project_id") == "another project")
retagged:Destroy()

show(2)
local nestedModel = controller._visual
local nestedLight = controller._lights[1].item
local authorChild = make("Folder")
authorChild.Name, authorChild.Parent = "AuthorLightChild", nestedLight
controller:Clear("light foreign child")
assert(not nestedModel.Destroyed and authorChild.Parent == nestedLight and not nestedLight.Enabled)
nestedModel:Destroy()

-- Partial allocation is unpublished and rolled back, then a retry works.
for _, offset in {#Flashlight.Definitions()+2, #Flashlight.Definitions()+3, #Flashlight.Definitions()+4, #Flashlight.Definitions()+5} do
	failAt = allocation + offset
	local before = #created
	show(2)
	assert(not controller._visual)
	for index = before+1, #created do assert(created[index].Destroyed, "Partial allocation leaked an Instance") end
end
failAt = nil
show(2)
lightsEnabled(true)
controller:SetSnapshot({phase="active",minimap={round_id=0/0}})
assert(controller._visual and controller._roundId == 2)
controller:SetSnapshot({phase="unknown",minimap={round_id=2}})
noVisual()
assert(not next(bindings))
show(3)
local finalModel = controller._visual
controller:Destroy()
noVisual()
assert(finalModel.Destroyed and not next(bindings) and not next(actions))
assert(rootWrites == 0, "Flashlight modified a gameplay Root")
player.CharacterAdded:Fire(hero)
input.WindowFocused:Fire()
assert(not controller._visual and not next(bindings))
print("PASS: real FlashlightController A/B LMB toggle/default-on/lifecycle, 11 parts/three lens-directed spots/no sphere or air Beams, shared core/spill lens and forward axis, no decorative raycasts, camera rollback/no accumulation, cursor/map/menu/capture/death/respawn cleanup, foreign subtree edits preserved, light allocation rollback, no Root writes")
]==]
assert(loadstring(setup .. checks, "flashlight-controller"))()
