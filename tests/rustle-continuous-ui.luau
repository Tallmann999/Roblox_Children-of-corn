-- Actual MovementController with the same deterministic GUI/input adapters.
-- The removed comparison fixture supplies setup only; no old A/B behavior runs.
local fs = require("@lune/fs")
local setup = assert(
	fs.readFile("tests/audio-controller.luau")
		:match('^(.-)local module = load%("src/client/Controllers/AudioController.luau"')
)
local bootstrap = assert(
	fs.readFile("tests/rustle-comparison-ui.luau"):match("local cases = %[%=%[(.-)local object =")
)
local cases = [=[
local object = setmetatable({}, { __index = movementModule })
object:Init({})
object:Start({})
assert(object.BindRustleComparison == nil and object.SetRustleComparison == nil,
	"A/B comparison APIs must be removed from production MovementController")
assert(object._rustleButtons == nil and object._rustleCallback == nil,
	"A/B comparison state must not remain in normal HUD")
for _, item in object._gui:GetDescendants() do
	assert(not item.Name:match("^RustleSound") and not item.Name:find("Comparison", 1, true),
		"Removed comparison buttons must not exist in normal HUD")
end
assert(object._gui:GetAttribute("RustleMode") == nil
	and object._gui:GetAttribute("RustleSound2Available") == nil,
	"Comparison GUI attributes must be removed")
object:SetSnapshot({ phase = "active", stamina = 100, stamina_capacity = 100,
	sprint_exhausted = false, start_look = roblox.Vector3.zAxis })
local function alt()
	return actions.CornCursor("CornCursor", roblox.Enum.UserInputState.Begin)
end
assert(not object._cursorOpen and not object._cursorGuard.Visible)
alt()
assert(object._cursorOpen and object._cursorGuard.Visible,
	"Normal Alt cursor release must survive removal of comparison controls")
alt()
assert(not object._cursorOpen and not object._cursorGuard.Visible)
object:SetMapOpen(true)
alt()
assert(object._mapOpen and not object._cursorOpen and object._cursorGuard.Visible,
	"Map must retain its own normal cursor behavior")
object:SetMapOpen(false)
object:SetCaptureActive(true)
alt()
assert(not object._cursorOpen and not object._gui.Enabled,
	"Capture still blocks normal Alt cursor")
object:Destroy()
assert(object._gui.Destroyed and not actions.CornCursor and not actions.CornSprint)
for _, connection in connections do assert(not connection.Connected, "Movement GUI/input connection leaked") end
assert(requests == 0, "Normal cursor test sent gameplay requests")
print("PASS continuous corn UI adapter: A/B buttons/state/APIs/attrs absent; existing Alt cursor release, map/capture guards and GUI/input cleanup retained. Physical input requires Studio.")
]=]
assert(loadstring(setup .. bootstrap .. cases, "rustle-continuous-ui-focused"))()
