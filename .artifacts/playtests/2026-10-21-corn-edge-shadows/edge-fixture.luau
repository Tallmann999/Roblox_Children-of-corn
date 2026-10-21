local adapter = require("../../../tests/scene-adapter")
local r,fs=adapter.r,adapter.fs
local serde=require("@lune/serde")
local source=fs.readFile("src/shared/Game/CornLayout.luau")
local fn=assert(loadstring(source:gsub("item%.Position", "item.CFrame.Position")))
setfenv(fn,setmetatable({CFrame=r.CFrame,Vector3=r.Vector3,Vector2=r.Vector2},{__index=getfenv()}))
local layout=fn()
local checks=0
local function check(value,message) checks+=1;assert(value,message) end
local function near(a,b) return (a-b).Magnitude<0.0001 end
local function fixture(variant)
	local map=r.Instance.new("Model");map.Name="CornMap"
	map:SetAttribute("corn_project_id","children_of_corn");map:SetAttribute("HarvestArtVariant",variant)
	local field=r.Instance.new("Part");field.Name="FieldZone";field.Size=r.Vector3.new(630,10,630);field.Parent=map
	local noCorn=r.Instance.new("Folder");noCorn.Name="NoCornZones";noCorn.Parent=map
	local maze=r.Instance.new("Folder");maze.Name="Maze02Masks";maze.Parent=noCorn
	maze:SetAttribute("corn_project_id","children_of_corn");maze:SetAttribute("CornMazeOwner","corn_maze02_v1")
	local trail=r.Instance.new("Part");trail.Name="trail_001";trail.Size=r.Vector3.new(60,.08,4);trail.Parent=maze
	trail:SetAttribute("corn_project_id","children_of_corn");trail:SetAttribute("CornMazeOwner","corn_maze02_v1")
	return map,field,trail
end
local map,field,trail=fixture("B")
local ex=layout.ReadExclusions(map,field)
check(#ex.TrailEdges==1,"Owned B trail indexed")
check(ex.Boxes[1].HalfSize.Y==2,"Only visible4stud path excludes roots")
local function point(x,z) return r.Vector3.new(x,14.4,z) end
check(near(layout.TrailEdgePosition(point(0,4.4),ex),point(0,2.05)),"Positive edge projection")
check(near(layout.TrailEdgePosition(point(0,-4.4),ex),point(0,-2.05)),"Negative edge projection")
check(near(layout.TrailEdgePosition(point(0,4.7),ex),point(0,4.7)),"Distant cell retained")
check(near(layout.TrailEdgePosition(point(29.5,4.4),ex),point(29.5,4.4)),"End cap retained")
local old=layout.TrailEdgePosition(point(0,4.4),{Boxes=ex.Boxes,Circles={},Signature="legacy"})
check(near(old,point(0,4.4)),"Legacy/no edge exclusions unchanged")
for _,variant in {"A","foreign"} do
	local m,f=fixture(variant);local e=layout.ReadExclusions(m,f)
	check(#e.TrailEdges==0 and e.Boxes[1].HalfSize.Y==3.5,"Other variant clearance retained")
	check(near(layout.TrailEdgePosition(point(0,4.4),e),point(0,4.4)),"Other variant position retained")
end
for _,mutate in {
	function(t) t:SetAttribute("CornMazeOwner",nil) end,
	function(t) t.Name="trail_101" end,
	function(t) t.Name="trail_000" end,
	function(t) t.Size=r.Vector3.new(60,.08,5) end,
	function(t) t.Size=r.Vector3.new(60,.2,4) end,
	function(t) t.CFrame=r.CFrame.Angles(0,.1,0) end,
	function(t) t.Parent:SetAttribute("CornMazeOwner",nil) end,
} do
	local m,f,t=fixture("B");mutate(t);local e=layout.ReadExclusions(m,f)
	check(#e.TrailEdges==0,"Malformed/non-owned trail not indexed")
	check(near(layout.TrailEdgePosition(point(0,4.4),e),point(0,4.4)),"Malformed trail cannot move roots")
end
for _,case in {
	{tag="corn_key_slot",radius=6,center=-3},
	{tag="corn_spawn",radius=10,center=-7},
} do
	local m,f=fixture("B")
	local marker=r.Instance.new("Part");marker.Name="Marker";marker.Size=r.Vector3.new(.1,.1,.1)
	marker.CFrame=r.CFrame.new(0,14.4,case.center);marker.Parent=m;marker:AddTag(case.tag)
	local e=layout.ReadExclusions(m,f)
	check(not layout.IsExcluded(point(0,4.4),e),"Original root outside circle")
	check(layout.IsExcluded(point(0,2.05),e),"Projected root would enter circle")
	check(near(layout.TrailEdgePosition(point(0,4.4),e),point(0,4.4)),"Circle clearance prevents projection")
end
do
	local m,f=fixture("B")
	local props=r.Instance.new("Folder");props.Name="Props";props.Parent=m
	local barn=r.Instance.new("Part");barn.Name="Barn";barn.Size=r.Vector3.new(10,20,4);barn.Parent=props
	local e=layout.ReadExclusions(m,f)
	check(not layout.IsExcluded(point(0,4.4),e),"Original root outside barn margin")
	check(near(layout.TrailEdgePosition(point(0,4.4),e),point(0,4.4)),"Barn margin prevents projection")
end
do
	local m,f=fixture("B")
	local gate=r.Instance.new("Model");gate.Name="EscapeGate";gate.Parent=m
	local door=r.Instance.new("Part");door.Name="Door";door.Size=r.Vector3.new(12,18,2);door.CFrame=r.CFrame.new(0,14.4,-4);door.Parent=gate
	local e=layout.ReadExclusions(m,f)
	check(not layout.IsExcluded(point(0,4.4),e),"Original root outside gate margin")
	check(near(layout.TrailEdgePosition(point(0,4.4),e),point(0,4.4)),"Gate margin prevents projection")
end
do
	local m,f,t=fixture("B")
	local crossing=t:Clone();crossing.Name="trail_002";crossing.Size=r.Vector3.new(4,.08,60);crossing.Parent=t.Parent
	local e=layout.ReadExclusions(m,f)
	for x=-5,5,.25 do for z=-5,5,.25 do
		local p=point(x,z);local target=layout.TrailEdgePosition(p,e)
		if layout.IsExcluded(p,e) then check(near(p,target),"Excluded junction cell cannot be pulled out")
		else check(not layout.IsExcluded(target,e),"Junction corridor remains root-free") end
		check((target-p).Magnitude<=layout.SpacingFor(f),"Shift bounded by one spacing")
		check(target.Y==p.Y,"Root height retained")
	end end
end
local report={assertions=checks,layout_sha256=serde.hash("sha256",source),result="PASS"}
fs.writeFile(".artifacts/playtests/2026-10-21-corn-edge-shadows/edge-fixture.json",serde.encode("json",report,true))
print(serde.encode("json",report))
