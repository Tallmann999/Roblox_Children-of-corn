-- Paste ALL of repair-corn-scene.luau into the correct scene's Studio Command Bar.
local run = game:GetService("RunService")
assert(run:IsStudio() and not run:IsRunning(), "Stop Play before Corn scene repair")
local world = game:GetService("Workspace")
assert(not world:FindFirstChild("Asmr_Base") and not world:FindFirstChild("ASMR_Models"),
    "Speed Monkey detected; nothing changed")
local map = world:FindFirstChild("CornMap")
assert(map and map:IsA("Model") and map:GetAttribute("corn_project_id") == "children_of_corn",
    "Open the installed Children_of_corn scene; nothing changed")
local function resolve(path)
    local found = game
    for _, segment in string.split(path, "/") do found = found and found:FindFirstChild(segment) end
    return found
end
local function normalized(source) return (string.gsub(source, "\r\n", "\n")) end
local editor = game:GetService("ScriptEditorService")
local freshPaths = {
    ["ReplicatedStorage/GameShared/Game/CornLayout"] = true,
    ["ServerScriptService/GameServer/Game/MapAuthoring"] = true,
}
