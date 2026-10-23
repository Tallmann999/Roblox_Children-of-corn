--!strict

-- B mixes the original imported green plant with three authored FBX shapes.
-- Both bounded renderers use the same deterministic geometry, size and anchor.
local Geometry = require(script.Parent.CornGreenGeometry)
local detailedTemplates = nil
local detailedBuilding = false
local templateSizes = nil
local templateContents = nil
local SOURCE_SHA256 = "259fbe167d4c0a24e6813282a5f3026d582b67d7af1f701bad39bed706a193df"
local EXPECTED_SIZE = Vector3.new(3.0026558642674086, 8, 3.1309012101883917)
local OPTIONS = {
	CollisionFidelity = Enum.CollisionFidelity.Box,
	RenderFidelity = Enum.RenderFidelity.Precise,
}
local CornAppearance = {
	MeshId = "rbxassetid://104111861186519",
	GreenTextureId = "rbxassetid://137803536172445",
	-- CornField.Prepare uses this legacy property before art can replicate.
	-- Its B value deliberately stays green in every menu and round mode.
	DryTextureId = "rbxassetid://137803536172445",
	DetailedNearChunkLimit = 8,
	DetailedNearPlantLimit = 1152,
	DetailedHeight = 8,
}

local originalDescription = table.freeze({
	size = EXPECTED_SIZE,
	rootOffset = Vector3.new(0, 4, 0),
	sourceHash = SOURCE_SHA256,
})
local function description(variety)
	if variety == 1 then
		return originalDescription
	end
	return Geometry.Describe(string.format("Var%02d", variety - 1))
end

function CornAppearance.Variety(column: number, row: number): number
	return ((column * 73856093 + row * 19349663 + 817) % 104729) % 4 + 1
end

function CornAppearance.IsDetailedMap(map: Instance?): boolean
	return map ~= nil
		and map:IsA("Model")
		and map.Name == "CornMap"
		and map:GetAttribute("corn_project_id") == "children_of_corn"
		and map:GetAttribute("HarvestArtVariant") == "B"
end

function CornAppearance.DetailedKey(variety: number, lod: string): string
	assert(variety >= 1 and variety <= 4 and variety % 1 == 0, "Corn variety must be 1..4")
	assert(lod == "Near" or lod == "Mid" or lod == "Far", "Unknown corn geometry LOD")
	return "Corn_" .. string.char(64 + variety) .. "_" .. lod
end

local function attributes(variety: number, lod: string): { [string]: any }
	local data = description(variety)
	return {
		corn_project_id = "children_of_corn",
		CornPlantTemplateOwned = true,
		CornGreenOriginal = true,
		CornGreenTemplateOwned = true,
		CornGreenTemplateVersion = 2,
		CornGreenSourceSHA256 = data.sourceHash,
		CornGreenVariety = variety,
		CornGreenLod = lod,
		HarvestRootOffset = data.rootOffset,
		CornGreenTemplateSize = data.size,
	}
end

function CornAppearance.IsDetailedPlant(part: Instance, variety: number, lod: string): boolean
	CornAppearance.DetailedKey(variety, lod)
	local data = description(variety)
	return part:IsA("MeshPart")
		and part:GetAttribute("corn_project_id") == "children_of_corn"
		and part:GetAttribute("CornGreenOriginal") == true
		and part:GetAttribute("CornGreenTemplateOwned") == true
		and part:GetAttribute("CornGreenTemplateVersion") == 2
		and part:GetAttribute("CornGreenSourceSHA256") == data.sourceHash
		and part:GetAttribute("CornGreenVariety") == variety
		and part:GetAttribute("CornGreenLod") == lod
		and (if variety == 1
			then part.MeshId == CornAppearance.MeshId
				and part.MeshContent.SourceType == Enum.ContentSourceType.Uri
			else part.MeshContent.SourceType == Enum.ContentSourceType.Opaque)
		and part.TextureID == CornAppearance.GreenTextureId
		and part.Anchored
		and part.Archivable
		and not part.CanCollide
		and not part.CanTouch
		and not part.CanQuery
end

function CornAppearance.DetailedPivot(plant: BasePart, position: Vector3, yaw: number): CFrame
	assert(
		plant:IsA("MeshPart")
			and plant:GetAttribute("CornGreenOriginal") == true
			and plant:GetAttribute("corn_project_id") == "children_of_corn",
		"Original green corn root binding required"
	)
	local offset, size =
		plant:GetAttribute("HarvestRootOffset"), plant:GetAttribute("CornGreenTemplateSize")
	assert(
		typeof(offset) == "Vector3"
			and typeof(size) == "Vector3"
			and size.X > 0
			and size.Y > 0
			and size.Z > 0,
		"Authored corn anchor required"
	)
	local scaled = Vector3.new(
		offset.X * plant.Size.X / size.X,
		offset.Y * plant.Size.Y / size.Y,
		offset.Z * plant.Size.Z / size.Z
	)
	return CFrame.new(position) * CFrame.Angles(0, yaw, 0) * CFrame.new(scaled)
end

