--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("GameShared"):WaitForChild("Game")
local Inventory = require(Shared:WaitForChild("Inventory"))
local Stamina = require(Shared:WaitForChild("Stamina"))
local SoloRound = require(script.Parent:WaitForChild("SoloRound"))

local Participant = {}
Participant.__index = Participant

-- These helpers touch only this player's state or validate a world interaction.
-- SoloRound:Start and its shared-world lifecycle are never used by a participant.
for _, name in
	{
		"_livingCharacter",
		"_controls",
		"_fallbackSpawn",
		"_setRespawnLocation",
		"_moveToStart",
		"_promptNearby",
		"_canInteract",
		"_inventoryRequest",
		"_sprintRequest",
		"_movement",
		"_recordCharacterDeath",
	}
do
	Participant[name] = SoloRound[name]
end

function Participant.new(team: any, player: Player): any
	local self = SoloRound.new(team.context)
	setmetatable(self, Participant)
	self.team = team
	self.player = player
	self.world = team.world
	self.admitted = false
	self.ready = false
	self.inRound = false
	self.destroyed = false
	self.joinedRound = 0
	return self
end

function Participant:_send()
	local player = self.player
	if self.destroyed or not player or player.Parent ~= Players then
		return
	end
	local now = os.clock()
	local facing = if self.selectedSpawn
		then self.selectedSpawn.CFrame.LookVector
		else Vector3.zAxis
	local horizontal = Vector3.new(facing.X, 0, facing.Z)
	local playing = self.inRound and (self.phase == "active" or self.phase == "caught")
	self.snapshot:FireClient(player, {
		phase = self.phase,
		lighting_mode = self.lightingMode,
		minimap = self.minimap:Snapshot(),
		inventory = Inventory.Snapshot(self.inventory, now),
		has_key = self.hasKey,
		gate_open = self.team.gateOpen,
		evacuation = {
			active = playing and self.team.evacuationActive,
			remaining = if playing and self.team.evacuationDeadline
				then math.clamp(self.team.evacuationDeadline - now, 0, 120)
				else 0,
			duration = 120,
		},
		team = self.team:Snapshot(self),
		session_diamonds = self.diamonds,
		reward_diamonds = self.reward,
		elapsed_sec = if playing and self.team.startedAt
			then now - self.team.startedAt
			else self.elapsed,
		notice = self.notice,
		stamina = self.stamina.value,
		stamina_capacity = self.balance.stamina_capacity,
		is_sprinting = self.stamina.sprinting,
		sprint_exhausted = self.stamina.exhausted,
		start_look = if horizontal.Magnitude > 0 then horizontal.Unit else Vector3.new(0, 0, -1),
		catches_remaining = math.max(0, self.balance.max_catches - self.catches),
		capture = {
			id = self.catches,
			remaining = if self.phase == "caught"
				then math.clamp(self.captureUntil - now, 0, 1)
				else 0,
			frame = self.captureFrame,
		},
		monster_state = self.team:MonsterState(self),
		protection_sec = math.max(0, self.protectedUntil - now),
	})
end

function Participant:Reset(spawn: BasePart)
	self.epoch += 1
	self.ready = false
	self.inRound = true
	self.joinedRound = self.team.roundId
	self.phase = "preparing"
	self.world = self.team.world
	self.items = nil
	self.selectedSpawn = spawn
	self:_setRespawnLocation()
	self.inventory = Inventory.new(os.clock())
	self.stamina = Stamina.new(self.balance.stamina_capacity, os.clock())
	self.minimap:ResetHistory()
	self.catches = 0
	self.captureFrame = CFrame.identity
	self.captureUntil = 0
	self.protectedUntil = 0
	self.elapsed = 0
	self.reward = 0
	self.notice = ""
	self.hasKey = false
	self.roundCharacter = nil
	self.lightingMode = self.team.lightingMode
	self:_controls(false)
end

function Participant:_finish(phase: string, notice: string)
	if self.phase ~= "active" and self.phase ~= "preparing" and self.phase ~= "caught" then
		return
	end
	local _, _, root = self:_livingCharacter()
	if not root and self.roundCharacter then
		local lastRoot = self.roundCharacter:FindFirstChild("HumanoidRootPart")
		if lastRoot and lastRoot:IsA("BasePart") then
			root = lastRoot
		end
	end
	self.team:DropKey(self, if root then root.Position else nil)
	self.phase = phase -- Commit before reward, client events or team completion.
	self.epoch += 1
	self.captureUntil = 0
	self.elapsed = if self.team.startedAt then os.clock() - self.team.startedAt else 0
	self.notice = notice
	self.reward = if phase == "escaped" then self.balance.escape_reward_diamonds else 0
	self.diamonds += self.reward
	self.hasKey = false
	self.inventory = Inventory.new(os.clock())
	self:_controls(false)
	self.team:CompleteIfDone()
	self.team:Broadcast()
