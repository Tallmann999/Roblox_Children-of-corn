-- 23-Oct read-only ClientPlay public-output audit. No require-cache assumptions.
-- Run after ordinary bootstrap + Start/Confirm + completed FarReady.
-- Does not write Instances, Sources, attributes, camera, character, input or globals.
local Run = game:GetService("RunService")
local Players = game:GetService("Players")
local Http = game:GetService("HttpService")
assert(Run:IsStudio() and Run:IsRunning() and Players.LocalPlayer, "Studio ClientPlay required")
local map = assert(workspace:FindFirstChild("CornMap"), "CornMap missing")
assert(
	map:IsA("Model")
		and map:GetAttribute("corn_project_id") == "children_of_corn"
		and map:GetAttribute("HarvestArtVariant") == "B",
	"Exact B map required"
)
assert(
	not workspace:FindFirstChild("Asmr_Base") and not workspace:FindFirstChild("ASMR_Models"),
	"Foreign game refused"
)
local field = assert(map:FindFirstChild("FieldZone"), "FieldZone missing")
local ground = assert(map:FindFirstChild("Ground"), "Ground missing")
assert(
	field:IsA("BasePart")
		and field.Size == Vector3.new(630, 10, 630)
		and ground:IsA("BasePart")
		and ground.Size == Vector3.new(630, 2, 630),
	"Accepted B field required"
)
local report = {
	pass = true,
	failures = {},
	scope = "23-Oct actual ClientPlay public outputs",
	privateControllerStateObservable = false,
	requireCacheUsed = false,
	GPUAcceptance = false,
	sustainedFPSAcceptance = false,
	publicationAcceptance = false,
	frameSampleNote = "120 stationary Heartbeat events only; no long FPS, walking, or earlier publication-spike acceptance",
}
local function check(ok, message)
	if not ok then
		report.pass = false
		table.insert(report.failures, message)
	end
end
local function pos(part)
	return if part and part:IsA("BasePart")
		then { part.Position.X, part.Position.Y, part.Position.Z }
		else nil
end
local character = Players.LocalPlayer.Character
local root = character and character:FindFirstChild("HumanoidRootPart")
local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
report.player = { before = pos(root), health = humanoid and humanoid.Health }
-- Time sample precedes all heavy property scans.
Run.Heartbeat:Wait()
local timings, sum, maximum = {}, 0, 0
local started = os.clock()
for i = 1, 120 do
	local dt = Run.Heartbeat:Wait()
	timings[i], sum, maximum = dt, sum + dt, math.max(maximum, dt)
end
table.sort(timings)
report.frames = {
	count = 120,
	totalDt = sum,
	wallSeconds = os.clock() - started,
	maxDt = maximum,
	meanDt = sum / 120,
	p95Dt = timings[114],
	above33ms = 0,
	above50ms = 0,
	includesPropertyScan = false,
}
for _, dt in timings do
	if dt > 1 / 30 then
		report.frames.above33ms += 1
	end
	if dt > 0.05 then
		report.frames.above50ms += 1
	end
end
report.player.after = pos(root)
local playerScripts = Players.LocalPlayer:FindFirstChild("PlayerScripts")
local client = playerScripts and playerScripts:FindFirstChild("GameClient")
local controllers = client and client:FindFirstChild("Controllers")
local bootstrap = client and client:FindFirstChild("Bootstrap")
report.bootstrap = {
	path = bootstrap and bootstrap:GetFullName(),
	enabled = bootstrap and bootstrap:IsA("LocalScript") and bootstrap.Enabled,
	controllerCopies = controllers and #controllers:GetChildren() or 0,
}
check(
	report.bootstrap.enabled and report.bootstrap.controllerCopies == 18,
	"Ordinary enabled Bootstrap + 18 controller copies required"
)
local SHAPES = {
	{
		hash = "259fbe167d4c0a24e6813282a5f3026d582b67d7af1f701bad39bed706a193df",
		size = Vector3.new(3.0026558642674086, 8, 3.1309012101883917),
		offset = Vector3.new(0, 4, 0),
		kind = Enum.ContentSourceType.Uri,
	},
	{
		hash = "f9fdbe90134919e69f1c0a0611f7557973869208e7ea281d23883578705e422e",
		size = Vector3.new(3.670954663325867, 8, 2.9915173196191303),
		offset = Vector3.new(0.42936572432518005, 4, 0.15668721497058868),
		kind = Enum.ContentSourceType.Opaque,
	},
	{
		hash = "7cb15c7c521d0a5db66467211b56d1d0f29bc69f2cbed6c8a5095103dbedb867",
		size = Vector3.new(3.9219837683471974, 8, 3.689774904984928),
		offset = Vector3.new(-0.04207272082567215, 4, -0.05359083414077759),
		kind = Enum.ContentSourceType.Opaque,
	},
	{
		hash = "f6b04f2860cd09bb4d8d78897b8e6a74e983221c1b2a67d746bdd887edb798cc",
		size = Vector3.new(3.6044152686720112, 8, 3.209386489064556),
		offset = Vector3.new(-0.40497368574142456, 4, -0.22510722279548645),
		kind = Enum.ContentSourceType.Opaque,
	},
}
local function variety(column, row)
	return ((column * 73856093 + row * 19349663 + 817) % 104729) % 4 + 1
