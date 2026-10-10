--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local shared = ReplicatedStorage:WaitForChild("GameShared")
local Endpoints = require(shared:WaitForChild("Network"):WaitForChild("EndpointNames"))
local Text = require(shared:WaitForChild("Game"):WaitForChild("RoundText"))

local MovementController = { Name = "MovementController", Order = 90 }
local SPRINT_ACTION = "CornSprint"
local CURSOR_ACTION = "CornCursor"
local player = Players.LocalPlayer

function MovementController:_intent(value: boolean)
	if self._intentValue ~= value then
		self._intentValue = value
		if self._remote then
			self._remote:FireServer(value)
		end
	end
end

function MovementController:_release()
	table.clear(self._shifts)
	self:_intent(false)
end

function MovementController:_camera()
	if self._active or (self._snapshot and self._snapshot.phase == "caught") then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		player.CameraMinZoomDistance = 0.5
		player.CameraMaxZoomDistance = 0.5
		local camera = workspace.CurrentCamera
		if camera and self._snapshot and self._active then
			local position = camera.CFrame.Position
			camera.CFrame = CFrame.lookAt(position, position + self._snapshot.start_look)
		end
	else
		player.CameraMaxZoomDistance = self._savedMax
		player.CameraMinZoomDistance = self._savedMin
		player.CameraMode = self._savedMode
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end

function MovementController:_render()
	self._gui.Enabled = self._active
	self._cursorGuard.Visible = self._active and self._cursorOpen
	if self._roundLeave then
		self._roundLeave.Modal = self._active and self._cursorOpen
	end
	local s = self._snapshot
	if not s then
		return
	end
	local ratio = math.clamp(s.stamina / s.stamina_capacity, 0, 1)
	self._fill.Size = UDim2.fromScale(ratio, 1)
	self._fill.BackgroundColor3 = if s.sprint_exhausted
		then Color3.fromRGB(191, 146, 71)
		else Color3.fromRGB(119, 161, 86)
	self._label.Text = string.gsub(
		Text.corn_movement_stamina,
		"{percent}",
		tostring(math.floor(ratio * 100 + 0.5))
	)
	self._hint.Text = if self._cursorOpen
		then Text.corn_movement_cursor
		elseif s.sprint_exhausted then Text.corn_movement_exhausted
		else Text.corn_movement_controls
end

function MovementController:Init(_context: any)
	self._active = false
	self._cursorOpen = false
	self._intentValue = false
	self._shifts = {}
	self._connections = {}
	self._savedMode = player.CameraMode
	self._savedMin = player.CameraMinZoomDistance
	self._savedMax = player.CameraMaxZoomDistance
	local gui = Instance.new("ScreenGui")
	gui.Name = "CornMovementHud"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	self._gui = gui
	local guard = Instance.new("TextButton")
	guard.Name = "CursorGuard"
	guard.Size = UDim2.fromOffset(1, 1)
	guard.BackgroundTransparency = 1
	guard.Text = ""
	guard.Modal = true
	guard.Visible = false
	guard.Parent = gui
	self._cursorGuard = guard
	local panel = Instance.new("Frame")
	panel.Name = "Stamina"
	panel.Size = UDim2.fromOffset(350, 88)
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, 20, 1, -20)
	panel.BackgroundColor3 = Color3.fromRGB(27, 32, 28)
	panel.BackgroundTransparency = 0.12
	panel.BorderSizePixel = 0
	panel.Parent = gui
	local function label(name: string, y: number, size: number): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.Position = UDim2.fromOffset(12, y)
		l.Size = UDim2.new(1, -24, 0, 24)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.Gotham
		l.TextSize = size
		l.TextColor3 = Color3.fromRGB(239, 242, 233)
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Parent = panel
		return l
	end
	self._label = label("Amount", 6, 16)
	self._hint = label("Controls", 57, 12)
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Position = UDim2.fromOffset(12, 37)
	track.Size = UDim2.new(1, -24, 0, 10)
	track.BackgroundColor3 = Color3.fromRGB(63, 69, 61)
	track.BorderSizePixel = 0
	track.Parent = panel
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BorderSizePixel = 0
	fill.Parent = track
	self._fill = fill
end

function MovementController:SetSnapshot(snapshot: any)
	local active = snapshot.phase == "active"
	local previousPhase = if self._snapshot then self._snapshot.phase else ""
	self._snapshot = snapshot
	if active ~= self._active then
		self:_release()
		self._cursorOpen = false
		self._active = active
		self:_camera()
	elseif snapshot.phase ~= previousPhase then
		self:_camera()
	end
	self:_render()
end

function MovementController:Start(_context: any)
	local folder = ReplicatedStorage:WaitForChild("GameRemotes", 10)
	assert(folder, "Movement remotes are unavailable")
	local remote = folder:WaitForChild(Endpoints.RequestSprintIntent, 10)
	assert(remote and remote:IsA("RemoteEvent"), "Sprint intent remote is unavailable")
	self._remote = remote
	self._roundLeave = player.PlayerGui:WaitForChild("CornRoundHud"):WaitForChild("LeaveRound")
	ContextActionService:BindActionAtPriority(
		SPRINT_ACTION,
		function(_, state: Enum.UserInputState, input: InputObject)
			if state == Enum.UserInputState.Begin then
				if
					self._active
					and not self._cursorOpen
					and not UserInputService:GetFocusedTextBox()
				then
					self._shifts[input.KeyCode] = true
				end
			elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				self._shifts[input.KeyCode] = nil
			end
			self:_intent(self._active and not self._cursorOpen and next(self._shifts) ~= nil)
			return Enum.ContextActionResult.Sink
		end,
		false,
		3000,
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.RightShift
	)
	ContextActionService:BindActionAtPriority(CURSOR_ACTION, function(_, state: Enum.UserInputState)
		if not self._active then
			return Enum.ContextActionResult.Pass
		end
		if state == Enum.UserInputState.Begin then
			self._cursorOpen = not self._cursorOpen
			self:_release()
			self:_render()
		end
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.KeyCode.LeftAlt)
	for _, signal in { UserInputService.WindowFocusReleased, GuiService.MenuOpened } do
		table.insert(
			self._connections,
			signal:Connect(function()
				self:_release()
			end)
		)
	end
	table.insert(
		self._connections,
		player.CharacterAdded:Connect(function()
			self:_release()
			self:_camera()
		end)
	)
end

function MovementController:Destroy()
	self:_release()
	self._active = false
	self:_camera()
	ContextActionService:UnbindAction(SPRINT_ACTION)
	ContextActionService:UnbindAction(CURSOR_ACTION)
	for _, connection in self._connections do
		connection:Disconnect()
	end
	self._gui:Destroy()
end

return MovementController
