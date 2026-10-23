-- B-only soil provider. Exact validated C FBX channels; no world writes or publication.
-- The sibling GreenBedGeometryData contains Center/End/Skirt.
local AssetService = game:GetService("AssetService")

local Geometry = {}
local KEYS = { "Center", "End", "Skirt" }
local SIZES = {
	Center = Vector3.new(18.296041720615904, 0.7117668934956944, 18.296041774249794),
	End = Vector3.new(18.296041720615904, 0.7117668934956903, 18.296041720615904),
	Skirt = Vector3.new(21.65385258547726, 1.3001554177724333, 21.318965503815413),
}
local BATCH = 128
local OPTIONS = {
	CollisionFidelity = Enum.CollisionFidelity.Box,
	RenderFidelity = Enum.RenderFidelity.Precise,
}
local templates = nil
local building = false

local function vector(value)
	assert(type(value) == "table" and #value == 3, "Mesh Vector3 triple required")
	for _, number in value do
		assert(
			type(number) == "number" and number == number and math.abs(number) < math.huge,
			"Finite mesh channel required"
		)
	end
	return Vector3.new(value[1], value[2], value[3])
end

local function indices(value, count)
	assert(type(value) == "table" and #value == 3, "Triangle corner triple required")
	for _, index in value do
		assert(
			type(index) == "number" and index % 1 == 0 and index >= 1 and index <= count,
			"Mesh corner index outside channel"
		)
	end
end

local function validate(data, key)
	assert(type(data) == "table" and data.key == key, "B green beds neutral geometry key mismatch")
	assert(
		type(data.source_sha256) == "string" and #data.source_sha256 == 64,
		"Source FBX hash required"
	)
	assert(
		type(data.positions) == "table" and #data.positions > 0 and #data.positions <= 500,
		"Bounded vertex channel required"
	)
	assert(
		type(data.triangles) == "table" and #data.triangles > 0 and #data.triangles <= 500,
		"Bounded triangle channel required"
	)
	assert(
		type(data.uvs) == "table" and #data.uvs > 0 and #data.uvs <= 1500,
		"Bounded UV channel required"
	)
	assert(
		type(data.normals) == "table" and #data.normals > 0 and #data.normals <= 1500,
		"Bounded normal channel required"
	)
	assert(
		#data.triangle_uvs == #data.triangles and #data.triangle_normals == #data.triangles,
		"Mesh corner channel count mismatch"
	)
	assert((vector(data.bounds.size) - SIZES[key]).Magnitude < 0.0001, "Neutral mesh size mismatch")
	assert(
		data.texture_uri == "rbxassetid://95855894892409",
		"B green beds palette binding mismatch"
	)
end

local function decorate(part, key, size, texture, sourceHash, sourceName, triangleCount)
	part.Name = sourceName
	part:SetAttribute("BGreenBedsOwner", "corn_B_green_beds_v1")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = true
	part.DoubleSided = true
	part.Transparency = 0
	part.Reflectance = 0
	part.Material = Enum.Material.Plastic
	part.Color = Color3.new(1, 1, 1)
	part.TextureID = texture
	part.CFrame = CFrame.identity
	part.PivotOffset = CFrame.identity
	part.Size = size
	part:SetAttribute("BGreenBedGeometryOwned", true)
	part:SetAttribute("BGreenBedGeometryKey", key)
	part:SetAttribute("BGreenBedSourceSHA256", sourceHash)
	part:SetAttribute("BGreenBedSourceTriangles", triangleCount)
	return part
end

local function neutralTemplate(data, key)
	validate(data, key)
	local editable = nil
	local temporary = nil
	local baked = nil
	local ok, result = pcall(function()
		editable = assert(
			AssetService:CreateEditableMesh(),
			"B green beds EditableMesh preparation budget unavailable"
		)
		local vertices, uvs, normals = {}, {}, {}
		local operations = 0
		local function batch()
			operations += 1
			if operations >= BATCH then
				operations = 0
				task.wait()
			end
		end
		for i, value in data.positions do
			vertices[i] = editable:AddVertex(vector(value))
			batch()
		end
		for i, value in data.uvs do
			assert(type(value) == "table" and #value == 2, "Mesh UV pair required")
			for _, number in value do
				assert(
					type(number) == "number" and number == number and math.abs(number) < math.huge,
					"Finite mesh UV required"
				)
			end
			uvs[i] = editable:AddUV(Vector2.new(value[1], value[2]))
			batch()
		end
		for i, value in data.normals do
			normals[i] = editable:AddNormal(vector(value))
			batch()
		end
		for i, triangle in data.triangles do
			indices(triangle, #vertices)
			local uv, normal = data.triangle_uvs[i], data.triangle_normals[i]
			indices(uv, #uvs)
			indices(normal, #normals)
			local face = editable:AddTriangle(
				vertices[triangle[1]],
				vertices[triangle[2]],
				vertices[triangle[3]]
			)
			batch()
			editable:SetFaceUVs(face, { uvs[uv[1]], uvs[uv[2]], uvs[uv[3]] })
			batch()
			editable:SetFaceNormals(
				face,
				{ normals[normal[1]], normals[normal[2]], normals[normal[3]] }
			)
			batch()
		end
		-- Object-backed EditableMesh content does not cast native shadows. The
		-- published template is always the opaque session static bake below.
		temporary = assert(
			AssetService:CreateMeshPartAsync(Content.fromObject(editable), OPTIONS),
			"B green beds temporary mesh unavailable"
		)
		local status, content = AssetService:CreateDataModelContentAsync(temporary.MeshContent)
		assert(
			status == Enum.CreateContentResult.Success
				and content.SourceType == Enum.ContentSourceType.Opaque,
			"B green beds static geometry bake failed: " .. tostring(status)
		)
		baked = assert(
			AssetService:CreateMeshPartAsync(content, OPTIONS),
			"B green beds static MeshPart unavailable"
		)
		assert(
			baked.MeshContent.SourceType == Enum.ContentSourceType.Opaque,
			"B green beds geometry remained editable"
		)
		assert(
			(baked.MeshSize - SIZES[key]).Magnitude < 0.001,
			"B green beds static mesh bounds changed"
		)
		return decorate(
			baked,
			key,
			SIZES[key],
			data.texture_uri,
			data.source_sha256,
			data.name,
			#data.triangles
		)
	end)
	if temporary then
		temporary:Destroy()
	end
	if editable then
		editable:Destroy()
	end
	if not ok then
		if baked then
			baked:Destroy()
		end
		error("B green beds " .. key .. " template failed: " .. tostring(result), 0)
	end
	return result
end

local function validCache(cache)
	for _, key in KEYS do
		local part = cache[key]
		assert(
			part and part:IsA("MeshPart") and part.Parent == nil,
			"B green beds cached template was externally moved or removed"
		)
		assert(
			part:GetAttribute("BGreenBedGeometryOwned") == true
				and part:GetAttribute("BGreenBedGeometryKey") == key,
			"B green beds cached template ownership changed"
		)
	end
end

function Geometry.BuildTemplates()
	while building do
		task.wait()
	end
	if templates then
		validCache(templates)
		return table.freeze(table.clone(templates))
	end
	building = true
	local created = {}
	local ok, problem = pcall(function()
		local dataFolder = assert(
			script.Parent:FindFirstChild("GreenBedGeometryData"),
			"Map B green beds Geometry beside its Data folder"
		)
		for _, key in KEYS do
			local source =
				assert(dataFolder:FindFirstChild(key), "B green beds neutral data missing: " .. key)
			assert(source:IsA("ModuleScript"), "B green beds neutral data must be a ModuleScript")
			created[key] = neutralTemplate(require(source), key)
		end
		validCache(created)
	end)
	building = false
	if not ok then
		for _, part in created do
			part:Destroy()
		end
		error(
			"B green beds templates unavailable; cache remains empty and a later call can retry: "
				.. tostring(problem),
			0
		)
	end
	templates = created
	return table.freeze(table.clone(created))
end

-- CFrame denotes the centered MeshPart. For bottom placement, add Size.Y / 2.
-- Clones remain unparented until the caller publishes a complete test layout.
function Geometry.Clone(key, frame)
	assert(type(key) == "string" and SIZES[key], "Unknown B green beds geometry key")
	assert(typeof(frame) == "CFrame", "B green beds clone CFrame required")
	for _, number in { frame:GetComponents() } do
		assert(
			number == number and math.abs(number) < math.huge,
			"Finite B green beds CFrame required"
		)
	end
	local cache = Geometry.BuildTemplates()
	local clone = assert(cache[key]:Clone(), "B green beds mesh clone unavailable")
	clone.CFrame = frame
	return clone
end

function Geometry.GetSizes()
	return table.clone(SIZES)
end

function Geometry.DestroyCache()
	while building do
		task.wait()
	end
	if templates then
		for _, part in templates do
			part:Destroy()
		end
		templates = nil
	end
end

return table.freeze(Geometry)
