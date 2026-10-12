--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local CollectionService = game:GetService("CollectionService")

local Geometry = require(
	ReplicatedStorage:WaitForChild("GameShared")
		:WaitForChild("Game")
		:WaitForChild("MinimapGeometry")
)
local MinimapHud = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("MinimapHud"))
local player = Players.LocalPlayer
local MinimapController = { Name = "MinimapController", Order = 95 }
local VISIBLE_PHASES =
	{ active = true, caught = true, escaped = true, aborted = true, caught_out = true }

function MinimapController:Init(_context: any)
	self._hud = MinimapHud.new(player:WaitForChild("PlayerGui"))
	self._snapshot = nil
	self._field = nil
	self._expanded = false
	self._visible = false
	self._elapsed = math.huge
	self._connections = {}
	self._movement = nil
	self._hud:SetOnExpand(function()
		self:SetExpanded(true)
	end)
	self._hud:SetOnClose(function()
		self:SetExpanded(false)
	end)
end

function MinimapController:SetExpanded(expanded: boolean)
	expanded = expanded and self._visible
	if self._expanded == expanded then
		return
	end
	self._expanded = expanded
	self._hud:SetExpanded(expanded)
	if self._movement then
		self._movement:SetMapOpen(expanded)
	end
end

function MinimapController:SetSnapshot(snapshot: any)
	local previous = self._snapshot
	if
		not previous
		or previous.phase ~= snapshot.phase
		or previous.minimap.round_id ~= snapshot.minimap.round_id
	then
		self:SetExpanded(false)
		self._elapsed = math.huge
	end
	self._snapshot = snapshot
	self._visible = VISIBLE_PHASES[snapshot.phase] == true
	self._hud:SetVisible(self._visible)
	self._hud:SetSnapshot(snapshot)
end

function MinimapController:_gatePosition(field: BasePart): Vector3?
	local map = workspace:FindFirstChild("CornMap")
	if
		not map
		or not map:IsA("Model")
		or map:GetAttribute("corn_project_id") ~= "children_of_corn"
		or not field:IsDescendantOf(map)
	then
		return nil
	end
	local gate = map:FindFirstChild("EscapeGate")
	if not gate or not gate:IsA("Model") or not gate:HasTag("corn_gate") then
		return nil
	end
	local anchor = gate:FindFirstChild("InteractionAnchor")
	return if anchor and anchor:IsA("BasePart") then anchor.Position else nil
end

function MinimapController:_update()
	if not self._visible then
		return
	end
	local field = self._field
	if not field or not field:IsDescendantOf(workspace) then
		self._field = nil
		local map = workspace:FindFirstChild("CornMap")
		if map and map:GetAttribute("corn_project_id") == "children_of_corn" then
			for _, candidate in CollectionService:GetTagged("corn_field_zone") do
				if candidate:IsA("BasePart") and candidate:IsDescendantOf(map) then
					self._field = candidate
					break
				end
			end
		end
		field = self._field
	end
	if not field or field.Size.X <= 0 or field.Size.Z <= 0 then
		return
	end
	local position = nil
	local direction = nil
	local snapshot = self._snapshot
	if snapshot and (snapshot.phase == "active" or snapshot.phase == "caught") then
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			position = root.Position
			direction = root.CFrame.LookVector
		end
	end
	local camera = workspace.CurrentCamera
	if camera then
		local topLeft, bottomRight = GuiService:GetGuiInset()
		self._hud:SetViewport(camera.ViewportSize - topLeft - bottomRight)
	end
	self._hud:Update(field.CFrame, field.Size, position, direction, self:_gatePosition(field))
end

function MinimapController:_input(input: InputObject, processed: boolean)
	if UserInputService:GetFocusedTextBox() then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape then
		if self._expanded then
			self:SetExpanded(false)
		end
	elseif input.KeyCode == Enum.KeyCode.M and not processed and self._visible then
		self:SetExpanded(not self._expanded)
	end
end

function MinimapController:Start(context: any)
	self._movement = context.Controllers.MovementController
	table.insert(
		self._connections,
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			self:_input(input, processed)
		end)
	)
	table.insert(
		self._connections,
		GuiService.MenuOpened:Connect(function()
			self:SetExpanded(false)
		end)
	)
	table.insert(
		self._connections,
		RunService.RenderStepped:Connect(function(dt: number)
			self._elapsed += dt
			if self._elapsed >= 1 / Geometry.UpdateHz then
				self._elapsed = 0
				self:_update()
			end
		end)
	)
end

function MinimapController:Destroy()
	self:SetExpanded(false)
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	self._hud:Destroy()
	self._snapshot = nil
	self._field = nil
	self._movement = nil
end

return MinimapController
