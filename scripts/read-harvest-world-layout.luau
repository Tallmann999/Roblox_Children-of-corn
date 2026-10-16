-- Read-only saved-scene layout inspection; no serialization or Studio writes.
local fs = require("@lune/fs")
local r = require("@lune/roblox")
local serde = require("@lune/serde")
local place = r.deserializePlace(fs.readFile("place/Children_of_corn.rbxl"))
local map = place:GetService("Workspace").CornMap
local result = {}
for _, item in map:GetDescendants() do
	if item:IsA("BasePart") and (item.Parent.Name == "KeySlots" or item.Parent.Name == "CornerSpawns" or item.Parent.Name == "VillageRoad" or item.Parent.Name:match("^House") or item.Parent.Name == "ScarecrowMarker" or item.Name == "Ground" or item.Name == "FieldZone") then
		table.insert(result, {path = item:GetFullName(), class = item.ClassName, name=item.Name, frame={item.CFrame:GetComponents()}, size={item.Size.X,item.Size.Y,item.Size.Z},transparency=item.Transparency,attrs=item:GetAttributes(),collide=item.CanCollide,query=item.CanQuery})
	end
end
print(serde.encode("json",result))
