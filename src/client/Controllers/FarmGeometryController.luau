--!strict
local storage = game:GetService("ReplicatedStorage")
local run = game:GetService("RunService")
local world = game:GetService("Workspace")
local Builder = require(
	storage:WaitForChild("GameShared"):WaitForChild("Game"):WaitForChild("FarmEditableMeshBuilder")
)
local Controller = { Name = "FarmGeometryController", Order = 40 }
local PROJECT = "children_of_corn"
function Controller:Init(context: any)
	self._enabled = run:IsStudio()
		and context.Config.Environment == "DEV"
		and context.Config.Game.SessionMode == "solo_local"
	self._runtime = Builder.newRuntime("client")
	self._connections = {}
	self._parts = {}
	self._running = false
	self._queued = false
	self._pending = false
	self._started = false
	self._map = nil
	self._props = nil
	self._lastError = nil
end
function Controller:_status(status: string, pending: number, problem: string?)
	local map = self._map
	if not map or map.Parent ~= world or map:GetAttribute("corn_project_id") ~= PROJECT then
		return
	end
	map:SetAttribute("CornFarmGeometryStatus", status)
	map:SetAttribute("CornFarmGeometryPending", pending)
	map:SetAttribute("CornFarmGeometryError", if problem then problem:sub(1, 1200) else "")
end
function Controller:_schedule()
	if not self._enabled then
		return
	end
	if self._running then
		self._pending = true
		return
	end
	if self._queued then
		return
	end
	self._queued = true
	task.defer(function()
		self._queued = false
		if self._enabled then
			self:_ensure()
		end
	end)
end
function Controller:_watch(item: Instance): boolean
	if self._parts[item] then
		return true
	end
	local isModel = item:IsA("Model") and item.Parent == self._props
	local model = if isModel then item else item.Parent
	if
		not model
		or (not isModel and (not item:IsA("MeshPart") or model.Parent ~= self._props))
		or not (
			model:GetAttribute("CornFarmAssetOwned") == true or Builder.AssetKeyForName(model.Name)
		)
	then
		return false
	end
	local connections = {}
	local attributes = if isModel
		then { "CornFarmAssetOwned", "corn_project_id", "AssetKey" }
		else { "CornFarmMeshOwned", "corn_project_id", "AssetKey", "MeshIndex" }
	for _, attribute in attributes do
		table.insert(
			connections,
			item:GetAttributeChangedSignal(attribute):Connect(function()
				self:_schedule()
			end)
		)
	end
	if isModel then
		table.insert(
			connections,
			item:GetPropertyChangedSignal("Name"):Connect(function()
				self:_schedule()
			end)
		)
	else
		table.insert(
			connections,
			item:GetPropertyChangedSignal("MeshContent"):Connect(function()
				-- ApplyMesh and rollback also fire this signal. During Ensure, current
				-- server content is captured after construction; our own writes need no retry.
				if not self._running then
					self:_schedule()
				end
			end)
		)
	end
	self._parts[item] = connections
	return true
end
function Controller:_bind()
	if self._props then
		return
	end
	local map = world:WaitForChild("CornMap", 10)
	self._map = map
	local props = map and map:WaitForChild("Props", 10)
	assert(props and props:IsA("Folder"), "Farm geometry client Props unavailable")
	if not self._enabled then
		return
	end
	self._props = props
	table.insert(
		self._connections,
		props.DescendantAdded:Connect(function(item)
			if self:_watch(item) or item:GetAttribute("CornFarmMeshOwned") == true then
				self:_schedule()
			end
		end)
	)
	table.insert(
		self._connections,
		props.DescendantRemoving:Connect(function(item)
			local connections = self._parts[item]
			if connections then
				for _, connection in connections do
					connection:Disconnect()
				end
				self._parts[item] = nil
				self:_schedule()
			end
		end)
	)
	for _, item in props:GetDescendants() do
		self:_watch(item)
	end
end
function Controller:_ensure()
	if not self._enabled then
		return
	end
	self._running = true
	self._pending = false
	local ok, result = pcall(function()
		self:_bind()
		if not self._enabled then
			return nil
		end
		self:_status("building", 0)
		return self._runtime:Ensure()
	end)
	self._running = false
	if not self._enabled then
		return
	end
	if not ok then
		local problem = "[FarmGeometryController] local rendering restoration failed: "
			.. tostring(result)
		self:_status("error", 0, problem)
		if self._lastError ~= problem then
			warn(problem)
		end
		self._lastError = problem
	else
		self._lastError = nil
		self:_status(if result.pending > 0 then "waiting" else "ready", result.pending)
	end
	if self._pending then
		self:_schedule()
	end
end
function Controller:Start()
	if not self._enabled or self._started then
		return
	end
	self._started = true
	-- Streaming and EditableMesh allocation must not interrupt other controllers.
	self:_schedule()
end
function Controller:Destroy()
	self._enabled = false
	self:_status("stopped", 0)
	for _, connection in self._connections do
		connection:Disconnect()
	end
	for _, connections in self._parts do
		for _, connection in connections do
			connection:Disconnect()
		end
	end
	self._connections = {}
	self._parts = {}
	self._runtime:Destroy()
end
return Controller
