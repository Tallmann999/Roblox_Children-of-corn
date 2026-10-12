assert(
	game.RunService:IsStudio() and not game.RunService:IsRunning(),
	"Stopped Studio Edit required"
)
local map = workspace.CornMap
assert(map:GetAttribute("corn_project_id") == "children_of_corn", "Wrong map")
local old, new = "rbxassetid://137803536172445", "rbxassetid://95855894892409"
local parts = {}
for _, root in { map.Props, game.ServerStorage.CornFarmAssets } do
	for _, p in root:GetDescendants() do
		if p:GetAttribute("CornFarmMeshOwned") == true then
			assert(
				p:IsA("MeshPart")
					and p:GetAttribute("corn_project_id") == "children_of_corn"
					and (p.TextureID == old or p.TextureID == new),
				"Unknown farm texture"
			)
			table.insert(parts, p)
		end
	end
end
assert(#parts == 40, "Expected40 farm mesh parts")
game.ChangeHistoryService:SetWaypoint("Before original farm atlas")
for _, p in parts do
	p.TextureID = new
end
game.ChangeHistoryService:SetWaypoint("Original PolygonFarm atlas")
return {
	changed = #parts,
	atlas = new,
	cornOriginalPreserved = game.ServerStorage
		:FindFirstChild("SM_Prop_Plant_Corn_01_L")
		:FindFirstChildWhichIsA("MeshPart", true).TextureID,
}
