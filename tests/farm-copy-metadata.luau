-- Read-only typed signatures used by verify-farm-copy.py. Never saves a place.
local fs = require("@lune/fs")
local r = require("@lune/roblox")
local process = require("@lune/process")
local serde = require("@lune/serde")
local place = r.deserializePlace(fs.readFile(process.args[1]))
local records = {}
local paths = {}
local ordered = {}
local function collect(parent, prefix)
	local occurrences = {}
	for _, item in parent:GetChildren() do
		local key = item.ClassName .. "\0" .. item.Name
		occurrences[key] = (occurrences[key] or 0) + 1
		local component = item.Name
			.. (if occurrences[key] == 1 then "" else "#" .. tostring(occurrences[key]))
		local path = (if prefix == "" then "" else prefix .. "/") .. component
		paths[item] = path
		table.insert(ordered, item)
		collect(item, path)
	end
end
collect(place, "")
local function typed(value)
	local kind = typeof(value)
	local data = value
	if kind == "CFrame" then
		data = { value:GetComponents() }
	elseif kind == "Vector3" then
		data = { value.X, value.Y, value.Z }
	elseif kind == "Color3" then
		data = { value.R, value.G, value.B }
	elseif kind == "EnumItem" then
		data = { name = value.Name, value = value.Value, enum = tostring(value.EnumType) }
	elseif kind == "Instance" then
		data = assert(paths[value], "Unresolved instance reference")
	elseif kind ~= "string" and kind ~= "boolean" and kind ~= "number" then
		data = tostring(value)
	end
	return { type = kind, value = data }
end
local properties = {
	"Anchored",
	"CFrame",
	"CanCollide",
	"CanQuery",
	"CanTouch",
	"CastShadow",
	"Color",
	"Material",
	"PrimaryPart",
	"Size",
	"Text",
	"Transparency",
	"Value",
	"BottomSurface",
	"Shape",
	"TopSurface",
}
for _, item in ordered do
	local attrs = {}
	for key, value in item:GetAttributes() do
		attrs[key] = typed(value)
	end
	local props = {}
	for _, key in properties do
		local ok, value = pcall(function()
			return item[key]
		end)
		if ok and value ~= nil then
			props[key] = typed(value)
		end
	end
	local tags = item:GetTags()
	table.sort(tags)
	records[paths[item]] =
		{ class = item.ClassName, attributes = attrs, properties = props, tags = tags }
end
print(serde.encode("json", records))
