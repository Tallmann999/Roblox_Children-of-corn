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
		end)
	end
	self._restored = true
end

function Controller:_unbindMonster()
	self:_restore()
	disconnect(self._monsterConnections)
	self._model, self._root, self._parts = nil, nil, {}
	self._previousPosition, self._movingUntil = nil, 0
	self._state, self._stateAt, self._lastWrites = nil, self._time, 0
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
		if part.Parent ~= model or part.Name ~= name or not decorative(part) then
			return false
		end
	end
	return true
end

function Controller:_resolveMonster()
	local model = self._runtime and self._runtime:FindFirstChild("Monster")
	if model == self._model and self:_valid() then
		return
	end
	self:_unbindMonster()
	if
		not model
		or not model:IsA("Model")
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
			if not Pose.Rest[item.Name] or parts[item.Name] or not decorative(item) then
				return
			end
			parts[item.Name], count = item, count + 1
		end
	end
	if count ~= #Pose.Parts then
		return
	end
	self._model, self._root, self._parts = model, root, parts
	self._previousPosition = root.Position
	self._state, self._stateAt = model:GetAttribute("HuntState"), self._time
	self._restored = false
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
	for _, attribute in { "CornMonsterOwned", "corn_project_id", "MonsterRigVersion" } do
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
				if item.Name == "Monster" then
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
	if pose == Pose.Rest and self._restored then
		return
	end
	local frame = self._root.CFrame
	for name, part in self._parts do
		part.CFrame = frame * pose[name]
		self._lastWrites += 1
	end
	self._restored = pose == Pose.Rest
end

function Controller:Init(context: any)
	self._enabled = RunService:IsStudio()
		and context.Config.Environment == "DEV"
		and context.Config.Game.SessionMode == "solo_local"
	self._map, self._runtime, self._model, self._root = nil, nil, nil, nil
	self._parts = {}
	self._topConnections, self._mapConnections, self._runtimeConnections, self._monsterConnections =
		{}, {}, {}, {}
	self._time, self._stateAt, self._movingUntil, self._lastWrites = 0, 0, 0, 0
	self._updateElapsed, self._resolveElapsed = UPDATE_SEC, RESOLVE_SEC
	self._state, self._previousPosition, self._restored = nil, nil, true
	self._connection = nil
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
end

function Controller:Destroy()
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	self:_clearMap()
	disconnect(self._topConnections)
	self._enabled = false
end

return Controller
