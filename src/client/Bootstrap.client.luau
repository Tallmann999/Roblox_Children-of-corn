--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameShared = ReplicatedStorage:WaitForChild("GameShared")
local Config = require(GameShared:WaitForChild("Config"):WaitForChild("GameConfig"))
local Workspace = game:GetService("Workspace")
local map = Workspace:WaitForChild("CornMap", 10)
if
	not map
	or map:GetAttribute("corn_project_id") ~= "children_of_corn"
	or Workspace:FindFirstChild("Asmr_Base")
	or Workspace:FindFirstChild("ASMR_Models")
then
	warn("[ChildrenOfCorn] Inactive: editable CornMap missing or another game detected")
	return
end
local Logger = require(GameShared:WaitForChild("Core"):WaitForChild("Logger"))
local log = Logger.new("ClientBootstrap", Config.Debug)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
if
	not RunService:IsStudio()
	or Config.Environment ~= "DEV"
	or (Config.Game.SessionMode ~= "solo_local" and Config.Game.SessionMode ~= "team_local")
then
	warn("[ChildrenOfCorn] Inactive: this local prototype requires Studio DEV mode")
	return
end
local Endpoints = require(GameShared:WaitForChild("Network"):WaitForChild("EndpointNames"))
local STARTUP_TIMEOUT = 60
local deadline = os.clock() + STARTUP_TIMEOUT
local loading: ScreenGui? = nil
local function uniqueChild(parent: Instance, name: string): Instance?
	local found: Instance? = nil
	for _, child in parent:GetChildren() do
		if child.Name == name then
			assert(not found, "Duplicate server readiness binding: " .. name)
			found = child
		end
	end
	return found
end
local function ready(): (boolean, string)
	local remotes = uniqueChild(ReplicatedStorage, "GameRemotes")
	if not remotes then
		return false, "GameRemotes"
	end
	assert(remotes:IsA("Folder"), "GameRemotes must be a Folder")
	for _, name in
		{
			Endpoints.RequestRoundAction,
			Endpoints.RoundSnapshot,
			Endpoints.RequestSprintIntent,
			Endpoints.RequestInventoryAction,
		}
	do
		local endpoint = uniqueChild(remotes, name)
		if not endpoint then
			return false, name
		end
		assert(endpoint:IsA("RemoteEvent"), "Server endpoint must be a RemoteEvent: " .. name)
	end
	local art = uniqueChild(ReplicatedStorage, "CornRuntimeArt")
	if not art then
		return false, "CornRuntimeArt"
	end
	assert(art:IsA("Folder"), "CornRuntimeArt must be a Folder")
	local owner, project =
		art:GetAttribute("CornRuntimeArtOwned"), art:GetAttribute("corn_project_id")
	assert(owner == nil or owner == true, "CornRuntimeArt has foreign ownership")
	assert(
		project == nil or project == "children_of_corn",
		"CornRuntimeArt belongs to another project"
	)
	if owner ~= true or project ~= "children_of_corn" then
		return false, "CornRuntimeArt ownership"
	end
	local template = uniqueChild(art, "CornPlantTemplate")
	if not template then
		return false, "CornPlantTemplate"
	end
	assert(template:IsA("MeshPart"), "CornPlantTemplate must be a MeshPart")
	local templateOwner = template:GetAttribute("CornPlantTemplateOwned")
	assert(templateOwner == nil or templateOwner == true, "CornPlantTemplate has foreign ownership")
	if templateOwner ~= true then
		return false, "CornPlantTemplate ownership"
	end
	local mesh = template :: MeshPart
	if
		not mesh.Anchored
		or not mesh.Archivable
		or mesh.CanCollide
		or mesh.CanTouch
		or mesh.CanQuery
		or mesh.MeshId == ""
	then
		return false, "CornPlantTemplate static art"
	end
	for _, value in { mesh.Size.X, mesh.Size.Y, mesh.Size.Z } do
		assert(
			value == value and value > 0 and value < math.huge,
			"CornPlantTemplate has invalid Size"
		)
	end
	for _, child in template:GetDescendants() do
		assert(
			not child:IsA("LuaSourceContainer")
				and not child:IsA("Sound")
				and not child:IsA("ParticleEmitter")
				and not child:IsA("Beam")
				and not child:IsA("Trail")
				and not child:IsA("ProximityPrompt")
				and not child:IsA("ClickDetector")
				and not child:IsA("RemoteEvent")
				and not child:IsA("RemoteFunction"),
			"CornPlantTemplate must contain only static art"
		)
	end
	return true, ""
