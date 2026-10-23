-- Executes actual ManualSceneService with small Lune Instances and write-counting
-- proxies. No native replication, renderer, scene I/O or performance claim.
local adapter = require("./scene-adapter")
local fs, r, I = adapter.fs, adapter.r, adapter.I
local serde = require("@lune/serde")
local code = fs.readFile("variants/B/server/Services/ManualSceneService.luau")
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end
local function child(parent, class, name)
	local result = I.new(class)
	result.Name, result.Parent = name, parent
	return result
end
local function sameFrame(a, b)
	for index, value in { a:GetComponents() } do
		check(value == ({ b:GetComponents() })[index], "Authored CFrame changed")
	end
end
local function sameAttributes(a, b)
	for key, value in a do
		check(b[key] == value, "Authored attribute changed: " .. key)
	end
	for key in b do
		check(a[key] ~= nil, "Unexpected authored attribute: " .. key)
	end
end
local function fixture(options)
	options = options or {}
	local world, storage = I.new("Workspace"), I.new("ReplicatedStorage")
	local gameFolder = child(child(storage, "Folder", "GameShared"), "Folder", "Game")
	local manualModule = child(gameFolder, "ModuleScript", "ManualScene")
	local map = child(world, "Model", "CornMap")
	map:SetAttribute("corn_project_id", "children_of_corn")
	map:SetAttribute("HarvestArtVariant", options.variant or "B")
	map:SetAttribute("BManualAuthoringVersion", 1)
	local corn = child(map, "Folder", "CornAuthoring")
	local plants, chunks, before = {}, {}, {}
	local function plant(parent, index)
		local part = child(parent, "MeshPart", "Corn_" .. index)
		part.CFrame = r.CFrame.new(index * 2.7, 18 + index / 10, -index * 3.1)
			* r.CFrame.Angles(0.1, index / 7, 0.03)
		part.Size = r.Vector3.new(1.1, 6.8 + index / 10, 1.4)
		part.Transparency = index / 100
		part.Color = r.Color3.fromRGB(20 + index, 120 + index, 35)
		part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
		part.CastShadow = true
		part:SetAttribute("corn_project_id", "children_of_corn")
		part:SetAttribute("CornGreenVariety", index % 4 + 1)
		part:SetAttribute("CornAuthorColumn", index)
		part:SetAttribute("AuthorNote", "retained " .. index)
		part:AddTag("fixture_authored_plant")
		table.insert(plants, part)
		before[part] = {
			frame = part.CFrame,
			size = part.Size,
			opacity = part.Transparency,
			color = part.Color,
			attributes = part:GetAttributes(),
			parent = parent,
		}
		return part
	end
	for index = 1, options.chunks or 3 do
		local model = child(corn, "Model", "Chunk_" .. index)
		model:SetAttribute("corn_project_id", "children_of_corn")
		model:SetAttribute("AuthorChunk", index)
		table.insert(chunks, model)
		plant(model, index * 2)
		plant(model, index * 2 + 1)
	end
	local direct = plant(corn, 90)
	table.insert(chunks, direct)
	local helper = child(map, "Part", "StartHelper")
	helper.Transparency = 0.35
	helper.CanCollide, helper.CanTouch, helper.CanQuery = true, true, true
	helper:SetAttribute("BAuthoringHelper", true)
	local label = child(helper, "BillboardGui", "EditorLabel")
	label.Enabled = true
	label:SetAttribute("BAuthoringHelper", true)
	local ordinary = child(map, "Part", "Unrelated")
	ordinary.Transparency = 0.2
	ordinary.CanCollide, ordinary.CanTouch, ordinary.CanQuery = true, true, true
	local ordinaryLabel = child(ordinary, "BillboardGui", "NormalLabel")
	ordinaryLabel.Enabled = true
	local unknown
	if options.unknownPool then
		unknown = child(storage, "Folder", "BManualEditorSources")
		unknown:SetAttribute("AuthorData", "preserve")
		child(unknown, "Part", "UnrelatedAuthorPart")
	end
	local wrapped, raw, writes, attributeWrites = {}, {}, {}, {}
	local methods = {}
	local wrap
	local function unwrap(value)
		return raw[value] or value
	end
	local function list(items)
		local result = {}
		for _, item in items do
			table.insert(result, wrap(item))
		end
		return result
	end
	function methods:GetChildren()
		return list(raw[self]:GetChildren())
	end
	function methods:GetDescendants()
		return list(raw[self]:GetDescendants())
	end
	function methods:FindFirstChild(name)
		return wrap(raw[self]:FindFirstChild(name))
	end
	function methods:IsA(class)
		return raw[self]:IsA(class)
	end
	function methods:GetAttribute(name)
		return raw[self]:GetAttribute(name)
	end
	function methods:SetAttribute(name, value)
		local item = raw[self]
		attributeWrites[item] = (attributeWrites[item] or 0) + 1
		item:SetAttribute(name, value)
	end
	wrap = function(item)
		if not item then
			return nil
		end
		if wrapped[item] then
			return wrapped[item]
		end
		local proxy = {}
		wrapped[item], raw[proxy] = proxy, item
		setmetatable(proxy, {
			__index = function(_, key)
				if methods[key] then
					return methods[key]
				end
				local value = item[key]
				return if typeof(value) == "Instance" then wrap(value) else value
			end,
			__newindex = function(_, key, value)
				writes[item] = writes[item] or {}
				writes[item][key] = (writes[item][key] or 0) + 1
				item[key] = unwrap(value)
			end,
		})
		return proxy
	end
	local yields, logs = 0, {}
	local gameProxy = {}
	function gameProxy:GetService(name)
		if name == "ReplicatedStorage" then
			return wrap(storage)
		end
		if name == "RunService" then
			return {
				IsStudio = function()
					return options.studio ~= false
				end,
			}
		end
		error(name)
	end
	local chunk = assert(loadstring(code, "ManualSceneService"))
	setfenv(
		chunk,
		setmetatable({
			game = gameProxy,
			workspace = wrap(world),
			Instance = {
				new = function(class)
					return wrap(I.new(class))
				end,
			},
			require = function(module)
				check(raw[module] == manualModule, "Unexpected module dependency")
				return {
					IsTarget = function(candidate)
						return candidate
							and candidate:GetAttribute("corn_project_id") == "children_of_corn"
							and candidate:GetAttribute("HarvestArtVariant") == "B"
							and candidate:GetAttribute("BManualAuthoringVersion") == 1
					end,
				}
			end,
			task = {
				wait = function()
					yields += 1
				end,
			},
			print = function(...)
				table.insert(logs, { ... })
			end,
		}, { __index = getfenv() })
	)
	local service = chunk()
	return {
		world = world,
		storage = storage,
		map = map,
		corn = corn,
		plants = plants,
		chunks = chunks,
		before = before,
		direct = direct,
		helper = helper,
		label = label,
		ordinary = ordinary,
		ordinaryOpacity = ordinary.Transparency,
		ordinaryLabel = ordinaryLabel,
		unknown = unknown,
		writes = writes,
		attributeWrites = attributeWrites,
		logs = logs,
		run = function()
			service:Init({ Config = { Environment = options.environment or "DEV" } })
		end,
		yields = function()
			return yields
		end,
	}
