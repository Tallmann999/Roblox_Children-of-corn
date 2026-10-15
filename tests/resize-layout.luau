-- Actual generated resize installer against an in-memory exact engine scene.
-- Limited Lune property adapter, no serialized scene writes or Studio claim.
local adapter = require("./scene-adapter")
local fs, r, I = adapter.fs, adapter.r, adapter.I
local serde = require("@lune/serde")
local baseline = "place/Children_of_corn.before-resize-yellow-20261015.rbxl"
local bytes = fs.readFile(baseline)
local source = fs.readFile("scripts/install-resize-layout.luau")
local refValues = {}
local function fixtureRefGet(item)
	local state = refValues[item]
	return if state then state.value else item.Value
end
local function fixtureRefSet(item, value)
	-- Lune cannot assign nil into reflected Ref. A bounded overlay implements
	-- only ObjectValue.Value nil/read/restore; Studio uses the real setter.
	refValues[item] = { value = value }
	if value ~= nil then
		item.Value = value
	end
end
local manifest = serde.decode("json", fs.readFile("scripts/resize-layout.json"))
local allowedCF, allowedSize = {}, {}
for _, row in manifest.property_changes do
	if row.property == "CFrame" then
		allowedCF[row.uid] = true
	elseif row.property == "size" then
		allowedSize[row.uid] = true
	end
end
assert(
	manifest.summary.counts.EditorPreview == 904 and #manifest.removed_plants == 2684,
	"Fixed manifest changed"
)
r.implementProperty("Model", "WorldPivot", function(item)
	return item.WorldPivotData
end, function(item, value)
	item.WorldPivotData = value
end)
r.implementProperty("MeshPart", "MeshId", function(item)
	return item.MeshContent.Uri
end, function(item, value)
	item.MeshContent = r.Content.fromUri(value)
end)
r.implementProperty("MeshPart", "TextureID", function(item)
	return item.TextureContent.Uri
end, function(item, value)
	item.TextureContent = r.Content.fromUri(value)
end)
local function setup()
	local place = r.deserializePlace(bytes)
	place:GetService("RunService")
	place:GetService("ChangeHistoryService")
	-- Lune reflects old string/pivot aliases as inert fields. Seed them from
	-- decoded Content/OptionalCFrame; this fixture checks intended property
	-- operations, while actual Studio independently checks engine coupling.
	for _, item in place:GetDescendants() do
		if item:IsA("Model") and item.WorldPivotData then
			item.WorldPivot = item.WorldPivotData
		end
		if item:IsA("MeshPart") then
			item.MeshId = item.MeshContent.Uri or ""
			item.TextureID = item.TextureContent.Uri or ""
		end
	end
	return place
end
local function run(place, code, running, studio, yieldAt)
	local yields = 0
	local proxy = {
		FindFirstChild = function(_, name)
			return place:FindFirstChild(name)
		end,
		GetService = function(_, name)
			if name == "RunService" then
				return {
					IsStudio = function()
						return studio ~= false
					end,
					IsRunning = function()
						return running == true or (yieldAt ~= nil and yields >= yieldAt)
					end,
				}
			end
			return place:GetService(name)
		end,
	}
	local fixtureCode = (code or source):gsub(
		'"Unknown saved corn position"',
		'"Unknown saved corn position "..folderName.."/"..id.."/"..tostring(item.CFrame)'
	)
	fixtureCode = fixtureCode:gsub(
		"local function refGet%(item%) return item.Value end",
		"local function refGet(item) return fixtureRefGet(item) end"
	)
	fixtureCode = fixtureCode:gsub(
		"local function refSet%(item,value%) item.Value=value end",
		"local function refSet(item,value) fixtureRefSet(item,value) end"
	)
	local fn = assert(loadstring(fixtureCode))
	setfenv(
		fn,
		setmetatable({
			game = proxy,
			workspace = place:GetService("Workspace"),
			CFrame = r.CFrame,
			Vector3 = r.Vector3,
			Color3 = r.Color3,
			typeof = typeof,
			fixtureRefGet = fixtureRefGet,
			fixtureRefSet = fixtureRefSet,
			task = {
				wait = function()
					yields += 1
				end,
			},
		}, { __index = getfenv() })
	)
	return pcall(fn)
end
local function snap(place)
	local rows = {}
	for _, item in place:GetDescendants() do
		local row = {
			parent = item.Parent,
			name = item.Name,
			attrs = item:GetAttributes(),
			tags = item:GetTags(),
			class = item.ClassName,
			uid = tostring(item.UniqueId),
		}
		if item:IsA("BasePart") then
			row.cf = item.CFrame
			row.size = item.Size
			row.color = item.Color
		end
		if item:IsA("MeshPart") then
			row.mesh = item.MeshId
			row.texture = item.TextureID
		end
		if item:IsA("Model") and item.WorldPivotData then
			row.pivot = item.WorldPivot
		end
		if item:IsA("ObjectValue") then
			row.isRef = true
			row.value = fixtureRefGet(item)
		end
		if item:IsA("LuaSourceContainer") then
			row.source = item.Source
		end
		rows[item] = row
	end
	return rows
