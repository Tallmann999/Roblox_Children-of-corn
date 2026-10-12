-- Guarded narrow authoring, independent of code installation. Exact engine backup required.
local run = game:GetService("RunService")
assert(run:IsStudio() and not run:IsRunning(), "Stop Play before torch update")
local map = workspace:FindFirstChild("CornMap")
assert(map and map:GetAttribute("corn_project_id") == "children_of_corn", "Wrong scene")
local storage = game:GetService("ServerStorage")
local torches = map:FindFirstChild("TorchMarkers")
assert(torches and torches:GetAttribute("CornTorchMarkersOwned") == true, "Unknown torch folder")
local existing = storage:FindFirstChild("CornInventoryTorchArchive")
if existing then
	assert(existing:IsA("Folder") and #existing:GetChildren()==4 and #torches:GetChildren()==27, "Partial torch update")
	for _,model in torches:GetChildren() do assert(model:GetAttribute("CornTorchOwned")==true and model:FindFirstChild("Flame").TorchLight.Brightness==1, "Manual torch edit") end
	return {repeated=true,count=27}
end
assert(#torches:GetChildren()==31, "Expected farm torch baseline")
local originals={}
for _,model in torches:GetChildren() do
	assert(model:IsA("Model") and model:GetAttribute("CornTorchOwned")==true and model:GetAttribute("corn_project_id")=="children_of_corn" and model:HasTag("corn_torch"),"Foreign torch")
	local pole,flame=model:FindFirstChild("Pole"),model:FindFirstChild("Flame")
	assert(pole and pole:IsA("Part") and flame and flame:IsA("Part") and #model:GetDescendants()==4,"Unknown torch structure")
	local light=flame:FindFirstChild("TorchLight")
	assert(light and light:IsA("PointLight") and light.Brightness==2,"Manual brightness")
	table.insert(originals,{model=model,pole=pole,flame=flame,poleCF=pole.CFrame,flameCF=flame.CFrame,light=light})
end
for row=1,8 do
	local model=torches:FindFirstChild(string.format("road_exit_row_%02d",row))
	assert(model and model:GetAttribute("CornRoadExitOwned")==true,"Unknown exit torch")
	local x=if row<=4 then -10 else 10
	local z=421-8*((row-1)%4+1)
	assert((model.Pole.Position-Vector3.new(x,20.899986267089844,z)).Magnitude<0.001,"Moved exit torch")
end
local history=game:GetService("ChangeHistoryService");history:SetWaypoint("Before inventory torches")
local archive=Instance.new("Folder");archive.Name="CornInventoryTorchArchive"
local ok,problem=pcall(function()
	archive.Parent=storage
	for _,entry in originals do
		local row=tonumber(string.match(entry.model.Name,"^road_exit_row_(%d+)$"))
		if row and row%2==0 then entry.model.Parent=archive
		else
			entry.light.Brightness=1
			if row then
				local offset=Vector3.new(if row<=4 then -4 else 4,0,if row==1 or row==5 then -4 else -12)
				entry.pole.CFrame=entry.poleCF+offset;entry.flame.CFrame=entry.flameCF+offset
			end
		end
	end
end)
if not ok then
	for _,entry in originals do entry.model.Parent=torches;entry.pole.CFrame=entry.poleCF;entry.flame.CFrame=entry.flameCF;entry.light.Brightness=2 end
	archive:Destroy();error("Torch update rolled back: "..tostring(problem))
end
history:SetWaypoint("Inventory torches installed")
return {count=27,exitPoles=4,wallTorches=2,brightness=1,archived=4}
