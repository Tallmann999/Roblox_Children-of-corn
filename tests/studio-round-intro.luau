-- Client only: actual GUI and controlled confirmed-state snapshots, no remotes/gameplay writes.
-- Real Start/Retry/Confirm/Back mouse paths are exercised separately through Studio MCP.
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local player = assert(Players.LocalPlayer)
local Hud = require(player.PlayerScripts.GameClient.Game.RoundHud)
local Text = require(game.ReplicatedStorage.GameShared.Game.RoundText)
local Balance = require(game.ReplicatedStorage.GameShared.Game.Balance)
local savedFocus = GuiService.SelectedObject
local hud = Hud.new(player.PlayerGui)
hud._root.Name, hud._introRoot.Name = "HuntIntroAcceptance", "HuntIntroModalAcceptance"
local actualRoot, actualIntro = hud._root, hud._introRoot
local calls, checks, foreign = {}, {}, nil
hud:SetOnAction(function(action, mode)
	table.insert(calls, { action = action, mode = mode })
end)
local base = {
	lighting_mode = "medium",
	phase = "ready",
	has_key = false,
	gate_open = false,
	session_diamonds = 0,
	reward_diamonds = 0,
	elapsed_sec = 0,
	notice = "",
	stamina = 100,
	stamina_capacity = 100,
	is_sprinting = false,
	sprint_exhausted = false,
	start_look = Vector3.new(0, 0, -1),
	catches_remaining = 2,
	monster_state = "dormant",
	protection_sec = 0,
	minimap = { round_id = 1, visited = {}, deaths = {} },
	inventory = {
		slots = { "empty", "empty", "empty", "empty", "empty" },
		selected = 1,
		energy_remaining = 0,
		use = { id = 0, kind = "none" },
	},
	capture = { id = 0, remaining = 0, frame = CFrame.identity },
}
local function expect(condition, message)
	assert(condition, message or "Actual objective/countdown fixture failed")
end
local function render(changes)
	local snapshot = table.clone(base)
	for name, value in changes do
		snapshot[name] = value
	end
	hud:Render(snapshot)
end
local function inside(item, parent)
	local a, b = item.AbsolutePosition, parent.AbsolutePosition
	local size, outer = item.AbsoluteSize, parent.AbsoluteSize
	expect(
		a.X >= b.X - 1
			and a.Y >= b.Y - 1
			and a.X + size.X <= b.X + outer.X + 1
			and a.Y + size.Y <= b.Y + outer.Y + 1,
		item.Name .. " actual viewport overflow"
	)
