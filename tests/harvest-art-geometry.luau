-- Real shared producer over the actual verified catalog in a limited API adapter.
-- No scene serialization, Studio/GPU, asset moderation or FPS claim.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local r = require("@lune/roblox")
local V3, CF = r.Vector3, r.CFrame
local catalog = serde.decode("json", fs.readFile("assets/harvest-warden/roblox-catalog.json"))
local source = fs.readFile("src/shared/Game/HarvestArtGeometry.luau")
local OWNER, PROJECT = "harvest_warden_v1", "children_of_corn"
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
local Enum = setmetatable(
	{ ContentSourceType = { None = "None", Object = "Object", Uri = "Uri" } },
	{ __index = r.Enum }
)
local function content(object, uri)
	return {
		SourceType = if object then "Object" elseif uri and uri ~= "" then "Uri" else "None",
		Object = object,
		Uri = uri or "",
	}
end

local function runTogether(...)
	local threads, result = {}, {}
	for index, callback in { ... } do
		threads[index] = coroutine.create(function()
			result[index] = table.pack(callback())
		end)
	end
	local iterations = 0
	while true do
		local active = false
		for _, thread in threads do
			if coroutine.status(thread) ~= "dead" then
				active = true
				local ok, problem = coroutine.resume(thread)
				assert(ok, problem)
			end
		end
		if not active then
			break
		end
		iterations += 1
		assert(iterations < 100000, "Fixture construction deadlocked")
	end
	return result
end
local function run(callback)
	return table.unpack(runTogether(callback)[1])
end

