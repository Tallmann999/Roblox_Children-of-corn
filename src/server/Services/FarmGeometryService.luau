--!strict
local run = game:GetService("RunService")
local Geometry = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("FarmGeometry"))
local Service = { Name = "FarmGeometryService", Order = 15 }
function Service:Init(context: any)
	if
		not run:IsStudio()
		or context.Config.Environment ~= "DEV"
		or context.Config.Game.SessionMode ~= "solo_local"
	then
		return
	end
	local report = Geometry.Ensure()
	context.Log:Info(
		"Farm geometry restored before RoundService:",
		report.targets,
		report.built,
		report.applied
	)
end
function Service:Destroy()
	Geometry.Destroy()
end
return Service
