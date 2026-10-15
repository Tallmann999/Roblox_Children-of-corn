-- Imported editor adapted to mode-aware Atmosphere haze. No legacy Fog writes,
-- Atmosphere reparenting, particles, lights, geometry or camera changes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
if not player then
	return
end
local playerGui = player:WaitForChild("PlayerGui")
local bootstrap = script.Parent
if not (bootstrap:IsA("ScreenGui") and bootstrap.Name == "CornfieldFogBootstrap") then
	bootstrap = nil
end

-- Resolve the exact installation before acquiring ownership. ObjectValue targets may
-- arrive after the bootstrap itself, so an initial nil is not an uninstall signal.
local runtime = nil
local binding = bootstrap
	and (bootstrap:FindFirstChild("Runtime") or bootstrap:WaitForChild("Runtime", 10))
if bootstrap then
	if not binding or not binding:IsA("ObjectValue") then
		bootstrap:Destroy()
		return
	end
	local deadline = os.clock() + 10
	while not binding.Value and os.clock() < deadline and bootstrap:IsDescendantOf(playerGui) do
		task.wait(0.05)
	end
	runtime = binding.Value
else
	runtime = ReplicatedStorage:FindFirstChild("CornfieldFogRuntime")
	if not runtime then
		runtime = ReplicatedStorage:WaitForChild("CornfieldFogRuntime", 10)
	end
end
if not runtime or not runtime:IsA("Folder") or not runtime:IsDescendantOf(ReplicatedStorage) then
	if bootstrap then
		bootstrap:Destroy()
	end
	return
end

local OWNER_NAME = "_CornfieldFogClientOwner"
local previousOwner = playerGui:FindFirstChild(OWNER_NAME)
if previousOwner and previousOwner:IsA("ObjectValue") then
	local other = previousOwner.Value
	if other and other ~= script and other:IsDescendantOf(playerGui) then
		local oldBinding = other.Parent and other.Parent:FindFirstChild("Runtime")
		local oldRuntime = oldBinding and oldBinding:IsA("ObjectValue") and oldBinding.Value
		if oldRuntime == runtime then
			return
		end
		-- Give the old controller a synchronous restore opportunity before taking a baseline.
		local stop = previousOwner:FindFirstChild("Stop")
		if stop and stop:IsA("BindableEvent") then
			stop:Fire()
		end
		local deadline = os.clock() + 2
		while previousOwner.Parent and os.clock() < deadline do
			task.wait()
		end
		if previousOwner.Parent then
			return
		end
	else
		previousOwner:Destroy()
	end
end
local owner = Instance.new("ObjectValue")
owner.Name = OWNER_NAME
owner.Value = script
owner.Parent = playerGui

local connections = {}
local uiConnections = {}
local atmosphereConnections = {}
local dead = false
local gui, controls, drag, refreshUI
local panelOpen = false
local pendingMessage, pendingSerial = nil, 0
local atmosphere, baseline, lastOwn = nil, {}, {}
local createdAtmosphere, foreignCreatedEdit = false, false
local removingCharacter = false
local applying, bindingDirty, bindingBusy = false, true, false
local lastTarget, targetAge, pollElapsed = nil, 0, 0
local PROPERTIES = { "Density", "Haze", "Offset", "Color", "Decay", "Glare" }
local PROJECT = "children_of_corn"
local UPDATE = 0.1
local function connect(bucket, signal, callback)
	local connection = signal:Connect(callback)
	table.insert(bucket, connection)
	return connection
end
local function disconnect(bucket)
	for _, connection in bucket do
		connection:Disconnect()
	end
	table.clear(bucket)
