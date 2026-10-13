--!strict
local PathfindingService = game:GetService("PathfindingService")
local Pose = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("GameShared")
		:WaitForChild("Game")
		:WaitForChild("MonsterPose")
)
local MonsterHunt = {}
MonsterHunt.__index = MonsterHunt

function MonsterHunt.new(world: any, balance: any, startedAt: number, targetUserId: number?)
	local home = world.Home:FindFirstChild("Body") :: BasePart
	assert(home and home:IsA("BasePart"), "Scarecrow home body missing")
	local floor = world.Ground.Position.Y + world.Ground.Size.Y / 2
	local model = Instance.new("Model")
	model.Name = "Monster"
	model:SetAttribute("CornMonsterOwned", true)
	model:SetAttribute("corn_project_id", "children_of_corn")
	model:SetAttribute("MonsterRigVersion", 1)
	model:SetAttribute("HuntState", "dormant")
	model:SetAttribute("ChaseTargetUserId", 0)
	local origin = Vector3.new(home.Position.X, floor + 3, home.Position.Z)
	local visuals = {}
	local function part(
		name: string,
		size: Vector3,
		offset: Vector3,
		color: Color3,
		hidden: boolean?
	): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = CFrame.new(origin + offset)
		p.Color = color
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Transparency = 1
		p.Parent = model
		if not hidden then
			table.insert(visuals, p)
		end
		return p
	end
	local root = part("Root", Vector3.new(3, 6, 2), Vector3.zero, Color3.new(), true)
	for _, definition in Pose.Parts do
		local visual = part(
			definition.Name,
			definition.Size,
			Pose.Rest[definition.Name].Position,
			definition.Color
		)
		visual.Material = definition.Material
	end
	model:SetAttribute("MonsterHeightScale", Pose.HeightScale)
	model.PrimaryPart = root
	model.Parent = world.Runtime
	return setmetatable({
		world = world,
		balance = balance,
		startedAt = startedAt,
		model = model,
		root = root,
		visuals = visuals,
		home = origin,
		state = "dormant",
		chaseStartedAt = nil,
		targetUserId = if targetUserId
				and targetUserId > 0
				and targetUserId % 1 == 0
			then targetUserId
			else 0,
		stunnedUntil = nil,
		lostSince = nil,
		lastSeenPosition = nil,
		patrolSlot = nil,
		patrolIndex = nil,
		goal = nil,
		route = nil,
		routeIndex = 2,
		pathAt = -math.huge,
		pathBusy = false,
		generation = 0,
		destroyed = false,
		originalMarker = {},
		blockedSince = nil,
	}, MonsterHunt)
end

function MonsterHunt:_state(state: string, now: number?)
	if self.state == state then
		return
	end
	-- A completed path belongs to the state that requested it. Cancel stale work
	-- only on transitions; visible chase polls must preserve a current path.
	self.generation += 1
	self.route = nil
	self.routeIndex = 2
	self.pathBusy = false
	self.pathAt = -math.huge
	self.state = state
	self.chaseStartedAt = if state == "chase" then now or os.clock() else nil
	self.model:SetAttribute("HuntState", state)
	self.model:SetAttribute("ChaseTargetUserId", if state == "chase" then self.targetUserId else 0)
end

function MonsterHunt:_params(character: Model?): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if character
		then { self.model, self.world.Home, character }
		else { self.model, self.world.Home }
	params.RespectCanCollide = true
	return params
end

function MonsterHunt:CanSee(playerRoot: BasePart): boolean
	local start = self.root.Position + Vector3.new(0, 1, 0)
	return workspace:Raycast(
		start,
		playerRoot.Position - start,
		self:_params(playerRoot.Parent :: Model)
	) == nil
end

function MonsterHunt:CanCapture(playerRoot: BasePart, now: number?): boolean
	if
		self.destroyed
		or self.state ~= "chase"
		or not self.chaseStartedAt
		or (now or os.clock()) - self.chaseStartedAt < self.balance.monster_chase_windup_sec
	then
		return false
	end
	local delta = playerRoot.Position - self.root.Position
	if
		Vector3.new(delta.X, 0, delta.Z).Magnitude > self.balance.monster_capture_radius
		or math.abs(delta.Y) > 7
	then
		return false
	end
	return self:CanSee(playerRoot)
