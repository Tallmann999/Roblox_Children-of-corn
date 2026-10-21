--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Controller = { Name = "CornShadowController", Order = 56 }
local PROJECT = "children_of_corn"
local INTERVAL, ENTER_RADIUS, RETAIN_RADIUS, LIMIT = 0.3, 26, 28, 256
local SCAN_LIMIT = 1296 -- Nine nearby chunks, each at most twelve by twelve plants.
local CHUNK_WIDTH = 36 -- Existing CornLayout.Spacing3 * ChunkCells12.
local PROPERTIES = {
	"Name",
	"Size",
	"Color",
	"Material",
	"Transparency",
	"LocalTransparencyModifier",
	"Anchored",
	"CanCollide",
	"CanTouch",
	"CanQuery",
}

local function equalMap(a: any, b: any): boolean
	for key, value in a do
		if b[key] ~= value then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local function decorative(part: BasePart): boolean
	return part.Anchored and not part.CanCollide and not part.CanTouch and not part.CanQuery
end

function Controller:_binding(): (any, any, any)
	local renderer = self._renderer
	local map, field, folder =
		renderer and renderer._map, renderer and renderer._field, renderer and renderer._folder
	local variant = map and map:GetAttribute("HarvestArtVariant")
	local ground = map and map:FindFirstChild("Ground")
	if
		not renderer
		or not renderer._enabled
		or type(renderer._chunks) ~= "table"
		or not map
		or not map:IsA("Model")
		or map.Name ~= "CornMap"
		or map.Parent ~= Workspace
		or Workspace:FindFirstChild("CornMap") ~= map
		or map:GetAttribute("corn_project_id") ~= PROJECT
		or variant ~= "A"
		or not ground
		or not ground:IsA("BasePart")
		or ground.Size ~= Vector3.new(630, 2, 630)
		or not field
		or field.Parent ~= map
		or field.Name ~= "FieldZone"
		or not field:IsA("BasePart")
		or field.Size ~= Vector3.new(630, 10, 630)
		or field.CFrame.UpVector:Dot(Vector3.yAxis) < 0.9999
		or not folder
		or not folder:IsA("Folder")
		or folder.Name ~= "CornClientPlants"
		or folder.Parent ~= map
		or folder:GetAttribute("CornClientRendererOwned") ~= true
		or folder:GetAttribute("corn_project_id") ~= PROJECT
	then
		return nil, nil, nil
	end
	return map, field, folder
end

function Controller:_windEntry(part: BasePart, chunk: any): (any, any)
	local wind = self._wind
	local layer = wind and wind._layers and wind._layers.near
	local entry = layer and layer.Entries and layer.Entries[part]
	if
		layer
		and layer.Folder == self._folder
		and entry
		and entry.Layer == layer
		and entry.Plant == part
		and entry.Parent == chunk.Folder
	then
		for _, saved in entry.Parts do
			if saved.Part == part then
				return entry, saved.Frame
			end
		end
	end
	return nil, nil
end

function Controller:_frameOwned(record: any): boolean
	local part = record.part
	if part.CFrame == record.frame then
		return true
	end
	local entry, frame = self:_windEntry(part, record.chunk)
	if not entry or not entry.Moved or frame ~= record.frame then
		return false
	end
	-- CornWind legitimately tilts these exact instances around its saved base.
	-- Accept that bounded transform, but never an unrelated translation/yaw.
	local relative = CFrame.new(-entry.Base)
		* part.CFrame
		* frame:Inverse()
		* CFrame.new(entry.Base)
	local x, y, z = relative:ToEulerAnglesXYZ()
	return relative.Position.Magnitude < 0.0001
		and math.abs(y) < 0.0001
		and math.abs(x) <= math.rad(2.25) + 0.0001
		and math.abs(z) <= math.rad(1.05) + 0.0001
end

function Controller:_valid(record: any): boolean
	local part, chunk = record.part, record.chunk
	if
		not self._map
		or self._map.Name ~= "CornMap"
		or self._map:GetAttribute("corn_project_id") ~= PROJECT
		or self._map:GetAttribute("HarvestArtVariant") ~= self._variant
		or not self._folder
		or self._folder.Parent ~= self._map
		or self._folder.Name ~= "CornClientPlants"
		or self._folder:GetAttribute("CornClientRendererOwned") ~= true
		or self._folder:GetAttribute("corn_project_id") ~= PROJECT
		or self._renderer._chunks[record.key] ~= chunk
		or not chunk.Alive
		or chunk.Folder ~= record.parent
		or record.parent.Parent ~= self._folder
		or record.parent.Name ~= "Chunk_" .. record.key
		or part.Parent ~= record.parent
		or part:GetAttribute("CornPlantTemplateOwned") ~= true
		or not decorative(part)
		or not equalMap(part:GetAttributes(), record.attributes)
		or not equalMap(part:GetTags(), record.tags)
	then
		return false
	end
	for key, value in record.properties do
		if part[key] ~= value then
			return false
		end
	end
	return self:_frameOwned(record)
end

function Controller:_release(part: BasePart, record: any)
	-- Foreign changes opt out for this controller's lifetime, including reparenting.
	if self:_valid(record) and part.CastShadow == true then
		part.CastShadow = false
		self._lastWrites += 1
	else
		self._retired[part] = true
	end
	self._active[part] = nil
