--!strict
-- Peer-local art only. The server's Root, hunt and capture rules are untouched.
local Pose = require(script.Parent:WaitForChild("MonsterPose"))
local Visual = {}
Visual.__index = Visual
local OWNER, PROJECT = "harvest_warden_v1", "children_of_corn"
local MAX_PARTS = 64
local ALLOWED = { WardenClassic = true, WardenDetailed = true }

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

function Visual.new(template: Model, host: Instance)
	assert(template:IsA("Model"), "Warden model template required")
	assert(not host:FindFirstChild("HarvestWardenVisual"), "Warden visual name occupied")
	local clone = template:Clone()
	clone.Name = "HarvestWardenVisual"
	clone:SetAttribute("HarvestGeometryOwner", OWNER)
	clone:SetAttribute("corn_project_id", PROJECT)
	local parts, lights, sections = {}, {}, {}
	local assetKey = nil
	local ok, problem = pcall(function()
		for _, item in clone:GetDescendants() do
			assert(not item:IsA("LuaSourceContainer"), "Code in Warden art template")
			if not item:IsA("BasePart") then
				assert(
					item:IsA("Model") or item:IsA("Folder") or item:IsA("SurfaceAppearance"),
					"Unsupported Warden art descendant"
				)
				item:SetAttribute("HarvestGeometryOwner", OWNER)
				item:SetAttribute("corn_project_id", PROJECT)
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
					if key == "WardenDetailed" then
						-- B keeps the dark sockets; the red emissive surface stays hidden.
						item.Transparency = 1
					else
						item.Color = Color3.fromRGB(255, 16, 14)
					end
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
		end
		for _, definition in Pose.Parts do
			assert(sections[definition.Name], "Incomplete Warden section " .. definition.Name)
		end
		for _, name in { "LeftEye", "RightEye" } do
			if assetKey == "WardenDetailed" then
				continue
			end
			local eye = nil
			for _, entry in parts do
				if entry.section == name and entry.part.Material == Enum.Material.Neon then
					eye = entry.part
					break
				end
			end
			assert(eye, "Warden red Neon eye missing")
			local light = Instance.new("PointLight")
			light.Name = "HarvestEyeLight"
			light:SetAttribute("HarvestGeometryOwner", OWNER)
			light:SetAttribute("corn_project_id", PROJECT)
			light.Color = Color3.fromRGB(255, 16, 14)
			light.Range, light.Brightness, light.Shadows = 24, 3, false
			light.Enabled = false
			light.Parent = eye
			table.insert(lights, { light = light, parent = eye, section = name })
		end
	end)
	if not ok then
		clone:Destroy()
		error(problem)
	end
	clone.Parent = host
	return setmetatable({ model = clone, host = host, parts = parts, lights = lights }, Visual)
end

function Visual:Valid(): boolean
	if self.model.Parent ~= self.host or not owned(self.model) then
		return false
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
			or entry.light.Range ~= 24
			or entry.light.Brightness ~= 3
			or entry.light.Shadows
			or entry.light.Color ~= Color3.fromRGB(255, 16, 14)
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
	return #self.parts
end

function Visual:Destroy()
	if self.model.Parent == self.host and owned(self.model) then
		-- A manual insertion is preserved outside the owned temporary model.
		for _, item in self.model:GetDescendants() do
			if not owned(item) and item.Parent and owned(item.Parent) then
				item.Parent = self.host
			end
		end
		self.model:Destroy()
	end
end

return table.freeze(Visual)
