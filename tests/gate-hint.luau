-- Current gate-hint geometry/state/lifecycle methods with Lune CFrames/Instances.
-- GUI drawing is separately accepted in Studio; no world/file writes here.
local adapter = require("./scene-adapter")
local fs, r, I = adapter.fs, adapter.r, adapter.I
local V3, CF = r.Vector3, r.CFrame
local function node(name)
	return {
		Name = name,
		WaitForChild = function(_, child)
			return node(child)
		end,
	}
end
local callback, disconnected = nil, false
local services = {
	Players = { LocalPlayer = {} },
	GuiService = {},
	RunService = {
		RenderStepped = {
			Connect = function(_, fn)
				callback = fn
				return {
					Disconnect = function()
						disconnected = true
					end,
				}
			end,
		},
	},
}
local world = I.new("Workspace")
local map = I.new("Model")
map.Name = "CornMap"
map:SetAttribute("corn_project_id", "children_of_corn")
map.Parent = world
local gate = I.new("Model")
gate.Name = "EscapeGate"
gate:AddTag("corn_gate")
gate.Parent = map
local anchor = I.new("Part")
anchor.Name = "InteractionAnchor"
anchor.CFrame = CF.new(100, 20, -30) * CF.Angles(0, math.rad(37), 0)
anchor.Parent = gate
local source = fs.readFile("src/client/Controllers/GateHintController.luau")
	:gsub("anchor%.Position", "anchor.CFrame.Position")
local fn = assert(loadstring(source))
setfenv(
	fn,
	setmetatable({
		workspace = world,
		game = {
			GetService = function(_, name)
				return services[name]
			end,
		},
	}, { __index = getfenv() })
)
local Module = fn()
local destroyed = false
local gui = {
	Enabled = false,
	Destroy = function()
		destroyed = true
	end,
}
local controller = setmetatable(
	{ _shown = false, _elapsed = math.huge, _panel = { Visible = false }, _gui = gui },
	{ __index = Module }
)
local active = { phase = "active", has_key = false, gate_open = false }
controller:SetSnapshot(active)
local at = anchor.CFrame.Position
assert(controller:_gatePosition() == at)
assert(controller:_canShow(at + V3.new(22, 12, 0), at, true))
assert(not controller:_canShow(at + V3.new(22.001, 0, 0), at, true))
assert(not controller:_canShow(at + V3.new(0, 12.001, 0), at, true))
assert(controller:_canShow(at + V3.new(0, 0, -22), at, true), "Hint should work on both sides")
controller:_show(true)
assert(gui.Enabled and controller._panel.Visible)
assert(controller:_canShow(at + V3.new(24, 0, 0), at, true))
assert(not controller:_canShow(at + V3.new(24.001, 0, 0), at, true))
controller:_show(false)
assert(not controller:_canShow(at + V3.new(23, 0, 0), at, true), "Hysteresis entered too early")
for _, phase in { "ready", "preparing", "caught", "caught_out", "escaped", "aborted" } do
	controller:SetSnapshot(active)
	controller:_show(true)
	controller:SetSnapshot({ phase = phase, has_key = false, gate_open = false })
	assert(not gui.Enabled and not controller._shown and not controller:_canShow(at, at, true))
end
for _, state in
	{
		{ phase = "active", has_key = true, gate_open = false },
		{ phase = "active", has_key = false, gate_open = true },
		nil,
	}
do
	controller:SetSnapshot(active)
	controller:_show(true)
	controller:SetSnapshot(state)
	assert(not gui.Enabled and not controller:_canShow(at, at, true))
end
controller:SetSnapshot(nil)
assert(not controller:_canShow(at, at, true) and not controller._shown)
controller:SetSnapshot({ phase = "active" })
assert(not controller:_canShow(at, at, true))
controller:SetSnapshot(active)
assert(not controller:_canShow(at, at, false))
assert(not controller:_canShow(nil, at, true) and not controller:_canShow(at, nil, true))
controller:_show(true)
controller:SetSnapshot(active)
assert(controller._shown, "Same valid snapshot closed the hint")
anchor.CFrame = CF.new(-50, 5, 90) * CF.Angles(0, math.rad(-72), 0)
assert(controller:_gatePosition() == anchor.CFrame.Position)
assert(not controller:_canShow(at, anchor.CFrame.Position, true))
assert(controller:_canShow(anchor.CFrame.Position, anchor.CFrame.Position, true))
gate:RemoveTag("corn_gate")
assert(controller:_gatePosition() == nil)
gate:AddTag("corn_gate")
map:SetAttribute("corn_project_id", "foreign")
assert(controller:_gatePosition() == nil)
map:SetAttribute("corn_project_id", "children_of_corn")
anchor.Name = "Missing"
assert(controller:_gatePosition() == nil)
anchor.Name = "InteractionAnchor"
local updates = 0
controller._update = function()
	updates += 1
