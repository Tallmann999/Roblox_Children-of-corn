-- Generated verified Harvest GLB geometry; peer-local art only.
local chunks = {}
for _, name in { "Chunk01", "Chunk02", "Chunk03", "Chunk04", "Chunk05", "Chunk06" } do
	table.insert(chunks, require(script:WaitForChild(name)))
end
return game:GetService("HttpService"):JSONDecode(table.concat(chunks))