end
local function height(column, row)
	return 8 * (0.85 + ((column * 73856093 + row * 19349663 + 817 * 97) % 104729) / 104729 * 0.3)
end
local groundY = ground.Position.Y + ground.Size.Y / 2
local roots = { Near = {}, Far = {} }
local function corn(folder, kind)
	local result = {
		count = 0,
		invalid = 0,
		uri = 0,
		opaque = 0,
		green = 0,
		white = 0,
		noncollidable = 0,
		shadows = 0,
		markers = 0,
		species = { 0, 0, 0, 0 },
		yawBins = table.create(16, 0),
		minHeight = math.huge,
		maxHeight = 0,
		minRootY = math.huge,
		maxRootY = -math.huge,
		farHashHeightInvalid = 0,
		badExamples = {},
		retiredDuringScan = 0,
	}
	if not folder or not folder:IsA("Folder") then
		check(false, kind .. " folder missing")
		return result
	end
	result.ready = folder:GetAttribute("Ready") == true
	result.loadedAttribute = folder:GetAttribute("LoadedPlants")
	result.windMode = folder:GetAttribute("CornWindMode")
	result.windAnimated = folder:GetAttribute("CornWindAnimated")
	check(
		folder:GetAttribute("corn_project_id") == "children_of_corn"
			and folder:GetAttribute(
					if kind == "Near" then "CornClientRendererOwned" else "CornClientBackdropOwned"
				)
				== true,
		kind .. " folder ownership differs"
	)
	for index, item in folder:GetDescendants() do
		if item:IsA("BasePart") then
			if not item:IsDescendantOf(folder) then
				result.retiredDuringScan += 1
			else
				result.count += 1
				local species = item:GetAttribute("CornGreenVariety")
				local shape = SHAPES[species]
				local valid = item:IsA("MeshPart") and shape ~= nil
				local frame, size = item.CFrame, item.Size
				local offset, templateSize =
					item:GetAttribute("HarvestRootOffset"),
					item:GetAttribute("CornGreenTemplateSize")
				if item:IsA("MeshPart") then
					if item.MeshContent.SourceType == Enum.ContentSourceType.Uri then
						result.uri += 1
					end
					if item.MeshContent.SourceType == Enum.ContentSourceType.Opaque then
						result.opaque += 1
					end
					if item.TextureID == "rbxassetid://137803536172445" then
						result.green += 1
					end
				end
				if item.Color == Color3.new(1, 1, 1) then
					result.white += 1
				end
				if
					item.Anchored
					and not item.CanCollide
					and not item.CanTouch
					and not item.CanQuery
				then
					result.noncollidable += 1
				end
				if item.CastShadow then
					result.shadows += 1
				end
				if item:GetAttribute("CornGreenOriginal") == true then
					result.markers += 1
				end
				result.minHeight, result.maxHeight =
					math.min(result.minHeight, size.Y), math.max(result.maxHeight, size.Y)
				local yaw = math.atan2(-frame.RightVector.Z, frame.RightVector.X) % (math.pi * 2)
				local bin = math.clamp(math.floor(yaw / (math.pi * 2) * 16) + 1, 1, 16)
				result.yawBins[bin] += 1
				if shape then
					result.species[species] += 1
				end
				valid = valid and typeof(offset) == "Vector3" and typeof(templateSize) == "Vector3"
				if valid then
					valid = (offset - shape.offset).Magnitude < 0.001
						and (templateSize - shape.size).Magnitude < 0.001
						and item.MeshContent.SourceType == shape.kind
						and (species ~= 1 or item.MeshId == "rbxassetid://104111861186519")
						and item:GetAttribute("CornGreenSourceSHA256") == shape.hash
						and math.abs(size.X - templateSize.X) < 0.001
						and math.abs(size.Z - templateSize.Z) < 0.001
						and size.Y >= 6.8 - 0.001
						and size.Y <= 9.2 + 0.001
						and item:GetAttribute("corn_project_id") == "children_of_corn"
						and item:GetAttribute("CornGreenTemplateOwned") == true
						and item:GetAttribute("CornGreenTemplateVersion") == 2
						and item:GetAttribute("CornGreenOriginal") == true
						and item.Anchored
						and not item.CanCollide
						and not item.CanTouch
						and not item.CanQuery
						and item.CastShadow
						and item.DoubleSided
						and item.Transparency == 0
						and item.TextureID == "rbxassetid://137803536172445"
						and item.Color == Color3.new(1, 1, 1)
						and item.Material == Enum.Material.Plastic
					local scaled = Vector3.new(
						offset.X * size.X / templateSize.X,
						offset.Y * size.Y / templateSize.Y,
						offset.Z * size.Z / templateSize.Z
					)
					local plantedRoot = frame:PointToWorldSpace(-scaled)
					result.minRootY, result.maxRootY =
						math.min(result.minRootY, plantedRoot.Y),
						math.max(result.maxRootY, plantedRoot.Y)
					local localRoot = field.CFrame:PointToObjectSpace(plantedRoot)
					valid = valid
						and math.abs(localRoot.X) <= 315.003
						and math.abs(localRoot.Z) <= 315.003
						and plantedRoot.Y >= groundY - 0.003
						and plantedRoot.Y <= groundY + 1
					table.insert(
						roots[kind],
						{ root = plantedRoot, species = species, height = size.Y }
					)
					if kind == "Far" then
						local column, row = item.Name:match("^Far_(%-?%d+)_(%-?%d+)$")
						if
							not column
							or variety(tonumber(column), tonumber(row)) ~= species
							or math.abs(height(tonumber(column), tonumber(row)) - size.Y) > 0.001
						then
							result.farHashHeightInvalid += 1
							valid = false
						end
					end
				end
				if not valid then
					result.invalid += 1
					if #result.badExamples < 4 then
						table.insert(result.badExamples, item:GetFullName())
					end
				end
			end
		end
		if index % 512 == 0 then
			Run.Heartbeat:Wait()
		end
	end
	if result.count == 0 then
		result.minHeight, result.minRootY, result.maxRootY = 0, 0, 0
	end
	result.yawBinsOccupied = 0
	for _, count in result.yawBins do
		if count > 0 then
			result.yawBinsOccupied += 1
		end
	end
	check(result.count > 0 and result.invalid == 0, kind .. " shape/appearance/anchor invalid")
	check(result.count <= (if kind == "Near" then 8064 else 30000), kind .. " cap exceeded")
	for species = 1, 4 do
		check(result.species[species] > 0, kind .. " missing shape " .. species)
	end
	check(
		result.yawBinsOccupied >= 12 and result.maxHeight - result.minHeight > 1.5,
		kind .. " yaw/height distribution unexpectedly uniform"
	)
	if kind == "Far" then
		check(
			result.ready and result.count == 14607 and result.loadedAttribute == 14607,
			"FarReady exact 14607 required"
		)
	end
	return result
