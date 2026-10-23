-- MCP-only staged construction. Never saves, serializes, publishes or changes A/C.
local S = assert(_G.__CornBManualAuthoringV1, "Fresh baseline required")
local H = game:GetService("HttpService")
local M = workspace.CornMap
local G = game.ReplicatedStorage.GameShared.Game
local API = {}
local function identity()
	assert(game:GetService("RunService"):IsStudio() and not game:GetService("RunService"):IsRunning())
	assert(game.Name == "Children_of_corn_B.rbxl" and game.PlaceId == 0)
	assert(M.Parent == workspace and M:GetAttribute("corn_project_id") == "children_of_corn"
		and M:GetAttribute("HarvestArtVariant") == "B" and M.FieldZone.Size == Vector3.new(630,10,630))
end
local function set(item, property, value)
	if item[property] == value then return end
	table.insert(S.journal, {item=item,property=property,before=item[property],after=value})
	item[property]=value
end
local function attr(item, key, value)
	if item:GetAttribute(key) == value then return end
	table.insert(S.journal,{item=item,attribute=key,before=item:GetAttribute(key),after=value})
	item:SetAttribute(key,value)
end
local function own(item)
	item:SetAttribute("corn_project_id","children_of_corn")
	item:SetAttribute("BManualAuthoringVersion",1)
	return item
end
local function add(item)
	table.insert(S.added,item)
	return item
end
local function sameBefore()
	local now=S.snapshot({sourceCount=168})
	assert(now.allSha256==S.before.allSha256,"Author edits since baseline; nothing installed")
	return now
