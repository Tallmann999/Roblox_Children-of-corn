assert(normalized(author.Source) == normalized(baselineSource)
    or normalized(author.Source) == normalized(latestSource),
    "Unrecognized manual MapAuthoring Source edit; nothing changed")
local overview = map:FindFirstChild("EditorFieldOverview")
assert(overview and overview:IsA("Folder")
    and overview:GetAttribute("CornEditorOverview") == true
    and overview:GetAttribute("corn_project_id") == "children_of_corn"
    and overview:GetAttribute("OverviewSpacing") == 16,
    "Unrecognized EditorFieldOverview; nothing changed")
local storage = game:GetService("ServerStorage")
local named = storage:FindFirstChild("CornPlantTemplate")
local imported = storage:FindFirstChild("SM_Prop_Plant_Corn_01_L")
assert(not (named and imported), "Ambiguous corn source; nothing changed")
local source = named or imported
assert(source and (source:IsA("Model") or source:IsA("MeshPart")), "Imported corn source missing; nothing changed")
local sourceMesh = if source:IsA("MeshPart") then source else source:FindFirstChildWhichIsA("MeshPart", true)
assert(sourceMesh and sourceMesh:IsA("MeshPart"), "Imported corn MeshPart missing; nothing changed")
local parts = 0
local sourceItems = source:GetDescendants()
table.insert(sourceItems, source)
for _, item in sourceItems do
    assert(not item:IsA("LuaSourceContainer"), "Corn source contains code; nothing changed")
    if item:IsA("BasePart") then parts += 1 end
end
assert(parts == 1 and sourceMesh.Size.Y > 0, "Expected the single-mesh imported corn; nothing changed")
local target = sourceMesh.Size * (8 / sourceMesh.Size.Y)
local function close(a, b) return math.abs(a - b) < 0.001 end
local function matches(size, scaleXZ)
    return close(size.X, target.X * scaleXZ) and close(size.Y, target.Y)
        and close(size.Z, target.Z * scaleXZ)
end
local entries = {}
for _, item in overview:GetChildren() do
    assert(item:IsA("MeshPart") and item.Name == "DistantCorn"
        and item:GetAttribute("CornEditorOverview") == true
        and item:GetAttribute("corn_project_id") == "children_of_corn"
        and #item:GetChildren() == 0,
        "EditorFieldOverview contains manual or unowned objects; nothing changed")
    assert(item.MeshContent == sourceMesh.MeshContent and item.TextureContent == sourceMesh.TextureContent,
        "Overview corn mesh or texture was manually changed; nothing changed")
    assert(matches(item.Size, 6) or matches(item.Size, 1),
        "Overview corn has a custom Size; nothing changed")
    table.insert(entries, {item=item, size=item.Size, frame=item.CFrame, pivot=item.PivotOffset})
end
assert(#entries > 0 and #entries <= 6000, "Unexpected overview plant count; nothing changed")
local oldApproximation = overview:GetAttribute("OverviewApproximation")
local oldPlantScale = overview:GetAttribute("OverviewPlantScale")
local parent = author.Parent
local replacement = nil
local swapped = false
local history = game:GetService("ChangeHistoryService")
history:SetWaypoint("Before Corn proportion correction")
local ok, problem = pcall(function()
    if normalized(author.Source) ~= normalized(latestSource) then
        -- Replace only this validated leaf, avoiding Studio edit-mode require caches.
        replacement = author:Clone()
        assert(replacement, "MapAuthoring clone failed")
        replacement.Source = latestSource
        author.Parent = nil
        replacement.Parent = parent
        swapped = true
    end
    for _, entry in entries do
        entry.item.Size = target
        assert(entry.item.CFrame == entry.frame and entry.item.PivotOffset == entry.pivot,
            "Unexpected transform change while correcting corn Size")
    end
    overview:SetAttribute("OverviewApproximation", true)
    overview:SetAttribute("OverviewPlantScale", 1)
    history:SetWaypoint("Corrected Corn overview proportions")
end)
if not ok then
    for _, entry in entries do
        if entry.item.Size ~= entry.size then entry.item.Size = entry.size end
        if entry.item.CFrame ~= entry.frame then entry.item.CFrame = entry.frame end
        if entry.item.PivotOffset ~= entry.pivot then entry.item.PivotOffset = entry.pivot end
    end
    overview:SetAttribute("OverviewApproximation", oldApproximation)
    overview:SetAttribute("OverviewPlantScale", oldPlantScale)
    if replacement then replacement:Destroy() end
    if swapped or author.Parent == nil then author.Parent = parent end
    error("Corn proportion correction rolled back: " .. tostring(problem))
end
if swapped then author:Destroy() end
print("ChildrenOfCorn corn proportions fixed: " .. #entries
    .. " upright overview plants; sparse overview retained, dense detail uses 3-stud spacing; SAVE, then Play")