end
controller:Start({})
controller:Start({})
callback(0.01)
assert(updates == 1)
for _ = 1, 9 do
	callback(0.01)
end
assert(updates == 1, "Hint refreshed above10Hz")
callback(0.02)
assert(updates == 2)
controller:SetSnapshot({ phase = "ready", has_key = false, gate_open = false })
assert(
	not controller:_canShow(anchor.CFrame.Position, anchor.CFrame.Position, true),
	"Menu snapshot allowed stale hint to return"
)
controller:Destroy()
assert(disconnected and destroyed and controller._snapshot == nil and controller._connection == nil)

-- Actual color-only neon methods: no GUI/world object creation, projections,
-- field scans, camera/Root writes, LTM/Enabled/Material writes are permitted.
local created, colorWrites, live = 0, 0, 0
local methods = {}
local function storedPartColor(value)
	return r.Color3.fromRGB(
		math.floor(value.R * 255 + 0.00001),
		math.floor(value.G * 255 + 0.00001),
		math.floor(value.B * 255 + 0.00001)
	)
end
local function fake(class, name, parent)
	created += 1
	local item = setmetatable({
		_class = class,
		_children = {},
		_attrs = {},
		_values = {
			Name = name,
			Health = 100,
			Color = r.Color3.fromRGB(34, 191, 113),
			TextColor3 = r.Color3.fromRGB(244, 255, 247),
			Material = r.Enum.Material.Neon,
			LocalTransparencyModifier = 0.23,
			Enabled = true,
			Visible = true,
			TextTransparency = 0,
			Transparency = 0,
			AlwaysOnTop = false,
			PixelsPerStud = 16,
		},
	}, {
		__index = function(self, key)
			return methods[key] or self._values[key]
		end,
		__newindex = function(self, key, value)
			if live > 0 then
				assert(
					(self._class == "Part" and key == "Color")
						or (self._class == "TextLabel" and key == "TextColor3"),
					"Physical neon wrote forbidden property " .. self.Name .. "." .. key
				)
				colorWrites += 1
			end
			if key == "Parent" then
				local old = self._values.Parent
				if old then
					local index = table.find(old._children, self)
					if index then
						table.remove(old._children, index)
					end
				end
				if value then
					table.insert(value._children, self)
				end
			end
			self._values[key] = if self._class == "Part" and key == "Color"
				then storedPartColor(value)
				else value
		end,
	})
	item.Parent = parent
	return item
end
function methods:IsA(class)
	return self._class == class or (class == "BasePart" and self._class == "Part")
end
function methods:FindFirstChild(name)
	for _, child in self._children do
		if child.Name == name then
			return child
		end
	end
	return nil
end
function methods:FindFirstChildOfClass(class)
	for _, child in self._children do
		if child:IsA(class) then
			return child
		end
	end
	return nil
end
function methods:GetAttribute(name)
	return self._attrs[name]
end
function methods:SetAttribute(name, value)
	self._attrs[name] = value
end
function methods:GetDescendants()
	error("Neon attempted a field scan")
end
function methods:WorldToViewportPoint()
	error("Physical neon attempted a HUD projection")
end
local fakeWorld = fake("Workspace", "Workspace")
local playerGui = fake("PlayerGui", "PlayerGui")
local foreignGui = fake("ScreenGui", "CornExitBeacon", playerGui)
local hero = fake("Model", "Hero", fakeWorld)
local humanoid = fake("Humanoid", "Humanoid", hero)
local heroRoot = fake("Part", "HumanoidRootPart", hero)
local fakePlayer = { Character = hero }
local menu = { MenuIsOpen = false }
local function beacon(enabled)
	local root = fake("Model", "CornMap", fakeWorld)
	root:SetAttribute("corn_project_id", "children_of_corn")
	local props = fake("Folder", "Props", root)
	local road = fake("Model", "VillageRoad", props)
	local sign = fake("Part", "ExitSign", road)
	sign.Size, sign.CFrame = V3.new(36, 9.6, 0.9), CF.new(0, 39.4, 419.7)
	local surface = fake("SurfaceGui", "ExitTextSurface", sign)
	local text = fake("TextLabel", "ExitText", surface)
	text.Text = "ВЫХОД"
	for _, entry in
		{
			{ road, "Road" },
			{ sign, "ExitSign" },
			{ surface, "ExitTextSurface" },
			{ text, "ExitText" },
		}
	do
		entry[1]:SetAttribute("corn_project_id", "children_of_corn")
		entry[1]:SetAttribute("CornRoadExitOwned", true)
		entry[1]:SetAttribute("RoadExitVersion", 1)
		entry[1]:SetAttribute("RoadExitRole", entry[2])
	end
	surface.Enabled = enabled ~= false
	return {
		map = root,
		props = props,
		road = road,
		sign = sign,
		surface = surface,
		text = text,
		color = sign.Color,
		textColor = text.TextColor3,
	}