end

function Controller:_clear()
	for part, record in self._active do
		self:_release(part, record)
	end
	self._map, self._field, self._folder, self._variant = nil, nil, nil, nil
end

function Controller:_reconcile()
	self._lastWrites, self._lastScanned = 0, 0
	local map, field, folder = self:_binding()
	local character = self._player and self._player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not map or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		self:_clear()
		return
	end
	if self._folder ~= folder or self._map ~= map or self._field ~= field then
		self:_clear()
		self._map, self._field, self._folder = map, field, folder
		self._variant = map:GetAttribute("HarvestArtVariant")
	end
	local position = root.Position
	local localPosition = field.CFrame:PointToObjectSpace(position)
	local candidates = {}
	for column = math.floor((localPosition.X - RETAIN_RADIUS) / CHUNK_WIDTH), math.floor((localPosition.X + RETAIN_RADIUS) / CHUNK_WIDTH) do
		if self._lastScanned >= SCAN_LIMIT then
			break
		end
		for row = math.floor((localPosition.Z - RETAIN_RADIUS) / CHUNK_WIDTH), math.floor((localPosition.Z + RETAIN_RADIUS) / CHUNK_WIDTH) do
			if self._lastScanned >= SCAN_LIMIT then
				break
			end
			local key = column .. ":" .. row
			local chunk = self._renderer._chunks[key]
			if
				not chunk
				or not chunk.Alive
				or chunk.Lod ~= 1
				or chunk.Folder.Parent ~= folder
				or chunk.Folder.Name ~= "Chunk_" .. key
			then
				continue
			end
			-- Only direct foreground plants of at most nine nearby existing chunks.
			for _, part in chunk.Folder:GetChildren() do
				if self._lastScanned >= SCAN_LIMIT then
					break
				end
				self._lastScanned += 1
				if
					not part:IsA("BasePart")
					or part.Name ~= "Corn"
					or not decorative(part)
					or part:GetAttribute("CornPlantTemplateOwned") ~= true
					or self._retired[part]
				then
					continue
				end
				local record = self._active[part]
				if record and (not self:_valid(record) or part.CastShadow ~= true) then
					self._active[part], self._retired[part] = nil, true
					continue
				end
				local distance = (part.Position - position).Magnitude
				if
					distance > (if record then RETAIN_RADIUS else ENTER_RADIUS)
					or (not record and part.CastShadow)
				then
					continue
				end
				if not self._ids[part] then
					self._nextId += 1
					self._ids[part] = self._nextId
				end
				table.insert(candidates, {
					part = part,
					chunk = chunk,
					key = key,
					distance = distance,
					id = self._ids[part],
				})
			end
		end
	end
	table.sort(candidates, function(a, b)
		return if a.distance == b.distance then a.id < b.id else a.distance < b.distance
	end)
	local wanted = {}
	for index = 1, math.min(#candidates, LIMIT) do
		wanted[candidates[index].part] = candidates[index]
	end
	for part, record in self._active do
		if not wanted[part] then
			self:_release(part, record)
		end
	end
	for part, candidate in wanted do
		if self._active[part] then
			continue
		end
		local properties = {}
		for _, key in PROPERTIES do
			properties[key] = part[key]
		end
		if part:IsA("MeshPart") then
			properties.MeshId, properties.TextureID = part.MeshId, part.TextureID
		end
		local _, windFrame = self:_windEntry(part, candidate.chunk)
		local record = {
			part = part,
			chunk = candidate.chunk,
			key = candidate.key,
			parent = part.Parent,
			frame = windFrame or part.CFrame,
			properties = properties,
			attributes = part:GetAttributes(),
			tags = part:GetTags(),
		}
		if self:_valid(record) and part.CastShadow == false then
			part.CastShadow = true
			self._active[part] = record
			self._lastWrites += 1
		end
	end
end

function Controller:_step(delta: number)
	if delta ~= delta or delta < 0 or delta == math.huge then
		return
	end
	self._elapsed += delta
	if self._elapsed >= INTERVAL then
		self._elapsed %= INTERVAL
		self:_reconcile()
	end
end

function Controller:Init(context: any)
	local map = Workspace:FindFirstChild("CornMap")
	self._enabled = RunService:IsStudio()
		and context.Config.Environment == "DEV"
		and (context.Config.Game.SessionMode == "solo_local" or context.Config.Game.SessionMode == "team_local")
		and not (map and map:GetAttribute("HarvestArtVariant") == "B")
	self._renderer, self._wind =
		context.Controllers.CornController, context.Controllers.CornWindController
	self._player, self._connection = Players.LocalPlayer, nil
	self._map, self._field, self._folder = nil, nil, nil
	self._active, self._retired, self._ids =
		{}, setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
	self._elapsed, self._nextId, self._lastWrites, self._lastScanned = INTERVAL, 0, 0, 0
end

function Controller:Start(_context: any)
	if not self._enabled or not self._renderer or self._connection then
		return
	end
	self._connection = RunService.Heartbeat:Connect(function(delta)
		self:_step(delta)
	end)
end

function Controller:Destroy()
	self._enabled = false
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	self._lastWrites = 0
	self:_clear()
end

return Controller
