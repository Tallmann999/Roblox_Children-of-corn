--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CornLayout = require(
	ReplicatedStorage:WaitForChild("GameShared"):WaitForChild("Game"):WaitForChild("CornLayout")
)

local CornBackdropController = { Name = "CornBackdropController", Order = 45 }
local PROJECT_ID = "children_of_corn"
local FOLDER_NAME = "CornClientBackdrop"
local STRIDE = 2
local MAX_PLANTS = 20000
local CLONE_BUDGET = 18
local TIME_BUDGET = 0.002
local POLL_SEC = 1

local function owned(item: Instance): boolean
	return item:GetAttribute("CornClientBackdropOwned") == true
		and item:GetAttribute("corn_project_id") == PROJECT_ID
end

local function ownedTree(folder: Instance): boolean
	if not owned(folder) then
		return false
	end
	for _, item in folder:GetDescendants() do
		if not owned(item) then
			return false
		end
	end
	return true
end

local function staticArt(template: Instance): boolean
	for _, item in template:GetDescendants() do
		if
			item:IsA("LuaSourceContainer")
			or item:IsA("Sound")
			or item:IsA("ParticleEmitter")
			or item:IsA("Beam")
			or item:IsA("Trail")
			or item:IsA("ProximityPrompt")
			or item:IsA("ClickDetector")
			or item:IsA("RemoteEvent")
			or item:IsA("RemoteFunction")
		then
			return false
		end
	end
	return template.Archivable
end

function CornBackdropController:_warn(message: string)
	if self._lastWarning ~= message then
		self._lastWarning = message
		warn("[CornBackdropController] " .. message)
	end
end

function CornBackdropController:_bridge(folder: Folder): boolean
	local renderer = self._renderer
	return renderer ~= nil
		and typeof(renderer.UseBackdropReady) == "function"
		and renderer:UseBackdropReady(folder) == true
end

function CornBackdropController:_restoreOriginals()
	for part, previous in self._originals do
		if part.Parent then
			part.LocalTransparencyModifier = previous
		end
	end
	table.clear(self._originals)
end

function CornBackdropController:_clear()
	self._epoch += 1
	local folder = self._folder
	if folder and owned(folder) then
		self:_bridge(folder)
		folder:SetAttribute("Ready", false)
	end
	self:_restoreOriginals()
	if folder then
		if ownedTree(folder) then
			folder:Destroy()
		else
			self:_warn(
				"Changed ownership or foreign backdrop content was preserved; saved overview restored"
			)
		end
	end
	self._folder = nil
	self._map = nil
	self._field = nil
	self._template = nil
	self._exclusions = nil
	self._signature = nil
	self._ready = false
	self._count = 0
	self._detailed = false
	self._detailedTemplates = nil
end

function CornBackdropController:_publish(): boolean
	local folder, map = self._folder, self._map
	if not folder or not map or folder.Parent ~= map or not owned(folder) then
		return false
	end
	local overview = map:FindFirstChild("EditorFieldOverview")
	if
		not overview
		or not overview:IsA("Folder")
		or overview:GetAttribute("CornEditorOverview") ~= true
		or overview:GetAttribute("corn_project_id") ~= PROJECT_ID
	then
		self:_warn("Unrecognized saved overview was preserved; backdrop not published")
		return false
	end
	local originals = overview:GetChildren()
	for _, part in originals do
		if
			not part:IsA("BasePart")
			or part:GetAttribute("CornEditorOverview") ~= true
			or part:GetAttribute("corn_project_id") ~= PROJECT_ID
		then
			self:_warn("Foreign saved overview content was preserved; backdrop not published")
			return false
		end
	end
	-- Bridge clears the old near-field mask before we capture its exact original LTM.
	-- No yield between bridge, capture/hide and publication.
	if not self:_bridge(folder) then
		self:_warn("Near-field backdrop bridge unavailable; saved overview preserved")
		return false
	end
	for _, item in originals do
		local part = item :: BasePart
		self._originals[part] = part.LocalTransparencyModifier
		part.LocalTransparencyModifier = 1
	end
	self._ready = true
	folder:SetAttribute("LoadedPlants", self._count)
	folder:SetAttribute("Ready", true)
	return true
end

