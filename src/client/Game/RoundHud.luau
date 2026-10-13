--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local RoundText: { [string]: string } = require(
	ReplicatedStorage:WaitForChild("GameShared"):WaitForChild("Game"):WaitForChild("RoundText")
)

local LightingModes = require(ReplicatedStorage.GameShared.Game.LightingModes)

local ModePreviewImages = require(ReplicatedStorage.GameShared.Game.ModePreviewImages)

local MinimapGeometry = require(ReplicatedStorage.GameShared.Game.MinimapGeometry)
local Balance = require(ReplicatedStorage.GameShared.Game.Balance)

export type Snapshot = {
	capture: { id: number, remaining: number, frame: CFrame },
	inventory: {
		slots: { string },
		selected: number,
		energy_remaining: number,
		use: { id: number, kind: string },
	},
	minimap: MinimapGeometry.History,
	lighting_mode: string,
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
	catches_remaining: number,
	monster_state: string,
	protection_sec: number,
}

local RoundHud = {}
RoundHud.__index = RoundHud

local PANEL_COLOR = Color3.fromRGB(27, 32, 28)
local TEXT_COLOR = Color3.fromRGB(239, 242, 233)
local MUTED_COLOR = Color3.fromRGB(190, 199, 186)
local BUTTON_COLOR = Color3.fromRGB(84, 109, 67)
local DISABLED_COLOR = Color3.fromRGB(63, 69, 61)
local NOTICE_COLOR = Color3.fromRGB(233, 209, 142)
local CHASE_COLOR = Color3.fromRGB(233, 94, 83)

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

