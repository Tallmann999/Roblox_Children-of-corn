-- File-backed proportion regression fixtures, using the limited Lune geometry adapter.
-- No Roblox renderer, physics, networking, live Studio, or place-file writes.
local adapter = require("./scene-adapter")
local fs, r, I, CF, V3 = adapter.fs, adapter.r, adapter.I, adapter.CF, adapter.V3
local original = fs.readFile("place/Children_of_corn.before-proportion-fix.rbxl")
local function setup(openTab)
    local place = r.deserializePlace(original)
    local author = place:GetService("ServerScriptService").GameServer.Game.MapAuthoring
    local install, load = adapter.runner(place, if openTab then author else nil, "scripts/fix-corn-proportions.luau")
    return place, install, load
end
local function snapshot(place)
    local frames, sizes, sources = {}, {}, {}
    for _, item in place:GetDescendants() do
        if item:IsA("BasePart") then
            frames[item] = {frame=item.CFrame, pivot=item.PivotOffset}
            sizes[item] = item.Size
        elseif item:IsA("LuaSourceContainer") then sources[item] = item.Source end
    end
    return {frames=frames, sizes=sizes, sources=sources}
end
local function unchanged(place, before, sizeExcept, sourceExcept)
    for item, entry in before.frames do
        assert(item.CFrame == entry.frame and item.PivotOffset == entry.pivot,
            "Moved author geometry: " .. item:GetFullName())
        if not sizeExcept or item.Parent ~= sizeExcept then
            assert((item.Size - before.sizes[item]).Magnitude < 0.00001, "Changed unrelated size: " .. item:GetFullName())
        end
    end
    for item, source in before.sources do
        if item ~= sourceExcept then
            assert(item.Source == source and item.Parent, "Changed unrelated code: " .. item.Name)
        end
    end
