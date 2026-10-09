--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameShared = ReplicatedStorage:WaitForChild("GameShared")
local Config = require(GameShared:WaitForChild("Config"):WaitForChild("GameConfig"))
local Logger = require(GameShared:WaitForChild("Core"):WaitForChild("Logger"))
local log = Logger.new("ClientBootstrap", Config.Debug)

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
