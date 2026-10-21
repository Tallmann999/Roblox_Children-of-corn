-- Execute the actual factory against a faulting native-API adapter; no scene is saved.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local luau = require("@lune/luau")
local process = require("@lune/process")
local code = fs.readFile("scripts/maze02-refine-native-core.luau")
local baselineBytes = require("../scripts/read-maze02-refine-baseline").Read()
local baseline = roblox.deserializePlace(baselineBytes)
local sourceRecords, sourceSpecs = {}, {}
for _, item in baseline:GetDescendants() do
	if item:IsA("LuaSourceContainer") then
		local path, source = item:GetFullName():gsub("%.", "/"), item.Source:gsub("\r\n", "\n")
		sourceRecords[path] = { class = item.ClassName, source = source }
		sourceSpecs[path] = { class = item.ClassName, sha256 = serde.hash("sha256", source) }
	end
end
local assertions, refusals, rollbacks = 0, 0, 0
local function check(value, message)
	assertions += 1
	assert(value, message)
end
local function copy(value)
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, item in value do
		result[key] = copy(item)
	end
	return result
end
local function vector(x, y, z)
	return { kind = "Vector3", value = { x, y, z } }
end
local function frame(x, y, z)
	return { kind = "CFrame", value = { x, y, z, 1, 0, 0, 0, 1, 0, 0, 0, 1 } }