end

function MonsterHunt:BeginCapture(playerPosition: Vector3): CFrame
	local at = self.root.Position
	local facing = Vector3.new(playerPosition.X - at.X, 0, playerPosition.Z - at.Z)
	if facing.Magnitude > 0.001 then
		self.model:PivotTo(CFrame.lookAt(at, at + facing))
	end
	self.goal = nil
	self.lostSince = nil
	self.lastSeenPosition = nil
	self:_state("capturing")
	return self.root.CFrame
end

function MonsterHunt:GetPosition(): Vector3?
	if self.destroyed or self.state == "dormant" or self.state == "stopped" then
		return nil
	end
	return self.root.Position
end

function MonsterHunt:Stun(now: number, duration: number): boolean
	if
		self.destroyed
		or (self.state ~= "patrol" and self.state ~= "chase")
		or typeof(now) ~= "number"
		or typeof(duration) ~= "number"
		or now ~= now
		or duration ~= duration
		or math.abs(now) == math.huge
		or duration <= 0
		or duration == math.huge
		or math.abs(now + duration) == math.huge
	then
		return false
	end
	self.stunnedUntil = now + duration
	self.goal = nil
	self.lostSince = nil
	self.lastSeenPosition = nil
	self.blockedSince = nil
	-- _state invalidates pending ComputeAsync jobs before they can restore a
	-- route for the chase that stepped into the trap.
	self:_state("trapped")
	return true
end

function MonsterHunt:_patrol(_playerPosition: Vector3): Vector3
	local slots = self.world.Slots
	local index = self.patrolIndex
	if index then
		index = (index - 1 + 7) % #slots + 1
	else
		local distance = math.huge
		for candidateIndex, slot in slots do
			local d = (slot.Position - self.root.Position).Magnitude
			if d < distance then
				index = candidateIndex
				distance = d
			end
		end
	end
	-- AuthoredWorld sorts the fifteen available slots by their unique slot_id.
	-- A stride of seven visits every slot once without using the player's position.
	self.patrolIndex = index or 1
	self.patrolSlot = slots[self.patrolIndex]
	return self.patrolSlot.Position
end

function MonsterHunt:_path(goal: Vector3, now: number)
	if self.pathBusy or now - self.pathAt < 1 then
		return
	end
	self.pathBusy = true
	self.pathAt = now
	local generation = self.generation
	local began = self.root.Position
	task.spawn(function()
		local path = PathfindingService:CreatePath({
			AgentRadius = 2,
			AgentHeight = 9,
			AgentCanJump = false,
			WaypointSpacing = 4,
		})
		local ok = pcall(function()
			path:ComputeAsync(began, goal)
		end)
		if self.destroyed or self.generation ~= generation then
			return
		end
		self.pathBusy = false
		if ok and path.Status == Enum.PathStatus.Success then
			self.route = path:GetWaypoints()
			self.routeIndex = 2
		else
			self.route = nil
		end
	end)
end

function MonsterHunt:ResetHome()
	self.stunnedUntil = nil
	self.generation += 1
	self.pathBusy = false
	self.route = nil
	self.goal = nil
	self.lostSince = nil
	self.lastSeenPosition = nil
	self.patrolSlot = nil
	self.patrolIndex = nil
	self.blockedSince = nil
	self.model:PivotTo(CFrame.new(self.home))
	self:_state("patrol")
end

