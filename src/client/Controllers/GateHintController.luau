--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local player = Players.LocalPlayer

local GateHintController = { Name = "GateHintController", Order = 86 }
local ENTER_RADIUS = 22
local EXIT_RADIUS = 24
local HEIGHT_TOLERANCE = 12
local UPDATE_INTERVAL = 0.1
local PANEL_WIDTH = 436

local function eligible(snapshot: any): boolean
	return snapshot ~= nil
		and snapshot.phase == "active"
		and snapshot.has_key == false
		and snapshot.gate_open == false
end

local function label(
	parent: Instance,
	name: string,
	position: UDim2,
	size: UDim2,
	text: string,
	font: Enum.Font,
	textSize: number
): TextLabel
	local item = Instance.new("TextLabel")
	item.Name = name
	item.Position = position
	item.Size = size
	item.BackgroundTransparency = 1
	item.Active = false
	item.Font = font
	item.TextSize = textSize
	item.TextColor3 = Color3.fromRGB(239, 242, 233)
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.Text = text
	item.Parent = parent
	return item
end

function GateHintController:Init(_context: any)
	self._snapshot = nil
	self._shown = false
	self._elapsed = math.huge
	self._connection = nil
	local gui = Instance.new("ScreenGui")
	gui.Name = "CornGateHint"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 18
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	self._gui = gui
	local panel = Instance.new("Frame")
	panel.Name = "NeedKey"
	panel.Size = UDim2.fromOffset(PANEL_WIDTH, 92)
	panel.Position = UDim2.new(0.5, 0, 1, -124)
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.BackgroundColor3 = Color3.fromRGB(27, 32, 28)
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Active = false
	panel.Parent = gui
	self._panel = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = panel
	local border = Instance.new("UIStroke")
	border.Color = Color3.fromRGB(219, 73, 63)
	border.Transparency = 0.25
	border.Thickness = 1
	border.Parent = panel
	local icon = Instance.new("Frame")
	icon.Name = "StopSign"
	icon.Position = UDim2.fromOffset(14, 14)
	icon.Size = UDim2.fromOffset(64, 64)
	icon.BackgroundTransparency = 1
	icon.Active = false
	icon.Parent = panel
	for row, width in { 44, 54, 60, 64, 64, 60, 54, 44 } do
		local slice = Instance.new("Frame")
		slice.Name = "Slice" .. row
		slice.Size = UDim2.fromOffset(width, 8)
		slice.Position = UDim2.new(0.5, 0, 0, (row - 1) * 8)
		slice.AnchorPoint = Vector2.new(0.5, 0)
		slice.BackgroundColor3 = Color3.fromRGB(219, 73, 63)
		slice.BorderSizePixel = 0
		slice.Active = false
		slice.Parent = icon
	end
	local stop = label(
		icon,
		"StopText",
		UDim2.fromOffset(0, 0),
		UDim2.fromScale(1, 1),
		"STOP",
		Enum.Font.GothamBold,
		17
	)
	stop.TextXAlignment = Enum.TextXAlignment.Center
	stop.ZIndex = 2
	label(
		panel,
		"Headline",
		UDim2.fromOffset(92, 17),
		UDim2.fromOffset(328, 27),
		"Нужно найти ключ",
		Enum.Font.GothamBold,
		19
	)
	local helper = label(
		panel,
		"Helper",
		UDim2.fromOffset(92, 46),
		UDim2.fromOffset(328, 25),
		"Найди ключ в одном из просветов",
		Enum.Font.Gotham,
		13
	)
	helper.TextColor3 = Color3.fromRGB(190, 199, 186)
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	self._scale = scale
end

function GateHintController:_show(visible: boolean)
	if self._shown == visible then
		return
	end
	self._shown = visible
	self._panel.Visible = visible
	self._gui.Enabled = visible
end

function GateHintController:SetSnapshot(snapshot: any)
	self._snapshot = snapshot
	if not eligible(snapshot) then
		self:_show(false)
	end
end

function GateHintController:_gatePosition(): Vector3?
	local map = workspace:FindFirstChild("CornMap")
	if
		not map
		or not map:IsA("Model")
		or map:GetAttribute("corn_project_id") ~= "children_of_corn"
	then
		return nil
	end
	local gate = map:FindFirstChild("EscapeGate")
	if not gate or not gate:IsA("Model") or not gate:HasTag("corn_gate") then
		return nil
	end
	local anchor = gate:FindFirstChild("InteractionAnchor")
	return if anchor and anchor:IsA("BasePart") then anchor.Position else nil
end

function GateHintController:_canShow(position: Vector3?, anchor: Vector3?, alive: boolean): boolean
	if not eligible(self._snapshot) or not alive or not position or not anchor then
		return false
	end
	local delta = position - anchor
	local radius = if self._shown then EXIT_RADIUS else ENTER_RADIUS
	return math.abs(delta.Y) <= HEIGHT_TOLERANCE
		and delta.X * delta.X + delta.Z * delta.Z <= radius * radius
end

function GateHintController:_update()
	local position = nil
	local alive = false
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		position = root.Position
		alive = true
	end
	self:_show(self:_canShow(position, self:_gatePosition(), alive))
	local camera = workspace.CurrentCamera
	if camera then
		local topLeft, bottomRight = GuiService:GetGuiInset()
		local viewport = camera.ViewportSize - topLeft - bottomRight
		self._scale.Scale = math.min(1, math.max(0.1, (viewport.X - 24) / PANEL_WIDTH))
	end
end

function GateHintController:Start(_context: any)
	if self._connection then
		return
	end
	self._connection = RunService.RenderStepped:Connect(function(dt: number)
		self._elapsed += dt
		if self._elapsed >= UPDATE_INTERVAL then
			self._elapsed = 0
			self:_update()
		end
	end)
end

function GateHintController:Destroy()
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	self:_show(false)
	if self._gui then
		self._gui:Destroy()
		self._gui = nil
	end
	self._snapshot = nil
end

return GateHintController
