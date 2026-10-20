-- Read-only normal-bootstrap Client observer. No actor/camera/light writes.
-- Run while walking or turning in a real active A round. Diagnostics, not FPS QA.
local run = game:GetService("RunService")
local http = game:GetService("HttpService")
assert(run:IsStudio() and run:IsClient() and run:IsRunning(), "Studio Client Play required")
local player = assert(game:GetService("Players").LocalPlayer)
local map = assert(workspace:FindFirstChild("CornMap"))
assert(
	map:GetAttribute("corn_project_id") == "children_of_corn"
		and map:GetAttribute("HarvestArtVariant") == "A"
)
local client = player.PlayerScripts.GameClient
assert(client.Bootstrap.Enabled, "Normal Bootstrap must run")
local controller = require(client.Controllers.FlashlightController)
assert(controller._snapshot and controller._snapshot.phase == "active", "Start a real round first")
local model = assert(
	workspace.CurrentCamera:FindFirstChild("CornPersonalFlashlight"),
	"Personal light not visible"
)
assert(controller._visual == model and controller:_visualOwned(), "Native exact ownership failed")
local parts, spots, pointLights = 0, {}, {}
for _, item in model:GetDescendants() do
	assert(not item:IsA("LuaSourceContainer"), "Code in viewmodel")
	if item:IsA("BasePart") then
		parts += 1
		assert(
			item.Anchored
				and not item.CanCollide
				and not item.CanTouch
				and not item.CanQuery
				and not item.CastShadow
		)
	elseif item:IsA("SpotLight") then
		spots[item.Name] = {
			range = item.Range,
			brightness = item.Brightness,
			angle = item.Angle,
			shadows = item.Shadows,
			enabled = item.Enabled,
		}
	elseif item:IsA("PointLight") then
		pointLights[item.Name] =
			{ range = item.Range, brightness = item.Brightness, enabled = item.Enabled }
	end
end
local samples = {}
local started = os.clock()
for _ = 1, 100 do
	run.RenderStepped:Wait()
	assert(
		controller._visual == model and controller:_visualOwned(),
		"Viewmodel churn or native ownership drift"
	)
	local root = assert(player.Character and player.Character:FindFirstChild("HumanoidRootPart"))
	local frame = workspace.CurrentCamera.CFrame
	local effect, state = controller._effect, controller._state
	local offset = if effect then effect.base:ToObjectSpace(effect.result) else CFrame.identity
	local pitch, yaw, roll = offset:ToOrientation()
	table.insert(samples, {
		t = os.clock() - started,
		speed = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude,
		position = { root.Position.X, root.Position.Y, root.Position.Z },
		look = { frame.LookVector.X, frame.LookVector.Y, frame.LookVector.Z },
		weight = state.weight,
		phase = state.phase,
		lag = { state.lagPitch, state.lagYaw },
		cameraOffset = { offset.X, offset.Y, offset.Z, pitch, yaw, roll },
		on = controller._on,
	})
end
local lighting = game:GetService("Lighting")
local atmospheres = {}
for _, item in lighting:GetChildren() do
	if item:IsA("Atmosphere") then
		table.insert(atmospheres, { name = item.Name, density = item.Density, haze = item.Haze })
	end
end
return http:JSONEncode({
	passed = true,
	duration = os.clock() - started,
	parts = parts,
	spots = spots,
	pointLights = pointLights,
	samples = samples,
	brightness = lighting.Brightness,
	ambient = { lighting.Ambient.R, lighting.Ambient.G, lighting.Ambient.B },
	atmospheres = atmospheres,
	limits = "One real client, normal bootstrap. Read-only render sampling; motion/input staging recorded separately. Not long FPS, fear, or four-client acceptance.",
})