local function modePreview(parent: Instance, mode: string)
	local photo = Instance.new("ImageLabel")
	photo.Name = "LightingPreview"
	photo.Size = UDim2.new(1, -20, 0, 128)
	photo.Position = UDim2.fromOffset(10, 10)
	photo.BackgroundColor3 = PANEL_COLOR
	photo.BorderSizePixel = 0
	photo.Image = ModePreviewImages[mode]
	photo.ScaleType = Enum.ScaleType.Crop
	photo.ClipsDescendants = true
	photo.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = photo
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
	local cardScale = Instance.new("UIScale")
	cardScale.Parent = card
	local title = label(card, "Title", UDim2.new(1, -48, 0, 38), UDim2.fromOffset(24, 20), 27)
	title.Font = Enum.Font.GothamBold
	local message = label(card, "Message", UDim2.new(1, -48, 0, 52), UDim2.fromOffset(24, 68), 19)
	local resultTime =
		label(card, "Elapsed", UDim2.new(1, -48, 0, 26), UDim2.fromOffset(24, 124), 16)
	resultTime.TextColor3 = MUTED_COLOR
	local balance = label(card, "Balance", UDim2.new(1, -48, 0, 26), UDim2.fromOffset(24, 154), 16)
	balance.TextColor3 = MUTED_COLOR
	local notice = label(card, "Notice", UDim2.new(1, -48, 0, 46), UDim2.fromOffset(24, 186), 16)
	notice.TextColor3 = NOTICE_COLOR
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

	local modeCards = Instance.new("Frame")
	modeCards.Name = "ModeCards"
	modeCards.BackgroundTransparency = 1
	modeCards.Size = UDim2.new(1, -48, 0, 254)
	modeCards.Position = UDim2.fromOffset(24, 142)
	modeCards.Parent = card
	local choose =
		label(card, "ChooseMode", UDim2.new(1, -48, 0, 24), UDim2.fromOffset(24, 110), 16)
	choose.TextColor3 = MUTED_COLOR
	local modeHint =
		label(card, "ModeHint", UDim2.new(1, -48, 0, 24), UDim2.fromOffset(24, 406), 15)
	modeHint.TextColor3 = MUTED_COLOR
	local modeButtons, modeStrokes = {}, {}
	for index, mode in LightingModes.Order do
		local option = panel(
			modeCards,
			mode,
			UDim2.new(1 / 3, -8, 1, 0),
			UDim2.new((index - 1) / 3, (index - 1) * 4, 0, 0)
		)
		option.BackgroundColor3 = Color3.fromRGB(38, 45, 38)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Parent = option
		modeStrokes[mode] = stroke
		modePreview(option, mode)
		local name = label(option, "Name", UDim2.new(1, -20, 0, 28), UDim2.fromOffset(10, 144), 21)
		name.Font = Enum.Font.GothamBold
		name.Text = text("corn_modes_" .. mode)
		local description =
			label(option, "Description", UDim2.new(1, -20, 0, 30), UDim2.fromOffset(10, 176), 15)
		description.TextColor3 = MUTED_COLOR
		description.Text = text("corn_modes_" .. mode .. "_desc")
		local select = button(
			option,
			"Select",
			"corn_modes_select",
			UDim2.new(1, -20, 0, 32),
			UDim2.fromOffset(10, 212)
		)
		select.Modal = true
		modeButtons[mode] = select
	end

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
	local waking =
		panel(root, "AwakeningWarning", UDim2.fromOffset(600, 120), UDim2.new(0.5, 0, 0, 150))
	waking.AnchorPoint = Vector2.new(0.5, 0)
	waking.Active = false
	local wakingMessage =
		label(waking, "Message", UDim2.new(1, -32, 0, 56), UDim2.fromOffset(16, 8), 21)
	wakingMessage.TextColor3 = NOTICE_COLOR
	wakingMessage.TextXAlignment = Enum.TextXAlignment.Center
	local wakingSeconds =
		label(waking, "Seconds", UDim2.new(1, -32, 0, 42), UDim2.fromOffset(16, 68), 36)
	wakingSeconds.Font = Enum.Font.GothamBold
	wakingSeconds.TextColor3 = NOTICE_COLOR
	wakingSeconds.TextXAlignment = Enum.TextXAlignment.Center
	local introRoot = Instance.new("ScreenGui")
	introRoot.Name = "CornRoundIntro"
	introRoot.ResetOnSpawn = false
	introRoot.IgnoreGuiInset = true
	introRoot.ScreenInsets = Enum.ScreenInsets.None
	introRoot.ClipToDeviceSafeArea = false
	introRoot.DisplayOrder = 60
	introRoot.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	introRoot.Enabled = false
	introRoot.Parent = playerGui
	local shade = Instance.new("Frame")
	shade.Name = "Backdrop"
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.fromRGB(13, 19, 15)
	shade.BorderSizePixel = 0
	shade.Active = true
	shade.Parent = introRoot
	local introPanel = Instance.new("Frame")
	introPanel.Name = "ObjectivePanel"
	introPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	introPanel.Position = UDim2.fromScale(0.5, 0.5)
	introPanel.Size = UDim2.fromOffset(640, 390)
	introPanel.BackgroundTransparency = 1
	introPanel.Parent = introRoot
	local introTitle =
		label(introPanel, "Title", UDim2.new(1, -32, 0, 32), UDim2.fromOffset(16, 18), 24)
	introTitle.Text = text("corn_loop_intro_title")
	introTitle.TextColor3 = MUTED_COLOR
	introTitle.TextXAlignment = Enum.TextXAlignment.Center
	local introMessage =
		label(introPanel, "Objective", UDim2.new(1, -32, 0, 168), UDim2.fromOffset(16, 70), 32)
	introMessage.Text = text("corn_loop_intro_objective")
	introMessage.Font = Enum.Font.GothamBold
	introMessage.TextXAlignment = Enum.TextXAlignment.Center
	local introMode =
		label(introPanel, "Mode", UDim2.new(1, -32, 0, 28), UDim2.fromOffset(16, 244), 17)
	introMode.TextColor3 = MUTED_COLOR
	introMode.TextXAlignment = Enum.TextXAlignment.Center
	local introConfirm = button(
		introPanel,
		"Confirm",
		"corn_loop_intro_confirm",
		UDim2.new(1, -32, 0, 48),
		UDim2.fromOffset(16, 278)
	)
	local introBack = button(
		introPanel,
		"Back",
		"corn_loop_intro_back",
		UDim2.new(1, -32, 0, 36),
		UDim2.fromOffset(16, 336)
	)
	introConfirm.Modal, introBack.Modal = true, true
	introConfirm.SelectionOrder, introBack.SelectionOrder = 0, 1
	introConfirm.NextSelectionDown, introBack.NextSelectionUp = introBack, introConfirm

	local self = setmetatable({
		_root = root,
		_card = card,
		_cardScale = cardScale,
		_modeCards = modeCards,
		_chooseMode = choose,
		_modeHint = modeHint,
		_modeButtons = modeButtons,
		_modeStrokes = modeStrokes,
		_selectedMode = LightingModes.Default,
		_lastPhase = "loading",
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
		_waking = waking,
		_wakingMessage = wakingMessage,
		_wakingSeconds = wakingSeconds,
		_introRoot = introRoot,
		_introPanel = introPanel,
		_introMessage = introMessage,
		_introMode = introMode,
		_introConfirm = introConfirm,
		_introBack = introBack,
		_introPending = nil,
		_introVisible = false,
		_savedSelection = nil,
		_onAction = nil,
		_actionBound = false,
		_destroyed = false,
		_buttons = { start, retry, menu, preparingLeave, activeLeave },
		_connections = {} :: { RBXScriptConnection },
		_snapshot = nil :: Snapshot?,
		_busy = false,
		_captureActive = false,
		_unavailable = false,
	}, RoundHud)
	for mode, select in modeButtons do
		table.insert(
			self._connections,
			select.Activated:Connect(function()
				if
					not self._busy
					and not self._unavailable
					and not self._introPending
					and not self._destroyed
					and self._snapshot
				then
					self._selectedMode = mode
					self:_render()
				end
			end)
		)
	end
	table.insert(
		self._connections,
		root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			self:_fitCard()
			self:_fitOverlays()
		end)
	)
	table.insert(
		self._connections,
		introRoot:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			self:_fitOverlays()
		end)
	)
	self:_render()
	return self
