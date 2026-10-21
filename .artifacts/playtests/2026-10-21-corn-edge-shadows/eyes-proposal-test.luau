-- Production visual adapter on real Lune Instances/CFrames, neutral asset metadata.
-- No EditableMesh rendering, network, brightness perception or FPS acceptance.
local adapter = require("../../../tests/scene-adapter")
local fs, r, I = adapter.fs, adapter.r, adapter.I
local serde = require("@lune/serde")
local CF, V3 = r.CFrame, r.Vector3
local function load(path, extra)
	local fn = assert(loadstring(fs.readFile(path)))
	local env = {
		CFrame = CF,
		Vector3 = V3,
		Color3 = r.Color3,
		ColorSequence = r.ColorSequence,
		NumberSequence = r.NumberSequence,
		NumberSequenceKeypoint = r.NumberSequenceKeypoint,
		Enum = r.Enum,
		Instance = I,
	}
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
local Visual = load(".artifacts/playtests/2026-10-21-corn-edge-shadows/eyes-proposed-HarvestWardenVisual.luau", {
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
local checks = 0
local function check(value, message)
 assert(value, message)
 checks += 1
end
for _, variant in {"detailed", "classic"} do
 local source = template(variant)
 local root = I.new("Part")
 root.CFrame, root.Size = CF.new(20,9,-10), V3.new(3,6,2)
 local rootFrame, rootSize = root.CFrame, root.Size
 local visual = Visual.new(source, root)
 local detailed = variant == "detailed"
 check(visual:Valid(), "Proposed visual invalid")
 check(#visual.lights == (if detailed then 0 else 2), "B eye light survived / classic changed")
 local hidden = 0
 for _, entry in visual.parts do
  local original = assert(source:FindFirstChild(entry.part.Name))
  check(original.Transparency == 0, "Immutable geometry template mutated")
  if detailed and (entry.section == "LeftEye" or entry.section == "RightEye") and entry.part.Material == r.Enum.Material.Neon then
   hidden += 1
   check(entry.transparency == 1 and entry.part.Transparency == 1, "Red emitter visible")
  end
 end
 check(hidden == (if detailed then 2 else 0), "Wrong red eye surface count")
 for _, state in {"chase", "capturing", "idle", "search"} do
  for sample = 0, 20 do
   local frame = CF.new(20+sample/10,9,-10)*CF.Angles(0,sample/100,0)
   local pose = Pose.GetWarden(state,sample/30,true)
   check(visual:Step(frame, pose, true) == #visual.parts, "Step rejected")
   for _, entry in visual.parts do
    local part = entry.part
    local redEmitter = detailed and (entry.section == "LeftEye" or entry.section == "RightEye") and part.Material == r.Enum.Material.Neon
    check(part.Transparency == (if redEmitter then 1 else 0), "Visible emissive surface or hidden face")
    close(part.CFrame, frame*Pose.WardenAssetFrame*Pose.ScaleWardenFrame(pose[entry.section]*entry.offset))
   end
  end
 end
 for _, node in visual.model:GetDescendants() do
  if detailed then check(not node:IsA("PointLight") and not node:IsA("SpotLight"), "Detailed eye light generated") end
 end
 visual:Step(root.CFrame,Pose.WardenRest,false)
 for _, entry in visual.parts do check(entry.part.Transparency == 1, "Hidden phase visible") end
 check(root.CFrame == rootFrame and root.Size == rootSize, "Authoritative Root changed")
 local edited = visual.parts[1].part
 local old = edited.CanQuery
 edited.CanQuery = true
 check(not visual:Valid(), "Foreign property edit accepted")
 edited.CanQuery = old
 check(visual:Valid(), "Guard did not recover")
 local foreign = I.new("Folder")
 foreign.Name, foreign.Parent = "ManualDecoration", visual.model
 visual:Destroy()
 check(foreign.Parent == root, "Foreign author decoration deleted")
 check(not root:FindFirstChild("HarvestWardenVisual"), "Cleanup leaked presentation")
end
print("PASS: "..checks.." assertions; exact saved-B presentation proposal, Detailed red emitters hidden in all animation/capture poses, no Detailed light instances, dark sockets/face geometry and old B Classic path preserved, template/Root/guard/cleanup behavior retained")
