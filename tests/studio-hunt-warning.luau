-- Run only in the verified Studio Client during Play. Real engine GUI rendering
-- with fixture snapshots; does not change actual gameplay, remotes or world.
local player = game:GetService("Players").LocalPlayer
local RoundHud = require(player.PlayerScripts.GameClient.Game.RoundHud)
local Text = require(game.ReplicatedStorage.GameShared.Game.RoundText)
local hud = RoundHud.new(player.PlayerGui)
hud._root.Name = "HuntWarningAcceptance"
local yellow = Color3.fromRGB(233, 209, 142)
local red = Color3.fromRGB(233, 94, 83)
local base = {
	lighting_mode = "medium",
	phase = "active",
	has_key = false,
	gate_open = false,
	session_diamonds = 0,
	reward_diamonds = 0,
	elapsed_sec = 16,
	notice = "corn_hunt_awakened",
	stamina = 100,
	stamina_capacity = 100,
	is_sprinting = false,
	sprint_exhausted = false,
	start_look = Vector3.new(0, 0, -1),
	catches_remaining = 2,
	monster_state = "patrol",
	protection_sec = 0,
	minimap = { round_id = 1, visited = {}, deaths = {} },
}
local checks = {}
local function render(changes)
	local snapshot = table.clone(base)
	for key, value in changes do
		snapshot[key] = value
	end
	hud:Render(snapshot)
	return snapshot
end
local function assertNotice(expected, color, font)
	assert(hud._activeNotice.Text == expected, "Unexpected warning: " .. hud._activeNotice.Text)
	assert(hud._activeNotice.TextColor3 == color, "Warning color was not updated")
	assert(hud._activeNotice.Font == font, "Warning font was not reset")
end
local ok, problem = pcall(function()
	render({})
	assert(hud._active.Visible and not hud._card.Visible)
	assertNotice(Text.corn_hunt_awakened, yellow, Enum.Font.Gotham)
	checks.patrol_preserves_notice = true
	render({ monster_state = "chase" })
	assertNotice(Text.corn_hunt_chase, red, Enum.Font.GothamBold)
	hud:SetBusy(true)
	assertNotice(Text.corn_hunt_chase, red, Enum.Font.GothamBold)
	hud:SetBusy(false)
	checks.chase_and_rerender = true
	render({ monster_state = "chase", protection_sec = 2.2 })
	assertNotice("Защита после возврата: 3 с", yellow, Enum.Font.Gotham)
	checks.protection_has_priority = true
	render({ monster_state = "chase" })
	assertNotice(Text.corn_hunt_chase, red, Enum.Font.GothamBold)
	render({})
	assertNotice(Text.corn_hunt_awakened, yellow, Enum.Font.Gotham)
	checks.chase_lost_resets_style = true
	render({ monster_state = "chase" })
	render({ phase = "caught", notice = "corn_hunt_first_catch", catches_remaining = 1 })
	assert(not hud._active.Visible and hud._card.Visible)
	assert(hud._message.Text == Text.corn_hunt_first_catch)
	assertNotice("", yellow, Enum.Font.Gotham)
	checks.caught_clears_warning = true
	render({ protection_sec = 5, catches_remaining = 1, notice = "corn_hunt_first_catch" })
	assertNotice("Защита после возврата: 5 с", yellow, Enum.Font.Gotham)
	render({ monster_state = "chase" })
	render({
		phase = "caught_out",
		monster_state = "stopped",
		catches_remaining = 0,
		notice = "corn_hunt_defeat_notice",
	})
	assert(hud._retry.Visible and hud._card.Visible and not hud._active.Visible)
	assertNotice("", yellow, Enum.Font.Gotham)
	checks.result_clears_warning = true
	render({ phase = "preparing", monster_state = "stopped", notice = "" })
	assertNotice("", yellow, Enum.Font.Gotham)
	render({
		monster_state = "dormant",
		elapsed_sec = 0,
		notice = "",
		minimap = { round_id = 2, visited = {}, deaths = {} },
	})
	assert(hud._active.Visible)
	assertNotice("", yellow, Enum.Font.Gotham)
	checks.retry_starts_without_warning = true
end)
hud:Destroy()
assert(ok, tostring(problem))
assert(not player.PlayerGui:FindFirstChild("HuntWarningAcceptance"))
checks.cleanup = true
checks.method = "Actual RoundHud engine GUI with controlled confirmed-state snapshots"
return game:GetService("HttpService"):JSONEncode(checks)
