-- Real MonsterHunt/Balance and engine LOS in an isolated runtime scratch.
-- No player, saved map, working hunters or Lighting modifications.
assert(game:GetService("RunService"):IsServer() and game:GetService("RunService"):IsRunning())
assert(workspace.CornMap:GetAttribute("corn_project_id") == "children_of_corn")
local Hunt = require(game.ServerScriptService.GameServer.Game.MonsterHunt)
local Balance = require(game.ReplicatedStorage.GameShared.Game.Balance)
local owner = assert(game.Players:GetPlayers()[1])
local scratch = Instance.new("Folder")
scratch.Name = "CornEntityDetectionAcceptance"
scratch:SetAttribute("CornDiagnosticOwned", true)
scratch.Parent = workspace
local function part(name, position, parent, collidable)
	local value = Instance.new("Part")
	value.Name = name
	value.Position = position
	value.Anchored = true
	value.CanCollide = collidable == true
	value.CanQuery = collidable == true
	value.Parent = parent
	return value
end
local ground = part("Ground", Vector3.new(0, 499, 0), scratch, true)
ground.Size = Vector3.new(630, 2, 630)
local home = Instance.new("Model")
home.Parent = scratch
part("Body", Vector3.new(0, 504, 0), home)
local runtime = Instance.new("Folder")
runtime.Parent = scratch
local slots = {}
for index = 1, 15 do
	local slot = part(
		"Slot" .. index,
		Vector3.new((index % 5 - 2) * 80, 500, (math.floor((index - 1) / 5) - 1) * 80),
		scratch
	)
	slot:SetAttribute("slot_id", tostring(index))
	table.insert(slots, slot)
end
local character = Instance.new("Model")
character.Parent = scratch
local root = part("HumanoidRootPart", Vector3.new(40, 503, 0), character)
local world = { Home = home, Ground = ground, Runtime = runtime, Slots = slots }
local checks, hunt = {}, nil
local ok, problem = xpcall(function()
	assert(Balance.monster_detect_radius == 48)
	for _, final in { false, true } do
		local radius = if final then 96 else 48
		for index = 1, if final then 3 else 1 do
			for _, offset in { -0.01, 0.01 } do
				hunt =
					Hunt.new(world, Balance, 0, owner.UserId, { index = index, immediate = true })
				if final then
					hunt:SetDetectionMultiplier(2)
				end
				root.CFrame = CFrame.new(hunt.root.Position + Vector3.new(radius + offset, 0, 0))
				local caught = hunt:Step(0, os.clock(), root, false)
				assert(not caught and hunt.detectRadius == radius)
				assert(hunt.state == (if offset < 0 then "chase" else "patrol"))
				table.insert(
					checks,
					{
						index = index,
						radius = radius,
						tested_distance = radius + offset,
						state = hunt.state,
					}
				)
				hunt:Destroy()
				hunt = nil
			end
		end
	end
	hunt = Hunt.new(world, Balance, 0, owner.UserId, { immediate = true })
	root.CFrame = CFrame.new(hunt.root.Position + Vector3.new(40, 0, 0))
	local wall = part("PhysicalWall", Vector3.new(20, 504, 0), scratch, true)
	wall.Size = Vector3.new(1, 12, 12)
	hunt:Step(0, os.clock(), root, false)
	assert(hunt.state == "patrol" and not hunt:CanSee(root))
	wall.CanCollide = false
	hunt:Step(0, os.clock(), root, true)
	assert(hunt.state == "patrol")
	hunt:Step(0, os.clock(), root, false)
	assert(hunt.state == "chase")
	table.insert(checks, { physical_los = true, protection = true, visible_at_40 = true })
end, debug.traceback)
if hunt then
	hunt:Destroy()
end
scratch:Destroy()
assert(ok, problem)
return {
	passed = true,
	base_radius = 48,
	finale_radius = 96,
	checks = checks,
	scratch_removed = true,
	scope = "Actual production NPC methods and real engine LOS; isolated actors, no player or author-world changes",
}
