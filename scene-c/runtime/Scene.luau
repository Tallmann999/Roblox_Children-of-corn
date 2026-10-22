-- Isolated C test. This module never binds to A/B code or map containers.
local Geometry = require(script.Parent.Geometry)
local Layout = require(script.Parent.Layout)
local Scene = {}
local PROJECT = "children_of_corn_C_test"
local VERSION = 1
local PART_COUNT = 368
local ASSETS = {
	Grass = {
		"SM_Generic_Grass_Patch_01",
		"72e76ced16844dab4b24895521f2bc3701e156f99918e0181ebfc8337ef40179",
		42,
	},
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
	Corn = {
		"SM_Prop_Plant_Corn_01_L",
		"259fbe167d4c0a24e6813282a5f3026d582b67d7af1f701bad39bed706a193df",
		510,
	},
}
-- Persist the authored public properties so a later Play never silently replaces
-- a manually edited mesh. Enum/optional values use strings supported by attributes.
local PLACED_PROPERTIES = {
	"CFrame",
	"Size",
	"TextureID",
	"MeshId",
	"MeshSize",
	"PivotOffset",
	"Material",
	"MaterialVariant",
	"Reflectance",
	"Color",
	"Transparency",
	"Anchored",
	"CanCollide",
	"CanTouch",
	"CanQuery",
	"CastShadow",
	"DoubleSided",
	"RenderFidelity",
	"CollisionFidelity",
	"Archivable",
	"Locked",
	"CollisionGroup",
	"Massless",
	"RootPriority",
	"CustomPhysicalProperties",
	"TopSurface",
	"BottomSurface",
	"FrontSurface",
	"BackSurface",
	"LeftSurface",
	"RightSurface",
}
local PART_ATTRIBUTES = {
	SceneCGeometryOwned = true,
	SceneCGeometryKey = true,
	SceneCSourceSHA256 = true,
	SceneCSourceTriangles = true,
	SceneCPlacement = true,
}
for _, property in PLACED_PROPERTIES do
	PART_ATTRIBUTES["SceneCPlaced" .. property] = true
end

local function propertyValue(item, property)
	local value = item[property]
	if value == nil then
		return "nil"
	end
	local kind = typeof(value)
	if kind == "EnumItem" or kind == "PhysicalProperties" then
		return tostring(value)
	end
	return value
end

local function frameFor(pose)
	local position = pose.position
	return CFrame.new(position[1], position[2], position[3]) * CFrame.Angles(0, pose.yaw, 0)
end

local function samePlacedFrame(actual, expected)
	if actual == expected then
		return true
	end
	local run = game:GetService("RunService")
	if not (run:IsRunning() and run:IsClient()) or typeof(expected) ~= "CFrame" then
		return false
	end
	-- Replicated Part CFrames compress rotation separately from CFrame attributes.
	-- Only the client accepts this bounded transport error; authoring/server stay exact.
	local actualComponents = { actual:GetComponents() }
	local expectedComponents = { expected:GetComponents() }
	for index, value in actualComponents do
		local tolerance = if index <= 3 then 0.0001 else 0.00025
		local difference = math.abs(value - expectedComponents[index])
		if difference ~= difference or difference > tolerance then
			return false
		end
	end
	return true
end

