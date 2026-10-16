-- Generated verified Harvest GLB geometry; peer-local art only.
local chunks = {}
for _, name in { "Chunk01" } do
	table.insert(chunks, require(script:WaitForChild(name)))
end
return game:GetService("HttpService"):JSONDecode(table.concat(chunks))
