-- Execute the actual narrow installer with the accepted B Sources and faulting property adapter.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local luau = require("@lune/luau")
local code = fs.readFile("scripts/install-corn-shadows.luau")
local payload = serde.decode("json", assert(code:match("%[====%[(.-)%]====%]")))
local baseline = roblox.deserializePlace(fs.readFile("place/Children_of_corn_B.rbxl"))
local sources = {}
for _, item in baseline:GetDescendants() do
	if item:IsA("LuaSourceContainer") then
		sources[item:GetFullName():gsub("%.", "/")] = { class = item.ClassName, source = item.Source }
	end
end
local cases, refused, rolled = 0, 0, 0
local function check(value, message)
	cases += 1
	assert(value, message)
end
local function setup()
	local state = { running = false, studio = true, documents = {}, fault = nil, faulted = false }
	local methods = {}
	local function make(class, name, parent)
		local item = { values = { ClassName = class, Name = name, Archivable = true }, children = {}, attrs = {}, tags = {} }
		setmetatable(item, {
			__index = function(self, key) return methods[key] or self.values[key] end,
			__newindex = function(self, key, value)
				if key == "Parent" then
					local previous = self.values.Parent
					if previous then table.remove(previous.children, assert(table.find(previous.children, self))) end
					if value then table.insert(value.children, self) end
				end
				self.values[key] = value
				local fail = (state.fault == "source" and self.values.Name == "CornShadowController" and key == "Source")
					or (state.fault == "wide" and self == state.wide and key == "Shadows" and value == true)
					or (state.fault == "core" and self == state.core and key == "Shadows" and value == true)
					or (state.fault == "parent" and self.values.Name == "CornShadowController" and key == "Parent" and value == state.controllers)
				if fail and not state.faulted then state.faulted = true; error("injected " .. state.fault) end
			end,
		})
		item.Parent = parent
		return item
	end
	function methods:IsA(class)
		return self.ClassName == class or (class == "LuaSourceContainer" and ({ Script = true, LocalScript = true, ModuleScript = true })[self.ClassName]) == true
	end
	function methods:GetChildren() return table.clone(self.children) end
	function methods:GetDescendants()
		local result = {}
		local function visit(parent)
			for _, child in parent.children do table.insert(result, child); visit(child) end
		end
		visit(self)
		return result
	end
	function methods:GetFullName()
		if not self.Parent or self.Parent.ClassName == "DataModel" then return self.Name end
		return self.Parent:GetFullName() .. "." .. self.Name
	end
	function methods:FindFirstChild(name)
		for _, child in self.children do if child.Name == name then return child end end
		return nil
	end
	function methods:GetAttribute(name) return self.attrs[name] end
	function methods:GetAttributes() return table.clone(self.attrs) end
	function methods:GetTags() return table.clone(self.tags) end
	function methods:Destroy()
		for _, child in self:GetChildren() do child:Destroy() end
		self.Parent = nil
	end
	local game = make("DataModel", "Children_of_corn_B.rbxl")
	local paths = {}
	local function ensure(path, class)
		if paths[path] then
			if class and class ~= "Folder" then paths[path].ClassName = class end
			return paths[path]
		end
		local prefix, name = path:match("^(.*)/([^/]+)$")
		local parent = if prefix then ensure(prefix, "Folder") else game
		local item = make(class or "Folder", name or path, parent)
		paths[path] = item
		return item
	end
	for path, spec in sources do ensure(path, spec.class).Source = spec.source end
	game.StarterPlayer = paths.StarterPlayer
	game.ReplicatedStorage = paths.ReplicatedStorage
	local world = ensure("Workspace")
	local map = ensure("Workspace/CornMap", "Model")
	map.attrs = { corn_project_id = "children_of_corn", HarvestArtVariant = "B" }
	map.Ground = ensure("Workspace/CornMap/Ground", "Part")
	map.Ground.Size = roblox.Vector3.new(630, 2, 630)
	map.FieldZone = ensure("Workspace/CornMap/FieldZone", "Part")
	map.FieldZone.Size = roblox.Vector3.new(630, 10, 630)
	local lighting = { LightingStyle = "Realistic", GlobalShadows = true }
	game.Lighting = lighting
	local bank = ensure("ReplicatedStorage/CornFlashlightSettings", "Folder")
	bank.attrs = { Pitch = -6, CornFlashlightSettingsVersion = 1, corn_project_id = "children_of_corn" }
	local function light(name, brightness, angle, range)
		local item = ensure("ReplicatedStorage/CornFlashlightSettings/" .. name, "SpotLight")
		item.Brightness, item.Angle, item.Range = brightness, angle, range
		item.Enabled, item.Shadows = true, false
		item.Color, item.Face = roblox.Color3.new(1, 1, 1), roblox.Enum.NormalId.Front
		return item
	end
	state.wide, state.core = light("Wide", 2.08, 78, 18), light("Core", 22.62, 12, 24)
	state.controllers = paths["StarterPlayer/StarterPlayerScripts/GameClient/Controllers"]
	local services = {
		RunService = { IsStudio = function() return state.studio end, IsRunning = function() return state.running end },
		HttpService = { JSONDecode = function(_, value) return serde.decode("json", value) end },
		EncodingService = { ComputeStringHash = function(_, value)
			return (serde.hash("sha256", value):gsub("..", function(byte) return string.char(tonumber(byte, 16)) end))
		end },
		ScriptEditorService = { GetScriptDocuments = function() return state.documents end },
		ChangeHistoryService = { SetWaypoint = function() end },
	}
	function game:GetService(name) return assert(services[name], name) end
	state.game, state.map, state.bank, state.paths, state.make = game, map, bank, paths, make
	state.env = setmetatable({ game = game, workspace = world, Vector3 = roblox.Vector3, Color3 = roblox.Color3,
		Enum = { LightingStyle = { Realistic = "Realistic" }, NormalId = roblox.Enum.NormalId, HashAlgorithm = { Sha256 = "sha256" } },
		Instance = { new = function(class) return make(class, class) end } }, { __index = getfenv() })
	function state:run() return luau.load(code, { environment = self.env })() end
	function state:snapshot()
		local rows = {}
		for _, item in self.game:GetDescendants() do
			rows[item:GetFullName()] = { class = item.ClassName, source = item.Source, attrs = item:GetAttributes(), tags = item:GetTags(),
				shadows = item.Shadows, brightness = item.Brightness, angle = item.Angle, range = item.Range }
		end
		return serde.encode("json", rows)
	end
	return state
