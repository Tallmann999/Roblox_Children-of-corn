--!strict
-- Studio authoring panel. All changes are personal to this Play session.
local Panel = {}
Panel.__index = Panel

function Panel.new(parent: PlayerGui, callbacks: any): any
	if parent:FindFirstChild("CornFlashlightTuning") then
		return nil
	end
	local self = setmetatable({ _connections = {}, _open = false, _fields = {} }, Panel)
	local function create(class: string, name: string, owner: Instance, properties: any): any
		local item = Instance.new(class)
		item.Name = name
		for key, value in properties do
			item[key] = value
		end
		item.Parent = owner
		return item
	end
	local gui = create("ScreenGui", "CornFlashlightTuning", parent, {
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 80,
	})
	gui:SetAttribute("CornFlashlightTuningOwned", true)
	self._gui = gui
	local buttonStyle = {
		BackgroundColor3 = Color3.fromRGB(44, 51, 58),
		TextColor3 = Color3.fromRGB(239, 240, 231),
		BorderSizePixel = 0,
		Font = Enum.Font.Gotham,
		TextSize = 14,
	}
	local function button(
		name: string,
		owner: Instance,
		text: string,
		position: UDim2,
		size: UDim2
	): TextButton
		local b = create("TextButton", name, owner, buttonStyle)
		b.Text, b.Position, b.Size = text, position, size
		return b
	end
	local toggle = button(
		"Toggle",
		gui,
		"Настройка фонаря · Alt",
		UDim2.new(1, -300, 0, 390),
		UDim2.fromOffset(280, 34)
	)
	local card = create("Frame", "Panel", gui, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -20, 0.5, 0),
		Size = UDim2.fromOffset(306, 462),
		BackgroundColor3 = Color3.fromRGB(20, 25, 29),
		BorderSizePixel = 0,
		Visible = false,
	})
	local function label(name: string, text: string, y: number, height: number): TextLabel
		return create("TextLabel", name, card, {
			Position = UDim2.fromOffset(12, y),
			Size = UDim2.fromOffset(282, height),
			BackgroundTransparency = 1,
			Text = text,
			TextColor3 = Color3.fromRGB(235, 236, 224),
			Font = Enum.Font.Gotham,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
		})
	end
	label("Title", "ФОНАРЬ · ДВА ПУЧКА ИЗ ЛИНЗЫ", 8, 24)
	label(
		"Hint",
		"Alt — курсор. Свет остаётся виден при настройке.",
		34,
		32
	)
	local rows = {
		{ "wide", "brightness", "Широкий · яркость", 1 },
		{ "wide", "angle", "Широкий · угол", 2 },
		{ "wide", "range", "Широкий · дальность", 1 },
		{ "core", "brightness", "Линза · яркость", 1 },
		{ "core", "angle", "Линза · угол", 2 },
		{ "core", "range", "Линза · дальность", 1 },
		{ "pose", "pitch", "Наклон фонаря", 1 },
	}
	local function refresh()
		local values = callbacks.read()
		for _, field in self._fields do
			field.box.Text = string.format("%.2f", values[field.group][field.key])
		end
	end
	for index, row in rows do
		local group, key, title, step = row[1], row[2], row[3], row[4]
		local y = 70 + (index - 1) * 35
		label(group .. key .. "Label", title, y, 28).Size = UDim2.fromOffset(156, 28)
		local minus = button(
			group .. key .. "Minus",
			card,
			"−",
			UDim2.fromOffset(166, y),
			UDim2.fromOffset(26, 28)
		)
		local box = create("TextBox", group .. key, card, {
			Position = UDim2.fromOffset(196, y),
			Size = UDim2.fromOffset(60, 28),
			BackgroundColor3 = Color3.fromRGB(33, 39, 44),
			TextColor3 = Color3.new(1, 1, 1),
			Font = Enum.Font.Gotham,
			TextSize = 14,
			ClearTextOnFocus = false,
			BorderSizePixel = 0,
		})
		local plus = button(
			group .. key .. "Plus",
			card,
			"+",
			UDim2.fromOffset(260, y),
			UDim2.fromOffset(26, 28)
		)
		table.insert(self._fields, { group = group, key = key, box = box })
		local function set(value: number?)
			if value then
				callbacks.change(group, key, value)
			end
			refresh()
		end
		table.insert(
			self._connections,
			minus.Activated:Connect(function()
				set(callbacks.read()[group][key] - step)
			end)
		)
		table.insert(
			self._connections,
			plus.Activated:Connect(function()
				set(callbacks.read()[group][key] + step)
			end)
		)
		table.insert(
			self._connections,
			box.FocusLost:Connect(function()
				set(tonumber((box.Text:gsub(",", "."))))
			end)
		)
	end
	local reset = button(
		"Reset",
		card,
		"Исходные",
		UDim2.fromOffset(12, 320),
		UDim2.fromOffset(136, 30)
	)
	local close = button(
		"Close",
		card,
		"Закрыть",
		UDim2.fromOffset(158, 320),
		UDim2.fromOffset(136, 30)
	)
	local export = button(
		"ShowValues",
		card,
		"Показать значения для сохранения",
		UDim2.fromOffset(12, 356),
		UDim2.fromOffset(282, 30)
	)
	local values = create("TextBox", "Values", card, {
		Position = UDim2.fromOffset(12, 390),
		Size = UDim2.fromOffset(282, 38),
		BackgroundTransparency = 0.1,
		BackgroundColor3 = Color3.fromRGB(33, 39, 44),
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.Code,
		TextSize = 11,
		ClearTextOnFocus = false,
		TextEditable = false,
		TextWrapped = true,
		Text = "",
		BorderSizePixel = 0,
	})
	label(
		"Session",
		"Настройки действуют в этом Play. Перед Stop сохраните значения.",
		430,
		28
	)
	local function open(value: boolean)
		self._open, card.Visible, toggle.Visible = value, value, not value
		callbacks.open(value)
	end
	table.insert(
		self._connections,
		toggle.Activated:Connect(function()
			open(true)
		end)
	)
	table.insert(
		self._connections,
		close.Activated:Connect(function()
			open(false)
		end)
	)
	table.insert(
		self._connections,
		reset.Activated:Connect(function()
			callbacks.reset()
			refresh()
		end)
	)
	table.insert(
		self._connections,
		export.Activated:Connect(function()
			values.Text = callbacks.export()
			values:CaptureFocus()
		end)
	)
	refresh()
	return self
end

function Panel:IsOpen(): boolean
	return self._open
end

function Panel:Destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	if self._gui.Parent and self._gui:GetAttribute("CornFlashlightTuningOwned") == true then
		self._gui:Destroy()
	end
end

return Panel
