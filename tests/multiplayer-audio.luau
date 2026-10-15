-- Production RoundAudio with the current deterministic sound/character adapters.
-- Verifies server metadata authority and lifecycle, not engine/audible playback.
local fs = require("@lune/fs")
local setup = assert(fs.readFile("tests/round-audio.luau"):match("^(.-)for id = 10, 1, %-1 do"))
local cases = [=[
local owner, peer, waiting = {UserId = 20}, {UserId = -2}, {UserId = -1}
local ownerHumanoid, ownerRoot = character(owner)
local peerHumanoid, peerRoot = character(peer)
local waitingHumanoid = character(waiting)
waitingHumanoid.WalkSpeed = 12
table.insert(players, owner)
table.insert(players, peer)
table.insert(players, waiting)
ownerHumanoid.WalkSpeed, peerHumanoid.WalkSpeed = 12, 24
local activity = {[owner] = true, [peer] = true}
local function eligible(player) return activity[player] == true end
fixtureId = realAssets.Get("COC_Corn_Continuous_02").Id
local npcRoot = child("Part", "MonsterRoot", world.Runtime)
npcRoot.Position = roblox.Vector3.new(-80, 3, 40)
local hunt = {
    root = npcRoot, targetRoot = peerRoot, state = "chase", destroyed = false,
    balance = {monster_patrol_speed = 10},
    _chaseSpeed = function(_, target)
        assert(target == peerRoot, "NPC audio used owner rather than its actual target")
        return target.Parent:FindFirstChildOfClass("Humanoid").WalkSpeed
    end,
}
local audio = Audio.new(world, owner, hunt, rand)
local tick = 0
local function poll(phase)
    advance(tick)
    audio:Step(tick, phase or "active", "hard", hunt, {hunt}, eligible)
    tick += 0.125
end
local function move()
    ownerRoot.Position += roblox.Vector3.new(0.6, 0, 0)
    peerRoot.Position += roblox.Vector3.new(0.6, 0, 0)
    npcRoot.Position += roblox.Vector3.new(0.6, 0, 0)
end
poll()
local ownSound, peerSound, waitingSound = audio.actors[owner].sound, audio.actors[peer].sound, audio.actors[waiting].sound
move()
poll()
assert(ownSound:GetAttribute("AudioCornActive") and peerSound:GetAttribute("AudioCornActive"))
assert(not waitingSound:GetAttribute("AudioCornActive"), "Waiting player must remain ineligible")
assert(audio.npc.sound:GetAttribute("AudioCornSpeed") == 2, "NPC pitch must follow selected target speed24")
peerHumanoid.WalkSpeed = 18
move()
poll()
assert(audio.npc.sound:GetAttribute("AudioCornSpeed") == 1.8, "Target sprint18 must provide stable NPC pitch1.8")
activity[owner] = false
move()
poll("caught")
assert(not ownSound:GetAttribute("AudioCornActive") and peerSound:GetAttribute("AudioCornActive"),
    "Caught owner must not pause active teammate")
assert(audio.actors[owner].sound == ownSound and audio.actors[peer].sound == peerSound,
    "Personal phase changes must retain spatial loop cursor bindings")
activity[owner], activity[peer] = true, false
move()
poll()
assert(ownSound:GetAttribute("AudioCornActive") and not peerSound:GetAttribute("AudioCornActive"),
    "Eligibility must also gate non-owner actors")
activity[peer] = true
peerHumanoid.Health = 0
move()
poll()
assert(not audio.actors[peer] and peerSound.Destroyed, "Dead actor source must be cleaned up")
peerHumanoid, peerRoot = character(peer)
peerHumanoid.WalkSpeed = 12
hunt.targetRoot = peerRoot
move()
poll()
assert(audio.actors[peer] and audio.actors[peer].sound ~= peerSound)
peerSound = audio.actors[peer].sound
assert(not peerSound:GetAttribute("AudioCornActive"), "Replacement Root starts a fresh movement sample")
move()
poll()
assert(peerSound:GetAttribute("AudioCornActive"))
for _, actor in audio.actors do
    assert(actor.sound.Volume == 0 and actor.sound.PlayCount == 0 and actor.sound.StopCount == 0,
        "Multiplayer corn source must remain silent metadata")
end
assert(audio.npc.sound.Volume == 0 and audio.npc.sound.PlayCount == 0)
local sources = {ownSound, peerSound, waitingSound, audio.npc.sound}
audio:Destroy()
for _, source in sources do assert(source.Destroyed) end
assert(next(audio.actors) == nil and next(audio.npcActors) == nil)

-- Absence of the new callback preserves the established owner-only caught gate.
local legacy = Audio.new(world, owner, nil, rand)
step(legacy, 2, "caught", "hard", nil)
ownerRoot.Position += roblox.Vector3.new(0.6, 0, 0)
peerRoot.Position += roblox.Vector3.new(0.6, 0, 0)
step(legacy, 2.125, "caught", "hard", nil)
assert(not legacy.actors[owner].sound:GetAttribute("AudioCornActive"))
assert(legacy.actors[peer].sound:GetAttribute("AudioCornActive"), "Optional callback must preserve legacy default")
legacy:Destroy()
print("PASS multiplayer-audio: per-player eligibility, caught-owner isolation, waiting/dead/root replacement, retained loop bindings, actual NPC target speed, silent sources, cleanup, legacy default")
]=]
local fn = assert(loadstring(setup .. cases, "multiplayer-audio"))
setfenv(fn, getfenv())
fn()
