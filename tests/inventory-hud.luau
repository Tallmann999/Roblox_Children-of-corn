-- Actual HUD/input methods with deterministic GUI and signal adapters.
-- This verifies state, layout and input routing, not Roblox pixels or live networking.
local fs = require("@lune/fs")
local r = require("@lune/roblox")
local viewport = r.Vector2.new(1400, 800)
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
local meta = {
	__index = function(item, key)
		if methods[key] then
			return methods[key]
		end
		if key == "AbsoluteSize" then
			return viewport
		end
		if item._props[key] ~= nil then
			return item._props[key]
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
			local old = item._props.Parent
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
		item._props[key] = value
	end,
}
local function make(class)
	return setmetatable({
		_class = class,
		_children = {},
		_signals = {},
		_props = {
			Name = class,
			Parent = nil,
			Size = r.UDim2.fromOffset(0, 0),
			Position = r.UDim2.fromOffset(0, 0),
			Scale = 1,
			AnchorPoint = r.Vector2.zero,
			Active = false,
			Visible = true,
			Enabled = true,
			Text = "",
			Activated = signal(),
		},
	}, meta)
end
function methods:IsA(class)
	return self._class == class
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
function methods:GetPropertyChangedSignal(name)
	if not self._signals[name] then
		self._signals[name] = signal()
	end
	return self._signals[name]
end
function methods:Destroy()
	for _, child in table.clone(self._children) do
		child:Destroy()
	end
	self.Parent = nil
end
local function load(path, env)
	local fn = assert(loadstring(fs.readFile(path), path))
	setfenv(fn, setmetatable(env, { __index = getfenv() }))
	return fn()
end
local guiEnv = {
	Instance = { new = make },
	UDim2 = r.UDim2,
	UDim = r.UDim,
	Vector2 = r.Vector2,
	Color3 = r.Color3,
	Enum = r.Enum,
}
local Hud = load("src/client/Game/InventoryHud.luau", guiEnv)
local Inventory = load("src/shared/Game/Inventory.luau", {})
-- Roblox EnumItems are canonical; Lune adapter lookup keys need stable identities.
local keys = {}
for _, name in { "One", "Two", "Three", "Four", "Five", "E" } do
	keys[name] = r.Enum.KeyCode[name]
end
local inputEnum = setmetatable({ KeyCode = keys }, { __index = r.Enum })
local gui = make("PlayerGui")
local hud = Hud.new(gui, true)
local requests = {}
hud:SetOnAction(function(action, slot)
	table.insert(requests, { action, slot })
end)
local state =
	{ slots = { "key", "energy", "trap", "energy", "trap" }, selected = 2, energy_remaining = 30, use = { id = 0, kind = "none" } }
