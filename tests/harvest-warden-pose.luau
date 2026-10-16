-- Actual production pose module and exact Blender neutral pivots.
-- Geometry-only adapter: does not assert Roblox rendering, lights or FPS.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local r = require("@lune/roblox")
local fn = assert(loadstring(fs.readFile("src/shared/Game/MonsterPose.luau")))
setfenv(
	fn,
	setmetatable({
		CFrame = r.CFrame,
		Vector3 = r.Vector3,
		Color3 = r.Color3,
		Enum = r.Enum,
	}, { __index = getfenv() })
)
local Pose = fn()
local function close(a, b, reason)
	for index, value in { a:GetComponents() } do
		assert(math.abs(value - ({ b:GetComponents() })[index]) < 0.00001, reason)
	end
end
for _, variant in { "classic", "detailed" } do
	local data = serde.decode(
		"json",
		fs.readFile("assets/harvest-warden/exports/warden/" .. variant .. "/mesh-data.json")
	)
	for name, pivot in Pose.WardenPivots do
		local expected = data.sections[name].pivot
		assert(
			(pivot - r.Vector3.new(unpack(expected))).Magnitude < 0.000001,
			"Production joint differs from Blender neutral pivot: " .. name
		)
	end
end
assert(table.isfrozen(Pose.WardenRest) and table.isfrozen(Pose.WardenPivots))
assert(Pose.GetWarden("dormant", 0, false) == Pose.WardenRest)
assert(Pose.GetWarden("stopped", 1, true) == Pose.WardenRest)
assert(Pose.GetWarden("foreign", 0, true) == Pose.WardenRest)
assert(Pose.GetWarden("chase", math.huge, true) == Pose.WardenRest)
assert(Pose.GetWarden("chase", 0 / 0, true) == Pose.WardenRest)
local asset = Pose.WardenAssetFrame
assert(Pose.WardenScale == 1.3)
local eye = asset * Pose.ScaleWardenFrame(r.CFrame.new(0, 7.7, 0.42))
assert(math.abs(eye.Position.Y + 3 - 10.01) < 0.00001, "Scaled eyes do not clear 8-stud corn")
local rotated = r.CFrame.new(1, 2, 3) * r.CFrame.Angles(0.2, 0.3, 0.4)
local scaled = Pose.ScaleWardenFrame(rotated)
assert((scaled.Position - rotated.Position * 1.3).Magnitude < 0.00001)
close(scaled.Rotation, rotated.Rotation, "Uniform scaling changed rotation")
assert((asset:PointToWorldSpace(r.Vector3.zero) - r.Vector3.new(0, -3, 0)).Magnitude < 0.000001)
assert(asset:VectorToWorldSpace(r.Vector3.zAxis).Z < -0.99999, "Asset faces away from Root front")
for _, state in { "patrol", "chase", "trapped", "capturing" } do
	for _, moving in { true, false } do
		for sample = 0, 150 do
			local pose = Pose.GetWarden(state, sample / 30, moving)
			local count = 0
			for name, delta in pose do
				assert(Pose.WardenRest[name], "Unexpected bone")
				count += 1
				for _, value in { delta:GetComponents() } do
					assert(value == value and math.abs(value) < 15, "Unbounded visual delta")
				end
				local pivot = Pose.WardenPivots[name]
				if pivot then
					assert(
						(delta:PointToWorldSpace(pivot) - pivot).Magnitude < 0.00001,
						"Animation moved an anatomical joint"
					)
				end
			end
			assert(count == 9)
			for _, name in { "Hat", "LeftEye", "RightEye" } do
				close(pose.Head, pose[name], "Head group separated")
			end
			if not moving and (state == "patrol" or state == "chase") then
				close(pose.LeftLeg, r.CFrame.new(), "Stationary left leg walked")
				close(pose.RightLeg, r.CFrame.new(), "Stationary right leg walked")
			end
		end
	end
end
local moving = Pose.GetWarden("chase", 0.15, true)
assert(moving.LeftLeg.LookVector.Y * moving.RightLeg.LookVector.Y < 0, "Walking legs not opposed")
local capture = Pose.GetWarden("capturing", 1, false)
local hand = r.Vector3.new(-1.4, 2.0, 0)
assert(
	capture.LeftArm:PointToWorldSpace(hand).Z > hand.Z + 1,
	"Capture arm did not reach asset front"
)
print(
	"PASS: Warden exact offline pivots, finite nine-section deltas, opposite gait, stationary legs, grouped head/hat/eyes, capture reach and Root-relative feet/front; legacy pose API retained"
)