end
local place, fix, load = setup()
local map = place:GetService("Workspace").CornMap
local overview = map.EditorFieldOverview
local source = place:GetService("ServerStorage").SM_Prop_Plant_Corn_01_L.SM_Prop_Plant_Corn_01_L
local target = source.Size * (8 / source.Size.Y)
local oldAuthor = place:GetService("ServerScriptService").GameServer.Game.MapAuthoring
local cachedAuthor = load(oldAuthor)
assert(cachedAuthor.RebuildOverview and oldAuthor.Source:find("prepared.Size.X * 6", 1, true))
-- Deliberate author movement must survive the correction along with the already saved map shift.
local moved = overview:GetChildren()[1]
moved.CFrame = moved.CFrame * CF.new(1, 2, -3) * CF.Angles(0, 0.2, 0)
local before = snapshot(place)
local count = #overview:GetChildren()
local ok, problem = fix()
assert(ok, tostring(problem))
assert(#overview:GetChildren() == count and count > 5000)
for _, item in overview:GetChildren() do
    assert((item.Size - target).Magnitude < 0.001, "Overview retained stretched proportions")
end
unchanged(place, before, overview, oldAuthor)
local newAuthor = place:GetService("ServerScriptService").GameServer.Game.MapAuthoring
assert(newAuthor ~= oldAuthor and oldAuthor.Parent == nil)
assert(not newAuthor.Source:find("prepared.Size.X * 6", 1, true))
assert(load(newAuthor) ~= cachedAuthor, "Edit require cache was not refreshed")
assert(overview:GetAttribute("OverviewApproximation") == true)
assert(overview:GetAttribute("OverviewPlantScale") == 1)
assert(fs.readFile("place/Children_of_corn.before-proportion-fix.rbxl") == original)
print("PASS: exact saved scene corrected in place; every CFrame/PivotOffset, original art and unrelated geometry/code retained; module cache refreshed")
local repeatBefore = snapshot(place)
assert(fix())
assert(place:GetService("ServerScriptService").GameServer.Game.MapAuthoring == newAuthor)
unchanged(place, repeatBefore)
print("PASS: repeated correction is idempotent and retains manual moves")
-- Newly rebuilt overviews must also use the original aspect ratio.
local author = load(newAuthor)
local rebuilt = author.RebuildOverview(map)
assert(rebuilt > 5000 and rebuilt <= 6000)
for _, item in map.EditorFieldOverview:GetChildren() do
    assert((item.Size - target).Magnitude < 0.001, "Future overview rebuild stretches source art")
end
print("PASS: future MapAuthoring overview rebuild keeps correct proportions and bounded sparse count")
local function refuses(mutate, openTab)
    local other, install = setup(openTab)
    local otherMap = other:GetService("Workspace").CornMap
    mutate(other, otherMap)
    local beforeRefusal = snapshot(other)
    local module = other:GetService("ServerScriptService").GameServer.Game.MapAuthoring
    local layer = otherMap.EditorFieldOverview
    local ok = install()
    assert(not ok, "Unsafe correction unexpectedly accepted")
    assert(module == other:GetService("ServerScriptService").GameServer.Game.MapAuthoring)
    assert(layer == otherMap.EditorFieldOverview)
    unchanged(other, beforeRefusal)
end
refuses(function(other)
    local marker = I.new("Folder")
    marker.Name = "Asmr_Base"
    marker.Parent = other:GetService("Workspace")
end)
refuses(function(_, otherMap)
    local plant = otherMap.EditorFieldOverview:GetChildren()[1]
    plant.Size = V3.new(4, 8, 4)
end)
refuses(function(other)
    local module = other:GetService("ServerScriptService").GameServer.Game.MapAuthoring
    module.Source ..= "\n-- author edit"
end)
refuses(function() end, true)
refuses(function(_, otherMap)
    otherMap.EditorFieldOverview:SetAttribute("CornEditorOverview", false)
end)
refuses(function(_, otherMap)
    local marker = I.new("Part")
    marker.Name = "HandPlacedProp"
    marker.Parent = otherMap.EditorFieldOverview
end)
refuses(function(_, otherMap)
    local marker = I.new("Folder")
    marker.Name = "HandPlacedChild"
    marker.Parent = otherMap.EditorFieldOverview:GetChildren()[1]
end)
refuses(function(other)
    local module = other:GetService("ServerScriptService").GameServer.Game.MapAuthoring
    local marker = I.new("Folder")
    marker.Name = "HandPlacedChild"
    marker.Parent = module
end)
print("PASS: wrong game, custom Size/Source, open script tab, unowned layer and manual extra children refuse before changes")
-- Failure after mutation must restore the exact old module, sizes and annotations.
local failed = setup()
local failedMap = failed:GetService("Workspace").CornMap
local failedAuthor = failed:GetService("ServerScriptService").GameServer.Game.MapAuthoring
local failedBefore = snapshot(failed)
local failingHistory = {SetWaypoint=function(_, label)
    if label == "Corrected Corn overview proportions" then error("Fixture transaction failure") end
end}
local failureProxy = {GetService=function(_, name)
    if name == "ChangeHistoryService" then return failingHistory end
    if name == "ScriptEditorService" then return {FindScriptDocument=function() return nil end} end
    return failed:GetService(name)
end, FindFirstChild=function(_, name) return failed:FindFirstChild(name) end}
local failureFn = assert(loadstring(fs.readFile("scripts/fix-corn-proportions.luau")))
setfenv(failureFn, setmetatable({game=failureProxy, Instance=I}, {__index=getfenv()}))
local failureOk, failureProblem = pcall(failureFn)
assert(not failureOk and tostring(failureProblem):find("rolled back", 1, true))
assert(failed:GetService("ServerScriptService").GameServer.Game.MapAuthoring == failedAuthor)
assert(failedMap.EditorFieldOverview:GetAttribute("OverviewApproximation") == nil)
assert(failedMap.EditorFieldOverview:GetAttribute("OverviewPlantScale") == nil)
unchanged(failed, failedBefore)
print("PASS: post-mutation failure rolls back module, all sizes/frames/pivots and overview annotations")
