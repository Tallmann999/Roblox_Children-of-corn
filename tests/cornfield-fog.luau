-- Execute the audited portable model's actual Sources against bounded event/UI
-- adapters. This checks ownership/state/validation, not engine haze or rendering.
local fs = require("@lune/fs")
local r = require("@lune/roblox")
local V3, C3, CF = r.Vector3, r.Color3, r.CFrame
local folder = "assets/CornfieldFog/"
local clientSource = fs.readFile(folder .. "ClientTemplate.client.luau")
local serverSource = fs.readFile(folder .. "RuntimeServer.server.luau")
local configSource = fs.readFile(folder .. "Config.luau")

local function close(actual, expected, message)
	assert(
		math.abs(actual - expected) < 0.00001,
		(message or "Unexpected number") .. ": " .. tostring(actual) .. " vs " .. tostring(expected)
	)
end

local function signal()
	local callbacks = {}
	return {
		Connect = function(_, callback)
			local connection = { Connected = true }
			function connection:Disconnect()
				self.Connected = false
			end
			table.insert(callbacks, { connection, callback })
			return connection
		end,
		Fire = function(_, ...)
			for _, entry in table.clone(callbacks) do
				if entry[1].Connected then
					entry[2](...)
				end
			end
		end,
		Count = function()
			local count = 0
			for _, entry in callbacks do
				if entry[1].Connected then
					count += 1
				end
			end
			return count
		end,
	}
end

