--!strict

local MonsterPose = {}
local cf, v3 = CFrame.new, Vector3.new
MonsterPose.HeightScale = 1.3
MonsterPose.FeetY = -3
function MonsterPose.ScalePosition(position: Vector3): Vector3
	return v3(
		position.X,
		(position.Y - MonsterPose.FeetY) * MonsterPose.HeightScale + MonsterPose.FeetY,
		position.Z
	)
end
local function rest(x: number, y: number, z: number): CFrame
	return cf(MonsterPose.ScalePosition(v3(x, y, z)))
end
local cloth = Color3.fromRGB(54, 43, 30)
local head = Color3.fromRGB(101, 76, 45)
local eye = Color3.fromRGB(235, 138, 49)
local definitions = {
	{
		Name = "Coat",
		Size = v3(4, 7, 2),
		Color = Color3.fromRGB(35, 32, 28),
		Material = Enum.Material.Fabric,
	},
	{ Name = "LeftArm", Size = v3(4, 1.4, 1.4), Color = cloth, Material = Enum.Material.Plastic },
	{ Name = "RightArm", Size = v3(4, 1.4, 1.4), Color = cloth, Material = Enum.Material.Plastic },
	{
		Name = "LeftLeg",
		Size = v3(1.1, 3, 1.1),
		Color = Color3.fromRGB(32, 29, 25),
		Material = Enum.Material.Plastic,
	},
	{
		Name = "RightLeg",
		Size = v3(1.1, 3, 1.1),
		Color = Color3.fromRGB(32, 29, 25),
		Material = Enum.Material.Plastic,
	},
	{ Name = "Head", Size = v3(2.5, 2.5, 2.5), Color = head, Material = Enum.Material.Plastic },
	{
		Name = "Hat",
		Size = v3(5, 0.6, 4),
		Color = Color3.fromRGB(24, 23, 21),
		Material = Enum.Material.Plastic,
	},
	{ Name = "LeftEye", Size = v3(0.3, 0.3, 0.1), Color = eye, Material = Enum.Material.Neon },
	{ Name = "RightEye", Size = v3(0.3, 0.3, 0.1), Color = eye, Material = Enum.Material.Neon },
}
for _, definition in definitions do
	definition.Size =
		v3(definition.Size.X, definition.Size.Y * MonsterPose.HeightScale, definition.Size.Z)
	table.freeze(definition)
end
MonsterPose.Parts = table.freeze(definitions)
MonsterPose.Rest = table.freeze({
	Coat = rest(0, 1.5, 0),
	LeftArm = rest(-3.5, 3, 0),
	RightArm = rest(3.5, 3, 0),
	LeftLeg = rest(-1, -1.5, 0),
	RightLeg = rest(1, -1.5, 0),
	Head = rest(0, 6, 0),
	Hat = rest(0, 7.5, 0),
	LeftEye = rest(-0.55, 6.2, -1.3),
	RightEye = rest(0.55, 6.2, -1.3),
})

local function around(pivot: Vector3, x: number, y: number, z: number): CFrame
	pivot = MonsterPose.ScalePosition(pivot)
	return cf(pivot) * CFrame.Angles(x, y, z) * cf(-pivot)
end

function MonsterPose.Get(state: string, time: number, moving: boolean): { [string]: CFrame }
	if time ~= time or math.abs(time) == math.huge then
		return MonsterPose.Rest
	end
	if state ~= "patrol" and state ~= "chase" and state ~= "trapped" and state ~= "capturing" then
		return MonsterPose.Rest
	end
	local pose = table.clone(MonsterPose.Rest)
	local step, reach, shoulder, headYaw, headPitch, roll = 0, 0, 0, 0, 0, 0
	if state == "patrol" then
		step = if moving then math.sin(time * 3.2) * math.rad(18) else 0
		shoulder = math.rad(24)
		headYaw = math.sin(time * 0.85) * math.rad(16)
	elseif state == "chase" then
		step = if moving then math.sin(time * 5.5) * math.rad(28) else 0
		reach, shoulder = math.rad(66), math.rad(8)
		headPitch = math.rad(-6)
		headYaw = math.sin(time * 2.5) * math.rad(3)
	elseif state == "trapped" then
		step = math.sin(time * 6) * math.rad(5)
		reach = math.rad(28) + math.sin(time * 4.5) * math.rad(10)
		shoulder = math.rad(20) + math.sin(time * 7) * math.rad(8)
		headYaw, roll = math.sin(time * 5) * math.rad(12), math.sin(time * 6) * math.rad(3)
	else
		local progress = math.clamp(time / 0.3, 0, 1)
		local eased = progress * progress * (3 - 2 * progress)
		reach = math.rad(78) * eased
		shoulder, headPitch = math.rad(5) * eased, math.rad(-9) * eased
	end
	pose.Coat = around(v3(0, 0, 0), 0, 0, roll) * MonsterPose.Rest.Coat
	for _, side in { -1, 1 } do
		local armName = if side < 0 then "LeftArm" else "RightArm"
		local legName = if side < 0 then "LeftLeg" else "RightLeg"
		pose[armName] = around(
			v3(side * 1.5, 3, 0),
			step * side * 0.3,
			reach * side,
			-shoulder * side
		) * MonsterPose.Rest[armName]
		pose[legName] = around(v3(side, 0, 0), step * side, 0, 0) * MonsterPose.Rest[legName]
	end
	local headTransform = around(v3(0, 4.75, 0), headPitch, headYaw, roll)
	for _, name in { "Head", "Hat", "LeftEye", "RightEye" } do
		pose[name] = headTransform * MonsterPose.Rest[name]
	end
	return pose
