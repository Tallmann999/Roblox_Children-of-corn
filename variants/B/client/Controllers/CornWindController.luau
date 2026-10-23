--!strict
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local CornWindController = { Name = "CornWindController", Order = 55 }
local PROJECT_ID = "children_of_corn"
local BUCKET_SIZE = 6
local RADIUS = 5
local MONSTER_VIEW_RADIUS = 70
local UPDATE_SEC = 1 / 12
local SELECT_SEC = 0.2
local RESOLVE_SEC = 0.5
local INDEX_BUDGET = 64
local INDEX_SECONDS = 0.001
local ACTOR_LIMIT = 2
local SCAN_LIMIT = 128
local PART_LIMIT = 32
local TRAIL_SEC = 0.3
local MAX_PARTS_PER_PLANT = 8
local ANGLE = math.rad(3)

local function disconnect(connections: { RBXScriptConnection })
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function decorative(part: BasePart): boolean
	return part.Anchored and not part.CanCollide and not part.CanTouch and not part.CanQuery
end

local function bucketKey(x: number, z: number): string
	return tostring(x) .. ":" .. tostring(z)
end

function CornWindController:_ownedLayer(folder: Instance, kind: string): boolean
	return folder:IsA("Folder")
		and folder.Parent == self._map
		and folder:GetAttribute("corn_project_id") == PROJECT_ID
		and (
			if kind == "near"
				then folder.Name == "CornClientPlants" and folder:GetAttribute(
					"CornClientRendererOwned"
				) == true
				else folder.Name == "CornClientBackdrop" and folder:GetAttribute(
					"CornClientBackdropOwned"
				) == true and folder:GetAttribute("CornEditorOverview") == true
		)
end

function CornWindController:_validEntry(entry: any): boolean
	local layer = entry.Layer
	if
		self._layers[layer.Kind] ~= layer
		or not self:_ownedLayer(layer.Folder, layer.Kind)
		or entry.Plant.Parent ~= entry.Parent
	then
		return false
	end
	if layer.Kind == "near" then
		if
			entry.Parent.Parent ~= layer.Folder
			or entry.Plant.Name ~= "Corn"
			or entry.Plant:GetAttribute("CornPlantTemplateOwned") ~= true
		then
			return false
		end
	elseif
		entry.Plant:GetAttribute("CornClientBackdropOwned") ~= true
		or entry.Plant:GetAttribute("corn_project_id") ~= PROJECT_ID
	then
		return false
	end
	for _, saved in entry.Parts do
		if not decorative(saved.Part) then
			return false
		end
	end
	return true
end

function CornWindController:_restore(entry: any)
	if not entry.Moved then
		return
	end
	-- Removed copies can still be unparented Instances. Restore their exact frames
	-- before forgetting them; destroyed copies need no recovery.
	for _, saved in entry.Parts do
		pcall(function()
			saved.Part.CFrame = saved.Frame
		end)
	end
	entry.Moved = false
end

function CornWindController:_restoreActive()
	for entry in self._active do
		self:_restore(entry)
	end
	self._active = {}
	self._selected = {}
end

function CornWindController:_remove(layer: any, plant: Instance)
	local entry = layer.Entries[plant]
	if not entry then
		return
	end
	self:_restore(entry)
	self._active[entry] = nil
	layer.Entries[plant] = nil
	layer.Count -= 1
	local bucket = layer.Buckets[entry.Bucket]
	if bucket then
		bucket[entry] = nil
		if next(bucket) == nil then
			layer.Buckets[entry.Bucket] = nil
		end
	end
	local group = layer.Groups[entry.Parent]
	if group then
		group.Entries[plant] = nil
	end
	self._selectElapsed = SELECT_SEC
end

function CornWindController:_enqueue(layer: any, plant: Instance, parent: Instance)
	self._pendingTail += 1
	self._pending[self._pendingTail] = { Layer = layer, Plant = plant, Parent = parent }
