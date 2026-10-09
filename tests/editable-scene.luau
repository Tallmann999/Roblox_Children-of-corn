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
local selection = {}
r.implementMethod("Selection", "Set", function(_, items) selection = items end)
r.implementMethod("Selection", "Get", function() return selection end)
local function runner(place, openScript)
    local loaded = {}
    local collection = { AddTag = function(_, item, tag) item:AddTag(tag) end,
        HasTag = function(_, item, tag) return item:HasTag(tag) end }
    local editor = { FindScriptDocument = function(_, item)
        return if item == openScript then {} else nil
    end }
    local gameProxy = { GetService = function(_, name)
        if name == "CollectionService" then return collection end
        if name == "ScriptEditorService" then return editor end
        return place:GetService(name)
    end, FindFirstChild = function(_, name) return place:FindFirstChild(name) end }
    local function moduleRequire(module)
        if loaded[module] ~= nil then return loaded[module] end
        local env = setmetatable({game=gameProxy, script=module, Instance=I, CFrame=CF,
            Vector3=V3, Vector2=r.Vector2, Color3=r.Color3, Enum=r.Enum}, {__index=getfenv()})
        env.require = moduleRequire
        local moduleSource = module.Source
        if module.Name == "MapAuthoring" then
            -- Lune has inert Position fields; emulate the engine coupling for this factory.
            local count
            moduleSource, count = moduleSource:gsub("item%.Position = position", "item.Position = position\nitem.CFrame = CFrame.new(position)")
            assert(count == 1)
        end
        local fn = assert(loadstring(moduleSource, module:GetFullName()))
        setfenv(fn, env)
        local value = fn()
        loaded[module] = value
        return value
    end
    local function install()
        local fn = assert(loadstring(fs.readFile("scripts/install-editable-scene.luau")))
        setfenv(fn, setmetatable({game=gameProxy, Instance=I, require=moduleRequire}, {__index=getfenv()}))
        return pcall(fn)
    end
    return install, moduleRequire
