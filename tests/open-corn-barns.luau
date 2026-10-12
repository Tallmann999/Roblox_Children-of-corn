-- File-backed in-memory geometry/refusal/rollback check, not Roblox physics.
local adapter = require("./scene-adapter")
local fs, r, I, CF, V3 = adapter.fs, adapter.r, adapter.I, adapter.CF, adapter.V3
local bytes = fs.readFile("place/Children_of_corn.before-autumn-20261012.rbxl")
local source = fs.readFile("scripts/open-corn-barns.luau")
local HOUSE_NAMES = { "HouseWest", "HouseEast", "HouseNorthWest" }
local CHANGED =
	{ Transparency = true, CanCollide = true, CanTouch = true, CanQuery = true, CastShadow = true }
local TRACKED = {
	"CFrame",
	"Size",
	"Material",
	"Color",
	"Anchored",
	"Transparency",
	"CanCollide",
	"CanTouch",
	"CanQuery",
	"CastShadow",
}
local function setup()
	local place = r.deserializePlace(bytes)
	for _, name in { "RunService", "ChangeHistoryService" } do
		place:GetService(name)
	end
	return place
end
local function run(place, scriptSource, running, studio)
	local service = {
		IsRunning = function()
			return running == true
		end,
		IsStudio = function()
			return studio ~= false
		end,
	}
	local gameProxy = {
		GetService = function(_, name)
			return if name == "RunService" then service else place:GetService(name)
		end,
	}
	local fn = assert(loadstring(scriptSource or source))
	setfenv(
		fn,
		setmetatable({
			game = gameProxy,
			Instance = I,
			CFrame = CF,
			Vector3 = V3,
			Color3 = r.Color3,
			Enum = r.Enum,
			print = function() end,
		}, { __index = getfenv() })
	)
	return pcall(fn)
end
local function snapshot(place)
	local result = {}
	for _, item in place:GetDescendants() do
		local state = {
			parent = item.Parent,
			name = item.Name,
			class = item.ClassName,
			attrs = item:GetAttributes(),
			properties = {},
		}
		if item:IsA("BasePart") then
			for _, key in TRACKED do
				state.properties[key] = item[key]
			end
		end
		if item:IsA("LuaSourceContainer") then
			state.properties.Source = item.Source
		end
		result[item] = state
	end
	return result
end
local function attrsEqual(left, right)
	for key, value in left do
		assert(right[key] == value, "Attribute changed: " .. key)
	end
	for key, value in right do
		assert(left[key] == value, "New attribute: " .. key)
	end
end
local function unchanged(place, before, allowGhost, allowNew)
	local originals, current = 0, 0
	for item, state in before do
		originals += 1
		assert(
			item.Parent == state.parent
				and item.Name == state.name
				and item.ClassName == state.class,
			"Original instance identity changed"
		)
		attrsEqual(state.attrs, item:GetAttributes())
		local approved = allowGhost
			and (item.Name == "Body" or item.Name == "DecorativeDoor")
			and table.find(HOUSE_NAMES, item.Parent.Name)
		for key, value in state.properties do
			if approved and CHANGED[key] then
				assert(
					item[key] == (if key == "Transparency" then 1 else false),
					"Ghost state mismatch"
				)
			else
				assert(
					item[key] == value,
					"Original property changed: " .. item:GetFullName() .. "/" .. key
				)
			end
		end
	end
	for _, item in place:GetDescendants() do
		current += 1
		if not before[item] then
			assert(
				allowNew
					and item:GetAttribute("CornOpenBarnShellOwned") == true
					and item:GetAttribute("corn_project_id") == "children_of_corn",
				"Unexpected new instance"
			)
		end
	end
	assert(
		current == originals + (if allowNew then 21 else 0),
		"Instance count changed unexpectedly"
	)
end
local place = setup()
local before = snapshot(place)
local map = place:GetService("Workspace").CornMap
local bounds = {}
for _, name in HOUSE_NAMES do
	local cf, size = map.Props[name]:GetBoundingBox()
	bounds[name] = { cf = cf, size = size }
