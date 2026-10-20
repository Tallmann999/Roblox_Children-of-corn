--!strict

-- Both atlases use the original mesh UVs; the imported green art stays intact.
local detailedTemplates = nil
local detailedBuilding = false
local CornAppearance = {
	MeshId = "rbxassetid://104111861186519",
	GreenTextureId = "rbxassetid://137803536172445",
	DryTextureId = "rbxassetid://103653296385119",
	DetailedNearChunkLimit = 4,
	DetailedNearPlantLimit = 576,
	DetailedHeight = 10,
}

function CornAppearance.Variety(column: number, row: number): number
	-- Keep the same shape at every detail level, including the even backdrop grid.
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

function CornAppearance.IsDetailedPlant(part: Instance, variety: number, lod: string): boolean
	return part:IsA("MeshPart")
		and part:GetAttribute("corn_project_id") == "children_of_corn"
		and part:GetAttribute("HarvestGeometryOwner") == "harvest_warden_v1"
		and part:GetAttribute("HarvestAssetKey") == CornAppearance.DetailedKey(variety, lod)
		and part.Anchored
		and part.Archivable
		and not part.CanCollide
		and not part.CanTouch
		and not part.CanQuery
end

function CornAppearance.DetailedPivot(plant: BasePart, position: Vector3, yaw: number): CFrame
	local offset = plant:GetAttribute("HarvestRootOffset")
	assert(typeof(offset) == "Vector3", "Detailed corn root offset required")
	local varied = Vector3.new(offset.X, offset.Y * plant.Size.Y / 8, offset.Z)
	return CFrame.new(position) * CFrame.Angles(0, yaw, 0) * CFrame.new(varied)
end

function CornAppearance.DetailedTemplates(): any
	while detailedBuilding do
		task.wait()
	end
	if detailedTemplates then
		return detailedTemplates
	end
	-- EditableMesh Content is reconstructed separately on each peer, as with farm art.
	-- Replicated dynamic mesh objects are never assumed to carry visible geometry.
	detailedBuilding = true
	local created = {}
	local ok, result = pcall(function()
		local geometry = require(script.Parent:WaitForChild("HarvestArtGeometry"))
		local templates = {}
		local seen: { [Instance]: boolean } = {}
		for _, lod in { "Near", "Mid", "Far" } do
			templates[lod] = {}
			for variety = 1, 4 do
				local part = geometry.CornTemplate(variety, lod)
				assert(
					CornAppearance.IsDetailedPlant(part, variety, lod)
						and part:GetAttribute("CornPlantTemplateOwned") == true
						and math.abs(part.Size.Y - 8) < 0.001
						and typeof(part:GetAttribute("HarvestRootOffset")) == "Vector3"
						and part.PivotOffset == CFrame.identity
						and not seen[part],
					"Unknown detailed corn template binding"
				)
				seen[part] = true
				-- Keep immutable catalog geometry at eight studs. Only the personal
				-- B render template grows vertically; rooted placement scales its Y.
				local taller = part:Clone()
				table.insert(created, taller)
				taller.Size = Vector3.new(part.Size.X, CornAppearance.DetailedHeight, part.Size.Z)
				templates[lod][variety] = taller
			end
		end
		return templates
	end)
	detailedBuilding = false
	if not ok then
		for _, part in created do
			part:Destroy()
		end
	end
	assert(ok, tostring(result))
	detailedTemplates = result
	return result
end

function CornAppearance.IsDry(mode: string?): boolean
	-- Ready/menu already show the only playable night field.
	return mode == nil or mode == "medium" or mode == "hard"
end

function CornAppearance.IsValidMode(mode: any): boolean
	return mode == nil or mode == "easy" or mode == "medium" or mode == "hard"
end

return table.freeze(CornAppearance)