end
local now = 0
local neonFn = assert(loadstring(source))
setfenv(
	neonFn,
	setmetatable({
		workspace = fakeWorld,
		Enum = r.Enum,
		Color3 = r.Color3,
		game = {
			GetService = function(_, name)
				if name == "Players" then
					return { LocalPlayer = fakePlayer }
				end
				if name == "GuiService" then
					return menu
				end
				return services[name]
			end,
		},
		Instance = {
			new = function()
				error("Physical neon created a GUI/light/world object")
			end,
		},
		os = {
			clock = function()
				return now
			end,
		},
	}, { __index = getfenv() })
)
local Neon = neonFn()
for _, method in { "_blinkBeacon", "_restoreBeacon" } do
	local production = Neon[method]
	Neon[method] = function(self, ...)
		local before = colorWrites
		live += 1
		production(self, ...)
		live -= 1
		assert(colorWrites - before <= 2, "Neon exceeded two bounded color writes")
	end
end
local function controller()
	return setmetatable({
		_shown = false,
		_elapsed = math.huge,
		_panel = { Visible = false },
		_gui = { Enabled = false, Destroy = function() end },
	}, { __index = Neon })
end
local function closeColor(a, b)
	return math.abs(a.R - b.R) < 0.00001
		and math.abs(a.G - b.G) < 0.00001
		and math.abs(a.B - b.B) < 0.00001
end
local function expectColor(binding, bright)
	assert(
		closeColor(
			binding.sign.Color,
			storedPartColor(
				if bright then binding.color else binding.color:Lerp(r.Color3.new(0, 0, 0), 0.94)
			)
		)
	)
	assert(
		closeColor(
			binding.text.TextColor3,
			if bright then binding.textColor else binding.textColor:Lerp(r.Color3.new(0, 0, 0), 0.9)
		)
	)
	assert(
		binding.sign.Material == r.Enum.Material.Neon
			and binding.sign.Transparency == 0
			and binding.sign.LocalTransparencyModifier == 0.23
			and binding.surface.Enabled
			and not binding.surface.AlwaysOnTop
			and binding.surface.PixelsPerStud == 16
			and binding.text.Visible
			and binding.text.TextTransparency == 0,
		"Panel/text material, visibility or native surface properties changed"
	)
end
local binding = beacon()
local neon = controller()
neon:SetSnapshot(active)
local beforeCreated, size, frame = created, binding.sign.Size, binding.sign.CFrame
neon:_blinkBeacon(0)
for _, time in { 0, 0.79, 1.51, 2.09, 3.01, 7.49, 8.31, 14.29, 14.31, 29 } do
	neon:_blinkBeacon(time)
	expectColor(binding, true)
end
for _, time in { 0.81, 1.49, 2.11, 2.99, 7.51, 8.29, 15.11, 16.51 } do
	neon:_blinkBeacon(time)
	expectColor(binding, false)
end
local transitions, previous, lastChange = 0, nil, -math.huge
for index = 0, 429 do
	local time = index / 10
	neon:_blinkBeacon(time)
	local bright = closeColor(binding.sign.Color, binding.color)
	if previous ~= nil and bright ~= previous then
		assert(time - lastChange >= 0.59, "Neon produced rapid flashing")
		lastChange, transitions = time, transitions + 1
	end
	previous = bright