function CornBackdropController:_resolveInputs(): boolean
	if not self._renderer or typeof(self._renderer.UseBackdropReady) ~= "function" then
		self:_clear()
		self:_warn("Near-field backdrop bridge unavailable; saved overview preserved")
		return false
	end
	local map = Workspace:FindFirstChild("CornMap")
	local field = if map then map:FindFirstChild("FieldZone") else nil
	local art = ReplicatedStorage:FindFirstChild("CornRuntimeArt")
	local template = if art then art:FindFirstChild("CornPlantTemplate") else nil
	if template and template:IsA("Model") then
		self:_clear()
		self:_warn(
			"Backdrop needs a prepared BasePart template compatible with near-field coverage; saved overview preserved"
		)
		return false
	end
	if
		not map
		or not map:IsA("Model")
		or map:GetAttribute("corn_project_id") ~= PROJECT_ID
		or Workspace:FindFirstChild("Asmr_Base")
		or Workspace:FindFirstChild("ASMR_Models")
		or not field
		or not field:IsA("BasePart")
		or field.CFrame.UpVector:Dot(Vector3.yAxis) < 0.9999
		or field.Size.X <= 0
		or field.Size.Z <= 0
		or not art
		or not art:IsA("Folder")
		or art:GetAttribute("CornRuntimeArtOwned") ~= true
		or art:GetAttribute("corn_project_id") ~= PROJECT_ID
		or not template
		or not template:IsA("BasePart")
		or template:GetAttribute("CornPlantTemplateOwned") ~= true
		or not staticArt(template)
	then
		self:_clear()
		self:_warn(
			"Owned horizontal field and prepared static art unavailable; saved overview preserved"
		)
		return false
	end
	local detailed = map:GetAttribute("HarvestArtVariant") == "B"
	local templates, appearance = self._detailedTemplates, self._appearance
	if detailed and not templates then
		if self._detailPreparing then
			return false
		end
		self._detailPreparing = true
		local epoch = self._epoch
		local ok, result = pcall(function()
			local module = require(
				ReplicatedStorage:WaitForChild("GameShared")
					:WaitForChild("Game")
					:WaitForChild("CornAppearance")
			)
			return { Appearance = module, Templates = module.DetailedTemplates() }
		end)
		self._detailPreparing = false
		if
			self._epoch ~= epoch
			or not map.Parent
			or map:GetAttribute("HarvestArtVariant") ~= "B"
		then
			return false
		end
		if not ok then
			self:_warn(
				"Detailed backdrop unavailable; saved overview preserved: " .. tostring(result)
			)
			return false
		end
		templates, appearance = result.Templates, result.Appearance
	end
	local exclusions = CornLayout.ReadExclusions(map, field)
	local bounds, size = CornLayout.Bounds(template)
	local signature = exclusions.Signature
		.. "/template/"
		.. tostring(bounds)
		.. "/"
		.. tostring(size)
		.. (if detailed then "/variant/B" else "")
	local folder = self._folder
	if
		self._map == map
		and self._field == field
		and self._template == template
		and self._signature == signature
		and folder
		and folder.Parent == map
		and owned(folder)
		and folder:GetAttribute("CornEditorOverview") == true
		and folder:GetAttribute("Ready") == self._ready
		and (self._detailed == true) == detailed
	then
		return true
	end
	self:_clear()
	if map:FindFirstChild(FOLDER_NAME) then
		self:_warn("Existing CornMap/CornClientBackdrop was preserved; no replacement attempted")
		return false
	end
	if self._failedSignature == signature then
		return false
	end
	local minColumn, maxColumn, minRow, maxRow = CornLayout.GetCellBounds(field)
	minColumn, minRow = math.ceil(minColumn / STRIDE) * STRIDE, math.ceil(minRow / STRIDE) * STRIDE
	maxColumn, maxRow =
		math.floor(maxColumn / STRIDE) * STRIDE, math.floor(maxRow / STRIDE) * STRIDE
	local candidateCount = (math.floor((maxColumn - minColumn) / STRIDE) + 1)
		* (math.floor((maxRow - minRow) / STRIDE) + 1)
	if candidateCount > MAX_PLANTS or candidateCount <= 0 then
		self:_warn("Full-field grid exceeds the 20000 plant cap; saved overview preserved")
		return false
	end
	self._map, self._field, self._template = map, field, template
	self._detailed, self._detailedTemplates, self._appearance = detailed, templates, appearance
	self._exclusions, self._signature = exclusions, signature
	self._minColumn, self._maxColumn = minColumn, maxColumn
	self._minRow, self._maxRow = minRow, maxRow
	self._column, self._row = minColumn, minRow
	self._fieldFrame = field.CFrame
	self._fieldSize = field.Size
	self._fieldYaw = math.atan2(-field.CFrame.LookVector.X, -field.CFrame.LookVector.Z)
	folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder:SetAttribute("CornClientBackdropOwned", true)
	folder:SetAttribute("CornEditorOverview", true)
	folder:SetAttribute("corn_project_id", PROJECT_ID)
	folder:SetAttribute("Ready", false)
	folder:SetAttribute("Stride", STRIDE)
	folder:SetAttribute("DetailStride", STRIDE * CornLayout.SpacingFor(field))
	folder:SetAttribute("MaxPlants", MAX_PLANTS)
	folder:SetAttribute("LoadedPlants", 0)
	if detailed then
		folder:SetAttribute("HarvestArtVariant", "B")
		folder:SetAttribute("HarvestCornLod", "Far")
	end
	folder.Parent = map
	self._folder = folder
	self._lastWarning = ""
	return true
