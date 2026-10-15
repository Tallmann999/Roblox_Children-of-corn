-- Current server methods with a limited Lune ray/geometry adapter.
-- Real Roblox Raycast/physics acceptance is tests/studio-hunt-quality.luau.
local adapter = require("./scene-adapter")
local fs, r, I = adapter.fs, adapter.r, adapter.I
local V3, CF = r.Vector3, r.CFrame
local Balance = require("../src/shared/Game/Balance")
local Stamina = require("../src/shared/Game/Stamina")
local walls = {}
local deferPaths = false
local pendingPaths = {}
local pathfindingProxy = {
	CreatePath = function()
		local began, goal
		return {
			Status = r.Enum.PathStatus.Success,
			ComputeAsync = function(_, from, to)
				began, goal = from, to
			end,
			GetWaypoints = function()
				return { { Position = began }, { Position = goal } }
			end,
		}
	end,
}
local function segmentHits(part, origin, direction)
	local point = part.CFrame:PointToObjectSpace(origin)
	local delta = part.CFrame:VectorToObjectSpace(direction)
	local half = part.Size / 2
	local low, high = 0, 1
	for _, axis in { "X", "Y", "Z" } do
		if math.abs(delta[axis]) < 0.000001 then
			if math.abs(point[axis]) > half[axis] then
				return false
			end
		else
			local a = (-half[axis] - point[axis]) / delta[axis]
			local b = (half[axis] - point[axis]) / delta[axis]
			low = math.max(low, math.min(a, b))
			high = math.min(high, math.max(a, b))
			if low > high then
				return false
			end
		end
	end
	return true
end
local workspaceProxy = {
	Raycast = function(_, origin, direction, params)
		assert(params.RespectCanCollide == true, "LOS must respect physical Props")
		assert(
			#params.FilterDescendantsInstances == 3,
			"Own monster/home/character must be excluded"
		)
		for _, wall in walls do
			if wall.CanCollide and segmentHits(wall, origin, direction) then
				return { Instance = wall }
			end
		end
		return nil
	end,
	Blockcast = function()
		return nil
	end,
}
-- Lune does not expose Position defaults on fresh BaseParts; read their CFrame instead.
local source = fs.readFile("src/server/Game/MonsterHunt.luau")
for _, name in { "world.Ground", "home", "self.root", "playerRoot", "slot", "self.patrolSlot" } do
	local pattern = name:gsub("%.", "%%.") .. "%.Position"
	source = source:gsub(pattern, name .. ".CFrame.Position")
