-- Real pure presentation module with Lune data types. No rendering/Studio claim.
local fs = require("@lune/fs")
local r = require("@lune/roblox")
local CF, V3, V2 = r.CFrame, r.Vector3, r.Vector2
local fn = assert(loadstring(fs.readFile("src/shared/Game/FlashlightPresentation.luau")))
setfenv(
	fn,
	setmetatable({
		CFrame = CF,
		Vector3 = V3,
		Color3 = r.Color3,
		ColorSequence = r.ColorSequence,
		NumberSequence = r.NumberSequence,
		NumberSequenceKeypoint = r.NumberSequenceKeypoint,
		Enum = r.Enum,
	}, { __index = getfenv() })
)
local Flash = fn()
local function close(a, b, tolerance, message)
	for index, value in { a:GetComponents() } do
		assert(math.abs(value - ({ b:GetComponents() })[index]) <= tolerance, message)
	end
end
local function finiteFrame(frame)
	for _, value in { frame:GetComponents() } do
		assert(value == value and math.abs(value) < 4, "Nonfinite/unbounded local frame")
	end
	assert(math.abs(frame.XVector.Magnitude - 1) < 0.00001)
	assert(math.abs(frame.XVector:Dot(frame.YVector)) < 0.00001)
	assert(frame.XVector:Cross(frame.YVector):Dot(frame.ZVector) > 0.99999)
