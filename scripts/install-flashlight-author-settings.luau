-- Only the exact user-created Workspace.Flashlight Part/SpotLight are in scope.
-- Its actual SpotLight instance is retained in a non-rendered editable bank.
local run = game:GetService("RunService")
assert(run:IsStudio() and run:IsEdit() and not run:IsRunning(), "Stop Play")
assert(workspace.CornMap:GetAttribute("corn_project_id") == "children_of_corn" and workspace.CornMap:GetAttribute("HarvestArtVariant") == "A", "Verified Corn A required")
local storage = game:GetService("ReplicatedStorage")
local bank = storage:FindFirstChild("CornFlashlightSettings")
if bank then
	assert(bank.ClassName == "Folder" and bank:GetAttribute("corn_project_id") == "children_of_corn" and bank:GetAttribute("CornFlashlightSettingsVersion") == 1, "Foreign settings bank")
	assert(#bank:GetChildren() == 2 and bank.Wide.ClassName == "SpotLight" and bank.Core.ClassName == "SpotLight", "Changed settings bank")
	assert(not workspace:FindFirstChild("Flashlight"), "New author Part appeared; preserve it")
	return { repeated = true, removedParts = 0 }
end
local part = assert(workspace:FindFirstChild("Flashlight"), "User-created Flashlight required")
assert(part.ClassName == "Part" and #part:GetChildren() == 1 and #part:GetTags() == 0 and next(part:GetAttributes()) == nil, "Changed author Part; preserved")
local wide = assert(part:FindFirstChild("SpotLight"))
assert(wide.ClassName == "SpotLight" and #wide:GetChildren() == 0 and #wide:GetTags() == 0 and next(wide:GetAttributes()) == nil, "Changed author light; preserved")
assert(wide.Range == 24 and wide.Angle == 54 and math.abs(wide.Brightness - 15.08) < 0.00001 and wide.Face == Enum.NormalId.Front and not wide.Shadows and wide.Enabled and wide.Color == Color3.new(1, 1, 1), "Author parameters changed; reread before transfer")
local folder = Instance.new("Folder")
folder.Name = "CornFlashlightSettings"
folder:SetAttribute("corn_project_id", "children_of_corn")
folder:SetAttribute("CornFlashlightSettingsVersion", 1)
folder:SetAttribute("Pitch", -6)
local core = wide:Clone()
core.Name, core.Angle, core.Brightness = "Core", 26, 22.62
core.Parent = folder
local ok, problem = pcall(function()
	wide.Parent, wide.Name = folder, "Wide"
	folder.Parent = storage
	part.Parent = nil
end)
if not ok then
	wide.Parent, wide.Name = part, "SpotLight"
	part.Parent = workspace
	folder:Destroy()
	error("Author light transfer rolled back: " .. tostring(problem))
end
assert(wide.Parent == folder and #part:GetChildren() == 0)
part:Destroy()
return { repeated = false, removedParts = 1, retainedAuthorLight = true, addedCore = true, bank = folder:GetFullName() }
