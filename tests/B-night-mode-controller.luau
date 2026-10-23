-- Execute the actual B controller with immediate/deferred Roblox-style signals.
-- Checks Lighting ownership and round-start races, rather than mirroring UI code.
local fs, r = require("@lune/fs"), require("@lune/roblox")
local source = fs.readFile("variants/B/client/Controllers/NightModeController.luau")
local checks = 0
local function check(ok, message)
	checks += 1
	assert(ok, message)
end
local PROFILE = {
	ClockTime = 0,
	Brightness = 1,
	Ambient = r.Color3.fromRGB(18, 22, 30),
	OutdoorAmbient = r.Color3.fromRGB(38, 42, 53),
	EnvironmentDiffuseScale = 1,
	EnvironmentSpecularScale = 1,
	GlobalShadows = true,
}
local HARD = {
	ClockTime = 20.5,
	Brightness = 0,
	Ambient = r.Color3.new(),
	OutdoorAmbient = r.Color3.new(),
	EnvironmentDiffuseScale = 0,
	EnvironmentSpecularScale = 0,
	GlobalShadows = true,
}

local function harness(deferred, options)
	options = options or {}
	local h = { queue = {}, signals = {}, writes = {}, external = false }
	local function signal()
		local entries = {}
		local event = {}
		function event:Connect(callback)
			local connection = { Connected = true }
			function connection.Disconnect(item)
				item.Connected = false
			end
			table.insert(entries, { connection, callback })
			return connection
		end
		function event:Fire(...)
			for _, entry in table.clone(entries) do
				if entry[1].Connected then
					entry[2](...)
				end
			end
		end
		function event:Count()
			local count = 0
			for _, entry in entries do
				if entry[1].Connected then
					count += 1
				end
			end
			return count
		end
		table.insert(h.signals, event)
		return event
	end
	local methods = {}
	local function event(object, key)
		object._events[key] = object._events[key] or signal()
		return object._events[key]
	end
	local function ancestors(object)
		local result = {}
		while object do
			table.insert(result, object)
			object = object.Parent
		end
		return result
	end
	function h.new(class)
		return setmetatable({
			_class = class,
			_values = { Name = class },
			_children = {},
			_events = {},
			_attrs = {},
		}, {
			__index = function(object, key)
				if methods[key] then
					return methods[key]
				end
				if object._values[key] ~= nil then
					return object._values[key]
				end
				if
					table.find({
						"AttributeChanged",
						"AncestryChanged",
						"ChildAdded",
						"ChildRemoved",
						"DescendantAdded",
						"DescendantRemoving",
						"Activated",
					}, key)
				then
					return event(object, key)
				end
				return nil
			end,
			__newindex = function(object, key, value)
				local old = object._values[key]
				if old == value then
					return
				end
				if key == "Parent" then
					local descendants = object:GetDescendants()
					table.insert(descendants, 1, object)
					if old then
						for _, ancestor in ancestors(old) do
							for _, item in descendants do
								event(ancestor, "DescendantRemoving"):Fire(item)
							end
						end
						table.remove(old._children, assert(table.find(old._children, object)))
					end
					object._values.Parent = value
					if old then
						event(old, "ChildRemoved"):Fire(object)
					end
					if value then
						table.insert(value._children, object)
						event(value, "ChildAdded"):Fire(object)
						for _, ancestor in ancestors(value) do
							for _, item in descendants do
								event(ancestor, "DescendantAdded"):Fire(item)
							end
						end
					end
					for _, item in descendants do
						event(item, "AncestryChanged"):Fire(item, item.Parent)
					end
				else
					object._values[key] = value
				end
				if object == h.lighting and not h.external then
					table.insert(h.writes, { key, value })
				end
				local changed = object._events["property:" .. key]
				if changed then
					if deferred and object == h.lighting then
						table.insert(h.queue, function()
							changed:Fire()
						end)
					else
						changed:Fire()
					end
				end
			end,
		})
	end
	function methods:IsA(class)
		return self._class == class or (class == "BasePart" and self._class == "Part")
	end
	function methods:GetChildren()
		return table.clone(self._children)
	end
	function methods:GetDescendants()
		local result = {}
		for _, child in self._children do
			table.insert(result, child)
			for _, item in child:GetDescendants() do
				table.insert(result, item)
			end
		end
		return result
	end
	function methods:FindFirstChild(name)
		for _, child in self._children do
			if child.Name == name then
				return child
			end
		end
		return nil
	end
	function methods:GetAttribute(name)
		return self._attrs[name]
	end
	function methods:SetAttribute(name, value)
		if self._attrs[name] ~= value then
			self._attrs[name] = value
			event(self, "AttributeChanged"):Fire(name)
			event(self, "attribute:" .. name):Fire()
		end
	end
	function methods:GetAttributeChangedSignal(name)
		return event(self, "attribute:" .. name)
	end
	function methods:GetPropertyChangedSignal(name)
		return event(self, "property:" .. name)
	end
	function methods:Destroy()
		self.Parent = nil
		for _, child in self:GetChildren() do
			child:Destroy()
		end
	end
	function h.flush()
		local iterations = 0
		while #h.queue > 0 do
			iterations += 1
			check(iterations < 200, "Deferred event/reassert loop")
			local queue = h.queue
			h.queue = {}
			for _, callback in queue do
				callback()
			end
		end
	end
	function h.write(values)
		h.external = true
		for key, value in values do
			h.lighting[key] = value
		end
		h.external = false
	end
	function h.profile(values, message)
		for key, value in values do
			check(h.lighting[key] == value, message .. ": " .. key)
		end
	end
	h.workspace, h.lighting = h.new("Workspace"), h.new("Lighting")
	h.write(HARD)
	h.write({
		FogStart = 55,
		FogEnd = 320,
		FogColor = r.Color3.fromRGB(20, 27, 36),
		ExposureCompensation = -0.3,
	})
	h.map, h.field, h.player, h.playerGui =
		h.new("Model"), h.new("Part"), h.new("Player"), h.new("PlayerGui")
	h.map.Name, h.map.Parent = "CornMap", h.workspace
	h.map:SetAttribute("corn_project_id", "children_of_corn")
	h.map:SetAttribute("HarvestArtVariant", options.variant or "B")
	h.field.Name, h.field.Size, h.field.Parent = "FieldZone", r.Vector3.new(630, 10, 630), h.map
	h.playerGui.Name, h.playerGui.Parent = "PlayerGui", h.player
	h.player:SetAttribute("CornfieldFogCanEdit", options.canEdit ~= false)
	function h.gui()
		h.screen, h.outer, h.panel, h.body =
			h.new("ScreenGui"), h.new("Frame"), h.new("Frame"), h.new("ScrollingFrame")
		h.screen.Name, h.screen.Parent = "CornfieldFogControls", h.playerGui
		h.outer.Parent = h.screen
		h.panel.Name, h.panel.Parent = "Panel", h.outer
		h.body.Parent = h.panel
		return h.body
	end
	if not options.lateGui then
		h.gui()
	end
	local services = {
		Lighting = h.lighting,
		Workspace = h.workspace,
		Players = { LocalPlayer = h.player },
		RunService = {
			IsStudio = function()
				return options.studio ~= false
			end,
			IsClient = function()
				return options.client ~= false
			end,
		},
	}
	local fn = assert(loadstring(source, "NightModeController"))
	setfenv(
		fn,
		setmetatable({
			game = {
				GetService = function(_, name)
					return assert(services[name], name)
				end,
			},
			Instance = { new = h.new },
			task = {
				defer = function(callback)
					table.insert(h.queue, callback)
				end,
			},
			Color3 = r.Color3,
			Vector3 = r.Vector3,
			UDim = r.UDim,
			UDim2 = r.UDim2,
			Enum = r.Enum,
		}, { __index = getfenv() })
	)
	h.controller = fn()
	h.controller:Init({
		Config = {
			Environment = options.environment or "DEV",
			Game = { SessionMode = "solo_local" },
		},
	})
	h.controller:Start()
	h.flush()
	function h.block()
		return h.body and h.body:FindFirstChild("BNightModeBlock")
	end
	function h.click()
		local block = assert(h.block(), "Toggle block missing")
		assert(block:FindFirstChild("ToggleNight")).Activated:Fire()
	end
	function h.finish()
		h.controller:Stop()
		h.flush()
		for _, entry in h.signals do
			check(entry:Count() == 0, "Connection leaked after Stop")
		end
		for _, write in h.writes do
			check(PROFILE[write[1]] ~= nil, "Controller changed haze/other Lighting property")
		end
		check(h.lighting.FogStart == 55 and h.lighting.FogEnd == 320, "Legacy fog changed")
		check(h.lighting.ExposureCompensation == -0.3, "Exposure changed")
	end
	return h
