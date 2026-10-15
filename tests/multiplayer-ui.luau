-- Actual RoundHud and RoundController with the existing deterministic GUI/remotes
-- adapter. These assertions exercise team state transitions, not engine pixels.
local fs = require("@lune/fs")
local fixture = fs.readFile("tests/round-intro.luau")
local setup = assert(fixture:match("^(.-)local calls = {}"))
local controllerSetup = assert(
	fixture:match(
		'(%-%- Actual RoundController callback wiring.-)assert%(#networkCalls == 1 and networkCalls%[1%]%[1%] == "sync"%)'
	)
)
local cases = [=[
local function team(changes)
	local value = {
		round_id = 1, state = "waiting", capacity = 4, count = 4,
		ready_count = 1, remaining = 0, ready = false, can_start = true,
		key_state = "hidden", carrier_name = "",
	}
	for key, entry in changes or {} do value[key] = entry end
	return value
end
local calls = {}
hud:SetOnAction(function(action, mode) table.insert(calls, { action, mode }) end)
render({})
assert(hud._start.Active and hud._start.Text == modules.RoundText.corn_loop_start,
	"Absent team data must preserve the solo start")
render({ team = team() })
assert(hud._start.Active and hud._notice.Text == "Готовы: 1 / 4")
hud._start.Activated:Fire()
assert(hud._introRoot.Enabled and #calls == 0)
assert(hud._introMessage.Text == modules.RoundText.corn_team_intro_objective)
assert(hud._introConfirm.Text == modules.RoundText.corn_team_intro_confirm)
hud._introConfirm.Activated:Fire()
assert(#calls == 1 and calls[1][1] == "start" and calls[1][2] == "hard")

hud._start.Activated:Fire()
render({ team = team({ ready = true, ready_count = 2, can_start = false }) })
assert(not hud._introRoot.Enabled and not hud._start.Active,
	"Confirmed readiness must cancel an open objective and disable another start")
hud:ShowObjective("start")
hud:ConfirmObjective()
hud._start.Activated:Fire()
assert(#calls == 1 and hud._start.Text == modules.RoundText.corn_team_ready)
assert(hud._message.Text == modules.RoundText.corn_team_waiting_ready)

render({ team = team() })
hud._start.Activated:Fire()
render({ team = team({ round_id = 2 }) })
assert(not hud._introRoot.Enabled, "Changed shared round retained old confirmation")
hud._start.Activated:Fire()
render({})
assert(not hud._introRoot.Enabled, "Removed shared-round identity retained confirmation")
render({ team = team() })
hud._start.Activated:Fire()
render({ team = team({ state = "active", remaining = 3, can_start = false }) })
assert(not hud._start.Active and not hud._introRoot.Enabled)
assert(hud._message.Text == modules.RoundText.corn_team_waiting_result)
assert(hud._notice.Text == "В поле: 3 / 4", "Late join did not display the running team")

local running = team({ state = "active", remaining = 3, can_start = false,
	key_state = "carried", carrier_name = "Corn friend" })
render({ phase = "active", team = running })
assert(hud._objective.Text == modules.RoundText.corn_team_key_carried,
	"A teammate carrying the key must replace the search objective")
assert(hud._activeBalance.Text:find("Corn friend", 1, true))
assert(hud._activeTime.Text:find("В поле: 3 / 4", 1, true))
render({ phase = "active", has_key = true, team = running })
assert(hud._objective.Text == modules.RoundText.corn_loop_objective_return,
	"The actual carrier must still return to open the gate")
render({ phase = "active", gate_open = true,
	team = team({ state = "active", remaining = 3, can_start = false, key_state = "opened" }) })
assert(hud._objective.Text == modules.RoundText.corn_loop_objective_exit)
render({ phase = "active", team = team({ state = "active", remaining = 3, can_start = false }) })
assert(hud._objective.Text == modules.RoundText.corn_loop_objective_search,
	"A dropped shared key must restore the search objective")

render({ phase = "escaped", team = running })
assert(not hud._retry.Active and hud._menu.Active)
hud._retry.Activated:Fire()
assert(not hud._introRoot.Enabled and #calls == 1)
hud._menu.Activated:Fire()
assert(#calls == 2 and calls[2][1] == "menu", "Waiting result must retain menu")
render({ phase = "caught", catches_remaining = 1,
	capture = { id = 1, remaining = 0, frame = r.CFrame.identity }, team = running })
assert(hud._captureRevive.Active and hud._captureExit.Active,
	"Team next-round readiness must not block first-catch revival")
hud._captureRevive.Activated:Fire()
assert(#calls == 3 and calls[3][1] == "revive" and calls[3][2] == nil)
hud:SetBusy(false)
render({ phase = "active", team = running })
render({ phase = "caught_out", catches_remaining = 0,
	capture = { id = 2, remaining = 0, frame = r.CFrame.identity }, team = running })
assert(hud._captureChoices.Visible and not hud._captureRevive.Active and hud._captureExit.Active)
assert(guiService.SelectedObject == hud._captureExit,
	"Waiting capture must focus the available menu action")
assert(hud._captureMessage.Text == modules.RoundText.corn_team_waiting_result)
hud._captureRevive.Activated:Fire()
hud:ChooseCapture("revive")
assert(#calls == 3 and not hud._introRoot.Enabled)
hud._captureExit.Activated:Fire()
assert(#calls == 4 and calls[4][1] == "menu")
hud:SetBusy(false)
local finished = team({ state = "finished", ready_count = 0, remaining = 0 })
render({ phase = "caught_out", catches_remaining = 0,
	capture = { id = 2, remaining = 0, frame = r.CFrame.identity }, team = finished })
assert(hud._captureRevive.Active)
hud._captureRevive.Activated:Fire()
assert(hud._introRoot.Enabled and hud._introPending.action == "retry")
hud._introConfirm.Activated:Fire()
assert(#calls == 5 and calls[5][1] == "retry")
render({ phase = "caught_out", catches_remaining = 0,
	capture = { id = 2, remaining = 0, frame = r.CFrame.identity },
	team = team({ state = "finished", ready = true, ready_count = 2, can_start = false }) })
assert(not hud._captureRevive.Active and hud._captureExit.Active,
	"Own next-round readiness must disable a repeated retry")
hud:Destroy()
]=]
local networkCases = [=[
assert(#networkCalls == 1 and networkCalls[1][1] == "sync")
local function payload(changes)
	local result = table.clone(state)
	result.team = team()
	for key, entry in changes or {} do result[key] = entry end
	return result
end
local function receive(value)
	snapshots.OnClientEvent:Fire(value)
end
local invalidCount = 0
local function rejected(changes)
	local invalid = payload({ team = team(changes) })
	receive(invalid)
	assert(controller._snapshot == nil and controller._hud._unavailable,
		"Malformed bounded team data was accepted")
	invalidCount += 1
end
for _, field in { "round_id", "count", "ready_count", "remaining" } do
	for _, value in { -1, 0.5, math.huge, 0 / 0, "1", false } do rejected({ [field] = value }) end
end
for _, value in { 0, 3, 5, "4", false } do rejected({ capacity = value }) end
for _, field in { "count", "ready_count", "remaining" } do rejected({ [field] = 5 }) end
rejected({ round_id = 9007199254740992 })
rejected({ count = 1, ready_count = 2 })
rejected({ count = 1, remaining = 2 })
for _, field in { "ready", "can_start" } do
	for _, value in { 0, "true", {} } do rejected({ [field] = value }) end
end
for _, value in { "ready", "escaped", "", 1, true } do rejected({ state = value }) end
for _, value in { "dropped", "", 1, true } do rejected({ key_state = value }) end
for _, value in { string.rep("A", 51), 1, false, {} } do rejected({ carrier_name = value }) end
for key in team() do
	local missing = team()
	missing[key] = nil
	receive(payload({ team = missing }))
	assert(controller._snapshot == nil, "Missing team field was accepted: " .. key)
	invalidCount += 1
end
for _, value in { false, "team", 4 } do
	receive(payload({ team = value }))
	assert(controller._snapshot == nil)
	invalidCount += 1
end
for _, shared in {
	team({ count = 0, ready_count = 0, remaining = 0 }),
	team({ ready_count = 4, remaining = 4, carrier_name = string.rep("A", 50) }),
} do
	receive(payload({ team = shared }))
	assert(controller._snapshot ~= nil, "Valid bounded team snapshot was rejected")
end
receive(payload())
local liveHud = controller._hud
liveHud._start.Activated:Fire()
assert(liveHud._introRoot.Enabled and #networkCalls == 1)
liveHud._introConfirm.Activated:Fire()
assert(#networkCalls == 2 and networkCalls[2][1] == "start")
now += 1
liveHud:SetBusy(false)
receive(payload({ team = team({ ready = true }) }))
controller:_request("start", "hard")
liveHud:ShowObjective("start")
assert(#networkCalls == 2 and not liveHud._introRoot.Enabled,
	"Client forwarded repeated own-ready start")
receive(payload({ team = team({ state = "active", can_start = false, remaining = 3 }) }))
controller:_request("start", "hard")
assert(#networkCalls == 2, "Late join forwarded a start")
local caught = payload({ phase = "caught", catches_remaining = 1,
	capture = { id = 1, remaining = 0, frame = r.CFrame.identity },
	team = team({ state = "active", can_start = false, remaining = 3 }) })
receive(caught)
controller:_request("revive")
assert(#networkCalls == 3 and networkCalls[3][1] == "revive",
	"Client incorrectly blocked same-round revival")
now += 1
liveHud:SetBusy(false)
local second = table.clone(caught)
second.phase, second.catches_remaining = "caught_out", 0
second.capture = { id = 2, remaining = 0, frame = r.CFrame.identity }
receive(second)
controller:_request("retry", "hard")
assert(#networkCalls == 3, "Client forwarded retry during running team round")
controller:_request("menu")
assert(#networkCalls == 4 and networkCalls[4][1] == "menu")
now += 1
liveHud:SetBusy(false)
second.team = team({ state = "finished", ready_count = 0 })
receive(second)
controller:_request("retry", "hard")
assert(#networkCalls == 5 and networkCalls[5][1] == "retry")
now += 1
liveHud:SetBusy(false)
second.team = team({ state = "finished", ready = true, can_start = true })
receive(second)
controller:_request("retry", "hard")
assert(#networkCalls == 5, "Own-ready retry bypassed can_start check")
controller:Destroy()
print("PASS shared-key multiplayer UI/controller: team ready/count/remaining, carrier/search/exit objectives, confirmed readiness and stale-round cancellation, late join/result waiting, first-catch revival, final-catch retry/menu and " .. tostring(invalidCount) .. " malformed bounded team payloads. Existing solo adapter retained; no physical-input or engine-pixel claim.")
]=]
assert(loadstring(setup .. cases .. controllerSetup .. networkCases, "multiplayer-ui-focused"))()
