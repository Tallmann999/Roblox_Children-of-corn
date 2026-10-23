-- Four real green datasets over deterministic EditableMesh/native-content APIs.
-- Exercises production Geometry, Appearance and Wind registration; no Studio/GPU.
local fs, r, serde = require("@lune/fs"), require("@lune/roblox"), require("@lune/serde")
local CF, V3, V2, C3 = r.CFrame, r.Vector3, r.Vector2, r.Color3
local SOURCE = {
	geometry = fs.readFile("variants/B/shared/Game/CornGreenGeometry.luau"),
	appearance = fs.readFile("variants/B/shared/Game/CornAppearance.luau"),
	wind = fs.readFile("variants/B/client/Controllers/CornWindController.luau"),
}
local manifest = serde.decode(
	"json",
	fs.readFile(".artifacts/asset-variants/2026-10-23-green-corn/manifest.json")
)
local DATA, META = {}, {}
local checks = 0
local function check(ok, message)
	checks += 1
	assert(ok, message)
end
for _, item in manifest.assets do
	local bytes = fs.readFile(item.runtime_json)
	check(serde.hash("sha256", bytes) == item.runtime_sha256, "Frozen runtime JSON changed")
	DATA[item.key], META[item.key] = serde.decode("json", bytes), item
	if item.module then
		check(
			serde.hash("sha256", fs.readFile(item.module)) == item.module_sha256,
			"Frozen ModuleScript changed"
		)
		check(
			serde.hash("sha256", fs.readFile(item.fbx.path)) == item.fbx.sha256,
			"Frozen root FBX changed"
		)
	end
end
local Enum = setmetatable({
	ContentSourceType = { Uri = "Uri", Object = "Object", Opaque = "Opaque" },
	CreateContentResult = { Success = "Success", StorageLimitExceeded = "StorageLimitExceeded" },
}, { __index = r.Enum })
local originalSize = V3.new(3.0026558642674086, 8, 3.1309012101883917)
local meshId, textureId = "rbxassetid://104111861186519", "rbxassetid://137803536172445"
local function together(...)
	local threads, results = {}, {}
	for i, fn in { ... } do
		threads[i] = coroutine.create(function()
			results[i] = table.pack(fn())
		end)
	end
	for _ = 1, 3000 do
		local any = false
		for _, thread in threads do
			if coroutine.status(thread) ~= "dead" then
				any = true
				local ok, problem = coroutine.resume(thread)
				assert(ok, problem)
			end
		end
		if not any then
			return results
		end
	end
	error("Variant provider deadlock")
end
local function load(source, name, env)
	local fn = assert(loadstring(source, name))
	setfenv(fn, setmetatable(env, { __index = getfenv() }))
	return fn()
