local fs=require('@lune/fs')
local r=require('@lune/roblox')
local serde=require('@lune/serde')
local p=r.deserializePlace(fs.readFile('place/Children_of_corn_B.rbxl'))
local t={}
for _,s in p:GetChildren() do
 local a={class=s.ClassName,name=s.Name}
 if s.ClassName=='Instance' or s.Name=='' then
  a.children={}
  for _,c in s:GetChildren() do table.insert(a.children,{class=c.ClassName,name=c.Name}) end
 end
 table.insert(t,a)
end
print(serde.encode('json',t))
