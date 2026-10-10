-- Only verified Children_of_corn Server during Play. Owned scratch NPC/Parts;
-- no player teleport, no alteration of the working hunt, no saved scene writes.
local run = game:GetService("RunService")
assert(run:IsStudio() and run:IsRunning(), "Use the verified Studio Server during Play")
local map = workspace.CornMap
assert(map:GetAttribute("corn_project_id") == "children_of_corn")
local scratch = Instance.new("Folder")
scratch.Name = "HuntQualityAcceptance"
scratch.Parent = map.CornRoundRuntime
local Hunt = require(game.ServerScriptService.GameServer.Game.MonsterHunt)
local balance = require(game.ReplicatedStorage.GameShared.Game.Balance)
local slots = map.KeySlots:GetChildren()
table.sort(slots, function(a, b)
	return a:GetAttribute("slot_id") < b:GetAttribute("slot_id")
end)
local world =
	{ Home = map.Props.ScarecrowMarker, Ground = map.Ground, Slots = slots, Runtime = scratch }
local hunt = Hunt.new(world, balance, 0)
local character = Instance.new("Model")
character.Parent = scratch
local root = Instance.new("Part")
root.Name = "HumanoidRootPart"
root.Anchored = true
root.CanCollide = false
root.CanQuery = false
root.Parent = character
local wall = Instance.new("Part")
wall.Anchored = true
wall.CanCollide = true
wall.Size = Vector3.new(1, 12, 12)
wall.Parent = scratch
local checks = {}
local ok, problem = pcall(function()
	root.CFrame = CFrame.new(hunt.root.Position + Vector3.new(20, 0, 0))
	wall.CFrame = CFrame.new(hunt.root.Position + Vector3.new(10, 1, 0))
	hunt:Step(0, 14.999, root, false)
	assert(hunt.state == "dormant")
	hunt:Step(0, 15, root, false)
	assert(not hunt:CanSee(root) and hunt.state == "patrol")
	checks.collidable_wall_blocks_detection = true
	wall.CanCollide = false
	hunt:Step(0, 15.1, root, false)
	assert(hunt:CanSee(root) and hunt.state == "chase")
	checks.noncollidable_corn_does_not_block = true
	local seen = root.Position
	wall.CanCollide = true
	root.CFrame = CFrame.new(hunt.root.Position + Vector3.new(25, 0, 5))
	hunt:Step(0, 15.2, root, false)
	assert(hunt.goal == seen and hunt.lastSeenPosition == seen)
	hunt:Step(0, 16.449, root, false)
	assert(hunt.state == "chase")
	hunt:Step(0, 16.451, root, false)
	assert(hunt.state == "patrol")
	checks.hidden_goal_frozen_and_lost_after_1_25 = true
	wall.CanCollide = false
	root.CFrame = CFrame.new(hunt.root.Position + Vector3.new(20, 0, 0))
	hunt:Step(0, 17, root, false)
	root.CFrame = CFrame.new(hunt.root.Position + Vector3.new(43, 0, 0))
	hunt:Step(0, 17.1, root, false)
	hunt:Step(0, 18.349, root, false)
	assert(hunt.state == "chase")
	hunt:Step(0, 18.351, root, false)
	assert(hunt.state == "patrol")
	checks.distance_loss_42_after_1_25 = true
	root.CFrame = CFrame.new(hunt.root.Position + Vector3.new(2, 0, 0))
	wall.Size = Vector3.new(0.3, 8, 8)
	wall.CFrame = CFrame.new(hunt.root.Position + Vector3.new(1, 1, 0))
	wall.CanCollide = true
	assert(not hunt:CanCapture(root))
	wall.CanCollide = false
	assert(hunt:CanCapture(root) and not hunt:Step(0, 19, root, true))
	checks.capture_wall_and_protection = true
	hunt:ResetHome()
	local sequence, seenSlots = {}, {}
	for index = 1, 15 do
		sequence[index] = hunt:_patrol(Vector3.new(index * 10000, 0, 10000))
		assert(not seenSlots[hunt.patrolIndex])
		seenSlots[hunt.patrolIndex] = true
		if index > 1 then
			assert(hunt.patrolIndex == (sequence[index - 1].index - 1 + 7) % 15 + 1)
		end
		sequence[index] = { position = sequence[index], index = hunt.patrolIndex }
	end
	assert(hunt:_patrol(Vector3.zero) == sequence[1].position)
	hunt:ResetHome()
	for index = 1, 15 do
		assert(hunt:_patrol(Vector3.new(-10000, 0, -index * 10000)) == sequence[index].position)
	end
	checks.player_independent_full_cycle = true
	-- Synchronous engine state fixture: no artificial async path service.
	hunt:_state("chase")
	local generation = hunt.generation
	local retainedRoute = { { Position = hunt.home }, { Position = root.Position } }
	hunt.route, hunt.routeIndex, hunt.pathBusy, hunt.pathAt = retainedRoute, 4, true, 100
	hunt:_state("chase")
	assert(hunt.generation == generation and hunt.route == retainedRoute)
	assert(hunt.routeIndex == 4 and hunt.pathBusy and hunt.pathAt == 100)
	hunt:_state("patrol")
	assert(hunt.generation == generation + 1 and hunt.route == nil)
	assert(hunt.routeIndex == 2 and not hunt.pathBusy and hunt.pathAt == -math.huge)
	checks.state_transition_cancels_routes_same_chase_preserves = true
	checks.method =
		"Real Studio Raycast with collidable wall/noncollidable corn, current MonsterHunt methods, isolated owned scratch; ordinary walkthrough separate"
end)
hunt:Destroy()
scratch:Destroy()
assert(ok, tostring(problem))
return game.HttpService:JSONEncode(checks)