local function harness(studio)
	local h = {
		now = 10,
		warnings = {},
		scheduled = {},
		created = {},
		writes = {},
		sending = {},
		studio = studio ~= false,
	}
	local methods = {}
	local function event(self, key)
		if not self._events[key] then
			self._events[key] = signal()
		end
		return self._events[key]
	end
	local function ancestors(item)
		local result = {}
		while item do
			table.insert(result, item)
			item = item.Parent
		end
		return result
	end
	function h.new(className)
		local object = setmetatable({
			_class = className,
			_children = {},
			_attrs = {},
			_events = {},
			_destroyed = false,
			_values = {
				Name = className,
				Enabled = true,
				Visible = true,
				AbsoluteSize = r.Vector2.new(1280, 720),
				AbsolutePosition = r.Vector2.zero,
				Position = V3.zero,
				CFrame = CF.identity,
				Text = "",
				Density = 0.08,
				Haze = 0,
				Offset = 0.25,
				Color = C3.fromRGB(199, 216, 229),
				Decay = C3.fromRGB(153, 168, 183),
				Glare = 0,
				ClockTime = 13.5,
			},
		}, {
			__index = function(self, key)
				if methods[key] then
					return methods[key]
				end
				if self._values[key] ~= nil then
					return self._values[key]
				end
				if
					table.find({
						"Destroying",
						"AncestryChanged",
						"DescendantAdded",
						"ChildAdded",
						"ChildRemoved",
						"AttributeChanged",
						"Activated",
						"FocusLost",
						"InputBegan",
						"InputChanged",
						"InputEnded",
						"Event",
						"OnServerEvent",
						"PlayerAdded",
						"PlayerRemoving",
						"CharacterAdded",
						"CharacterRemoving",
					}, key)
				then
					return event(self, key)
				end
				for _, child in self._children do
					if child.Name == key then
						return child
					end
				end
				return nil
			end,
			__newindex = function(self, key, value)
				if h.quantize and self._class == "Atmosphere" and type(value) == "number" then
					local encoded = buffer.create(4)
					buffer.writef32(encoded, 0, value)
					value = buffer.readf32(encoded, 0)
				end
				local before = self._values[key]
				if before == value then
					return
				end
				if self._class == "Lighting" then
					assert(
						key ~= "FogStart" and key ~= "FogEnd" and key ~= "FogColor",
						"Haze wrote legacy Lighting." .. key
					)
				end
				table.insert(h.writes, { object = self, key = key, value = value, at = h.now })
				if key == "Parent" then
					local descendants = self:GetDescendants()
					if before then
						local index = table.find(before._children, self)
						if index then
							table.remove(before._children, index)
						end
					end
					self._values[key] = value
					if value then
						table.insert(value._children, self)
					end
					if before then
						event(before, "ChildRemoved"):Fire(self)
					end
					if value then
						event(value, "ChildAdded"):Fire(self)
						for _, ancestor in ancestors(value) do
							event(ancestor, "DescendantAdded"):Fire(self)
							for _, descendant in descendants do
								event(ancestor, "DescendantAdded"):Fire(descendant)
							end
						end
					end
					event(self, "AncestryChanged"):Fire(self, value)
					for _, descendant in descendants do
						event(descendant, "AncestryChanged"):Fire(descendant, descendant.Parent)
					end
				else
					self._values[key] = value
				end
				event(self, "property:" .. key):Fire()
			end,
		})
		table.insert(h.created, object)
		return object
	end
	function methods:IsA(name)
		return self._class == name
			or name == "Instance"
			or (name == "BasePart" and self._class == "Part")
	end
	function methods:IsDescendantOf(parent)
		local current = self.Parent
		while current do
			if current == parent then
				return true
			end
			current = current.Parent
		end
		return false
	end
	function methods:GetChildren()
		return table.clone(self._children)
	end
	function methods:GetDescendants()
		local result = {}
		for _, child in self._children do
			table.insert(result, child)
			for _, descendant in child:GetDescendants() do
				table.insert(result, descendant)
			end
		end
		return result
	end
	function methods:FindFirstChild(name, recursive)
		for _, child in self._children do
			if child.Name == name then
				return child
			end
			if recursive then
				local found = child:FindFirstChild(name, true)
				if found then
					return found
				end
			end
		end
		return nil
	end
	function methods:WaitForChild(name)
		return self:FindFirstChild(name)
	end
	function methods:FindFirstChildOfClass(name)
		for _, child in self._children do
			if child:IsA(name) then
				return child
			end
		end
		return nil
	end
	function methods:GetPropertyChangedSignal(name)
		return event(self, "property:" .. name)
	end
	function methods:GetAttributeChangedSignal(name)
		return event(self, "attribute:" .. name)
	end
	function methods:GetAttribute(name)
		return self._attrs[name]
	end
	function methods:SetAttribute(name, value)
		if self._attrs[name] == value then
			return
		end
		self._attrs[name] = value
		event(self, "attribute:" .. name):Fire()
		event(self, "AttributeChanged"):Fire(name)
	end
	function methods:GetAttributes()
		return table.clone(self._attrs)
	end
	function methods:GetFullName()
		return self.Name
	end
	function methods:Clone()
		local clone = h.new(self._class)
		for key, value in self._values do
			if key ~= "Parent" then
				clone[key] = value
			end
		end
		for key, value in self._attrs do
			clone:SetAttribute(key, value)
		end
		for _, child in self._children do
			local copy = child:Clone()
			copy.Parent = clone
		end
		return clone
	end
	function methods:Destroy()
		if self._destroyed then
			return
		end
		rawset(self, "_destroyed", true)
		event(self, "Destroying"):Fire()
		for _, child in self:GetChildren() do
			child:Destroy()
		end
		self.Parent = nil
	end
	function methods:Fire(...)
		event(self, "Event"):Fire(...)
	end
	function methods:FireServer(patch)
		table.insert(h.sending, patch)
		event(self, "OnServerEvent"):Fire(h.player, patch)
	end
	function methods:IsFocused()
		return false
	end
	function methods:GetPlayers()
		return self:GetChildren()
	end
	function methods:IsStudio()
		return h.studio
	end
	function methods:GetFocusedTextBox()
		return nil
	end
	function methods:GetService(name)
		return assert(h.services[name], name)
	end
	function h.node(className, name, parent)
		local item = h.new(className)
		item.Name, item.Parent = name, parent
		return item
	end
	h.game = h.new("DataModel")
	h.game.CreatorType, h.game.CreatorId = r.Enum.CreatorType.User, 77
	h.services = {}
	for _, name in
		{
			"Players",
			"ReplicatedStorage",
			"RunService",
			"Lighting",
			"UserInputService",
			"Workspace",
			"ServerScriptService",
		}
	do
		h.services[name] = h.node(name, name, h.game)
	end
	h.services.RunService.RenderStepped = signal()
	h.services.UserInputService.TouchEnabled = false
	h.player = h.node("Player", "Author", h.services.Players)
	h.player.UserId = 77
	h.playerGui = h.node("PlayerGui", "PlayerGui", h.player)
	h.character = h.node("Model", "Character", h.services.Workspace)
	h.characterRoot = h.node("Part", "HumanoidRootPart", h.character)
	h.player.Character = h.character
	h.services.Players.LocalPlayer = h.player
	h.services.Workspace.CurrentCamera = { CFrame = CF.new() }
	h.root = h.node("Model", "CornfieldFog", h.services.Workspace)
	h.config = h.node("ModuleScript", "Config", h.root)
	h.server = h.node("Script", "RuntimeServer", h.root)
	h.template = h.node("LocalScript", "ClientTemplate", h.server)
	local fakeOs = setmetatable({
		clock = function()
			return h.now
		end,
	}, { __index = os })
	h.env = setmetatable({
		game = h.game,
		workspace = h.services.Workspace,
		Instance = { new = h.new },
		Color3 = C3,
		Vector3 = V3,
		Vector2 = r.Vector2,
		CFrame = CF,
		UDim = r.UDim,
		UDim2 = r.UDim2,
		Enum = r.Enum,
		os = fakeOs,
		warn = function(message)
			table.insert(h.warnings, message)
		end,
		task = {
			spawn = function(callback, ...)
				callback(...)
			end,
			defer = function(callback, ...)
				table.insert(
					h.scheduled,
					{ at = h.now, callback = callback, args = table.pack(...) }
				)
			end,
			delay = function(delay, callback, ...)
				table.insert(
					h.scheduled,
					{ at = h.now + delay, callback = callback, args = table.pack(...) }
				)
			end,
			wait = function(delay)
				h.now += delay or 0.01
			end,
		},
	}, { __index = getfenv() })
	function h.execute(source, scriptObject)
		local fn = assert(loadstring(source, scriptObject and scriptObject.Name or "Config"))
		setfenv(
			fn,
			setmetatable({
				script = scriptObject,
				require = function(item)
					assert(item == h.config, "Only the audited Config module may be required")
					return h.settings
				end,
			}, { __index = h.env })
		)
		return fn()
	end
	h.settings = h.execute(configSource, h.config)
	function h.serverStart()
		h.execute(serverSource, h.server)
		h.runtime = h.services.ReplicatedStorage:FindFirstChild("CornfieldFogRuntime")
		return h.runtime
	end
	function h.clientStart()
		local bootstrap = assert(h.playerGui:FindFirstChild("CornfieldFogBootstrap"))
		h.client = assert(bootstrap:FindFirstChild("CornfieldFogClient"))
		h.execute(clientSource, h.client)
	end
	function h.frame(dt)
		h.now += dt
		h.services.RunService.RenderStepped:Fire(dt)
		for index = #h.scheduled, 1, -1 do
			local pending = h.scheduled[index]
			if pending.at <= h.now then
				table.remove(h.scheduled, index)
				pending.callback(table.unpack(pending.args, 1, pending.args.n))
			end
		end
	end
	function h.advance(seconds)
		for _ = 1, math.ceil(seconds / 0.02) do
			h.frame(0.02)
		end
	end
	function h.request(player, request, wait)
		h.now += wait or 0.1
		h.runtime.Control.OnServerEvent:Fire(player, request)
	end
	function h.atmosphere()
		return h.services.Lighting:FindFirstChildOfClass("Atmosphere")
	end
	function h.lightingWrites()
		local count = 0
		for _, write in h.writes do
			if
				write.object:IsA("Atmosphere")
				and table.find(
					{ "Density", "Haze", "Color", "Decay", "Offset", "Glare" },
					write.key
				)
			then
				count += 1
			end
		end
		return count
	end
	return h
