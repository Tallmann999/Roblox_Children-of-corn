local prior = {}
for _, entry in baseline do prior[entry.path] = entry end
local previous = {}
for _, entry in previousRepair do previous[entry.path] = entry end
local objects = {}
for _, entry in updates do
    local item = resolve(entry.path)
    assert(item and item.ClassName == entry.class, "Missing code object: " .. entry.path .. "; nothing changed")
    assert(editor:FindScriptDocument(item) == nil, "Close script tab: " .. entry.path .. "; nothing changed")
    local old = prior[entry.path]
    assert(normalized(item.Source) == normalized(old.source)
        or normalized(item.Source) == normalized(previous[entry.path].source)
        or normalized(item.Source) == normalized(entry.source),
        "Unrecognized manual Source edit: " .. entry.path .. "; nothing changed")
    if freshPaths[entry.path] then
        assert(#item:GetChildren() == 0, "Authoring module contains extra objects: " .. entry.path .. "; nothing changed")
    end
    objects[entry.path] = item
end
local oldPreview = map:FindFirstChild("EditorPreview")
local oldOverview = map:FindFirstChild("EditorFieldOverview")
for _, record in {{oldPreview, "CornEditorPreview"}, {oldOverview, "CornEditorOverview"}} do
    local folder = record[1]
    if folder then
        assert(folder:IsA("Folder") and folder:GetAttribute(record[2]) == true
            and folder:GetAttribute("corn_project_id") == "children_of_corn", "Unrecognized authoring layer; nothing changed")
    end
end
local art = game:GetService("ServerStorage")
local artSource = art:FindFirstChild("CornPlantTemplate") or art:FindFirstChild("SM_Prop_Plant_Corn_01_L")
assert(artSource, "Corn source missing; nothing changed")
local function shape(item, rootName)
    local children = {}
    for _, child in item:GetChildren() do table.insert(children, shape(child)) end
    table.sort(children)
    return item.ClassName .. ":" .. (rootName or item.Name) .. "[" .. table.concat(children, "|") .. "]"
end
local sourceMesh = if artSource:IsA("MeshPart") then artSource else artSource:FindFirstChildWhichIsA("MeshPart", true)
assert(sourceMesh and sourceMesh:IsA("MeshPart"), "Expected imported corn mesh; nothing changed")
local modelShape = shape(artSource, "Corn")
local meshShape = shape(sourceMesh, "Corn")
if oldPreview then
    for _, item in oldPreview:GetChildren() do
        local itemShape = shape(item)
        assert(item.Name == "Corn" and (itemShape == modelShape or itemShape == meshShape),
            "EditorPreview contains manual objects; nothing changed")
    end
end
if oldOverview then
    local overviewShape = shape(sourceMesh, "DistantCorn")
    for _, item in oldOverview:GetChildren() do
        assert(item:IsA("MeshPart") and item:GetAttribute("CornEditorOverview") == true
            and item:GetAttribute("corn_project_id") == "children_of_corn" and shape(item) == overviewShape,
            "EditorFieldOverview contains manual objects; nothing changed")
    end
end
local oldCorners = map:FindFirstChild("CornerSpawns")
local lowerSpawn = world:FindFirstChild("SpawnLocation")
local lowerWasEnabled = if lowerSpawn and lowerSpawn:IsA("SpawnLocation") then lowerSpawn.Enabled else nil
local previousVersion = map:GetAttribute("map_version")
local changed, swapped = {}, {}
local layersDetached = false
local history = game:GetService("ChangeHistoryService")
history:SetWaypoint("Before Corn spawn and field repair")
local ok, problem = pcall(function()
    for _, entry in updates do
        local item = objects[entry.path]
        if freshPaths[entry.path] then
            -- New instances avoid edit-mode require() caches from the original install.
            local replacement = item:Clone()
            assert(replacement, "Module clone failed")
            replacement.Source = entry.source
            local parent = item.Parent
            item.Parent = nil
            replacement.Parent = parent
            table.insert(swapped, {old=item, new=replacement, parent=parent})
        else
            table.insert(changed, {item=item, source=item.Source})
            item.Source = entry.source
        end
    end
    if oldPreview then oldPreview.Parent = nil end
    if oldOverview then oldOverview.Parent = nil end
    layersDetached = true
    local author = require(resolve("ServerScriptService/GameServer/Game/MapAuthoring"))
    local corners = author.EnsureCornerSpawns(map)
    local selected = corners:FindFirstChild("SW")
    assert(selected and selected:IsA("SpawnLocation"), "SW corner is missing")
    author.RebuildOverview(map)
    author.Preview(map, selected.Position)
    local field = map:FindFirstChild("FieldZone")
    if lowerWasEnabled ~= nil and field and field:IsA("BasePart")
        and lowerSpawn.Position.Y < field.Position.Y - field.Size.Y / 2 - 10 then
        lowerSpawn.Enabled = false
    end
    map:SetAttribute("map_version", 2)
    game:GetService("Selection"):Set({selected})
end)
if not ok then
    if layersDetached then
        for _, name in {"EditorPreview", "EditorFieldOverview"} do
            local newLayer = map:FindFirstChild(name)
            if newLayer then newLayer:Destroy() end
        end
    end
    if not oldCorners then
        local corners = map:FindFirstChild("CornerSpawns")
        if corners then corners:Destroy() end
    end
    if oldPreview then oldPreview.Parent = map end
    if oldOverview then oldOverview.Parent = map end
    if lowerWasEnabled ~= nil then lowerSpawn.Enabled = lowerWasEnabled end
    map:SetAttribute("map_version", previousVersion)
    for _, entry in changed do entry.item.Source = entry.source end
    for index = #swapped, 1, -1 do
        local entry = swapped[index]
        entry.new:Destroy()
        entry.old.Parent = entry.parent
    end
    error("Corn scene repair rolled back: " .. tostring(problem))
end
if oldPreview then oldPreview:Destroy() end
if oldOverview then oldOverview:Destroy() end
for _, entry in swapped do entry.old:Destroy() end
history:SetWaypoint("Repaired Corn corner starts and dense field")
print("ChildrenOfCorn scene repaired: 4 corner spawns, dense corn, full field overview; press F, SAVE, then Play")