end
local function sameTable(a, b)
	for k, v in a do
		assert(b[k] == v, "Table field changed: " .. k)
	end
	for k in b do
		assert(a[k] ~= nil, "Table field added: " .. k)
	end
end
local function unchanged(place, before, rollbackWrites)
	local count = 0
	for _, item in place:GetDescendants() do
		count += 1
		assert(before[item], "Instance added")
	end
	local expected = 0
	for item, row in before do
		expected += 1
		assert(
			item.Parent == row.parent and item.Name == row.name and item.ClassName == row.class,
			"Instance identity changed"
		)
		sameTable(row.attrs, item:GetAttributes())
		sameTable(row.tags, item:GetTags())
		if row.cf then
			local sameFrame = item.CFrame == row.cf
			local sameSize = item.Size == row.size
				or (
					rollbackWrites
					and allowedSize[row.uid]
					and (item.Size - row.size).Magnitude < 0.00002
				)
			if not sameFrame and rollbackWrites and allowedCF[row.uid] then
				sameFrame = true
				local actual, expectedFrame =
					{ item.CFrame:GetComponents() }, { row.cf:GetComponents() }
				for index, value in actual do
					if math.abs(value - expectedFrame[index]) > 0.00002 then
						sameFrame = false
					end
				end
			end
			assert(
				sameFrame and sameSize and item.Color == row.color,
				"Geometry changed: "
					.. item:GetFullName()
					.. " CFrame "
					.. tostring(item.CFrame)
					.. " expected "
					.. tostring(row.cf)
					.. " size "
					.. tostring(item.Size)
					.. " expected "
					.. tostring(row.size)
			)
		end
		if row.mesh then
			assert(item.MeshId == row.mesh and item.TextureID == row.texture, "Art changed")
		end
		if row.pivot then
			assert(item.WorldPivot == row.pivot, "Pivot changed")
		end
		if row.isRef then
			assert(fixtureRefGet(item) == row.value, "Reference changed")
		end
		if row.source then
			assert(item.Source == row.source, "Source changed")
		end
	end
	assert(count == expected, "Instance removed")
end
local place = setup()
local removedIDs = {}
for _, row in manifest.removed_plants do
	removedIDs[row.uid] = true
end
local orphanCopies = {}
for _, item in place:GetService("Workspace").CornMap.Props.VillageRoad.HiddenCornIndex:GetChildren() do
	if item.Value and removedIDs[tostring(item.Value.UniqueId)] then
		table.insert(orphanCopies, { item = item, leaf = item.Value:Clone() })
	end
