-- B preset is the author's last A tuning. Do not move or clone authored A nodes.
local run = game:GetService("RunService")
assert(run:IsStudio() and run:IsEdit() and not run:IsRunning(), "Stopped Edit required")
assert(workspace.CornMap:GetAttribute("corn_project_id") == "children_of_corn" and workspace.CornMap:GetAttribute("HarvestArtVariant") == "B", "Owned B required")
local storage = game:GetService("ReplicatedStorage")
local specs = { Wide = { Brightness = 2, Angle = 100, Range = 32 }, Core = { Brightness = 13, Angle = 30, Range = 4 } }
local bank = storage:FindFirstChild("CornFlashlightSettings")
if bank then
	assert(bank.ClassName == "Folder" and #bank:GetChildren() == 2 and #bank:GetTags() == 0, "Changed settings bank; preserved")
	local attrs = bank:GetAttributes()
	assert(attrs.corn_project_id == "children_of_corn" and attrs.CornFlashlightSettingsVersion == 1 and attrs.Pitch == -4, "Changed settings; preserved")
	local count = 0
	for _ in attrs do count += 1 end
	assert(count == 3, "Unexpected bank attributes")
	for name, spec in specs do
		local light = assert(bank:FindFirstChild(name))
		assert(light.ClassName == "SpotLight" and #light:GetChildren() == 0 and #light:GetTags() == 0 and next(light:GetAttributes()) == nil, "Changed light; preserved")
		for prop, value in spec do assert(light[prop] == value, "Changed light parameters; preserved") end
		assert(light.Face == Enum.NormalId.Front and light.Color == Color3.new(1,1,1) and light.Enabled and not light.Shadows, "Changed light properties")
	end
	return { repeated = true, addedSettings = 0 }
end
local created = {}
local ok, result = pcall(function()
	local folder = Instance.new("Folder");table.insert(created,folder)
	folder.Name = "CornFlashlightSettings"
	folder:SetAttribute("corn_project_id","children_of_corn")
	folder:SetAttribute("CornFlashlightSettingsVersion",1)
	folder:SetAttribute("Pitch",-4)
	for name, spec in specs do
		local light = Instance.new("SpotLight");table.insert(created,light);light.Name = name
		for prop,value in spec do light[prop] = value end
		light.Color,light.Face,light.Shadows,light.Enabled = Color3.new(1,1,1),Enum.NormalId.Front,false,true
		light.Parent = folder
	end
	folder.Parent = storage
	return { repeated = false, addedSettings = 3 }
end)
if not ok then for i=#created,1,-1 do created[i]:Destroy() end;error(result) end
return result