end

for _, deferred in { false, true } do
	local h = harness(deferred)
	check(#h.writes == 0, "Default absolute mode wrote Lighting")
	check(h.block().LayoutOrder == 0, "New block is not first in existing body")
	check(
		h.block():FindFirstChild("ToggleNight").Text == "Ночь: абсолютная",
		"Wrong default label"
	)
	h.click()
	h.flush()
	h.profile(PROFILE, "Ordinary midnight profile")
	check(
		h.block():FindFirstChild("ToggleNight").Text == "Ночь: обычная · 00:00",
		"Wrong ordinary label"
	)
	local count = #h.writes
	for _ = 1, 10 do
		h.controller:_queueRefresh()
	end
	h.flush()
	check(#h.writes == count, "Idle UI refresh rewrote Lighting")
	h.click()
	h.flush()
	h.profile(HARD, "Toggle restores captured hard baseline")

	-- The server reapplies its hard profile after Start/Confirm while overlay is on.
	h.click()
	h.flush()
	local round = table.clone(HARD)
	round.ClockTime, round.Ambient = 21.75, r.Color3.fromRGB(3, 7, 11)
	round.GlobalShadows = false
	h.write(round)
	h.flush()
	h.profile(PROFILE, "Round change reasserts ordinary overlay")
	h.click()
	h.flush()
	h.profile(round, "Toggle restores latest replicated round baseline")

	-- An external author write before deferred event delivery wins when exiting.
	h.click()
	h.flush()
	h.write({ ClockTime = 23.125, Brightness = 0.25 })
	h.click()
	h.flush()
	check(
		h.lighting.ClockTime == 23.125 and h.lighting.Brightness == 0.25,
		"Undelivered foreign edit overwritten"
	)

	-- Old queued reasserts cannot affect a later enable epoch.
	h.click()
	h.flush()
	h.write({ ClockTime = 19.25 })
	h.click()
	h.click()
	h.write({ Ambient = r.Color3.fromRGB(9, 8, 7) })
	h.flush()
	h.profile(PROFILE, "Rapid toggles leave requested overlay active")
	h.click()
	h.flush()
	check(h.lighting.ClockTime == 19.25, "Epoch race lost foreign baseline")
	check(h.lighting.Ambient == r.Color3.fromRGB(9, 8, 7), "Epoch race lost later server edit")

	h.click()
	h.flush()
	h.player:SetAttribute("CornfieldFogCanEdit", false)
	h.flush()
	check(h.block() == nil and not h.controller._ordinary, "Permission loss kept overlay/UI")
	check(h.lighting.ClockTime == 19.25, "Permission loss did not restore baseline")
	h.player:SetAttribute("CornfieldFogCanEdit", true)
	h.flush()
	check(
		h.block() ~= nil and not h.controller._ordinary,
		"Permission regain did not create default-off control"
	)
	h.click()
	h.flush()
	h.screen:Destroy()
	h.flush()
	check(not h.controller._ordinary and h.controller._body == nil, "Panel deletion kept overlay")
	check(h.lighting.ClockTime == 19.25, "Panel deletion did not restore")
	h.gui()
	h.flush()
	h.click()
	h.flush()
	h.map:SetAttribute("HarvestArtVariant", "A")
	h.flush()
	check(h.block() == nil and not h.controller._ordinary, "Foreign map retained B control")
	h.profile({ ClockTime = 19.25 }, "Foreign map restores baseline")
	h.finish()
end

for _, options in
	{
		{ studio = false },
		{ client = false },
		{ environment = "PROD" },
		{ variant = "A" },
		{ canEdit = false },
	}
do
	local h = harness(true, options)
	check(h.block() == nil and #h.writes == 0, "Unauthorized context created UI or Lighting writes")
	h.finish()
end

do
	local h = harness(true, { lateGui = true })
	check(h.controller._body == nil, "Missing panel invented another GUI")
	h.gui()
	h.flush()
	check(h.block() ~= nil, "Late existing panel did not bind")
	h.click()
	h.flush()
	h.map.Parent = nil
	h.flush()
	check(h.block() == nil and not h.controller._ordinary, "Removed map retained overlay")
	h.profile(HARD, "Removed map restores")
	h.finish()
end

do
	local h = harness(true, { canEdit = false })
	local foreign = h.new("Frame")
	foreign.Name, foreign.Parent = "BNightModeBlock", h.body
	h.player:SetAttribute("CornfieldFogCanEdit", true)
	h.flush()
	check(
		h.controller._block == nil and foreign.Parent == h.body,
		"Foreign UI collision overwritten"
	)
	h.finish()
end

print(
	string.format(
		"B night mode controller: %d checks PASS (immediate/deferred signals, round changes, guarded restore, UI and B/DEV lifecycle)",
		checks
	)
)
