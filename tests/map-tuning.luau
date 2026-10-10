local adapter = require("./scene-adapter")
local fs, r = adapter.fs, adapter.r
local bytes = fs.readFile("place/Children_of_corn.before-map-tuning-20261010.rbxl")
local p = r.deserializePlace(bytes)
local map = p:GetService("Workspace").CornMap
local art = p:GetService("ServerStorage").SM_Prop_Plant_Corn_01_L
local mesh = art:FindFirstChildWhichIsA("MeshPart", true)
local artSize, artFrame = mesh.Size, mesh.CFrame
local unrelated = p:GetService("Workspace").Baseplate
local baseSize, baseFrame = unrelated.Size, unrelated.CFrame
local houseSize = map.Props.HouseWest.Body.Size
local apply = adapter.runner(p, nil, "scripts/install-hunt.luau")
local ok, result = apply()
assert(ok, tostring(result))
assert(map.FieldZone.Size.X == 840 and map.FieldZone.Size.Z == 840)
assert(#map.TorchMarkers:GetChildren() == 21)
assert(map:GetAttribute("TorchClearanceVersion") == 1)
assert(map.Props.HouseWest.Body.Size == houseSize)
assert(mesh.Size == artSize and mesh.CFrame == artFrame)
assert(unrelated.Size == baseSize and unrelated.CFrame == baseFrame)
local count = #map.EditorFieldOverview:GetChildren()
assert(count < 5500 and count > 4000)
assert(apply())
assert(#map.EditorFieldOverview:GetChildren() == count, "Repeat rebuilt author map")
print("PASS: 840 field, 21 torches, human-size houses, imported art/unrelated Baseplate retained; repeat keeps map")
local _, moduleRequire = adapter.runner(p)
local layout = moduleRequire(p:GetService("ReplicatedStorage").GameShared.Game.CornLayout)
for row = -40, 40 do
    for column = -40, 40 do
        local shift = layout.CellPosition(map.FieldZone, column, row) - layout.BaseCellPosition(map.FieldZone, column, row)
        assert(math.abs(shift.X) <= 0.3001 and math.abs(shift.Z) <= 0.3001)
        local degrees = math.abs(math.deg(layout.CellYaw(column, row)))
        assert(degrees >= 10 and degrees <= 30)
        local difference = math.abs(layout.HeightFactor(column, row) - 1)
        assert(difference >= 0.09999 and difference <= 0.15001)
        assert(layout.CellPosition(map.FieldZone, column, row) == layout.CellPosition(map.FieldZone, column, row))
    end
end
print("PASS: 6561 deterministic cells satisfy position, yaw and height ranges")

local failure = fs.readFile("scripts/install-hunt.luau")
local inject = '    resolve("ServerScriptService/GameServer/Game/MapTuning").Source = resolve("ServerScriptService/GameServer/Game/MapTuning").Source:gsub("Authoring%%.RebuildOverview%%(map%%)", \'error("Injected world failure")\')\n'
inject = inject:gsub("%%%%", "%%")
failure = failure:gsub('    if map:GetAttribute%("MapTuningVersion"%)==nil then', function(text) return inject .. text end)
fs.writeFile("build/map-tuning-failure.luau", failure)
local rolled = r.deserializePlace(bytes)
local saved = {}
for _, item in rolled:GetDescendants() do
    if item:IsA("BasePart") then saved[item] = {frame=item.CFrame, size=item.Size, parent=item.Parent}
    elseif item:IsA("LuaSourceContainer") then saved[item] = {source=item.Source, parent=item.Parent} end
end
local failed = adapter.runner(rolled, nil, "build/map-tuning-failure.luau")
local failedOk, failureReason = failed()
assert(not failedOk, "Injected failure did not fail")
assert(tostring(failureReason):find("Injected world failure", 1, true), tostring(failureReason))
for item, state in saved do
    assert(item.Parent == state.parent, "Parent was not restored: " .. item.Name)
    if state.frame then
        assert((item.CFrame.Position-state.frame.Position).Magnitude < 0.0001
            and (item.CFrame.RightVector-state.frame.RightVector).Magnitude < 0.0001
            and (item.CFrame.UpVector-state.frame.UpVector).Magnitude < 0.0001
            and (item.Size-state.size).Magnitude < 0.0001, "Geometry was not restored: " .. item:GetFullName())
    else assert(item.Source == state.source) end
end
assert(not rolled:GetService("Workspace").CornMap:FindFirstChild("TorchMarkers"))
assert(rolled:GetService("Workspace").CornMap:GetAttribute("MapTuningVersion") == nil)
print("PASS: injected world failure restores old layers, all authored part properties and original code")

local wrong = r.deserializePlace(bytes)
local otherGame = r.Instance.new("Folder")
otherGame.Name = "Asmr_Base"; otherGame.Parent = wrong:GetService("Workspace")
local wrongOk, wrongReason = adapter.runner(wrong, nil, "scripts/install-hunt.luau")()
assert(not wrongOk and tostring(wrongReason):find("Wrong game",1,true))
assert(wrong:GetService("Workspace").CornMap.FieldZone.Size.X == 1200)
assert(not wrong:GetService("ServerScriptService").GameServer.Game:FindFirstChild("MonsterHunt"))

local manual = r.deserializePlace(bytes)
local manualModule = manual:GetService("ServerScriptService").GameServer.Game.SoloRound
manualModule.Source = "-- Author's unknown manual edit"
local manualOk, manualReason = adapter.runner(manual, nil, "scripts/install-hunt.luau")()
assert(not manualOk and tostring(manualReason):find("Manual Source edit",1,true))
assert(manualModule.Source == "-- Author's unknown manual edit")
assert(manual:GetService("Workspace").CornMap.FieldZone.Size.X == 1200)
print("PASS: wrong game and unknown manual Source rejected before any map/code mutation")
