local fs = require("@lune/fs")
local r = require("@lune/roblox")
local serde = require("@lune/serde")
local process = require("@lune/process")
local place = r.deserializePlace(fs.readFile(process.args[1]))
local roots = { "ReplicatedStorage/GameShared", "ServerScriptService/GameServer", "StarterPlayer/StarterPlayerScripts/GameClient" }
local result = { classes = {}, sources = {}, instances = #place:GetDescendants() }
local function pathOf(item)
	return item:GetFullName():gsub("%.", "/")
end
for _, item in place:GetDescendants() do
	local path = pathOf(item)
	local owned = false
	for _, root in roots do if path == root or path:sub(1, #root + 1) == root .. "/" then owned = true end end
	if owned then result.classes[path] = item.ClassName end
	if item:IsA("LuaSourceContainer") then
		assert(not result.sources[path], "Duplicate persistent Source")
		local source = item.Source:gsub("\r\n", "\n")
		result.sources[path] = { class = item.ClassName, sha256 = serde.hash("sha256", source), bytes = #source }
	end
end
print(serde.encode("json", result))
