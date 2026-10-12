-- Neutral-data builder fixture with an API-shaped mock; not an engine/GPU test.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local r = require("@lune/roblox")
local builderSource = fs.readFile("scripts/build-farm-editable-mesh.luau")
local allocations, yields, last, failKind = 0, 0, nil, nil
local function newMesh()
	allocations += 1
	local mesh = {
		vertices = {},
		uvs = {},
		normals = {},
		colors = {},
		faces = {},
		faceUvs = {},
		faceNormals = {},
		destroyed = false,
	}
	local vertexAt, uvAt, normalAt, colorAt, faceAt = 0, 0, 0, 0, 0
	function mesh:AddVertex(value)
		vertexAt += 1
		if failKind == "vertex" and vertexAt == 17 then
			error("Injected AddVertex failure")
		end
		local id = 1000 + vertexAt * 7
		self.vertices[id] = value
		return id
	end
	function mesh:AddUV(value)
		uvAt += 1
		local id = 2000 + uvAt * 11
		self.uvs[id] = value
		return id
	end
	function mesh:AddNormal(value)
		normalAt += 1
		local id = 3000 + normalAt * 13
		self.normals[id] = value
		return id
	end
	function mesh:AddColor(value, alpha)
		colorAt += 1
		local id = 4000 + colorAt * 17
		self.colors[id] = { value, alpha }
		return id
	end
	function mesh:AddTriangle(a, b, c)
		faceAt += 1
		if failKind == "triangle" and faceAt == 31 then
			error("Injected AddTriangle failure")
		end
		local id = 5000 + faceAt * 19
		self.faces[id] = { a, b, c }
		return id
	end
	function mesh:SetFaceUVs(id, values)
		self.faceUvs[id] = values
	end
	function mesh:SetFaceNormals(id, values)
		self.faceNormals[id] = values
	end
	function mesh:SetFaceColors(id, values)
		self.faceColors = self.faceColors or {}
		self.faceColors[id] = values
	end
	function mesh:Destroy()
		self.destroyed = true
	end
	last = mesh
	return mesh
end
local gameProxy = {
	GetService = function(_, name)
		assert(name == "AssetService")
		return {
			CreateEditableMesh = function()
				return newMesh()
			end,
		}
	end,
}
local chunk = assert(loadstring(builderSource))
setfenv(
	chunk,
	setmetatable(
		{
			game = gameProxy,
			Vector3 = r.Vector3,
			Vector2 = r.Vector2,
			Color3 = r.Color3,
			task = {
				wait = function()
					yields += 1
				end,
			},
		},
		{ __index = getfenv() }
	)
)
local build = chunk()
local function nearVector(a, b)
	assert((a - b).Magnitude < 0.00015, "Float32 geometry differed")
end
local assets =
	{ "SM_Bld_Barn_03", "SM_Prop_Truck_Rusted_01", "SM_Prop_Tyre_01", "SM_Prop_Rubbish_Pile_05" }
local totalVertices, totalFaces, totalMeshes = 0, 0, 0
for _, name in assets do
	local asset = serde.decode("json", fs.readFile("assets/farm/neutral/" .. name .. ".json"))
	for _, data in asset.meshes do
		local beforeYield = yields
		local mesh, center, bounds = build(data, 500)
		assert(mesh == last and not mesh.destroyed and bounds.SourceName == data.name)
		nearVector(center, r.Vector3.new(table.unpack(data.world_bounds.center)))
		nearVector(bounds.Size, r.Vector3.new(table.unpack(data.world_bounds.size)))
		for i, position in data.positions do
			local id = 1000 + i * 7
			nearVector(mesh.vertices[id] + center, r.Vector3.new(table.unpack(position)))
		end
		for i, triangle in data.triangles do
			local id = 5000 + i * 19
			for corner, vertex in triangle do
				assert(mesh.faces[id][corner] == 1000 + vertex * 7, "Stable vertex ID mapping lost")
				local uvId = mesh.faceUvs[id][corner]
				local expected = data.uvs_roblox_flip_v[data.triangle_uvs[i][corner]]
				assert(
					(mesh.uvs[uvId] - r.Vector2.new(expected[1], expected[2])).Magnitude < 0.000001,
					"Corner UV seam lost"
				)
				local normalId = mesh.faceNormals[id][corner]
				nearVector(
					mesh.normals[normalId],
					r.Vector3.new(table.unpack(data.normals[data.triangle_normals[i][corner]]))
				)
			end
		end
		assert(yields > beforeYield, "Large mesh construction did not yield")
		totalVertices += #data.positions
		totalFaces += #data.triangles
		totalMeshes += 1
	end
end
assert(totalMeshes == 10 and totalFaces == 16226)
print(
	"PASS: API-shaped mock builds 10 original meshes/16226 triangles; center offsets restore positions, stable IDs retain every UV/normal corner, 500-operation yielding"
)
local tyre = serde.decode("json", fs.readFile("assets/farm/neutral/SM_Prop_Tyre_01.json")).meshes[1]
local before = allocations
local invalid = serde.decode("json", serde.encode("json", tyre))
invalid.triangles[1][1] = #invalid.positions + 1
assert(not pcall(build, invalid))
assert(allocations == before, "Invalid triangle allocated a mesh")
for _, kind in { "vertex", "triangle" } do
	failKind = kind
	assert(not pcall(build, tyre))
	assert(last.destroyed, "Failed construction leaked EditableMesh")
end
failKind = nil
print(
	"PASS: invalid index refuses before allocation; vertex/triangle setter errors destroy incomplete mesh; no upload/Workspace calls"
)
