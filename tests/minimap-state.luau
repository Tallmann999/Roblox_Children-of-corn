-- Server state/ordering tests with real saved map geometry and a limited Lune adapter.
-- Does not run Studio networking, physics or humanoid event scheduling.
local adapter = require("./scene-adapter")
local fs, r = adapter.fs, adapter.r
local V3, CF = r.Vector3, r.CFrame
local function loadSource(path, env)
    local fn = assert(loadstring(fs.readFile(path), path))
    setfenv(fn, setmetatable(env, {__index=getfenv()}))
    return fn()
end
local Geometry = loadSource("src/shared/Game/MinimapGeometry.luau", {Vector3=V3, Vector2=r.Vector2})
local function node(name)
    return {Name=name, WaitForChild=function(_, child) return node(child) end}
end
local fakeGame = {GetService=function(_, name) return node(name) end}
local State = loadSource("src/server/Game/MinimapState.luau", {game=fakeGame, Vector3=V3, require=function() return Geometry end})
assert(State.PollInterval == 0.1)
local place = r.deserializePlace(fs.readFile("place/Children_of_corn.rbxl"))
local map = place:GetService("Workspace").CornMap
local world = {Root=map, Field={Position=map.FieldZone.CFrame.Position}, Slots={}}
local function slotProxy(part)
    return setmetatable({}, {__index=function(_, key)
        if key == "Position" then return part.CFrame.Position end
        if key == "IsDescendantOf" then return function(_, root) return part:IsDescendantOf(root) end end
        if key == "HasTag" then return function(_, tag) return part:HasTag(tag) end end
        if key == "GetAttribute" then return function(_, name) return part:GetAttribute(name) end end
    end})
