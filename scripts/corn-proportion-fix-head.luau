-- Paste ALL of fix-corn-proportions.luau into Children_of_corn Studio Command Bar.
-- Corrects proportions in place; no field, props, spawns or imported art are rebuilt.
local run = game:GetService("RunService")
assert(run:IsStudio() and not run:IsRunning(), "Stop Play before correcting corn proportions; nothing changed")
local world = game:GetService("Workspace")
assert(not world:FindFirstChild("Asmr_Base") and not world:FindFirstChild("ASMR_Models"),
    "Speed Monkey detected; nothing changed")
local map = world:FindFirstChild("CornMap")
assert(map and map:IsA("Model") and map:GetAttribute("corn_project_id") == "children_of_corn",
    "Open the installed Children_of_corn scene; nothing changed")
local function resolve(path)
    local item = game
    for _, name in string.split(path, "/") do item = item and item:FindFirstChild(name) end
    return item
end
local function normalized(source) return (string.gsub(source, "\r\n", "\n")) end
local author = resolve("ServerScriptService/GameServer/Game/MapAuthoring")
assert(author and author:IsA("ModuleScript"), "MapAuthoring missing; nothing changed")
assert(#author:GetChildren() == 0 and author.Archivable,
    "MapAuthoring contains extra objects or cannot be cloned; nothing changed")
local editor = game:GetService("ScriptEditorService")
assert(editor:FindScriptDocument(author) == nil, "Close the MapAuthoring script tab; nothing changed")
