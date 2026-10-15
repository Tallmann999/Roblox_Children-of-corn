--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameShared = ReplicatedStorage:WaitForChild("GameShared")
local EndpointNames = require(GameShared:WaitForChild("Network"):WaitForChild("EndpointNames"))
local LightingModes = require(GameShared:WaitForChild("Game"):WaitForChild("LightingModes"))
local MinimapGeometry = require(GameShared:WaitForChild("Game"):WaitForChild("MinimapGeometry"))
local Inventory = require(GameShared:WaitForChild("Game"):WaitForChild("Inventory"))
local Capture = require(GameShared:WaitForChild("Game"):WaitForChild("CapturePresentation"))
local RoundHud = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("RoundHud"))

type Snapshot = RoundHud.Snapshot

local RoundController = {
	Name = "RoundController",
	Order = 100,
	_snapshot = nil :: Snapshot?,
	_requestRemote = nil :: RemoteEvent?,
	_snapshotConnection = nil :: RBXScriptConnection?,
	_lastRequest = -math.huge,
	_hud = nil :: any,
}

local PHASES: { [string]: boolean } = {
	ready = true,
	preparing = true,
	active = true,
	escaped = true,
	aborted = true,
	caught = true,
	caught_out = true,
}
local ACTIONS: { [string]: boolean } = {
	start = true,
	retry = true,
	abort = true,
	menu = true,
	revive = true,
}
local DEBOUNCE_SEC = 0.55
local REMOTE_WAIT_SEC = 10

local function nonnegativeNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value >= 0 and value < math.huge
end

local function validSnapshot(value: any): boolean
	return typeof(value) == "table"
		and LightingModes.IsValid(value.lighting_mode)
		and MinimapGeometry.IsValid(value.minimap)
		and Inventory.IsValidSnapshot(value.inventory)
		and Capture.IsValidSnapshot(value.capture)
		and typeof(value.phase) == "string"
		and PHASES[value.phase] == true
		and (value.phase == "caught" or value.capture.remaining == 0)
		and typeof(value.has_key) == "boolean"
		and typeof(value.gate_open) == "boolean"
		and (value.evacuation == nil or (typeof(value.evacuation) == "table" and typeof(
			value.evacuation.active
		) == "boolean" and value.evacuation.duration == 120 and nonnegativeNumber(
			value.evacuation.remaining
		) and value.evacuation.remaining <= 120 and (value.evacuation.active or value.evacuation.remaining == 0)))
		and nonnegativeNumber(value.session_diamonds)
		and nonnegativeNumber(value.reward_diamonds)
		and nonnegativeNumber(value.elapsed_sec)
		and typeof(value.notice) == "string"
		and nonnegativeNumber(value.stamina)
		and nonnegativeNumber(value.stamina_capacity)
		and value.stamina_capacity > 0
		and value.stamina <= value.stamina_capacity
		and typeof(value.is_sprinting) == "boolean"
		and typeof(value.sprint_exhausted) == "boolean"
		and nonnegativeNumber(value.catches_remaining)
		and value.catches_remaining <= 2
		and value.catches_remaining % 1 == 0
		and typeof(value.monster_state) == "string"
		and ({
			dormant = true,
			patrol = true,
			chase = true,
			stopped = true,
			trapped = true,
			capturing = true,
		})[value.monster_state] == true
		and nonnegativeNumber(value.protection_sec)
		and typeof(value.start_look) == "Vector3"
		and value.start_look.Magnitude > 0.99
		and value.start_look.Magnitude < 1.01
		and math.abs(value.start_look.Y) < 0.001
end

local function getRemote(folder: Instance, name: string): RemoteEvent?
	local instance = folder:WaitForChild(name, REMOTE_WAIT_SEC)
	if not instance or not instance:IsA("RemoteEvent") then
		warn(
			string.format(
				"[RoundController] RemoteEvent %s is unavailable after %ds",
				name,
				REMOTE_WAIT_SEC
			)
		)
		return nil
	end
	return instance
end

function RoundController:Init(_context: any)
	self._snapshot = nil :: Snapshot?
	self._requestRemote = nil :: RemoteEvent?
	self._snapshotConnection = nil :: RBXScriptConnection?
	self._lastRequest = -math.huge
	self._hud = nil

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui", REMOTE_WAIT_SEC)
	if not playerGui or not playerGui:IsA("PlayerGui") then
		warn("[RoundController] PlayerGui is unavailable; the round interface was not created")
		return
	end
	self._hud = RoundHud.new(playerGui)
	self._hud:SetOnAction(function(action: string, mode: string?)
		self:_request(action, mode)
	end)
