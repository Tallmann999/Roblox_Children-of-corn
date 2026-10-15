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
local PROJECT = "children_of_corn"
local NEON_CYCLE = {
	{ 0.8, true },
	{ 0.7, false },
	{ 0.6, true },
	{ 0.9, false },
	{ 4.5, true },
	{ 0.8, false },
	{ 6, true },
}

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
	self._beacon = nil
	self._beaconRefused = nil
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
	if not snapshot or (snapshot.phase ~= "active" and snapshot.phase ~= "caught") then
		self:_restoreBeacon()
		self._beaconRefused = nil
	end
end

local function roadExitOwned(item: Instance, role: string): boolean
	return item:GetAttribute("CornRoadExitOwned") == true
		and item:GetAttribute("corn_project_id") == PROJECT
		and item:GetAttribute("RoadExitVersion") == 1
		and item:GetAttribute("RoadExitRole") == role
end

local function beaconOwned(state: any): boolean
	return workspace:FindFirstChild("CornMap") == state.map
		and state.map:GetAttribute("corn_project_id") == PROJECT
		and state.map:FindFirstChild("Props") == state.props
		and state.props:FindFirstChild("VillageRoad") == state.road
		and state.road:FindFirstChild("ExitSign") == state.sign
		and state.sign:FindFirstChild("ExitTextSurface") == state.surface
		and state.surface:FindFirstChild("ExitText") == state.text
		and state.props.Parent == state.map
		and state.road.Parent == state.props
		and state.sign.Parent == state.road
		and state.surface.Parent == state.sign
		and state.text.Parent == state.surface
		and roadExitOwned(state.road, "Road")
		and roadExitOwned(state.sign, "ExitSign")
		and roadExitOwned(state.surface, "ExitTextSurface")
		and roadExitOwned(state.text, "ExitText")
		and state.text.Text == "ВЫХОД"
end

local function sameBeacon(a: any, b: any): boolean
	return a.sign == b.sign and a.surface == b.surface and a.text == b.text
end

function GateHintController:_restoreBeacon()
	local state = self._beacon
	self._beacon = nil
	if not state or not beaconOwned(state) then
		return
	end
	if state.sign.Color == state.lastColor then
		state.sign.Color = state.color
	end
	if state.text.TextColor3 == state.lastTextColor then
		state.text.TextColor3 = state.textColor
	end
end

local function neonBright(elapsed: number): boolean
	local phase = math.max(0, elapsed) % 14.3
	for _, segment in NEON_CYCLE do
		if phase < segment[1] then
			return segment[2]
		end
		phase -= segment[1]
	end
	return true
end

function GateHintController:_blinkBeacon(now: number)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local capture = self._snapshot and self._snapshot.capture
	if
		not self._snapshot
		or (self._snapshot.phase ~= "active" and self._snapshot.phase ~= "caught")
		or not humanoid
		or humanoid.Health <= 0
		or not root
		or not root:IsA("BasePart")
		or (type(capture) == "table" and type(capture.remaining) == "number" and capture.remaining > 0)
		or GuiService.MenuIsOpen
	then
		self:_restoreBeacon()
		return
	end
	local map = workspace:FindFirstChild("CornMap")
	local props = if map then map:FindFirstChild("Props") else nil
	local road = if props then props:FindFirstChild("VillageRoad") else nil
	local sign = if road then road:FindFirstChild("ExitSign") else nil
	local surface = if sign then sign:FindFirstChild("ExitTextSurface") else nil
	local text = if surface then surface:FindFirstChild("ExitText") else nil
	local candidate =
		{ map = map, props = props, road = road, sign = sign, surface = surface, text = text }
	local state = self._beacon
	if state and not beaconOwned(state) then
		self:_restoreBeacon()
		self._beaconRefused = state
		state = nil
	end
	if self._beaconRefused and sameBeacon(self._beaconRefused, candidate) then
		return
	end
	if
		not map
		or not map:IsA("Model")
		or not props
		or not road
		or not road:IsA("Model")
		or not sign
		or not sign:IsA("BasePart")
		or not surface
		or not surface:IsA("SurfaceGui")
		or not text
		or not text:IsA("TextLabel")
		or not beaconOwned(candidate)
	then
		self:_restoreBeacon()
		return
	end
	self._beaconRefused = nil
	if state and not sameBeacon(state, candidate) then
		self:_restoreBeacon()
		state = nil
	end
	if not state then
		if sign.Material ~= Enum.Material.Neon then
			return
		end
		state = candidate
		state.startedAt = now
		state.color, state.textColor = sign.Color, text.TextColor3
		state.lastColor, state.lastTextColor = sign.Color, text.TextColor3
		state.material, state.ltm, state.enabled =
			sign.Material, sign.LocalTransparencyModifier, surface.Enabled
		state.visible, state.transparency = text.Visible, text.TextTransparency
		self._beacon = state
	end
	-- Foreign changes release this exact pair until ready or a streamed replacement.
	if
		sign.Color ~= state.lastColor
		or text.TextColor3 ~= state.lastTextColor
		or sign.Material ~= state.material
		or sign.LocalTransparencyModifier ~= state.ltm
		or surface.Enabled ~= state.enabled
		or text.Visible ~= state.visible
		or text.TextTransparency ~= state.transparency
	then
		self:_restoreBeacon()
		self._beaconRefused = state
		return
	end
	if not state.enabled or not state.visible then
		return
	end
	local bright = neonBright(now - state.startedAt)
	local color = if bright then state.color else state.color:Lerp(Color3.new(0, 0, 0), 0.94)
	local textColor = if bright
		then state.textColor
		else state.textColor:Lerp(Color3.new(0, 0, 0), 0.9)
	if sign.Color ~= color then
		sign.Color = color
	end
	if text.TextColor3 ~= textColor then
		text.TextColor3 = textColor
	end
	-- BasePart.Color is stored at engine precision. Guard the value actually
	-- written so rounding cannot be mistaken for an external edit next tick.
	state.lastColor, state.lastTextColor = sign.Color, text.TextColor3
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
	self:_blinkBeacon(os.clock())
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
	self:_restoreBeacon()
	self._beaconRefused = nil
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