end

function CornWindController:_register(job: any)
	local layer, plant, parent = job.Layer, job.Plant, job.Parent
	if
		self._layers[layer.Kind] ~= layer
		or layer.Entries[plant]
		or not self:_ownedLayer(layer.Folder, layer.Kind)
		or plant.Parent ~= parent
	then
		return
	end
	if layer.Kind == "near" then
		if
			not layer.Groups[parent]
			or plant.Name ~= "Corn"
			or plant:GetAttribute("CornPlantTemplateOwned") ~= true
		then
			return
		end
	elseif
		not plant.Name:match("^Far_%-?%d+_%-?%d+$")
		or plant:GetAttribute("CornClientBackdropOwned") ~= true
		or plant:GetAttribute("corn_project_id") ~= PROJECT_ID
	then
		return
	end
	local detailed = self._map:GetAttribute("HarvestArtVariant") == "B"
	local limit = if layer.Kind == "near"
		then (if detailed then 8192 else 4096)
		else (if detailed then 30000 else 20000)
	if layer.Count >= limit then
		return
	end
	local parts, frame, size = {}, nil, nil
	if plant:IsA("BasePart") then
		if not decorative(plant) then
			return
		end
		table.insert(parts, { Part = plant, Frame = plant.CFrame })
		frame, size = plant.CFrame, plant.Size
	elseif plant:IsA("Model") then
		for _, part in plant:GetDescendants() do
			if part:IsA("BasePart") then
				if not decorative(part) or #parts >= MAX_PARTS_PER_PLANT then
					return
				end
				table.insert(parts, { Part = part, Frame = part.CFrame })
			end
		end
		if #parts == 0 then
			return
		end
		frame, size = plant:GetBoundingBox()
	else
		return
	end
	local position = frame.Position
	local key =
		bucketKey(math.floor(position.X / BUCKET_SIZE), math.floor(position.Z / BUCKET_SIZE))
	local base = position - Vector3.new(0, size.Y / 2, 0)
	if plant:IsA("BasePart") and plant:GetAttribute("CornGreenOriginal") == true then
		local offset = plant:GetAttribute("HarvestRootOffset")
		local templateSize = plant:GetAttribute("CornGreenTemplateSize")
		if
			typeof(offset) == "Vector3"
			and typeof(templateSize) == "Vector3"
			and templateSize.X > 0
			and templateSize.Y > 0
			and templateSize.Z > 0
		then
			base = frame:PointToWorldSpace(
				-Vector3.new(
					offset.X * size.X / templateSize.X,
					offset.Y * size.Y / templateSize.Y,
					offset.Z * size.Z / templateSize.Z
				)
			)
		end
	end
	local entry = {
		Layer = layer,
		Plant = plant,
		Parent = parent,
		Parts = parts,
		Position = position,
		Base = base,
		Bucket = key,
		Phase = (position.X * 0.17 + position.Z * 0.11) % (math.pi * 2),
		Moved = false,
	}
	layer.Entries[plant] = entry
	layer.Count += 1
	if not layer.Buckets[key] then
		layer.Buckets[key] = {}
	end
	layer.Buckets[key][entry] = true
	if layer.Kind == "near" then
		layer.Groups[parent].Entries[plant] = true
	end
	self._selectElapsed = SELECT_SEC
end

function CornWindController:_indexBatch()
	local began, count = self._clock(), 0
	while
		self._pendingHead <= self._pendingTail
		and count < INDEX_BUDGET
		and self._clock() - began < INDEX_SECONDS
	do
		local job = self._pending[self._pendingHead]
		self._pending[self._pendingHead] = nil
		self._pendingHead += 1
		self:_register(job)
		count += 1
	end
	if self._pendingHead > self._pendingTail then
		self._pending, self._pendingHead, self._pendingTail = {}, 1, 0
	end
end

