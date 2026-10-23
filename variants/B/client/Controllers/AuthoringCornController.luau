--!strict
-- Edit placements are the B map source. Missing plants are never regenerated.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local modules = ReplicatedStorage:WaitForChild("GameShared"):WaitForChild("Game")
local Layout = require(modules:WaitForChild("CornLayout"))
local Appearance = require(modules:WaitForChild("CornAppearance"))
local Controller = { Name = "AuthoringCornController", Order = 46 }
local PROJECT, OWNER = "children_of_corn", "corn_B_manual_authoring_v1"
local CLONE_BUDGET, TIME_BUDGET = 18, 0.002
local INDEX_BUDGET, INDEX_TIME = 512, 0.002
local NEAR_CAP, FAR_CAP, RECORD_CAP = 8064, 30000, 100000
local DENSE_RADIUS, RADIUS, RETAIN = 60, 130, 148

local function finite(value)
	return value == value and value > -math.huge and value < math.huge
end

local function validSize(size)
	return finite(size.X)
		and finite(size.Y)
		and finite(size.Z)
		and size.X > 0
		and size.Y > 0
		and size.Z > 0
end

local function validFrame(frame)
	for _, value in { frame:GetComponents() } do
		if not finite(value) then
			return false
		end
	end
	return true
end

local function target()
	local map = Workspace:FindFirstChild("CornMap")
	local source = Layout.AuthoringSource(map)
	local field = map and map:FindFirstChild("FieldZone")
	if
		map
		and map:IsA("Model")
		and map:GetAttribute("corn_project_id") == PROJECT
		and map:GetAttribute("HarvestArtVariant") == "B"
		and map:GetAttribute("BManualAuthoringVersion") == 1
		and source
		and source:IsA("Folder")
		and source:GetAttribute("corn_project_id") == PROJECT
		and source:GetAttribute("BManualAuthoringVersion") == 1
		and source:GetAttribute("BManualServerReady") == true
		and field
		and field:IsA("BasePart")
		and validFrame(field.CFrame)
	then
		return map, source, field
	end
	return nil, nil, nil
end

local function stamp(item)
	item:SetAttribute("corn_project_id", PROJECT)
	item:SetAttribute("BManualCornRuntimeOwner", OWNER)
end

local function ownedTree(root)
	if root:GetAttribute("BManualCornRuntimeOwner") ~= OWNER then
		return false
	end
	for _, item in root:GetDescendants() do
		if item:GetAttribute("BManualCornRuntimeOwner") ~= OWNER then
			return false
		end
	end
	return true
end

function Controller:_warn(message)
	if self._warning ~= message then
		self._warning = message
		warn("[AuthoringCornController] " .. message)
	end
end

function Controller:_clear(restoreSources)
	self._epoch += 1
	for _, connection in self._sourceConnections or {} do
		connection:Disconnect()
	end
	self._sourceConnections = {}
	for part, previous in self._hidden do
		if part.Parent and part.LocalTransparencyModifier == 1 then
			part.LocalTransparencyModifier = previous
		end
	end
	table.clear(self._hidden)
	if restoreSources ~= false and self._source and self._source:IsDescendantOf(Workspace) then
		for _, part in self._source:GetDescendants() do
			if part:IsA("MeshPart") then
				local opacity = part:GetAttribute("BManualSourceTransparency")
				-- The server owns only its one startup write of exactly one.
				if
					type(opacity) == "number"
					and finite(opacity)
					and opacity >= 0
					and opacity <= 1
					and part.Transparency == 1
				then
					part.Transparency = opacity
				end
			end
		end
	end
	for _, folder in { self._nearFolder, self._farFolder } do
		if folder and folder.Parent then
			if folder:GetAttribute("BManualCornRuntimeOwner") == OWNER then
				folder:SetAttribute("Ready", false)
			end
			if ownedTree(folder) then
				folder:Destroy()
			else
				self:_warn("Foreign runtime content was preserved; author placements restored")
			end
		end
	end
	self._map, self._source, self._field = nil, nil, nil
	self._nearFolder, self._farFolder = nil, nil
	self._nodes, self._templates = nil, nil
	self._records, self._buckets, self._far, self._chunks = {}, {}, {}, {}
	self._nearByRecord, self._queue = {}, {}
	self._nearCount, self._farIndex, self._index = 0, 1, 1
	self._ready, self._preparing = false, false
	self._waiting, self._dirty, self._quiet, self._settleAge = false, false, 0, 0