end
local ok, problem = pcall(function()
	expect(
		Balance.hunt_start_delay_sec == 20,
		"Install the authorized 20-second Balance before this fixture"
	)
	render({})
	hud._selectedMode = "hard"
	GuiService.SelectedObject = hud._start
	hud:ShowObjective("start")
	task.wait(0.1)
	expect(
		#calls == 0
			and actualIntro.Enabled
			and not actualRoot.RoundCard.Visible
			and not hud._waking.Visible,
		"Objective start bypassed confirmation"
	)
	expect(hud._introMessage.Text == Text.corn_loop_intro_objective)
	expect(
		actualIntro.DisplayOrder > 30
			and actualIntro.IgnoreGuiInset
			and actualIntro.ScreenInsets == Enum.ScreenInsets.None
			and not actualIntro.ClipToDeviceSafeArea
	)
	expect(
		actualIntro.AbsoluteSize == workspace.CurrentCamera.ViewportSize,
		"Objective does not cover full viewport"
	)
	expect(
		actualIntro.Backdrop.AbsoluteSize == actualIntro.AbsoluteSize
			and actualIntro.Backdrop.Active
	)
	expect(
		hud._introConfirm.Active
			and hud._introConfirm.Modal
			and hud._introBack.Modal
			and GuiService.SelectedObject == hud._introConfirm
	)
	inside(hud._introPanel, actualIntro)
	inside(hud._introMessage, hud._introPanel)
	inside(hud._introConfirm, hud._introPanel)
	inside(hud._introBack, hud._introPanel)
	expect(
		hud._introMessage.TextBounds.Y <= hud._introMessage.AbsoluteSize.Y + 1,
		"Objective wrapped text clipped"
	)
	hud:CloseObjective()
	expect(
		#calls == 0
			and not actualIntro.Enabled
			and hud._card.Visible
			and GuiService.SelectedObject == hud._start
	)
	hud:ShowObjective("start")
	hud:SetBusy(true)
	hud:ConfirmObjective()
	expect(#calls == 0 and not hud._introConfirm.Active)
	hud:SetBusy(false)
	hud:ConfirmObjective()
	hud:ConfirmObjective()
	expect(
		#calls == 1
			and calls[1].action == "start"
			and calls[1].mode == "hard"
			and not actualIntro.Enabled
	)
	checks.actual_full_viewport_objective_confirm_back_modal_focus_no_early_action = true
	for _, phase in { "escaped", "aborted", "caught_out" } do
		render({ phase = phase })
		hud._selectedMode = "easy"
		hud:ShowObjective("retry")
		expect(actualIntro.Enabled)
		local before = #calls
		hud:ConfirmObjective()
		expect(
			#calls == before + 1
				and calls[#calls].action == "retry"
				and calls[#calls].mode == "easy"
		)
	end
	checks.retry_all_results_preserves_original_action_and_mode = true
	for count = 5, 1, -1 do
		render({ phase = "active", elapsed_sec = 20 - count })
		expect(
			hud._waking.Visible
				and hud._wakingMessage.Text == Text.corn_hunt_waking_warning
				and hud._wakingSeconds.Text == tostring(count) .. " с"
		)
	end
	for _, change in
		{
			{ phase = "active", elapsed_sec = 14.99 },
			{ phase = "active", elapsed_sec = 20 },
			{ phase = "active", elapsed_sec = 18, monster_state = "patrol" },
			{ phase = "caught", elapsed_sec = 18 },
			{ phase = "caught_out", elapsed_sec = 18 },
			{ phase = "escaped", elapsed_sec = 18 },
			{ phase = "aborted", elapsed_sec = 18 },
			{ phase = "preparing", elapsed_sec = 18 },
			{ phase = "ready", elapsed_sec = 18 },
			{
				phase = "active",
				elapsed_sec = 0,
				minimap = { round_id = 2, visited = {}, deaths = {} },
			},
		}
	do
		render(change)
		expect(
			not hud._waking.Visible
				and hud._wakingSeconds.Text == ""
				and hud._wakingMessage.Text == "",
			"Stale or early countdown"
		)
	end
	checks.server_elapsed_5_4_3_2_1_and_all_other_state_retry_clears = true
	render({})
	hud:ShowObjective("start")
	hud:ShowUnavailable()
	expect(not actualIntro.Enabled)
	render({})
	hud:ShowObjective("start")
	hud:SetCaptureActive(true)
	expect(not actualIntro.Enabled)
	hud:SetCaptureActive(false)
	render({})
	hud:ShowObjective("start")
	foreign = Instance.new("TextButton")
	foreign.Name, foreign.Parent = "ForeignFocusFixture", actualRoot
	GuiService.SelectedObject = foreign
	hud:CloseObjective()
	expect(GuiService.SelectedObject == foreign, "Modal cleanup replaced foreign focus")
	checks.unavailable_capture_foreign_focus_cleanup = true
	for _, viewport in
		{
			Vector2.new(1400, 800),
			Vector2.new(640, 480),
			Vector2.new(320, 568),
			Vector2.new(568, 320),
			Vector2.new(320, 320),
		}
	do
		hud._root, hud._introRoot = { AbsoluteSize = viewport }, { AbsoluteSize = viewport }
		hud:_fitOverlays()
		hud._root, hud._introRoot = actualRoot, actualIntro
		expect(
			hud._introPanel.Size.X.Offset <= viewport.X - 36 + 0.01
				and hud._introPanel.Size.Y.Offset <= viewport.Y - 36 + 0.01
		)
		expect(
			hud._introConfirm.Size.Y.Offset == 48
				and hud._introBack.Size.Y.Offset == 36
				and hud._introMessage.TextSize >= 18
		)
		local bodyEnd = hud._introMessage.Position.Y.Offset + hud._introMessage.Size.Y.Offset
		expect(
			bodyEnd <= hud._introMode.Position.Y.Offset
				and hud._introMode.Position.Y.Offset + 28 <= hud._introConfirm.Position.Y.Offset
		)
		expect(
			hud._introConfirm.Position.Y.Offset + 48 <= hud._introBack.Position.Y.Offset
				and hud._introBack.Position.Y.Offset + 36 <= hud._introPanel.Size.Y.Offset
		)
	end
	checks.phone_and_desktop_simulated_fit_unscaled_touch_targets = true
	checks.viewport = { x = actualIntro.AbsoluteSize.X, y = actualIntro.AbsoluteSize.Y }
	checks.method =
		"Actual engine GUI/viewport/text bounds, controlled Show/Confirm/Back snapshots and simulated responsive size inputs; real physical button routing tested separately"
end)
hud._root, hud._introRoot = actualRoot, actualIntro
hud:Destroy()
if
	savedFocus
	and savedFocus.Parent
	and savedFocus.Visible
	and (GuiService.SelectedObject == nil or GuiService.SelectedObject == foreign)
then
	GuiService.SelectedObject = savedFocus
end
expect(
	not player.PlayerGui:FindFirstChild("HuntIntroAcceptance")
		and not player.PlayerGui:FindFirstChild("HuntIntroModalAcceptance"),
	"Objective/countdown fixture GUI leaked"
)
expect(ok, tostring(problem))
checks.cleanup = true
return game:GetService("HttpService"):JSONEncode(checks)
