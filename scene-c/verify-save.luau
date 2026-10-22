-- Read-only audit of the author's engine Save. Never serialize a place.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
assert(#process.args == 2, "Usage: verify-save <C engine rbxl> <final manifest.json>")
local raw = fs.readFile(process.args[1])
local manifest = serde.decode("json", fs.readFile(process.args[2]))
local place = roblox.deserializePlace(raw)
-- Current Lune reflection exposes the serialized legacy ID fields through Content.
local function uri(item, property)
	local content = item[property]
	assert(typeof(content) == "Content", "Serialized Content expected")
	return content.SourceType.Name == "Uri" and content.Uri or ""
end
local world = assert(place.Workspace:FindFirstChild("CornCTestWorld"), "Authored C world missing")
assert(world:GetAttribute("corn_project_id") == "children_of_corn_C_test", "C ownership differs")
local decor = assert(world:FindFirstChild("Decor"), "C decoration missing")
assert(#decor:GetChildren() == 368, "Saved C requires complete 368 meshes")
local result = {
	passed = true,
	scene_bytes = #raw,
	instances = #place:GetDescendants(),
	sources = 0,
	counts = {},
	placements = 0,
	source_sha256 = {},
	mesh_content = { persistent_corn_uri = 0, regenerated_from_saved_data_on_Play = 0 },
}
local seen = {}
for _, item in place:GetDescendants() do
	if item:IsA("LuaSourceContainer") then
		local path = item:GetFullName():gsub("%.", "/")
		local expected = assert(manifest.sources[path], "Unexpected C Source: " .. path)
		assert(not seen[path] and item.ClassName == expected.class, "Source graph differs")
		seen[path] = true
		local hash = serde.hash("sha256", item.Source:gsub("\r\n", "\n"))
		assert(hash == expected.sha256, "Saved Source differs: " .. path)
		result.sources += 1
		result.source_sha256[path] = hash
		if item:IsA("BaseScript") then
			assert(not item.Disabled, "C bootstrap disabled")
		end
	end
end
assert(result.sources == 9, "Saved C requires nine exact Sources")
local placements = {}
for _, item in decor:GetChildren() do
	assert(item:IsA("MeshPart") and #item:GetChildren() == 0, "C mesh graph differs")
	local key = item:GetAttribute("SceneCGeometryKey")
	assert(manifest.layout_counts[key], "Unknown C asset")
	result.counts[key] = (result.counts[key] or 0) + 1
	local index = item:GetAttribute("SceneCPlacement")
	assert(
		type(index) == "number"
			and index % 1 == 0
			and index >= 1
			and index <= 368
			and not placements[index],
		"C placement differs"
	)
	placements[index] = true
	result.placements += 1
	assert(
		item.Anchored
			and not item.CanCollide
			and not item.CanTouch
			and not item.CanQuery
			and item.CastShadow
			and item.Transparency == 0,
		"C mesh physics/visibility differs"
	)
	assert(
		item.CFrame == item:GetAttribute("SceneCPlacedCFrame")
			and item.Size == item:GetAttribute("SceneCPlacedSize"),
		"Saved C placement differs"
	)
	assert(
		item.InitialSize == item:GetAttribute("SceneCPlacedMeshSize"),
		"Saved native mesh bounds differ"
	)
	assert(
		uri(item, "TextureContent") == item:GetAttribute("SceneCPlacedTextureID"),
		"Saved texture differs from native placement"
	)
	if key == "Corn" then
		assert(
			item.Size.Y == 8
				and uri(item, "MeshContent") == "rbxassetid://104111861186519"
				and uri(item, "TextureContent") == "rbxassetid://137803536172445",
			"Original corn asset/height differs"
		)
		result.mesh_content.persistent_corn_uri += 1
	else
		assert(
			uri(item, "TextureContent") == "rbxassetid://95855894892409",
			"Soil/grass atlas differs"
		)
		-- Opaque session meshes are not embedded by engine Save. The exact four
		-- geometry data modules and both enabled bootstraps recreate them on Play.
		assert(item.MeshContent.SourceType.Name == "None", "Unexpected saved non-corn mesh content")
		result.mesh_content.regenerated_from_saved_data_on_Play += 1
	end
end
for key, count in manifest.layout_counts do
	assert(result.counts[key] == count, "Asset count differs: " .. key)
end
assert(
	not place.Workspace:FindFirstChild("SpawnLocation")
		and place.ServerStorage:FindFirstChild("SpawnLocation"),
	"Original Baseplate spawn backup differs"
)
assert(
	place.StarterPlayer.CharacterWalkSpeed == 12
		and place.StarterPlayer.CameraMode.Name == "LockFirstPerson",
	"C walking settings differ"
)
assert(
	place.Lighting.GlobalShadows and place.Lighting.TimeOfDay == "14:00:00",
	"C lighting differs"
)
print(serde.encode("json", result))
