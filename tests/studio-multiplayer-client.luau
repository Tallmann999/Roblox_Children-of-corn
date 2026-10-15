-- Temporary real-client harness, installed outside GameClient only for Studio tests.
-- Uses the real gameplay remotes and engine ProximityPrompt custom-input API.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local probe = ReplicatedStorage:WaitForChild("CornMultiplayerTestProbe", 120)
assert(probe and RunService:IsStudio())
local remotes = ReplicatedStorage:WaitForChild("GameRemotes", 120)
local request = remotes:WaitForChild("request_round_action", 120)
remotes:WaitForChild("round_snapshot", 120).OnClientEvent:Connect(function(snapshot)
	local hud = player.PlayerGui:FindFirstChild("CornRoundHud")
	local active = hud and hud:FindFirstChild("ActiveStatus")
	local objective = active and active:FindFirstChild("Objective")
	probe:FireServer("snapshot", {
		phase = snapshot.phase,
		team = snapshot.team,
		has_key = snapshot.has_key,
		gate_open = snapshot.gate_open,
		evacuation = snapshot.evacuation,
		catches_remaining = snapshot.catches_remaining,
		capture_remaining = snapshot.capture.remaining,
		reward = snapshot.reward_diamonds,
		diamonds = snapshot.session_diamonds,
		inventory = snapshot.inventory,
		monster_state = snapshot.monster_state,
		hud = hud ~= nil,
		objective = objective and objective.Text or "",
		user_id = player.UserId,
	})
end)
probe.OnClientEvent:Connect(function(id, kind, argument)
	local ok, failure = pcall(function()
		if kind == "action" then
			request:FireServer(argument.action, argument.mode)
		elseif kind == "prompt" then
			local prompt = argument
			assert(prompt:IsA("ProximityPrompt") and prompt.Enabled)
			local camera = workspace.CurrentCamera
			local previousType = camera.CameraType
			local root = player.Character:FindFirstChild("HumanoidRootPart")
			game:GetService("GuiService").SelectedObject = nil
			camera.CameraType = Enum.CameraType.Scriptable
			local connection = RunService.RenderStepped:Connect(function()
				camera.CFrame = CFrame.lookAt(root.Position + Vector3.new(0, 1, 0), prompt.Parent.Position)
			end)
			task.wait(0.3)
			prompt:InputHoldBegin()
			task.wait(0.2)
			prompt:InputHoldEnd()
			connection:Disconnect()
			camera.CameraType = previousType
		elseif kind == "leave" then
			local service = game:GetService("StudioTestService")
			assert(service:CanLeaveTest(), "Client test cannot leave")
			service:LeaveTest()
		else
			error("Unknown diagnostic command")
		end
	end)
	probe:FireServer("ack", { id = id, ok = ok, failure = if ok then "" else tostring(failure) })
end)
request:FireServer("sync")
