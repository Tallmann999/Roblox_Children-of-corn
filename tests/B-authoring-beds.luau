-- Focused authored soil integration; production frozen-placement path retained.
local adapter = require("./scene-adapter")
local fs, r, I = adapter.fs, adapter.r, adapter.I
local CF, V3 = r.CFrame, r.Vector3
local checks = 0
local function check(value, reason)
	assert(value, reason)
	checks += 1
end
local function child(parent, class, name)
	local item = I.new(class)
	item.Name, item.Parent = name, parent
	return item
end
local metadata = {
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
local function fixture(manual, mutate)
	local world, storage = I.new("Workspace"), I.new("ReplicatedStorage")
	local modules = child(child(storage, "Folder", "GameShared"), "Folder", "Game")
	child(modules, "ModuleScript", "GreenBedLayout")
	child(modules, "ModuleScript", "GreenBedGeometry")
	local map = child(world, "Model", "CornMap")
	map:SetAttribute("corn_project_id", "children_of_corn")
	map:SetAttribute("HarvestArtVariant", "B")
	if manual then
		map:SetAttribute("BManualAuthoringVersion", 1)
		local authoring = child(map, "Folder", "CornAuthoring")
		authoring:SetAttribute("BManualAuthoringVersion", 1)
		authoring:SetAttribute("corn_project_id", "children_of_corn")
	end
	local field = child(map, "Part", "FieldZone")
	field.Size = V3.new(630, 10, 630)
	local editor = child(map, "Folder", "GreenBedEditor")
	editor:SetAttribute("BGreenBedsOwner", "corn_B_green_beds_v1")
	editor:SetAttribute("corn_project_id", "children_of_corn")
	local parts, tiles = {}, {}
	for index, key in { "Center", "End", "Skirt" } do
		local data = metadata[key]
		local part = child(editor, "MeshPart", data[1] .. "_" .. string.format("%04d", index))
		part:SetAttribute("BGreenBedsOwner", "corn_B_green_beds_v1")
		part:SetAttribute("BGreenBedGeometryOwned", true)
		part:SetAttribute("BGreenBedGeometryKey", key)
		part:SetAttribute("BGreenBedSourceSHA256", data[2])
		part:SetAttribute("BGreenBedSourceTriangles", data[3])
		part:SetAttribute("BGreenBedTile", index)
		part.CFrame, part.Size, part.PivotOffset =
			CF.new(index * 10, 14, 0), V3.new(20, 1, 20), CF.identity
		part.TextureID, part.Color, part.Material =
			"rbxassetid://95855894892409", r.Color3.new(1, 1, 1), r.Enum.Material.Plastic
		part.Transparency, part.Reflectance, part.Anchored = 0, 0, true
		part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow, part.DoubleSided =
			false, false, false, true, true
		part.LocalTransparencyModifier = 0.25
		parts[index] = part
		tiles[index] = { Key = key, Frame = part.CFrame, Size = part.Size }
	end
	if mutate then
		mutate(parts, editor)
	end
	local pending, warnings = {}, {}
	local run = {
		IsStudio = function()
			return true
		end,
		IsClient = function()
			return true
		end,
		Heartbeat = {
			Connect = function()
				return { Disconnect = function() end }
			end,
		},
	}
	local geometry = {
		BuildTemplates = function() end,
		Clone = function(key, frame)
			local part = I.new("MeshPart")
			part.CFrame = frame
			part:SetAttribute("BGreenBedsOwner", "corn_B_green_beds_v1")
			part:SetAttribute("BGreenBedGeometryKey", key)
			return part
		end,
	}
	local fn =
		assert(loadstring(fs.readFile("variants/B/client/Controllers/GreenBedController.luau")))
	setfenv(
		fn,
		setmetatable({
			game = {
				GetService = function(_, name)
					return if name == "RunService" then run else storage
				end,
			},
			workspace = world,
			Instance = I,
			Vector3 = V3,
			CFrame = CF,
			Color3 = r.Color3,
			Enum = r.Enum,
			require = function(module)
				return if module.Name == "GreenBedLayout" then { SoilTiles = tiles } else geometry
			end,
			task = {
				spawn = function(callback)
					table.insert(pending, callback)
				end,
			},
			warn = function(message)
				table.insert(warnings, message)
			end,
		}, { __index = getfenv() })
	)
	local prototype = fn()
	local controller = setmetatable({}, { __index = prototype })
	controller:Init({ Config = { Environment = "DEV" } })
	local function tick()
		local ok, problem = pcall(controller._step, controller, 1)
		if not ok then
			controller:_clear()
			table.insert(warnings, tostring(problem))
		end
		local queue = pending
		pending = {}
		for _, callback in queue do
			callback()
		end
	end
	return controller, parts, editor, warnings, tick
end

local controller, parts, _, warnings, tick = fixture(true, function(items, editor)
	items[1].CFrame *= CF.new(17, 2, 3) * CF.Angles(0, 0.3, 0)
	items[1].Size = V3.new(18, 1.3, 21)
	local copy = items[1]:Clone()
	copy.Name, copy.Parent = "Manual duplicate", editor
	copy.CFrame += V3.new(2, 0, 2)
	items[2]:Destroy()
	items[3]:SetAttribute("BManualSourceTransparency", 0.2)
	items[3].Transparency = 1
end)
tick()
tick()
tick()
check(controller._ready and #warnings == 0, "Authored soil failed")
check(#controller._folder:GetChildren() == 3, "Deleted soil was regenerated or duplicate dropped")
local found = false
for _, copy in controller._folder:GetChildren() do
	if copy.CFrame == parts[1].CFrame then
		found = true
		check(copy.Size == parts[1].Size, "Resized soil was reset")
	end
end
check(found, "Moved authored soil was reset")
check(parts[1].LocalTransparencyModifier == 1, "Author source did not hide after runtime readiness")
controller:Destroy()
check(math.abs(parts[1].LocalTransparencyModifier - 0.25) < 1e-6, "Source visibility not restored")
check(math.abs(parts[3].Transparency - 0.2) < 1e-6, "Server-hidden soil fallback not restored")

local legacy, _, _, legacyWarnings, legacyTick = fixture(false)
legacyTick()
legacyTick()
legacyTick()
check(legacy._ready and #legacyWarnings == 0, "Strict legacy soil changed")
legacy:Destroy()
local refused, _, _, refusedWarnings, refusedTick = fixture(false, function(items)
	items[1].CFrame += V3.new(0.1, 0, 0)
end)
refusedTick()
refusedTick()
check(refused._folder == nil and #refusedWarnings > 0, "Legacy frozen placement guard was weakened")
refused:Destroy()
local foreign, foreignParts, _, foreignWarnings, foreignTick = fixture(true, function(items)
	child(items[1], "Attachment", "Foreign")
end)
foreignTick()
check(foreign._folder == nil and #foreignWarnings == 1, "Foreign authored soil child was accepted")
check(foreignParts[1]:FindFirstChild("Foreign") ~= nil, "Foreign soil edit was removed")
foreign:Destroy()
print(
	"PASS: "
		.. checks
		.. " authored soil move/size/delete/duplicate/opacity/fallback and strict legacy guard checks"
)
