--!strict
-- Peer-local art only. The server's Root, hunt and capture rules are untouched.
local Pose = require(script.Parent:WaitForChild("MonsterPose"))
local Visual = {}
Visual.__index = Visual
local OWNER, PROJECT = "harvest_warden_v1", "children_of_corn"
local MAX_PARTS = 64
local ALLOWED = { WardenClassic = true, WardenDetailed = true }
local WHITE = Color3.fromRGB(255, 255, 255)
local RED = Color3.fromRGB(255, 16, 14)
local BEAM_LENGTH = 60
local BEAM_COLOR = ColorSequence.new(WHITE)
local BEAM_TRANSPARENCY = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.8),
	NumberSequenceKeypoint.new(0.78, 0.92),
	NumberSequenceKeypoint.new(1, 1),
})

local function stamp(item: Instance)
	item:SetAttribute("HarvestGeometryOwner", OWNER)
	item:SetAttribute("corn_project_id", PROJECT)
end

local function owned(item: Instance): boolean
	return item:GetAttribute("HarvestGeometryOwner") == OWNER
		and item:GetAttribute("corn_project_id") == PROJECT
end

local function finite(frame: CFrame): boolean
	for _, component in { frame:GetComponents() } do
		if component ~= component or math.abs(component) > 100000 then
			return false
		end
	end
	return true
end

local function sameSequence(a: any, b: any): boolean
	if #a.Keypoints ~= #b.Keypoints then
		return false
	end
	for index, point in a.Keypoints do
		local expected = b.Keypoints[index]
		if point.Time ~= expected.Time or point.Value ~= expected.Value then
			return false
		end
		if typeof(a) == "NumberSequence" and point.Envelope ~= expected.Envelope then
			return false
		end
	end
	return true
end