end

local profilesFn = assert(loadstring(fs.readFile("src/shared/Game/LightingModes.luau")))
setfenv(profilesFn, setmetatable({ Color3 = C3 }, { __index = getfenv() }))
-- Only night is playable. Day/dusk here are explicit author-tool environments,
-- exercising a portable effect across ClockTime edits rather than game modes.
local profiles = {
	day = {
		ClockTime = 13.5,
		Density = 0.08,
		Haze = 0,
		Offset = 0.25,
		Color = C3.fromRGB(199, 216, 229),
		Decay = C3.fromRGB(153, 168, 183),
	},
	dusk = {
		ClockTime = 17.9,
		Density = 0.18,
		Haze = 0.4,
		Offset = 0.25,
		Color = C3.fromRGB(168, 160, 155),
		Decay = C3.fromRGB(91, 83, 80),
	},
	night = profilesFn().Profiles.hard,
}
local hazeTarget = { day = 0.5, dusk = 1.25, night = 1.8 }
local function applyMode(h, mode)
	local profile = profiles[mode]
	h.services.Lighting.ClockTime = profile.ClockTime
	local atmosphere = h.atmosphere()
	if atmosphere then
		for _, property in { "Density", "Haze", "Offset", "Color", "Decay" } do
			atmosphere[property] = profile[property]
		end
		atmosphere.Glare = 0
	end