local function fixture(mutate)
	local state = {
		mutableLive = 0,
		maxMutable = 0,
		mutableCreated = 0,
		fixedCreated = 0,
		canonicalCreated = 0,
		applies = 0,
		yields = 0,
		requireCounts = {},
		meshes = {},
		parts = {},
		fail = nil,
		failOnce = false,
		clones = {},
	}
	local methods = {}
	local node
	node = function(class, name)
		local item = {
			_values = {
				ClassName = class,
				Name = name or class,
				Archivable = true,
				MeshId = "",
				MeshContent = content(),
				TextureID = "",
				TextureContent = content(),
				CFrame = CF.identity,
				Size = V3.one,
				PivotOffset = CF.identity,
				Color = r.Color3.new(1, 1, 1),
				Material = r.Enum.Material.Plastic,
				MaterialVariant = "",
				Transparency = 0,
				Reflectance = 0,
				Anchored = false,
				CanCollide = true,
				CanTouch = true,
				CanQuery = true,
				CastShadow = true,
				DoubleSided = false,
				CollisionGroup = "Default",
				Massless = false,
				CustomPhysicalProperties = nil,
				CollisionFidelity = r.Enum.CollisionFidelity.Box,
				RenderFidelity = r.Enum.RenderFidelity.Automatic,
			},
			_children = {},
			_attributes = {},
			_state = state,
			_writes = 0,
		}
		return setmetatable(item, {
			__index = function(self, key)
				return methods[key] or self._values[key]
			end,
			__newindex = function(self, key, value)
				if key == "Parent" then
					local previous = self._values.Parent
					if previous then
						local index = table.find(previous._children, self)
						if index then
							table.remove(previous._children, index)
						end
					end
					if value then
						table.insert(value._children, self)
					end
				elseif key == "TextureID" then
					self._values.TextureContent = content(nil, value)
				elseif key == "TextureContent" then
					self._values.TextureID = if value.SourceType == "Uri" then value.Uri else ""
				elseif key == "MeshId" then
					self._values.MeshContent = content(nil, value)
				elseif key == "MeshContent" then
					self._values.MeshId = if value.SourceType == "Uri" then value.Uri else ""
				end
				self._values[key] = value
				self._writes += 1
			end,
		})
	end
	function methods:IsA(class)
		return class == self.ClassName or (class == "BasePart" and self.ClassName == "MeshPart")
	end
	function methods:SetAttribute(key, value)
		self._attributes[key] = value
	end
	function methods:GetAttribute(key)
		return self._attributes[key]
	end
	function methods:GetAttributes()
		return table.clone(self._attributes)
	end
	function methods:GetChildren()
		return table.clone(self._children)
	end
	function methods:GetDescendants()
		local result = {}
		local function visit(parent)
			for _, child in parent._children do
				table.insert(result, child)
				visit(child)
			end
		end
		visit(self)
		return result
	end
	function methods:Clone()
		if self.Archivable == false then
			return nil
		end
		local clone = node(self.ClassName, self.Name)
		for key, value in self._values do
			if key ~= "Parent" then
				clone._values[key] = value
			end
		end
		clone._attributes = table.clone(self._attributes)
		for _, child in self._children do
			local copy = child:Clone()
			if copy then
				copy.Parent = clone
			end
		end
		table.insert(state.clones, clone)
		return clone
	end
	function methods:Destroy()
		self.Parent = nil
		for _, child in self:GetChildren() do
			child:Destroy()
		end
		self.Destroyed = true
	end
	function methods:ApplyMesh(other)
		state.applies += 1
		self.MeshContent = other.MeshContent
		for _, property in PROPERTIES do
			self[property] = other[property]
		end
		self.CollisionFidelity = other.CollisionFidelity
		self.RenderFidelity = other.RenderFidelity
		if state.failApply == self then
			state.failApply = nil
			error("injected partial ApplyMesh failure")
		end
	end
	local function shouldFail(kind)
		if state.fail == kind then
			if state.failOnce then
				state.fail = nil
			end
			return true
		end
		return false
	end
	local function mesh(fixed, original)
		local item = {
			FixedSize = fixed,
			vertices = original and original.vertices or {},
			normals = original and original.normals or {},
			uvs = original and original.uvs or {},
			faces = original and original.faces or {},
			faceNormals = original and original.faceNormals or {},
			faceUvs = original and original.faceUvs or {},
			Destroyed = false,
			_original = original,
		}
		if not fixed then
			state.mutableLive += 1
			state.maxMutable = math.max(state.maxMutable, state.mutableLive)
			assert(state.mutableLive == 1, "Producer did not serialize the tiny mutable budget")
		end
		local counters = { vertex = 0, normal = 0, uv = 0, face = 0 }
		function item:AddVertex(value)
			if shouldFail("vertex") then
				error("injected AddVertex failure")
			end
			counters.vertex += 1
			local id = 1000 + counters.vertex * 7
			self.vertices[id] = value
			return id
		end
		function item:AddNormal(value)
			counters.normal += 1
			local id = 2000 + counters.normal * 11
			self.normals[id] = value
			return id
		end
		function item:AddUV(value)
			counters.uv += 1
			local id = 3000 + counters.uv * 13
			self.uvs[id] = value
			return id
		end
		function item:AddTriangle(a, b, c)
			if shouldFail("triangle") then
				error("injected AddTriangle failure")
			end
			counters.face += 1
			local id = 4000 + counters.face * 17
			self.faces[id] = { a, b, c }
			return id
		end
		function item:SetFaceNormals(face, values)
			self.faceNormals[face] = values
		end
		function item:SetFaceUVs(face, values)
			self.faceUvs[face] = values
		end
		function item:Destroy()
			if not self.Destroyed and not self.FixedSize then
				state.mutableLive -= 1
			end
			self.Destroyed = true
		end
		table.insert(state.meshes, item)
		return item
	end
	local service = {}
	function service:CreateEditableMesh()
		state.mutableCreated += 1
		if shouldFail("mutable") then
			return nil
		end
		return mesh(false)
	end
	function service:CreateEditableMeshAsync(value, options)
		assert(
			value.SourceType == "Object"
				and value.Object
				and not value.Object.FixedSize
				and not value.Object.Destroyed
				and options.FixedSize == true,
			"Expected live mutable -> fixed-size conversion"
		)
		state.fixedCreated += 1
		if shouldFail("fixed") then
			error("injected fixed conversion failure")
		end
		return mesh(true, value.Object)
	end
	function service:CreateMeshPartAsync(value, options)
		assert(
			value.SourceType == "Object"
				and value.Object.FixedSize
				and not value.Object.Destroyed
				and state.mutableLive == 0,
			"Canonical published before mutable release/fixed conversion"
		)
		assert(
			options.CollisionFidelity == r.Enum.CollisionFidelity.Box
				and options.RenderFidelity == r.Enum.RenderFidelity.Automatic,
			"Unexpected art fidelity"
		)
		state.canonicalCreated += 1
		if shouldFail("part") then
			error("injected MeshPart allocation failure")
		end
		local part = node("MeshPart", "Canonical")
		part.MeshContent = value
		table.insert(state.parts, part)
		return part
	end
	local data = { Name = "HarvestGeometryData" }
	function data:WaitForChild(key)
		return { Name = key }
	end
	local fn = assert(loadstring(source, "HarvestArtGeometry"))
	setfenv(
		fn,
		setmetatable({
			game = {
				GetService = function(_, name)
					assert(name == "AssetService", "Unexpected service access: " .. name)
					return service
				end,
			},
			script = {
				Parent = {
					WaitForChild = function(_, name)
						assert(name == "HarvestGeometryData")
						return data
					end,
				},
			},
			require = function(ref)
				state.requireCounts[ref.Name] = (state.requireCounts[ref.Name] or 0) + 1
				if ref == data then
					return catalog
				end
				local result = { meshes = {} }
				for _, key in assert(catalog.assets[ref.Name]).meshes do
					result.meshes[key] = if mutate
						then serde.decode("json", serde.encode("json", catalog.meshes[key]))
						else catalog.meshes[key]
					if mutate then
						mutate(result.meshes[key])
					end
				end
				return result
			end,
			Instance = { new = node },
			CFrame = CF,
			Vector3 = V3,
			Vector2 = r.Vector2,
			Color3 = r.Color3,
			Enum = Enum,
			Content = {
				fromObject = function(object)
					return content(object)
				end,
			},
			task = {
				wait = function()
					state.yields += 1
					coroutine.yield()
				end,
			},
		}, { __index = getfenv() })
	)
	state.api = fn()
	state.node = node
	return state
