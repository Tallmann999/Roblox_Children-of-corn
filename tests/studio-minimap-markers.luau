-- Run only in the verified Studio Client during Play. Actual GUI rendering with
-- controlled projection inputs; public gate binding is read-only, world untouched.
local player = game:GetService("Players").LocalPlayer
local source = player.PlayerScripts.GameClient
local Hud = require(source.Game.MinimapHud)
local Controller = require(source.Controllers.MinimapController)
local Geometry = require(game.ReplicatedStorage.GameShared.Game.MinimapGeometry)
local gui = Hud.new(player.PlayerGui)
gui._gui.Name = "MinimapMarkersAcceptance"
gui:SetVisible(true)
local frame = CFrame.new(100, 10, -50) * CFrame.Angles(0, math.rad(37), 0)
local size = Vector3.new(200, 10, 120)
local visited = {
	{
		id = "fixture",
		kind = "clearing",
		position = frame:PointToWorldSpace(Vector3.new(20, 0, -15)),
	},
}
local deaths = { { id = 1, kind = "caught", position = frame.Position } }
local snapshot =
	{ phase = "active", minimap = { round_id = 1, visited = visited, deaths = deaths } }
local checks = {}
local function close(a, b)
	return math.abs(a - b) < 0.001
end
local ok, problem = pcall(function()
	gui:SetSnapshot(snapshot)
	gui:SetViewport(Vector2.new(1000, 800))
	gui:SetExpanded(true)
	task.wait()
	local gate = frame:PointToWorldSpace(Vector3.new(50, 0, 30))
	local playerAt = frame.Position
	for _, entry in
		{
			{ Vector3.new(0, 0, -1), 0 },
			{ Vector3.new(1, 0, 0), 90 },
			{ Vector3.new(0, 0, 1), 180 },
			{ Vector3.new(-1, 0, 0), -90 },
		}
	do
		gui:Update(frame, size, playerAt, frame:VectorToWorldSpace(entry[1]), gate)
		for _, view in gui._views do
			assert(view.Arrow:IsA("Frame") and view.Arrow.Visible)
			assert(view.Arrow.Size.Y.Offset > view.Arrow.Size.X.Offset * 1.7)
			assert(view.Arrow.Shaft.BackgroundColor3 == Color3.fromRGB(94, 220, 255))
			assert(
				view.Arrow.Tip:FindFirstChild("Slice1") and view.Arrow.Tip:FindFirstChild("Slice7")
			)
			assert(not view.Arrow.Tip.ClipsDescendants)
			assert(close(view.Arrow.Rotation, entry[2]))
			assert(
				close(view.Arrow.Position.X.Scale, 0.5) and close(view.Arrow.Position.Y.Scale, 0.5)
			)
			assert(view.Gate.Visible and view.Gate.BackgroundColor3 == Color3.fromRGB(61, 121, 255))
			assert(view.Gate.Size.X.Offset == view.Gate.Size.Y.Offset)
			assert(
				close(view.Gate.Position.X.Scale, 0.75) and close(view.Gate.Position.Y.Scale, 0.75)
			)
			assert(
				view.Visited.fixture.Parent == view.Field and view.Deaths[1].Parent == view.Field
			)
		end
	end
	checks.both_views_four_headings = true
	checks.cyan_elongated_geometry_and_blue_square = true
	checks.visits_deaths_preserved = true
	local movedFrame = CFrame.new(-70, 20, 90) * CFrame.Angles(0, math.rad(-52), 0)
	local movedGate = movedFrame:PointToWorldSpace(Vector3.new(-50, 0, -30))
	gui:Update(movedFrame, size, movedFrame.Position, movedFrame.LookVector, movedGate)
	for _, view in gui._views do
		assert(close(view.Gate.Position.X.Scale, 0.25) and close(view.Gate.Position.Y.Scale, 0.25))
		assert(close(view.Arrow.Rotation, 0))
	end
	checks.moved_rotated_projection = true
	gui:Update(
		movedFrame,
		size,
		movedFrame:PointToWorldSpace(Vector3.new(1000, 0, 1000)),
		movedFrame.LookVector,
		movedFrame:PointToWorldSpace(Vector3.new(1000, 0, 1000))
	)
	for _, view in gui._views do
		assert(view.Arrow.Position.X.Scale < 1 and view.Arrow.Position.X.Scale > 0.5)
		assert(view.Gate.Position.Y.Scale < 1 and view.Gate.Position.Y.Scale > 0.5)
	end
	checks.edge_insets = true
	gui:Update(frame, size, nil, nil, nil)
	for _, view in gui._views do
		assert(not view.Arrow.Visible and not view.Gate.Visible)
	end
	checks.absent_gate_hides = true
	local map = workspace.CornMap
	local actualField = map.FieldZone
	local bound = Controller._gatePosition({}, actualField)
	assert(bound == map.EscapeGate.InteractionAnchor.Position)
	gui:Update(actualField.CFrame, actualField.Size, nil, nil, bound)
	local actualProjection = Geometry.Project(actualField.CFrame, actualField.Size, bound)
	for _, view in gui._views do
		assert(view.Gate.Visible)
		assert(math.abs(view.Gate.Position.X.Scale - actualProjection.X) < 0.1)
		assert(math.abs(view.Gate.Position.Y.Scale - actualProjection.Y) < 0.1)
	end
	checks.actual_public_gate_binding = true
end)
gui:Destroy()
assert(ok, tostring(problem))
assert(not player.PlayerGui:FindFirstChild("MinimapMarkersAcceptance"))
checks.cleanup = true
checks.method =
	"Current HUD engine GUI, controlled projection inputs and read-only actual public gate"
return game:GetService("HttpService"):JSONEncode(checks)
