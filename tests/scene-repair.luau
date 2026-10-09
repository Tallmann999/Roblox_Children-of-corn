-- Regression fixtures for the exact saved scene with its missing RoundSpawn.
-- Limited geometry + Player/Humanoid/signal stubs; NOT Roblox physics/rendering.
local adapter = require("./scene-adapter")
local fs, r, I, CF, V3 = adapter.fs, adapter.r, adapter.I, adapter.CF, adapter.V3
local original = fs.readFile("place/Children_of_corn.before-spawn-fix.rbxl")
local function setup()
    local place = r.deserializePlace(original)
    local install, load = adapter.runner(place, nil, "scripts/repair-corn-scene.luau")
    return place, install, load
end
local place, repair, load = setup()
local world = place:GetService("Workspace")
local map = world.CornMap
assert(not map:FindFirstChild("RoundSpawn"), "Regression fixture must contain the observed missing start")
local groundCF, gateCF = map.Ground.CFrame, map.EscapeGate.Door.CFrame
local houseCF = map.Props.HouseWest.Body.CFrame
local slotCF = map.KeySlots.solo_slot_01.CFrame
local source = place:GetService("ServerStorage").SM_Prop_Plant_Corn_01_L
local mesh = source.SM_Prop_Plant_Corn_01_L
local meshCF, meshSize = mesh.CFrame, mesh.Size
local meshUri, textureUri = mesh.MeshContent.Uri, mesh.TextureContent.Uri
-- Deliberately fill the old edit-mode require cache; repair must replace both modules.
local oldLayout = place:GetService("ReplicatedStorage").GameShared.Game.CornLayout
local oldAuthor = place:GetService("ServerScriptService").GameServer.Game.MapAuthoring
load(oldLayout)
load(oldAuthor)
local ok, problem = repair()
assert(ok, tostring(problem))
assert(map.Parent == world and map:GetAttribute("map_version") == 2)
assert(not world.SpawnLocation.Enabled)
assert(#map.CornerSpawns:GetChildren() == 4)
assert(map.Ground.CFrame == groundCF and map.EscapeGate.Door.CFrame == gateCF)
assert(map.Props.HouseWest.Body.CFrame == houseCF and map.KeySlots.solo_slot_01.CFrame == slotCF)
assert(mesh.CFrame == meshCF and mesh.Size == meshSize)
assert(mesh.MeshContent.Uri == meshUri and mesh.TextureContent.Uri == textureUri)
assert(oldLayout.Parent == nil and oldAuthor.Parent == nil)
assert(map.EditorFieldOverview:GetAttribute("PlantCount") > 5000)
assert(map.EditorPreview:GetAttribute("PlantCount") > 700)
local quadrants = {}
for _, item in map.EditorFieldOverview:GetChildren() do
    local p = item.CFrame.Position
    quadrants[(if p.X < 0 then "W" else "E") .. (if p.Z < 0 then "S" else "N")] = true
    assert(item:IsA("MeshPart") and item:GetAttribute("CornEditorOverview"))
    assert(not item.CanCollide and math.abs(item.Size.Y - 8) < 0.001)
    item.LocalTransparencyModifier = 0 -- inert Lune field; Roblox default is zero
end
assert(quadrants.WS and quadrants.WN and quadrants.ES and quadrants.EN)
print("PASS: observed missing-start scene repaired; 4 real corner starts; full overview; author art/geometry retained; require cache refreshed")
local gameCode = place:GetService("ServerScriptService").GameServer.Game
local AuthoredWorld = load(gameCode.AuthoredWorld)
local binding = AuthoredWorld.new(4, 15)
assert(#binding.Spawns == 4)
for index = 1, 4 do
    local spawn = binding:SelectSpawn(index)
    local p = binding:GetSpawnCFrame().Position
    assert(spawn:IsA("SpawnLocation") and spawn.Enabled and spawn.Neutral)
    assert(p.Y > 83 and binding:IsOnPlayground(p))
    assert(spawn.CFrame.UpVector:Dot(V3.yAxis) > 0.999)
    -- Actual inward look direction is part of Studio acceptance; Lune lookAt differs.

end
local function signal()
    return {Connect=function() return {Disconnect=function() end} end}
end
local snapshots = {}
local remote = {OnServerEvent=signal(), FireClient=function(_, _, data) table.insert(snapshots, data) end}
local context = {Config=load(place:GetService("ReplicatedStorage").GameShared.Config.GameConfig),
    Services={NetworkService={GetEvent=function() return remote end}},
    Log={Info=function() end, Warn=function() end}}
local SoloRound = load(gameCode.SoloRound)
local round = SoloRound.new(context)
round.world = binding
local physicalCharacter = I.new("Model")
physicalCharacter.Name = "FixtureCharacter"
physicalCharacter.Parent = world
local root = I.new("Part")
root.Name = "HumanoidRootPart"
root.CFrame = CF.new(0, 4, 0)
root.Parent = physicalCharacter
physicalCharacter.PrimaryPart = root
local humanoid = {Health=100, WalkSpeed=16, JumpPower=50, JumpHeight=7.2,
    AutoRotate=true, Died=signal(), IsA=function(_, name) return name == "Humanoid" end}
local character = {Parent=world, WaitForChild=function(_, name)
    return if name == "Humanoid" then humanoid else root
end, FindFirstChildOfClass=function() return humanoid end,
    FindFirstChild=function(_, name) return if name == "HumanoidRootPart" then root else nil end,
    PivotTo=function(_, frame) physicalCharacter:PivotTo(frame) end}
local player = {Parent=place:GetService("Players"), Character=character,
    CharacterAdded=signal(), CharacterRemoving=signal()}
round:_chooseSpawn()
round:_addPlayer(player)
assert(player.RespawnLocation == round.selectedSpawn)
assert(root.CFrame.Position.Y > 83 and humanoid.WalkSpeed == 0)
local corner = 0
round.random = {NextInteger=function(_, low, high)
    if high == 4 then corner = corner % 4 + 1; return corner end
    return low
end}
local visited = {}
for _ = 1, 4 do
    round:_startRound()
    assert(round.phase == "active", "Actual server start function did not reach active")
    assert(root.CFrame.Position.Y > 83 and humanoid.WalkSpeed == context.Config.CoreLoop.walk_speed)
    assert(player.RespawnLocation == round.selectedSpawn)
    visited[round.selectedSpawn] = true
    round:_finish("aborted", "corn_loop_result_aborted")
end
local visitedCount = 0
for _ in visited do visitedCount += 1 end
assert(visitedCount == 4)
round:_startRound()
round.gateOpen = true
binding:SetGateOpen(true)
character:PivotTo(binding.Exit.CFrame)
round:_poll(os.clock())
assert(round.phase == "escaped" and round.diamonds == 10)
round:_poll(os.clock())
assert(round.diamonds == 10)
round:_startRound()
assert(round.phase == "active" and round.diamonds == 10 and binding.GatePrompt.Enabled)
round:_finish("aborted", "corn_loop_result_aborted")
print("PASS: server menu/start/retry teleport above field, choose all 4 corners, set RespawnLocation; exit rewards once")
local Renderer = load(place:GetService("StarterPlayer").StarterPlayerScripts.GameClient.Controllers.CornController)
root.CFrame = CF.new(125, 83.65, -410)
root.Position = root.CFrame.Position
Renderer:_reconcile(root)
for _ = 1, 360 do
    local before = Renderer._plantCount
    Renderer:_createBatch()
    assert(Renderer._plantCount - before <= 18)
end
assert(Renderer._plantCount > 1800 and Renderer._plantCount <= 4032)
local hidden, visible = 0, 0
for _, item in map.EditorFieldOverview:GetChildren() do
    if item.LocalTransparencyModifier == 1 then hidden += 1 else visible += 1 end
end
assert(hidden > 0 and visible > 4000)
root.CFrame = CF.new(5000, 83.65, 5000)
root.Position = root.CFrame.Position
Renderer:_reconcile(root)
assert(Renderer._plantCount == 0)
Renderer:Destroy()
for _, item in map.EditorFieldOverview:GetChildren() do assert(item.LocalTransparencyModifier == 0) end
print("PASS: dense nearby corn and distant overview coexist; only completed detail hides coarse plants; unloading restores overview")
-- Re-run after an author move: no houses/gate/corners are reset.
map.CornerSpawns.SW.CFrame = CF.new(-510, 80.075, -510) * CF.Angles(0, -3 * math.pi / 4, 0)
map.CornerSpawns.SW.Position = map.CornerSpawns.SW.CFrame.Position
local cornerFrame = map.CornerSpawns.SW.CFrame
local repeatOk, repeatProblem = repair()
assert(repeatOk, tostring(repeatProblem))
assert(map.CornerSpawns.SW.CFrame == cornerFrame and map.Props.HouseWest.Body.CFrame == houseCF)
print("PASS: repeated repair keeps moved corners and author geometry")
local unsafe, unsafeRepair = setup()
local unsafeMap = unsafe:GetService("Workspace").CornMap
local preview = unsafeMap.EditorPreview
local unsafeSource = unsafe:GetService("ServerScriptService").GameServer.Game.SoloRound.Source
unsafeMap.PlayBounds.Size = V3.new(10, 50, 10)
assert(not unsafeRepair())
assert(unsafeMap.EditorPreview == preview and preview.Parent == unsafeMap)
assert(not unsafeMap:FindFirstChild("CornerSpawns") and not unsafeMap:FindFirstChild("EditorFieldOverview"))
assert(unsafe:GetService("Workspace").SpawnLocation.Enabled)
assert(unsafe:GetService("ServerScriptService").GameServer.Game.SoloRound.Source == unsafeSource)
print("PASS: unsafe start geometry rolls back sources/layers/legacy spawn")
local manual, manualRepair = setup()
local manualMap = manual:GetService("Workspace").CornMap
local manualObject = I.new("Part")
manualObject.Name = "HandPlacedProp"
manualObject.Parent = manualMap.EditorPreview
local manualSource = manual:GetService("ServerScriptService").GameServer.Game.SoloRound.Source
assert(not manualRepair())
assert(manualObject.Parent == manualMap.EditorPreview)
assert(manual:GetService("ServerScriptService").GameServer.Game.SoloRound.Source == manualSource)
assert(not manualMap:FindFirstChild("CornerSpawns"))
print("PASS: manual object inside preview refuses before mutations")
local wrong, wrongRepair = setup()
local speedMarker = I.new("Folder")
speedMarker.Name = "Asmr_Base"
speedMarker.Parent = wrong:GetService("Workspace")
assert(not wrongRepair())
assert(not wrong:GetService("Workspace").CornMap:FindFirstChild("CornerSpawns"))
print("PASS: repair refuses wrong game before changes")