end
local function prepared(mode, withAtmosphere, studio)
	local h = harness(studio)
	if withAtmosphere ~= false then
		h.node("Atmosphere", "AuthorAtmosphere", h.services.Lighting)
	end
	applyMode(h, mode)
	h.serverStart()
	h.clientStart()
	return h
end

-- The test bodies below execute the production client/server closures; the
-- adapter never loads or imports the external asset or writes a place file.
for _, mode in { "day", "dusk", "night" } do
	local h = prepared(mode)
	local atmosphere = h.atmosphere()
	local originalParent = atmosphere.Parent
	h.advance(1)
	close(atmosphere.Haze, hazeTarget[mode], mode .. " haze")
	close(atmosphere.Density, profiles[mode].Density, mode .. " baseline density")
	close(atmosphere.Offset, 0.25, "Baseline offset")
	close(atmosphere.Glare, 0, "Baseline glare")
	assert(atmosphere.Parent == originalParent, "Existing Atmosphere was reparented")
	assert(h.services.Lighting.ClockTime == profiles[mode].ClockTime, "Haze changed mode")
	local writes = h.lightingWrites()
	h.advance(1)
	assert(h.lightingWrites() == writes, "Settled effect kept writing")
	h.request(h.player, { Enabled = false })
	h.advance(1)
	close(atmosphere.Haze, profiles[mode].Haze, "Off did not restore mode haze")
	assert(
		atmosphere.Color == profiles[mode].Color and atmosphere.Decay == profiles[mode].Decay,
		"Off did not restore mode palette"
	)
	assert(
		not atmosphere._destroyed and atmosphere.Parent == originalParent,
		"Off destroyed author Atmosphere"
	)
end

local function ui(h, className, text)
	for _, item in h.playerGui:GetDescendants() do
		if item:IsA(className) and item.Text == text then
			return item
		end
	end
	error("Missing actual UI " .. className .. ": " .. text)
end
local function visibleModalButtons(h)
	local count = 0
	for _, item in h.playerGui:GetDescendants() do
		if item:IsA("TextButton") and item.Modal then
			local visible, ancestor = true, item
			while ancestor and ancestor ~= h.playerGui do
				if ancestor.Visible == false or ancestor.Enabled == false then
					visible = false
					break
				end
				ancestor = ancestor.Parent
			end
			if visible then
				count += 1
			end
		end
	end
	return count
