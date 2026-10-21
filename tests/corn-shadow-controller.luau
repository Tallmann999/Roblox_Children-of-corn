-- Production controller with real Lune CFrame math and deterministic runtime proxies.
-- This verifies selection/ownership/lifecycle, not GPU silhouettes or FPS.
local adapter = require("./scene-adapter")
local fs, r = adapter.fs, adapter.r
local CF, V3 = r.CFrame, r.Vector3
local cases = 0
local function check(condition, message)
	assert(condition, message)
	cases += 1
end

local function node(class, name, extra)
	local values = {
		Name = name,
		ClassName = class,
		attributes = {},
		tags = {},
		children = {},
		reads = 0,
		writes = 0,
	}
	for key, value in extra or {} do
		values[key] = value
	end
	local methods = {}
	function methods:IsA(wanted)
		return class == wanted
			or (wanted == "BasePart" and (class == "Part" or class == "MeshPart"))
	end
	function methods:GetAttribute(key)
		return values.attributes[key]
	end
	function methods:SetAttribute(key, value)
		values.attributes[key] = value
	end
	function methods:GetAttributes()
		return table.clone(values.attributes)
	end
	function methods:GetTags()
		return table.clone(values.tags)
	end
	function methods:GetChildren()
		values.reads += 1
		return table.clone(values.children)
	end
	function methods:GetDescendants()
		error("Full tree scans are forbidden by this fixture")
	end
	function methods:FindFirstChild(wanted)
		for _, child in values.children do
			if child.Name == wanted then
				return child
			end
		end
		return nil
	end
	function methods:FindFirstChildOfClass(wanted)
		for _, child in values.children do
			if child:IsA(wanted) then
				return child
			end
		end
		return nil
	end
	local object
	object = setmetatable({}, {
		__index = function(_, key)
			if key == "Position" then
				return values.CFrame.Position
			end
			return methods[key] or values[key]
		end,
		__newindex = function(_, key, value)
			if key == "Parent" then
				local previous = values.Parent
				if previous then
					local index = table.find(previous.children, object)
					if index then
						table.remove(previous.children, index)
					end
				end
				if value then
					table.insert(value.children, object)
				end
			elseif key == "CastShadow" then
				values.writes += 1
			end
			values[key] = value
		end,
	})
	return object
end

local function setup(variant, studio, mode)
	local world = node("Workspace", "Workspace")
	local map = node("Model", "CornMap")
	map:SetAttribute("corn_project_id", "children_of_corn")
	map:SetAttribute("HarvestArtVariant", variant or "A")
	map.Parent = world
	local ground = node("Part", "Ground", { Size = V3.new(630, 2, 630), CFrame = CF.new(0, -1, 0) })
	ground.Parent = map
	local field =
		node("Part", "FieldZone", { Size = V3.new(630, 10, 630), CFrame = CF.new(0, 5, 0) })
	field.Parent = map
	local folder = node("Folder", "CornClientPlants")
	folder:SetAttribute("corn_project_id", "children_of_corn")
	folder:SetAttribute("CornClientRendererOwned", true)
	folder.Parent = map
	local backdrop = node("Folder", "CornClientBackdrop")
	backdrop.Parent = map
	local untouched = node("MeshPart", "Far_0_0", { CastShadow = false })
	untouched.Parent = backdrop
	local character = node("Model", "Character")
	local humanoid = node("Humanoid", "Humanoid", { Health = 100 })
	humanoid.Parent = character
	local root = node("Part", "HumanoidRootPart", { CFrame = CF.new(0, 3, 0) })
	root.Parent = character
	local player = { Character = character }
	local renderer = { _enabled = true, _map = map, _field = field, _folder = folder, _chunks = {} }
	local wind = { _layers = {} }
	local signal = { connections = 0, disconnections = 0 }
	local run = {
		IsStudio = function()
			return studio ~= false
		end,
		Heartbeat = {
			Connect = function(_, callback)
				signal.connections += 1
				signal.callback = callback
				return {
					Disconnect = function()
						signal.disconnections += 1
					end,
				}
			end,
		},
	}
	local services = { Players = { LocalPlayer = player }, Workspace = world, RunService = run }
	local source =
		assert(loadstring(fs.readFile("src/client/Controllers/CornShadowController.luau")))
	setfenv(
		source,
		setmetatable(
			{
				game = {
					GetService = function(_, key)
						return services[key]
					end,
				},
				Vector3 = V3,
				CFrame = CF,
			},
			{ __index = getfenv() }
		)
	)
	local controller = source()
	controller:Init({
		Config = { Environment = "DEV", Game = { SessionMode = mode or "solo_local" } },
		Controllers = { CornController = renderer, CornWindController = wind },
	})
	local state = {
		controller = controller,
		world = world,
		map = map,
		ground = ground,
		field = field,
		folder = folder,
		backdrop = backdrop,
		untouched = untouched,
		character = character,
		humanoid = humanoid,
		root = root,
		renderer = renderer,
		wind = wind,
		signal = signal,
	}
	function state:plant(x, z, shadows)
		local key = math.floor(x / 36) .. ":" .. math.floor(z / 36)
		local chunk = renderer._chunks[key]
		if not chunk then
			local group = node("Folder", "Chunk_" .. key)
			group.Parent = folder
			chunk = { Alive = true, Lod = 1, Folder = group }
			renderer._chunks[key] = chunk
		end
		local part = node(
			"MeshPart",
			"Corn",
			{
				CFrame = CF.new(x, 4, z),
				Size = V3.new(2, 8, 2),
				Color = r.Color3.new(1, 1, 1),
				Material = r.Enum.Material.Fabric,
				Transparency = 0,
				LocalTransparencyModifier = 0,
				Anchored = true,
				CanCollide = false,
				CanTouch = false,
				CanQuery = false,
				CastShadow = shadows == true,
				MeshId = "fixture-mesh",
				TextureID = "fixture-texture",
			}
		)
		part:SetAttribute("CornPlantTemplateOwned", true)
		part.Parent = chunk.Folder
		return part, chunk
	end
	return state
