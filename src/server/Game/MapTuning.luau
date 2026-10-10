--!strict
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Authoring = require(script.Parent:WaitForChild("MapAuthoring"))
local MapTuning = {}

local function torch(parent: Folder, id: string, position: Vector3)
	local model = Instance.new("Model")
	model.Name = id
	model:SetAttribute("corn_project_id", "children_of_corn")
	model:SetAttribute("CornTorchOwned", true)
	model:SetAttribute("torch_id", id)
	model:AddTag("corn_torch")
	local function part(name: string, size: Vector3, offset: Vector3, color: Color3): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = CFrame.new(position + offset)
		p.Color = color
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		p.Parent = model
		return p
	end
	local pole = part(
		"Pole",
		Vector3.new(0.45, 13, 0.45),
		Vector3.new(0, 6.5, 0),
		Color3.fromRGB(69, 48, 30)
	)
	pole.Material = Enum.Material.Wood
	local top = part(
		"Flame",
		Vector3.new(0.65, 0.8, 0.65),
		Vector3.new(0, 13, 0),
		Color3.fromRGB(255, 142, 40)
	)
	top.Material = Enum.Material.Neon
	local fire = Instance.new("Fire")
	fire.Name = "TorchFire"
	fire.Size = 3
	fire.Heat = 4
	fire.Color = Color3.fromRGB(255, 170, 60)
	fire.SecondaryColor = Color3.fromRGB(255, 70, 15)
	fire.Parent = top
	local light = Instance.new("PointLight")
	light.Name = "TorchLight"
	light.Color = Color3.fromRGB(255, 168, 86)
	light.Range = 18
	light.Brightness = 2
	light.Shadows = false
	light.Parent = top
	model.PrimaryPart = pole
	model.Parent = parent
end

