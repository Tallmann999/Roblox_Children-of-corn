--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Appearance = require(
	ReplicatedStorage:WaitForChild("GameShared"):WaitForChild("Game"):WaitForChild("CornAppearance")
)

local Controller = { Name = "CornAppearanceController", Order = 54 }
local PROJECT = "children_of_corn"
local BATCH = 384
local TIME_BUDGET = 0.002
local MAP_ROOTS = {
	EditorFieldOverview = "CornEditorOverview",
	CornClientPlants = "CornClientRendererOwned",
	CornClientBackdrop = "CornClientBackdropOwned",
}

local function recognized(root: Instance, flag: string): boolean
	return root:GetAttribute(flag) == true and root:GetAttribute("corn_project_id") == PROJECT
end

local function ownedPart(root: any, part: MeshPart): boolean
	local folder = root.folder
	if
		not recognized(folder, root.flag)
		or not part.Anchored
		or part.CanCollide
		or part.CanTouch
		or part.CanQuery
	then
		return false
	end
	if root.flag == "CornRuntimeArtOwned" then
		return part.Parent == folder
			and part.Name == "CornPlantTemplate"
			and part:GetAttribute("CornPlantTemplateOwned") == true
	elseif root.flag == "CornClientRendererOwned" then
		local group = part.Parent
		return group ~= nil
			and group:IsA("Folder")
			and group.Parent == folder
			and part.Name == "Corn"
			and part:GetAttribute("CornPlantTemplateOwned") == true
	end
	return part.Parent == folder
		and part:GetAttribute("CornEditorOverview") == true
		and part:GetAttribute("corn_project_id") == PROJECT
		and (
			root.flag ~= "CornClientBackdropOwned"
			or part:GetAttribute("CornClientBackdropOwned") == true
		)
end

function Controller:_enqueue(part: MeshPart)
	if not self._queued[part] then
		self._queued[part] = true
		table.insert(self._queue, part)
	end
end

function Controller:_restore(part: MeshPart, entry: any)
	-- Preserve an unrelated manual texture change rather than overwriting it.
	if entry.applied and part.TextureID == Appearance.DryTextureId then
		part.TextureID = entry.texture
	end
	entry.applied = false
end

function Controller:_forget(part: MeshPart)
	local entry = self._entries[part]
	if entry then
		self:_restore(part, entry)
		entry.root.parts[part] = nil
		self._entries[part] = nil
	end
	self._queued[part] = nil
end

function Controller:_register(root: any, item: Instance)
	if
		not item:IsA("MeshPart")
		or item.MeshId ~= Appearance.MeshId
		or self._entries[item]
		or not ownedPart(root, item)
	then
		return
	end
	if item:FindFirstChildWhichIsA("SurfaceAppearance") then
		return
	end
	local texture = item.TextureID
	if texture ~= Appearance.GreenTextureId and texture ~= Appearance.DryTextureId then
		return
	end
	-- Prepared/saved yellow copies keep that exact baseline through menu/cleanup.
	local entry = {
		root = root,
		texture = texture,
		applied = false,
	}
	self._entries[item] = entry
	root.parts[item] = true
	self:_enqueue(item)
end

function Controller:_bind(folder: Instance, flag: string)
	if self._roots[folder] then
		return
	end
	local root = { folder = folder, flag = flag, parts = {}, connections = {} }
	self._roots[folder] = root
	table.insert(
		root.connections,
		folder.DescendantAdded:Connect(function(item)
			self:_register(root, item)
		end)
	)
	table.insert(
		root.connections,
		folder.DescendantRemoving:Connect(function(item)
			if item:IsA("MeshPart") then
				self:_forget(item)
			end
		end)
	)
	for _, item in folder:GetDescendants() do
		self:_register(root, item)
	end
end

function Controller:_unbind(root: any)
	for _, connection in root.connections do
		connection:Disconnect()
	end
	for part in root.parts do
		self:_forget(part)
	end
	self._roots[root.folder] = nil
end

function Controller:_refresh()
	local map = Workspace:FindFirstChild("CornMap")
	local validMap = map and map:IsA("Model") and map:GetAttribute("corn_project_id") == PROJECT
	local desired = {}
	if
		validMap
		and not Workspace:FindFirstChild("Asmr_Base")
		and not Workspace:FindFirstChild("ASMR_Models")
	then
		for name, flag in MAP_ROOTS do
			local folder = map:FindFirstChild(name)
			if folder and folder:IsA("Folder") and recognized(folder, flag) then
				desired[folder] = flag
			end
		end
		local art = ReplicatedStorage:FindFirstChild("CornRuntimeArt")
		if art and art:IsA("Folder") and recognized(art, "CornRuntimeArtOwned") then
			desired[art] = "CornRuntimeArtOwned"
		end
	end
	for folder, root in self._roots do
		if not desired[folder] then
			self:_unbind(root)
		end
	end
	for folder, flag in desired do
		self:_bind(folder, flag)
	end
end

function Controller:_apply(part: MeshPart)
	local entry = self._entries[part]
	if not entry then
		return
	end
	local root = entry.root
	if
		not part:IsDescendantOf(root.folder)
		or not ownedPart(root, part)
		or part:FindFirstChildWhichIsA("SurfaceAppearance")
	then
		self:_forget(part)
		return
	end
	local expected = if entry.applied then Appearance.DryTextureId else entry.texture
	if part.TextureID ~= expected or part.MeshId ~= Appearance.MeshId then
		-- Drop ownership of this appearance; the author changed the runtime copy.
		root.parts[part] = nil
		self._entries[part] = nil
		return
	end
	if Appearance.IsDry(self._mode) then
		part.TextureID = Appearance.DryTextureId
		entry.applied = true
	else
		self:_restore(part, entry)
	end
end

function Controller:SetMode(mode: string?)
	if not Appearance.IsValidMode(mode) or mode == self._mode then
		return
	end
	self._mode = mode
	for part in self._entries do
		self:_enqueue(part)
	end
end

function Controller:Init(_context: any)
	self._mode = nil
	self._entries = {}
	self._roots = {}
	self._queue = {}
	self._queued = {}
	self._head = 1
	self._poll = 0
end

function Controller:Start(context: any)
	if
		not RunService:IsStudio()
		or context.Config.Environment ~= "DEV"
		or (
			context.Config.Game.SessionMode ~= "solo_local"
			and context.Config.Game.SessionMode ~= "team_local"
		)
	then
		return
	end
	self:_refresh()
	self._heartbeat = RunService.Heartbeat:Connect(function(dt)
		self._poll += dt
		if self._poll >= 1 then
			self._poll = 0
			self:_refresh()
		end
		local began, count = os.clock(), 0
		while self._head <= #self._queue and count < BATCH and os.clock() - began < TIME_BUDGET do
			local part = self._queue[self._head]
			self._head += 1
			self._queued[part] = nil
			self:_apply(part)
			count += 1
		end
		if self._head > #self._queue then
			table.clear(self._queue)
			self._head = 1
		end
	end)
end

function Controller:Destroy()
	if self._heartbeat then
		self._heartbeat:Disconnect()
		self._heartbeat = nil
	end
	for _, root in self._roots do
		self:_unbind(root)
	end
	table.clear(self._queue)
	table.clear(self._queued)
end

return Controller
