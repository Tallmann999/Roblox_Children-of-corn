-- HISTORICAL A/B acceptance; superseded by tests/rustle-continuous-server.luau.
-- Actual RoundAudio source with deterministic Instances/clock/raycast adapters.
-- These checks establish state/cadence authority, not decoding or audibility.
local fs = require("@lune/fs")
local setup = assert(fs.readFile("tests/round-audio.luau"):match("^(.-)for id = 10, 1, %-1 do"))
local cases = [=[
-- Binary-exact 0.125-second polls avoid making a 10 Hz boundary assertion
-- depend on 0.3-0.2 floating-point rounding in RoundAudio's poll throttle.
local originalStep = step
function step(audio, now, ...)
	originalStep(audio, now * 1.25, ...)
end
local activeWrites = 0
local originalSetAttribute = methods.SetAttribute
function methods:SetAttribute(key, value)
	if key == "AudioCornActive" then activeWrites += 1 end
	originalSetAttribute(self, key, value)
end
local owner = { UserId = 20 }
local humanoid, root = character(owner)
table.insert(players, owner)
local audio = Audio.new(world, owner, nil, rand)
step(audio, 0, "active", "hard", nil)
local actor = assert(audio.actors[owner])
local sound = actor.sound
assert(sound:GetAttribute("AudioCornActive") == false, "Initial/spawn motion must be inactive")
local writesAtSpawn = activeWrites
step(audio, 0.1, "active", "hard", nil)
assert(activeWrites == writesAtSpawn, "Settled false state must not rewrite attribute every poll")
root.Position += roblox.Vector3.new(0.6, 0, 0)
step(audio, 0.2, "active", "hard", nil)
assert(sound:GetAttribute("AudioCornActive") == true and actor.rustleId == 1,
	"Grounded physical motion in corn must enable loop and commit original cue")
local writesAtStart, firstId = activeWrites, actor.rustleId
assert(actor.nextAt > 0.3, "Precondition: the next metadata cue must still be delayed")
root.Position += roblox.Vector3.new(0.6, 0, 0)
step(audio, 0.3, "active", "hard", nil)
assert(sound:GetAttribute("AudioCornActive") == true and actor.rustleId == firstId
	and activeWrites == writesAtStart,
	"Loop activity must be independent of cue nextAt and change-only during motion")
step(audio, 0.4, "active", "hard", nil)
assert(sound:GetAttribute("AudioCornActive") == false and actor.rustleId == firstId,
	"An actual stop must immediately clear activity even while prior server clip is busy")
local stoppedWrites = activeWrites
step(audio, 0.5, "active", "hard", nil)
assert(activeWrites == stoppedWrites, "Settled pause must have zero attribute writes")

local function move(at, phase)
	root.Position += roblox.Vector3.new(0.6, 0, 0)
	step(audio, at, phase or "active", "hard", nil)
	return sound:GetAttribute("AudioCornActive")
end
assert(move(0.6), "Resumed in-corn motion must reactivate")
humanoid.FloorMaterial = roblox.Enum.Material.Air
assert(not move(0.7), "Jump/air cannot claim grounded loop movement")
humanoid.FloorMaterial = roblox.Enum.Material.Grass
assert(move(0.8), "Landing plus valid motion must resume")
groundHit = false
assert(not move(0.9), "Ground ray miss cannot activate the loop")
groundHit = true
assert(move(1.0), "Ground ray recovery must resume")
assert(not move(1.1, "caught"), "Capture phase must clear activity")
assert(move(1.2), "Revival active phase must resume")
root.Position += roblox.Vector3.new(20, 0, 0)
step(audio, 1.3, "active", "hard", nil)
assert(not sound:GetAttribute("AudioCornActive"), "Teleport must not activate or retain loop")
assert(move(1.4), "Normal motion after a rejected teleport must recover")

-- This is the actual CornLayout exclusion reader, not an _inCorn stub.
local zone = child("Part", "RoadClearance", child("Folder", "NoCornZones", world.Root))
zone.Size, zone.Position = roblox.Vector3.new(12, 10, 240), roblox.Vector3.new(0, 5, 0)
audio.exclusions = layout.ReadExclusions(world.Root, world.Field)
root.Position = roblox.Vector3.new(-1.2, 3, 20)
step(audio, 1.5, "active", "hard", nil) -- reposition is deliberately a teleport
assert(not move(1.6), "Actual road exclusion must disable valid physical motion")
root.Position = roblox.Vector3.new(120, 3, 20)
step(audio, 1.7, "active", "hard", nil)
assert(not move(1.8), "Motion beyond the field cannot activate the loop")
root.Position = roblox.Vector3.new(-80, 3, 20)
step(audio, 1.9, "active", "hard", nil)
assert(move(2.0), "Returning to corn must recover after discontinuity")
humanoid.Health = 0
step(audio, 2.1, "active", "hard", nil)
assert(audio.actors[owner] == nil and sound.Destroyed,
	"Dead actor must release its source rather than leave a true live binding")
audio:Destroy()
print("PASS comparison server adapter: initial false; grounded actual motion; change-only writes; nextAt/busy independence; stop/air/raycast/caught/teleport/real road/outside field/death; recovery. No audible or Studio claim.")
]=]
assert(loadstring(setup .. cases, "rustle-comparison-server-focused"))()
