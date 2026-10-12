-- Guarded Edit-only opening of the three recognized temporary Corn barns.
-- No Source writes, scene serialization, removal or movement of authored instances.
local run = game:GetService("RunService")
local world = game:GetService("Workspace")
local history = game:GetService("ChangeHistoryService")
assert(run:IsStudio() and not run:IsRunning(), "Open barns only in Children_of_corn stopped Edit")
assert(
	not world:FindFirstChild("Asmr_Base") and not world:FindFirstChild("ASMR_Models"),
	"Wrong game; nothing changed"
)

local PROJECT = "children_of_corn"
local SHELL = "OpenBarnShell"
local EPS = 0.0001
local CHANGED = { "Transparency", "CanCollide", "CanTouch", "CanQuery", "CastShadow" }
local GHOST =
	{ Transparency = 1, CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false }
local ORIGINAL =
	{ Transparency = 0, CanCollide = true, CanTouch = true, CanQuery = true, CastShadow = true }
local BASELINES = {
	{ name = "HouseWest", frame = CFrame.new(-126, 20.399986, -133) },
	{ name = "HouseEast", frame = CFrame.new(147, 20.399986, 84) },
	{ name = "HouseNorthWest", frame = CFrame.new(-294, 20.399986, 168) },
}
local PANELS = {
	{ name = "LeftWall", size = Vector3.new(1, 12, 24), offset = Vector3.new(-9.5, 0, 0) },
	{ name = "RightWall", size = Vector3.new(1, 12, 24), offset = Vector3.new(9.5, 0, 0) },
	{ name = "BackWall", size = Vector3.new(18, 12, 1), offset = Vector3.new(0, 0, 11.5) },
	{ name = "FrontLeft", size = Vector3.new(7.5, 12, 1), offset = Vector3.new(-6.25, 0, -11.5) },
	{ name = "FrontRight", size = Vector3.new(7.5, 12, 1), offset = Vector3.new(6.25, 0, -11.5) },
	{ name = "Lintel", size = Vector3.new(5, 5, 1), offset = Vector3.new(0, 3.5, -11.5) },
}
local function frameEqual(a, b)
	local left, right = { a:GetComponents() }, { b:GetComponents() }
	for i, value in left do
		if math.abs(value - right[i]) > EPS then
			return false
		end
	end
	return true
end
local function valueEqual(a, b)
	if typeof(a) == "CFrame" and typeof(b) == "CFrame" then
		return frameEqual(a, b)
	end
	if typeof(a) == "Vector3" and typeof(b) == "Vector3" then
		return (a - b).Magnitude <= EPS
	end
	return a == b
end
local function onlyNamed(parent, name)
	local found = nil
	for _, item in parent:GetChildren() do
		if item.Name == name then
			assert(not found, "Duplicate name: " .. parent:GetFullName() .. "/" .. name)
			found = item
		end
	end
	return found
end
local function attributesEqual(item, expected)
	local actual, count = item:GetAttributes(), 0
	for key, value in actual do
		count += 1
		assert(
			expected[key] ~= nil and valueEqual(value, expected[key]),
			"Unrecognized metadata: " .. item:GetFullName() .. "/" .. key
		)
	end
	local expectedCount = 0
	for _ in expected do
		expectedCount += 1
	end
	assert(count == expectedCount, "Incomplete snapshot/ownership: " .. item:GetFullName())
end
local function validateOriginal(part, name, frame, size, material, color, open)
	assert(
		part and part.ClassName == "Part" and #part:GetChildren() == 0,
		"Unrecognized original part: " .. name
	)
	assert(
		frameEqual(part.CFrame, frame) and valueEqual(part.Size, size),
		"Author geometry differs: " .. part:GetFullName()
	)
	assert(
		part.Material == material
			and part.Color == color
			and part.Anchored
			and part.Shape == Enum.PartType.Block,
		"Author appearance differs: " .. part:GetFullName()
	)
	local expected = if open then GHOST else ORIGINAL
	for _, key in CHANGED do
		assert(
			part[key] == expected[key],
			"Unexpected original state: " .. part:GetFullName() .. "/" .. key
		)
	end
end
local function shellSnapshot(body, door)
	local attrs = {
		corn_project_id = PROJECT,
		CornOpenBarnShellOwned = true,
		OpenBarnVersion = 1,
		SourceBodyCFrame = body.CFrame,
		SourceBodySize = body.Size,
		SourceDoorCFrame = door.CFrame,
		SourceDoorSize = door.Size,
	}
	for _, key in CHANGED do
		attrs["SourceBody" .. key] = ORIGINAL[key]
		attrs["SourceDoor" .. key] = ORIGINAL[key]
	end
	return attrs
end
local function panelAttrs(name)
	return {
		corn_project_id = PROJECT,
		CornOpenBarnShellOwned = true,
		OpenBarnVersion = 1,
		OpenBarnRole = name,
	}
end
local function validateShell(folder, body, door)
	assert(
		folder.ClassName == "Folder" and #folder:GetChildren() == #PANELS,
		"Unrecognized shell: " .. folder:GetFullName()
	)
	attributesEqual(folder, shellSnapshot(body, door))
	for _, entry in PANELS do
		local item = onlyNamed(folder, entry.name)
		assert(
			item and item.ClassName == "Part" and #item:GetChildren() == 0,
			"Foreign/missing shell part: " .. entry.name
		)
		attributesEqual(item, panelAttrs(entry.name))
		assert(
			frameEqual(item.CFrame, body.CFrame * CFrame.new(entry.offset))
				and valueEqual(item.Size, entry.size),
			"Shell geometry differs: " .. entry.name
		)
		assert(
			item.Anchored
				and item.Shape == Enum.PartType.Block
				and item.Material == body.Material
				and item.Color == body.Color,
			"Shell appearance differs: " .. entry.name
		)
		assert(
			item.Transparency == 0
				and item.CanCollide
				and item.CanQuery
				and not item.CanTouch
				and item.CastShadow,
			"Shell collision differs: " .. entry.name
		)
		assert(
			item.TopSurface == Enum.SurfaceType.Smooth
				and item.BottomSurface == Enum.SurfaceType.Smooth,
			"Shell surface differs: " .. entry.name
		)
	end
