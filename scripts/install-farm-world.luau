-- Guarded local EditableMesh scene authoring. No upload or place-file serialization.
local RunService = game:GetService("RunService")
assert(RunService:IsStudio() and not RunService:IsRunning(), "Stop Children_of_corn Play first")
local map = workspace:FindFirstChild("CornMap")
assert(map and map:GetAttribute("corn_project_id") == "children_of_corn", "Wrong scene")
assert(
	not workspace:FindFirstChild("ASMR_Models") and not workspace:FindFirstChild("Asmr_Base"),
	"Wrong scene"
)
local storage = game:GetService("ServerStorage")
local props = assert(map:FindFirstChild("Props"), "Props missing")
local ground = assert(map:FindFirstChild("Ground"), "Ground missing")
local SharedGame = game.ReplicatedStorage.GameShared.Game
local Geometry = require(game.ServerScriptService.GameServer.Game.FarmGeometry)
local projectId = "children_of_corn"
local atlas = "rbxassetid://95855894892409"
local barnKey = "SM_Bld_Barn_03"
local assetKeys =
	{ barnKey, "SM_Prop_Truck_Rusted_01", "SM_Prop_Tyre_01", "SM_Prop_Rubbish_Pile_05" }
local houseNames = { "HouseWest", "HouseEast", "HouseNorthWest" }
local data = {}
local canonical = {}
for _, key in assetKeys do
	data[key] = require(SharedGame.FarmGeometryData:FindFirstChild(key))
	assert(
		data[key].file == key .. ".fbx" and data[key].index_base == 1,
		"Unexpected geometry data"
	)
end
local function unique(parent, name)
	local found
	for _, child in parent:GetChildren() do
		if child.Name == name then
			assert(not found, "Duplicate name: " .. name)
			found = child
		end
	end
	return found
end
local function own(instance, kind)
	instance:SetAttribute(kind, true)
	instance:SetAttribute("corn_project_id", projectId)
