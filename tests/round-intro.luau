-- Current RoundHud constructor/render/Activated/_fitCard methods, deterministic
-- GUI-object adapter. No engine pixels/network asset loading or physical mouse claims.
local fs = require("@lune/fs")
local process = require("@lune/process")
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
local guiService = {}
local Hud = load("src/client/Game/RoundHud.luau", {
	game = {
		GetService = function(_, name)
			return if name == "GuiService" then guiService else storage
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
local state = {
	lighting_mode = "hard",
	phase = "ready",
	has_key = false,
	gate_open = false,
	session_diamonds = 0,
	reward_diamonds = 0,
	elapsed_sec = 0,
	notice = "",
	stamina = 100,
	stamina_capacity = 100,
	is_sprinting = false,
	sprint_exhausted = false,
	start_look = r.Vector3.new(0, 0, -1),
	catches_remaining = 2,
	monster_state = "dormant",
	protection_sec = 0,
	minimap = { round_id = 1, visited = {}, deaths = {} },
	inventory = {
		slots = { "empty", "empty", "empty", "empty", "empty" },
		selected = 1,
		energy_remaining = 0,
		use = { id = 0, kind = "none" },
	},
	capture = { id = 0, remaining = 0, frame = r.CFrame.identity },
}
local function render(changes)
	local value = table.clone(state)
	for key, entry in changes do
		value[key] = entry
	end
	hud:Render(value)
	return value
end
local calls = {}
hud:SetOnAction(function(action, mode)
	table.insert(calls, { action, mode })
end)
render({})
assert(
	modules.LightingModes.Default == "hard" and hud._modeButtons == nil,
	"Night-only default/GUI"
)
guiService.SelectedObject = hud._start
hud._start.Activated:Fire()
assert(
	#calls == 0 and hud._introRoot.Enabled and not hud._card.Visible and not hud._waking.Visible,
	"Start sent a round before objective confirmation"
)
assert(
	hud._introMessage.Text == modules.RoundText.corn_loop_intro_objective
		and guiService.SelectedObject == hud._introConfirm
)
assert(
	hud._introRoot.IgnoreGuiInset
		and hud._introRoot.ScreenInsets == r.Enum.ScreenInsets.None
		and not hud._introRoot.ClipToDeviceSafeArea
		and hud._introRoot.DisplayOrder > 30
)
assert(hud._introRoot.Backdrop.Size == r.UDim2.fromScale(1, 1) and hud._introRoot.Backdrop.Active)
assert(hud._introConfirm.Modal and hud._introBack.Modal and hud._introConfirm.Active)
hud._start.Activated:Fire()
hud._menu.Activated:Fire()
assert(
	hud._introPending.mode == "hard" and #calls == 0,
	"Hidden underlying controls operated through modal"
)
hud._introBack.Activated:Fire()
assert(
	not hud._introRoot.Enabled
		and hud._card.Visible
		and #calls == 0
		and guiService.SelectedObject == hud._start
)
hud._start.Activated:Fire()
hud:SetBusy(true)
hud._introConfirm.Activated:Fire()
hud._introBack.Activated:Fire()
assert(hud._introRoot.Enabled and #calls == 0 and not hud._introConfirm.Active)
hud:SetBusy(false)
hud._introConfirm.Activated:Fire()
hud._introConfirm.Activated:Fire()
assert(
	#calls == 1 and calls[1][1] == "start" and calls[1][2] == "hard" and not hud._introRoot.Enabled,
	"Confirm did not send exactly one original start/mode"
)
render({ phase = "escaped" })
hud._retry.Activated:Fire()
assert(#calls == 1 and hud._introRoot.Enabled and hud._introPending.action == "retry")
hud._introConfirm.Activated:Fire()
assert(
	#calls == 2 and calls[2][1] == "retry" and calls[2][2] == "hard",
	"Result retry left night mode"
)
for _, phase in { "aborted", "caught_out" } do
	render({
		phase = phase,
		catches_remaining = if phase == "caught_out" then 0 else 2,
		capture = {
			id = if phase == "caught_out" then 2 else 0,
			remaining = 0,
			frame = r.CFrame.identity,
		},
	})
	local control = if phase == "caught_out" then hud._captureRevive else hud._retry
	control.Activated:Fire()
	assert(hud._introRoot.Enabled and hud._introPending.action == "retry")
	hud._introBack.Activated:Fire()
	assert(not hud._introRoot.Enabled and #calls == 2)
end

-- First capture has no automatic continuation; two explicit choices appear
-- only after both the confirmed server timer and local scene have finished.
render({
	phase = "caught",
	catches_remaining = 1,
	capture = { id = 1, remaining = 0.5, frame = r.CFrame.identity },
})
assert(not hud._captureChoices.Visible and not hud._card.Visible and hud._modeCards == nil)
hud._captureRevive.Activated:Fire()
hud._captureExit.Activated:Fire()
assert(#calls == 2, "Early capture choices emitted a request")
hud:SetCaptureActive(true)
render({
	phase = "caught",
	catches_remaining = 1,
	capture = { id = 1, remaining = 0, frame = r.CFrame.identity },
})
assert(not hud._captureChoices.Visible)
hud._captureRevive.Activated:Fire()
assert(#calls == 2)
hud:SetCaptureActive(false)
assert(hud._captureChoices.Visible and hud._captureRevive.Modal and hud._captureExit.Modal)
assert(
	hud._captureRevive.Text == "Возрождение"
		and hud._captureExit.Text == "Выход из игры"
)
assert(guiService.SelectedObject == hud._captureRevive)
hud:SetBusy(true)
hud._captureRevive.Activated:Fire()
hud._captureExit.Activated:Fire()
assert(#calls == 2 and not hud._captureRevive.Active)
hud:SetBusy(false)
hud._captureRevive.Activated:Fire()
hud._captureRevive.Activated:Fire()
hud._captureExit.Activated:Fire()
assert(
	#calls == 3 and calls[3][1] == "revive" and calls[3][2] == nil and not hud._introRoot.Enabled
)
hud:SetBusy(false)
render({ phase = "active" })
assert(
	not hud._captureChoices.Visible
		and not hud._captureRevive.Active
		and not hud._captureRevive.Modal
)
render({
	phase = "caught_out",
	catches_remaining = 0,
	lighting_mode = "hard",
	capture = { id = 2, remaining = 0, frame = r.CFrame.identity },
})
assert(hud._modeButtons == nil, "Capture kept hidden mode choices")
hud._captureRevive.Activated:Fire()
assert(
	hud._introRoot.Enabled and not hud._captureChoices.Visible and hud._introPending.mode == "hard"
)
hud._captureExit.Activated:Fire()
assert(#calls == 3)
hud._introBack.Activated:Fire()
assert(hud._captureChoices.Visible and not hud._introRoot.Enabled and #calls == 3)
hud._captureRevive.Activated:Fire()
hud._introConfirm.Activated:Fire()
hud._introConfirm.Activated:Fire()
assert(#calls == 4 and calls[4][1] == "retry" and calls[4][2] == "hard")
hud:SetBusy(false)
hud._captureExit.Activated:Fire()
hud._captureExit.Activated:Fire()
assert(#calls == 5 and calls[5][1] == "menu" and calls[5][2] == nil)
hud:SetBusy(false)
hud:ShowUnavailable()
assert(not hud._captureChoices.Visible and not hud._captureRevive.Active)
hud._captureRevive.Activated:Fire()
assert(#calls == 5)
render({
	phase = "caught_out",
	catches_remaining = 0,
	capture = { id = 2, remaining = 0, frame = r.CFrame.identity },
})
hud._captureRevive.Activated:Fire()
render({ phase = "preparing", minimap = { round_id = 2, visited = {}, deaths = {} } })
assert(not hud._captureChoices.Visible and not hud._introRoot.Enabled)
render({})
hud._start.Activated:Fire()
render({ minimap = { round_id = 2, visited = {}, deaths = {} } })
assert(
	not hud._introRoot.Enabled and hud._introPending == nil,
	"Changed round did not cancel objective"
)
hud._start.Activated:Fire()
render({ phase = "preparing" })
assert(
	not hud._introRoot.Enabled and hud._introPending == nil,
	"Phase transition left stale objective"
)
render({})
hud._start.Activated:Fire()
hud:ShowUnavailable()
assert(not hud._introRoot.Enabled and not hud._introConfirm.Active)
render({})
hud._start.Activated:Fire()
hud:SetCaptureActive(true)
assert(not hud._introRoot.Enabled and hud._introPending == nil)
hud:SetCaptureActive(false)
hud._start.Activated:Fire()
local foreignSelection = make("TextButton")
foreignSelection.Parent = playerGui
guiService.SelectedObject = foreignSelection
hud:CloseObjective()
assert(
	guiService.SelectedObject == foreignSelection,
	"Modal cleanup replaced foreign selection focus"
)
foreignSelection:Destroy()
guiService.SelectedObject = nil
local wake = modules.Balance.hunt_start_delay_sec
for _, elapsed in { 0, wake - 5.01, wake, wake + 1 } do
	render({ phase = "active", elapsed_sec = elapsed })
	assert(
		not hud._waking.Visible and hud._wakingSeconds.Text == "" and hud._wakingMessage.Text == "",
		"Countdown visible outside final five seconds"
	)
end
for count = 5, 1, -1 do
	render({ phase = "active", elapsed_sec = wake - count })
	assert(
		hud._waking.Visible
			and hud._wakingMessage.Text == modules.RoundText.corn_hunt_waking_warning
			and hud._wakingSeconds.Text == tostring(count) .. " с"
	)
	hud:SetBusy(true)
	assert(
		hud._wakingSeconds.Text == tostring(count) .. " с",
		"Rerender advanced server-derived countdown"
	)
	hud:SetBusy(false)
end
render({ phase = "active", elapsed_sec = wake - 4.3 })
assert(hud._wakingSeconds.Text == "5 с", "Server subsecond elapsed rounded incorrectly")
for _, phase in { "ready", "preparing", "caught", "escaped", "aborted", "caught_out" } do
	render({ phase = phase, elapsed_sec = wake - 2 })
	assert(not hud._waking.Visible and hud._wakingSeconds.Text == "")
end
for _, monsterState in { "patrol", "chase", "trapped", "capturing", "stopped" } do
	render({ phase = "active", elapsed_sec = wake - 2, monster_state = monsterState })
	assert(not hud._waking.Visible)
end
render({ phase = "active", elapsed_sec = wake - 2 })
hud:ShowUnavailable()
assert(not hud._waking.Visible and hud._wakingSeconds.Text == "", "Unavailable HUD kept countdown")
render({ phase = "active", elapsed_sec = wake - 2 })
hud:SetCaptureActive(true)
assert(not hud._waking.Visible)
hud:SetCaptureActive(false)
render({ phase = "active", elapsed_sec = 0, minimap = { round_id = 3, visited = {}, deaths = {} } })
assert(not hud._waking.Visible and hud._wakingSeconds.Text == "", "Retry kept prior wake countdown")
local function inside(item, parent)
	local a, b = item.AbsolutePosition, parent.AbsolutePosition
	local size, outer = item.AbsoluteSize, parent.AbsoluteSize
	assert(
		a.X >= b.X - 0.01
			and a.Y >= b.Y - 0.01
			and a.X + size.X <= b.X + outer.X + 0.01
			and a.Y + size.Y <= b.Y + outer.Y + 0.01,
		item.Name .. " viewport overflow"
	)
end
local function separate(a, b)
	assert(
		a.AbsolutePosition.Y + a.AbsoluteSize.Y <= b.AbsolutePosition.Y + 0.01,
		a.Name .. "/" .. b.Name .. " overlap"
	)
end
for _, view in
	{
		r.Vector2.new(1400, 800),
		r.Vector2.new(640, 480),
		r.Vector2.new(320, 568),
		r.Vector2.new(568, 320),
		r.Vector2.new(320, 320),
	}
do
	viewport = view
	render({})
	hud._start.Activated:Fire()
	assert(hud._introRoot.AbsoluteSize == view and hud._introRoot.Backdrop.AbsoluteSize == view)
	inside(hud._introPanel, hud._introRoot)
	for _, item in
		{
			hud._introPanel.Title,
			hud._introMessage,
			hud._introConfirm,
			hud._introBack,
		}
	do
		inside(item, hud._introPanel)
	end
	separate(hud._introPanel.Title, hud._introMessage)
	separate(hud._introMessage, hud._introConfirm)
	separate(hud._introConfirm, hud._introBack)
	assert(
		hud._introConfirm.AbsoluteSize.Y == 48
			and hud._introBack.AbsoluteSize.Y == 36
			and hud._introMessage.TextSize >= 18
	)
	hud:CloseObjective()
	render({
		phase = "caught_out",
		catches_remaining = 0,
		capture = { id = 2, remaining = 0, frame = r.CFrame.identity },
	})
	inside(hud._captureChoices, hud._root)
	inside(hud._captureMessage, hud._captureChoices)
	inside(hud._captureRevive, hud._captureChoices)
	inside(hud._captureExit, hud._captureChoices)
	separate(hud._captureMessage, hud._captureRevive)
	separate(hud._captureRevive, hud._captureExit)
	render({ phase = "active", elapsed_sec = wake - 3 })
	inside(hud._waking, hud._root)
	inside(hud._wakingMessage, hud._waking)
	inside(hud._wakingSeconds, hud._waking)
	separate(hud._wakingMessage, hud._wakingSeconds)
end
viewport = r.Vector2.new(1400, 800)
-- The local clock interpolates server remaining time without pausing for the
-- capture film or its revival modal. Only the server can decide the outcome.
render({ phase = "active", evacuation = { active = true, remaining = 120, duration = 120 } })
local countdownStart = hud._evacuationUntil - 120
hud:_stepEvacuation(countdownStart)
assert(hud._evacuation.Visible and hud._evacuationClock.Text == "2:00")
hud:_stepEvacuation(countdownStart + 1.2)
assert(hud._evacuationClock.Text == "1:59")
local firstPulse = hud._evacuationClock.TextTransparency
hud:_stepEvacuation(countdownStart + 1.4)
assert(firstPulse ~= hud._evacuationClock.TextTransparency, "Countdown did not pulse")
render({
	phase = "caught",
	catches_remaining = 1,
	capture = { id = 1, remaining = 0, frame = r.CFrame.identity },
	evacuation = { active = true, remaining = 97, duration = 120 },
})
local caughtDeadline = hud._evacuationUntil
hud:_stepEvacuation(caughtDeadline - 92)
assert(
	hud._evacuation.Visible and hud._evacuationClock.Text == "1:32" and hud._captureChoices.Visible
)
hud:SetCaptureActive(true)
hud:_stepEvacuation(caughtDeadline - 90)
assert(hud._evacuation.Visible and hud._evacuationClock.Text == "1:30")
hud:SetCaptureActive(false)
render({
	phase = "caught_out",
	notice = "corn_evacuation_expired",
	evacuation = { active = false, remaining = 0, duration = 120 },
})
assert(not hud._evacuation.Visible and hud._captureTitle.Text == "Время вышло")
for _, reward in { 5, 10, 20 } do
	render({
		phase = "escaped",
		reward_diamonds = reward,
		evacuation = { active = false, remaining = 0, duration = 120 },
	})
	assert(
		not hud._evacuation.Visible and string.find(hud._message.Text, tostring(reward), 1, true)
	)
end
local oldConnections = table.clone(hud._connections)
hud:Destroy()
for _, connection in oldConnections do
	assert(not connection.Connected)
end
assert(#playerGui:GetChildren() == 0 and #hud._connections == 0)
hud:ConfirmObjective()
assert(#calls == 5, "Destroyed HUD emitted a stale action")

-- Actual RoundController callback wiring and validation with fake remotes.
modules.Inventory = load("src/shared/Game/Inventory.luau", {})
modules.CapturePresentation =
	load("src/shared/Game/CapturePresentation.luau", { CFrame = r.CFrame })
modules.EndpointNames = load("src/shared/Network/EndpointNames.luau", {})
modules.RoundHud = Hud
for _, name in { "Inventory", "CapturePresentation" } do
	local node = make("ModuleScript")
	node.Name, node.Parent = name, gameFolder
end
local network = make("Folder")
network.Name, network.Parent = "Network", shared
local endpoints = make("ModuleScript")
endpoints.Name, endpoints.Parent = "EndpointNames", network
local remotes = make("Folder")
remotes.Name, remotes.Parent = "GameRemotes", storage
local request, snapshots = make("RemoteEvent"), make("RemoteEvent")
request.Name, request.Parent = modules.EndpointNames.RequestRoundAction, remotes
snapshots.Name, snapshots.Parent = modules.EndpointNames.RoundSnapshot, remotes
snapshots.OnClientEvent = signal()
local networkCalls, delayed, now = {}, {}, 1000
request.FireServer = function(_, action, mode)
	table.insert(networkCalls, { action, mode })
end
local localPlayer = make("Player")
playerGui.Parent = localPlayer
local client, controllers, games = make("Folder"), make("Folder"), make("Folder")
controllers.Name, controllers.Parent = "Controllers", client
games.Name, games.Parent = "Game", client
local hudNode, scriptNode = make("ModuleScript"), make("ModuleScript")
hudNode.Name, hudNode.Parent = "RoundHud", games
scriptNode.Name, scriptNode.Parent = "RoundController", controllers
local Controller = load("src/client/Controllers/RoundController.luau", {
	game = {
		GetService = function(_, name)
			return if name == "Players" then { LocalPlayer = localPlayer } else storage
		end,
	},
	script = scriptNode,
	require = function(node)
		return assert(modules[node.Name], node.Name)
	end,
	os = {
		clock = function()
			return now
		end,
	},
	task = {
		delay = function(duration, callback)
			table.insert(delayed, { at = now + duration, callback = callback })
		end,
	},
	warn = function() end,
})
local controller = setmetatable({}, { __index = Controller })
local stubControllers = setmetatable({}, {
	__index = function(self, name)
		local value = setmetatable({}, {
			__index = function()
				return function() end
			end,
		})
		rawset(self, name, value)
		return value
	end,
})
controller:Init({})
controller:Start({ Controllers = stubControllers })
assert(#networkCalls == 1 and networkCalls[1][1] == "sync")
snapshots.OnClientEvent:Fire(state)
for _, mode in { "easy", "medium" } do
	controller:_request("start", mode)
	assert(#networkCalls == 1, "Client forwarded a removed mode from ready")
	local invalid = table.clone(state)
	invalid.lighting_mode = mode
	snapshots.OnClientEvent:Fire(invalid)
	assert(controller._snapshot == nil, "Client accepted a removed-mode snapshot")
	snapshots.OnClientEvent:Fire(state)
end
for _, evacuation in
	{
		{ active = true, remaining = -1, duration = 120 },
		{ active = true, remaining = 121, duration = 120 },
		{ active = true, remaining = 0 / 0, duration = 120 },
		{ active = true, remaining = 60, duration = 60 },
		{ active = false, remaining = 1, duration = 120 },
	}
do
	local invalid = table.clone(state)
	invalid.evacuation = evacuation
	snapshots.OnClientEvent:Fire(invalid)
	assert(controller._snapshot == nil and not controller._hud._evacuation.Visible)
end
snapshots.OnClientEvent:Fire(state)
local liveHud = controller._hud
assert(liveHud._modeButtons == nil, "Live controller restored mode controls")
liveHud._start.Activated:Fire()
assert(#networkCalls == 1 and liveHud._introRoot.Enabled and controller._snapshot.elapsed_sec == 0)
liveHud._introBack.Activated:Fire()
assert(#networkCalls == 1)
liveHud._start.Activated:Fire()
liveHud._introConfirm.Activated:Fire()
assert(#networkCalls == 2 and networkCalls[2][1] == "start" and networkCalls[2][2] == "hard")
liveHud._introConfirm.Activated:Fire()
assert(#networkCalls == 2)
local result = table.clone(state)
result.phase, result.monster_state = "escaped", "stopped"
snapshots.OnClientEvent:Fire(result)
now += 1
for _, event in delayed do
	if event.at <= now then
		event.callback()
	end
end
for _, mode in { "easy", "medium" } do
	controller:_request("retry", mode)
	assert(#networkCalls == 2, "Client forwarded a removed mode from a retry phase")
end
liveHud._retry.Activated:Fire()
assert(#networkCalls == 2 and liveHud._introRoot.Enabled)
liveHud._introConfirm.Activated:Fire()
assert(#networkCalls == 3 and networkCalls[3][1] == "retry" and networkCalls[3][2] == "hard")
now += 1
controller:_request("start", "easy")
controller:_request("retry", "unknown")
assert(#networkCalls == 3, "Client forwarded wrong-phase start or unknown mode")
local caught = table.clone(state)
caught.phase, caught.catches_remaining = "caught", 1
caught.capture = { id = 1, remaining = 0.5, frame = r.CFrame.identity }
snapshots.OnClientEvent:Fire(caught)
controller:_request("revive")
assert(#networkCalls == 3 and not liveHud._captureChoices.Visible, "Early revival was forwarded")
caught.capture = { id = 1, remaining = 0, frame = r.CFrame.identity }
snapshots.OnClientEvent:Fire(caught)
liveHud:SetBusy(false)
liveHud:SetCaptureActive(true)
controller:_request("revive")
assert(#networkCalls == 3, "A still-active capture scene forwarded revival")
liveHud:SetCaptureActive(false)
controller:_request("revive", "hard")
assert(#networkCalls == 3, "Revival with a mode was forwarded")
liveHud._captureRevive.Activated:Fire()
liveHud._captureRevive.Activated:Fire()
controller:_request("revive")
assert(#networkCalls == 4 and networkCalls[4][1] == "revive" and networkCalls[4][2] == nil)
now += 1
local second = table.clone(caught)
second.phase, second.catches_remaining, second.lighting_mode = "caught_out", 0, "hard"
second.capture = { id = 2, remaining = 0, frame = r.CFrame.identity }
snapshots.OnClientEvent:Fire(second)
liveHud:SetBusy(false)
controller:_request("revive")
assert(#networkCalls == 4, "Second capture forwarded same-round revival")
liveHud._captureRevive.Activated:Fire()
liveHud._introBack.Activated:Fire()
assert(liveHud._captureChoices.Visible and #networkCalls == 4)
liveHud._captureRevive.Activated:Fire()
liveHud._introConfirm.Activated:Fire()
assert(#networkCalls == 5 and networkCalls[5][1] == "retry" and networkCalls[5][2] == "hard")
now += 1
snapshots.OnClientEvent:Fire(caught)
liveHud:SetBusy(false)
liveHud._captureExit.Activated:Fire()
liveHud._captureExit.Activated:Fire()
assert(#networkCalls == 6 and networkCalls[6][1] == "menu" and networkCalls[6][2] == nil)
now += 1
snapshots.OnClientEvent:Fire({})
controller:_request("revive")
assert(
	controller._snapshot == nil and not liveHud._captureChoices.Visible and #networkCalls == 6,
	"Malformed snapshot retained a captured-state action"
)
snapshots.OnClientEvent:Fire(state)
for _, event in delayed do
	if event.at <= now then
		event.callback()
	end
end
liveHud._start.Activated:Fire()
assert(liveHud._introRoot.Enabled)
snapshots.OnClientEvent:Fire({})
assert(
	not liveHud._introRoot.Enabled and liveHud._introPending == nil,
	"Malformed snapshot retained objective"
)
controller:Destroy()
for _, event in delayed do
	event.callback()
end
assert(#playerGui:GetChildren() == 0 and not controller._snapshot and #networkCalls == 6)
print(
	"PASS: actual RoundHud first capture scene/timer gating, small revive/menu choices, second-capture fixed-mode retry objective/back, duplicate/busy/unavailable/phase cleanup; actual RoundController early/second/mode/debounce/malformed revival guards and menu/retry routing; original full-screen start/retry confirmation, selection/capture/destroy lifecycle, server-elapsed-only 5→1 warning and desktop/phone GUI bounds. Adapter only; no engine pixels or gameplay acceptance."
)
