--!strict

local InventoryHud = {}
InventoryHud.__index = InventoryHud

local CAPACITY = 5
local SLOT_SIZE = 68
local GAP = 8
local WIDTH = CAPACITY * SLOT_SIZE + (CAPACITY - 1) * GAP
local SEGMENTS = 36
local PANEL = Color3.fromRGB(27, 32, 28)
local TEXT = Color3.fromRGB(239, 242, 233)
local MUTED = Color3.fromRGB(171, 181, 170)
local GREEN = Color3.fromRGB(104, 222, 128)
local RED = Color3.fromRGB(248, 91, 83)
local ITEM_NAMES =
	{ empty = "", key = "Ключ", energy = "Энергетик", trap = "Капкан" }

local function frame(
	parent: Instance,
	name: string,
	size: UDim2,
	position: UDim2,
	color: Color3
): Frame
	local item = Instance.new("Frame")
	item.Name = name
	item.Size = size
	item.Position = position
	item.BackgroundColor3 = color
	item.BorderSizePixel = 0
	item.Parent = parent
	return item
end

local function corner(parent: Instance, radius: number)
	local item = Instance.new("UICorner")
	item.CornerRadius = UDim.new(0, radius)
	item.Parent = parent
end

local function label(
	parent: Instance,
	name: string,
	size: UDim2,
	position: UDim2,
	textSize: number
): TextLabel
	local item = Instance.new("TextLabel")
	item.Name = name
	item.Size = size
	item.Position = position
	item.BackgroundTransparency = 1
	item.Font = Enum.Font.GothamMedium
	item.TextSize = textSize
	item.TextColor3 = TEXT
	item.Text = ""
	item.Parent = parent
	return item
end

local function icon(parent: Instance, kind: string): Frame
	local root = frame(parent, kind, UDim2.fromOffset(42, 32), UDim2.fromOffset(13, 16), PANEL)
	root.BackgroundTransparency = 1
	root.Visible = false
	if kind == "key" then
		local gold = Color3.fromRGB(246, 211, 112)
		local ring = frame(root, "Bow", UDim2.fromOffset(17, 17), UDim2.fromOffset(2, 4), gold)
		corner(ring, 9)
		local hollow = frame(ring, "Hole", UDim2.fromOffset(9, 9), UDim2.fromOffset(4, 4), PANEL)
		corner(hollow, 5)
		frame(root, "Shaft", UDim2.fromOffset(24, 5), UDim2.fromOffset(15, 10), gold)
		frame(root, "Tooth1", UDim2.fromOffset(5, 7), UDim2.fromOffset(26, 14), gold)
		frame(root, "Tooth2", UDim2.fromOffset(5, 10), UDim2.fromOffset(34, 14), gold)
	elseif kind == "energy" then
		local can = frame(root, "Can", UDim2.fromOffset(20, 30), UDim2.fromOffset(11, 1), GREEN)
		corner(can, 4)
		frame(can, "Top", UDim2.fromOffset(18, 3), UDim2.fromOffset(1, 1), MUTED)
		frame(can, "Bottom", UDim2.fromOffset(18, 3), UDim2.fromOffset(1, 26), MUTED)
		local mark = label(can, "Mark", UDim2.fromOffset(20, 20), UDim2.fromOffset(0, 4), 20)
		mark.Text = "+"
		mark.TextColor3 = PANEL
	elseif kind == "trap" then
		local steel = Color3.fromRGB(180, 190, 197)
		local base = frame(root, "Base", UDim2.fromOffset(38, 15), UDim2.fromOffset(2, 13), steel)
		corner(base, 7)
		local opening =
			frame(base, "Opening", UDim2.fromOffset(28, 7), UDim2.fromOffset(5, 4), PANEL)
		corner(opening, 4)
		for index = 0, 4 do
			local tooth = frame(
				root,
				"Tooth" .. index,
				UDim2.fromOffset(4, 8),
				UDim2.fromOffset(5 + index * 7, 7),
				steel
			)
			tooth.Rotation = if index % 2 == 0 then -15 else 15
		end
		frame(root, "Plate", UDim2.fromOffset(9, 5), UDim2.fromOffset(17, 18), steel)
	end
	return root
end

