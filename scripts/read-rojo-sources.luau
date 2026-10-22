-- Read-only extraction: never serialize or write a place/model.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

assert(#process.args == 1, "Usage: read-rojo-sources <engine-saved.rbxl>")
local place = roblox.deserializePlace(fs.readFile(process.args[1]))
local roots = {
	"ReplicatedStorage/GameShared",
	"ServerScriptService/GameServer",
	"StarterPlayer/StarterPlayerScripts/GameClient",
}
local result = { sources = {}, classes = {}, instances = #place:GetDescendants() }
for _, item in place:GetDescendants() do
	local path = item:GetFullName():gsub("%.", "/")
	for _, root in roots do
		if path == root or path:sub(1, #root + 1) == root .. "/" then
			assert(not result.classes[path], "Duplicate code instance: " .. path)
			result.classes[path] = item.ClassName
		end
	end
	if item:IsA("LuaSourceContainer") then
		assert(not result.sources[path], "Duplicate Source: " .. path)
		local row = { class = item.ClassName, source = item.Source:gsub("\r\n", "\n") }
		if item:IsA("BaseScript") then
			row.runContext = item.RunContext.Name
			row.disabled = item.Disabled
		end
		result.sources[path] = row
	end
end
print(serde.encode("json", result))