end
local original = fs.readFile("place/Children_of_corn.before-editable.rbxl")
local place = r.deserializePlace(original)
local source = place:GetService("ServerStorage").SM_Prop_Plant_Corn_01_L
local mesh = source.SM_Prop_Plant_Corn_01_L
local initialSize, initialFrame = mesh.Size, mesh.CFrame
local meshUri, textureUri = mesh.MeshContent.Uri, mesh.TextureContent.Uri
local install, loadModule = runner(place)
local ok, err = install()
assert(ok, tostring(err))
local map = place:GetService("Workspace").CornMap
assert(map.Ground.Size.X == 1200 and map.Ground.Size.Z == 1200)
assert(map.FieldZone.Size.X == 1200 and map.FieldZone.Position.Y == 85)
assert(#map.KeySlots:GetChildren() == 15)
assert(map.EditorPreview:GetAttribute("PlantCount") > 300 and map.EditorPreview:GetAttribute("PlantCount") < 1000)
assert(mesh.Size == initialSize and mesh.CFrame == initialFrame)
assert(mesh.MeshContent.Uri == meshUri and mesh.TextureContent.Uri == textureUri)
assert(source.Parent == place:GetService("ServerStorage"))
assert(place:GetService("Workspace"):FindFirstChild("Baseplate"))
print("PASS: install creates 1200 map + preview; imported source and existing world retained")
local authoring = place:GetService("ServerScriptService").GameServer.Game
local World = loadModule(authoring.AuthoredWorld)
local binding = World.new(4, 15)
assert(binding:IsValid())
binding:SpawnKey(binding.Slots[1])
assert(binding.Key and binding.KeyPrompt)
binding:ClearKey()
assert(not binding.Key and map.Parent == place:GetService("Workspace"))
binding:SetGateOpen(true)
assert(not binding.Gate.CanCollide)
binding:SetGateOpen(false)
assert(binding.Gate.CanCollide and binding.Gate.Transparency == 0)
map.EscapeGate:PivotTo(CF.new(210, 89, 400) * CF.Angles(0, math.pi / 2, 0))
local front = binding.Gate.CFrame:PointToWorldSpace(V3.new(0, 0, -6))
local back = binding.Gate.CFrame:PointToWorldSpace(V3.new(0, 0, 6))
assert(binding:IsGateFront(front) and not binding:IsGateFront(back))
assert(binding:IsInExit(binding.Exit.Position))
assert(not binding:IsInExit(binding.Exit.CFrame:PointToWorldSpace(V3.new(7, 0, 0))))
map.RoundSpawn.CFrame = CF.new(125, 80.075, -410) * CF.Angles(0, math.pi / 2, 0)
assert(math.abs(binding:GetSpawnCFrame().Position.X - 125) < 0.001)
assert(binding:IsOnPlayground(binding:GetSpawnCFrame().Position))
print("PASS: key cleanup retains map; rotated gate/exit and moved spawn use authored coordinates")
local moved = map.EscapeGate.Door.CFrame
assert(install())
assert(map.EscapeGate.Door.CFrame == moved, "Reinstall overwrote manual edits")
print("PASS: repeat install preserves authored changes")
local wrong = I.new("DataModel")
local marker = I.new("Folder")
marker.Name = "Asmr_Base"
marker.Parent = wrong:GetService("Workspace")
local wrongInstall = runner(wrong)
local beforeWrong = #wrong:GetDescendants()
assert(not wrongInstall())
-- The guarded read creates RunService only; it creates no Corn code or map.
assert(not wrong:GetService("Workspace"):FindFirstChild("CornMap"))
assert(not wrong:GetService("ReplicatedStorage"):FindFirstChild("GameShared"))
assert(marker.Parent == wrong:GetService("Workspace"))
print("PASS: installer refuses Speed Monkey before source/world changes")
local changed = r.deserializePlace(original)
local config = changed:GetService("ReplicatedStorage").GameShared.Config.GameConfig
config.Source ..= "\n-- manual edit"
local changedInstall = runner(changed)
assert(not changedInstall())
assert(not changed:GetService("Workspace"):FindFirstChild("CornMap"))
assert(config.Source:find("manual edit", 1, true))
print("PASS: changed source refuses installation without overwriting it")
local extra = r.deserializePlace(original)
local extraGame = extra:GetService("ServerScriptService").GameServer.Game
local extraSource = extraGame.SoloRound.Source
local child = I.new("Folder")
child.Name = "ManualNotes"
child.Parent = extraGame.GreyboxWorld
local extraInstall = runner(extra)
assert(not extraInstall())
assert(child.Parent == extraGame.GreyboxWorld)
assert(extraGame.SoloRound.Source == extraSource)
assert(not extra:GetService("Workspace"):FindFirstChild("CornMap"))
print("PASS: legacy module with extra objects refuses before any source/world changes")
local editing = r.deserializePlace(original)
local openScript = editing:GetService("ServerScriptService").GameServer.Game.SoloRound
local openSource = openScript.Source
local editingInstall = runner(editing, openScript)
assert(not editingInstall())
assert(openScript.Source == openSource)
assert(not editing:GetService("Workspace"):FindFirstChild("CornMap"))
assert(not openScript.Parent:FindFirstChild("MapAuthoring"))
print("PASS: open script editor refuses before any source/world changes")
local broken = r.deserializePlace(original)
local code = broken:GetService("ServerScriptService").GameServer.Game.SoloRound.Source
broken:GetService("ServerStorage").SM_Prop_Plant_Corn_01_L.SM_Prop_Plant_Corn_01_L:Destroy()
local brokenInstall = runner(broken)
assert(not brokenInstall())
assert(not broken:GetService("Workspace"):FindFirstChild("CornMap"))
assert(broken:GetService("ServerScriptService").GameServer.Game.SoloRound.Source == code)
assert(broken:GetService("ServerScriptService").GameServer.Game:FindFirstChild("GreyboxWorld"))
assert(not broken:GetService("ServerScriptService").GameServer.Game:FindFirstChild("MapAuthoring"))
print("PASS: art preparation failure rolls back code and leaves original map untouched")


local client = place:GetService("StarterPlayer").StarterPlayerScripts.GameClient
local Renderer = loadModule(client.Controllers.CornController)
local renderRoot = I.new("Part")
renderRoot.CFrame = CF.new(125, 83.65, -410)
renderRoot.Position = renderRoot.CFrame.Position
Renderer:_reconcile(renderRoot)
for _ = 1, 140 do
    local beforeBatch = Renderer._plantCount
    Renderer:_createBatch()
    assert(Renderer._plantCount - beforeBatch <= 18, "Exceeded creation budget")
end
local chunks = 0
for _ in Renderer._chunks do chunks += 1 end
assert(chunks <= 28 and Renderer._plantCount > 0 and Renderer._plantCount <= 1792)
local artFolder = place:GetService("ReplicatedStorage").CornRuntimeArt
local artTemplate = artFolder.CornPlantTemplate
local _, artSize = loadModule(place:GetService("ReplicatedStorage").GameShared.Game.CornLayout).Bounds(artTemplate)
assert(math.abs(artSize.Y - 8) < 0.001)
local preparedMesh = artTemplate.SM_Prop_Plant_Corn_01_L
assert(preparedMesh.DoubleSided and not mesh.DoubleSided)
assert(preparedMesh.MeshContent.Uri == meshUri and preparedMesh.TextureContent.Uri == textureUri)
renderRoot.CFrame = CF.new(5000, 83.65, 5000)
renderRoot.Position = renderRoot.CFrame.Position
Renderer:_reconcile(renderRoot)
assert(Renderer._plantCount == 0, "Far chunks were retained")
Renderer:Destroy()
assert(map.Parent == place:GetService("Workspace") and map.Props:FindFirstChild("HouseWest"))
print("PASS: corn normalized to height 8; creation/chunk limits and unloading; author Props retained")