end

function Controller:_begin(map, source, field)
	self:_clear(false)
	assert(
		not map:FindFirstChild("CornClientPlants") and not map:FindFirstChild("CornClientBackdrop"),
		"Existing runtime layers were preserved"
	)
	self._map, self._source, self._field = map, source, field
	self._fieldFrame, self._fieldSize = field.CFrame, field.Size
	self._width = Layout.SpacingFor(field) * Layout.ChunkCells
	assert(finite(self._width) and self._width > 0, "Invalid authored corn chunk width")
	self._waiting, self._quiet, self._settleAge = true, 0, 0
	local function changed()
		if self._source == source then
			if not self._dirty then
				self._settleAge = 0
			end
			self._dirty, self._quiet = true, 0
		end
	end
	self._sourceConnections = {
		source.DescendantAdded:Connect(changed),
		source.DescendantRemoving:Connect(changed),
	}
	self._preparing = true
	local epoch = self._epoch
	task.spawn(function()
		local ok, templates = pcall(Appearance.DetailedTemplates)
		if self._epoch ~= epoch then
			return
		end
		self._preparing = false
		if ok then
			self._templates = templates
		else
			self._failedSource = source
			self:_clear()
			self:_warn("Authored corn retained: " .. tostring(templates))
		end
	end)
end

