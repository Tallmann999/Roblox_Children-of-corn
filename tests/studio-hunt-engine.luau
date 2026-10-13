local m = workspace.CornMap
local scratch = Instance.new("Folder")
scratch.Name = "HuntAcceptanceScratch"
scratch.Parent = m.CornRoundRuntime
local Hunt = require(game.ServerScriptService.GameServer.Game.MonsterHunt)
local balance = require(game.ReplicatedStorage.GameShared.Game.Balance)
local world = {
	Home = m.Props.ScarecrowMarker,
	Ground = m.Ground,
	Slots = m.KeySlots:GetChildren(),
	Runtime = scratch,
}
local begun = os.clock()
local hunt = Hunt.new(world, balance, begun)
local fake = Instance.new("Model")
fake.Parent = scratch
local root = Instance.new("Part")
root.Name = "TestRoot"
root.Anchored = true
root.CanCollide = false
root.CanQuery = false
root.Parent = fake
local checks = {}
local ok, err = pcall(function()
	root.CFrame = CFrame.new(hunt.home + Vector3.new(16, 0, 0))
	hunt:Step(0, begun + 19.990000000000002, root, false)
	assert(hunt.state == "dormant" and hunt.root.Position == hunt.home)
	checks.delay = true
	hunt:Step(0, begun + 20.0, root, false)
	assert(hunt.state == "chase")
	root.CFrame = CFrame.new(hunt.home + Vector3.new(48, 0, 0))
	hunt:Step(0, begun + 20.1, root, false)
	hunt:Step(0, begun + 21.61, root, false)
	assert(hunt.state == "patrol")
	checks.escape_threshold = true
	hunt:ResetHome()
	root.CFrame = CFrame.new(hunt.home + Vector3.new(2, 0, 0))
	hunt:_state("chase", begun + 22)
	assert(not hunt:CanCapture(root, begun + 23.999) and hunt:CanCapture(root, begun + 24))
	local wall = Instance.new("Part")
	wall.Anchored = true
	wall.Size = Vector3.new(0.3, 8, 8)
	wall.CFrame = CFrame.new(hunt.home + Vector3.new(1, 0, 0))
	wall.Parent = scratch
	assert(not hunt:CanCapture(root, begun + 24))
	wall:Destroy()
	checks.no_capture_through_wall = true
	local captured = hunt:Step(0, begun + 22.0, root, true)
	assert(not captured)
	checks.protection = true
	local body = m.Props.HouseWest.Body
	local center = Vector3.new(body.Position.X, hunt.home.Y, body.Position.Z)
	hunt.model:PivotTo(CFrame.new(center + Vector3.new(0, 0, -18)))
	root.CFrame = CFrame.new(center + Vector3.new(0, 0, 18))
	hunt:_state("chase")
	hunt.goal = nil
	hunt.route = nil
	hunt.pathAt = -math.huge
	local pathCount = 0
	for i = 1, 70 do
		local caught = hunt:Step(0.1, begun + 23.0 + i * 0.1, root, false)
		local localPos = body.CFrame:PointToObjectSpace(hunt.root.Position)
		assert(
			math.abs(localPos.X) >= body.Size.X / 2 or math.abs(localPos.Z) >= body.Size.Z / 2,
			"Monster entered house"
		)
		if hunt.route then
			pathCount = math.max(pathCount, #hunt.route)
		end
		if caught then
			break
		end
		task.wait(0.1)
	end
	assert(pathCount > 0, "Pathfinding route missing")
	assert((hunt.root.Position - root.Position).Magnitude < 4, "Could not route around house")
	checks.path_around_house = true
	checks.route_waypoints = pathCount
end)
hunt:Destroy()
scratch:Destroy()
assert(ok, tostring(err))
return game.HttpService:JSONEncode(checks)