function CornWindController:_removeGroup(layer: any, folder: Instance)
	local group = layer.Groups[folder]
	if not group then
		return
	end
	disconnect(group.Connections)
	for plant in group.Entries do
		self:_remove(layer, plant)
	end
	layer.Groups[folder] = nil
end

function CornWindController:_bindGroup(layer: any, folder: Instance)
	if
		layer.Groups[folder]
		or not folder:IsA("Folder")
		or folder.Parent ~= layer.Folder
		or not folder.Name:match("^Chunk_")
	then
		return
	end
	local group = { Connections = {}, Entries = {} }
	layer.Groups[folder] = group
	table.insert(
		group.Connections,
		folder.ChildAdded:Connect(function(plant)
			self:_enqueue(layer, plant, folder)
		end)
	)
	table.insert(
		group.Connections,
		folder.ChildRemoved:Connect(function(plant)
			self:_remove(layer, plant)
		end)
	)
	for _, plant in folder:GetChildren() do
		self:_enqueue(layer, plant, folder)
	end
end

function CornWindController:_detachLayer(kind: string)
	local layer = self._layers[kind]
	if not layer then
		return
	end
	for _, group in layer.Groups do
		disconnect(group.Connections)
	end
	disconnect(layer.Connections)
	for _, entry in layer.Entries do
		self:_restore(entry)
		self._active[entry] = nil
	end
	self._layers[kind] = nil
	self._selectElapsed = SELECT_SEC
end

function CornWindController:_bindLayer(folder: Instance?, kind: string)
	local previous = self._layers[kind]
	if previous and previous.Folder == folder and self:_ownedLayer(previous.Folder, kind) then
		return
	end
	self:_detachLayer(kind)
	if not folder or not self:_ownedLayer(folder, kind) then
		return
	end
	local layer = {
		Kind = kind,
		Folder = folder,
		Connections = {},
		Entries = {},
		Buckets = {},
		Groups = {},
		Count = 0,
	}
	self._layers[kind] = layer
	table.insert(
		layer.Connections,
		folder.ChildAdded:Connect(function(plant)
			if kind == "near" then
				self:_bindGroup(layer, plant)
			else
				self:_enqueue(layer, plant, folder)
			end
		end)
	)
	table.insert(
		layer.Connections,
		folder.ChildRemoved:Connect(function(plant)
			if kind == "near" then
				self:_removeGroup(layer, plant)
			else
				self:_remove(layer, plant)
			end
		end)
	)
	for _, attribute in
		{
			"corn_project_id",
			if kind == "near" then "CornClientRendererOwned" else "CornClientBackdropOwned",
			"Ready",
		}
	do
		table.insert(
			layer.Connections,
			folder:GetAttributeChangedSignal(attribute):Connect(function()
				if not self:_ownedLayer(folder, kind) then
					self:_detachLayer(kind)
				elseif kind == "far" and folder:GetAttribute("Ready") ~= true then
					folder:SetAttribute("CornWindAnimated", 0)
					for entry in self._active do
						if entry.Layer == layer then
							self:_restore(entry)
							self._active[entry] = nil
						end
					end
				end
				self._selectElapsed = SELECT_SEC
			end)
		)
	end
	for _, plant in folder:GetChildren() do
		if kind == "near" then
			self:_bindGroup(layer, plant)
		else
			self:_enqueue(layer, plant, folder)
		end
	end
end

function CornWindController:_clearMap()
	self._monsterSamples = {}
	self:_detachLayer("near")
	self:_detachLayer("far")
	disconnect(self._mapConnections)
	self._map = nil
	self._pending, self._pendingHead, self._pendingTail = {}, 1, 0
	self:_restoreActive()
end

