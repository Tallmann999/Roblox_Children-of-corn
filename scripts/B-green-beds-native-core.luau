-- Studio MCP only. Sources and geometry are prepared before any persistent write.
-- selene: allow(global_usage)
return function(payload, mode)
	local OWNER = "corn_B_green_beds_v1"
	local KEY = "__CornBGreenBedsV1_work"
	local http = game:GetService("HttpService")
	local encoding = game:GetService("EncodingService")
	local function hash(value)
		return (
			encoding
				:ComputeStringHash(value:gsub("\r\n", "\n"), Enum.HashAlgorithm.Sha256)
				:gsub(".", function(c)
					return string.format("%02x", c:byte())
				end)
		)
	end
	local function target()
		assert(
			game:GetService("RunService"):IsStudio()
				and not game:GetService("RunService"):IsRunning(),
			"Stopped B Edit required"
		)
		assert(
			game.Name == "Children_of_corn_B.rbxl" and game.PlaceId == 0,
			"Exact local B required"
		)
		local map = assert(workspace:FindFirstChild("CornMap"), "CornMap required")
		assert(
			map:GetAttribute("corn_project_id") == "children_of_corn"
				and map:GetAttribute("HarvestArtVariant") == "B",
			"B identity required"
		)
		assert(
			map.FieldZone.Size == Vector3.new(630, 10, 630)
				and map.FieldZone.CFrame == CFrame.new(0, 19.399986267089844, 0),
			"Frozen B field required"
		)
		return map
	end
	local function locate(path)
		local item = game
		for segment in path:gmatch("[^/]+") do
			local nextItem = nil
			for _, child in item:GetChildren() do
				if child.Name == segment then
					assert(not nextItem, "Duplicate code path")
					nextItem = child
				end
			end
			if not nextItem then
				return nil
			end
			item = nextItem
		end
		return item
	end
	local function sourceGuard(installed)
		local expected = table.clone(payload.sources)
		if installed then
			for path, row in payload.sourceChanges do
				expected[path] = { class = expected[path].class, sha256 = row.after_sha256 }
			end
			for path, row in payload.newSources do
				expected[path] = row
			end
		end
		local count = 0
		for _, item in game:GetDescendants() do
			if item:IsA("LuaSourceContainer") then
				count += 1
				local path = item:GetFullName():gsub("%.", "/")
				local row = expected[path]
				assert(
					row and row.class == item.ClassName and hash(item.Source) == row.sha256,
					"Author Source preserved: " .. path
				)
				assert(
					game:GetService("ScriptEditorService"):GetEditorSource(item) == item.Source,
					"Author buffer preserved: " .. path
				)
			end
		end
		assert(count == (if installed then 163 else 157), "Complete source state required")
	end
	local function typed(value)
		local kind = typeof(value)
		if kind == "Vector3" then
			return { kind = kind, value = { value.X, value.Y, value.Z } }
		end
		if kind == "Color3" then
			return { kind = kind, value = { value.R, value.G, value.B } }
		end
		if kind == "CFrame" then
			return { kind = kind, value = { value:GetComponents() } }
		end
		if kind == "EnumItem" then
			return { kind = "Enum", value = value.Value }
		end
		assert(
			kind == "boolean" or kind == "number" or kind == "string",
			"Explicit public property type required"
		)
		return value
	end
	local function newRecord(item, prototype)
		local props = {}
		if item:IsA("MeshPart") then
			for _, key in
				{
					"CFrame",
					"Size",
					"PivotOffset",
					"Color",
					"TextureID",
					"Transparency",
					"Reflectance",
					"Material",
					"Anchored",
					"CanCollide",
					"CanTouch",
					"CanQuery",
					"CastShadow",
					"DoubleSided",
					"RenderFidelity",
				}
			do
				props[key] = typed(item[key])
			end
			props.InitialSize = typed(item.MeshSize)
		end
		return {
			class = item.ClassName,
			prototype = prototype,
			properties = props,
			attributes = item:GetAttributes(),
			tags = item:GetTags(),
		}
	end
	local function oldSame(row, after)
		local item, values = row.item, if after then row.after else row.before
		return item.Parent == row.parent
			and item.Name == row.name
			and #item:GetChildren() == 0
			and item.MeshId == "rbxassetid://104111861186519"
			and item.CFrame == values.CFrame
			and item.Size == values.Size
			and item.Color == values.Color
			and item.TextureID == values.TextureID
			and item.Transparency == values.Transparency
	end
	local function same(a, b)
		if type(a) ~= type(b) then
			return false
		end
		if type(a) ~= "table" then
			return a == b
		end
		for key, value in a do
			if not same(value, b[key]) then
				return false
			end
		end
		for key in b do
			if a[key] == nil then
				return false
			end
		end
		return true
	end
	local function bedsGuard(work)
		for index, item in work.created do
			local path = "Workspace/CornMap/GreenBedEditor/" .. item.Name
			assert(
				item.Parent == work.root
					and same(
						newRecord(item, work.layout.SoilTiles[index].Key),
						work.proposal.new_nodes[path]
					),
				"Complete prepared bed preserved"
			)
		end
	end
	local map = target()
	assert(payload.owner == OWNER, "Wrong payload")
	if mode == "prepare" then
		sourceGuard(false)
		assert(
			_G[KEY] == nil and not map:FindFirstChild("GreenBedEditor"),
			"Existing green-bed work preserved"
		)
		local work = {
			owner = OWNER,
			state = "preparing",
			old = {},
			added = {},
			changes = {},
			nodes = {},
			created = {},
			proposal = {
				version = 1,
				owner = OWNER,
				baseline_sha256 = "268474cacf629bdf450538e86876a8060363a1f458e253b8368cac8126bbab60",
				payload_sha256 = _G.__CornBGreenBedsV1_transport.sha256,
				old = {},
				new_nodes = {},
			},
		}
		_G[KEY] = work
		local private = Instance.new("Folder")
		private.Name = "Game"
		work.private = private
		local data = Instance.new("Folder")
		data.Name = "GreenBedGeometryData"
		data.Parent = private
		data:SetAttribute("BGreenBedsOwner", OWNER)
		data:SetAttribute("corn_project_id", "children_of_corn")
		work.data = data
		local ok, problem = pcall(function()
			for path, row in payload.newSources do
				assert(
					not locate(path) and hash(row.source) == row.sha256,
					"New Source path/hash differs"
				)
				local item = Instance.new(row.class)
				item.Name = path:match("([^/]+)$")
				item.Source = row.source
				item:SetAttribute("BGreenBedsOwner", OWNER)
				item:SetAttribute("corn_project_id", "children_of_corn")
				work.added[path] = item
				if path:find("/GreenBedGeometryData/", 1, true) then
					item.Parent = data
				elseif not path:find("/Controllers/", 1, true) then
					item.Parent = private
				end
				work.proposal.new_nodes[path] = newRecord(item, "ModuleScript")
			end
			for path, row in payload.sourceChanges do
				local original = assert(locate(path), "Retained Source required")
				assert(hash(row.source) == row.after_sha256, "Changed Source hash required")
				work.changes[path] =
					{ item = original, before = original.Source, after = row.source }
			end
			local layout = require(work.added["ReplicatedStorage/GameShared/Game/GreenBedLayout"])
			work.layout = layout
			local geometry =
				require(work.added["ReplicatedStorage/GameShared/Game/GreenBedGeometry"])
			work.geometry = geometry
			geometry.BuildTemplates()
			local root = Instance.new("Folder")
			root.Name = "GreenBedEditor"
			root:SetAttribute("BGreenBedsOwner", OWNER)
			root:SetAttribute("corn_project_id", "children_of_corn")
			work.root = root
			work.proposal.new_nodes["ReplicatedStorage/GameShared/Game/GreenBedGeometryData"] =
				newRecord(data, "Folder")
			work.proposal.new_nodes["Workspace/CornMap/GreenBedEditor"] = newRecord(root, "Folder")
			for index, tile in layout.SoilTiles do
				local item = geometry.Clone(tile.Key, tile.Frame)
				item.Size = tile.Size
				item.Name ..= "_" .. string.format("%04d", index)
				item:SetAttribute("BGreenBedTile", index)
				item.Parent = root
				work.created[index] = item
				work.proposal.new_nodes["Workspace/CornMap/GreenBedEditor/" .. item.Name] =
					newRecord(item, tile.Key)
				if index % 64 == 0 then
					task.wait()
				end
			end
			assert(#work.created == 1406, "Complete bed preparation required")
			local seen = {}
			local spacing = 3 / math.sqrt(2.6)
			for _, folderName in { "EditorPreview", "EditorFieldOverview" } do
				local folder = map[folderName]
				local expected = if folderName == "EditorPreview" then 904 else 2576
				assert(#folder:GetChildren() == expected, "Frozen editor corn count required")
				for _, item in folder:GetChildren() do
					assert(
						item:IsA("MeshPart")
							and item.MeshId == "rbxassetid://104111861186519"
							and #item:GetChildren() == 0,
						"Known childless original corn required"
					)
					assert(
						item.TextureID == "rbxassetid://103653296385119",
						"Unknown editor corn texture"
					)
					local old = {
						CFrame = item.CFrame,
						Size = item.Size,
						Color = item.Color,
						TextureID = item.TextureID,
						Transparency = item.Transparency,
					}
					local column, row =
						math.round(item.Position.X / spacing), math.round(item.Position.Z / spacing)
					local point = Vector3.new(column * spacing, layout.GroundY, row * spacing)
					local token = column .. ":" .. row
					local valid = layout.Contains(point) and not seen[token]
					if valid then
						seen[token] = true
					end
					local meshSize = item.MeshSize
					local size = meshSize * (8 / meshSize.Y)
					local yaw = math.atan2(-item.CFrame.LookVector.X, -item.CFrame.LookVector.Z)
					local after = {
						CFrame = CFrame.new(layout.Position(point) + Vector3.new(0, 4, 0))
							* CFrame.Angles(0, yaw, 0),
						Size = size,
						Color = Color3.new(1, 1, 1),
						TextureID = "rbxassetid://137803536172445",
						Transparency = if valid then 0 else 1,
					}
					local record = {
						item = item,
						parent = folder,
						name = item.Name,
						before = old,
						after = after,
						id = item:GetDebugId(0),
					}
					table.insert(work.old, record)
					table.insert(work.proposal.old, {
						path = item:GetFullName():gsub("%.", "/"),
						oldFrame = { old.CFrame:GetComponents() },
						beforeSize = { old.Size.X, old.Size.Y, old.Size.Z },
						oldTexture = old.TextureID,
						cframe = { after.CFrame:GetComponents() },
						size = { size.X, size.Y, size.Z },
						color = { 1, 1, 1 },
						texture = after.TextureID,
						transparency = after.Transparency,
						nativeDebugId = record.id,
					})
					if #work.old % 64 == 0 then
						task.wait()
					end
				end
			end
			assert(#work.old == 3480, "Complete corn preparation required")
			work.proposalText = http:JSONEncode(work.proposal)
			work.state = "prepared"
		end)
		if not ok then
			if work.geometry then
				work.geometry.DestroyCache()
			end
			if work.root then
				work.root:Destroy()
			end
			for _, item in work.added do
				item:Destroy()
			end
			private:Destroy()
			_G[KEY] = nil
			error("Preparation failed; persistent B untouched: " .. tostring(problem), 0)
		end
		return {
			prepared = true,
			corn = #work.old,
			beds = #work.created,
			proposalBytes = #work.proposalText,
			proposalSha256 = hash(work.proposalText),
		}
	end
	local work = assert(_G[KEY], "Prepared work required")
	assert(work.owner == OWNER, "Owned preparation required")
	if mode == "verify" then
		assert(work.state == "installed", "Installed state required")
		sourceGuard(true)
		for _, row in work.old do
			assert(oldSame(row, true), "Changed installed editor corn preserved")
		end
		assert(
			work.root.Parent == map and #work.root:GetChildren() == 1406,
			"Complete bed publication required"
		)
		for index, item in work.created do
			local tile = work.layout.SoilTiles[index]
			assert(
				item.Parent == work.root
					and item.CFrame == tile.Frame
					and item.Size == tile.Size
					and item:GetAttribute("BGreenBedTile") == index,
				"Changed bed preserved"
			)
		end
		bedsGuard(work)
		return { verified = true, sourceCount = 163, corn = #work.old, beds = #work.created }
	end
	assert(mode == "install" and work.state == "prepared", "Explicit fresh install required")
	sourceGuard(false)
	bedsGuard(work)
	for _, row in work.old do
		assert(oldSame(row, false), "Author corn change preserved")
	end
	assert(not map:FindFirstChild("GreenBedEditor"), "Author bed folder preserved")
	local written = {}
	local ok, problem = pcall(function()
		work.data.Parent = game.ReplicatedStorage.GameShared.Game
		for path, item in work.added do
			if not path:find("/GreenBedGeometryData/", 1, true) then
				item.Parent = assert(locate(path:match("^(.*)/[^/]+$")), "Source parent required")
			end
		end
		for path, row in work.changes do
			assert(
				locate(path) == row.item and row.item.Source == row.before,
				"Author Source identity preserved"
			)
			row.item.Source = row.after
		end
		for _, row in work.old do
			assert(oldSame(row, false), "Concurrent author corn change preserved")
			written[#written + 1] = row
			for property, value in row.after do
				row.item[property] = value
			end
			if #written % 64 == 0 then
				task.wait()
			end
		end
		for _, item in work.created do
			item.Parent = nil
		end
		work.root.Parent = map
		for index, item in work.created do
			item.Parent = work.root
			if index % 64 == 0 then
				task.wait()
			end
		end
		sourceGuard(true)
		for _, row in work.old do
			assert(oldSame(row, true), "Installed corn fully verified")
		end
		bedsGuard(work)
		work.state = "installed"
	end)
	if not ok then
		local conflicts = 0
		for index = #written, 1, -1 do
			local row = written[index]
			for property, value in row.before do
				if row.item[property] == row.after[property] then
					row.item[property] = value
				elseif row.item[property] ~= value then
					conflicts += 1
				end
			end
		end
		for _, row in work.changes do
			if row.item.Source == row.after then
				row.item.Source = row.before
			elseif row.item.Source ~= row.before then
				conflicts += 1
			end
		end
		if work.root.Parent then
			work.root.Parent = nil
		end
		for _, item in work.created do
			item.Parent = work.root
		end
		for path, item in work.added do
			if path:find("/GreenBedGeometryData/", 1, true) then
				item.Parent = work.data
			elseif not path:find("/Controllers/", 1, true) then
				item.Parent = work.private
			else
				item.Parent = nil
			end
		end
		work.data.Parent = work.private
		work.state = "prepared"
		if conflicts == 0 then
			sourceGuard(false)
		end
		error(
			"Install rolled back; preserved concurrent author values="
				.. conflicts
				.. ": "
				.. tostring(problem),
			0
		)
	end
	return {
		installed = true,
		sourceChanges = 2,
		newSources = 6,
		corn = #written,
		newBeds = #work.created,
	}
end
