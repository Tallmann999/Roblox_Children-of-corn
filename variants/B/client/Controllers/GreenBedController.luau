-- B-only static soil. The authored session meshes regenerate after engine Save.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local gameModules = ReplicatedStorage:WaitForChild("GameShared"):WaitForChild("Game")
local Geometry = require(gameModules:WaitForChild("GreenBedGeometry"))
local Layout = require(gameModules:WaitForChild("GreenBedLayout"))
local OWNER = "corn_B_green_beds_v1"
local PROJECT = "children_of_corn"
local Controller = { Name = "GreenBedController", Order = 43 }

local function target()
	local map = workspace:FindFirstChild("CornMap")
	if
		map
		and map:IsA("Model")
		and map:GetAttribute("corn_project_id") == PROJECT
		and map:GetAttribute("HarvestArtVariant") == "B"
	then
		local field = map:FindFirstChild("FieldZone")
		if field and field:IsA("BasePart") and field.Size == Vector3.new(630, 10, 630) then
			return map
		end
	end
	return nil
end

local function owned(folder)
	if folder:GetAttribute("BGreenBedsOwner") ~= OWNER then
		return false
	end
	for _, item in folder:GetChildren() do
		if
			not item:IsA("MeshPart")
			or item:GetAttribute("BGreenBedsOwner") ~= OWNER
			or #item:GetChildren() ~= 0
		then
			return false
		end
	end
	return true
end

local SOURCES = {
	Center = {
		"SM_Env_Dirt_Rows_Center_01",
		"d74a40009c77e5aad34fff8449e96ef25cf292b419a75355aa3adb50c9914527",
		364,
	},
	End = {
		"SM_Env_Dirt_Rows_End_Top_01",
		"f635796ba1c7ff2f129e77404704444e112ac864a39b64d02636b4932bf9b586",
		469,
	},
	Skirt = {
		"SM_Env_Dirt_Skirt_01",
		"b944eb93ac814ff19320a24409f496a983e5c84faaa5ba7bbb07c555f1bb59b8",
		352,
	},
}
local PART_ATTRIBUTES = {
	BGreenBedsOwner = true,
	BGreenBedGeometryOwned = true,
	BGreenBedGeometryKey = true,
	BGreenBedSourceSHA256 = true,
	BGreenBedSourceTriangles = true,
	BGreenBedTile = true,
}

local function unchangedFrame(actual, expected)
	if not RunService:IsClient() then
		return actual == expected
	end
	local values = { expected:GetComponents() }
	for index, value in { actual:GetComponents() } do
		if
			value ~= value
			or math.abs(value - values[index]) > (if index <= 3 then 0.0001 else 0.00025)
		then
			return false
		end
	end
	return true
end

local function untouchedEditor(folder)
	if
		not folder:IsA("Folder")
		or not owned(folder)
		or #folder:GetTags() ~= 0
		or folder:GetAttribute("corn_project_id") ~= PROJECT
	then
		return false
	end
	for attribute in folder:GetAttributes() do
		if attribute ~= "BGreenBedsOwner" and attribute ~= "corn_project_id" then
			return false
		end
	end
	local children = folder:GetChildren()
	if #children ~= #Layout.SoilTiles then
		return false
	end
	local seen = {}
	for _, item in children do
		local index = item:GetAttribute("BGreenBedTile")
		if
			type(index) ~= "number"
			or index % 1 ~= 0
			or seen[index]
			or not Layout.SoilTiles[index]
		then
			return false
		end
		seen[index] = true
		local tile = Layout.SoilTiles[index]
		local source = SOURCES[tile.Key]
		if
			item.Name ~= source[1] .. "_" .. string.format("%04d", index)
			or item:GetAttribute("BGreenBedGeometryOwned") ~= true
			or item:GetAttribute("BGreenBedGeometryKey") ~= tile.Key
			or item:GetAttribute("BGreenBedSourceSHA256") ~= source[2]
			or item:GetAttribute("BGreenBedSourceTriangles") ~= source[3]
			or not unchangedFrame(item.CFrame, tile.Frame)
			or item.Size ~= tile.Size
			or item.PivotOffset ~= CFrame.identity
			or item.TextureID ~= "rbxassetid://95855894892409"
			or item.Color ~= Color3.new(1, 1, 1)
			or item.Material ~= Enum.Material.Plastic
			or item.Transparency ~= 0
			or item.Reflectance ~= 0
			or not item.Anchored
			or item.CanCollide
			or item.CanTouch
			or item.CanQuery
			or not item.CastShadow
			or not item.DoubleSided
			or #item:GetTags() ~= 0
		then
			return false
		end
		for attribute in item:GetAttributes() do
			if not PART_ATTRIBUTES[attribute] then
				return false
			end
		end
	end
	return true