end
local function finite(value, fallback)
	if typeof(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return fallback
	end
	return value
end
local function valuesClose(a, b)
	if typeof(a) == "Color3" and typeof(b) == "Color3" then
		return math.abs(a.R - b.R) < 0.00001
			and math.abs(a.G - b.G) < 0.00001
			and math.abs(a.B - b.B) < 0.00001
	end
	return typeof(a) == "number" and typeof(b) == "number" and math.abs(a - b) < 0.00001
end
local function createdOwned(effect)
	return effect
		and effect:GetAttribute("CornfieldFogAtmosphereOwned") == true
		and effect:GetAttribute("corn_project_id") == PROJECT
		and effect:GetAttribute("CornfieldFogVersion") == 2
end
local function releaseAtmosphere()
	disconnect(atmosphereConnections)
	local effect = atmosphere
	atmosphere = nil
	if effect and effect.Parent == Lighting then
		applying = true
		for _, property in PROPERTIES do
			if lastOwn[property] ~= nil and effect[property] == lastOwn[property] then
				effect[property] = baseline[property]
			end
		end
		applying = false
		if createdAtmosphere and createdOwned(effect) then
			-- A user who edited our transient effect owns the resulting baseline. Keep
			-- that object/its children instead of deleting someone else's later work.
			if not foreignCreatedEdit and #effect:GetChildren() == 0 then
				effect:Destroy()
			else
				effect:SetAttribute("CornfieldFogAtmosphereOwned", nil)
				effect:SetAttribute("corn_project_id", nil)
				effect:SetAttribute("CornfieldFogVersion", nil)
			end
		end
	end
	baseline, lastOwn, lastTarget = {}, {}, nil
	createdAtmosphere, foreignCreatedEdit, targetAge = false, false, 0
end
local function destroyUI()
	drag, controls = nil, nil
	disconnect(uiConnections)
	if gui then
		gui:Destroy()
		gui = nil
	end
end
local function cleanup()
	if dead then
		return
	end
	dead = true
	script:SetAttribute("CornfieldFogStopped", true)
	releaseAtmosphere()
	disconnect(connections)
	destroyUI()
	if owner.Parent and owner.Value == script then
		owner:Destroy()
	end
	if bootstrap then
		local previous = bootstrap
		task.defer(function()
			if previous.Parent then
				previous:Destroy()
			end
		end)
	end
end
local stop = Instance.new("BindableEvent")
stop.Name, stop.Parent = "Stop", owner
connect(connections, stop.Event, cleanup)
connect(connections, script.Destroying, cleanup)
connect(connections, script.AncestryChanged, function()
	if not script:IsDescendantOf(playerGui) then
		cleanup()
	end
end)
if bootstrap then
	connect(connections, bootstrap.Destroying, cleanup)
end
connect(connections, runtime.Destroying, cleanup)
connect(connections, runtime.AncestryChanged, function()
	if not runtime:IsDescendantOf(ReplicatedStorage) then
		cleanup()
	end
end)
local rootBinding = runtime:FindFirstChild("Owner")
if rootBinding and rootBinding:IsA("ObjectValue") then
	local watched = {}
	local function watchOwner()
		local root = rootBinding.Value
		if not root or watched[root] then
			return
		end
		watched[root] = true
		local wasInGame = root:IsDescendantOf(game)
		connect(connections, root.AncestryChanged, function()
			if root:IsDescendantOf(game) then
				wasInGame = true
			elseif wasInGame then
				cleanup()
			end
		end)
	end
	connect(connections, rootBinding:GetPropertyChangedSignal("Value"), watchOwner)
	watchOwner()
end
local function readState()
	local color, center, size =
		runtime:GetAttribute("FogColor"),
		runtime:GetAttribute("FieldCenter"),
		runtime:GetAttribute("FieldSize")
	local minimum = math.max(1, math.floor(finite(runtime:GetAttribute("MinSteps"), 10) + 0.5))
	local maximum =
		math.max(minimum, math.floor(finite(runtime:GetAttribute("MaxSteps"), 120) + 0.5))
	return {
		Enabled = runtime:GetAttribute("Enabled") ~= false,
		Steps = math.clamp(finite(runtime:GetAttribute("Steps"), 20), minimum, maximum),
		MinSteps = minimum,
		MaxSteps = maximum,
		StartRatio = math.clamp(finite(runtime:GetAttribute("StartRatio"), 0.2), 0, 0.8),
		FogColor = typeof(color) == "Color3" and color or Color3.fromRGB(177, 184, 158),
		Preset = runtime:GetAttribute("Preset") or "Auto",
		HazeDay = math.clamp(finite(runtime:GetAttribute("HazeDay"), 0.5), 0, 2),
		HazeDusk = math.clamp(finite(runtime:GetAttribute("HazeDusk"), 0.85), 0, 2),
		HazeNight = math.clamp(finite(runtime:GetAttribute("HazeNight"), 1), 0, 2),
		MaxDensity = math.clamp(finite(runtime:GetAttribute("MaxDensity"), 0.36), 0, 0.5),
		MaxHaze = math.clamp(finite(runtime:GetAttribute("MaxHaze"), 2.8), 0, 3),
		FieldOnly = runtime:GetAttribute("FieldOnly") == true,
		FieldCenter = typeof(center) == "Vector3" and center or Vector3.zero,
		FieldSize = typeof(size) == "Vector3" and size or Vector3.new(840, 300, 840),
		EdgeFadeStuds = math.max(0, finite(runtime:GetAttribute("EdgeFadeStuds"), 30)),
	}
end
local state = readState()
local function canEdit()
	return player:GetAttribute("CornfieldFogCanEdit") == true
end
local function send(patch)
	if dead or not canEdit() then
		return
	end
	local remote = runtime:FindFirstChild("Control")
	if not remote or not remote:IsA("RemoteEvent") then
		pendingMessage = "Нет связи с сервером"
		if refreshUI then
			refreshUI()
		end
		return
	end
	pendingMessage = "Применяется на сервере…"
	pendingSerial += 1
	local serial = pendingSerial
	local ok = pcall(function()
		remote:FireServer(patch)
	end)
	if not ok then
		pendingMessage = "Нет связи с сервером"
	end
	if refreshUI then
		refreshUI()
	end
	task.delay(2, function()
		if not dead and pendingSerial == serial then
			pendingMessage = nil
			if refreshUI then
				refreshUI()
			end
		end
	end)
end
local function regionWeight()
	if not state.FieldOnly then
		return 1
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	local position = root and root:IsA("BasePart") and root.Position
		or camera and camera.CFrame.Position
	if not position then
		return 0
	end
	local dx, dz =
		math.abs(position.X - state.FieldCenter.X), math.abs(position.Z - state.FieldCenter.Z)
	local margin =
		math.min(math.abs(state.FieldSize.X) * 0.5 - dx, math.abs(state.FieldSize.Z) * 0.5 - dz)
	if margin <= 0 then
		return 0
	end
	return if state.EdgeFadeStuds <= 0 then 1 else math.clamp(margin / state.EdgeFadeStuds, 0, 1)
end
local function neutralProfile(clock)
	local night, dusk = clock >= 19.5 or clock < 6, clock >= 16.5 and clock < 19.5
	return {
		Density = if night then 0.27 elseif dusk then 0.18 else 0.08,
		Haze = if night then 0.8 elseif dusk then 0.4 else 0,
		Offset = 0.25,
		Glare = 0,
		Color = if night
			then Color3.fromRGB(95, 110, 130)
			elseif dusk then Color3.fromRGB(185, 176, 167)
			else Color3.fromRGB(199, 216, 229),
		Decay = if night
			then Color3.fromRGB(32, 41, 56)
			elseif dusk then Color3.fromRGB(98, 77, 107)
			else Color3.fromRGB(153, 168, 183),
	}
end
local function bindAtmosphere()
	if not bindingDirty or bindingBusy then
		return
	end
	bindingBusy = true
	local effects = {}
	for _, effect in Lighting:GetChildren() do
		if effect:IsA("Atmosphere") then
			table.insert(effects, effect)
		end
	end
	-- A later real Atmosphere replaces our optional transient, without moving it.
	if #effects > 1 and atmosphere and createdAtmosphere then
		releaseAtmosphere()
		effects = {}
		for _, effect in Lighting:GetChildren() do
			if effect:IsA("Atmosphere") then
				table.insert(effects, effect)
			end
		end
	end
	if #effects > 1 then
		releaseAtmosphere()
		pendingMessage = "Несколько Atmosphere: дымка приостановлена"
		if refreshUI then
			refreshUI()
		end
	elseif #effects == 0 then
		releaseAtmosphere()
		local effect = Instance.new("Atmosphere")
		effect.Name = "CornfieldFogAtmosphere"
		effect:SetAttribute("CornfieldFogAtmosphereOwned", true)
		effect:SetAttribute("corn_project_id", PROJECT)
		effect:SetAttribute("CornfieldFogVersion", 2)
		-- No pre-existing Atmosphere: inherit the current mode's neutral baseline.
		for property, value in neutralProfile(Lighting.ClockTime) do
			effect[property] = value
		end
		effect.Parent = Lighting
		atmosphere, createdAtmosphere = effect, true
	elseif effects[1] ~= atmosphere then
		releaseAtmosphere()
		atmosphere = effects[1]
	end
	if atmosphere and next(baseline) == nil then
		local effect = atmosphere
		for _, property in PROPERTIES do
			baseline[property] = effect[property]
			connect(atmosphereConnections, effect:GetPropertyChangedSignal(property), function()
				if applying or effect ~= atmosphere or effect.Parent ~= Lighting then
					return
				end
				local value = effect[property]
				if lastOwn[property] ~= nil and value == lastOwn[property] then
					return
				end
				baseline[property], lastOwn[property], lastTarget = value, nil, nil
				if createdAtmosphere then
					foreignCreatedEdit = true
				end
			end)
		end
		connect(atmosphereConnections, effect.AncestryChanged, function()
			if effect.Parent ~= Lighting then
				-- A reparented effect no longer belongs to this renderer; never move it.
				releaseAtmosphere()
				bindingDirty = true
			end
		end)
	end
	bindingDirty, bindingBusy = false, false
end
for _, signal in { Lighting.ChildAdded, Lighting.ChildRemoved } do
	connect(connections, signal, function(item)
		if item:IsA("Atmosphere") then
			bindingDirty = true
		end
	end)
end
connect(connections, Lighting:GetPropertyChangedSignal("ClockTime"), function()
	if createdAtmosphere and not foreignCreatedEdit then
		baseline = neutralProfile(Lighting.ClockTime)
	end
	lastTarget = nil
end)
connect(connections, player.CharacterRemoving, function()
	removingCharacter = true
	releaseAtmosphere()
	bindingDirty = true
end)
connect(connections, player.CharacterAdded, function()
	removingCharacter = false
	bindingDirty = true
end)
local function targets(weight)
	local target = {}
	for _, property in PROPERTIES do
		target[property] = baseline[property]
	end
	local clock = Lighting.ClockTime
	local boost = if clock >= 19.5 or clock < 6
		then state.HazeNight
		elseif clock >= 16.5 then state.HazeDusk
		else state.HazeDay
	local power = math.clamp(state.Steps / 20, 0.25, 3)
	target.Haze = baseline.Haze
		+ (math.clamp(baseline.Haze + boost * power, 0, state.MaxHaze) - baseline.Haze) * weight
	target.Density = baseline.Density
		+ (
				math.clamp(baseline.Density + (power - 1) * 0.035, 0, state.MaxDensity)
				- baseline.Density
			)
			* weight
	if state.Preset ~= "Auto" then
		target.Color = baseline.Color:Lerp(state.FogColor, state.StartRatio * weight)
	end
	return target
end
local function renderHaze(deltaTime)
	if dead then
		return
	end
	if not runtime:IsDescendantOf(ReplicatedStorage) then
		cleanup()
		return
	end
	pollElapsed += math.max(0, finite(deltaTime, 0))
	if pollElapsed + 0.000001 < UPDATE then
		return
	end
	local dt = math.min(pollElapsed, 0.2)
	pollElapsed = 0
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local wanted = state.Enabled
		and not removingCharacter
		and root
		and root:IsA("BasePart")
		and (not humanoid or humanoid.Health > 0)
	local weight = if wanted then regionWeight() else 0
	if weight > 0 then
		bindAtmosphere()
	elseif not atmosphere then
		return
	end
	if not atmosphere or atmosphere.Parent ~= Lighting then
		return
	end
	local target = targets(weight)
	local changed = not lastTarget
	if lastTarget then
		for _, property in PROPERTIES do
			if not valuesClose(target[property], lastTarget[property]) then
				changed = true
				break
			end
		end
	end
	if changed then
		targetAge = 0
	else
		targetAge += dt
	end
	lastTarget = target
	local alpha = if targetAge >= 0.6 then 1 else 1 - math.exp(-dt / 0.14)
	local settled = true
	for _, property in PROPERTIES do
		local value = atmosphere[property]
		local goal = target[property]
		if not valuesClose(value, goal) then
			settled = false
			local nextValue = if typeof(value) == "Color3"
				then value:Lerp(goal, alpha)
				else value + (goal - value) * alpha
			applying = true
			lastOwn[property] = nextValue
			atmosphere[property] = nextValue
			lastOwn[property] = atmosphere[property]
			applying = false
		end
	end
	if weight == 0 and settled then
		releaseAtmosphere()
		bindingDirty = true
	end
end
connect(connections, RunService.RenderStepped, renderHaze)
local COLORS = {
	background = Color3.fromRGB(25, 30, 37),
	card = Color3.fromRGB(42, 49, 59),
	text = Color3.fromRGB(244, 247, 250),
	muted = Color3.fromRGB(174, 186, 199),
	accent = Color3.fromRGB(75, 154, 126),
}
local function create(className, properties, parent)
	local object = Instance.new(className)
	for key, value in properties do
		object[key] = value
	end
	object.Parent = parent
	return object
end
local function rounded(object, radius)
	create("UICorner", { CornerRadius = UDim.new(0, radius or 8) }, object)
end
local function text(parent, value, position, size, fontSize)
	return create("TextLabel", {
		BackgroundTransparency = 1,
		Text = value,
		TextColor3 = COLORS.text,
		Font = Enum.Font.Gotham,
		TextSize = fontSize or 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = position,
		Size = size,
	}, parent)
end
local function button(parent, value, position, size)
	local object = create("TextButton", {
		BackgroundColor3 = COLORS.card,
		BorderSizePixel = 0,
		Text = value,
		TextColor3 = COLORS.text,
		Font = Enum.Font.GothamMedium,
		TextSize = 16,
		AutoButtonColor = true,
		Position = position,
		Size = size,
	}, parent)
	rounded(object)
	return object
end
local function input(parent, position, size)
	local object = create("TextBox", {
		BackgroundColor3 = COLORS.card,
		BorderSizePixel = 0,
		Text = "",
		TextColor3 = COLORS.text,
		PlaceholderColor3 = COLORS.muted,
		Font = Enum.Font.GothamMedium,
		TextSize = 19,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = position,
		Size = size,
	}, parent)
	rounded(object)
	return object
end
local function parseNumber(value)
	return tonumber((value:gsub("%%", ""):gsub("%s", ""):gsub(",", ".")))
end
local function setPanel(open)
	panelOpen = open
	if controls then
		controls.panel.Visible = open
	end
end
local function buildUI()
	if dead or gui or not canEdit() then
		return
	end
	gui = create("ScreenGui", {
		Name = "CornfieldFogControls",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
		ClipToDeviceSafeArea = false,
		DisplayOrder = 80,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	local screen =
		create("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, gui)
	local opener = button(
		screen,
		UserInputService.TouchEnabled and "Дымка" or "Дымка · F6",
		UDim2.new(1, -20, 0, 16),
		UDim2.fromOffset(140, 40)
	)
	opener.AnchorPoint = Vector2.new(1, 0)
	local panel = create("Frame", {
		Name = "Panel",
		BackgroundColor3 = COLORS.background,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 64),
		Size = UDim2.fromOffset(360, 500),
		Visible = panelOpen,
	}, screen)
	rounded(panel, 12)
	text(panel, "Дымка поля", UDim2.fromOffset(16, 9), UDim2.new(1, -78, 0, 38), 21)
	local close = button(panel, "×", UDim2.new(1, -54, 0, 6), UDim2.fromOffset(44, 44))
	-- The visible panel releases Roblox's first-person mouse lock. Hiding or
	-- destroying its ancestor automatically relinquishes that modal ownership.
	close.Modal = true
	local body = create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(14, 56),
		Size = UDim2.new(1, -28, 1, -66),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = COLORS.muted,
	}, panel)
	create(
		"UIListLayout",
		{ Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder },
		body
	)
	local order = 0
	local function block(height)
		order += 1
		return create(
			"Frame",
			{ BackgroundTransparency = 1, Size = UDim2.new(1, -6, 0, height), LayoutOrder = order },
			body
		)
	end
	local intro = block(32)
	local status = text(intro, "", UDim2.new(), UDim2.fromScale(1, 1), 14)
	status.TextColor3 = COLORS.muted
	status.TextWrapped = true
	local stepBlock = block(104)
	text(stepBlock, "Интенсивность дымки", UDim2.new(), UDim2.new(1, 0, 0, 24))
	local minus = button(stepBlock, "−5", UDim2.fromOffset(0, 32), UDim2.new(0.25, -5, 0, 48))
	local stepBox = input(stepBlock, UDim2.new(0.25, 5, 0, 32), UDim2.new(0.5, -10, 0, 48))
	local plus = button(stepBlock, "+5", UDim2.new(0.75, 5, 0, 32), UDim2.new(0.25, -5, 0, 48))
	local distanceText = text(stepBlock, "", UDim2.fromOffset(0, 84), UDim2.new(1, 0, 0, 20), 13)
	distanceText.TextColor3 = COLORS.muted
	local sliderBlock = block(58)
	local sliderArea = button(sliderBlock, "", UDim2.new(), UDim2.new(1, 0, 0, 40))
	sliderArea.BackgroundTransparency = 1
	local track = create("Frame", {
		BackgroundColor3 = COLORS.card,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 10, 0.5, -4),
		Size = UDim2.new(1, -20, 0, 8),
	}, sliderArea)
	rounded(track, 4)
	local fill = create(
		"Frame",
		{ BackgroundColor3 = COLORS.accent, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1) },
		track
	)
	rounded(fill, 4)
	local thumb = create("Frame", {
		BackgroundColor3 = COLORS.text,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(22, 22),
	}, track)
	rounded(thumb, 11)
	local minimum = text(sliderBlock, "", UDim2.fromOffset(0, 38), UDim2.new(0.5, 0, 0, 20), 13)
	minimum.TextColor3 = COLORS.muted
	local maximum = text(sliderBlock, "", UDim2.new(0.5, 0, 0, 38), UDim2.new(0.5, 0, 0, 20), 13)
	maximum.TextXAlignment = Enum.TextXAlignment.Right
	maximum.TextColor3 = COLORS.muted
	local ratioBlock = block(80)
	text(ratioBlock, "Сила оттенка, %", UDim2.new(), UDim2.new(1, -100, 0, 42))
	local ratioBox = input(ratioBlock, UDim2.new(1, -88, 0, 0), UDim2.fromOffset(88, 44))
	local startText = text(ratioBlock, "", UDim2.fromOffset(0, 48), UDim2.new(1, 0, 0, 28), 13)
	startText.TextColor3 = COLORS.muted
	startText.TextWrapped = true
	local presetBlock = block(78)
	text(
		presetBlock,
		"Оттенок · режим сохраняется",
		UDim2.new(),
		UDim2.new(1, 0, 0, 24)
	)
	local presets = {}
	for i, preset in
		{
			{ "Auto", "Режим" },
			{ "Field", "Поле" },
			{ "Dawn", "Тёплый" },
			{ "Night", "Ночной" },
		}
	do
		local item = button(
			presetBlock,
			preset[2],
			UDim2.new((i - 1) / 4, i > 1 and 3 or 0, 0, 31),
			UDim2.new(1 / 4, -6, 0, 44)
		)
		presets[preset[1]] = item
		connect(uiConnections, item.Activated, function()
			send({ Preset = preset[1] })
		end)
	end
	local toggleBlock = block(48)
	local toggle = button(toggleBlock, "", UDim2.new(), UDim2.fromScale(1, 1))
	local resetBlock = block(44)
	local reset = button(
		resetBlock,
		"Сбросить настройки",
		UDim2.new(),
		UDim2.fromScale(1, 1)
	)
	local footerBlock = block(38)
	local footer = text(
		footerBlock,
		"Визуальные настройки текущего запуска.",
		UDim2.new(),
		UDim2.fromScale(1, 1),
		12
	)
	footer.TextColor3 = COLORS.muted
	footer.TextWrapped = true
	controls = {
		panel = panel,
		status = status,
		stepBox = stepBox,
		ratioBox = ratioBox,
		distanceText = distanceText,
		startText = startText,
		fill = fill,
		thumb = thumb,
		presets = presets,
		toggle = toggle,
		minimum = minimum,
		maximum = maximum,
	}
	local function resize()
		local size = screen.AbsoluteSize
		panel.Size = UDim2.fromOffset(
			math.max(220, math.min(360, size.X - 28)),
			math.max(180, math.min(540, size.Y - 84))
		)
	end
	connect(uiConnections, screen:GetPropertyChangedSignal("AbsoluteSize"), resize)
	resize()
	connect(uiConnections, opener.Activated, function()
		setPanel(not panelOpen)
	end)
	connect(uiConnections, close.Activated, function()
		setPanel(false)
	end)
	connect(uiConnections, minus.Activated, function()
		send({
			Steps = math.clamp(math.floor(state.Steps + 0.5) - 5, state.MinSteps, state.MaxSteps),
		})
	end)
	connect(uiConnections, plus.Activated, function()
		send({
			Steps = math.clamp(math.floor(state.Steps + 0.5) + 5, state.MinSteps, state.MaxSteps),
		})
	end)
	connect(uiConnections, toggle.Activated, function()
		send({ Enabled = not state.Enabled })
	end)
	connect(uiConnections, reset.Activated, function()
		send({ Reset = true })
	end)
	connect(uiConnections, stepBox.FocusLost, function()
		local value = parseNumber(stepBox.Text)
		if value and value == value then
			value = math.clamp(math.floor(value + 0.5), state.MinSteps, state.MaxSteps)
			if value ~= state.Steps then
				send({ Steps = value })
			end
		end
		refreshUI()
	end)
	connect(uiConnections, ratioBox.FocusLost, function()
		local value = parseNumber(ratioBox.Text)
		if value and value == value then
			value = math.clamp(value / 100, 0, 0.8)
			if math.abs(value - state.StartRatio) > 0.0001 then
				send({ StartRatio = value })
			end
		end
		refreshUI()
	end)
	local function previewAt(x)
		if not drag or not controls then
			return
		end
		local fraction =
			math.clamp((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
		drag.steps = math.floor(state.MinSteps + fraction * (state.MaxSteps - state.MinSteps) + 0.5)
		refreshUI()
	end
	connect(uiConnections, sliderArea.InputBegan, function(inputObject)
		if drag then
			return
		end
		if
			inputObject.UserInputType ~= Enum.UserInputType.MouseButton1
			and inputObject.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		drag = {
			input = inputObject,
			touch = inputObject.UserInputType == Enum.UserInputType.Touch,
			steps = state.Steps,
		}
		previewAt(inputObject.Position.X)
	end)
	connect(uiConnections, UserInputService.InputChanged, function(inputObject)
		if not drag then
			return
		end
		if
			(drag.touch and inputObject == drag.input)
			or (not drag.touch and inputObject.UserInputType == Enum.UserInputType.MouseMovement)
		then
			previewAt(inputObject.Position.X)
		end
	end)
	connect(uiConnections, UserInputService.InputEnded, function(inputObject)
		if not drag then
			return
		end
		if
			inputObject == drag.input
			or (not drag.touch and inputObject.UserInputType == Enum.UserInputType.MouseButton1)
		then
			local value = drag.steps
			drag = nil
			if value ~= state.Steps then
				send({ Steps = value })
			end
			refreshUI()
		end
	end)
	refreshUI()
end

refreshUI = function()
	if not controls then
		return
	end
	local shownSteps = drag and drag.steps or state.Steps
	local fraction = math.clamp(
		(shownSteps - state.MinSteps) / math.max(1, state.MaxSteps - state.MinSteps),
		0,
		1
	)
	controls.fill.Size = UDim2.fromScale(fraction, 1)
	controls.thumb.Position = UDim2.fromScale(fraction, 0.5)
	if not controls.stepBox:IsFocused() then
		controls.stepBox.Text = tostring(math.floor(shownSteps + 0.5))
	end
	if not controls.ratioBox:IsFocused() then
		controls.ratioBox.Text = string.format("%.0f", state.StartRatio * 100)
	end
	controls.distanceText.Text = "Без жёсткой границы видимости"
	controls.startText.Text = "0–80% · только выбранный оттенок"
	controls.minimum.Text = tostring(state.MinSteps)
	controls.maximum.Text = tostring(state.MaxSteps)
	controls.status.Text = pendingMessage
		or (
			state.FieldOnly
				and "Дымка плавно ослабевает у края поля."
			or "Мягкая дымка текущего режима освещения."
		)
	controls.toggle.Text = state.Enabled and "Дымка: включена"
		or "Дымка: выключена"
	controls.toggle.BackgroundColor3 = state.Enabled and COLORS.accent or COLORS.card
	for name, item in controls.presets do
		item.BackgroundColor3 = state.Preset == name and COLORS.accent or COLORS.card
	end
end
connect(connections, runtime.AttributeChanged, function()
	if dead then
		return
	end
	state = readState()
	pendingMessage = nil
	refreshUI()
end)
connect(connections, player:GetAttributeChangedSignal("CornfieldFogCanEdit"), function()
	if canEdit() then
		buildUI()
	else
		destroyUI()
	end
end)
connect(connections, UserInputService.InputBegan, function(inputObject, processed)
	if processed or not canEdit() or UserInputService:GetFocusedTextBox() then
		return
	end
	if inputObject.KeyCode == Enum.KeyCode.F6 then
		setPanel(not panelOpen)
	end
end)
if canEdit() then
	buildUI()
end
