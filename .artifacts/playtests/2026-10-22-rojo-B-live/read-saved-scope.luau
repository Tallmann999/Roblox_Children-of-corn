-- Read-only saved baseline inventory. Does not serialize or modify a scene.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local place = roblox.deserializePlace(fs.readFile("place/Children_of_corn_B.rbxl"))
local roots, classes = {}, {}
for _, item in place:GetChildren() do
	roots[#roots + 1] = { name = item.Name, class = item.ClassName, descendants = #item:GetDescendants() }
end
for _, item in place:GetDescendants() do
	classes[item.ClassName] = (classes[item.ClassName] or 0) + 1
end
table.sort(roots, function(a, b) return a.name < b.name end)
print(serde.encode("json", { roots = roots, classes = classes, instances = #place:GetDescendants() }))