end

function CornBackdropController:_advance()
	self._column += STRIDE
	if self._column > self._maxColumn then
		self._column = self._minColumn
		self._row += STRIDE
	end
end

function CornBackdropController:_buildStep()
	local folder, field, template, exclusions =
		self._folder, self._field, self._template, self._exclusions
	if not folder or not field or not template or not exclusions or self._ready then
		return
	end
	if
		folder.Parent ~= self._map
		or not owned(folder)
		or field.CFrame ~= self._fieldFrame
		or field.Size ~= self._fieldSize
		or (self._map:GetAttribute("HarvestArtVariant") == "B") ~= (self._detailed == true)
	then
		self:_clear()
		self._pollElapsed = POLL_SEC
		return
	end
	local epoch, start = self._epoch, self._clock()
	local created = 0
	while
		self._epoch == epoch
		and self._row <= self._maxRow
		and created < CLONE_BUDGET
		and self._count < MAX_PLANTS
		and self._clock() - start < TIME_BUDGET
	do
		local column, row = self._column, self._row
		self:_advance()
		local position = CornLayout.CellPosition(field, column, row)
		if CornLayout.IsExcluded(position, exclusions) then
			continue
		end
		position = CornLayout.TrailEdgePosition(position, exclusions)
		local source = if self._detailed
			then self._detailedTemplates.Far[self._appearance.Variety(column, row)]
			else template
		local plant = source:Clone()
		if not plant then
			error("Prepared backdrop plant could not be cloned")
		end
		plant.Name = string.format("Far_%d_%d", column, row)
		local parts = plant:GetDescendants()
		table.insert(parts, plant)
		for _, item in parts do
			item:SetAttribute("CornClientBackdropOwned", true)
			item:SetAttribute("CornEditorOverview", true)
			item:SetAttribute("corn_project_id", PROJECT_ID)
			item:SetAttribute("CornPlantTemplateOwned", nil)
			if item:IsA("BasePart") then
				item.Anchored = true
				item.CanCollide = false
				item.CanTouch = false
				item.CanQuery = false
				item.CastShadow = self._detailed == true
			end
		end
		CornLayout.ApplyVariation(plant, column, row)
		local yaw = CornLayout.CellYaw(column, row) + self._fieldYaw
		plant:PivotTo(
			if self._detailed
				then self._appearance.DetailedPivot(plant, position, yaw)
				else CornLayout.PivotForPlant(plant, position, yaw)
		)
		plant.Parent = folder
		created += 1
		self._count += 1
	end
	folder:SetAttribute("LoadedPlants", self._count)
	folder:SetAttribute("LastFrameClones", created)
	folder:SetAttribute("LastFrameSeconds", self._clock() - start)
	if self._row > self._maxRow then
		if not self:_publish() then
			local failed = self._signature
			self:_clear()
			self._failedSignature = failed
		end
	end
end

function CornBackdropController:_step(delta: number)
	self._pollElapsed += delta
	if self._pollElapsed >= POLL_SEC then
		self._pollElapsed = 0
		self:_resolveInputs()
	end
	self:_buildStep()
end

function CornBackdropController:Init(context: any)
	self._enabled = RunService:IsStudio()
		and context.Config.Environment == "DEV"
		and (
			context.Config.Game.SessionMode == "solo_local"
			or context.Config.Game.SessionMode == "team_local"
		)
	self._renderer = context.Controllers.CornController
	self._connection = nil
	self._clock = os.clock
	self._epoch = 0
	self._originals = {}
	self._ready = false
	self._count = 0
	self._lastWarning = ""
	self._pollElapsed = math.huge
	self._failedSignature = nil
end

function CornBackdropController:Start()
	if not self._enabled or self._connection then
		return
	end
	self._connection = RunService.Heartbeat:Connect(function(delta: number)
		local ok, problem = pcall(self._step, self, delta)
		if not ok then
			local failed = self._signature
			self:_clear()
			self._failedSignature = failed
			self:_warn("Backdrop build failed; saved overview restored: " .. tostring(problem))
		end
	end)
end

function CornBackdropController:Destroy()
	self._enabled = false
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	self:_clear()
	self._renderer = nil
end

return CornBackdropController
