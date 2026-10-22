local fs = require("@lune/fs")
local r = require("@lune/roblox")
local s = require("@lune/serde")
local place = r.deserializePlace(fs.readFile("place/Children_of_corn_TestScene.rbxl"))
local seen, result = {}, {}
for _, item in place.Workspace.CornCTestWorld.Decor:GetChildren() do
	local key = item:GetAttribute("SceneCGeometryKey")
	if not seen[key] then
		seen[key] = true
		local row = { key = key, placedTexture = item:GetAttribute("SceneCPlacedTextureID"), placedMeshSize = tostring(item:GetAttribute("SceneCPlacedMeshSize")), placedMeshId = item:GetAttribute("SceneCPlacedMeshId"), properties = {} }
		for _, property in { "TextureID", "TextureContent", "MeshId", "MeshContent", "MeshSize", "InitialSize", "VertexCount", "SceneCPlacedMeshSize" } do
			local ok, value = pcall(function() return item[property] end)
			local record = { ok = ok, type = typeof(value), text = ok and tostring(value) or "unavailable" }
			if ok and typeof(value) == "Content" then
				for _, sub in { "SourceType", "Uri", "Object" } do
					local got, v = pcall(function() return value[sub] end)
					record[sub] = got and tostring(v) or "unavailable"
				end
			end
			row.properties[property] = record
		end
		table.insert(result, row)
	end
end
print(s.encode("json", result))
