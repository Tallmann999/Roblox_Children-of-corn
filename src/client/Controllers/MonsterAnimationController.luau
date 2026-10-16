--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Pose = require(
	ReplicatedStorage:WaitForChild("GameShared"):WaitForChild("Game"):WaitForChild("MonsterPose")
)

local Controller = { Name = "MonsterAnimationController", Order = 80 }
local PROJECT = "children_of_corn"
local UPDATE_SEC, RESOLVE_SEC = 1 / 30, 0.5
local sizes = {}
for _, definition in Pose.Parts do
	sizes[definition.Name] = definition.Size
end

local function disconnect(connections: { RBXScriptConnection })
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function decorative(part: Instance?): boolean
	return part ~= nil
		and part:IsA("BasePart")
		and part.Anchored
		and not part.CanCollide
		and not part.CanTouch
		and not part.CanQuery
end

function Controller:_restore()
	local root = self._root
	if not root then
		return
	end
	for name, part in self._parts do
		pcall(function()
			part.CFrame = root.CFrame * Pose.Rest[name]
			if self._wardenFallback then
				part.Transparency = 1
			end
		end)
	end
	if self._warden then
		self._warden:Step(root.CFrame, Pose.WardenRest, false, self._parts)
	end
	self._restored = true
end

function Controller:_unbindMonster()
	self._wardenGeneration += 1
	if self._warden then
		self._warden:Destroy()
		self._warden = nil
	end
	self:_restore()
	disconnect(self._monsterConnections)
	self._model, self._root, self._parts = nil, nil, {}
	self._harvestVariant = nil
	self._wardenBuildPending, self._wardenFallback = false, false
	self._wardenRetryAt, self._wardenError = 0, nil
	self._previousPosition, self._movingUntil = nil, 0
	self._state, self._stateAt, self._lastWrites = nil, self._time, 0
	self._lastArtWrites = 0
end

function Controller:_valid(): boolean
	local model, root, runtime, map = self._model, self._root, self._runtime, self._map
	if
		not map
		or map.Parent ~= Workspace
		or map:GetAttribute("corn_project_id") ~= PROJECT
		or not runtime
		or runtime.Parent ~= map
		or runtime:GetAttribute("corn_project_id") ~= PROJECT
		or not model
		or model.Parent ~= runtime
		or model.Name ~= (if self._monsterIndex == 1
			then "Monster"
			else "Monster" .. self._monsterIndex)
		or model:GetAttribute("MonsterIndex") ~= self._monsterIndex
		or model:GetAttribute("CornMonsterOwned") ~= true
		or model:GetAttribute("corn_project_id") ~= PROJECT
		or model:GetAttribute("MonsterRigVersion") ~= 1
		or not decorative(root)
		or root.Parent ~= model
		or model.PrimaryPart ~= root
	then
		return false
	end
	for name, part in self._parts do
		if
			part.Parent ~= model
			or part.Name ~= name
			or part.Size ~= sizes[name]
			or not decorative(part)
		then
			return false
		end
	end
	local variant = model:GetAttribute("HarvestArtVariant")
	local expectedVariant = if model:GetAttribute("HarvestWardenVersion") == 1
			and (variant == "A" or variant == "B")
		then variant
		else nil
	if expectedVariant ~= self._harvestVariant then
		return false
	end
	if self._warden and not self._warden:Valid() then
		return false
	end
	return true
end

function Controller:_createWarden(model: Model, root: BasePart)
	local variant = model:GetAttribute("HarvestArtVariant")
	if model:GetAttribute("HarvestWardenVersion") ~= 1 or (variant ~= "A" and variant ~= "B") then
		return
	end
	local generation = self._wardenGeneration
	self._wardenBuildPending = true
	task.spawn(function()
		local visual = nil
		local ok, problem = pcall(function()
			local shared = ReplicatedStorage:WaitForChild("GameShared"):WaitForChild("Game")
			local builder = require(shared:WaitForChild("HarvestArtGeometry"))
			local template =
				builder.Template(if variant == "B" then "WardenDetailed" else "WardenClassic")
			-- Mesh construction may yield. Never attach to a replaced round/streamed rig.
			if
				self._wardenGeneration ~= generation
				or self._model ~= model
				or not self:_valid()
			then
				return
			end
			local presentation = require(shared:WaitForChild("HarvestWardenVisual"))
			visual = presentation.new(template, root)
			if
				self._wardenGeneration ~= generation
				or self._model ~= model
				or not self:_valid()
			then
				visual:Destroy()
				return
			end
			self._warden = visual
			if self._wardenFallback then
				for _, part in self._parts do
					part.Transparency = 1
				end
			end
			self._wardenFallback, self._wardenError = false, nil
			self._restored = false
			self._updateElapsed = UPDATE_SEC
		end)
		if self._wardenGeneration ~= generation then
			return
		end
		self._wardenBuildPending = false
		if not ok then
			if visual then
				visual:Destroy()
			end
			self._wardenRetryAt = self._time + 5
			self._wardenFallback = true
			local message = "[MonsterAnimationController] Harvest Warden rendering failed; using legacy visual until retry: "
				.. tostring(problem)
			if self._wardenError ~= message then
				warn(message)
				self._wardenError = message
			end
		end
	end)