end
report.near = corn(map:FindFirstChild("CornClientPlants"), "Near")
report.far = corn(map:FindFirstChild("CornClientBackdrop"), "Far")
-- Recover actual physical stem anchors from public placement metadata. Near and
-- Far overlap should agree even if only one copy is currently wind-rotated.
local buckets = {}
for _, entry in roots.Far do
	local key = math.floor(entry.root.X) .. ":" .. math.floor(entry.root.Z)
	buckets[key] = buckets[key] or {}
	table.insert(buckets[key], entry)
end
report.overlap = {
	matched = 0,
	mismatch = 0,
	maxAnchorDistance = 0,
	maxHeightDifference = 0,
	method = "Actual recovered stem anchors within .002 studs in XZ; no require/private cache",
}
for _, near in roots.Near do
	local bx, bz = math.floor(near.root.X), math.floor(near.root.Z)
	local best, distance = nil, math.huge
	for x = bx - 1, bx + 1 do
		for z = bz - 1, bz + 1 do
			for _, far in buckets[x .. ":" .. z] or {} do
				local delta = near.root - far.root
				local candidate = math.sqrt(delta.X * delta.X + delta.Z * delta.Z)
				if candidate < distance then
					best, distance = far, candidate
				end
			end
		end
	end
	if best and distance <= 0.002 then
		local anchorDistance = (near.root - best.root).Magnitude
		local heightDifference = math.abs(near.height - best.height)
		report.overlap.matched += 1
		report.overlap.maxAnchorDistance =
			math.max(report.overlap.maxAnchorDistance, anchorDistance)
		report.overlap.maxHeightDifference =
			math.max(report.overlap.maxHeightDifference, heightDifference)
		if near.species ~= best.species or anchorDistance > 0.003 or heightDifference > 0.001 then
			report.overlap.mismatch += 1
		end
	end
