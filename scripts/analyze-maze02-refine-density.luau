-- Read-only scene analysis. Changes are applied only to a private deserialized
-- model; no Roblox instances or scene files are serialized or installed.
local adapter = require("../tests/scene-adapter")
local fs, r = adapter.fs, adapter.r
local serde = require("@lune/serde")
local process = require("@lune/process")
local OUT = ".artifacts/playtests/2026-10-21-maze02-refine/"
local baseline = serde.decode("json", fs.readFile(OUT .. "baseline.json"))
local plan = serde.decode("json", fs.readFile(OUT .. "path-plan.json"))
local payloadBytes = fs.readFile(OUT .. "payload.json")
local payload = serde.decode("json", payloadBytes)
local scenePath = process.args[1] or "before-refine.zip#checkpoint/B-before-refine.rbxl"
local sceneBytes = if process.args[1]
	then fs.readFile(process.args[1])
	else require("./read-maze02-refine-baseline").Read()
assert(
	serde.hash("sha256", sceneBytes) == baseline.baseline_sha256,
	"Exact saved maze-02 baseline required"
)
assert(#sceneBytes == baseline.baseline_bytes and plan.baseline_sha256 == baseline.baseline_sha256)
assert(payload.owner == "corn_maze02_refine_v1" and #plan.changes == 399)
local placeBefore = r.deserializePlace(sceneBytes)
local placeAfter = r.deserializePlace(sceneBytes)
local pathIndex = {}
for _, item in placeAfter:GetDescendants() do
	local path = item:GetFullName():gsub("%.", "/")
	pathIndex[path] = pathIndex[path] or {}
	table.insert(pathIndex[path], item)
end
local function typed(value)
	if type(value) ~= "table" then
		return value
	end
	assert(type(value.value) == "table", "Unknown typed value")
	if value.kind == "Vector3" then
		return r.Vector3.new(table.unpack(value.value))
	end
	if value.kind == "CFrame" then
		return r.CFrame.new(table.unpack(value.value))
	end
	error("Unsupported plan type " .. tostring(value.kind))
end
local function close(a, b)
	if typeof(a) == "CFrame" and typeof(b) == "CFrame" then
		local aa, bb = { a:GetComponents() }, { b:GetComponents() }
		for index, value in aa do
			if math.abs(value - bb[index]) > 0.0001 then
				return false
			end
		end
		return true
	elseif typeof(a) == "Vector3" and typeof(b) == "Vector3" then
		return (a - b).Magnitude < 0.0001
	end
	return a == b
end
for _, change in plan.changes do
	local matches = {}
	for _, item in pathIndex[change.path] or {} do
		local selected = true
		for property, value in change.selector or {} do
			if not close(item[property], typed(value)) then
				selected = false
				break
			end
		end
		if selected then
			table.insert(matches, item)
		end
	end
	assert(#matches == 1, "Ambiguous/missing plan target: " .. change.path)
	local item = matches[1]
	local before = if change.attribute
		then item:GetAttribute(change.property)
		else item[change.property]
	assert(
		close(before, typed(change.before)),
		"Before-value mismatch: " .. change.path .. "/" .. change.property
	)
	if change.attribute then
		item:SetAttribute(change.property, typed(change.after))
	else
		item[change.property] = typed(change.after)
	end
end
local function layout(source)
	-- Lune omits the engine Position getter on some saved fixture parts.
	source = source:gsub("item%.Position", "item.CFrame.Position")
	local fn = assert(loadstring(source, "CornLayout density analysis"))
	setfenv(
		fn,
		setmetatable(
			{ CFrame = r.CFrame, Vector3 = r.Vector3, Vector2 = r.Vector2 },
			{ __index = getfenv() }
		)
	)
	return fn()
end
local oldModule = placeBefore:GetService("ReplicatedStorage").GameShared.Game.CornLayout
local sourceRow = assert(payload.sourceChanges["ReplicatedStorage/GameShared/Game/CornLayout"])
assert(serde.hash("sha256", oldModule.Source:gsub("\r\n", "\n")) == sourceRow.before_sha256)
assert(serde.hash("sha256", sourceRow.source) == sourceRow.after_sha256)
assert(
	serde.hash("sha256", fs.readFile("src/shared/Game/CornLayout.luau"):gsub("\r\n", "\n"))
		== sourceRow.after_sha256
)
local oldLayout, newLayout = layout(oldModule.Source), layout(sourceRow.source)
local mapBefore, mapAfter =
	placeBefore:GetService("Workspace").CornMap, placeAfter:GetService("Workspace").CornMap
assert(
	mapBefore:GetAttribute("HarvestArtVariant") == "B"
		and mapAfter:GetAttribute("HarvestArtVariant") == "B"
)
local function measure(module, map)
	local started = os.clock()
	local field = map.FieldZone
	local exclusions = module.ReadExclusions(map, field)
	local minColumn, maxColumn, minRow, maxRow = module.GetCellBounds(field)
	local firstColumn, lastColumn = math.ceil(minColumn / 2) * 2, math.floor(maxColumn / 2) * 2
	local firstRow, lastRow = math.ceil(minRow / 2) * 2, math.floor(maxRow / 2) * 2
	local count = 0
	for column = firstColumn, lastColumn, 2 do
		for row = firstRow, lastRow, 2 do
			if not module.IsExcluded(module.CellPosition(field, column, row), exclusions) then
				count += 1
			end
		end
	end
	local spacing = if module.SpacingFor then module.SpacingFor(field) else module.Spacing
	local candidates = ((lastColumn - firstColumn) / 2 + 1) * ((lastRow - firstRow) / 2 + 1)
	assert(
		candidates <= 20000 and count > 0 and count <= candidates,
		"Backdrop cap would reject this grid"
	)
	return {
		spacing = spacing,
		nominal_density = 1 / (spacing * spacing),
		chunk_width = spacing * module.ChunkCells,
		far_stride_cells = 2,
		far_stride_studs = spacing * 2,
		dense_candidate_cells = (maxColumn - minColumn + 1) * (maxRow - minRow + 1),
		far_candidate_cells = candidates,
		far_plants = count,
		far_excluded_cells = candidates - count,
		exclusion_boxes = #exclusions.Boxes,
		exclusion_circles = #exclusions.Circles,
		far_plant_cap = 20000,
		elapsed_analysis_seconds = os.clock() - started,
	}
end
local before = measure(oldLayout, mapBefore)
local narrowOnly = measure(oldLayout, mapAfter)
local densityOnly = measure(newLayout, mapBefore)
local combined = measure(newLayout, mapAfter)
local report = {
	schema_version = 1,
	baseline_sha256 = baseline.baseline_sha256,
	payload_sha256 = serde.hash("sha256", payloadBytes),
	before_layout_source_sha256 = sourceRow.before_sha256,
	after_layout_source_sha256 = sourceRow.after_sha256,
	private_model_changes = #plan.changes,
	before = before,
	narrow_paths_only = narrowOnly,
	density_only = densityOnly,
	after = combined,
	nominal_density_increase_percent = (combined.nominal_density / before.nominal_density - 1)
		* 100,
	far_increase_from_narrow_paths_percent = (narrowOnly.far_plants / before.far_plants - 1) * 100,
	far_increase_from_density_percent = (densityOnly.far_plants / before.far_plants - 1) * 100,
	far_increase_combined_percent = (combined.far_plants / before.far_plants - 1) * 100,
	note = "Counts use production CornLayout CellPosition and IsExcluded with the accepted saved B and declared 399 path/editor deltas. Native rendering, timing, visibility and LOD overlap are separate checks. No scene serialization or installation.",
}
fs.writeFile(OUT .. "density-analysis.json", serde.encode("json", report, true))
print(serde.encode("json", report))
