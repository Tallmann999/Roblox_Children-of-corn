--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RoundText: { [string]: string } = require(
	ReplicatedStorage:WaitForChild("GameShared"):WaitForChild("Game"):WaitForChild("RoundText")
)

local LightingModes = require(ReplicatedStorage.GameShared.Game.LightingModes)

local MinimapGeometry = require(ReplicatedStorage.GameShared.Game.MinimapGeometry)

export type Snapshot = {
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
	local profile = (LightingModes.Profiles :: any)[mode]
	local sky = Instance.new("Frame")
	sky.Name = "LightingPreview"
	sky.Size = UDim2.new(1, -20, 0, 112)
	sky.Position = UDim2.fromOffset(10, 10)
	sky.BorderSizePixel = 0
	sky.BackgroundColor3 = Color3.new(1, 1, 1)
	sky.ClipsDescendants = true
	sky.Parent = parent
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(profile.SkyTop, profile.SkyBottom)
	gradient.Rotation = 90
	gradient.Parent = sky
	local sun = Instance.new("Frame")
	sun.Name = if mode == "hard" then "Moon" else "Sun"
	sun.Size =
		UDim2.fromOffset(if mode == "hard" then 12 else 22, if mode == "hard" then 12 else 22)
	sun.Position = UDim2.fromScale(0.76, if mode == "medium" then 0.46 else 0.16)
	sun.BackgroundColor3 = if mode == "hard"
		then Color3.fromRGB(185, 203, 220)
		else Color3.fromRGB(255, 224, 158)
	sun.BorderSizePixel = 0
	sun.Parent = sky
	local circle = Instance.new("UICorner")
	circle.CornerRadius = UDim.new(1, 0)
	circle.Parent = sun
	local view = Instance.new("ViewportFrame")
	view.Name = "FieldImage"
	view.Size = UDim2.fromScale(1, 1)
	view.BackgroundTransparency = 1
	view.Ambient = profile.Ambient
	view.LightColor = if mode == "easy"
		then Color3.fromRGB(255, 244, 204)
		elseif mode == "medium" then Color3.fromRGB(182, 126, 90)
		else Color3.fromRGB(65, 80, 110)
	view.LightDirection = Vector3.new(-0.5, -1, -0.3)
	view.Parent = sky
	local world = Instance.new("WorldModel")
	world.Parent = view
	local function part(
		name: string,
		size: Vector3,
		frame: CFrame,
		color: Color3,
		neon: boolean?
	): Part
		local item = Instance.new("Part")
		item.Name = name
		item.Size = size
		item.CFrame = frame
		item.Color = color
		item.Anchored = true
		item.CanCollide = false
		item.CastShadow = false
		item.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
		item.Parent = world
		return item
	end
	part("Ground", Vector3.new(28, 0.4, 28), CFrame.new(0, -0.2, 0), Color3.fromRGB(74, 70, 39))
	for row = 1, 4 do
		for column = 1, 6 do
			local x, z = (column - 3.5) * 3.4, (row - 2.5) * 3.4
			if math.abs(x) > 2.5 or row > 2 then
				local height = 4.5 + ((row + column) % 3) * 0.35
				part(
					"Stalk",
					Vector3.new(0.15, height, 0.15),
					CFrame.new(x, height / 2, z),
					Color3.fromRGB(120, 126, 53)
				)
				for _, side in { -1, 1 } do
					part(
						"Leaf",
						Vector3.new(2, 0.25, 0.7),
						CFrame.new(x + side * 0.65, height * 0.6, z)
							* CFrame.Angles(0, row * 0.4, side * 0.4),
						Color3.fromRGB(99, 119, 43)
					)
				end
			end
		end
	end
	part("House", Vector3.new(5, 4, 4), CFrame.new(-8, 2, -9), Color3.fromRGB(84, 60, 46))
	part("Roof", Vector3.new(6, 0.5, 5), CFrame.new(-8, 4.2, -9), Color3.fromRGB(51, 42, 40))
	part("TorchPole", Vector3.new(0.3, 7, 0.3), CFrame.new(2.4, 3.5, 1), Color3.fromRGB(86, 60, 38))
	if profile.Torches then
		part(
			"TorchFlame",
			Vector3.new(0.7, 1.2, 0.7),
			CFrame.new(2.4, 7.3, 1),
			Color3.fromRGB(255, 154, 51),
			true
		)
	end
	local camera = Instance.new("Camera")
	camera.FieldOfView = 48
	camera.CFrame = CFrame.lookAt(Vector3.new(16, 12, 23), Vector3.new(0, 2.4, 0))
	camera.Parent = view
	view.CurrentCamera = camera
	if mode == "hard" then
		local fog = Instance.new("Frame")
		fog.Name = "Mist"
		fog.Size = UDim2.fromScale(1, 1)
		fog.BorderSizePixel = 0
		fog.BackgroundColor3 = profile.FogColor
		fog.BackgroundTransparency = 0.65
		fog.Parent = sky
		local fade = Instance.new("UIGradient")
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(0.65, 0.7),
			NumberSequenceKeypoint.new(1, 0),
		})
		fade.Parent = fog
	end
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
	modeCards.Size = UDim2.new(1, -48, 0, 242)
	modeCards.Position = UDim2.fromOffset(24, 142)
	modeCards.Parent = card
	local choose =
		label(card, "ChooseMode", UDim2.new(1, -48, 0, 24), UDim2.fromOffset(24, 110), 16)
	choose.TextColor3 = MUTED_COLOR
	local modeHint =
		label(card, "ModeHint", UDim2.new(1, -48, 0, 24), UDim2.fromOffset(24, 392), 15)
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
		local name = label(option, "Name", UDim2.new(1, -20, 0, 28), UDim2.fromOffset(10, 128), 21)
		name.Font = Enum.Font.GothamBold
		name.Text = text("corn_modes_" .. mode)
		local description =
			label(option, "Description", UDim2.new(1, -20, 0, 30), UDim2.fromOffset(10, 160), 15)
		description.TextColor3 = MUTED_COLOR
		description.Text = text("corn_modes_" .. mode .. "_desc")
		local select = button(
			option,
			"Select",
			"corn_modes_select",
			UDim2.new(1, -20, 0, 32),
			UDim2.fromOffset(10, 200)
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
		_buttons = { start, retry, menu, preparingLeave, activeLeave },
		_connections = {} :: { RBXScriptConnection },
		_snapshot = nil :: Snapshot?,
		_busy = false,
		_unavailable = false,
	}, RoundHud)
	for mode, select in modeButtons do
		table.insert(
			self._connections,
			select.Activated:Connect(function()
				if not self._busy and not self._unavailable and self._snapshot then
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
		end)
	)
	self:_render()
	return self
