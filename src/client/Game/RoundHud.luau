--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RoundText: { [string]: string } = require(
	ReplicatedStorage:WaitForChild("GameShared"):WaitForChild("Game"):WaitForChild("RoundText")
)

export type Snapshot = {
	phase: string,
	has_key: boolean,
	gate_open: boolean,
	session_diamonds: number,
	reward_diamonds: number,
	elapsed_sec: number,
	notice: string,
	stamina: number,
	stamina_capacity: number,
	is_sprinting: boolean,
	sprint_exhausted: boolean,
	start_look: Vector3,
}

local RoundHud = {}
RoundHud.__index = RoundHud

local PANEL_COLOR = Color3.fromRGB(27, 32, 28)
local TEXT_COLOR = Color3.fromRGB(239, 242, 233)
local MUTED_COLOR = Color3.fromRGB(190, 199, 186)
local BUTTON_COLOR = Color3.fromRGB(84, 109, 67)
local DISABLED_COLOR = Color3.fromRGB(63, 69, 61)

local function text(key: string, values: { [string]: string | number }?): string
	local template = RoundText[key] or ""
	return (
		string.gsub(template, "{([%w_]+)}", function(name)
			local value = if values then values[name] else nil
			return if value ~= nil then tostring(value) else "{" .. name .. "}"
		end)
	)
end

local function elapsedText(seconds: number): string
	local whole = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", math.floor(whole / 60), whole % 60)
end

local function label(
	parent: Instance,
	name: string,
	size: UDim2,
	position: UDim2,
	fontSize: number
): TextLabel
	local result = Instance.new("TextLabel")
	result.Name = name
	result.Size = size
	result.Position = position
	result.BackgroundTransparency = 1
	result.Font = Enum.Font.Gotham
	result.TextSize = fontSize
	result.TextColor3 = TEXT_COLOR
	result.TextWrapped = true
	result.TextXAlignment = Enum.TextXAlignment.Left
	result.TextYAlignment = Enum.TextYAlignment.Center
	result.Text = ""
	result.Parent = parent
	return result
end

local function button(
	parent: Instance,
	name: string,
	key: string,
	size: UDim2,
	position: UDim2
): TextButton
	local result = Instance.new("TextButton")
	result.Name = name
	result.Size = size
	result.Position = position
	result.BackgroundColor3 = BUTTON_COLOR
	result.BorderSizePixel = 0
	result.Font = Enum.Font.GothamMedium
	result.TextSize = 17
	result.TextColor3 = TEXT_COLOR
	result.Text = text(key)
	result.Modal = parent.Name == "RoundCard"
	result.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = result
	return result
end

local function panel(parent: Instance, name: string, size: UDim2, position: UDim2): Frame
	local result = Instance.new("Frame")
	result.Name = name
	result.Size = size
	result.Position = position
	result.BackgroundColor3 = PANEL_COLOR
	result.BackgroundTransparency = 0.08
	result.BorderSizePixel = 0
	result.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = result
	return result
end

function RoundHud.new(playerGui: PlayerGui)
	local root = Instance.new("ScreenGui")
	root.Name = "CornRoundHud"
	root.ResetOnSpawn = false
	root.DisplayOrder = 10
	root.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	root.Parent = playerGui

	local card = panel(root, "RoundCard", UDim2.fromOffset(460, 320), UDim2.fromScale(0.5, 0.5))
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	local title = label(card, "Title", UDim2.new(1, -48, 0, 38), UDim2.fromOffset(24, 20), 27)
	title.Font = Enum.Font.GothamBold
	local message = label(card, "Message", UDim2.new(1, -48, 0, 52), UDim2.fromOffset(24, 68), 19)
	local resultTime =
		label(card, "Elapsed", UDim2.new(1, -48, 0, 26), UDim2.fromOffset(24, 124), 16)
	resultTime.TextColor3 = MUTED_COLOR
	local balance = label(card, "Balance", UDim2.new(1, -48, 0, 26), UDim2.fromOffset(24, 154), 16)
	balance.TextColor3 = MUTED_COLOR
	local notice = label(card, "Notice", UDim2.new(1, -48, 0, 46), UDim2.fromOffset(24, 186), 16)
	notice.TextColor3 = Color3.fromRGB(233, 209, 142)
	local start = button(
		card,
		"Start",
		"corn_loop_start",
		UDim2.new(1, -48, 0, 44),
		UDim2.fromOffset(24, 250)
	)
	local retry = button(
		card,
		"Retry",
		"corn_loop_retry",
		UDim2.new(0.5, -30, 0, 44),
		UDim2.fromOffset(24, 250)
	)
	local menu = button(
		card,
		"Menu",
		"corn_loop_menu",
		UDim2.new(0.5, -30, 0, 44),
		UDim2.new(0.5, 6, 0, 250)
	)
	local preparingLeave = button(
		card,
		"Leave",
		"corn_loop_leave",
		UDim2.new(1, -48, 0, 44),
		UDim2.fromOffset(24, 250)
	)

	local active = panel(root, "ActiveStatus", UDim2.new(0.64, 0, 0, 128), UDim2.fromOffset(20, 16))
	local activeConstraint = Instance.new("UISizeConstraint")
	activeConstraint.MaxSize = Vector2.new(690, 128)
	activeConstraint.Parent = active
	local objective =
		label(active, "Objective", UDim2.new(1, -32, 0, 32), UDim2.fromOffset(16, 8), 19)
	objective.Font = Enum.Font.GothamMedium
	local activeTime =
		label(active, "Elapsed", UDim2.new(1, -32, 0, 24), UDim2.fromOffset(16, 42), 15)
	activeTime.TextColor3 = MUTED_COLOR
	local activeBalance =
		label(active, "Balance", UDim2.new(1, -32, 0, 24), UDim2.fromOffset(16, 66), 15)
	activeBalance.TextColor3 = MUTED_COLOR
	local activeNotice =
		label(active, "Notice", UDim2.new(1, -32, 0, 24), UDim2.fromOffset(16, 94), 16)
	activeNotice.TextColor3 = notice.TextColor3
	local activeLeave = button(
		root,
		"LeaveRound",
		"corn_loop_leave",
		UDim2.fromOffset(185, 40),
		UDim2.new(1, -205, 0, 16)
	)

	local self = setmetatable({
		_root = root,
		_card = card,
		_title = title,
		_message = message,
		_time = resultTime,
		_balance = balance,
		_notice = notice,
		_active = active,
		_objective = objective,
		_activeTime = activeTime,
		_activeBalance = activeBalance,
		_activeNotice = activeNotice,
		_start = start,
		_retry = retry,
		_menu = menu,
		_preparingLeave = preparingLeave,
		_activeLeave = activeLeave,
		_buttons = { start, retry, menu, preparingLeave, activeLeave },
		_connections = {} :: { RBXScriptConnection },
		_snapshot = nil :: Snapshot?,
		_busy = false,
		_unavailable = false,
	}, RoundHud)
	self:_render()
	return self
