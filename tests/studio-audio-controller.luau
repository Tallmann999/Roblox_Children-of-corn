-- Client engine fixture: separate owned SoundService folder and controlled snapshots.
-- Simulated target attributes are local fixture objects; no production NPC or gameplay writes.
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local player = assert(Players.LocalPlayer)
local character = assert(player.Character, "Wait for a live character")
local humanoid = assert(character:FindFirstChildOfClass("Humanoid"))
local root = assert(character:FindFirstChild("HumanoidRootPart"))
assert(humanoid.Health > 0 and not GuiService.MenuIsOpen, "Resume a living round for this fixture")
local Module = require(player.PlayerScripts.GameClient.Controllers.AudioController)
local Rules = require(game.ReplicatedStorage.GameShared.Game.AudioRules)
local Assets = require(game.ReplicatedStorage.GameShared.Game.AudioAssets)
local camera = assert(workspace.CurrentCamera)
local baseline = {
	root = root.CFrame,
	walk = humanoid.WalkSpeed,
	camera = camera.CameraType,
	subject = camera.CameraSubject,
	fov = camera.FieldOfView,
}
local controller = setmetatable({}, { __index = Module })
controller:Init({})
controller._folderName = "CornPersonalAudioFixture_" .. HttpService:GenerateGUID(false)
controller._capture = { _state = { active = false } }
local checks, loaded = {}, {}
local function own(instance, role)
	instance:SetAttribute("CornAudioOwned", true)
	instance:SetAttribute("corn_project_id", "children_of_corn")
	instance:SetAttribute("AudioVersion", 1)
	instance:SetAttribute("audio_role", role)
end
local function expect(condition, message)
	assert(condition, message or "Engine personal audio fixture failed")
end
local function snapshot(roundId, useId, kind, phase, state)
	return {
		minimap = { round_id = roundId },
		phase = phase or "active",
		monster_state = state or "patrol",
		inventory = {
			slots = { "empty", "empty", "empty", "empty", "empty" },
			selected = 1,
			energy_remaining = 0,
			use = { id = useId, kind = kind },
		},
	}
end
local function show(roundId, useId, kind, phase, state)
	controller:SetSnapshot(snapshot(roundId, useId, kind, phase, state))
end
local function step(dt)
	controller:_step(dt, os.clock())