end
for _, part in map.KeySlots:GetChildren() do table.insert(world.Slots, slotProxy(part)) end
assert(#world.Slots == 15)
local state = State.new()
assert(state:Snapshot().round_id == 0 and #state:Snapshot().visited == 0)
state:ResetHistory()
for _, slot in world.Slots do
    assert(state:Poll(world, V3.new(slot.Position.X, world.Field.Position.Y, slot.Position.Z)))
end
assert(#state:Snapshot().visited == 15)
for _, name in {"HouseWest", "HouseEast", "HouseNorthWest"} do
    local frame = map.Props[name]:GetBoundingBox()
    assert(state:Poll(world, frame.Position))
end
assert(#state:Snapshot().visited == 18)
for _, slot in world.Slots do state:Poll(world, V3.new(slot.Position.X, world.Field.Position.Y, slot.Position.Z)) end
assert(#state:Snapshot().visited == 18, "Repeated visit created duplicates")
local snapshots = state:Snapshot()
snapshots.visited[1].id = "tampered"
snapshots.visited[1].position = V3.zero
assert(state:Snapshot().visited[1].id ~= "tampered", "Snapshot aliases internal history")
for key in state:Snapshot() do assert(key=="round_id" or key=="visited" or key=="deaths", "Hidden gameplay field leaked") end
-- Empty props isolate clearing boundary/vertical tests. Slot geometry is moved at runtime.
local markerFrame = CF.new(100, 0, 100)
local marker = {
    IsDescendantOf=function() return true end, HasTag=function() return true end,
    GetAttribute=function() return "test" end,
}
setmetatable(marker, {__index=function(_, key) if key=="Position" then return markerFrame.Position end end})
local isolated = {Field={Position=V3.zero}, Slots={marker}, Root={FindFirstChild=function() return nil end}}
state:ResetHistory()
assert(not state:Poll(isolated, V3.new(109.001, 0, 100)))
assert(not state:Poll(isolated, V3.new(100, 12.001, 100)))
assert(state:Poll(isolated, V3.new(109, 12, 100)))
assert(#state:Snapshot().visited==1)
state:ResetHistory()
markerFrame=CF.new(200, 0, 200)
assert(not state:Poll(isolated, V3.new(100, 0, 100)), "Old clearing position retained")
assert(state:Poll(isolated, V3.new(200, 0, 200)))
assert(state:Snapshot().visited[1].position==markerFrame.Position)
-- Rotated and relocated house bounds: one house identity, independent of its two torches.
local houseFrame = CF.new(50, 7, 50) * CF.Angles(0, math.rad(37), 0)
local houseSize = V3.new(20, 14, 24)
local house = {
    IsA=function(_, class) return class=="Model" end,
    FindFirstChildWhichIsA=function() return true end,
    GetBoundingBox=function() return houseFrame, houseSize end,
}
local props = {FindFirstChild=function(_, name) return if name=="HouseWest" then house else nil end}
local houseWorld = {Field={Position=V3.zero}, Slots={}, Root={FindFirstChild=function() return props end}}
state:ResetHistory()
assert(not state:Poll(houseWorld, houseFrame:PointToWorldSpace(V3.new(13.001, 0, 0))))
assert(not state:Poll(houseWorld, houseFrame.Position+V3.new(0, 12.001, 0)))
assert(state:Poll(houseWorld, houseFrame:PointToWorldSpace(V3.new(13, 0, 0))))
assert(not state:Poll(houseWorld, houseFrame:PointToWorldSpace(V3.new(-13, 0, 0))))
assert(state:Snapshot().visited[1].id=="house:HouseWest" and #state:Snapshot().visited==1)
state:ResetHistory()
houseFrame=CF.new(-80, 7, 95) * CF.Angles(0, math.rad(-64), 0)
assert(not state:Poll(houseWorld, V3.new(50, 7, 50)))
assert(state:Poll(houseWorld, houseFrame.Position))
-- Two captures of the same surviving avatar, then a real death, retain all three positions.
local character = {}
local first, second, dead = V3.new(1,2,3), V3.new(4,5,6), V3.new(7,8,9)
assert(state:RecordCaught(first) and state:RecordCaught(second))
assert(state:RecordDeath(character, dead))
assert(not state:RecordDeath(character, V3.zero) and not state:RecordCaught(V3.zero))
local history=state:Snapshot()
assert(#history.deaths==3 and history.deaths[1].position==first and history.deaths[2].position==second and history.deaths[3].position==dead)
assert(history.deaths[1].kind=="caught" and history.deaths[3].kind=="death")
assert(not state:RecordCaught(V3.new(0/0,0,0)))
local previousId=history.round_id
state:ClearHistory()
assert(state:Snapshot().round_id==previousId and #state:Snapshot().visited==0 and #state:Snapshot().deaths==0)
state:ResetHistory()
assert(state:Snapshot().round_id==previousId+1 and state:RecordDeath(character, dead))
-- Real SoloRound methods: visit must happen before capture/finish/teleport in one poll.
local dependencies = {MinimapState=State, LightingModes={Default="medium"}, Stamina={}, AuthoredWorld={}, MonsterHunt={}, EndpointNames={}}
local Round=loadSource("src/server/Game/SoloRound.luau", {
    game=fakeGame, script={Parent=node("Game")}, Vector3=V3,
    require=function(module) return assert(dependencies[module.Name], module.Name) end,
})
local livingRoot={Position=V3.new(200,0,200), IsA=function() return true end}
local roundCharacter={FindFirstChild=function() return livingRoot end, FindFirstChildOfClass=function() return {Health=0} end}
local simultaneous=State.new(); simultaneous:ResetHistory()
local fixture=setmetatable({phase="active", roundCharacter=roundCharacter, world=isolated, minimap=simultaneous,
    catches=1, balance={max_catches=2}, huntAt=0, protectedUntil=0,
    _livingCharacter=function() return roundCharacter, nil, livingRoot end,
    _finish=function(self, phase) self.phase=phase; livingRoot.Position=V3.zero end,
}, Round)
isolated.IsValid=function() return true end
isolated.IsOnPlayground=function() return true end
fixture.hunt={Step=function() assert(#simultaneous:Snapshot().visited==1, "Hunt ran before visit"); return true, false end}
fixture:_poll(1)
assert(fixture.phase=="caught_out" and #simultaneous:Snapshot().deaths==1)
assert(simultaneous:Snapshot().deaths[1].position==V3.new(200,0,200), "Capture marker used post-teleport position")
-- A zero-health humanoid still has a root; polling must preserve its death before aborting.
fixture.phase="active"; fixture.hunt=nil; fixture.minimap=State.new(); fixture.minimap:ResetHistory()
livingRoot.Position=dead; fixture._livingCharacter=function() return nil,nil,nil end
fixture:_poll(2)
assert(fixture.phase=="aborted" and fixture.minimap:Snapshot().deaths[1].position==dead)
fixture:_recordCharacterDeath(roundCharacter)
assert(#fixture.minimap:Snapshot().deaths==1, "Died + poll/removal duplicated one death")
print("PASS: saved-map 15 clearings/3 houses; duplicate suppression; clearing/rotated-house boundaries and height; live positions; bounded/copied history; retry/clear; simultaneous visit/capture before teleport; zero-health death root")
