-- Run only in the verified Studio Server during Play. Independent engine fixture;
-- relocates the test avatar temporarily and restores it. Does not fire E input.
local p = game.Players:GetPlayers()[1]
local root, h = p.Character.HumanoidRootPart, p.Character.Humanoid
local map = workspace.CornMap
local savedFrame, savedVelocity = root.CFrame, root.AssemblyLinearVelocity
local savedSpeed, savedJumpPower, savedJumpHeight = h.WalkSpeed, h.JumpPower, h.JumpHeight
local scratch = Instance.new("Folder")
scratch.Name = "HuntPriorityScratch"
scratch.Parent = map.CornRoundRuntime
local Round = require(game.ServerScriptService.GameServer.Game.SoloRound)
local Hunt = require(game.ServerScriptService.GameServer.Game.MonsterHunt)
local World = require(game.ServerScriptService.GameServer.Game.AuthoredWorld)
local balance = require(game.ReplicatedStorage.GameShared.Game.Balance)
local snapshots = {}
local channel = {
	FireClient = function(_, _, snapshot)
		table.insert(snapshots, snapshot)
	end,
}
local context = {
	Config = { CoreLoop = balance },
	Services = { NetworkService = {
		GetEvent = function()
			return channel
		end,
	} },
	Log = { Info = function() end },
}
local world = {
	Root = map,
	Runtime = scratch,
	Home = map.Props.ScarecrowMarker,
	Ground = map.Ground,
	Slots = map.KeySlots:GetChildren(),
	Bounds = map.PlayBounds,
	Exit = map.EscapeGate.ExitZone,
	IsValid = function()
		return true
	end,
	ClearKey = function() end,
	SetInteractionEnabled = function() end,
	IsOnPlayground = World.IsOnPlayground,
	IsInExit = World.IsInExit,
}
local hunt
local ok, problem = pcall(function()
	root.CFrame = CFrame.new(
		map.EscapeGate.ExitZone.Position.X,
		17.399986,
		map.EscapeGate.ExitZone.Position.Z
	)
	root.AssemblyLinearVelocity = Vector3.zero
	assert(world:IsInExit(root.Position))
	local now = os.clock()
	local first = Round.new(context)
	first.player = p
	first.roundCharacter = p.Character
	first.phase = "active"
	first.world = world
	first.startedAt = now - 16
	first.hunt = Hunt.new(world, balance, now - 16)
	first:_caught(root)
	assert(snapshots[#snapshots].phase == "caught" and snapshots[#snapshots].elapsed_sec >= 16)
	first:_finish("aborted", "") -- Cancels this fixture's delayed return.
	local caught = Round.new(context)
	caught.player = p
	caught.roundCharacter = p.Character
	caught.phase = "active"
	caught.world = world
	caught.gateOpen = true
	caught.catches = 1
	caught.startedAt = now - 16
	caught.huntAt = now
	hunt = Hunt.new(world, balance, now - 16)
	caught.hunt = hunt
	hunt.root.CFrame = CFrame.new(root.Position + Vector3.new(1.5, 0, 0))
	hunt:_state("chase", now - 2)
	caught:_poll(now)
	assert(
		caught.phase == "caught"
			and caught.catches == 2
			and caught.reward == 0
			and caught.hunt.state == "capturing"
	)
	task.wait(balance.capture_transition_sec + 0.1)
	assert(caught.phase == "caught_out" and caught.reward == 0 and caught.diamonds == 0)
	assert(caught.hunt == nil and not scratch:FindFirstChild("Monster"))
	local escaped = Round.new(context)
	escaped.player = p
	escaped.roundCharacter = p.Character
	escaped.phase = "active"
	escaped.world = world
	escaped.gateOpen = true
	escaped.startedAt = now
	escaped:_poll(now)
	escaped:_poll(now + 0.1)
	assert(escaped.phase == "escaped" and escaped.reward == 10 and escaped.diamonds == 10)
end)
if hunt then
	hunt:Destroy()
end
scratch:Destroy()
root.CFrame = savedFrame
root.AssemblyLinearVelocity = savedVelocity
h.WalkSpeed = savedSpeed
h.JumpPower = savedJumpPower
h.JumpHeight = savedJumpHeight
assert(ok, tostring(problem))
return game.HttpService:JSONEncode({
	capture_before_escape = true,
	capture_reward = 0,
	escape_reward_once = 10,
	first_capture_elapsed_preserved = true,
	method = "isolated server engine fixture",
})