end
local function begin(h)
	h.serverStart()
	h.clientStart()
	h.advance(1)
	return h
end

-- Mode writes are actual server-style property notifications, not a fake
-- reset of client internals. The newest mode must become cleanup's baseline.
do
	local h = prepared("night")
	h.advance(1)
	for _, mode in { "day", "dusk", "night", "day" } do
		applyMode(h, mode)
		h.advance(1)
		close(h.atmosphere().Haze, hazeTarget[mode], "Changed mode haze")
		close(h.atmosphere().Density, profiles[mode].Density, "Changed mode density")
		assert(h.atmosphere().Color == profiles[mode].Color, "Auto retained stale palette")
	end
	h.request(h.player, { Enabled = false })
	h.advance(1)
	close(h.atmosphere().Haze, profiles.day.Haze, "Off restored historical night")
	close(h.atmosphere().Density, profiles.day.Density, "Off restored historical density")
end

-- UI actions execute their real event handlers and server whitelist. Palette
-- selection is explicit; default Auto never forces the imported Night tint.
do
	local h = prepared("day")
	h.advance(1)
	assert(h.runtime:GetAttribute("Preset") == "Auto", "Mode palette is not default")
	ui(h, "TextLabel", "Интенсивность дымки")
	ui(h, "TextLabel", "Сила оттенка, %")
	ui(h, "TextLabel", "Без жёсткой границы видимости")
	local fogGui = assert(h.playerGui:FindFirstChild("CornfieldFogControls"))
	local opener = ui(h, "TextButton", "Дымка · F6")
	assert(
		fogGui.IgnoreGuiInset
			and fogGui.ScreenInsets == r.Enum.ScreenInsets.None
			and fogGui.ClipToDeviceSafeArea == false,
		"Fog opener inherited the Roblox top inset"
	)
	for _, dimensions in { r.Vector2.new(1280, 720), r.Vector2.new(1914, 801) } do
		local width = opener.Size.X.Scale * dimensions.X + opener.Size.X.Offset
		local height = opener.Size.Y.Scale * dimensions.Y + opener.Size.Y.Offset
		local x = opener.Position.X.Scale * dimensions.X
			+ opener.Position.X.Offset
			- opener.AnchorPoint.X * width
		local y = opener.Position.Y.Scale * dimensions.Y
			+ opener.Position.Y.Offset
			- opener.AnchorPoint.Y * height
		assert(
			x >= 0 and x + width <= dimensions.X and y >= 0 and y + height <= 60,
			"Fog opener is outside its top-right strip"
		)
		-- Root's actual engine LeaveRound bounds are Y74..114. This checks
		-- created GUI layout inputs, not simulated engine pixels/top-bar rendering.
		assert(y + height < 74, "Fog opener overlaps the observed LeaveRound row")
	end
	local fogPanel = assert(fogGui:FindFirstChild("Panel", true))
	assert(not fogPanel.Visible and fogPanel.Position.Y.Offset >= 64, "Panel opens over top strip")
	local closeButton = ui(h, "TextButton", "×")
	assert(closeButton.Modal == true, "Open author panel does not release first-person mouse")
	assert(visibleModalButtons(h) == 0, "Hidden panel retains a visible modal button")
	opener.Activated:Fire()
	assert(fogPanel.Visible and visibleModalButtons(h) == 1, "Opener did not expose modal panel")
	closeButton.Activated:Fire()
	assert(
		not fogPanel.Visible and visibleModalButtons(h) == 0,
		"Close kept a modal button visible"
	)
	h.services.UserInputService.InputBegan:Fire({ KeyCode = r.Enum.KeyCode.F6 }, false)
	assert(fogPanel.Visible and visibleModalButtons(h) == 1, "F6 did not expose modal panel")
	for _, item in h.playerGui:GetDescendants() do
		if item:IsA("TextLabel") or item:IsA("TextButton") then
			assert(
				not string.find(item.Text, "шаг", 1, true),
				"UI still claims visibility steps"
			)
		end
	end
	ui(h, "TextButton", "+5").Activated:Fire()
	assert(h.runtime:GetAttribute("Steps") == 25, "Intensity UI did not use validated request")
	h.advance(1)
	close(h.atmosphere().Haze, 0.625, "Intensity did not affect actual Haze")
	close(h.atmosphere().Density, 0.08875, "Intensity density adjustment")
	ui(h, "TextButton", "Поле").Activated:Fire()
	h.advance(1)
	assert(
		h.atmosphere().Color == profiles.day.Color:Lerp(h.settings.Presets.Field, 0.2),
		"Subtle tint"
	)
	assert(h.services.Lighting.ClockTime == profiles.day.ClockTime, "Tint changed difficulty")
	ui(h, "TextButton", "Режим").Activated:Fire()
	h.advance(1)
	assert(h.atmosphere().Color == profiles.day.Color, "Auto did not restore current mode palette")
	ui(h, "TextButton", "Дымка: включена").Activated:Fire()
	h.advance(1)
	close(h.atmosphere().Haze, 0, "Toggle did not restore baseline")
	h.client:Destroy()
	assert(visibleModalButtons(h) == 0, "Controller cleanup left a modal button visible")
