-- Synthetic Source transaction fixture; no scene is opened or serialized.
local fs, serde, r = require("@lune/fs"), require("@lune/serde"), require("@lune/roblox")
local original = serde.decode(
	"json",
	fs.readFile(".artifacts/playtests/2026-10-23-B-manual-authoring/payload.json")
)
local manifest = serde.decode("json", fs.readFile("rojo/source-map.json"))
local code = fs.readFile("scripts/install-B-manual-authoring-sources.luau")
assert(loadstring(code))
local checks, refusals, rollbacks = 0, {}, {}
local function check(value, message)
	checks += 1
	assert(value, message)
end
local function clone(value)
	return serde.decode("json", serde.encode("json", value))
end
local function hash(text)
	return serde.hash("sha256", text)
end
local function setup()
	local p = r.Instance.new("DataModel")
	local sourcePayload = clone(original)
	local classes = manifest.variants.B.classes
	local function resolve(path, create)
		local parent, prefix = p, ""
		for _, name in path:split("/") do
			prefix = if prefix == "" then name else prefix .. "/" .. name
			local item = parent:FindFirstChild(name)
			if not item and create then
				local class = classes[prefix] or (if parent == p then name else "Folder")
				item = r.Instance.new(class)
				item.Name, item.Parent = name, parent
			end
			if not item then
				return nil
			end
			parent = item
		end
		return parent
	end
	local nativeSources = {}
	local beforePaths = {}
	for path in sourcePayload.expectedBeforeSources do
		table.insert(beforePaths, path)
	end
	table.sort(beforePaths)
	for _, path in beforePaths do
		local row = sourcePayload.expectedBeforeSources[path]
		local item = resolve(path, true)
		if item.ClassName ~= row.class then
			local parent, name = item.Parent, item.Name
			item:Destroy()
			item = r.Instance.new(row.class)
			item.Name, item.Parent = name, parent
		end
		item.Source = "return { old = true }\n"
		row.sha256 = hash(item.Source)
		local identityOk, nativeId = pcall(function()
			return item:GetDebugId(0)
		end)
		nativeSources[path] = {
			id = if identityOk then tostring(nativeId) else tostring(item.UniqueId),
			class = item.ClassName,
			sha256 = row.sha256,
		}
	end
	for _, rows in { sourcePayload.sourceChanges, sourcePayload.newSources } do
		for path, row in rows do
			row.source = "return { updated = true, name = " .. string.format("%q", path) .. " }\n"
			row.sha256 = hash(row.source)
			if row.beforeSha256 then
				row.beforeSha256 = sourcePayload.expectedBeforeSources[path].sha256
			end
		end
	end
	local workspace = p:FindFirstChild("Workspace")
	local map = r.Instance.new("Model")
	map.Name, map.Parent = "CornMap", workspace
	map:SetAttribute("corn_project_id", "children_of_corn")
	map:SetAttribute("HarvestArtVariant", "B")
	map:SetAttribute("BManualAuthoringVersion", 1)
	for name, size in
		{ Ground = r.Vector3.new(630, 2, 630), FieldZone = r.Vector3.new(630, 10, 630) }
	do
		local part = r.Instance.new("Part")
		part.Name, part.Size, part.Parent = name, size, map
	end
	local folder = r.Instance.new("Folder")
	folder.Name, folder.Parent = "CornAuthoring", map
	folder:SetAttribute("Ready", true)
	folder:SetAttribute("InitialPlantCount", 70664)
	local s = {
		phase = "grouped",
		before = { sourceCount = 168, sources = nativeSources },
		journal = {},
		added = {},
		folder = folder,
		created = 70664,
	}
	local run = { studio = true, running = false }
	function run:IsStudio()
		return self.studio
	end
	function run:IsRunning()
		return self.running
	end
	local editor = { dirty = {}, documents = {} }
	function editor:GetEditorSource(item)
		return self.dirty[item] or item.Source
	end
	function editor:GetScriptDocuments()
		return self.documents
	end
	local gameProxy = { Name = "Children_of_corn_B.rbxl", PlaceId = 0, GameId = 0 }
	function gameProxy:GetChildren()
		return p:GetChildren()
	end
	function gameProxy:GetDescendants()
		return p:GetDescendants()
	end
	function gameProxy:GetService(name)
		if name == "RunService" then
			return run
		end
		if name == "ScriptEditorService" then
			return editor
		end
		if name == "EncodingService" then
			return {
				ComputeStringHash = function(_, text)
					return hash(text):gsub("..", function(byte)
						return string.char(tonumber(byte, 16))
					end)
				end,
			}
		end
		error(name)
	end
	local env = setmetatable(
		{
			game = gameProxy,
			workspace = workspace,
			Instance = r.Instance,
			Enum = r.Enum,
			Vector3 = r.Vector3,
			_G = { __CornBManualAuthoringV1 = s },
		},
		{ __index = getfenv() }
	)
	local function execute(text)
		local chunk = assert(loadstring(text or code))
		setfenv(chunk, env)
		return pcall(chunk(), sourcePayload)
	end
	local function snapshot()
		local out = {}
		for _, item in p:GetDescendants() do
			out[item] = {
				parent = item.Parent,
				name = item.Name,
				source = if item:IsA("LuaSourceContainer") then item.Source else nil,
			}
		end
		return out
	end
	local function same(before)
		local count = 0
		for _, item in p:GetDescendants() do
			count += 1
			local old = before[item]
			if
				not old
				or item.Parent ~= old.parent
				or item.Name ~= old.name
				or (old.source and item.Source ~= old.source)
			then
				return false
			end
		end
		local wanted = 0
		for _ in before do
			wanted += 1
		end
		return count == wanted
	end
	return {
		state = s,
		payload = sourcePayload,
		map = map,
		resolve = resolve,
		run = run,
		editor = editor,
		game = gameProxy,
		execute = execute,
		snapshot = snapshot,
		same = same,
	}
