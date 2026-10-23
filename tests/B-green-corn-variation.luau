-- Real B layout/soil queries, offline only; no Studio, GPU, or network claim.
local fs = require("@lune/fs")
local r = require("@lune/roblox")
local serde = require("@lune/serde")
local process = require("@lune/process")
local started = os.clock()
local function load(path, environment)
	local fn = assert(loadstring(fs.readFile(path), path))
	setfenv(fn, setmetatable(environment, { __index = getfenv() }))
	return fn()
end
local plan = load("variants/B/shared/Game/GreenBedLayout.luau", {
	game = {
		GetService = function()
			return {
				JSONDecode = function(_, text)
					return serde.decode("json", text)
				end,
			}
		end,
	},
	Vector3 = r.Vector3,
	CFrame = r.CFrame,
})
local layout = load("variants/B/shared/Game/CornLayout.luau", {
	script = { Parent = { GreenBedLayout = {} } },
	require = function()
		return plan
	end,
	Vector3 = r.Vector3,
	Vector2 = r.Vector2,
	CFrame = r.CFrame,
	Color3 = r.Color3,
})
local inputs = serde.decode(
	"json",
	fs.readFile(".artifacts/playtests/2026-10-22-B-green-beds/native-inputs.json")
)
local exclusions = { Boxes = {}, Circles = {}, TrailEdges = inputs.trailEdges, GreenBeds = true }
for _, box in inputs.boxes do
	table.insert(
		exclusions.Boxes,
		{ Frame = r.CFrame.new(unpack(box.frame)), HalfSize = r.Vector2.new(unpack(box.half)) }
	)
end
for _, circle in inputs.circles do
	table.insert(
		exclusions.Circles,
		{ Center = r.Vector3.new(unpack(circle.center)), Radius = circle.radius }
	)
end
local world = r.Instance.new("Workspace")
local map = r.Instance.new("Model")
map.Name, map.Parent = "CornMap", world
map:SetAttribute("corn_project_id", "children_of_corn")
map:SetAttribute("HarvestArtVariant", "B")
local field = r.Instance.new("Part")
field.Name, field.Parent = "FieldZone", map
field.Size, field.CFrame =
	r.Vector3.new(unpack(inputs.fieldSize)), r.CFrame.new(unpack(inputs.fieldFrame))
local checks = 0
local function check(value, message)
	assert(value, message)
	checks += 1
end
local spacing = layout.SpacingFor(field)
exclusions.TrailEdgeMaxShift = spacing
check(math.abs(spacing - (3 / math.sqrt(2.6)) / math.sqrt(0.7)) < 1e-12, "Density grid is not 70%")
local minColumn, maxColumn, minRow, maxRow = layout.GetCellBounds(field)
local plants, far, shifted, directGaps, beforeGaps, shiftDistances = 0, 0, 0, {}, {}, {}
local tightTargetRoots = 0
local edgeCells = {}
local projectedSeen = {}
local minHeight, maxHeight, minYaw, maxYaw = math.huge, -math.huge, math.huge, -math.huge
local heightBins, yawBins = {}, {}
local function gapToNearestTrail(point, includeEdge)
	local best = math.huge
	local nearest = nil
	for _, edge in inputs.trailEdges do
		local dx, dz = point.X - edge.CenterX, point.Z - edge.CenterZ
		local along = if edge.AlongX then dx else dz
		if math.abs(along) <= edge.HalfLength - 1 then
			local across = if edge.AlongX then dz else dx
			local gap = math.abs(across) - edge.HalfWidth
			if gap < best then
				best, nearest = gap, edge
			end
		end
	end
	if includeEdge then
		return best, nearest
	end
	return best
end
for column = minColumn, maxColumn do
	for row = minRow, maxRow do
		local base = layout.CellPosition(field, column, row)
		-- Every frozen soil footprint was independently proved outside all masks.
		-- Query all soil cells; inspect full production masks on all moved roots
		-- and a regular sample of the unchanged interior as an additional check.
		if not plan.Contains(base) then
			continue
		end
		plants += 1
		if column % 2 == 0 and row % 2 == 0 then
			far += 1
		end
		local point = layout.TrailEdgePosition(base, exclusions)
		if point.X ~= base.X or point.Z ~= base.Z or (column % 17 == 0 and row % 17 == 0) then
			check(
				not layout.IsExcluded(point, exclusions),
				"Projected corn enters a forbidden area"
			)
		end
		check(plan.GetHeight(point) ~= nil, "Projected root has no bed surface")
		local code = string.format("%.4f:%.4f", point.X, point.Z)
		check(not projectedSeen[code], "Duplicate corn root after projection")
		projectedSeen[code] = true
		if point.X ~= base.X or point.Z ~= base.Z then
			shifted += 1
			local gap, edge = gapToNearestTrail(point, true)
			check(
				gap > 0 and gap <= spacing + 0.0001,
				"Projected root crossed a trail or exceeded its reach"
			)
			if gap <= 0.201 then
				tightTargetRoots += 1
			end
			table.insert(directGaps, gap)
			table.insert(beforeGaps, gapToNearestTrail(base))
			table.insert(
				shiftDistances,
				math.max(math.abs(point.X - base.X), math.abs(point.Z - base.Z))
			)
			local across = if edge.AlongX then point.Z - edge.CenterZ else point.X - edge.CenterX
			local side = if across < 0 then -1 else 1
			local variety = ((column * 73856093 + row * 19349663 + 817) % 104729) % 4 + 1
			table.insert(edgeCells, {
				column,
				row,
				base.X,
				base.Y,
				base.Z,
				point.X,
				point.Y,
				point.Z,
				edge.CenterX,
				edge.CenterZ,
				if edge.AlongX then 1 else 0,
				edge.HalfWidth,
				edge.HalfLength,
				if edge.AlongX then 0 else side,
				if edge.AlongX then side else 0,
				gap,
				8 * layout.HeightFactor(column, row),
				layout.CellYaw(column, row),
				variety,
				edge.Key,
			})
			check(
				point == layout.TrailEdgePosition(base, exclusions),
				"Edge projection is nondeterministic"
			)
		end
		local factor, yaw = layout.HeightFactor(column, row), layout.CellYaw(column, row)
		local height = 8 * factor
		check(height >= 6.8 and height <= 9.2, "Green height outside requested spread")
		check(yaw >= 0 and yaw < math.pi * 2, "Yaw outside full circle")
		minHeight, maxHeight = math.min(minHeight, height), math.max(maxHeight, height)
		minYaw, maxYaw = math.min(minYaw, yaw), math.max(maxYaw, yaw)
		heightBins[math.min(11, math.floor((height - 6.8) / 0.2))] = true
		yawBins[math.floor(yaw / (math.pi * 2) * 36)] = true
	end