end
local good = fixture()
good.run()
local pool = good.storage:FindFirstChild("BManualEditorSources")
local source = pool and pool:FindFirstChild("CornAuthoring")
check(source ~= nil and source:GetAttribute("BManualServerReady") == true, "Pool readiness missing")
check(
	pool:GetAttribute("corn_project_id") == "children_of_corn"
		and pool:GetAttribute("BManualAuthoringVersion") == 1,
	"Pool ownership missing"
)
check(
	#good.corn:GetChildren() == 0 and #source:GetChildren() == #good.chunks,
	"Chunks not fully transferred"
)
for _, chunk in good.chunks do
	check(
		chunk.Parent == source and good.writes[chunk].Parent == 1,
		"Each chunk must move exactly once"
	)
end
for _, part in good.plants do
	local old = good.before[part]
	sameFrame(part.CFrame, old.frame)
	check(
		part.Size == old.size and part.Transparency == old.opacity and part.Color == old.color,
		"Authored size/opacity/color changed"
	)
	sameAttributes(old.attributes, part:GetAttributes())
	check(part:HasTag("fixture_authored_plant"), "Plant tag lost")
	check(not good.attributeWrites[part], "Per-plant attribute write")
	for key in good.writes[part] or {} do
		check(part == good.direct and key == "Parent", "Per-plant property write: " .. key)
	end
	check(
		part == good.direct or part.Parent == old.parent,
		"Plant identity/parent changed inside chunk"
	)
end
check(
	good.helper.Transparency == 1
		and not good.helper.CanCollide
		and not good.helper.CanTouch
		and not good.helper.CanQuery,
	"Editor helper still active"
)
check(not good.label.Enabled and good.ordinaryLabel.Enabled, "Helper label policy changed")
check(
	good.ordinary.Transparency == good.ordinaryOpacity
		and good.ordinary.CanCollide
		and not good.writes[good.ordinary],
	"Unrelated art changed"
)
local unknown = fixture({ unknownPool = true })
local oldPool, oldChildren = unknown.unknown, #unknown.storage:GetDescendants()
local ok = pcall(unknown.run)
check(not ok, "Unknown pre-existing source pool accepted")
check(
	unknown.storage:FindFirstChild("BManualEditorSources") == oldPool
		and #unknown.storage:GetDescendants() == oldChildren,
	"Unknown pool replaced or modified"
)
check(
	oldPool:GetAttribute("AuthorData") == "preserve" and #oldPool:GetChildren() == 1,
	"Unknown pool content changed"
)
check(
	next(unknown.writes) == nil and next(unknown.attributeWrites) == nil,
	"Unknown pool refusal wrote world properties"
)
for _, options in { { studio = false }, { environment = "LIVE" }, { variant = "A" } } do
	local disabled = fixture(options)
	disabled.run()
	check(
		next(disabled.writes) == nil
			and next(disabled.attributeWrites) == nil
			and not disabled.storage:FindFirstChild("BManualEditorSources"),
		"Non-DEV/B session modified"
	)
end
local yielding = fixture({ chunks = 24 })
yielding.run()
check(yielding.yields() == 1, "Chunk transfer yield budget changed")
local report = {
	passed = true,
	checks = checks,
	chunks = 4,
	plants = 7,
	allAuthoredValuesExact = true,
	perPlantTransparencyWrites = 0,
	perPlantAttributeWrites = 0,
	helpersHidden = true,
	unknownPoolReadOnlyRefusal = true,
	sceneIO = false,
}
fs.writeFile(
	".artifacts/playtests/2026-10-23-B-manual-authoring/editor-pool-service-fixture.json",
	serde.encode("json", report)
)
print(serde.encode("json", report))
