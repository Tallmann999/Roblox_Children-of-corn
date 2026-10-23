-- Read-only ClientPlay acceptance. Run after ordinary Start/Confirm.
-- MCP has a separate require cache. Observe the actual player-script copies and
-- their public outputs; do not mistake unstarted MCP tables for running state.
-- No Source, property, camera, root, input, binding, Instance or global writes.
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
assert(
	RunService:IsStudio() and RunService:IsRunning() and Players.LocalPlayer,
	"ClientPlay required"
)
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
assert(field:IsA("BasePart") and field.Size == Vector3.new(630, 10, 630), "630 B field required")
local report = {
	pass = true,
	failures = {},
	scope = "ClientPlay read-only current runtime",
	GPUAcceptance = false,
	sustainedFPSAcceptance = false,
	publicationAcceptance = false,
}
local function check(ok, message)
	if not ok then
		report.pass = false
		table.insert(report.failures, message)
	end
end
local function position(part)
	if not part or not part:IsA("BasePart") then
		return nil
	end
	return { part.Position.X, part.Position.Y, part.Position.Z }
end
local character = Players.LocalPlayer.Character
local root = character and character:FindFirstChild("HumanoidRootPart")
local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
report.player = { before = position(root), health = humanoid and humanoid.Health }

-- Measure before scene scans, so the audit's property reads do not inflate this
-- stationary sample. It does not include a publication that completed earlier.
RunService.Heartbeat:Wait()
local timings, sum, maximum = {}, 0, 0
local started = os.clock()
for index = 1, 120 do
	local dt = RunService.Heartbeat:Wait()
	timings[index], sum, maximum = dt, sum + dt, math.max(maximum, dt)