end
local function quantile(values, fraction)
	table.sort(values)
	return values[math.max(1, math.ceil(#values * fraction))]
end
for _, variant in { 1, 2, 3, 4 } do
	local plant = r.Instance.new("MeshPart")
	plant.Size, plant.CFrame = r.Vector3.new(3, 8, 3.2), r.CFrame.new(11, 22, 33)
	plant:SetAttribute("CornGreenOriginal", true)
	plant:SetAttribute("CornGreenVariety", variant)
	local savedFrame, savedSize = plant.CFrame, plant.Size
	layout.ApplyVariation(plant, 27 + variant, -31)
	check(plant.CFrame == savedFrame, "Height variation moved the plant pivot")
	check(
		plant.Size.X == savedSize.X and plant.Size.Z == savedSize.Z,
		"Height variation stretched leaf width"
	)
	check(
		math.abs(plant.Size.Y - savedSize.Y * layout.HeightFactor(27 + variant, -31)) < 0.00002,
		"Original and new variants use different height factors: "
			.. tostring(plant.Size.Y)
			.. " / "
			.. tostring(savedSize.Y * layout.HeightFactor(27 + variant, -31))
	)
end
local aSourceBefore = fs.readFile("variants/A/shared/Game/CornLayout.luau")
map:SetAttribute("HarvestArtVariant", "A")
check(layout.SpacingFor(field) == 3, "B density leaked into an A field")
check(fs.readFile("variants/A/shared/Game/CornLayout.luau") == aSourceBefore, "A source changed")
local function keyCount(values)
	local count = 0
	for _ in values do
		count += 1
	end
	return count
end
check(
	keyCount(heightBins) == 12 and keyCount(yawBins) == 36,
	"Height or yaw distribution collapsed"
)
check(
	math.abs(plants / 84191 - 0.7) < 0.005 and math.abs(far / 20965 - 0.7) < 0.01,
	"Actual full-grid and Far counts are not close to a thirty-percent reduction"
)
local sourceHash =
	serde.hash("sha256", fs.readFile("variants/B/shared/Game/CornLayout.luau"):gsub("\r\n", "\n"))
if process.args[1] then
	local target = process.args[1]
	check(
		target == ".artifacts/playtests/2026-10-23-B-green-variants/edge-cells.json",
		"Unexpected edge analysis output path"
	)
	fs.writeFile(
		target,
		serde.encode("json", {
			schema = 1,
			sourceSHA256 = sourceHash,
			spacing = spacing,
			nativeMutation = false,
			fields = {
				"column",
				"row",
				"fromX",
				"fromY",
				"fromZ",
				"x",
				"y",
				"z",
				"edgeCenterX",
				"edgeCenterZ",
				"alongX",
				"halfWidth",
				"halfLength",
				"normalX",
				"normalZ",
				"gap",
				"height",
				"yawRadians",
				"variety",
				"edgeKey",
			},
			cells = edgeCells,
		})
	)
end
local report = {
	pass = true,
	checks = checks,
	spacing = spacing,
	denseEligible = plants,
	farEligible = far,
	denseRatio = plants / 84191,
	farRatio = far / 20965,
	shiftedRoots = shifted,
	tightTargetRoots = tightTargetRoots,
	projectedGap = {
		min = quantile(directGaps, 0),
		median = quantile(directGaps, 0.5),
		max = quantile(directGaps, 1),
	},
	originalGapMedian = quantile(beforeGaps, 0.5),
	maximumShift = quantile(shiftDistances, 1),
	heightRange = { minHeight, maxHeight },
	yawDegrees = { math.deg(minYaw), math.deg(maxYaw) },
	heightBinCount = keyCount(heightBins),
	yawBinCount = keyCount(yawBins),
	elapsedSeconds = os.clock() - started,
	nativeMutation = false,
	GPUAcceptance = false,
	sourceSHA256 = sourceHash,
}
print(serde.encode("json", report))