end

function Participant:_caught(root: BasePart, captor: any)
	if self.phase ~= "active" then
		return
	end
	local now = os.clock()
	self.minimap:RecordCaught(root.Position)
	self.catches += 1
	self.captureFrame = captor:BeginCapture(root.Position)
	self.captureUntil = now + self.balance.capture_transition_sec
	self.phase = "caught"
	self.inventory.energyUntil = 0
	local hadKey = self.hasKey
	self.team:DropKey(self, root.Position)
	self.notice = if self.catches >= self.balance.max_catches
		then "corn_hunt_defeat_notice"
		elseif hadKey then "corn_hunt_key_dropped"
		else "corn_hunt_first_catch"
	self:_controls(false)
	self.team:Broadcast()
	local teamEpoch, actorEpoch = self.team.epoch, self.epoch
	task.delay(self.balance.capture_transition_sec, function()
		if self.team.epoch ~= teamEpoch then
			return
		end
		if not captor.destroyed and captor.state == "capturing" then
			captor:EndCapture()
		end
		if self.destroyed or self.epoch ~= actorEpoch or self.phase ~= "caught" then
			return
		end
		self.captureUntil = 0
		if self.catches >= self.balance.max_catches then
			self:_finish("caught_out", "corn_hunt_defeat_notice")
		else
			self:_send()
		end
	end)
end

function Participant:_revive()
	if self.team:ExpireEvacuation(os.clock()) then
		return
	end
	if
		self.phase ~= "caught"
		or self.captureUntil ~= 0
		or self.catches ~= 1
		or self.team.state ~= "active"
	then
		return
	end
	local character = self:_livingCharacter()
	if
		not character
		or character ~= self.roundCharacter
		or not self.world
		or not self.world:IsValid()
	then
		self:_finish("aborted", "corn_loop_result_aborted")
		return
	end
	self:_moveToStart(character)
	self.stamina = Stamina.new(self.balance.stamina_capacity, os.clock())
	self.protectedUntil = os.clock() + self.balance.respawn_protection_sec
	self.phase = "active"
	self.notice = ""
	self:_controls(true)
	self.team:Broadcast()
end

function Participant:_menu()
	if self.phase == "caught" and self.captureUntil == 0 then
		self:_finish("aborted", "corn_loop_result_aborted")
	end
	if self.phase ~= "escaped" and self.phase ~= "aborted" and self.phase ~= "caught_out" then
		return
	end
	self.phase = "ready"
	self.ready = false
	self.inRound = false
	self.notice = ""
	self.minimap:ClearHistory()
	local character = self:_livingCharacter()
	if character then
		self:_moveToStart(character)
	end
	self:_controls(false)
	self.team:Broadcast()
end

function Participant:_bindCharacter(character: Model)
	if self.destroyed or character == self.boundCharacter then
		return
	end
	if self.roundCharacter and character ~= self.roundCharacter then
		self:_recordCharacterDeath(self.roundCharacter)
		self:_finish("aborted", "corn_loop_result_aborted")
	end
	self.boundCharacter = character
	if self.deathConnection then
		self.deathConnection:Disconnect()
	end
	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 10)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if
			self.destroyed
			or self.player.Character ~= character
			or self.boundCharacter ~= character
		then
			return
		end
		if not humanoid or not humanoid:IsA("Humanoid") or not root or not root:IsA("BasePart") then
			self:_finish("aborted", "corn_loop_setup_error")
			return
		end
		self.deathConnection = humanoid.Died:Connect(function()
			if self.player.Character == character and self.roundCharacter == character then
				self:_recordCharacterDeath(character)
				self:_finish("aborted", "corn_loop_result_aborted")
			end
		end)
		if self.phase ~= "active" and self.phase ~= "preparing" then
			self:_moveToStart(character)
		end
		self:_controls(self.phase == "active" and self.roundCharacter == character)
		self:_send()
	end)
end

function Participant:Bind()
	self.characterConnection = self.player.CharacterAdded:Connect(function(character)
		self:_bindCharacter(character)
	end)
	self.characterRemovingConnection = self.player.CharacterRemoving:Connect(function(character)
		-- A previous round's corpse can disappear while the next round waits
		-- for a fresh character. Only the committed round character can end it.
		if character == self.roundCharacter then
			self:_recordCharacterDeath(character)
			local root = character:FindFirstChild("HumanoidRootPart")
			self.team:DropKey(self, if root and root:IsA("BasePart") then root.Position else nil)
			self:_finish("aborted", "corn_loop_result_aborted")
		end
	end)
	if self.player.Character then
		self:_bindCharacter(self.player.Character)
	end
end

function Participant:Destroy()
	self.destroyed = true
	self.epoch += 1
	for _, name in { "characterConnection", "characterRemovingConnection", "deathConnection" } do
		if self[name] then
			self[name]:Disconnect()
			self[name] = nil
		end
	end
end

return Participant
