-- OPTIONAL temporary real LocalScript observer. Install only in Play under the
-- verified LocalPlayer.PlayerScripts. It writes only its own Result StringValue.
-- Root creates script + child Result with ObserverOwner below, supplies Frames,
-- and deletes both after collecting the report. No input/camera/character writes.
local Run = game:GetService("RunService")
local Players = game:GetService("Players")
local Http = game:GetService("HttpService")
local OWNER = "corn_B_green_motion_audit_20261023"
assert(Run:IsStudio() and Run:IsClient() and Run:IsRunning(), "Real ClientPlay context required")
local player = assert(Players.LocalPlayer, "LocalPlayer missing")
assert(
	script:IsA("LocalScript")
		and script:IsDescendantOf(player.PlayerScripts)
		and script:GetAttribute("ObserverOwner") == OWNER,
	"Owned temporary player LocalScript required"
)
local output = assert(script:FindFirstChild("Result"), "Root must supply owned Result StringValue")
assert(
	output:IsA("StringValue") and output:GetAttribute("ObserverOwner") == OWNER,
	"Owned observer output required"
)
local map = assert(workspace:FindFirstChild("CornMap"))
assert(
	map:GetAttribute("corn_project_id") == "children_of_corn"
		and map:GetAttribute("HarvestArtVariant") == "B",
	"Exact B required"
)
local report = {
	owner = OWNER,
	done = false,
	pass = false,
	scope = "Actual LocalScript VM cached Wind state during ordinary externally supplied movement",
	observerMovesCharacter = false,
	observerChangesCamera = false,
	observerChangesProduction = false,
	privateControllerStateObservable = true,
	frames = 0,
	maxNearIndexed = 0,
	maxFarIndexed = 0,
	maxAnimatedNear = 0,
	maxAnimatedFar = 0,
	maxActualChangedParts = 0,
	maxWrites = 0,
	anchorChecks = 0,
	maxAnchorError = 0,
	invalidAnchorEntries = 0,
	anchorExamples = {},
	modes = {},
}
local function rootPosition()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end
local before = rootPosition()
report.playerBefore = before and { before.X, before.Y, before.Z }
local frames = math.clamp(tonumber(script:GetAttribute("Frames")) or 480, 120, 1200)
output.Value = Http:JSONEncode(report)
local ok, problem = pcall(function()
	local modules =
		assert(player.PlayerScripts:FindFirstChild("GameClient")):FindFirstChild("Controllers")
	assert(modules, "Ordinary GameClient.Controllers missing")
	local wind = require(assert(modules:FindFirstChild("CornWindController")))
	assert(
		wind._enabled
			and wind._connection
			and wind._connection.Connected
			and type(wind._layers) == "table",
		"Actual ordinary Wind lifecycle is inactive"
	)
	local started = os.clock()
	for frame = 1, frames do
		Run.Heartbeat:Wait()
		assert(script.Parent ~= nil and output.Parent == script, "Observer transport removed")
		report.frames = frame
		local near = wind._layers.near
		local far = wind._layers.far
		report.maxNearIndexed = math.max(report.maxNearIndexed, near and near.Count or 0)
		report.maxFarIndexed = math.max(report.maxFarIndexed, far and far.Count or 0)
		report.maxWrites = math.max(report.maxWrites, wind._lastWrites or 0)
		report.modes[wind._mode or "off"] = true
		local nearFolder = map:FindFirstChild("CornClientPlants")
		local farFolder = map:FindFirstChild("CornClientBackdrop")
		report.maxAnimatedNear = math.max(
			report.maxAnimatedNear,
			nearFolder and nearFolder:GetAttribute("CornWindAnimated") or 0
		)
		report.maxAnimatedFar = math.max(
			report.maxAnimatedFar,
			farFolder and farFolder:GetAttribute("CornWindAnimated") or 0
		)
		local changed = 0
		for entry in wind._active or {} do
			local plant = entry.Plant
			if
				plant
				and plant:IsA("BasePart")
				and plant.Parent
				and plant:GetAttribute("CornGreenOriginal") == true
			then
				local offset, size =
					plant:GetAttribute("HarvestRootOffset"),
					plant:GetAttribute("CornGreenTemplateSize")
				if
					typeof(offset) == "Vector3"
					and typeof(size) == "Vector3"
					and size.X > 0
					and size.Y > 0
					and size.Z > 0
				then
					local scaled = Vector3.new(
						offset.X * plant.Size.X / size.X,
						offset.Y * plant.Size.Y / size.Y,
						offset.Z * plant.Size.Z / size.Z
					)
					local actualRoot = plant.CFrame:PointToWorldSpace(-scaled)
					local error = (actualRoot - entry.Base).Magnitude
					report.anchorChecks += 1
					report.maxAnchorError = math.max(report.maxAnchorError, error)
					if error > 0.0002 then
						report.invalidAnchorEntries += 1
						if #report.anchorExamples < 4 then
							table.insert(
								report.anchorExamples,
								{ path = plant:GetFullName(), error = error }
							)
						end
					end
				else
					report.invalidAnchorEntries += 1
				end
				for _, saved in entry.Parts do
					if saved.Part.Parent and saved.Part.CFrame ~= saved.Frame then
						changed += 1
					end
				end
			end
		end
		report.maxActualChangedParts = math.max(report.maxActualChangedParts, changed)
		if frame % 60 == 0 then
			output.Value = Http:JSONEncode(report)
		end
	end
	report.wallSeconds = os.clock() - started
	local after = rootPosition()
	report.playerAfter = after and { after.X, after.Y, after.Z }
	report.playerDistance = if before and after then (after - before).Magnitude else nil
	report.observedMotion = report.maxActualChangedParts > 0
	report.pass = report.maxNearIndexed > 0
		and report.maxNearIndexed <= 8192
		and report.maxFarIndexed == 14607
		and report.maxWrites <= 32
		and report.invalidAnchorEntries == 0
		and report.observedMotion
		and report.anchorChecks > 0
end)
report.done = true
if not ok then
	report.pass = false
	report.error = tostring(problem)
end
output.Value = Http:JSONEncode(report)
