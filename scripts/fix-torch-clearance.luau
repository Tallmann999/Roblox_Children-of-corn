-- One guarded correction for the freshly authored slot torches; never changes houses/art.
local run = game:GetService("RunService")
assert(run:IsStudio() and not run:IsRunning(), "Stop Play")
assert(not workspace:FindFirstChild("Asmr_Base") and not workspace:FindFirstChild("ASMR_Models"), "Wrong game")
local map = workspace:FindFirstChild("CornMap")
assert(map and map:GetAttribute("corn_project_id") == "children_of_corn" and map:GetAttribute("MapTuningVersion") == 1, "Wrong Corn map")
assert(map:GetAttribute("TorchClearanceVersion") == nil, "Already corrected; preserve manual edits")
local entries = {}
local floor = map.Ground.Position.Y + map.Ground.Size.Y / 2
for _, slot in map.KeySlots:GetChildren() do
    local model = map.TorchMarkers:FindFirstChild("torch_" .. slot.Name)
    assert(model and model:IsA("Model") and model:GetAttribute("CornTorchOwned") == true, "Unknown torch")
    local pole = model:FindFirstChild("Pole")
    local expected = Vector3.new(slot.Position.X + 4, floor + 6.5, slot.Position.Z)
    assert(pole and (pole.Position - expected).Magnitude < 0.01, "Manual torch placement; not overwritten")
    table.insert(entries, {item = model, frame = model:GetPivot()})
end
assert(#entries == 15)
local oldCount = map:GetAttribute("EditorCornCount")
local ok, problem = pcall(function()
    for _, entry in entries do entry.item:PivotTo(entry.frame + Vector3.new(-4, 0, 4)) end
    map:SetAttribute("EditorCornCount", #map.EditorPreview:GetChildren())
    map:SetAttribute("TorchClearanceVersion", 1)
end)
if not ok then
    for _, entry in entries do entry.item:PivotTo(entry.frame) end
    map:SetAttribute("EditorCornCount", oldCount)
    map:SetAttribute("TorchClearanceVersion", nil)
    error(tostring(problem))
end
return {cleared_barrels = 15}
