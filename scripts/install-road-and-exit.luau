--!strict
-- Guarded authoring only; exact engine backup/save is handled by the caller.
local run = game:GetService("RunService")
local world = game:GetService("Workspace")
local history = game:GetService("ChangeHistoryService")
local PROJECT = "children_of_corn"
local OWNED = "CornRoadExitOwned"
local ROAD = "VillageRoad"
local MESH = "rbxassetid://104111861186519"
local WIDTH, LENGTH, CLEAR_WIDTH = 14, 840, 18
local HIDE_HALF = CLEAR_WIDTH / 2 + 1.5

local function same(a: any, b: any): boolean
	if a == b then
		return true
	end
	if typeof(a) ~= typeof(b) then
		return false
	end
	if typeof(a) == "CFrame" then
		return (a.Position - b.Position).Magnitude < 0.0002
			and a.RightVector:Dot(b.RightVector) > 0.99999
			and a.UpVector:Dot(b.UpVector) > 0.99999
	elseif typeof(a) == "Vector3" or typeof(a) == "Vector2" then
		return (a - b).Magnitude < 0.0002
	elseif typeof(a) == "Color3" then
		return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < 0.00001
	elseif typeof(a) == "number" then
		return math.abs(a - b) < 0.00001
	end
	return a == b
end
local function exactPart(parent: Instance, name: string): BasePart
	local item = parent:FindFirstChild(name)
	assert(item and item.ClassName == "Part", "Missing/unknown map part: " .. name)
	return item :: BasePart
end
assert(run:IsStudio() and not run:IsRunning(), "Stop Play; road authoring requires Studio Edit")
assert(
	not world:FindFirstChild("Asmr_Base") and not world:FindFirstChild("ASMR_Models"),
	"Wrong game; nothing changed"
)
local map = world:FindFirstChild("CornMap")
assert(
	map and map:IsA("Model") and map:GetAttribute("corn_project_id") == PROJECT,
	"Open Children_of_corn; nothing changed"
)
assert(
	map:GetAttribute("map_version") == 3
		and map:GetAttribute("MapTuningVersion") == 1
		and map:GetAttribute("TorchClearanceVersion") == 1,
	"Unknown map revision; nothing changed"
)
for _, name in { "CornRoundRuntime", "CornClientPlants", "CornClientBackdrop" } do
	assert(not map:FindFirstChild(name), "Live runtime; stop Play: " .. name)
