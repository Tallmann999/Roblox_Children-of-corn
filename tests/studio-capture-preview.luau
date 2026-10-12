-- Controlled ten-second GPU preview of the ending pose, not a real capture test.
-- Client only; one temporary owned rig/camera and automatic exact cleanup.
local player = assert(game:GetService("Players").LocalPlayer, "Client required")
local camera = assert(workspace.CurrentCamera)
assert(
	not workspace:FindFirstChild("CornCaptureVisual")
		and camera:GetAttribute("CornCaptureCameraOwner") == nil,
	"Capture already active"
)
local Module = require(player.PlayerScripts.GameClient.Controllers.CaptureController)
local Capture = require(game.ReplicatedStorage.GameShared.Game.CapturePresentation)
local root = assert(player.Character and player.Character:FindFirstChild("HumanoidRootPart"))
local controller = setmetatable({}, { __index = Module })
controller:Init({})
local now = os.clock()
local capture = { id = 1, remaining = 1, frame = root.CFrame * CFrame.new(0, 0, -8) }
assert(Capture.Observe(controller._state, 1, capture, "caught", now) == "begin")
controller._snapshot = { phase = "ready" }
-- Fixture-only timing: production observations still enforce a maximum of one second.
controller._state.deadline = now + 10
controller._state.started = now - Capture.ApproachDuration
local ok, began = pcall(function()
	return controller:_begin()
end)
if not ok or not began then
	controller:Destroy()
	error(tostring(began))
end
task.delay(10.1, function()
	controller:Destroy()
end)
return game:GetService("HttpService"):JSONEncode({
	preview = true,
	real_capture = false,
	duration_sec = 10,
	parts = 9,
	ending_FOV = camera.FieldOfView,
	owned_camera = true,
	automatic_exact_cleanup = true,
})
