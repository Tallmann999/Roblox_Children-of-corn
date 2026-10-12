-- Actual engine GUI fixture, current geometry/state methods. Does not relocate the
-- player, write world geometry, request a gate action, or replace live proximity acceptance.
local player = game:GetService("Players").LocalPlayer
local Module = require(player.PlayerScripts.GameClient.Controllers.GateHintController)
local controller = setmetatable({}, { __index = Module })
controller:Init({})
controller._gui.Name = "GateHintAcceptance"
local snapshot = { phase = "active", has_key = false, gate_open = false }
local checks = {}
local ok, problem = pcall(function()
	local anchor = workspace.CornMap.EscapeGate.InteractionAnchor
	local beforeFrame, beforeSize = anchor.CFrame, anchor.Size
	local point = controller:_gatePosition()
	assert(point == anchor.Position)
	controller:SetSnapshot(snapshot)
	controller:_show(controller:_canShow(point + Vector3.new(10, 0, 0), point, true))
	assert(controller._gui.Enabled and controller._panel.Visible)
	local panel = controller._panel
	assert(panel.Headline.Text == "Нужно найти ключ")
	assert(panel.Helper.Text == "Найди ключ в одном из просветов")
	assert(panel.StopSign.StopText.Text == "STOP")
	assert(panel.StopSign.Slice1.Size.X.Offset < panel.StopSign.Slice4.Size.X.Offset)
	assert(panel.StopSign.Slice8.Size.X.Offset == panel.StopSign.Slice1.Size.X.Offset)
	for _, item in controller._gui:GetDescendants() do
		assert(not item:IsA("TextButton") and not item:IsA("ImageButton"))
		if item:IsA("GuiObject") then
			assert(not item.Active, "Passive hint became input-active")
		end
	end
	checks.public_gate_and_noninteractive_stop_popup = true
	for _, state in
		{
			{ phase = "active", has_key = true, gate_open = false },
			{ phase = "active", has_key = false, gate_open = true },
			{ phase = "caught", has_key = false, gate_open = false },
			{ phase = "ready", has_key = false, gate_open = false },
			{ phase = "escaped", has_key = false, gate_open = true },
		}
	do
		controller:SetSnapshot(snapshot)
		controller:_show(true)
		controller:SetSnapshot(state)
		assert(not controller._gui.Enabled and not controller._panel.Visible)
		assert(not controller:_canShow(point, point, true))
	end
	checks.key_open_and_phase_hide_immediately = true
	controller:SetSnapshot(snapshot)
	controller:_show(controller:_canShow(point + Vector3.new(23, 0, 0), point, true))
	assert(not controller._shown)
	controller:_show(controller:_canShow(point + Vector3.new(22, 0, 0), point, true))
	assert(controller._shown)
	controller:_show(controller:_canShow(point + Vector3.new(24, 0, 0), point, true))
	assert(controller._shown)
	controller:_show(controller:_canShow(point + Vector3.new(24.1, 0, 0), point, true))
	assert(not controller._shown)
	assert(anchor.CFrame == beforeFrame and anchor.Size == beforeSize)
	checks.hysteresis_and_world_unchanged = true
end)
controller:Destroy()
assert(ok, tostring(problem))
assert(not player.PlayerGui:FindFirstChild("GateHintAcceptance"))
checks.cleanup = true
checks.method =
	"Actual passive engine GUI + controlled geometry/state; live approach and server rejection tested separately"
return game:GetService("HttpService"):JSONEncode(checks)
