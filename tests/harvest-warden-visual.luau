-- Production visual adapter on real Lune Instances/CFrames, neutral asset metadata.
-- No EditableMesh rendering, network, brightness perception or FPS acceptance.
local adapter = require("./scene-adapter")
local fs, r, I = adapter.fs, adapter.r, adapter.I
local serde = require("@lune/serde")
local CF, V3 = r.CFrame, r.Vector3
local function load(path, extra)
	local fn = assert(loadstring(fs.readFile(path)))
	local env = { CFrame = CF, Vector3 = V3, Color3 = r.Color3, Enum = r.Enum, Instance = I }
	for name, value in extra or {} do
		env[name] = value
	end
	setfenv(fn, setmetatable(env, { __index = getfenv() }))
	return fn()
end
local Pose = load("src/shared/Game/MonsterPose.luau")
local module = I.new("ModuleScript")
module.Name = "MonsterPose"
local folder = I.new("Folder")
module.Parent = folder
local Visual = load("src/shared/Game/HarvestWardenVisual.luau", {
	script = { Parent = folder },
	require = function(item)
		assert(item == module)
		return Pose
	end,
})
local function close(a, b)
	for index, value in { a:GetComponents() } do
		assert(
			math.abs(value - ({ b:GetComponents() })[index]) < 0.00001,
			"Visual section detached"
		)
	end
end
local function template(variant)
	local source = serde.decode(
		"json",
		fs.readFile("assets/harvest-warden/exports/warden/" .. variant .. "/mesh-data.json")
	)
	local model = I.new("Model")
	model.Name = "WardenTemplate"
	for name, data in source.sections do
		local materials = {}
		for _, material in data.triangle_materials do
			materials[material] = true
		end
		for material in materials do
			local low, high =
				V3.new(math.huge, math.huge, math.huge), V3.new(-math.huge, -math.huge, -math.huge)
			for index, triangle in data.triangles do
				if data.triangle_materials[index] == material then
					for _, vertex in triangle do
						local xyz = data.vertices[vertex + 1]
						local v = V3.new(unpack(xyz))
						low =
							V3.new(math.min(v.X, low.X), math.min(v.Y, low.Y), math.min(v.Z, low.Z))
						high = V3.new(
							math.max(v.X, high.X),
							math.max(v.Y, high.Y),
							math.max(v.Z, high.Z)
						)
					end
				end
			end
			local part = I.new("MeshPart")
			part.Name = name .. material
			part:SetAttribute("HarvestGeometryOwner", "harvest_warden_v1")
			part:SetAttribute("corn_project_id", "children_of_corn")
			part:SetAttribute(
				"HarvestAssetKey",
				if variant == "classic" then "WardenClassic" else "WardenDetailed"
			)
			part:SetAttribute("HarvestSection", name)
			part:SetAttribute("HarvestOffset", CF.new((low + high) / 2))
			part.CFrame, part.Size = CF.new((low + high) / 2), high - low
			part.Material = if material == 4 then r.Enum.Material.Neon else r.Enum.Material.Fabric
			part.Color = if material == 4
				then r.Color3.fromRGB(255, 16, 14)
				else r.Color3.fromRGB(80, 60, 40)
			part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
			part.Transparency, part.LocalTransparencyModifier = 0, 0
			part.Parent = model
		end
	end
	return model