hud:Render(state, "active", 100)
assert(hud._root.Enabled and #hud._buttons == 5)
assert(
	hud._caption.Text:find("5/5", 1, true) and hud._use.Text == "Выпить" and hud._use.Active
)
assert(hud._seconds.Text == "30" and hud._energy.Visible)
hud._buttons[3].Activated:Fire()
assert(requests[1][1] == "select" and requests[1][2] == 3)
assert(hud._inventory.selected == 2, "Selection became locally authoritative")
hud._use.Activated:Fire()
assert(requests[2][1] == "use" and requests[2][2] == 2)
state = table.clone(state)
state.selected = 1
hud:Render(state, "active", 100)
assert(not hud._use.Active and hud._use.Text == "Ключ · к воротам")
hud._use.Activated:Fire()
assert(#requests == 2, "Key activation request leaked")
state.selected = 3
hud:Render(state, "active", 100)
assert(hud._use.Text == "Поставить капкан" and hud._icons[3].trap.Visible)
for _, size in
	{
		r.Vector2.new(1400, 800),
		r.Vector2.new(800, 600),
		r.Vector2.new(640, 360),
		r.Vector2.new(390, 844),
	}
do
	viewport = size
	hud:SetViewport(size)
	local scale = hud._scale.Scale
	local width = hud._bar.Size.X.Offset * scale
	local height = hud._bar.Size.Y.Offset * scale
	local right = size.X + hud._bar.Position.X.Offset
	local bottom = size.Y + hud._bar.Position.Y.Offset
	assert(right <= size.X and right - width >= 0 and bottom - height >= 0)
	assert(
		bottom <= size.Y - 108 or right - width >= 370,
		"Inventory overlaps existing left stamina HUD"
	)
	for index, slot in hud._buttons do
		assert(slot.Position.X.Offset + slot.Size.X.Offset <= hud._bar.Size.X.Offset)
		assert(hud._icons[index][state.slots[index]].Visible, "Item icon not visible")
	end
end
hud:Render(state, "active", 100)
hud:Update(124.99)
assert(hud._seconds.Text == "6" and hud._seconds.TextColor3 == r.Color3.fromRGB(104, 222, 128))
hud:Update(125)
assert(hud._seconds.Text == "5" and hud._seconds.TextColor3 == r.Color3.fromRGB(248, 91, 83))
local priorBlink = hud._seconds.TextTransparency
hud:Update(125.25)
assert(hud._seconds.TextTransparency ~= priorBlink, "Last-five countdown does not blink")
hud:Update(130)
assert(not hud._energy.Visible, "Expired acceleration timer remains")
hud:Render(state, "caught", 100)
assert(hud._root.Enabled and not hud._energy.Visible and not hud._use.Active)
hud._buttons[5].Activated:Fire()
assert(#requests == 2, "Caught inventory accepted item selection")
for _, phase in { "ready", "preparing", "escaped", "aborted", "caught_out" } do
	hud:Render(state, phase, 100)
	assert(not hud._root.Enabled, "Inventory visible outside playable/caught phase")
end
local connections = table.clone(hud._connections)
hud:Destroy()
assert(#gui._children == 0 and #hud._connections == 0)
for _, connection in connections do
	assert(not connection.Connected, "HUD connection leaked")
end

local now, menu, focused, backpack = 50, false, nil, true
local playerGui = make("PlayerGui")
playerGui.Name = "PlayerGui"
local player = make("Player")
playerGui.Parent = player
local storage = make("ReplicatedStorage")
local shared = make("Folder")
shared.Name = "GameShared"
shared.Parent = storage
local games = make("Folder")
games.Name = "Game"
games.Parent = shared
local network = make("Folder")
network.Name = "Network"
network.Parent = shared
local inventoryModule = make("ModuleScript")
inventoryModule.Name = "Inventory"
inventoryModule.Parent = games
local endpointsModule = make("ModuleScript")
endpointsModule.Name = "EndpointNames"
endpointsModule.Parent = network
local client = make("Folder")
local controllers = make("Folder")
controllers.Parent = client
local clientGame = make("Folder")
clientGame.Name = "Game"
clientGame.Parent = client
local hudModule = make("ModuleScript")
hudModule.Name = "InventoryHud"
hudModule.Parent = clientGame
local scriptNode = make("ModuleScript")
scriptNode.Parent = controllers
local remotes = make("Folder")
remotes.Name = "GameRemotes"
remotes.Parent = storage
local remote = make("RemoteEvent")
remote.Name = "request_inventory_action"
remote.Parent = remotes
local sent = {}
remote.FireServer = function(_, action, slot)
	table.insert(sent, { action, slot })
end
local input = {
	TouchEnabled = false,
	InputBegan = signal(),
	GetFocusedTextBox = function()
		return focused
	end,
}
local prompts = { PromptShown = signal(), PromptHidden = signal() }
local frames = { RenderStepped = signal() }
local starter = {
	GetCoreGuiEnabled = function()
		return backpack
	end,
	SetCoreGuiEnabled = function(_, _, value)
		backpack = value
	end,
}
local services = {
	Players = { LocalPlayer = player },
	ReplicatedStorage = storage,
	UserInputService = input,
	ProximityPromptService = prompts,
	GuiService = setmetatable({}, {
		__index = function(_, key)
			if key == "MenuIsOpen" then
				return menu
			end
		end,
	}),
	RunService = frames,
	StarterGui = starter,
}
local Controller = load("src/client/Controllers/InventoryController.luau", {
	game = {
		GetService = function(_, name)
			return assert(services[name])
		end,
	},
	script = scriptNode,
	Enum = inputEnum,
	os = {
		clock = function()
			return now
		end,
	},
	require = function(item)
		return if item.Name == "Inventory"
			then Inventory
			elseif item.Name == "InventoryHud" then Hud
			else { RequestInventoryAction = remote.Name }
	end,
})
Controller:Init({})
local map = { _expanded = false }
Controller:Start({ Controllers = { MinimapController = map } })
assert(not backpack, "Vanilla backpack keys remain enabled")
local confirmed = { phase = "active", inventory = state }
confirmed.inventory.selected = 2
Controller:SetSnapshot(confirmed)
input.InputBegan:Fire({ KeyCode = keys.Three }, false)
assert(#sent == 1 and sent[1][1] == "select" and sent[1][2] == 3)
assert(Controller._snapshot.inventory.selected == 2)
input.InputBegan:Fire({ KeyCode = keys.E }, false)
assert(#sent == 2 and sent[2][1] == "use" and sent[2][2] == 2)
input.InputBegan:Fire({ KeyCode = keys.E }, false)
assert(#sent == 2, "Use button debounce failed")
now += 1
local prompt = make("ProximityPrompt")
prompt.Parent = storage
prompt.KeyboardKeyCode = keys.E
prompts.PromptShown:Fire(prompt)
input.InputBegan:Fire({ KeyCode = keys.E }, false)
assert(#sent == 2, "World E prompt did not take priority")
prompts.PromptHidden:Fire(prompt)
for _, reason in { "processed", "map", "menu", "textbox", "caught" } do
	map._expanded, menu, focused, confirmed.phase =
		reason == "map",
		reason == "menu",
		if reason == "textbox" then {} else nil,
		if reason == "caught" then "caught" else "active"
	Controller:SetSnapshot(confirmed)
	input.InputBegan:Fire({ KeyCode = keys.E }, reason == "processed")
	input.InputBegan:Fire({ KeyCode = keys.Five }, reason == "processed")
	assert(#sent == 2, "Input guard failed: " .. reason)
end
map._expanded, menu, focused, confirmed.phase = false, false, nil, "active"
confirmed.inventory.selected = 1
Controller:SetSnapshot(confirmed)
input.InputBegan:Fire({ KeyCode = keys.E }, false)
assert(#sent == 2, "Key was activated with E")
confirmed.inventory.selected = 3
Controller:SetSnapshot(confirmed)
input.InputBegan:Fire({ KeyCode = keys.E }, false)
assert(#sent == 3 and sent[3][2] == 3, "Trap E request failed")
local owned = table.clone(Controller._connections)
Controller:Destroy()
assert(backpack and #playerGui._children == 0 and #Controller._connections == 0)
for _, connection in owned do
	assert(not connection.Connected, "Controller signal leaked")
end
print(
	"PASS: five persistent slots, authoritative selection, touch use/key guard, 1400/800/640/390 viewport layout, interpolated circular countdown/green/red/blink/expiry, input 1–5/E/prompt priority/menu/map/textbox/caught guards, debounce and cleanup"
)