end

function Controller:_restore()
	for part, value in self._hidden do
		if part.Parent then
			part.LocalTransparencyModifier = value
		end
	end
	table.clear(self._hidden)
end

function Controller:_clear()
	self._epoch += 1
	self:_restore()
	if self._folder and self._folder.Parent and owned(self._folder) then
		self._folder:Destroy()
	end
	self._folder, self._map = nil, nil
	self._index = 1
	self._ready = false
end

function Controller:_build(map)
	self:_clear()
	self._map = map
	local folder = Instance.new("Folder")
	folder.Name = "CornClientGreenBeds"
	folder:SetAttribute("BGreenBedsOwner", OWNER)
	folder:SetAttribute("corn_project_id", PROJECT)
	folder:SetAttribute("Ready", false)
	folder:SetAttribute("LoadedParts", 0)
	folder.Parent = map
	self._folder = folder
	self._building = true
	local epoch = self._epoch
	task.spawn(function()
		local ok, problem = pcall(Geometry.BuildTemplates)
		if epoch ~= self._epoch then
			return
		end
		self._building = false
		if not ok then
			self:_clear()
			self._failedMap = map
			warn("[GreenBedController] Saved preview retained: " .. tostring(problem))
		end
	end)
end

function Controller:_step(delta)
	self._poll += delta
	if self._poll >= 1 then
		self._poll = 0
		local map = target()
		if map ~= self._map then
			if map and map ~= self._failedMap then
				self:_build(map)
			else
				self:_clear()
			end
		end
	end
	if not self._map or not self._folder or self._building or self._ready then
		return
	end
	local start, count = os.clock(), 0
	while self._index <= #Layout.SoilTiles and count < 8 and os.clock() - start < 0.002 do
		local tile = Layout.SoilTiles[self._index]
		local item = Geometry.Clone(tile.Key, tile.Frame)
		item.Size = tile.Size
		item:SetAttribute("BGreenBedTile", self._index)
		item.Parent = self._folder
		self._index += 1
		count += 1
	end
	self._folder:SetAttribute("LoadedParts", self._index - 1)
	self._folder:SetAttribute("LastFrameClones", count)
	self._folder:SetAttribute("LastFrameSeconds", os.clock() - start)
	if self._index > #Layout.SoilTiles then
		local saved = self._map:FindFirstChild("GreenBedEditor")
		if saved then
			assert(untouchedEditor(saved), "Manual editor beds preserved")
			for _, item in saved:GetChildren() do
				self._hidden[item] = item.LocalTransparencyModifier
				item.LocalTransparencyModifier = 1
			end
		end
		self._ready = true
		self._folder:SetAttribute("Ready", true)
	end
end

function Controller:Init(context)
	self._enabled = RunService:IsStudio() and context.Config.Environment == "DEV"
	self._epoch, self._poll, self._index = 0, math.huge, 1
	self._hidden = {}
	self._ready, self._building = false, false
end

function Controller:Start()
	if not self._enabled or self._connection then
		return
	end
	self._connection = RunService.Heartbeat:Connect(function(delta)
		local ok, problem = pcall(self._step, self, delta)
		if not ok then
			local failed = self._map
			self:_clear()
			self._failedMap = failed
			warn(
				"[GreenBedController] Soil build failed; old preview retained: "
					.. tostring(problem)
			)
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
