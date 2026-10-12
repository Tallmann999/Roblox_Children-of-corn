-- Run with project-local Lune, or as code_file on verified Children_of_corn
-- Server during Play. Studio uses real Parts/LOS; only an owned scratch NPC
-- and test character are changed, never the player or working hunt.
local studio = game ~= nil
local Hunt, Balance, I, V3, CF, color
local pendingPaths = {}
local scene, baseY
if studio then
	local run = game:GetService("RunService")
	assert(run:IsStudio() and run:IsRunning(), "Use verified Studio Server during Play")
	local map = workspace:FindFirstChild("CornMap")
	assert(map and map:GetAttribute("corn_project_id") == "children_of_corn")
	assert(map:FindFirstChild("CornRoundRuntime"))
	Hunt = require(game.ServerScriptService.GameServer.Game.MonsterHunt)
	Balance = require(game.ReplicatedStorage.GameShared.Game.Balance)
	I, V3, CF, color = Instance, Vector3, CFrame, Color3
	scene = I.new("Folder")
	scene.Name = "MonsterTrapAcceptance"
	scene:SetAttribute("corn_inventory_owned", true)
	scene:SetAttribute("corn_project_id", "children_of_corn")
	scene.Parent = map.CornRoundRuntime
	baseY = map.Ground.Position.Y + 300
else
	local adapter = require("./scene-adapter")
	local fs, r = adapter.fs, adapter.r
	I, V3, CF, color = adapter.I, r.Vector3, r.CFrame, r.Color3
	Balance = require("../src/shared/Game/Balance")
	local source = fs.readFile("src/server/Game/MonsterHunt.luau")
	for _, name in { "world.Ground", "home", "self.root", "playerRoot", "slot", "self.patrolSlot" } do
		source = source:gsub(name:gsub("%.", "%%.") .. "%.Position", name .. ".CFrame.Position")
	end
	local fn = assert(loadstring(source))
	setfenv(
		fn,
		setmetatable({
			game = {
				GetService = function(_, name)
					assert(name == "PathfindingService")
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
			workspace = {
				Raycast = function()
					return nil
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
					table.insert(pendingPaths, callback)
				end,
			},
		}, { __index = getfenv() })
	)
	Hunt = fn()
	scene = I.new("Model")
	baseY = 0
end

local function part(name, frame, parent)
	local p = I.new("Part")
	p.Name, p.CFrame, p.Anchored = name, frame, true
	p.CanCollide, p.CanTouch, p.CanQuery = false, false, false
	p.Parent = parent
	return p
end
local home = I.new("Model")
home.Parent = scene
part("Body", CF.new(0, baseY + 8, 0), home)
local ground = part("Ground", CF.new(0, baseY - 1, 0), scene)
ground.Size = V3.new(840, 2, 840)
local runtime = I.new("Folder")
runtime.Parent = scene
local slots = {}
for index = 1, 15 do
	slots[index] = part("Slot" .. index, CF.new(index * 10, baseY, 100), scene)
end
local world = { Home = home, Ground = ground, Slots = slots, Runtime = runtime }
local character = I.new("Model")
character.Parent = scene
local root = part("HumanoidRootPart", CF.new(100, baseY + 3, 0), character)
local hunt = Hunt.new(world, Balance, 0)
local checks = {}
local ok, problem = pcall(function()
	assert(not hunt:Stun(1, 10) and hunt:GetPosition() == nil)
	hunt:Step(0, Balance.hunt_start_delay_sec, root, true)
	assert(hunt.state == "patrol" and hunt:GetPosition() == hunt.root.CFrame.Position)
	checks.dormant_cannot_trigger = true

	for _, invalid in { "10", {}, 0 / 0, math.huge, -math.huge } do
		assert(not hunt:Stun(invalid, 10), "Invalid clock accepted")
		assert(not hunt:Stun(20, invalid), "Invalid duration accepted")
	end
	assert(not hunt:Stun(20, 0) and not hunt:Stun(20, -1))
	assert(hunt.state == "patrol" and hunt.stunnedUntil == nil)
	checks.invalid_duration_and_clock = true

	hunt:_state("chase")
	hunt.goal, hunt.lastSeenPosition, hunt.lostSince =
		root.CFrame.Position, root.CFrame.Position, 19
	hunt.blockedSince = 19
	hunt.route = { { Position = hunt.home }, { Position = root.CFrame.Position } }
	hunt.routeIndex = 4
	if not studio then
		hunt:_path(root.CFrame.Position, 20)
	end
	local generation = hunt.generation
	local original = hunt.root.CFrame
	assert(hunt:Stun(20, 10))
	assert(hunt.state == "trapped" and hunt.model:GetAttribute("HuntState") == "trapped")
	assert(hunt.stunnedUntil == 30 and hunt.generation == generation + 1)
	assert(hunt.route == nil and hunt.routeIndex == 2 and not hunt.pathBusy)
	assert(hunt.goal == nil and hunt.lastSeenPosition == nil and hunt.lostSince == nil)
	assert(hunt.blockedSince == nil)
	checks.trap_cancels_navigation_and_last_seen = true
	if not studio then
		assert(#pendingPaths == 1)
		pendingPaths[1]()
		assert(hunt.route == nil and not hunt.pathBusy)
		checks.deferred_chase_result_rejected = true
	end

	root.CFrame = CF.new(original.Position + V3.new(2, 0, 0))
	assert(not hunt:CanCapture(root))
	for _, now in { 20, 21, 25, 29.999 } do
		local caught, awakened = hunt:Step(0.25, now, root, false)
		assert(not caught and not awakened and hunt.root.CFrame == original)
		assert(hunt.state == "trapped")
	end
	assert(not hunt:Stun(25, 10) and hunt.stunnedUntil == 30)
	checks.freeze_no_capture_no_extension = true
	assert(hunt:Step(0, 30, root, false))
	assert(hunt.state == "chase" and hunt.stunnedUntil == nil)
	checks.exact_ten_second_release_and_visible_reacquisition = true

	assert(hunt:Stun(40, 10))
	root.CFrame = CF.new(original.Position + V3.new(100, 0, 0))
	assert(not hunt:Step(0, 50, root, false))
	assert(hunt.state == "patrol" and hunt.lastSeenPosition == nil)
	checks.release_forgets_escaped_player = true

	assert(hunt:Stun(60, 10))
	hunt:ResetHome()
	assert(hunt.state == "patrol" and hunt.stunnedUntil == nil)
	assert(hunt.root.CFrame.Position == hunt.home)
	checks.reset_clears_trap = true
	assert(hunt:Stun(70, 10))
	hunt:Destroy()
	assert(hunt:GetPosition() == nil and not hunt:Stun(71, 10))
	assert(not hunt:CanCapture(root) and not hunt:Step(0.25, 80, root, false))
	checks.destroy_clears_and_refuses_actions = true
end)
if not hunt.destroyed then
	hunt:Destroy()
end
scene:Destroy()
assert(ok, tostring(problem))
if studio then
	checks.method =
		"Real Studio Parts/LOS with isolated scratch NPC, synthetic authoritative clock; actual planted-trap sweep is a separate integration test"
	return game:GetService("HttpService"):JSONEncode(checks)
end
print(
	"PASS monster-trap: dormant/invalid guards, route cancellation including late async result, no motion/capture for 10 seconds, no stacking, exact expiry/reacquisition/escape, reset/destroy"
)
