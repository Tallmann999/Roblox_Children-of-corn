-- Project-local Lune OR verified Children_of_corn Studio Server during Play.
-- Actual MonsterHunt methods. Studio: real Parts/Humanoid/LOS in owned scratch.
-- Lune: limited geometry/task adapters; does not claim engine acceptance.
-- Existing fixtures use message-free assertions; this focused fixture supplies
-- a fallback message for every check and preserves assert's returned value.
local function expect(condition, reason)
	return assert(condition, reason or "First chase acceptance assertion failed")
end
local studio = game ~= nil
local Hunt, Balance, I, V3, CF, color, scene, baseY
local pending = {}
local blockedLOS = false
if studio then
	local run = game:GetService("RunService")
	expect(
		run:IsStudio() and run:IsRunning() and run:IsServer(),
		"Verified Studio Play Server required"
	)
	local map = workspace:FindFirstChild("CornMap")
	expect(map and map:GetAttribute("corn_project_id") == "children_of_corn")
	Hunt = require(game.ServerScriptService.GameServer.Game.MonsterHunt)
	Balance = require(game.ReplicatedStorage.GameShared.Game.Balance)
	I, V3, CF, color = Instance, Vector3, CFrame, Color3
	scene = I.new("Model")
	scene.Name = "FirstChaseAcceptance"
	scene:SetAttribute("corn_test_owned", true)
	scene.Parent = workspace
	baseY = map.Ground.Position.Y + 400