end
local function fixture()
	local state = {
		created = {},
		editables = {},
		creates = 0,
		clones = 0,
		bakes = 0,
		editableCalls = 0,
		operations = {},
		fail = nil,
		copiedChannels = {},
	}
	local function failure(kind, call)
		if state.fail and state.fail.kind == kind and state.fail.call == call then
			state.fail = nil
			return true
		end
		return false
	end
	local function operation(kind)
		state.operations[kind] = (state.operations[kind] or 0) + 1
		if failure(kind, state.operations[kind]) then
			error("Injected " .. kind)
		end
	end
	local methods = {}
	local function newPart(content, size)
		local part = setmetatable({
			_attrs = {},
			_children = {},
			_tags = {},
			_values = {
				Name = "MeshPart",
				MeshContent = content,
				MeshId = if content.SourceType == "Uri" then content.Uri else "",
				MeshSize = size,
				Size = size,
				CFrame = CF.identity,
				PivotOffset = CF.identity,
				Archivable = true,
				Anchored = false,
				CanCollide = true,
				CanTouch = true,
				CanQuery = true,
				CastShadow = true,
				DoubleSided = false,
				Color = C3.new(1, 1, 1),
				Material = r.Enum.Material.Plastic,
				MaterialVariant = "",
				Transparency = 0,
				Reflectance = 0,
				Massless = false,
				CollisionGroup = "Default",
				CollisionFidelity = r.Enum.CollisionFidelity.Box,
				RenderFidelity = r.Enum.RenderFidelity.Precise,
			},
		}, {
			__index = function(self, key)
				return methods[key] or self._values[key]
			end,
			__newindex = function(self, key, value)
				self._values[key] = value
			end,
		})
		table.insert(state.created, part)
		return part
	end
	function methods:IsA(class)
		return class == "MeshPart" or class == "BasePart"
	end
	function methods:GetAttribute(key)
		return self._attrs[key]
	end
	function methods:SetAttribute(key, value)
		if key == "CornGreenTemplateVersion" then
			operation("decorate")
		end
		self._attrs[key] = value
	end
	function methods:GetAttributes()
		return table.clone(self._attrs)
	end
	function methods:GetTags()
		return table.clone(self._tags)
	end
	function methods:GetChildren()
		return table.clone(self._children)
	end
	function methods:GetDescendants()
		return table.clone(self._children)
	end
	function methods:Destroy()
		self.Destroyed = true
		self.Parent = nil
	end
	function methods:Clone()
		state.clones += 1
		if failure("cloneNil", state.clones) then
			return nil
		end
		if failure("cloneError", state.clones) then
			error("Injected clone")
		end
		local clone = newPart(self.MeshContent, self.MeshSize)
		clone._values, clone._attrs = table.clone(self._values), table.clone(self._attrs)
		return clone
	end
	local editableMethods = {}
	local function newEditable()
		local object = setmetatable(
			{ vertices = {}, uvs = {}, normals = {}, faces = {}, uvFaces = {}, normalFaces = {} },
			{ __index = editableMethods }
		)
		table.insert(state.editables, object)
		return object
	end
	function editableMethods:AddVertex(value)
		operation("vertex")
		local id = #self.vertices + 1
		self.vertices[id] = value
		return id * 13 + 100
	end
	function editableMethods:AddUV(value)
		operation("uv")
		local id = #self.uvs + 1
		self.uvs[id] = value
		return id * 17 + 200
	end
	function editableMethods:AddNormal(value)
		operation("normal")
		local id = #self.normals + 1
		self.normals[id] = value
		return id * 19 + 300
	end
	function editableMethods:AddTriangle(a, b, c)
		operation("triangle")
		local id = #self.faces + 1
		for _, key in { a, b, c } do
			check(self.vertices[(key - 100) / 13] ~= nil, "Wrong vertex handle")
		end
		self.faces[id] = { a, b, c }
		return id * 23 + 400
	end
	function editableMethods:SetFaceUVs(face, values)
		operation("faceUV")
		check(self.faces[(face - 400) / 23] ~= nil, "Wrong face UV handle")
		for _, key in values do
			check(self.uvs[(key - 200) / 17] ~= nil, "Wrong corner UV handle")
		end
		self.uvFaces[(face - 400) / 23] = table.clone(values)
	end
	function editableMethods:SetFaceNormals(face, values)
		operation("faceNormal")
		check(self.faces[(face - 400) / 23] ~= nil, "Wrong face normal handle")
		for _, key in values do
			check(self.normals[(key - 300) / 19] ~= nil, "Wrong corner normal handle")
		end
		self.normalFaces[(face - 400) / 23] = table.clone(values)
	end
	function editableMethods:Destroy()
		self.Destroyed = true
	end
	local function meshSize(mesh)
		local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
		for _, p in mesh.vertices do
			for i, value in { p.X, p.Y, p.Z } do
				lo[i], hi[i] = math.min(lo[i], value), math.max(hi[i], value)
			end
		end
		return V3.new(hi[1] - lo[1], hi[2] - lo[2], hi[3] - lo[3])
	end
	local service = {}
	function service:CreateEditableMesh()
		state.editableCalls += 1
		if failure("editableNil", state.editableCalls) then
			return nil
		end
		if failure("editableError", state.editableCalls) then
			error("Injected editable")
		end
		return newEditable()
	end
	function service:CreateMeshPartAsync(content, options)
		state.creates += 1
		check(
			options.RenderFidelity == r.Enum.RenderFidelity.Precise
				and options.CollisionFidelity == r.Enum.CollisionFidelity.Box,
			"C fidelity changed"
		)
		coroutine.yield()
		if failure("createNil", state.creates) then
			return nil
		end
		if failure("createError", state.creates) then
			error("Injected create")
		end
		local size = if content.SourceType == "Uri"
			then originalSize * 100
			else meshSize(content.Geometry or content.Object)
		local part = newPart(content, size)
		if failure("contentType", state.creates) then
			part.MeshContent = { SourceType = "Object" }
		end
		if failure("meshBounds", state.creates) then
			part.MeshSize = V3.one
		end
		if failure("foreignAttr", state.creates) then
			part:SetAttribute("Foreign", true)
		end
		if failure("foreignChild", state.creates) then
			part._children = { {} }
		end
		if failure("foreignTag", state.creates) then
			part._tags = { "Foreign" }
		end
		return part
	end
	function service:CreateDataModelContentAsync(content)
		state.bakes += 1
		check(
			content.SourceType == "Object" and not content.Object.Destroyed,
			"Bake did not use live preparation mesh"
		)
		coroutine.yield()
		if failure("bakeError", state.bakes) then
			error("Injected bake")
		end
		if failure("bakeStatus", state.bakes) then
			return "StorageLimitExceeded", { SourceType = "Opaque" }
		end
		if failure("bakeType", state.bakes) then
			return "Success", content
		end
		return "Success", { SourceType = "Opaque", Geometry = content.Object, Token = state.bakes }
	end
	local dataModules = {}
	for _, key in { "Var01", "Var02", "Var03" } do
		dataModules[key] = {
			Key = key,
			IsA = function(_, class)
				return class == "ModuleScript"
			end,
		}
	end
	local folder = {
		FindFirstChild = function(_, key)
			return dataModules[key]
		end,
	}
	local common = {
		CFrame = CF,
		Vector3 = V3,
		Vector2 = V2,
		Color3 = C3,
		Enum = Enum,
		Content = {
			fromUri = function(uri)
				return { SourceType = "Uri", Uri = uri }
			end,
			fromObject = function(mesh)
				return { SourceType = "Object", Object = mesh }
			end,
		},
		task = {
			wait = function()
				coroutine.yield()
			end,
		},
		game = {
			GetService = function(_, name)
				check(name == "AssetService", "Unexpected service")
				return service
			end,
		},
	}
	local geometryEnv = table.clone(common)
	geometryEnv.script = {
		Parent = {
			FindFirstChild = function(_, name)
				return if name == "CornGreenGeometryData" then folder else nil
			end,
		},
	}
	geometryEnv.require = function(module)
		local data = DATA[module.Key]
		return if state.override then state.override(module.Key, data) else data
	end
	local geometry = load(SOURCE.geometry, "CornGreenGeometry", geometryEnv)
	local appearanceEnv = table.clone(common)
	appearanceEnv.script = { Parent = { CornGreenGeometry = geometry } }
	appearanceEnv.require = function(module)
		check(module == geometry, "Wrong geometry require")
		return geometry
	end
	local appearance = load(SOURCE.appearance, "B CornAppearance", appearanceEnv)
	return appearance, geometry, state
