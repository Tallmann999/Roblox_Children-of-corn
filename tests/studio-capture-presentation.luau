-- Children_of_corn Client only, when no real capture is active.
-- Temporary actual camera/visual fixture, controlled capture snapshots; no gameplay/remotes.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = assert(Players.LocalPlayer, "Client required")
local Module = require(player.PlayerScripts.GameClient.Controllers.CaptureController)
local Capture = require(game.ReplicatedStorage.GameShared.Game.CapturePresentation)
local Pose = require(game.ReplicatedStorage.GameShared.Game.MonsterPose)
local camera = assert(workspace.CurrentCamera)
local playerGui = assert(player:FindFirstChildOfClass("PlayerGui"))
assert(
	not workspace:FindFirstChild("CornCaptureVisual")
		and not playerGui:FindFirstChild("CornCapturePaint")
		and camera:GetAttribute("CornCaptureCameraOwner") == nil,
	"Capture already active; retry fixture outside the catch"
)
local baseline = {
	frame = camera.CFrame,
	focus = camera.Focus,
	cameraType = camera.CameraType,
	subject = camera.CameraSubject,
	fov = camera.FieldOfView,
}
local controller = setmetatable({}, { __index = Module })
controller:Init({})
local movement = {
	SetCaptureActive = function(self, value)
		self.active = value
	end,
}
local minimap = {
	_expanded = true,
	SetExpanded = function(self, value)
		self._expanded = value
	end,
}
local hud = {
	SetCaptureActive = function(self, value)
		self.active = value
	end,
}
controller:Start({
	Controllers = {
		MovementController = movement,
		MinimapController = minimap,
		RoundController = { _hud = hud },
	},
})
local character = assert(player.Character)
local root = assert(character:FindFirstChild("HumanoidRootPart"))
local frame = root.CFrame * CFrame.new(0, 0, -8)
local checks, replacement = {}, nil
local function expect(condition, message)
	assert(
		condition,
		(message or "Actual capture presentation fixture failed")
			.. "\n"
			.. debug.traceback("Expectation location", 2)
	)
end
local function snapshot(roundId, id, remaining, phase)
	return {
		minimap = { round_id = roundId },
		capture = { id = id, remaining = remaining, frame = frame },
		phase = phase or "caught",
		start_look = Vector3.new(0, 0, -1),
	}
end
local function clean()
	expect(
		not controller._state.active
			and not controller._bound
			and not workspace:FindFirstChild("CornCaptureVisual")
			and not playerGui:FindFirstChild("CornCapturePaint")
	)
	expect(not movement.active and not hud.active)
	expect(camera:GetAttribute("CornCaptureCameraOwner") == nil)
	expect(camera.FieldOfView == baseline.fov and camera.CameraType == baseline.cameraType)
