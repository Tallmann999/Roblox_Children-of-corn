-- Production MonsterHunt and Balance with the existing finite geometry adapter.
-- Actual Roblox geometry acceptance is a separate Studio fixture.
local fs = require("@lune/fs")
local adapter = require("./scene-adapter")
local balance = require("../src/shared/Game/Balance")
local stamina = require("../src/shared/Game/Stamina")
local setup = assert(fs.readFile("tests/hunt-quality.luau"):match("^(.-)local wall = I.new"))
local cases = [=[
assert(Balance.monster_detect_radius == 48, "Confirmed base detection must be 48")
for _, final in {false, true} do
	local expected = if final then 96 else 48
	for index = 1, if final then 3 else 1 do
		for _, inside in {true, false} do
			local hunt = Hunt.new(world, Balance, 0, 123, {index=index, immediate=true})
			if final then hunt:SetDetectionMultiplier(2) end
			assert(hunt.detectRadius == expected)
			root.CFrame = CF.new(hunt.root.CFrame.Position + V3.new(expected + (if inside then -0.001 else 0.001),0,0))
			local caught = hunt:Step(0, 20, root, false)
			assert(not caught)
			assert(hunt.state == (if inside then "chase" else "patrol"), "Wrong acquisition boundary")
			hunt:Destroy()
		end
	end
end
local wall = I.new("Part")
wall.CFrame, wall.Size, wall.CanCollide = CF.new(20,4,0), V3.new(1,12,12), true
wall.Parent = scene
table.insert(walls, wall)
local hunt = Hunt.new(world, Balance, 0, 123, {immediate=true})
root.CFrame = CF.new(hunt.root.CFrame.Position + V3.new(40,0,0))
hunt:Step(0,20,root,false)
assert(hunt.state == "patrol", "Expanded range must still respect physical LOS")
wall.CanCollide = false
hunt:Step(0,20.1,root,true)
assert(hunt.state == "patrol", "Protection still prevents acquisition")
hunt:Step(0,20.2,root,false)
assert(hunt.state == "chase", "Expanded range must detect a visible player at40")
hunt:Destroy()
print("PASS entity-detection: production48/96 boundaries for all three finale NPCs, physical LOS, protection and real acquisition at40; geometry adapter, not native physics")
]=]
local fn = assert(loadstring(setup .. cases, "entity-detection"))
setfenv(
	fn,
	setmetatable({
		require = function(path)
			if path == "./scene-adapter" then
				return adapter
			end
			if path == "../src/shared/Game/Balance" then
				return balance
			end
			if path == "../src/shared/Game/Stamina" then
				return stamina
			end
			error("Unexpected setup dependency: " .. path)
		end,
	}, { __index = getfenv() })
)
fn()
