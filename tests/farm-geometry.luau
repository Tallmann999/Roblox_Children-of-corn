-- Actual farm runtime/catalog/builder in an API-shaped Lune adapter.
-- This verifies ownership, geometry channels and transactional preservation; not engine serialization/GPU.
local fs = require("@lune/fs")
local r = require("@lune/roblox")
local serde = require("@lune/serde")
local V3, CF = r.Vector3, r.CFrame
local PROJECT = "children_of_corn"
local KEYS =
	{ "SM_Bld_Barn_03", "SM_Prop_Truck_Rusted_01", "SM_Prop_Tyre_01", "SM_Prop_Rubbish_Pile_05" }
local PROPERTIES = {
	"CFrame",
	"Size",
	"PivotOffset",
	"TextureID",
	"TextureContent",
	"Color",
	"Material",
	"MaterialVariant",
	"Transparency",
	"Reflectance",
	"Anchored",
	"CanCollide",
	"CanTouch",
	"CanQuery",
	"CastShadow",
	"DoubleSided",
	"CollisionGroup",
	"Massless",
	"CustomPhysicalProperties",
}
local FIDELITIES = { "CollisionFidelity", "RenderFidelity", "FluidFidelity" }
local Enum = setmetatable({
	FluidFidelity = { Automatic = { Name = "Automatic" } },
	ContentSourceType = {
		None = { Name = "None" },
		Object = { Name = "Object" },
		Uri = { Name = "Uri" },
	},
}, { __index = r.Enum })
local function content(object, uri)
	return {
		SourceType = object and Enum.ContentSourceType.Object
			or uri and Enum.ContentSourceType.Uri
			or Enum.ContentSourceType.None,
		Object = object,
		Uri = uri,
	}
end
local function equalContent(a, b)
	return a.SourceType == b.SourceType and a.Object == b.Object and a.Uri == b.Uri
end
local function signal()
	local listeners = {}
	return {
		Connect = function(_, callback)
			local connection = { Connected = true }
			function connection:Disconnect()
				self.Connected = false
			end
			table.insert(listeners, { Connection = connection, Callback = callback })
			return connection
		end,
		Fire = function(_, ...)
			for _, item in listeners do
				if item.Connection.Connected then
					item.Callback(...)
				end
			end
		end,
	}
end
local methods = {}
local function node(class, name)
	return setmetatable({
		_values = {
			ClassName = class,
			Name = name,
			DescendantAdded = signal(),
			DescendantRemoving = signal(),
		},
		_children = {},
		_attributes = {},
		_propertySignals = {},
	}, {
		__index = function(self, key)
			return methods[key] or self._values[key]
		end,
		__newindex = function(self, key, value)
			local priorValue = self._values[key]
			if key == "Parent" then
				local previous = self._values.Parent
				local moved = { self }
				for _, child in self:GetDescendants() do
					table.insert(moved, child)
				end
				local ancestor = previous
				while ancestor do
					for _, child in moved do
						ancestor.DescendantRemoving:Fire(child)
					end
					ancestor = ancestor.Parent
				end
				if previous then
					local index = table.find(previous._children, self)
					if index then
						table.remove(previous._children, index)
					end
				end
				if value then
					table.insert(value._children, self)
				end
			end
			self._values[key] = value
			if key == "Parent" and value then
				local moved = { self }
				for _, child in self:GetDescendants() do
					table.insert(moved, child)
				end
				local ancestor = value
				while ancestor do
					for _, child in moved do
						ancestor.DescendantAdded:Fire(child)
					end
					ancestor = ancestor.Parent
				end
			end
			if priorValue ~= value and self._propertySignals[key] then
				self._propertySignals[key]:Fire()
			end
			if rawget(self, "_watch") then
				self._writes += 1
			end
		end,
	})
end
function methods:IsA(class)
	return self.ClassName == class
		or (class == "BasePart" and (self.ClassName == "Part" or self.ClassName == "MeshPart"))
end
function methods:GetAttribute(name)
	return self._attributes[name]
end
function methods:SetAttribute(name, value)
	local prior = self._attributes[name]
	self._attributes[name] = value
	if prior ~= value and self._attributeSignals and self._attributeSignals[name] then
		self._attributeSignals[name]:Fire()
	end
end
function methods:GetAttributeChangedSignal(name)
	if not self._attributeSignals then
		rawset(self, "_attributeSignals", {})
	end
	if not self._attributeSignals[name] then
		self._attributeSignals[name] = signal()
	end
	return self._attributeSignals[name]
end
function methods:GetPropertyChangedSignal(name)
	if not self._propertySignals[name] then
		self._propertySignals[name] = signal()
	end
	return self._propertySignals[name]
end
function methods:GetAttributes()
	return table.clone(self._attributes)
end
function methods:GetChildren()
	return table.clone(self._children)
end
function methods:GetDescendants()
	local all = {}
	local function visit(parent)
		for _, child in parent._children do
			table.insert(all, child)
			visit(child)
		end
	end
	visit(self)
	return all
end
function methods:FindFirstChild(name)
	for _, child in self._children do
		if child.Name == name then
			return child
		end
	end
	return nil
end
function methods:WaitForChild(name)
	return assert(self:FindFirstChild(name), "Missing fixture child " .. name)
end
function methods:IsDescendantOf(parent)
	local current = self.Parent
	while current do
		if current == parent then
			return true
		end
		current = current.Parent
	end
	return false
end
function methods:GetFullName()
	return self.Parent and self.Parent:GetFullName() .. "." .. self.Name or self.Name
end
function methods:Clone()
	local clone = node(self.ClassName, self.Name)
	for key, value in self._values do
		if key ~= "Parent" then
			clone[key] = key == "MeshContent" and table.clone(value) or value
		end
	end
	clone._attributes = table.clone(self._attributes)
	local state = rawget(self, "_fixture")
	rawset(clone, "_fixture", state)
	if state then
		table.insert(state.snapshots, clone)
	end
	return clone
end
function methods:Destroy()
	self.Parent = nil
	self.Destroyed = true
end
local function snapshot(part)
	local result = {
		MeshContent = table.clone(part.MeshContent),
		MeshId = part.MeshId,
		Parent = part.Parent,
		Name = part.Name,
		Attributes = part:GetAttributes(),
	}
	for _, key in PROPERTIES do
		result[key] = part[key]
	end
	for _, key in FIDELITIES do
		result[key] = part[key]
	end
	return result
