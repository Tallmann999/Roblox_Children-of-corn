assert(
	game.RunService:IsStudio() and not game.RunService:IsRunning(),
	"Stopped Studio Edit required"
)
local map = workspace.CornMap
assert(map:GetAttribute("corn_project_id") == "children_of_corn", "Wrong map")
local changed = 0
game.ChangeHistoryService:SetWaypoint("Before farm Atomic streaming")
for _, root in { map.Props, game.ServerStorage.CornFarmAssets } do
	for _, model in root:GetChildren() do
		if
			model:GetAttribute("CornFarmAssetOwned") == true
			and model:GetAttribute("corn_project_id") == "children_of_corn"
		then
			assert(model:IsA("Model"))
			assert(
				model.ModelStreamingMode == Enum.ModelStreamingMode.Default
					or model.ModelStreamingMode == Enum.ModelStreamingMode.Atomic,
				"Manual streaming change"
			)
			if model.ModelStreamingMode ~= Enum.ModelStreamingMode.Atomic then
				model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
				changed += 1
			end
		end
	end
end
game.ChangeHistoryService:SetWaypoint("Farm models stream atomically")
return { changed = changed, globalStreamingPreserved = workspace.StreamingEnabled }