end

local positive = setup()
local result = positive:run()
check(result.created == 1 and result.changedProperties == 2 and positive.wide.Shadows and positive.core.Shadows, "Requested install failed")
local installed = assert(positive.controllers:FindFirstChild("CornShadowController"))
check(installed.Source == payload.source and #positive.game:GetDescendants() > 156, "Wrong added Source")
local repeated = positive:run()
check(repeated.created == 0 and repeated.changedProperties == 0 and repeated.repeated, "Repeat was not idempotent")

local guards = {
	function(s) s.game.Name = "Game" end,
	function(s) s.running = true end,
	function(s) s.studio = false end,
	function(s) s.map.attrs.HarvestArtVariant = "A" end,
	function(s) s.map.attrs.corn_project_id = "other" end,
	function(s) s.map.Ground.Size = roblox.Vector3.new(1, 2, 1) end,
	function(s) s.game.Lighting.GlobalShadows = false end,
	function(s) s.paths["ReplicatedStorage/GameShared/Game/HarvestWardenVisual"].Source ..= "--manual" end,
	function(s) s.paths["Workspace/CornfieldFog/Config"]:Destroy() end,
	function(s) s.make("Script", "Foreign", s.game) end,
	function(s) local old = s.paths["ReplicatedStorage/GameShared/Game/HarvestWardenVisual"]; local duplicate = s.make(old.ClassName,old.Name,old.Parent); duplicate.Source = old.Source end,
	function(s) s.wide.Shadows = true end,
	function(s) s.wide.Brightness = 4 end,
	function(s) s.bank.attrs.Pitch = -4 end,
	function(s) s.wide.tags = { "foreign" } end,
	function(s) local item = s.make("ModuleScript","CornShadowController",s.controllers); item.Source = "--manual" end,
	function(s) s:run(); local item = s.controllers:FindFirstChild("CornShadowController"); item.attrs.Foreign = true end,
	function(s) s:run(); local item = s.controllers:FindFirstChild("CornShadowController"); s.documents = { { GetScript = function() return item end } } end,
	function(s) s:run(); s.core.Shadows = false end,
}
for _, mutate in guards do
	local state = setup()
	mutate(state)
	local before = state:snapshot()
	check(not pcall(function() state:run() end), "Unsafe installer state accepted")
	check(state:snapshot() == before, "Refusal mutated the scene")
	refused += 1
end
for _, fault in { "source", "wide", "core", "parent" } do
	local state = setup()
	local before = state:snapshot()
	state.fault = fault
	check(not pcall(function() state:run() end) and state.faulted, "Expected injected write failure")
	check(state:snapshot() == before and not state.controllers:FindFirstChild("CornShadowController"), "Write failure did not rollback")
	rolled += 1
end
print(string.format("corn-shadows-installer PASS (%d assertions, %d refusals, %d rollback points)", cases, refused, rolled))