function InventoryHud.new(playerGui: PlayerGui, touch: boolean)
	local root = Instance.new("ScreenGui")
	root.Name = "CornInventoryHud"
	root.ResetOnSpawn = false
	root.DisplayOrder = 25
	root.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	root.Enabled = false
	root.Parent = playerGui
	local bar =
		frame(root, "Inventory", UDim2.fromOffset(WIDTH, 94), UDim2.new(1, -20, 1, -20), PANEL)
	bar.AnchorPoint = Vector2.new(1, 1)
	bar.BackgroundTransparency = 1
	local scale = Instance.new("UIScale")
	scale.Parent = bar
	local caption = label(bar, "Controls", UDim2.new(1, 0, 0, 20), UDim2.fromOffset(0, 0), 12)
	caption.TextXAlignment = Enum.TextXAlignment.Right
	caption.TextColor3 = MUTED
	local buttons, strokes, names, icons = {}, {}, {}, {}
	for index = 1, CAPACITY do
		local button = Instance.new("TextButton")
		button.Name = "Slot" .. index
		button.Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE)
		button.Position = UDim2.fromOffset((index - 1) * (SLOT_SIZE + GAP), 24)
		button.BackgroundColor3 = PANEL
		button.BackgroundTransparency = 0.12
		button.BorderSizePixel = 0
		button.Text = ""
		button.Parent = bar
		corner(button, 7)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Parent = button
		local number = label(button, "Number", UDim2.fromOffset(16, 16), UDim2.fromOffset(5, 3), 11)
		number.Text = tostring(index)
		number.TextColor3 = MUTED
		local name = label(button, "ItemName", UDim2.new(1, -4, 0, 18), UDim2.fromOffset(2, 48), 10)
		buttons[index], strokes[index], names[index] = button, stroke, name
		icons[index] = {
			key = icon(button, "key"),
			energy = icon(button, "energy"),
			trap = icon(button, "trap"),
		}
	end
	local use = Instance.new("TextButton")
	use.Name = "UseItem"
	use.Size = UDim2.fromOffset(176, 38)
	use.AnchorPoint = Vector2.new(1, 1)
	use.Position = UDim2.new(1, 0, 0, -8)
	use.BackgroundColor3 = Color3.fromRGB(65, 109, 73)
	use.BorderSizePixel = 0
	use.Font = Enum.Font.GothamMedium
	use.TextSize = 14
	use.TextColor3 = TEXT
	use.Visible = touch
	use.Parent = bar
	corner(use, 7)
	local energy =
		frame(root, "EnergyTimer", UDim2.fromOffset(174, 82), UDim2.new(0, 20, 1, -124), PANEL)
	energy.AnchorPoint = Vector2.new(0, 1)
	energy.BackgroundTransparency = 1
	energy.Visible = false
	local circle = frame(energy, "Circle", UDim2.fromOffset(76, 76), UDim2.fromOffset(3, 3), PANEL)
	circle.BackgroundTransparency = 0.12
	corner(circle, 38)
	local segments = {}
	for index = 1, SEGMENTS do
		local angle = (index - 1) / SEGMENTS * 2 * math.pi
		local segment = frame(
			circle,
			"Progress" .. index,
			UDim2.fromOffset(3, 8),
			UDim2.fromOffset(38 + math.sin(angle) * 29, 38 - math.cos(angle) * 29),
			GREEN
		)
		segment.AnchorPoint = Vector2.new(0.5, 0.5)
		segment.Rotation = math.deg(angle)
		segments[index] = segment
	end
	local seconds = label(circle, "Seconds", UDim2.fromOffset(48, 32), UDim2.fromOffset(14, 22), 24)
	seconds.Font = Enum.Font.GothamBold
	local boost = label(energy, "Boost", UDim2.fromOffset(90, 28), UDim2.fromOffset(84, 12), 15)
	boost.Text = "Скорость ×2"
	local suffix = label(energy, "Suffix", UDim2.fromOffset(90, 20), UDim2.fromOffset(84, 40), 12)
	suffix.Text = "Энергетик"
	suffix.TextColor3 = MUTED
	local self = setmetatable({
		_root = root,
		_bar = bar,
		_scale = scale,
		_caption = caption,
		_buttons = buttons,
		_strokes = strokes,
		_names = names,
		_icons = icons,
		_use = use,
		_energy = energy,
		_segments = segments,
		_seconds = seconds,
		_boost = boost,
		_suffix = suffix,
		_touch = touch,
		_phase = "ready",
		_inventory = nil,
		_energyUntil = 0,
		_onAction = nil,
		_connections = {} :: { RBXScriptConnection },
	}, InventoryHud)
	for index, button in buttons do
		table.insert(
			self._connections,
			button.Activated:Connect(function()
				if self._phase == "active" and self._onAction then
					self._onAction("select", index)
				end
			end)
		)
	end
	table.insert(
		self._connections,
		use.Activated:Connect(function()
			if self._phase == "active" and self._inventory and self._onAction and use.Active then
				self._onAction("use", self._inventory.selected)
			end
		end)
	)
	table.insert(
		self._connections,
		root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			self:SetViewport(root.AbsoluteSize)
		end)
	)
	self:SetViewport(root.AbsoluteSize)
	return self
