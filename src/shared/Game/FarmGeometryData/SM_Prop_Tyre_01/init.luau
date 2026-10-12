-- Generated verified neutral FBX geometry; no Cloud asset upload.
local chunks = {}
for _, name in { "Chunk01", "Chunk02" } do
	table.insert(chunks, require(script:WaitForChild(name)))
end
return game:GetService("HttpService"):JSONDecode(table.concat(chunks))
