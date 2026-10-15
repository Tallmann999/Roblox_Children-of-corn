-- Current AudioController with local adapters: simulated Ended, not real decoding.
local fs = require("@lune/fs")
local setup =
	assert(fs.readFile("tests/audio-controller.luau"):match("^(.-)gameplayWrites, scans = 0, 0"))
local cases = [=[
function methods:GetChildren() return table.clone(self._children) end
for index, key in Rules.CornKeys do
	assetList[key] = assetList["SpatialClip" .. index]
	assetList["SpatialClip" .. index] = nil
end
local oldSetAttribute = methods.SetAttribute
function methods:GetAttributeChangedSignal(key)
	self._attributeSignals = self._attributeSignals or {}
	self._attributeSignals[key] = self._attributeSignals[key] or signal()
	return self._attributeSignals[key]
end
function methods:SetAttribute(key, value)
	local previous = self:GetAttribute(key)
	oldSetAttribute(self, key, value)
	if previous ~= value and self._attributeSignals and self._attributeSignals[key] then
		self._attributeSignals[key]:Fire()
	end
end
local function source(at, seq, key, requested)
	local sound = make("Sound")
	sound.Name, sound.SoundId, sound.Volume = "CornAudio_corn_rustle", assetList[key].Id, 0.38
	sound:SetAttribute("CornAudioOwned", true)
	sound:SetAttribute("corn_project_id", "children_of_corn")
	sound:SetAttribute("audio_role", "corn_rustle")
	sound:SetAttribute("AudioRustleId", seq)
	sound:SetAttribute("AudioRustleStart", tostring(seq) .. ":" .. key)
	sound:SetAttribute("AudioRequestedPlaying", requested)
	sound.Parent = at
	return sound
end
local function commit(sound, seq, key)
	-- Atomic id/key wins even while unrelated replicated URI/IsPlaying lag.
	sound:SetAttribute("AudioRustleId", seq)
	sound:SetAttribute("AudioRustleStart", tostring(seq) .. ":" .. key)
end
local function voices(entry)
	assert(#entry.voices == 2 and entry.voices[1] == entry, "Primary alias/two-voice bound changed")
	assert(entry.voices[2].sound.Name == "CornLocalRustle2" and entry.sound.Name == "CornLocalRustle")
	for _, voice in entry.voices do
		assert(voice.sound.Parent == entry.root and voice.sound.Looped == false and voice.sound.PlaybackSpeed == 1)
		assert(voice.sound.SoundGroup == entry.sound.SoundGroup
			and voice.sound.RollOffMinDistance == Rules.Ranges.Rustle.Min
			and voice.sound.RollOffMaxDistance == Rules.Ranges.Rustle.Max, "Spatial/mix settings diverged")
	end
	return entry.voices[1], entry.voices[2]
end
local function ended(voice)
	local sound, id, plays, stops = voice.sound, voice.sound.SoundId, voice.sound.plays, voice.sound.stops
	sound._values.IsPlaying = false
	sound.Ended:Fire()
	assert(not voice.active and voice.current == nil, "Own Ended must release this voice")
	assert(sound.SoundId == id and sound.plays == plays and sound.stops == stops,
		"Ended dispatch must not Stop/replay/change URI before all listeners complete")
end
local function destroyed(entry)
	for _, voice in entry.voices do assert(voice.sound.Destroyed, "Local voice survived cleanup") end
end
createdSoundsLoaded = true
local server = source(root, 5, "COC_Corn_13", false)
local object = new()
show(object, 1, 0, "none")
local entry = assert(object._rustles[root])
local first, second = voices(entry)
assert(server.Volume == 0 and first.sound.plays == 0 and second.sound.plays == 0 and entry.lastId == 5,
	"Initial stopped history must not play either voice")
commit(server, 6, "COC_Corn_13")
assert(first.sound.plays == 1 and first.current.id == 6 and first.sound.SoundId == assetList.COC_Corn_13.Id)
commit(server, 7, "COC_Corn_11")
assert(first.active and second.active and second.sound.plays == 1 and second.current.id == 7,
	"Two cues must onset before either voice Ends")
commit(server, 8, "COC_Corn_02")
commit(server, 9, "COC_Corn_20")
commit(server, 9, "COC_Corn_11")
commit(server, 8, "COC_Corn_02")
server:SetAttribute("AudioRustleStart", "10:COC_Fire")
assert(entry.pending.id == 9 and entry.pending.key == "COC_Corn_20" and entry.lastId == 9,
	"Busy voices need newest pending only; duplicate/stale/malformed commits must be ignored")
advance(object, 20)
assert(first.sound.plays == 1 and second.sound.plays == 1 and first.sound.stops == 0 and second.sound.stops == 0)
assert(first.sound.SoundId == assetList.COC_Corn_13.Id and second.sound.SoundId == assetList.COC_Corn_11.Id,
	"Manifest/server URI/timer replaced a started voice")
server:SetAttribute("AudioRequestedPlaying", false)
show(object, 1, 0, "none", "caught", "capturing")
gui.MenuIsOpen = true
gui.MenuOpened:Fire()
advance(object, 0.2)
assert(first.sound.IsPlaying and second.sound.IsPlaying and first.sound.stops == 0 and second.sound.stops == 0,
	"Stopped intent/caught/menu must retain both tails")
gui.MenuIsOpen = false
ended(second)
assert(first.active and first.current.id == 6 and entry.pending.id == 9, "Second Ended changed first tail/pending")
advance(object, 0.01)
assert(first.sound.plays == 1 and first.current.id == 6 and second.sound.plays == 2
	and second.current.id == 9 and entry.pending == nil and second.sound.SoundId == assetList.COC_Corn_20.Id,
	"Only free second voice may start newest pending on the next heartbeat")
ended(first)
advance(object, 0.01)
assert(first.sound.plays == 1 and not first.active and second.active, "Primary Ended replayed obsolete history")
ended(second)
advance(object, 10)
assert(not first.active and not second.active and first.sound.plays == 1 and second.sound.plays == 2,
	"Bounded scheduler retained queue history")
server.Volume = 0.55
assert(server.Volume == 0 and entry.previousVolume == 0.55, "Gain rewrite must be remuted/remembered")
local foreignChild = make("Folder")
foreignChild.Name, foreignChild.Parent = "AuthorChild", second.sound
show(object, 1, 0, "none", "escaped", "stopped")
destroyed(entry)
assert(object._rustleCount == 0 and server.Volume == 0.55 and foreignChild.Parent == root,
	"Terminal must cleanup both voices, preserve foreign children and restore latest gain")
foreignChild:Destroy()
server:SetAttribute("AudioRequestedPlaying", false)
server:SetAttribute("AudioRustleStart", "10:COC_Corn_02")
show(object, 2, 0, "none")
entry = assert(object._rustles[root])
first, second = voices(entry)
assert(first.sound.plays == 0 and second.sound.plays == 0 and entry.lastId == 10, "Retry replayed stopped history")
commit(server, 11, "COC_Corn_02")
commit(server, 12, "COC_Corn_13")
humanoid._values.Health = 0
advance(object, 0.1)
destroyed(entry)
assert(object._rustleCount == 0 and server.Volume == 0.55, "Death must cleanup both voices")
humanoid._values.Health = 100
server:SetAttribute("AudioRequestedPlaying", false)
object:Clear("test reset")
show(object, 3, 0, "none")
entry = assert(object._rustles[root])
commit(server, 13, "COC_Corn_13")
commit(server, 14, "COC_Corn_11")
server.SoundId, server.Volume = "rbxassetid://999", 0.19
advance(object, 0.1)
destroyed(entry)
assert(server.Volume == 0.19, "Foreign source identity/gain must survive guarded release")
object:Destroy()
server:Destroy()

-- Expire both cold voices. Failed older cues must never be requeued after id5.
server = source(root, 1, "COC_Corn_13", true)
createdSoundsLoaded = false
object = new()
show(object, 4, 0, "none")
entry = assert(object._rustles[root])
first, second = voices(entry)
commit(server, 2, "COC_Corn_11")
first.sound._values.IsPlaying, second.sound._values.IsPlaying = false, false
commit(server, 3, "COC_Corn_02")
commit(server, 4, "COC_Corn_18")
commit(server, 5, "COC_Corn_20")
assert(first.sound.plays == 1 and second.sound.plays == 1 and not first.sound.IsLoaded and not second.sound.IsLoaded)
advance(object, 8.1)
assert(first.sound.stops == 1 and second.sound.stops == 1 and not first.active and not second.active
	and entry.pending.id == 5, "Cold loads must expire with one newest pending")
advance(object, 0.51)
assert(first.sound.plays == 2 and first.current.id == 5 and first.sound.SoundId == assetList.COC_Corn_20.Id
	and second.sound.plays == 1 and not second.active and entry.pending == nil,
	"Cold retry replayed superseded ids or started a third voice")
first.sound._values.IsLoaded, first.sound._values.IsPlaying, first.sound._values.TimePosition = true, true, 0.1
advance(object, 10)
assert(first.sound.stops == 1 and first.active and second.sound.stops == 1, "Recovered playback lost full tail")
ended(first)
advance(object, 10)
assert(first.sound.plays == 2 and second.sound.plays == 1 and not entry.pending, "Old failed cue retried after newer acceptance")
object:Destroy()
destroyed(entry)
assert(server.Volume == 0.38 and object._rustleCount == 0)
server:Destroy()

createdSoundsLoaded = true
local function npc(index)
	local model, npcRoot = make("Model"), make("Part")
	model.Name, model.Parent = "Monster" .. index, runtime
	for key, value in { CornMonsterOwned = true, corn_project_id = "children_of_corn",
		MonsterRigVersion = 1, MonsterIndex = index, HuntState = "chase", ChaseTargetUserId = 20 } do
		model:SetAttribute(key, value)
	end
	npcRoot.Name, npcRoot.Parent = "Root", model
	return model, npcRoot
end
local secondNpc, secondRoot = npc(2)
local thirdNpc, thirdRoot = npc(3)
local fourthNpc, fourthRoot = npc(4)
local npcSources = { source(enemy, 1, "COC_Corn_13", true), source(secondRoot, 1, "COC_Corn_11", true),
	source(thirdRoot, 1, "COC_Corn_20", true), source(fourthRoot, 1, "COC_Corn_02", true) }
object = new()
show(object, 5, 0, "none")
assert(object._rustleCount == 3 and object._rustles[enemy] and object._rustles[secondRoot]
	and object._rustles[thirdRoot] and not object._rustles[fourthRoot], "Fixed three NPC registry guard failed")
local firstTail, secondTail, thirdTail = object._rustles[enemy], object._rustles[secondRoot], object._rustles[thirdRoot]
for _, tail in { firstTail, secondTail, thirdTail } do
	local a, b = voices(tail)
	commit(tail.source, 2, "COC_Corn_02")
	commit(tail.source, 3, "COC_Corn_18")
	assert(a.sound.plays == 1 and b.sound.plays == 1 and tail.pending.id == 3 and tail.source.Volume == 0,
		"Each NPC needs two independent busy voices and one pending cue")
end
ended(secondTail.voices[2])
advance(object, 0.3)
assert(secondTail.voices[2].sound.plays == 2 and secondTail.voices[2].current.id == 3
	and firstTail.voices[2].sound.plays == 1 and thirdTail.voices[2].sound.plays == 1
	and secondTail.current.id == 1, "One NPC/voice Ended replaced another tail")
secondNpc:SetAttribute("corn_project_id", "foreign")
advance(object, 0.3)
destroyed(secondTail)
assert(npcSources[2].Volume == 0.38 and object._rustleCount == 2, "Foreign NPC release failed")
show(object, 5, 0, "none", "caught", "capturing")
advance(object, 1)
for _, tail in { firstTail, thirdTail } do
	for _, voice in tail.voices do assert(voice.active and voice.sound.stops == 0, "Capture cut NPC tail") end
end
object:Destroy()
destroyed(firstTail); destroyed(thirdTail)
assert(npcSources[1].Volume == 0.38 and npcSources[3].Volume == 0.38 and npcSources[4].Volume == 0.38)
for _, npcSource in npcSources do npcSource:Destroy() end
secondNpc:Destroy(); thirdNpc:Destroy(); fourthNpc:Destroy()

object = new()
show(object, 6, 0, "none")
local slots, allVoices = {}, {}
for index = 1, 12 do
	local testRoot = make("Part")
	testRoot.Name, testRoot.Parent = "HumanoidRootPart", hero
	local testSource = source(testRoot, 1, "COC_Corn_02", false)
	local bound = object:_bindRustle(testRoot, testSource)
	assert((index <= 11) == (bound ~= nil), "Hard eleven-actor cap must hold")
	if bound then
		voices(bound)
		for _, voice in bound.voices do table.insert(allVoices, voice.sound) end
	end
	table.insert(slots, {testRoot, testSource})
end
assert(object._rustleCount == 11 and #allVoices == 22, "Eleven actors must own exactly twenty-two voices")
object:Clear("cap cleanup")
assert(object._rustleCount == 0)
for _, sound in allVoices do assert(sound.Destroyed and sound.Parent == nil, "Clear leaked one of twenty-two voices") end
for _, pair in slots do assert(pair[2].Volume == 0.38); pair[1]:Destroy() end
object:Destroy()
for _, connection in connections do assert(not connection.Connected, "Rustle/audio connection leaked") end
print("PASS client two-voice adapters: two onsets before Ended; atomic key/id/history guards; bounded2+newest pending1; independent Ended/heartbeat reuse/noStop/activeURIcuts/history; caught/menu tails; guardedgain/foreign/death/retry cleanup; cold8s newest-only recovery; three NPC independence/fourth refusal; eleven actors/twenty-two Sound cleanup. Real decoding requires Studio fixture.")
]=]
local fixture = assert(loadstring(setup .. cases, "rustle-client-focused"))
fixture()