end
local poseFn = assert(loadstring(fs.readFile("src/shared/Game/MonsterPose.luau")))
setfenv(
	poseFn,
	setmetatable(
		{ CFrame = CF, Vector3 = V3, Color3 = r.Color3, Enum = r.Enum },
		{ __index = getfenv() }
	)
)
local pose = poseFn()
local rsProxy = {
	WaitForChild = function(self)
		return self
	end,
}
local fn = assert(loadstring(source))
setfenv(
	fn,
	setmetatable({
		game = {
			GetService = function(_, name)
				if name == "ReplicatedStorage" then
					return rsProxy
				end
				assert(name == "PathfindingService")
				return pathfindingProxy
			end,
		},
		require = function()
			return pose
		end,
		workspace = workspaceProxy,
		Instance = I,
		Vector3 = V3,
		CFrame = CF,
		Color3 = r.Color3,
		Enum = r.Enum,
		RaycastParams = {
			new = function()
				return {}
			end,
		},
		task = {
			spawn = function(callback)
				if deferPaths then
					table.insert(pendingPaths, callback)
				else
					callback()
				end
			end,
		},
	}, { __index = getfenv() })
)
local Hunt = fn()
local scene = I.new("Model")
local home = I.new("Model")
home.Name = "Home"
home.Parent = scene
local body = I.new("Part")
body.Name = "Body"
body.CFrame = CF.new(0, 8, 0)
body.Parent = home
local ground = I.new("Part")
ground.CFrame = CF.new(0, -1, 0)
ground.Size = V3.new(840, 2, 840)
ground.Parent = scene
local runtime = I.new("Folder")
runtime.Parent = scene
local slots = {}
for _, z in { -252, -126, 0, 126, 252 } do
	for _, x in { -252, 0, 252 } do
		local slot = I.new("Part")
		slot.CFrame = CF.new(x, 0, z)
		slot:SetAttribute("slot_id", string.format("solo_slot_%02d", #slots + 1))
		slot.Parent = scene
		table.insert(slots, slot)
	end
end
local world = { Home = home, Ground = ground, Slots = slots, Runtime = runtime }
local character = I.new("Model")
character.Parent = scene
local root = I.new("Part")
root.Name = "HumanoidRootPart"
root.CFrame = CF.new(16, 3, 0)
root.Parent = character
local wall = I.new("Part")
wall.CFrame = CF.new(10, 4, 0)
wall.Size = V3.new(1, 12, 12)
wall.CanCollide = true
wall.Parent = scene
table.insert(walls, wall)
local hunt = Hunt.new(world, Balance, 0)
local origin = hunt.root.CFrame.Position
hunt:Step(0, 19.999000000000002, root, false)
assert(hunt.state == "dormant" and hunt.root.CFrame.Position == origin)
hunt:Step(0, 20.0, root, false)
assert(hunt.state == "patrol" and not hunt:CanSee(root), "Collidable wall allowed detection")
wall.CanCollide = false
hunt:Step(0, 20.1, root, false)
assert(hunt.state == "chase" and hunt:CanSee(root), "Noncollidable corn blocked detection")
local seen = root.CFrame.Position
wall.CanCollide = true
root.CFrame = CF.new(25, 3, 5)
hunt:Step(0, 20.2, root, false)
assert(hunt.goal == seen and hunt.lastSeenPosition == seen, "Hidden player updated chase goal")
hunt:Step(0, 21.449, root, false)
assert(hunt.state == "chase")
hunt:Step(0, 21.451, root, false)
assert(hunt.state == "patrol" and hunt.lastSeenPosition == nil, "Blocked LOS did not expire")
wall.CanCollide = false
root.CFrame = CF.new(16, 3, 0)
hunt:Step(0, 22.0, root, false)
wall.CanCollide = true
hunt:Step(0, 22.1, root, false)
wall.CanCollide = false
root.CFrame = CF.new(24, 3, 1)
hunt:Step(0, 23.0, root, false)
assert(
	hunt.lostSince == nil and hunt.lastSeenPosition == root.CFrame.Position,
	"Visible reacquisition retained loss timer"
)
root.CFrame = CF.new(43, 3, 0)
hunt:Step(0, 24.0, root, false)
hunt:Step(0, 25.249, root, false)
assert(hunt.state == "chase")
hunt:Step(0, 25.251, root, false)
assert(hunt.state == "patrol", "Distance loss did not expire")
wall.CFrame = CF.new(1, 4, 0)
wall.Size = V3.new(0.3, 8, 8)
wall.CanCollide = true
root.CFrame = CF.new(2, 3, 0)
hunt:_state("chase", 26)
assert(not hunt:CanCapture(root, 28), "Capture crossed collidable wall")
wall.CanCollide = false
assert(not hunt:CanCapture(root, 27.999) and hunt:CanCapture(root, 28))
assert(not hunt:Step(0, 28, root, true), "Protection allowed capture")
assert(hunt.state == "patrol" and hunt.lastSeenPosition == nil)
hunt:ResetHome()
local firstSequence = {}
for index = 1, 15 do
	firstSequence[index] = hunt:_patrol(V3.new(50000 * index, 0, 50000))
	assert(
		hunt.patrolIndex == (8 - 1 + (index - 1) * 7) % 15 + 1,
		"Wrong independent patrol stride"
	)
end
local unique = {}
for _, position in firstSequence do
	unique[tostring(position)] = true
end
local count = 0
for _ in unique do
	count += 1
end
assert(
	count == 15 and hunt:_patrol(V3.zero) == firstSequence[1],
	"Patrol did not cycle through all slots"
)
hunt:ResetHome()
for index = 1, 15 do
	assert(
		hunt:_patrol(V3.new(-50000, 0, -50000 * index)) == firstSequence[index],
		"Player position changed patrol route"
	)
end
hunt:Destroy()
-- Retain actual _path task callbacks across state changes, then complete them
-- in both orders. Stale jobs must neither clear a fresh busy flag nor replace
-- the fresh route, while repeated chase polls must retain pending work.
hunt = Hunt.new(world, Balance, 0)
deferPaths = true
hunt:_state("chase")
local chaseGoal = V3.new(20, 3, 0)
local patrolGoal = V3.new(-252, 3, 126)
hunt.route = { { Position = V3.zero }, { Position = chaseGoal } }
hunt.routeIndex = 5
hunt:_path(chaseGoal, 22)
assert(hunt.pathBusy and #pendingPaths == 1)
local chaseGeneration, chasePathAt, chaseRoute = hunt.generation, hunt.pathAt, hunt.route
hunt:_state("chase")
assert(
	hunt.generation == chaseGeneration
		and hunt.pathBusy
		and hunt.pathAt == chasePathAt
		and hunt.route == chaseRoute
		and hunt.routeIndex == 5,
	"Repeated chase cancelled a current path"
)
hunt:_state("patrol")
assert(
	hunt.generation == chaseGeneration + 1
		and hunt.route == nil
		and hunt.routeIndex == 2
		and not hunt.pathBusy
		and hunt.pathAt == -math.huge,
	"Transition retained chase route or throttled its replacement"
)
hunt:_path(patrolGoal, 22)
assert(hunt.pathBusy and #pendingPaths == 2)
pendingPaths[1]()
assert(hunt.pathBusy and hunt.route == nil, "Stale completion cleared fresh pending path")
pendingPaths[2]()
assert(not hunt.pathBusy and hunt.route[2].Position == patrolGoal, "Fresh path was rejected")
hunt:_state("chase")
hunt:_path(chaseGoal, 23)
hunt:_state("patrol")
hunt:_path(patrolGoal, 23)
assert(#pendingPaths == 4)
pendingPaths[4]()
local freshRoute = hunt.route
pendingPaths[3]()
assert(
	hunt.route == freshRoute and freshRoute[2].Position == patrolGoal,
	"Late chase replaced fresh patrol route"
)
hunt:Destroy()
pendingPaths = {}
deferPaths = false
-- Integrate the real Stamina rule and actual MonsterHunt movement on a free line.
-- Exercise the unchanged subsequent-chase contract; first chase has its own fixture.
wall.CanCollide = false
hunt = Hunt.new(world, Balance, 0)
hunt.firstChaseUsed = true
root.CFrame = CF.new(hunt.root.CFrame.Position + V3.new(16, 0, 0))
hunt:Step(0, 20.0, root, false)
assert(hunt.state == "chase")
local stamina = Stamina.new(100, 20)
assert(Stamina.Request(stamina, true, 20, true))
local lostAt = nil
for index = 1, 100 do
	local dt = 0.05
	Stamina.Step(stamina, dt, true, true, Balance)
	local speed = if stamina.sprinting then Balance.sprint_speed else Balance.walk_speed
	root.CFrame = CF.new(root.CFrame.Position + V3.new(speed * dt, 0, 0))
	assert(not hunt:Step(dt, 20 + index * dt, root, false), "Full sprint was captured")
	if hunt.state == "patrol" then
		lostAt = index * dt
		break
	end
end
assert(not lostAt and stamina.exhausted, "Preserved42stud loss rule changed unexpectedly")
assert(
	(root.CFrame.Position - hunt.root.CFrame.Position).Magnitude > Balance.monster_capture_radius,
	"Reaction plus full sprint provided no separation"
)
hunt:Destroy()
hunt = Hunt.new(world, Balance, 0)
hunt.firstChaseUsed = true
assert(
	Balance.hunt_start_delay_sec == 20
		and Balance.monster_detect_radius == 16
		and Balance.monster_chase_windup_sec == 2
)
assert(hunt.root.Size == V3.new(3, 6, 2) and hunt.model:GetAttribute("MonsterHeightScale") == 1.3)
root.CFrame = CF.new(hunt.home + V3.new(16.001, 0, 0))
assert(not hunt:Step(0, 19.999, root, false) and hunt.state == "dormant")
local captured, awakened = hunt:Step(0, 20, root, false)
assert(not captured and awakened and hunt.state == "patrol")
root.CFrame = CF.new(hunt.home + V3.new(16, 0, 0))
hunt:Step(0, 20.1, root, false)
assert(hunt.state == "chase" and hunt.chaseStartedAt == 20.1)
for _, entry in { { 20.2, 1 }, { 22.099, 1 }, { 22.1, 1.3 } } do
	root.CFrame = CF.new(hunt.root.CFrame.Position + V3.new(30, 0, 0))
	local before = hunt.root.CFrame.Position
	assert(not hunt:Step(0.1, entry[1], root, false))
	assert(
		math.abs((hunt.root.CFrame.Position - before).Magnitude - entry[2]) < 0.0001,
		"Subsequent chase windup speed10 then13"
	)
end
root.CFrame = CF.new(hunt.root.CFrame.Position + V3.new(2, 0, 0))
assert(not hunt:CanCapture(root, 22.099) and hunt:CanCapture(root, 22.1))
hunt:Step(0, 22.2, root, true)
assert(hunt.state == "patrol" and hunt.chaseStartedAt == nil)
hunt:Step(0, 22.3, root, false)
assert(hunt.chaseStartedAt == 22.3 and not hunt:CanCapture(root, 24.299))
assert(hunt:Stun(22.4, 10) and hunt.chaseStartedAt == nil)
hunt:ResetHome()
assert(hunt.chaseStartedAt == nil)
hunt:Destroy()
scene:Destroy()
print(
	"PASS: physical-wall adapter/transparent corn; hidden last-seen goal; reacquisition/distance/LOS loss timers; capture/protection; deferred paths reject stale state results without cancelling repeated chase; player-independent 15-slot cycle; actual Stamina full sprint survives (straightline escape is not guaranteed with16detect/42loss), lostAt="
		.. tostring(lostAt)
		.. "s"
)
