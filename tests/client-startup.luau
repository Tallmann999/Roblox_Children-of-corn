-- Actual client Bootstrap with a deterministic replication clock and API-shaped Instances.
-- Verifies readiness/timeout/UI lifecycle and controller order, not Roblox networking/rendering.
local fs = require("@lune/fs")
local r = require("@lune/roblox")
local EndpointNames = assert(
	loadstring(fs.readFile("src/shared/Network/EndpointNames.luau")),
	"EndpointNames compile failed"
)()
local PROJECT = "children_of_corn"
local methods = {}
local function node(state, class, name)
	local object = setmetatable({
		_state = state,
		_children = {},
		_attributes = {},
		_values = { ClassName = class, Name = name or class },
	}, {
		__index = function(self, key)
			return methods[key] or self._values[key]
		end,
		__newindex = function(self, key, value)
			if key == "Parent" then
				local previous = self._values.Parent
				if previous then
					local index = table.find(previous._children, self)
					if index then
						table.remove(previous._children, index)
					end
				end
				if value then
					table.insert(value._children, self)
				end
			end
			self._values[key] = value
		end,
	})
	return object
end
function methods:IsA(class)
	return self.ClassName == class
		or (class == "LuaSourceContainer" and (self.ClassName == "Script" or self.ClassName == "LocalScript" or self.ClassName == "ModuleScript"))
		or (class == "BasePart" and (self.ClassName == "Part" or self.ClassName == "MeshPart"))
end
function methods:GetAttribute(name)
	return self._attributes[name]
end
function methods:SetAttribute(name, value)
	self._attributes[name] = value
end
function methods:GetAttributes()
	return table.clone(self._attributes)
end
function methods:GetChildren()
	return table.clone(self._children)
end
function methods:GetDescendants()
	local result = {}
	local function visit(parent)
		for _, child in parent._children do
			table.insert(result, child)
			visit(child)
		end
	end
	visit(self)
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
function methods:WaitForChild(name, timeout)
	local ready = self:FindFirstChild(name)
	if ready then
		return ready
	end
	assert(
		type(timeout) == "number" and timeout >= 0,
		"Startup used unbounded WaitForChild for " .. self.Name .. "/" .. name
	)
	local started = self._state.now
	while self._state.now - started < timeout do
		self._state:advance(math.min(0.1, timeout - (self._state.now - started)))
		ready = self:FindFirstChild(name)
		if ready then
			return ready
		end
	end
	return nil
end
function methods:GetFullName()
	return self.Parent and self.Parent:GetFullName() .. "." .. self.Name or self.Name
end
function methods:Destroy()
	for _, child in self:GetChildren() do
		child:Destroy()
	end
	self.Parent = nil
	self.Destroyed = true
end
local function child(state, parent, class, name)
	local object = node(state, class, name)
	object.Parent = parent
	return object
