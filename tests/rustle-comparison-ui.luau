-- HISTORICAL A/B acceptance; its setup is reused by rustle-continuous-ui.luau.
-- Production MovementController + deterministic GUI/input adapters.
-- Activated/Alt dispatch here is adapter coverage, not a physical Studio click.
local fs = require("@lune/fs")
local setup = assert(
	fs.readFile("tests/audio-controller.luau")
		:match('^(.-)local module = load%("src/client/Controllers/AudioController.luau"')
)
local cases = [=[
local playerGui = make("PlayerGui")
playerGui.Name, playerGui.Parent = "PlayerGui", hero
player.PlayerGui = playerGui
function player:WaitForChild(name) return assert(self[name]) end
local function child(class, name, parent)
	local value = make(class)
	value.Name, value.Parent = name, parent
	return value
end
local endpoints = load("src/shared/Network/EndpointNames.luau", {})
local text = load("src/shared/Game/RoundText.luau", {})
local networkNode = child("Folder", "Network", folder)
child("ModuleScript", "EndpointNames", networkNode)
child("ModuleScript", "RoundText", games)
local remotes = child("Folder", "GameRemotes", storage)
local remote = child("RemoteEvent", endpoints.RequestSprintIntent, remotes)
local requests = 0
function remote:FireServer() requests += 1 end
child("TextButton", "LeaveRound", child("ScreenGui", "CornRoundHud", playerGui))
local actions = {}
local actionService = {}
function actionService:BindActionAtPriority(name, callback) actions[name] = callback end
function actionService:UnbindAction(name) actions[name] = nil end
local input = { WindowFocusReleased = signal(), MouseBehavior = roblox.Enum.MouseBehavior.Default }
function input:GetFocusedTextBox() return nil end
local serviceMap = {
	Players = services.Players, ReplicatedStorage = storage,
	ContextActionService = actionService, UserInputService = input, GuiService = gui,
}
local function uiMake(class)
	local value = make(class)
	value._values.Activated = signal()
	return value
end
local movementModule = load("src/client/Controllers/MovementController.luau", {
	game = { GetService = function(_, name) return assert(serviceMap[name]) end },
	workspace = world, Instance = { new = uiMake },
	Enum = roblox.Enum, Vector2 = roblox.Vector2, UDim2 = roblox.UDim2,
	Color3 = roblox.Color3, CFrame = roblox.CFrame,
	require = function(node) return if node.Name == "EndpointNames" then endpoints else text end,
})
local object = setmetatable({}, { __index = movementModule })
object:Init({})
object:Start({})
local calls = {}
object:BindRustleComparison(function(mode) table.insert(calls, mode) end)
object:SetRustleComparison(1, true, "недоступен")
object:SetSnapshot({ phase = "active", stamina = 100, stamina_capacity = 100,
	sprint_exhausted = false, start_look = roblox.Vector3.zAxis })
local first, second = object._rustleButtons[1], object._rustleButtons[2]
assert(first.Visible and second.Visible and not first.Active and not second.Active
	and not object:IsCursorOpen(), "Buttons must be visible but locked until Alt")
first.Activated:Fire(); second.Activated:Fire()
assert(#calls == 0, "Direct Activated without Alt must be refused")
local function alt()
	return actions.CornCursor("CornCursor", roblox.Enum.UserInputState.Begin)
end
alt()
assert(object:IsCursorOpen() and first.Active and second.Active and object._cursorGuard.Visible,
	"Existing Alt binding must release cursor and enable comparison clicks")
second.Activated:Fire()
assert(#calls == 1 and calls[1] == 2, "Alt plus second button did not select sound 2")
object:SetRustleComparison(2, true)
assert(object._gui:GetAttribute("RustleMode") == 2
	and object._gui:GetAttribute("RustleSound2Available") == true,
	"Comparison selection/availability attrs must reflect actual UI state")
object:SetRustleComparison(1, false, "нужен импорт")
assert(not second.Active and second.Text:find("нужен импорт", 1, true))
second.Activated:Fire()
assert(#calls == 1, "Unavailable sound 2 must refuse even an injected Activated")
first.Activated:Fire()
assert(#calls == 2 and calls[2] == 1)
object:SetRustleComparison(2, true)
object:SetMapOpen(true)
assert(not object:IsCursorOpen() and not first.Visible and not second.Visible)
second.Activated:Fire(); alt()
assert(#calls == 2 and not object:IsCursorOpen(), "Map must block click/Alt switching")
object:SetMapOpen(false)
assert(object:IsCursorOpen(), "Closing map must restore prior Alt state")
object:SetCaptureActive(true)
assert(not object:IsCursorOpen() and not first.Visible and not second.Visible)
second.Activated:Fire(); alt()
assert(#calls == 2, "Capture must block comparison")
object:SetCaptureActive(false)
if not object:IsCursorOpen() then alt() end
gui.MenuIsOpen = true
second.Activated:Fire()
assert(#calls == 2, "Roblox menu must block comparison")
gui.MenuIsOpen = false
object:BindRustleComparison(nil)
assert(not first.Active and not second.Active, "Unbound audio callback must disable both buttons")
second.Activated:Fire()
assert(#calls == 2)
object:BindRustleComparison(function(mode) table.insert(calls, mode) end)
object:SetSnapshot({ phase = "caught", stamina = 100, stamina_capacity = 100,
	sprint_exhausted = false, start_look = roblox.Vector3.zAxis })
assert(not object:IsCursorOpen() and not first.Visible and not second.Visible)
first.Activated:Fire(); second.Activated:Fire(); alt()
assert(#calls == 2, "Caught/terminal UI must refuse comparison")
object:Destroy()
assert(first.Destroyed and second.Destroyed and not actions.CornCursor and not actions.CornSprint)
for _, connection in connections do assert(not connection.Connected, "Movement comparison GUI connection leaked") end
assert(requests == 0, "Comparison controls sent gameplay requests")
print("PASS comparison Movement UI adapter: existing Alt/active click gate; exactly two HUD buttons; selected/available attrs; missing asset label; map/capture/Roblox menu/caught/no callback refusals; map restores Alt; no gameplay requests; GUI/input connection cleanup. Physical input requires Studio.")
]=]
assert(loadstring(setup .. cases, "rustle-comparison-ui-focused"))()