end

function RoundHud:_fitCard()
	if self._destroyed then
		return
	end
	local viewport = self._root.AbsoluteSize
	if viewport.X > 0 and viewport.Y > 0 then
		self._cardScale.Scale = math.min(
			1,
			(viewport.X - 36) / self._card.Size.X.Offset,
			(viewport.Y - 36) / self._card.Size.Y.Offset
		)
	end
end

function RoundHud:_fitOverlays()
	if self._destroyed then
		return
	end
	local viewport = self._introRoot.AbsoluteSize
	if viewport.X > 0 and viewport.Y > 0 then
		local width, height = math.min(640, viewport.X - 36), math.min(390, viewport.Y - 36)
		self._introPanel.Size = UDim2.fromOffset(math.max(1, width), math.max(1, height))
		local bodyHeight = math.max(40, height - 222)
		self._introMessage.Size = UDim2.new(1, -32, 0, bodyHeight)
		self._introMessage.TextSize =
			math.min(if width < 390 then 24 else 32, math.max(18, bodyHeight / 3))
		self._introMode.Position = UDim2.fromOffset(16, height - 146)
		self._introConfirm.Position = UDim2.fromOffset(16, height - 112)
		self._introBack.Position = UDim2.fromOffset(16, height - 54)
	end
	local hudViewport = self._root.AbsoluteSize
	if hudViewport.X > 0 and hudViewport.Y > 0 then
		local width = math.min(600, math.max(1, hudViewport.X - 36))
		self._waking.Size = UDim2.fromOffset(width, 120)
		self._waking.Position =
			UDim2.new(0.5, 0, 0, math.max(0, math.min(150, hudViewport.Y - 144)))
		self._wakingMessage.TextSize = if width < 390 then 17 else 21
	end
end

function RoundHud:_canAct(): boolean
	return not self._destroyed
		and not self._busy
		and not self._unavailable
		and self._snapshot ~= nil
end

function RoundHud:_introValid(): boolean
	local pending, snapshot = self._introPending, self._snapshot
	return pending ~= nil
		and snapshot ~= nil
		and snapshot.phase == pending.phase
		and snapshot.minimap.round_id == pending.roundId
		and LightingModes.IsValid(pending.mode)
end

function RoundHud:_introVisibility(visible: boolean)
	self._introRoot.Enabled = visible
	if visible == self._introVisible then
		return
	end
	self._introVisible = visible
	if visible then
		self._savedSelection = GuiService.SelectedObject
		GuiService.SelectedObject = self._introConfirm
	elseif
		GuiService.SelectedObject == self._introConfirm
		or GuiService.SelectedObject == self._introBack
	then
		local saved = self._savedSelection
		GuiService.SelectedObject = if saved and saved.Parent and saved.Visible then saved else nil
	end
	if not visible then
		self._savedSelection = nil
	end
end

function RoundHud:ShowObjective(action: string)
	local snapshot = self._snapshot
	if not self:_canAct() or not snapshot or self._captureActive or self._introPending then
		return
	end
	local allowed = (action == "start" and snapshot.phase == "ready")
		or (
			action == "retry"
			and (
				snapshot.phase == "escaped"
				or snapshot.phase == "aborted"
				or snapshot.phase == "caught_out"
			)
		)
	if not allowed or not LightingModes.IsValid(self._selectedMode) then
		return
	end
	self._introPending = {
		action = action,
		mode = self._selectedMode,
		phase = snapshot.phase,
		roundId = snapshot.minimap.round_id,
	}
	self:_render()
