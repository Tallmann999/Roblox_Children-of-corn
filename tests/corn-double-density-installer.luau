-- Run the actual Source-only native factory against a faulting adapter and
-- optionally the exact private archived B DOM. No scene is saved or serialized.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local luau = require("@lune/luau")
local process = require("@lune/process")
local code = fs.readFile("scripts/corn-double-density-native-core.luau")
local directory = ".artifacts/playtests/2026-10-22-B-double-density/"
local archive = directory .. "before-double-density.zip"
assert(
	serde.hash("sha256", fs.readFile(archive))
		== "7c169aa2e045c36ba4d2b0bd6876be899a36fd682a62a202270e4928783741fd"
)
local read = process.exec("python", {
	"-c",
	"import sys,zipfile;sys.stdout.write(zipfile.ZipFile(sys.argv[1]).read('checkpoint/B-before-double-density.rbxl').hex())",
	archive,
})
assert(read.ok, read.stderr)
assert(#read.stdout == 1499095 * 2 and not read.stdout:find("[^%x]"), "Invalid archived bytes")
local baselineBytes = read.stdout:gsub("%x%x", function(pair)
	return string.char(tonumber(pair, 16) :: number)
end)
assert(
	serde.hash("sha256", baselineBytes)
		== "94c55e17bed0dc2f4b2e7c6020f60c031d80bc636be16166fe0effb6df146d5f"
)
local baseline = roblox.deserializePlace(baselineBytes)
local sourceRecords, sourceSpecs = {}, {}
for _, item in baseline:GetDescendants() do
	if item:IsA("LuaSourceContainer") then
		local path, source = item:GetFullName():gsub("%.", "/"), item.Source:gsub("\r\n", "\n")
		assert(not sourceRecords[path], "Ambiguous archived Source")
		sourceRecords[path] = { class = item.ClassName, source = source }
		sourceSpecs[path] = { class = item.ClassName, sha256 = serde.hash("sha256", source) }
	end
end
local changedPaths = {
	"ReplicatedStorage/GameShared/Game/CornLayout",
	"ReplicatedStorage/GameShared/Game/CornAppearance",
	"StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornController",
	"StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornBackdropController",
	"StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornWindController",
}
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
local function binaryHash(_, value)
	return (
		serde.hash("sha256", value):gsub("..", function(byte)
			return string.char(tonumber(byte, 16) :: number)
		end)
	)
end
local nativeEnum = setmetatable(
	{ HashAlgorithm = { Sha256 = "sha256" } },
	{ __index = roblox.Enum }
)
local function setup()
	local state = { running = false, studio = true, paths = {}, documents = {}, sourceWrites = 0 }
	local methods = {}
	local function make(class, name, parent)
		local item =
			{ values = { ClassName = class, Name = name }, attrs = {}, tags = {}, children = {} }
		setmetatable(item, {
			__index = function(self, key)
				if methods[key] then
					return methods[key]
				end
				if key == "Source" and state.sourceReadFault then
					local override = state.sourceReadFault(self)
					if override then
						return override
					end
				end
				if self.values[key] ~= nil then
					return self.values[key]
				end
				for _, child in self.children do
					if child.Name == key then
						return child
					end
				end
				return nil
			end,
			__newindex = function(self, key, value)
				if key == "Source" and state.countWrites then
					state.sourceWrites += 1
					if state.sourceWriteFault then
						state.sourceWriteFault(self, value)
					end
				end
				if key == "Parent" then
					local old = self.values.Parent
					if old then
						table.remove(old.children, assert(table.find(old.children, self)))
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
		return if not self.Parent or self.Parent.ClassName == "DataModel"
			then self.Name
			else self.Parent:GetFullName() .. "." .. self.Name
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
	function methods:GetTags()
		return table.clone(self.tags)
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
	for path, row in sourceRecords do
		ensure(path, row.class).Source = row.source
	end
	local map = ensure("Workspace/CornMap", "Model")
	map.attrs = { corn_project_id = "children_of_corn", HarvestArtVariant = "B" }
	ensure("Workspace/CornMap/Ground", "Part").Size = roblox.Vector3.new(630, 2, 630)
	ensure("Workspace/CornMap/FieldZone", "Part").Size = roblox.Vector3.new(630, 10, 630)
	local author = ensure("Workspace/Author Corn", "MeshPart")
	author.CFrame, author.Size = roblox.CFrame.new(350, 20, 0), roblox.Vector3.new(2, 10, 2)
	author.attrs.AuthorEditableCornCopy, author.tags = true, { "AuthorWork" }
	local sourceChanges = {}
	for _, path in changedPaths do
		local source = sourceRecords[path].source .. "\n-- Doubled density fixture payload\n"
		sourceChanges[path] = {
			before_sha256 = sourceSpecs[path].sha256,
			after_sha256 = serde.hash("sha256", source),
			source = source,
		}
	end
	state.payload = {
		owner = "corn_double_density_v1",
		sources = copy(sourceSpecs),
		sourceChanges = sourceChanges,
		changes = {},
		nodes = {},
	}
	local services = {
		RunService = {
			IsStudio = function()
				return state.studio
			end,
			IsRunning = function()
				return state.running
			end,
		},
		EncodingService = { ComputeStringHash = binaryHash },
		ChangeHistoryService = { SetWaypoint = function() end },
		ScriptEditorService = {
			GetScriptDocuments = function()
				return state.documents
			end,
		},
	}
	function game:GetService(name)
		return assert(services[name], name)
	end
	local env = setmetatable({
		game = game,
		workspace = state.paths.Workspace,
		Vector3 = roblox.Vector3,
		Enum = nativeEnum,
	}, { __index = getfenv() })
	state.factory = luau.load(code, { environment = env })()
	state.game, state.map, state.author, state.make, state.ensure = game, map, author, make, ensure
	state.countWrites = true
	function state:run(options)
		return self.factory(self.payload, options)
	end
	function state:snapshot()
		local rows = {}
		for _, item in game:GetDescendants() do
			local values = {}
			for key, value in item.values do
				if key ~= "Parent" then
					values[key] = if typeof(value) == "Vector3"
							or typeof(value) == "CFrame"
						then tostring(value)
						else value
				end
			end
			rows[#rows + 1] =
				{ path = item:GetFullName(), values = values, attrs = item.attrs, tags = item.tags }
		end
		return serde.encode("json", rows)
	end
	return state
end

local positive = setup()
local before = positive:snapshot()
local dry = positive:run({ dryRun = true })
check(
	dry.state == "baseline"
		and dry.plannedSourceChanges == 5
		and dry.retainedSources == 157
		and dry.worldChanges == 0
		and dry.created == 0
		and positive:snapshot() == before
		and positive.sourceWrites == 0,
	"Dry run mutated scene"
)
local result = positive:run()
check(
	result.changedSources == 5
		and result.worldChanges == 0
		and result.created == 0
		and positive.sourceWrites == 5,
	"Wrong Source-only installation counts"
)
for path, row in sourceRecords do
	local expected = if positive.payload.sourceChanges[path]
		then positive.payload.sourceChanges[path].source
		else row.source
	check(positive.paths[path].Source == expected, "Wrong retained Source: " .. path)
end
check(
	positive.author.CFrame == roblox.CFrame.new(350, 20, 0)
		and positive.author:GetAttribute("AuthorEditableCornCopy") == true,
	"Author world was changed"
)
local installed = positive:snapshot()
check(
	positive:run().repeated and positive.sourceWrites == 5 and positive:snapshot() == installed,
	"Repeat wrote to scene"
)
check(
	positive:run({ dryRun = true }).state == "installed"
		and positive.sourceWrites == 5
		and positive:snapshot() == installed,
	"Installed dry run wrote"
)

local function refusal(label, mutate)
	local state = setup()
	mutate(state)
	local snapshot, writes = state:snapshot(), state.sourceWrites
	check(not pcall(function()
		state:run()
	end), "Unsafe state accepted: " .. label)
	check(
		state:snapshot() == snapshot and state.sourceWrites == writes,
		"Refusal changed author work: " .. label
	)
	refusals += 1
end
local cases = {
	{
		"wrong filename",
		function(s)
			s.game.Name = "Showroom.rbxlx"
		end,
	},
	{
		"A filename",
		function(s)
			s.game.Name = "Children_of_corn.rbxl"
		end,
	},
	{
		"Play",
		function(s)
			s.running = true
		end,
	},
	{
		"Player",
		function(s)
			s.studio = false
		end,
	},
	{
		"wrong map class",
		function(s)
			s.map.ClassName = "Folder"
		end,
	},
	{
		"A variant",
		function(s)
			s.map.attrs.HarvestArtVariant = "A"
		end,
	},
	{
		"foreign project",
		function(s)
			s.map.attrs.corn_project_id = "other"
		end,
	},
	{
		"missing map",
		function(s)
			s.map:Destroy()
		end,
	},
	{
		"Ground bounds",
		function(s)
			s.paths["Workspace/CornMap/Ground"].Size = roblox.Vector3.one
		end,
	},
	{
		"Field bounds",
		function(s)
			s.paths["Workspace/CornMap/FieldZone"].Size = roblox.Vector3.one
		end,
	},
	{
		"unknown payload",
		function(s)
			s.payload.owner = "other"
		end,
	},
	{
		"missing guards",
		function(s)
			s.payload.sources = nil
		end,
	},
	{
		"missing replacements",
		function(s)
			s.payload.sourceChanges = nil
		end,
	},
	{
		"missing world list",
		function(s)
			s.payload.changes = nil
		end,
	},
	{
		"world write",
		function(s)
			s.payload.changes =
				{ { path = "Workspace/Author Corn", property = "CastShadow", after = false } }
		end,
	},
	{
		"missing node list",
		function(s)
			s.payload.nodes = nil
		end,
	},
	{
		"new node",
		function(s)
			s.payload.nodes = { { path = "Workspace/New", class = "Part" } }
		end,
	},
	{
		"missing Source",
		function(s)
			s.paths["Workspace/CornfieldFog/Config"]:Destroy()
		end,
	},
	{
		"extra Source",
		function(s)
			s.make("Script", "Author", s.game).Source = "Author"
		end,
	},
	{
		"ambiguous Source",
		function(s)
			local item = s.paths[changedPaths[1]]
			s.make(item.ClassName, item.Name, item.Parent).Source = item.Source
		end,
	},
	{
		"class changed",
		function(s)
			s.paths[changedPaths[1]].ClassName = "LocalScript"
		end,
	},
	{
		"retained author Source",
		function(s)
			s.paths["ReplicatedStorage/GameShared/Game/HarvestWardenVisual"].Source ..= "-- Author"
		end,
	},
	{
		"changed author Source",
		function(s)
			s.paths[changedPaths[1]].Source ..= "-- Author"
		end,
	},
	{
		"partial install",
		function(s)
			s.paths[changedPaths[1]].Source = s.payload.sourceChanges[changedPaths[1]].source
		end,
	},
	{
		"guard omitted",
		function(s)
			s.payload.sources[changedPaths[1]] = nil
		end,
	},
	{
		"foreign guard",
		function(s)
			s.payload.sources["Workspace/NoSuchSource"] =
				{ class = "ModuleScript", sha256 = string.rep("0", 64) }
		end,
	},
	{
		"guard class",
		function(s)
			s.payload.sources[changedPaths[1]].class = "Script"
		end,
	},
	{
		"guard hash invalid",
		function(s)
			s.payload.sources[changedPaths[1]].sha256 = "x"
		end,
	},
	{
		"four replacements",
		function(s)
			s.payload.sourceChanges[changedPaths[1]] = nil
		end,
	},
	{
		"wrong whitelist",
		function(s)
			s.payload.sourceChanges["ReplicatedStorage/GameShared/Game/HarvestWardenVisual"] =
				s.payload.sourceChanges[changedPaths[1]]
			s.payload.sourceChanges[changedPaths[1]] = nil
		end,
	},
	{
		"before hash changed",
		function(s)
			s.payload.sourceChanges[changedPaths[1]].before_sha256 = string.rep("0", 64)
		end,
	},
	{
		"after hash invalid",
		function(s)
			s.payload.sourceChanges[changedPaths[1]].after_sha256 = string.rep("A", 64)
		end,
	},
	{
		"no-op replacement",
		function(s)
			local row = s.payload.sourceChanges[changedPaths[1]]
			row.after_sha256, row.source = row.before_sha256, sourceRecords[changedPaths[1]].source
		end,
	},
	{
		"corrupted Source",
		function(s)
			s.payload.sourceChanges[changedPaths[1]].source ..= "foreign"
		end,
	},
	{
		"empty Source",
		function(s)
			s.payload.sourceChanges[changedPaths[1]].source = ""
		end,
	},
	{
		"CR bytes",
		function(s)
			local row = s.payload.sourceChanges[changedPaths[1]]
			row.source = "\r\n"
			row.after_sha256 = serde.hash("sha256", "\n")
		end,
	},
	{
		"NUL bytes",
		function(s)
			local row = s.payload.sourceChanges[changedPaths[1]]
			row.source = "\0"
			row.after_sha256 = serde.hash("sha256", row.source)
		end,
	},
	{
		"open changed editor",
		function(s)
			s.documents =
				{ {
					GetScript = function()
						return s.paths[changedPaths[1]]
					end,
				} }
		end,
	},
}
for _, case in cases do
	refusal(case[1], case[2])
end

for point = 1, 5 do
	local state = setup()
	local snapshot = state:snapshot()
	check(not pcall(function()
		state:run({ failAfterWrites = point })
	end), "Injected failure missed: " .. point)
	check(state:snapshot() == snapshot, "Rollback changed exact source/world bytes: " .. point)
	check(state:run({ dryRun = true }).state == "baseline", "Rollback left partial phase")
	rollbacks += 1
end
-- Studio may reject a Source assignment or return unexpected readback bytes.
-- Both paths must restore every journaled Source without touching world work.
for _, kind in { "setter", "readback" } do
	local state = setup()
	local exactBefore = state:snapshot()
	if kind == "setter" then
		state.sourceWriteFault = function()
			if state.sourceWrites == 3 then
				error("Native Source permission failure")
			end
		end
	else
		state.sourceReadFault = function()
			if state.sourceWrites == 3 then
				state.sourceReadFault = nil
				return "Unexpected native readback"
			end
			return nil
		end
	end
	check(not pcall(function()
		state:run()
	end), "Native " .. kind .. " failure ignored")
	check(
		state:snapshot() == exactBefore and state:run({ dryRun = true }).state == "baseline",
		"Native " .. kind .. " failure lost Source/world state"
	)
	rollbacks += 1
end
local restoreFailure = setup()
local blockedPath = changedPaths[1]
restoreFailure.sourceWriteFault = function(item, value)
	if
		restoreFailure.sourceWrites > 5
		and item == restoreFailure.paths[blockedPath]
		and value == sourceRecords[blockedPath].source
	then
		error("Native restoration permission failure")
	end
end
local restored, restoreProblem = pcall(function()
	restoreFailure:run({ failAfterWrites = 5 })
end)
check(
	not restored and tostring(restoreProblem):find("rollback errors", 1, true) ~= nil,
	"Rollback failure hidden"
)
check(
	restoreFailure.sourceWrites == 10,
	"One refused restoration prevented remaining journal attempts"
)
for _, path in changedPaths do
	check(
		restoreFailure.paths[path].Source
			== (
				if path == blockedPath
					then restoreFailure.payload.sourceChanges[path].source
					else sourceRecords[path].source
			),
		"Unrelated Source was left installed after restoration refusal"
	)
end
local concurrent = setup()
check(not pcall(function()
	concurrent:run({
		prepareYield = function()
			concurrent.paths[changedPaths[1]].Source ..= "-- Author concurrent"
		end,
	})
end), "Concurrent Source edit accepted")
check(
	concurrent.paths[changedPaths[1]].Source
			== sourceRecords[changedPaths[1]].source .. "-- Author concurrent"
		and concurrent.paths[changedPaths[2]].Source == sourceRecords[changedPaths[2]].source,
	"Concurrent Source edit overwritten"
)
refusals += 1
local replaced = setup()
local replacement
check(not pcall(function()
	replaced:run({
		prepareYield = function()
			local original = replaced.paths[changedPaths[1]]
			replacement = replaced.make(original.ClassName, original.Name, original.Parent)
			replacement.Source = original.Source
			original:Destroy()
		end,
	})
end), "Concurrent identity replacement accepted")
check(
	replacement and replacement.Source == sourceRecords[changedPaths[1]].source,
	"Concurrent replacement overwritten"
)
refusals += 1
local authorWorld = setup()
check(
	authorWorld:run({
		prepareYield = function()
			authorWorld.author.Size = roblox.Vector3.new(3, 12, 3)
		end,
	}).changedSources
			== 5
		and authorWorld.author.Size == roblox.Vector3.new(3, 12, 3),
	"Source-only commit lost concurrent author world edit"
)
local unrelatedEditor = setup()
unrelatedEditor.documents = {
	{
		GetScript = function()
			return unrelatedEditor.paths["ReplicatedStorage/GameShared/Game/HarvestWardenVisual"]
		end,
	},
}
check(unrelatedEditor:run().changedSources == 5, "Unchanged Source editor was blocked")
local installedAuthor = setup()
installedAuthor:run()
installedAuthor.paths[changedPaths[1]].Source ..= "-- Author after install"
local installedAuthorSnapshot = installedAuthor:snapshot()
check(not pcall(function()
	installedAuthor:run()
end) and installedAuthor:snapshot() == installedAuthorSnapshot, "Installed author edit overwritten")
refusals += 1

if table.find(process.args, "--full") then
	local payloadBytes = fs.readFile(directory .. "payload.json")
	assert(
		serde.hash("sha256", payloadBytes)
			== "a1955446f4d7b7b7093bd9ce575c08251cc0ee1fe3896cbc0d2b342da8732f90",
		"Frozen payload changed"
	)
	local payload = serde.decode("json", payloadBytes)
	local function realSetup()
		local scene = roblox.deserializePlace(baselineBytes)
		local services = {
			RunService = {
				IsStudio = function()
					return true
				end,
				IsRunning = function()
					return false
				end,
			},
			EncodingService = { ComputeStringHash = binaryHash },
			ChangeHistoryService = { SetWaypoint = function() end },
			ScriptEditorService = {
				GetScriptDocuments = function()
					return {}
				end,
			},
		}
		local proxy = { Name = "Children_of_corn_B.rbxl" }
		function proxy:GetDescendants()
			return scene:GetDescendants()
		end
		function proxy:GetService(name)
			return assert(services[name], name)
		end
		local env = setmetatable({
			game = proxy,
			workspace = scene:GetService("Workspace"),
			Vector3 = roblox.Vector3,
			Enum = nativeEnum,
		}, { __index = getfenv() })
		local factory = luau.load(code, { environment = env })()
		local function snapshot()
			local rows = {}
			for _, item in scene:GetDescendants() do
				local props = {}
				if item:IsA("BasePart") then
					for _, name in
						{
							"CFrame",
							"Size",
							"Transparency",
							"CanCollide",
							"CanQuery",
							"CanTouch",
							"CastShadow",
							"Anchored",
							"Color",
							"Material",
						}
					do
						props[name] = tostring(item[name])
					end
				end
				local attrs = {}
				for name, value in item:GetAttributes() do
					attrs[name] = tostring(value)
				end
				rows[#rows + 1] = {
					path = item:GetFullName(),
					class = item.ClassName,
					properties = props,
					attrs = attrs,
					tags = item:GetTags(),
					source = if item:IsA("LuaSourceContainer") then item.Source else nil,
				}
			end
			return serde.encode("json", rows)
		end
		return factory, snapshot
	end
	local factory, snapshot = realSetup()
	local original = snapshot()
	local fullDry = factory(payload, { dryRun = true })
	check(
		fullDry.state == "baseline"
			and fullDry.plannedSourceChanges == 5
			and fullDry.retainedSources == 157
			and snapshot() == original,
		"Full private B dry run failed"
	)
	local fullResult = factory(payload)
	check(
		fullResult.changedSources == 5 and fullResult.worldChanges == 0 and fullResult.created == 0,
		"Full private B installation counts differ"
	)
	local fullInstalled = snapshot()
	check(factory(payload).repeated and snapshot() == fullInstalled, "Full private B repeat wrote")
	check(
		factory(payload, { dryRun = true }).state == "installed" and snapshot() == fullInstalled,
		"Full installed dry run wrote"
	)
	for point = 1, 5 do
		local rollbackFactory, rollbackSnapshot = realSetup()
		local exactBefore = rollbackSnapshot()
		check(not pcall(function()
			rollbackFactory(payload, { failAfterWrites = point })
		end), "Full B failure injection missed")
		check(
			rollbackSnapshot() == exactBefore,
			"Full private DOM rollback changed bytes: " .. point
		)
		check(
			rollbackFactory(payload, { dryRun = true }).state == "baseline",
			"Full B rollback left partial state"
		)
		rollbacks += 1
	end
	print(
		"corn-double-density full private B payload PASS (5 exact Sources, 157 guards, 0 world writes)"
	)
end
print(
	serde.encode(
		"json",
		{ passed = true, assertions = assertions, refusals = refusals, rollbackPoints = rollbacks }
	)
)
