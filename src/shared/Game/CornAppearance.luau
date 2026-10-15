--!strict

-- Both atlases use the original mesh UVs; the imported green art stays intact.
local CornAppearance = {
	MeshId = "rbxassetid://104111861186519",
	GreenTextureId = "rbxassetid://137803536172445",
	DryTextureId = "rbxassetid://103653296385119",
}

function CornAppearance.IsDry(mode: string?): boolean
	-- Ready/menu already show the only playable night field.
	return mode == nil or mode == "medium" or mode == "hard"
end

function CornAppearance.IsValidMode(mode: any): boolean
	return mode == nil or mode == "easy" or mode == "medium" or mode == "hard"
end

return table.freeze(CornAppearance)