end
assert(#orphanCopies == 193, "Wrong fixed orphan reference count")
local ok, result = run(place)
assert(ok, tostring(result))
assert(
	result.fieldSide == 630
		and result.removed == 2684
		and result.preview == 904
		and result.overview == 2576
		and not result.repeated,
	"Wrong output"
)
assert(
	place:GetService("Workspace").CornMap.FieldZone.Size == r.Vector3.new(630, 10, 630),
	"Field wrong"
)
assert(#place:GetService("Workspace").CornMap.KeySlots:GetChildren() == 15, "Slots lost")
assert(#place:GetService("Workspace").CornMap.TorchMarkers:GetChildren() == 27, "Torches lost")
local after = snap(place)
ok, result = run(place)
assert(ok, tostring(result))
assert(result.repeated and result.changed == 0, "Repeat must not write")
unchanged(place, after)
-- Exact legacy after geometry from the first Studio installation retained all
-- 193 detached original leaf references. Clone copies emulate those accessible
-- leaf fingerprints in Lune; no foreign object is mutated during cleanup.
for _, entry in orphanCopies do
	fixtureRefSet(entry.item, entry.leaf)
end
local orphanBefore = snap(place)
local broken = source:gsub(
	"%-%- RESIZE_AFTER_REFERENCE_REPAIR",
	'if #repaired==87 then error("Injected reference repair")end'
)
ok, result = run(place, broken)
assert(not ok and tostring(result):find("rolled back", 1, true), "Reference repair rollback failed")
unchanged(place, orphanBefore, true)
orphanCopies[1].leaf.TextureID = "rbxassetid://999"
ok, result = run(place)
assert(not ok, "Unknown orphan art accepted")
orphanCopies[1].leaf.TextureID = "rbxassetid://137803536172445"
fixtureRefSet(orphanCopies[1].item, nil)
ok, result = run(place)
assert(not ok, "Partial legacy reference cleanup accepted")
fixtureRefSet(orphanCopies[1].item, orphanCopies[1].leaf)
ok, result = run(place)
assert(ok, tostring(result))
assert(
	result.referenceCleanup and result.changed == 193,
	"Legacy repair must only clear193references"
)
ok, result = run(place)
assert(ok and result.repeated and result.changed == 0, "Reference cleanup repeat must write0")
local rejected = 0
for _, kind in
	{
		"running",
		"not-studio",
		"wrong-project",
		"wrong-scene",
		"runtime",
		"manual-slot",
		"partial-field",
		"manual-barn",
		"manual-plant",
		"plant-size",
		"plant-texture",
		"foreign-child",
		"plant-child",
		"slot-tag",
		"torch-light",
		"barrel-reorder",
		"wrong-reference",
	}
do
	local fixture = setup()
	local map = fixture:GetService("Workspace").CornMap
	if kind == "wrong-project" then
		map:SetAttribute("corn_project_id", "foreign")
	end
	if kind == "wrong-scene" then
		local x = I.new("Folder")
		x.Name = "Asmr_Base"
		x.Parent = fixture:GetService("Workspace")
	end
	if kind == "runtime" then
		local x = I.new("Folder")
		x.Name = "CornRoundRuntime"
		x.Parent = map
	end
	if kind == "manual-slot" then
		map.KeySlots.solo_slot_01.CFrame += r.Vector3.new(0.1, 0, 0)
	end
	if kind == "partial-field" then
		map.Ground.Size = r.Vector3.new(630, 2, 630)
	end
	if kind == "manual-barn" then
		map.Props.HouseWest.SM_Bld_Barn_03.CFrame += r.Vector3.new(1, 0, 0)
	end
	local corn = map.EditorPreview:GetChildren()[1]
	if kind == "manual-plant" then
		corn.CFrame += r.Vector3.new(0.1, 0, 0)
	end
	if kind == "plant-size" then
		corn.Size += r.Vector3.new(0.1, 0, 0)
	end
	if kind == "plant-texture" then
		corn.TextureID = "rbxassetid://999"
	end
	if kind == "foreign-child" then
		local x = I.new("Part")
		x.Parent = map.EditorPreview
	end
	if kind == "plant-child" then
		local x = I.new("Folder")
		x.Parent = corn
	end
	if kind == "slot-tag" then
		map.KeySlots.solo_slot_01:RemoveTag("corn_key_slot")
	end
	if kind == "torch-light" then
		map.TorchMarkers.torch_solo_slot_01.Flame.TorchLight.Brightness = 2
	end
	if kind == "barrel-reorder" then
		-- A known full before must remain valid regardless of same-name sibling order.
		local b = map.Props:FindFirstChild("LookoutBarrel")
		b.Parent = nil
		b.Parent = map.Props
		ok, result = run(fixture)
		assert(ok, tostring(result))
		continue
	end
	if kind == "wrong-reference" then
		map.Props.VillageRoad.HiddenCornIndex:GetChildren()[1].Value = corn
	end
	local before = snap(fixture)
	ok, result = run(fixture, nil, kind == "running", kind ~= "not-studio")
	assert(not ok, "Unsafe resize accepted: " .. kind)
	unchanged(fixture, before)
	rejected += 1
end
for _, where in { "first", "middle", "last-plant" } do
	local fixture = setup()
	local before = snap(fixture)
	local code
	if where == "first" then
		code = source:gsub("%-%- RESIZE_AFTER_WRITE", 'if #changed==1 then error("Injected")end')
	elseif where == "middle" then
		code = source:gsub("%-%- RESIZE_AFTER_WRITE", 'if #changed==50 then error("Injected")end')
	else
		code = source:gsub("%-%- RESIZE_AFTER_PLANT", 'if #removed==2684 then error("Injected")end')
	end
	ok, result = run(fixture, code)
	assert(
		not ok and tostring(result):find("rolled back", 1, true),
		"Expected rollback: " .. tostring(result)
	)
	unchanged(fixture, before, true)
end
for _, yieldAt in { 1, 12 } do
	local fixture = setup()
	local before = snap(fixture)
	ok, result = run(fixture, nil, false, true, yieldAt)
	assert(not ok, "Play during batch yield was accepted")
	unchanged(fixture, before, true)
end
assert(fs.readFile(baseline) == bytes, "Immutable baseline changed")
print(
	"PASS: actual generated resize630/27torches/15slots/904preview/2576overview, dry-before-visible, fullrepeat0; "
		.. rejected
		.. "refusals; same-name barrel ordering; rollbackfirst/middle/plant; exact immutablebytes. Lune adapter only."
)