end

local map = onlyNamed(world, "CornMap")
assert(
	map and map:IsA("Model") and map:GetAttribute("corn_project_id") == PROJECT,
	"Correct CornMap required"
)
assert(
	map:GetAttribute("map_version") == 3
		and map:GetAttribute("MapTuningVersion") == 1
		and map:GetAttribute("TorchClearanceVersion") == 1,
	"Unrecognized Corn map version"
)
local field, props = onlyNamed(map, "FieldZone"), onlyNamed(map, "Props")
assert(
	field and field:IsA("BasePart") and valueEqual(field.Size, Vector3.new(840, 10, 840)),
	"Expected current FieldZone840"
)
assert(props and props:IsA("Folder"), "Expected CornMap Props")
local entries, installed = {}, 0
for _, baseline in BASELINES do
	local house = onlyNamed(props, baseline.name)
	assert(house and house:IsA("Model"), "Missing temporary barn: " .. baseline.name)
	local body, door, shell =
		onlyNamed(house, "Body"), onlyNamed(house, "DecorativeDoor"), onlyNamed(house, SHELL)
	assert(
		#house:GetChildren() == (if shell then 5 else 4),
		"Foreign child in temporary barn: " .. baseline.name
	)
	validateOriginal(
		body,
		"Body",
		baseline.frame,
		Vector3.new(20, 12, 24),
		Enum.Material.WoodPlanks,
		Color3.fromRGB(95, 84, 62),
		shell ~= nil
	)
	validateOriginal(
		door,
		"DecorativeDoor",
		baseline.frame * CFrame.new(0, -2.5, -12.1),
		Vector3.new(4, 7, 0.25),
		Enum.Material.Wood,
		Color3.fromRGB(58, 45, 33),
		shell ~= nil
	)
	local roofCount, sides = 0, {}
	for _, roof in house:GetChildren() do
		if roof.Name == "Roof" then
			roofCount += 1
			assert(roof.ClassName == "Part" and #roof:GetChildren() == 0, "Unrecognized roof")
			local side = if roof.CFrame.Position.X < body.CFrame.Position.X then -1 else 1
			assert(not sides[side], "Duplicate roof side")
			sides[side] = true
			validateOriginal(
				roof,
				"Roof",
				baseline.frame
					* CFrame.new(side * 5, 8, 0)
					* CFrame.Angles(0, 0, -side * math.pi / 8),
				Vector3.new(12, 1, 26),
				Enum.Material.Slate,
				Color3.fromRGB(54, 57, 49),
				false
			)
		end
	end
	assert(roofCount == 2 and sides[-1] and sides[1], "Expected both original roofs")
	if shell then
		validateShell(shell, body, door)
		installed += 1
	end
	table.insert(entries, { house = house, body = body, door = door })
end
assert(installed == 0 or installed == #BASELINES, "Mixed partial barn opening; nothing changed")
if installed == #BASELINES then
	print("ChildrenOfCorn: three recognized open barns already installed; nothing changed")
	return
end

-- Preflight above covers all three models. Exact property snapshots precede mutation.
local saved, created = {}, {}
for _, entry in entries do
	for _, item in { entry.body, entry.door } do
		local state = { item = item, values = {} }
		for _, key in CHANGED do
			state.values[key] = item[key]
		end
		table.insert(saved, state)
	end
end
history:SetWaypoint("Before opening Corn temporary barns")
local ok, problem = pcall(function()
	for _, entry in entries do
		local folder = Instance.new("Folder")
		folder.Name = SHELL
		table.insert(created, folder)
		for key, value in shellSnapshot(entry.body, entry.door) do
			folder:SetAttribute(key, value)
		end
		for _, panel in PANELS do
			local item = Instance.new("Part")
			item.Parent = folder
			item.Name, item.Size = panel.name, panel.size
			item.CFrame = entry.body.CFrame * CFrame.new(panel.offset)
			item.Material, item.Color = entry.body.Material, entry.body.Color
			item.Anchored, item.CanCollide, item.CanQuery, item.CastShadow = true, true, true, true
			item.CanTouch = false
			item.TopSurface, item.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
			for key, value in panelAttrs(panel.name) do
				item:SetAttribute(key, value)
			end
		end
		folder.Parent = entry.house
		for _, original in { entry.body, entry.door } do
			for _, key in CHANGED do
				original[key] = GHOST[key]
			end
		end
	end
	for _, entry in entries do
		validateShell(entry.house[SHELL], entry.body, entry.door)
	end
	history:SetWaypoint("Opened three Corn temporary barns")
end)
if not ok then
	for _, state in saved do
		for _, key in CHANGED do
			state.item[key] = state.values[key]
		end
	end
	for _, folder in created do
		folder:Destroy()
	end
	error("Corn barn opening rolled back: " .. tostring(problem))
end
print(
	"ChildrenOfCorn: three temporary barns opened, 5x7 entrances; original bounds/roofs and other world preserved"
)