end

local appearance, geometry, state = fixture()
for _, key in { "Var01", "Var02", "Var03" } do
	local description = geometry.Describe(key)
	check(
		description.sourceHash == META[key].fbx.sha256,
		"Variant source hash does not bind actual FBX"
	)
	check(
		(description.size - V3.new(table.unpack(DATA[key].bounds.size))).Magnitude < 1e-6,
		"Variant dimensions changed"
	)
	check(
		(description.rootOffset + V3.new(table.unpack(DATA[key].root_offset_studs))).Magnitude
			< 1e-6,
		"Root sign changed"
	)
end
local result = together(appearance.DetailedTemplates, appearance.DetailedTemplates)
local bank = result[1][1]
check(
	result[2][1] == bank
		and state.bakes == 3
		and state.editableCalls == 3
		and state.creates == 7
		and state.clones == 8,
	"Provider must build one URI, three Opaque geometries and eight LOD clones once"
)
check(appearance.DetailedTemplates() == bank and state.bakes == 3, "Bank rebaked")
check(table.isfrozen(bank) and table.isfrozen(bank.Near), "Mutable provider tables")
for i, mesh in state.editables do
	local data = DATA[string.format("Var%02d", i)]
	check(mesh.Destroyed, "Preparation mesh leaked")
	check(
		#mesh.vertices == #data.positions
			and #mesh.faces == 510
			and #mesh.uvs == #data.uvs
			and #mesh.normals == #data.normals,
		"Preparation channels changed"
	)
	for vertex, value in mesh.vertices do
		check(
			(value - V3.new(table.unpack(data.positions[vertex]))).Magnitude < 1e-6,
			"Vertex channel changed"
		)
	end
	for index, triangle in data.triangles do
		for corner, vertex in triangle do
			check(mesh.faces[index][corner] == vertex * 13 + 100, "Triangle winding changed")
			check(
				mesh.uvFaces[index][corner] == data.triangle_uvs[index][corner] * 17 + 200,
				"Corner UV index changed"
			)
			check(
				mesh.normalFaces[index][corner] == data.triangle_normals[index][corner] * 19 + 300,
				"Corner normal index changed"
			)
		end
	end
	for uv, value in mesh.uvs do
		check((value - V2.new(table.unpack(data.uvs[uv]))).Magnitude < 1e-6, "Palette UV moved")
	end
	for normal, value in mesh.normals do
		check(
			(value - V3.new(table.unpack(data.normals[normal]))).Magnitude < 1e-6,
			"Normal channel changed"
		)
	end