function CornWindController:_resolveMap()
	local map = Workspace:FindFirstChild("CornMap")
	if
		not map
		or not map:IsA("Model")
		or map:GetAttribute("corn_project_id") ~= PROJECT_ID
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
			map.AncestryChanged:Connect(function()
				if self._map == map and map.Parent ~= Workspace then
					self:_clearMap()
				end
			end)
		)
		table.insert(
			self._mapConnections,
			map:GetAttributeChangedSignal("corn_project_id"):Connect(function()
				if self._map == map and map:GetAttribute("corn_project_id") ~= PROJECT_ID then
					self:_clearMap()
				end
			end)
		)
		table.insert(
			self._mapConnections,
			map.ChildAdded:Connect(function(item)
				if item.Name == "CornClientPlants" then
					self:_bindLayer(item, "near")
				elseif item.Name == "CornClientBackdrop" then
					self:_bindLayer(item, "far")
				end
			end)
		)
		table.insert(
			self._mapConnections,
			map.ChildRemoved:Connect(function(item)
				for kind, layer in self._layers do
					if layer.Folder == item then
						self:_detachLayer(kind)
					end
				end
			end)
		)
	end
	self:_bindLayer(map:FindFirstChild("CornClientPlants"), "near")
	self:_bindLayer(map:FindFirstChild("CornClientBackdrop"), "far")
end

local function horizontalDistanceSquared(a: Vector3, b: Vector3): number
	local delta = a - b
	return delta.X * delta.X + delta.Z * delta.Z
end

local function visible(entry: any, camera: Camera): boolean
	if
		horizontalDistanceSquared(entry.Position, camera.CFrame.Position)
		> MONSTER_VIEW_RADIUS ^ 2
	then
		return false
	end
	local shown = false
	for _, saved in entry.Parts do
		if saved.Part.Transparency < 0.99 and saved.Part.LocalTransparencyModifier < 0.99 then
			shown = true
			break
		end
	end
	if not shown then
		return false
	end
	local screen, onScreen = camera:WorldToViewportPoint(entry.Position)
	return onScreen and screen.Z > 0
end