local function validateDecor(folder)
	assert(folder:IsA("Folder"), "Foreign decoration container preserved")
	assert(folder:GetAttribute("corn_project_id") == PROJECT, "Foreign decoration folder preserved")
	assert(
		folder:GetAttribute("SceneCTestVersion") == VERSION,
		"Changed C decoration version preserved"
	)
	for attribute in folder:GetAttributes() do
		assert(
			attribute == "corn_project_id" or attribute == "SceneCTestVersion",
			"Manual decoration attribute preserved"
		)
	end
	assert(
		#game:GetService("CollectionService"):GetTags(folder) == 0,
		"Manual decoration tags preserved"
	)
	local children = folder:GetChildren()
	assert(
		#children == PART_COUNT and #Layout.poses == PART_COUNT,
		"Missing or additional C decoration preserved"
	)
	local placements = {}
	for _, item in children do
		assert(
			item:IsA("MeshPart") and #item:GetChildren() == 0,
			"Manual decoration child or descendant preserved"
		)
		assert(
			#game:GetService("CollectionService"):GetTags(item) == 0,
			"Manual mesh tags preserved"
		)
		local index = item:GetAttribute("SceneCPlacement")
		assert(
			type(index) == "number" and index % 1 == 0 and index >= 1 and index <= PART_COUNT,
			"Invalid C placement preserved"
		)
		assert(not placements[index], "Duplicate C placement preserved")
		placements[index] = item
		local pose = Layout.poses[index]
		local asset = assert(ASSETS[pose.key], "Unknown C layout asset")
		assert(
			item.Name == asset[1] and item:GetAttribute("SceneCGeometryKey") == pose.key,
			"Renamed or replaced C mesh preserved"
		)
		assert(
			item:GetAttribute("SceneCGeometryOwned") == true
				and item:GetAttribute("SceneCSourceSHA256") == asset[2]
				and item:GetAttribute("SceneCSourceTriangles") == asset[3],
			"Changed C geometry metadata preserved"
		)
		for attribute in item:GetAttributes() do
			assert(PART_ATTRIBUTES[attribute], "Manual mesh attribute preserved: " .. attribute)
		end
		for _, property in PLACED_PROPERTIES do
			local actual = propertyValue(item, property)
			local expected = item:GetAttribute("SceneCPlaced" .. property)
			assert(
				if property == "CFrame"
					then samePlacedFrame(actual, expected)
					else actual == expected,
				"Manually changed C property preserved: " .. property
			)
		end
		assert(samePlacedFrame(item.CFrame, frameFor(pose)), "Moved C placement preserved")
		assert(
			item.Anchored
				and not item.CanCollide
				and not item.CanTouch
				and not item.CanQuery
				and item.CastShadow
				and item.DoubleSided
				and item.Transparency == 0
				and item.Color == Color3.new(1, 1, 1)
				and item.Material == Enum.Material.Plastic
				and item.Reflectance == 0,
			"Changed C mesh settings preserved"
		)
	end
	return placements
end

local function authorize()
	local run = game:GetService("RunService")
	assert(run:IsStudio(), "Scene C is a local Studio inspection scene")
	if run:IsRunning() then
		local world = workspace:FindFirstChild("CornCTestWorld")
		assert(
			world and world:GetAttribute("corn_project_id") == PROJECT,
			"Authored C world required in Play"
		)
	else
		assert(
			game.Name == "Children_of_corn_C.rbxl" or game.Name == "Children_of_corn_TestScene.rbxl",
			"Separate C scene required"
		)
	end
	assert(not workspace:FindFirstChild("CornMap"), "A/B CornMap must never be modified by C")
end

local function own(item)
	item:SetAttribute("corn_project_id", PROJECT)
	item:SetAttribute("SceneCTestVersion", VERSION)
	return item
end

local function part(name, size, frame, parent)
	local item = own(Instance.new("Part"))
	item.Name = name
	item.Anchored = true
	item.Size = size
	item.CFrame = frame
	item.TopSurface = Enum.SurfaceType.Smooth
	item.BottomSurface = Enum.SurfaceType.Smooth
	item.Parent = parent
	return item
end