end
local function preserved(part, before, meshToo)
	for _, key in FIDELITIES do
		assert(part[key] == before[key], "Immutable fidelity changed " .. key)
	end
	for _, key in PROPERTIES do
		assert(part[key] == before[key], "ApplyMesh lost " .. key)
	end
	assert(
		part.Name == before.Name and part.Parent == before.Parent,
		"Restoration moved/replaced part"
	)
	for name, value in before.Attributes do
		assert(part:GetAttribute(name) == value, "Restoration changed attribute " .. name)
	end
	if meshToo then
		assert(
			equalContent(part.MeshContent, before.MeshContent) and part.MeshId == before.MeshId,
			"Rollback lost original mesh content"
		)
	end
end
function methods:ApplyMesh(other)
	local fixture = assert(rawget(self, "_fixture"), 'Fixture invariant: rawget(self, "_fixture")')
	fixture.applies += 1
	self.MeshContent = table.clone(other.MeshContent)
	self.MeshId = other.MeshId
	-- Roblox ApplyMesh copies geometry-related properties. Mutate the complete preserve set here
	-- so omission from restoration is observable, including collision and author texture settings.
	for _, key in PROPERTIES do
		self[key] = other[key]
	end
	for _, key in FIDELITIES do
		self[key] = other[key]
	end
	if fixture.failApply == self then
		fixture.failApply = nil
		error("Injected partial ApplyMesh failure")
	end
end
local function configure(part, ordinal)
	part.CFrame = CF.new(ordinal * 3, 10 + ordinal, -ordinal) * CF.Angles(0.1, ordinal / 10, -0.07)
	part.Size = V3.new(7 + ordinal, 9 + ordinal / 3, 4 + ordinal / 5)
	part.PivotOffset = CF.new(0.2, 0.3, 0.4) * CF.Angles(0.02, 0.04, 0.06)
	part.TextureID = "rbxassetid://123" .. ordinal
	part.TextureContent = content(nil, part.TextureID)
	part.Color = r.Color3.new(0.2, 0.3, 0.7)
	part.Material = r.Enum.Material.Wood
	part.MaterialVariant = "AuthoredWood"
	part.Massless = true
	part.CustomPhysicalProperties = { Density = 1.1, Friction = 0.4 }
	part.Transparency, part.Reflectance = 0.13, 0.08
	part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, true, false
	part.CastShadow, part.DoubleSided = false, true
	part.CollisionGroup = "AuthoredFarm"
	part.CollisionFidelity = r.Enum.CollisionFidelity.PreciseConvexDecomposition
	part.RenderFidelity = r.Enum.RenderFidelity.Automatic
	part.FluidFidelity = Enum.FluidFidelity.Automatic
	part.MeshId = ""
	part.MeshContent = content()
end
local function mark(object, attrs)
	object:SetAttribute("corn_project_id", PROJECT)
	for key, value in attrs do
		object:SetAttribute(key, value)
	end
	return object