end

local function near(a, b, tolerance)
	assert((a - b).Magnitude < (tolerance or 0.00015), "Geometry channel differs")
end
local function preserved(part, before, meshToo)
	for _, property in PROPERTIES do
		assert(part[property] == before[property], "Authored property lost: " .. property)
	end
	assert(
		part.Parent == before.Parent and part.Name == before.Name,
		"Authored identity/parent changed"
	)
	for key, value in before.Attributes do
		assert(part:GetAttribute(key) == value, "Authored attribute changed")
	end
	if meshToo then
		assert(
			part.MeshContent.Object == before.MeshContent.Object
				and part.MeshContent.SourceType == before.MeshContent.SourceType,
			"Rollback lost prior geometry"
		)
	end
end
local function snapshot(part)
	local result = {
		Parent = part.Parent,
		Name = part.Name,
		Attributes = part:GetAttributes(),
		MeshContent = part.MeshContent,
	}
	for _, property in PROPERTIES do
		result[property] = part[property]
	end
	return result
end

local state = fixture()
local geometry = state.api
assert(
	state.mutableCreated == 0 and state.requireCounts.HarvestGeometryData == 1,
	"Eager allocation/data require"
)
local cornKey = "Corn_A_Near/Corn_A_Near/1"
local info = geometry.MeshInfo(cornKey)
assert(
	state.requireCounts.Corn_A_Near == 1 and state.mutableCreated == 0,
	"MeshInfo must decode lazily without allocation"
)
assert(
	info.sourceName == "Corn_A_Near"
		and math.abs(info.size.Y - 8) < 0.0001
		and info.materialName
		and info.textureId == geometry.TextureId("corn_leaf_dry"),
	"Corn metadata/bounds/texture lost"
)
assert(geometry.MeshInfo(cornKey) == info, "MeshInfo is not cached")
assert(not pcall(function()
	info.textureId = "changed"
end), "MeshInfo is mutable")
local concurrent = runTogether(function()
	return geometry.Template("Corn_A_Near")
end, function()
	return geometry.Template("Corn_A_Near")
end, function()
	return geometry.Template("BarnDark_Open")
end)
assert(
	concurrent[1][1] == concurrent[2][1] and geometry.Stats().meshes == 5 and state.maxMutable == 1,
	"Concurrent same/different requests duplicated cache or exceeded allocator"
)
local assetKeys = {}
for key in catalog.assets do
	table.insert(assetKeys, key)