end
local ok, problem = pcall(function()
	expect(Capture.IsValidSnapshot(snapshot(1, 1, 1).capture))
	local started = os.clock()
	controller:SetSnapshot(snapshot(1, 1, 1))
	expect(controller._state.active and camera.CameraType == Enum.CameraType.Scriptable)
	expect(movement.active and hud.active and not minimap._expanded)
	local model = assert(workspace:FindFirstChild("CornCaptureVisual"))
	expect(controller._state.frame == frame, "Authoritative frame changed")
	local expectedHead = frame
		* CFrame.new(0, 4, 0)
		* Pose.Get("capturing", os.clock() - controller._state.started, false).Head
	expect(
		(model.Head.Position - expectedHead.Position).Magnitude < 0.05,
		"Local capture visual lacks four-stud clearance"
	)
	expect(#model:GetChildren() == 13 and model:GetAttribute("CornCaptureOwned") == true)
	for _, definition in Pose.Parts do
		local part = assert(model:FindFirstChild(definition.Name))
		expect(
			part:IsA("Part")
				and part.Size == definition.Size
				and part.Anchored
				and not part.CanCollide
				and not part.CanTouch
				and not part.CanQuery
		)
	end
	expect(model.Head.CaptureFaceLight.Brightness == 1 and model.Head.CaptureFaceLight.Range == 12)
	for _, name in { "OpenMouth", "LowerJaw", "UpperTeeth", "LowerTeeth" } do
		local part = assert(model:FindFirstChild(name))
		expect(
			part:IsA("Part")
				and part.Anchored
				and not part.CanCollide
				and not part.CanTouch
				and not part.CanQuery
		)
	end
	local paint = assert(playerGui:FindFirstChild("CornCapturePaint"))
	expect(paint:IsA("ScreenGui") and paint.DisplayOrder == 60 and #paint:GetChildren() == 21)
	for _, drop in paint:GetChildren() do
		expect(drop:IsA("Frame") and not drop.Active and not drop.Selectable)
	end
	checks.one_owned_static_collisionless_rig_and_face_light = true
	checks.local_visual_four_studs_above_unchanged_authoritative_frame = true
	task.wait(0.25)
	expect(
		camera.FieldOfView >= 62 and camera.FieldOfView < 70,
		"Camera approach/FOV did not render"
	)
	local firstHead = model.Head.CFrame
	task.wait(0.07)
	expect(
		(model.Head.CFrame.LookVector - firstHead.LookVector).Magnitude > 0.01,
		"Head shake did not render"
	)
	task.wait(0.23)
	expect(model.OpenMouth.Size.Y > 1.29, "Mouth did not open")
	for _, drop in paint:GetChildren() do
		expect(drop.BackgroundTransparency < 0.2, "Paint did not appear during capture")
	end
	local elapsed = os.clock() - controller._state.started
	local pose = Pose.Get("capturing", elapsed, false)
	for _, name in { "Hat", "LeftEye", "RightEye" } do
		local actual = model.Head.CFrame:Inverse() * model[name].CFrame
		local expected = pose.Head:Inverse() * pose[name]
		expect(
			(actual.Position - expected.Position).Magnitude < 0.05,
			"Head detail separated during shake"
		)
	end
	local mouthLocal = model.Head.CFrame:Inverse() * model.OpenMouth.CFrame
	expect(mouthLocal.Position.Z < -1.3 and math.abs(mouthLocal.Position.X) < 0.01)
	checks.open_mouth_grouped_rapid_head_motion_and_noninteractive_colour_paint = true
	local deadline = controller._state.deadline
	controller:SetSnapshot(snapshot(1, 1, 1))
	expect(controller._state.deadline == deadline and deadline <= started + 1.01)
	-- Deliberately remove frame updates; wall-clock cleanup must still release ownership.
	RunService:UnbindFromRenderStep("CornCaptureCamera")
	controller._bound = false
	local waitUntil = deadline + 0.1
	while os.clock() < waitUntil do
		task.wait(math.min(0.05, waitUntil - os.clock()))
	end
	clean()
	checks.approach_FOV_duplicate_does_not_extend_and_wall_clock_cleanup_without_frames = true
	controller:SetSnapshot(snapshot(1, 1, 1))
	clean()
	controller:SetSnapshot(snapshot(1, 2, 1))
	expect(controller._state.active)
	controller:SetSnapshot(snapshot(1, 2, 0, "caught_out"))
	clean()
	checks.first_and_second_capture_ids_and_terminal_cleanup = true
	controller:SetSnapshot(snapshot(2, 1, 1))
	controller:SetSnapshot(nil)
	clean()
	controller:SetSnapshot(snapshot(2, 1, 1))
	clean()
	controller:SetSnapshot(snapshot(3, 1, 1))
	controller:SetSnapshot(snapshot(4, 0, 0, "preparing"))
	clean()
	checks.malformed_cancels_without_replay_and_retry_round_cancels = true
	controller:SetSnapshot(snapshot(4, 1, 1))
	replacement = Instance.new("Camera")
	replacement.Name = "CaptureReplacementAcceptance"
	replacement.FieldOfView = 91
	replacement.CameraType = Enum.CameraType.Custom
	replacement.Parent = workspace
	workspace.CurrentCamera = replacement
	controller:_step(os.clock())
	expect(
		not controller._state.active
			and replacement.FieldOfView == 91
			and replacement.CameraType == Enum.CameraType.Custom
	)
	workspace.CurrentCamera = camera
	replacement:Destroy()
	replacement = nil
	clean()
	checks.replacement_camera_untouched = true
	controller:SetSnapshot(snapshot(5, 1, 1))
	controller:Cancel("controlled fixture menu cancellation")
	clean()
	checks.explicit_cancel_restores_owned_camera_visual_and_coordinator_flags = true
end)
if replacement then
	if workspace.CurrentCamera == replacement then
		workspace.CurrentCamera = camera
	end
	replacement:Destroy()
end
controller._snapshot = { phase = "ready" }
controller:Destroy()
if workspace.CurrentCamera == camera and camera:GetAttribute("CornCaptureCameraOwner") == nil then
	camera.CFrame, camera.Focus = baseline.frame, baseline.focus
	camera.FieldOfView, camera.CameraSubject, camera.CameraType =
		baseline.fov, baseline.subject, baseline.cameraType
end
expect(ok, tostring(problem))
checks.cleanup = true
checks.method =
	"Actual current camera/Parts and scheduled1s cleanup with controlled snapshots; real first/second catches accepted separately"
return game:GetService("HttpService"):JSONEncode(checks)