end
local good = setup()
local ok, result = good.execute()
check(ok, tostring(result))
check(
	result.changedSources == 8 and result.newSources == 3 and result.totalSources == 171,
	"Closed successful counts"
)
check(
	#good.state.journal == 8 and #good.state.added == 3 and good.state.phase == "sources-installed",
	"Journal integration"
)
check(good.state.verifySources().totalSources == 171, "Post-install 171 guard")
local final = good.snapshot()
ok, result = good.execute()
check(
	ok and result.repeated and result.changedSources == 0 and result.newSources == 0,
	"Idempotent repeat"
)
check(good.same(final), "Repeat wrote persistent state")
local function reject(name, change, injected)
	local fixture = setup()
	if change then
		change(fixture)
	end
	local before = fixture.snapshot()
	local accepted, problem = fixture.execute(injected)
	check(not accepted, "Unsafe install accepted: " .. name)
	check(
		fixture.same(before),
		"Rejected install changed persistent state: " .. name .. ": " .. tostring(problem)
	)
	check(
		#fixture.state.journal == 0 and #fixture.state.added == 0,
		"Rejected transaction polluted root journal"
	)
	table.insert(refusals, name)
end
reject("Play", function(f)
	f.run.running = true
end)
reject("foreign file", function(f)
	f.game.Name = "Foreign.rbxl"
end)
reject("A variant", function(f)
	f.map:SetAttribute("HarvestArtVariant", "A")
end)
reject("wrong phase", function(f)
	f.state.phase = "built"
end)
reject("missing version", function(f)
	f.map:SetAttribute("BManualAuthoringVersion", nil)
end)
reject("extra Source", function(f)
	local m = r.Instance.new("ModuleScript")
	m.Name, m.Source, m.Parent = "Extra", "return nil", f.resolve("ReplicatedStorage")
end)
reject("new path collision", function(f)
	local m = r.Instance.new("Folder")
	m.Name, m.Parent = "ManualScene", f.resolve("ReplicatedStorage/GameShared/Game")
end)
reject("Fog author edit", function(f)
	f.resolve("Workspace/CornfieldFog/RuntimeServer").Source ..= "-- author"
end)
reject("editor buffer", function(f)
	local path = next(f.payload.sourceChanges)
	f.editor.dirty[f.resolve(path)] = "return 'author'"
end)
reject("wrong change set", function(f)
	local path = next(f.payload.sourceChanges)
	f.payload.sourceChanges[path] = nil
end)
reject("Source pin", function(f)
	local _, row = next(f.payload.newSources)
	row.source ..= "-- pin mismatch"
end)
reject("syntax", function(f)
	local _, row = next(f.payload.newSources)
	row.source = "return ("
	row.sha256 = hash(row.source)
end)
for point = 1, 14 do
	local injection = "local fixtureWrites=0;local function fixtureFault() fixtureWrites+=1;if fixtureWrites=="
		.. point
		.. " then error('injected write failure') end end\n"
		.. code
	local a, b
	injection, a =
		injection:gsub("item.Source = row.source", "item.Source = row.source\nfixtureFault()")
	injection, b = injection:gsub("item.Parent = parent", "item.Parent = parent\nfixtureFault()")
	check(a == 2 and b == 1, "Fault hook patterns changed")
	reject("rollback:" .. point, nil, injection)
	table.insert(rollbacks, point)
end
local report = {
	passed = true,
	checks = checks,
	refusals = refusals,
	rollbackPoints = rollbacks,
	changedSources = 8,
	newSources = 3,
	totalSources = 171,
	sceneIO = false,
}
fs.writeFile(
	".artifacts/playtests/2026-10-23-B-manual-authoring/source-installer-fixture.json",
	serde.encode("json", report)
)
print(serde.encode("json", report))