end

-- The Blender sections are authored in Y-up asset space with feet at Y=0
-- and their front along +Z. These are deformation deltas around the exact
-- neutral export pivots; the authoritative Root and legacy rig stay unchanged.
MonsterPose.WardenPivots = table.freeze({
	Coat = v3(0, 3.7, 0),
	LeftArm = v3(-0.9, 6.38, 0),
	RightArm = v3(0.9, 6.38, 0),
	LeftLeg = v3(-0.37, 3.75, 0),
	RightLeg = v3(0.37, 3.75, 0),
	Head = v3(0, 6.85, 0),
})
local wardenRest = {}
for _, definition in MonsterPose.Parts do
	wardenRest[definition.Name] = cf()
end
MonsterPose.WardenRest = table.freeze(wardenRest)
MonsterPose.WardenScale = 1.3
MonsterPose.WardenAssetFrame = CFrame.Angles(0, math.pi, 0) * cf(0, -3, 0)
function MonsterPose.ScaleWardenFrame(frame: CFrame): CFrame
	-- Scale the posed asset uniformly after evaluating its raw anatomical pivots.
	-- Eyes are about 10 studs above the floor, above the 8-stud corn canopy.
	return cf(frame.Position * MonsterPose.WardenScale) * frame.Rotation
end

function MonsterPose.GetWarden(state: string, time: number, moving: boolean): { [string]: CFrame }
	if time ~= time or math.abs(time) == math.huge then
		return MonsterPose.WardenRest
	end
	if state ~= "patrol" and state ~= "chase" and state ~= "trapped" and state ~= "capturing" then
		return MonsterPose.WardenRest
	end
	local pose = table.clone(MonsterPose.WardenRest)
	local step, reach, spread, sway = 0, 0, 0.07, 0
	if state == "patrol" then
		step = if moving then math.sin(time * 4.7) * 0.24 else 0
		sway = math.sin(time * 1.4) * 0.018
	elseif state == "chase" then
		step = if moving then math.sin(time * 6.85) * 0.4 else 0
		reach, spread = -0.24, 0.21
		sway = math.sin(time * 2.1) * 0.024
	elseif state == "trapped" then
		step = math.sin(time * 7) * 0.1
		reach = -0.2 + math.sin(time * 5) * 0.08
		spread = 0.14 + math.sin(time * 8) * 0.045
		sway = math.sin(time * 6) * 0.035
	else
		local progress = math.clamp(time / 0.3, 0, 1)
		reach = -0.9 * progress * progress * (3 - 2 * progress)
		spread = 0.07
	end
	local function joint(name: string, x: number, y: number, z: number): CFrame
		local pivot = MonsterPose.WardenPivots[name]
		return cf(pivot) * CFrame.Angles(x, y, z) * cf(-pivot)
	end
	pose.Coat = joint("Coat", 0, 0, sway)
	for _, side in { -1, 1 } do
		local arm = if side < 0 then "LeftArm" else "RightArm"
		local leg = if side < 0 then "LeftLeg" else "RightLeg"
		pose[arm] = joint(arm, reach - step * side * 0.55, 0, spread * side)
		pose[leg] = joint(leg, step * side, 0, 0)
	end
	local headDelta = joint("Head", 0, 0.07 + math.sin(time * 1.8) * 0.035, sway)
	for _, name in { "Head", "Hat", "LeftEye", "RightEye" } do
		pose[name] = headDelta
	end
	return pose
end

return table.freeze(MonsterPose)
