--!strict
local storage = game:GetService("ReplicatedStorage")
local Builder = require(
	storage:WaitForChild("GameShared"):WaitForChild("Game"):WaitForChild("FarmEditableMeshBuilder")
)
local runtime = Builder.newRuntime("server")
local FarmGeometry = {}
function FarmGeometry.new(): any
	return Builder.newRuntime("server")
end
function FarmGeometry.Ensure(): any
	return runtime:Ensure()
end
function FarmGeometry.Destroy()
	runtime:Destroy()
end
return FarmGeometry
