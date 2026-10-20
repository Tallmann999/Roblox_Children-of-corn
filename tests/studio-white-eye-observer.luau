-- Read-only normal-bootstrap Client observer. Does not move actors, write
-- Lighting, invoke remotes, or claim perceived visibility, fear or long FPS.
local run = game:GetService("RunService")
local http = game:GetService("HttpService")
local lighting = game:GetService("Lighting")
local function check(condition, label, facts)
	assert(condition, label .. (if facts then ": " .. http:JSONEncode(facts) else ""))
end
check(run:IsStudio() and run:IsRunning() and run:IsClient(), "Studio Play Client required")
local player = assert(game:GetService("Players").LocalPlayer)
local bootstrap = player.PlayerScripts.GameClient:FindFirstChild("Bootstrap")
check(bootstrap and bootstrap:IsA("LocalScript") and bootstrap.Enabled, "Normal Bootstrap required")
local map = assert(workspace:FindFirstChild("CornMap"))
check(map:GetAttribute("corn_project_id") == "children_of_corn", "Wrong project")
check(map:GetAttribute("HarvestArtVariant") == "A", "Variant A required")
local runtime = assert(map:FindFirstChild("CornRoundRuntime"), "Start a normal round first")
local white = Color3.new(1, 1, 1)
local activeStates = { patrol = true, chase = true, trapped = true, capturing = true }
local models = {}
for index = 1, 3 do
	local name = if index == 1 then "Monster" else "Monster" .. index
	local model = assert(runtime:FindFirstChild(name), "Gate must produce all three NPCs: " .. name)
	check(
		model:GetAttribute("CornMonsterOwned") == true
			and model:GetAttribute("MonsterIndex") == index
			and model:GetAttribute("MonsterRigVersion") == 1
			and model:GetAttribute("HarvestWardenVersion") == 1
			and model:GetAttribute("HarvestArtVariant") == "A",
		"Unexpected Warden ownership/version",
		{ actor = index }
	)
	local root = assert(model:FindFirstChild("Root"), "NPC Root missing")
	check(
		root.Size == Vector3.new(3, 6, 2)
			and model.PrimaryPart == root
			and #model:GetChildren() == 10
			and root.Anchored
			and not root.CanCollide
			and not root.CanTouch
			and not root.CanQuery,
		"Authoritative rig topology/physics changed",
		{ actor = index, children = #model:GetChildren(), size = tostring(root.Size) }
	)
	local visual =
		assert(root:FindFirstChild("HarvestWardenVisual"), "Wait for peer-local art: " .. name)
	local parts, eyes, spots, beams, pointLights, sections, head = {}, {}, {}, {}, 0, {}, nil
	for _, item in visual:GetDescendants() do
		check(not item:IsA("LuaSourceContainer"), "Code inside local art")
		if item:IsA("BasePart") then
			check(
				item:IsA("MeshPart")
					and item.Anchored
					and not item.CanCollide
					and not item.CanTouch
					and not item.CanQuery
					and item:GetAttribute("HarvestGeometryOwner") == "harvest_warden_v1"
					and item:GetAttribute("corn_project_id") == "children_of_corn"
					and item:GetAttribute("HarvestAssetKey") == "WardenClassic"
					and item.MeshContent.SourceType == Enum.ContentSourceType.Object,
				"Invalid local Classic mesh",
				{ actor = index, part = item.Name }
			)
			local section = item:GetAttribute("HarvestSection")
			sections[section] = true
			if section == "Head" then
				head = item
			end
			if
				(section == "LeftEye" or section == "RightEye")
				and item.Material == Enum.Material.Neon
			then
				check(
					item.Color == white,
					"Eye is not white",
					{ actor = index, section = section, color = tostring(item.Color) }
				)
				eyes[section] = item
			end
			table.insert(parts, item)
		elseif item:IsA("SpotLight") then
			check(
				item.Name == "HarvestEyeLight"
					and item.Color == white
					and item.Range == 60
					and item.Angle == 14
					and item.Brightness == 2.5
					and not item.Shadows
					and item.Parent:IsA("Attachment"),
				"Unexpected eye spotlight",
				{
					actor = index,
					range = item.Range,
					angle = item.Angle,
					brightness = item.Brightness,
				}
			)
			table.insert(spots, item)
		elseif item:IsA("PointLight") then
			pointLights += 1
		elseif item:IsA("Beam") then
			check(
				item.Name == "HarvestEyeBeam"
					and item.Texture == ""
					and item.FaceCamera
					and item.Width0 == 0.125
					and item.Width1 == 5.5
					and item.Attachment0
					and item.Attachment1
					and item.Attachment0.Parent == item.Attachment1.Parent,
				"Unexpected asset-free eye beam",
				{ actor = index, texture = item.Texture, faceCamera = item.FaceCamera }
			)
			for _, keypoint in item.Color.Keypoints do
				check(keypoint.Value == white, "Beam is not white", { actor = index })
			end
			table.insert(beams, item)
		end
	end
	local sectionCount = 0
	for _ in sections do
		sectionCount += 1
	end
	check(
		#parts == 19
			and #spots == 2
			and #beams == 2
			and pointLights == 0
			and eyes.LeftEye
			and eyes.RightEye
			and sectionCount == 9
			and head,
		"Classic part/light/anatomy budget wrong",
		{
			actor = index,
			parts = #parts,
			spots = #spots,
			beams = #beams,
			pointLights = pointLights,
			sections = sectionCount,
		}
	)
	for _, spot in spots do
		local found = false
		for _, beam in beams do
			if beam.Attachment0 == spot.Parent then
				found = true
			end
		end
		check(found, "SpotLight does not share the beam direction", { actor = index })
	end
	table.insert(models, {
		index = index,
		model = model,
		root = root,
		visual = visual,
		eyes = eyes,
		spots = spots,
		beams = beams,
		head = head,
		previous = root.CFrame:ToObjectSpace(head.CFrame),
		changed = false,
		minEyeHeight = math.huge,
		maxEyeHeight = -math.huge,
		minDot = 1,
		minDivergence = math.huge,
		maxDivergence = 0,
		minLength = math.huge,
		maxLength = 0,
		activeSamples = 0,
		maskedSamples = 0,
		enabledLightSamples = 0,
		enabledBeamSamples = 0,
	})
end
local began, samples, issue = os.clock(), 0, nil
local function sample()
	for _, actor in models do
		check(
			actor.model.Parent == runtime and actor.visual.Parent == actor.root,
			"Round/visual replaced during sample",
			{ actor = actor.index }
		)
		local state = actor.model:GetAttribute("HuntState")
		local active = activeStates[state] == true
		local masked = actor.eyes.LeftEye.LocalTransparencyModifier >= 1
			or actor.eyes.RightEye.LocalTransparencyModifier >= 1
		if active then
			actor.activeSamples += 1
		end
		if masked then
			actor.maskedSamples += 1
		end
		local relative = actor.root.CFrame:ToObjectSpace(actor.head.CFrame)
		local before, after = { actor.previous:GetComponents() }, { relative:GetComponents() }
		for component, value in after do
			check(
				value == value and math.abs(value) < 50,
				"Nonfinite relative head frame",
				{ actor = actor.index }
			)
			if math.abs(value - before[component]) > 0.0001 then
				actor.changed = true
			end
		end
		actor.previous = relative
		local directions = {}
		for _, beam in actor.beams do
			local first, last = beam.Attachment0, beam.Attachment1
			local displacement = last.WorldPosition - first.WorldPosition
			local length, direction = displacement.Magnitude, first.WorldCFrame.LookVector
			local dot = direction:Dot(actor.root.CFrame.LookVector)
			check(
				math.abs(length - 60) < 0.01 and displacement.Unit:Dot(direction) > 0.999,
				"Beam length/Attachment axis mismatch",
				{ actor = actor.index, length = length, axisDot = displacement.Unit:Dot(direction) }
			)
			check(
				dot > 0.9,
				"Eye beam points away from NPC front",
				{ actor = actor.index, forwardDot = dot }
			)
			local height = actor.root.CFrame:PointToObjectSpace(first.WorldPosition).Y + 3
			check(
				height > 9.4 and height < 10.8,
				"Eye beam below corn canopy",
				{ actor = actor.index, height = height }
			)
			actor.minEyeHeight, actor.maxEyeHeight =
				math.min(actor.minEyeHeight, height), math.max(actor.maxEyeHeight, height)
			actor.minDot = math.min(actor.minDot, dot)
			actor.minLength, actor.maxLength =
				math.min(actor.minLength, length), math.max(actor.maxLength, length)
			if beam.Enabled then
				actor.enabledBeamSamples += 1
			end
			table.insert(directions, direction)
		end
		local divergence = math.deg(math.acos(math.clamp(directions[1]:Dot(directions[2]), -1, 1)))
		check(
			divergence > 13.5 and divergence < 14.5,
			"Eye beams do not diverge by 14 degrees",
			{ actor = actor.index, divergence = divergence }
		)
		actor.minDivergence, actor.maxDivergence =
			math.min(actor.minDivergence, divergence), math.max(actor.maxDivergence, divergence)
		for _, light in actor.spots do
			if light.Enabled then
				actor.enabledLightSamples += 1
			end
		end
	end
	samples += 1
end
local connection = run.RenderStepped:Connect(function()
	if issue then
		return
	end
	local ok, problem = pcall(sample)
	if not ok then
		issue = tostring(problem)
	end
end)
while os.clock() - began < 1.3 and not issue do
	task.wait(0.02)
end
connection:Disconnect()
check(not issue, "Render sample failed", { problem = issue })
check(samples >= 2, "No rendered frames during bounded sample", { samples = samples })
local actors, animated = {}, false
for _, actor in models do
	local lights, beams = 0, 0
	for _, light in actor.spots do
		if light.Enabled then
			lights += 1
		end
	end
	for _, beam in actor.beams do
		if beam.Enabled then
			beams += 1
		end
	end
	local state = actor.model:GetAttribute("HuntState")
	local masked = actor.eyes.LeftEye.LocalTransparencyModifier >= 1
		or actor.eyes.RightEye.LocalTransparencyModifier >= 1
	if activeStates[state] and not masked then
		check(
			lights == 2 and beams == 2,
			"Active unmasked Warden eyes not enabled at tail",
			{ actor = actor.index, state = state, lights = lights, beams = beams }
		)
	end
	animated = animated or actor.changed
	table.insert(actors, {
		index = actor.index,
		state = state,
		meshParts = 19,
		spots = 2,
		beams = 2,
		pointLights = 0,
		enabledLightsTail = lights,
		enabledBeamsTail = beams,
		maskedTail = masked,
		enabledLightSamples = actor.enabledLightSamples,
		enabledBeamSamples = actor.enabledBeamSamples,
		activeSamples = actor.activeSamples,
		maskedSamples = actor.maskedSamples,
		animated = actor.changed,
		eyeHeight = { actor.minEyeHeight, actor.maxEyeHeight },
		length = { actor.minLength, actor.maxLength },
		minForwardDot = actor.minDot,
		divergence = { actor.minDivergence, actor.maxDivergence },
	})
end
local anyActive = false
for _, actor in models do
	anyActive = anyActive or actor.activeSamples > 0
end
check(not anyActive or animated, "Awake normal Bootstrap produced no relative head movement")
local skyFaces = { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp" }
local skies, atmospheres = {}, {}
for _, effect in lighting:GetChildren() do
	if effect:IsA("Sky") then
		local sameBlack = true
		for _, property in skyFaces do
			sameBlack = sameBlack and effect[property] == "rbxassetid://127362238475901"
		end
		table.insert(skies, {
			name = effect.Name,
			allFacesBlackURI = sameBlack,
			faceURI = effect.SkyboxBk,
			celestial = effect.CelestialBodiesShown,
			stars = effect.StarCount,
		})
	elseif effect:IsA("Atmosphere") then
		table.insert(atmospheres, {
			name = effect.Name,
			density = effect.Density,
			haze = effect.Haze,
			offset = effect.Offset,
		})
	end
end
local torchLights, torchesEnabled = 0, 0
for _, item in map:GetDescendants() do
	if item:IsA("Light") and not item:IsDescendantOf(runtime) then
		torchLights += 1
		if item.Enabled then
			torchesEnabled += 1
		end
	end
end
local result = {
	passed = true,
	readOnly = true,
	regularBootstrap = true,
	variant = "A",
	actorCount = #actors,
	elapsed = os.clock() - began,
	renderSamples = samples,
	anyRelativeHeadAnimation = animated,
	actors = actors,
	lighting = {
		clock = lighting.ClockTime,
		brightness = lighting.Brightness,
		ambient = tostring(lighting.Ambient),
		outdoorAmbient = tostring(lighting.OutdoorAmbient),
		diffuse = lighting.EnvironmentDiffuseScale,
		specular = lighting.EnvironmentSpecularScale,
		fogStart = lighting.FogStart,
		fogEnd = lighting.FogEnd,
		fogColor = tostring(lighting.FogColor),
		skies = skies,
		atmospheres = atmospheres,
		mapLights = torchLights,
		enabledMapLights = torchesEnabled,
	},
	method = "1.3-second RenderStepped read-only actual geometry, spot/beam axes, carrier-compatible root bounds, mask-aware enabled tail and lighting readback; no distant perception/FPS claim.",
}
print("PASS white eye client observer", http:JSONEncode(result))
return result
