-- Current client gate-binding method with real in-memory Lune Instances.
-- No Studio renderer/networking or place-file writes; Position coupling adapted.
local adapter = require("./scene-adapter")
local fs, r, I = adapter.fs, adapter.r, adapter.I
local CF, V3 = r.CFrame, r.Vector3
local Geometry = (function()
	local fn = assert(loadstring(fs.readFile("src/shared/Game/MinimapGeometry.luau")))
	setfenv(fn, setmetatable({ Vector2 = r.Vector2, Vector3 = V3 }, { __index = getfenv() }))
	return fn()
end)()
local function node(name)
	return {
		Name = name,
		WaitForChild = function(_, child)
			return node(child)
		end,
	}
end
local services = {
	Players = { LocalPlayer = {} },
	ReplicatedStorage = node("ReplicatedStorage"),
	RunService = {},
	UserInputService = {},
	GuiService = {},
	CollectionService = {},
}
local world = I.new("Workspace")
local map = I.new("Model")
map.Name = "CornMap"
map:SetAttribute("corn_project_id", "children_of_corn")
map.Parent = world
local field = I.new("Part")
field.Name = "FieldZone"
field.Size = V3.new(200, 10, 100)
field.CFrame = CF.new(100, 10, 50) * CF.Angles(0, math.rad(37), 0)
field.Parent = map
local gate = I.new("Model")
gate.Name = "EscapeGate"
gate:AddTag("corn_gate")
gate.Parent = map
local anchor = I.new("Part")
anchor.Name = "InteractionAnchor"
anchor.CFrame = field.CFrame * CF.new(30, 0, -25)
anchor.Parent = gate
local source = fs.readFile("src/client/Controllers/MinimapController.luau")
source = source:gsub("anchor%.Position", "anchor.CFrame.Position")
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
		script = { Parent = { Parent = node("GameClient") } },
		require = function(module)
			return if module.Name == "MinimapGeometry" then Geometry else {}
		end,
	}, { __index = getfenv() })
)
local Controller = fn()
assert(Controller._gatePosition({}, field) == anchor.CFrame.Position)
local projected = Geometry.Project(field.CFrame, field.Size, Controller._gatePosition({}, field))
assert(math.abs(projected.X - 0.65) < 1e-5 and math.abs(projected.Y - 0.25) < 1e-5)
field.CFrame = CF.new(-200, 25, -90) * CF.Angles(0, math.rad(-52), 0)
anchor.CFrame = field.CFrame * CF.new(-50, 0, 25)
assert(Controller._gatePosition({}, field) == anchor.CFrame.Position)
projected = Geometry.Project(field.CFrame, field.Size, Controller._gatePosition({}, field))
assert(math.abs(projected.X - 0.25) < 1e-5 and math.abs(projected.Y - 0.75) < 1e-5)
gate:RemoveTag("corn_gate")
assert(Controller._gatePosition({}, field) == nil)
gate:AddTag("corn_gate")
anchor.Name = "Missing"
assert(Controller._gatePosition({}, field) == nil)
local invalid = I.new("Folder")
invalid.Name = "InteractionAnchor"
invalid.Parent = gate
assert(Controller._gatePosition({}, field) == nil)
invalid:Destroy()
anchor.Name = "InteractionAnchor"
map:SetAttribute("corn_project_id", "another_project")
assert(Controller._gatePosition({}, field) == nil)
map:SetAttribute("corn_project_id", "children_of_corn")
field.Parent = world
assert(Controller._gatePosition({}, field) == nil)
field.Parent = map
local beforeFrame, beforeSize = anchor.CFrame, anchor.Size
for _ = 1, 20 do
	assert(Controller._gatePosition({}, field) == anchor.CFrame.Position)
end
assert(anchor.CFrame == beforeFrame and anchor.Size == beforeSize and anchor.Parent == gate)
print(
	"PASS: public tagged gate binding, moved/rotated field+anchor projection, absent/unrecognized binding hides, unrelated field rejected, read-only geometry"
)
