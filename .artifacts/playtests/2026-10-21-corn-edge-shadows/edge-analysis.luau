-- Read-only private deserialization analysis; never writes a scene.
local root = "D:/ROBLOX/My_Projects/Roblox_Children of Corn/"
local adapter = require("../../../tests/scene-adapter")
local r, fs = adapter.r, adapter.fs
local serde = require("@lune/serde")
local bytes = fs.readFile(root .. "place/Children_of_corn_B.rbxl")
assert(serde.hash("sha256", bytes) == "b113d584f1a60e16f34ba4ec40ce051b0338cab712467f07d762d9fc8528b1d2")
local scene = r.deserializePlace(bytes)
local map = scene:GetService("Workspace").CornMap
local source = scene:GetService("ReplicatedStorage").GameShared.Game.CornLayout.Source
source = source:gsub("item%.Position", "item.CFrame.Position")
local function module(text)
	local fn = assert(loadstring(text))
	setfenv(fn, setmetatable({ CFrame = r.CFrame, Vector3 = r.Vector3, Vector2 = r.Vector2, map=map }, { __index = getfenv() }))
	return fn()
end
local normal = module(source)
local edge = module(fs.readFile(root .. "src/shared/Game/CornLayout.luau"):gsub("item%.Position", "item.CFrame.Position"))
local field = map.FieldZone
local normalEx, edgeEx = normal.ReadExclusions(map, field), edge.ReadExclusions(map, field)
local function fastExcluded(ex)
	local boxes, circles = {}, {}
	for _, b in ex.Boxes do
		local a={b.Frame:GetComponents()}
		table.insert(boxes,{a[1],a[3],a[4],a[10],a[6],a[12],b.HalfSize.X,b.HalfSize.Y})
	end
	for _,c in ex.Circles do table.insert(circles,{c.Center.X,c.Center.Z,c.Radius*c.Radius}) end
	return function(p)
		local x,z=p.X,p.Z
		for _,c in circles do local dx,dz=x-c[1],z-c[2]; if dx*dx+dz*dz<=c[3] then return true end end
		for _,b in boxes do
			local dx,dz=x-b[1],z-b[2]
			if math.abs(dx*b[3]+dz*b[4])<=b[7] and math.abs(dx*b[5]+dz*b[6])<=b[8] then return true end
		end
		return false
	end
end
local normalExcluded,edgeExcluded=fastExcluded(normalEx),fastExcluded(edgeEx)
edge.IsExcluded=edgeExcluded
local loC, hiC, loR, hiR = normal.GetCellBounds(field)
local normalRoots, edgeRoots, projectedRoots = {}, {}, {}
local moved,maxShift=0,0
for column = loC, hiC do
	for row = loR, hiR do
		local p = normal.CellPosition(field, column, row)
		local record = {column, row, p.X, p.Z, normal.CellYaw(column, row), normal.HeightFactor(column, row)}
		if not normalExcluded(p) then table.insert(normalRoots, record) end
		if not edgeExcluded(p) then
			table.insert(edgeRoots, record)
			local target=edge.TrailEdgePosition(p,edgeEx)
			local delta=(target-p).Magnitude
			assert(delta<=edge.SpacingFor(field)+.0001 and not edgeExcluded(target))
			if delta>.0001 then moved+=1;maxShift=math.max(maxShift,delta) end
			table.insert(projectedRoots,{column,row,target.X,target.Z,record[5],record[6]})
		end
	end
end
local trails = {}
for _, p in map.NoCornZones.Maze02Masks:GetChildren() do
	assert(p:IsA("BasePart") and math.min(p.Size.X,p.Size.Z) == 4)
	table.insert(trails,{name=p.Name,x=p.CFrame.Position.X,z=p.CFrame.Position.Z,sx=p.Size.X,sz=p.Size.Z})
end
-- Only the private deserialized model is altered to isolate non-trail clearances.
map.NoCornZones.Maze02Masks:Destroy()
local hardEx = normal.ReadExclusions(map, field)
local hardExcluded=fastExcluded(hardEx)
local samples = {}
for _, trail in trails do
	local horizontal = trail.sx > trail.sz
	local half = math.max(trail.sx,trail.sz)/2 - 5
	for d = -half, half, 3 do
		local p = r.Vector3.new(trail.x + (if horizontal then d else 0), field.CFrame.Position.Y, trail.z + (if horizontal then 0 else d))
		if not hardExcluded(p) then
			table.insert(samples,{trail=trail.name,x=p.X,z=p.Z,horizontal=horizontal})
		end
	end
end
local out = {baseline_sha256=serde.hash("sha256",bytes),spacing=normal.SpacingFor(field),normal_roots=normalRoots,edge_roots=edgeRoots,projected_roots=projectedRoots,projected_count=moved,max_shift=maxShift,trails=trails,samples=samples}
fs.writeFile(root .. ".artifacts/playtests/2026-10-21-corn-edge-shadows/edge-analysis-data.json",serde.encode("json",out))
print(serde.encode("json",{normal_roots=#normalRoots,edge_roots=#edgeRoots,projected_count=moved,max_shift=maxShift,eligible_trail_samples=#samples,exclusion_boxes=#normalEx.Boxes,exclusion_circles=#normalEx.Circles}))