end

function RoundHud:CloseObjective()
	self._introPending = nil
	self:_render()
end

function RoundHud:ConfirmObjective()
	if
		not self:_canAct()
		or self._captureActive
		or not self:_introValid()
		or not self._onAction
	then
		return
	end
	local pending = self._introPending
	self._introPending = nil
	self:_render()
	self._onAction(pending.action, pending.mode)
end

function RoundHud:SetOnAction(callback: (string, string?) -> ())
	self._onAction = callback
	if self._actionBound then
		return
	end
	self._actionBound = true
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
				if self:_canAct() and not self._introPending and self._onAction then
					if binding.action == "start" or binding.action == "retry" then
						self:ShowObjective(binding.action)
					else
						self._onAction(binding.action, nil)
					end
				end
			end)
		)
	end
	table.insert(
		self._connections,
		self._introConfirm.Activated:Connect(function()
			self:ConfirmObjective()
		end)
	)
	table.insert(
		self._connections,
		self._introBack.Activated:Connect(function()
			if self:_canAct() then
				self:CloseObjective()
			end
		end)
	)
end

function RoundHud:_render()
	if self._destroyed then
		return
	end
	if not self:_introValid() or self._unavailable or self._captureActive then
		self._introPending = nil
	end
	local intro = self._introPending ~= nil
	local snapshot = self._snapshot
	local phase = if snapshot then snapshot.phase else "loading"
	local isActive = phase == "active"
	local isResult = phase == "escaped" or phase == "aborted" or phase == "caught_out"
	local expanded = phase == "ready" or isResult
	self._card.Size = if expanded then UDim2.fromOffset(780, 530) else UDim2.fromOffset(460, 320)
	self._modeCards.Visible = expanded
	self._chooseMode.Visible = expanded
	self._modeHint.Visible = expanded
	self._chooseMode.Text =
		text("corn_modes_selected", { mode = text("corn_modes_" .. self._selectedMode) })
	self._modeHint.Text = text("corn_modes_hint")
	self._message.Position = UDim2.fromOffset(24, if expanded then 62 else 68)
	self._message.Size = UDim2.new(1, -48, 0, if expanded then 32 else 52)
	self._time.Position = UDim2.fromOffset(24, if expanded then 96 else 124)
	self._time.Visible = not expanded or isResult
	self._time.Size = UDim2.new(1, -48, 0, if expanded then 22 else 26)
	self._chooseMode.Position = UDim2.fromOffset(24, if isResult then 118 else 110)
	self._balance.Position = UDim2.fromOffset(24, if expanded then 440 else 154)
	self._notice.Position = UDim2.fromOffset(24, if expanded then 392 else 186)
	self._notice.Visible = not expanded
	for _, control in { self._start, self._retry, self._menu, self._preparingLeave } do
		control.Position = UDim2.new(
			control.Position.X.Scale,
			control.Position.X.Offset,
			0,
			if expanded then 476 else 250
		)
	end
	for mode, control in self._modeButtons do
		local enabled = expanded
			and snapshot ~= nil
			and not self._busy
			and not self._unavailable
			and not intro
		control.Active = enabled
		control.AutoButtonColor = enabled
		local selected = mode == self._selectedMode
		control.Text = text(if selected then "corn_modes_selected_button" else "corn_modes_select")
		control.BackgroundColor3 = if enabled
			then (if selected then BUTTON_COLOR else DISABLED_COLOR)
			else DISABLED_COLOR
		self._modeStrokes[mode].Color = if selected
			then Color3.fromRGB(204, 190, 114)
			else Color3.fromRGB(61, 71, 60)
		self._modeStrokes[mode].Transparency = if selected then 0 else 0.6
	end
	self:_fitCard()
	self._card.Visible = not intro
		and not isActive
		and not (phase == "caught" and self._captureActive)
	self._active.Visible = isActive
	self._activeLeave.Visible = isActive
	self._start.Visible = phase == "ready" or phase == "loading"
	self._retry.Visible = isResult
	self._menu.Visible = isResult
	self._preparingLeave.Visible = phase == "preparing" or phase == "caught"
	for _, control in self._buttons do
		local enabled = snapshot ~= nil and not self._busy and not self._unavailable and not intro
		control.Active = enabled
		control.AutoButtonColor = enabled
		control.BackgroundColor3 = if enabled then BUTTON_COLOR else DISABLED_COLOR
		control.TextTransparency = if enabled then 0 else 0.35
	end
	for _, control in { self._introConfirm, self._introBack } do
		control.Active = intro and self:_canAct()
		control.AutoButtonColor = control.Active
		control.BackgroundColor3 = if control.Active then BUTTON_COLOR else DISABLED_COLOR
		control.Modal = intro
	end
	if self._introPending then
		self._introMode.Text =
			text("corn_modes_selected", { mode = text("corn_modes_" .. self._introPending.mode) })
	else
		self._introMode.Text = ""
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
	elseif phase == "loading" or phase == "preparing" or phase == "caught" then
		self._message.Text = if phase == "caught"
			then text(snapshot and snapshot.notice or "corn_hunt_first_catch")
			else text("corn_loop_loading")
	elseif phase == "ready" then
		self._message.Text = text("corn_modes_choose")
	elseif snapshot and isResult then
		self._title.Text = text(
			if phase == "escaped"
				then "corn_loop_result_escape"
				elseif phase == "caught_out" then "corn_hunt_defeat"
				else "corn_loop_result_aborted"
		)
		self._message.Text = if phase == "escaped"
			then text("corn_loop_reward", { count = snapshot.reward_diamonds })
			else ""
		self._time.Text = text("corn_loop_round_time", { time = elapsedText(snapshot.elapsed_sec) })
	end

	-- Clear inactive/stale warning styling before rendering this confirmed state.
	self._activeNotice.Text = ""
	self._activeNotice.TextColor3 = NOTICE_COLOR
	self._activeNotice.Font = Enum.Font.Gotham
	if snapshot and isActive then
		local objectiveKey = if snapshot.gate_open
			then "corn_loop_objective_exit"
			elseif snapshot.has_key then "corn_loop_objective_return"
			else "corn_loop_objective_search"
		self._objective.Text = text(objectiveKey)
		self._activeTime.Text = text(
			"corn_loop_round_time",
			{ time = elapsedText(snapshot.elapsed_sec) }
		) .. " · " .. text(
			"corn_modes_active",
			{ mode = text("corn_modes_" .. snapshot.lighting_mode) }
		)
		self._activeBalance.Text = self._balance.Text
		local chasing = snapshot.protection_sec <= 0 and snapshot.monster_state == "chase"
		self._activeNotice.Text = if snapshot.protection_sec > 0
			then text("corn_hunt_protected", { seconds = math.ceil(snapshot.protection_sec) })
			elseif chasing then text("corn_hunt_chase")
			else text(snapshot.notice)
		self._activeNotice.TextColor3 = if chasing then CHASE_COLOR else NOTICE_COLOR
		self._activeNotice.Font = if chasing then Enum.Font.GothamBold else Enum.Font.Gotham
		self._activeBalance.Text ..= " · " .. text(
			"corn_hunt_attempts",
			{ count = snapshot.catches_remaining }
		)
	end
	local remaining = if snapshot
		then math.ceil(Balance.hunt_start_delay_sec - snapshot.elapsed_sec)
		else 0
	local waking = snapshot ~= nil
		and isActive
		and not self._unavailable
		and not self._captureActive
		and snapshot.monster_state == "dormant"
		and remaining >= 1
		and remaining <= 5
		and snapshot.elapsed_sec < Balance.hunt_start_delay_sec
	self._waking.Visible = waking
	self._wakingMessage.Text = if waking then text("corn_hunt_waking_warning") else ""
	self._wakingSeconds.Text = if waking
		then text("corn_hunt_waking_seconds", { seconds = remaining })
		else ""
	self:_fitOverlays()
	self:_introVisibility(intro)
end

function RoundHud:Render(snapshot: Snapshot)
	self._unavailable = false
	if snapshot.phase ~= self._lastPhase and snapshot.phase ~= "ready" then
		self._selectedMode = snapshot.lighting_mode
	end
	self._lastPhase = snapshot.phase
	self._snapshot = snapshot
	self:_render()
end

function RoundHud:SetBusy(busy: boolean)
	self._busy = busy
	self:_render()
end

function RoundHud:SetCaptureActive(active: boolean)
	self._captureActive = active
	self:_render()
end

function RoundHud:ShowUnavailable()
	self._unavailable = true
	self:_render()
end

function RoundHud:Destroy()
	self._introPending = nil
	self:_introVisibility(false)
	self._destroyed = true
	self._snapshot, self._onAction = nil, nil
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	self._root:Destroy()
	self._introRoot:Destroy()
end

return RoundHud
