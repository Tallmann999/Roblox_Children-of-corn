-- Client engine fixture using actual Sound property/child events on isolated fixture Models.
-- It does not alter the live character, default script, corn audio, camera or gameplay.
local player = assert(game:GetService("Players").LocalPlayer)
local SoundService = game:GetService("SoundService")
local HttpService = game:GetService("HttpService")
local Module = require(player.PlayerScripts.GameClient.Controllers.AudioController)
local controller = setmetatable({}, { __index = Module })
controller:Init({})
local state = { characterConnections = {}, rootConnections = {}, sounds = {} }
local fixture = Instance.new("Folder")
fixture.Name = "CornFootstepFixture_" .. HttpService:GenerateGUID(false)
fixture:SetAttribute("corn_test_owned", true)
fixture.Parent = SoundService
local DEFAULT = "rbxasset://sounds/action_footsteps_plastic.mp3"
local checks = {}
local function expect(condition, message)
	assert(condition, message or "Default footstep engine fixture failed")
end
local function sound(root, name, id, volume)
	local value = Instance.new("Sound")
	value.Name, value.SoundId, value.Volume = name, id, volume
	value.Parent = root
	return value
end
local function character()
	local value = Instance.new("Model")
	value.Name = "FixtureCharacter"
	value.Parent = fixture
	return value
end
local function root(characterModel)
	local value = Instance.new("Part")
	value.Name = "HumanoidRootPart"
	value.Anchored = true
	value.CanCollide, value.CanTouch, value.CanQuery = false, false, false
	value.Parent = characterModel
	return value
end
local ok, problem = pcall(function()
	local first = character()
	controller:_bindFootstepCharacter(state, first)
	local firstRoot = root(first)
	local running = sound(firstRoot, "Running", DEFAULT, 0.65)
	local climbing = sound(firstRoot, "Climbing", "", 0.42)
	local jump = sound(firstRoot, "Jumping", "rbxasset://sounds/action_jump.mp3", 0.4)
	local died = sound(firstRoot, "Died", "rbxasset://sounds/uuhhh.mp3", 0.3)
	local corn = sound(firstRoot, "CornRustle", "rbxassetid://99", 0.25)
	local duplicate = sound(firstRoot, "Running", DEFAULT, 0.61)
	task.wait()
	expect(
		running.Volume == 0 and math.abs(climbing.Volume - 0.42) < 0.00001,
		"Late Root/new default/custom Sound matching failed"
	)
	climbing.SoundId = DEFAULT
	task.wait()
	expect(climbing.Volume == 0, "Late default SoundId was not muted")
	running.Volume = 0.8
	task.wait()
	expect(running.Volume == 0, "Default volume rewrite escaped mute")
	expect(
		math.abs(jump.Volume - 0.4) < 0.00001
			and math.abs(died.Volume - 0.3) < 0.00001
			and corn.Volume == 0.25
			and math.abs(duplicate.Volume - 0.61) < 0.00001,
		"Unrelated/duplicate Sounds were altered"
	)
	checks.late_character_root_sound_id_and_volume_events_default_only = true
	checks.jump_death_corn_duplicate_unchanged = true
	running.SoundId = "rbxassetid://77"
	running.Volume = 0.19
	task.wait()
	controller:_bindFootstepCharacter(state, nil)
	expect(
		math.abs(climbing.Volume - 0.42) < 0.00001,
		"Unbind did not restore original default volume"
	)
	expect(
		math.abs(running.Volume - 0.19) < 0.00001,
		"Changed Sound identity received an unsafe restore"
	)
	checks.guarded_restore_preserves_changed_identity = true
	local nextCharacter = character()
	local nextRoot = root(nextCharacter)
	local nextRunning = sound(nextRoot, "Running", DEFAULT, 0.65)
	local nextClimbing = sound(nextRoot, "Climbing", DEFAULT, 0.65)
	controller:_bindFootstepCharacter(state, nextCharacter)
	expect(
		nextRunning.Volume == 0 and nextClimbing.Volume == 0,
		"Existing Sounds on respawn were not muted"
	)
	local connections = {}
	for _, connection in state.characterConnections do
		table.insert(connections, connection)
	end
	for _, connection in state.rootConnections do
		table.insert(connections, connection)
	end
	for _, entry in state.sounds do
		for _, connection in entry.connections do
			table.insert(connections, connection)
		end
	end
	controller:_bindFootstepCharacter(state, nil)
	expect(
		math.abs(nextRunning.Volume - 0.65) < 0.00001
			and math.abs(nextClimbing.Volume - 0.65) < 0.00001,
		"Respawn cleanup lost original volumes"
	)
	for _, connection in connections do
		expect(not connection.Connected, "Character/root/Sound connection leaked")
	end
	expect(
		next(state.sounds) == nil
			and #state.characterConnections == 0
			and #state.rootConnections == 0
	)
	checks.existing_respawn_defaults_and_connection_cleanup = true
	checks.method =
		"Actual client Sound/Part/Model events in isolated SoundService fixture; production default mute checked separately"
end)
controller:_bindFootstepCharacter(state, nil)
controller:Destroy()
fixture:Destroy()
expect(ok, tostring(problem))
checks.fixture_cleanup = true
return HttpService:JSONEncode(checks)