end
local field, ground = exactPart(map, "FieldZone"), exactPart(map, "Ground")
assert(
	same(field.Size, Vector3.new(840, 10, 840)) and same(ground.Size, Vector3.new(840, 2, 840)),
	"Unknown field/ground size"
)
assert(
	field.CFrame.UpVector:Dot(Vector3.yAxis) > 0.99999
		and ground.CFrame.UpVector:Dot(Vector3.yAxis) > 0.99999,
	"Horizontal field/ground required"
)
assert(
	field.CFrame.RightVector:Dot(ground.CFrame.RightVector) > 0.99999,
	"Ground/field rotation mismatch"
)
local floorY = ground.CFrame.Position.Y + ground.Size.Y / 2
assert(math.abs(field.CFrame.Position.Y - floorY - 5) < 0.001, "Field/ground heights mismatch")
assert(
	(Vector3.new(field.CFrame.Position.X, 0, field.CFrame.Position.Z) - Vector3.new(
		ground.CFrame.Position.X,
		0,
		ground.CFrame.Position.Z
	)).Magnitude < 0.001,
	"Field/ground centers mismatch"
)
local props, torches = map:FindFirstChild("Props"), map:FindFirstChild("TorchMarkers")
assert(props and props:IsA("Folder"), "Props folder missing")
assert(
	torches
		and torches:IsA("Folder")
		and torches:GetAttribute("CornTorchMarkersOwned") == true
		and torches:GetAttribute("corn_project_id") == PROJECT,
	"Unrecognized TorchMarkers"
)
local gate = map:FindFirstChild("EscapeGate")
assert(
	gate
		and gate:IsA("Model")
		and gate:HasTag("corn_gate")
		and gate:GetAttribute("gate_id") == "solo_gate",
	"Unrecognized gate"
)
local door, header = exactPart(gate, "Door"), exactPart(gate, "Header")
local anchor, exit = exactPart(gate, "InteractionAnchor"), exactPart(gate, "ExitZone")
local localDoor = field.CFrame:PointToObjectSpace(door.CFrame.Position)
assert(
	math.abs(localDoor.X) < 0.001 and localDoor.Z >= 420 and localDoor.Z <= 425,
	"Gate must remain on the road's north end"
)
assert(
	same(door.Size, Vector3.new(12, 18, 2)) and same(header.Size, Vector3.new(12, 2, 2)),
	"Unknown gate sizes"
)
assert(
	door.Anchored
		and door.CanCollide
		and door.CanQuery
		and door.CFrame.UpVector:Dot(Vector3.yAxis) > 0.99999,
	"Expected closed anchored gate"
)
assert(
	door.CFrame.RightVector:Dot(field.CFrame.RightVector) > 0.99999
		and math.abs(door.CFrame.Position.Y - floorY - 9) < 0.001,
	"Gate pose mismatch"
)
assert(
	same(header.CFrame, door.CFrame * CFrame.new(0, 10, 0))
		and same(anchor.CFrame, door.CFrame * CFrame.new(0, -6, -1.3))
		and same(exit.CFrame, door.CFrame * CFrame.new(0, 2, 9)),
	"Gate/header/anchor/exit relationship changed"
)
local existing = props:FindFirstChild(ROAD)
local roadNames = 0
for _, child in props:GetChildren() do
	if child.Name == ROAD then
		roadNames += 1
	end
end
assert(roadNames <= 1, "Duplicate road name collision; nothing changed")
local targets = {}
for _, folderName in { "EditorFieldOverview", "EditorPreview" } do
	local folder = map:FindFirstChild(folderName)
	local flag = if folderName == "EditorPreview" then "CornEditorPreview" else "CornEditorOverview"
	assert(
		folder
			and folder:IsA("Folder")
			and folder:GetAttribute(flag) == true
			and folder:GetAttribute("corn_project_id") == PROJECT,
		"Unknown editor corn folder"
	)
	for index, item in folder:GetChildren() do
		assert(
			item:IsA("MeshPart")
				and item.MeshId == MESH
				and item.Anchored
				and not item.CanCollide
				and not item.CanTouch
				and not item.CanQuery
				and #item:GetChildren() == 0,
			"Unknown/manual editor corn; nothing changed"
		)
		if folderName == "EditorFieldOverview" then
			assert(
				item:GetAttribute("CornEditorOverview") == true
					and item:GetAttribute("corn_project_id") == PROJECT,
				"Unowned overview plant"
			)
		else
			assert(item.Name == "Corn", "Unrecognized preview plant")
		end
		local relative = field.CFrame:ToObjectSpace(item.CFrame)
		local half = item.Size / 2
		local spanX = math.abs(field.CFrame.RightVector:Dot(item.CFrame.RightVector)) * half.X
			+ math.abs(field.CFrame.RightVector:Dot(item.CFrame.UpVector)) * half.Y
			+ math.abs(field.CFrame.RightVector:Dot(item.CFrame.LookVector)) * half.Z
		local spanZ = math.abs(field.CFrame.LookVector:Dot(item.CFrame.RightVector)) * half.X
			+ math.abs(field.CFrame.LookVector:Dot(item.CFrame.UpVector)) * half.Y
			+ math.abs(field.CFrame.LookVector:Dot(item.CFrame.LookVector)) * half.Z
		if
			math.abs(relative.X) <= HIDE_HALF + spanX
			and math.abs(relative.Z) <= LENGTH / 2 + 1.5 + spanZ
		then
			assert(
				item.Transparency == (if existing then 1 else 0),
				"Manual/partial road corn visibility; nothing changed"
			)
			table.insert(targets, {
				Part = item,
				Name = (if folderName == "EditorPreview" then "Preview_" else "Overview_")
					.. string.format("%04d", index),
			})
		end
	end