end
assert(transitions >= 18 and transitions <= 20, "Irregular flicker did not repeat continuously")
assert(created == beforeCreated and binding.sign.Size == size and binding.sign.CFrame == frame)
assert(
	foreignGui.Parent == playerGui and foreignGui.Name == "CornExitBeacon",
	"Foreign old marker was touched"
)
-- Native text and the physical panel are restored during every inactive lifecycle.
neon:SetSnapshot({ phase = "ready" })
for _, phase in { "ready", "preparing", "caught_out", "escaped", "aborted" } do
	neon:SetSnapshot(active)
	neon:_blinkBeacon(100)
	neon:_blinkBeacon(100.9)
	expectColor(binding, false)
	neon:SetSnapshot({ phase = phase })
	assert(not neon._beacon)
	expectColor(binding, true)
	neon:_blinkBeacon(101)
	assert(not neon._beacon)
end
neon:SetSnapshot(active)
neon:_blinkBeacon(200)
neon:_blinkBeacon(200.9)
humanoid.Health = 0
neon:_blinkBeacon(201)
expectColor(binding, true)
assert(not neon._beacon)
humanoid.Health = 100
neon:_blinkBeacon(202)
neon:_blinkBeacon(202.9)
menu.MenuIsOpen = true
neon:_blinkBeacon(203)
expectColor(binding, true)
assert(not neon._beacon)
menu.MenuIsOpen = false
neon:_blinkBeacon(204)
neon:_blinkBeacon(204.9)
neon:SetSnapshot({ phase = "caught", capture = { remaining = 0.5 } })
neon:_blinkBeacon(205)
expectColor(binding, true)
assert(not neon._beacon)
neon:SetSnapshot({ phase = "caught", capture = { remaining = 0 } })
neon:_blinkBeacon(206)
neon:_blinkBeacon(206.9)
expectColor(binding, false)
neon:Destroy()
expectColor(binding, true)
-- A foreign property change is preserved, while the other still-owned color restores.
for _, kind in
	{ "color", "text-color", "material", "ltm", "enabled", "visible", "text-transparency" }
do
	local owned = controller()
	owned:SetSnapshot(active)
	owned:_blinkBeacon(0)
	owned:_blinkBeacon(0.9)
	if kind == "color" then
		binding.sign.Color = r.Color3.fromRGB(80, 50, 20)
	end
	if kind == "text-color" then
		binding.text.TextColor3 = r.Color3.fromRGB(90, 20, 80)
	end
	if kind == "material" then
		binding.sign.Material = r.Enum.Material.Plastic
	end
	if kind == "ltm" then
		binding.sign.LocalTransparencyModifier = 0.7
	end
	if kind == "enabled" then
		binding.surface.Enabled = false
	end
	if kind == "visible" then
		binding.text.Visible = false
	end
	if kind == "text-transparency" then
		binding.text.TextTransparency = 0.6
	end
	local foreignColor, foreignText = binding.sign.Color, binding.text.TextColor3
	owned:_blinkBeacon(1)
	assert(not owned._beacon and owned._beaconRefused.sign == binding.sign)
	if kind == "color" then
		assert(binding.sign.Color == foreignColor)
	else
		assert(binding.sign.Color == binding.color)
	end
	if kind == "text-color" then
		assert(binding.text.TextColor3 == foreignText)
	else
		assert(binding.text.TextColor3 == binding.textColor)
	end
	local writes = colorWrites
	for _, time in { 2, 4, 15 } do
		owned:_blinkBeacon(time)
	end
	assert(colorWrites == writes, "Foreign property was reclaimed automatically")
	assert(
		binding.sign.Material
			== (if kind == "material" then r.Enum.Material.Plastic else r.Enum.Material.Neon)
	)
	assert(binding.sign.LocalTransparencyModifier == (if kind == "ltm" then 0.7 else 0.23))
	assert(
		binding.surface.Enabled == (kind ~= "enabled")
			and binding.text.Visible == (kind ~= "visible")
	)
	assert(binding.text.TextTransparency == (if kind == "text-transparency" then 0.6 else 0))
	owned:SetSnapshot({ phase = "ready" })
	owned:Destroy()
	binding.sign.Color, binding.text.TextColor3 = binding.color, binding.textColor
	binding.sign.Material, binding.sign.LocalTransparencyModifier = r.Enum.Material.Neon, 0.23
	binding.surface.Enabled, binding.text.Visible, binding.text.TextTransparency = true, true, 0
end
-- Ownership/path changes never restore a detached or repurposed object's color.
for _, kind in
	{
		"sign-owner",
		"surface-owner",
		"text-owner",
		"road-owner",
		"map-owner",
		"props-parent",
		"road-parent",
		"sign-parent",
		"surface-parent",
		"text-parent",
		"rename",
		"role",
		"version",
		"content",
	}
