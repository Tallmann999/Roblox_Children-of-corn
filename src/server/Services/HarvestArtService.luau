--!strict
local run = game:GetService("RunService")
local HarvestWorld = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("HarvestWorld"))
local Service = { Name = "HarvestArtService", Order = 17 }
function Service:Init(context: any)
	if
		not run:IsStudio()
		or context.Config.Environment ~= "DEV"
		or (
			context.Config.Game.SessionMode ~= "solo_local"
			and context.Config.Game.SessionMode ~= "team_local"
		)
	then
		return
	end
	local report = HarvestWorld.Ensure()
	context.Log:Info(
		"Harvest art ready before RoundService:",
		report.variant,
		report.parts,
		report.changed
	)
end
return Service