end

function RoundHud:_fitCard()
	local viewport = self._root.AbsoluteSize
	if viewport.X > 0 and viewport.Y > 0 then
		self._cardScale.Scale = math.min(
			1,
			(viewport.X - 36) / self._card.Size.X.Offset,
			(viewport.Y - 36) / self._card.Size.Y.Offset
		)
	end
end

function RoundHud:SetOnAction(callback: (string, string?) -> ())
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
					callback(
						binding.action,
						if binding.action == "start" or binding.action == "retry"
							then self._selectedMode
							else nil
					)
				end
			end)
		)
	end
end

function RoundHud:_render()
	local snapshot = self._snapshot
	local phase = if snapshot then snapshot.phase else "loading"
	local isActive = phase == "active"
	local isResult = phase == "escaped" or phase == "aborted" or phase == "caught_out"
	local expanded = phase == "ready" or isResult
	self._card.Size = if expanded then UDim2.fromOffset(780, 510) else UDim2.fromOffset(460, 320)
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
	self._balance.Position = UDim2.fromOffset(24, if expanded then 420 else 154)
	self._notice.Position = UDim2.fromOffset(24, if expanded then 392 else 186)
	self._notice.Visible = not expanded
	for _, control in { self._start, self._retry, self._menu, self._preparingLeave } do
		control.Position = UDim2.new(
			control.Position.X.Scale,
			control.Position.X.Offset,
			0,
			if expanded then 456 else 250
		)
	end
	for mode, control in self._modeButtons do
		local enabled = expanded and snapshot ~= nil and not self._busy and not self._unavailable
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
	self._card.Visible = not isActive
	self._active.Visible = isActive
	self._activeLeave.Visible = isActive
	self._start.Visible = phase == "ready" or phase == "loading"
	self._retry.Visible = isResult
	self._menu.Visible = isResult
	self._preparingLeave.Visible = phase == "preparing" or phase == "caught"
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
