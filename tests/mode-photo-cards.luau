-- Current RoundHud constructor/render/Activated/_fitCard methods, deterministic
-- GUI-object adapter. No engine pixels/network asset loading or physical mouse claims.
local fs = require("@lune/fs")
local r = require("@lune/roblox")
local viewport = r.Vector2.new(1400, 800)
local function signal()
	local items = {}
	return {
		Connect = function(_, fn)
			local c = {
				Connected = true,
				Disconnect = function(self)
					self.Connected = false
				end,
			}
			table.insert(items, { c, fn })
			return c
		end,
		Fire = function(_, ...)
			for _, entry in items do
				if entry[1].Connected then
					entry[2](...)
				end
			end
		end,
	}
end
local api, make = {}, nil
local function sizeOf(item)
	if item._class == "ScreenGui" or item._class == "PlayerGui" then
		return viewport
	end
	local parent = if item.Parent then sizeOf(item.Parent) else viewport
	return r.Vector2.new(
		item.Size.X.Scale * parent.X + item.Size.X.Offset,
		item.Size.Y.Scale * parent.Y + item.Size.Y.Offset
	)
end
local function scaleOf(item)
	local result = if item.Parent then scaleOf(item.Parent) else 1
	for _, child in item._children do
		if child._class == "UIScale" then
			result *= child.Scale
		end
	end
	return result
end
local meta = {
	__index = function(item, key)
		if api[key] then
			return api[key]
		end
		if key == "Parent" then
			return item._props.Parent
		end
		if key == "AbsoluteSize" then
			return sizeOf(item) * scaleOf(item)
		end
		if key == "AbsolutePosition" then
			if item._class == "ScreenGui" or item._class == "PlayerGui" then
				return r.Vector2.zero
			end
			local parentSize = if item.Parent then sizeOf(item.Parent) else viewport
			local parentScale = if item.Parent then scaleOf(item.Parent) else 1
			local parentPos = if item.Parent then item.Parent.AbsolutePosition else r.Vector2.zero
			local own = sizeOf(item) * scaleOf(item)
			return parentPos
				+ r.Vector2.new(
					item.Position.X.Scale * parentSize.X + item.Position.X.Offset,
					item.Position.Y.Scale * parentSize.Y + item.Position.Y.Offset
				) * parentScale
				- r.Vector2.new(item.AnchorPoint.X * own.X, item.AnchorPoint.Y * own.Y)
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
			local prior = item._props.Parent
			if prior then
				for index, child in prior._children do
					if child == item then
						table.remove(prior._children, index)
						break
					end
				end
			end
			item._props.Parent = value
			if value then
				table.insert(value._children, item)
			end
		else
			item._props[key] = value
		end
	end,
}
make = function(class)
	return setmetatable({
		_class = class,
		_children = {},
		_signals = {},
		_props = {
			Name = class,
			Size = r.UDim2.fromOffset(0, 0),
			Position = r.UDim2.fromOffset(0, 0),
			AnchorPoint = r.Vector2.zero,
			Visible = true,
			Active = false,
			Scale = 1,
			Text = "",
			Image = "",
			Activated = signal(),
		},
	}, meta)
end
function api:IsA(class)
	return self._class == class or class == "Instance"
end
function api:GetChildren()
	return table.clone(self._children)
end
function api:GetDescendants()
	local all = {}
	for _, child in self._children do
		table.insert(all, child)
		for _, nested in child:GetDescendants() do
			table.insert(all, nested)
		end
	end
	return all
end
function api:FindFirstChild(name)
	for _, child in self._children do
		if child.Name == name then
			return child
		end
	end
	return nil
end
function api:WaitForChild(name)
	return assert(self:FindFirstChild(name), "Missing fixture node " .. name)
end
function api:GetPropertyChangedSignal(name)
	if not self._signals[name] then
		self._signals[name] = signal()
	end
	return self._signals[name]
end
function api:Destroy()
	for _, child in self:GetChildren() do
		child:Destroy()
	end
	self.Parent = nil
	self._props.Destroyed = true
end
local function load(path, env)
	local fn = assert(loadstring(fs.readFile(path), path))
	setfenv(fn, setmetatable(env, { __index = getfenv() }))
	return fn()
end
local modules = {
	Balance = load("src/shared/Game/Balance.luau", {}),
	LightingModes = load("src/shared/Game/LightingModes.luau", { Color3 = r.Color3 }),
	RoundText = load("src/shared/Game/RoundText.luau", {}),
	MinimapGeometry = load(
		"src/shared/Game/MinimapGeometry.luau",
		{ Vector2 = r.Vector2, Vector3 = r.Vector3 }
	),
}
local storage = make("Folder")
storage.Name = "ReplicatedStorage"
local shared = make("Folder")
shared.Name = "GameShared"
shared.Parent = storage
local gameFolder = make("Folder")
gameFolder.Name = "Game"
gameFolder.Parent = shared
for name in modules do
	local item = make("ModuleScript")
	item.Name = name
	item.Parent = gameFolder