function MapTuning.Apply(map: Model): any
	assert(RunService:IsStudio() and not RunService:IsRunning(), "Stop Play before map tuning")
	assert(
		map.Parent == workspace and map:GetAttribute("corn_project_id") == "children_of_corn",
		"Wrong Corn scene"
	)
	assert(
		not workspace:FindFirstChild("Asmr_Base") and not workspace:FindFirstChild("ASMR_Models"),
		"Wrong game"
	)
	assert(
		map:GetAttribute("MapTuningVersion") == nil,
		"Map tuning already installed; preserve manual edits"
	)
	local field = map:FindFirstChild("FieldZone") :: BasePart
	local ground = map:FindFirstChild("Ground") :: BasePart
	local bounds = map:FindFirstChild("PlayBounds") :: BasePart
	assert(
		field
			and ground
			and bounds
			and math.abs(field.Size.X - 1200) < 0.1
			and math.abs(field.Size.Z - 1200) < 0.1,
		"Expected 1200 field"
	)
	assert(field.CFrame.UpVector:Dot(Vector3.yAxis) > 0.9999, "Horizontal field required")
	local gateDoor = map.EscapeGate.Door :: BasePart
	local gatePosition = field.CFrame:PointToObjectSpace(gateDoor.Position)
	assert(
		math.abs(gatePosition.X) < 0.1
			and math.abs(gatePosition.Z - 601) < 0.1
			and math.abs(gateDoor.Size.X - 12) < 0.1,
		"Custom gate geometry requires a new resize plan; nothing changed"
	)
	local oldFolders = {}
	for _, name in { "EditorPreview", "EditorFieldOverview" } do
		local folder = map:FindFirstChild(name)
		assert(
			folder
				and folder:IsA("Folder")
				and folder:GetAttribute("corn_project_id") == "children_of_corn",
			"Unknown decoration folder"
		)
		for _, child in folder:GetChildren() do
			assert(
				child:IsA("BasePart")
					and (
						name == "EditorPreview" and child.Name == "Corn"
						or child:GetAttribute("CornEditorOverview") == true
					),
				"Manual decoration retained"
			)
		end
		table.insert(oldFolders, folder)
	end
	assert(not map:FindFirstChild("TorchMarkers"), "TorchMarkers collision")
	local original, pivots = {}, {}
	for _, item in map:GetDescendants() do
		if item:IsA("BasePart") then
			table.insert(original, { item = item, frame = item.CFrame, size = item.Size })
		elseif item:IsA("Model") then
			table.insert(pivots, { item = item, pivot = item.WorldPivot })
		end
	end
	local oldAttributes = map:GetAttributes()
	local oldLighting = {
		ClockTime = Lighting.ClockTime,
		Brightness = Lighting.Brightness,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		FogStart = Lighting.FogStart,
		FogEnd = Lighting.FogEnd,
		FogColor = Lighting.FogColor,
	}
	local marker = map.Props.ScarecrowMarker
	local hadHome = marker:HasTag("corn_monster_home")
	local oldHome = marker:GetAttribute("monster_home_id")
	local created = {}
	local function rollback()
		for _, item in created do
			item:Destroy()
		end
		for _, name in { "EditorPreview", "EditorFieldOverview" } do
			local item = map:FindFirstChild(name)
			if item then
				item:Destroy()
			end
		end
		for _, entry in original do
			entry.item.CFrame = entry.frame
			entry.item.Size = entry.size
		end
		for _, entry in pivots do
			entry.item.WorldPivot = entry.pivot
		end
		for _, item in oldFolders do
			item.Parent = map
		end
		for key in map:GetAttributes() do
			map:SetAttribute(key, nil)
		end
		for key, value in oldAttributes do
			map:SetAttribute(key, value)
		end
		for key, value in oldLighting do
			(Lighting :: any)[key] = value
		end
		if not hadHome then
			marker:RemoveTag("corn_monster_home")
		end
		marker:SetAttribute("monster_home_id", oldHome)
	end
	local ok, problem = pcall(function()
		for _, item in oldFolders do
			item.Parent = nil
		end
		local function reduced(position: Vector3): Vector3
			local localPoint = field.CFrame:PointToObjectSpace(position)
			return field.CFrame:PointToWorldSpace(
				Vector3.new(localPoint.X * 0.7, localPoint.Y, localPoint.Z * 0.7)
			)
		end
		for _, folder in { map.Props, map.KeySlots, map.CornerSpawns, map.NoCornZones } do
			for _, item in folder:GetChildren() do
				if item:IsA("Model") then
					local pivot = item:GetPivot()
					item:PivotTo(pivot + (reduced(pivot.Position) - pivot.Position))
				elseif item:IsA("BasePart") then
					item.CFrame += reduced(item.Position) - item.Position
				end
			end
		end
		local gate = map.EscapeGate
		local delta = field.CFrame:VectorToWorldSpace(Vector3.new(0, 0, -180))
		gate:PivotTo(gate:GetPivot() + delta)
		ground.Size = Vector3.new(840, ground.Size.Y, 840)
		field.Size = Vector3.new(840, field.Size.Y, 840)
		bounds.Size = Vector3.new(840, bounds.Size.Y, 880)
		local walls = map.Boundaries
		local function wall(name: string, x: number, z: number, sx: number, sz: number)
			local p = walls[name] :: BasePart
			local localPoint = field.CFrame:PointToObjectSpace(p.Position)
			p.CFrame = CFrame.new(field.CFrame:PointToWorldSpace(Vector3.new(x, localPoint.Y, z)))
				* p.CFrame.Rotation
			p.Size = Vector3.new(sx, p.Size.Y, sz)
		end
		wall("West", -421, 0, 2, 844)
		wall("East", 421, 0, 2, 844)
		wall("South", 0, -421, 840, 2)
		wall("NorthLeft", -213, 421, 414, 2)
		wall("NorthRight", 213, 421, 414, 2)
		local torches = Instance.new("Folder")
		torches.Name = "TorchMarkers"
		torches:SetAttribute("corn_project_id", "children_of_corn")
		torches:SetAttribute("CornTorchMarkersOwned", true)
		torches.Parent = map
		table.insert(created, torches)
		local floorY = ground.Position.Y + ground.Size.Y / 2
		for _, slot in map.KeySlots:GetChildren() do
			if slot:IsA("BasePart") then
				torch(
					torches,
					"torch_" .. slot.Name,
					Vector3.new(slot.Position.X, floorY, slot.Position.Z + 4)
				)
			end
		end
		local houses = 0
		for _, model in map.Props:GetChildren() do
			if model:IsA("Model") and model:FindFirstChild("DecorativeDoor") then
				houses += 1
				local door = model.DecorativeDoor :: BasePart
				for _, side in { -1, 1 } do
					local position = door.CFrame:PointToWorldSpace(Vector3.new(side * 6, 0, -3))
					torch(
						torches,
						"torch_" .. model.Name .. tostring(side),
						Vector3.new(position.X, floorY, position.Z)
					)
				end
			end
		end
		assert(houses == 3 and #torches:GetChildren() == 21, "Expected 15 slots / 3 houses")
		marker:AddTag("corn_monster_home")
		marker:SetAttribute("monster_home_id", "solo_home")
		map:SetAttribute("MapTuningVersion", 1)
		map:SetAttribute("TorchClearanceVersion", 1)
		map:SetAttribute("FieldSide", 840)
		map:SetAttribute("map_version", 3)
		Lighting.ClockTime = 20.5
		Lighting.Brightness = 1
		Lighting.Ambient = Color3.fromRGB(18, 22, 30)
		Lighting.OutdoorAmbient = Color3.fromRGB(38, 42, 53)
		Lighting.FogStart = 55
		Lighting.FogEnd = 320
		Lighting.FogColor = Color3.fromRGB(20, 27, 36)
		Authoring.RebuildOverview(map)
		Authoring.Preview(map, map.CornerSpawns.SW.Position, 75)
	end)
	if not ok then
		rollback()
		error("Map tuning rolled back: " .. tostring(problem))
	end
	for _, item in oldFolders do
		item:Destroy()
	end
	return {
		side = 840,
		torches = 21,
		overview = #map.EditorFieldOverview:GetChildren(),
		preview = #map.EditorPreview:GetChildren(),
	}
end

return MapTuning
