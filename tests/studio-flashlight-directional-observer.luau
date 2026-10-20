-- Same-context normal-bootstrap observer; no actor, camera or light writes.
-- Focus/cursor diagnostic staging, if present, must be recorded separately.
local run = game:GetService("RunService")
local p = assert(game.Players.LocalPlayer)
assert(run:IsStudio() and run:IsClient() and run:IsRunning())
local f = require(p.PlayerScripts.GameClient.Controllers.FlashlightController)
local model = assert(f._visual, "Active A lamp required")
assert(f:_visualOwned() and workspace.CornMap:GetAttribute("HarvestArtVariant") == "A")
local main, fill = model.Emitter.LensAim.main, model.Emitter.LensAim.fill
assert(main.Face == Enum.NormalId.Front and fill.Face == main.Face)
assert(main.Parent == fill.Parent and main.Parent.CFrame == CFrame.identity)
assert(main.Angle == 28 and main.Range == 64 and main.Brightness == 4 and main.Shadows)
assert(fill.Angle == 56 and fill.Range == 32 and math.abs(fill.Brightness - 0.45) < 1e-6 and fill.Shadows)
local parts, lights = 0, 0
for _, d in model:GetDescendants() do
	assert(not d:IsA("Beam") and not d:IsA("PointLight") and not d:IsA("LuaSourceContainer"))
	if d:IsA("BasePart") then
		parts += 1
		assert(d.Anchored and not d.CanCollide and not d.CanTouch and not d.CanQuery and not d.CastShadow)
	elseif d:IsA("Light") then
		lights += 1
		assert(d:IsA("SpotLight"))
	end
end
assert(parts == 12 and lights == 3)
local samples, start = {}, os.clock()
for _ = 1, 100 do
	run.RenderStepped:Wait()
	assert(f._visual == model and f:_visualOwned(), "Native model churn/ownership drift")
	assert(main.Enabled == f._on and fill.Enabled == f._on)
	local axis, camera = main.Parent.WorldCFrame, workspace.CurrentCamera.CFrame
	assert(axis.LookVector:Dot(camera.LookVector) > 0.998, "Lens direction diverges from mouse aim")
	local effect = f._effect
	local offset = if effect then effect.base:ToObjectSpace(effect.result) else CFrame.identity
	local pitch, _, roll = offset:ToOrientation()
	assert(offset.Position.Magnitude < 0.04 and math.abs(roll) <= math.rad(0.351))
	table.insert(samples, {
		t = os.clock() - start,
		on = f._on,
		lens = { axis.X, axis.Y, axis.Z },
		forwardDot = axis.LookVector:Dot(camera.LookVector),
		cameraTranslation = offset.Position.Magnitude,
		cameraRoll = roll,
		cameraPitch = pitch,
	})
end
local atmosphere = game.Lighting:FindFirstChildOfClass("Atmosphere")
return game.HttpService:JSONEncode({
	passed = true,
	parts = parts,
	spotLights = lights,
	beams = 0,
	pointLights = 0,
	duration = os.clock() - start,
	samples = samples,
	ambient = tostring(game.Lighting.Ambient),
	brightness = game.Lighting.Brightness,
	fog = atmosphere and { density = atmosphere.Density, haze = atmosphere.Haze },
	limits = "One normal-bootstrap client. Focus/cursor staging recorded separately. No GPU image acceptance, physical mouse movement, long FPS, four-client or fear acceptance.",
})