end
local ok, problem = pcall(function()
	expect(controller:_build())
	local folder = assert(controller._folder)
	expect(folder.Parent == SoundService and folder:GetAttribute("CornAudioOwned") == true)
	expect(
		math.abs(controller._groups.Music.Volume - Rules.Mix.Master * Rules.Mix.Music) < 0.00001,
		"Music group gain differs from AudioRules"
	)
	expect(
		math.abs(controller._groups.Effects.Volume - Rules.Mix.Master * Rules.Mix.Effects) < 0.00001,
		"Effects group gain differs from AudioRules"
	)
	for _, child in folder:GetDescendants() do
		expect(child:GetAttribute("CornAudioOwned") == true)
	end
	controller:_preloadAssets()
	local deadline = os.clock() + 6
	while os.clock() < deadline do
		local ready = true
		for _, entry in controller._sounds do
			ready = ready and entry.sound.IsLoaded
		end
		if ready then
			break
		end
		task.wait(0.1)
	end
	for role, entry in controller._sounds do
		loaded[role] = {
			id = entry.sound.SoundId,
			isLoaded = entry.sound.IsLoaded,
			timeLength = entry.sound.TimeLength,
		}
		expect(
			entry.sound.IsLoaded and entry.sound.TimeLength > 0,
			"Unloaded real asset: " .. role .. " " .. entry.sound.SoundId
		)
	end
	checks.category_groups_owned_local_folder = true
	checks.assets = loaded
	checks.asset_ids_pending = next(controller._sounds) == nil
	show(1, 4, "energy")
	local energy, trap = controller._sounds.Energy, controller._sounds.Trap
	if energy then
		expect(not energy.playing and not energy.sound.IsPlaying, "Initial sync replayed energy")
	end
	if trap then
		expect(not trap.playing and not trap.sound.IsPlaying, "Initial sync replayed trap")
	end
	step(0.4)
	local background, hunt = controller._sounds.Background, controller._sounds.Hunt
	if background then
		expect(background.playing and background.sound.IsPlaying)
		expect(background.sound.Volume > 0 and background.sound.Volume < background.gain)
		task.wait(0.18)
		expect(background.sound.TimePosition > 0, "Loaded background failed actual playback")
		loaded.Background.playbackPosition = background.sound.TimePosition
	end
	step(0.4)
	if background then
		expect(math.abs(background.sound.Volume - background.gain) < 0.00001)
	end
	checks.initial_sync_skip_and_background_fade = true
	local enemyModel, enemyRoot = Instance.new("Model"), Instance.new("Part")
	enemyModel.Name = "TargetFixture"
	own(enemyModel, "fixture-monster")
	enemyModel:SetAttribute("CornMonsterOwned", true)
	enemyModel:SetAttribute("MonsterRigVersion", 1)
	enemyModel:SetAttribute("MonsterIndex", 1)
	enemyModel:SetAttribute("HuntState", "chase")
	enemyModel.Name = "Monster"
	enemyModel:SetAttribute("ChaseTargetUserId", player.UserId)
	enemyModel.Parent = folder
	enemyRoot.Name = "Root"
	own(enemyRoot, "fixture-root")
	enemyRoot.Anchored, enemyRoot.CanCollide, enemyRoot.CanTouch, enemyRoot.CanQuery =
		true, false, false, false
	enemyRoot.Position = root.Position + Vector3.new(0, 0, 10)
	enemyRoot.Parent = enemyModel
	controller._monster, controller._monsterRoot = enemyModel, enemyRoot
	controller._monsters = { { model = enemyModel, root = enemyRoot, runtime = folder, index = 1 } }
	controller._resolveAt = math.huge
	show(1, 4, "energy", "active", "chase")
	step(0.14)
	if hunt then
		expect(
			hunt.playing
				and hunt.sound.IsPlaying
				and math.abs(hunt.sound.Volume - hunt.gain * 0.1) < 0.00001
		)
	end
	step(1.4)
	if hunt then
		expect(math.abs(hunt.sound.Volume - hunt.gain) < 0.00001)
		task.wait(0.18)
		expect(hunt.sound.TimePosition > 0, "Loaded hunt failed actual playback")
		loaded.Hunt.playbackPosition = hunt.sound.TimePosition
	end
	enemyModel:SetAttribute("ChaseTargetUserId", player.UserId + 1)
	step(0.3)
	if hunt then
		expect(hunt.playing and hunt.sound.Volume > 0 and hunt.sound.Volume < hunt.gain)
	end
	step(2.5)
	if hunt then
		expect(not hunt.playing and not hunt.sound.IsPlaying and hunt.sound.Volume == 0)
	end
	enemyModel:SetAttribute("ChaseTargetUserId", player.UserId)
	enemyRoot.Position = root.Position + Vector3.new(0, 0, 100)
	step(2)
	if hunt then
		expect(not hunt.playing, "Far target heard chase music")
	end
	enemyRoot.Position = root.Position + Vector3.new(0, 0, 10)
	step(0.3)
	checks.simulated_server_target_identity_quiet_chase_fadeout_stop_and_far_mute = true
	show(1, 5, "energy", "active", "chase")
	local useDeadline = if energy then energy.deadline else nil
	if energy then
		expect(energy.playing and energy.sound.IsPlaying)
		task.wait(0.12)
		expect(energy.sound.TimePosition > 0, "Loaded energy failed actual playback")
		loaded.Energy.playbackPosition = energy.sound.TimePosition
	end
	show(1, 5, "energy", "active", "chase")
	show(1, 4, "energy", "active", "chase")
	if energy then
		expect(energy.deadline == useDeadline, "Duplicate/stale use replayed effect")
	end
	show(1, 6, "trap", "active", "chase")
	if trap then
		expect(trap.playing and trap.sound.IsPlaying)
		task.wait(0.12)
		expect(trap.sound.TimePosition > 0, "Loaded trap failed actual playback")
		loaded.Trap.playbackPosition = trap.sound.TimePosition
	end
	show(1, 6, "trap", "caught", "capturing")
	for _, role in { "Hunt", "Energy", "Trap" } do
		local entry = controller._sounds[role]
		if entry then
			expect(
				not entry.playing and not entry.sound.IsPlaying,
				"Caught failed immediate stop: " .. role
			)
		end
	end
	show(1, 0, "none", "caught_out", "stopped")
	show(1, 6, "trap", "active", "chase")
	step(1)
	for _, entry in controller._sounds do
		expect(not entry.playing and not entry.sound.IsPlaying, "Old active revived terminal round")
	end
	show(2, 3, "energy")
	if energy then
		expect(not energy.playing, "New round initial sync replayed use")
	end
	controller:Clear("fixture reset")
	expect(controller._snapshot == nil)
	for _, entry in controller._sounds do
		expect(not entry.playing and not entry.sound.IsPlaying)
	end
	checks.accepted_energy_trap_duplicate_stale_capture_terminal_retry_clear_guards = true
	expect(humanoid.WalkSpeed == baseline.walk, "Audio changed movement speed")
	expect(
		camera.CameraType == baseline.camera
			and camera.CameraSubject == baseline.subject
			and camera.FieldOfView == baseline.fov,
		"Audio changed camera state"
	)
	checks.no_camera_or_gameplay_properties_written = true
	-- In a real active round physics may move Root during task.wait; no position equality claim.
	for role, key in
		{
			Background = "COC_Background_02",
			Hunt = "COC_Hunt",
			Energy = "COC_Energy_Open",
			Trap = "COC_Trap_Place",
		}
	do
		if Assets.Get(key).Id == "" then
			expect(not controller._sounds[role], "Missing asset created a player")
		end
	end
	checks.method =
		"Actual SoundService groups/Sounds and playback if real IDs exist; controlled snapshots and owned simulated target binding; actual NPC detection/world audio tested separately"
end)
local folder = controller._folder
local connections = table.clone(controller._connections)
controller:Destroy()
expect(folder == nil or folder.Parent == nil, "Fixture owned audio folder leaked")
for _, connection in connections do
	expect(not connection.Connected, "Fixture sound connection leaked")
end
expect(ok, tostring(problem))
checks.cleanup = true
return HttpService:JSONEncode(checks)
