--!strict
local RunService = game:GetService("RunService")
local Manual = require(game:GetService("ReplicatedStorage").GameShared.Game.ManualScene)
local Service = { Name = "ManualSceneService", Order = 10 }

function Service:Init(context: any)
	self._enabled = RunService:IsStudio() and context.Config.Environment == "DEV"
	if not self._enabled then
		return
	end
	local map = workspace:FindFirstChild("CornMap")
	if not Manual.IsTarget(map) then
		return
	end
	assert(map, "Manual scene missing")
	local corn = assert(map:FindFirstChild("CornAuthoring"), "Authored corn folder required")
	local storage = game:GetService("ReplicatedStorage")
	assert(
		not storage:FindFirstChild("BManualEditorSources"),
		"Existing editor source pool preserved"
	)
	local pool = Instance.new("Folder")
	pool.Name = "BManualEditorSources"
	pool:SetAttribute("corn_project_id", "children_of_corn")
	pool:SetAttribute("BManualAuthoringVersion", 1)
	pool.Parent = storage
	local source = Instance.new("Folder")
	source.Name = "CornAuthoring"
	source:SetAttribute("corn_project_id", "children_of_corn")
	source:SetAttribute("BManualAuthoringVersion", 1)
	source:SetAttribute("BManualServerReady", false)
	source.Parent = pool
	local count = 0
	-- Transfer small existing chunks instead of updating visibility on every
	-- plant. ReplicatedStorage retains authored values and does not render art.
	for index, chunk in corn:GetChildren() do
		assert(
			chunk:GetAttribute("corn_project_id") == "children_of_corn",
			"Foreign authored chunk"
		)
		count += if chunk:IsA("BasePart") then 1 else #chunk:GetDescendants()
		chunk.Parent = source
		if index % 24 == 0 then
			task.wait()
		end
	end
	for index, item in map:GetDescendants() do
		if item:IsA("BasePart") then
			if item:GetAttribute("BAuthoringHelper") == true then
				item.Transparency = 1
				item.CanCollide, item.CanTouch, item.CanQuery = false, false, false
			end
		elseif item:IsA("BillboardGui") and item:GetAttribute("BAuthoringHelper") == true then
			item.Enabled = false
		end
		if index % 512 == 0 then
			task.wait()
		end
	end
	source:SetAttribute("BManualServerReady", true)
	print("[ManualSceneService] Authored B plants ready:", count)
end

return Service