end

function RoundHud:SetOnAction(callback: (string) -> ())
	local bindings = {
		{ button = self._start, action = "start" },
		{ button = self._retry, action = "retry" },
		{ button = self._menu, action = "menu" },
		{ button = self._preparingLeave, action = "abort" },
		{ button = self._activeLeave, action = "abort" },
	}
	for _, binding in bindings do
		table.insert(
			self._connections,
			binding.button.Activated:Connect(function()
				if not self._busy and not self._unavailable and self._snapshot ~= nil then
					callback(binding.action)
				end
			end)
		)
	end
end

function RoundHud:_render()
	local snapshot = self._snapshot
	local phase = if snapshot then snapshot.phase else "loading"
	local isActive = phase == "active"
	local isResult = phase == "escaped" or phase == "aborted"
	self._card.Visible = not isActive
	self._active.Visible = isActive
	self._activeLeave.Visible = isActive
	self._start.Visible = phase == "ready" or phase == "loading"
	self._retry.Visible = isResult
	self._menu.Visible = isResult
	self._preparingLeave.Visible = phase == "preparing"
	for _, control in self._buttons do
		local enabled = snapshot ~= nil and not self._busy and not self._unavailable
		control.Active = enabled
		control.AutoButtonColor = enabled
		control.BackgroundColor3 = if enabled then BUTTON_COLOR else DISABLED_COLOR
		control.TextTransparency = if enabled then 0 else 0.35
	end

	self._title.Text = text("corn_loop_title")
	self._time.Text = ""
	self._notice.Text = if snapshot then text(snapshot.notice) else ""
	self._balance.Visible = snapshot ~= nil
	self._balance.Text = text(
		"corn_loop_test_balance",
		{ count = if snapshot then snapshot.session_diamonds else 0 }
	)
	if self._unavailable then
		self._message.Text = text("corn_loop_connection_error")
	elseif phase == "loading" or phase == "preparing" then
		self._message.Text = text("corn_loop_loading")
	elseif phase == "ready" then
		self._message.Text = text("corn_loop_objective_search")
	elseif snapshot and isResult then
		self._title.Text = text(
			if phase == "escaped" then "corn_loop_result_escape" else "corn_loop_result_aborted"
		)
		self._message.Text = if phase == "escaped"
			then text("corn_loop_reward", { count = snapshot.reward_diamonds })
			else ""
		self._time.Text = text("corn_loop_round_time", { time = elapsedText(snapshot.elapsed_sec) })
	end

	if snapshot and isActive then
		local objectiveKey = if snapshot.gate_open
			then "corn_loop_objective_exit"
			elseif snapshot.has_key then "corn_loop_objective_return"
			else "corn_loop_objective_search"
		self._objective.Text = text(objectiveKey)
		self._activeTime.Text =
			text("corn_loop_round_time", { time = elapsedText(snapshot.elapsed_sec) })
		self._activeBalance.Text = self._balance.Text
		self._activeNotice.Text = text(snapshot.notice)
	end
end

function RoundHud:Render(snapshot: Snapshot)
	self._unavailable = false
	self._snapshot = snapshot
	self:_render()
end

function RoundHud:SetBusy(busy: boolean)
	self._busy = busy
	self:_render()
end

function RoundHud:ShowUnavailable()
	self._unavailable = true
	self:_render()
end

function RoundHud:Destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	self._root:Destroy()
end

return RoundHud
