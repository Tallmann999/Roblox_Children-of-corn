-- Children_of_corn stopped Edit only. Three authorized properties, with rollback.
local Run = game:GetService("RunService")
assert(Run:IsStudio() and not Run:IsRunning(), "Stop Children_of_corn Play first")
local map = workspace:FindFirstChild("CornMap")
assert(map and map:GetAttribute("corn_project_id") == "children_of_corn", "Wrong project")
assert(
	not workspace:FindFirstChild("Asmr_Base") and not workspace:FindFirstChild("ASMR_Models"),
	"Wrong scene"
)
local road = assert(map.Props:FindFirstChild("VillageRoad"), "VillageRoad missing")
local sign = assert(road:FindFirstChild("ExitSign"), "ExitSign missing")
local surface = assert(sign:FindFirstChild("ExitTextSurface"), "ExitTextSurface missing")
local label = assert(surface:FindFirstChild("ExitText"), "ExitText missing")
for item, role in
	{
		[road] = "VillageRoad",
		[sign] = "ExitSign",
		[surface] = "ExitTextSurface",
		[label] = "ExitText",
	}
do
	assert(
		item:GetAttribute("corn_project_id") == "children_of_corn"
			and item:GetAttribute("CornRoadExitOwned") == true
			and item:GetAttribute("RoadExitVersion") == 1,
		"Unknown owned sign state"
	)
	if item ~= road then
		assert(item:GetAttribute("RoadExitRole") == role, "Unknown sign role")
	end
end
assert(
	sign:IsA("Part")
		and surface:IsA("SurfaceGui")
		and label:IsA("TextLabel")
		and label.Text == "ВЫХОД",
	"Unexpected sign topology"
)
assert(
	sign.Anchored
		and not sign.CanCollide
		and not sign.CanTouch
		and not sign.CanQuery
		and sign.Material == Enum.Material.Neon,
	"Sign properties changed"
)
local beforeSize = Vector3.new(12, 3.2, 0.3)
local beforeFrame = CFrame.new(0, 36.1999855, 419.700012)
local afterSize = beforeSize * 3
local afterFrame = beforeFrame + Vector3.new(0, 3.2, 0)
local function frameMatches(a, b)
	local ac, bc = { a:GetComponents() }, { b:GetComponents() }
	for i = 1, 12 do
		if math.abs(ac[i] - bc[i]) > 0.00005 then
			return false
		end
	end
	return true
end
local before = (sign.Size - beforeSize).Magnitude < 0.00001
	and frameMatches(sign.CFrame, beforeFrame)
local after = (sign.Size - afterSize).Magnitude < 0.00001 and frameMatches(sign.CFrame, afterFrame)
assert(before or after, "Manual/partial sign size or placement; nothing changed")
local oldPixels, oldTop = surface.PixelsPerStud, surface.AlwaysOnTop
-- Accept only the initial authored state, the two explicitly installed
-- geometry-only/intermediate states, or the exact final physical text state.
local initial = before and oldPixels == 48 and oldTop == false
local intermediate = after and oldPixels == 48 and (oldTop == false or oldTop == true)
local current = after and oldPixels == 16 and oldTop == false
assert(
	initial or intermediate or current,
	"Unknown sign text density/overlay state; nothing changed"
)
if current then
	return { changed = 0, repeated = true, size = tostring(sign.Size) }
end
local oldSize, oldFrame = sign.Size, sign.CFrame
game:GetService("ChangeHistoryService"):SetWaypoint("Before Corn exit sign 3x")
local ok, problem = pcall(function()
	if before then
		sign.Size = afterSize
		sign.CFrame = oldFrame + Vector3.new(0, oldSize.Y, 0)
	end
	-- The existing pixel-sized label occupies three times the physical size.
	-- AlwaysOnTop stays false; undo only the recognized previous overlay state.
	surface.PixelsPerStud = 16
	if oldTop then
		surface.AlwaysOnTop = false
	end
end)
if not ok then
	if before then
		sign.Size, sign.CFrame = oldSize, oldFrame
	end
	surface.PixelsPerStud = oldPixels
	surface.AlwaysOnTop = oldTop
	error("Exit sign rolled back: " .. tostring(problem))
end
game:GetService("ChangeHistoryService"):SetWaypoint("Corn exit sign 3x")
return {
	changed = (if before then 2 else 0) + 1 + (if oldTop then 1 else 0),
	physical_letters_scale = 3,
	pixels_per_stud = surface.PixelsPerStud,
	always_on_top = surface.AlwaysOnTop,
	size = tostring(sign.Size),
	frame = tostring(sign.CFrame),
	lower_edge_preserved = true,
}
