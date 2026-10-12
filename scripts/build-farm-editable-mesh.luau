-- Pure EditableMesh construction from verified neutral FBX data.
-- Never uploads, parents instances, changes Workspace, or reads/writes a place.
return function(data, batchSize)
	assert(
		type(data) == "table" and type(data.positions) == "table" and #data.positions > 0,
		"Verified mesh positions required"
	)
	assert(
		type(data.triangles) == "table" and #data.triangles > 0,
		"Verified mesh triangles required"
	)
	assert(type(data.world_bounds) == "table", "Baked world bounds required")
	local limit = batchSize or 500
	assert(type(limit) == "number" and limit >= 1 and limit % 1 == 0, "Integer batch size required")
	local function vector(v)
		assert(type(v) == "table" and #v == 3, "Vector3 triple required")
		for _, n in v do
			assert(
				type(n) == "number" and n == n and math.abs(n) < math.huge,
				"Finite mesh coordinates required"
			)
		end
		return Vector3.new(v[1], v[2], v[3])
	end
	local low, high = vector(data.world_bounds.min), vector(data.world_bounds.max)
	local center = (low + high) / 2
	local vertexCount, uvCount, normalCount, colorCount =
		#data.positions, #data.uvs_roblox_flip_v, #data.normals, #data.colors
	assert(
		#data.triangle_uvs == #data.triangles
			and #data.triangle_normals == #data.triangles
			and #data.triangle_colors == #data.triangles,
		"Per-corner channel counts differ"
	)
	local function indices(values, size)
		assert(type(values) == "table" and #values == 3, "Triangle index triple required")
		for _, n in values do
			assert(
				type(n) == "number" and n % 1 == 0 and n >= 1 and n <= size,
				"Out-of-range mesh index"
			)
		end
	end
	for i, triangle in data.triangles do
		indices(triangle, vertexCount)
		indices(data.triangle_uvs[i], uvCount)
		if normalCount > 0 then
			indices(data.triangle_normals[i], normalCount)
		end
		if colorCount > 0 then
			indices(data.triangle_colors[i], colorCount)
		end
	end
	local mesh = assert(
		game:GetService("AssetService"):CreateEditableMesh(),
		"EditableMesh memory budget unavailable"
	)
	local operations = 0
	local function tick()
		operations += 1
		if operations >= limit then
			operations = 0
			task.wait()
		end
	end
	local ok, problem = pcall(function()
		local vertices, uvs, normals, colors = {}, {}, {}, {}
		for i, value in data.positions do
			vertices[i] = mesh:AddVertex(vector(value) - center)
			tick()
		end
		for i, value in data.uvs_roblox_flip_v do
			assert(
				type(value) == "table"
					and #value == 2
					and value[1] == value[1]
					and value[2] == value[2],
				"Finite UV pair required"
			)
			uvs[i] = mesh:AddUV(Vector2.new(value[1], value[2]))
			tick()
		end
		for i, value in data.normals do
			normals[i] = mesh:AddNormal(vector(value))
			tick()
		end
		for i, value in data.colors do
			assert(type(value) == "table" and #value == 4, "RGBA color required")
			colors[i] = mesh:AddColor(Color3.new(value[1], value[2], value[3]), value[4])
			tick()
		end
		for i, triangle in data.triangles do
			local face = mesh:AddTriangle(
				vertices[triangle[1]],
				vertices[triangle[2]],
				vertices[triangle[3]]
			)
			tick()
			local uv = data.triangle_uvs[i]
			mesh:SetFaceUVs(face, { uvs[uv[1]], uvs[uv[2]], uvs[uv[3]] })
			tick()
			if normalCount > 0 then
				local n = data.triangle_normals[i]
				mesh:SetFaceNormals(face, { normals[n[1]], normals[n[2]], normals[n[3]] })
				tick()
			end
			if colorCount > 0 then
				local c = data.triangle_colors[i]
				mesh:SetFaceColors(face, { colors[c[1]], colors[c[2]], colors[c[3]] })
				tick()
			end
		end
	end)
	if not ok then
		mesh:Destroy()
		error("Neutral mesh construction failed: " .. tostring(problem))
	end
	-- Center and Size remain raw cm. Parent applies one uniform scale to size and center,
	-- then places MeshPart at modelFrame * CFrame.new(center * scale).
	return mesh,
		center,
		{
			Min = low,
			Max = high,
			Size = high - low,
			SourceName = data.name,
			VertexCount = vertexCount,
			TriangleCount = #data.triangles,
		}
end
