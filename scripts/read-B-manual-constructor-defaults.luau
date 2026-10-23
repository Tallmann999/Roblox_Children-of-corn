-- Independent rbxreflection constructor defaults only. No place is read,
-- instantiated, saved or rewritten; the XML exists solely on stdout.
local r = require("@lune/roblox")
local stdio = require("@lune/stdio")
local items = {}
local db = r.getReflectionDatabase()
for _, className in { "Model", "Part", "BillboardGui", "TextLabel" } do
	local item = r.Instance.new(className)
	for name, value in db:GetClass(className).DefaultProperties do
		item[name] = value
	end
	local class = db:GetClass(className)
	local seen = {}
	while class do
		for name in class.Properties do
			if not seen[name] then
				seen[name] = true
				local property = class.Properties[name]
				if
					property.Datatype == "Ref"
					and name ~= "Parent"
					and property.Scriptability == "ReadWrite"
				then
					-- A dangling in-memory reference serializes to the constructor's
					-- null Ref without adding any object to the exported model list.
					pcall(function()
						item[name] = r.Instance.new("Folder")
					end)
				else
					pcall(function()
						item[name] = item[name]
					end)
				end
			end
		end
		class = if class.Superclass then db:GetClass(class.Superclass) else nil
	end
	table.insert(items, item)
end
stdio.write(r.serializeModel(items, true))
