-- Execute actual install/verify core against a faulting prepared-state adapter.
-- No Studio calls or scene serialization. Preparation geometry is not mocked as acceptance.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local luau = require("@lune/luau")
local process = require("@lune/process")
local code = fs.readFile("scripts/B-green-variants-native-core.luau")
local out = ".artifacts/playtests/2026-10-23-B-green-variants/"
assert(
	serde.hash("sha256", fs.readFile(out .. "before-green-variants.zip"))
		== "d61ef19552dadfdb402b87c9482d62b7693824f51ff7f5b35703d3a2b8d279a2",
	"Immutable B archive changed"
)
local archived = process.exec("python", {
	"-c",
	"import sys,zipfile;sys.stdout.write(zipfile.ZipFile(sys.argv[1]).read('B-before-green-variants.rbxl').hex())",
	out .. "before-green-variants.zip",
})
assert(archived.ok, archived.stderr)
local bytes = archived.stdout:gsub("%x%x", function(pair)
	return string.char(tonumber(pair, 16))
end)
assert(
	serde.hash("sha256", bytes)
		== "db9398781ec6d68da97bfadb1514e5a589cdf5a293424538e19bc29869f7a371",
	"Archived B bytes differ"
)
local baseline = roblox.deserializePlace(bytes)
local originalSources = {}
for _, item in baseline:GetDescendants() do
	if item:IsA("LuaSourceContainer") then
		originalSources[item:GetFullName():gsub("%.", "/")] =
			{ class = item.ClassName, source = item.Source }
	end
end
local payload = serde.decode("json", fs.readFile(out .. "payload.json"))
local assertions, refusals, rollbacks = 0, 0, 0
local function check(value, message)
	assertions += 1
	assert(value, message)
end
local function clone(value)
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, item in value do
		result[key] = clone(item)
	end
	return result
end
local function typed(value)
	local kind = typeof(value)
	if kind == "CFrame" then
		return { kind = kind, value = { value:GetComponents() } }
	end
	if kind == "Vector3" then
		return { kind = kind, value = { value.X, value.Y, value.Z } }
	end
	if kind == "Color3" then
		return { kind = kind, value = { value.R, value.G, value.B } }
	end
	if kind == "EnumItem" then
		return { kind = "Enum", value = value.Value }
	end
	return value
end
local function record(item, prototype)
	local props = {}
	if item:IsA("MeshPart") then
		for _, key in
			{
				"CFrame",
				"Size",
				"PivotOffset",
				"Color",
				"TextureID",
				"Transparency",
				"Reflectance",
				"Material",
				"Anchored",
				"CanCollide",
				"CanTouch",
				"CanQuery",
				"CastShadow",
				"DoubleSided",
				"RenderFidelity",
			}
		do
			props[key] = typed(item[key])
		end
		props.InitialSize = typed(item.MeshSize)
	end
	return {
		class = item.ClassName,
		prototype = prototype,
		properties = props,
		attributes = item:GetAttributes(),
		tags = item:GetTags(),
	}
end
local function partSnapshot(item, immutable)
	local props = {}
	local mutable =
		{ CFrame = true, Size = true, Color = true, TextureID = true, Transparency = true }
	for _, key in
		{
			"Archivable",
			"Locked",
			"CFrame",
			"Size",
			"MeshId",
			"MeshContent",
			"MeshSize",
			"TextureID",
			"TextureContent",
			"PivotOffset",
			"Color",
			"Material",
			"MaterialVariant",
			"Reflectance",
			"Transparency",
			"Anchored",
			"CanCollide",
			"CanTouch",
			"CanQuery",
			"CastShadow",
			"DoubleSided",
			"Massless",
			"CollisionGroup",
			"CustomPhysicalProperties",
			"RootPriority",
			"RenderFidelity",
			"CollisionFidelity",
		}
	do
		if not immutable or not mutable[key] then
			props[key] = item[key]
		end
	end
	return {
		properties = props,
		attributes = item:GetAttributes(),
		tags = item:GetTags(),
		children = item:GetChildren(),
	}
