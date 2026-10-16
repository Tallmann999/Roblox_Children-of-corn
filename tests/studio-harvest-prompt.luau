-- Diagnostic actual client prompt input, with server-positioned character.
-- Prefix this file with local targetPath={...}. Not a physical keyboard/UI test.
local Run = game:GetService("RunService")
local Gui = game:GetService("GuiService")
assert(Run:IsStudio() and Run:IsClient() and Run:IsRunning())
local target = game
for _, name in targetPath do
	target = assert(target:FindFirstChild(name), "Prompt path missing: " .. name)
end
assert(target:IsA("ProximityPrompt") and target.Enabled)
local player = game.Players.LocalPlayer
local root = assert(player.Character and player.Character:FindFirstChild("HumanoidRootPart"))
local camera = workspace.CurrentCamera
local oldFrame, oldType, oldSelection = camera.CFrame, camera.CameraType, Gui.SelectedObject
local connection, held, last = nil, false, nil
local result = { method = "Engine InputHoldBegin/End; diagnostic position and temporary camera aim" }
local ok, problem = pcall(function()
	Gui.SelectedObject = nil
	camera.CameraType = Enum.CameraType.Scriptable
	local function aim()
		if target.Parent then
			last = CFrame.lookAt(root.Position + Vector3.new(0, 1, 0), target.Parent.Position)
			camera.CFrame = last
		end
	end
	aim()
	connection = Run.RenderStepped:Connect(aim)
	task.wait(0.4)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	local ray = workspace:Raycast(camera.CFrame.Position, target.Parent.Position - camera.CFrame.Position, params)
	result.ray = ray and ray.Instance:GetFullName() or "clear/nohit"
	result.distance = (root.Position - target.Parent.Position).Magnitude
	result.menuOpen = Gui.MenuIsOpen
	held = true
	target:InputHoldBegin()
	task.wait(0.2)
	local released, releaseError = pcall(function()
		target:InputHoldEnd()
	end)
	held = false
	assert(released or not target.Parent, tostring(releaseError))
end)
if connection then
	connection:Disconnect()
end
if held then
	pcall(function()
		target:InputHoldEnd()
	end)
end
if workspace.CurrentCamera == camera and (last == nil or camera.CFrame == last) then
	camera.CFrame, camera.CameraType = oldFrame, oldType
end
if Gui.SelectedObject == nil then
	Gui.SelectedObject = oldSelection
end
assert(ok, problem)
result.inputCompleted = true
return game:GetService("HttpService"):JSONEncode(result)