end

-- Actual property writes are bounded even with 50Hz RenderStepped input.
do
	local h = prepared("day")
	h.advance(1)
	local began = #h.writes
	h.request(h.player, { Steps = 40, Preset = "Field" })
	h.advance(1)
	local lastAt, changed = {}, 0
	for index = began + 1, #h.writes do
		local write = h.writes[index]
		if write.object:IsA("Atmosphere") then
			if lastAt[write.key] then
				assert(write.at - lastAt[write.key] >= 0.09999, "Atmosphere writes exceeded10Hz")
			end
			lastAt[write.key] = write.at
			changed += 1
		end
	end
	assert(changed > 0, "Rate bound did not observe actual transition")
	local settledWrites = h.lightingWrites()
	h.advance(2)
	assert(h.lightingWrites() == settledWrites, "Settled transition kept writing")
end

-- Foreign/server property signals update individual baselines. Immediate and
-- later cleanup preserve those values rather than an activation snapshot.
do
	local h = prepared("night")
	h.advance(1)
	local effect = h.atmosphere()
	local foreign = {
		Density = 0.11,
		Haze = 0.2,
		Offset = 0.4,
		Glare = 0.15,
		Color = C3.fromRGB(123, 145, 167),
		Decay = C3.fromRGB(45, 67, 89),
	}
	for property, value in foreign do
		effect[property] = value
	end
	h.advance(1)
	close(effect.Haze, 1.2, "Haze ignored latest foreign baseline")
	h.client:Destroy()
	for property, value in foreign do
		assert(effect[property] == value, "Cleanup lost latest " .. property)
	end
	assert(effect.Parent == h.services.Lighting and not effect._destroyed, "Author effect removed")
	local writes = h.lightingWrites()
	h.advance(1)
	assert(h.lightingWrites() == writes, "Dead renderer still writes")
	assert(h.services.RunService.RenderStepped:Count() == 0, "Renderer connection leaked")
end
do
	local h = prepared("dusk")
	h.advance(1)
	local effect = h.atmosphere()
	effect.Haze = 0.123
	h.client:Destroy()
	close(effect.Haze, 0.123, "Immediate foreign write overwritten during cleanup")
end

