--!strict
-- EditableMesh content is peer-local; restores only explicitly owned decorative MeshParts.
local storage = game:GetService("ReplicatedStorage")
local run = game:GetService("RunService")
local world = game:GetService("Workspace")
local Geometry = require(
	storage:WaitForChild("GameShared"):WaitForChild("Game"):WaitForChild("HarvestArtGeometry")
)
local Controller = { Name = "HarvestGeometryController", Order = 45 }
local PROJECT, OWNER = "children_of_corn", "harvest_warden_v1"

function Controller:Init(context: any)
	self._enabled = run:IsStudio()
		and context.Config.Environment == "DEV"
		and (
			context.Config.Game.SessionMode == "solo_local"
			or context.Config.Game.SessionMode == "team_local"
		)
	self._connections, self._parts = {}, {}
	self._queued, self._running, self._pending = false, false, false
	self._lastError = nil
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

function Controller:_watch(part: Instance)
	if (not part:IsA("MeshPart") and not part:IsA("Folder")) or self._parts[part] then
		return
	end
	local connections = {}
	for _, name in { "HarvestGeometryOwner", "HarvestMeshKey", "corn_project_id" } do
		table.insert(
			connections,
			part:GetAttributeChangedSignal(name):Connect(function()
				self:_schedule()
			end)
		)
	end
	if part:IsA("MeshPart") then
		table.insert(
			connections,
			part:GetPropertyChangedSignal("MeshContent"):Connect(function()
				if not self._running then
					self:_schedule()
				end
			end)
		)
	end
	self._parts[part] = connections
end

function Controller:_ensure()
	self._running, self._pending = true, false
	local map = self._map
	local ok, problem = pcall(function()
		assert(
			map and map.Parent == world and map:GetAttribute("corn_project_id") == PROJECT,
			"Harvest client CornMap binding changed"
		)
		local root = map:FindFirstChild("HarvestDecor")
		local props = map:FindFirstChild("Props")
		local marker = props and props:FindFirstChild("ScarecrowMarker")
		local home = marker and marker:FindFirstChild("HarvestWardenHome")
		for _, visualRoot in { root, home } do
			if not visualRoot then
				continue
			end
			self:_watch(visualRoot)
			if
				visualRoot:GetAttribute("corn_project_id") == nil
				or visualRoot:GetAttribute("HarvestGeometryOwner") == nil
			then
				continue
			end
			assert(
				visualRoot:IsA("Folder")
					and visualRoot:GetAttribute("corn_project_id") == PROJECT
					and visualRoot:GetAttribute("HarvestGeometryOwner") == OWNER,
				"Foreign HarvestDecor preserved by client"
			)
			for _, part in visualRoot:GetDescendants() do
				if part:IsA("MeshPart") then
					self:_watch(part)
					local project, owner, key =
						part:GetAttribute("corn_project_id"),
						part:GetAttribute("HarvestGeometryOwner"),
						part:GetAttribute("HarvestMeshKey")
					-- Metadata can arrive after the replicated MeshPart; attribute events retry it.
					if project == nil or owner == nil or key == nil then
						continue
					end
					assert(
						project == PROJECT and owner == OWNER and type(key) == "string",
						"Foreign Harvest mesh preserved by client"
					)
					Geometry.Apply(part, key)
					if not self._enabled then
						return
					end
				end
			end
		end
	end)
	self._running = false
	if not ok then
		local message = "[HarvestGeometryController] " .. tostring(problem)
		if message ~= self._lastError then
			warn(message)
		end
		self._lastError = message
	else
		self._lastError = nil
	end
	if self._pending then
		self:_schedule()
	end
end

function Controller:Start()
	if not self._enabled then
		return
	end
	local map = world:WaitForChild("CornMap", 10)
	assert(
		map and map:IsA("Model") and map:GetAttribute("corn_project_id") == PROJECT,
		"Harvest client CornMap unavailable"
	)
	self._map = map
	table.insert(
		self._connections,
		map.DescendantAdded:Connect(function(item)
			local root = map:FindFirstChild("HarvestDecor")
			local props = map:FindFirstChild("Props")
			local marker = props and props:FindFirstChild("ScarecrowMarker")
			local home = marker and marker:FindFirstChild("HarvestWardenHome")
			if
				item.Name == "HarvestDecor"
				or item.Name == "HarvestWardenHome"
				or (root and item:IsDescendantOf(root))
				or (home and item:IsDescendantOf(home))
			then
				self:_watch(item)
				self:_schedule()
			end
		end)
	)
	table.insert(
		self._connections,
		map.DescendantRemoving:Connect(function(item)
			local connections = self._parts[item]
			if connections then
				for _, connection in connections do
					connection:Disconnect()
				end
				self._parts[item] = nil
			end
		end)
	)
	self:_schedule()
end

function Controller:Destroy()
	self._enabled = false
	for _, connection in self._connections do
		connection:Disconnect()
	end
	for _, connections in self._parts do
		for _, connection in connections do
			connection:Disconnect()
		end
	end
	self._connections, self._parts = {}, {}
end

return Controller
