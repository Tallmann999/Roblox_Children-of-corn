-- Read-only actual Client sampler after regular Bootstrap. This does not move
-- actors, write hunt state, trigger captures, or claim human fear/FPS acceptance.
local run = game:GetService("RunService")
assert(run:IsStudio() and run:IsRunning() and run:IsClient(), "Studio Play Client required")
local player = assert(game:GetService("Players").LocalPlayer)
local bootstrap = assert(player.PlayerScripts.GameClient:FindFirstChild("Bootstrap"))
assert(bootstrap:IsA("LocalScript") and bootstrap.Enabled, "Regular Bootstrap required")
local map = assert(workspace:FindFirstChild("CornMap"))
assert(map:GetAttribute("corn_project_id") == "children_of_corn", "Wrong game")
local variant = map:GetAttribute("HarvestArtVariant")
assert(variant == "A" or variant == "B", "Harvest art variant required")
local runtime = assert(map:FindFirstChild("CornRoundRuntime"))
local Pose = require(game.ReplicatedStorage.GameShared.Game.MonsterPose)
assert(Pose.WardenScale == 1.3, "Warden uniform art scale missing")
local models, deadline = {}, os.clock() + 20
for index = 1, 3 do
	local name = if index == 1 then "Monster" else "Monster" .. index
	local model = runtime:FindFirstChild(name)
	if model then
		assert(
			model:GetAttribute("CornMonsterOwned") == true
				and model:GetAttribute("MonsterIndex") == index
		)
		assert(
			model:GetAttribute("MonsterRigVersion") == 1
				and model:GetAttribute("HarvestWardenVersion") == 1
		)
		local root = assert(model:FindFirstChild("Root"))
		assert(root.Size == Vector3.new(3, 6, 2) and model.PrimaryPart == root)
		assert(root.Anchored and not root.CanCollide and not root.CanTouch and not root.CanQuery)
		assert(#model:GetChildren() == 10, "Compatibility topology changed")
		local visual = root:FindFirstChild("HarvestWardenVisual")
		while not visual and os.clock() < deadline and model.Parent == runtime do
			task.wait(0.05)
			visual = root:FindFirstChild("HarvestWardenVisual")
		end
		assert(
			visual and visual:GetAttribute("HarvestGeometryOwner") == "harvest_warden_v1",
			"Peer-local Warden missing"
		)
		local parts, lights, sections = {}, {}, {}
		local trackedPart = nil
		local minEyeHeight, maxEyeHeight = math.huge, -math.huge
		for _, item in visual:GetDescendants() do
			assert(not item:IsA("LuaSourceContainer"))
			if item:IsA("BasePart") then
				assert(
					item:IsA("MeshPart")
						and item.Anchored
						and not item.CanCollide
						and not item.CanTouch
						and not item.CanQuery
				)
				assert(item:GetAttribute("HarvestGeometryOwner") == "harvest_warden_v1")
				local section, offset =
					item:GetAttribute("HarvestSection"), item:GetAttribute("HarvestOffset")
				assert(Pose.WardenRest[section] and typeof(offset) == "CFrame")
				assert(
					item.MeshContent.SourceType == Enum.ContentSourceType.Object,
					"Local mesh geometry not reconstructed"
				)
				sections[section] = true
				if section == "Head" then
					trackedPart = item
				end
				table.insert(parts, { part = item, section = section, offset = offset })
			elseif item:IsA("PointLight") then
				assert(
					item.Name == "HarvestEyeLight"
						and item.Range == 24
						and item.Brightness == 3
						and not item.Shadows
				)
				assert(
					item.Parent.Material == Enum.Material.Neon
						and item.Color == Color3.fromRGB(255, 16, 14)
				)
				table.insert(lights, item)
				local height = root.CFrame:PointToObjectSpace(item.Parent.Position).Y + 3
				assert(height > 9.4 and height < 10.8, "Red eyes do not clear corn canopy")
				minEyeHeight = math.min(minEyeHeight, height)
				maxEyeHeight = math.max(maxEyeHeight, height)
			end
		end
		for _, definition in Pose.Parts do
			assert(sections[definition.Name], "Missing anatomy section")
			local carrier = assert(model:FindFirstChild(definition.Name))
			assert(carrier.Size == definition.Size and carrier.Transparency == 1)
		end
		assert(#parts > 9 and #parts <= 64 and #lights == 2, "Warden part/light budget wrong")
		table.insert(models, {
			model = model,
			root = root,
			visual = visual,
			parts = parts,
			trackedPart = assert(trackedPart),
			minEyeHeight = minEyeHeight,
			maxEyeHeight = maxEyeHeight,
			lights = lights,
			index = index,
		})
	end
end
assert(#models >= 1, "Start a normal round before observing")
local began, samples, changed, previous = os.clock(), 0, {}, {}
for _, actor in models do
	previous[actor.index] = actor.root.CFrame:ToObjectSpace(actor.trackedPart.CFrame)
end
while os.clock() - began < 1.25 do
	task.wait(1 / 60)
	for _, actor in models do
		assert(
			actor.model.Parent == runtime and actor.visual.Parent == actor.root,
			"Round ended during observer"
		)
		local relative = actor.root.CFrame:ToObjectSpace(actor.trackedPart.CFrame)
		local a, b = { relative:GetComponents() }, { previous[actor.index]:GetComponents() }
		for index, value in a do
			assert(value == value and math.abs(value) < 50, "Nonfinite/bad relative visual frame")
			if math.abs(value - b[index]) > 0.0001 then
				changed[actor.index] = true
			end
		end
		previous[actor.index] = relative
	end
	samples += 1
end
local actors = {}
for _, actor in models do
	local state = actor.model:GetAttribute("HuntState")
	local active = state == "patrol"
		or state == "chase"
		or state == "trapped"
		or state == "capturing"
	if active then
		assert(changed[actor.index], "Regular animation produced no relative visual movement")
	end
	local enabled = 0
	for _, light in actor.lights do
		if light.Enabled then
			enabled += 1
		end
	end
	table.insert(actors, {
		index = actor.index,
		state = state,
		parts = #actor.parts,
		lights = #actor.lights,
		enabledLights = enabled,
		animated = changed[actor.index] == true,
		minEyeHeight = actor.minEyeHeight,
		maxEyeHeight = actor.maxEyeHeight,
	})
end
local result = {
	variant = variant,
	actors = actors,
	elapsed = os.clock() - began,
	samples = samples,
	read_only = true,
	regular_bootstrap = true,
	method = "Actual peer-local mesh content, carried legacy rig bounds, anatomy/Neon/light budgets and real relative animation. No visual/fear/long FPS claim.",
}
print("PASS Harvest Warden client observer", game:GetService("HttpService"):JSONEncode(result))
return result
