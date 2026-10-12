--!strict
-- Shared peer-local construction/restoration; never uploads or authors placements.
local KEYS =
	{ "SM_Bld_Barn_03", "SM_Prop_Truck_Rusted_01", "SM_Prop_Tyre_01", "SM_Prop_Rubbish_Pile_05" }
local DataFolder = script.Parent:WaitForChild("FarmGeometryData")
local Catalog = {}
local total = 0
for _, key in KEYS do
	local data = require(DataFolder:WaitForChild(key))
	assert(
		type(data) == "table"
			and data.index_base == 1
			and type(data.meshes) == "table"
			and #data.meshes == (if key == "SM_Bld_Barn_03" then 7 else 1),
		"Unknown neutral farm catalog: " .. key
	)
	Catalog[key] = data
	total += #data.meshes
end
assert(total == 10, "Expected ten verified original farm meshes")
local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < 10000000
end
local function validate(data: any)
	assert(
		type(data) == "table" and type(data.world_bounds) == "table",
		"Neutral mesh/bounds required"
	)
	local operations = 0
	local function tick()
		operations += 1
		if operations >= 500 then
			operations = 0
			task.wait()
		end
	end
	local function tuples(values: any, width: number, limit: number)
		assert(type(values) == "table" and #values <= limit, "Invalid/oversized mesh channel")
		for _, tuple in values do
			assert(type(tuple) == "table" and #tuple == width, "Mesh channel tuple width mismatch")
			for _, value in tuple do
				assert(finite(value), "Nonfinite mesh channel coordinate")
			end
			tick()
		end
	end
	tuples(data.positions, 3, 60000)
	assert(#data.positions > 0, "Mesh vertices required")
	tuples(data.uvs_roblox_flip_v, 2, 120000)
	assert(#data.uvs_roblox_flip_v > 0, "Mesh UVs required")
	tuples(data.normals, 3, 120000)
	tuples(data.colors, 4, 120000)
	tuples({ data.world_bounds.min, data.world_bounds.max }, 3, 2)
	local low, high = data.world_bounds.min, data.world_bounds.max
	for axis = 1, 3 do
		assert(high[axis] > low[axis], "Positive mesh bounds required")
	end
	assert(
		type(data.triangles) == "table" and #data.triangles > 0 and #data.triangles <= 20000,
		"Triangle count outside supported limits"
	)
	local function corner(indices: any, limit: number)
		assert(type(indices) == "table" and #indices == 3, "Triangle corner triple required")
		for _, index in indices do
			assert(
				finite(index) and index % 1 == 0 and index >= 1 and index <= limit,
				"Invalid triangle/corner index"
			)
		end
	end
	for _, name in { "triangle_uvs", "triangle_normals", "triangle_colors" } do
		assert(
			type(data[name]) == "table" and #data[name] == #data.triangles,
			"Triangle channel count mismatch"
		)
	end
	for index, triangle in data.triangles do
		corner(triangle, #data.positions)
		corner(data.triangle_uvs[index], #data.uvs_roblox_flip_v)
		if #data.normals > 0 then
			corner(data.triangle_normals[index], #data.normals)
		end
		if #data.colors > 0 then
			corner(data.triangle_colors[index], #data.colors)
		end
		tick()
	end
end

-- Pure EditableMesh construction from verified neutral FBX data.
-- Never uploads, parents instances, changes Workspace, or reads/writes a place.
local function rawBuild(data, batchSize)
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

local function build(data: any, batchSize: number?)
	validate(data)
	return rawBuild(data, batchSize)
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
local PROJECT = "children_of_corn"
local Runtime = {}
Runtime.__index = Runtime
local function assetKeyForName(name: string): string?
	if table.find({ "HouseWest", "HouseEast", "HouseNorthWest" }, name) then
		return KEYS[1]
	elseif name == "RustedTruck" then
		return KEYS[2]
	elseif name:match("^Tyre_%d+$") then
		return KEYS[3]
	elseif name:match("^RubbishPile_%d+$") then
		return KEYS[4]
	end
	return nil
end
local function modelKey(model: Instance, source: boolean): string?
	local key = model:GetAttribute("AssetKey")
	if type(key) ~= "string" or not Catalog[key] then
		return nil
	end
	if source then
		return if model.Name == key then key else nil
	end
	return if assetKeyForName(model.Name) == key then key else nil
end
local function contentObject(part: MeshPart): any
	local content = part.MeshContent
	assert(part.MeshId == "", "Owned farm mesh has manual URI; preserving it: " .. part.Name)
	assert(
		content.SourceType == Enum.ContentSourceType.None
			or content.SourceType == Enum.ContentSourceType.Object,
		"Unsupported owned farm content type"
	)
	return if content.SourceType == Enum.ContentSourceType.Object then content.Object else nil
end
function Runtime:_collect(): ({ any }, number)
	local world = game:GetService("Workspace")
	local map = world:FindFirstChild("CornMap")
	assert(
		map
			and map:IsA("Model")
			and map:GetAttribute("corn_project_id") == PROJECT
			and not world:FindFirstChild("Asmr_Base")
			and not world:FindFirstChild("ASMR_Models"),
		"Farm geometry requires Children_of_corn"
	)
	local props = map:FindFirstChild("Props")
	assert(props and props:IsA("Folder"), "CornMap Props missing")
	local roots = { { Root = props, Source = false } }
	if self._scope == "server" then
		local source = game:GetService("ServerStorage"):FindFirstChild("CornFarmAssets")
		if source then
			assert(
				source:IsA("Folder")
					and source:GetAttribute("CornFarmAssetsOwned") == true
					and source:GetAttribute("corn_project_id") == PROJECT,
				"Foreign CornFarmAssets was preserved"
			)
			table.insert(roots, { Root = source, Source = true })
		end
	end
	local targets, pending = {}, 0
	for _, root in roots do
		for _, model in root.Root:GetChildren() do
			local owned = model:GetAttribute("CornFarmAssetOwned") == true
			if not owned then
				local pendingOwner = false
				for _, item in model:GetDescendants() do
					if item:GetAttribute("CornFarmMeshOwned") == true then
						if
							self._scope == "client"
							and model:IsA("Model")
							and assetKeyForName(model.Name)
						then
							pendingOwner = true
						else
							error("Owned farm mesh outside recognized model")
						end
					end
				end
				if pendingOwner then
					pending += 1
				end
				continue
			end
			assert(model:IsA("Model"), "Malformed owned farm model")
			local project, declaredKey =
				model:GetAttribute("corn_project_id"), model:GetAttribute("AssetKey")
			if
				self._scope == "client"
				and (project == nil or declaredKey == nil)
				and assetKeyForName(model.Name)
			then
				pending += 1
				continue
			end
			assert(project == PROJECT, "Malformed owned farm model")
			local key = modelKey(model, root.Source)
			assert(key, "Unknown owned farm model/key; preserving metadata")
			local indices, modelTargets, incomplete = {}, {}, false
			for _, part in model:GetDescendants() do
				if part:GetAttribute("CornFarmMeshOwned") ~= true then
					continue
				end
				assert(
					part:IsA("MeshPart") and part.Parent == model,
					"Malformed/outside owned farm MeshPart"
				)
				local partProject, partKey, index =
					part:GetAttribute("corn_project_id"),
					part:GetAttribute("AssetKey"),
					part:GetAttribute("MeshIndex")
				if
					self._scope == "client"
					and (partProject == nil or partKey == nil or index == nil)
				then
					incomplete = true
					continue
				end
				assert(
					partProject == PROJECT and partKey == key,
					"Malformed/outside owned farm MeshPart"
				)
				assert(
					finite(index)
						and index % 1 == 0
						and index >= 1
						and index <= #Catalog[key].meshes
						and not indices[index],
					"Invalid/duplicate owned farm MeshIndex"
				)
				indices[index] = true
				contentObject(part)
				assert(
					finite(part.Size.X)
						and finite(part.Size.Y)
						and finite(part.Size.Z)
						and part.Size.X > 0
						and part.Size.Y > 0
						and part.Size.Z > 0,
					"Invalid authored mesh Size"
				)
				assert(
					finite(part.CFrame.Position.X)
						and finite(part.CFrame.Position.Y)
						and finite(part.CFrame.Position.Z),
					"Invalid authored mesh CFrame"
				)
				table.insert(modelTargets, {
					Part = part,
					Model = model,
					Root = root.Root,
					Map = map,
					Source = root.Source,
					AssetKey = key,
					MeshIndex = index,
					Key = key .. ":" .. tostring(index),
				})
			end
			for index = 1, #Catalog[key].meshes do
				if not indices[index] then
					incomplete = true
				end
			end
			if incomplete then
				assert(self._scope == "client", "Owned farm asset is incomplete: " .. model.Name)
				pending += 1
			else
				for _, target in modelTargets do
					table.insert(targets, target)
				end
			end
		end
	end
	return targets, pending
end
function Runtime:_validateTarget(target: any)
	local world = game:GetService("Workspace")
	local map, root = target.Map, target.Root
	assert(
		map.Parent == world
			and world:FindFirstChild("CornMap") == map
			and map:GetAttribute("corn_project_id") == PROJECT
			and not world:FindFirstChild("Asmr_Base")
			and not world:FindFirstChild("ASMR_Models"),
		"Farm map binding changed during construction"
	)
	if target.Source then
		local storage = game:GetService("ServerStorage")
		assert(
			root.Parent == storage
				and storage:FindFirstChild("CornFarmAssets") == root
				and root:GetAttribute("CornFarmAssetsOwned") == true
				and root:GetAttribute("corn_project_id") == PROJECT,
			"Farm source folder binding changed during construction"
		)
	else
		assert(
			root.Parent == map and map:FindFirstChild("Props") == root,
			"Farm Props binding changed during construction"
		)
	end
	local part, model = target.Part, target.Model
	assert(
		model.Parent == target.Root
			and model:GetAttribute("CornFarmAssetOwned") == true
			and model:GetAttribute("corn_project_id") == PROJECT
			and modelKey(model, target.Source) == target.AssetKey,
		"Farm binding changed during construction"
	)
	assert(
		part.Parent == model
			and part:GetAttribute("CornFarmMeshOwned") == true
			and part:GetAttribute("corn_project_id") == PROJECT
			and part:GetAttribute("AssetKey") == target.AssetKey
			and part:GetAttribute("MeshIndex") == target.MeshIndex,
		"Farm mesh metadata changed during construction"
	)
	contentObject(part)
end
local function dispose(entry: any)
	if entry.Part then
		entry.Part:Destroy()
	end
	if entry.Mesh then
		entry.Mesh:Destroy()
	end
end
local function snapshot(part: MeshPart): any
	local values = {}
	for _, property in PROPERTIES do
		values[property] = (part :: any)[property]
	end
	local clone = assert(part:Clone(), "Owned farm mesh is not Archivable; cannot protect rollback")
	clone.Parent = nil
	return { Part = part, Values = values, Clone = clone }
end
local function restoreProperties(saved: any)
	-- TextureContent is restored after TextureID so object-backed textures survive too.
	for _, property in PROPERTIES do
		(saved.Part :: any)[property] = saved.Values[property]
	end
end
function Runtime:Ensure(): any
	assert(not self._destroyed, "Farm geometry runtime is destroyed")
	assert(not self._busy, "Farm geometry restoration is already running")
	self._busy = true
	local generation = self._generation
	local created, snapshots, applied = {}, {}, {}
	local report = { targets = 0, built = 0, applied = 0, pending = 0, scope = self._scope }
	local ok, result = pcall(function()
		local targets, pending = self:_collect()
		report.targets = #targets
		report.pending = pending
		local requested = {}
		for _, target in targets do
			local part = target.Part
			local prior = requested[target.Key]
			local collision, render = part.CollisionFidelity, part.RenderFidelity
			if prior then
				assert(
					prior.Collision == collision and prior.Render == render,
					"One farm mesh has incompatible authored fidelity settings"
				)
			else
				requested[target.Key] = { Target = target, Collision = collision, Render = render }
			end
		end
		for key, request in requested do
			local target = request.Target
			local cached = self._cache[key]
			if cached then
				assert(
					cached.Collision == request.Collision and cached.Render == request.Render,
					"Authored fidelity changed; preserving manual settings"
				)
			else
				validate(Catalog[target.AssetKey].meshes[target.MeshIndex])
			end
		end
		local service = game:GetService("AssetService")
		for key, request in requested do
			if self._cache[key] then
				continue
			end
			assert(
				not self._destroyed and self._generation == generation,
				"Farm restoration cancelled"
			)
			local data = Catalog[request.Target.AssetKey].meshes[request.Target.MeshIndex]
			local mesh, center, bounds = rawBuild(data, 500)
			local entry = {
				Mesh = mesh,
				Center = center,
				Bounds = bounds,
				Collision = request.Collision,
				Render = request.Render,
			}
			created[key] = entry
			if self._scope == "client" then
				local fixed = assert(
					service:CreateEditableMeshAsync(Content.fromObject(mesh), { FixedSize = true }),
					"Fixed-size farm EditableMesh memory budget unavailable"
				)
				entry.Mesh = fixed
				mesh:Destroy()
				mesh = fixed
				assert(fixed.FixedSize, "Client farm cache requires fixed-size geometry")
				assert(
					not self._destroyed and self._generation == generation,
					"Farm restoration cancelled"
				)
			end
			entry.Part = assert(
				service:CreateMeshPartAsync(
					Content.fromObject(mesh),
					{ CollisionFidelity = request.Collision, RenderFidelity = request.Render }
				),
				"Canonical farm MeshPart unavailable"
			)
			entry.Part.Parent = nil
			report.built += 1
		end
		assert(not self._destroyed and self._generation == generation, "Farm restoration cancelled")
		for _, target in targets do
			self:_validateTarget(target)
			local entry = self._cache[target.Key] or created[target.Key]
			assert(
				target.Part.CollisionFidelity == entry.Collision
					and target.Part.RenderFidelity == entry.Render,
				"Fidelity changed during construction"
			)
			assert(
				target.Part.FluidFidelity == entry.Part.FluidFidelity,
				"Unsupported authored fluid fidelity was preserved"
			)
			if contentObject(target.Part) ~= entry.Mesh then
				local saved = snapshot(target.Part)
				saved.Entry = entry
				table.insert(snapshots, saved)
			end
		end
		for _, saved in snapshots do
			table.insert(applied, saved)
			saved.Part:ApplyMesh(saved.Entry.Part)
			restoreProperties(saved)
			assert(
				contentObject(saved.Part) == saved.Entry.Mesh,
				"EditableMesh application did not produce current local Object content"
			)
			report.applied += 1
		end
		for key, entry in created do
			self._cache[key] = entry
		end
		for _, saved in snapshots do
			saved.Clone:Destroy()
		end
		return report
	end)
	self._busy = false
	if not ok then
		local rollbackErrors = {}
		for index = #applied, 1, -1 do
			local saved = applied[index]
			local restored, problem = pcall(function()
				saved.Part:ApplyMesh(saved.Clone)
				restoreProperties(saved)
			end)
			if not restored then
				table.insert(rollbackErrors, tostring(problem))
			end
		end
		for _, saved in snapshots do
			saved.Clone:Destroy()
		end
		for _, entry in created do
			dispose(entry)
		end
		error(
			"Farm geometry restoration failed; preserved authored placement: "
				.. tostring(result)
				.. (
					if #rollbackErrors > 0
						then "; rollback errors: " .. table.concat(rollbackErrors, "; ")
						else ""
				)
		)
	end
	self._lastReport = result
	return result
end
function Runtime:Destroy()
	self._destroyed = true
	self._generation += 1
	for _, entry in self._cache do
		dispose(entry)
	end
	self._cache = {}
end
local function newRuntime(scope: string): any
	assert(scope == "server" or scope == "client", "Farm runtime peer scope required")
	return setmetatable(
		{ _scope = scope, _cache = {}, _busy = false, _destroyed = false, _generation = 0 },
		Runtime
	)
end
return setmetatable({
	Build = build,
	Validate = validate,
	newRuntime = newRuntime,
	AssetKeyForName = assetKeyForName,
}, {
	__call = function(_, data, batchSize)
		return build(data, batchSize)
	end,
})
