local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local OUT = ".artifacts/playtests/2026-10-21-corn-edge-shadows/"
local bytes = fs.readFile("place/Children_of_corn_B.rbxl")
assert(serde.hash("sha256", bytes) == "b113d584f1a60e16f34ba4ec40ce051b0338cab712467f07d762d9fc8528b1d2")
local dom = roblox.deserializePlace(bytes)
local result = { sources = {}, eyes = {} }
for _, item in dom:GetDescendants() do
	if item:IsA("LuaSourceContainer") and (item.Name == "HarvestWardenVisual" or item.Name == "HarvestWorld" or item.Name == "CaptureController" or item.Name == "HarvestGeometry") then
		local source = item.Source
		fs.writeFile(OUT .. "eyes-saved-" .. item.Name .. ".luau", source)
		result.sources[item:GetFullName():gsub("%.", "/")] = { sha256 = serde.hash("sha256", source:gsub("\r\n", "\n")), bytes = #source }
	end
	local section = item:GetAttribute("HarvestSection")
	if item:IsA("BasePart") and (section == "LeftEye" or section == "RightEye") then
		local attrs = {}
		for key, value in item:GetAttributes() do
			local kind = typeof(value)
			if kind == "Vector3" then attrs[key] = {kind=kind, value={value.X,value.Y,value.Z}}
			elseif kind == "Color3" then attrs[key] = {kind=kind, value={value.R,value.G,value.B}}
			elseif kind == "CFrame" then attrs[key] = {kind=kind, value={value:GetComponents()}}
			else attrs[key] = value end
		end
		table.insert(result.eyes, {path=item:GetFullName():gsub("%.", "/"), class=item.ClassName, material=item.Material.Name, color={item.Color.R,item.Color.G,item.Color.B}, transparency=item.Transparency, attrs=attrs})
	end
end
fs.writeFile(OUT .. "eyes-saved-analysis.json", serde.encode("json", result))
print(serde.encode("json", {sources=result.sources,eyeParts=#result.eyes}))
