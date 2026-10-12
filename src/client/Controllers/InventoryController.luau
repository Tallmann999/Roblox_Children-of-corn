--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local Endpoints = require(
	ReplicatedStorage:WaitForChild("GameShared")
		:WaitForChild("Network")
		:WaitForChild("EndpointNames")
)
local Inventory = require(ReplicatedStorage.GameShared.Game:WaitForChild("Inventory"))
local Hud = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("InventoryHud"))
local player = Players.LocalPlayer
local KEY_SLOTS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
}
local Controller = { Name = "InventoryController", Order = 96 }

function Controller:Init(_context: any)
	self._snapshot = nil
	self._remote = nil
	self._minimap = nil
	self._prompts = {}
	self._connections = {}
	self._elapsed = 0
	self._lastUse = -math.huge
	self._hud = Hud.new(player:WaitForChild("PlayerGui"), UserInputService.TouchEnabled)
	self._hud:SetOnAction(function(action: string, slot: number)
		self:_request(action, slot)
	end)
	self._backpackWasEnabled = nil
	local ok, enabled = pcall(function()
		return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack)
	end)
	if ok then
		self._backpackWasEnabled = enabled
	end
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
end

function Controller:SetSnapshot(snapshot: any)
	if not snapshot or not Inventory.IsValidSnapshot(snapshot.inventory) then
		return
	end
	self._snapshot = snapshot
	self._hud:Render(snapshot.inventory, snapshot.phase, os.clock())
end

function Controller:_canAct(): boolean
	return self._snapshot ~= nil
		and self._snapshot.phase == "active"
		and not GuiService.MenuIsOpen
		and not UserInputService:GetFocusedTextBox()
		and not (self._minimap and self._minimap._expanded)
end

function Controller:_hasPrompt(): boolean
	for item in self._prompts do
		if item.Parent and item.Enabled and item.KeyboardKeyCode == Enum.KeyCode.E then
			return true
		end
	end
	return false
end

function Controller:_request(action: string, slot: number)
	if not self:_canAct() or not self._remote or slot < 1 or slot > Inventory.Capacity then
		return
	end
	if action == "use" then
		local kind = self._snapshot.inventory.slots[slot]
		if self:_hasPrompt() or (kind ~= "energy" and kind ~= "trap") then
			return
		end
		local now = os.clock()
		if now - self._lastUse < 0.25 then
			return
		end
		self._lastUse = now
	elseif action ~= "select" then
		return
	end
	self._remote:FireServer(action, slot)
end

function Controller:_input(input: InputObject, processed: boolean)
	if processed or not self:_canAct() then
		return
	end
	local slot = KEY_SLOTS[input.KeyCode]
	if slot then
		self:_request("select", slot)
	elseif input.KeyCode == Enum.KeyCode.E then
		self:_request("use", self._snapshot.inventory.selected)
	end
end

function Controller:Start(context: any)
	self._minimap = context.Controllers.MinimapController
	local folder = ReplicatedStorage:WaitForChild("GameRemotes", 10)
	assert(folder, "Inventory remotes are unavailable")
	local remote = folder:WaitForChild(Endpoints.RequestInventoryAction, 10)
	assert(remote and remote:IsA("RemoteEvent"), "Inventory action remote is unavailable")
	self._remote = remote
	table.insert(
		self._connections,
		UserInputService.InputBegan:Connect(function(input, processed)
			self:_input(input, processed)
		end)
	)
	table.insert(
		self._connections,
		ProximityPromptService.PromptShown:Connect(function(item: ProximityPrompt)
			self._prompts[item] = true
		end)
	)
	table.insert(
		self._connections,
		ProximityPromptService.PromptHidden:Connect(function(item: ProximityPrompt)
			self._prompts[item] = nil
		end)
	)
	table.insert(
		self._connections,
		RunService.RenderStepped:Connect(function(dt: number)
			self._elapsed += dt
			if self._elapsed >= 0.1 then
				self._elapsed = 0
				self._hud:Update(os.clock())
			end
		end)
	)
	-- CoreGui can be unavailable during the first Init; repeat once after startup.
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
end

function Controller:Destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	table.clear(self._prompts)
	self._hud:Destroy()
	self._snapshot = nil
	self._remote = nil
	self._minimap = nil
	if self._backpackWasEnabled ~= nil then
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, self._backpackWasEnabled)
		end)
	end
end

return Controller