end
local function setup()
	local s = {
		paths = {},
		nodes = {},
		running = false,
		studio = true,
		yields = 0,
		sourceWrites = 0,
		active = false,
		editor = {},
	}
	local methods = {}
	local function make(class, name, parent)
		local item =
			{ values = { ClassName = class, Name = name }, children = {}, attrs = {}, tags = {} }
		setmetatable(item, {
			__index = function(self, key)
				if methods[key] then
					return methods[key]
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
				if s.active then
					if key == "Source" then
						s.sourceWrites += 1
					end
					if s.fault then
						s.fault(self, key, value)
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
		s.nodes[#s.nodes + 1] = item
		return item
	end
	function methods:IsA(class)
		return self.ClassName == class
			or (
					class == "LuaSourceContainer"
					and ({ ModuleScript = true, LocalScript = true, Script = true })[self.ClassName]
				)
				== true
	end
	function methods:GetChildren()
		return table.clone(self.children)
	end
	function methods:FindFirstChild(name)
		for _, item in self.children do
			if item.Name == name then
				return item
			end
		end
		return nil
	end
	function methods:GetDescendants()
		local result = {}
		local function visit(item)
			for _, child in item.children do
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
	function methods:GetAttribute(name)
		return self.attrs[name]
	end
	function methods:GetAttributes()
		return table.clone(self.attrs)
	end
	function methods:GetTags()
		return table.clone(self.tags)
	end
	local game = make("DataModel", "Children_of_corn_B.rbxl")
	game.PlaceId = 0
	local function ensure(path, class)
		if s.paths[path] then
			if class then
				s.paths[path].ClassName = class
			end
			return s.paths[path]
		end
		local prefix, name = path:match("^(.*)/([^/]+)$")
		local item = make(class or "Folder", name or path, if prefix then ensure(prefix) else game)
		s.paths[path] = item
		return item
	end
	for path, row in originalSources do
		ensure(path, row.class).Source = row.source
	end
	local map = ensure("Workspace/CornMap", "Model")
	map.attrs = { corn_project_id = "children_of_corn", HarvestArtVariant = "B" }
	local field = ensure("Workspace/CornMap/FieldZone", "Part")
	field.Size, field.CFrame =
		roblox.Vector3.new(630, 10, 630), roblox.CFrame.new(0, 19.399986267089844, 0)
	ensure("Workspace/CornMap/Ground", "Part").Size = roblox.Vector3.new(630, 2, 630)
	local retained = {}
	for path in originalSources do
		retained[path] = { item = s.paths[path], parent = s.paths[path].Parent }
	end
	local boxes, circles, edges =
		table.create(188, true), table.create(19, true), table.create(100, true)
	local work = {
		owner = payload.owner,
		state = "prepared",
		old = {},
		added = {},
		changes = {},
		created = {},
		proposal = { new_nodes = {} },
		layout = {
			SoilTiles = {},
			ReadExclusions = function()
				return {
					Boxes = boxes,
					Circles = circles,
					TrailEdges = edges,
					GreenBeds = true,
					Signature = "fixture-signature",
				}
			end,
		},
		map = map,
		field = field,
		retained = retained,
		beds = {},
		signature = "fixture-signature",
		afterVisible = 1814,
	}
	work.private = make("Folder", "Game")
	work.data = make("Folder", "CornGreenGeometryData", work.private)
	work.data.attrs = { BGreenVariantsOwner = payload.owner, corn_project_id = "children_of_corn" }
	work.proposal.new_nodes["ReplicatedStorage/GameShared/Game/CornGreenGeometryData"] =
		record(work.data, "Folder")
	for path, row in payload.newSources do
		local item = make(row.class, path:match("([^/]+)$"))
		item.Source = row.source
		item.attrs = { BGreenVariantsOwner = payload.owner, corn_project_id = "children_of_corn" }
		if path:find("/CornGreenGeometryData/", 1, true) then
			item.Parent = work.data
		elseif not path:find("/Controllers/", 1, true) then
			item.Parent = work.private
		end
		work.added[path] = item
		work.proposal.new_nodes[path] = record(item, "ModuleScript")
	end
	for path, row in payload.sourceChanges do
		work.changes[path] = {
			item = s.paths[path],
			parent = s.paths[path].Parent,
			before = s.paths[path].Source,
			after = row.source,
		}
	end
	local cornFolder = make("Folder", "EditorPreview", map)
	for index = 1, 3480 do
		local item = make("MeshPart", "Corn" .. index, cornFolder)
		item.MeshId = "rbxassetid://104111861186519"
		local old = {
			CFrame = roblox.CFrame.new(index, 19, 0),
			Size = roblox.Vector3.new(3, 10, 3),
			Color = roblox.Color3.new(0.7, 0.7, 0.7),
			TextureID = "rbxassetid://103653296385119",
			Transparency = 0,
		}
		local after = {
			CFrame = roblox.CFrame.new(index, 20, 0),
			Size = roblox.Vector3.new(3, 8, 3),
			Color = roblox.Color3.new(1, 1, 1),
			TextureID = "rbxassetid://137803536172445",
			Transparency = 0,
		}
		for key, value in old do
			item[key] = value
		end
		work.old[index] = {
			item = item,
			parent = cornFolder,
			name = item.Name,
			before = old,
			after = after,
			immutable = partSnapshot(item, true),
		}
	end
	work.root = make("Folder", "GreenBedEditor", map)
	work.bedRoot = work.root
	work.bedRootAttrs, work.bedRootTags = work.root:GetAttributes(), work.root:GetTags()
	for index = 1, 1406 do
		local item = make("MeshPart", "SM_Bed_" .. index, work.root)
		item.CFrame, item.PivotOffset = roblox.CFrame.new(index, 15, 20), roblox.CFrame.new()
		item.Size, item.MeshSize = roblox.Vector3.new(18, 0.7, 18), roblox.Vector3.new(18, 0.7, 18)
		item.Color, item.TextureID, item.Transparency, item.Reflectance =
			roblox.Color3.new(1, 1, 1), "rbxassetid://95855894892409", 0, 0
		item.Anchored, item.CanCollide, item.CanTouch, item.CanQuery, item.CastShadow, item.DoubleSided =
			true, false, false, false, true, true
		item.Material, item.RenderFidelity =
			roblox.Enum.Material.Plastic, roblox.Enum.RenderFidelity.Precise
		item.attrs = { BGreenBedTile = index, BGreenBedsOwner = payload.owner }
		work.created[index] = item
		work.beds[index] = { item = item, name = item.Name, before = partSnapshot(item, false) }
		work.layout.SoilTiles[index] = { Frame = item.CFrame, Size = item.Size, Key = "Center" }
	end
	local services = {
		HttpService = {
			JSONEncode = function(_, value)
				return serde.encode("json", value)
			end,
		},
		EncodingService = {
			ComputeStringHash = function(_, value)
				return serde.hash("sha256", value):gsub("..", function(byte)
					return string.char(tonumber(byte, 16))
				end)
			end,
		},
		RunService = {
			IsStudio = function()
				return s.studio
			end,
			IsRunning = function()
				return s.running
			end,
		},
		ScriptEditorService = {
			GetEditorSource = function(_, item)
				return s.editor[item] or item.Source
			end,
		},
	}
	function game:GetService(name)
		return assert(services[name], name)
	end
	local enum = setmetatable({ HashAlgorithm = { Sha256 = "sha256" } }, { __index = roblox.Enum })
	local globals = { __CornBGreenVariantsV1_work = work }
	local env = setmetatable({
		game = game,
		workspace = s.paths.Workspace,
		Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame,
		Enum = enum,
		_G = globals,
		task = {
			wait = function()
				s.yields += 1
				if s.onYield then
					s.onYield()
				end
			end,
		},
	}, { __index = getfenv() })
	s.factory = luau.load(code, { environment = env })()
	s.game, s.map, s.work = game, map, work
	s.active = true
	function s:run(mode)
		return self.factory(payload, mode)
	end
	function s:baselineExact()
		for path, row in originalSources do
			if self.paths[path].Source ~= row.source then
				return false
			end
		end
		for _, row in work.old do
			for key, value in row.before do
				if row.item[key] ~= value then
					return false
				end
			end
		end
		return work.root.Parent == map
			and work.data.Parent == work.private
			and #work.root:GetChildren() == 1406
			and #game:GetDescendants() > 3480
	end
	return s
end

local good = setup()
local installed = good:run("install")
check(
	installed.installed
		and installed.corn == 3480
		and installed.bedsUntouched == 1406
		and installed.newWorldNodes == 0,
	"Complete prepared install failed"
)
check(good:run("verify").verified and good.work.state == "installed", "Installed verify failed")
local count = good.sourceWrites
check(good:run("verify").verified and good.sourceWrites == count, "Verify wrote Sources")

local function refuse(name, mutate)
	local s = setup()
	mutate(s)
	local ok = pcall(function()
		s:run("install")
	end)
	check(
		not ok and s.sourceWrites == 0 and s.work.state == "prepared",
		"Unsafe preflight accepted/wrote: " .. name
	)
	refusals += 1
end
refuse("running", function(s)
	s.running = true
end)
refuse("wrong filename", function(s)
	s.game.Name = "Children_of_corn.rbxl"
end)
refuse("wrong variant", function(s)
	s.map.attrs.HarvestArtVariant = "A"
end)
refuse("foreign old corn edit", function(s)
	s.work.old[1].item.Size = roblox.Vector3.new(99, 99, 99)
end)
refuse("foreign bed physics", function(s)
	s.work.created[1].CanCollide = true
end)
refuse("foreign bed attributes", function(s)
	s.work.created[1].attrs.AuthorEdit = true
end)
refuse("foreign Source body", function(s)
	s.paths[next(payload.sources)].Source = "return 'author'"
	s.sourceWrites = 0
end)
refuse("unsaved Source buffer", function(s)
	s.editor[s.paths[next(payload.sources)]] = "unsaved author text"
end)

local function rollback(name, configure)
	local s = setup()
	configure(s)
	local ok, problem = pcall(function()
		s:run("install")
	end)
	check(
		not ok and tostring(problem):find("Install rolled back", 1, true) and s:baselineExact(),
		"Rollback failed: " .. name .. ": " .. tostring(problem)
	)
	check(s.work.state == "prepared", "Rollback left wrong state")
	rollbacks += 1
end
rollback("Source write", function(s)
	local n = 0
	s.fault = function(_, key)
		if key == "Source" then
			n += 1
			if n == 2 then
				s.fault = nil
				error("injected Source write failure")
			end
		end
	end
end)
rollback("corn partial row write", function(s)
	s.fault = function(item, key)
		if item == s.work.old[65].item and key == "Size" then
			s.fault = nil
			error("injected corn failure")
		end
	end
end)
rollback("root publication", function(s)
	s.fault = function(item, key, value)
		if
			item == s.work.data
			and key == "Parent"
			and value == s.paths["ReplicatedStorage/GameShared/Game"]
		then
			s.fault = nil
			error("injected root publication failure")
		end
	end
end)
rollback("bounded child publication", function(s)
	s.fault = function(item, key, value)
		if
			item == s.work.added["ReplicatedStorage/GameShared/Game/CornGreenGeometry"]
			and key == "Parent"
			and value == s.paths["ReplicatedStorage/GameShared/Game"]
		then
			s.fault = nil
			error("injected child publication failure")
		end
	end
end)

local changedSource = next(payload.sourceChanges)
for _, kind in { "corn", "Source" } do
	local s = setup()
	local authorColor = roblox.Color3.new(0.13, 0.17, 0.19)
	s.onYield = function()
		s.onYield = nil
		if kind == "corn" then
			s.work.old[1].item.Color = authorColor
		else
			s.paths[changedSource].Source = "-- Concurrent author Source\nreturn 'author'"
		end
	end
	local ok, problem = pcall(function()
		s:run("install")
	end)
	check(
		not ok and tostring(problem):find("preserved concurrent author values=1", 1, true),
		"Concurrent change was not detected/preserved: " .. kind
	)
	if kind == "corn" then
		check(s.work.old[1].item.Color == authorColor, "Rollback overwrote author corn")
		s.work.old[1].item.Color = s.work.old[1].before.Color
	else
		check(
			s.paths[changedSource].Source == "-- Concurrent author Source\nreturn 'author'",
			"Rollback overwrote author Source"
		)
		s.paths[changedSource].Source = originalSources[changedSource].source
	end
	check(s:baselineExact(), "Rollback damaged unrelated state after author conflict")
	rollbacks += 1
end
print(serde.encode("json", {
	passed = true,
	assertions = assertions,
	refusals = refusals,
	rollbackPoints = rollbacks,
	sources = 163,
	installedSources = 167,
	corn = 3480,
	beds = 1406,
	preparationGeometryAccepted = false,
	scope = "Actual install/verify core against faulting prepared-state adapter; no scene writes",
}))
