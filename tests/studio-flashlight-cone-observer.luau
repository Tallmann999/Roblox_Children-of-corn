-- Run in a temporary LocalScript beside the normal Bootstrap, not MCP require cache.
-- Read-only render sample; diagnostic focus/camera/input staging is external.
local run = game:GetService("RunService")
local http = game:GetService("HttpService")
assert(run:IsStudio() and run:IsClient() and run:IsRunning())
local player = assert(game:GetService("Players").LocalPlayer)
local controller = require(player.PlayerScripts.GameClient.Controllers.FlashlightController)
local model = assert(controller._visual, "Start a real active A round")
assert(workspace.CornMap:GetAttribute("HarvestArtVariant") == "A")
assert(controller:_visualOwned(), "Native ownership readback failed")
local beams, lights = {}, {}
local parts = 0
for _, item in model:GetDescendants() do
	assert(not item:IsA("LuaSourceContainer"))
	if item:IsA("Beam") then
		table.insert(beams, item)
		assert(item.FaceCamera and item.Texture == "" and item.Attachment0 and item.Attachment1)
	elseif item:IsA("Light") then
		assert(item:IsA("SpotLight"), "Spherical PointLight remains")
		lights[item.Name] = { angle = item.Angle, range = item.Range, brightness = item.Brightness }
	elseif item:IsA("BasePart") then
		parts += 1
		assert(item.Anchored and not item.CanCollide and not item.CanTouch and not item.CanQuery)
	end
end
assert(#beams == 4 and parts <= 14, "Unexpected cone budget")
local samples = {}
local started = os.clock()
for _ = 1, 80 do
	run.RenderStepped:Wait()
	assert(
		controller._visual == model and controller:_visualOwned(),
		"Viewmodel churn or native ownership drift"
	)
	local current = {}
	for _, beam in beams do
		assert(beam.Enabled == (controller._on and controller._coneDistance >= 0.5))
		local delta = beam.Attachment1.WorldPosition - beam.Attachment0.WorldPosition
		assert(delta.Magnitude > 0 and delta.Magnitude <= 30.01)
		assert(beam.Width0 < beam.Width1 and beam.Width0 <= 0.2)
		local forward = workspace.CurrentCamera.CFrame.LookVector
		table.insert(
			current,
			{
				name = beam.Name,
				length = delta.Magnitude,
				startWidth = beam.Width0,
				endWidth = beam.Width1,
				forwardDot = delta.Unit:Dot(forward),
				enabled = beam.Enabled,
			}
		)
	end
	table.insert(samples, { t = os.clock() - started, beams = current })
end
return http:JSONEncode({
	passed = true,
	duration = os.clock() - started,
	parts = parts,
	lights = lights,
	beams = #beams,
	samples = samples,
	limits = "One normal-bootstrap client. Read-only render sampling, not full-round fear/FPS/four-client acceptance.",
})
