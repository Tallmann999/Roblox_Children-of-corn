-- Production RoundAudio with deterministic Instances/time/ground ray adapters.
-- Metadata-only sources do not prove real decoding or audible output.
local fs = require("@lune/fs")
local setup = assert(fs.readFile("tests/round-audio.luau"):match("^(.-)for id = 10, 1, %-1 do"))
local cases = [=[
-- Binary-exact polls avoid decimal rounding at the server's 0.1-second throttle.
local baseStep = step
function step(audio, tick, ...)
	baseStep(audio, tick * 0.125, ...)
end
local attributeWrites = { AudioCornActive = 0, AudioCornSpeed = 0 }
local baseAttribute = methods.SetAttribute
function methods:SetAttribute(key, value)
	if attributeWrites[key] then attributeWrites[key] += 1 end
	baseAttribute(self, key, value)
end
local owner = { UserId = 20 }
local humanoid, root = character(owner)
humanoid.WalkSpeed = 12
table.insert(players, owner)
fixtureId = realAssets.Get("COC_Corn_Continuous_02").Id
local audio = Audio.new(world, owner, nil, rand)
step(audio, 0, "active", "hard", nil)
local actor = assert(audio.actors[owner])
local sound = actor.sound
local expectedId = realAssets.Get("COC_Corn_Continuous_02").Id
assert(sound.SoundId == expectedId and sound.Volume == 0 and sound.Looped == true,
	"Server corn source must bind only the author loop as silent metadata")
assert(sound:GetAttribute("AudioCornActive") == false and sound:GetAttribute("AudioCornSpeed") == 1,
	"Initial spawn must publish inactive/default speed")
local atSpawn = table.clone(attributeWrites)
step(audio, 1, "active", "hard", nil)
assert(attributeWrites.AudioCornActive == atSpawn.AudioCornActive
	and attributeWrites.AudioCornSpeed == atSpawn.AudioCornSpeed,
	"Settled false/speed state must not rewrite attrs every poll")
local function move(tick, phase)
	root.Position += roblox.Vector3.new(0.6, 0, 0)
	step(audio, tick, phase or "active", "hard", nil)
	return sound:GetAttribute("AudioCornActive")
end
assert(move(2) and sound:GetAttribute("AudioCornSpeed") == 1,
	"Grounded real movement in corn must activate walk loop")
local movingWrites = table.clone(attributeWrites)
assert(move(3))
assert(attributeWrites.AudioCornActive == movingWrites.AudioCornActive
	and attributeWrites.AudioCornSpeed == movingWrites.AudioCornSpeed,
	"Unchanged motion must have zero metadata writes")
humanoid.WalkSpeed = 18
assert(move(4) and sound:GetAttribute("AudioCornSpeed") == 1.5, "Sprint18 must map to loop speed1.5")
humanoid.WalkSpeed = 24
assert(move(5) and sound:GetAttribute("AudioCornSpeed") == 2, "Energy24 must map to loop speed2")
humanoid.WalkSpeed = 200
assert(move(6) and sound:GetAttribute("AudioCornSpeed") == 2, "Server speed must clamp above2")
humanoid.WalkSpeed = 1
assert(move(7) and sound:GetAttribute("AudioCornSpeed") == 1, "Server speed must clamp below1")
step(audio, 8, "active", "hard", nil)
assert(not sound:GetAttribute("AudioCornActive"), "Actual stop must pause source metadata")
local stoppedWrites = table.clone(attributeWrites)
step(audio, 9, "active", "hard", nil)
assert(attributeWrites.AudioCornActive == stoppedWrites.AudioCornActive
	and attributeWrites.AudioCornSpeed == stoppedWrites.AudioCornSpeed,
	"Settled pause must not rewrite metadata")
assert(move(10))
humanoid.FloorMaterial = roblox.Enum.Material.Air
assert(not move(11), "Jump cannot activate corn movement")
humanoid.FloorMaterial = roblox.Enum.Material.Grass
assert(move(12))
groundHit = false
assert(not move(13), "Missing ground ray must pause")
groundHit = true
assert(move(14))
assert(not move(15, "caught"), "Caught owner must pause")
assert(move(16), "Revival must resume eligible movement")
root.Position += roblox.Vector3.new(20, 0, 0)
step(audio, 17, "active", "hard", nil)
assert(not sound:GetAttribute("AudioCornActive"), "Teleport must not sound as corn motion")
assert(move(18))
local zone = child("Part", "RoadClearance", child("Folder", "NoCornZones", world.Root))
zone.Size, zone.Position = roblox.Vector3.new(12, 10, 240), roblox.Vector3.new(0, 5, 0)
audio.exclusions = layout.ReadExclusions(world.Root, world.Field)
root.Position = roblox.Vector3.new(-1.2, 3, 20)
step(audio, 19, "active", "hard", nil)
assert(not move(20), "Actual CornLayout road exclusion must pause")
root.Position = roblox.Vector3.new(120, 3, 20)
step(audio, 21, "active", "hard", nil)
assert(not move(22), "Outside field motion must pause")
assert(sound.SoundId == expectedId and sound.Volume == 0 and sound.PlayCount == 0 and sound.StopCount == 0,
	"Movement/stops/phase transitions must never play, stop or replace server metadata clip")

-- Three genuine RoundAudio NPC bindings use each rig's measured horizontal motion.
local hunts, roots = {}, {}
for index = 1, 3 do
	local npcRoot = child("Part", "MonsterRoot" .. index, world.Runtime)
	npcRoot.Position = roblox.Vector3.new(-80, 3, 30 + index * 5)
	roots[index] = npcRoot
	hunts[index] = { root = npcRoot, state = "patrol", destroyed = false, home = npcRoot.Position }
end
step(audio, 23, "active", "hard", hunts[1], hunts)
for index = 1, 3 do roots[index].Position += roblox.Vector3.new(1.25, 0, 0) end
step(audio, 24, "active", "hard", hunts[1], hunts)
for index = 1, 3 do
	local npcSound = assert(audio.npcActors[roots[index]]).sound
	assert(npcSound:GetAttribute("AudioCornActive") == true and npcSound:GetAttribute("AudioCornSpeed") == 1,
		"Each moving patrol NPC must publish its own activity/speed")
	assert(npcSound.SoundId == expectedId and npcSound.Volume == 0 and npcSound.PlayCount == 0
		and npcSound.StopCount == 0, "NPC metadata source must stay silent and stable")
end
roots[1].Position += roblox.Vector3.new(1.625, 0, 0) --13 studs/sec
roots[2].Position += roblox.Vector3.new(2.5, 0, 0) --20 studs/sec
hunts[3].state = "trapped"
roots[3].Position += roblox.Vector3.new(1.25, 0, 0)
step(audio, 25, "active", "hard", hunts[1], hunts)
assert(audio.npcActors[roots[1]].sound:GetAttribute("AudioCornSpeed") == 1.3,
	"NPC measured13 speed must quantize to1.3")
assert(audio.npcActors[roots[2]].sound:GetAttribute("AudioCornSpeed") == 2,
	"NPC measured20 speed must clamp to2")
assert(not audio.npcActors[roots[3]].sound:GetAttribute("AudioCornActive"),
	"Trapped NPC must pause independently of other moving rigs")
step(audio, 26, "caught", "hard", hunts[1], hunts)
for index = 1, 3 do
	local npcSound = audio.npcActors[roots[index]].sound
	assert(npcSound:GetAttribute("AudioCornActive") == false and npcSound.PlayCount == 0
		and npcSound.StopCount == 0, "Capture must pause all NPC metadata without Sound operations")
end
local primary = hunts[1]
primary.balance = { monster_patrol_speed = 10 }
primary.state = "patrol"
roots[1].Position += roblox.Vector3.new(1.8, 0, 0) -- noisy measured14.4
step(audio, 27, "active", "hard", primary, hunts)
local primarySound = audio.npcActors[roots[1]].sound
assert(primarySound:GetAttribute("AudioCornActive") and primarySound:GetAttribute("AudioCornSpeed") == 1,
	"Authoritative patrol balance10 must override noisy measured motion")
local getterCalls = 0
function primary:_chaseSpeed(playerRoot, now)
	assert(playerRoot == root and now >= 3.5, "Stable chase getter must receive actual owner Root/server time")
	getterCalls += 1
	return 13
end
primary.state = "chase"
roots[1].Position += roblox.Vector3.new(0.6, 0, 0) -- measured4.8, getter13
step(audio, 28, "active", "hard", primary, hunts)
assert(primarySound:GetAttribute("AudioCornSpeed") == 1.3 and getterCalls == 1,
	"Stable chase getter13 must win over motion noise")
roots[1].Position += roblox.Vector3.new(1.9, 0, 0) -- measured15.2, same getter13
step(audio, 29, "active", "hard", primary, hunts)
assert(primarySound:GetAttribute("AudioCornSpeed") == 1.3 and getterCalls == 2,
	"Repeated noisy chase polls must retain the authoritative1.3 speed")
assert(primarySound.PlayCount == 0 and primarySound.StopCount == 0 and primarySound.SoundId == expectedId,
	"Stable speed resolution must not play/stop/replace metadata Sound")
audio:Destroy()
assert(sound.Destroyed and next(audio.actors) == nil and next(audio.npcActors) == nil)
print("PASS continuous corn server adapter: only silent loop metadata; initial/change-only active+speed; walk12/sprint18/energy24 clamps; physical movement/ground/corn/stop/air/road/teleport/caught validation; all3NPC independent measured/quantized speed and trapped/capture pause; stable patrol10/chase getter13 override poll noise; no server Play/Stop/URI changes before cleanup. No audible claim.")
]=]
assert(loadstring(setup .. cases, "rustle-continuous-server-focused"))()