end
local Hud = load("src/client/Game/RoundHud.luau", {
	game = {
		GetService = function(_, name)
			return if name == "GuiService" then {} else storage
		end,
	},
	require = function(item)
		return assert(modules[item.Name], item.Name)
	end,
	Instance = { new = make },
	UDim2 = r.UDim2,
	UDim = r.UDim,
	Vector2 = r.Vector2,
	Color3 = r.Color3,
	Enum = r.Enum,
})
local playerGui = make("PlayerGui")
local hud = Hud.new(playerGui)
local base = {
	lighting_mode = "hard",
	phase = "ready",
	has_key = false,
	gate_open = false,
	session_diamonds = 0,
	reward_diamonds = 0,
	elapsed_sec = 15,
	notice = "",
	stamina = 100,
	stamina_capacity = 100,
	is_sprinting = false,
	sprint_exhausted = false,
	start_look = r.Vector3.new(0, 0, -1),
	catches_remaining = 2,
	monster_state = "patrol",
	protection_sec = 0,
	minimap = { round_id = 1, visited = {}, deaths = {} },
	capture = { id = 0, remaining = 0, frame = r.CFrame.identity },
}
local function render(phase)
	local state = table.clone(base)
	state.phase = phase
	if phase == "caught_out" then
		state.catches_remaining = 0
		state.capture = { id = 2, remaining = 0, frame = r.CFrame.identity }
	end
	hud:Render(state)
end
local function rect(item)
	return {
		x = item.AbsolutePosition.X,
		y = item.AbsolutePosition.Y,
		w = item.AbsoluteSize.X,
		h = item.AbsoluteSize.Y,
	}
end
local function inside(item, parent)
	local a, b = rect(item), rect(parent)
	assert(
		a.x >= b.x - 0.01
			and a.y >= b.y - 0.01
			and a.x + a.w <= b.x + b.w + 0.01
			and a.y + a.h <= b.y + b.h + 0.01,
		item.Name .. " overflow"
	)
	return a
end
local function separate(a, b, message)
	assert(
		a.x + a.w <= b.x + 0.01
			or b.x + b.w <= a.x + 0.01
			or a.y + a.h <= b.y + 0.01
			or b.y + b.h <= a.y + 0.01,
		message
	)
end
-- This historical test filename now checks removal of the old chooser.
local calls = {}
hud:SetOnAction(function(action, mode)
	table.insert(calls, { action, mode })
end)
local function noModes()
	assert(
		hud._modeCards == nil and hud._modeButtons == nil and hud._introMode == nil,
		"Removed mode controls still have controller state"
	)
	for _, root in { hud._root, hud._introRoot } do
		for _, item in root:GetDescendants() do
			assert(
				not item:IsA("ImageLabel")
					and not item:IsA("ViewportFrame")
					and not item:IsA("WorldModel"),
				"Mode imagery or artificial world remains"
			)
			assert(
				item.Name ~= "ModeCards" and item.Name ~= "ChooseMode" and item.Name ~= "ModeHint",
				"Mode selection node remains"
			)
			if item.Text then
				assert(
					not item.Text:find("сложност", 1, true)
						and not item.Text:find("Режим:", 1, true)
						and not item.Text:find("Выбрано:", 1, true),
					"Mode text remains in the UI"
				)
			end
		end
	end
end
for _, size in { r.Vector2.new(1400, 800), r.Vector2.new(800, 600), r.Vector2.new(640, 480) } do
	viewport = size
	for _, phase in { "ready", "preparing", "active", "caught", "escaped", "aborted", "caught_out" } do
		render(phase)
		noModes()
		assert(hud._card.Size == r.UDim2.fromOffset(460, 320), "Obsolete wide mode chooser layout")
		assert(
			hud._card.Visible == (phase ~= "active" and phase ~= "caught" and phase ~= "caught_out"),
			"Round card visibility changed"
		)
		inside(hud._card, hud._root)
		if phase == "ready" or phase == "escaped" or phase == "aborted" then
			local action = if phase == "ready" then hud._start else hud._retry
			assert(action.Visible and action.Active, "Single round action unavailable")
			assert(hud._start.Visible ~= hud._retry.Visible, "Start and retry are both visible")
			local message = inside(hud._message, hud._card)
			local balance = inside(hud._balance, hud._card)
			local button = inside(action, hud._card)
			separate(message, balance, "Message/balance overlap")
			separate(balance, button, "Balance/action overlap")
			if phase ~= "ready" then
				separate(button, inside(hud._menu, hud._card), "Retry/menu overlap")
			end
			local before = #calls
			action.Activated:Fire()
			assert(
				#calls == before and hud._introRoot.Enabled and hud._introPending.mode == "hard",
				"Action bypassed objective or retained an old mode"
			)
			noModes()
			hud._introConfirm.Activated:Fire()
			assert(
				#calls == before + 1
					and calls[#calls][1] == (if phase == "ready" then "start" else "retry")
					and calls[#calls][2] == "hard",
				"Confirmed action did not use night"
			)
		end
	end
end
render("escaped")
local before = #calls
hud._menu.Activated:Fire()
assert(
	#calls == before + 1 and calls[#calls][1] == "menu" and calls[#calls][2] == nil,
	"Menu action changed"
)
render("ready")
assert(
	hud._start.Visible
		and not hud._retry.Visible
		and not hud._menu.Visible
		and not hud._introRoot.Enabled,
	"Menu return did not restore a single main Start"
)
hud:SetBusy(true)
before = #calls
hud._start.Activated:Fire()
assert(#calls == before and not hud._introRoot.Enabled, "Busy Start operated")
hud:SetBusy(false)
hud:ShowUnavailable()
hud._start.Activated:Fire()
assert(#calls == before and not hud._introRoot.Enabled, "Unavailable Start operated")
local oldConnections = table.clone(hud._connections)
hud:Destroy()
assert(#playerGui:GetChildren() == 0 and #hud._connections == 0, "Night-only GUI cleanup failed")
for _, connection in oldConnections do
	assert(not connection.Connected, "Night-only GUI signal leaked")
end
print(
	"PASS: actual RoundHud has zero mode cards/buttons/images/text, compact main Start/result Retry, all phases at 1400x800/800x600/640x480, objective-confirmed hard only, menu return, busy/unavailable and cleanup. Adapter only; no engine pixels or gameplay claim."
)
