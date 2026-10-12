-- Read-only live Client sampler. Run after regular GameClient Bootstrap starts.
-- Root motion is reported separately; this script writes no Instances/properties.
assert(game:GetService("RunService"):IsClient(), "Run this sampler in Client")
local player = assert(game:GetService("Players").LocalPlayer)
local gameClient =
	assert(player.PlayerScripts:FindFirstChild("GameClient"), "Regular GameClient missing")
local bootstrap = assert(gameClient:FindFirstChild("Bootstrap"), "Regular Bootstrap missing")
assert(bootstrap:IsA("LocalScript") and bootstrap.Enabled, "Regular Bootstrap is disabled")
local Pose = require(game.ReplicatedStorage.GameShared.Game.MonsterPose)
local map = assert(workspace:FindFirstChild("CornMap"))
assert(map:GetAttribute("corn_project_id") == "children_of_corn", "Wrong map")
local runtime = assert(map:FindFirstChild("CornRoundRuntime"))
assert(runtime:GetAttribute("corn_project_id") == "children_of_corn", "Wrong runtime")
local model = assert(runtime:FindFirstChild("Monster"))
assert(
	model:GetAttribute("CornMonsterOwned") == true and model:GetAttribute("MonsterRigVersion") == 1,
	"Unknown rig"
)
local root = assert(model:FindFirstChild("Root"))
local parts = {}
for _, definition in Pose.Parts do
	local part = assert(model:FindFirstChild(definition.Name), "Missing " .. definition.Name)
	assert(
		part:IsA("BasePart")
			and part.Anchored
			and not part.CanCollide
			and not part.CanTouch
			and not part.CanQuery,
		"Unsafe visual"
	)
	parts[definition.Name] = part
end
local function differs(a, b, epsilon)
	local av, bv = { a:GetComponents() }, { b:GetComponents() }
	for index, value in av do
		if math.abs(value - bv[index]) > epsilon then
			return true
		end
	end
	return false
end
local firstRoot, previousRoot = root.CFrame, root.CFrame
local previous, changed, relativeMaximum = {}, {}, 0
for name, part in parts do
	previous[name] = firstRoot:ToObjectSpace(part.CFrame)
end
local began, samples, rootSamples, groupError, initialState =
	os.clock(), 0, 0, 0, model:GetAttribute("HuntState")
while os.clock() - began < 1.1 and model.Parent == runtime do
	task.wait(1 / 60)
	local frame = root.CFrame
	if differs(frame, previousRoot, 0.0001) then
		rootSamples += 1
	end
	previousRoot = frame
	for name, part in parts do
		local relative = frame:ToObjectSpace(part.CFrame)
		if differs(relative, previous[name], 0.0001) then
			changed[name] = true
		end
		previous[name] = relative
		for _, value in { relative:GetComponents() } do
			assert(value == value and math.abs(value) <= 13, "Nonfinite/unbounded relative pose")
			relativeMaximum = math.max(relativeMaximum, math.abs(value))
		end
	end
	for _, name in { "Hat", "LeftEye", "RightEye" } do
		local actual = parts.Head.CFrame:ToObjectSpace(parts[name].CFrame)
		local expected = Pose.Rest.Head:ToObjectSpace(Pose.Rest[name])
		if differs(actual, expected, 0.002) then
			groupError += 1
		end
	end
	samples += 1
end
assert(groupError == 0, "Head/Hat/Eyes separated during live pose")
local changedNames = {}
for name in changed do
	table.insert(changedNames, name)
end
table.sort(changedNames)
local active = initialState == "patrol"
	or initialState == "chase"
	or initialState == "trapped"
	or initialState == "capturing"
if active and model.Parent == runtime then
	assert(#changedNames > 0, "Active regular LocalScript produced no relative animation")
end
local result = {
	regular_bootstrap = true,
	initial_state = initialState,
	final_state = model:GetAttribute("HuntState"),
	active_animation_exercised = active,
	elapsed = os.clock() - began,
	samples = samples,
	visual_parts = #Pose.Parts,
	changed_relative_parts = changedNames,
	root_motion_samples = rootSamples,
	root_total_distance = (root.Position - firstRoot.Position).Magnitude,
	maximum_relative_component = relativeMaximum,
	head_group_errors = groupError,
	read_only = true,
}
print("PASS live NPC animation sampler", game:GetService("HttpService"):JSONEncode(result))
return result