end
local ids = {}
for row = 1, 8 do
	table.insert(ids, string.format("road_exit_row_%02d", row))
end
for _, side in { "left", "right" } do
	table.insert(ids, "road_exit_wall_" .. side)
end
local oldCount, newCount, seen = 0, 0, {}
for _, model in torches:GetChildren() do
	assert(
		model:IsA("Model")
			and model:GetAttribute("CornTorchOwned") == true
			and model:GetAttribute("corn_project_id") == PROJECT
			and model:HasTag("corn_torch"),
		"Foreign torch content; nothing changed"
	)
	local id = model:GetAttribute("torch_id")
	assert(type(id) == "string" and model.Name == id and not seen[id], "Unknown/duplicate torch id")
	seen[id] = true
	if table.find(ids, id) then
		newCount += 1
	else
		oldCount += 1
	end
end
assert(
	oldCount == 21 and newCount == (if existing then 10 else 0),
	"Partial/unknown torch installation; nothing changed"
)

local function mark(item: Instance, role: string)
	item:SetAttribute(OWNED, true)
	item:SetAttribute("corn_project_id", PROJECT)
	item:SetAttribute("RoadExitVersion", 1)
	item:SetAttribute("RoadExitRole", role)
end
local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	frame: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local item = Instance.new("Part")
	item.Name = name
	item.Size = size
	item.CFrame = frame
	item.Anchored = true
	item.CanCollide = false
	item.CanTouch = false
	item.CanQuery = false
	item.CastShadow = false
	item.Transparency = 0
	item.Color = color
	item.Material = material
	item.TopSurface = Enum.SurfaceType.Smooth
	item.BottomSurface = Enum.SurfaceType.Smooth
	mark(item, name)
	item.Parent = parent
	return item
end
local referenceTargets = {}
for _, entry in targets do
	referenceTargets[entry.Name] = entry.Part