end

function InventoryHud:SetOnAction(callback: (string, number) -> ())
	self._onAction = callback
end

function InventoryHud:SetViewport(viewport: Vector2)
	if viewport.X <= 0 or viewport.Y <= 0 then
		return
	end
	self._scale.Scale = math.min(1, math.max(0.6, (viewport.X - 40) / WIDTH))
	local narrow = viewport.X < 840
	self._bar.Position = UDim2.new(1, -20, 1, if narrow then -120 else -20)
	self._energy.Size = UDim2.fromOffset(if narrow then 82 else 174, 82)
	self._energy.Position =
		UDim2.new(0, 20, 1, if viewport.X < 500 then -234 elseif narrow then -120 else -124)
	self._boost.Visible = not narrow
	self._suffix.Visible = not narrow
end

function InventoryHud:Render(inventory: any, phase: string, now: number)
	self._phase = phase
	self._inventory = inventory
	self._energyUntil = now + inventory.energy_remaining
	self._root.Enabled = phase == "active" or phase == "caught"
	local count = 0
	for index = 1, CAPACITY do
		local kind = inventory.slots[index]
		if kind ~= "empty" then
			count += 1
		end
		self._names[index].Text = ITEM_NAMES[kind] or ""
		for iconKind, item in self._icons[index] do
			item.Visible = iconKind == kind
		end
		local selected = inventory.selected == index
		self._strokes[index].Color = if selected then GREEN else MUTED
		self._strokes[index].Transparency = if selected then 0 else 0.65
		self._buttons[index].Active = phase == "active"
		self._buttons[index].AutoButtonColor = phase == "active"
	end
	local selectedKind = inventory.slots[inventory.selected]
	local canUse = selectedKind == "energy" or selectedKind == "trap"
	self._use.Active = phase == "active" and canUse
	self._use.AutoButtonColor = self._use.Active
	self._use.BackgroundTransparency = if self._use.Active then 0 else 0.45
	self._use.Text = if selectedKind == "key"
		then "Ключ · к воротам"
		elseif selectedKind == "energy" then "Выпить"
		elseif selectedKind == "trap" then "Поставить капкан"
		else "Выбери предмет"
	self._caption.Text = string.format(
		"С собой %d/5 · %s",
		count,
		if selectedKind == "key"
			then "ключ для ворот"
			elseif self._touch then "коснись слота"
			else "1–5 · E использовать"
	)
	self:Update(now)
end

function InventoryHud:Update(now: number)
	local remaining = math.max(0, self._energyUntil - now)
	self._energy.Visible = self._phase == "active" and remaining > 0
	if not self._energy.Visible then
		return
	end
	local urgent = remaining <= 5
	local color = if urgent then RED else GREEN
	local blinking = urgent and math.floor(now * 4) % 2 == 1
	self._seconds.Text = tostring(math.ceil(remaining))
	self._seconds.TextColor3 = color
	self._seconds.TextTransparency = if blinking then 0.65 else 0
	self._boost.TextColor3 = color
	for index, segment in self._segments do
		segment.BackgroundColor3 = color
		segment.BackgroundTransparency = if index > math.ceil(remaining / 30 * SEGMENTS)
			then 0.86
			elseif blinking then 0.65
			else 0
	end
end

function InventoryHud:Destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	self._onAction = nil
	self._root:Destroy()
end

return InventoryHud