end
local kept = {}
for lod, list in bank do
	for variety, part in list do
		kept[part] = true
		check(appearance.IsDetailedPlant(part, variety, lod), "Hybrid renderer contract refused")
		check(
			part.Parent == nil
				and part.Size.Y == 8
				and part.TextureID == textureId
				and part.Color == C3.new(1, 1, 1),
			"Variant appearance/proportions changed"
		)
		check(
			part.MeshContent.SourceType == (if variety == 1 then "Uri" else "Opaque"),
			"Wrong source content kind"
		)
		check(
			part.Anchored
				and not part.CanCollide
				and not part.CanTouch
				and not part.CanQuery
				and part.CastShadow
				and part.DoubleSided,
			"Variant physics/shadows changed"
		)
	end
end
for _, part in state.created do
	if not kept[part] then
		check(part.Destroyed, "Temporary carrier leaked")
	end
end
for _, mode in { "easy", "medium", "hard", "unknown" } do
	check(not appearance.IsDry(mode), "B became dry")
end
check(
	appearance.DryTextureId == textureId and not appearance.IsDry(nil),
	"Preparation/menu became dry"
)

-- Root placement and actual Wind registration over all shapes/heights/yaws.
local function folder(name, parent, attrs)
	return {
		Name = name,
		Parent = parent,
		IsA = function(_, class)
			return class == "Folder"
		end,
		GetAttribute = function(_, key)
			return attrs[key]
		end,
	}