end
local templates = unique(storage, "CornFarmAssets")
local archive = unique(storage, "CornFarmSceneArchive")
if templates or archive then
	assert(
		templates and archive and templates:IsA("Folder") and archive:IsA("Folder"),
		"Partial farm installation"
	)
	assert(
		templates:GetAttribute("CornFarmAssetsOwned") == true
			and archive:GetAttribute("CornFarmArchiveOwned") == true,
		"Foreign farm folders"
	)
	assert(
		templates:GetAttribute("corn_project_id") == projectId
			and archive:GetAttribute("corn_project_id") == projectId,
		"Foreign project"
	)
	assert(
		#templates:GetChildren() == 4 and #archive:GetChildren() == 3,
		"Manual farm folder edits"
	)
	for _, key in assetKeys do
		local model = assert(unique(templates, key), "Template missing")
		assert(
			model:GetAttribute("CornFarmAssetOwned") == true
				and model:GetAttribute("AssetKey") == key,
			"Template ownership changed"
		)
		assert(#model:GetChildren() == #data[key].meshes, "Template children changed")
	end
	for _, name in houseNames do
		local house = assert(unique(props, name), "House missing")
		assert(
			house:GetAttribute("CornFarmAssetOwned") == true
				and house:GetAttribute("AssetKey") == barnKey,
			"Manual house replacement"
		)
		assert(unique(archive, name), "Archived house missing")
	end
	for _, name in
		{
			"RustedTruck",
			"Tyre_01",
			"Tyre_02",
			"Tyre_03",
			"Tyre_04",
			"Tyre_05",
			"RubbishPile_01",
			"RubbishPile_02",
			"RubbishPile_03",
		}
	do
		local model = assert(unique(props, name), "Farm prop missing")
		assert(
			model:GetAttribute("CornFarmAssetOwned") == true
				and model:GetAttribute("corn_project_id") == projectId,
			"Foreign farm prop"
		)
	end
	Geometry.Ensure()
	return { repeated = true, templates = 4, houses = 3, decorations = 9 }
end
local oldHouses = {}
for _, name in houseNames do
	local house = assert(unique(props, name), "Original house missing")
	assert(house:IsA("Model") and #house:GetChildren() == 5, "Unrecognized temporary house")
	local body, door, shell =
		unique(house, "Body"), unique(house, "DecorativeDoor"), unique(house, "OpenBarnShell")
	assert(body and door and body:IsA("Part") and door:IsA("Part"), "Unknown original house")
	assert(
		body.Size == Vector3.new(20, 12, 24) and door.Size == Vector3.new(4, 7, 0.25),
		"Manual house sizing"
	)
	assert(
		body.Transparency == 1
			and door.Transparency == 1
			and not body.CanCollide
			and not door.CanCollide,
		"Open-barn predecessor required"
	)
	assert(
		shell and shell:GetAttribute("CornOpenBarnShellOwned") == true and #shell:GetChildren() == 6,
		"Unknown open shell"
	)
	for _, descendant in house:GetDescendants() do
		assert(not descendant:IsA("LuaSourceContainer"), "Original house contains code")
	end
	table.insert(
		oldHouses,
		{ model = house, center = body.Position, rotation = body.CFrame.Rotation }
	)
end
for _, name in
	{
		"RustedTruck",
		"Tyre_01",
		"Tyre_02",
		"Tyre_03",
		"Tyre_04",
		"Tyre_05",
		"RubbishPile_01",
		"RubbishPile_02",
		"RubbishPile_03",
	}
do
	assert(not unique(props, name), "Farm prop name collision: " .. name)
end
local function vector(values)
	return Vector3.new(values[1], values[2], values[3])
end
local function createModel(name, key, frame, scale, openDoors)
	local model = Instance.new("Model")
	model.Name = name
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	own(model, "CornFarmAssetOwned")
	model:SetAttribute("AssetKey", key)
	model:SetAttribute("FarmGeometryVersion", 1)
	model:SetAttribute("SourceFbxSHA256", data[key].source_sha256)
	model:SetAttribute("FarmUniformScale", scale)
	for index, mesh in data[key].meshes do
		local part = assert(canonical[key .. "/" .. index].part, "Canonical mesh missing"):Clone()
		part.Name = mesh.name
		own(part, "CornFarmMeshOwned")
		part:SetAttribute("AssetKey", key)
		part:SetAttribute("MeshIndex", index)
		part:SetAttribute("FarmGeometryVersion", 1)
		part.Anchored = true
		part.CanTouch = false
		part.CanCollide = true
		part.CanQuery = true
		part.Size = vector(mesh.world_bounds.size) * scale
		part.CFrame = frame * CFrame.new(vector(mesh.world_bounds.center) * scale)
		part.TextureID = atlas
		part.Color = Color3.new(1, 1, 1)
		part.Material = Enum.Material.SmoothPlastic
		if openDoors and string.find(mesh.name, "_Door_", 1, true) then
			part.Transparency = 1
			part.CanCollide = false
			part.CanQuery = false
			part.CastShadow = false
			part:SetAttribute("FarmDoorHeldOpen", true)
		end
		part.Parent = model
	end
	model.WorldPivot = frame
	return model
end
local topY = ground.Position.Y + ground.Size.Y / 2
local made = {}
local function floorFrame(x, z, yaw, key, scale)
	return CFrame.new(x, topY - data[key].world_bounds.min[2] * scale, z)
		* CFrame.Angles(0, math.rad(yaw), 0)
end
local function placed(name, key, x, z, yaw, scale, openDoors)
	local model = createModel(name, key, floorFrame(x, z, yaw, key, scale), scale, openDoors)
	table.insert(made, model)
	return model
end
local history = game:GetService("ChangeHistoryService")
history:SetWaypoint("Before local FBX farm authoring")
local ok, problem = pcall(function()
	local Builder = require(SharedGame.FarmEditableMeshBuilder)
	for _, key in assetKeys do
		for index, meshData in data[key].meshes do
			local mesh = Builder.Build(meshData, 500)
			local entry = { mesh = mesh }
			canonical[key .. "/" .. index] = entry
			entry.part = game.AssetService:CreateMeshPartAsync(Content.fromObject(mesh), {
				CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition,
				RenderFidelity = Enum.RenderFidelity.Automatic,
			})
		end
	end
	templates = Instance.new("Folder")
	templates.Name = "CornFarmAssets"
	own(templates, "CornFarmAssetsOwned")
	archive = Instance.new("Folder")
	archive.Name = "CornFarmSceneArchive"
	own(archive, "CornFarmArchiveOwned")
	for _, key in assetKeys do
		createModel(key, key, CFrame.new(), 1, false).Parent = templates
	end
	local barnScale = 7.5 / 351.6280822753906
	for _, old in oldHouses do
		placed(old.model.Name, barnKey, old.center.X, old.center.Z, -90, barnScale, true)
	end
	placed(
		"RustedTruck",
		"SM_Prop_Truck_Rusted_01",
		3,
		140,
		20,
		18 / data.SM_Prop_Truck_Rusted_01.world_bounds.size[3],
		false
	)
	local tyreScale = 1.8 / data.SM_Prop_Tyre_01.world_bounds.size[1]
	placed("Tyre_01", "SM_Prop_Tyre_01", -114.5, -137, 0, tyreScale, false)
	placed("Tyre_02", "SM_Prop_Tyre_01", 158.5, 79, 30, tyreScale, false)
	placed("Tyre_03", "SM_Prop_Tyre_01", -282.5, 164, -10, tyreScale, false)
	placed("Tyre_04", "SM_Prop_Tyre_01", 9.8, 129, 25, tyreScale, false)
	placed("Tyre_05", "SM_Prop_Tyre_01", 11.7, 128, 0, tyreScale, false)
	local rubbishScale = 3.2 / data.SM_Prop_Rubbish_Pile_05.world_bounds.size[1]
	placed("RubbishPile_01", "SM_Prop_Rubbish_Pile_05", -114.5, -131, 40, rubbishScale, false)
	placed("RubbishPile_02", "SM_Prop_Rubbish_Pile_05", 160, 86, 15, rubbishScale, false)
	placed("RubbishPile_03", "SM_Prop_Rubbish_Pile_05", 10.2, 135, -35, rubbishScale, false)
	templates.Parent = storage
	archive.Parent = storage
	for _, old in oldHouses do
		old.model.Parent = archive
	end
	for _, model in made do
		model.Parent = props
	end
	Geometry.Ensure()
end)
for _, entry in canonical do
	if entry.part then
		entry.part:Destroy()
	end
	entry.mesh:Destroy()
end
if not ok then
	for _, model in made do
		model:Destroy()
	end
	for _, old in oldHouses do
		old.model.Parent = props
	end
	if templates then
		templates:Destroy()
	end
	if archive then
		archive:Destroy()
	end
	error("Farm installation rolled back: " .. tostring(problem))
end
history:SetWaypoint("Installed local FBX farm")
return { templates = 4, houses = 3, decorations = 9, archivedHouses = 3, localEditableMesh = true }