end
table.sort(assetKeys)
local templates = {}
for _, key in assetKeys do
	templates[key] = run(function()
		return geometry.Template(key)
	end)
end
assert(
	geometry.Stats().meshes == 86
		and state.mutableCreated == 86
		and state.fixedCreated == 86
		and state.canonicalCreated == 86,
	"Catalog mesh/cache count differs"
)
assert(
	state.mutableLive == 0 and state.yields > 0,
	"Mutable geometry leaked or large construction did not yield"
)
local totalFaces, totalVertices = 0, 0
for _, part in state.parts do
	assert(
		part.Parent == nil
			and part.Archivable
			and part.Anchored
			and part.Massless
			and not part.CanCollide
			and not part.CanTouch
			and not part.CanQuery,
		"Canonical is parented or affects physics"
	)
	local key = part:GetAttribute("HarvestMeshKey")
	local data = catalog.meshes[key]
	local fixed = part.MeshContent.Object
	assert(
		fixed.FixedSize and not fixed.Destroyed and fixed._original.Destroyed,
		"Canonical must retain only fixed mesh"
	)
	assert(
		part:GetAttribute("HarvestGeometryOwner") == OWNER
			and part:GetAttribute("corn_project_id") == PROJECT
			and part:GetAttribute("HarvestAssetKey") == data.assetKey,
		"Canonical ownership lost"
	)
	local center = V3.new(table.unpack(data.center))
	near(part.CFrame.Position, center)
	near(part.Size, V3.new(table.unpack(data.size)))
	assert(
		part.TextureID == data.textureId
			and part.Material == r.Enum.Material[data.material]
			and part.DoubleSided == data.doubleSided,
		"Canonical material/texture lost"
	)
	for index, position in data.positions do
		near(fixed.vertices[1000 + index * 7] + center, V3.new(table.unpack(position)))
		near(fixed.normals[2000 + index * 11], V3.new(table.unpack(data.normals[index])))
		near(fixed.uvs[3000 + index * 13], r.Vector2.new(table.unpack(data.uvs[index])), 0.000001)
	end
	for index, triangle in data.triangles do
		local face = 4000 + index * 17
		for corner, vertex in triangle do
			assert(fixed.faces[face][corner] == 1000 + vertex * 7, "Stable vertex IDs lost")
			assert(
				fixed.faceNormals[face][corner] == 2000 + vertex * 11
					and fixed.faceUvs[face][corner] == 3000 + vertex * 13,
				"Face UV/normal channels lost"
			)
		end
	end
	totalFaces += #data.triangles
	totalVertices += #data.positions
