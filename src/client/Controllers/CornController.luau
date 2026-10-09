--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameShared = ReplicatedStorage:WaitForChild("GameShared")
local CornLayout = require(GameShared:WaitForChild("Game"):WaitForChild("CornLayout"))

type Chunk = {
	Key: string,
	Folder: Folder,
	MinColumn: number,
	MaxColumn: number,
	MinRow: number,
	MaxRow: number,
	Column: number,
	Row: number,
	Distance: number,
	Count: number,
	Alive: boolean,
	Done: boolean,
}

type OverviewItem = {
	Part: BasePart,
	PreviousModifier: number,
	Frame: CFrame,
	Size: Vector3,
	Keys: { string },
	Hidden: boolean,
}

local CornController = {
	Name = "CornController",
	Order = 50,
	_enabled = false,
	_connection = nil :: RBXScriptConnection?,
	_map = nil :: Model?,
	_field = nil :: BasePart?,
	_template = nil :: CornLayout.Plant?,
	_folder = nil :: Folder?,
	_chunks = {} :: { [string]: Chunk },
	_queue = {} :: { Chunk },
	_exclusions = nil :: CornLayout.Exclusions?,
	_pivotOffset = CFrame.identity,
	_height = CornLayout.Height,
	_pollElapsed = math.huge,
	_plantCount = 0,
	_lastWarning = "",
	_overviewFolder = nil :: Folder?,
	_overviewParts = {} :: { [BasePart]: OverviewItem },
	_overviewByChunk = {} :: { [string]: { OverviewItem } },
	_overviewDirty = {} :: { [OverviewItem]: boolean },
	_overviewFieldFrame = CFrame.identity,
	_overviewFieldSize = Vector3.zero,
}

local PROJECT_ID = "children_of_corn"
local POLL_SEC = 0.3
local CREATE_BUDGET = 18
local CELL_BUDGET = 100
local TIME_BUDGET_SEC = 0.003
local MAX_CHUNKS = 28

function CornController:_warn(message: string)
	if self._lastWarning ~= message then
		self._lastWarning = message
		warn("[CornController] " .. message)
	end
end

local function overviewKeys(field: BasePart, part: BasePart): { string }
	local relative = field.CFrame:ToObjectSpace(part.CFrame)
	local half = part.Size / 2
	-- Require completed fine groups across the entire rotated coarse footprint.
	-- The margin also covers the small deterministic cell stagger.
	local padding = CornLayout.Spacing * 0.75
	local halfX = math.abs(relative.RightVector.X) * half.X
		+ math.abs(relative.UpVector.X) * half.Y
		+ math.abs(relative.LookVector.X) * half.Z
		+ padding
	local halfZ = math.abs(relative.RightVector.Z) * half.X
		+ math.abs(relative.UpVector.Z) * half.Y
		+ math.abs(relative.LookVector.Z) * half.Z
		+ padding
	local fieldHalf = field.Size / 2
	local minX = math.max(relative.Position.X - halfX, -fieldHalf.X)
	local maxX = math.min(relative.Position.X + halfX, fieldHalf.X)
	local minZ = math.max(relative.Position.Z - halfZ, -fieldHalf.Z)
	local maxZ = math.min(relative.Position.Z + halfZ, fieldHalf.Z)
	local keys: { string } = {}
	if minX > maxX or minZ > maxZ then
		return keys
	end
	local width = CornLayout.Spacing * CornLayout.ChunkCells
	local offset = CornLayout.Spacing / 2
	for column = math.floor((minX + offset) / width), math.floor((maxX + offset) / width) do
		for row = math.floor((minZ + offset) / width), math.floor((maxZ + offset) / width) do
			table.insert(keys, column .. ":" .. row)
		end
	end
	return keys
end

function CornController:_showOverview()
	for _, entry in self._overviewParts do
		if entry.Hidden then
			if entry.Part.Parent then
				entry.Part.LocalTransparencyModifier = entry.PreviousModifier
			end
			entry.Hidden = false
		end
	end
	self._overviewDirty = {}
end

function CornController:_restoreOverview()
	self:_showOverview()
	self._overviewFolder = nil
	self._overviewParts = {}
	self._overviewByChunk = {}
end

function CornController:_markOverviewChunk(key: string)
	for _, entry in self._overviewByChunk[key] or {} do
		self._overviewDirty[entry] = true
	end
end