end
check(
	report.overlap.matched > 0 and report.overlap.mismatch == 0,
	"Near/Far overlap roots/shape/heights differ"
)
local beds, editor = map:FindFirstChild("CornClientGreenBeds"), map:FindFirstChild("GreenBedEditor")
report.beds = { count = 0, opaque = 0, invalid = 0, keys = {}, editorCount = 0, editorHidden = 0 }
if beds and beds:IsA("Folder") then
	report.beds.ready = beds:GetAttribute("Ready") == true
	report.beds.loadedAttribute = beds:GetAttribute("LoadedParts")
	for index, item in beds:GetChildren() do
		report.beds.count += 1
		local key = item:GetAttribute("BGreenBedGeometryKey") or "missing"
		report.beds.keys[key] = (report.beds.keys[key] or 0) + 1
		local valid = item:IsA("MeshPart")
			and item.MeshContent.SourceType == Enum.ContentSourceType.Opaque
		if valid then
			report.beds.opaque += 1
		end
		if
			not (
				valid
				and item:GetAttribute("BGreenBedsOwner") == "corn_B_green_beds_v1"
				and item:GetAttribute("BGreenBedGeometryOwned") == true
				and item.TextureID == "rbxassetid://95855894892409"
				and item.Anchored
				and not item.CanCollide
				and not item.CanTouch
				and not item.CanQuery
				and item.CastShadow
				and item.DoubleSided
				and item.Transparency == 0
				and item.Color == Color3.new(1, 1, 1)
			)
		then
			report.beds.invalid += 1
		end
		if index % 256 == 0 then
			Run.Heartbeat:Wait()
		end
	end
end
if editor and editor:IsA("Folder") then
	for _, item in editor:GetChildren() do
		report.beds.editorCount += 1
		if item:IsA("BasePart") and item.LocalTransparencyModifier == 1 then
			report.beds.editorHidden += 1
		end
	end
end
check(
	report.beds.ready
		and report.beds.count == 1406
		and report.beds.loadedAttribute == 1406
		and report.beds.opaque == 1406
		and report.beds.invalid == 0,
	"Unchanged 1406 Opaque beds not Ready/valid"
)
check(
	report.beds.keys.Center == 413 and report.beds.keys.End == 290 and report.beds.keys.Skirt == 703,
	"Bed-type counts changed"
)
check(
	report.beds.editorCount == 1406 and report.beds.editorHidden == 1406,
	"Saved bed preview not all locally hidden"
)
report.historicalControllerMessages = {}
local ok, logs = pcall(function()
	return game:GetService("LogService"):GetLogHistory()
end)
report.historyReadable = ok
if ok then
	for _, entry in logs do
		local message = tostring(entry.message or "")
		if
			(
				message:find("[CornController]", 1, true)
				or message:find("[CornBackdropController]", 1, true)
				or message:find("[GreenBedController]", 1, true)
				or message:find("Started 18 controllers", 1, true)
				or message:find("Failed to require controller", 1, true)
			) and #report.historicalControllerMessages < 16
		then
			table.insert(
				report.historicalControllerMessages,
				{ message = message, timestamp = entry.timestamp, messageType = tostring(
					entry.messageType
				) }
			)
		end
	end
end
return Http:JSONEncode(report)
