-- Read-only layout inventory; never serialize an instance.
local fs = require("@lune/fs")
local r = require("@lune/roblox")
local serde = require("@lune/serde")
local place = r.deserializePlace(fs.readFile("place/Children_of_corn_B.rbxl"))
local map = assert(place.Workspace:FindFirstChild("CornMap"))
local result = { attrs = map:GetAttributes(), children = {}, parts = {}, groups = {} }
for _, item in map:GetChildren() do
	table.insert(result.children, { name=item.Name,class=item.ClassName,children=#item:GetChildren() })
end
local function vector(v) return {v.X,v.Y,v.Z} end
for _, item in map:GetDescendants() do
	local path = item:GetFullName():gsub("%.", "/")
	local interesting = path:find("CornerSpawns/") or path:find("Slots/") or path:find("NoCornZones/")
		or path:find("EscapeGate/") or path:find("Props/Village") or path:find("Props/Farm")
		or path:find("Props/House") or path:find("TorchMarkers/") or item.Name == "Ground"
		or item.Name == "FieldZone" or item.Name == "ExitZone" or item.Name == "PlayBounds"
		or path:find("NoCornZone")
	if interesting and item:IsA("BasePart") then
		table.insert(result.parts,{path=path,class=item.ClassName,size=vector(item.Size),
			frame={item.CFrame:GetComponents()},transparency=item.Transparency,collide=item.CanCollide,
			query=item.CanQuery,attrs=item:GetAttributes(),tags=item:GetTags(),material=tostring(item.Material)})
	end
	if item:IsA("Model") and (item.Parent==map.Props or item.Parent==map.TorchMarkers or item.Parent==map.NoCornZones) then
		local ok,pivot=pcall(function() return item:GetPivot() end)
		table.insert(result.groups,{path=path,attrs=item:GetAttributes(),pivot=if ok then {pivot:GetComponents()} else nil,children=#item:GetChildren()})
	end
end
local function plain(value)
	if typeof(value)=="CFrame" then return {kind="CFrame",value={value:GetComponents()}} end
	if typeof(value)=="Vector3" then return {kind="Vector3",value=vector(value)} end
	if typeof(value)=="Color3" then return {kind="Color3",value={value.R,value.G,value.B}} end
	if type(value)=="table" then local out={};for key,item in value do out[key]=plain(item) end;return out end
	if type(value)=="userdata" then return tostring(value) end
	return value
end
print(serde.encode("json",plain(result)))
