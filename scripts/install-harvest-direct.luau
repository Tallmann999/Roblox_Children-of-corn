-- Generated guarded Harvest code-only installer. Input is the exact JSON payload string.
return function(raw)
local run = game:GetService("RunService")
assert(run:IsStudio() and run:IsEdit() and not run:IsRunning(), "Stop Play before Harvest code installation")
local world = game:GetService("Workspace")
for _, name in { "Asmr_Base", "ASMR_Models", "Cooking_Cheff", "SpeedMonkey", "New_+1 speed monkey" } do
    assert(not world:FindFirstChild(name), "Foreign game root; nothing changed: " .. name)
end
local map = world:FindFirstChild("CornMap")
assert(map and map:IsA("Model") and map:GetAttribute("corn_project_id") == "children_of_corn", "Open owned Children_of_corn; nothing changed")
local ground, field = map:FindFirstChild("Ground"), map:FindFirstChild("FieldZone")
assert(ground and ground:IsA("BasePart") and ground.Size == Vector3.new(630, 2, 630), "Expected accepted 630 Ground; nothing changed")
assert(field and field:IsA("BasePart") and field.Size == Vector3.new(630, 10, 630), "Expected accepted 630 FieldZone; nothing changed")
for _, name in { "Runtime", "CornRoundRuntime", "CornClientPlants", "CornClientBackdrop" } do
    assert(not map:FindFirstChild(name), "Runtime exists; nothing changed: " .. name)
end
assert(not game:GetService("ReplicatedStorage"):FindFirstChild("CornRuntimeArt"), "Runtime art exists; nothing changed")
local encoding = game:GetService("EncodingService")
local function rawDigest(value)
    local raw = encoding:ComputeStringHash(value, Enum.HashAlgorithm.Sha256)
    return (string.gsub(raw, ".", function(byte) return string.format("%02x", string.byte(byte)) end))
end
local function digest(value)
    return rawDigest((string.gsub(value, "\r\n", "\n")))
end
assert(type(raw) == "string" and rawDigest(raw) == "0ab19ed60dd76e3440e1b08489092bc19b3bdb5e239de17723cdd0a743d491ec", "Harvest payload SHA256 mismatch; nothing changed")
local payload = game:GetService("HttpService"):JSONDecode(raw)
assert(payload.version == 1 and payload.owner == "harvest_warden_v1" and payload.baselineSha256 == "b5084774be98e97a045c6b90a819bdd061b8d4f61b259c3a6e4eb77233ff2646", "Unknown Harvest payload; nothing changed")
local function uniqueChild(parent, name)
    local found = nil
    for _, child in parent:GetChildren() do
        if child.Name == name then assert(not found, "Duplicate instance name; nothing changed: " .. name) found = child end
    end
    return found
end
local function resolve(path)
    local item = game
    for _, name in string.split(path, "/") do item = item and uniqueChild(item, name) end
    return item
end
local function pathOf(item)
    local names = {}
    while item and item ~= game do table.insert(names, 1, item.Name) item = item.Parent end
    assert(item == game, "Detached code instance; nothing changed")
    return table.concat(names, "/")
end
local editor = game:GetService("ScriptEditorService")
local byPath, baseline, final = {}, true, true
for _, entry in payload.entries do
    assert(not byPath[entry.path], "Duplicate payload Source binding; nothing changed")
    byPath[entry.path] = entry
    assert(not entry.source or digest(entry.source) == entry.after, "Payload Source hash differs; nothing changed")
    local item = resolve(entry.path)
    if item then
        assert(item.ClassName == entry.class, "Source class collision; nothing changed: " .. entry.path)
        assert(not editor:FindScriptDocument(item), "Close script tab; nothing changed: " .. entry.path)
        local hash = digest(item.Source)
        baseline = baseline and entry.before ~= nil and hash == entry.before
        final = final and hash == entry.after
    else
        assert(entry.before == nil, "Missing original Source; nothing changed: " .. entry.path)
        final = false
    end
end
for path, class in payload.classes do
    local item = resolve(path)
    if item then
        assert(item.ClassName == class, "Code class collision; nothing changed: " .. path)
        baseline = baseline and payload.beforeClasses[path] == class
    else
        assert(not payload.beforeClasses[path], "Missing original code container; nothing changed: " .. path)
        final = false
    end
end
for _, prefix in payload.roots do
    local root = assert(resolve(prefix), "Missing owned code root; nothing changed")
    for _, item in root:GetDescendants() do
        local path = pathOf(item)
        assert(payload.classes[path] == item.ClassName and resolve(path) == item, "Unexpected code topology; nothing changed: " .. path)
    end
end
local sourceCount = 0
for _, item in game:GetDescendants() do
    if item:IsA("LuaSourceContainer") then
        local path = pathOf(item)
        assert(byPath[path] and resolve(path) == item, "Unexpected persistent Source; nothing changed: " .. path)
        sourceCount += 1
    end
end
assert(baseline or final, "Unknown Source edits or partial Harvest install; nothing changed")
assert(sourceCount == (if baseline then 80 else #payload.entries), "Persistent Source count differs; nothing changed")
if final then return { changed = 0, created = 0, totalSources = #payload.entries, repeated = true } end
local history = game:GetService("ChangeHistoryService")
history:SetWaypoint("Before Corn Harvest art code")
local changed, created = {}, {}
local ok, problem = pcall(function()
    for _, row in payload.addedNodes do
        assert(not resolve(row.path), "Added node appeared; rollback: " .. row.path)
        local parent = assert(resolve(string.match(row.path, "^(.*)/[^/]+$")))
        local item = Instance.new(row.class)
        table.insert(created, item)
        item.Name = string.match(row.path, "[^/]+$")
        local entry = byPath[row.path]
        if entry then item.Source = assert(entry.source) end
        item.Parent = parent
    end
    for _, entry in payload.entries do
        if entry.before and entry.source then
            local item = assert(resolve(entry.path))
            assert(digest(item.Source) == entry.before, "Original Source changed; rollback: " .. entry.path)
            table.insert(changed, { item = item, source = item.Source })
            item.Source = entry.source
        end
    end
    for _, entry in payload.entries do
        local item = assert(resolve(entry.path))
        assert(digest(item.Source) == entry.after, "Final Source verification failed; rollback: " .. entry.path)
    end
    for path, class in payload.classes do assert(resolve(path).ClassName == class, "Final code topology differs; rollback") end
end)
if not ok then
    for index = #changed, 1, -1 do changed[index].item.Source = changed[index].source end
    for index = #created, 1, -1 do created[index]:Destroy() end
    error("Harvest code update rolled back: " .. tostring(problem))
end
history:SetWaypoint("Installed Corn Harvest art code")
return { changed = #changed, created = #created, totalSources = #payload.entries, repeated = false }
end
