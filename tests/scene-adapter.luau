-- File-backed integration check using a limited Lune geometry adapter.
-- This does not run Roblox physics, rendering, networking or a Studio Play Test.
local fs = require("@lune/fs")
local r = require("@lune/roblox")
local I, CF, V3 = r.Instance, r.CFrame, r.Vector3
r.implementProperty("BasePart", "Position", function(p) return p.CFrame.Position end,
    function(p, pos) p.CFrame = CF.new(pos) * p.CFrame.Rotation end)
r.implementMethod("BasePart", "GetPivot", function(p) return p.CFrame * p.PivotOffset end)
r.implementMethod("BasePart", "PivotTo", function(p, frame) p.CFrame = frame * p.PivotOffset:Inverse() end)
local function parts(model)
    local result = {}
    for _, item in model:GetDescendants() do
        if item:IsA("BasePart") then table.insert(result, item) end
    end
    return result
end
r.implementMethod("Model", "GetPivot", function(m)
    local p = m.PrimaryPart or parts(m)[1]
    return if p then p:GetPivot() else CF.identity
end)
-- Lune lacks the optional editor WorldPivot default; geometry is checked separately.
r.implementMethod("Model", "PivotTo", function(m, frame)
    local delta = frame * m:GetPivot():Inverse()
    for _, p in parts(m) do p.CFrame = delta * p.CFrame; p.Position = p.CFrame.Position end
end)
r.implementMethod("Model", "GetScale", function(m) return m:GetAttribute("TestScale") or 1 end)
r.implementMethod("Model", "ScaleTo", function(m, scale)
    local ratio = scale / m:GetScale()
    local pivot = m:GetPivot()
    for _, p in parts(m) do
        local localFrame = pivot:ToObjectSpace(p.CFrame)
        p.CFrame = pivot * CF.new(localFrame.Position * ratio) * localFrame.Rotation
        p.Size *= ratio
        p.PivotOffset = CF.new(p.PivotOffset.Position * ratio) * p.PivotOffset.Rotation
    end
    m:SetAttribute("TestScale", scale)
end)
r.implementMethod("Model", "GetBoundingBox", function(m)
    local frame = m:GetPivot()
    local low = V3.new(math.huge, math.huge, math.huge)
    local high = -low
    for _, p in parts(m) do
        for _, x in {-1, 1} do for _, y in {-1, 1} do for _, z in {-1, 1} do
            local point = frame:PointToObjectSpace(p.CFrame:PointToWorldSpace(p.Size * V3.new(x, y, z) / 2))
            low = V3.new(math.min(low.X, point.X), math.min(low.Y, point.Y), math.min(low.Z, point.Z))
            high = V3.new(math.max(high.X, point.X), math.max(high.Y, point.Y), math.max(high.Z, point.Z))
        end end end
    end
    return frame * CF.new((low + high) / 2), high - low
end)
r.implementMethod("Instance", "WaitForChild", function(p, name) return assert(p:FindFirstChild(name), name) end)
r.implementMethod("RunService", "IsRunning", function() return false end)
r.implementMethod("RunService", "IsStudio", function() return true end)
r.implementMethod("ChangeHistoryService", "SetWaypoint", function() end)
r.implementMethod("CollectionService", "AddTag", function(_, item, tag) item:AddTag(tag) end)
r.implementMethod("CollectionService", "HasTag", function(_, item, tag) return item:HasTag(tag) end)
r.implementProperty("ProximityPrompt", "Triggered", function()
    return {Connect=function() return {Disconnect=function() end} end}
end)
local selection = {}
r.implementMethod("Selection", "Set", function(_, items) selection = items end)
r.implementMethod("Selection", "Get", function() return selection end)
local function runner(place, openScript, installerPath)
    local loaded = {}
    local collection = { AddTag = function(_, item, tag) item:AddTag(tag) end,
        HasTag = function(_, item, tag) return item:HasTag(tag) end }
    local editor = { FindScriptDocument = function(_, item)
        return if item == openScript then {} else nil
    end }
    local lightingProxy = {ClockTime=12.1, Brightness=0.5, Ambient=r.Color3.new(), OutdoorAmbient=r.Color3.new(), FogStart=0, FogEnd=1000, FogColor=r.Color3.new()}
    local gameProxy = { GetService = function(_, name)
        if name == "Lighting" then return lightingProxy end
        if name == "CollectionService" then return collection end
        if name == "ScriptEditorService" then return editor end
        return place:GetService(name)
    end, FindFirstChild = function(_, name) return place:FindFirstChild(name) end }
    local function moduleRequire(module)
        if loaded[module] ~= nil then return loaded[module] end
        local env = setmetatable({game=gameProxy, workspace=place:GetService("Workspace"), script=module, Instance=I, CFrame=CF,
            Vector3=V3, Vector2=r.Vector2, Color3=r.Color3, Enum=r.Enum, task={wait=function() end, spawn=function(fn) fn() end}, Random={new=function() return {NextInteger=function(_, low) return low end} end}}, {__index=getfenv()})
        env.require = moduleRequire
        local moduleSource = module.Source
        if module.Name == "MapAuthoring" then
            -- Lune has inert Position fields; emulate the engine coupling for this factory.
            local count
            moduleSource, count = moduleSource:gsub("item%.Position = position", "item.Position = position\nitem.CFrame = CFrame.new(position)")
            assert(count == 1)
        end
        if module.Name == "CornLayout" then
            moduleSource = moduleSource:gsub("item%.Position", "item.CFrame.Position")
        end
        if module.Name == "MapAuthoring" then
            moduleSource = moduleSource:gsub("field%.Position", "field.CFrame.Position")
            moduleSource = moduleSource:gsub("selected%.Position", "selected.CFrame.Position")
            moduleSource = moduleSource:gsub("spawn%.Position", "spawn.CFrame.Position")
        end
        if module.Name == "MapTuning" then
            for _, name in {"ground", "slot", "item", "p", "gateDoor", "map.CornerSpawns.SW"} do
                local pattern = name:gsub("%.", "%%.") .. "%.Position"
                moduleSource = moduleSource:gsub(pattern, name .. ".CFrame.Position")
            end
            -- The adapter checks restored part geometry, not the editor's optional pivot metadata.
            moduleSource = moduleSource:gsub("pivot = item%.WorldPivot", "pivot = item:GetPivot()")
            moduleSource = moduleSource:gsub("entry%.item%.WorldPivot = entry%.pivot", "-- optional editor pivot metadata is not emulated")
        end
        local fn = assert(loadstring(moduleSource, module:GetFullName()))
        setfenv(fn, env)
        local value = fn()
        loaded[module] = value
        return value
    end
    local function install()
        local source = fs.readFile(installerPath or "scripts/install-editable-scene.luau")
        source = source:gsub("selected%.Position", "selected.CFrame.Position")
        source = source:gsub("lowerSpawn%.Position", "lowerSpawn.CFrame.Position")
        source = source:gsub("field%.Position", "field.CFrame.Position")
        local fn = assert(loadstring(source))
        setfenv(fn, setmetatable({game=gameProxy, Instance=I, require=moduleRequire}, {__index=getfenv()}))
        return pcall(fn)
    end
    return install, moduleRequire
end

return {runner=runner, fs=fs, r=r, I=I, CF=CF, V3=V3}
