-- Client only: historical filename now verifies the removed chooser in the real GUI.
-- Controlled confirmed snapshots and local callbacks; no remotes, world or camera writes.
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local player = assert(Players.LocalPlayer, "Client context required")
local shared = game.ReplicatedStorage.GameShared.Game
local Modes = require(shared.LightingModes)
local Hud = require(player.PlayerScripts.GameClient.Game.RoundHud)
local savedFocus = GuiService.SelectedObject
local hud = Hud.new(player.PlayerGui)
hud._root.Name, hud._introRoot.Name = "NightOnlyAcceptance", "NightOnlyIntroAcceptance"
local checks, calls = {}, {}
local function expect(condition, message)
	assert(condition, message or "Actual night-only GUI fixture failed")
end
local base = {
	lighting_mode = "hard",
	phase = "ready",
	has_key = false,
	gate_open = false,
	session_diamonds = 0,
	reward_diamonds = 0,
	elapsed_sec = 15,
	notice = "",
	stamina = 100,
	stamina_capacity = 100,
	is_sprinting = false,
	sprint_exhausted = false,
	start_look = Vector3.new(0, 0, -1),
	catches_remaining = 2,
	monster_state = "patrol",
	protection_sec = 0,
	minimap = { round_id = 1, visited = {}, deaths = {} },
	capture = { id = 0, remaining = 0, frame = CFrame.identity },
	inventory = {
		slots = { "empty", "empty", "empty", "empty", "empty" },
		selected = 1,
		energy_remaining = 0,
		use = { id = 0, kind = "none" },
	},
}
local function render(phase)
	local value = table.clone(base)
	value.phase = phase
	if phase == "caught_out" then
		value.catches_remaining = 0
		value.capture = { id = 2, remaining = 0, frame = CFrame.identity }
	end
	hud:Render(value)
end
local function inside(item, parent)
	local a, b = item.AbsolutePosition, parent.AbsolutePosition
	local size, outer = item.AbsoluteSize, parent.AbsoluteSize
	expect(
		a.X >= b.X - 1
			and a.Y >= b.Y - 1
			and a.X + size.X <= b.X + outer.X + 1
			and a.Y + size.Y <= b.Y + outer.Y + 1,
		item.Name .. " viewport overflow"
	)
end
local function noModes()
	expect(
		hud._modeCards == nil and hud._modeButtons == nil and hud._introMode == nil,
		"Removed mode state remains"
	)
	for _, root in { hud._root, hud._introRoot } do
		for _, item in root:GetDescendants() do
			expect(
				not item:IsA("ImageLabel")
					and not item:IsA("ViewportFrame")
					and not item:IsA("WorldModel"),
				"Mode imagery remains"
			)
			expect(
				item.Name ~= "ModeCards" and item.Name ~= "ChooseMode" and item.Name ~= "ModeHint",
				"Mode selection node remains"
			)
			if item:IsA("TextLabel") or item:IsA("TextButton") then
				expect(
					not item.Text:find("сложност", 1, true)
						and not item.Text:find("Режим:", 1, true)
						and not item.Text:find("Выбрано:", 1, true),
					"Mode label remains"
				)
			end
		end
	end
end
hud:SetOnAction(function(action, mode)
	table.insert(calls, { action = action, mode = mode })
end)
local ok, problem = pcall(function()
	expect(
		Modes.Default == "hard"
			and #Modes.Order == 1
			and Modes.Order[1] == "hard"
			and not Modes.IsValid("easy")
			and not Modes.IsValid("medium"),
		"Night whitelist mismatch"
	)
	for _, phase in { "ready", "preparing", "active", "caught", "escaped", "aborted", "caught_out" } do
		render(phase)
		task.wait(0.05)
		noModes()
		expect(hud._card.Size == UDim2.fromOffset(460, 320), "Obsolete chooser size")
		expect(
			hud._card.Visible == (phase ~= "active" and phase ~= "caught" and phase ~= "caught_out")
		)
		inside(hud._card, hud._root)
		if phase == "ready" or phase == "escaped" or phase == "aborted" then
			local action = if phase == "ready" then "start" else "retry"
			local control = if phase == "ready" then hud._start else hud._retry
			expect(control.Visible and control.Active and hud._start.Visible ~= hud._retry.Visible)
			inside(control, hud._card)
			local before = #calls
			hud:ShowObjective(action)
			task.wait(0.05)
			expect(#calls == before and hud._introRoot.Enabled and hud._introPending.mode == "hard")
			noModes()
			inside(hud._introPanel, hud._introRoot)
			hud:ConfirmObjective()
			expect(
				#calls == before + 1
					and calls[#calls].action == action
					and calls[#calls].mode == "hard"
			)
		end
	end
	checks.no_mode_gui_all_phases = true
	checks.actual_viewport_start_retry_objective_hard_only = true
	render("ready")
	expect(
		hud._start.Visible
			and not hud._retry.Visible
			and not hud._menu.Visible
			and not hud._introRoot.Enabled,
		"Main menu did not restore one Start"
	)
	checks.main_start = true
	checks.viewport = { x = hud._root.AbsoluteSize.X, y = hud._root.AbsoluteSize.Y }
end)
hud:Destroy()
if GuiService.SelectedObject == nil and savedFocus and savedFocus.Parent then
	GuiService.SelectedObject = savedFocus
end
expect(ok, tostring(problem))
expect(
	not player.PlayerGui:FindFirstChild("NightOnlyAcceptance")
		and not player.PlayerGui:FindFirstChild("NightOnlyIntroAcceptance"),
	"Fixture GUI leaked"
)
checks.cleanup = true
checks.method =
	"Actual GUI current viewport; controlled snapshots and ShowObjective/Confirm callbacks. No real mouse, server gameplay or blind round claim."
return game:GetService("HttpService"):JSONEncode(checks)