function Controller:_startSnapshot()
	self._nodes = self._source:GetDescendants()
	assert(#self._nodes <= RECORD_CAP + 10000, "Authoring snapshot exceeds its bounded inventory")
	self._waiting, self._dirty, self._index, self._settleAge = false, false, 1, 0
end

function Controller:_record(part)
	local transparency = part:GetAttribute("BManualSourceTransparency")
	if type(transparency) ~= "number" then
		transparency = part.Transparency
	end
	assert(
		finite(transparency) and transparency >= 0 and transparency <= 1,
		"Authored plant transparency is invalid"
	)
	if transparency >= 1 then
		return
	end
	local variety = part:GetAttribute("CornGreenVariety")
	local offset, templateSize =
		part:GetAttribute("HarvestRootOffset"), part:GetAttribute("CornGreenTemplateSize")
	assert(
		type(variety) == "number" and variety % 1 == 0 and variety >= 1 and variety <= 4,
		"Authored plant needs CornGreenVariety 1..4"
	)
	assert(
		typeof(offset) == "Vector3"
			and finite(offset.X)
			and finite(offset.Y)
			and finite(offset.Z)
			and typeof(templateSize) == "Vector3"
			and validSize(templateSize)
			and validSize(part.Size)
			and validFrame(part.CFrame)
			and #part:GetChildren() == 0,
		"Authored plant has invalid geometry metadata or foreign children"
	)
	assert(
		part.Anchored and not part.CanCollide and not part.CanTouch and not part.CanQuery,
		"Authored corn must remain static decorative art"
	)
	assert(#self._records < RECORD_CAP, "Authored corn record cap exceeded")
	local size, frame = part.Size, part.CFrame
	local scaled = Vector3.new(
		offset.X * size.X / templateSize.X,
		offset.Y * size.Y / templateSize.Y,
		offset.Z * size.Z / templateSize.Z
	)
	local root = frame:PointToWorldSpace(-scaled)
	local localRoot = self._fieldFrame:PointToObjectSpace(root)
	local spacing = Layout.SpacingFor(self._field)
	local column, row = part:GetAttribute("CornAuthorColumn"), part:GetAttribute("CornAuthorRow")
	if type(column) ~= "number" or not finite(column) or column % 1 ~= 0 then
		column = math.floor(localRoot.X / spacing + 0.5)
	end
	if type(row) ~= "number" or not finite(row) or row % 1 ~= 0 then
		row = math.floor(localRoot.Z / spacing + 0.5)
	end
	local record = {
		Source = part,
		Frame = frame,
		Size = size,
		Variety = variety,
		Root = root,
		Column = column,
		Row = row,
		Index = #self._records + 1,
		Transparency = transparency,
	}
	table.insert(self._records, record)
	local x, z = math.floor(localRoot.X / self._width), math.floor(localRoot.Z / self._width)
	local key = x .. ":" .. z
	local bucket = self._buckets[key]
	if not bucket then
		bucket = { Key = key, X = x, Z = z, Records = {} }
		self._buckets[key] = bucket
	end
	table.insert(bucket.Records, record)
	if column % 2 == 0 and row % 2 == 0 then
		assert(#self._far < FAR_CAP, "Authored stride-two backdrop exceeds 30000 plants")
		table.insert(self._far, record)
	end
end

function Controller:_hide(part)
	if self._hidden[part] == nil then
		self._hidden[part] = part.LocalTransparencyModifier
		part.LocalTransparencyModifier = 1
	end
end

function Controller:_publishSnapshot()
	local map = self._map
	assert(
		not map:FindFirstChild("CornClientPlants") and not map:FindFirstChild("CornClientBackdrop"),
		"Existing runtime layers were preserved"
	)
	local near, far = Instance.new("Folder"), Instance.new("Folder")
	near.Name, far.Name = "CornClientPlants", "CornClientBackdrop"
	stamp(near)
	stamp(far)
	near:SetAttribute("CornClientRendererOwned", true)
	far:SetAttribute("CornClientBackdropOwned", true)
	far:SetAttribute("CornEditorOverview", true)
	far:SetAttribute("Ready", false)
	far:SetAttribute("DetailStride", Layout.SpacingFor(self._field) * 2)
	far:SetAttribute("MaxPlants", FAR_CAP)
	near:SetAttribute("NearPlantCap", NEAR_CAP)
	near:SetAttribute("LoadedPlants", 0)
	far:SetAttribute("LoadedPlants", 0)
	self._nearFolder, self._farFolder = near, far
	near.Parent, far.Parent = map, map
	if not self._source:IsDescendantOf(ReplicatedStorage) then
		for _, record in self._records do
			if record.Source.Transparency < 1 then
				self:_hide(record.Source)
			end
		end
	end
	for _, name in { "EditorPreview", "EditorFieldOverview" } do
		local folder = map:FindFirstChild(name)
		local attribute = if name == "EditorPreview"
			then "CornEditorPreview"
			else "CornEditorOverview"
		if
			folder
			and folder:GetAttribute("corn_project_id") == PROJECT
			and folder:GetAttribute(attribute) == true
		then
			for _, part in folder:GetDescendants() do
				if
					part:IsA("BasePart")
					and part:GetAttribute("corn_project_id") == PROJECT
					and part:GetAttribute(attribute) == true
				then
					self:_hide(part)
				end
			end
		end
	end
	self._nodes, self._ready = nil, true
	near:SetAttribute("AuthoredPlants", #self._records)
	self._reconcileElapsed = math.huge
end

function Controller:_indexBatch()
	if self._preparing or not self._templates or not self._nodes then
		return
	end
	local began, count = self._clock(), 0
	while
		self._index <= #self._nodes
		and count < INDEX_BUDGET
		and self._clock() - began < INDEX_TIME
	do
		local item = self._nodes[self._index]
		self._index += 1
		count += 1
		assert(item:IsDescendantOf(self._source), "Authoring inventory changed during snapshot")
		if item:IsA("MeshPart") then
			self:_record(item)
		else
			assert(
				item:IsA("Model") or item:IsA("Folder"),
				"Foreign authoring contents were preserved"
			)
		end
	end
	if self._index > #self._nodes then
		self:_publishSnapshot()
	end
end

function Controller:_dropChunk(chunk)
	for _, record in chunk.Records do
		if self._nearByRecord[record] then
			self._nearByRecord[record] = nil
			self._nearCount -= 1
			if record.FarPart and record.FarPart.Parent == self._farFolder then
				record.FarPart.LocalTransparencyModifier = 0
			end
		end
	end
	if ownedTree(chunk.Folder) then
		chunk.Folder:Destroy()
	else
		error("Foreign near chunk content was preserved")
	end
	self._chunks[chunk.Key] = nil
end

function Controller:_reconcile()
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local point = self._fieldFrame:PointToObjectSpace(root.CFrame.Position)
	local desired = {}
	for x = math.floor((point.X - RETAIN) / self._width), math.floor((point.X + RETAIN) / self._width) do
		for z = math.floor((point.Z - RETAIN) / self._width), math.floor((point.Z + RETAIN) / self._width) do
			local key = x .. ":" .. z
			local bucket = self._buckets[key]
			local distance = ((x + 0.5) * self._width - point.X) ^ 2
				+ ((z + 0.5) * self._width - point.Z) ^ 2
			if bucket and distance <= (if self._chunks[key] then RETAIN else RADIUS) ^ 2 then
				table.insert(desired, { Bucket = bucket, Distance = distance })
			end
		end
	end
	table.sort(desired, function(a, b)
		return if a.Distance == b.Distance
			then a.Bucket.Key < b.Bucket.Key
			else a.Distance < b.Distance
	end)
	local wanted = {}
	for index, candidate in desired do
		if index > 200 then
			break
		end
		local bucket = candidate.Bucket
		wanted[bucket.Key] = true
		local chunk = self._chunks[bucket.Key]
		local denseRadius = if chunk and chunk.Stride == 1
			then DENSE_RADIUS + 12
			elseif chunk then DENSE_RADIUS - 12
			else DENSE_RADIUS
		local stride = if candidate.Distance <= denseRadius ^ 2 then 1 else 2
		if chunk and chunk.Stride ~= stride then
			self:_dropChunk(chunk)
			chunk = nil
		end
		if not chunk then
			local folder = Instance.new("Folder")
			folder.Name = "Chunk_" .. bucket.Key
			stamp(folder)
			folder.Parent = self._nearFolder
			chunk = {
				Key = bucket.Key,
				Folder = folder,
				Records = bucket.Records,
				Index = 1,
				Stride = stride,
				Lod = if index <= 8 then "Near" else "Mid",
			}
			self._chunks[bucket.Key] = chunk
		end
		chunk.Distance = candidate.Distance
	end
	local removals = {}
	for key, chunk in self._chunks do
		if not wanted[key] then
			table.insert(removals, chunk)
		end
	end
	for _, chunk in removals do
		self:_dropChunk(chunk)
	end
	self._queue = {}
	for _, chunk in self._chunks do
		if chunk.Index <= #chunk.Records then
			table.insert(self._queue, chunk)
		end
	end
	table.sort(self._queue, function(a, b)
		return a.Distance < b.Distance
	end)
end

function Controller:_clone(record, lod)
	local plant =
		assert(self._templates[lod][record.Variety]:Clone(), "Authored corn template clone failed")
	plant.Size, plant.CFrame = record.Size, record.Frame
	plant.Transparency, plant.CastShadow = record.Transparency, true
	plant:SetAttribute("BManualSourceTransparency", nil)
	stamp(plant)
	return plant
end

function Controller:_buildBatch()
	if not self._ready then
		return
	end
	local began, created, examined = self._clock(), 0, 0
	while created < CLONE_BUDGET and examined < 100 and self._clock() - began < TIME_BUDGET do
		examined += 1
		local chunk = self._queue[1]
		if chunk and self._nearCount < NEAR_CAP then
			local record = chunk.Records[chunk.Index]
			chunk.Index += 1
			if chunk.Index > #chunk.Records then
				table.remove(self._queue, 1)
			end
			if record.Column % chunk.Stride ~= 0 or record.Row % chunk.Stride ~= 0 then
				continue
			end
			local plant = self:_clone(record, chunk.Lod)
			plant.Name, plant.Parent = "Corn", chunk.Folder
			self._nearByRecord[record] = plant
			self._nearCount += 1
			if record.FarPart then
				record.FarPart.LocalTransparencyModifier = 1
			end
		elseif self._farIndex <= #self._far then
			local record = self._far[self._farIndex]
			self._farIndex += 1
			local plant = self:_clone(record, "Far")
			plant.Name = "Far_" .. record.Index .. "_0"
			plant:SetAttribute("CornClientBackdropOwned", true)
			plant:SetAttribute("CornEditorOverview", true)
			plant:SetAttribute("CornPlantTemplateOwned", nil)
			plant.LocalTransparencyModifier = if self._nearByRecord[record] then 1 else 0
			plant.Parent, record.FarPart = self._farFolder, plant
		else
			break
		end
		created += 1
	end
	self._nearFolder:SetAttribute("LoadedPlants", self._nearCount)
	self._farFolder:SetAttribute("LoadedPlants", self._farIndex - 1)
	self._farFolder:SetAttribute("LastFrameClones", created)
	self._farFolder:SetAttribute("LastFrameSeconds", self._clock() - began)
	if self._farIndex > #self._far then
		self._farFolder:SetAttribute("Ready", true)
	end
end

function Controller:_step(delta)
	self._poll += delta
	if self._poll >= 0.5 then
		self._poll = 0
		local map, source, field = target()
		if map ~= self._map or source ~= self._source or field ~= self._field then
			if source and source ~= self._failedSource then
				self:_begin(map, source, field)
			else
				self:_clear()
			end
		end
	end
	if not self._map then
		return
	end
	local map, source, field = target()
	assert(
		map == self._map
			and source == self._source
			and field == self._field
			and field.CFrame == self._fieldFrame
			and field.Size == self._fieldSize,
		"Authoring ownership or field changed; saved placements restored"
	)
	self._quiet += delta
	self._settleAge += delta
	if (self._waiting or self._dirty) and (self._quiet >= 0.75 or self._settleAge >= 10) then
		if self._waiting then
			self:_startSnapshot()
		else
			self:_begin(map, source, field)
			self._quiet = 0.75
		end
	end
	if self._ready then
		assert(
			self._nearFolder.Parent == map
				and self._farFolder.Parent == map
				and self._nearFolder:GetAttribute("BManualCornRuntimeOwner") == OWNER
				and self._farFolder:GetAttribute("BManualCornRuntimeOwner") == OWNER,
			"Runtime ownership changed; author placements restored"
		)
	end
	self:_indexBatch()
	if self._ready then
		self._reconcileElapsed += delta
		if self._reconcileElapsed >= 0.3 then
			self._reconcileElapsed = 0
			self:_reconcile()
		end
		self:_buildBatch()
	end
end

function Controller:Init(context)
	self._enabled = RunService:IsStudio()
		and context.Config.Environment == "DEV"
		and (
			context.Config.Game.SessionMode == "solo_local"
			or context.Config.Game.SessionMode == "team_local"
		)
	self._epoch, self._hidden = 0, {}
	self._clock, self._poll, self._reconcileElapsed = os.clock, math.huge, math.huge
	self:_clear()
end

function Controller:Start()
	if not self._enabled or self._connection then
		return
	end
	self._connection = RunService.Heartbeat:Connect(function(delta)
		local ok, problem = pcall(self._step, self, delta)
		if not ok then
			self._failedSource = self._source
			self:_clear()
			self:_warn("Authored scene preserved: " .. tostring(problem))
		end
	end)
end

function Controller:Destroy()
	self._enabled = false
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	self:_clear()
end

return Controller
