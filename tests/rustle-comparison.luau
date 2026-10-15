-- HISTORICAL A/B acceptance; superseded by tests/rustle-continuous.luau.
-- Production AudioController with deterministic Sound/Heartbeat adapters.
-- The test substitutes a fake asset ID locally; it establishes no real decode/audio result.
local fs = require("@lune/fs")
local setup =
	assert(fs.readFile("tests/audio-controller.luau"):match("^(.-)gameplayWrites, scans = 0, 0"))
setup = setup:gsub(
	'assert%(#ids == 15, "Preload did not cover all 15 unique valid clips"%)',
	'assert(#ids == 15 or #ids == 16, "Expected original clips plus optional comparison clip")'
)
setup = setup:gsub("local module = load%(", function()
	return [=[
-- Explicit adapter-only identity, never installed in Studio.
assetList.COC_Corn_Continuous_02 = { Id = "rbxassetid://991234567", Gain = 1, Duration = 11.064 }
for index, key in Rules.CornKeys do
	assetList[key] = assetList["SpatialClip" .. index]
	assetList["SpatialClip" .. index] = nil
end
function methods:GetChildren() return table.clone(self._children) end
function methods:Pause()
	assert(self._class == "Sound")
	self.pauses = (self.pauses or 0) + 1
	self.IsPlaying, self.IsPaused = false, true
end
function methods:Resume()
	assert(self._class == "Sound")
	self.resumes = (self.resumes or 0) + 1
	self.IsPlaying, self.IsPaused = true, false
end
local originalPlay = methods.Play
function methods:Play()
	originalPlay(self)
	self.IsPaused = false
end
local originalSetAttribute = methods.SetAttribute
function methods:GetAttributeChangedSignal(key)
	self._attributeSignals = self._attributeSignals or {}
	self._attributeSignals[key] = self._attributeSignals[key] or signal()
	return self._attributeSignals[key]
end
function methods:SetAttribute(key, value)
	local previous = self:GetAttribute(key)
	originalSetAttribute(self, key, value)
	if previous ~= value and self._attributeSignals and self._attributeSignals[key] then
		self._attributeSignals[key]:Fire()
	end
end
local module = load(]=]
end)
local cases = [=[
gameplayWrites, scans = 0, 0
local movement = { selected = nil, available = nil, callback = nil, cursor = true }
function movement:BindRustleComparison(callback) self.callback = callback end
function movement:SetRustleComparison(selected, available)
	self.selected, self.available = selected, available
end
function movement:IsCursorOpen() return self.cursor end
context.Controllers.MovementController = movement
local function source(at, seq, key)
	local sound = make("Sound")
	sound.Name, sound.SoundId, sound.Volume = "CornAudio_corn_rustle", assetList[key].Id, 0.38
	sound:SetAttribute("CornAudioOwned", true)
	sound:SetAttribute("corn_project_id", "children_of_corn")
	sound:SetAttribute("audio_role", "corn_rustle")
	sound:SetAttribute("AudioRustleId", seq)
	sound:SetAttribute("AudioRustleStart", tostring(seq) .. ":" .. key)
	sound:SetAttribute("AudioRequestedPlaying", false)
	sound:SetAttribute("AudioCornActive", false)
	sound.Parent = at
	return sound
end
local function commit(sound, seq, key)
	sound:SetAttribute("AudioRustleId", seq)
	sound:SetAttribute("AudioRustleStart", tostring(seq) .. ":" .. key)
end
local function activity(object, sourceSound, value)
	sourceSound:SetAttribute("AudioCornActive", value)
	advance(object, 0)
end
local function current(object, round, phase, sprinting)
	local value = snapshot(round, 0, "none", phase)
	value.is_sprinting = sprinting == true
	object:SetSnapshot(value)
end
local function naturalEnd(voice)
	voice.sound._values.IsPlaying = false
	voice.sound.Ended:Fire()
end
createdSoundsLoaded = true
local ownSource = source(root, 1, "COC_Corn_13")
local npcSource = source(enemy, 1, "COC_Corn_11")
local object = new()
current(object, 1, "active", false)
local loop = assert(object._sounds.CornLoop, "Configured comparison asset did not create one loop")
local sound = loop.sound
assert(sound.Parent == object._folder and sound.SoundGroup == object._groups.Effects
	and sound.Looped == true, "Comparison clip must use existing personal Effects folder")
assert(object._rustleMode == 1 and sound.plays == 0 and movement.available == true,
	"Session must start in original mode with available comparison control")
for _, invalid in { 0, 3, "2", false, {} } do
	assert(object:SetRustleMode(invalid) == false and object._rustleMode == 1, "Invalid mode accepted")
end
commit(ownSource, 2, "COC_Corn_13")
commit(ownSource, 3, "COC_Corn_11")
commit(ownSource, 4, "COC_Corn_02")
local own = assert(object._rustles[root])
assert(own.voices[1].active and own.voices[2].active and own.pending.id == 4,
	"Precondition: original two started tails plus newest pending")
assert(object:SetRustleMode(2) == true and object._rustleMode == 2 and own.pending == nil,
	"Comparison mode must discard own pending without stopping started tails")
for _, voice in own.voices do
	assert(voice.active and voice.sound.IsPlaying and voice.sound.stops == 0,
		"Switching cut a started original tail")
end
assert(sound.plays == 0, "Mode switch alone cannot fake server movement")
commit(ownSource, 5, "COC_Corn_18")
commit(ownSource, 6, "COC_Corn_20")
assert(own.lastId == 6 and own.pending == nil, "Mode 2 must consume own new ids without queue/history")
commit(npcSource, 2, "COC_Corn_02")
local npc = assert(object._rustles[enemy])
assert(npc.voices[1].sound.plays == 1 and npc.voices[1].active,
	"Comparison choice must retain NPC short cues")
activity(object, ownSource, true)
assert(sound.plays == 1 and sound.IsPlaying and sound.PlaybackSpeed == 1,
	"First actual in-corn movement must Play the loop at walk speed")
sound.TimePosition = 11
activity(object, ownSource, false)
assert(not sound.IsPlaying and sound.TimePosition == 11 and sound.stops == 0 and sound.pauses == 1,
	"Stop at second 11 must Pause without resetting the session cursor")
advance(object, 2)
assert(sound.TimePosition == 11 and sound.pauses == 1 and sound.plays == 1,
	"Settled pause must not repeatedly pause/restart or advance the cursor")
activity(object, ownSource, true)
assert(sound.IsPlaying and sound.TimePosition == 11 and sound.plays == 1 and sound.resumes == 1,
	"Next movement must Resume from second 11")
current(object, 1, "active", true)
assert(sound.PlaybackSpeed == Rules.CornLoopSprintSpeed and sound.PlaybackSpeed == 1.5,
	"Server sprint snapshot must accelerate the loop to 1.5")
current(object, 1, "active", false)
assert(sound.PlaybackSpeed == Rules.CornLoopSpeed and sound.PlaybackSpeed == 1,
	"Returning to walk must restore playback speed 1")
-- Simulate Roblox's Looped wrap, then verify the controller leaves it running.
sound.TimePosition = (sound.TimePosition + 0.2 * sound.PlaybackSpeed) % assetList.COC_Corn_Continuous_02.Duration
local wrapped = sound.TimePosition
advance(object, 0.2)
assert(sound.Looped and sound.IsPlaying and sound.plays == 1 and sound.resumes == 1
	and sound.TimePosition == wrapped and wrapped < 0.2,
	"Natural loop wrap must not be implemented as a repeated Play/seek")
local position = sound.TimePosition
gui.MenuIsOpen = true
gui.MenuOpened:Fire()
assert(not sound.IsPlaying and sound.TimePosition == position and sound.stops == 0,
	"Roblox menu must pause without cursor reset")
gui.MenuIsOpen = false
advance(object, 0.1)
assert(sound.IsPlaying and sound.plays == 1 and sound.resumes == 2)
capture._state.active = true
advance(object, 0.1)
assert(not sound.IsPlaying and sound.TimePosition == position and sound.stops == 0,
	"Capture film must pause the loop")
capture._state.active = false
advance(object, 0.1)
assert(sound.IsPlaying and sound.plays == 1 and sound.resumes == 3)
current(object, 1, "caught", false)
assert(not sound.IsPlaying and sound.TimePosition == position and sound.stops == 0)
current(object, 1, "active", false)
assert(sound.IsPlaying and sound.plays == 1 and sound.resumes == 4)
assert(object:SetRustleMode(1) and not sound.IsPlaying and sound.TimePosition == position and sound.stops == 0)
naturalEnd(own.voices[1]); naturalEnd(own.voices[2])
advance(object, 0.1)
assert(own.voices[1].sound.plays == 1 and own.voices[2].sound.plays == 1 and own.pending == nil,
	"Returning to mode 1 must not replay ids skipped in mode 2")
commit(ownSource, 7, "COC_Corn_13")
assert(own.voices[1].sound.plays == 2 and own.voices[1].current.id == 7,
	"A fresh cue after returning to mode 1 must play normally")
assert(object:SetRustleMode(2))
advance(object, 0.1)
local playsBefore = sound.plays
current(object, 1, "escaped", false)
assert(not sound.IsPlaying and sound.TimePosition == position and sound.stops == 0,
	"Terminal phase must preserve comparison cursor")
current(object, 2, "active", false)
assert(sound.plays == playsBefore and sound.TimePosition == position,
	"Retry must retain this session's single loop instance and cursor")
activity(object, ownSource, true)
assert(sound.IsPlaying and sound.plays == playsBefore, "Retry must resume, not replay from zero")
player.Character = nil
advance(object, 0.1)
assert(not sound.IsPlaying and sound.TimePosition == position and sound.stops == 0,
	"Lost character/root must pause and preserve cursor")
player.Character = hero
advance(object, 0.3)
assert(sound.plays == playsBefore, "Root recovery must not create a new loop player")
local setupWrites = gameplayWrites
root.Name = "FormerRoot"
local replacement = make("Part")
replacement.Name, replacement.Parent = "HumanoidRootPart", hero
local replacementSource = source(replacement, 1, "COC_Corn_13")
gameplayWrites = setupWrites -- Authoring the replacement is fixture setup.
activity(object, replacementSource, false)
assert(not sound.IsPlaying and sound.TimePosition == position and sound.stops == 0,
	"An actual new Root with inactive source must pause the session loop")
activity(object, replacementSource, true)
assert(sound.IsPlaying and sound.plays == playsBefore and sound.TimePosition == position
	and object._sounds.CornLoop == loop and sound.Parent == object._folder,
	"New Root must resume the same personal Sound/cursor only after its own valid active source")
object:Destroy()
assert(sound.Destroyed, "Owned comparison Sound survived Destroy")
ownSource:Destroy(); npcSource:Destroy()
setupWrites = gameplayWrites
replacement:Destroy(); root.Name = "HumanoidRootPart"
gameplayWrites = setupWrites -- Fixture-only root cleanup.

-- Missing asset is a visible unavailable option, without losing original mode.
assetList.COC_Corn_Continuous_02.Id = ""
object = new()
current(object, 3, "active", false)
assert(not object._sounds.CornLoop and object._rustleMode == 1 and movement.available == false
	and object:SetRustleMode(2) == false, "Missing real ID must refuse mode 2 and retain mode 1")
object:Destroy()

-- Decode failure stays unavailable until this exact owned Sound later loads.
assetList.COC_Corn_Continuous_02.Id = "rbxassetid://991234567"
createdSoundsLoaded, preloadMode = false, "failure"
object = new()
current(object, 4, "active", false)
loop = assert(object._sounds.CornLoop)
sound = loop.sound
assert(loop.failed and movement.available == false and object:SetRustleMode(2) == false,
	"Failed unloaded decoder must refuse comparison selection")
sound._values.IsLoaded = true
advance(object, 0.1)
assert(not loop.failed and movement.available and object:SetRustleMode(2),
	"Late successful decode must heal this session's comparison option")
object:Destroy()

-- A foreign identity/loop/group change is never repaired or destroyed by audio cleanup.
createdSoundsLoaded, preloadMode = true, "success"
for _, property in { "SoundId", "Looped", "SoundGroup" } do
	object = new()
	current(object, 5, "active", false)
	loop = assert(object._sounds.CornLoop)
	sound = loop.sound
	local value = if property == "SoundId" then "rbxassetid://998888888"
		elseif property == "Looped" then false else make("SoundGroup")
	sound[property] = value
	sound.TimePosition, sound.Volume = 7, 0.17
	local priorStops, priorPauses = sound.stops, sound.pauses or 0
	advance(object, 0.1)
	assert(object:SetRustleMode(2) == false and object._rustleMode == 1
		and sound[property] == value and sound.TimePosition == 7 and sound.Volume == 0.17
		and sound.stops == priorStops and (sound.pauses or 0) == priorPauses,
		"Foreign comparison identity/loop/group was overwritten or paused")
	local preservedFolder = object._folder
	object:Destroy()
	assert(not sound.Destroyed and sound.Parent == preservedFolder and not preservedFolder.Destroyed
		and sound[property] == value and sound.TimePosition == 7 and sound.Volume == 0.17,
		"Destroy must preserve a foreign-modified loop and its container")
	-- Fixture cleanup after verifying production refusal, not controller behavior.
	preservedFolder:Destroy()
	if property == "SoundGroup" then value:Destroy() end
end
for _, connection in connections do assert(not connection.Connected, "Comparison lifecycle connection leaked") end
assert(gameplayWrites == 0, "Audio comparison wrote character/camera/gameplay state")
print("PASS comparison client adapter: configured/missing/failed/late-healed asset; mode validation; original tails retained; own history consumed/NPC preserved; one Play then Pause/Resume at 11; sprint1.5/walk1; Looped wrap; menu/capture/caught/terminal/retry/root pause cursor; original mode resumes only fresh cue; foreignURI/loop/group preserved through Destroy; cleanup/no gameplay writes. Asset ID is test-only, no audible claim.")
]=]
assert(loadstring(setup .. cases, "rustle-comparison-focused"))()