function Visual.new(template: Model, host: Instance)
	assert(template:IsA("Model"), "Warden model template required")
	assert(not host:FindFirstChild("HarvestWardenVisual"), "Warden visual name occupied")
	local clone = template:Clone()
	clone.Name = "HarvestWardenVisual"
	stamp(clone)
	local parts, lights, sections, beams, attachments, nodes = {}, {}, {}, {}, {}, {}
	local assetKey = nil
	local function track(item: Instance)
		stamp(item)
		nodes[item] = { parent = item.Parent, name = item.Name }
	end
	local ok, problem = pcall(function()
		for _, item in clone:GetDescendants() do
			assert(not item:IsA("LuaSourceContainer"), "Code in Warden art template")
			if not item:IsA("BasePart") then
				assert(
					item:IsA("Model") or item:IsA("Folder") or item:IsA("SurfaceAppearance"),
					"Unsupported Warden art descendant"
				)
				stamp(item)
			end
			if item:IsA("BasePart") then
				local section = item:GetAttribute("HarvestSection")
				local offset = item:GetAttribute("HarvestOffset")
				local key = item:GetAttribute("HarvestAssetKey")
				assert(
					item:IsA("MeshPart")
						and owned(item)
						and type(key) == "string"
						and ALLOWED[key]
						and type(section) == "string"
						and Pose.WardenRest[section]
						and typeof(offset) == "CFrame"
						and finite(offset)
						and item.Anchored
						and not item.CanCollide
						and not item.CanTouch
						and not item.CanQuery,
					"Unknown Warden material section"
				)
				assert(#parts < MAX_PARTS, "Warden visual part budget exceeded")
				assert(not assetKey or assetKey == key, "Mixed Warden templates refused")
				assetKey = key
				item.Size *= Pose.WardenScale
				if
					(section == "LeftEye" or section == "RightEye")
					and item.Material == Enum.Material.Neon
				then
					item.Color = if key == "WardenClassic" then WHITE else RED
				end
				table.insert(parts, {
					part = item,
					parent = item.Parent,
					section = section,
					offset = offset,
					size = item.Size,
					key = key,
					color = item.Color,
					material = item.Material,
					transparency = item.Transparency,
				})
				sections[section] = true
			end
			track(item)
		end
		for _, definition in Pose.Parts do
			assert(sections[definition.Name], "Incomplete Warden section " .. definition.Name)
		end
		for _, name in { "LeftEye", "RightEye" } do
			local eye = nil
			for _, entry in parts do
				if entry.section == name and entry.part.Material == Enum.Material.Neon then
					eye = entry.part
					break
				end
			end
			assert(eye, "Warden Neon eye missing")
			local classic = assetKey == "WardenClassic"
			local light = Instance.new(if classic then "SpotLight" else "PointLight")
			light.Name = "HarvestEyeLight"
			light.Color = if classic then WHITE else RED
			light.Range, light.Brightness, light.Shadows =
				if classic then BEAM_LENGTH else 24, if classic then 2.5 else 3, false
			light.Enabled = false
			local lightParent = eye
			if classic then
				-- The asset front is +Z. Attachment -Z points forward and outward;
				-- both endpoints follow this animated eye without per-frame writes.
				local side = if name == "LeftEye" then -1 else 1
				local startFrame = CFrame.Angles(0, math.pi + side * math.rad(7), 0)
					* CFrame.Angles(-math.rad(2.5), 0, 0)
				local direction = startFrame.LookVector
				local finishFrame = CFrame.new(direction * BEAM_LENGTH) * startFrame.Rotation
				local first = Instance.new("Attachment")
				first.Name, first.CFrame, first.Visible = "HarvestEyeBeamStart", startFrame, false
				first.Parent = eye
				track(first)
				local last = Instance.new("Attachment")
				last.Name, last.CFrame, last.Visible = "HarvestEyeBeamEnd", finishFrame, false
				last.Parent = eye
				track(last)
				table.insert(attachments, { item = first, frame = first.CFrame })
				table.insert(attachments, { item = last, frame = last.CFrame })
				local beam = Instance.new("Beam")
				beam.Name, beam.Attachment0, beam.Attachment1 = "HarvestEyeBeam", first, last
				beam.Color, beam.Transparency = BEAM_COLOR, BEAM_TRANSPARENCY
				beam.Width0, beam.Width1 = 0.125, 5.5
				beam.FaceCamera, beam.Segments = true, 8
				beam.CurveSize0, beam.CurveSize1 = 0, 0
				beam.LightEmission, beam.LightInfluence, beam.Brightness = 1, 0, 1
				beam.Texture, beam.Enabled = "", false
				beam.Parent = eye
				track(beam)
				table.insert(beams, { beam = beam, first = first, last = last, section = name })
				light.Angle, light.Face = 14, Enum.NormalId.Front
				lightParent = first
			end
			light.Parent = lightParent
			track(light)
			table.insert(lights, {
				light = light,
				parent = lightParent,
				section = name,
				classic = classic,
			})
		end
	end)
	if not ok then
		clone:Destroy()
		error(problem)
	end
	clone.Parent = host
	return setmetatable({
		model = clone,
		host = host,
		parts = parts,
		lights = lights,
		beams = beams,
		attachments = attachments,
		nodes = nodes,
	}, Visual)
end

function Visual:Valid(): boolean
	if self.model.Parent ~= self.host or not owned(self.model) then
		return false
	end
	local descendants = self.model:GetDescendants()
	local count = 0
	for item, expected in self.nodes do
		count += 1
		if item.Parent ~= expected.parent or item.Name ~= expected.name or not owned(item) then
			return false
		end
	end
	if #descendants ~= count then
		return false
	end
	for _, item in descendants do
		if not self.nodes[item] then
			return false
		end
	end
	for _, entry in self.parts do
		local part = entry.part
		if
			part.Parent ~= entry.parent
			or not part:IsDescendantOf(self.model)
			or not owned(part)
			or part:GetAttribute("HarvestSection") ~= entry.section
			or part:GetAttribute("HarvestOffset") ~= entry.offset
			or part:GetAttribute("HarvestAssetKey") ~= entry.key
			or part.Size ~= entry.size
			or part.Color ~= entry.color
			or part.Material ~= entry.material
			or not part.Anchored
			or part.CanCollide
			or part.CanTouch
			or part.CanQuery
		then
			return false
		end
	end
	for _, entry in self.lights do
		if
			entry.light.Parent ~= entry.parent
			or entry.light.Name ~= "HarvestEyeLight"
			or not owned(entry.light)
			or not entry.light:IsA(if entry.classic then "SpotLight" else "PointLight")
			or entry.light.Range ~= (if entry.classic then BEAM_LENGTH else 24)
			or entry.light.Brightness ~= (if entry.classic then 2.5 else 3)
			or entry.light.Shadows
			or entry.light.Color ~= (if entry.classic then WHITE else RED)
			or (
				entry.classic
				and (entry.light.Angle ~= 14 or entry.light.Face ~= Enum.NormalId.Front)
			)
		then
			return false
		end
	end
	for _, entry in self.attachments do
		if entry.item.CFrame ~= entry.frame or entry.item.Visible then
			return false
		end
	end
	for _, entry in self.beams do
		local beam = entry.beam
		if
			beam.Attachment0 ~= entry.first
			or beam.Attachment1 ~= entry.last
			or not sameSequence(beam.Color, BEAM_COLOR)
			or not sameSequence(beam.Transparency, BEAM_TRANSPARENCY)
			or beam.Width0 ~= 0.125
			or beam.Width1 ~= 5.5
			or not beam.FaceCamera
			or beam.Segments ~= 8
			or beam.CurveSize0 ~= 0
			or beam.CurveSize1 ~= 0
			or beam.LightEmission ~= 1
			or beam.LightInfluence ~= 0
			or beam.Brightness ~= 1
			or beam.Texture ~= ""
		then
			return false
		end
	end
	return true
end

function Visual:Step(
	frame: CFrame,
	pose: { [string]: CFrame },
	visible: boolean,
	carriers: any?
): number
	if not self:Valid() then
		return 0
	end
	local assetFrame = frame * Pose.WardenAssetFrame
	for _, entry in self.parts do
		local part = entry.part
		part.CFrame = assetFrame * Pose.ScaleWardenFrame(pose[entry.section] * entry.offset)
		local transparency = if visible then entry.transparency else 1
		if part.Transparency ~= transparency then
			part.Transparency = transparency
		end
		local carrier = carriers and carriers[entry.section]
		local modifier = if carrier then carrier.LocalTransparencyModifier else 0
		if part.LocalTransparencyModifier ~= modifier then
			part.LocalTransparencyModifier = modifier
		end
	end
	for _, entry in self.lights do
		local carrier = carriers and carriers[entry.section]
		local enabled = visible and (not carrier or carrier.LocalTransparencyModifier < 1)
		if entry.light.Enabled ~= enabled then
			entry.light.Enabled = enabled
		end
	end
	for _, entry in self.beams do
		local carrier = carriers and carriers[entry.section]
		local enabled = visible and (not carrier or carrier.LocalTransparencyModifier < 1)
		if entry.beam.Enabled ~= enabled then
			entry.beam.Enabled = enabled
		end
	end
	return #self.parts
end

function Visual:Destroy()
	if self.model.Parent == self.host and owned(self.model) then
		-- A manual insertion is preserved outside the owned temporary model.
		for _, item in self.model:GetDescendants() do
			if
				(not self.nodes[item] or not owned(item))
				and item.Parent
				and (item.Parent == self.model or self.nodes[item.Parent])
			then
				item.Parent = self.host
			end
		end
		self.model:Destroy()
	end
end

return table.freeze(Visual)