end
local wind = load(SOURCE.wind, "B CornWindController", {
	CFrame = CF,
	Vector3 = V3,
	Enum = Enum,
	game = {
		GetService = function(_, name)
			return if name == "Players" then { LocalPlayer = {} } else {}
		end,
	},
})
for variety = 1, 4 do
	for _, factor in { 0.85, 1, 1.15 } do
		for _, yaw in { 0, 0.73, 2.4, 5.9 } do
			local part = bank.Near[variety]:Clone()
			part.Name = "Corn"
			local size = part:GetAttribute("CornGreenTemplateSize")
			part.Size = V3.new(size.X, size.Y * factor, size.Z)
			local root = V3.new(288.75, 14.47, -153.4)
			part.CFrame = appearance.DetailedPivot(part, root, yaw)
			local offset = part:GetAttribute("HarvestRootOffset")
			local scaled = V3.new(offset.X, offset.Y * factor, offset.Z)
			check(
				(part.CFrame:PointToWorldSpace(-scaled) - root).Magnitude < 0.0001,
				"Tall/short rotated stem root detached"
			)
			local map = {
				GetAttribute = function(_, key)
					return if key == "HarvestArtVariant" then "B" else nil
				end,
			}
			local layerFolder = folder(
				"CornClientPlants",
				map,
				{ CornClientRendererOwned = true, corn_project_id = "children_of_corn" }
			)
			local group = folder("Chunk_1_2", layerFolder, {})
			part.Parent = group
			local layer = {
				Kind = "near",
				Folder = layerFolder,
				Entries = {},
				Count = 0,
				Buckets = {},
				Groups = { [group] = { Entries = {} } },
			}
			wind._map, wind._layers = map, { near = layer }
			wind:_register({ Layer = layer, Plant = part, Parent = group })
			local entry = layer.Entries[part]
			check(
				entry ~= nil and (entry.Base - root).Magnitude < 0.0001,
				"Wind pivot differs from actual stem root"
			)
			part:Destroy()
		end
	end
end

local function released(failed)
	for _, mesh in failed.editables do
		check(mesh.Destroyed, "Failed preparation EditableMesh leaked")
	end
	for _, part in failed.created do
		check(part.Destroyed, "Failed partial bank/carrier leaked")
	end
end
local failCases = {}
for _, kind in { "editableNil", "editableError", "bakeError", "bakeStatus", "bakeType" } do
	for _, call in { 1, 3 } do
		table.insert(failCases, { kind = kind, call = call })
	end
end
for _, kind in { "createNil", "createError" } do
	for _, call in { 1, 2, 3, 6, 7 } do
		table.insert(failCases, { kind = kind, call = call })
	end
end
for _, kind in { "contentType", "meshBounds", "foreignAttr", "foreignChild", "foreignTag" } do
	for _, call in { 1, 3, 7 } do
		table.insert(failCases, { kind = kind, call = call })
	end
end
for _, kind in { "cloneNil", "cloneError" } do
	for _, call in { 1, 4, 8 } do
		table.insert(failCases, { kind = kind, call = call })
	end
end
for _, kind in { "vertex", "uv", "normal", "triangle", "faceUV", "faceNormal", "decorate" } do
	table.insert(failCases, { kind = kind, call = 7 })
end
for _, planned in failCases do
	local subject, _, failed = fixture()
	failed.fail = planned
	local attempt = together(function()
		return pcall(subject.DetailedTemplates)
	end)[1]
	check(not attempt[1], "Injected failure accepted: " .. planned.kind .. "/" .. planned.call)
	released(failed)
	local retry = together(subject.DetailedTemplates)[1][1]
	check(retry.Far[4] ~= nil and subject.DetailedTemplates() == retry, "Failure poisoned retry")
end

