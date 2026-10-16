-- Reuse the established camera/event adapter, then exercise the actual new
-- CaptureController branch. The separate visual fixture uses actual Instances.
local fs = require("@lune/fs")
local base = fs.readFile("tests/capture-presentation.luau")
local marker = "controller:SetSnapshot(snapshot(1, 1, 1))"
local at = assert(base:find(marker, 1, true), "Capture adapter boundary changed")
local setup = base:sub(1, at - 1)
local checks = [==[
local keys, created = {}, {}
for _, name in {"HarvestArtGeometry", "HarvestWardenVisual"} do
	local item = make("ModuleScript")
	item.Name, item.Parent = name, games
end
local originalRequire = env.require
local failAfterYield = false
env.require = function(item)
	if item.Name == "HarvestArtGeometry" then
		return {Template = function(key)
			table.insert(keys, key)
			if failAfterYield then controller:Cancel("simulated mesh-build reset") end
			return {key = key}
		end}
	elseif item.Name == "HarvestWardenVisual" then
		return {new = function(template, host)
			local model = make("Model")
			model.Name, model.Parent = "HarvestWardenVisual", host
			local visual = {model = model, template = template}
			function visual:Step(frame, pose, visible)
				assert(visible and pose.Head and pose.LeftEye == pose.Head and pose.RightEye == pose.Head)
				self.frame, self.pose = frame, pose
			end
			function visual:Destroy() self.model:Destroy(); self.destroyed = true end
			table.insert(created, visual)
			return visual
		end}
	end
	return originalRequire(item)
end
for index, variant in {"A", "B"} do
	map:SetAttribute("HarvestArtVariant", variant)
	controller:SetSnapshot(snapshot(index, 1, 1))
	assert(controller._state.active and controller._bound and controller._warden)
	local visual = controller._warden
	assert(visual.template.key == (if variant == "A" then "WardenClassic" else "WardenDetailed"))
	assert(next(controller._mouthParts) == nil, "Legacy block mouth appeared on Warden")
	for _, part in controller._parts do assert(part.Transparency == 1) end
	assert(#controller._visual:GetChildren() == 10, "Compatibility carriers/topology changed")
	assert(controller._state.frame == value.frame, "Authoritative capture frame changed")
	local frame = value.frame * r.CFrame.new(0,4,0)
	local face = frame * Pose.WardenAssetFrame * Pose.ScaleWardenFrame(visual.pose.Head * r.CFrame.new(0,7.7,.42))
	local focus = face.Position + frame.LookVector * 1.05
	assert((camera.Focus.Position-focus).Magnitude < 0.00001, "Close-up targets old giant head")
	assert(#controller._hiddenServer == 27)
	assert(invisibleRoot.LocalTransparencyModifier == 0 and secondRoot.LocalTransparencyModifier == 0)
	now += .35
	controller:_step(now)
	assert(visual.pose.LeftArm ~= r.CFrame.identity, "Warden capture arms not animated")
	assert(visual.pose.Head == visual.pose.Hat and visual.pose.Head == visual.pose.LeftEye)
	controller:Cancel("test complete")
	assert(visual.destroyed and not controller._warden)
	clean()
	for _, part in originalParts do assert(part.LocalTransparencyModifier == .2) end
	for _, part in secondParts do assert(part.LocalTransparencyModifier == .2) end
	for _, part in thirdParts do assert(part.LocalTransparencyModifier == .3) end
end
-- Initial mesh generation can yield; a reset during that interval must reject
-- the stale art without beginning a camera effect or attaching a local rig.
failAfterYield = true
controller:SetSnapshot(snapshot(3, 1, 1))
assert(#created == 2 and not controller._warden and not controller._visual)
clean()
controller:Destroy()
print("PASS: actual CaptureController A/B template choice, nine hidden compatibility carriers, actual Warden face camera, grouped shaking head/eyes, capture arms, no old block mouth, three-rig masking/Root preservation, cleanup and stale mesh-build reset guard")
]==]
local fn = assert(loadstring(setup .. checks, "harvest-warden-capture"))
fn()
