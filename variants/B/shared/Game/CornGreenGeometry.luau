--!strict
-- Three authored FBX shapes, baked once to static session meshes. No world writes.
local AssetService = game:GetService("AssetService")
local Geometry = {}
local KEYS = { Var01 = true, Var02 = true, Var03 = true }
local OPTIONS =
	{ CollisionFidelity = Enum.CollisionFidelity.Box, RenderFidelity = Enum.RenderFidelity.Precise }
local descriptions = {}
local function vector(value)
	assert(type(value) == "table" and #value == 3, "Corn Vector3 triple required")
	for _, n in value do
		assert(
			type(n) == "number" and n == n and math.abs(n) < math.huge,
			"Finite corn channel required"
		)
	end
	return Vector3.new(value[1], value[2], value[3])
end
local function dataFor(key)
	assert(KEYS[key] == true, "Unknown authored green corn shape")
	local folder = assert(
		script.Parent:FindFirstChild("CornGreenGeometryData"),
		"Corn geometry data folder missing"
	)
	local source = assert(folder:FindFirstChild(key), "Corn shape data missing")
	assert(source:IsA("ModuleScript"), "Corn shape data must be a ModuleScript")
	local data = require(source)
	assert(
		type(data) == "table" and data.key == key and data.height_studs == 8,
		"Exact 8-stud corn data required"
	)
	assert(data.texture_uri == "rbxassetid://137803536172445", "Green corn palette required")
	assert(
		type(data.exported_fbx_sha256) == "string"
			and #data.exported_fbx_sha256 == 64
			and data.exported_fbx_sha256:match("^[a-f0-9]+$") ~= nil,
		"Exported FBX hash required"
	)
	assert(#data.positions == 377 and #data.triangles == 510, "Authored corn topology changed")
	assert(
		#data.uvs > 0 and #data.uvs <= 2000 and #data.normals > 0 and #data.normals <= 2000,
		"Bounded corn corner channels required"
	)
	assert(
		#data.triangle_uvs == 510 and #data.triangle_normals == 510,
		"Complete corn corner channels required"
	)
	return data
end
function Geometry.Describe(key)
	if descriptions[key] then
		return descriptions[key]
	end
	local data = dataFor(key)
	local size = vector(data.bounds.size)
	local offset = vector(data.bbox_center_from_root_studs)
	assert(
		size.Y == 8 and size.X > 0 and size.X < 6 and size.Z > 0 and size.Z < 6,
		"Bounded corn dimensions required"
	)
	assert(
		(offset + vector(data.root_offset_studs)).Magnitude < 0.00001
			and math.abs(offset.Y - 4) < 0.00001,
		"Exact corn root anchor required"
	)
	local result = table.freeze({
		size = size,
		rootOffset = offset,
		sourceHash = data.exported_fbx_sha256,
		sourceName = data.name,
		key = key,
	})
	descriptions[key] = result
	return result
end
local function indices(values, count)
	assert(type(values) == "table" and #values == 3, "Corn triangle corner triple required")
	for _, i in values do
		assert(
			type(i) == "number" and i % 1 == 0 and i >= 1 and i <= count,
			"Corn corner index outside channel"
		)
	end
end
function Geometry.Bake(key)
	local data, description = dataFor(key), Geometry.Describe(key)
	local editable, temporary, baked = nil, nil, nil
	local ok, result = pcall(function()
		editable = assert(
			AssetService:CreateEditableMesh(),
			"Corn EditableMesh preparation budget unavailable"
		)
		local vertices, uvs, normals = {}, {}, {}
		local count = 0
		local function batch()
			count += 1
			if count == 128 then
				count = 0
				task.wait()
			end
		end
		for i, value in data.positions do
			vertices[i] = editable:AddVertex(vector(value))
			batch()
		end
		for i, value in data.uvs do
			assert(type(value) == "table" and #value == 2, "Corn UV pair required")
			for _, n in value do
				assert(
					type(n) == "number" and n == n and math.abs(n) < math.huge,
					"Finite corn UV required"
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
		-- FBX colorSet1 is an unconnected authoring mask, not albedo. The source
		-- material uses the green palette alone; applying that mask would blacken it.
		temporary = assert(
			AssetService:CreateMeshPartAsync(Content.fromObject(editable), OPTIONS),
			"Corn temporary mesh unavailable"
		)
		local status, content = AssetService:CreateDataModelContentAsync(temporary.MeshContent)
		assert(
			status == Enum.CreateContentResult.Success
				and content.SourceType == Enum.ContentSourceType.Opaque,
			"Corn static bake failed: " .. tostring(status)
		)
		baked = assert(
			AssetService:CreateMeshPartAsync(content, OPTIONS),
			"Corn static MeshPart unavailable"
		)
		assert(
			baked:IsA("MeshPart")
				and baked.Parent == nil
				and baked.MeshContent.SourceType == Enum.ContentSourceType.Opaque,
			"Corn remained object-backed"
		)
		assert(
			(baked.MeshSize - description.size).Magnitude < 0.001,
			"Authored corn bounds changed during bake"
		)
		assert(
			#baked:GetChildren() == 0
				and #baked:GetTags() == 0
				and next(baked:GetAttributes()) == nil,
			"Unexpected static corn descendants or metadata"
		)
		return baked
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
		error("Authored corn " .. key .. " preparation failed: " .. tostring(result), 0)
	end
	return result, description
end
return table.freeze(Geometry)