else
	local adapter = require("./scene-adapter")
	local fs, r = adapter.fs, adapter.r
	I, V3, CF, color = adapter.I, r.Vector3, r.CFrame, r.Color3
	Balance = require("../src/shared/Game/Balance")
	local source = fs.readFile("src/server/Game/MonsterHunt.luau")
	for _, name in { "world.Ground", "home", "self.root", "playerRoot", "slot", "self.patrolSlot" } do
		source = source:gsub(name:gsub("%.", "%%.") .. "%.Position", name .. ".CFrame.Position")
	end
	local poseFn = expect(loadstring(fs.readFile("src/shared/Game/MonsterPose.luau")))
	setfenv(
		poseFn,
		setmetatable(
			{ CFrame = CF, Vector3 = V3, Color3 = color, Enum = r.Enum },
			{ __index = getfenv() }
		)
	)
	local pose = poseFn()
	local rs = {
		WaitForChild = function(self)
			return self
		end,
	}
	local fn = expect(loadstring(source))
	setfenv(
		fn,
		setmetatable({
			game = {
				GetService = function(_, name)
					if name == "ReplicatedStorage" then
						return rs
					end
					expect(name == "PathfindingService")
					return {
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
				end,
			},
			require = function()
				return pose
			end,
			workspace = {
				Raycast = function()
					return if blockedLOS then {} else nil
				end,
				Blockcast = function()
					return nil
				end,
			},
			Instance = I,
			Vector3 = V3,
			CFrame = CF,
			Color3 = color,
			Enum = r.Enum,
			RaycastParams = {
				new = function()
					return {}
				end,
			},
			task = {
				spawn = function(callback)
					table.insert(pending, callback)
				end,
			},
		}, { __index = getfenv() })
	)
	Hunt = fn()
	scene, baseY = I.new("Model"), 0
end
local function part(name, position, parent)
	local item = I.new("Part")
	item.Name, item.CFrame, item.Anchored = name, CF.new(position), true
	item.CanCollide, item.CanQuery, item.CanTouch = false, false, false
	item.Parent = parent or scene
	return item
end
local home = I.new("Model")
home.Parent = scene
part("Body", V3.new(0, baseY + 8, 0), home)
local ground = part("Ground", V3.new(0, baseY - 1, 0))
ground.Size = V3.new(200, 2, 200)
local runtime = I.new("Folder")
runtime.Parent = scene
local slots = {}
for index = 1, 15 do
	slots[index] = part("Slot" .. index, V3.new(index * 5, baseY, 80))
end
local world = { Home = home, Ground = ground, Slots = slots, Runtime = runtime }
local character = I.new("Model")
character.Parent = scene
local root = part("HumanoidRootPart", V3.new(16, baseY + 3, 0), character)
local humanoid = I.new("Humanoid")
humanoid.WalkSpeed = Balance.walk_speed
humanoid.Parent = character
local wall = part("LOSBlocker", V3.new(8, baseY + 4, 0))
wall.Size = V3.new(1, 12, 20)
local hunt, checks = nil, {}
local function atDistance(distance)
	root.CFrame = CF.new(hunt.root.CFrame.Position + V3.new(distance, 0, 0))
end
local function newHunt()
	if hunt then
		hunt:Destroy()
	end
	wall.CanCollide, blockedLOS = false, false
	humanoid.WalkSpeed = Balance.walk_speed
	hunt = Hunt.new(world, Balance, 0, 11644801627)
	atDistance(16)
	expect(not hunt.firstChaseUsed and hunt.firstChaseUntil == nil)
	return hunt
end
local function moveAndCheck(now, speed)
	atDistance(16)
	humanoid.WalkSpeed = speed
	local before = hunt.root.CFrame.Position
	expect(not hunt:Step(0.1, now, root, false))
	expect(
		math.abs((hunt.root.CFrame.Position - before).Magnitude - speed * 0.1) < 0.0001,
		"Actual movement does not match server WalkSpeed"
	)
end
local ok, problem = pcall(function()
	expect(
		Balance.monster_first_chase_duration_sec == 10
			and Balance.monster_first_chase_reacquire_sec == 1
	)
	newHunt()
	expect(
		not hunt:Step(0, 19.999, root, false)
			and hunt.state == "dormant"
			and not hunt.firstChaseUsed
	)
	wall.CanCollide, blockedLOS = true, true
	expect(not hunt:Step(0, 20, root, false) and hunt.state == "patrol" and not hunt.firstChaseUsed)
	wall.CanCollide, blockedLOS = false, false
	expect(not hunt:Step(0, 20.1, root, true) and not hunt.firstChaseUsed)
	moveAndCheck(20.2, 12)
	expect(hunt.firstChaseUsed and hunt.firstChaseUntil == 30.2 and hunt.chaseStartedAt == 20.2)
	for _, entry in { { 20.4, 18 }, { 21, 24 }, { 21.5, 36 }, { 22.2, 12 } } do
		moveAndCheck(entry[1], entry[2])
	end
	expect(
		hunt.firstChaseUntil == 30.2 and hunt.chaseStartedAt == 20.2,
		"Visible polls prolonged first chase"
	)
	checks.first_real_detection_consumes_once_matches_current_walk_sprint_energy = true
	atDistance(2)
	expect(
		not hunt:CanCapture(root, 22.199) and hunt:CanCapture(root, 22.2),
		"First chase must preserve two-second capture reaction"
	)
	expect(not hunt:CanCapture(root, 30.2), "First deadline must forbid capture before Step")
	checks.first_chase_two_second_no_capture = true
	-- A brief loss/reacquisition within the SAME chase must not extend deadline.
	atDistance(16)
	wall.CFrame = CF.new((root.CFrame.Position + hunt.root.CFrame.Position) / 2)
	wall.CanCollide, blockedLOS = true, true
	hunt:Step(0, 22.3, root, false)
	expect(hunt.state == "chase" and hunt.lostSince == 22.3)
	wall.CanCollide, blockedLOS = false, false
	hunt:Step(0, 22.8, root, false)
	expect(hunt.firstChaseUntil == 30.2 and hunt.chaseStartedAt == 20.2 and hunt.lostSince == nil)
	checks.los_reacquisition_does_not_extend_first_deadline = true
	atDistance(2)
	local generation = hunt.generation
	hunt.route, hunt.pathBusy =
		{ { Position = hunt.home }, { Position = root.CFrame.Position } }, true
	expect(not hunt:Step(0, 30.2, root, false), "Deadline must win over close visible capture")
	expect(hunt.state == "patrol" and hunt.firstChaseUsed and hunt.firstChaseUntil == nil)
	expect(hunt.generation == generation + 1 and hunt.route == nil and not hunt.pathBusy)
	expect(hunt.lastSeenPosition == nil and hunt.lostSince == nil and hunt.reacquireAt == 31.2)
	expect(
		not hunt:Step(0, 31.199, root, false) and hunt.state == "patrol",
		"Grace must prevent immediate redetection"
	)
	atDistance(16)
	hunt:Step(0, 31.2, root, false)
	expect(hunt.state == "chase" and hunt.firstChaseUntil == nil and hunt.chaseStartedAt == 31.2)
	checks.ten_second_deadline_before_capture_cancels_route_and_grace_one_second = true
	for _, entry in { { 31.3, 10 }, { 33.199, 10 }, { 33.2, 13 }, { 42, 13 } } do
		atDistance(16)
		humanoid.WalkSpeed = 36
		local before = hunt.root.CFrame.Position
		expect(not hunt:Step(0.1, entry[1], root, false))
		expect(math.abs((hunt.root.CFrame.Position - before).Magnitude - entry[2] * 0.1) < 0.0001)
	end
	expect(hunt.state == "chase", "Subsequent chase must not time out after ten seconds")
	checks.subsequent_chase_retains_ten_then_thirteen_and_no_forced_ten_second_loss = true
	for _, ending in { "trap", "capture", "home", "protection", "los", "distance" } do
		newHunt():Step(0, 20, root, false)
		expect(hunt.firstChaseUntil == 30)
		if ending == "trap" then
			expect(hunt:Stun(20.1, 10))
		elseif ending == "capture" then
			hunt:BeginCapture(root.CFrame.Position)
		elseif ending == "protection" then
			hunt:Step(0, 20.1, root, true)
		elseif ending == "los" then
			wall.CFrame = CF.new((root.CFrame.Position + hunt.root.CFrame.Position) / 2)
			wall.CanCollide, blockedLOS = true, true
			hunt:Step(0, 20.1, root, false)
			hunt:Step(0, 21.351, root, false)
			expect(hunt.state == "patrol")
		elseif ending == "distance" then
			atDistance(43)
			hunt:Step(0, 20.1, root, false)
			hunt:Step(0, 21.351, root, false)
			expect(hunt.state == "patrol")
		end
		hunt:ResetHome()
		expect(
			hunt.firstChaseUsed and hunt.firstChaseUntil == nil,
			"Ending/home reset renewed special chase: " .. ending
		)
		wall.CanCollide, blockedLOS = false, false
		atDistance(16)
		hunt:Step(0, 32, root, false)
		expect(hunt.state == "chase" and hunt.firstChaseUntil == nil and hunt.firstChaseUsed)
	end
	checks.trap_capture_home_protection_los_distance_do_not_refund_special_chase = true
	newHunt():Step(0, 20, root, false)
	expect(hunt.firstChaseUntil == 30, "New round must renew first chase")
	humanoid.WalkSpeed = 0
	expect(hunt:_chaseSpeed(root, 20.1) == 12, "Zero speed fallback")
	humanoid.WalkSpeed = 1000
	expect(hunt:_chaseSpeed(root, 20.1) == 36, "Server speed upper bound")
	if not studio then
		for _, invalid in { "36", {}, 0 / 0, math.huge, -math.huge, -1 } do
			local invalidRoot = {
				Parent = {
					FindFirstChildOfClass = function()
						return { WalkSpeed = invalid }
					end,
				},
			}
			expect(hunt:_chaseSpeed(invalidRoot, 20.1) == 12, "Invalid speed accepted")
		end
	end
	humanoid.Parent = nil
	expect(hunt:_chaseSpeed(root, 20.1) == 12, "Missing Humanoid fallback")
	humanoid.Parent = character
	checks.new_round_renews_first_chase_speed_is_bounded_and_invalid_falls_back = true
	if not studio then
		pending = {}
		hunt:_path(root.CFrame.Position, 20)
		expect(hunt.pathBusy and #pending == 1)
		hunt:Step(0, 30, root, false)
		expect(hunt.state == "patrol" and not hunt.pathBusy)
		local freshGoal = V3.new(-40, baseY + 3, 80)
		hunt:_path(freshGoal, 30)
		expect(hunt.pathBusy and #pending == 2)
		pending[1]()
		expect(
			hunt.pathBusy and hunt.route == nil,
			"Expired first chase completion corrupted fresh pending route"
		)
		pending[2]()
		expect(not hunt.pathBusy and hunt.route[2].Position == freshGoal)
		checks.deferred_expired_first_chase_path_cannot_overwrite_fresh_patrol = true
	end
	checks.method = if studio
		then "Real engine Parts/Humanoid/LOS with current server methods and controlled logical time; owned isolated world; no live character/gameplay/world changes or ordinary-round claim"
		else "Current server methods with Lune instance/LOS/deferred-path adapters; no engine or ordinary-round claim"
end)
if hunt then
	hunt:Destroy()
end
if humanoid.Parent == nil then
	humanoid:Destroy()
end
scene:Destroy()
expect(ok, tostring(problem))
checks.cleanup = true
if studio then
	return game:GetService("HttpService"):JSONEncode(checks)
end
print(
	"PASS first-chase: server speed12/18/24/36, no early capture, forced loss10s before capture, grace1s, later10/13, one per round through endings, speed validation, deferred route epoch"
)
return checks