function CornWindController:_actorCandidates(
	camera: Camera,
	position: Vector3,
	front: Vector3?,
	active: any
): { any }
	local result, scanned = {}, 0
	for _, kind in { "near", "far" } do
		local layer = self._layers[kind]
		if
			not layer
			or not self:_ownedLayer(layer.Folder, kind)
			or (kind == "far" and layer.Folder:GetAttribute("Ready") ~= true)
		then
			continue
		end
		for x = math.floor((position.X - RADIUS) / BUCKET_SIZE), math.floor((position.X + RADIUS) / BUCKET_SIZE) do
			for z = math.floor((position.Z - RADIUS) / BUCKET_SIZE), math.floor((position.Z + RADIUS) / BUCKET_SIZE) do
				for entry in layer.Buckets[bucketKey(x, z)] or {} do
					scanned += 1
					if scanned > SCAN_LIMIT then
						break
					end
					local delta = entry.Position - position
					local distance = delta.X * delta.X + delta.Z * delta.Z
					local ahead = front == nil
						or distance <= 1.8 ^ 2
						or delta.X * front.X + delta.Z * front.Z >= 0
					if
						distance <= RADIUS ^ 2
						and ahead
						and not active[entry]
						and math.abs(position.Y - entry.Base.Y) <= 7
						and self:_validEntry(entry)
						and visible(entry, camera)
					then
						table.insert(result, { Entry = entry, Distance = distance })
					end
				end
				if scanned > SCAN_LIMIT then
					break
				end
			end
			if scanned > SCAN_LIMIT then
				break
			end
		end
		if scanned > SCAN_LIMIT then
			break
		end
	end
	self._lastScanned += math.min(scanned, SCAN_LIMIT)
	table.sort(result, function(a, b)
		return a.Distance < b.Distance
	end)
	local selected = {}
	for index = 1, math.min(ACTOR_LIMIT, #result) do
		table.insert(selected, result[index].Entry)
	end
	return selected
end

function CornWindController:_playerPosition(): Vector3?
	local character = self._player and self._player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		self._playerRoot, self._previousPlayer, self._playerTrail = nil, nil, 0
		return nil
	end
	if self._playerRoot ~= root then
		self:_restoreActive()
		self._playerRoot, self._previousPlayer, self._playerTrail = root, nil, 0
	end
	local position = root.Position
	if
		humanoid.MoveDirection.Magnitude > 0.05
		or (
			self._previousPlayer
			and horizontalDistanceSquared(position, self._previousPlayer) > 0.01
		)
	then
		self._playerTrail = self._time + TRAIL_SEC
	end
	self._previousPlayer = position
	return if self._playerTrail > self._time then position else nil
end

function CornWindController:_monsterPosition(): Vector3?
	local runtime = self._map and self._map:FindFirstChild("CornRoundRuntime")
	local nearest, nearestRoot, distance = nil, nil, math.huge
	for index = 1, 3 do
		local monster = runtime
			and runtime:IsA("Folder")
			and runtime:GetAttribute("corn_project_id") == PROJECT_ID
			and runtime:FindFirstChild(if index == 1 then "Monster" else "Monster" .. index)
		local root = monster and monster:FindFirstChild("Root")
		local state = monster and monster:GetAttribute("HuntState")
		if
			not monster
			or not monster:IsA("Model")
			or monster:GetAttribute("CornMonsterOwned") ~= true
			or monster:GetAttribute("corn_project_id") ~= PROJECT_ID
			or monster:GetAttribute("MonsterRigVersion") ~= 1
			or monster:GetAttribute("MonsterIndex") ~= index
			or not root
			or not root:IsA("BasePart")
			or (state ~= "patrol" and state ~= "chase")
		then
			self._monsterSamples[index] = nil
			continue
		end
		local sample = self._monsterSamples[index]
		if not sample or sample.root ~= root then
			sample = { root = root, previous = root.Position, untilAt = 0 }
			self._monsterSamples[index] = sample
		end
		local position = root.Position
		if horizontalDistanceSquared(position, sample.previous) > 0.01 then
			sample.untilAt = self._time + TRAIL_SEC
		end
		sample.previous = position
		local candidate = if self._playerRoot
			then horizontalDistanceSquared(position, self._playerRoot.Position)
			else math.huge
		if sample.untilAt > self._time and candidate < distance then
			nearest, nearestRoot, distance = sample, root, candidate
		end
	end
	self._monsterRoot = nearestRoot
	self._previousMonster = if nearest then nearest.previous else nil
	self._monsterTrail = if nearest then nearest.untilAt else 0
	return if nearest then nearest.previous else nil
end

function CornWindController:_select(camera: Camera)
	local chosen, active = {}, {}
	self._lastScanned = 0
	local function add(position: Vector3?, front: Vector3?)
		if not position then
			return
		end
		for _, entry in self:_actorCandidates(camera, position, front, active) do
			active[entry] = true
			table.insert(chosen, entry)
		end
	end
	add(self:_playerPosition(), camera.CFrame.LookVector)
	if self._playerRoot then
		add(self:_monsterPosition(), nil)
	end
	for entry in self._active do
		if not active[entry] then
			self:_restore(entry)
		end
	end
	self._active, self._selected = active, chosen
end

function CornWindController:_diagnostics(near: number, far: number)
	for kind, layer in self._layers do
		if self:_ownedLayer(layer.Folder, kind) then
			local count = if kind == "near" then near else far
			if layer.Folder:GetAttribute("CornWindAnimated") ~= count then
				layer.Folder:SetAttribute("CornWindAnimated", count)
			end
			if layer.Folder:GetAttribute("CornWindMode") ~= (self._mode or "off") then
				layer.Folder:SetAttribute("CornWindMode", self._mode or "off")
			end
		end
	end
end

function CornWindController:_animate(camera: Camera)
	local writes, near, far = 0, 0, 0
	for _, entry in self._selected do
		if writes + #entry.Parts > PART_LIMIT then
			break
		end
		if
			not self._active[entry]
			or not self:_validEntry(entry)
			or (entry.Layer.Kind == "far" and entry.Layer.Folder:GetAttribute("Ready") ~= true)
			or not visible(entry, camera)
		then
			self:_restore(entry)
			continue
		end
		local phase = entry.Phase
		local x = ANGLE * 0.75 * math.sin(self._time * 7 + phase)
		local z = ANGLE * 0.35 * math.sin(self._time * 5 + phase * 1.4)
		local transform = CFrame.new(entry.Base) * CFrame.Angles(x, 0, z) * CFrame.new(-entry.Base)
		for _, saved in entry.Parts do
			saved.Part.CFrame = transform * saved.Frame
		end
		entry.Moved = true
		writes += #entry.Parts
		if entry.Layer.Kind == "near" then
			near += 1
		else
			far += 1
		end
	end
	self._lastWrites, self._lastNear, self._lastFar = writes, near, far
	self:_diagnostics(near, far)
end

function CornWindController:SetMode(mode: string?)
	local nextMode = if mode == "easy" or mode == "medium" or mode == "hard" then mode else nil
	if self._mode == nextMode then
		return
	end
	self:_restoreActive()
	self._mode = nextMode
	self._previousPlayer, self._previousMonster = nil, nil
	self._monsterSamples = {}
	self._playerTrail, self._monsterTrail = 0, 0
	self._updateElapsed, self._selectElapsed = UPDATE_SEC, SELECT_SEC
	self._lastWrites, self._lastNear, self._lastFar = 0, 0, 0
	self:_diagnostics(0, 0)
end

function CornWindController:_step(delta: number)
	self._time += math.clamp(delta, 0, 0.25)
	self._resolveElapsed += delta
	if self._resolveElapsed >= RESOLVE_SEC then
		self._resolveElapsed = 0
		self:_resolveMap()
	end
	self:_indexBatch()
	if not self._mode then
		return
	end
	self._updateElapsed += delta
	self._selectElapsed += delta
	if self._updateElapsed < UPDATE_SEC then
		return
	end
	self._updateElapsed = 0
	local camera = Workspace.CurrentCamera
	if
		not camera
		or not self._map
		or self._map.Parent ~= Workspace
		or self._map:GetAttribute("corn_project_id") ~= PROJECT_ID
	then
		self:_restoreActive()
		return
	end
	if self._selectElapsed >= SELECT_SEC then
		self._selectElapsed = 0
		self:_select(camera)
	end
	self:_animate(camera)
end

function CornWindController:Init(context: any)
	self._enabled = RunService:IsStudio()
		and context.Config.Environment == "DEV"
		and (
			context.Config.Game.SessionMode == "solo_local"
			or context.Config.Game.SessionMode == "team_local"
		)
	self._connection, self._player = nil, Players.LocalPlayer
	self._clock = os.clock
	self._map, self._mode = nil, nil
	self._layers, self._mapConnections, self._active, self._selected = {}, {}, {}, {}
	self._pending, self._pendingHead, self._pendingTail = {}, 1, 0
	self._time, self._resolveElapsed, self._updateElapsed, self._selectElapsed =
		0, RESOLVE_SEC, UPDATE_SEC, SELECT_SEC
	self._lastWrites, self._lastNear, self._lastFar, self._lastScanned = 0, 0, 0, 0
	self._previousPlayer, self._previousMonster, self._playerRoot, self._monsterRoot =
		nil, nil, nil, nil
	self._playerTrail, self._monsterTrail = 0, 0
	self._monsterSamples = {}
end

function CornWindController:Start()
	if not self._enabled or self._connection then
		return
	end
	self:_resolveMap()
	self._connection = RunService.Heartbeat:Connect(function(delta)
		self:_step(delta)
	end)
end

function CornWindController:Destroy()
	self:SetMode(nil)
	self._enabled = false
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	self:_clearMap()
end

return CornWindController
