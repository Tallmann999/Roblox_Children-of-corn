-- Real CornController methods with Lune geometry and deterministic signal proxies.
-- Event scheduling/rendered FPS and silhouettes still require Studio Client acceptance.
local adapter=require("./scene-adapter")
local fs,r=adapter.fs,adapter.r
local CF,V3,I=r.CFrame,r.Vector3,r.Instance
local function loadSource(path,env)
    local fn=assert(loadstring(fs.readFile(path),path));setfenv(fn,setmetatable(env,{__index=getfenv()}));return fn()
end
local layout=loadSource("src/shared/Game/CornLayout.luau",{CFrame=CF,Vector3=V3,Vector2=r.Vector2})
local workspaceProxy={CurrentCamera={CFrame=CF.new(0,5.4,0)}}
local function node(name) return {Name=name,WaitForChild=function(_,child) return node(child) end} end
local gameProxy={GetService=function(_,name) return if name=="Workspace" then workspaceProxy else node(name) end}
local controller=loadSource("src/client/Controllers/CornController.luau",{
    game=gameProxy,require=function() return layout end,CFrame=CF,Vector3=V3,Instance=I,Enum=r.Enum,warn=function() end,
})
-- New groups use base thresholds; existing groups do not churn in +/-12 bands.
assert(controller:_lodForDistance(60^2,nil,130)==1)
assert(controller:_lodForDistance(60.01^2,nil,130)==2)
assert(controller:_lodForDistance(130^2,nil,130)==2)
assert(controller:_lodForDistance(130.01^2,nil,130)==3)
assert(controller:_lodForDistance(72^2,1,130)==1)
assert(controller:_lodForDistance(72.01^2,1,130)==2)
assert(controller:_lodForDistance(48^2,2,130)==1)
assert(controller:_lodForDistance(48.01^2,2,130)==2)
assert(controller:_lodForDistance(142^2,2,130)==2)
assert(controller:_lodForDistance(142.01^2,2,130)==3)
assert(controller:_lodForDistance(118^2,3,130)==2)
assert(controller:_lodForDistance(118.01^2,3,130)==3)
assert(controller:_lodForDistance(156^2,2,144)==2)
assert(controller:_lodForDistance(156.01^2,2,144)==3)
local lod=1
for _=1,100 do for _,distance in {58,62,65,55} do lod=controller:_lodForDistance(distance^2,lod,130);assert(lod==1) end end
lod=2
for _=1,100 do for _,distance in {128,132,138,126} do lod=controller:_lodForDistance(distance^2,lod,130);assert(lod==2) end end
local function signal()
    local callbacks={}
    return {Connect=function(_,fn)
        local connection={Connected=true,Disconnect=function(self) self.Connected=false end}
        table.insert(callbacks,{connection,fn});return connection
    end,Fire=function()
        for _,entry in callbacks do if entry[1].Connected then entry[2]() end end
    end}
end
local function signals(object)
    local props,attrs={},{}
    object.GetPropertyChangedSignal=function(_,name) if not props[name] then props[name]=signal() end;return props[name] end
    object.GetAttributeChangedSignal=function(_,name) if not attrs[name] then attrs[name]=signal() end;return attrs[name] end
    return props,attrs
end
local field={CFrame=CF.new(0,5,0),Size=V3.new(840,10,840)}
local fieldProps=signals(field)
controller._field=field
local root={Position=V3.new(0,3.4,0)}
assert(not controller:_elevatedView(root,0))
root.Position=V3.new(0,7,0);assert(controller:_elevatedView(root,1))
root.Position=V3.new(0,3.4,0);assert(controller:_elevatedView(root,2.99));assert(not controller:_elevatedView(root,3))
workspaceProxy.CurrentCamera.CFrame=CF.new(0,6.01,0);assert(controller:_elevatedView(root,4))
workspaceProxy.CurrentCamera.CFrame=CF.new(0,5.4,0);assert(controller:_elevatedView(root,5.99));assert(not controller:_elevatedView(root,6))
-- Overview cache: no repeated GetChildren scan; every ownership/geometry/topology mutation invalidates.
local ownership={CornEditorOverview=true,corn_project_id="children_of_corn"}
local folder={Name="EditorFieldOverview",Parent=true,ChildAdded=signal(),ChildRemoved=signal(),AncestryChanged=signal(),
    IsA=function(_,class) return class=="Folder" end,GetAttribute=function(_,name) return ownership[name] end}
local folderProps,folderAttrs=signals(folder)
local function part(position)
    local attributes={CornEditorOverview=true,corn_project_id="children_of_corn"}
    local item={CFrame=CF.new(position),Size=V3.new(2,8,2),Parent=folder,LocalTransparencyModifier=0.25,
        IsA=function(_,class) return class=="BasePart" end,GetAttribute=function(_,name) return attributes[name] end}
    local props,attrs=signals(item);return item,attributes,props,attrs
