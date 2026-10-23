local r = require("@lune/roblox")
local db = r.getReflectionDatabase()
for _, className in {"Model", "BillboardGui", "TextLabel"} do
 local cls=db:GetClass(className)
 while cls do
  for name,prop in cls.Properties do
   if name:match("Adornee") or name:match("PrimaryPart") or name:match("Selection") or name:match("Localiz") or name:match("PlayerTo") or name=="Parent" then print(className,cls.Name,name,prop.Datatype) end
  end
  cls=if cls.Superclass then db:GetClass(cls.Superclass) else nil
 end
end
