-- Read-only actual runtime output; no MCP require of controller cache.
local lighting = game:GetService("Lighting")
local function color(value)
	return { value.R, value.G, value.B }
end
local out = { lighting = {}, effects = {}, buttons = {} }
for _, key in
	{
		"ClockTime",
		"Brightness",
		"EnvironmentDiffuseScale",
		"EnvironmentSpecularScale",
		"GlobalShadows",
	}
do
	out.lighting[key] = lighting[key]
end
out.lighting.Ambient = color(lighting.Ambient)
out.lighting.OutdoorAmbient = color(lighting.OutdoorAmbient)
out.fog = { color = color(lighting.FogColor), start = lighting.FogStart, finish = lighting.FogEnd }
for _, effect in lighting:GetChildren() do
	local row = { name = effect.Name, class = effect.ClassName, id = effect:GetDebugId(0) }
	if effect:IsA("Atmosphere") then
		row.density, row.haze, row.offset = effect.Density, effect.Haze, effect.Offset
		row.color, row.decay = color(effect.Color), color(effect.Decay)
	end
	table.insert(out.effects, row)
end
local player = game:GetService("Players").LocalPlayer
if player then
	out.canEdit = player:GetAttribute("CornfieldFogCanEdit")
	local gui = player:FindFirstChildOfClass("PlayerGui")
	for _, item in if gui then gui:GetDescendants() else {} do
		if item:IsA("TextButton") and (item.Text:find("Ночь") or item.Name:find("Night")) then
			local visible, ancestor = item.Visible, item.Parent
			while ancestor and ancestor:IsA("GuiObject") do
				visible = visible and ancestor.Visible
				ancestor = ancestor.Parent
			end
			table.insert(
				out.buttons,
				{
					path = item:GetFullName(),
					text = item.Text,
					visible = visible,
					position = { item.AbsolutePosition.X, item.AbsolutePosition.Y },
					size = { item.AbsoluteSize.X, item.AbsoluteSize.Y },
					layout = item.Parent.LayoutOrder,
				}
			)
		end
	end
end
out.camera = workspace.CurrentCamera and tostring(workspace.CurrentCamera.CameraType)
return game:GetService("HttpService"):JSONEncode(out)
