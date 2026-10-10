-- Read only. No place serialization or physics emulation.
local fs = require("@lune/fs")
local r = require("@lune/roblox")
local serde = require("@lune/serde")
local process = require("@lune/process")
local place = r.deserializePlace(fs.readFile(process.args[1]))
local map = place:GetService("Workspace").CornMap
local folder = map:FindFirstChild("TorchMarkers")
local valid, count = true, 0
if folder then
    valid = folder:GetAttribute("CornTorchMarkersOwned") == true
        and folder:GetAttribute("corn_project_id") == "children_of_corn"
    for _, model in folder:GetChildren() do
        count += 1
        valid = valid and model:IsA("Model") and model:HasTag("corn_torch")
            and #model:GetTags() == 1 and model:GetAttribute("CornTorchOwned") == true
            and model:GetAttribute("torch_id") == model.Name
            and model:GetAttribute("corn_project_id") == "children_of_corn"
        for _, part in model:GetChildren() do
            valid = valid and part:IsA("Part") and part.Anchored
                and not part.CanCollide and not part.CanQuery and not part.CanTouch and not part.CastShadow
        end
        valid = valid and model.Flame.TorchFire.Enabled and model.Flame.TorchFire.Size == 3
            and model.Flame.TorchFire.Heat == 4 and model.Flame.TorchLight.Enabled
            and model.Flame.TorchLight.Range == 18 and not model.Flame.TorchLight.Shadows
    end
end
print(serde.encode("json", {home_attributes=map.Props.ScarecrowMarker:GetAttributes(),
    torch_count=count, torches_valid=valid}))