function CornController:_bindOverview()
	local map = self._map
	local field = self._field
	local folder = if map then map:FindFirstChild("EditorFieldOverview") else nil
	if not folder then
		self:_restoreOverview()
		return
	end
	if
		not field
		or not folder:IsA("Folder")
		or folder:GetAttribute("CornEditorOverview") ~= true
		or folder:GetAttribute("corn_project_id") ~= PROJECT_ID
	then
		self:_restoreOverview()
		self:_warn("Unrecognized EditorFieldOverview is preserved")
		return
	end
	local children = folder:GetChildren()
	local cachedCount = 0
	for _ in self._overviewParts do
		cachedCount += 1
	end
	local reusable = self._overviewFolder == folder
		and self._overviewFieldFrame == field.CFrame
		and self._overviewFieldSize == field.Size
		and cachedCount == #children
	-- Validate the whole container before any local visibility changes.
	for _, item in children do
		if
			not item:IsA("BasePart")
			or item:GetAttribute("CornEditorOverview") ~= true
			or item:GetAttribute("corn_project_id") ~= PROJECT_ID
		then
			self:_restoreOverview()
			self:_warn("EditorFieldOverview contains unowned objects; all were preserved")
			return
		end
		local previous = self._overviewParts[item]
		if not previous or previous.Frame ~= item.CFrame or previous.Size ~= item.Size then
			reusable = false
		end
	end
	if reusable then
		return
	end
	self:_restoreOverview()
	self._overviewFolder = folder
	self._overviewFieldFrame = field.CFrame
	self._overviewFieldSize = field.Size
	for _, item in children do
		local part = item :: BasePart
		local entry: OverviewItem = {
			Part = part,
			PreviousModifier = part.LocalTransparencyModifier,
			Frame = part.CFrame,
			Size = part.Size,
			Keys = overviewKeys(field, part),
			Hidden = false,
		}
		self._overviewParts[part] = entry
		for _, key in entry.Keys do
			local items = self._overviewByChunk[key]
			if not items then
				items = {}
				self._overviewByChunk[key] = items
			end
			table.insert(items, entry)
		end
	end
	for key, chunk in self._chunks do
		if chunk.Done then
			self:_markOverviewChunk(key)
		end
	end
end

function CornController:_updateOverview()
	local folder = self._overviewFolder
	if not folder then
		return
	end
	if
		folder:GetAttribute("CornEditorOverview") ~= true
		or folder:GetAttribute("corn_project_id") ~= PROJECT_ID
	then
		self:_restoreOverview()
		return
	end
	for entry in self._overviewDirty do
		local part = entry.Part
		if
			part.Parent ~= folder
			or part:GetAttribute("CornEditorOverview") ~= true
			or part:GetAttribute("corn_project_id") ~= PROJECT_ID
		then
			self:_restoreOverview()
			self:_warn("Overview ownership changed; its visibility was restored")
			return
		end
		local covered = #entry.Keys > 0
		for _, key in entry.Keys do
			local chunk = self._chunks[key]
			if not chunk or not chunk.Done then
				covered = false
				break
			end
		end
		if covered ~= entry.Hidden then
			part.LocalTransparencyModifier = if covered then 1 else entry.PreviousModifier
			entry.Hidden = covered
		end
	end
	self._overviewDirty = {}
end

function CornController:_clearChunks()
	self:_showOverview()
	for _, chunk in self._chunks do
		chunk.Alive = false
		chunk.Folder:Destroy()
	end
	self._chunks = {}
	self._queue = {}
	self._plantCount = 0
	if self._folder then
		self._folder:SetAttribute("LoadedPlants", 0)
	end
end

function CornController:_clearInputs()
	self:_clearChunks()
	self:_restoreOverview()
	if self._folder then
		self._folder:Destroy()
	end
	self._folder = nil
	self._map = nil
	self._field = nil
	self._template = nil
	self._exclusions = nil
end