local function validateTemplate(
	part: MeshPart,
	variety: number,
	lod: string,
	size: Vector3,
	content: Content
)
	assert(
		CornAppearance.IsDetailedPlant(part, variety, lod)
			and part.Parent == nil
			and part.Name == CornAppearance.DetailedKey(variety, lod)
			and part.CFrame == CFrame.identity
			and part.PivotOffset == CFrame.identity
			and part.Size == size
			and part.MeshContent == content
			and part.CastShadow
			and part.DoubleSided
			and part.Transparency == 0
			and part.Reflectance == 0
			and part.Color == Color3.new(1, 1, 1)
			and part.Material == Enum.Material.Plastic
			and part.MaterialVariant == ""
			and part.Massless
			and part.CollisionGroup == "Default"
			and part.CustomPhysicalProperties == nil
			and part.CollisionFidelity == OPTIONS.CollisionFidelity
			and part.RenderFidelity == OPTIONS.RenderFidelity
			and #part:GetChildren() == 0
			and #part:GetTags() == 0,
		"Private B green corn template was changed; author work preserved"
	)
	local expected = attributes(variety, lod)
	local actual = part:GetAttributes()
	for key, value in expected do
		assert(actual[key] == value, "Private B green corn attribute changed: " .. key)
	end
	for key in actual do
		assert(expected[key] ~= nil, "Foreign private B green corn attribute: " .. key)
	end
end

local function validateCache(cache, sizes, contents)
	local seen: { [Instance]: boolean } = {}
	for _, lod in { "Near", "Mid", "Far" } do
		for variety = 1, 4 do
			local part = cache[lod][variety]
			assert(not seen[part], "Duplicate private B green corn template")
			seen[part] = true
			validateTemplate(part, variety, lod, sizes[variety], contents[variety])
		end
	end
end

local function decorate(part: MeshPart, variety: number, lod: string, size: Vector3)
	part.Name = CornAppearance.DetailedKey(variety, lod)
	part.Archivable = true
	part.CFrame = CFrame.identity
	part.PivotOffset = CFrame.identity
	part.Size = size
	part.TextureID = CornAppearance.GreenTextureId
	part.Color = Color3.new(1, 1, 1)
	part.Material = Enum.Material.Plastic
	part.MaterialVariant = ""
	part.Transparency = 0
	part.Reflectance = 0
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = true
	part.DoubleSided = true
	part.Massless = true
	part.CollisionGroup = "Default"
	part.CustomPhysicalProperties = nil
	for key, value in attributes(variety, lod) do
		part:SetAttribute(key, value)
	end
end

function CornAppearance.DetailedTemplates(): any
	while detailedBuilding do
		task.wait()
	end
	if detailedTemplates then
		validateCache(detailedTemplates, templateSizes, templateContents)
		return detailedTemplates
	end
	detailedBuilding = true
	local created: { MeshPart } = {}
	local ok, result = pcall(function()
		local assetService = game:GetService("AssetService")
		local original = assert(
			assetService:CreateMeshPartAsync(Content.fromUri(CornAppearance.MeshId), OPTIONS),
			"Original green corn mesh unavailable"
		)
		table.insert(created, original)
		assert(
			original:IsA("MeshPart")
				and original.Parent == nil
				and original.MeshContent.SourceType == Enum.ContentSourceType.Uri
				and original.MeshId == CornAppearance.MeshId
				and original.MeshSize.Y > 0
				and #original:GetChildren() == 0
				and #original:GetTags() == 0
				and next(original:GetAttributes()) == nil,
			"Original green corn asset binding changed"
		)
		local size = original.MeshSize * (CornAppearance.DetailedHeight / original.MeshSize.Y)
		assert((size - EXPECTED_SIZE).Magnitude < 0.003, "Original green corn FBX bounds differ")
		local templates = { Near = {}, Mid = {}, Far = {} }
		local bases = { original }
		local sizes = { size }
		local contents = { original.MeshContent }
		for variety = 2, 4 do
			local part, data = Geometry.Bake(string.format("Var%02d", variety - 1))
			table.insert(created, part)
			bases[variety] = part
			sizes[variety] = data.size
			contents[variety] = part.MeshContent
		end
		for _, lod in { "Near", "Mid", "Far" } do
			for variety = 1, 4 do
				local part = bases[variety]
				if lod ~= "Near" then
					part = assert(bases[variety]:Clone(), "Green corn private clone unavailable")
					table.insert(created, part)
				end
				decorate(part, variety, lod, sizes[variety])
				templates[lod][variety] = part
			end
			table.freeze(templates[lod])
		end
		validateCache(templates, sizes, contents)
		templateSizes = sizes
		templateContents = contents
		return table.freeze(templates)
	end)
	detailedBuilding = false
	if not ok then
		for _, part in created do
			part:Destroy()
		end
		error("B green corn unavailable; a later call can retry: " .. tostring(result), 0)
	end
	detailedTemplates = result
	return result
end

function CornAppearance.IsDry(_mode: string?): boolean
	return false
end

function CornAppearance.IsValidMode(mode: any): boolean
	return mode == nil or mode == "easy" or mode == "medium" or mode == "hard"
end

return table.freeze(CornAppearance)
