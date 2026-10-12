-- Verified Children_of_corn Play Client only. Temporary actual GUI objects.
-- Controlled snapshots/times and simulated layout inputs, no world or network mutation.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = assert(Players.LocalPlayer, "Client required")
local Hud = require(player.PlayerScripts.GameClient.Game.InventoryHud)
local Inventory = require(game.ReplicatedStorage.GameShared.Game.Inventory)
local gui = Hud.new(player.PlayerGui, true)
gui._root.Name = "InventoryAcceptance"
local state =
	{ slots = { "key", "energy", "trap", "energy", "trap" }, selected = 2, energy_remaining = 30 }
local checks = {}
local function expect(condition, message)
	assert(condition, message or "Inventory actual-GUI assertion failed")
end
local ok, problem = pcall(function()
	expect(Inventory.IsValidSnapshot(state), "Fixture snapshot invalid")
	gui:Render(state, "active", 100)
	expect(gui._root.Enabled and #gui._buttons == 5 and gui._use.Visible)
	for index, button in gui._buttons do
		expect(button:IsA("TextButton") and button.Active and button.Number.Text == tostring(index))
		expect(gui._icons[index][state.slots[index]].Visible, "Item shape missing")
	end
	expect(gui._icons[1].key:FindFirstChild("Bow") and gui._icons[1].key:FindFirstChild("Shaft"))
	expect(gui._icons[2].energy:FindFirstChild("Can"))
	expect(gui._icons[3].trap:FindFirstChild("Base"))
	expect(gui._use.Active and gui._use.Text == "Выпить")
	expect(gui._seconds.Text == "30" and gui._energy.Visible)
	checks.five_actual_buttons_and_procedural_item_icons = true
	state.selected = 1
	gui:Render(state, "active", 100)
	expect(not gui._use.Active and gui._use.Text == "Ключ · к воротам")
	state.selected = 3
	gui:Render(state, "active", 100)
	expect(gui._use.Active and gui._use.Text == "Поставить капкан")
	checks.key_inactive_and_touch_consumable_actions = true
	gui:Update(124.99)
	expect(gui._seconds.Text == "6" and gui._seconds.TextColor3 == Color3.fromRGB(104, 222, 128))
	gui:Update(125)
	expect(gui._seconds.Text == "5" and gui._seconds.TextColor3 == Color3.fromRGB(248, 91, 83))
	local blink = gui._seconds.TextTransparency
	gui:Update(125.25)
	expect(gui._seconds.TextTransparency ~= blink)
	gui:Update(130)
	expect(not gui._energy.Visible)
	checks.circular_green_red_blink_and_expiry = true
	for _, phase in { "ready", "preparing", "active", "caught", "escaped", "aborted", "caught_out" } do
		gui:Render(state, phase, 100)
		expect(gui._root.Enabled == (phase == "active" or phase == "caught"))
		for _, button in gui._buttons do
			expect(button.Active == (phase == "active"))
		end
		expect(gui._energy.Visible == (phase == "active"))
	end
	checks.all_round_phases_and_caught_readonly_inventory = true
	for _, size in
		{
			Vector2.new(1400, 800),
			Vector2.new(800, 600),
			Vector2.new(640, 360),
			Vector2.new(390, 844),
		}
	do
		gui:SetViewport(size)
		local width = gui._bar.Size.X.Offset * gui._scale.Scale
		local height = gui._bar.Size.Y.Offset * gui._scale.Scale
		local right = size.X + gui._bar.Position.X.Offset
		local bottom = size.Y + gui._bar.Position.Y.Offset
		expect(right - width >= 0 and bottom - height >= 0 and right <= size.X and bottom <= size.Y)
		expect(bottom <= size.Y - 108 or right - width >= 370, "Existing stamina overlap")
	end
	checks.simulated_1400_800_640_390_layout_bounds = true
	gui:Render(state, "active", 100)
	gui:SetViewport(gui._root.AbsoluteSize)
	RunService.RenderStepped:Wait()
	RunService.RenderStepped:Wait()
	local viewport = gui._root.AbsoluteSize
	local origin = gui._root.AbsolutePosition
	for _, button in gui._buttons do
		local position, size = button.AbsolutePosition - origin, button.AbsoluteSize
		expect(size.X > 35 and size.Y > 35, "Slot too small at actual viewport")
		expect(
			position.X >= 0 and position.X + size.X <= viewport.X + 0.1,
			"Actual slot horizontal bounds"
		)
		expect(
			position.Y >= 0 and position.Y + size.Y <= viewport.Y + 0.1,
			"Actual slot vertical bounds"
		)
	end
	checks.actual_viewport_button_sizes_and_bounds = tostring(viewport)
end)
local connections = table.clone(gui._connections)
gui:Destroy()
expect(not player.PlayerGui:FindFirstChild("InventoryAcceptance"), "Temporary GUI remains")
for _, connection in connections do
	expect(not connection.Connected, "Actual GUI connection leaked")
end
expect(ok, tostring(problem))
checks.cleanup = true
checks.method =
	"Actual GUI construction/styles/layout with controlled snapshots/time; no physical input or gameplay claim"
return game:GetService("HttpService"):JSONEncode(checks)