local mutations = {
	{
		"moved",
		function(p)
			p.Parent = {}
		end,
	},
	{
		"frame",
		function(p)
			p.CFrame = CF.new(1, 0, 0)
		end,
	},
	{
		"size",
		function(p)
			p.Size = V3.one
		end,
	},
	{
		"texture",
		function(p)
			p.TextureID = "rbxassetid://1"
		end,
	},
	{
		"contentIdentity",
		function(p)
			p.MeshContent = { SourceType = "Opaque", Foreign = true }
		end,
	},
	{
		"owner",
		function(p)
			p:SetAttribute("CornGreenTemplateOwned", nil)
		end,
	},
	{
		"sourceHash",
		function(p)
			p:SetAttribute("CornGreenSourceSHA256", string.rep("0", 64))
		end,
	},
	{
		"root",
		function(p)
			p:SetAttribute("HarvestRootOffset", V3.zero)
		end,
	},
	{
		"templateSize",
		function(p)
			p:SetAttribute("CornGreenTemplateSize", V3.one)
		end,
	},
	{
		"foreignAttr",
		function(p)
			p:SetAttribute("Manual", true)
		end,
	},
	{
		"foreignChild",
		function(p)
			p._children = { {} }
		end,
	},
	{
		"foreignTag",
		function(p)
			p._tags = { "Manual" }
		end,
	},
	{
		"collision",
		function(p)
			p.CanCollide = true
		end,
	},
	{
		"shadow",
		function(p)
			p.CastShadow = false
		end,
	},
	{
		"color",
		function(p)
			p.Color = C3.new(1, 0, 1)
		end,
	},
}
for _, mutation in mutations do
	local subject, _, changed = fixture()
	local templates = together(subject.DetailedTemplates)[1][1]
	local part = templates.Mid[3]
	mutation[2](part)
	check(not pcall(subject.DetailedTemplates), "Foreign cached geometry accepted: " .. mutation[1])
	check(
		not part.Destroyed and changed.bakes == 3,
		"Changed private author work overwritten/deleted"
	)
end
local invalidData = {
	{
		"hash",
		function(d)
			d.exported_fbx_sha256 = string.rep("g", 64)
		end,
	},
	{
		"root",
		function(d)
			d.root_offset_studs[1] += 1
		end,
	},
	{
		"height",
		function(d)
			d.bounds.size[2] = 9
		end,
	},
	{
		"triangle",
		function(d)
			d.triangles[2][1] = 99999
		end,
	},
	{
		"UVindex",
		function(d)
			d.triangle_uvs[2][1] = 99999
		end,
	},
	{
		"normalIndex",
		function(d)
			d.triangle_normals[2][1] = 99999
		end,
	},
	{
		"vertex",
		function(d)
			d.positions[2][1] = 0 / 0
		end,
	},
	{
		"UV",
		function(d)
			d.uvs[2][1] = math.huge
		end,
	},
	{
		"normal",
		function(d)
			d.normals[2][1] = math.huge
		end,
	},
}
for _, case in invalidData do
	local subject, _, failed = fixture()
	local changed = serde.decode("json", serde.encode("json", DATA.Var02))
	case[2](changed)
	failed.override = function(key, data)
		return if key == "Var02" then changed else data
	end
	local attempt = together(function()
		return pcall(subject.DetailedTemplates)
	end)[1]
	check(not attempt[1], "Invalid geometry data accepted: " .. case[1])
	released(failed)
end
local subject, _, concurrent = fixture()
concurrent.fail = { kind = "bakeError", call = 2 }
local recovered = together(function()
	return pcall(subject.DetailedTemplates)
end, subject.DetailedTemplates)
check(not recovered[1][1] and recovered[2][1].Far[4] ~= nil, "Concurrent waiter did not recover")
check(subject.DetailedTemplates() == recovered[2][1], "Concurrent retry not cached")
print(serde.encode("json", {
	pass = true,
	checks = checks,
	failureInjections = #failCases,
	cacheRefusals = #mutations,
	dataRefusals = #invalidData,
	shapes = 4,
	rootHeightYawCases = 48,
	productionSources = { "CornGreenGeometry", "CornAppearance", "CornWindController" },
	Studio = false,
	GPU = false,
	sustainedFPS = false,
}))