end
local function fixture()
	local state = {
		now = 0,
		events = {},
		warnings = {},
		created = {},
		infos = {},
		requiredControllers = 0,
		initialized = 0,
		started = 0,
		loadingSeen = false,
	}
	state.storage, state.world =
		node(state, "ReplicatedStorage", "ReplicatedStorage"), node(state, "Workspace", "Workspace")
	state.player = node(state, "Player", "TestPlayer")
	state.gui = child(state, state.player, "PlayerGui", "PlayerGui")
	state.foreign = child(state, state.gui, "ScreenGui", "AuthorInventory")
	state.foreign.Enabled, state.foreign.DisplayOrder, state.foreign.ResetOnSpawn = true, 77, false
	state.foreign:SetAttribute("author_marker", "preserve")
	state.foreignLabel = child(state, state.foreign, "TextLabel", "InventoryCount")
	state.foreignLabel.Text, state.foreignLabel.Visible = "Авторский GUI", true
	local shared = child(state, state.storage, "Folder", "GameShared")
	local config = child(state, shared, "Folder", "Config")
	local configModule = child(state, config, "ModuleScript", "GameConfig")
	configModule.ModuleValue =
		{ Debug = true, Environment = "DEV", Game = { Id = PROJECT, SessionMode = "solo_local" } }
	local network = child(state, shared, "Folder", "Network")
	child(state, network, "ModuleScript", "EndpointNames").ModuleValue = EndpointNames
	local core = child(state, shared, "Folder", "Core")
	child(state, core, "ModuleScript", "Logger").ModuleValue = {
		new = function()
			return {
				Info = function(_, ...)
					table.insert(state.infos, { ... })
				end,
				Warn = function(_, ...)
					table.insert(state.warnings, { ... })
				end,
			}
		end,
	}
	state.map = child(state, state.world, "Model", "CornMap")
	state.map:SetAttribute("corn_project_id", PROJECT)
	local field = child(state, state.map, "Part", "FieldZone")
	field.CFrame, field.Size = r.CFrame.new(), r.Vector3.new(840, 10, 840)
	local client = node(state, "Folder", "GameClient")
	state.script = child(state, client, "LocalScript", "Bootstrap")
	local controllers = child(state, client, "Folder", "Controllers")
	local function controller(name, order)
		local module = child(state, controllers, "ModuleScript", name)
		module.IsController = true
		module.ModuleValue = {
			Name = name,
			Order = order,
			Init = function(_, context)
				assert(state:ready(), "Controller Init ran before prepared inputs")
				assert(
					context.Controllers.First
						and context.Controllers.Second
						and context.Controllers.Last,
					"Controller context lacks peers"
				)
				state.initialized += 1
				table.insert(state.events, "init:" .. name)
			end,
			Start = function()
				assert(
					state:ready() and state.initialized == 3,
					"Controller Start ran before all Init/readiness"
				)
				state.started += 1
				table.insert(state.events, "start:" .. name)
			end,
		}
	end
	controller("Last", 100)
	controller("First", 10)
	controller("Second", 40)
	child(state, controllers, "Folder", "NotAController")
	function state:remotes(class)
		local folder = self.storage:FindFirstChild("GameRemotes")
			or child(self, self.storage, class or "Folder", "GameRemotes")
		return folder
	end
	function state:event(name, class)
		local folder = self:remotes()
		return folder:FindFirstChild(name) or child(self, folder, class or "RemoteEvent", name)
	end
	function state:allRemotes()
		for _, name in EndpointNames do
			self:event(name)
		end
	end
	function state:art(class)
		return self.storage:FindFirstChild("CornRuntimeArt")
			or child(self, self.storage, class or "Folder", "CornRuntimeArt")
	end
	function state:template(class)
		local art = self:art()
		return art:FindFirstChild("CornPlantTemplate")
			or child(self, art, class or "MeshPart", "CornPlantTemplate")
	end
	function state:allArt()
		local art = self:art()
		art:SetAttribute("CornRuntimeArtOwned", true)
		art:SetAttribute("corn_project_id", PROJECT)
		local template = self:template()
		template:SetAttribute("CornPlantTemplateOwned", true)
		template:SetAttribute("CornPlantHeight", 8)
		template.MeshId, template.TextureID =
			"rbxassetid://104111861186519", "rbxassetid://137803536172445"
		template.Size, template.CFrame = r.Vector3.new(3, 8, 3), r.CFrame.new()
		template.Anchored, template.CanCollide, template.CanTouch, template.CanQuery, template.Archivable =
			true, false, false, false, true
		return template
	end
	function state:ready()
		local remotes = self.storage:FindFirstChild("GameRemotes")
		if not remotes or not remotes:IsA("Folder") then
			return false
		end
		for _, name in EndpointNames do
			local event = remotes:FindFirstChild(name)
			if not event or not event:IsA("RemoteEvent") then
				return false
			end
		end
		local art = self.storage:FindFirstChild("CornRuntimeArt")
		local template = art and art:FindFirstChild("CornPlantTemplate")
		return art ~= nil
			and art:IsA("Folder")
			and art:GetAttribute("CornRuntimeArtOwned") == true
			and art:GetAttribute("corn_project_id") == PROJECT
			and template ~= nil
			and template:IsA("MeshPart")
			and template:GetAttribute("CornPlantTemplateOwned") == true
	end
	function state:advance(duration)
		assert(
			type(duration) == "number"
				and duration > 0
				and duration <= (self.allowOvershoot and 61 or 60),
			"Invalid startup wait"
		)
		self.now += duration
		assert(
			self.now <= (self.allowOvershoot and 61 or 60.15),
			"Startup exceeded shared sixty-second deadline"
		)
		if self.onTick then
			self.onTick(self)
		end
		for _, item in self.gui:GetDescendants() do
			if item:IsA("TextLabel") and item.Text == "Подготовка карты…" then
				self.loadingSeen = true
			end
		end
	end
	function state:run()
		local source = fs.readFile("src/client/Bootstrap.client.luau")
		local chunk = assert(loadstring(source), "Client Bootstrap compile failed")
		setfenv(
			chunk,
			setmetatable({
				game = {
					GetService = function(_, name)
						if name == "ReplicatedStorage" then
							return self.storage
						end
						if name == "Workspace" then
							return self.world
						end
						if name == "Players" then
							return { LocalPlayer = self.player }
						end
						if name == "RunService" then
							return {
								IsStudio = function()
									return true
								end,
							}
						end
						error("Unexpected Bootstrap service: " .. name)
					end,
				},
				workspace = self.world,
				script = self.script,
				Instance = {
					new = function(class)
						local object = node(self, class, class)
						table.insert(self.created, object)
						return object
					end,
				},
				Vector3 = r.Vector3,
				Vector2 = r.Vector2,
				UDim2 = r.UDim2,
				UDim = r.UDim,
				Color3 = r.Color3,
				Enum = r.Enum,
				os = setmetatable({
					clock = function()
						return self.now
					end,
				}, { __index = os }),
				time = function()
					return self.now
				end,
				task = {
					wait = function(duration)
						local elapsed = duration or 0.05
						if self.overshoot then
							elapsed += self.overshoot
							self.overshoot = nil
						end
						self:advance(elapsed)
						return elapsed
					end,
				},
				warn = function(...)
					table.insert(self.warnings, { ... })
				end,
				require = function(module)
					assert(module:IsA("ModuleScript"), "Bootstrap required non-ModuleScript")
					if module.IsController then
						assert(self:ready(), "Controller require ran before prepared inputs")
						self.requiredControllers += 1
						table.insert(self.events, "require:" .. module.Name)
					end
					return assert(module.ModuleValue, "Missing fixture module: " .. module.Name)
				end,
			}, { __index = getfenv() })
		)
		local ok, problem = pcall(chunk)
		self.ok, self.problem = ok, problem
		return ok, problem
	end
	return state
