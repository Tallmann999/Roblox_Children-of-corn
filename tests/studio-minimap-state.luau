-- Run in verified Children_of_corn Edit or Server. Detached geometry fixture only;
-- no authored world mutations, player teleport, sound or hidden-object payload.
local State=require(game.ServerScriptService.GameServer.Game.MinimapState)
local Geometry=require(game.ReplicatedStorage.GameShared.Game.MinimapGeometry)
local Round=require(game.ServerScriptService.GameServer.Game.SoloRound)
local source=workspace.CornMap
local scratch=Instance.new("Model")
scratch.Name="MinimapGeometryFixture"
local result
local ok,problem=pcall(function()
    local field=source.FieldZone:Clone(); field.Parent=scratch
    local slots={}
    local slotFolder=Instance.new("Folder");slotFolder.Name="KeySlots";slotFolder.Parent=scratch
    for _, item in source.KeySlots:GetChildren() do
        local slot=item:Clone();slot.Parent=slotFolder;table.insert(slots,slot)
    end
    local props=Instance.new("Folder");props.Name="Props";props.Parent=scratch
    for _, name in {"HouseWest","HouseEast","HouseNorthWest"} do
        local house=source.Props[name]:Clone();house.Parent=props
    end
    local world={Root=scratch,Field=field,Slots=slots,IsValid=function() return true end,IsOnPlayground=function() return true end}
    local state=State.new();state:ResetHistory()
    for _, slot in slots do
        assert(state:Poll(world,Vector3.new(slot.Position.X,field.Position.Y,slot.Position.Z)))
    end
    assert(#state:Snapshot().visited==15)
    for _, name in {"HouseWest","HouseEast","HouseNorthWest"} do
        local frame=props[name]:GetBoundingBox()
        assert(state:Poll(world,frame.Position))
    end
    assert(#state:Snapshot().visited==18 and Geometry.IsValid(state:Snapshot()))
    for _, slot in slots do state:Poll(world,Vector3.new(slot.Position.X,field.Position.Y,slot.Position.Z)) end
    assert(#state:Snapshot().visited==18)
    -- The engine recomputes moved/rotated bounds; the fixture never mutates source houses.
    state:ResetHistory()
    local house=props.HouseWest
    house:PivotTo(CFrame.new(5000,field.Position.Y,5000)*CFrame.Angles(0,math.rad(37),0))
    local frame,size=house:GetBoundingBox()
    assert(not state:Poll(world,frame:PointToWorldSpace(Vector3.new(size.X/2+3.01,0,0))))
    assert(state:Poll(world,frame:PointToWorldSpace(Vector3.new(size.X/2+3,0,0))))
    assert(state:Snapshot().visited[1].id=="house:HouseWest")
    -- Real SoloRound methods: capture and visit in one tick use the same pre-teleport position.
    local character=Instance.new("Model");character.Parent=scratch
    local root=Instance.new("Part");root.Name="HumanoidRootPart";root.Anchored=true;root.Parent=character
    root.Position=Vector3.new(slots[1].Position.X,field.Position.Y,slots[1].Position.Z)
    local beforeCapture=root.Position
    local simultaneous=State.new();simultaneous:ResetHistory()
    local fixture=setmetatable({phase="active",roundCharacter=character,world=world,minimap=simultaneous,
        catches=1,balance={max_catches=2},huntAt=0,protectedUntil=0,
        _livingCharacter=function() return character,nil,root end,
        _finish=function(self,phase) self.phase=phase;root.Position=Vector3.zero end,
    },Round)
    fixture.hunt={Step=function() assert(#simultaneous:Snapshot().visited>=1);return true,false end}
    fixture:_poll(1)
    assert(fixture.phase=="caught_out" and #simultaneous:Snapshot().deaths==1)
    assert(simultaneous:Snapshot().deaths[1].position==beforeCapture)
    -- Death paths must use a root even after the humanoid is already dead.
    local humanoid=Instance.new("Humanoid");humanoid.Parent=character;humanoid.Health=0
    fixture.phase="active";fixture.hunt=nil;fixture.minimap=State.new();fixture.minimap:ResetHistory()
    root.Position=beforeCapture;fixture._livingCharacter=function() return nil,nil,nil end
    fixture:_poll(2)
    assert(fixture.phase=="aborted" and fixture.minimap:Snapshot().deaths[1].position==beforeCapture)
    fixture:_recordCharacterDeath(character)
    assert(#fixture.minimap:Snapshot().deaths==1)
    assert(Geometry.IsValid(fixture.minimap:Snapshot()))
    local id=fixture.minimap:Snapshot().round_id
    fixture.minimap:ClearHistory()
    assert(fixture.minimap:Snapshot().round_id==id and #fixture.minimap:Snapshot().deaths==0)
    fixture.minimap:ResetHistory()
    assert(fixture.minimap:Snapshot().round_id==id+1)
    result={saved_clearings=15,saved_houses=3,duplicate_visits=false,rotated_house_boundary=true,
        visit_before_capture=true,capture_position_before_teleport=true,zero_health_death_root=true,
        death_deduplicated=true,clear_without_round_increment=true,retry_increments_round=true,
        authored_workspace_unchanged=true,method="detached Studio geometry + actual SoloRound methods"}
end)
scratch:Destroy()
assert(ok,tostring(problem))
return game.HttpService:JSONEncode(result)
