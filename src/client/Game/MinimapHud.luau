--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Geometry = require(
	ReplicatedStorage:WaitForChild("GameShared")
		:WaitForChild("Game")
		:WaitForChild("MinimapGeometry")
)

local MinimapHud = {}
MinimapHud.__index = MinimapHud

local PANEL = Color3.fromRGB(27, 32, 28)
local FIELD = Color3.fromRGB(49, 61, 40)
local GRID = Color3.fromRGB(87, 99, 70)
local CREAM = Color3.fromRGB(239, 242, 218)
local MUTED = Color3.fromRGB(185, 195, 173)
local RED = Color3.fromRGB(233, 94, 83)
local DARK = Color3.fromRGB(35, 25, 24)
local PLAYER = Color3.fromRGB(94, 220, 255)
local GATE = Color3.fromRGB(61, 121, 255)

local function round(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function frame(
	parent: Instance,
	name: string,
	size: UDim2,
	position: UDim2,
	color: Color3
): Frame
	local result = Instance.new("Frame")
	result.Name = name
	result.Size = size
	result.Position = position
	result.BackgroundColor3 = color
	result.BorderSizePixel = 0
	result.Parent = parent
	return result
end

local function label(
	parent: Instance,
	name: string,
	size: UDim2,
	position: UDim2,
	text: string,
	textSize: number
): TextLabel
	local result = Instance.new("TextLabel")
	result.Name = name
	result.Size = size
	result.Position = position
	result.BackgroundTransparency = 1
	result.Font = Enum.Font.GothamMedium
	result.TextColor3 = CREAM
	result.TextSize = textSize
	result.Text = text
	result.Parent = parent
	return result
end

local function skull(parent: Instance, name: string, scale: number): Frame
	local marker = frame(
		parent,
		name,
		UDim2.fromOffset(16 * scale, 18 * scale),
		UDim2.fromScale(0.5, 0.5),
		RED
	)
	marker.BackgroundTransparency = 1
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.ZIndex = 5
	local function part(
		partName: string,
		width: number,
		height: number,
		x: number,
		y: number,
		color: Color3,
		radius: number?
	)
		local item = frame(
			marker,
			partName,
			UDim2.fromOffset(width * scale, height * scale),
			UDim2.fromOffset(x * scale, y * scale),
			color
		)
		item.ZIndex = 6
		if radius then
			round(item, radius * scale)
		end
		return item
	end
	part("Head", 16, 13, 0, 0, RED, 6)
	part("Jaw", 10, 7, 3, 10, RED, 2)
	part("LeftEye", 4, 4, 2, 5, DARK, 1)
	part("RightEye", 4, 4, 10, 5, DARK, 1)
	part("Nose", 2, 3, 7, 8, DARK, 1)
	for x = 5, 11, 3 do
		part("Tooth" .. x, 1, 4, x, 13, DARK)
	end
	return marker
end

local function mapView(
	parent: Instance,
	name: string,
	side: number,
	position: UDim2,
	expanded: boolean
): any
	local box = frame(parent, name, UDim2.fromOffset(side, side), position, PANEL)
	local field = frame(box, "Field", UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), FIELD)
	field.AnchorPoint = Vector2.new(0.5, 0.5)
	local border = Instance.new("UIStroke")
	border.Color = GRID
	border.Thickness = 1
	border.Parent = field
	for i = 1, 4 do
		local fraction = i / 5
		local vertical = frame(
			field,
			"GridColumn" .. i,
			UDim2.new(0, 1, 1, 0),
			UDim2.fromScale(fraction, 0),
			GRID
		)
		vertical.BackgroundTransparency = 0.68
		local horizontal =
			frame(field, "GridRow" .. i, UDim2.new(1, 0, 0, 1), UDim2.fromScale(0, fraction), GRID)
		horizontal.BackgroundTransparency = 0.68
	end
	local north = label(
		field,
		"North",
		UDim2.fromOffset(24, 20),
		UDim2.new(0.5, -12, 0, 2),
		"С",
		if expanded then 14 else 11
	)
	north.TextColor3 = MUTED
	local scale = if expanded then 1.25 else 1
	local arrow = frame(
		field,
		"PlayerArrow",
		UDim2.fromOffset(16 * scale, 30 * scale),
		UDim2.fromScale(0.5, 0.5),
		PLAYER
	)
	arrow.BackgroundTransparency = 1
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.ZIndex = 7
	arrow.Visible = false
	local shaft = frame(
		arrow,
		"Shaft",
		UDim2.fromOffset(7 * scale, 20 * scale),
		UDim2.fromOffset(4.5 * scale, 8 * scale),
		PLAYER
	)
	shaft.ZIndex = 8
	local shaftBorder = Instance.new("UIStroke")
	shaftBorder.Color = PANEL
	shaftBorder.Thickness = 1
	shaftBorder.Parent = shaft
	-- Solid GUI rows keep the direction tip triangular at every arrow Rotation.
	local tip = frame(
		arrow,
		"Tip",
		UDim2.fromOffset(16 * scale, 10 * scale),
		UDim2.fromOffset(0, 0),
		PLAYER
	)
	tip.BackgroundTransparency = 1
	tip.ZIndex = 9
	for row = 1, 7 do
		local slice = frame(
			tip,
			"Slice" .. row,
			UDim2.fromOffset(row * 2 * scale, 1.25 * scale),
			UDim2.new(0.5, 0, 0, (row + 1) * scale),
			PLAYER
		)
		slice.AnchorPoint = Vector2.new(0.5, 0)
		slice.ZIndex = 9
	end
	local gateSide = if expanded then 15 else 10
	local gate = frame(
		field,
		"ExitGate",
		UDim2.fromOffset(gateSide, gateSide),
		UDim2.fromScale(0.5, 0.5),
		GATE
	)
	gate.AnchorPoint = Vector2.new(0.5, 0.5)
	gate.ZIndex = 3
	gate.Visible = false
	local gateBorder = Instance.new("UIStroke")
	gateBorder.Color = CREAM
	gateBorder.Transparency = 0.2
	gateBorder.Thickness = 1
	gateBorder.Parent = gate
	return {
		Field = field,
		Arrow = arrow,
		Gate = gate,
		Visited = {},
		Deaths = {},
		Expanded = expanded,
	}
