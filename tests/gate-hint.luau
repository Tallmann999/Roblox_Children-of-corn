-- Current gate-hint geometry/state/lifecycle methods with Lune CFrames/Instances.
-- GUI drawing is separately accepted in Studio; no world/file writes here.
local adapter = require("./scene-adapter")
local fs, r, I = adapter.fs, adapter.r, adapter.I
local V3, CF = r.Vector3, r.CFrame
local function node(name)
	return {
		Name = name,
		WaitForChild = function(_, child)
			return node(child)
		end,
	}
end
local callback, disconnected = nil, false
local services = {
	Players = { LocalPlayer = {} },
	GuiService = {},
	RunService = {
		RenderStepped = {
			Connect = function(_, fn)
				callback = fn
				return {
					Disconnect = function()
						disconnected = true
					end,
				}
			end,
		},
	},
}
local world = I.new("Workspace")
local map = I.new("Model")
map.Name = "CornMap"
map:SetAttribute("corn_project_id", "children_of_corn")
map.Parent = world
local gate = I.new("Model")
gate.Name = "EscapeGate"
gate:AddTag("corn_gate")
gate.Parent = map
local anchor = I.new("Part")
anchor.Name = "InteractionAnchor"
anchor.CFrame = CF.new(100, 20, -30) * CF.Angles(0, math.rad(37), 0)
anchor.Parent = gate
local source = fs.readFile("src/client/Controllers/GateHintController.luau")
	:gsub("anchor%.Position", "anchor.CFrame.Position")
local fn = assert(loadstring(source))
setfenv(
	fn,
	setmetatable({
		workspace = world,
		game = {
			GetService = function(_, name)
				return services[name]
			end,
		},
	}, { __index = getfenv() })
)
local Module = fn()
local destroyed = false
local gui = {
	Enabled = false,
	Destroy = function()
		destroyed = true
	end,
}
local controller = setmetatable(
	{ _shown = false, _elapsed = math.huge, _panel = { Visible = false }, _gui = gui },
	{ __index = Module }
)
local active = { phase = "active", has_key = false, gate_open = false }
controller:SetSnapshot(active)
local at = anchor.CFrame.Position
assert(controller:_gatePosition() == at)
assert(controller:_canShow(at + V3.new(22, 12, 0), at, true))
assert(not controller:_canShow(at + V3.new(22.001, 0, 0), at, true))
assert(not controller:_canShow(at + V3.new(0, 12.001, 0), at, true))
assert(controller:_canShow(at + V3.new(0, 0, -22), at, true), "Hint should work on both sides")
controller:_show(true)
assert(gui.Enabled and controller._panel.Visible)
assert(controller:_canShow(at + V3.new(24, 0, 0), at, true))
assert(not controller:_canShow(at + V3.new(24.001, 0, 0), at, true))
controller:_show(false)
assert(not controller:_canShow(at + V3.new(23, 0, 0), at, true), "Hysteresis entered too early")
for _, phase in { "ready", "preparing", "caught", "caught_out", "escaped", "aborted" } do
	controller:SetSnapshot(active)
	controller:_show(true)
	controller:SetSnapshot({ phase = phase, has_key = false, gate_open = false })
	assert(not gui.Enabled and not controller._shown and not controller:_canShow(at, at, true))
end
for _, state in
	{
		{ phase = "active", has_key = true, gate_open = false },
		{ phase = "active", has_key = false, gate_open = true },
		nil,
	}
do
	controller:SetSnapshot(active)
	controller:_show(true)
	controller:SetSnapshot(state)
	assert(not gui.Enabled and not controller:_canShow(at, at, true))
end
controller:SetSnapshot(nil)
assert(not controller:_canShow(at, at, true) and not controller._shown)
controller:SetSnapshot({ phase = "active" })
assert(not controller:_canShow(at, at, true))
controller:SetSnapshot(active)
assert(not controller:_canShow(at, at, false))
assert(not controller:_canShow(nil, at, true) and not controller:_canShow(at, nil, true))
controller:_show(true)
controller:SetSnapshot(active)
assert(controller._shown, "Same valid snapshot closed the hint")
anchor.CFrame = CF.new(-50, 5, 90) * CF.Angles(0, math.rad(-72), 0)
assert(controller:_gatePosition() == anchor.CFrame.Position)
assert(not controller:_canShow(at, anchor.CFrame.Position, true))
assert(controller:_canShow(anchor.CFrame.Position, anchor.CFrame.Position, true))
gate:RemoveTag("corn_gate")
assert(controller:_gatePosition() == nil)
gate:AddTag("corn_gate")
map:SetAttribute("corn_project_id", "foreign")
assert(controller:_gatePosition() == nil)
map:SetAttribute("corn_project_id", "children_of_corn")
anchor.Name = "Missing"
assert(controller:_gatePosition() == nil)
anchor.Name = "InteractionAnchor"
local updates = 0
controller._update = function()
	updates += 1
end
controller:Start({})
controller:Start({})
callback(0.01)
assert(updates == 1)
for _ = 1, 9 do
	callback(0.01)
end
assert(updates == 1, "Hint refreshed above10Hz")
callback(0.02)
assert(updates == 2)
controller:SetSnapshot({ phase = "ready", has_key = false, gate_open = false })
assert(
	not controller:_canShow(anchor.CFrame.Position, anchor.CFrame.Position, true),
	"Menu snapshot allowed stale hint to return"
)
controller:Destroy()
assert(disconnected and destroyed and controller._snapshot == nil and controller._connection == nil)
print(
	"PASS:22/24-radius/12height hysteresis, public moved gate binding, active/key/open/phase/dead/absent guards, unchanged snapshot,10Hz and Destroy cleanup"
)