function MonsterHunt:Step(
	dt: number,
	now: number,
	playerRoot: BasePart,
	protected: boolean
): (boolean, boolean)
	if self.destroyed or self.state == "capturing" then
		return false, false
	end
	if self.state == "trapped" then
		if now < self.stunnedUntil then
			return false, false
		end
		self.stunnedUntil = nil
		self:_state("patrol")
	end
	local awakened = false
	if self.state == "dormant" then
		if now - self.startedAt < self.balance.hunt_start_delay_sec then
			return false, false
		end
		for _, p in self.visuals do
			p.Transparency = 0
		end
		for _, item in self.world.Home:GetDescendants() do
			if item:IsA("BasePart") and item.Name ~= "Pole" then
				self.originalMarker[item] = item.Transparency
				item.Transparency = 1
			end
		end
		self:_state("patrol")
		awakened = true
	end
	local delta = playerRoot.Position - self.root.Position
	local distance = Vector3.new(delta.X, 0, delta.Z).Magnitude
	local canSee = not protected and self:CanSee(playerRoot)
	if canSee and distance <= self.balance.monster_detect_radius then
		self:_state("chase", now)
		self.lostSince = nil
		self.lastSeenPosition = playerRoot.Position
	end
	if self.state == "chase" then
		if protected then
			self:_state("patrol")
			self.goal = nil
			self.lostSince = nil
			self.lastSeenPosition = nil
		else
			if canSee then
				self.lastSeenPosition = playerRoot.Position
			end
			if distance > self.balance.monster_lose_radius or not canSee then
				self.lostSince = self.lostSince or now
				if now - self.lostSince >= self.balance.monster_lose_delay_sec then
					self:_state("patrol")
					self.goal = nil
					self.lostSince = nil
					self.lastSeenPosition = nil
				end
			else
				self.lostSince = nil
			end
		end
	end
	if not protected and self:CanCapture(playerRoot, now) then
		return true, awakened
	end
	if self.state == "chase" then
		self.goal = self.lastSeenPosition or self.root.Position
	elseif
		not self.goal
		or (Vector3.new(self.goal.X, self.root.Position.Y, self.goal.Z) - self.root.Position).Magnitude
			< 3
	then
		self.goal = self:_patrol(playerRoot.Position)
	end
	local goal = Vector3.new(self.goal.X, self.home.Y, self.goal.Z)
	local params = self:_params(playerRoot.Parent :: Model)
	local direct = goal - self.root.Position
	local obstructed = workspace:Blockcast(
		self.root.CFrame + Vector3.new(0, 0.3, 0),
		Vector3.new(3, 5.4, 2),
		direct,
		params
	) ~= nil
	local target = goal
	if obstructed then
		self:_path(goal, now)
		local route = self.route
		if route then
			while self.routeIndex <= #route do
				local waypoint = Vector3.new(
					route[self.routeIndex].Position.X,
					self.home.Y,
					route[self.routeIndex].Position.Z
				)
				if (waypoint - self.root.Position).Magnitude > 1 then
					target = waypoint
					break
				end
				self.routeIndex += 1
			end
		end
	end
	local direction = target - self.root.Position
	local speed = if self.state == "chase"
			and self.chaseStartedAt
			and now - self.chaseStartedAt >= self.balance.monster_chase_windup_sec
		then self.balance.monster_chase_speed
		else self.balance.monster_patrol_speed
	if direction.Magnitude > 0.05 then
		local step = direction.Unit * math.min(direction.Magnitude, speed * math.clamp(dt, 0, 0.25))
		local hit = workspace:Blockcast(
			self.root.CFrame + Vector3.new(0, 0.3, 0),
			Vector3.new(3, 5.4, 2),
			step,
			params
		)
		if not hit then
			local position = self.root.Position + step
			self.model:PivotTo(CFrame.lookAt(position, position + direction))
			self.blockedSince = nil
		else
			self.blockedSince = self.blockedSince or now
			if self.state == "patrol" and now - self.blockedSince > 2 then
				self.goal = nil
				self.route = nil
				self.blockedSince = nil
			end
		end
	end
	self.model:SetAttribute("TargetDistance", distance)
	return not protected and self:CanCapture(playerRoot, now), awakened
end

function MonsterHunt:Destroy()
	self.destroyed = true
	self.stunnedUntil = nil
	self.generation += 1
	for p, transparency in self.originalMarker do
		if p.Parent then
			p.Transparency = transparency
		end
	end
	self.model:Destroy()
	self.state = "stopped"
end

return MonsterHunt
