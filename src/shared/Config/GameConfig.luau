--!strict

local Balance = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("Balance"))

return {
	Environment = "DEV",
	Debug = true,
	Game = {
		Id = "children_of_corn",
		Name = "Дети кукурузы",
		Version = "0.1.0",
		SessionMode = "solo_local",
		SupportedDevice = "pc",
	},
	CoreLoop = Balance,
	Persistence = {
		Enabled = false,
		StoreName = "PlayerData_v1",
		SchemaVersion = 1,
	},
}
