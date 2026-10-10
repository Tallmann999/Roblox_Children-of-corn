-- Pure projection/transport fixture; engine input/network acceptance is separate.
local fs = require("@lune/fs")
local r = require("@lune/roblox")
local fn = assert(loadstring(fs.readFile("src/shared/Game/MinimapGeometry.luau")))
setfenv(fn, setmetatable({Vector2=r.Vector2}, {__index=getfenv()}))
local G = fn()
local cf = r.CFrame.new(130, 22, -170) * r.CFrame.Angles(0, math.rad(67), 0)
local size = r.Vector3.new(840, 10, 600)
local function near(a,b) assert(math.abs(a-b)<0.0001, tostring(a).." != "..tostring(b)) end
for _,v in {{-420,-300,0,0},{420,-300,1,0},{420,300,1,1},{-420,300,0,1},{0,0,0.5,0.5},{1000,-1000,1,0}} do
 local at = cf:PointToWorldSpace(r.Vector3.new(v[1],7,v[2]))
 local uv = G.Project(cf,size,at)
 near(uv.X,v[3]);near(uv.Y,v[4])
end
for _,v in {{0,-1,0},{1,0,90},{0,1,180},{-1,0,270}} do
 local facing=cf:VectorToWorldSpace(r.Vector3.new(v[1],0,v[2]))
 near((G.Heading(cf,facing)+360)%360,v[3])
end
assert(G.IsValid({round_id=1,visited={{id="clearing:a",kind="clearing",position=r.Vector3.zero}},deaths={{id=1,kind="caught",position=r.Vector3.zero}}}))
for _,bad in {
 {round_id=0/0,visited={},deaths={}},
 {round_id=1,visited={{id="x",kind="clearing",position=r.Vector3.new(0/0,0,0)}},deaths={}},
 {round_id=1,visited={{id="x",kind="key",position=r.Vector3.zero}},deaths={}},
 {round_id=1,visited={{id="x",kind="house",position=r.Vector3.zero},{id="x",kind="house",position=r.Vector3.zero}},deaths={}},
 {round_id=1,visited={},deaths={{id=1,kind="caught",position=r.Vector3.zero},{id=1,kind="death",position=r.Vector3.zero}}},
 {round_id=1,visited={hidden={id="x",kind="house",position=r.Vector3.zero}},deaths={}}
} do assert(not G.IsValid(bad),"Malformed minimap history accepted") end
print("PASS: rotated/translated non-square field, four corners/headings, edge clamp; malformed/non-finite/duplicate history rejection")