end
local definitions, names = Flash.Definitions(), {}
assert(table.isfrozen(Flash) and table.isfrozen(definitions) and #definitions == 11)
assert(#definitions <= Flash.MaxParts and Flash.NearClearance == 0.65)
assert(Flash.Settings.Lights.main.range == 24 and Flash.Settings.Lights.main.angle == 26)
assert(Flash.Settings.Lights.main.brightness == 22.62 and not Flash.Settings.Lights.main.shadows)
assert(Flash.Settings.Lights.fill.range == 24 and Flash.Settings.Lights.fill.angle == 54)
assert(Flash.Settings.Lights.fill.brightness == 15.08 and not Flash.Settings.Lights.fill.shadows)
assert(table.isfrozen(Flash.Settings.Lights.main) and table.isfrozen(Flash.Settings.Lights.fill))
assert(
	Flash.Settings.HandFill.range == 1.5
		and Flash.Settings.HandFill.angle == 75
		and Flash.Settings.HandFill.brightness == 0.08
		and not Flash.Settings.HandFill.shadows
)
local toPalm = (V3.new(0, -0.12, 0.22) - Flash.HandFillFrame.Position).Unit
assert(
	Flash.HandFillFrame.LookVector:Dot(toPalm) > 0.99,
	"Hand fill does not face back toward the grip"
)
assert(Flash.Settings.Cone == nil and Flash.ConeFrames == nil, "Rejected billboard cone remains")
-- Both cones widen physically from the lens: the spill always surrounds the core.
for _, distance in {1, 5, 10, 20, 32} do
 local coreRadius=distance*math.tan(math.rad(Flash.Settings.Lights.main.angle/2))
 local spillRadius=distance*math.tan(math.rad(Flash.Settings.Lights.fill.angle/2))
 assert(coreRadius>0 and spillRadius>coreRadius*2)
end
local defaults=Flash.Tuning(nil)
assert(defaults.wide.brightness==15.08 and defaults.wide.range==24 and defaults.wide.angle==54 and not defaults.wide.shadows)
assert(defaults.core.brightness>defaults.wide.brightness and defaults.core.angle<defaults.wide.angle)
assert(defaults.pose.pitch==-6)
local clamped=Flash.Tuning({wide={brightness=math.huge,range=-10,angle=1e9,shadows=true},core={brightness=100,range=999,angle=-10},pose={pitch=-100}})
assert(clamped.wide.brightness==15.08 and clamped.wide.range==4 and clamped.wide.angle==100 and clamped.wide.shadows)
assert(clamped.core.brightness==40 and clamped.core.range==64 and clamped.core.angle==6 and clamped.pose.pitch==-30)
for _,bad in {false,42,"bad",{wide=false,core=42,pose={pitch=0/0}}}do
 local v=Flash.Tuning(bad);assert(v.pose.pitch==-6 and v.core.range==24)
end
local copy=Flash.Tuning(defaults);copy.wide.angle=99;assert(defaults.wide.angle==54)
local hands = 0
for _, definition in definitions do
	assert(table.isfrozen(definition) and not names[definition.name])
	names[definition.name] = true
	assert(definition.size.X > 0 and definition.size.Y > 0 and definition.size.Z > 0)
	assert(definition.size.Magnitude < 0.8 and typeof(definition.color) == "Color3")
	assert(
		definition.material.EnumType == r.Enum.Material
			and definition.shape.EnumType == r.Enum.PartType
	)
	if definition.isHand then
		hands += 1
	end
end
assert(hands == 2 and names.Body and names.Head and names.Lens and names.Rim)
assert(Flash.LensFrame.LookVector:Dot(V3.new(0, 0, -1)) > 0.999)

local maxTranslation, maxRoll, maxPitch, maxVelocity, poses = 0, 0, 0, 0, 0
local function inspect(output)
	finiteFrame(output.view)
	finiteFrame(output.aim)
	finiteFrame(output.camera)
	assert(output.view.Position.X < 0 and output.view.Position.Y < -0.4)
	assert(output.bobWeight >= 0 and output.bobWeight <= 1.350001)
	local pitch, _, roll = output.camera:ToOrientation()
	maxTranslation = math.max(maxTranslation, output.camera.Position.Magnitude)
	maxRoll, maxPitch = math.max(maxRoll, math.abs(roll)), math.max(maxPitch, math.abs(pitch))
	assert(output.camera.Position.Magnitude <= 0.04)
	assert(math.abs(roll) <= math.rad(0.35) and math.abs(pitch) <= math.rad(0.2))
	local aimPitch, aimYaw = output.aim:ToOrientation()
	assert(math.abs(aimPitch) <= math.rad(2.001) and math.abs(aimYaw) <= math.rad(2.001))
	poses += 1
end
local segments = {
	{ duration = 1.5, speed = 0, grounded = true },
	{ duration = 3, speed = 12, grounded = true, turn = V2.new(0.03, -0.08) },
	{ duration = 0.7, speed = 0, grounded = true },
	{ duration = 2, speed = 18, grounded = true },
	{ duration = 0.5, speed = 18, grounded = false },
	{ duration = 1, speed = 3, grounded = true },
	{ duration = 0.5, speed = 0, grounded = true, turn = V2.new(-0.02, 0.1) },
}
local function simulate(fps)
	local state, endpoints, previous = Flash.NewState(), {}, nil
	for _, segment in segments do
		local elapsed, output = 0, nil
		while elapsed < segment.duration - 0.000000001 do
			local dt = math.min(1 / fps, segment.duration - elapsed)
			local old = state
			local input = {
				speed = segment.speed,
				grounded = segment.grounded,
				turn = (segment.turn or V2.zero) * dt,
			}
			state, output = Flash.Step(state, dt, input)
			assert(state ~= old and table.isfrozen(state), "Step mutates or reuses prior state")
			inspect(output)
			if previous then
				local velocity = (output.camera.Position - previous.Position).Magnitude / dt
				maxVelocity = math.max(maxVelocity, velocity)
				assert(velocity < 0.8, "Walking motion produced a positional jerk")
			end
			previous, elapsed = output.camera, elapsed + dt
		end
		table.insert(endpoints, { state = state, output = output })
	end
	return endpoints
end
local reference = simulate(60)
for _, fps in { 30, 48, 90, 144, 240 } do
	for index, endpoint in simulate(fps) do
		local expected = reference[index]
		for field, value in endpoint.state do
			assert(
				math.abs(value - expected.state[field]) < 0.00000001,
				"FPS-dependent state: " .. field .. " at " .. fps
			)
		end
		close(endpoint.output.camera, expected.output.camera, 0.000002, "FPS-dependent camera bob")
		close(endpoint.output.view, expected.output.view, 0.000002, "FPS-dependent hand bob")
		close(endpoint.output.aim, expected.output.aim, 0.000002, "FPS-dependent camera aim lag")
	end
end

-- Steady walk is 1.7 Hz; sprint cadence and amplitude remain capped.
local state, output = Flash.NewState(), nil
for _ = 1, 300 do
	state, output = Flash.Step(state, 1 / 60, { speed = 12, grounded = true })
end
local initialPhase = state.phase
for _ = 1, 60 do
	state, output = Flash.Step(state, 1 / 60, { speed = 12, grounded = true })
end
assert(math.abs((state.phase - initialPhase) % (2 * math.pi) - (1.7 % 1) * 2 * math.pi) < 0.000001)
for _ = 1, 300 do
	state, output = Flash.Step(state, 1 / 60, { speed = 50, grounded = true })
end
assert(math.abs(state.weight - 1.35) < 0.000001)
assert(state.travelSpeed <= 12 * 2.1 / 1.7 + 0.000001)
for _ = 1, 120 do
	state, output = Flash.Step(state, 1 / 60, { speed = 0, grounded = true })
end
assert(
	output.bobWeight < 0.000001 and output.camera.Position.Magnitude < 0.000001,
	"Stop did not settle"
)
for _ = 1, 240 do
	state, output = Flash.Step(state, 1 / 60, { speed = 0, grounded = true })
	close(output.camera, CF.identity, 0.000001, "Idle camera drifts or breathes")
end

-- Look lag starts opposite camera motion, then converges smoothly with no turn.
state, output = Flash.Step(Flash.NewState(), 1 / 60, { turn = V2.new(0.01, -0.02) })
assert(state.lagPitch < 0 and state.lagYaw > 0)
local startLag = math.abs(state.lagYaw)
for _ = 1, 120 do
	state, output = Flash.Step(state, 1 / 60, {})
end
assert(math.abs(state.lagYaw) < startLag * 0.000001)
for _ = 1, 180 do
	state, output = Flash.Step(state, 1 / 60, { turn = V2.new(1000, -1000) })
	inspect(output)
end
assert(math.abs(state.lagPitch) <= math.rad(2) and math.abs(state.lagYaw) <= math.rad(2))

-- Teleports, bad samples and long stalls cannot become motion/aim impulses.
local moving = Flash.Step(Flash.NewState(), 0.2, { speed = 18, grounded = true })
for _, input in
	{
		{ speed = 100000, grounded = true },
		{ speed = 0 / 0, grounded = true },
		{ speed = math.huge, grounded = true },
		{ speed = 12, grounded = true, teleported = true, turn = V2.new(1, 1) },
	}
do
	local reset, result = Flash.Step(moving, 1 / 60, input)
	assert(
		reset.weight == 0 and reset.travelSpeed == 0 and reset.lagYaw == 0 and reset.lagPitch == 0
	)
	close(result.camera, CF.identity, 0.000001, "Teleport/malformed input added camera shake")
	inspect(result)
end
for _, dt in { -1, 0, 0 / 0, math.huge, 100000 } do
	local _, result = Flash.Step(moving, dt, { speed = 12, grounded = true, turn = V2.new(1, 1) })
	inspect(result)
end
for _, old in
	{
		false,
		5,
		"wrong",
		{
			phase = math.huge,
			idlePhase = 0 / 0,
			weight = math.huge,
			travelSpeed = -50,
			lagPitch = 0 / 0,
			lagYaw = 99999,
		},
	}
do
	local _, result = Flash.Step(
		old,
		1 / 60,
		{ speed = -50, turn = V2.new(0 / 0, math.huge), aspect = math.huge }
	)
	inspect(result)
end

-- Entire primitive model stays ahead of the camera near plane at all tested
-- viewport shapes and gait phases, leaving the existing right inventory free.
local closest = -math.huge
for _, aspect in { 0.3, 0.56, 1, 16 / 9, 4, 0 / 0 } do
	local motion = Flash.NewState()
	for sample = 1, 240 do
		local pose
		motion, pose = Flash.Step(motion, 1 / 60, { speed = 18, grounded = true, aspect = aspect })
		for _, definition in definitions do
			local frame = pose.aim * pose.view * definition.localFrame
			for _, x in { -1, 1 } do
				for _, y in { -1, 1 } do
					for _, z in { -1, 1 } do
						local point = frame:PointToWorldSpace(definition.size * V3.new(x, y, z) / 2)
						closest = math.max(closest, point.Z)
						assert(
							point.Z < -Flash.NearClearance,
							"Flashlight intersects camera near plane"
						)
					end
				end
			end
		end
	end
end
print(
	"PASS: 11 frozen primitive flashlight/hand parts, bright circular core/soft wider spill at lens, directed hand fill, no billboard cone, pure immutable motion, 30/48/60/90/144/240 FPS equality, 1.7 Hz walk/2.1 Hz sprint cap, smooth idle/stop and directional mouse lag, teleport/NaN/stall guards, "
		.. poses
		.. " bounded rigid poses; camera max translation="
		.. maxTranslation
		.. " roll="
		.. math.deg(maxRoll)
		.. " pitch="
		.. math.deg(maxPitch)
		.. " velocity="
		.. maxVelocity
		.. "; near clearance="
		.. -closest
)
