-- Read-only metadata for explicit Corn repair preservation checks.
local fs = require("@lune/fs")
local r = require("@lune/roblox")
local process = require("@lune/process")
local serde = require("@lune/serde")
local place = r.deserializePlace(fs.readFile(process.args[1]))
local world = place:GetService("Workspace")
local map = world:FindFirstChild("CornMap")
local function attrs(item)
    local result = {}
    if item then for key, value in item:GetAttributes() do result[key] = {type=typeof(value), value=tostring(value)} end end
    return result
end
local field = if map then map:FindFirstChild("FieldZone") else nil
local spawn = world:FindFirstChild("SpawnLocation")
local corners = if map then map:FindFirstChild("CornerSpawns") else nil
local count = 0
local ids = {}
local valid = corners ~= nil and corners:GetAttribute("CornCornerSpawnsOwned") == true
for _, item in if corners then corners:GetChildren() else {} do
    local id = item:GetAttribute("spawn_id")
    valid = valid and item:IsA("SpawnLocation") and item.Enabled and item.Neutral
        and item:HasTag("corn_spawn") and type(id) == "string" and not ids[id]
    if id then ids[id] = true end
    count += 1
end
local preview = if map then map:FindFirstChild("EditorPreview") else nil
local overview = if map then map:FindFirstChild("EditorFieldOverview") else nil
print(serde.encode("json", {map_attrs=attrs(map), corner_count=count, corners_valid=valid and count == 4,
    preview_owned=preview ~= nil and preview:GetAttribute("CornEditorPreview") == true
        and preview:GetAttribute("corn_project_id") == "children_of_corn",
    overview_owned=overview ~= nil and overview:GetAttribute("CornEditorOverview") == true
        and overview:GetAttribute("corn_project_id") == "children_of_corn",
    lower_is_spawn=spawn ~= nil and spawn:IsA("SpawnLocation"),
    lower_enabled=if spawn and spawn:IsA("SpawnLocation") then spawn.Enabled else false,
    lower_below_field=spawn ~= nil and field ~= nil and spawn:IsA("BasePart") and field:IsA("BasePart")
        and spawn.CFrame.Position.Y < field.CFrame.Position.Y - field.Size.Y / 2 - 10}))
