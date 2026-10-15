-- Production AudioController with deterministic Sound/Heartbeat/network adapters.
-- A local fake asset identity exercises lifecycle logic; this is not an audible result.
local fs = require("@lune/fs")
local setup =
	assert(fs.readFile("tests/audio-controller.luau"):match("^(.-)gameplayWrites, scans = 0, 0"))
setup = setup:gsub(
	'assert%(#ids == 15, "Preload did not cover all 15 unique valid clips"%)',
	'assert(#ids == 9 or #ids == 10, "Expected 9 active non-corn clips plus optional continuous loop")'
)
setup = setup:gsub("for _, asset in assetList do", "for key, asset in assetList do")
setup = setup:gsub(
	'assert%(seen%[asset.Id%], "Valid spatial clip omitted from client preload"%)',
	'if table.find(Rules.CornKeys, key) then assert(not seen[asset.Id], "Archived short corn clip was preloaded") else assert(seen[asset.Id], "Active clip omitted from preload") end'
)
setup = setup:gsub("local module = load%(", function()
	return [=[
-- Adapter-only identity: never installed or requested from Roblox.
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
local basePlay = methods.Play
function methods:Play()
	basePlay(self)
	self.IsPaused = false
end
local baseAttribute = methods.SetAttribute
function methods:GetAttributeChangedSignal(key)
	self._attributeSignals = self._attributeSignals or {}
	self._attributeSignals[key] = self._attributeSignals[key] or signal()
	return self._attributeSignals[key]
end
function methods:SetAttribute(key, value)
	local previous = self:GetAttribute(key)
	baseAttribute(self, key, value)
	if previous ~= value and self._attributeSignals and self._attributeSignals[key] then
		self._attributeSignals[key]:Fire()
	end
end
local module = load(]=]
end)
local cases = [=[
gameplayWrites, scans = 0, 0
local LOOP = "COC_Corn_Continuous_02"
local function source(at, active, speed)
	local sound = make("Sound")
	sound.Name, sound.SoundId, sound.Volume = "CornAudio_corn_rustle", assetList[LOOP].Id, 0
	sound.Looped = true
	sound:SetAttribute("CornAudioOwned", true)
	sound:SetAttribute("corn_project_id", "children_of_corn")
	sound:SetAttribute("AudioVersion", 1)
	sound:SetAttribute("audio_role", "corn_rustle")
	sound:SetAttribute("AudioAssetKey", LOOP)
	sound:SetAttribute("AudioCornActive", active == true)
	sound:SetAttribute("AudioCornSpeed", speed or 1)
	sound.Parent = at
	return sound
end
local function activity(object, sourceSound, active, speed)
	sourceSound:SetAttribute("AudioCornActive", active == true)
	if speed then sourceSound:SetAttribute("AudioCornSpeed", speed) end
	advance(object, 0)
end
local function current(object, round, phase, sprinting)
	local value = snapshot(round, 0, "none", phase)
	value.is_sprinting = sprinting == true
	object:SetSnapshot(value)
end
local function spatial(at)
	local result = {}
	for _, child in at:GetChildren() do
		if child:IsA("Sound") and child:GetAttribute("audio_role") == "corn_loop_local" then
			table.insert(result, child)
		end
	end
	assert(#result == 1, "Each other actor must own exactly one spatial loop")
	return result[1]
end
local function assertSpatial(sound, at)
	assert(sound.Parent == at and sound.Looped == true and sound.SoundId == assetList[LOOP].Id,
		"Spatial loop identity/parent/looped URI diverged")
	assert(sound.RollOffMinDistance == Rules.Ranges.Rustle.Min
		and sound.RollOffMaxDistance == Rules.Ranges.Rustle.Max,
		"Spatial loop must retain near/far rolloff")
end
createdSoundsLoaded = true
local ownSource, primarySource = source(root, false), source(enemy, false)
local object = new()
current(object, 1, "active")
assert(object.SetRustleMode == nil and object._rustleMode == nil,
	"Continuous production must remove the old A/B selector API/state")
local loop = assert(object._sounds.CornLoop)
local sound = loop.sound
assert(sound.Parent == object._folder and sound.SoundGroup == object._groups.Effects
	and sound.Looped == true and sound.SoundId == assetList[LOOP].Id,
	"Owner uses exactly one persistent personal Effects loop")
for _, child in root:GetChildren() do
	assert(child:GetAttribute("audio_role") ~= "corn_loop_local", "Owner must not duplicate its personal loop spatially")
end
local primaryLoop = spatial(enemy)
assertSpatial(primaryLoop, enemy)
assert(sound.plays == 0 and primaryLoop.plays == 0, "Inactive metadata cannot start loops")
activity(object, ownSource, true, 1)
assert(sound.plays == 1 and sound.IsPlaying and sound.PlaybackSpeed == 1,
	"Owner's first eligible motion must automatically Play sound 2")
sound.TimePosition = 11
activity(object, ownSource, false)
assert(not sound.IsPlaying and sound.TimePosition == 11 and sound.stops == 0 and sound.pauses == 1,
	"Owner stop at second11 must Pause without rewind")
advance(object, 2)
assert(sound.TimePosition == 11 and sound.pauses == 1 and sound.plays == 1,
	"Settled pause must not replay or move session cursor")
current(object, 1, "active", true)
activity(object, ownSource, true, 1.5)
assert(sound.IsPlaying and sound.TimePosition == 11 and sound.plays == 1 and sound.resumes == 1
	and sound.PlaybackSpeed == 1.5, "Owner sprint must Resume same cursor at server speed1.5")
activity(object, ownSource, true, 2)
assert(sound.PlaybackSpeed == 1.5 and sound.plays == 1 and sound.resumes == 1,
	"Repeated active metadata must not replay the owner's sprint loop")
current(object, 1, "active", false)
activity(object, ownSource, true, 1)
assert(sound.PlaybackSpeed == 1)
sound.TimePosition = (sound.TimePosition + 0.2) % assetList[LOOP].Duration
local position = sound.TimePosition
advance(object, 0.2)
assert(position < 0.2 and sound.TimePosition == position and sound.IsPlaying
	and sound.plays == 1 and sound.resumes == 1,
	"Engine Looped wrap must remain natural, without manual Play/seek")
activity(object, primarySource, true, 1.3)
assert(primaryLoop.plays == 1 and primaryLoop.IsPlaying and primaryLoop.PlaybackSpeed == 1.3,
	"Primary NPC must independently use the continuous spatial clip")
primaryLoop.TimePosition = 4.25
activity(object, primarySource, false)
assert(not primaryLoop.IsPlaying and primaryLoop.TimePosition == 4.25 and primaryLoop.stops == 0,
	"NPC stop must Pause its own cursor")
activity(object, primarySource, true, 2)
assert(primaryLoop.plays == 1 and primaryLoop.resumes == 1 and primaryLoop.TimePosition == 4.25
	and primaryLoop.PlaybackSpeed == 2, "NPC must Resume the same clip/cursor at current speed")

-- Fixed 3-NPC registry plus seven other players: ten spatial loops, one personal loop.
local testRoots, sourceSounds = {}, { ownSource, primarySource }
local testModels = {}
for index = 2, 4 do
	local model, npcRoot = make("Model"), make("Part")
	model.Name, model.Parent = "Monster" .. index, runtime
	for key, value in { CornMonsterOwned = true, corn_project_id = "children_of_corn",
		MonsterRigVersion = 1, MonsterIndex = index, HuntState = "patrol" } do model:SetAttribute(key, value) end
	npcRoot.Name, npcRoot.Parent = "Root", model
	testModels[index], testRoots[index] = model, npcRoot
	table.insert(sourceSounds, source(npcRoot, true, 1 + index * 0.1))
end
local otherRoots = {}
for index = 1, 7 do
	local other = { UserId = 20 + index, CharacterAdded = signal(), CharacterRemoving = signal() }
	local character, otherHumanoid, otherRoot = make("Model"), make("Humanoid"), make("Part")
	otherHumanoid.Parent, otherRoot.Parent = character, character
	otherRoot.Name, other.Character = "HumanoidRootPart", character
	otherRoots[index] = otherRoot
	table.insert(sourceSounds, source(otherRoot, true, 1.5))
	services.Players.PlayerAdded:Fire(other)
end
gameplayWrites = 0 -- Fixture-only actor authoring above is not controller behavior.
advance(object, 0.3)
local allSpatial = { primaryLoop, spatial(testRoots[2]), spatial(testRoots[3]) }
for _, otherRoot in otherRoots do table.insert(allSpatial, spatial(otherRoot)) end
assert(#allSpatial == 10, "Eight admitted players plus3NPC need ten spatial loops plus owner's personal one")
for _, spatialSound in allSpatial do
	assertSpatial(spatialSound, spatialSound.Parent)
	assert(spatialSound.IsPlaying and spatialSound.plays == 1 and spatialSound.stops == 0,
		"Every admitted moving actor must use one continuous loop")
end
for _, child in testRoots[4]:GetChildren() do
	assert(child:GetAttribute("audio_role") ~= "corn_loop_local", "Fourth NPC must be refused")
end
gui.MenuIsOpen = true
gui.MenuOpened:Fire()
assert(not sound.IsPlaying and sound.TimePosition == position and sound.stops == 0,
	"Menu must preserve owner's loop cursor")
gui.MenuIsOpen = false
advance(object, 0.1)
assert(sound.IsPlaying and sound.plays == 1)
capture._state.active = true
advance(object, 0.1)
assert(not sound.IsPlaying and sound.TimePosition == position and sound.stops == 0)
capture._state.active = false
advance(object, 0.1)
current(object, 1, "caught")
assert(not sound.IsPlaying and sound.TimePosition == position and sound.stops == 0)
current(object, 1, "active")
assert(sound.IsPlaying and sound.plays == 1)
current(object, 1, "escaped")
assert(not sound.IsPlaying and sound.TimePosition == position and sound.stops == 0)
for _, spatialSound in allSpatial do assert(spatialSound.Destroyed, "Terminal must release spatial actor copies") end
current(object, 2, "active")
assert(object._sounds.CornLoop.sound == sound and sound.plays == 1 and sound.TimePosition == position,
	"Retry must retain owner's session loop and cursor")
local beforeReplacement = gameplayWrites
root.Name = "FormerRoot"
local replacement = make("Part")
replacement.Name, replacement.Parent = "HumanoidRootPart", hero
local replacementSource = source(replacement, false)
gameplayWrites = beforeReplacement
activity(object, replacementSource, false)
assert(not sound.IsPlaying and sound.TimePosition == position and sound.stops == 0,
	"Actual new Root must pause until its own metadata becomes active")
activity(object, replacementSource, true, 1)
assert(sound.IsPlaying and sound.plays == 1 and sound.TimePosition == position,
	"Actual new Root must Resume the same personal loop")
object:Destroy()
assert(sound.Destroyed and object._rustleCount == 0)
beforeReplacement = gameplayWrites
replacement:Destroy(); root.Name = "HumanoidRootPart"
for _, sourceSound in sourceSounds do sourceSound:Destroy() end
for _, model in testModels do model:Destroy() end
for _, otherRoot in otherRoots do otherRoot.Parent:Destroy() end
gameplayWrites = beforeReplacement

-- Missing/failed author clip does not silently revive the removed short alternatives.
assetList[LOOP].Id = ""
object = new(); current(object, 3, "active")
assert(not object._sounds.CornLoop, "Missing author clip must not create an invalid loop")
object:Destroy()
assetList[LOOP].Id = "rbxassetid://991234567"
createdSoundsLoaded, preloadMode = false, "failure"
object = new(); current(object, 4, "active")
loop = assert(object._sounds.CornLoop)
assert(loop.failed, "Unloaded preload failure must be recognized")
loop.sound._values.IsLoaded = true
advance(object, 0.1)
assert(not loop.failed, "A late decoder must recover the current loop without historical cues")
object:Destroy()
createdSoundsLoaded, preloadMode = true, "success"
for _, property in { "SoundId", "Looped", "SoundGroup" } do
	object = new(); current(object, 5, "active")
	local foreign = object._sounds.CornLoop.sound
	local value = if property == "SoundId" then "rbxassetid://998888888"
		elseif property == "Looped" then false else make("SoundGroup")
	foreign[property] = value
	foreign.TimePosition, foreign.Volume = 7, 0.17
	advance(object, 0.1)
	local preservedFolder = object._folder
	object:Destroy()
	assert(not foreign.Destroyed and not preservedFolder.Destroyed and foreign[property] == value
		and foreign.TimePosition == 7 and foreign.Volume == 0.17 and foreign.stops == 0,
		"Foreign personal loop identity/loop/group must survive cleanup untouched")
	preservedFolder:Destroy()
	if property == "SoundGroup" then value:Destroy() end
end
for _, connection in connections do assert(not connection.Connected, "Continuous corn connection leaked") end
assert(gameplayWrites == 0, "Continuous corn audio wrote character/camera/gameplay state")
print("PASS continuous corn client adapter: one persistent owner loop plus ten bounded spatial loops for7other players/3NPC, fourthNPC refused; automatic sound2/noAB; stableURI/rolloff; Pause/Resume at11 and independentNPC cursor; walk/sprint/energy speeds; naturalwrap; menu/capture/caught/terminal/retry/actualRoot replacement; missing/failed/late decode; foreign personal identity preservation; cleanup/no gameplay writes. No audible claim.")
]=]
assert(loadstring(setup .. cases, "rustle-continuous-focused"))()
