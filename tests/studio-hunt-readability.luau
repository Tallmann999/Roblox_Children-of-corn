-- Real engine geometry/Sounds with an isolated world and logical20second timeline.
-- The live countdown and audible awakening are separately tested on the regular round.
local Modules = game.ServerScriptService.GameServer.Game
local Hunt = require(Modules.MonsterHunt)
local Audio = require(Modules.RoundAudio)
local Shared = game.ReplicatedStorage.GameShared.Game
local Balance, Pose = require(Shared.Balance), require(Shared.MonsterPose)
local owner = assert(game.Players:GetPlayers()[1])
local scratch = Instance.new("Model")
scratch.Name = "HuntReadabilityAcceptance"
scratch.Parent = workspace
scratch:SetAttribute("corn_project_id", "children_of_corn")
local function part(name, size, position, parent, collision)
	local item = Instance.new("Part")
	item.Name = name
	item.Size = size
	item.Position = position
	item.Anchored = true
	item.CanCollide = collision == true
	item.CanQuery = collision == true
	item.Parent = parent or scratch
	return item
end
local ground = part("Ground", Vector3.new(300, 2, 300), Vector3.new(0, 500, 0), scratch, true)
local field = part("FieldZone", Vector3.new(300, 10, 300), Vector3.new(0, 506, 0))
local runtime = Instance.new("Folder")
runtime.Name = "CornRoundRuntime"
runtime:SetAttribute("corn_project_id", "children_of_corn")
runtime.Parent = scratch
local home = Instance.new("Model")
home.Name = "Home"
home.Parent = scratch
part("Body", Vector3.one, Vector3.new(0, 509, 0), home)
local slots = {}
for i = 1, 15 do
	slots[i] = part("Slot" .. i, Vector3.one, Vector3.new((i - 8) * 10, 501, 80))
end
local character = Instance.new("Model")
character.Parent = scratch
local root = part("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(16.001, 504, 0), character)
local world =
	{ Root = scratch, Runtime = runtime, Home = home, Ground = ground, Field = field, Slots = slots }
local hunt = Hunt.new(world, Balance, 0, owner.UserId)
local audio = Audio.new(world, owner, hunt, Random.new(78))
local checks = {}
local ok, problem = pcall(function()
	assert(
		Balance.hunt_start_delay_sec == 20
			and Balance.monster_detect_radius == 16
			and Balance.monster_chase_windup_sec == 2
	)
	assert(hunt.root.Size == Vector3.new(3, 6, 2) and hunt.root.Position == hunt.home)
	for _, definition in Pose.Parts do
		local visual = assert(hunt.model:FindFirstChild(definition.Name))
		assert(visual.Size == definition.Size)
		assert(
			(
				hunt.root.CFrame:ToObjectSpace(visual.CFrame).Position
				- Pose.Rest[definition.Name].Position
			).Magnitude < 0.0001
		)
	end
	local foot = hunt.model.LeftLeg.Position.Y - hunt.model.LeftLeg.Size.Y / 2
	local top = hunt.model.Hat.Position.Y + hunt.model.Hat.Size.Y / 2
	assert(math.abs(foot - 501) < 0.0001 and math.abs(top - foot - 10.8 * 1.3) < 0.0001)
	checks.visual_height_thirty_percent_root_and_feet_unchanged = true
	assert(not hunt:Step(0, 19.999, root, false) and hunt.state == "dormant")
	audio:Step(19.999, "active", "hard", hunt)
	assert(not audio.wakePlayed)
	local caught, awakened = hunt:Step(0, 20, root, false)
	assert(not caught and awakened and hunt.state == "patrol")
	audio:Step(20, "active", "hard", hunt)
	assert(audio.wakePlayed and audio.wakeSound:GetAttribute("AudioRequestedPlaying") == true)
	assert(
		audio.wakeSound.RollOffMode == Enum.RollOffMode.Linear
			and audio.wakeSound.RollOffMaxDistance > 840 * math.sqrt(2)
	)
	assert(audio.wakeSound.Parent.Position == hunt.home and not audio.wakeSound.Looped)
	checks.awakening_twenty_seconds_radius_sixteen_and_spatial_home_scream = true
	root.Position = hunt.home + Vector3.new(16, 0, 0)
	hunt:Step(0, 20.1, root, false)
	assert(hunt.state == "chase" and hunt.chaseStartedAt == 20.1)
	for _, entry in { { 20.2, 1 }, { 22.099, 1 }, { 22.1, 1.3 } } do
		root.Position = hunt.root.Position + Vector3.new(30, 0, 0)
		local before = hunt.root.Position
		assert(not hunt:Step(0.1, entry[1], root, false))
		assert(math.abs((hunt.root.Position - before).Magnitude - entry[2]) < 0.0001)
		audio:Step(entry[1], "active", "hard", hunt)
		for _, voice in audio.voices do
			assert(
				voice:GetAttribute("AudioRequestedPlaying") == false,
				"Regular voice overlapped awakening"
			)
		end
	end
	assert(audio.wakeSound.Parent.Position == hunt.home, "Awakening emitter followed monster")
	root.Position = hunt.root.Position + Vector3.new(2, 0, 0)
	assert(not hunt:CanCapture(root, 22.099) and hunt:CanCapture(root, 22.1))
	hunt:Step(0, 22.2, root, true)
	assert(hunt.chaseStartedAt == nil)
	hunt:Step(0, 22.3, root, false)
	assert(hunt.chaseStartedAt == 22.3 and not hunt:CanCapture(root, 24.299))
	assert(hunt:Stun(22.4, 10) and hunt.chaseStartedAt == nil)
	hunt:ResetHome()
	assert(hunt.chaseStartedAt == nil)
	checks.two_second_patrol_speed_then_chase_and_capture_reset_on_protection_trap_home = true
	audio:Step(22.5, "caught", "hard", hunt)
	assert(audio.wakeSound:GetAttribute("AudioRequestedPlaying") == false)
	audio:Step(30, "active", "hard", hunt)
	assert(audio.wakePlayed and audio.wakeSound:GetAttribute("AudioRequestedPlaying") == false)
	checks.one_awakening_and_capture_immediate_stop = true
	local sound, anchor = audio.wakeSound, audio.wakeSound.Parent
	audio:Destroy()
	assert(sound.Parent == nil and anchor.Parent == nil)
	checks.strict_owned_audio_cleanup = true
	checks.method =
		"Real engine Parts/Sounds/current modules, isolated logical20second clock; no claimed live UI countdown, listener mix or ordinary walkthrough."
end)
audio:Destroy()
hunt:Destroy()
scratch:Destroy()
assert(ok, problem)
return checks