end

function Controller:_resolveMonster()
	local name = if self._monsterIndex == 1 then "Monster" else "Monster" .. self._monsterIndex
	local model = self._runtime and self._runtime:FindFirstChild(name)
	if model == self._model and self:_valid() then
		if
			self._harvestVariant
			and not self._warden
			and not self._wardenBuildPending
			and self._time >= self._wardenRetryAt
		then
			self:_createWarden(model, self._root)
		end
		return
	end
	self:_unbindMonster()
	if
		not model
		or not model:IsA("Model")
		or model:GetAttribute("MonsterIndex") ~= self._monsterIndex
		or model:GetAttribute("CornMonsterOwned") ~= true
		or model:GetAttribute("corn_project_id") ~= PROJECT
		or model:GetAttribute("MonsterRigVersion") ~= 1
	then
		return
	end
	local root = model:FindFirstChild("Root")
	if not decorative(root) or model.PrimaryPart ~= root then
		return
	end
	local parts, count = {}, 0
	for _, item in model:GetChildren() do
		if item ~= root then
			if
				not Pose.Rest[item.Name]
				or parts[item.Name]
				or item.Size ~= sizes[item.Name]
				or not decorative(item)
			then
				return
			end
			parts[item.Name], count = item, count + 1
		end
	end
	if count ~= #Pose.Parts then
		return
	end
	self._model, self._root, self._parts = model, root, parts
	local variant = model:GetAttribute("HarvestArtVariant")
	self._harvestVariant = if model:GetAttribute("HarvestWardenVersion") == 1
			and (variant == "A" or variant == "B")
		then variant
		else nil
	self._previousPosition = root.Position
	self._state, self._stateAt = model:GetAttribute("HuntState"), self._time
	self._restored = false
	self:_createWarden(model, root)
	local function topologyChanged()
		self:_unbindMonster()
	end
	table.insert(self._monsterConnections, model.ChildAdded:Connect(topologyChanged))
	table.insert(self._monsterConnections, model.ChildRemoved:Connect(topologyChanged))
	table.insert(
		self._monsterConnections,
		model.AncestryChanged:Connect(function()
			if not self:_valid() then
				self:_unbindMonster()
			end
		end)
	)
	for _, attribute in
		{
			"CornMonsterOwned",
			"corn_project_id",
			"MonsterRigVersion",
			"MonsterIndex",
			"HarvestWardenVersion",
			"HarvestArtVariant",
		}
	do
		table.insert(
			self._monsterConnections,
			model:GetAttributeChangedSignal(attribute):Connect(function()
				if not self:_valid() then
					self:_unbindMonster()
				end
			end)
		)
	end
	table.insert(
		self._monsterConnections,
		model:GetAttributeChangedSignal("HuntState"):Connect(function()
			self._state, self._stateAt = model:GetAttribute("HuntState"), self._time
			self._updateElapsed = UPDATE_SEC
			if
				self._state ~= "patrol"
				and self._state ~= "chase"
				and self._state ~= "trapped"
				and self._state ~= "capturing"
			then
				self:_restore()
			end
		end)
	)
end

function Controller:_clearRuntime()
	self:_unbindMonster()
	disconnect(self._runtimeConnections)
	self._runtime = nil
end

function Controller:_resolveRuntime()
	local runtime = self._map and self._map:FindFirstChild("CornRoundRuntime")
	if
		not runtime
		or not runtime:IsA("Folder")
		or runtime:GetAttribute("corn_project_id") ~= PROJECT
	then
		self:_clearRuntime()
		return
	end
	if runtime ~= self._runtime then
		self:_clearRuntime()
		self._runtime = runtime
		table.insert(
			self._runtimeConnections,
			runtime.ChildAdded:Connect(function(item)
				if
					item.Name
					== (
						if self._monsterIndex == 1
							then "Monster"
							else "Monster" .. self._monsterIndex
					)
				then
					self:_resolveMonster()
				end
			end)
		)
		table.insert(
			self._runtimeConnections,
			runtime.ChildRemoved:Connect(function(item)
				if item == self._model then
					self:_unbindMonster()
				end
			end)
		)
		table.insert(
			self._runtimeConnections,
			runtime.AncestryChanged:Connect(function()
				if runtime.Parent ~= self._map then
					self:_clearRuntime()
				end
			end)
		)
		table.insert(
			self._runtimeConnections,
			runtime:GetAttributeChangedSignal("corn_project_id"):Connect(function()
				if runtime:GetAttribute("corn_project_id") ~= PROJECT then
					self:_clearRuntime()
				end
			end)
		)
	end
	self:_resolveMonster()
end

function Controller:_clearMap()
	self:_clearRuntime()
	disconnect(self._mapConnections)
	self._map = nil
end