end
local function cleanup(state)
	assert(
		state.foreign.Parent == state.gui
			and not state.foreign.Destroyed
			and state.foreign.Enabled == true
			and state.foreign.DisplayOrder == 77
			and state.foreign.ResetOnSpawn == false
			and state.foreign:GetAttribute("author_marker") == "preserve",
		"Loading lifecycle changed author's ScreenGui"
	)
	assert(
		state.foreignLabel.Parent == state.foreign
			and not state.foreignLabel.Destroyed
			and state.foreignLabel.Text == "Авторский GUI"
			and state.foreignLabel.Visible,
		"Loading lifecycle changed author's TextLabel"
	)
	for _, item in state.created do
		if item:IsA("ScreenGui") then
			assert(
				item.Name == "ChildrenOfCornLoading"
					and item:GetAttribute("CornLoadingOwned") == true
					and item:GetAttribute("corn_project_id") == PROJECT,
				"Startup loading GUI identity/owner differs"
			)
			assert(item.Destroyed and item.Parent == nil, "Loading GUI leaked after ready/error")
		end
	end
	assert(#state.gui:GetChildren() == 1, "Bootstrap left extra PlayerGui objects")
end
local function success(state)
	assert(state.ok, "Bootstrap failed valid readiness: " .. tostring(state.problem))
	assert(
		state.requiredControllers == 3 and state.initialized == 3 and state.started == 3,
		"Controller lifecycle count differs"
	)
	local lifecycle = {}
	for _, event in state.events do
		if not event:match("^require:") then
			table.insert(lifecycle, event)
		end
	end
	assert(
		table.concat(lifecycle, ",")
			== "init:First,init:Second,init:Last,start:First,start:Second,start:Last",
		"Controller Init/Start order or stage separation changed"
	)
	cleanup(state)
end
local function failure(state)
	assert(
		not state.ok and type(state.problem) == "string",
		"Invalid readiness did not report a typed error"
	)
	assert(
		state.requiredControllers == 0 and state.initialized == 0 and state.started == 0,
		"Invalid readiness loaded/started controllers"
	)
	cleanup(state)
end

local delayed = fixture()
delayed.onTick = function(s)
	assert(
		s.requiredControllers == 0 and s.initialized == 0 and s.started == 0,
		"Partial replication initialized controllers"
	)
	if s.now >= 0.5 then
		s:event(EndpointNames.RoundSnapshot)
	end
	if s.now >= 1.0 then
		s:event(EndpointNames.RequestRoundAction)
	end
	if s.now >= 2.0 then
		s:event(EndpointNames.RequestSprintIntent)
	end
	if s.now >= 3.0 then
		s:art()
	end
	if s.now >= 4.0 then
		s:template()
	end
	if s.now >= 5.0 then
		s:allArt()
	end
	if s.now >= 5.5 then
		s:event(EndpointNames.RequestInventoryAction)
	end
end
delayed:run()
success(delayed)
assert(
	delayed.now >= 5.5 and delayed.loadingSeen,
	"Partial endpoints/art did not keep loading screen visible"
)
print(
	"PASS: partial endpoint/art replication waits for all four typed endpoints, including late inventory; owned complete inputs unlock all require/Init/Start in order; loading UI removed and author GUI exact"
)

local ready = fixture()
ready:allRemotes()
ready:allArt()
ready:run()
success(ready)
assert(ready.now == 0, "Already-ready inputs were delayed")

local missingInventory = fixture()
missingInventory:allRemotes()
missingInventory:allArt()
missingInventory:remotes():FindFirstChild(EndpointNames.RequestInventoryAction):Destroy()
missingInventory:run()
failure(missingInventory)
assert(
	missingInventory.now >= 60
		and missingInventory.now <= 60.15
		and missingInventory.loadingSeen
		and tostring(missingInventory.problem):find(EndpointNames.RequestInventoryAction, 1, true),
	"Missing fourth inventory endpoint did not wait to the shared deadline with exact diagnostic"
)
print(
	"PASS: missing fourth inventory endpoint blocks all controllers and reports its exact name at the shared deadline"
)

local timeout = fixture()
timeout.onTick = function(s)
	if s.now >= 55 then
		s:allRemotes()
		s:art()
	end
end
timeout:run()
failure(timeout)
assert(
	timeout.now >= 60 and timeout.now <= 60.15 and timeout.loadingSeen,
	"Resources used separate timeouts or did not show loading state"
)
assert(
	tostring(timeout.problem):find("Corn", 1, true),
	"Timeout error does not identify prepared Corn inputs"
)
print(
	"PASS: staggered remotes/art share one <=60-second deadline, timeout cleans loading UI and never requires controllers"
)

for _, kind in
	{
		"remotes_class",
		"event_class",
		"inventory_event_class",
		"art_class",
		"template_class",
		"art_owner",
		"art_project",
		"template_owner",
	}
do
	local invalid = fixture()
	invalid:allRemotes()
	invalid:allArt()
	if kind == "remotes_class" then
		invalid.storage:FindFirstChild("GameRemotes").ClassName = "Model"
	elseif kind == "event_class" then
		invalid:remotes():FindFirstChild(EndpointNames.RequestSprintIntent).ClassName =
			"RemoteFunction"
	elseif kind == "inventory_event_class" then
		invalid:remotes():FindFirstChild(EndpointNames.RequestInventoryAction).ClassName =
			"RemoteFunction"
	elseif kind == "art_class" then
		invalid:art().ClassName = "Model"
	elseif kind == "template_class" then
		invalid:template().ClassName = "Part"
	elseif kind == "art_owner" then
		invalid:art():SetAttribute("CornRuntimeArtOwned", false)
	elseif kind == "art_project" then
		invalid:art():SetAttribute("corn_project_id", "another_game")
	else
		invalid:template():SetAttribute("CornPlantTemplateOwned", false)
	end
	invalid:run()
	failure(invalid)
	if kind == "inventory_event_class" then
		assert(
			invalid.now == 0
				and tostring(invalid.problem):find(EndpointNames.RequestInventoryAction, 1, true),
			"Wrong fourth endpoint class did not refuse immediately with exact inventory diagnostic"
		)
	end
end
print(
	"PASS: wrong endpoint/art/template classes and foreign ownership never load controllers; all error paths preserve unrelated GUI"
)

local foreignName = fixture()
foreignName.foreign.Name = "ChildrenOfCornLoading"
foreignName:allRemotes()
foreignName:allArt()
foreignName:run()
success(foreignName)
assert(
	foreignName.foreign.Name == "ChildrenOfCornLoading",
	"Existing same-name author GUI was changed"
)

local lateGui = fixture()
lateGui.gui.Parent = nil
lateGui.onTick = function(s)
	if s.now >= 55 and s.gui.Parent == nil then
		s.gui.Parent = s.player
	end
	if s.now >= 58 then
		s:allRemotes()
	end
end
lateGui:run()
failure(lateGui)
assert(
	lateGui.now >= 60 and lateGui.now <= 60.15,
	"PlayerGui availability reset the shared startup deadline"
)

for _, kind in
	{
		"player_gui",
		"anchored",
		"collide",
		"touch",
		"query",
		"archivable",
		"size_zero",
		"size_infinite",
		"mesh_empty",
		"script",
		"sound",
		"particles",
		"prompt",
		"nested_remote",
	}
do
	local invalid = fixture()
	invalid:allRemotes()
	local template = invalid:allArt()
	if kind == "player_gui" then
		invalid.gui.ClassName = "Folder"
	elseif kind == "anchored" then
		template.Anchored = false
	elseif kind == "collide" then
		template.CanCollide = true
	elseif kind == "touch" then
		template.CanTouch = true
	elseif kind == "query" then
		template.CanQuery = true
	elseif kind == "archivable" then
		template.Archivable = false
	elseif kind == "size_zero" then
		template.Size = r.Vector3.new(0, 8, 3)
	elseif kind == "size_infinite" then
		template.Size = r.Vector3.new(math.huge, 8, 3)
	elseif kind == "mesh_empty" then
		template.MeshId = ""
	else
		local classes = {
			script = "Script",
			sound = "Sound",
			particles = "ParticleEmitter",
			prompt = "ProximityPrompt",
			nested_remote = "RemoteEvent",
		}
		child(invalid, template, classes[kind], "ForeignChild")
	end
	invalid:run()
	failure(invalid)
end
print(
	"PASS: one deadline includes late PlayerGui; same-name author GUI preserved; invalid template physics/geometry and active descendants refuse before controllers"
)

-- task.wait may resume after its requested duration; late readiness must still obey the total deadline.
for _, stage in { "inputs", "player_gui" } do
	local overslept = fixture()
	overslept.allowOvershoot, overslept.overshoot = true, 60.5
	if stage == "player_gui" then
		overslept.gui.Parent = nil
	end
	overslept.onTick = function(s)
		s.gui.Parent = s.player
		s:allRemotes()
		s:allArt()
	end
	overslept:run()
	failure(overslept)
	assert(
		overslept.now > 60
			and (
				tostring(overslept.problem):find("60", 1, true)
				or tostring(overslept.problem):find("deadline", 1, true)
			),
		"Oversleep was not rejected by actual shared deadline"
	)
end
print(
	"PASS: scheduler oversleep cannot unlock controllers after sixty seconds, including late PlayerGui arrival"
)

for _, duplicate in
	{
		"GameRemotes",
		"CornRuntimeArt",
		"CornPlantTemplate",
		EndpointNames.RoundSnapshot,
		EndpointNames.RequestInventoryAction,
	}
do
	local duplicated = fixture()
	duplicated:allRemotes()
	duplicated:allArt()
	local parent, class = duplicated.storage, "Folder"
	if duplicate == "CornPlantTemplate" then
		parent, class = duplicated:art(), "MeshPart"
	elseif
		duplicate == EndpointNames.RoundSnapshot
		or duplicate == EndpointNames.RequestInventoryAction
	then
		parent, class = duplicated:remotes(), "RemoteEvent"
	end
	child(duplicated, parent, class, duplicate)
	duplicated:run()
	failure(duplicated)
	assert(
		duplicated.now == 0 and tostring(duplicated.problem):find(duplicate, 1, true),
		"Duplicate binding lacked immediate exact diagnostic"
	)
end
print(
	"PASS: duplicate server bindings refuse immediately with exact names and preserve existing GUI"
)