function Scene.AuthorWorld()
	authorize()
	local existing = workspace:FindFirstChild("CornCTestWorld")
	if existing then
		assert(
			existing:IsA("Model") and existing:GetAttribute("corn_project_id") == PROJECT,
			"Foreign C root preserved"
		)
		assert(
			existing:GetAttribute("SceneCTestVersion") == VERSION,
			"Changed C world version preserved"
		)
		return existing
	end
	local world = own(Instance.new("Model"))
	world.Name = "CornCTestWorld"
	world:SetAttribute("SceneCServerReady", false)
	local ground = part("Ground", Vector3.new(96, 1, 96), CFrame.new(0, -0.45, 0), world)
	ground.Material = Enum.Material.Grass
	ground.Color = Color3.fromRGB(91, 112, 59)
	world.PrimaryPart = ground
	for _, side in { -1, 1 } do
		local floor = part(
			"SmoothWalkFloor" .. (if side < 0 then "West" else "East"),
			Vector3.new(Layout.fieldTile, 0.2, Layout.fieldTile * 3),
			CFrame.new(side * Layout.bedCenterX, Layout.fieldColliderTop - 0.1, 0),
			world
		)
		floor.Transparency = 1
		floor.CastShadow = false
	end
	local spawn = own(Instance.new("SpawnLocation"))
	spawn.Name = "CTestSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(4, 1, 4)
	spawn.CFrame = CFrame.new(0, 0.55, 39)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanTouch = false
	spawn.CastShadow = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = world
	world.Parent = workspace
	return world
end

function Scene.Ensure(peer)
	authorize()
	assert(peer == "Edit" or peer == "Server" or peer == "Client", "Explicit C peer required")
	local world = Scene.AuthorWorld()
	local name = if peer == "Client" then "ClientDecor" else "Decor"
	local previous = world:FindFirstChild(name)
	if previous then
		validateDecor(previous)
	end
	local serverDecor = if peer == "Client" then world:FindFirstChild("Decor") else nil
	if peer == "Client" then
		assert(serverDecor, "Complete replicated C server decor required")
		validateDecor(serverDecor)
	end
	Geometry.BuildTemplates()
	local result = own(Instance.new("Folder"))
	result.Name = name
	local ok, problem = pcall(function()
		for index, pose in Layout.poses do
			local item = Geometry.Clone(pose.key, frameFor(pose))
			item:SetAttribute("SceneCPlacement", index)
			for _, property in PLACED_PROPERTIES do
				item:SetAttribute("SceneCPlaced" .. property, propertyValue(item, property))
			end
			item.Parent = result
			if index % 64 == 0 then
				task.wait()
			end
		end
		validateDecor(result)
	end)
	if not ok then
		result:Destroy()
		error("Scene C layout preparation failed; old scene preserved: " .. tostring(problem), 0)
	end
	local visibility = {}
	local published, publishProblem = pcall(function()
		-- Preparation yields; recheck the old scene immediately before publication.
		if previous then
			assert(previous.Parent == world, "Changed C decoration parent preserved")
			validateDecor(previous)
		end
		if serverDecor then
			assert(serverDecor.Parent == world, "Changed server decoration parent preserved")
			for _, item in validateDecor(serverDecor) do
				visibility[item] = item.LocalTransparencyModifier
				item.LocalTransparencyModifier = 1
			end
		end
		result.Parent = world
	end)
	if not published then
		for item, value in visibility do
			item.LocalTransparencyModifier = value
		end
		result:Destroy()
		error(
			"Scene C publication failed; previous visibility preserved: "
				.. tostring(publishProblem),
			0
		)
	end
	if previous then
		previous:Destroy()
	end
	if peer == "Server" then
		world:SetAttribute("SceneCServerReady", true)
	end
	return { peer = peer, corn = 288, grass = 68, soil = 12, parts = 368 }
end

function Scene.WaitForServerDecor(timeout)
	authorize()
	assert(
		type(timeout) == "number" and timeout > 0 and timeout <= 60,
		"Bounded C replication wait required"
	)
	local world = Scene.AuthorWorld()
	local deadline = os.clock() + timeout
	local lastProblem = "Server geometry is not ready"
	repeat
		local folder = world:FindFirstChild("Decor")
		if world:GetAttribute("SceneCServerReady") and folder then
			local ok, problem = pcall(validateDecor, folder)
			if ok then
				return folder
			end
			lastProblem = tostring(problem)
		end
		task.wait(0.1)
	until os.clock() >= deadline
	error("Scene C replication incomplete; server visibility preserved: " .. lastProblem, 0)
end

function Scene.ValidateDecor(folder)
	authorize()
	return validateDecor(folder)
end

return table.freeze(Scene)