do
	binding.map.Parent = nil
	local candidate = beacon()
	local owned = controller()
	owned:SetSnapshot(active)
	owned:_blinkBeacon(0)
	owned:_blinkBeacon(0.9)
	if kind == "sign-owner" then
		candidate.sign:SetAttribute("CornRoadExitOwned", false)
	end
	if kind == "surface-owner" then
		candidate.surface:SetAttribute("CornRoadExitOwned", false)
	end
	if kind == "text-owner" then
		candidate.text:SetAttribute("CornRoadExitOwned", false)
	end
	if kind == "road-owner" then
		candidate.road:SetAttribute("CornRoadExitOwned", false)
	end
	if kind == "map-owner" then
		candidate.map:SetAttribute("corn_project_id", "foreign")
	end
	if kind == "props-parent" then
		candidate.props.Parent = fakeWorld
	end
	if kind == "road-parent" then
		candidate.road.Parent = candidate.map
	end
	if kind == "sign-parent" then
		candidate.sign.Parent = candidate.props
	end
	if kind == "surface-parent" then
		candidate.surface.Parent = candidate.props
	end
	if kind == "text-parent" then
		candidate.text.Parent = candidate.props
	end
	if kind == "rename" then
		candidate.sign.Name = "AuthorRenamedSign"
	end
	if kind == "role" then
		candidate.text:SetAttribute("RoadExitRole", "foreign")
	end
	if kind == "version" then
		candidate.sign:SetAttribute("RoadExitVersion", 2)
	end
	if kind == "content" then
		candidate.text.Text = "Author replacement"
	end
	local color, textColor = candidate.sign.Color, candidate.text.TextColor3
	owned:_blinkBeacon(1)
	assert(
		not owned._beacon
			and candidate.sign.Color == color
			and candidate.text.TextColor3 == textColor
	)
	owned:Destroy()
	assert(candidate.sign.Color == color and candidate.text.TextColor3 == textColor)
	candidate.map.Parent = nil
	candidate.props.Parent = nil
	candidate.road.Parent = nil
	candidate.sign.Parent = nil
	candidate.surface.Parent = nil
	candidate.text.Parent = nil
end
-- Exact streamed replacement has its own original colors and a fresh cycle.
local old = beacon()
local streamed = controller()
streamed:SetSnapshot(active)
streamed:_blinkBeacon(0)
streamed:_blinkBeacon(0.9)
old.map.Parent = nil
local replacement = beacon()
replacement.sign.Color = r.Color3.fromRGB(20, 130, 95)
replacement.text.TextColor3 = r.Color3.fromRGB(220, 230, 210)
replacement.color, replacement.textColor = replacement.sign.Color, replacement.text.TextColor3
local oldColor = old.sign.Color
streamed:_blinkBeacon(10)
assert(streamed._beacon.sign == replacement.sign and old.sign.Color == oldColor)
streamed:_blinkBeacon(10.9)
expectColor(replacement, false)
streamed:Destroy()
expectColor(replacement, true)
replacement.map.Parent = nil
-- Authored disabled text remains unchanged; scheduler still caps work at10Hz.
local disabled = beacon(false)
local stopped = controller()
stopped:SetSnapshot(active)
stopped:_blinkBeacon(0)
stopped:_blinkBeacon(0.9)
assert(
	disabled.sign.Color == disabled.color
		and disabled.text.TextColor3 == disabled.textColor
		and not disabled.surface.Enabled
)
stopped:Destroy()
disabled.map.Parent = nil
local scheduledBinding = beacon()
local scheduled = controller()
scheduled._update = function(self)
	self:_blinkBeacon(now)
end
scheduled:SetSnapshot(active)
scheduled:Start({})
scheduled:Start({})
now = 0
callback(0.01)
now = 0.9
local writes = colorWrites
for _ = 1, 9 do
	callback(0.01)
end
assert(colorWrites == writes, "Neon refreshed above10Hz")
callback(0.02)
expectColor(scheduledBinding, false)
scheduled:Destroy()
expectColor(scheduledBinding, true)
assert(created >= beforeCreated and foreignGui.Parent == playerGui)
print(
	"PASS:22/24-radius gate hint plus actual physicalNeon continuous14.3s/segments>=.6, color-only2writes/10Hz, nativeoccludedSurface/visiblepanel/noHUD/newobjects/projection, phase/menu/death/capture cleanup, foreigncolors/material/LTM/Enabled/path/version/content refusal and streaming restoration. Adapter only; no live GPU claim."
)