-- Field fade follows moving roots continuously; leaving restores, reentering
-- never compounds the previous haze into a new baseline.
do
	local h = harness()
	h.node("Atmosphere", "AuthorAtmosphere", h.services.Lighting)
	applyMode(h, "day")
	h.settings.FieldOnly, h.settings.FieldSize, h.settings.EdgeFadeStuds =
		true, V3.new(100, 30, 100), 20
	begin(h)
	close(h.atmosphere().Haze, 0.5, "Field center")
	h.characterRoot.Position = V3.new(40, 0, 0)
	h.advance(1)
	close(h.atmosphere().Haze, 0.25, "Field inner fade")
	h.characterRoot.Position = V3.new(48, 0, 0)
	h.advance(1)
	close(h.atmosphere().Haze, 0.05, "Field near edge")
	h.characterRoot.Position = V3.new(51, 0, 0)
	h.advance(1)
	close(h.atmosphere().Haze, 0, "Field exit baseline")
	h.characterRoot.Position = V3.zero
	h.advance(1)
	close(h.atmosphere().Haze, 0.5, "Field reentry compounded baseline")
end

-- No effect initially: one owned transient, deleted on disable/cleanup.
-- If an author adds a real effect, it replaces our transient; multiple author
-- effects pause safely without reparenting/deleting any of them.
do
	local h = prepared("dusk", false)
	h.advance(1)
	local transient = h.atmosphere()
	assert(
		transient:GetAttribute("CornfieldFogAtmosphereOwned") == true,
		"Missing transient ownership"
	)
	close(transient.Haze, 1.25, "Transient inherited mode")
	h.request(h.player, { Enabled = false })
	h.advance(1)
	assert(transient._destroyed and h.atmosphere() == nil, "Transient remained after disable")
	h.request(h.player, { Enabled = true })
	h.advance(1)
	local second = h.atmosphere()
	assert(second and second ~= transient, "Reenable did not create one new transient")
	local author = h.node("Atmosphere", "NewAuthorAtmosphere", h.services.Lighting)
	author.Haze = 0.3
	h.advance(1)
	assert(second._destroyed and h.atmosphere() == author, "Transient displaced author effect")
	close(author.Haze, 1.15, "New author baseline not respected")
	h.client:Destroy()
	close(author.Haze, 0.3, "Author replacement baseline cleanup")
end
do
	local h = harness()
	local first = h.node("Atmosphere", "First", h.services.Lighting)
	local second = h.node("Atmosphere", "Second", h.services.Lighting)
	first.Haze, second.Haze = 0.1, 0.6
	begin(h)
	close(first.Haze, 0.1, "Ambiguous first modified")
	close(second.Haze, 0.6, "Ambiguous second modified")
	assert(
		first.Parent == h.services.Lighting and second.Parent == h.services.Lighting,
		"Ambiguous Atmospheres were reparented"
	)
	second.Parent = h.services.Workspace
	h.advance(1)
	close(first.Haze, 0.6, "Unambiguous effect did not recover")
	second.Parent = h.services.Lighting
	h.advance(1)
	close(first.Haze, 0.1, "Ambiguity did not restore acquired first")
	close(second.Haze, 0.6, "Ambiguity altered new second")
end
do
	local h = prepared("day", false)
	h.advance(1)
	local transient = h.atmosphere()
	transient.Haze = 0.35
	h.client:Destroy()
	assert(
		not transient._destroyed and transient.Parent == h.services.Lighting,
		"Foreign edited transient deleted"
	)
	close(transient.Haze, 0.35, "Foreign edited transient overwritten")
	assert(
		transient:GetAttribute("CornfieldFogAtmosphereOwned") == nil,
		"Ownership not relinquished"
	)
end

do
	local h = prepared("day")
	h.advance(1)
	h.player.CharacterRemoving:Fire(h.character)
	close(h.atmosphere().Haze, 0, "Character removal did not restore synchronously")
	h.advance(0.4)
	close(h.atmosphere().Haze, 0, "Removing character rebound old root")
	h.player.CharacterAdded:Fire(h.character)
	h.advance(1)
	close(h.atmosphere().Haze, 0.5, "New character did not recover")
	h.root.Parent = nil
	h.advance(0.1)
	close(h.atmosphere().Haze, 0, "Model removal failed cleanup")
	assert(
		h.runtime.Parent == nil and h.playerGui:FindFirstChild("CornfieldFogControls") == nil,
		"Runtime/UI leaked"
	)