end

local function place(marker: GuiObject, field: Frame, point: Vector2, padding: number?)
	local dimensions = field.AbsoluteSize
	local inset = padding or 13
	local padX = math.min(0.49, inset / math.max(1, dimensions.X))
	local padY = math.min(0.49, inset / math.max(1, dimensions.Y))
	marker.Position =
		UDim2.fromScale(math.clamp(point.X, padX, 1 - padX), math.clamp(point.Y, padY, 1 - padY))
end

function MinimapHud.new(playerGui: PlayerGui)
	local gui = Instance.new("ScreenGui")
	gui.Name = "CornMinimapHud"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	gui.Enabled = false
	gui.Parent = playerGui

	local compact = Instance.new("TextButton")
	compact.Name = "CompactMap"
	compact.Size = UDim2.fromOffset(Geometry.CompactSize + 24, Geometry.CompactSize + 68)
	compact.AnchorPoint = Vector2.new(1, 0)
	compact.Position = UDim2.new(1, -20, 0, 68)
	compact.BackgroundColor3 = PANEL
	compact.BorderSizePixel = 0
	compact.AutoButtonColor = false
	compact.Text = ""
	compact.Parent = gui
	round(compact, 7)
	local title =
		label(compact, "Title", UDim2.new(1, -24, 0, 22), UDim2.fromOffset(12, 3), "КАРТА", 12)
	title.TextXAlignment = Enum.TextXAlignment.Left
	local compactView =
		mapView(compact, "Map", Geometry.CompactSize, UDim2.fromOffset(12, 30), false)
	local count = label(
		compact,
		"VisitCount",
		UDim2.new(1, -16, 0, 15),
		UDim2.fromOffset(8, Geometry.CompactSize + 35),
		"Проверено: 0 / 18",
		11
	)
	count.TextColor3 = MUTED
	local hint = label(
		compact,
		"OpenHint",
		UDim2.new(1, -16, 0, 15),
		UDim2.fromOffset(8, Geometry.CompactSize + 50),
		"Alt + клик · M",
		11
	)
	hint.TextColor3 = MUTED
	local compactScale = Instance.new("UIScale")
	compactScale.Parent = compact

	local overlay = frame(
		gui,
		"ExpandedMap",
		UDim2.fromScale(1, 1),
		UDim2.fromScale(0, 0),
		Color3.fromRGB(7, 10, 8)
	)
	overlay.BackgroundTransparency = 0.28
	overlay.Visible = false
	overlay.Active = true
	local panel =
		frame(overlay, "MapCard", UDim2.fromOffset(640, 700), UDim2.fromScale(0.5, 0.5), PANEL)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	round(panel, 9)
	local heading = label(
		panel,
		"Title",
		UDim2.fromOffset(440, 32),
		UDim2.fromOffset(20, 12),
		"КАРТА ПОЛЯ",
		21
	)
	heading.TextXAlignment = Enum.TextXAlignment.Left
	local close = Instance.new("TextButton")
	close.Name = "CloseMap"
	close.Position = UDim2.fromOffset(510, 12)
	close.Size = UDim2.fromOffset(110, 32)
	close.BackgroundColor3 = Color3.fromRGB(72, 86, 56)
	close.BorderSizePixel = 0
	close.Text = "Закрыть · M"
	close.TextSize = 13
	close.TextColor3 = CREAM
	close.Font = Enum.Font.GothamMedium
	close.Modal = true
	close.Parent = panel
	round(close, 5)
	local expandedView = mapView(panel, "Map", 600, UDim2.fromOffset(20, 58), true)
	local legend = label(
		panel,
		"Legend",
		UDim2.fromOffset(590, 20),
		UDim2.fromOffset(25, 666),
		"Голубая стрелка — вы · синий квадрат — выход · × проверено · череп — смерть",
		13
	)
	legend.TextColor3 = MUTED
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	local self = setmetatable({
		_gui = gui,
		_compact = compact,
		_compactScale = compactScale,
		_overlay = overlay,
		_expandedScale = scale,
		_count = count,
		_views = { compactView, expandedView },
		_visited = {},
		_deaths = {},
		_connections = {},
		_onExpand = nil,
		_onClose = nil,
	}, MinimapHud)
	table.insert(
		self._connections,
		compact.Activated:Connect(function()
			if self._onExpand then
				self._onExpand()
			end
		end)
	)
	table.insert(
		self._connections,
		close.Activated:Connect(function()
			if self._onClose then
				self._onClose()
			end
		end)
	)
	return self