end
for _, variant in { "classic", "detailed" } do
	local source = template(variant)
	local root = I.new("Part")
	root.Name = "Root"
	root.Size = V3.new(3, 6, 2)
	root.CFrame = CF.new(20, 9, -10) * CF.Angles(0, 0.45, 0)
	local rootFrame, rootSize = root.CFrame, root.Size
	local visual = Visual.new(source, root)
	assert(visual:Valid() and #visual.parts > 9 and #visual.parts <= 64)
	for _, entry in visual.parts do
		local original = assert(source:FindFirstChild(entry.part.Name))
		assert(
			(entry.part.Size - original.Size * 1.3).Magnitude < 0.0002,
			"Warden section did not receive uniform size scale: "
				.. entry.part.Name
				.. " actual="
				.. tostring(entry.part.Size)
				.. " source="
				.. tostring(original.Size)
		)
		assert(original.CFrame == entry.offset, "Template offset was mutated")
	end
	assert(#visual.lights == 2)
	local carriers = {}
	for _, definition in Pose.Parts do
		local carrier = I.new("Part")
		carrier.LocalTransparencyModifier = 0
		carriers[definition.Name] = carrier
	end
	local frame = root.CFrame
	assert(visual:Step(frame, Pose.WardenRest, false, carriers) == #visual.parts)
	for _, entry in visual.parts do
		assert(entry.part.Transparency == 1)
		close(
			entry.part.CFrame,
			frame * Pose.WardenAssetFrame * Pose.ScaleWardenFrame(entry.offset)
		)
	end
	for _, entry in visual.lights do
		assert(not entry.light.Enabled)
	end
	for sample = 0, 120 do
		frame = CF.new(20 + sample / 10, 9, -10) * CF.Angles(0, 0.45 + sample / 100, 0)
		local pose = Pose.GetWarden("chase", sample / 30, true)
		visual:Step(frame, pose, true, carriers)
		for _, entry in visual.parts do
			close(
				entry.part.CFrame,
				frame
					* Pose.WardenAssetFrame
					* Pose.ScaleWardenFrame(pose[entry.section] * entry.offset)
			)
			assert(entry.part.Transparency == 0 and entry.part.LocalTransparencyModifier == 0)
		end
	end
	for _, entry in visual.lights do
		local light = entry.light
		assert(light.Enabled and light.Range == 24 and light.Brightness == 3 and not light.Shadows)
	end
	-- Capture hides the existing nine carriers; decorative art follows that local mask.
	for _, carrier in carriers do
		carrier.LocalTransparencyModifier = 1
	end
	visual:Step(frame, Pose.GetWarden("capturing", 0.2, false), true, carriers)
	for _, entry in visual.parts do
		assert(entry.part.LocalTransparencyModifier == 1)
	end
	for _, entry in visual.lights do
		assert(not entry.light.Enabled)
	end
	for _, carrier in carriers do
		carrier.LocalTransparencyModifier = 0.25
	end
	visual:Step(frame, Pose.WardenRest, true, carriers)
	for _, entry in visual.parts do
		assert(entry.part.LocalTransparencyModifier == 0.25)
	end
	assert(root.CFrame == rootFrame and root.Size == rootSize, "Art wrote authoritative Root")
	local edited = visual.parts[1].part
	edited.CanQuery = true
	assert(not visual:Valid() and visual:Step(frame, Pose.WardenRest, true) == 0)
	edited.CanQuery = false
	assert(visual:Valid())
	local foreign = I.new("Folder")
	foreign.Name = "ManualDecoration"
	foreign.Parent = visual.model
	visual:Destroy()
	assert(
		foreign.Parent == root and not root:FindFirstChild("HarvestWardenVisual"),
		"Foreign insertion lost"
	)
	local bad = source:Clone()
	bad:GetChildren()[1]:SetAttribute("HarvestSection", "Unknown")
	assert(not pcall(Visual.new, bad, root), "Unknown bone accepted")
	assert(not root:FindFirstChild("HarvestWardenVisual"), "Failed build leaked visual")
	local scriptNode = I.new("Script")
	scriptNode.Parent = source
	assert(not pcall(Visual.new, source, root), "Source accepted in art")
end
print(
	"PASS: both actual neutral Warden material groups, Root-relative anatomy/feet/turns, bounded decorative nonquery geometry, dormant visibility, two bounded red Neon lights, capture LTM masking, unchanged Root, foreign/bone/code guards and cleanup"
)