end
local ok, problem = run(place)
assert(ok, tostring(problem))
unchanged(place, before, true, true)
for _, name in HOUSE_NAMES do
	local house = map.Props[name]
	local body = house.Body
	local shell = house.OpenBarnShell
	assert(#shell:GetChildren() == 6)
	local cf, size = house:GetBoundingBox()
	assert(cf == bounds[name].cf and size == bounds[name].size, "House minimap bounds changed")
	assert(
		math.abs(
			body.CFrame.Position.Y
				- body.Size.Y / 2
				- (map.Ground.CFrame.Position.Y + map.Ground.Size.Y / 2)
		) < 0.0001,
		"Existing Ground does not form floor"
	)
	for _, panel in shell:GetChildren() do
		local center = body.CFrame:PointToObjectSpace(panel.CFrame.Position)
		local half = panel.Size / 2
		assert(
			math.abs(center.X) + half.X <= body.Size.X / 2 + 0.0001
				and math.abs(center.Y) + half.Y <= body.Size.Y / 2 + 0.0001
				and math.abs(center.Z) + half.Z <= body.Size.Z / 2 + 0.0001,
			"Panel leaves original body extents"
		)
		for z = -14, 0, 0.5 do
			-- A 2x6x2 avatar envelope can traverse the centered entrance from outside.
			local delta = center - V3.new(0, -3, z)
			local avatar = V3.new(1, 3, 1)
			local overlap = math.abs(delta.X) < half.X + avatar.X - 0.0001
				and math.abs(delta.Y) < half.Y + avatar.Y - 0.0001
				and math.abs(delta.Z) < half.Z + avatar.Z - 0.0001
			assert(not overlap, "Entrance blocked: " .. panel.Name)
		end
	end
end
local _, requireModule = adapter.runner(place, nil, "scripts/open-corn-barns.luau")
local layout = requireModule(place:GetService("ReplicatedStorage").GameShared.Game.CornLayout)
local exclusions = layout.ReadExclusions(map, map.FieldZone)
for _, name in HOUSE_NAMES do
	assert(
		layout.IsExcluded(map.Props[name].Body.CFrame.Position, exclusions),
		"Corn can grow in barn interior"
	)
end
local installed = snapshot(place)
assert(run(place))
unchanged(place, installed, false, false)
print(
	"PASS: saved baseline, 3 real 5x7 openings, shell within extents, bounds/floor/exclusions preserved, repeat exact"
)

for _, kind in
	{
		"wrong",
		"running",
		"notStudio",
		"duplicate",
		"bodyCF",
		"bodySize",
		"bodyMaterial",
		"doorState",
		"roofCF",
		"collision",
		"foreignChild",
		"unexpectedOpen",
	}
do
	local fixture = setup()
	local world = fixture:GetService("Workspace")
	local house = world.CornMap.Props.HouseEast
	if kind == "wrong" then
		local item = I.new("Folder")
		item.Name = "Asmr_Base"
		item.Parent = world
	end
	if kind == "duplicate" then
		local item = house:Clone()
		item.Parent = house.Parent
	end
	if kind == "bodyCF" then
		house.Body.CFrame *= CF.new(1, 0, 0)
	end
	if kind == "bodySize" then
		house.Body.Size += V3.new(1, 0, 0)
	end
	if kind == "bodyMaterial" then
		house.Body.Material = r.Enum.Material.Concrete
	end
	if kind == "doorState" then
		house.DecorativeDoor.CanQuery = false
	end
	if kind == "roofCF" then
		house.Roof.CFrame *= CF.new(0, 1, 0)
	end
	if kind == "collision" or kind == "foreignChild" then
		local item = I.new("Folder")
		item.Name = if kind == "collision" then "OpenBarnShell" else "AuthorManual"
		item.Parent = house
	end
	if kind == "unexpectedOpen" then
		house.Body.Transparency = 1
	end
	local prior = snapshot(fixture)
	assert(not run(fixture, nil, kind == "running", kind ~= "notStudio"), "Guard failed: " .. kind)
	unchanged(fixture, prior, false, false)
end
for _, kind in { "mixed", "snapshot", "ownedGeometry", "ownedForeignChild", "ownedRole" } do
	local fixture = setup()
	assert(run(fixture))
	local shell = fixture:GetService("Workspace").CornMap.Props.HouseEast.OpenBarnShell
	if kind == "mixed" then
		local house = shell.Parent
		shell:Destroy()
		for _, item in { house.Body, house.DecorativeDoor } do
			for key in CHANGED do
				item[key] = if key == "Transparency" then 0 else true
			end
		end
	elseif kind == "snapshot" then
		shell:SetAttribute("SourceBodyCanCollide", false)
	elseif kind == "ownedGeometry" then
		shell.LeftWall.Size += V3.new(1, 0, 0)
	elseif kind == "ownedForeignChild" then
		local item = I.new("Part")
		item.Parent = shell
	elseif kind == "ownedRole" then
		shell.LeftWall:SetAttribute("OpenBarnRole", "Unknown")
	end
	local prior = snapshot(fixture)
	assert(not run(fixture), "Repeat guard failed: " .. kind)
	unchanged(fixture, prior, false, false)
end
print(
	"PASS: all preflight/manual/foreign/mixed/unknown-snapshot guards refuse without changing any instance"
)

for failAt = 1, 2 do
	local fixture = setup()
	local prior = snapshot(fixture)
	local patched, replacements = source:gsub(
		"folder.Parent = entry.house",
		"folder.Parent = entry.house\nif #created == "
			.. failAt
			.. ' then entry.body.Transparency = 1; entry.door.CanCollide = false; error("Injected fixture failure") end'
	)
	assert(replacements == 1)
	assert(not run(fixture, patched), "Injected error must fail")
	unchanged(fixture, prior, false, false)
end
assert(
	fs.readFile("place/Children_of_corn.before-autumn-20261012.rbxl") == bytes,
	"Input scene file changed"
)
print(
	"PASS: failures in first/second barn restore exact original properties and remove only new shell; input rbxl unchanged"
)