end

-- Both variants use the same new module while preserving their existing renderers.
for _, variant in { "A", "B" } do
	local s = setup(variant, true, "team_local")
	local part = s:plant(2, 0)
	s.controller:Start({})
	s.controller:Start({})
	check(s.signal.connections == 1, "Start must be idempotent")
	s.signal.callback(0.01)
	check(
		part.CastShadow and s.controller._lastWrites == 1,
		"Eligible foreground did not acquire shadows"
	)
	local reads = part.Parent.reads
	for _ = 1, 100 do
		s.signal.callback(0.001)
	end
	check(part.Parent.reads == reads, "Selection scanned on every frame")
	s.signal.callback(0.3)
	check(s.controller._lastWrites == 0 and part.writes == 1, "Unchanged selection rewrote shadows")
	check(s.backdrop.reads == 0 and not s.untouched.CastShadow, "Backdrop was scanned or mutated")
	s.root.CFrame = CF.new(100, 3, 0)
	s.controller:_reconcile()
	check(not part.CastShadow, "Player movement did not restore owned shadow")
	s.root.CFrame = CF.new(0, 3, 0)
	s.controller:_reconcile()
	check(part.CastShadow, "Returning player did not reacquire eligible plant")
	s.humanoid.Health = 0
	s.controller:_reconcile()
	check(not part.CastShadow, "Death did not restore owned values")
	s.humanoid.Health = 100
	s.controller:_reconcile()
	s.map.Parent = nil
	s.controller:_reconcile()
	check(not part.CastShadow, "Detached owned map did not restore shadows")
	s.controller:Destroy()
	s.controller:Destroy()
	check(s.signal.disconnections == 1, "Destroy must disconnect once")
end

-- Exact deterministic cap; foreign pre-existing true values are never owned.
local cap = setup()
local parts = {}
for x = -9, 9 do
	for z = -9, 9 do
		local part = cap:plant(x, z)
		table.insert(parts, part)
	end
end
local foreignTrue = cap:plant(0, 0, true)
cap.controller:_reconcile()
local selected = {}
for _, part in parts do
	if part.CastShadow then
		selected[part] = true
	end
end
local count = 0
for _ in selected do
	count += 1
end
check(count == 256, "Caster cap must be exactly 256 in a dense fixture")
check(foreignTrue.writes == 0, "Pre-existing true shadow was claimed")
cap.controller:_reconcile()
check(cap.controller._lastWrites == 0, "Deterministic selection churned at equal distances")
for part in selected do
	check(part.CastShadow, "Stable candidate was replaced")
end
cap.controller:Destroy()
for _, part in parts do
	check(not part.CastShadow, "Destroy did not restore a selected caster")
end
check(foreignTrue.CastShadow and foreignTrue.writes == 0, "Destroy reset a foreign true shadow")

