-- Local B authoring control, appended to the existing F6 haze panel.
-- Only these seven Lighting properties are overlaid; haze keeps its own lifecycle.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local PROJECT = "children_of_corn"
local BLOCK = "BNightModeBlock"
local PROFILE = {
	ClockTime = 0,
	Brightness = 1,
	Ambient = Color3.fromRGB(18, 22, 30),
	OutdoorAmbient = Color3.fromRGB(38, 42, 53),
	EnvironmentDiffuseScale = 1,
	EnvironmentSpecularScale = 1,
	GlobalShadows = true,
}
local Controller = { Name = "NightModeController", Order = 90 }

local function disconnect(bucket)
	for _, connection in bucket do
		connection:Disconnect()
	end
	table.clear(bucket)
end

local function unique(parent, name, class)
	local found = nil
	for _, child in parent:GetChildren() do
		if child.Name == name then
			if found or not child:IsA(class) then
				return nil
			end
			found = child
		end
	end
	return found
end

function Controller:_connect(bucket, signal, callback)
	table.insert(bucket, signal:Connect(callback))
end

function Controller:_target()
	local map = unique(Workspace, "CornMap", "Model")
	local field = map and unique(map, "FieldZone", "BasePart")
	if
		map
		and map:GetAttribute("corn_project_id") == PROJECT
		and map:GetAttribute("HarvestArtVariant") == "B"
		and field
		and field.Size == Vector3.new(630, 10, 630)
		and not Workspace:FindFirstChild("Asmr_Base")
		and not Workspace:FindFirstChild("ASMR_Models")
	then
		return map
	end
	return nil
end

function Controller:_bodyForPanel()
	if not self._player or self._player:GetAttribute("CornfieldFogCanEdit") ~= true then
		return nil
	end
	local gui = unique(self._playerGui, "CornfieldFogControls", "ScreenGui")
	if not gui then
		return nil
	end
	local panel = nil
	for _, item in gui:GetDescendants() do
		if item.Name == "Panel" and item:IsA("Frame") then
			if panel then
				return nil
			end
			panel = item
		end
	end
	local body = nil
	for _, item in if panel then panel:GetChildren() else {} do
		if item:IsA("ScrollingFrame") then
			if body then
				return nil
			end
			body = item
		end
	end
	return body
end

function Controller:_refreshText()
	if self._button then
		self._button.Text = if self._ordinary
			then "Ночь: обычная · 00:00"
			else "Ночь: абсолютная"
		self._button.BackgroundColor3 = if self._ordinary
			then Color3.fromRGB(75, 154, 126)
			else Color3.fromRGB(42, 49, 59)
		self._hint.Text = if self._ordinary
			then "Нажми, чтобы вернуть абсолютную ночь."
			else "Нажми для обычной тёмной ночи в 00:00."
	end
end

function Controller:_restore()
	self._ordinary = false
	self._epoch += 1
	self._applyQueued = nil
	disconnect(self._lightingConnections)
	for property, value in self._baseline do
		-- A foreign write that has not delivered its event yet still wins on exit.
		if Lighting[property] == self._lastOwn[property] and Lighting[property] ~= value then
			Lighting[property] = value
		end
	end
	table.clear(self._baseline)
	table.clear(self._lastOwn)
	self:_refreshText()
end

function Controller:_detach()
	self:_restore()
	disconnect(self._uiConnections)
	local block = self._block
	self._block, self._body, self._button, self._hint = nil, nil, nil, nil
	if block then
		block:Destroy()
	end
end

function Controller:_bindingValid()
	return self:_target() ~= nil
		and self._body ~= nil
		and self:_bodyForPanel() == self._body
		and self._block ~= nil
		and self._block.Parent == self._body
		and self._button.Parent == self._block
		and self._hint.Parent == self._block
end

function Controller:_apply()
	if not self._ordinary then
		return
	end
	if not self:_bindingValid() then
		self:_detach()
		return
	end
	for property, value in PROFILE do
		local actual = Lighting[property]
		if self._lastOwn[property] ~= nil and actual ~= self._lastOwn[property] then
			self._baseline[property] = actual
		end
		-- Property signals can be deferred; this value identifies our own write.
		self._lastOwn[property] = value
		if actual ~= value then
			Lighting[property] = value
		end
	end
end

function Controller:SetOrdinary(enabled)
	if not enabled then
		self:_restore()
		return
	end
	if self._ordinary or not self:_bindingValid() then
		return
	end
	for property in PROFILE do
		self._baseline[property] = Lighting[property]
	end
	self._ordinary = true
	for property in PROFILE do
		self:_connect(
			self._lightingConnections,
			Lighting:GetPropertyChangedSignal(property),
			function()
				if not self._ordinary then
					return
				end
				local actual = Lighting[property]
				if actual == self._lastOwn[property] then
					return
				end
				self._baseline[property] = actual
				if self._applyQueued == self._epoch then
					return
				end
				local epoch = self._epoch
				self._applyQueued = epoch
				task.defer(function()
					if self._applyQueued == epoch then
						self._applyQueued = nil
					end
					if self._ordinary and self._epoch == epoch then
						self:_apply()
					end
				end)
			end
		)
	end
	self:_apply()
	self:_refreshText()
