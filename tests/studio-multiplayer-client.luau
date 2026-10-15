-- Temporary actual-client harness outside GameClient, removed after Studio test.
-- Real gameplay remotes/custom prompt input; no physical E/native-click claim.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Run = game:GetService("RunService")
local Gui = game:GetService("GuiService")
local STS = game:GetService("StudioTestService")
assert(Run:IsStudio() and Run:IsClient(), "Studio test Client required")
local player = assert(Players.LocalPlayer, "LocalPlayer missing")
local probe = assert(RS:WaitForChild("CornMultiplayerTestProbe", 120), "Test probe missing")
local remotes = assert(RS:WaitForChild("GameRemotes", 120), "Gameplay remotes missing")
local request = assert(remotes:WaitForChild("request_round_action", 120), "Round action missing")
local snapshotRemote = assert(remotes:WaitForChild("round_snapshot", 120), "Snapshot missing")
local function acknowledge(id, ok, failure, details)
	probe:FireServer("ack", { id = id, ok = ok, failure = failure or "", details = details })
end
snapshotRemote.OnClientEvent:Connect(function(snapshot)
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
local function resolvePrompt(argument)
	if typeof(argument) == "Instance" then
		return argument
	end
	assert(type(argument) == "table" and type(argument.path) == "table", "Prompt path missing")
	local item, deadline = game, os.clock() + 10
	for _, name in argument.path do
		assert(type(name) == "string", "Invalid prompt path")
		item = assert(
			item:WaitForChild(name, math.max(0.01, deadline - os.clock())),
			"Prompt did not replicate: " .. name
		)
	end
	return item
end
local function inputPrompt(argument)
	local prompt = resolvePrompt(argument)
	assert(prompt:IsA("ProximityPrompt") and prompt.Enabled, "Prompt unavailable")
	local camera = assert(workspace.CurrentCamera, "Camera missing")
	local previousType, previousFrame = camera.CameraType, camera.CFrame
	local previousSelection = Gui.SelectedObject
	local connection, lastFrame, held = nil, nil, false
	local ok, failure = xpcall(function()
		local root = assert(
			player.Character and player.Character:FindFirstChild("HumanoidRootPart"),
			"Character missing"
		)
		Gui.SelectedObject = nil
		camera.CameraType = Enum.CameraType.Scriptable
		lastFrame = CFrame.lookAt(root.Position + Vector3.new(0, 1, 0), prompt.Parent.Position)
		camera.CFrame = lastFrame
		connection = Run.RenderStepped:Connect(function()
			if not prompt.Parent or not root.Parent or workspace.CurrentCamera ~= camera then
				return
			end
			lastFrame = CFrame.lookAt(root.Position + Vector3.new(0, 1, 0), prompt.Parent.Position)
			camera.CFrame = lastFrame
		end)
		task.wait(0.3)
		held = true
		prompt:InputHoldBegin()
		task.wait(0.2)
		local ended, endProblem = pcall(function()
			prompt:InputHoldEnd()
		end)
		held = false
		-- A successful pickup destroys the prompt before its release can arrive.
		assert(ended or not prompt.Parent, tostring(endProblem))
	end, debug.traceback)
	if held then
		pcall(function()
			prompt:InputHoldEnd()
		end)
	end
	if connection then
		connection:Disconnect()
	end
	if workspace.CurrentCamera == camera and camera.CameraType == Enum.CameraType.Scriptable then
		if lastFrame and camera.CFrame == lastFrame then
			camera.CFrame = previousFrame
		end
		camera.CameraType = previousType
	end
	if Gui.SelectedObject == nil and previousSelection and previousSelection.Parent then
		Gui.SelectedObject = previousSelection
	end
	assert(ok, tostring(failure))
	return {
		render_disconnected = true,
		held_input_released = true,
		camera_cleanup_attempted = true,
	}
end
probe.OnClientEvent:Connect(function(id, kind, argument)
	if kind == "leave" then
		local allowed = STS:CanLeaveTest()
		acknowledge(
			id,
			allowed,
			if allowed then "" else "Client cannot leave test",
			{ leave_ack_before_disconnect = true }
		)
		if allowed then
			-- Let the acknowledgement enter transport before the client disconnects.
			task.delay(0.15, function()
				STS:LeaveTest()
			end)
		end
		return
	end
	local details
	local ok, failure = xpcall(function()
		if kind == "action" then
			request:FireServer(argument.action, argument.mode)
			details = {
				sent_action = argument.action,
				sent_mode = if argument.mode == nil then "<nil>" else argument.mode,
				sent_action_type = typeof(argument.action),
				sent_mode_type = typeof(argument.mode),
				sent_argument_count = 2,
				client_clock_at_send = os.clock(),
				remote_path = request:GetFullName(),
			}
		elseif kind == "prompt" then
			details = inputPrompt(argument)
		else
			error("Unknown diagnostic command: " .. tostring(kind))
		end
	end, debug.traceback)
	acknowledge(id, ok, if ok then "" else tostring(failure), details)
end)
request:FireServer("sync")
probe:FireServer("ready", {
	command_handler_connected = true,
	rendering_mode = "normal",
})
