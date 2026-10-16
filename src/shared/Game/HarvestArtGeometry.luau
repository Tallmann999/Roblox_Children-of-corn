--!strict
-- Peer-local, cached art geometry. No cloud uploads, placements, or gameplay state.
local AssetService = game:GetService("AssetService")
local Data = script.Parent:WaitForChild("HarvestGeometryData")
local Catalog = require(Data)
local OWNER, PROJECT = "harvest_warden_v1", "children_of_corn"
assert(Catalog.version == 1 and Catalog.owner == OWNER, "Unknown Harvest geometry catalog")

local Geometry = {}
local loaded, infoCache, canonicals, templates = {}, {}, {}, {}
local pending, failures = {}, {}
local allocatorBusy = false
local cornTemplates = nil
local builds = 0

local function finite(number: any): boolean
	return type(number) == "number" and number == number and math.abs(number) < 1000000
end

local function vector(tuple: any): Vector3
	assert(type(tuple) == "table" and #tuple == 3, "Harvest Vector3 tuple required")
	for _, number in tuple do
		assert(finite(number), "Nonfinite Harvest mesh coordinate")
	end
	return Vector3.new(tuple[1], tuple[2], tuple[3])
end

local function asset(key: string)
	local meta = Catalog.assets[key]
	assert(type(key) == "string" and meta, "Unknown Harvest asset key")
	if not loaded[key] then
		local decoded = require(Data:WaitForChild(key))
		assert(
			type(decoded) == "table" and type(decoded.meshes) == "table",
			"Harvest asset data missing"
		)
		local count = 0
		for meshKey in decoded.meshes do
			assert(table.find(meta.meshes, meshKey), "Unexpected Harvest mesh")
			count += 1
		end
		assert(count == #meta.meshes, "Incomplete Harvest asset")
		loaded[key] = decoded
	end
	return loaded[key], meta
end

local function meshData(key: string)
	assert(type(key) == "string", "Harvest mesh key required")
	local assetKey = string.split(key, "/")[1]
	local decoded = asset(assetKey)
	local mesh = decoded.meshes[key]
	assert(mesh and mesh.assetKey == assetKey, "Unknown Harvest mesh key")
	return mesh
end

function Geometry.TextureId(key: string): string
	local value = Catalog.textures[key]
	assert(type(value) == "string" and value:match("^rbxassetid://%d+$"), "Unknown Harvest texture")
	return value
end

function Geometry.MeshInfo(key: string)
	if infoCache[key] then
		return infoCache[key]
	end
	local mesh = meshData(key)
	local center, size = vector(mesh.center), vector(mesh.size)
	assert(size.X > 0 and size.Y > 0 and size.Z > 0, "Positive Harvest mesh bounds required")
	local color = vector(mesh.color)
	assert(
		color.X >= 0
			and color.X <= 1
			and color.Y >= 0
			and color.Y <= 1
			and color.Z >= 0
			and color.Z <= 1,
		"Invalid Harvest color"
	)
	local texture = mesh.textureId
	assert(
		texture == "" or (type(texture) == "string" and texture:match("^rbxassetid://%d+$")),
		"Invalid Harvest texture URI"
	)
	local material = Enum.Material[mesh.material]
	assert(material ~= nil, "Unknown Harvest material")
	local info = table.freeze({
		center = center,
		size = size,
		textureId = texture,
		color = Color3.new(color.X, color.Y, color.Z),
		material = material,
		materialName = mesh.materialName,
		section = mesh.section,
		sourceName = mesh.sourceName,
		assetKey = mesh.assetKey,
		doubleSided = mesh.doubleSided == true,
		triangles = mesh.trianglesCount,
	})
	infoCache[key] = info
	return info
end

local function validate(mesh)
	assert(
		type(mesh.positions) == "table" and #mesh.positions > 0 and #mesh.positions <= 60000,
		"Harvest vertex budget exceeded"
	)
	assert(
		#mesh.normals == #mesh.positions and #mesh.uvs == #mesh.positions,
		"Harvest corner channels differ"
	)
	assert(
		#mesh.triangles > 0 and #mesh.triangles <= 20000 and mesh.trianglesCount == #mesh.triangles,
		"Harvest triangle budget exceeded"
	)
	local operations = 0
	local function tick()
		operations += 1
		if operations >= 1000 then
			operations = 0
			task.wait()
		end
	end
	for index, point in mesh.positions do
		vector(point)
		local normal = vector(mesh.normals[index])
		assert(normal.Magnitude > 0.99 and normal.Magnitude < 1.01, "Harvest unit normal required")
		local uv = mesh.uvs[index]
		assert(
			type(uv) == "table" and #uv == 2 and finite(uv[1]) and finite(uv[2]),
			"Invalid Harvest UV"
		)
		tick()
	end
	for _, triangle in mesh.triangles do
		assert(type(triangle) == "table" and #triangle == 3, "Harvest triangle triple required")
		for _, index in triangle do
			assert(
				finite(index) and index % 1 == 0 and index >= 1 and index <= #mesh.positions,
				"Invalid Harvest vertex index"
			)
		end
		local a, b, c =
			vector(mesh.positions[triangle[1]]),
			vector(mesh.positions[triangle[2]]),
			vector(mesh.positions[triangle[3]])
		assert((b - a):Cross(c - a).Magnitude > 1e-10, "Degenerate Harvest triangle")
		tick()
	end
end

local function canonical(key: string)
	if canonicals[key] then
		return canonicals[key]
	end
	if pending[key] then
		repeat
			task.wait()
		until not pending[key]
		assert(canonicals[key], failures[key] or "Harvest concurrent construction failed")
		return canonicals[key]
	end
	pending[key] = true
	local mesh, fixed, part = nil, nil, nil
	local heldAllocator = false
	local ok, problem = pcall(function()
		local data = meshData(key)
		local info = Geometry.MeshInfo(key)
		validate(data)
		while allocatorBusy do
			task.wait()
		end
		allocatorBusy, heldAllocator = true, true
		mesh = assert(
			AssetService:CreateEditableMesh(),
			"Harvest EditableMesh memory budget unavailable"
		)
		local vertices, normals, uvs = {}, {}, {}
		local operations = 0
		local function tick()
			operations += 1
			if operations >= 500 then
				operations = 0
				task.wait()
			end
		end
		for index, point in data.positions do
			vertices[index] = mesh:AddVertex(vector(point) - info.center)
			normals[index] = mesh:AddNormal(vector(data.normals[index]))
			local uv = data.uvs[index]
			uvs[index] = mesh:AddUV(Vector2.new(uv[1], uv[2]))
			tick()
		end
		for _, triangle in data.triangles do
			local a, b, c = triangle[1], triangle[2], triangle[3]
			local face = mesh:AddTriangle(vertices[a], vertices[b], vertices[c])
			mesh:SetFaceNormals(face, { normals[a], normals[b], normals[c] })
			mesh:SetFaceUVs(face, { uvs[a], uvs[b], uvs[c] })
			tick()
		end
		fixed = assert(
			AssetService:CreateEditableMeshAsync(Content.fromObject(mesh), { FixedSize = true }),
			"Harvest fixed-size mesh memory budget unavailable"
		)
		assert(fixed.FixedSize, "Harvest fixed-size geometry required")
		mesh:Destroy()
		mesh = nil
		part = assert(
			AssetService:CreateMeshPartAsync(Content.fromObject(fixed), {
				CollisionFidelity = Enum.CollisionFidelity.Box,
				RenderFidelity = Enum.RenderFidelity.Automatic,
			}),
			"Harvest canonical MeshPart unavailable"
		)
		part.Name = data.name .. "_Material" .. key:match("/([^/]+)$")
		part.Size, part.CFrame, part.PivotOffset =
			info.size, CFrame.new(info.center), CFrame.identity
		part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
		part.Archivable, part.Massless = true, true
		part.DoubleSided, part.TextureID, part.Color, part.Material =
			info.doubleSided, info.textureId, info.color, info.material
		part.CastShadow = Catalog.assets[info.assetKey].kind ~= "corn"
		part:SetAttribute("corn_project_id", PROJECT)
		part:SetAttribute("HarvestGeometryOwner", OWNER)
		part:SetAttribute("HarvestAssetKey", info.assetKey)
		part:SetAttribute("HarvestMeshKey", key)
		part:SetAttribute("HarvestOffset", CFrame.new(info.center))
		if info.section then
			part:SetAttribute("HarvestSection", info.section)
		end
		canonicals[key] = { Part = part, Mesh = fixed }
		builds += 1
	end)
	if heldAllocator then
		allocatorBusy = false
	end
	pending[key] = nil
	if not ok then
		if part then
			part:Destroy()
		end
		if fixed then
			fixed:Destroy()
		end
		if mesh then
			mesh:Destroy()
		end
		failures[key] = tostring(problem)
		error(problem, 0)
	end
	failures[key] = nil
	return canonicals[key]
end

function Geometry.Template(key: string): Instance
	if templates[key] then
		return templates[key]
	end
	local _, meta = asset(key)
	local entries = {}
	for _, meshKey in meta.meshes do
		table.insert(entries, canonical(meshKey))
	end
	-- Check again after yielding construction; another request may have published it.
	if templates[key] then
		return templates[key]
	end
	if meta.kind == "corn" then
		assert(#entries == 1, "Corn template must be one MeshPart")
		local part = entries[1].Part:Clone()
		part.Name = key
		part:SetAttribute("CornPlantTemplateOwned", true)
		part:SetAttribute("HarvestRootOffset", Geometry.MeshInfo(meta.meshes[1]).center)
		templates[key] = part
		return part
	end
	local model = Instance.new("Model")
	model.Name, model.WorldPivot = key, CFrame.identity
	model:SetAttribute("corn_project_id", PROJECT)
	model:SetAttribute("HarvestGeometryOwner", OWNER)
	model:SetAttribute("HarvestAssetKey", key)
	for _, entry in entries do
		local part = entry.Part:Clone()
		part.Parent = model
	end
	templates[key] = model
	return model
end

function Geometry.CornTemplate(index: number, lod: string): MeshPart
	assert(index % 1 == 0 and index >= 1 and index <= 4, "Corn variety outside catalog")
	assert(lod == "Near" or lod == "Mid" or lod == "Far", "Corn LOD outside catalog")
	local key = "Corn_" .. string.char(64 + index) .. "_" .. lod
	return Geometry.Template(key) :: MeshPart
end

function Geometry.GetCornTemplates()
	if not cornTemplates then
		local ready = { Near = {}, Mid = {}, Far = {} }
		for lod, list in ready do
			for index = 1, 4 do
				list[index] = Geometry.CornTemplate(index, lod)
			end
		end
		cornTemplates = ready
	end
	return cornTemplates
end

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

function Geometry.Apply(part: MeshPart, key: string): boolean
	local function valid()
		assert(
			part:IsA("MeshPart")
				and part:GetAttribute("HarvestGeometryOwner") == OWNER
				and part:GetAttribute("corn_project_id") == PROJECT
				and part:GetAttribute("HarvestMeshKey") == key,
			"Foreign Harvest target was preserved"
		)
		assert(part.MeshId == "", "Manual Harvest mesh URI was preserved")
		assert(part.Archivable, "Nonarchivable Harvest target was preserved")
	end
	valid()
	local entry = canonical(key)
	valid()
	assert(
		part.CollisionFidelity == entry.Part.CollisionFidelity
			and part.RenderFidelity == entry.Part.RenderFidelity,
		"Manually changed Harvest fidelity was preserved"
	)
	local content = part.MeshContent
	assert(
		content.SourceType == Enum.ContentSourceType.None
			or content.SourceType == Enum.ContentSourceType.Object,
		"Foreign Harvest content was preserved"
	)
	if content.SourceType == Enum.ContentSourceType.Object and content.Object == entry.Mesh then
		return false
	end
	local snapshot = {}
	for _, name in PROPERTIES do
		snapshot[name] = (part :: any)[name]
	end
	local backup = assert(part:Clone(), "Harvest rollback snapshot unavailable")
	local ok, problem = pcall(function()
		part:ApplyMesh(entry.Part)
		for _, name in PROPERTIES do
			(part :: any)[name] = snapshot[name]
		end
	end)
	if not ok then
		pcall(function()
			part:ApplyMesh(backup)
			for _, name in PROPERTIES do
				(part :: any)[name] = snapshot[name]
			end
		end)
	end
	backup:Destroy()
	assert(ok, problem)
	return true
end

function Geometry.Stats()
	return { meshes = builds }
end

return table.freeze(Geometry)