end

function RoundController:_request(action: string, mode: string?)
	local remote = self._requestRemote
	local hud = self._hud
	if
		not remote
		or not hud
		or hud._unavailable
		or not self._snapshot
		or ACTIONS[action] ~= true
	then
		return
	end
	if (action == "start" or action == "retry") and not LightingModes.IsValid(mode) then
		return
	end
	if action == "start" and self._snapshot.phase ~= "ready" then
		return
	end
	if
		action == "revive"
		and (
			mode ~= nil
			or self._snapshot.phase ~= "caught"
			or self._snapshot.capture.remaining ~= 0
			or self._snapshot.catches_remaining ~= 1
			or hud._captureActive
		)
	then
		return
	end
	if
		action == "retry"
		and self._snapshot.phase ~= "escaped"
		and self._snapshot.phase ~= "aborted"
		and self._snapshot.phase ~= "caught_out"
	then
		return
	end
	local now = os.clock()
	if now - self._lastRequest < DEBOUNCE_SEC then
		return
	end
	self._lastRequest = now
	hud:SetBusy(true)
	remote:FireServer(action, mode)
	-- Only the server changes the view. A rejected request must not leave buttons stuck.
	task.delay(DEBOUNCE_SEC, function()
		if self._hud == hud then
			hud:SetBusy(false)
		end
	end)
end

function RoundController:Start(context: any)
	local hud = self._hud
	if not hud then
		return
	end
	local folder = ReplicatedStorage:WaitForChild("GameRemotes", REMOTE_WAIT_SEC)
	if not folder or not folder:IsA("Folder") then
		warn("[RoundController] GameRemotes is unavailable; check RoundService startup in Output")
		hud:ShowUnavailable()
		return
	end
	local requestRemote = getRemote(folder, EndpointNames.RequestRoundAction)
	local snapshotRemote = getRemote(folder, EndpointNames.RoundSnapshot)
	if not requestRemote or not snapshotRemote then
		hud:ShowUnavailable()
		return
	end
	self._requestRemote = requestRemote
	self._snapshotConnection = snapshotRemote.OnClientEvent:Connect(function(payload: any)
		if not validSnapshot(payload) then
			self._snapshot = nil
			hud:ShowUnavailable()
			context.Controllers.CaptureController:Cancel("malformed snapshot")
			context.Controllers.HandheldController:Clear("malformed snapshot")
			context.Controllers.AudioController:Clear("malformed snapshot")
			warn("[RoundController] Ignored a malformed round_snapshot")
			return
		end
		self._snapshot = payload :: Snapshot
		context.Controllers.CaptureController:SetSnapshot(payload)
		hud:Render(payload :: Snapshot)
		context.Controllers.MovementController:SetSnapshot(payload)
		context.Controllers.MinimapController:SetSnapshot(payload)
		context.Controllers.InventoryController:SetSnapshot(payload)
		context.Controllers.HandheldController:SetSnapshot(payload)
		context.Controllers.AudioController:SetSnapshot(payload)
		context.Controllers.CornController:SetLightingMode(
			if payload.phase == "ready" then nil else payload.lighting_mode
		)
		local cornMode = if payload.phase == "ready" then nil else payload.lighting_mode
		context.Controllers.CornAppearanceController:SetMode(cornMode)
		context.Controllers.CornWindController:SetMode(cornMode)
		context.Controllers.GateHintController:SetSnapshot(payload)
	end)

	-- Subscribe first: initial server messages may precede the client controller.
	requestRemote:FireServer("sync")
	task.delay(2, function()
		if self._hud == hud and self._snapshot == nil then
			requestRemote:FireServer("sync")
		end
	end)
	task.delay(REMOTE_WAIT_SEC, function()
		if self._hud == hud and self._snapshot == nil then
			warn("[RoundController] No valid initial round_snapshot; check RoundService Output")
			hud:ShowUnavailable()
		end
	end)
end

function RoundController:Destroy()
	if self._snapshotConnection then
		self._snapshotConnection:Disconnect()
		self._snapshotConnection = nil
	end
	if self._hud then
		self._hud:Destroy()
		self._hud = nil
	end
	self._requestRemote = nil
	self._snapshot = nil
end

return RoundController
