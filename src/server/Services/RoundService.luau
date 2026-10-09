--!strict

local RunService = game:GetService("RunService")
local SoloRound = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("SoloRound"))

local RoundService = { Name = "RoundService", Order = 30 }
local runtime: any = nil

function RoundService:Init(context: any)
	if
		not RunService:IsStudio()
		or context.Config.Environment ~= "DEV"
		or context.Config.Game.SessionMode ~= "solo_local"
	then
		context.Log:Warn("Temporary solo prototype is available only in Studio DEV mode")
		return
	end
	runtime = SoloRound.new(context)
end

function RoundService:Start()
	if runtime then
		runtime:Start()
	end
end

return RoundService
