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
local log = Logger.new("ServerBootstrap", Config.Debug)

local servicesFolder = script.Parent:WaitForChild("Services")

type RuntimeModule = {
	Name: string?,
	Order: number?,
	Init: ((self: RuntimeModule, context: any) -> ())?,
	Start: ((self: RuntimeModule, context: any) -> ())?,
}

local loaded: { RuntimeModule } = {}
local byName: { [string]: RuntimeModule } = {}

for _, child in servicesFolder:GetChildren() do
	if child:IsA("ModuleScript") then
		local ok, result = pcall(require, child)
		if not ok then
			error(
				string.format(
					"Failed to require service %s: %s",
					child:GetFullName(),
					tostring(result)
				)
			)
		end
		if type(result) ~= "table" then
			error(string.format("Service %s must return a table", child:GetFullName()))
		end
		local module = result :: RuntimeModule
		local name = module.Name or child.Name
		if byName[name] then
			error(string.format("Duplicate service name: %s", name))
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
	Services = byName,
	Log = Logger.new("Server", Config.Debug),
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

log:Info(string.format("Started %d services", #loaded))