end

function Controller:_attach(body)
	if body:FindFirstChild(BLOCK) then
		return
	end
	local block = Instance.new("Frame")
	block.Name = BLOCK
	block.BackgroundTransparency = 1
	block.Size = UDim2.new(1, -6, 0, 76)
	block.LayoutOrder = 0
	local button = Instance.new("TextButton")
	button.Name = "ToggleNight"
	button.BorderSizePixel = 0
	button.Size = UDim2.new(1, 0, 0, 40)
	button.Font = Enum.Font.GothamMedium
	button.TextSize = 16
	button.TextColor3 = Color3.fromRGB(244, 247, 250)
	button.AutoButtonColor = true
	button.Parent = block
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button
	local hint = Instance.new("TextLabel")
	hint.Name = "NextNightMode"
	hint.BackgroundTransparency = 1
	hint.Position = UDim2.fromOffset(0, 44)
	hint.Size = UDim2.new(1, 0, 0, 32)
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 13
	hint.TextWrapped = true
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextColor3 = Color3.fromRGB(174, 186, 199)
	hint.Parent = block
	self._body, self._block, self._button, self._hint = body, block, button, hint
	self:_refreshText()
	self:_connect(self._uiConnections, button.Activated, function()
		self:SetOrdinary(not self._ordinary)
	end)
	self:_connect(self._uiConnections, block.AncestryChanged, function()
		self:_queueRefresh()
	end)
	self:_connect(self._uiConnections, button.AncestryChanged, function()
		self:_queueRefresh()
	end)
	block.Parent = body
end

function Controller:_queueRefresh()
	if self._refreshQueued or not self._started then
		return
	end
	self._refreshQueued = true
	task.defer(function()
		self._refreshQueued = false
		if self._started then
			self:_refresh()
		end
	end)
end

function Controller:_refresh()
	local map = unique(Workspace, "CornMap", "Model")
	local field = map and unique(map, "FieldZone", "BasePart")
	if map ~= self._watchedMap or field ~= self._watchedField then
		disconnect(self._mapConnections)
		self._watchedMap, self._watchedField = map, field
		if map then
			for _, signal in
				{
					map.AttributeChanged,
					map.ChildAdded,
					map.ChildRemoved,
					map:GetPropertyChangedSignal("Name"),
				}
			do
				self:_connect(self._mapConnections, signal, function()
					self:_queueRefresh()
				end)
			end
		end
		if field then
			self:_connect(self._mapConnections, field:GetPropertyChangedSignal("Size"), function()
				self:_queueRefresh()
			end)
		end
	end
	local body = self:_target() and self:_bodyForPanel() or nil
	if self._body and (body ~= self._body or not self:_bindingValid()) then
		self:_detach()
	end
	if body and not self._body then
		self:_attach(body)
	end
end

function Controller:Init(context)
	self._config = context.Config
	self._connections, self._mapConnections, self._uiConnections, self._lightingConnections =
		{}, {}, {}, {}
	self._baseline, self._lastOwn = {}, {}
	self._epoch, self._ordinary = 0, false
	self._started, self._refreshQueued, self._applyQueued = false, false, nil
end

function Controller:Start()
	local config = self._config
	if
		self._started
		or not RunService:IsStudio()
		or not RunService:IsClient()
		or config.Environment ~= "DEV"
		or (config.Game.SessionMode ~= "solo_local" and config.Game.SessionMode ~= "team_local")
	then
		return
	end
	self._player = Players.LocalPlayer
	self._playerGui = self._player and self._player:FindFirstChild("PlayerGui")
	if not self._playerGui or not self._playerGui:IsA("PlayerGui") then
		return
	end
	self._started = true
	for _, signal in
		{
			Workspace.ChildAdded,
			Workspace.ChildRemoved,
			self._playerGui.DescendantAdded,
			self._playerGui.DescendantRemoving,
			self._player:GetAttributeChangedSignal("CornfieldFogCanEdit"),
		}
	do
		self:_connect(self._connections, signal, function()
			self:_queueRefresh()
		end)
	end
	self:_refresh()
end

function Controller:Stop()
	self._started = false
	self:_detach()
	disconnect(self._connections)
	disconnect(self._mapConnections)
	self._watchedMap, self._watchedField = nil, nil
end

function Controller:Destroy()
	self:Stop()
end

return Controller