end

-- Engine numeric storage can quantize values: own-write comparisons must use
-- actual readback, or our own .18/.27/1.8 becomes a false foreign baseline.
do
	local h = harness()
	h.quantize = true
	h.node("Atmosphere", "QuantizedAuthorAtmosphere", h.services.Lighting)
	applyMode(h, "night")
	begin(h)
	for _, mode in { "dusk", "day", "night" } do
		applyMode(h, mode)
		h.advance(1)
		close(h.atmosphere().Haze, hazeTarget[mode], "Quantized mode accumulated own writes")
	end
	local writes = h.lightingWrites()
	h.advance(1)
	assert(h.lightingWrites() == writes, "Quantized settled effect kept writing")
	h.client:Destroy()
	close(h.atmosphere().Haze, profiles.night.Haze, "Quantized readback lost baseline restore")
	close(h.atmosphere().Density, profiles.night.Density, "Quantized density baseline")
end

-- Actual existing remote rejects unauthorized/malformed/nonfinite values,
-- clamps valid numbers, rate-limits duplicates, and resets session defaults.
do
	local h = harness(false)
	h.game.CreatorId = 999
	h.serverStart()
	assert(h.player:GetAttribute("CornfieldFogCanEdit") == false, "Unauthorized panel access")
	h.request(h.player, { Steps = 99, Enabled = false })
	assert(
		h.runtime:GetAttribute("Steps") == 20 and h.runtime:GetAttribute("Enabled") == true,
		"Unauthorized request applied"
	)
end
do
	local h = harness(false)
	h.serverStart()
	for _, request in { false, "malformed", 42 } do
		h.request(h.player, request)
	end
	h.request(h.player, {
		Steps = 0 / 0,
		StartRatio = math.huge,
		Enabled = "false",
		Preset = "Unknown",
		HazeDay = 2,
		FogColor = C3.new(),
	})
	assert(
		h.runtime:GetAttribute("Steps") == 20 and h.runtime:GetAttribute("StartRatio") == 0.2,
		"Invalid numbers applied"
	)
	assert(
		h.runtime:GetAttribute("Preset") == "Auto" and h.runtime:GetAttribute("HazeDay") == 0.5,
		"Unknown fields escaped whitelist"
	)
	h.request(h.player, { Steps = 999, StartRatio = -1, Preset = "Night" })
	assert(
		h.runtime:GetAttribute("Steps") == 120 and h.runtime:GetAttribute("StartRatio") == 0,
		"Numeric bounds not clamped"
	)
	assert(h.runtime:GetAttribute("Preset") == "Night", "Validated palette rejected")
	h.request(h.player, { Steps = 10 }, 0.01)
	assert(h.runtime:GetAttribute("Steps") == 120, "Rate limiter accepted rapid duplicate")
	h.request(h.player, { Steps = -999, StartRatio = 999 }, 0.08)
	assert(
		h.runtime:GetAttribute("Steps") == 10 and h.runtime:GetAttribute("StartRatio") == 0.8,
		"Lower/upper clamps"
	)
	h.request(h.player, { Reset = true })
	assert(
		h.runtime:GetAttribute("Steps") == 20 and h.runtime:GetAttribute("Preset") == "Auto",
		"Reset lost Auto/default intensity"
	)
	local runtime = h.runtime
	h.serverStart()
	assert(
		h.runtime == runtime and #h.warnings == 1,
		"Duplicate server replaced existing controller"
	)
end

print(
	"PASS: CornfieldFog actual source adapters: author day/dusk/night ClockTime edits/latest baseline; validated density/tint UI and modal panel lifecycle; <=10Hz transitions/zero settled writes; field edge/reentry; foreign/ambiguous/transient/character/model cleanup; admin/malformed/nonfinite/whitelist/clamp/rate/reset/duplicate server guards. No Studio/rendering claim."
)