end
local function setup()
	local state = { running = false, studio = true, paths = {}, yields = 0 }
	local methods = {}
	local function make(class, name, parent)
		local values = { ClassName = class, Name = name, Archivable = true }
		if class == "Part" then
			values.Size, values.CFrame = roblox.Vector3.new(4, 1, 2), roblox.CFrame.new()
			values.Transparency, values.Anchored = 0, false
			values.CanCollide, values.CanQuery, values.CanTouch, values.CastShadow =
				true, true, true, true
			values.Material = roblox.Enum.Material.Plastic
		end
		local item = { values = values, attrs = {}, tags = {}, children = {} }
		setmetatable(item, {
			__index = function(self, key)
				return methods[key] or self.values[key]
			end,
			__newindex = function(self, key, value)
				if key == "Parent" then
					local previous = self.values.Parent
					if previous then
						table.remove(previous.children, assert(table.find(previous.children, self)))
					end
					if value then
						table.insert(value.children, self)
					end
				end
				self.values[key] = value
			end,
		})
		item.Parent = parent
		return item
	end
	function methods:IsA(class)
		return self.ClassName == class
			or (
					class == "LuaSourceContainer"
					and ({ Script = true, LocalScript = true, ModuleScript = true })[self.ClassName]
				)
				== true
	end
	function methods:GetChildren()
		return table.clone(self.children)
	end
	function methods:GetDescendants()
		local result = {}
		local function visit(parent)
			for _, child in parent.children do
				result[#result + 1] = child
				visit(child)
			end
		end
		visit(self)
		return result
	end
	function methods:GetFullName()
		if not self.Parent or self.Parent.ClassName == "DataModel" then
			return self.Name
		end
		return self.Parent:GetFullName() .. "." .. self.Name
	end
	function methods:FindFirstChild(name)
		for _, child in self.children do
			if child.Name == name then
				return child
			end
		end
		return nil
	end
	function methods:GetAttribute(name)
		return self.attrs[name]
	end
	function methods:GetAttributes()
		return table.clone(self.attrs)
	end
	function methods:SetAttribute(name, value)
		self.attrs[name] = value
	end
	function methods:GetTags()
		return table.clone(self.tags)
	end
	function methods:AddTag(tag)
		self.tags[#self.tags + 1] = tag
	end
	function methods:Destroy()
		for _, child in self:GetChildren() do
			child:Destroy()
		end
		self.Parent = nil
	end
	local game = make("DataModel", "Children_of_corn_B.rbxl")
	local function ensure(path, class)
		if state.paths[path] then
			if class then
				state.paths[path].ClassName = class
			end
			return state.paths[path]
		end
		local prefix, name = path:match("^(.*)/([^/]+)$")
		local item = make(class or "Folder", name or path, if prefix then ensure(prefix) else game)
		state.paths[path] = item
		return item
	end
	for path, record in sourceRecords do
		ensure(path, record.class).Source = record.source
	end
	local map = ensure("Workspace/CornMap", "Model")
	map.attrs = { corn_project_id = "children_of_corn", HarvestArtVariant = "B" }
	ensure("Workspace/CornMap/Ground", "Part").Size = roblox.Vector3.new(630, 2, 630)
	ensure("Workspace/CornMap/FieldZone", "Part").Size = roblox.Vector3.new(630, 10, 630)
	ensure("Workspace/CornMap/NoCornZones")
	local road = ensure("Workspace/CornMap/Props/VillageRoad/RoadSurface", "Part")
	road.CFrame = roblox.CFrame.new(0, 80, 0)
	local services = {
		RunService = {
			IsStudio = function()
				return state.studio
			end,
			IsRunning = function()
				return state.running
			end,
		},
		EncodingService = {
			ComputeStringHash = function(_, value)
				return (
					serde.hash("sha256", value):gsub("..", function(byte)
						return string.char(tonumber(byte, 16))
					end)
				)
			end,
		},
		ChangeHistoryService = { SetWaypoint = function() end },
	}
	function game:GetService(name)
		return assert(services[name], name)
	end
	local changedSources = {}
	for _, path in
		{
			"ReplicatedStorage/GameShared/Game/CornLayout",
			"StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornController",
			"StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornBackdropController",
			"StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornShadowController",
		}
	do
		local before = sourceRecords[path].source
		local after = before .. "\n-- Refine fixture source\n"
		changedSources[path] = {
			before_sha256 = serde.hash("sha256", before),
			after_sha256 = serde.hash("sha256", after),
			source = after,
		}
	end
	local preview = ensure("Workspace/CornMap/EditorPreview", "Folder")
	local corn1, corn2 = make("Part", "Corn", preview), make("Part", "Corn", preview)
	corn1.CFrame, corn2.CFrame = roblox.CFrame.new(1, 80, 4), roblox.CFrame.new(2, 80, 4)
	corn1.CastShadow, corn2.CastShadow = false, false
	state.corn1, state.corn2 = corn1, corn2
	local literal = make("Part", "Coat.001", ensure("Workspace/AuthorProps"))
	literal.CastShadow = false
	state.literal = literal
	state.documents = {}
	services.ScriptEditorService = {
		GetScriptDocuments = function()
			return state.documents
		end,
	}
	state.payload = {
		owner = "corn_maze02_refine_v1",
		sources = copy(sourceSpecs),
		sourceChanges = changedSources,
		expectedWorkspaceDescendants = #state.paths.Workspace:GetDescendants(),
		changes = {
			{
				path = "Workspace/CornMap/Props/VillageRoad/RoadSurface",
				property = "CFrame",
				attribute = false,
				before = frame(0, 80, 0),
				after = frame(0, 80, 100),
			},
			{
				path = "Workspace/CornMap",
				property = "RefineVersion",
				attribute = true,
				before = { kind = "Nil" },
				after = 1,
			},
			{
				path = "Workspace/CornMap/EditorPreview/Corn",
				selector = { CFrame = frame(1, 80, 4) },
				installedSelector = { CFrame = frame(1, 80, 4) },
				property = "CastShadow",
				attribute = false,
				before = false,
				after = true,
			},
			{
				path = "Workspace/AuthorProps/Coat/001",
				property = "CastShadow",
				attribute = false,
				before = false,
				after = true,
			},
		},
		guards = {
			{
				path = "Workspace/CornMap",
				class = "Model",
				properties = { Archivable = true },
				attributes = { corn_project_id = "children_of_corn", HarvestArtVariant = "B" },
				tags = {},
			},
			{
				path = "Workspace/CornMap/Props/VillageRoad/RoadSurface",
				class = "Part",
				properties = { Archivable = true, CFrame = frame(0, 80, 0), Size = vector(4, 1, 2) },
				attributes = {},
				tags = {},
			},
			{
				path = "Workspace/CornMap/EditorPreview/Corn",
				selector = { CFrame = frame(1, 80, 4) },
				installedSelector = { CFrame = frame(1, 80, 4) },
				class = "Part",
				properties = {
					CastShadow = false,
					CFrame = frame(1, 80, 4),
					Size = vector(4, 1, 2),
				},
				attributes = {},
				tags = {},
			},
			{
				path = "Workspace/CornMap/EditorPreview/Corn",
				selector = { CFrame = frame(2, 80, 4) },
				installedSelector = { CFrame = frame(2, 80, 4) },
				class = "Part",
				properties = {
					CastShadow = false,
					CFrame = frame(2, 80, 4),
					Size = vector(4, 1, 2),
				},
				attributes = {},
				tags = {},
			},
			{
				path = "Workspace/AuthorProps/Coat/001",
				class = "Part",
				properties = { CastShadow = false, CFrame = frame(0, 0, 0), Size = vector(4, 1, 2) },
				attributes = {},
				tags = {},
			},
		},
	}
	local env = setmetatable({
		game = game,
		workspace = state.paths.Workspace,
		Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		Enum = setmetatable({ HashAlgorithm = { Sha256 = "sha256" } }, { __index = roblox.Enum }),
		Instance = {
			new = function(class)
				return make(class, class)
			end,
		},
		task = {
			wait = function()
				state.yields += 1
			end,
		},
	}, { __index = getfenv() })
	state.factory = luau.load(code, { environment = env })()
	state.game, state.map, state.road, state.make, state.ensure = game, map, road, make, ensure
	function state:run(options)
		return self.factory(self.payload, options)
	end
	function state:snapshot()
		local rows, occurrences = {}, {}
		for _, item in game:GetDescendants() do
			local values = {}
			for key, value in item.values do
				if key ~= "Parent" then
					values[key] = if typeof(value) == "Vector3"
							or typeof(value) == "CFrame"
							or typeof(value) == "EnumItem"
						then tostring(value)
						else value
				end
			end
			local path = item:GetFullName()
			occurrences[path] = (occurrences[path] or 0) + 1
			rows[path .. "#" .. occurrences[path]] =
				{ values = values, attrs = item:GetAttributes(), tags = item:GetTags() }
		end
		return serde.encode("json", rows)
	end
	return state
end

local positive = setup()
local baselineSnapshot = positive:snapshot()
local dry = positive:run({ dryRun = true })
check(
	dry.state == "baseline"
		and dry.plannedChanges == 4
		and dry.plannedSourceChanges == 4
		and dry.retainedSources == 157
		and positive:snapshot() == baselineSnapshot,
	"Dry run changed scene"
)
local report = positive:run()
check(
	report.created == 0 and report.changedProperties == 4 and report.changedSources == 4,
	"Install counts differ"
)
check(
	positive.road.CFrame == roblox.CFrame.new(0, 80, 100)
		and positive.corn1.CastShadow
		and not positive.corn2.CastShadow
		and positive.literal.CastShadow,
	"Duplicate/literal-name targets differ"
)
local installedSnapshot = positive:snapshot()
local repeated = positive:run()
check(
	repeated.repeated
		and repeated.changedProperties == 0
		and repeated.changedSources == 0
		and positive:snapshot() == installedSnapshot,
	"Repeat wrote to scene"
)
check(
	positive:run({ dryRun = true }).state == "installed"
		and positive:snapshot() == installedSnapshot,
	"Installed dry run changed scene"
)

local guardCases = {
	function(s)
		s.game.Name = "Showroom.rbxlx"
	end,
	function(s)
		s.running = true
	end,
	function(s)
		s.studio = false
	end,
	function(s)
		s.map.attrs.HarvestArtVariant = "A"
	end,
	function(s)
		s.map.attrs.corn_project_id = "other"
	end,
	function(s)
		s.paths["Workspace/CornMap/Ground"].Size = roblox.Vector3.one
	end,
	function(s)
		s.payload.owner = "unknown"
	end,
	function(s)
		s.payload.nodes = { { path = "Workspace/New", class = "Part" } }
	end,
	function(s)
		s.paths["ReplicatedStorage/GameShared/Game/HarvestWardenVisual"].Source ..= "--Author"
	end,
	function(s)
		s.paths["ReplicatedStorage/GameShared/Game/CornLayout"].Source ..= "--Author"
	end,
	function(s)
		s.paths["Workspace/CornfieldFog/Config"]:Destroy()
	end,
	function(s)
		s.make("Script", "Author", s.game).Source = "Author"
	end,
	function(s)
		s.make("Part", "Author", s.paths.Workspace)
	end,
	function(s)
		local item = s.paths["Workspace/CornfieldFog/Config"]
		s.make(item.ClassName, item.Name, item.Parent).Source = item.Source
	end,
	function(s)
		s.road.CFrame = roblox.CFrame.new(1, 80, 100)
	end,
	function(s)
		s.road.CFrame = roblox.CFrame.new(0, 80, 100)
	end,
	function(s)
		local path = next(s.payload.sourceChanges)
		s.paths[path].Source = s.payload.sourceChanges[path].source
	end,
	function(s)
		s.road.Size = roblox.Vector3.new(1, 1, 1)
	end,
	function(s)
		s.road.attrs.Author = true
	end,
	function(s)
		s.road.tags = { "Author" }
	end,
	function(s)
		s.corn2.CFrame = s.corn1.CFrame
	end,
	function(s)
		s.payload.changes[#s.payload.changes + 1] = copy(s.payload.changes[1])
	end,
	function(s)
		s.payload.changes[1].property = "Source"
	end,
	function(s)
		s.payload.changes[1].path = "ReplicatedStorage/GameShared/Game/CornLayout"
	end,
	function(s)
		s.payload.changes[1].after = s.payload.changes[1].before
	end,
	function(s)
		table.remove(s.payload.guards, 2)
	end,
	function(s)
		s.payload.guards[2].properties.CFrame = nil
	end,
	function(s)
		s.payload.sourceChanges["ReplicatedStorage/GameShared/Game/HarvestWardenVisual"] =
			{ before_sha256 = "x", after_sha256 = "y", source = "z" }
	end,
	function(s)
		local path = next(s.payload.sourceChanges)
		s.payload.sourceChanges[path].source ..= "foreign"
	end,
	function(s)
		local path = next(s.payload.sourceChanges)
		s.payload.sourceChanges[path].before_sha256 = string.rep("0", 64)
	end,
	function(s)
		local path = next(s.payload.sourceChanges)
		s.payload.sourceChanges[path].source = "\r\n"
	end,
	function(s)
		local path = next(s.payload.sourceChanges)
		s.documents = { {
			GetScript = function()
				return s.paths[path]
			end,
		} }
	end,
}
for index, mutate in guardCases do
	local s = setup()
	mutate(s)
	local before = s:snapshot()
	local ok = pcall(function()
		s:run()
	end)
	check(not ok, "Unsafe mutation accepted: " .. index)
	check(s:snapshot() == before, "Refusal lost author edit: " .. index)
	refusals += 1
end
for point = 1, 8 do
	local s = setup()
	local before = s:snapshot()
	check(not pcall(function()
		s:run({ failAfterWrites = point })
	end), "Write failure not injected")
	check(s:snapshot() == before, "Source/world rollback differed at" .. point)
	check(s:run({ dryRun = true }).state == "baseline", "Rollback left a partial phase")
	rollbacks += 1
end
local concurrent = setup()
check(not pcall(function()
	concurrent:run({
		prepareYield = function()
			concurrent.road.Size = roblox.Vector3.new(3, 1, 2)
		end,
	})
end), "Concurrent author mutation accepted")
check(
	concurrent.road.Size == roblox.Vector3.new(3, 1, 2)
		and concurrent.paths["ReplicatedStorage/GameShared/Game/CornLayout"].Source
			== sourceRecords["ReplicatedStorage/GameShared/Game/CornLayout"].source,
	"Concurrent author mutation overwritten"
)
refusals += 1
local installedAuthor = setup()
installedAuthor:run()
installedAuthor.road.attrs.Author = true
local authorSnapshot = installedAuthor:snapshot()
check(not pcall(function()
	installedAuthor:run()
end) and installedAuthor:snapshot() == authorSnapshot, "Installed author edit overwritten")
refusals += 1
print(
	serde.encode(
		"json",
		{ passed = true, assertions = assertions, refusals = refusals, rollbackPoints = rollbacks }
	)
)

local fullPayloadPath = ".artifacts/playtests/2026-10-21-maze02-refine/payload.json"
if fs.isFile(fullPayloadPath) then
	local fullPayload = serde.decode("json", fs.readFile(fullPayloadPath))
	local function realSetup()
		local scene = roblox.deserializePlace(baselineBytes)
		scene.Name = "Children_of_corn_B.rbxl"
		local guardIndex = {}
		for _, row in fullPayload.guards do
			if row.attributes.FarmUniformScale then
				guardIndex[row.path] = row
			end
		end
		-- Lune omits TextureContent -> TextureID getters. Harvest independently
		-- seals its baseline URI in an existing serialized attribute.
		for _, item in scene:GetDescendants() do
			local editorCorn = item.Parent
				and (
					item.Parent.Name == "EditorPreview"
					or item.Parent.Name == "EditorFieldOverview"
				)
			local row = guardIndex[item:GetFullName():gsub("%.", "/")]
			if row then
				local original, nativeJson =
					item:GetAttribute("FarmUniformScale"), row.attributes.FarmUniformScale
				if original ~= nativeJson then
					assert(
						type(original) == "number"
							and type(nativeJson) == "number"
							and math.abs(original - nativeJson)
								<= math.max(math.abs(original), math.abs(nativeJson)) * 2 ^ -52,
						"Farm scale differs beyond one JSON float ULP"
					)
					-- Emulate native JSONDecode's one-ULP decimal conversion only in this reader adapter.
					item:SetAttribute("FarmUniformScale", nativeJson)
				end
			end
			if item:IsA("MeshPart") and not pcall(function()
				return item.TextureID
			end) then
				item.TextureID = item:GetAttribute("HarvestTexture")
					or (
						if item:GetAttribute("CornFarmMeshOwned") == true
							then "rbxassetid://95855894892409"
							elseif editorCorn then "rbxassetid://103653296385119"
							else ""
					)
			end
			if item:IsA("MeshPart") and not pcall(function()
				return item.MeshId
			end) then
				item.MeshId = if editorCorn then "rbxassetid://104111861186519" else ""
			end
		end
		local services = {
			RunService = {
				IsStudio = function()
					return true
				end,
				IsRunning = function()
					return false
				end,
			},
			EncodingService = {
				ComputeStringHash = function(_, value)
					return (
						serde.hash("sha256", value):gsub("..", function(byte)
							return string.char(tonumber(byte, 16))
						end)
					)
				end,
			},
			ChangeHistoryService = { SetWaypoint = function() end },
			ScriptEditorService = {
				GetScriptDocuments = function()
					return {}
				end,
			},
		}
		-- Lune's old Part.Size setter snaps very thin parts to 1/65536 studs;
		-- Studio preserves the native float32 value. Adapt only Size writes while
		-- every other property and all topology use the real imported Instances.
		local wrappers, actuals, sizeWrites, frameWrites, attributeWrites = {}, {}, {}, {}, {}
		local wrap
		local function wrappedList(items)
			local result = {}
			for _, item in items do
				result[#result + 1] = wrap(item)
			end
			return result
		end
		wrap = function(actual)
			if not actual then
				return nil
			end
			if wrappers[actual] then
				return wrappers[actual]
			end
			local wrapper = {}
			wrappers[actual], actuals[wrapper] = wrapper, actual
			setmetatable(wrapper, {
				__index = function(_, key)
					if key == "SetAttribute" then
						return function(_, name, value)
							local writes = attributeWrites[actual]
							if not writes then
								writes = {}
								attributeWrites[actual] = writes
							end
							writes[name] = { value = value }
							actual:SetAttribute(name, value)
						end
					end
					if key == "GetAttribute" then
						return function(_, name)
							local written = attributeWrites[actual]
								and attributeWrites[actual][name]
							if written then
								return written.value
							end
							return actual:GetAttribute(name)
						end
					end
					if key == "GetAttributes" then
						return function()
							local attrs = actual:GetAttributes()
							for name, written in attributeWrites[actual] or {} do
								attrs[name] = written.value
							end
							return attrs
						end
					end
					if key == "Size" and sizeWrites[actual] then
						return sizeWrites[actual]
					end
					if key == "CFrame" and frameWrites[actual] then
						return frameWrites[actual]
					end
					if key == "Parent" then
						return wrap(actual.Parent)
					end
					if key == "GetChildren" or key == "GetDescendants" then
						return function()
							return wrappedList(actual[key](actual))
						end
					end
					local value = actual[key]
					if type(value) == "function" then
						return function(_, ...)
							return value(actual, ...)
						end
					end
					return value
				end,
				__newindex = function(_, key, value)
					if key == "Size" then
						sizeWrites[actual] = value
					elseif key == "CFrame" then
						frameWrites[actual] = value
					else
						actual[key] = actuals[value] or value
					end
				end,
			})
			return wrapper
		end
		local proxy = { Name = scene.Name }
		function proxy:GetChildren()
			return wrappedList(scene:GetChildren())
		end
		function proxy:GetDescendants()
			return wrappedList(scene:GetDescendants())
		end
		function proxy:GetService(name)
			return assert(services[name], name)
		end
		local env = setmetatable({
			game = proxy,
			workspace = scene:GetService("Workspace"),
			Vector3 = roblox.Vector3,
			CFrame = roblox.CFrame,
			Color3 = roblox.Color3,
			Enum = setmetatable(
				{ HashAlgorithm = { Sha256 = "sha256" } },
				{ __index = roblox.Enum }
			),
			Instance = {
				new = function(class)
					return wrap(roblox.Instance.new(class))
				end,
			},
			task = { wait = function() end },
		}, { __index = getfenv() })
		local factory = luau.load(code, { environment = env })()
		local function fullSnapshot()
			local rows, occurrences = {}, {}
			for _, item in proxy:GetDescendants() do
				local path = item:GetFullName()
				occurrences[path] = (occurrences[path] or 0) + 1
				local props = {}
				if item:IsA("BasePart") then
					for _, property in
						{
							"CFrame",
							"Size",
							"Transparency",
							"CanCollide",
							"CanQuery",
							"CanTouch",
							"CastShadow",
						}
					do
						props[property] = tostring(item[property])
					end
				end
				local attrs = {}
				for name, value in item:GetAttributes() do
					attrs[name] = tostring(value)
				end
				rows[path .. "#" .. occurrences[path]] = {
					class = item.ClassName,
					properties = props,
					attributes = attrs,
					tags = item:GetTags(),
					source = if item:IsA("LuaSourceContainer") then item.Source else nil,
				}
			end
			return serde.encode("json", rows)
		end
		return factory, fullSnapshot
	end
	local fullFactory, fullSnapshot = realSetup()
	local fullBefore = fullSnapshot()
	local fullDry = fullFactory(fullPayload, { dryRun = true })
	check(
		fullDry.state == "baseline"
			and fullDry.plannedChanges == 4054
			and fullDry.plannedSourceChanges == 4
			and fullDry.guardedInstances == 4315
			and fullSnapshot() == fullBefore,
		"Full refine dry run failed"
	)
	local fullResult = fullFactory(fullPayload)
	check(
		fullResult.created == 0
			and fullResult.changedProperties == 4054
			and fullResult.changedSources == 4,
		"Full refine install failed"
	)
	local fullInstalled = fullSnapshot()
	check(
		fullFactory(fullPayload).repeated and fullSnapshot() == fullInstalled,
		"Full refine repeat wrote"
	)
	check(
		fullFactory(fullPayload, { dryRun = true }).state == "installed"
			and fullSnapshot() == fullInstalled,
		"Full installed dry run wrote"
	)
	for _, point in { 4, 4058 } do
		local rollbackFactory, rollbackSnapshot = realSetup()
		local rollbackBefore = rollbackSnapshot()
		check(not pcall(function()
			rollbackFactory(fullPayload, { failAfterWrites = point })
		end), "Full injected failure missed")
		check(
			rollbackSnapshot() == rollbackBefore,
			"Full Source/world rollback differed at" .. point
		)
		check(
			rollbackFactory(fullPayload, { dryRun = true }).state == "baseline",
			"Full rollback left partial state"
		)
		rollbacks += 1
	end
	print("maze02-refine full payload PASS (4054 world changes, 4 Sources, 4315 guards)")
end
print(
	serde.encode(
		"json",
		{ passed = true, assertions = assertions, refusals = refusals, rollbackPoints = rollbacks }
	)
)