-- Boundary hysteresis never permits a caster beyond 28 studs.
local edge = setup()
local edgePart = edge:plant(25, 0)
edge.controller:_reconcile()
check(edgePart.CastShadow, "Plant inside enter radius must qualify")
edge.root.CFrame = CF.new(-2, 3, 0)
edge.controller:_reconcile()
check(edgePart.CastShadow, "Existing selection should survive inside retention radius")
edge.root.CFrame = CF.new(-3, 3, 0)
edge.controller:_reconcile()
check(not edgePart.CastShadow, "Out-of-range caster was not restored")
edge.root.CFrame = CF.new(-2, 3, 0)
edge.controller:_reconcile()
check(not edgePart.CastShadow, "New candidate bypassed enter hysteresis")
edge.controller:Destroy()

-- Unknown map/layer/topology and disabled contexts cannot write.
for _, mutation in
	{
		function(s)
			s.map:SetAttribute("HarvestArtVariant", "foreign")
		end,
		function(s)
			s.map:SetAttribute("corn_project_id", "other")
		end,
		function(s)
			s.ground.Size = V3.new(840, 2, 840)
		end,
		function(s)
			s.field.Size = V3.new(630, 11, 630)
		end,
		function(s)
			s.folder:SetAttribute("CornClientRendererOwned", false)
		end,
		function(s)
			s.folder:SetAttribute("corn_project_id", "other")
		end,
		function(s)
			s.renderer._chunks["0:0"].Alive = false
		end,
		function(s)
			s.renderer._chunks["0:0"].Lod = 3
		end,
	}
do
	local s = setup()
	local part = s:plant(1, 1)
	mutation(s)
	s.controller:_reconcile()
	check(not part.CastShadow and part.writes == 0, "Unverified binding changed art")
	s.controller:Destroy()
end
for _, args in { { "A", false, "solo_local" }, { "A", true, "public" } } do
	local s = setup(table.unpack(args))
	s.controller:Start({})
	check(s.signal.connections == 0, "Disabled context connected Heartbeat")
	s.controller:Destroy()
end

-- A foreign edit retires that exact instance; reset/re-entry never overwrites it.
for _, mutation in
	{
		function(s, p)
			p.CastShadow = false
		end,
		function(s, p)
			p.Size = V3.new(3, 8, 2)
		end,
		function(s, p)
			p.CFrame = CF.new(10, 4, 0)
		end,
		function(s, p)
			p.TextureID = "author"
		end,
		function(s, p)
			p:SetAttribute("author", true)
		end,
		function(s, p)
			table.insert(p.tags, "author")
		end,
		function(s, p)
			p.Parent = s.map
		end,
		function(s, p)
			s.folder:SetAttribute("CornClientRendererOwned", false)
		end,
	}
do
	local s = setup()
	local part = s:plant(1, 0)
	s.controller:_reconcile()
	mutation(s, part)
	local expected, writes = part.CastShadow, part.writes
	s.controller:_reconcile()
	s.controller:_reconcile()
	s.controller:Destroy()
	check(
		part.CastShadow == expected and part.writes == writes,
		"Foreign or moved node was overwritten"
	)
end

-- Existing wind animation is an owned bounded rotation, not a manual move.
local moving = setup()
local plant, chunk = moving:plant(1, 0)
local baseFrame = plant.CFrame
local layer = { Folder = moving.folder, Entries = {} }
local entry = {
	Layer = layer,
	Plant = plant,
	Parent = chunk.Folder,
	Base = V3.new(1, 0, 0),
	Parts = { { Part = plant, Frame = baseFrame } },
	Moved = false,
}
layer.Entries[plant], moving.wind._layers.near = entry, layer
moving.controller:_reconcile()
for _, angles in { { 2.25, 1.05 }, { -2.25, -1.05 }, { 0.2, -0.7 } } do
	plant.CFrame = CF.new(entry.Base)
		* CF.Angles(math.rad(angles[1]), 0, math.rad(angles[2]))
		* CF.new(-entry.Base)
		* baseFrame
	entry.Moved = true
	moving.controller:_reconcile()
	check(
		plant.CastShadow and not moving.controller._retired[plant],
		"Owned wind tilt lost shadows"
	)
end
moving.controller:Destroy()
check(not plant.CastShadow, "Destroy did not restore wind-animated caster")

-- Bounded scanning even if a foreign insertion overfills a nearby chunk.
local bounded = setup()
for _ = 1, 1500 do
	bounded:plant(1, 1)
end
bounded.controller:_reconcile()
check(bounded.controller._lastScanned == 1296, "Foreground scan exceeded the bounded chunk budget")
bounded.controller:Destroy()
print(string.format("corn-shadow-controller PASS (%d assertions)", cases))
