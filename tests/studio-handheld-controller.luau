-- Client only, active first-person round with the real selected slot empty.
-- Actual owned camera-child geometry and controlled snapshots; no gameplay/remotes/camera-state writes.
local player = assert(game:GetService("Players").LocalPlayer)
local camera = assert(workspace.CurrentCamera)
local character = assert(player.Character)
local humanoid = assert(character:FindFirstChildOfClass("Humanoid"))
assert(
	humanoid.Health > 0
		and player.CameraMode == Enum.CameraMode.LockFirstPerson
		and camera.CameraType == Enum.CameraType.Custom
		and camera.CameraSubject == humanoid,
	"Activate a first-person round before this fixture"
)
assert(
	not camera:FindFirstChild("CornHandheld")
		and camera:GetAttribute("CornCaptureCameraOwner") == nil,
	"Select an empty real slot; no capture may be active"
)
local Module = require(player.PlayerScripts.GameClient.Controllers.HandheldController)
local Presentation = require(game.ReplicatedStorage.GameShared.Game.HandheldPresentation)
local controller = setmetatable({}, { __index = Module })
controller:Init({})
controller._minimap, controller._capture = { _expanded = false }, { _state = { active = false } }
local baseline =
	{ cameraType = camera.CameraType, subject = camera.CameraSubject, fov = camera.FieldOfView }
local checks, foreign = {}, nil
local function expect(condition, message)
	assert(condition, message or "Actual handheld fixture failed")
end
local function snapshot(roundId, useId, useKind, kind, phase, selected)
	local index = selected or 1
	local slots = { "empty", "empty", "empty", "empty", "empty" }
	slots[index] = kind
	return {
		minimap = { round_id = roundId },
		phase = phase or "active",
		inventory = {
			slots = slots,
			selected = index,
			energy_remaining = 0,
			use = { id = useId, kind = useKind },
		},
	}
end
local function show(roundId, useId, useKind, kind, phase, selected)
	controller:SetSnapshot(snapshot(roundId, useId, useKind, kind, phase, selected))
end
local function noVisual()
	expect(controller._visual == nil and not camera:FindFirstChild("CornHandheld"))
end
local ok, problem = pcall(function()
	show(1, 3, "trap", "key")
	expect(
		controller._visual and controller._kind == "key" and not controller._gesture,
		"Initial sync replayed use"
	)
	for _, kind in { "key", "energy", "trap" } do
		show(1, 3, "trap", kind)
		local model = assert(controller._visual)
		expect(
			model.Parent == camera
				and model:GetAttribute("CornHandheldOwned") == true
				and model:GetAttribute("ItemKind") == kind
		)
		expect(
			#model:GetChildren() == #Presentation.Definitions(kind) + 3
				and #model:GetChildren() <= 24
		)
		for _, part in model:GetChildren() do
			expect(
				part:IsA("Part")
					and part.Anchored
					and not part.CanCollide
					and not part.CanTouch
					and not part.CanQuery
					and not part.CastShadow
			)
		end
		expect(model.PrimaryPart == model.Anchor and model.Anchor.Transparency == 1)
		for _, child in model:GetDescendants() do
			expect(
				not child:IsA("Light") and not child:IsA("Attachment"),
				"Held model still lights the world"
			)
		end
		if kind == "energy" then
			local label = assert(model.Can:FindFirstChild("EnergyLabel"))
			expect(
				label:IsA("SurfaceGui")
					and label.Face == Enum.NormalId.Back
					and label.CanvasSize == Vector2.new(256, 256)
			)
			expect(not label.AlwaysOnTop and not label.Active and label.LightInfluence == 0)
			expect(
				label.Paper.Rotation == 90
					and label.Paper.Logo.Text == "+"
					and label.Paper:FindFirstChild("Name").Text == "ENERGY"
			)
		end
		local right = character:FindFirstChild("RightHand")
			or character:FindFirstChild("Right Arm")
			or character:FindFirstChild("RightLowerArm")
		if right and right:IsA("BasePart") then
			expect(model.RightHand.Color == right.Color, "Avatar hand color mismatch")
		end
		controller:_step(os.clock())
		expect(controller._visual == model, "Unchanged kind rebuilt geometry")
	end
	checks.actual_key_can_trap_avatar_hands_safe_flags_bound_and_no_rebuild = true
	checks.readable_can_label_camera_side_no_alwaysontop_no_world_lighting = true
	show(1, 3, "trap", "energy")
	local model = controller._visual
	local label = model.Can.EnergyLabel
	show(1, 4, "energy", "empty")
	expect(
		controller._gesture and controller._gesture.kind == "energy" and controller._visual == model
	)
	local deadline = controller._gesture.deadline
	task.wait(0.15)
	controller:_step(os.clock())
	show(1, 4, "energy", "empty")
	expect(controller._gesture.deadline == deadline, "Duplicate extended energy")
	local finished = deadline + 0.07
	while os.clock() < finished do
		task.wait(math.min(0.05, finished - os.clock()))
	end
	noVisual()
	expect(not controller._gesture)
	expect(model.Parent == nil and label.Parent == nil, "Can label survived model cleanup")
	checks.accepted_energy_consumed_kind_reuses_geometry_and_wallclock_point9_cleanup = true
	show(1, 4, "energy", "trap")
	show(1, 5, "trap", "empty")
	expect(controller._gesture and controller._gesture.kind == "trap")
	local trapDeadline = controller._gesture.deadline
	task.wait(0.1)
	show(1, 5, "trap", "empty")
	expect(controller._gesture.deadline == trapDeadline)
	show(1, 5, "trap", "key", "active", 2)
	expect(
		not controller._gesture and controller._kind == "key",
		"Selection did not cancel gesture"
	)
	checks.accepted_trap_point55_and_selection_interrupt = true
	show(1, 0, "none", "empty", "caught_out")
	noVisual()
	show(1, 5, "trap", "key")
	noVisual()
	show(2, 0, "none", "trap")
	expect(controller._visual)
	controller._capture._state.active = true
	controller:_step(os.clock())
	noVisual()
	controller._capture._state.active = false
	controller:_step(os.clock())
	expect(controller._visual)
	controller._minimap._expanded = true
	controller:_step(os.clock())
	noVisual()
	controller._minimap._expanded = false
	controller:_step(os.clock())
	expect(controller._visual)
	show(2, 0, "none", "trap", "caught")
	noVisual()
	checks.terminal_reset_stale_active_retry_capture_map_and_caught_cleanup = true
	controller:Clear("foreign fixture")
	foreign = Instance.new("Model")
	foreign.Name = "CornHandheld"
	foreign.Parent = camera
	show(3, 0, "none", "key")
	expect(controller._visual == nil and foreign.Parent == camera, "Foreign model touched")
	foreign:Destroy()
	foreign = nil
	controller:_step(os.clock())
	expect(controller._visual)
	controller:SetSnapshot(nil)
	noVisual()
	checks.foreign_model_refusal_and_malformed_cleanup = true
	expect(
		camera.CameraType == baseline.cameraType
			and camera.CameraSubject == baseline.subject
			and camera.FieldOfView == baseline.fov,
		"Handheld altered camera state"
	)
	checks.camera_type_subject_FOV_unchanged = true
end)
controller:Destroy()
if foreign then
	foreign:Destroy()
end
expect(not camera:FindFirstChild("CornHandheld"), "Fixture model remains")
expect(ok, tostring(problem))
checks.cleanup = true
checks.method =
	"Actual local held Parts/whole-model pivot with controlled selected/use snapshots; ordinary real accepted use tested separately"
return game:GetService("HttpService"):JSONEncode(checks)