end
local function meshAdapter(fixture, fixedSource)
	local mesh = {
		ClassName = "EditableMesh",
		FixedSize = fixedSource ~= nil,
		vertices = {},
		uvs = {},
		normals = {},
		colors = {},
		faces = {},
		faceUvs = {},
		faceNormals = {},
		faceColors = {},
	}
	if fixedSource then
		local function copy(value)
			if type(value) ~= "table" then
				return value
			end
			local result = {}
			for key, entry in value do
				result[key] = copy(entry)
			end
			return result
		end
		for _, channel in
			{
				"vertices",
				"uvs",
				"normals",
				"colors",
				"faces",
				"faceUvs",
				"faceNormals",
				"faceColors",
			}
		do
			mesh[channel] = copy(fixedSource[channel])
		end
	else
		fixture.dynamicLive += 1
		fixture.maxDynamicLive = math.max(fixture.maxDynamicLive, fixture.dynamicLive)
	end
	local counts = { vertex = 0, uv = 0, normal = 0, color = 0, face = 0 }
	local function finite(n)
		assert(n == n and math.abs(n) < math.huge, "Nonfinite builder channel")
	end
	function mesh:AddVertex(value)
		finite(value.X)
		finite(value.Y)
		finite(value.Z)
		counts.vertex += 1
		if fixture.failBuild and counts.vertex == 17 then
			error("Injected builder setter failure")
		end
		local id = 1000 + counts.vertex * 7
		self.vertices[id] = value
		return id
	end
	function mesh:AddUV(value)
		finite(value.X)
		finite(value.Y)
		counts.uv += 1
		local id = 2000 + counts.uv * 11
		self.uvs[id] = value
		return id
	end
	function mesh:AddNormal(value)
		finite(value.X)
		finite(value.Y)
		finite(value.Z)
		counts.normal += 1
		local id = 3000 + counts.normal * 13
		self.normals[id] = value
		return id
	end
	function mesh:AddColor(value, alpha)
		finite(value.R)
		finite(value.G)
		finite(value.B)
		finite(alpha)
		counts.color += 1
		local id = 4000 + counts.color * 17
		self.colors[id] = { value, alpha }
		return id
	end
	function mesh:AddTriangle(a, b, c)
		assert(
			self.vertices[a] and self.vertices[b] and self.vertices[c],
			"Unknown triangle vertex ID"
		)
		counts.face += 1
		local id = 5000 + counts.face * 19
		self.faces[id] = { a, b, c }
		return id
	end
	local function channel(self, face, values, source, destination)
		assert(self.faces[face] and #values == 3, "Unknown face or malformed channel")
		for _, id in values do
			assert(source[id], "Unknown channel ID")
		end
		destination[face] = table.clone(values)
	end
	function mesh:SetFaceUVs(face, values)
		channel(self, face, values, self.uvs, self.faceUvs)
	end
	function mesh:SetFaceNormals(face, values)
		channel(self, face, values, self.normals, self.faceNormals)
	end
	function mesh:SetFaceColors(face, values)
		channel(self, face, values, self.colors, self.faceColors)
	end
	function mesh:Destroy()
		if not self.Destroyed and not self.FixedSize then
			fixture.dynamicLive -= 1
		end
		self.Destroyed = true
	end
	table.insert(fixture.meshes, mesh)
	return mesh
end
local function scriptRef(path)
	local isInit = path:match("/init%.luau$") ~= nil
	local base = isInit and assert(path:match("^(.*)/[^/]+$"), "Init folder required") or path
	local ref = { Path = path, Name = base:match("([^/]+)$"):gsub("%.luau$", "") }
	function ref:WaitForChild(name)
		local child = base .. "/" .. name
		if pcall(fs.readFile, child .. ".luau") then
			return scriptRef(child .. ".luau")
		end
		if pcall(fs.readFile, child .. "/init.luau") then
			return scriptRef(child .. "/init.luau")
		end
		return scriptRef(child)
	end
	ref.FindFirstChild = ref.WaitForChild
	return setmetatable(ref, {
		__index = function(_, key)
			if key == "Parent" then
				return scriptRef(assert(base:match("^(.*)/[^/]+$"), "Script parent required"))
			end
			error("Unrecognized script reference " .. key)
		end,
	})
end

local function fixture(all)
	local state = {
		meshes = {},
		canonicals = {},
		builds = {},
		applies = 0,
		dynamicLive = 0,
		maxDynamicLive = 0,
		fixedClones = {},
		fixedCreates = 0,
		creates = 0,
		yields = 0,
		warnings = {},
		rawTexts = {},
		chunkSources = {},
		deferred = {},
		snapshots = {},
	}
	local storage, workspace =
		node("ServerStorage", "ServerStorage"), node("Workspace", "Workspace")
	state.storage, state.workspace = storage, workspace
	local folder = mark(node("Folder", "CornFarmAssets"), { CornFarmAssetsOwned = true })
	folder.Parent = storage
	local map = mark(node("Model", "CornMap"), { CornMapOwned = true })
	map.Parent = workspace
	local props = node("Folder", "Props")
	props.Parent = map
	state.folder, state.props, state.map = folder, props, map
	state.parts = {}
	function state:flush()
		local iterations = 0
		while #self.deferred > 0 do
			iterations += 1
			assert(iterations < 30, "Deferred restoration did not settle")
			local callback = table.remove(self.deferred, 1)
			callback()
		end
	end
	function state:model(parent, key, name)
		local model =
			mark(node("Model", name or key), { CornFarmAssetOwned = true, AssetKey = key })
		model.Parent = parent
		return model
	end
	function state:part(model, key, index)
		local part = mark(
			node("MeshPart", "Mesh_" .. index),
			{ CornFarmMeshOwned = true, AssetKey = key, MeshIndex = index }
		)
		configure(part, #self.parts + 1)
		rawset(part, "_fixture", self)
		part.Parent = model
		rawset(part, "_writes", 0)
		rawset(part, "_watch", true)
		table.insert(self.parts, part)
		return part
	end
	local assetService = {}
	function assetService:CreateEditableMesh()
		if state.dynamicLimit and state.dynamicLive >= state.dynamicLimit then
			return nil
		end
		return meshAdapter(state)
	end
	function assetService:CreateEditableMeshAsync(value, options)
		assert(options.FixedSize == true, "Client clone must be fixed")
		local dynamic = assert(value.Object, "Fixed clone needs source object")
		assert(
			not dynamic.FixedSize and not dynamic.Destroyed,
			"Fixed clone source must be live dynamic"
		)
		state.fixedCreates += 1
		if state.failFixed == state.fixedCreates then
			error("Injected fixed clone allocation failure")
		end
		local fixed = meshAdapter(state, dynamic)
		table.insert(state.fixedClones, { Dynamic = dynamic, Fixed = fixed })
		return fixed
	end
	function assetService:CreateMeshPartAsync(value, options)
		assert(
			value.SourceType == Enum.ContentSourceType.Object
				and value.Object
				and not value.Object.Destroyed,
			"Fixture invariant: value.SourceType == Enum.ContentSourceType.Object and value.Object and not value.Object.Destroyed"
		)
		if state.requireFixed then
			assert(
				value.Object.FixedSize and state.dynamicLive == 0,
				"Client canonical retained dynamic geometry"
			)
		end
		state.creates += 1
		if state.onCreate then
			state.onCreate(state.creates)
		end
		if state.failCreate == state.creates then
			error("Injected CreateMeshPartAsync failure")
		end
		local part = node("MeshPart", "Canonical")
		configure(part, -state.creates)
		part.PivotOffset = CF.new(-9, -8, -7)
		part.Color, part.Material, part.MaterialVariant =
			r.Color3.new(0.9, 0.8, 0.1), r.Enum.Material.Plastic, "Canonical"
		part.Transparency, part.Reflectance = 0.91, 0.72
		part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = false, true, false, true
		part.CastShadow, part.DoubleSided, part.CollisionGroup = true, false, "Default"
		part.Massless, part.CustomPhysicalProperties = false, { Density = 0.2, Friction = 0.9 }
		part.CollisionFidelity, part.RenderFidelity =
			options.CollisionFidelity, options.RenderFidelity
		part.MeshContent = table.clone(value)
		rawset(part, "_fixture", state)
		table.insert(state.canonicals, part)
		assert(part.Parent == nil, "Canonical was parented")
		return part
	end
	local modules = {}
	local game = {
		GetService = function(_, name)
			if name == "HttpService" then
				return {
					JSONDecode = function(_, value)
						local data = serde.decode("json", value)
						if type(data) == "table" and type(data.file) == "string" then
							state.rawTexts[data.file:gsub("%.fbx$", "")] = value
						end
						return data
					end,
				}
			end
			if name == "AssetService" then
				return assetService
			end
			if name == "ServerStorage" then
				return storage
			end
			if name == "Workspace" then
				return workspace
			end
			if name == "ReplicatedStorage" then
				return {
					WaitForChild = function(_, child)
						assert(child == "GameShared", 'Fixture invariant: child == "GameShared"')
						return scriptRef("src/shared")
					end,
				}
			end
			if name == "RunService" then
				return {
					IsStudio = function()
						return state.isStudio ~= false
					end,
				}
			end
			error("Unexpected service " .. name)
		end,
	}
	local function loadModule(path)
		if modules[path] ~= nil then
			return modules[path]
		end
		local source = fs.readFile(path)
		if path:match("/Chunk%d+%.luau$") then
			assert(#source <= 140000, "Studio Source budget exceeded: " .. path)
			state.chunkSources[path] = source
		end
		local chunk = assert(loadstring(source, path), "Fixture module could not compile: " .. path)
		setfenv(
			chunk,
			setmetatable({
				game = game,
				workspace = workspace,
				script = scriptRef(path),
				Enum = Enum,
				Vector3 = V3,
				Vector2 = r.Vector2,
				Color3 = r.Color3,
				CFrame = CF,
				Content = {
					fromObject = function(value)
						return content(value)
					end,
					none = content(),
				},
				warn = function(message)
					table.insert(state.warnings, message)
				end,
				task = {
					defer = function(callback)
						table.insert(state.deferred, callback)
					end,
					wait = function()
						state.yields += 1
						if state.onWait then
							state.onWait()
						end
					end,
				},
				typeof = function(value)
					return type(value) == "table" and value.ClassName and "Instance"
						or typeof(value)
				end,
				require = function(module)
					return loadModule(assert(module.Path, "Fixture invariant: module.Path"))
				end,
			}, { __index = getfenv() })
		)
		local result = chunk()

		modules[path] = result
		return result
	end
	state.loadModule = loadModule
	state.SharedBuilder = loadModule("src/shared/Game/FarmEditableMeshBuilder.luau")
	state.Module = loadModule("src/server/Game/FarmGeometry.luau")
	state.runtime = state.Module.new()
	state.catalog = {}
	for _, key in KEYS do
		state.catalog[key] = loadModule("src/shared/Game/FarmGeometryData/" .. key .. "/init.luau")
	end
	if all then
		for _, key in KEYS do
			local original = state:model(folder, key)
			for index in state.catalog[key].meshes do
				state:part(original, key, index)
			end
		end
		for _, name in { "HouseWest", "HouseEast", "HouseNorthWest" } do
			local model = state:model(props, KEYS[1], name)
			for index in state.catalog[KEYS[1]].meshes do
				state:part(model, KEYS[1], index)
			end
		end
		for _, pair in
			{ { "RustedTruck", KEYS[2] }, { "Tyre_1", KEYS[3] }, { "RubbishPile_1", KEYS[4] } }
		do
			state:part(state:model(props, pair[2], pair[1]), pair[2], 1)
		end
	else
		state:part(state:model(folder, KEYS[3]), KEYS[3], 1)
	end
	return state
end
local function zeroWrites(state)
	assert(
		state.creates == 0 and #state.meshes == 0 and state.applies == 0,
		"Refusal allocated or applied geometry"
	)
	for _, part in state.parts do
		assert(part._writes == 0, "Refusal wrote a target property")
	end
end
local function refuse(mutator)
	local state = fixture(false)
	mutator(state)
	for _, part in state.parts do
		rawset(part, "_writes", 0)
	end
	assert(not pcall(function()
		state.runtime:Ensure()
	end), "Invalid ownership/content was accepted")
	zeroWrites(state)
	state.runtime:Destroy()
end

local function checkGeometry(data, mesh, center)
	assert(not mesh.Destroyed, "Fixture invariant: not mesh.Destroyed")
	for index, value in data.positions do
		assert(
			(mesh.vertices[1000 + index * 7] + center - V3.new(table.unpack(value))).Magnitude
				< 0.0002,
			"Fixture invariant: (mesh.vertices[1000 + index * 7] + center - V3.new(table.unpack(value))).Magnitude < 0.0002"
		)
	end
	for index, face in data.triangles do
		local id = 5000 + index * 19
		for corner, vertex in face do
			assert(
				mesh.faces[id][corner] == 1000 + vertex * 7,
				"Position index remapped incorrectly"
			)
			local uv = data.uvs_roblox_flip_v[data.triangle_uvs[index][corner]]
			assert(
				(mesh.uvs[mesh.faceUvs[id][corner]] - r.Vector2.new(table.unpack(uv))).Magnitude
					< 0.000002,
				"Fixture invariant: (mesh.uvs[mesh.faceUvs[id][corner]] - r.Vector2.new(table.unpack(uv))).Magnitude < 0.000002"
			)
			local normal = data.normals[data.triangle_normals[index][corner]]
			assert(
				(mesh.normals[mesh.faceNormals[id][corner]] - V3.new(table.unpack(normal))).Magnitude
					< 0.0002,
				"Fixture invariant: (mesh.normals[mesh.faceNormals[id][corner]] - V3.new(table.unpack(normal))).Magnitude < 0.0002"
			)
		end
	end
end

-- Full actual catalog: stable nonsequential IDs must preserve every position/UV/normal seam.
local state = fixture(true)
for _, key in KEYS do
	assert(
		state.rawTexts[key] == fs.readFile("assets/farm/neutral/" .. key .. ".json"),
		"Chunk concat changed exact neutral JSON bytes: " .. key
	)
end
assert(next(state.chunkSources) ~= nil, "No real chunk Sources were loaded")
print(
	"PASS: actual chunk Sources stay within 140000 bytes; their concat equals all four original neutral JSON files exactly"
)
local before = {}
for _, part in state.parts do
	before[part] = snapshot(part)
end
local totalFaces = 0
for _, key in KEYS do
	for _, data in state.catalog[key].meshes do
		local mesh, center = state.SharedBuilder.Build(data, 500)
		table.insert(state.builds, { data = data, mesh = mesh, center = center })
	end
end
assert(
	#state.builds == 10 and #state.meshes == 10,
	"Fixture invariant: #state.builds == 10 and #state.meshes == 10"
)
for _, build in state.builds do
	totalFaces += #build.data.triangles
	checkGeometry(build.data, build.mesh, build.center)
end
assert(totalFaces == 16226, "Catalog geometry count changed")
for _, mesh in state.meshes do
	mesh:Destroy()
end
state.meshes = {}
local report = state.runtime:Ensure()
assert(type(report) == "table", 'Fixture invariant: type(report) == "table"')
assert(state.creates == 10 and #state.meshes == 10, "Original mesh cache was duplicated")
assert(
	state.fixedCreates == 0 and state.dynamicLive == 10,
	"Server unexpectedly converted or freed cached dynamic meshes"
)
assert(
	state.applies == #state.parts and state.yields > 0,
	"Fixture invariant: state.applies == #state.parts and state.yields > 0"
)
for _, part in state.parts do
	preserved(part, before[part])
	assert(part.MeshContent.Object, "Fixture invariant: part.MeshContent.Object")
end
local creates, applies = state.creates, state.applies
state.runtime:Ensure()
assert(
	state.creates == creates and state.applies == applies,
	"Repeat rebuilt or reapplied intact meshes"
)
local clone = state:part(state:model(state.props, KEYS[3], "Tyre_2"), KEYS[3], 1)
local cloneBefore = snapshot(clone)
state.runtime:Ensure()
assert(
	state.creates == creates and state.applies == applies + 1,
	"New owned instance did not reuse canonical"
)
preserved(clone, cloneBefore)
local beforeReset = snapshot(clone)
clone.MeshContent = content({ marker = "replaced session mesh" })
state.runtime:Ensure()
assert(
	state.creates == creates and state.applies == applies + 2,
	"Changed mesh content did not restore from cache"
)
preserved(clone, beforeReset)
local tyreObject = clone.MeshContent.Object
for _, part in state.parts do
	if part:GetAttribute("AssetKey") == KEYS[3] then
		assert(part.MeshContent.Object == tyreObject, "Shared mesh object differs")
	end
end
state.runtime:Destroy()
for _, mesh in state.meshes do
	assert(mesh.Destroyed, "Destroy leaked EditableMesh")
end
for _, saved in state.snapshots do
	assert(saved.Destroyed, "Snapshot clone leaked")
end
for _, canonical in state.canonicals do
	assert(canonical.Destroyed and canonical.Parent == nil, "Destroy leaked canonical")
end
print(
	"PASS: 10 actual catalog meshes retain positions/corner channels; cache shared/reused; new owned copy restored; all author properties preserved; cleanup"
)

-- Unknown ownership/content must be refused before allocations and writes.
refuse(function(s)
	s.parts[1]:SetAttribute("MeshIndex", 0)
end)
refuse(function(s)
	s.parts[1]:SetAttribute("MeshIndex", 1.5)
end)
refuse(function(s)
	s.parts[1]:SetAttribute("MeshIndex", 99)
end)
refuse(function(s)
	s.parts[1]:SetAttribute("AssetKey", "Unknown")
end)
refuse(function(s)
	s.parts[1]:SetAttribute("corn_project_id", "other")
end)
refuse(function(s)
	s.folder:SetAttribute("CornFarmAssetsOwned", false)
end)
refuse(function(s)
	s.parts[1].Parent:SetAttribute("AssetKey", KEYS[2])
end)
refuse(function(s)
	s.parts[1].Parent = s.workspace
end)
refuse(function(s)
	s.parts[1].Parent:SetAttribute("corn_project_id", "other")
end)
refuse(function(s)
	s.parts[1].Parent = s:model(s.props, KEYS[3], "ManualUnrecognizedTyre")
end)
refuse(function(s)
	s.parts[1].MeshId = "rbxassetid://999"
	s.parts[1].MeshContent = content(nil, "rbxassetid://999")
end)
print(
	"PASS: malformed metadata, wrong owner/root/model and authored URI refuse before geometry allocation or target writes"
)

-- An unrelated mesh and an unowned extra part inside a recognized model remain exact.
local ignored = fixture(false)
local foreign = node("MeshPart", "UnrelatedImportedArt")
configure(foreign, 77)
foreign.Parent = ignored.workspace
rawset(foreign, "_fixture", ignored)
local extra = node("MeshPart", "HandAuthoredExtra")
configure(extra, 78)
extra.Parent = ignored.parts[1].Parent
rawset(extra, "_fixture", ignored)
local foreignBefore, extraBefore = snapshot(foreign), snapshot(extra)
ignored.runtime:Ensure()
preserved(foreign, foreignBefore, true)
preserved(extra, extraBefore, true)
assert(ignored.applies == 1, "Fixture invariant: ignored.applies == 1")
ignored.runtime:Destroy()

-- Build failures occur before any ApplyMesh; partially built resources are released.
for _, failure in { "setter", "create" } do
	local failed = fixture(false)
	local original = snapshot(failed.parts[1])
	if failure == "setter" then
		failed.failBuild = true
	else
		failed.failCreate = 1
	end
	assert(not pcall(function()
		failed.runtime:Ensure()
	end), "Injected build failure accepted")
	assert(failed.applies == 0, "Fixture invariant: failed.applies == 0")
	preserved(failed.parts[1], original, true)
	for _, mesh in failed.meshes do
		assert(mesh.Destroyed, "Failed build leaked mesh")
	end
	failed.failBuild, failed.failCreate = false, nil
	failed.runtime:Ensure()
	assert(failed.applies == 1, "Build failure left runtime busy")
	failed.runtime:Destroy()
end

-- Partial ApplyMesh failure must roll back all prior/current targets and original object/empty content.
local rollback = fixture(false)
local second = rollback:part(rollback:model(rollback.props, KEYS[3], "Tyre_1"), KEYS[3], 1)
local oldObject = { marker = "authored old EditableMesh" }
rollback.parts[1].MeshContent = content(oldObject)
local snapshots = {}
for _, part in rollback.parts do
	snapshots[part] = snapshot(part)
end
rollback.failApply = second
assert(not pcall(function()
	rollback.runtime:Ensure()
end), "Partial ApplyMesh failure accepted")
for _, part in rollback.parts do
	preserved(part, snapshots[part], true)
end
rollback.runtime:Ensure()
for _, part in rollback.parts do
	preserved(part, snapshots[part])
end
rollback.runtime:Destroy()
print(
	"PASS: unrelated art skipped; build failure is atomic; partial ApplyMesh restores original mesh contents/properties and allows retry"
)

-- Snapshot after asynchronous construction preserves author edits made during a yield.
local edited = fixture(false)
local editedPart = edited.parts[1]
local concurrentRefused, expected = false, nil
edited.onCreate = function()
	concurrentRefused = not pcall(function()
		edited.runtime:Ensure()
	end)
	editedPart.CFrame = CF.new(91, 22, -33) * CF.Angles(0.1, 0.4, 0.2)
	editedPart.Size = V3.new(8, 7, 6)
	editedPart.TextureID = "rbxassetid://56789"
	expected = snapshot(editedPart)
end
edited.runtime:Ensure()
assert(concurrentRefused, "Concurrent Ensure was accepted")
preserved(editedPart, (assert(expected, "Fixture invariant: expected")))
edited.runtime:Destroy()
print("PASS: concurrent Ensure refuses cleanly; post-yield snapshot honors current author edits")

-- Every required canonical must be ready before changing the first target.
local lateFailure = fixture(true)
local lateBefore = {}
for _, part in lateFailure.parts do
	lateBefore[part] = snapshot(part)
end
lateFailure.onCreate = function()
	assert(lateFailure.applies == 0, "Applied target before all builds completed")
end
lateFailure.failCreate = 10
assert(not pcall(function()
	lateFailure.runtime:Ensure()
end), "Fixture invariant: not pcall(function() lateFailure.runtime:Ensure() end)")
assert(
	lateFailure.creates == 10 and lateFailure.applies == 0,
	"Fixture invariant: lateFailure.creates == 10 and lateFailure.applies == 0"
)
for _, part in lateFailure.parts do
	preserved(part, lateBefore[part], true)
end
lateFailure.runtime:Destroy()
for _, mesh in lateFailure.meshes do
	assert(mesh.Destroyed, "Late build failure cleanup leaked mesh")
end
for _, part in lateFailure.canonicals do
	assert(part.Destroyed, "Late build failure cleanup leaked canonical")
end

-- Mesh fidelity is immutable on existing targets: mixed values for one shared geometry must refuse.
refuse(function(s)
	local other = s:part(s:model(s.props, KEYS[3], "Tyre_1"), KEYS[3], 1)
	other.RenderFidelity = r.Enum.RenderFidelity.Precise
end)
local fluid = fixture(false)
fluid.parts[1].FluidFidelity = { Name = "NonAutomatic" }
local fluidBefore = snapshot(fluid.parts[1])
assert(not pcall(function()
	fluid.runtime:Ensure()
end), "Fixture invariant: not pcall(function() fluid.runtime:Ensure() end)")
assert(fluid.applies == 0 and fluid.parts[1]._writes == 1, "Fluid fidelity refusal wrote target")
preserved(fluid.parts[1], fluidBefore, true)
fluid.runtime:Destroy()
for _, mesh in fluid.meshes do
	assert(mesh.Destroyed, "Fluid mismatch leaked mesh")
end
for _, part in fluid.canonicals do
	assert(part.Destroyed, "Fluid mismatch leaked canonical")
end

-- Validate all neutral values/indices rather than relying on API setters to reject nonfinite data.
for _, mutation in { "vertex", "uv", "normal", "color", "index" } do
	local invalid = fixture(false)
	local data = invalid.catalog[KEYS[3]].meshes[1]
	if mutation == "vertex" then
		data.positions[1][1] = math.huge
	elseif mutation == "uv" then
		data.uvs_roblox_flip_v[1][2] = math.huge
	elseif mutation == "normal" then
		data.normals[1][3] = 0 / 0
	elseif mutation == "color" then
		data.colors = { { 0.2, math.huge, 0.7, 0.9 } }
		for i in data.triangle_colors do
			data.triangle_colors[i] = { 1, 1, 1 }
		end
	else
		data.triangle_uvs[1][2] = #data.uvs_roblox_flip_v + 1
	end
	assert(not pcall(function()
		invalid.SharedBuilder.Build(data)
	end), "Invalid neutral " .. mutation .. " accepted")
	assert(#invalid.meshes == 0, "Invalid neutral channel allocated a mesh before validation")
	invalid.runtime:Destroy()
end
print(
	"PASS: late build failure leaves every target exact; conflicting fidelity and nonfinite/index data refuse before allocation"
)

-- Client rehydrates its own visible object-content copies. ServerStorage art is out of client scope.
local visible = fixture(true)
visible.dynamicLimit, visible.requireFixed = 1, true
local sourceSnapshots = {}
local visibleCount = 0
for _, part in visible.parts do
	if part:IsDescendantOf(visible.storage) then
		sourceSnapshots[part] = snapshot(part)
	else
		visibleCount += 1
	end
end
local client = visible.SharedBuilder.newRuntime("client")
client:Ensure()
assert(
	visible.creates == 10 and visible.applies == visibleCount,
	"Client did not restore exactly visible owned copies"
)
for part, beforePart in sourceSnapshots do
	preserved(part, beforePart, true)
end
assert(
	visible.maxDynamicLive == 1 and visible.dynamicLive == 0 and visible.fixedCreates == 10,
	"Client did not release one-at-a-time dynamic builders"
)
for _, pair in visible.fixedClones do
	assert(pair.Dynamic.Destroyed and pair.Fixed.FixedSize, "Client cache contains dynamic mesh")
end
for key, entry in client._cache do
	local asset, index = key:match("^(.*):(%d+)$")
	assert(entry.Mesh.FixedSize, "Client retained mutable mesh cache")
	checkGeometry(visible.catalog[asset].meshes[tonumber(index)], entry.Mesh, entry.Center)
end
local clientCreates, clientApplies = visible.creates, visible.applies
client:Ensure()
assert(
	visible.creates == clientCreates and visible.applies == clientApplies,
	"Client repeat duplicated content"
)
client:Destroy()
visible.runtime:Destroy()
for _, mesh in visible.meshes do
	assert(mesh.Destroyed, "Client destroy leaked mesh")
end
print(
	"PASS: client runtime restores visible Props only, leaves ServerStorage exact and repeats without rebuilding"
)

-- Real service calls the server default before RoundService only in authorized solo Studio DEV.
for _, mode in { "studio", "production", "live", "multiplayer" } do
	local serviceState = fixture(false)
	serviceState.isStudio = mode ~= "live"
	local calls, destroyed, logs = 0, 0, 0
	local ensure, destroy = serviceState.Module.Ensure, serviceState.Module.Destroy
	serviceState.Module.Ensure = function()
		calls += 1
		return ensure()
	end
	serviceState.Module.Destroy = function()
		destroyed += 1
		return destroy()
	end
	local service = serviceState.loadModule("src/server/Services/FarmGeometryService.luau")
	assert(
		service.Name == "FarmGeometryService" and service.Order == 15,
		'Fixture invariant: service.Name == "FarmGeometryService" and service.Order == 15'
	)
	service:Init({
		Config = {
			Environment = mode == "production" and "PROD" or "DEV",
			Game = { SessionMode = mode == "multiplayer" and "multiplayer" or "solo_local" },
		},
		Log = {
			Info = function()
				logs += 1
			end,
		},
	})
	local expectedCalls = mode == "studio" and 1 or 0
	assert(
		calls == expectedCalls and logs == expectedCalls and serviceState.applies == expectedCalls,
		"Farm service environment/startup guard differs"
	)
	service:Destroy()
	assert(destroyed == 1, "Fixture invariant: destroyed == 1")
	serviceState.runtime:Destroy()
	for _, mesh in serviceState.meshes do
		assert(mesh.Destroyed, "Service destroy leaked runtime mesh")
	end
end
print(
	"PASS: actual FarmGeometryService restores before RoundService only for solo Studio DEV and destroys default cache"
)

-- Real client controller watches local content changes and repairs late server object replication.
local controlled = fixture(false)
controlled.dynamicLimit, controlled.requireFixed = 1, true
local model = controlled:model(controlled.props, KEYS[3], "Tyre_1")
local part = controlled:part(model, KEYS[3], 1)
local controller = controlled.loadModule("src/client/Controllers/FarmGeometryController.luau")
controller:Init({ Config = { Environment = "DEV", Game = { SessionMode = "solo_local" } } })
assert(
	controller.Name == "FarmGeometryController" and controller.Order == 40,
	'Fixture invariant: controller.Name == "FarmGeometryController" and controller.Order == 40'
)
controller:Start()
controlled:flush()
assert(
	controlled.creates == 1 and controlled.applies == 1,
	"Fixture invariant: controlled.creates == 1 and controlled.applies == 1"
)
local connection = assert(controller._parts[part], "Fixture invariant: controller._parts[part]")
controller:Start()
assert(controller._parts[part] == connection, "Repeated Start duplicated watchers")
local count = controlled.applies
part.MeshContent = content({ marker = "late replicated server peer object" })
controlled:flush()
assert(
	controlled.creates == 1 and controlled.applies == count + 1,
	"Late content replacement did not reuse local mesh"
)
assert(
	part.MeshContent.Object == controller._runtime._cache[KEYS[3] .. ":1"].Mesh,
	'Fixture invariant: part.MeshContent.Object == controller._runtime._cache[KEYS[3] .. ":1"].Mesh'
)
model.Parent = nil
for _, watcher in connection do
	assert(not watcher.Connected, "Removing part leaked watcher")
end
assert(controller._parts[part] == nil, "Removed part remained registered")
controlled:flush()
part.MeshContent = content({ marker = "removed object edit" })
assert(#controlled.deferred == 0, "Removed part still scheduled restoration")
model.Parent = controlled.props
assert(#controlled.deferred > 0, "Fixture invariant: #controlled.deferred > 0")
count = controlled.applies
controller:Destroy()
controlled:flush()
assert(
	controlled.applies == count and next(controller._parts) == nil,
	"Destroyed controller wrote targets from deferred work"
)
controlled.runtime:Destroy()
for _, mesh in controlled.meshes do
	assert(mesh.Destroyed, "Controller cleanup leaked mesh")
end
print(
	"PASS: actual client controller repairs late peer content with cache, disconnects removed parts and cancels deferred work on Destroy"
)

-- Async construction must revalidate owner roots as well as individual target metadata.
for _, mutation in
	{
		"part_metadata",
		"part_uri",
		"root_owner",
		"root_parent",
		"root_name",
		"map_owner",
		"map_parent",
		"props_parent",
	}
do
	local async = fixture(false)
	if mutation == "props_parent" then
		async:part(async:model(async.props, KEYS[3], "Tyre_1"), KEYS[3], 1)
	end
	local asyncExpected
	async.onCreate = function()
		if mutation == "part_metadata" then
			async.parts[1]:SetAttribute("MeshIndex", 99)
		elseif mutation == "part_uri" then
			async.parts[1].MeshId = "rbxassetid://manual"
			async.parts[1].MeshContent = content(nil, "rbxassetid://manual")
		elseif mutation == "root_owner" then
			async.folder:SetAttribute("CornFarmAssetsOwned", false)
		elseif mutation == "root_name" then
			async.folder.Name = "MovedFarmAssets"
		elseif mutation == "map_owner" then
			async.map:SetAttribute("corn_project_id", "other")
		elseif mutation == "map_parent" then
			async.map.Parent = nil
		elseif mutation == "props_parent" then
			async.props.Parent = nil
		else
			async.folder.Parent = async.workspace
		end
		asyncExpected = snapshot(async.parts[1])
	end
	local ok = pcall(function()
		async.runtime:Ensure()
	end)
	assert(not ok and async.applies == 0, "Async ownership change accepted: " .. mutation)
	preserved(async.parts[1], assert(asyncExpected, "Fixture invariant: asyncExpected"), true)
	async.runtime:Destroy()
end
print("PASS: owner roots/content/metadata are revalidated after yields before target writes")

local canceled = fixture(false)
local canceledBefore = snapshot(canceled.parts[1])
canceled.onCreate = function()
	canceled.runtime:Destroy()
end
assert(not pcall(function()
	canceled.runtime:Ensure()
end), "Fixture invariant: not pcall(function() canceled.runtime:Ensure() end)")
assert(canceled.applies == 0, "Fixture invariant: canceled.applies == 0")
preserved(canceled.parts[1], canceledBefore, true)
for _, mesh in canceled.meshes do
	assert(mesh.Destroyed, "Cancellation leaked in-flight mesh")
end
for _, canonical in canceled.canonicals do
	assert(canonical.Destroyed, "Cancellation leaked in-flight canonical")
end
print("PASS: Destroy during async creation cancels writes and releases in-flight resources")

-- Streaming can deliver a partial owned model to the client; server remains strict.
local incomplete = fixture(false)
incomplete.dynamicLimit, incomplete.requireFixed = 1, true
local partial = incomplete:model(incomplete.props, KEYS[1], "HouseWest")
local incompletePart = incomplete:part(partial, KEYS[1], 1)
local incompleteBefore = snapshot(incompletePart)
assert(not pcall(function()
	incomplete.runtime:Ensure()
end), "Server accepted malformed incomplete owned model")
assert(
	incomplete.applies == 0 and incomplete.creates == 0,
	"Server incomplete refusal built/applied geometry"
)
local incompleteController =
	incomplete.loadModule("src/client/Controllers/FarmGeometryController.luau")
incompleteController:Init({
	Config = { Environment = "DEV", Game = { SessionMode = "solo_local" } },
})
assert(
	pcall(function()
		incompleteController:Start()
	end),
	"Partial client replication terminated bootstrap"
)
assert(incomplete.applies == 0 and incomplete.creates == 0, "Start synchronously built geometry")
incomplete:flush()
assert(
	incomplete.map:GetAttribute("CornFarmGeometryStatus") == "waiting"
		and incomplete.map:GetAttribute("CornFarmGeometryPending") == 1,
	"Partial model did not report waiting/pending"
)
assert(
	incomplete.applies == 0 and incomplete.creates == 0 and #incomplete.deferred == 0,
	"Partial model repeatedly built or retried without arrival"
)
preserved(incompletePart, incompleteBefore, true)
local completeWhilePending =
	incomplete:part(incomplete:model(incomplete.props, KEYS[3], "Tyre_1"), KEYS[3], 1)
incomplete:flush()
assert(
	incomplete.creates == 1
		and incomplete.applies == 1
		and completeWhilePending.MeshContent.Object.FixedSize,
	"One partial streamed model blocked a separate complete model"
)
assert(
	incomplete.map:GetAttribute("CornFarmGeometryPending") == 1,
	"Partial Barn lost waiting state after another model loaded"
)
for index = 2, 7 do
	incomplete:part(partial, KEYS[1], index)
end
incomplete:flush()
assert(
	incomplete.creates == 8 and incomplete.applies == 8 and incomplete.fixedCreates == 8,
	"Completed model arrival did not restore all seven fixed meshes"
)
assert(
	incomplete.map:GetAttribute("CornFarmGeometryStatus") == "ready"
		and incomplete.map:GetAttribute("CornFarmGeometryPending") == 0,
	"Completed stream did not clear waiting"
)
assert(
	incomplete.dynamicLive == 0 and incomplete.maxDynamicLive == 1,
	"Streaming retained multiple mutable client meshes"
)
incompleteController:Destroy()
incomplete:flush()
assert(
	incomplete.map:GetAttribute("CornFarmGeometryStatus") == "stopped",
	"Controller cleanup lacks stopped status"
)
incomplete.runtime:Destroy()
print(
	"PASS: server stays strict; streamed partial client model waits without bootstrap abort/polling, then events restore all seven fixed meshes"
)

-- Fixed clone allocation failure must be explicit, atomic, and event-retry only.
local fixedFailure = fixture(false)
fixedFailure.dynamicLimit, fixedFailure.requireFixed, fixedFailure.failFixed = 1, true, 1
local failedModel = fixedFailure:model(fixedFailure.props, KEYS[3], "Tyre_1")
local failedPart = fixedFailure:part(failedModel, KEYS[3], 1)
local failedBefore = snapshot(failedPart)
local failedController =
	fixedFailure.loadModule("src/client/Controllers/FarmGeometryController.luau")
failedController:Init({ Config = { Environment = "DEV", Game = { SessionMode = "solo_local" } } })
assert(
	pcall(function()
		failedController:Start()
	end),
	"Memory error synchronously aborted bootstrap"
)
fixedFailure:flush()
assert(
	fixedFailure.map:GetAttribute("CornFarmGeometryStatus") == "error"
		and fixedFailure.map:GetAttribute("CornFarmGeometryError") ~= ""
		and #fixedFailure.warnings > 0,
	"Fixed memory failure was not explicitly reported"
)
assert(
	fixedFailure.fixedCreates == 1 and fixedFailure.applies == 0 and fixedFailure.dynamicLive == 0,
	"Fixed copy failure applied/leaked mutable geometry"
)
preserved(failedPart, failedBefore, true)
assert(#fixedFailure.deferred == 0, "Failed build started unconditional retry loop")
fixedFailure:flush()
assert(fixedFailure.fixedCreates == 1, "Idle retry repeated known memory failure")
fixedFailure.failFixed = nil
failedPart.MeshContent = content({ marker = "real late content event triggers retry" })
fixedFailure:flush()
assert(
	fixedFailure.fixedCreates == 2 and fixedFailure.creates == 1 and fixedFailure.applies == 1,
	"Actual content event failed to retry cached repair"
)
assert(
	fixedFailure.map:GetAttribute("CornFarmGeometryStatus") == "ready"
		and fixedFailure.map:GetAttribute("CornFarmGeometryError") == "",
	"Successful event retry retained stale error status"
)
failedController:Destroy()
fixedFailure.runtime:Destroy()
for _, mesh in fixedFailure.meshes do
	assert(mesh.Destroyed, "Memory failure/retry cleanup leaked mesh")
end
print(
	"PASS: fixed-copy memory failure releases temporary geometry, reports error, avoids idle retries and recovers on a real content event"
)

-- Metadata replication can complete without another DescendantAdded or content event.
local metadata = fixture(false)
metadata.dynamicLimit, metadata.requireFixed = 1, true
local metadataModel = metadata:model(metadata.props, KEYS[3], "Tyre_1")
local metadataPart = metadata:part(metadataModel, KEYS[3], 1)
metadataModel:SetAttribute("CornFarmAssetOwned", nil)
metadataModel:SetAttribute("AssetKey", nil)
metadataPart:SetAttribute("MeshIndex", nil)
local metadataController = metadata.loadModule("src/client/Controllers/FarmGeometryController.luau")
metadataController:Init({ Config = { Environment = "DEV", Game = { SessionMode = "solo_local" } } })
metadataController:Start()
metadata:flush()
assert(
	metadata.map:GetAttribute("CornFarmGeometryStatus") == "waiting"
		and metadata.map:GetAttribute("CornFarmGeometryPending") == 1
		and metadata.creates == 0,
	"Missing initial model ownership metadata was not pending"
)
metadataModel:SetAttribute("CornFarmAssetOwned", true)
metadataModel:SetAttribute("AssetKey", KEYS[3])
metadata:flush()
assert(
	metadata.map:GetAttribute("CornFarmGeometryPending") == 1 and metadata.creates == 0,
	"Missing part metadata was not kept pending"
)
metadataPart:SetAttribute("MeshIndex", 1)
metadata:flush()
assert(
	metadata.creates == 1
		and metadata.applies == 1
		and metadata.map:GetAttribute("CornFarmGeometryStatus") == "ready",
	"Metadata-only arrival failed to trigger complete-model repair"
)
metadataController:Destroy()
metadata.runtime:Destroy()
for _, mesh in metadata.meshes do
	assert(mesh.Destroyed, "Metadata retry leaked geometry")
end
print(
	"PASS: missing model/part metadata waits; ownership/key/index attribute events alone trigger complete fixed repair"
)

-- A failed canonical after fixed conversion must release both temporary and fixed resources atomically.
local fixedCanonical = fixture(true)
fixedCanonical.dynamicLimit, fixedCanonical.requireFixed, fixedCanonical.failCreate = 1, true, 10
local fixedClient = fixedCanonical.SharedBuilder.newRuntime("client")
local originalFixedTargets = {}
for _, target in fixedCanonical.parts do
	originalFixedTargets[target] = snapshot(target)
end
assert(not pcall(function()
	fixedClient:Ensure()
end), "Client late canonical failure accepted")
assert(
	fixedCanonical.fixedCreates == 10
		and fixedCanonical.applies == 0
		and fixedCanonical.dynamicLive == 0,
	"Late fixed canonical failure applied/leaked mutable geometry"
)
for target, beforeTarget in originalFixedTargets do
	preserved(target, beforeTarget, true)
end
fixedClient:Destroy()
fixedCanonical.runtime:Destroy()
for _, mesh in fixedCanonical.meshes do
	assert(mesh.Destroyed, "Client canonical failure leaked fixed/dynamic mesh")
end
for _, canonical in fixedCanonical.canonicals do
	assert(canonical.Destroyed, "Client canonical failure leaked canonical")
end
print(
	"PASS: failure after tenth fixed conversion applies nothing and releases every fixed/dynamic/canonical resource"
)