end
assert(totalFaces == 22608 and totalVertices == 39153, "Actual catalog geometry totals differ")
for _, key in { "WardenClassic", "WardenDetailed" } do
	local template = templates[key]
	local sections = {}
	assert(
		template:IsA("Model") and template.Parent == nil,
		"Warden template must remain unparented"
	)
	local names, neonEyes = {}, {}
	for _, part in template:GetChildren() do
		local section = part:GetAttribute("HarvestSection")
		sections[section] = true
		assert(part:GetAttribute("HarvestOffset") == part.CFrame, "Section offset lost")
		assert(not names[part.Name], "Material primitives have duplicate names: " .. part.Name)
		names[part.Name] = true
		if
			(section == "LeftEye" or section == "RightEye")
			and part.Material == r.Enum.Material.Neon
		then
			assert(
				part.Material == r.Enum.Material.Neon and part.Color.R > 0.9 and part.Color.G < 0.1,
				"Red Neon eyes missing"
			)
			neonEyes[section] = true
		end
	end
	assert(neonEyes.LeftEye and neonEyes.RightEye, "Two glowing eye primitives required")
	for _, section in
		{
			"Coat",
			"Head",
			"Hat",
			"LeftArm",
			"RightArm",
			"LeftLeg",
			"RightLeg",
			"LeftEye",
			"RightEye",
		}
	do
		assert(sections[section], "Warden section missing: " .. section)
	end
	local clone = template:Clone()
	assert(
		clone ~= template
			and #clone:GetChildren() == #template:GetChildren()
			and clone:GetAttribute("HarvestGeometryOwner") == OWNER,
		"Template clone lost geometry/ownership"
	)
	clone:Destroy()
	assert(not template.Destroyed, "Destroying a clone destroyed cached template")
end
local allCorn = run(function()
	return geometry.GetCornTemplates()
end)
assert(
	geometry.GetCornTemplates() == allCorn
		and #allCorn.Near == 4
		and #allCorn.Mid == 4
		and #allCorn.Far == 4,
	"Corn LOD catalog differs"
)
for _, lod in { "Near", "Mid", "Far" } do
	for index = 1, 4 do
		assert(
			allCorn[lod][index]:IsA("MeshPart")
				and allCorn[lod][index]:GetAttribute("CornPlantTemplateOwned") == true,
			"Corn ownership/shape differs"
		)
	end
end
assert(not pcall(function()
	geometry.CornTemplate(0, "Near")
end) and not pcall(function()
	geometry.CornTemplate(1, "Other")
end), "Unknown corn index/LOD accepted")

local target = templates.Corn_A_Near:Clone()
target.Name = "AuthoredCorn"
target.Parent = state.node("Folder", "OwnedArt")
target.CFrame = CF.new(11, 27, -91) * CF.Angles(0.2, 0.4, 0.1)
target.Size = V3.new(4, 7.5, 3)
target.PivotOffset = CF.new(0.2, 0.3, 0.4)
target.TextureID = "rbxassetid://999"
target.Color = r.Color3.new(0.2, 0.3, 0.4)
target.Material = r.Enum.Material.Wood
target.MaterialVariant = "Authored"
target.Transparency = 0.18
target.Reflectance = 0.08
target.Anchored = false
target.CanCollide = true
target.CanTouch = true
target.CanQuery = true
target.CastShadow = true
target.DoubleSided = false
target.CollisionGroup = "Authored"
target.Massless = false
target.CustomPhysicalProperties = { Density = 1.2 }
target.MeshContent = content()
local before = snapshot(target)
assert(run(function()
	return geometry.Apply(target, cornKey)
end) == true, "Empty peer content not restored")
preserved(target, before)
local applies = state.applies
assert(run(function()
	return geometry.Apply(target, cornKey)
end) == false and state.applies == applies, "Apply is not idempotent")
target.MeshContent = content()
target.TextureContent = content({ EditableImage = "manual" })
before = snapshot(target)
assert(run(function()
	return geometry.Apply(target, cornKey)
end))
preserved(target, before)

local function refuse(mutator)
	local part = target:Clone()
	part.MeshContent = content()
	mutator(part)
	local saved = snapshot(part)
	local writes, allocations, applied = part._writes, state.mutableCreated, state.applies
	local ok = pcall(function()
		run(function()
			geometry.Apply(part, cornKey)
		end)
	end)
	assert(not ok, "Foreign/unsafe target accepted")
	assert(
		part._writes == writes and state.mutableCreated == allocations and state.applies == applied,
		"Unsafe target caused allocation/write"
	)
	preserved(part, saved, true)