end
local a,aOwnership,aProps,aAttrs=part(V3.new(18,4,18))
local b=part(V3.new(54,4,54))
local children={a,b};local reads=0
folder.GetChildren=function() reads+=1;return table.clone(children) end
local activeBackdrop
local map={FindFirstChild=function(_,name)
    if name=="EditorFieldOverview" then return folder elseif name=="CornClientBackdrop" then return activeBackdrop end
    return nil
end,IsA=function(_,class) return class=="Model" end,GetAttribute=function(_,name) return if name=="corn_project_id" then "children_of_corn" else nil end}
folder.Parent=map
workspaceProxy.FindFirstChild=function(_,name) return if name=="CornMap" then map else nil end
controller._map=map;controller._elevatedUntil=nil
controller:_bindOverview()
local firstReads=reads
assert(not controller._overviewInvalid and #controller._overviewConnections==16)
for _=1,100 do controller:_bindOverview() end
assert(reads==firstReads,"Overview was fully rescanned on unchanged polls")
local function cover()
    for _,entry in controller._overviewParts do
        for _,key in entry.Keys do controller._chunks[key]={Done=true,Lod=1};controller:_markOverviewChunk(key) end
    end
    controller:_updateOverview()
    assert(a.LocalTransparencyModifier==1 and b.LocalTransparencyModifier==1)
end
cover()
a.CFrame=CF.new(100,4,100);aProps.CFrame:Fire()
assert(controller._overviewInvalid and a.LocalTransparencyModifier==0.25 and b.LocalTransparencyModifier==0.25)
controller:_updateOverview();assert(a.LocalTransparencyModifier==0.25,"Invalid index hid author art")
controller:_bindOverview();assert(controller._overviewParts[a].Frame==a.CFrame and reads==firstReads+1)
cover()
a.Size=V3.new(4,8,4);aProps.Size:Fire();assert(controller._overviewInvalid and a.LocalTransparencyModifier==0.25)
controller:_bindOverview();assert(controller._overviewParts[a].Size==a.Size)
cover();aOwnership.CornEditorOverview=false;aAttrs.CornEditorOverview:Fire()
assert(controller._overviewInvalid and a.LocalTransparencyModifier==0.25)
controller:_bindOverview();assert(controller._overviewFolder==nil and #controller._overviewConnections==0)
aOwnership.CornEditorOverview=true;controller:_bindOverview();cover()
local stranger={IsA=function() return false end,Parent=folder}
table.insert(children,stranger);folder.ChildAdded:Fire();assert(controller._overviewInvalid and a.LocalTransparencyModifier==0.25)
controller:_bindOverview();assert(controller._overviewFolder==nil and stranger.Parent==folder)
table.remove(children);controller:_bindOverview();cover()
field.CFrame=CF.new(10,5,0);fieldProps.CFrame:Fire();assert(controller._overviewInvalid and a.LocalTransparencyModifier==0.25)
controller:_bindOverview();assert(controller._overviewFieldFrame==field.CFrame)
cover();ownership.corn_project_id="other";folderAttrs.corn_project_id:Fire()
assert(controller._overviewInvalid and a.LocalTransparencyModifier==0.25)
controller:_bindOverview();assert(controller._overviewFolder==nil)
ownership.corn_project_id="children_of_corn";controller:_bindOverview()
local previousConnections=table.clone(controller._overviewConnections)
controller:_restoreOverview();assert(#controller._overviewConnections==0)
for _,connection in previousConnections do assert(not connection.Connected,"Signal connection leaked") end
-- Ready handoff: fallback remains authored; runtime copies avoid per-part connection explosion.
local backdropOwnership={CornClientBackdropOwned=true,CornEditorOverview=true,corn_project_id="children_of_corn",Ready=false,DetailStride=6}
activeBackdrop={Name="CornClientBackdrop",Parent=map,ChildAdded=signal(),ChildRemoved=signal(),AncestryChanged=signal(),
    DescendantAdded=signal(),DescendantRemoving=signal(),IsA=function(_,class) return class=="Folder" end,
    GetAttribute=function(_,name) return backdropOwnership[name] end}
local _,backdropAttrs=signals(activeBackdrop)
local farA,farOwnership,farProps=part(V3.new(180,4,180));farA.Parent=activeBackdrop;farA.LocalTransparencyModifier=0
local farB=part(V3.new(216,4,216));farB.Parent=activeBackdrop;farB.LocalTransparencyModifier=0
activeBackdrop.GetChildren=function() return {farA,farB} end
controller:_bindOverview();assert(controller._overviewFolder==folder,"Incomplete runtime backdrop replaced authored fallback")
cover()
local other={Name="CornClientBackdrop",Parent=folder,IsA=function() return true end,GetAttribute=function(_,name) return backdropOwnership[name] end}
assert(not controller:UseBackdropReady(other) and a.LocalTransparencyModifier==1,"Unknown handoff cleared existing mask")
assert(controller:UseBackdropReady(activeBackdrop))
assert(controller._overviewFolder==nil and a.LocalTransparencyModifier==0.25 and b.LocalTransparencyModifier==0.25,"Handoff captured hidden authored pixels")
local savedA,savedB=a.LocalTransparencyModifier,b.LocalTransparencyModifier
a.LocalTransparencyModifier=1;b.LocalTransparencyModifier=1 -- Backdrop owns whole authored visibility.
backdropOwnership.Ready=true
controller:_bindOverview();assert(controller._overviewFolder==activeBackdrop and controller._overviewRuntime)
assert(#controller._overviewConnections==12 and farProps.CFrame==nil and farProps.Size==nil,"Runtime layer allocated per-part geometry watchers")
for _,entry in controller._overviewParts do for _,key in entry.Keys do controller._chunks[key]={Done=true,Lod=1};controller:_markOverviewChunk(key) end end
controller:_updateOverview();assert(farA.LocalTransparencyModifier==1 and farB.LocalTransparencyModifier==1)
assert(a.LocalTransparencyModifier==1,"Fine mask overwrote backdrop's authored visibility")
-- Dirty-entry guard refuses an unexpected runtime ownership edit; no stale hide after rejection.
farOwnership.CornEditorOverview=false
for _,entry in controller._overviewParts do controller._overviewDirty[entry]=true end
controller:_updateOverview()
assert(controller._overviewFolder==nil and farA.LocalTransparencyModifier==0 and farB.LocalTransparencyModifier==0)
farOwnership.CornEditorOverview=true;controller:_bindOverview()
activeBackdrop.DescendantAdded:Fire();assert(controller._overviewInvalid,"Runtime subtree topology left stale coverage")
controller:_bindOverview()
local runtimeConnections=table.clone(controller._overviewConnections)
assert(controller:UseBackdropReady(activeBackdrop));backdropOwnership.Ready=false;backdropAttrs.Ready:Fire()
a.LocalTransparencyModifier=savedA;b.LocalTransparencyModifier=savedB
controller:_bindOverview();assert(controller._overviewFolder==folder and not controller._overviewRuntime)
for _,connection in runtimeConnections do assert(not connection.Connected,"Runtime handoff signal leaked") end
controller:_restoreOverview();activeBackdrop=nil
-- Owned immutable backdrop is never traversed by gameplay exclusions, even at20k copies.
local ignored={Name="CornClientBackdrop",GetAttribute=function(_,name)
    if name=="corn_project_id" then return "children_of_corn" elseif name=="CornClientBackdropOwned" then return true end
    return nil
end,GetChildren=function() error("ReadExclusions traversed immutable far layer") end}
local exclusionMap={FindFirstChild=function() return nil end,GetChildren=function() return {ignored} end}
local cleanExclusions=layout.ReadExclusions(exclusionMap,field)
assert(#cleanExclusions.Boxes==0 and #cleanExclusions.Circles==0)
-- The same folder name without ownership is author content and must still bind tagged geometry.
local manual={CFrame=CF.new(30,4,30),Size=V3.new(8,8,8),Name="ManualZone",
    GetAttribute=function() return nil end,GetFullName=function() return "CornMap/CornClientBackdrop/ManualZone" end,
    GetChildren=function() return {} end,IsA=function(_,class) return class=="BasePart" end,
    HasTag=function(_,tag) return tag=="corn_no_corn_zone" end}
ignored.GetAttribute=function(_,name) return if name=="corn_project_id" then "children_of_corn" else nil end
ignored.GetChildren=function() return {manual} end;ignored.IsA=function() return false end
assert(#layout.ReadExclusions(exclusionMap,field).Boxes==1,"Unowned author folder was hidden from bindings")
-- Actual reconcile retains existing outer groups up to18, but creates no new groups there.
controller._chunks={};controller._field=field;field.CFrame=CF.new(0,5,0)
controller._resolveInputs=function() return true end
controller._bindOverview=function() end
layout.ReadExclusions=function() return {Signature="stable",Boxes={},Circles={}} end
local runtime=I.new("Folder");controller._folder=runtime;controller._exclusions=nil
local function chunk(key)
    local f=I.new("Folder");f.Parent=runtime
    return {Key=key,Lod=3,Folder=f,Count=0,Alive=true,Done=true}
end
local retained=chunk("4:0");controller._chunks["4:0"]=retained
controller._chunks["5:0"]=chunk("5:0")
controller:_reconcile(root)
assert(controller._chunks["4:0"]==retained,"Existing161stud group was not retained")
assert(controller._chunks["5:0"]==nil,"196stud group exceeded retention")
assert(controller._chunks["4:1"]==nil,"New outer group was created beyond150")
root.Position=V3.new(-20,3.4,0);controller:_reconcile(root)
assert(controller._chunks["4:0"]==nil,"Outer group never unloaded after exceeding168")
root.Position=V3.new(0,3.4,0);workspaceProxy.CurrentCamera.CFrame=CF.new(0,10,0);controller:_reconcile(root)
local groups=0;for _ in controller._chunks do groups+=1 end
assert(groups<=100 and runtime:GetAttribute("ViewRadius")==200 and runtime:GetAttribute("ElevatedDetail")==true)
-- A completed stride6 background must never be replaced by a sparser stride9 ring.
controller:_clearChunks()
backdropOwnership.Ready=true
controller._overviewFolder=farA.Parent;controller._overviewRuntime=true;controller._overviewInvalid=false
controller._overviewParts={};controller._overviewByChunk={}
local sparse=chunk("4:0");sparse.Count=7;controller._chunks={["4:0"]=sparse};controller._plantCount=7
for _=1,7 do local plant=I.new("MeshPart");plant.Parent=sparse.Folder end
local coverage={Part=farA,PreviousModifier=0,Frame=farA.CFrame,Size=farA.Size,Keys={"4:0"},Hidden=false}
farA.LocalTransparencyModifier=0
controller._overviewParts[farA]=coverage;controller._overviewDirty[coverage]=true
controller:_updateOverview()
assert(farA.LocalTransparencyModifier==0,"Sparse LOD3 hid the denser whole-field backdrop")
controller:_reconcile(root)
assert(controller._chunks["4:0"]==nil and controller._plantCount==0,"Old LOD3 survived or leaked its loaded count")
for _,group in controller._chunks do assert(group.Lod<=2,"Backdrop6 generated a sparse LOD3 ring") end
local prepared=I.new("MeshPart");prepared.Size=V3.new(2,8,2);prepared.CFrame=CF.new(0,4,0)
controller._template=prepared;controller._exclusions={Boxes={},Circles={}}
controller:_createBatch()
local loaded=0
for _,group in controller._chunks do loaded+=#group.Folder:GetChildren() end
assert(loaded==controller._plantCount and loaded==runtime:GetAttribute("LoadedPlants") and loaded<=18,"Fine-only loaded statistics mismatch")
controller:_clearChunks();prepared:Destroy();controller._template=nil
controller._overviewFolder=nil;controller._overviewRuntime=false;controller._overviewInvalid=true
controller._overviewParts={};controller._overviewDirty={}
controller:_reconcile(root)
local fallbackSparse=false
for _,group in controller._chunks do if group.Lod==3 then fallbackSparse=true end end
assert(fallbackSparse,"Saved fallback lost its sparse3/6/9 renderer")
-- A sparse clone preserves X/Z and inherited fidelity, suppresses shadows, and respects4032 cap.
controller:_clearChunks()
local template=I.new("MeshPart");template.Size=V3.new(2,8,2);template.CFrame=CF.new(0,4,0)
local templateSize=template.Size;local originalFidelity=template.RenderFidelity
controller._template=template;controller._exclusions={Boxes={},Circles={}};controller._plantCount=4031
local pending=chunk("fixture");pending.Done=false;pending.MinColumn=0;pending.MaxColumn=3;pending.MinRow=0;pending.MaxRow=3;pending.Column=0;pending.Row=0;pending.Lod=3
controller._queue={pending};controller._chunks={fixture=pending}
controller:_createBatch()
assert(controller._plantCount==4032 and pending.Count==1,"Plant cap was exceeded")
local clone=pending.Folder:GetChildren()[1]
assert(clone.Size.X==templateSize.X and clone.Size.Z==templateSize.Z)
assert(clone.RenderFidelity==originalFidelity and not clone.CastShadow,"Runtime clone changed inherited fidelity or shadow budget")
assert(template.Size==templateSize and template.RenderFidelity==originalFidelity,"Imported/template art mutated")
controller:_clearChunks();runtime:Destroy();template:Destroy()
print("PASS: LOD hysteresis/no threshold churn; root/camera elevation+2s; overview cache/event invalidation/ownership restore/disconnect; Ready fallback+visibility handoff; runtime immutable cache/dirty guard; far6 no sparse9 hole/fine-only loaded counts;18stud retention;100groups/4032plants; inherited fidelity/aspect/source preservation")
