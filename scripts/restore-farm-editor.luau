-- Run through Studio MCP/Command Bar after reopening the saved local place.
-- EditableMesh objects are peer-local; saved geometry data is authoritative.
assert(
	game.RunService:IsStudio() and not game.RunService:IsRunning(),
	"Stopped Studio Edit required"
)
local map = workspace:FindFirstChild("CornMap")
assert(map and map:GetAttribute("corn_project_id") == "children_of_corn", "Wrong project")
assert(
	not workspace:FindFirstChild("ASMR_Models") and not workspace:FindFirstChild("Asmr_Base"),
	"Wrong scene"
)
local code = game.ServerScriptService:FindFirstChild("GameServer")
local geometry = code and code:FindFirstChild("Game") and code.Game:FindFirstChild("FarmGeometry")
assert(geometry and geometry:IsA("ModuleScript"), "Farm geometry code missing")
return require(geometry).Ensure()