end
function API.prepare()
	identity(); assert(S.phase=="baseline")
	sameBefore()
	S.layout=require(G.CornLayout); S.beds=require(G.GreenBedLayout); S.appearance=require(G.CornAppearance)
	S.exclusions=S.layout.ReadExclusions(M,M.FieldZone)
	S.templates=S.appearance.DetailedTemplates()
	S.ground=M.Ground.Position.Y+M.Ground.Size.Y/2
	S.boxes={}; S.circles={}; S.records={}; S.groups={}; S.groupKeys={}
	local function box(part,padding)
		local half=part.Size/2
		local cf=part.CFrame
		local x=math.abs(cf.RightVector.X)*half.X+math.abs(cf.UpVector.X)*half.Y+math.abs(cf.LookVector.X)*half.Z+padding
		local z=math.abs(cf.RightVector.Z)*half.X+math.abs(cf.UpVector.Z)*half.Y+math.abs(cf.LookVector.Z)*half.Z+padding
		table.insert(S.boxes,{x=cf.X,z=cf.Z,hx=x,hz=z})
	end
	for _,part in M.NoCornZones.Maze02Masks:GetChildren() do assert(part:IsA("BasePart"));box(part,0) end
	for _,part in M.Props:GetDescendants() do
		if part:IsA("BasePart") and (part:GetAttribute("CornFarmMeshOwned")==true or part.Parent==M.Props
			or part:IsDescendantOf(M.Props.VillageRoad)) then box(part,0.5) end
	end
	for _,spawn in M.CornerSpawns:GetChildren() do box(spawn,1) end
	box(M.EscapeGate.Door,3);box(M.EscapeGate.ApproachClearance,0)
	local models=require(game.ServerScriptService.GameServer.Game.ItemModels)
	S.sitePreviews={}
	for _,slot in M.KeySlots:GetChildren() do
		assert(slot:IsA("BasePart") and slot:HasTag("corn_key_slot"))
		local stump=own(Instance.new("Model")); stump.Name="PreviewStump"
		stump:SetAttribute("BAuthoringPreview",true)
		local pos=Vector3.new(slot.Position.X+3.6,S.ground,slot.Position.Z)
		stump.PrimaryPart=models.Stump(stump,CFrame.new(pos+Vector3.new(0,4,0)))
		for _,part in stump:GetDescendants() do
			if part:IsA("BasePart") then
				box(part,0.35);part.CanCollide=false;part.CanQuery=false;part.CanTouch=false
				part:SetAttribute("BAuthoringHelper",true);part:SetAttribute("corn_project_id","children_of_corn")
			end
		end
		S.sitePreviews[slot]={stump=stump,energy=CFrame.new(pos+Vector3.new(0,8.68,0)),trap=CFrame.new(slot.Position.X-3.6,S.ground+0.22,slot.Position.Z)}
		table.insert(S.circles,{x=slot.Position.X,z=slot.Position.Z,r2=2.2*2.2})
	end
	S.index=0; S.oldCount=0; S.addedCells=0; S.removedCells=0
	S.minC,S.maxC,S.minR,S.maxR=S.layout.GetCellBounds(M.FieldZone)
	S.nextColumn=S.minC; S.phase="planning"
	sameBefore()
	return {prepared=true,boxes=#S.boxes,columns=S.maxC-S.minC+1}
end
local function excluded(point)
	for _,b in S.boxes do if math.abs(point.X-b.x)<=b.hx and math.abs(point.Z-b.z)<=b.hz then return true end end
	for _,c in S.circles do if (point.X-c.x)^2+(point.Z-c.z)^2<=c.r2 then return true end end
	return false
end
function API.plan(columns)
	identity();assert(S.phase=="planning")
	for _=1,columns or 8 do
		local c=S.nextColumn;if c>S.maxC then break end
		for r=S.minR,S.maxR do
			local p=S.layout.CellPosition(M.FieldZone,c,r)
			local old=not S.layout.IsExcluded(p,S.exclusions)
			if old then S.oldCount+=1 end
			if not excluded(p) then
				if old then p=S.layout.TrailEdgePosition(p,S.exclusions) end
				if not excluded(p) then
					p=Vector3.new(p.X,S.beds.GetHeight(p) or S.ground,p.Z)
					local record={column=c,row=r,position=p,variety=S.appearance.Variety(c,r)}
					local key=math.floor(c/12)..":"..math.floor(r/12)
					if not S.groups[key] then S.groups[key]={};table.insert(S.groupKeys,key) end
					table.insert(S.groups[key],record);table.insert(S.records,record)
					if not old then S.addedCells+=1 end
				elseif old then S.removedCells+=1 end
			elseif old then S.removedCells+=1 end
		end
		S.nextColumn+=1;task.wait()
	end
	local done=S.nextColumn>S.maxC
	if done then table.sort(S.groupKeys);S.phase="planned" end
	return {done=done,column=S.nextColumn,count=#S.records,previous=S.oldCount,filled=S.addedCells,removed=S.removedCells,chunks=#S.groupKeys}
end
function API.begin()
	identity();assert(S.phase=="planned");sameBefore()
	assert(not M:FindFirstChild("CornAuthoring"),"Existing authored plants preserved")
	local folder=add(own(Instance.new("Folder")));folder.Name="CornAuthoring"
	folder:SetAttribute("Ready",false);folder.Parent=M
	S.folder=folder;S.nextGroup=1;S.created=0;S.phase="building"
	return {started=true,plants=#S.records,chunks=#S.groupKeys}
end
function API.build(chunks)
	identity();assert(S.phase=="building")
	for _=1,chunks or 6 do
		local key=S.groupKeys[S.nextGroup];if not key then break end
		local model=own(Instance.new("Model"));model.Name="Chunk_"..key:gsub(":","_")
		model.ModelStreamingMode=Enum.ModelStreamingMode.Atomic
		for _,record in S.groups[key] do
			local part=S.templates.Near[record.variety]:Clone()
			part.Name="Corn_"..record.column.."_"..record.row
			S.layout.ApplyVariation(part,record.column,record.row)
			part.CFrame=S.appearance.DetailedPivot(part,record.position,S.layout.CellYaw(record.column,record.row))
			part:SetAttribute("CornAuthorColumn",record.column);part:SetAttribute("CornAuthorRow",record.row)
			part:SetAttribute("CornAuthorPlant",true)
			part.Parent=model;S.created+=1
		end
		model.Parent=S.folder
		S.nextGroup+=1;task.wait()
	end
	local done=S.nextGroup>#S.groupKeys
	if done then S.phase="built";S.folder:SetAttribute("Ready",true);S.folder:SetAttribute("InitialPlantCount",S.created) end
	return {done=done,created=S.created,chunks=S.nextGroup-1,totalChunks=#S.groupKeys}
end
local function label(part,text,color)
	local gui=own(Instance.new("BillboardGui"));gui.Name="EditorLabel";gui.Size=UDim2.fromOffset(190,38)
	gui.StudsOffset=Vector3.new(0,2.5,0);gui.MaxDistance=100;gui.AlwaysOnTop=true
	gui:SetAttribute("BAuthoringHelper",true);gui.Parent=part
	local textLabel=Instance.new("TextLabel");textLabel.Size=UDim2.fromScale(1,1);textLabel.BackgroundColor3=Color3.fromRGB(20,25,18)
	textLabel.BackgroundTransparency=0.2;textLabel.Text=text;textLabel.TextColor3=color;textLabel.TextSize=15;textLabel.Parent=gui
	return gui
end
local function point(parent,name,frame,color,kind)
	local part=own(Instance.new("Part"));part.Name=name;part.Size=Vector3.new(1.2,0.12,1.2);part.CFrame=frame
	part.Color=color;part.Material=Enum.Material.Neon;part.Anchored=true;part.CanCollide=false;part.CanTouch=false;part.CanQuery=false
	part.CastShadow=false;part:SetAttribute("BAuthoringHelper",true);part:SetAttribute("BAuthoringPoint",kind);part.Parent=parent
	label(part,kind=="energy" and "ЭНЕРГЕТИК / ПЕНЁК" or "КАПКАН",color)
	return part
end
function API.group()
	identity();assert(S.phase=="built")
	for slot,preview in S.sitePreviews do
		local site=add(own(Instance.new("Model")));site.Name="Site_"..slot:GetAttribute("slot_id");site.Parent=M.KeySlots
		set(slot,"Parent",site);set(slot,"Transparency",0.45);set(slot,"Color",Color3.fromRGB(235,190,65))
		attr(slot,"BAuthoringHelper",true);site.PrimaryPart=slot
		local torch=M.TorchMarkers:FindFirstChild("torch_"..slot:GetAttribute("slot_id"));assert(torch,"Slot torch missing")
		set(torch,"Parent",site)
		preview.stump.Parent=site
		point(site,"EnergyPoint",preview.energy,Color3.fromRGB(65,220,95),"energy")
		point(site,"TrapPoint",preview.trap,Color3.fromRGB(240,110,65),"trap")
		add(label(slot,slot:GetAttribute("slot_id").." / КЛЮЧ",Color3.fromRGB(255,220,100)))
	end
	for _,name in {"HouseWest","HouseEast","HouseNorthWest"} do
		local house=M.Props[name]
		local overlay=add(own(Instance.new("Model")));overlay.Name="B_Visuals";overlay.Parent=house
		for _,item in M.HarvestDecor.VariantB:GetChildren() do
			if item:GetAttribute("HarvestSourceHouse")==name then set(item,"Parent",overlay) end
		end
		for _,item in M.HarvestDecor.Common:GetChildren() do
			if item.Name:sub(1,#name+1)==name.."_" then set(item,"Parent",overlay) end
		end
		for _,torch in M.TorchMarkers:GetChildren() do if torch.Name:sub(1,#name+6)=="torch_"..name then set(torch,"Parent",house) end end
	end
	for _,spawn in M.CornerSpawns:GetChildren() do
		set(spawn,"Transparency",0.35);set(spawn,"Color",Color3.fromRGB(80,160,255));attr(spawn,"BAuthoringHelper",true)
		add(label(spawn,"СТАРТ ИГРОКА / "..spawn.Name,Color3.fromRGB(120,195,255)))
	end
	local home=M.Props.ScarecrowMarker
	local handle=point(home,"WardenSpawn",CFrame.new(home.Body.Position.X,S.ground+0.15,home.Body.Position.Z),Color3.fromRGB(210,80,240),"warden")
	handle.EditorLabel.TextLabel.Text="СПАУН ЧУЧЕЛА — двигать Model"
	add(handle)
	for _,name in {"EditorPreview","EditorFieldOverview"} do
		for index,part in M[name]:GetDescendants() do if part:IsA("BasePart") then set(part,"Transparency",1) end;if index%256==0 then task.wait() end end
	end
	attr(M,"BManualAuthoringVersion",1)
	S.phase="grouped"
	return {sites=15,starts=4,plants=S.created,journal=#S.journal,helpersHiddenInPlay=true}
end
function API.rollback()
	identity()
	for index=#S.journal,1,-1 do local row=S.journal[index];if row.attribute then row.item:SetAttribute(row.attribute,row.before) else row.item[row.property]=row.before end end
	for index=#S.added,1,-1 do local item=S.added[index];if item.Parent then item:Destroy() end end
	for _,row in S.sitePreviews or {} do if not row.stump.Parent then row.stump:Destroy() end end
	S.phase="rolled-back"
	return {rolledBack=true}
end
return API
