-- Execute the actual factory against a faulting native-API adapter; no scene is saved.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local luau = require("@lune/luau")
local process = require("@lune/process")
local code = fs.readFile("scripts/maze02-native-core.luau")
local baseline = roblox.deserializePlace(fs.readFile("place/Children_of_corn_B.rbxl"))
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
	local owner = { corn_project_id = "children_of_corn", CornMazeOwner = "corn_maze02_v1" }
	local nodes = {
		{
			path = "Workspace/CornMap/Maze02",
			class = "Folder",
			properties = { Archivable = true },
			attributes = copy(owner),
			tags = {},
		},
	}
	for index = 1, 65 do
		nodes[#nodes + 1] = {
			path = string.format("Workspace/CornMap/Maze02/Trail%03d", index),
			class = "Part",
			properties = {
				Archivable = true,
				Size = vector(6, 0.1, 12),
				CFrame = frame(index * 3, 80, 0),
				Anchored = true,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
				Transparency = 0,
				Material = { kind = "Enum", value = { "Material", "Ground" } },
			},
			attributes = copy(owner),
			tags = { "corn_maze_trail" },
		}
	end
	state.payload = {
		owner = "corn_maze02_v1",
		sources = copy(sourceSpecs),
		nodes = nodes,
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
				property = "MazeVersion",
				attribute = true,
				before = { kind = "Nil" },
				after = 2,
			},
		},
		guards = {
			{
				path = "Workspace/CornMap/Props/VillageRoad/RoadSurface",
				class = "Part",
				properties = { CFrame = frame(0, 80, 0), Size = vector(4, 1, 2), Archivable = true },
				attributes = {},
				tags = {},
			},
			{
				path = "Workspace/CornMap",
				class = "Model",
				properties = { Archivable = true },
				attributes = { corn_project_id = "children_of_corn", HarvestArtVariant = "B" },
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
if process.args[1] ~= "--full-only" then
	local positive = setup()
	local initialSnapshot = positive:snapshot()
	local dry = positive:run({ dryRun = true })
	check(
		dry.dryRun
			and dry.state == "baseline"
			and dry.plannedNodes == 66
			and positive:snapshot() == initialSnapshot,
		"Dry run wrote to scene"
	)
	local result = positive:run()
	check(
		result.created == 66 and result.changedProperties == 2 and positive.yields == 1,
		"Valid install failed"
	)
	check(
		positive.road.CFrame == roblox.CFrame.new(0, 80, 100)
			and positive.map:GetAttribute("MazeVersion") == 2,
		"Retained changes differ"
	)
	local installed = positive:snapshot()
	local repeatResult = positive:run()
	check(
		repeatResult.repeated
			and repeatResult.created == 0
			and repeatResult.changedProperties == 0
			and positive:snapshot() == installed,
		"Repeat changed world"
	)
	check(
		positive:run({ dryRun = true }).state == "installed" and positive:snapshot() == installed,
		"Installed dry run wrote"
	)

	local guards = {
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
			s.paths["Workspace/CornMap/Ground"].Size = roblox.Vector3.new(1, 2, 1)
		end,
		function(s)
			s.paths["ReplicatedStorage/GameShared/Game/HarvestWardenVisual"].Source ..= "--manual"
		end,
		function(s)
			s.paths["Workspace/CornfieldFog/Config"]:Destroy()
		end,
		function(s)
			s.make("Script", "Foreign", s.game).Source = "foreign"
		end,
		function(s)
			local item = s.paths["Workspace/CornfieldFog/Config"]
			s.make(item.ClassName, item.Name, item.Parent).Source = item.Source
		end,
		function(s)
			s.road.CFrame = roblox.CFrame.new(30, 80, 0)
		end,
		function(s)
			s.road.CFrame = roblox.CFrame.new(0, 80, 100)
		end,
		function(s)
			s.road.Size = roblox.Vector3.new(4, 2, 2)
		end,
		function(s)
			s.road.attrs.Author = true
		end,
		function(s)
			s.road.tags = { "author" }
		end,
		function(s)
			s.payload.nodes[2].path = "Workspace/CornMap/Other/Trail"
		end,
		function(s)
			s.payload.nodes[2].class = "Script"
		end,
		function(s)
			s.payload.nodes[2].attributes.CornMazeOwner = "foreign"
		end,
		function(s)
			s.payload.nodes[#s.payload.nodes + 1] = copy(s.payload.nodes[2])
		end,
		function(s)
			s.payload.changes[1].property = "Parent"
		end,
		function(s)
			s.payload.changes[1].after.value[1] = 0 / 0
		end,
		function(s)
			s.make("Folder", "Maze02", s.map)
		end,
		function(s)
			table.remove(s.payload.nodes, 1)
			s.make("Folder", "Maze02", s.map)
		end,
		function(s)
			s:run()
			s.make("Part", "Foreign", s.map:FindFirstChild("Maze02"))
		end,
		function(s)
			s:run()
			s.map:FindFirstChild("Maze02"):FindFirstChild("Trail001").Transparency = 0.5
		end,
		function(s)
			s:run()
			s.map:FindFirstChild("Maze02"):FindFirstChild("Trail001").attrs.Author = true
		end,
		function(s)
			s:run()
			s.map:FindFirstChild("Maze02"):FindFirstChild("Trail001").tags = { "other" }
		end,
		function(s)
			s:run()
			s.map:FindFirstChild("Maze02"):FindFirstChild("Trail001"):Destroy()
		end,
	}
	for _, mutate in guards do
		local state = setup()
		mutate(state)
		local before = state:snapshot()
		check(not pcall(function()
			state:run()
		end), "Unsafe state accepted")
		check(state:snapshot() == before, "Refusal mutated world")
		refusals += 1
	end
	for _, fault in { 1, 2, 32, 66, 67, 68 } do
		local state = setup()
		local before = state:snapshot()
		check(not pcall(function()
			state:run({ failAfterWrites = fault })
		end), "Write failure injection missed")
		check(
			state:snapshot() == before and not state.map:FindFirstChild("Maze02"),
			"Transaction failed to rollback"
		)
		rollbacks += 1
	end
	local concurrent = setup()
	local changed = false
	check(not pcall(function()
		concurrent:run({
			prepareYield = function()
				if not changed then
					concurrent.road.Size = roblox.Vector3.new(3, 1, 2)
					changed = true
				end
			end,
		})
	end), "Author mutation during preparation accepted")
	check(
		concurrent.road.Size == roblox.Vector3.new(3, 1, 2)
			and not concurrent.map:FindFirstChild("Maze02"),
		"Concurrent author edit lost"
	)

	local function barrels(state)
		local barrelItems = {}
		for index = 1, 3 do
			local item = state.make("Part", "LookoutBarrel", state.paths["Workspace/CornMap/Props"])
			item.CFrame = roblox.CFrame.new(index * 10, 80, 20)
			barrelItems[index] = item
			local row = {
				path = "Workspace/CornMap/Props/LookoutBarrel",
				property = "CFrame",
				attribute = false,
				before = frame(index * 10, 80, 20),
				after = frame(index * 10, 80, 30),
				selector = { CFrame = frame(index * 10, 80, 20) },
				installedSelector = { CFrame = frame(index * 10, 80, 30) },
			}
			state.payload.changes[#state.payload.changes + 1] = row
			state.payload.guards[#state.payload.guards + 1] = {
				path = row.path,
				class = "Part",
				properties = { CFrame = row.before, Size = vector(4, 1, 2) },
				attributes = {},
				tags = {},
				selector = row.selector,
				installedSelector = row.installedSelector,
			}
		end
		return barrelItems
	end
	local duplicateNames = setup()
	local barrelRefs = barrels(duplicateNames)
	check(duplicateNames:run().changedProperties == 5, "Exact duplicate-name selectors refused")
	for index, item in barrelRefs do
		check(
			item.CFrame == roblox.CFrame.new(index * 10, 80, 30),
			"Wrong duplicate-name target moved"
		)
	end
	local duplicateSnapshot = duplicateNames:snapshot()
	check(
		duplicateNames:run().repeated and duplicateNames:snapshot() == duplicateSnapshot,
		"Selector repeat failed"
	)
	local ambiguous = setup()
	local ambiguousRefs = barrels(ambiguous)
	ambiguousRefs[2].CFrame = ambiguousRefs[1].CFrame
	local ambiguousSnapshot = ambiguous:snapshot()
	check(not pcall(function()
		ambiguous:run()
	end) and ambiguous:snapshot() == ambiguousSnapshot, "Ambiguous selector mutated world")
	refusals += 1
	local selectorRollback = setup()
	barrels(selectorRollback)
	local selectorSnapshot = selectorRollback:snapshot()
	check(not pcall(function()
		selectorRollback:run({ failAfterWrites = 70 })
	end) and selectorRollback:snapshot() == selectorSnapshot, "Duplicate-name rollback failed")
	rollbacks += 1

	-- Full reviewed payload on the actual accepted B Instances in memory. No serialization.
end
local fullPayloadPath = ".artifacts/playtests/2026-10-21-maze02/payload.json"
if fs.isFile(fullPayloadPath) then
	local fullPayload = serde.decode("json", fs.readFile(fullPayloadPath))
	local function realSetup()
		local scene = roblox.deserializePlace(fs.readFile("place/Children_of_corn_B.rbxl"))
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
			and fullDry.plannedNodes == #fullPayload.nodes
			and fullSnapshot() == fullBefore,
		"Full payload dry run failed"
	)
	local fullResult = fullFactory(fullPayload)
	check(
		fullResult.created == #fullPayload.nodes
			and fullResult.changedProperties == #fullPayload.changes,
		"Full payload install failed"
	)
	local fullInstalled = fullSnapshot()
	check(
		fullFactory(fullPayload).repeated and fullSnapshot() == fullInstalled,
		"Full payload repeat changed scene"
	)
	local rollbackFactory, rollbackSnapshot = realSetup()
	local rollbackBefore = rollbackSnapshot()
	check(not pcall(function()
		rollbackFactory(
			fullPayload,
			{ failAfterWrites = #fullPayload.nodes + #fullPayload.changes }
		)
	end), "Full payload late failure missed")
	check(rollbackSnapshot() == rollbackBefore, "Full payload late rollback lost baseline")
	rollbacks += 1
	print(
		string.format(
			"maze02 full payload PASS (%d nodes, %d changes, %d guards)",
			#fullPayload.nodes,
			#fullPayload.changes,
			#fullPayload.guards
		)
	)
end
print(
	string.format(
		"maze02-installer PASS (%d assertions, %d refusals, %d rollback points)",
		assertions,
		refusals,
		rollbacks
	)
)
