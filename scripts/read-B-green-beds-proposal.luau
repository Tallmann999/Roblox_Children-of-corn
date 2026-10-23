-- READ ONLY. Export explicit prepared intent; never writes an Instance/Source.
-- spec.old: [{item:MeshPart, cframe:CFrame, size:Vector3, color:Color3,
--             texture:string, transparency:number}]
-- spec.new_nodes: {[full planned path]:{item:Instance,prototype:string}}
-- New items may be unparented. This does not read protected IDs or GUIDs.
return function(spec)
	local run = game:GetService("RunService")
	assert(run:IsStudio() and not run:IsRunning(), "Stopped B Edit required")
	assert(game.Name == "Children_of_corn_B.rbxl", "B filename required")
	local map = assert(workspace:FindFirstChild("CornMap"), "CornMap required")
	assert(
		map:GetAttribute("corn_project_id") == "children_of_corn"
			and map:GetAttribute("HarvestArtVariant") == "B",
		"Verified B identity required"
	)
	assert(spec.owner == "corn_B_green_beds_v1", "Owned prepared specification required")
	local function frame(value)
		return { value:GetComponents() }
	end
	local function vector(value)
		return { value.X, value.Y, value.Z }
	end
	local function color(value)
		return { value.R, value.G, value.B }
	end
	local function typed(value)
		local kind = typeof(value)
		if kind == "CFrame" then
			return { kind = kind, value = frame(value) }
		elseif kind == "Vector3" then
			return { kind = kind, value = vector(value) }
		elseif kind == "Color3" then
			return { kind = kind, value = color(value) }
		elseif kind == "EnumItem" then
			return { kind = "Enum", value = value.Value }
		end
		assert(
			kind == "boolean" or kind == "string" or kind == "number",
			"Unsupported public value"
		)
		return value
	end
	local result = {
		version = 1,
		owner = spec.owner,
		baseline_sha256 = "268474cacf629bdf450538e86876a8060363a1f458e253b8368cac8126bbab60",
		payload_sha256 = spec.payload_sha256,
		old = {},
		new_nodes = {},
	}
	local seen = {}
	for index, row in spec.old do
		if index % 128 == 0 then
			task.wait()
		end
		local item = row.item
		assert(item:IsA("MeshPart") and item:IsDescendantOf(map), "Existing native B corn required")
		assert(not seen[item], "Duplicate prepared old corn")
		seen[item] = true
		result.old[#result.old + 1] = {
			path = item:GetFullName():gsub("%.", "/"),
			nativeDebugId = item:GetDebugId(0),
			oldFrame = frame(item.CFrame),
			beforeSize = vector(item.Size),
			oldTexture = item.TextureID,
			cframe = frame(row.cframe),
			size = vector(row.size),
			color = color(row.color),
			texture = row.texture,
			transparency = row.transparency,
		}
	end
	for path, row in spec.new_nodes do
		local item = row.item
		assert(
			item:IsA("MeshPart") or item:IsA("ModuleScript") or item:IsA("Folder"),
			"Unexpected proposed new class"
		)
		local props = {}
		if item:IsA("MeshPart") then
			assert(
				item.MeshContent.SourceType == Enum.ContentSourceType.Opaque,
				"Exact opaque static bed mesh required"
			)
			for _, key in
				{
					"CFrame",
					"Size",
					"PivotOffset",
					"Color",
					"TextureID",
					"Transparency",
					"Anchored",
					"CanCollide",
					"CanTouch",
					"CanQuery",
					"CastShadow",
					"DoubleSided",
					"Material",
					"MaterialVariant",
					"RenderFidelity",
					"CollisionGroup",
					"Massless",
					"RootPriority",
					"Reflectance",
					"Locked",
				}
			do
				props[key] = typed(item[key])
			end
			props.InitialSize = typed(item.MeshSize)
		end
		local attrs = {}
		for key, value in item:GetAttributes() do
			attrs[key] = typed(value)
		end
		local tags = item:GetTags()
		table.sort(tags)
		result.new_nodes[path] = {
			class = item.ClassName,
			prototype = row.prototype,
			properties = props,
			attributes = attrs,
			tags = tags,
		}
	end
	return result
end