function CornController:_resolveInputs(): boolean
	local map = Workspace:FindFirstChild("CornMap")
	local field = if map then map:FindFirstChild("FieldZone") else nil
	local art = ReplicatedStorage:FindFirstChild("CornRuntimeArt")
	local template = if art then art:FindFirstChild("CornPlantTemplate") else nil
	if not map or not map:IsA("Model") or map:GetAttribute("corn_project_id") ~= PROJECT_ID then
		self:_clearInputs()
		self:_warn("The owned CornMap is not available; editor preview is preserved")
		return false
	end
	if
		not field
		or not field:IsA("BasePart")
		or field.CFrame.UpVector:Dot(Vector3.yAxis) < 0.9999
	then
		self:_clearInputs()
		self:_warn("CornMap needs a horizontal FieldZone; editor preview is preserved")
		return false
	end
	if
		not art
		or not art:IsA("Folder")
		or art:GetAttribute("CornRuntimeArtOwned") ~= true
		or art:GetAttribute("corn_project_id") ~= PROJECT_ID
		or not template
		or (not template:IsA("Model") and not template:IsA("BasePart"))
		or template:GetAttribute("CornPlantTemplateOwned") ~= true
	then
		self:_clearInputs()
		self:_warn("Prepared corn art is not available; check CornField Output")
		return false
	end
	if
		self._map == map
		and self._field == field
		and self._template == template
		and self._folder
	then
		return true
	end
	self:_clearInputs()
	local existing = map:FindFirstChild("CornClientPlants")
	if existing then
		if
			not existing:IsA("Folder")
			or existing:GetAttribute("CornClientRendererOwned") ~= true
			or existing:GetAttribute("corn_project_id") ~= PROJECT_ID
		then
			self:_warn("Refused to replace unowned CornMap/CornClientPlants")
			return false
		end
		existing:Destroy()
	end
	local bounds, size = CornLayout.Bounds(template)
	self._pivotOffset = template:GetPivot():ToObjectSpace(bounds):Inverse()
	self._height = size.Y
	self._map = map
	self._field = field
	self._template = template
	local folder = Instance.new("Folder")
	folder.Name = "CornClientPlants"
	folder:SetAttribute("CornClientRendererOwned", true)
	folder:SetAttribute("corn_project_id", PROJECT_ID)
	folder:SetAttribute("LoadedPlants", 0)
	folder.Parent = map
	self._folder = folder
	-- This client-only deletion never changes the author's saved scene or Props.
	local preview = map:FindFirstChild("EditorPreview")
	if
		preview
		and preview:IsA("Folder")
		and preview:GetAttribute("CornEditorPreview") == true
		and preview:GetAttribute("corn_project_id") == PROJECT_ID
	then
		preview:Destroy()
	end
	self._lastWarning = ""
	return true
end

function CornController:_reconcile(root: BasePart)
	if not self:_resolveInputs() then
		return
	end
	local map = self._map :: Model
	local field = self._field :: BasePart
	local folder = self._folder :: Folder
	self:_bindOverview()
	local exclusions = CornLayout.ReadExclusions(map, field)
	if self._exclusions and self._exclusions.Signature ~= exclusions.Signature then
		self:_clearChunks()
	end
	self._exclusions = exclusions
	local minColumn, maxColumn, minRow, maxRow = CornLayout.GetCellBounds(field)
	local localRoot = field.CFrame:PointToObjectSpace(root.Position)
	local width = CornLayout.Spacing * CornLayout.ChunkCells
	local radius = CornLayout.RenderRadius
	local desired: { any } = {}
	for chunkColumn = math.floor((localRoot.X - radius) / width), math.floor((localRoot.X + radius) / width) do
		for chunkRow = math.floor((localRoot.Z - radius) / width), math.floor((localRoot.Z + radius) / width) do
			local firstColumn = math.max(minColumn, chunkColumn * CornLayout.ChunkCells)
			local lastColumn = math.min(maxColumn, (chunkColumn + 1) * CornLayout.ChunkCells - 1)
			local firstRow = math.max(minRow, chunkRow * CornLayout.ChunkCells)
			local lastRow = math.min(maxRow, (chunkRow + 1) * CornLayout.ChunkCells - 1)
			if firstColumn > lastColumn or firstRow > lastRow then
				continue
			end
			local centerX = (firstColumn + lastColumn) * CornLayout.Spacing / 2
			local centerZ = (firstRow + lastRow) * CornLayout.Spacing / 2
			local distance = (centerX - localRoot.X) ^ 2 + (centerZ - localRoot.Z) ^ 2
			if distance <= radius * radius then
				table.insert(desired, {
					Key = chunkColumn .. ":" .. chunkRow,
					MinColumn = firstColumn,
					MaxColumn = lastColumn,
					MinRow = firstRow,
					MaxRow = lastRow,
					Distance = distance,
				})
			end
		end
	end
	table.sort(desired, function(a, b)
		return if a.Distance == b.Distance then a.Key < b.Key else a.Distance < b.Distance
	end)
	local wanted: { [string]: boolean } = {}
	for index, candidate in desired do
		if index > MAX_CHUNKS then
			break
		end
		wanted[candidate.Key] = true
		local chunk = self._chunks[candidate.Key]
		if chunk then
			chunk.Distance = candidate.Distance
		else
			local chunkFolder = Instance.new("Folder")
			chunkFolder.Name = "Chunk_" .. candidate.Key
			chunkFolder.Parent = folder
			chunk = {
				Key = candidate.Key,
				Folder = chunkFolder,
				MinColumn = candidate.MinColumn,
				MaxColumn = candidate.MaxColumn,
				MinRow = candidate.MinRow,
				MaxRow = candidate.MaxRow,
				Column = candidate.MinColumn,
				Row = candidate.MinRow,
				Distance = candidate.Distance,
				Count = 0,
				Alive = true,
				Done = false,
			}
			self._chunks[candidate.Key] = chunk
		end
	end
	for key, chunk in self._chunks do
		if not wanted[key] then
			self:_markOverviewChunk(key)
			chunk.Alive = false
			self._plantCount -= chunk.Count
			chunk.Folder:Destroy()
			self._chunks[key] = nil
		end
	end
	self._queue = {}
	for _, chunk in self._chunks do
		if not chunk.Done then
			table.insert(self._queue, chunk)
		end
	end
	table.sort(self._queue, function(a, b)
		return if a.Distance == b.Distance then a.Key < b.Key else a.Distance < b.Distance
	end)
	self:_updateOverview()
