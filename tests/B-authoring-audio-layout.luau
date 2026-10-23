-- Actual B CornLayout; no Studio audio, GPU, physics or networking acceptance.
local adapter = require("./scene-adapter")
local fs, r, I = adapter.fs, adapter.r, adapter.I
local CF, V3 = r.CFrame, r.Vector3
local signals = {}
for _, name in { "DescendantAdded", "DescendantRemoving" } do
	r.implementProperty("Instance", name, function(item)
		signals[item] = signals[item] or {}
		if not signals[item][name] then
			local callbacks = {}
			signals[item][name] = {
				Connect = function(_, callback)
					table.insert(callbacks, callback)
					return {
						Disconnect = function()
							table.clear(callbacks)
						end,
					}
				end,
				Fire = function()
					for _, callback in callbacks do
						callback()
					end
				end,
			}
		end
		return signals[item][name]
	end)
end
local checks = 0
local function check(value, reason)
	assert(value, reason)
	checks += 1
end
local function child(parent, class, name)
	local item = I.new(class)
	item.Name, item.Parent = name, parent
	return item
end
local map = I.new("Model")
local storage = I.new("ReplicatedStorage")
map.Name = "CornMap"
map:SetAttribute("corn_project_id", "children_of_corn")
map:SetAttribute("HarvestArtVariant", "B")
map:SetAttribute("BManualAuthoringVersion", 1)
local field = child(map, "Part", "FieldZone")
field.Size, field.CFrame = V3.new(630, 10, 630), CF.new(0, 19, 0)
local source = child(map, "Folder", "CornAuthoring")
source:SetAttribute("corn_project_id", "children_of_corn")
source:SetAttribute("BManualAuthoringVersion", 1)
local group = child(source, "Model", "Chunk")
local function plant(x, opacity)
	local item = child(group, "MeshPart", "Corn")
	item.Size, item.CFrame = V3.new(3, 8, 3), CF.new(x, 18, 0)
	item:SetAttribute("HarvestRootOffset", V3.new(0, 4, 0))
	item:SetAttribute("CornGreenTemplateSize", V3.new(3, 8, 3))
	item:SetAttribute("BManualSourceTransparency", opacity or 0)
	item.Transparency = 1
	return item
end
local moved = plant(0)
moved.CFrame = CF.new(40, 18, 0)
local deleted = plant(5)
plant(10, 1)
local spawns = child(map, "Folder", "CornerSpawns")
local spawn = child(spawns, "Part", "SW")
spawn:AddTag("corn_spawn")
spawn.CFrame = CF.new(123, 14, 37)
local slots = child(map, "Folder", "KeySlots")
local slot = child(slots, "Part", "Slot")
slot:AddTag("corn_key_slot")
slot.CFrame = CF.new(-200, 14, -100)
local frozen = {
	Signature = "frozen-signature-that-manual-layout-cannot-match",
	GetHeight = function()
		error("Frozen soil projection entered manual audio")
	end,
	Contains = function()
		error("Frozen soil coverage entered manual audio")
	end,
}
local fn = assert(loadstring(fs.readFile("variants/B/shared/Game/CornLayout.luau")))
setfenv(
	fn,
	setmetatable({
		CFrame = CF,
		Vector3 = V3,
		Vector2 = r.Vector2,
		script = { Parent = { GreenBedLayout = {} } },
		require = function()
			return frozen
		end,
		game = {
			GetService = function(_, name)
				if name == "ReplicatedStorage" then
					return storage
				end
				return {
					IsClient = function()
						return false
					end,
				}
			end,
		},
	}, { __index = getfenv() })
)
local layout = fn()
local exclusions = layout.ReadExclusions(map, field)
check(
	exclusions.AuthoredCorn and exclusions.AuthoredCorn.Count == 2,
	"Moved spawn/slot still entered frozen guard or hidden plants counted"
)
check(not layout.IsExcluded(V3.new(40, 14, 0), exclusions), "Moved plant not at its actual root")
check(layout.IsExcluded(V3.new(0, 14, 0), exclusions), "Old procedural root still rustles")
check(layout.IsExcluded(V3.new(10, 14, 0), exclusions), "Author hidden plant still rustles")
check(not layout.IsExcluded(V3.new(5, 14, 0), exclusions), "Visible authored plant missing")
local buckets = exclusions.AuthoredCorn.Buckets
for _ = 1, 1000 do
	layout.IsExcluded(V3.new(40.2, 14, 0.1), exclusions)
end
check(
	exclusions.AuthoredCorn.Buckets == buckets,
	"Audio queries repeatedly rescanned authored scene"
)
deleted:Destroy()
signals[source].DescendantRemoving:Fire()
check(
	layout.IsExcluded(V3.new(5, 14, 0), exclusions),
	"Deleted source still produces audio coverage"
)
check(exclusions.AuthoredCorn.Count == 1, "Deleted source cache did not invalidate")
local copied = moved:Clone()
copied.CFrame, copied.Parent = CF.new(60, 18, 0), group
signals[source].DescendantAdded:Fire()
check(
	not layout.IsExcluded(V3.new(60, 14, 0), exclusions) and exclusions.AuthoredCorn.Count == 2,
	"Added/duplicated source missing from held audio exclusions"
)
check(
	exclusions.AuthoredCorn.Width > 2 * exclusions.AuthoredCorn.Radius,
	"Audio query can visit more than four buckets"
)
check(layout.IsExcluded(V3.new(400, 14, 0), exclusions), "Audio accepted outside FieldZone")
check(
	layout.ReadExclusions(map, field).AuthoredCorn == exclusions.AuthoredCorn,
	"Unchanged source cache not reused"
)
local archive = child(storage, "Folder", "BManualEditorSources")
archive:SetAttribute("corn_project_id", "children_of_corn")
archive:SetAttribute("BManualAuthoringVersion", 1)
local archived = child(archive, "Folder", "CornAuthoring")
archived:SetAttribute("corn_project_id", "children_of_corn")
archived:SetAttribute("BManualAuthoringVersion", 1)
group.Parent = archived
for _, item in { moved, copied } do
	item:SetAttribute("BManualSourceTransparency", nil)
	item.Transparency = 0
end
local replicatedExclusions = layout.ReadExclusions(map, field)
check(
	replicatedExclusions.AuthoredCorn.Source == archived
		and replicatedExclusions.AuthoredCorn.Count == 2,
	"Audio did not prioritize archived source over empty Workspace placeholder"
)
check(
	not layout.IsExcluded(V3.new(40, 14, 0), replicatedExclusions),
	"Archived visible corn did not produce audio coverage"
)
check(
	moved.Transparency == 0 and moved:GetAttribute("BManualSourceTransparency") == nil,
	"Audio source resolution rewrote archived visibility"
)
map:SetAttribute("BManualAuthoringVersion", nil)
check(not pcall(layout.ReadExclusions, map, field), "Legacy frozen layout guard was weakened")
print(
	"PASS: "
		.. checks
		.. " authored audio actual-root/moved spawn/hidden/delete/duplicate/cache/legacy guard checks"
)