end
refuse(function(p)
	p:SetAttribute("corn_project_id", "foreign")
end)
refuse(function(p)
	p:SetAttribute("HarvestMeshKey", "Corn_B_Near/Corn_B_Near/1")
end)
refuse(function(p)
	p.MeshId = "rbxassetid://777"
end)
refuse(function(p)
	p.Archivable = false
end)
refuse(function(p)
	p.CollisionFidelity = r.Enum.CollisionFidelity.PreciseConvexDecomposition
end)

target.MeshContent = content({ FixedSize = true, Prior = true })
before = snapshot(target)
state.failApply = target
assert(not pcall(function()
	run(function()
		geometry.Apply(target, cornKey)
	end)
end), "Partial ApplyMesh failure accepted")
preserved(target, before, true)
assert(
	run(function()
		return geometry.Apply(target, cornKey)
	end),
	"Apply retry after rollback failed"
)

for _, kind in { "mutable", "vertex", "triangle", "fixed", "part" } do
	local failed = fixture()
	failed.fail, failed.failOnce = kind, true
	assert(not pcall(function()
		run(function()
			failed.api.Template("Corn_A_Near")
		end)
	end), "Injected allocation/setter failure accepted: " .. kind)
	assert(
		failed.mutableLive == 0 and failed.api.Stats().meshes == 0,
		"Failure leaked mutable/published cache"
	)
	for _, mesh in failed.meshes do
		assert(mesh.Destroyed, "Failed construction leaked fixed/mutable mesh")
	end
	assert(
		run(function()
			return failed.api.Template("Corn_A_Near")
		end),
		"Cache/allocator did not recover after " .. kind
	)
	assert(failed.api.Stats().meshes == 1 and failed.mutableLive == 0, "Retry did not converge")
end
local invalids = {
	function(data)
		data.positions[1][1] = 0 / 0
	end,
	function(data)
		data.normals[1] = { 0, 0, 0 }
	end,
	function(data)
		data.uvs[1][2] = math.huge
	end,
	function(data)
		data.triangles[1][1] = 0
	end,
	function(data)
		data.triangles[1] = { 1, 1, 2 }
	end,
	function(data)
		data.trianglesCount += 1
	end,
}
for _, mutate in invalids do
	local invalid = fixture(mutate)
	assert(not pcall(function()
		run(function()
			invalid.api.Template("Corn_A_Far")
		end)
	end), "Malformed geometry was accepted")
	assert(
		invalid.mutableCreated == 0 and invalid.canonicalCreated == 0,
		"Malformed geometry allocated before validation"
	)
end
local failedConcurrent = fixture()
failedConcurrent.fail, failedConcurrent.failOnce = "fixed", true
local failedResults = runTogether(function()
	return pcall(function()
		return failedConcurrent.api.Template("Corn_A_Near")
	end)
end, function()
	return pcall(function()
		return failedConcurrent.api.Template("Corn_A_Near")
	end)
end)
assert(
	failedResults[1][1] == false
		and failedResults[2][1] == false
		and failedConcurrent.mutableLive == 0,
	"Concurrent followers did not receive a cleaned failure"
)
assert(
	run(function()
		return failedConcurrent.api.Template("Corn_A_Near")
	end) and failedConcurrent.api.Stats().meshes == 1,
	"Concurrent failure left pending/allocator locked"
)
local peer = fixture()
local peerCorn = run(function()
	return peer.api.Template("Corn_A_Near")
end)
assert(
	peerCorn.MeshContent.Object ~= templates.Corn_A_Near.MeshContent.Object
		and peer.api.Stats().meshes == 1,
	"Peer caches share object geometry"
)
print(
	"PASS harvest-art-geometry: actual 86 meshes/39153 vertices/22608 faces, all material/UV/normal channels, fixed canonical, serialized allocator, lazy caches, corn LOD/warden sections/Neon, guarded property-preserving Apply/rollback, 6 invalid catalogs, 5 allocation failure retries and concurrent failure recovery"
)
