-- Read-only guard, invoked immediately before installation in the same MCP call.
return function()
	assert(
		game:GetService("RunService"):IsStudio() and not game:GetService("RunService"):IsRunning(),
		"Stopped local C Edit required"
	)
	assert(game.PlaceId == 0 and not workspace:FindFirstChild("CornMap"), "Local C only")
	local http = game:GetService("HttpService")
	local encoding = game:GetService("EncodingService")
	local function hash(value)
		return (
			encoding:ComputeStringHash(value, Enum.HashAlgorithm.Sha256):gsub(".", function(c)
				return string.format("%02x", string.byte(c))
			end)
		)
	end
	local function value(v)
		local kind = typeof(v)
		if kind == "number" then
			return string.format("%.17g", v)
		elseif kind == "string" or kind == "boolean" then
			return http:JSONEncode(v)
		elseif kind == "CFrame" then
			local components = { v:GetComponents() }
			for i, component in components do
				components[i] = string.format("%.17g", component)
			end
			return kind .. ":" .. table.concat(components, ",")
		elseif kind == "Vector3" then
			return kind .. ":" .. value(v.X) .. "," .. value(v.Y) .. "," .. value(v.Z)
		elseif kind == "Color3" then
			return kind .. ":" .. value(v.R) .. "," .. value(v.G) .. "," .. value(v.B)
		end
		return kind .. ":" .. tostring(v)
	end
	local sources, lines = {}, { game.Name, tostring(game.PlaceId), tostring(game.CreatorId) }
	for _, item in game:GetDescendants() do
		if item:IsA("LuaSourceContainer") then
			table.insert(sources, item:GetFullName() .. ":" .. hash(item.Source:gsub("\r\n", "\n")))
		end
	end
	table.sort(sources)
	assert(#sources == 0 or #sources == 9, "Blank or complete C code required")
	if #sources == 0 then
		assert(not workspace:FindFirstChild("CornCTestWorld"), "Existing author C world preserved")
		local allowed = {
			Camera = "Camera",
			Terrain = "Terrain",
			Baseplate = "Part",
			SpawnLocation = "SpawnLocation",
		}
		local seen = {}
		for _, item in workspace:GetChildren() do
			assert(
				allowed[item.Name] == item.ClassName and not seen[item.Name],
				"Fresh Baseplate required; author world preserved"
			)
			seen[item.Name] = true
			for _, child in item:GetDescendants() do
				assert(
					child:IsA("Texture") or child:IsA("Decal"),
					"Fresh Baseplate descendants required"
				)
			end
		end
		assert(
			seen.Baseplate and seen.Terrain and seen.SpawnLocation,
			"Complete fresh Baseplate required"
		)
	else
		assert(
			workspace:FindFirstChild("CornCTestWorld")
				and workspace.CornCTestWorld:GetAttribute("corn_project_id")
					== "children_of_corn_C_test",
			"Owned C required"
		)
	end
	local properties = {
		"CFrame",
		"Size",
		"Anchored",
		"CanCollide",
		"CanTouch",
		"CanQuery",
		"CastShadow",
		"Transparency",
		"Color",
		"Material",
		"Reflectance",
		"Texture",
		"TextureID",
		"Enabled",
		"LightingStyle",
		"ClockTime",
		"Brightness",
		"GlobalShadows",
		"Ambient",
		"OutdoorAmbient",
		"EnvironmentDiffuseScale",
		"EnvironmentSpecularScale",
		"ExposureCompensation",
		"CameraMode",
		"CameraMinZoomDistance",
		"CameraMaxZoomDistance",
		"CharacterWalkSpeed",
		"WaterColor",
		"WaterReflectance",
		"WaterTransparency",
		"WaterWaveSize",
		"WaterWaveSpeed",
	}
	local function record(item)
		if item:IsA("Camera") then
			return
		end
		local prefix = item:GetFullName() .. ":" .. item.ClassName .. ":"
		table.insert(lines, prefix)
		for _, property in properties do
			local ok, result = pcall(function()
				return item[property]
			end)
			if ok then
				table.insert(lines, prefix .. property .. "=" .. value(result))
			end
		end
		for name, attribute in item:GetAttributes() do
			table.insert(lines, prefix .. "@" .. name .. "=" .. value(attribute))
		end
		for _, tag in item:GetTags() do
			table.insert(lines, prefix .. "#" .. tag)
		end
	end
	for _, service in { workspace, game:GetService("Lighting"), game:GetService("StarterPlayer") } do
		record(service)
		for _, item in service:GetDescendants() do
			record(item)
		end
	end
	for _, line in sources do
		table.insert(lines, "Source:" .. line)
	end
	table.sort(lines)
	return {
		name = game.Name,
		placeId = game.PlaceId,
		sourceCount = #sources,
		fingerprint = hash(table.concat(lines, "\n")),
		records = #lines,
	}
end