end
local staged = {}
local road = Instance.new("Model")
road.Name = ROAD
mark(road, "Road")
table.insert(staged, road)
road:SetAttribute("SourceFieldFrame", field.CFrame)
road:SetAttribute("SourceGroundFrame", ground.CFrame)
road:SetAttribute("SourceDoorFrame", door.CFrame)
road:SetAttribute("SourceHeaderFrame", header.CFrame)
road:SetAttribute("HiddenCornCount", #targets)
local surfaceFrame = CFrame.new(field.CFrame.Position.X, floorY, field.CFrame.Position.Z)
	* field.CFrame.Rotation
part(
	road,
	"RoadSurface",
	Vector3.new(WIDTH, 0.08, LENGTH),
	surfaceFrame,
	Color3.fromRGB(119, 93, 65),
	Enum.Material.Ground
)
for _, side in { -1, 1 } do
	part(
		road,
		if side < 0 then "RutLeft" else "RutRight",
		Vector3.new(1.6, 0.02, LENGTH),
		surfaceFrame * CFrame.new(side * 3, 0.05, 0),
		Color3.fromRGB(96, 75, 52),
		Enum.Material.Ground
	)
end
local clearance = part(
	road,
	"RoadClearance",
	Vector3.new(CLEAR_WIDTH, 10, LENGTH),
	surfaceFrame * CFrame.new(0, 5, 0),
	Color3.new(),
	Enum.Material.Plastic
)
clearance.Transparency = 1
clearance:AddTag("corn_no_corn_zone")
local indexFolder = Instance.new("Folder")
indexFolder.Name = "HiddenCornIndex"
mark(indexFolder, "HiddenCornIndex")
indexFolder.Parent = road
for _, entry in targets do
	local reference = Instance.new("ObjectValue")
	reference.Name = entry.Name
	reference.Value = entry.Part
	mark(reference, "HiddenCornReference")
	reference:SetAttribute("OriginalTransparency", 0)
	reference:SetAttribute("OriginalFrame", entry.Part.CFrame)
	reference:SetAttribute("OriginalSize", entry.Part.Size)
	reference.Parent = indexFolder
end
local sign = part(
	road,
	"ExitSign",
	Vector3.new(12, 3.2, 0.3),
	door.CFrame * CFrame.new(0, 12.8, -1.3),
	Color3.fromRGB(34, 191, 113),
	Enum.Material.Neon
)
local gui = Instance.new("SurfaceGui")
gui.Name = "ExitTextSurface"
gui.Face = Enum.NormalId.Front
gui.AlwaysOnTop = false
gui.LightInfluence = 0
gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
gui.PixelsPerStud = 48
mark(gui, "ExitTextSurface")
gui.Parent = sign
local label = Instance.new("TextLabel")
label.Name = "ExitText"
label.Size = UDim2.fromScale(1, 1)
label.BackgroundTransparency = 1
label.Text = "ВЫХОД"
label.TextScaled = true
label.Font = Enum.Font.GothamBlack
label.TextColor3 = Color3.fromRGB(244, 255, 247)
label.TextStrokeColor3 = Color3.fromRGB(18, 70, 43)
label.TextStrokeTransparency = 0.2
mark(label, "ExitText")
label.Parent = gui
local newTorches = {}
local function torch(id: string, base: CFrame, length: number)
	local model = Instance.new("Model")
	model.Name = id
	mark(model, "Torch")
	table.insert(staged, model)
	model:SetAttribute("CornTorchOwned", true)
	model:SetAttribute("torch_id", id)
	model:AddTag("corn_torch")
	local pole = part(
		model,
		"Pole",
		Vector3.new(0.45, length, 0.45),
		base * CFrame.new(0, length / 2, 0),
		Color3.fromRGB(69, 48, 30),
		Enum.Material.Wood
	)
	local flame = part(
		model,
		"Flame",
		Vector3.new(0.65, 0.8, 0.65),
		base * CFrame.new(0, length, 0),
		Color3.fromRGB(255, 142, 40),
		Enum.Material.Neon
	)
	local fire = Instance.new("Fire")
	fire.Name = "TorchFire"
	fire.Size = 3
	fire.Heat = 4
	fire.Color = Color3.fromRGB(255, 170, 60)
	fire.SecondaryColor = Color3.fromRGB(255, 70, 15)
	fire.Enabled = true
	mark(fire, "TorchFire")
	fire.Parent = flame
	local light = Instance.new("PointLight")
	light.Name = "TorchLight"
	light.Color = Color3.fromRGB(255, 168, 86)
	light.Range = 18
	light.Brightness = 2
	light.Shadows = false
	light.Enabled = true
	mark(light, "TorchLight")
	light.Parent = flame
	model.PrimaryPart = pole
	table.insert(newTorches, model)
end
for row = 1, 8 do
	local side = if row <= 4 then -1 else 1
	local distance = ((row - 1) % 4 + 1) * 8
	local at = door.CFrame * CFrame.new(side * 10, -9, -distance)
	torch(ids[row], at, 13)
end
for index, side in { -1, 1 } do
	torch(
		ids[8 + index],
		door.CFrame * CFrame.new(side * 7, -1, -1.6) * CFrame.Angles(0, 0, side * math.pi / 4),
		3
	)
end
local PROPERTIES = {
	BasePart = {
		"CFrame",
		"Size",
		"Color",
		"Material",
		"Anchored",
		"CanCollide",
		"CanTouch",
		"CanQuery",
		"CastShadow",
		"Transparency",
		"TopSurface",
		"BottomSurface",
	},
	Fire = { "Size", "Heat", "Color", "SecondaryColor", "Enabled" },
	PointLight = { "Color", "Range", "Brightness", "Shadows", "Enabled" },
	SurfaceGui = { "Face", "AlwaysOnTop", "LightInfluence", "SizingMode", "PixelsPerStud" },
	TextLabel = {
		"Size",
		"BackgroundTransparency",
		"Text",
		"TextScaled",
		"Font",
		"TextColor3",
		"TextStrokeColor3",
		"TextStrokeTransparency",
	},
	ObjectValue = {},
}
local function checkTree(actual: Instance, expected: Instance)
	assert(
		actual.ClassName == expected.ClassName and actual.Name == expected.Name,
		"Owned road tree class/name changed"
	)
	local left, right = actual:GetAttributes(), expected:GetAttributes()
	for key, value in right do
		assert(same(left[key], value), "Owned road snapshot/attribute changed: " .. key)
	end
	for key in left do
		assert(right[key] ~= nil, "Foreign owned road attribute: " .. key)
	end
	local aTags, eTags = actual:GetTags(), expected:GetTags()
	assert(#aTags == #eTags, "Owned road tags changed")
	for _, tag in eTags do
		assert(actual:HasTag(tag), "Owned road tag changed")
	end
	local keys = if actual:IsA("BasePart")
		then PROPERTIES.BasePart
		else PROPERTIES[actual.ClassName]
	for _, key in keys or {} do
		assert(
			same((actual :: any)[key], (expected :: any)[key]),
			"Owned road property changed: " .. actual.Name .. "/" .. key
		)
	end
	if actual:IsA("Model") then
		local a, e = actual.PrimaryPart, (expected :: Model).PrimaryPart
		assert(
			(a == nil and e == nil) or (a and e and a.Parent == actual and a.Name == e.Name),
			"Owned road primary part changed"
		)
	end
	if actual:IsA("ObjectValue") then
		assert(
			actual.Value == referenceTargets[expected.Name],
			"Owned road original reference changed"
		)
	end
	local aChildren, eChildren = actual:GetChildren(), expected:GetChildren()
	assert(#aChildren == #eChildren, "Foreign/missing owned road child")
	local names = {}
	for _, child in aChildren do
		assert(not names[child.Name], "Duplicate owned road child")
		names[child.Name] = child
	end
	for _, child in eChildren do
		assert(names[child.Name], "Missing owned road child")
		checkTree(names[child.Name], child)
	end
end
local function destroyStaged()
	for _, item in staged do
		item:Destroy()
	end
end
if existing then
	local ok, problem = pcall(function()
		checkTree(existing, road)
		for _, model in newTorches do
			checkTree(torches:FindFirstChild(model.Name), model)
		end
	end)
	destroyStaged()
	assert(ok, "Manual/unknown road update refused; nothing changed: " .. tostring(problem))
	print("ChildrenOfCorn: recognized road/exit already installed; exact repeat made no changes")
	return
end
history:SetWaypoint("Before Corn road and exit decoration")
local saved = {}
for _, entry in targets do
	table.insert(saved, { Part = entry.Part, Transparency = entry.Part.Transparency })
end
local ok, problem = pcall(function()
	road.Parent = props
	for _, model in newTorches do
		model.Parent = torches
	end
	for _, entry in saved do
		entry.Part.Transparency = 1
	end
	checkTree(road, road)
	assert(#torches:GetChildren() == 31, "Torch publication incomplete")
	history:SetWaypoint("Installed Corn road and exit decoration")
end)
if not ok then
	for _, entry in saved do
		entry.Part.Transparency = entry.Transparency
	end
	destroyStaged()
	error("Corn road/exit rolled back: " .. tostring(problem))
end
print(
	"ChildrenOfCorn: 14-stud road840; 8 row+2 wall torches; neon ВЫХОД; hid "
		.. tostring(#targets)
		.. " owned editor plants in place"
)
