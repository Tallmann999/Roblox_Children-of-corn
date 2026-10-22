local Players = game:GetService("Players")
local player = Players.LocalPlayer
local system = game:GetService("ReplicatedStorage"):WaitForChild("CornCTestSystem", 60)
if not system then
	warn("Scene C system unavailable; server visibility preserved")
	return
end
local world = workspace:WaitForChild("CornCTestWorld", 60)
if not world then
	warn("Scene C world unavailable; server visibility preserved")
	return
end
local ready, problem = pcall(function()
	local sceneModule = assert(system:WaitForChild("Scene", 60), "Scene C module unavailable")
	local Scene = require(sceneModule)
	Scene.WaitForServerDecor(60)
	Scene.Ensure("Client")
end)
if not ready then
	warn("Scene C local preparation failed; server visibility preserved: " .. tostring(problem))
	return
end
player.CameraMode = Enum.CameraMode.LockFirstPerson
local gui = Instance.new("ScreenGui")
gui.Name = "CornCTestInstructions"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
local label = Instance.new("TextLabel")
label.Name = "Instructions"
label.Size = UDim2.fromOffset(430, 66)
label.Position = UDim2.fromOffset(16, 16)
label.BackgroundColor3 = Color3.fromRGB(27, 34, 22)
label.BackgroundTransparency = 0.15
label.BorderSizePixel = 0
label.TextColor3 = Color3.fromRGB(239, 240, 219)
label.Font = Enum.Font.GothamMedium
label.TextSize = 16
label.Text =
	"СЦЕНА C · исходная кукуруза 8 studs\nWASD — ходьба · мышь — обзор · растения проходимы"
label.Parent = gui
gui.Parent = player:WaitForChild("PlayerGui")
print("Corn C local geometry ready: 288 corn / 68 grass / 12 soil")