end

function MinimapHud:SetOnExpand(callback: () -> ())
	self._onExpand = callback
end

function MinimapHud:SetOnClose(callback: () -> ())
	self._onClose = callback
end

function MinimapHud:SetVisible(visible: boolean)
	self._gui.Enabled = visible
end

function MinimapHud:SetExpanded(expanded: boolean)
	self._overlay.Visible = expanded
	self._compact.Visible = not expanded
end

function MinimapHud:SetViewport(size: Vector2)
	self._expandedScale.Scale =
		math.min(1, math.max(0.1, math.min((size.X - 32) / 640, (size.Y - 32) / 700)))
	self._compactScale.Scale =
		math.min(1, math.max(0.25, (size.Y - 84) / (Geometry.CompactSize + 68)))
end

function MinimapHud:SetSnapshot(snapshot: any)
	self._visited = snapshot.minimap.visited
	self._deaths = snapshot.minimap.deaths
	self._count.Text = string.format("Проверено: %d / 18", #self._visited)
	for _, view in self._views do
		local visitedIds = {}
		for _, entry in self._visited do
			visitedIds[entry.id] = true
			if not view.Visited[entry.id] then
				local marker = label(
					view.Field,
					"Visited_" .. entry.id,
					UDim2.fromOffset(20, 20),
					UDim2.fromScale(0.5, 0.5),
					"×",
					if view.Expanded then 22 else 17
				)
				marker.AnchorPoint = Vector2.new(0.5, 0.5)
				marker.ZIndex = 4
				view.Visited[entry.id] = marker
			end
		end
		for id, marker in view.Visited do
			if not visitedIds[id] then
				marker:Destroy()
				view.Visited[id] = nil
			end
		end
		local deathIds = {}
		for _, entry in self._deaths do
			deathIds[entry.id] = true
			if not view.Deaths[entry.id] then
				view.Deaths[entry.id] =
					skull(view.Field, "Death_" .. entry.id, if view.Expanded then 1.2 else 1)
			end
		end
		for id, marker in view.Deaths do
			if not deathIds[id] then
				marker:Destroy()
				view.Deaths[id] = nil
			end
		end
	end
end

function MinimapHud:Update(
	fieldFrame: CFrame,
	fieldSize: Vector3,
	playerPosition: Vector3?,
	direction: Vector3?,
	gatePosition: Vector3?
)
	local ratio = fieldSize.X / math.max(0.001, fieldSize.Z)
	for _, view in self._views do
		view.Field.Size = UDim2.fromScale(math.min(1, ratio), math.min(1, 1 / ratio))
		for _, entry in self._visited do
			place(
				view.Visited[entry.id],
				view.Field,
				Geometry.Project(fieldFrame, fieldSize, entry.position)
			)
		end
		for _, entry in self._deaths do
			place(
				view.Deaths[entry.id],
				view.Field,
				Geometry.Project(fieldFrame, fieldSize, entry.position)
			)
		end
		view.Gate.Visible = gatePosition ~= nil
		if gatePosition then
			place(
				view.Gate,
				view.Field,
				Geometry.Project(fieldFrame, fieldSize, gatePosition),
				if view.Expanded then 10 else 7
			)
		end
		view.Arrow.Visible = playerPosition ~= nil and direction ~= nil
		if playerPosition and direction then
			place(
				view.Arrow,
				view.Field,
				Geometry.Project(fieldFrame, fieldSize, playerPosition),
				if view.Expanded then 22 else 18
			)
			view.Arrow.Rotation = Geometry.Heading(fieldFrame, direction)
		end
	end
end

function MinimapHud:Destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	self._onExpand = nil
	self._onClose = nil
	self._gui:Destroy()
end

return MinimapHud
