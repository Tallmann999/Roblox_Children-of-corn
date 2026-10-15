-- Production MonsterHunt selection with the existing geometry/LOS/path adapters.
-- Registered actor tables are server inputs; this is not network/Studio acceptance.
local fs = require("@lune/fs")
local adapter = require("./scene-adapter")
local balance = require("../src/shared/Game/Balance")
local setup = assert(
	fs.readFile("tests/first-chase.luau"):match("^(.-)local ok, problem = pcall%(function%(%)")
)
setup = setup:gsub('"self%.root",', '"self.root", "candidate.root", "root",')
local cases = [=[
local secondCharacter = I.new("Model")
secondCharacter.Parent = scene
local secondRoot = part("HumanoidRootPart", V3.new(8, baseY + 3, 0), secondCharacter)
local secondHumanoid = I.new("Humanoid")
secondHumanoid.WalkSpeed, secondHumanoid.Parent = 24, secondCharacter
local a = { userId = 11644801627, root = root, protected = false }
local b = { userId = -2, root = secondRoot, protected = false }
local function position(candidate, distance)
    candidate.root.CFrame = CF.new(hunt.root.CFrame.Position + V3.new(distance, 0, 0))
end
local count = 0
local function countedHunt()
    newHunt()
    count = 0
    hunt.Step = function(self, ...)
        count += 1
        return Hunt.Step(self, ...)
    end
    a.protected, b.protected = false, false
    position(a, 14)
    position(b, 8)
end
local ok, problem = pcall(function()
    countedHunt()
    local before = hunt.root.CFrame.Position
    local caught, awakened = hunt:StepPlayers(0.1, 20, {a, b})
    expect(caught == nil and awakened and count == 1, "One NPC tick must call Step exactly once")
    expect(hunt.targetRoot == secondRoot and hunt.targetUserId == -2 and hunt.state == "chase")
    expect(hunt.model:GetAttribute("ChaseTargetUserId") == -2, "Registered negative Studio ID lost")
    expect(math.abs((hunt.root.CFrame.Position - before).Magnitude - 2.4) < 0.0001,
        "First chase must use selected target's server WalkSpeed")
    local began, untilAt = hunt.chaseStartedAt, hunt.firstChaseUntil
    position(a, 2)
    hunt:StepPlayers(0, 20.1, {a, b})
    expect(hunt.targetRoot == secondRoot and hunt.chaseStartedAt == began and hunt.firstChaseUntil == untilAt,
        "A closer teammate must not steal a retained chase or restart its timers")

    local actualCanSee = hunt.CanSee
    hunt.CanSee = function(self, target)
        return target ~= secondRoot and actualCanSee(self, target)
    end
    hunt:StepPlayers(0, 20.2, {a, b})
    expect(hunt.targetRoot == secondRoot and hunt.state == "chase" and hunt.lostSince == 20.2,
        "Brief target occlusion must retain chase through its normal loss delay")
    hunt:StepPlayers(0, 21.451, {a, b})
    expect(hunt.state == "patrol", "Normal occlusion loss timeout must still work")
    hunt:StepPlayers(0, 21.5, {a, b})
    expect(hunt.targetRoot == root and hunt.state == "chase", "Visible eligible teammate must acquire after loss")

    countedHunt()
    hunt:StepPlayers(0, 20, {a, b})
    pending = {}
    hunt:_path(secondRoot.CFrame.Position, 20)
    expect(hunt.pathBusy and #pending == 1)
    local generation = hunt.generation
    before = hunt.root.CFrame.Position
    hunt:StepPlayers(0, 20.1, {a})
    expect(hunt.targetRoot == root and hunt.targetUserId == a.userId and hunt.generation > generation)
    expect(hunt.root.CFrame.Position == before and hunt.route == nil and not hunt.pathBusy,
        "Departure must cancel the old chase path without teleport")
    pending[1]()
    expect(hunt.route == nil, "Departed target's async path must never reappear")
    a.protected = true
    hunt:StepPlayers(0, 20.2, {a})
    expect(hunt.state == "patrol" and hunt.targetRoot == nil and hunt.model:GetAttribute("ChaseTargetUserId") == 0)
    a.protected = false
    local replacement = part("ReplacementRoot", root.CFrame.Position, secondCharacter)
    hunt:StepPlayers(0, 20.3, {a})
    local oldStart = hunt.chaseStartedAt
    a.root = replacement
    hunt:StepPlayers(0, 20.4, {a})
    expect(hunt.targetRoot == replacement and hunt.chaseStartedAt ~= oldStart,
        "Replacement character must receive a fresh windup")
    a.root = root
    replacement:Destroy()

    countedHunt()
    hunt:StepPlayers(0, 20, {a, b})
    position(b, 2)
    expect(hunt:StepPlayers(0, 21.999, {a, b}) == nil, "Team selection must preserve capture windup")
    expect(hunt:StepPlayers(0, 22, {a, b}) == b, "Capture must identify the actual registered target")
    hunt:BeginCapture(secondRoot.CFrame.Position)
    before = hunt.root.CFrame
    expect(hunt:StepPlayers(0.1, 22.5, {a}) == nil and hunt.state == "capturing")
    expect(hunt:EndCapture() and hunt.state == "patrol" and hunt.root.CFrame == before,
        "EndCapture must release only this captor without teleporting")
    expect(hunt.firstChaseUsed and hunt.firstChaseUntil == nil and not hunt:EndCapture())
    expect(hunt:Stun(23, 10))
    local trappedAt = hunt.root.CFrame
    expect(not hunt:EndCapture() and hunt.stunnedUntil == 33, "EndCapture must preserve a trap")
    hunt:StepPlayers(0.1, 25, {})
    expect(hunt.state == "trapped" and hunt.root.CFrame == trappedAt and hunt.stunnedUntil == 33)
    hunt:StepPlayers(0.1, 33, {})
    expect(hunt.state == "patrol" and hunt.stunnedUntil == nil, "Empty candidate list must still advance trap expiry/patrol")

    countedHunt()
    position(a, 8)
    position(b, -8)
    hunt:StepPlayers(0, 20, {a, b})
    expect(hunt.targetUserId == -2, "Equal distance selection must use stable user ID tie break")
    countedHunt()
    position(a, 8)
    position(b, -8)
    hunt:StepPlayers(0, 20, {b, a})
    expect(hunt.targetUserId == -2, "Candidate iteration order must not change ties")
    countedHunt()
    a.protected, b.protected = true, true
    before = hunt.root.CFrame.Position
    hunt:StepPlayers(0.1, 20, {a, b})
    expect(count == 1 and hunt.state == "patrol" and hunt.targetRoot == nil)
    expect((hunt.root.CFrame.Position - before).Magnitude > 0, "Protected players must not freeze patrol")
    countedHunt()
    local zero = {userId = 0, root = root, protected = false}
    local nan = {userId = 0/0, root = root, protected = false}
    hunt:StepPlayers(0.1, 20, {zero, nan, {userId = -1, root = scene, protected = false}})
    expect(hunt.state == "patrol" and hunt.targetUserId == 0 and count == 1)
    for _, id in {-1, -2, 11644801627, 0, 1.5, math.huge, -math.huge, 0/0} do
        hunt:Destroy()
        hunt = Hunt.new(world, Balance, 0, id)
        expect(hunt.targetUserId == (if id == -1 or id == -2 or id == 11644801627 then id else 0))
    end
end)
if hunt then hunt:Destroy() end
scene:Destroy()
expect(ok, tostring(problem))
print("PASS multiplayer-hunt: single-step selection, negative IDs, target speed/retention/LOS loss, departure/path cancellation, replacement windup, actual victim, capture release/trap preservation, no-target patrol, stable ties")
]=]
local fn = assert(loadstring(setup .. cases, "multiplayer-hunt"))
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
			error("Unexpected setup module: " .. path)
		end,
	}, { __index = getfenv() })
)
fn()
