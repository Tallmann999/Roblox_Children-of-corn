-- Existing imported model/server/remote topology; haze settings are authoritative.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local root = script.Parent
local config = require(root:WaitForChild("Config"))
local runtimeName = "CornfieldFogRuntime"
local previous = ReplicatedStorage:FindFirstChild(runtimeName)
if previous then
	local previousOwner = previous:FindFirstChild("Owner")
	if
		previousOwner
		and previousOwner:IsA("ObjectValue")
		and (not previousOwner.Value or not previousOwner.Value:IsDescendantOf(game))
	then
		-- Studio Delete can unparent the model without firing Destroying.
		previous:Destroy()
		previous = nil
	end
end
if previous then
	warn("[CornfieldFog] A controller already exists. Keep only one CornfieldFog model.")
	return
end

local function finite(n)
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end
local function number(n, fallback, low, high)
	if not finite(n) then
		n = fallback
	end
	return math.clamp(n, low, high)
end
local minSteps = number(config.MinSteps, 10, 1, 1000)
local maxSteps = number(config.MaxSteps, 120, minSteps, 1000)
local presets = config.Presets
local function canEdit(player)
	if config.PanelInStudio and RunService:IsStudio() then
		return true
	end
	if
		config.AllowExperienceOwner
		and game.CreatorType == Enum.CreatorType.User
		and player.UserId == game.CreatorId
	then
		return true
	end
	return table.find(config.AdminUserIds, player.UserId) ~= nil
end

local runtime = Instance.new("Folder")
runtime.Name = runtimeName
local remote = Instance.new("RemoteEvent")
remote.Name = "Control"
remote.Parent = runtime
local owner = Instance.new("ObjectValue")
owner.Name = "Owner"
owner.Value = root
owner.Parent = runtime
local defaultPreset = if config.Preset == "Auto"
		or typeof(presets[config.Preset]) == "Color3"
	then config.Preset
	else "Auto"
local boosts = config.HazeBoost or {}
local defaults = {
	Enabled = config.Enabled ~= false,
	Steps = number(config.Steps, 20, minSteps, maxSteps),
	StartRatio = number(config.StartRatio, 0.2, 0, 0.8),
	FogColor = presets[defaultPreset] or presets.Field,
	Preset = defaultPreset,
	HazeDay = number(boosts.Day, 0.5, 0, 2),
	HazeDusk = number(boosts.Dusk, 0.85, 0, 2),
	HazeNight = number(boosts.Night, 1, 0, 2),
	MaxDensity = number(config.MaxDensity, 0.36, 0, 0.5),
	MaxHaze = number(config.MaxHaze, 2.8, 0, 3),
	FieldOnly = config.FieldOnly == true,
	FieldCenter = config.FieldCenter,
	FieldSize = config.FieldSize,
	EdgeFadeStuds = number(config.EdgeFadeStuds, 30, 0, 420),
}
runtime:SetAttribute("MinSteps", minSteps)
runtime:SetAttribute("MaxSteps", maxSteps)
for key, value in defaults do
	runtime:SetAttribute(key, value)
end
-- Publish a completely initialized state, so joining clients cannot read partial defaults.
runtime.Parent = ReplicatedStorage

local connections = {}
local installed = {}
local installing = {}
local lastRequest = {}
local alive = true
local template = script:WaitForChild("ClientTemplate")

local function install(player)
	if installing[player] or installed[player] then
		return
	end
	installing[player] = true
	local playerGui = player:WaitForChild("PlayerGui", 20)
	if not alive or not playerGui or player.Parent ~= Players then
		installing[player] = nil
		return
	end
	player:SetAttribute("CornfieldFogCanEdit", canEdit(player))
	local bootstrap = Instance.new("ScreenGui")
	bootstrap.Name = "CornfieldFogBootstrap"
	bootstrap.ResetOnSpawn = false
	local runtimeReference = Instance.new("ObjectValue")
	runtimeReference.Name = "Runtime"
	runtimeReference.Value = runtime
	runtimeReference.Parent = bootstrap
	bootstrap.Parent = playerGui
	local client = template:Clone()
	client.Name = "CornfieldFogClient"
	client.Enabled = true
	installed[player] = bootstrap
	installing[player] = nil
	client.Parent = bootstrap
end

connections[#connections + 1] = remote.OnServerEvent:Connect(function(player, request)
	if not canEdit(player) or type(request) ~= "table" then
		return
	end
	local now = os.clock()
	if now - (lastRequest[player] or -math.huge) < 0.08 then
		return
	end
	lastRequest[player] = now
	if request.Reset == true then
		for key, value in defaults do
			runtime:SetAttribute(key, value)
		end
		return
	end
	-- Only these small, validated fields may be changed by the control panel.
	if finite(request.Steps) then
		runtime:SetAttribute(
			"Steps",
			math.floor(math.clamp(request.Steps, minSteps, maxSteps) * 10 + 0.5) / 10
		)
	end
	if finite(request.StartRatio) then
		runtime:SetAttribute("StartRatio", math.clamp(request.StartRatio, 0, 0.8))
	end
	if type(request.Enabled) == "boolean" then
		runtime:SetAttribute("Enabled", request.Enabled)
	end
	if
		type(request.Preset) == "string"
		and (request.Preset == "Auto" or typeof(presets[request.Preset]) == "Color3")
	then
		runtime:SetAttribute("Preset", request.Preset)
		if request.Preset ~= "Auto" then
			runtime:SetAttribute("FogColor", presets[request.Preset])
		end
	end
end)
connections[#connections + 1] = Players.PlayerAdded:Connect(function(player)
	task.spawn(install, player)
end)
connections[#connections + 1] = Players.PlayerRemoving:Connect(function(player)
	installed[player] = nil
	installing[player] = nil
	lastRequest[player] = nil
end)
for _, player in Players:GetPlayers() do
	task.spawn(install, player)
end

local function cleanup()
	if not alive then
		return
	end
	alive = false
	for _, connection in connections do
		connection:Disconnect()
	end
	-- Clients observe Destroying / removal and restore their original Lighting.
	runtime:Destroy()
	for player in installed do
		if player.Parent == Players then
			player:SetAttribute("CornfieldFogCanEdit", nil)
		end
	end
end
script.Destroying:Connect(cleanup)
root.Destroying:Connect(cleanup)
runtime.Destroying:Connect(cleanup)
connections[#connections + 1] = root.AncestryChanged:Connect(function()
	if not root:IsDescendantOf(game) then
		cleanup()
	end
end)
connections[#connections + 1] = script.AncestryChanged:Connect(function()
	if not script:IsDescendantOf(root) then
		cleanup()
	end
end)
connections[#connections + 1] = runtime.AncestryChanged:Connect(function()
	if runtime.Parent ~= ReplicatedStorage then
		cleanup()
	end
end)