function Controller:_resolveMap()
	local map = Workspace:FindFirstChild("CornMap")
	if
		not map
		or not map:IsA("Model")
		or map:GetAttribute("corn_project_id") ~= PROJECT
		or Workspace:FindFirstChild("Asmr_Base")
		or Workspace:FindFirstChild("ASMR_Models")
	then
		self:_clearMap()
		return
	end
	if map ~= self._map then
		self:_clearMap()
		self._map = map
		table.insert(
			self._mapConnections,
			map.ChildAdded:Connect(function(item)
				if item.Name == "CornRoundRuntime" then
					self:_resolveRuntime()
				end
			end)
		)
		table.insert(
			self._mapConnections,
			map.ChildRemoved:Connect(function(item)
				if item == self._runtime then
					self:_clearRuntime()
				end
			end)
		)
		table.insert(
			self._mapConnections,
			map.AncestryChanged:Connect(function()
				if map.Parent ~= Workspace then
					self:_clearMap()
				end
			end)
		)
		table.insert(
			self._mapConnections,
			map:GetAttributeChangedSignal("corn_project_id"):Connect(function()
				if map:GetAttribute("corn_project_id") ~= PROJECT then
					self:_clearMap()
				end
			end)
		)
	end
	self:_resolveRuntime()
end

function Controller:_step(delta: number)
	self._time += math.clamp(delta, 0, 0.25)
	self._resolveElapsed += delta
	if self._resolveElapsed >= RESOLVE_SEC then
		self._resolveElapsed = 0
		self:_resolveMap()
	end
	self._updateElapsed += delta
	if self._updateElapsed < UPDATE_SEC or not self._model then
		return
	end
	self._updateElapsed %= UPDATE_SEC
	self._lastWrites = 0
	self._lastArtWrites = 0
	if not self:_valid() then
		self:_unbindMonster()
		return
	end
	local position = self._root.Position
	if self._previousPosition and (position - self._previousPosition).Magnitude > 0.015 then
		self._movingUntil = self._time + 0.15
	end
	self._previousPosition = position
	local pose = Pose.Get(self._state, self._time - self._stateAt, self._movingUntil > self._time)
	if pose == Pose.Rest and self._restored and not self._warden then
		return
	end
	local frame = self._root.CFrame
	local visible = self._state == "patrol"
		or self._state == "chase"
		or self._state == "trapped"
		or self._state == "capturing"
	for name, part in self._parts do
		part.CFrame = frame * pose[name]
		if self._wardenFallback then
			part.Transparency = if visible then 0 else 1
		end
		self._lastWrites += 1
	end
	if self._warden then
		self._lastArtWrites = self._warden:Step(
			frame,
			Pose.GetWarden(self._state, self._time - self._stateAt, self._movingUntil > self._time),
			visible,
			self._parts
		)
	end
	self._restored = pose == Pose.Rest
end

function Controller:Init(context: any, monsterIndex: number?)
	self._monsterIndex = monsterIndex or 1
	self._companions = {}
	self._enabled = RunService:IsStudio()
		and context.Config.Environment == "DEV"
		and (
			context.Config.Game.SessionMode == "solo_local"
			or context.Config.Game.SessionMode == "team_local"
		)
	self._map, self._runtime, self._model, self._root = nil, nil, nil, nil
	self._parts = {}
	self._warden, self._wardenGeneration = nil, 0
	self._wardenBuildPending, self._wardenFallback = false, false
	self._wardenRetryAt, self._wardenError = 0, nil
	self._topConnections, self._mapConnections, self._runtimeConnections, self._monsterConnections =
		{}, {}, {}, {}
	self._time, self._stateAt, self._movingUntil, self._lastWrites = 0, 0, 0, 0
	self._lastArtWrites = 0
	self._updateElapsed, self._resolveElapsed = UPDATE_SEC, RESOLVE_SEC
	self._state, self._previousPosition, self._restored = nil, nil, true
	self._connection = nil
	if monsterIndex == nil then
		-- Reuse the same guarded lifecycle independently for exactly three rigs.
		for index = 2, 3 do
			-- Bootstrap initializes this Module table itself. A __index pointing
			-- at it would inherit its later _connection and skip companion Start.
			local companion = table.clone(Controller)
			companion:Init(context, index)
			table.insert(self._companions, companion)
		end
	end
end

function Controller:Start()
	if not self._enabled or self._connection then
		return
	end
	self:_resolveMap()
	table.insert(
		self._topConnections,
		Workspace.ChildAdded:Connect(function(item)
			if item.Name == "CornMap" then
				self:_resolveMap()
			end
		end)
	)
	table.insert(
		self._topConnections,
		Workspace.ChildRemoved:Connect(function(item)
			if item == self._map then
				self:_clearMap()
			end
		end)
	)
	self._connection = RunService.Heartbeat:Connect(function(delta)
		self:_step(delta)
	end)
	for _, companion in self._companions do
		companion:Start()
	end
end

function Controller:Destroy()
	for _, companion in self._companions do
		companion:Destroy()
	end
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	self:_clearMap()
	disconnect(self._topConnections)
	self._enabled = false
end

return Controller