end

function CornController:_createBatch()
	local template = self._template
	local field = self._field
	local exclusions = self._exclusions
	if not template or not field or not exclusions then
		return
	end
	local began = os.clock()
	local _, fieldYaw = field.CFrame:ToOrientation()
	local examined = 0
	local created = 0
	while
		#self._queue > 0
		and examined < CELL_BUDGET
		and created < CREATE_BUDGET
		and os.clock() - began < TIME_BUDGET_SEC
	do
		local chunk = self._queue[1]
		if not chunk.Alive or chunk.Done then
			table.remove(self._queue, 1)
			continue
		end
		local column = chunk.Column
		local row = chunk.Row
		chunk.Column += 1
		if chunk.Column > chunk.MaxColumn then
			chunk.Column = chunk.MinColumn
			chunk.Row += 1
		end
		if chunk.Row > chunk.MaxRow then
			chunk.Done = true
			self:_markOverviewChunk(chunk.Key)
			table.remove(self._queue, 1)
		end
		examined += 1
		local position = CornLayout.CellPosition(field, column, row)
		if CornLayout.IsExcluded(position, exclusions) then
			continue
		end
		local clone = template:Clone()
		if not clone then
			self:_warn("Prepared corn template is not Archivable")
			self:Destroy()
			return
		end
		local plant = clone :: CornLayout.Plant
		plant.Name = "Corn"
		plant:PivotTo(
			CFrame.new(position + Vector3.new(0, self._height / 2, 0))
				* CFrame.Angles(0, CornLayout.CellYaw(column, row) + fieldYaw, 0)
				* self._pivotOffset
		)
		plant.Parent = chunk.Folder
		chunk.Count += 1
		self._plantCount += 1
		created += 1
	end
	if self._folder then
		self._folder:SetAttribute("LoadedPlants", self._plantCount)
	end
	self:_updateOverview()
end

function CornController:_step(delta: number)
	self._pollElapsed += delta
	if self._pollElapsed >= POLL_SEC then
		self._pollElapsed = 0
		local character = Players.LocalPlayer.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if root and root:IsA("BasePart") then
			self:_reconcile(root)
		else
			self:_clearChunks()
		end
	end
	self:_createBatch()
end

function CornController:Init(context: any)
	self._enabled = RunService:IsStudio()
		and context.Config.Environment == "DEV"
		and context.Config.Game.SessionMode == "solo_local"
end

function CornController:Start()
	if not self._enabled or self._connection then
		return
	end
	self._connection = RunService.Heartbeat:Connect(function(delta: number)
		self:_step(delta)
	end)
end

function CornController:Destroy()
	self._enabled = false
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	self:_clearInputs()
end

return CornController