end
table.sort(timings)
report.frames = {
	count = #timings,
	totalDt = sum,
	wallSeconds = os.clock() - started,
	maxDt = maximum,
	meanDt = sum / #timings,
	p95Dt = timings[math.ceil(#timings * 0.95)],
	above33ms = 0,
	above50ms = 0,
	includesSceneScan = false,
}
for _, dt in timings do
	if dt > 1 / 30 then
		report.frames.above33ms += 1
	end
	if dt > 0.05 then
		report.frames.above50ms += 1
	end
end
report.player.after = position(root)

local playerScripts = Players.LocalPlayer:FindFirstChild("PlayerScripts")
local client = playerScripts and playerScripts:FindFirstChild("GameClient")
local modules = client and client:FindFirstChild("Controllers")
check(modules ~= nil, "Ordinary GameClient.Controllers missing")
local bootstrap = client and client:FindFirstChild("Bootstrap")
report.bootstrap = {
	path = bootstrap and bootstrap:GetFullName(),
	enabled = bootstrap and bootstrap:IsA("LocalScript") and bootstrap.Enabled,
	controllerCopies = modules and #modules:GetChildren() or 0,
}
check(report.bootstrap.enabled, "Ordinary player Bootstrap missing/disabled")
check(
	report.bootstrap.controllerCopies == 18,
	"Ordinary player controller-copy count differs from 18"
)
report.privateControllerStateObservable = false
report.controllerStateLimitation =
	"MCP uses a separate require cache; private running tables are not inspected"
report.controllers = {}
for _, name in
	{ "CornController", "CornBackdropController", "GreenBedController", "CornWindController" }
do
	local module = modules and modules:FindFirstChild(name)
	local actualCopy = module ~= nil
		and module:IsA("ModuleScript")
		and module:IsDescendantOf(Players.LocalPlayer.PlayerScripts)
	report.controllers[name] = {
		present = actualCopy,
		modulePath = module and module:GetFullName(),
		privateStateObserved = false,
	}
	check(actualCopy, name .. " actual player-script copy unavailable")
end

local meshId, textureId = "rbxassetid://104111861186519", "rbxassetid://137803536172445"
local function corn(folder, kind)
	local result = {
		count = 0,
		invalid = 0,
		retiredDuringScan = 0,
		badExamples = {},
		uri = 0,
		green = 0,
		shadow = 0,
		noncollidable = 0,
		originalMarker = 0,
		withinPlayerWindRadius = 0,
		minPlayerDistanceXZ = nil,
		minHeight = math.huge,
		maxHeight = 0,
	}
	if not folder or not folder:IsA("Folder") then
		check(false, kind .. " runtime folder missing")
		return result
	end
	result.ready = folder:GetAttribute("Ready") == true
	result.loadedAttribute = folder:GetAttribute("LoadedPlants")
	result.windMode = folder:GetAttribute("CornWindMode")
	result.windAnimated = folder:GetAttribute("CornWindAnimated")
	for index, item in folder:GetDescendants() do
		if item:IsA("BasePart") then
			if not item:IsDescendantOf(folder) then
				result.retiredDuringScan += 1
			else
				result.count += 1
				if root and root.Parent then
					local delta = item.Position - root.Position
					local distance = math.sqrt(delta.X * delta.X + delta.Z * delta.Z)
					result.minPlayerDistanceXZ =
						math.min(result.minPlayerDistanceXZ or math.huge, distance)
					if distance <= 5 then
						result.withinPlayerWindRadius += 1
					end
				end
				local uri = item:IsA("MeshPart")
					and item.MeshId == meshId
					and item.MeshContent.SourceType == Enum.ContentSourceType.Uri
				local green = item:IsA("MeshPart") and item.TextureID == textureId
				local decorative = item.Anchored
					and not item.CanCollide
					and not item.CanTouch
					and not item.CanQuery
				local marker = item:GetAttribute("CornGreenOriginal") == true
					and item:GetAttribute("corn_project_id") == "children_of_corn"
				if uri then
					result.uri += 1
				end
				if green then
					result.green += 1
				end
				if item.CastShadow then
					result.shadow += 1
				end
				if decorative then
					result.noncollidable += 1
				end
				if marker then
					result.originalMarker += 1
				end
				result.minHeight = math.min(result.minHeight, item.Size.Y)
				result.maxHeight = math.max(result.maxHeight, item.Size.Y)
				local owned = if kind == "Near"
					then item:GetAttribute("CornPlantTemplateOwned") == true and item.Name == "Corn"
					else item:GetAttribute("CornClientBackdropOwned") == true and item:GetAttribute(
						"CornEditorOverview"
					) == true
				if
					not (
						uri
						and green
						and decorative
						and marker
						and owned
						and item.CastShadow
						and item:IsA("MeshPart")
						and item.DoubleSided
						and math.abs(item.Size.Y - 8) < 0.0001
						and math.abs(item.Size.X - 3.0026558642674086) < 0.003
						and math.abs(item.Size.Z - 3.1309012101883917) < 0.003
						and item.Color == Color3.new(1, 1, 1)
						and item.Material == Enum.Material.Plastic
						and item.Transparency == 0
					)
				then
					result.invalid += 1
					if #result.badExamples < 4 then
						table.insert(result.badExamples, item:GetFullName())
					end
				end
			end
		end
		if index % 512 == 0 then
			RunService.Heartbeat:Wait()
		end
	end
	if result.count == 0 then
		result.minHeight = 0
	end
	check(result.count > 0 and result.invalid == 0, kind .. " green original corn invalid/empty")
	check(result.count <= (if kind == "Near" then 8064 else 30000), kind .. " plant cap exceeded")
	if kind == "Far" then
		check(
			result.ready and result.loadedAttribute == result.count,
			"Far not fully published/exact count"
		)
	end
	return result
end
report.near = corn(map:FindFirstChild("CornClientPlants"), "Near")
report.far = corn(map:FindFirstChild("CornClientBackdrop"), "Far")

local beds = map:FindFirstChild("CornClientGreenBeds")
local editor = map:FindFirstChild("GreenBedEditor")
report.beds = { count = 0, invalid = 0, opaque = 0, keys = {}, editorCount = 0, editorHidden = 0 }
if beds and beds:IsA("Folder") then
	report.beds.ready = beds:GetAttribute("Ready") == true
	report.beds.loadedAttribute = beds:GetAttribute("LoadedParts")
	report.beds.lastClones = beds:GetAttribute("LastFrameClones")
	report.beds.lastCloneSeconds = beds:GetAttribute("LastFrameSeconds")
	for index, item in beds:GetChildren() do
		report.beds.count += 1
		local valid = item:IsA("MeshPart")
			and item.MeshContent.SourceType == Enum.ContentSourceType.Opaque
		if valid then
			report.beds.opaque += 1
		end
		local key = item:GetAttribute("BGreenBedGeometryKey") or "missing"
		report.beds.keys[key] = (report.beds.keys[key] or 0) + 1
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
				and item.Material == Enum.Material.Plastic
			)
		then
			report.beds.invalid += 1
		end
		if index % 256 == 0 then
			RunService.Heartbeat:Wait()
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
	"1406 opaque client beds not Ready/valid"
)
check(
	report.beds.keys.Center == 413 and report.beds.keys.End == 290 and report.beds.keys.Skirt == 703,
	"Soil type counts differ from frozen plan"
)
check(
	report.beds.editorCount == 1406 and report.beds.editorHidden == 1406,
	"Saved editor beds not all locally hidden"
)

local art = ReplicatedStorage:FindFirstChild("CornRuntimeArt")
local template = art and art:FindFirstChild("CornPlantTemplate")
report.serverPrepared = {
	present = template ~= nil,
	green = template and template:IsA("MeshPart") and template.TextureID == textureId,
	height = template and template:IsA("BasePart") and template.Size.Y,
}
check(
	report.serverPrepared.green and math.abs((report.serverPrepared.height or 0) - 8) < 0.001,
	"Common server preparation reintroduced dry corn/wrong height"
)

-- Historical console records are evidence for review, not current-error counts.
report.historicalControllerMessages = {}
local logOk, logs = pcall(function()
	return game:GetService("LogService"):GetLogHistory()
end)
report.historyReadable = logOk
if logOk then
	for _, entry in logs do
		local message = tostring(entry.message or "")
		if
			(
				message:find("[GreenBedController]", 1, true)
				or message:find("[CornController]", 1, true)
				or message:find("[CornBackdropController]", 1, true)
				or message:find("Failed to require controller", 1, true)
				or message:find("Started 18 controllers", 1, true)
			) and #report.historicalControllerMessages < 12
		then
			table.insert(report.historicalControllerMessages, {
				message = message,
				timestamp = entry.timestamp,
				messageType = tostring(entry.messageType),
			})
		end
	end
end
return HttpService:JSONEncode(report)
