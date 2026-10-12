-- Ten-second controlled GPU preview; first-person active with actual selected slot empty.
-- Replace this fixture literal for key/trap/energy; no production debug API or gameplay claim.
local kind = "energy"
local using = false
local player = assert(game:GetService("Players").LocalPlayer)
local camera = assert(workspace.CurrentCamera)
assert(
	player.CameraMode == Enum.CameraMode.LockFirstPerson
		and camera.CameraType == Enum.CameraType.Custom,
	"Active first-person round required"
)
assert(
	not camera:FindFirstChild("CornHandheld")
		and camera:GetAttribute("CornCaptureCameraOwner") == nil,
	"Select an empty real slot outside capture"
)
local Module = require(player.PlayerScripts.GameClient.Controllers.HandheldController)
local Presentation = require(game.ReplicatedStorage.GameShared.Game.HandheldPresentation)
local controller = setmetatable({}, { __index = Module })
controller:Init({})
controller._minimap, controller._capture = { _expanded = false }, { _state = { active = false } }
controller:SetSnapshot({
	minimap = { round_id = 1 },
	phase = "active",
	inventory = {
		slots = { kind, "empty", "empty", "empty", "empty" },
		selected = 1,
		energy_remaining = 0,
		use = { id = 0, kind = "none" },
	},
})
assert(controller._visual, "Preview model could not be created")
local frozenTime = os.clock()
if using and Presentation.Duration(kind) > 0 then
	controller._gesture = {
		kind = kind,
		selected = 1,
		started = frozenTime - Presentation.Duration(kind) * 0.5,
		deadline = frozenTime + 10,
	}
end
controller:_step(frozenTime)
local RunService = game:GetService("RunService")
local name = "CornHandheldPreviewAcceptance"
RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 3, function()
	controller:_step(frozenTime)
end)
task.delay(10, function()
	RunService:UnbindFromRenderStep(name)
	controller:Destroy()
end)
return game:GetService("HttpService"):JSONEncode({
	preview = true,
	real_use = false,
	duration_sec = 10,
	kind = kind,
	using = using,
	parts = #controller._visual:GetChildren(),
	camera_state_untouched = true,
	automatic_cleanup = true,
})
