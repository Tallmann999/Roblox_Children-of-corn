-- READ ONLY. Returns callable(options); no Source, Instance, Camera, settings or file writes.
-- Baseline file supplies only class/property names and service scope, never expected values.
return function(options)
	options = options or {}
	local run = game:GetService("RunService")
	assert(run:IsStudio() and not run:IsRunning(), "Stopped Studio Edit required")
	assert(game.Name == "Children_of_corn_B.rbxl", "B filename required")
	local map = assert(workspace:FindFirstChild("CornMap"), "CornMap required")
	assert(map:GetAttribute("corn_project_id") == "children_of_corn" and map:GetAttribute("HarvestArtVariant") == "B", "B identity required")
	assert(map.Ground.Size == Vector3.new(630, 2, 630) and map.FieldZone.Size == Vector3.new(630, 10, 630), "Field dimensions changed")
	local http = game:GetService("HttpService")
	local encoding = game:GetService("EncodingService")
	local classProperties = http:JSONDecode([==[__PROPERTIES__]==])
	local rootClasses = http:JSONDecode([==[__ROOTS__]==])
	local function hash(value)
		return (encoding:ComputeStringHash(value, Enum.HashAlgorithm.Sha256):gsub(".", function(c) return string.format("%02x", c:byte()) end))
	end
	local function identity(item)
		if not item then return "nil" end
		if item == game then return "DataModel" end
		local ok, value = pcall(function() return item:GetDebugId(0) end)
		if ok then return tostring(value) end
		ok, value = pcall(function() return item.UniqueId end)
		assert(ok, "Stable read-only Instance identity unavailable: " .. item:GetFullName())
		return tostring(value)
	end
	local function quote(value) return string.format("%q", value) end
	local function num(value)
		if value ~= value then return "nan" end
		if value == math.huge then return "+inf" end
		if value == -math.huge then return "-inf" end
		return string.format("%.17g", value)
	end
	local function nums(...)
		local out = {}
		for _, value in {...} do out[#out + 1] = num(value) end
		return table.concat(out, ",")
	end
	local encode
	encode = function(value)
		local kind = typeof(value)
		if kind == "nil" then return "nil" end
		if kind == "string" then return "string:" .. quote(value) end
		if kind == "number" then return "number:" .. num(value) end
		if kind == "boolean" then return tostring(value) end
		if kind == "Instance" then return "Instance:" .. identity(value) end
		if kind == "Vector3" then return kind .. ":" .. nums(value.X, value.Y, value.Z) end
		if kind == "Vector2" then return kind .. ":" .. nums(value.X, value.Y) end
		if kind == "Color3" then return kind .. ":" .. nums(value.R, value.G, value.B) end
		if kind == "CFrame" then return kind .. ":" .. nums(value:GetComponents()) end
		if kind == "UDim" then return kind .. ":" .. nums(value.Scale, value.Offset) end
		if kind == "UDim2" then return kind .. ":" .. nums(value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset) end
		if kind == "BrickColor" then return kind .. ":" .. tostring(value.Number) end
		if kind == "Rect" then return kind .. ":" .. encode(value.Min) .. ":" .. encode(value.Max) end
		if kind == "NumberRange" then return kind .. ":" .. nums(value.Min, value.Max) end
		if kind == "NumberSequence" or kind == "ColorSequence" then
			local out = {}
			for _, keypoint in value.Keypoints do
				out[#out + 1] = num(keypoint.Time) .. ":" .. encode(keypoint.Value) .. (if kind == "NumberSequence" then ":" .. num(keypoint.Envelope) else "")
			end
			return kind .. ":" .. table.concat(out, "|")
		end
		if kind == "PhysicalProperties" then return kind .. ":" .. nums(value.Density, value.Friction, value.Elasticity, value.FrictionWeight, value.ElasticityWeight) end
		if kind == "Font" then return kind .. ":" .. value.Family .. ":" .. tostring(value.Weight) .. ":" .. tostring(value.Style) end
		if kind == "table" then
			local keys, out = {}, {}
			for key in value do keys[#keys + 1] = key end
			table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
			for _, key in keys do out[#out + 1] = encode(key) .. "=" .. encode(value[key]) end
			return "table:{" .. table.concat(out, ";") .. "}"
		end
		return kind .. ":" .. tostring(value)
	end
	-- Serialized metadata is represented by decoded public attrs/tags/identity instead.
	-- These hidden, security-protected or dynamic names are not queried.
	local skip = { AttributesSerialize=true, Tags=true, Name=true, UniqueId=true, HistoryId=true, Source=true,
		SerializedOverrides=true, Capabilities=true, DefinesCapabilities=true, ScriptGuid=true,
		SmoothGrid=true, PhysicsGrid=true, VoxelGridAssetContentMap=true, MaterialColors=true,
		CollisionGroupData=true, ModelMeshData=true, MeshData=true, PhysicalConfigData=true,
		DistributedGameTime=true, CurrentCamera=true, WorldPivotData=true }
	local aliases = { Color3uint8="Color", size="Size", heat_xml="Heat", size_xml="Size", MaterialVariantSerialized="MaterialVariant", SignalBehavior2="SignalBehavior" }
	local extra = {
		BasePart={"Archivable","CFrame","Size","Color","Material","MaterialVariant","Anchored","CanCollide","CanTouch","CanQuery","CastShadow","CollisionGroup","CustomPhysicalProperties","Massless","RootPriority","PivotOffset"},
		MeshPart={"MeshId","TextureID","MeshContent","TextureContent","MeshSize","RenderFidelity","CollisionFidelity","DoubleSided"},
		Model={"WorldPivot","PrimaryPart","ModelStreamingMode"},
		Attachment={"CFrame","Axis","SecondaryAxis","Visible"},
		Light={"Brightness","Range","Color","Enabled","Shadows"},
		LuaSourceContainer={"Archivable"},
		BaseScript={"Disabled","RunContext"},
		Lighting={"ClockTime","LightingStyle","PrioritizeLightingQuality","GlobalShadows"},
		Terrain={"Decoration","WaterColor","WaterReflectance","WaterTransparency","WaterWaveSize","WaterWaveSpeed","GrassLength"},
	}
	local items, includedRoots, skippedRoots = {}, {}, {}
	for _, root in game:GetChildren() do
		if rootClasses[root.ClassName] then
			includedRoots[#includedRoots + 1] = root.ClassName .. ":" .. root.Name
			items[#items + 1] = root
			for _, item in root:GetDescendants() do items[#items + 1] = item end
		else skippedRoots[#skippedRoots + 1] = root.ClassName .. ":" .. root.Name end
	end
	table.sort(includedRoots); table.sort(skippedRoots)
	local result = { owner="corn_rojo_B_readonly_snapshot_v1", scope="Persistent saved-service classes; all current descendants", gameName=game.Name,
		includedRoots=includedRoots, skippedRoots=skippedRoots, instances=#items, nodes={}, sources={}, classes={}, unreadable={}, unknownClasses={},
		propertyInventorySha256=hash(http:JSONEncode(classProperties)), totalReadableProperties=0,
		terrain={ rawGridRuntimeAudited=false, explanation="Hidden raw voxel and mesh binary data cannot be read through normal public properties; disk-byte SHA and Rojo patch scope are independent evidence.", materialPalette={} } }
	local allRows, nonSourceRows, sourceRows, worldRows = {}, {}, {}, {}
	for _, item in items do
		local id, class = identity(item), item.ClassName
		assert(not result.nodes[id], "Duplicate debug identity")
		result.classes[class] = (result.classes[class] or 0) + 1
		local path = item:GetFullName():gsub("%.", "/")
		local props, propertyNames, failures = {}, {Archivable=true}, {}
		if not classProperties[class] then result.unknownClasses[class] = true end
		for _, key in classProperties[class] or {} do if not skip[key] then propertyNames[aliases[key] or key] = true end end
		for base, names in extra do if item:IsA(base) then for _, key in names do propertyNames[key] = true end end end
		for key in propertyNames do
			local ok, value = pcall(function() return item[key] end)
			if ok then props[key] = encode(value); result.totalReadableProperties += 1
			else failures[#failures + 1] = key end
		end
		table.sort(failures)
		if #failures > 0 then result.unreadable[class] = failures end
		local tags = item:GetTags(); table.sort(tags)
		local attrs = item:GetAttributes()
		local row = { id=id, path=path, class=class, name=item.Name, parent=identity(item.Parent), attributesSha256=hash(encode(attrs)), tagsSha256=hash(encode(tags)), propertiesSha256=hash(encode(props)), properties=#(classProperties[class] or {}), unreadable=table.concat(failures, ",") }
		local signature = id .. "|" .. class .. "|" .. quote(item.Name) .. "|" .. row.parent .. "|" .. row.attributesSha256 .. "|" .. row.tagsSha256 .. "|" .. row.propertiesSha256
		row.nonSourceSha256 = hash(signature)
		nonSourceRows[#nonSourceRows + 1] = row.nonSourceSha256
		if item:IsA("LuaSourceContainer") then
			row.sourceSha256 = hash(item.Source:gsub("\r\n", "\n"))
			row.rawSourceSha256 = hash(item.Source)
			assert(not result.sources[path], "Ambiguous Source path")
			result.sources[path] = { id=id, class=class, sha256=row.sourceSha256, rawSha256=row.rawSourceSha256 }
			sourceRows[#sourceRows + 1] = path .. "|" .. id .. "|" .. row.sourceSha256 .. "|" .. row.rawSourceSha256
			signature ..= "|" .. row.sourceSha256 .. "|" .. row.rawSourceSha256
		end
		row.sha256 = hash(signature)
		allRows[#allRows + 1] = row.sha256
		if item:IsDescendantOf(workspace) or item == workspace or item:IsDescendantOf(game.Lighting) or item == game.Lighting then worldRows[#worldRows + 1] = row.sha256 end
		result.nodes[id] = row
	end
	for _, material in Enum.Material:GetEnumItems() do
		local ok, value = pcall(function() return workspace.Terrain:GetMaterialColor(material) end)
		if ok then result.terrain.materialPalette[material.Name] = encode(value) end
	end
	result.terrain.paletteSha256 = hash(encode(result.terrain.materialPalette))
	local function digest(rows) table.sort(rows); return hash(table.concat(rows, "\n")) end
	result.allSha256 = digest(allRows)
	result.nonSourceSha256 = digest(nonSourceRows)
	result.sourceSha256 = digest(sourceRows)
	result.worldLightingSha256 = digest(worldRows)
	result.sourceCount = #sourceRows
	assert(result.sourceCount == 157, "Expected 157 current persistent B Sources")
	result.editorDocuments = {}
	for _, document in game:GetService("ScriptEditorService"):GetScriptDocuments() do
		local script = document:GetScript()
		if script and script:IsDescendantOf(game) then
			result.editorDocuments[#result.editorDocuments + 1] = { path=script:GetFullName():gsub("%.", "/"), textSha256=hash(document:GetText():gsub("\r\n", "\n")), sourceSha256=hash(script.Source:gsub("\r\n", "\n")) }
		end
	end
	if options.storeKey then
		assert(type(options.storeKey) == "string" and options.storeKey:sub(1, 17) == "__CornRojoBLive_v1", "Owned store key required")
		assert(_G[options.storeKey] == nil, "Owned store already occupied")
		_G[options.storeKey] = result
	end
	if options.compact then
		local summary = table.clone(result)
		summary.nodes = nil
		return summary
	end
	return result
end