end
local readinessOk, problem = pcall(function()
	local player = assert(Players.LocalPlayer, "Local player unavailable during startup")
	local gui = player:FindFirstChild("PlayerGui")
	while not gui and os.clock() < deadline do
		task.wait(math.min(0.1, deadline - os.clock()))
		gui = player:FindFirstChild("PlayerGui")
	end
	assert(os.clock() <= deadline, "Server map readiness timed out after 60 seconds: PlayerGui")
	assert(gui and gui:IsA("PlayerGui"), "PlayerGui unavailable before startup deadline")
	local screen = Instance.new("ScreenGui")
	loading = screen
	screen.Name = "ChildrenOfCornLoading"
	screen:SetAttribute("CornLoadingOwned", true)
	screen:SetAttribute("corn_project_id", "children_of_corn")
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 1000
	local background = Instance.new("Frame")
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Color3.fromRGB(15, 19, 14)
	background.BackgroundTransparency = 0.12
	background.BorderSizePixel = 0
	background.Parent = screen
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -40, 0, 64)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 24
	label.TextColor3 = Color3.fromRGB(244, 231, 192)
	label.Text = "Подготовка карты…"
	label.Parent = background
	screen.Parent = gui
	local available, missing = ready()
	while not available do
		local remaining = deadline - os.clock()
		assert(remaining > 0, "Server map readiness timed out after 60 seconds: " .. missing)
		task.wait(math.min(0.1, remaining))
		assert(
			os.clock() <= deadline,
			"Server map readiness timed out after 60 seconds: " .. missing
		)
		available, missing = ready()
	end
	assert(
		os.clock() <= deadline,
		"Server map readiness timed out after 60 seconds: server bindings"
	)
end)
if loading then
	loading:Destroy()
end
if not readinessOk then
	error("[ChildrenOfCorn] Client startup failed before controllers: " .. tostring(problem))
end

local controllersFolder = script.Parent:WaitForChild("Controllers")

type RuntimeModule = {
	Name: string?,
	Order: number?,
	Init: ((self: RuntimeModule, context: any) -> ())?,
	Start: ((self: RuntimeModule, context: any) -> ())?,
}

local loaded: { RuntimeModule } = {}
local byName: { [string]: RuntimeModule } = {}

for _, child in controllersFolder:GetChildren() do
	if child:IsA("ModuleScript") then
		local ok, result = pcall(require, child)
		if not ok then
			error(
				string.format(
					"Failed to require controller %s: %s",
					child:GetFullName(),
					tostring(result)
				)
			)
		end
		if type(result) ~= "table" then
			error(string.format("Controller %s must return a table", child:GetFullName()))
		end
		local module = result :: RuntimeModule
		local name = module.Name or child.Name
		if byName[name] then
			error(string.format("Duplicate controller name: %s", name))
		end
		module.Name = name
		byName[name] = module
		table.insert(loaded, module)
	end
end

table.sort(loaded, function(a, b)
	return (a.Order or 100) < (b.Order or 100)
end)

local context = {
	Config = Config,
	Controllers = byName,
	Log = Logger.new("Client", Config.Debug),
}

for _, module in loaded do
	if module.Init then
		module:Init(context)
	end
end

for _, module in loaded do
	if module.Start then
		module:Start(context)
	end
end

log:Info(string.format("Started %d controllers", #loaded))
