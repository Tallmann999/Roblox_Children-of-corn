-- Studio MCP only. Preparation owns unparented helpers/templates; no world writes.
-- selene: allow(global_usage)
return function(payload, mode)
	local OWNER = "corn_B_green_variants_v1"
	local KEY = "__CornBGreenVariantsV1_work"
	local DATA = "ReplicatedStorage/GameShared/Game/CornGreenGeometryData"
	local GEOMETRY = "ReplicatedStorage/GameShared/Game/CornGreenGeometry"
	local LAYOUT = "ReplicatedStorage/GameShared/Game/CornLayout"
	local APPEARANCE = "ReplicatedStorage/GameShared/Game/CornAppearance"
	local BED_LAYOUT = "ReplicatedStorage/GameShared/Game/GreenBedLayout"
	local SOURCE_CHANGES = {
		[LAYOUT] = true,
		[APPEARANCE] = true,
		["StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornWindController"] = true,
	}
	local NEW_SOURCES = { [GEOMETRY] = true }
	for _, key in { "Var01", "Var02", "Var03" } do
		NEW_SOURCES[DATA .. "/" .. key] = true
	end
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
	local function validHash(value)
		return type(value) == "string" and #value == 64 and not value:find("[^0-9a-f]")
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
	local function target()
		local run = game:GetService("RunService")
		assert(run:IsStudio() and not run:IsRunning(), "Stopped B Edit required")
		assert(
			game.Name == "Children_of_corn_B.rbxl" and game.PlaceId == 0,
			"Exact local B required"
		)
		local map = assert(workspace:FindFirstChild("CornMap"), "CornMap required")
		assert(
			map:IsA("Model")
				and map:GetAttribute("corn_project_id") == "children_of_corn"
				and map:GetAttribute("HarvestArtVariant") == "B",
			"Verified B identity required"
		)
		local field = assert(map:FindFirstChild("FieldZone"), "Field required")
		assert(
			field.Size == Vector3.new(630, 10, 630)
				and field.CFrame == CFrame.new(0, 19.399986267089844, 0)
				and map.Ground.Size == Vector3.new(630, 2, 630),
			"Frozen B field required"
		)
		return map, field
	end
	local function locate(path)
		local item = game
		for segment in path:gmatch("[^/]+") do
			local found = nil
			for _, child in item:GetChildren() do
				if child.Name == segment then
					assert(not found, "Duplicate code path")
					found = child
				end
			end
			if not found then
				return nil
			end
			item = found
		end
		return item
	end
	assert(type(payload) == "table" and payload.owner == OWNER, "Owned payload required")
	local changeCount, newCount, guardCount = 0, 0, 0
	for path, row in payload.sources do
		assert(
			type(path) == "string" and type(row) == "table" and validHash(row.sha256),
			"Malformed Source guard"
		)
		guardCount += 1
	end
	assert(guardCount == 163, "All 163 old Sources required")
	for path, row in payload.sourceChanges do
		assert(
			SOURCE_CHANGES[path]
				and payload.sources[path]
				and row.before_sha256 == payload.sources[path].sha256
				and validHash(row.after_sha256)
				and row.before_sha256 ~= row.after_sha256
				and type(row.source) == "string"
				and not row.source:find("\r", 1, true)
				and hash(row.source) == row.after_sha256,
			"Unreviewed changed Source"
		)
		changeCount += 1
	end
	for path, row in payload.newSources do
		assert(
			NEW_SOURCES[path]
				and row.class == "ModuleScript"
				and validHash(row.sha256)
				and type(row.source) == "string"
				and not row.source:find("\r", 1, true)
				and hash(row.source) == row.sha256,
			"Unreviewed new Source"
		)
		newCount += 1
	end
	assert(changeCount == 3 and newCount == 4, "Exact three changes/four additions required")
	local function sourceGuard(installed, work)
		local expected = table.clone(payload.sources)
		if installed then
			for path, row in payload.sourceChanges do
				expected[path] = { class = expected[path].class, sha256 = row.after_sha256 }
			end
			for path, row in payload.newSources do
				expected[path] = row
			end
		end
		local count, found = 0, {}
		for _, item in game:GetDescendants() do
			if item:IsA("LuaSourceContainer") then
				local path = item:GetFullName():gsub("%.", "/")
				assert(not found[path], "Duplicate Source path")
				local row = expected[path]
				assert(
					row and row.class == item.ClassName and hash(item.Source) == row.sha256,
					"Author Source preserved: " .. path
				)
				assert(
					game:GetService("ScriptEditorService"):GetEditorSource(item) == item.Source,
					"Author buffer preserved: " .. path
				)
				if work and work.retained[path] then
					assert(
						item == work.retained[path].item
							and item.Parent == work.retained[path].parent,
						"Retained Source identity/parent changed"
					)
				elseif work and installed then
					assert(item == work.added[path], "New Source identity changed")
				end
				count += 1
				found[path] = { item = item, parent = item.Parent }
			end
		end
		assert(count == (if installed then 167 else 163), "Complete Source graph required")
		return found
	end
	local PART_PROPS = {
		"Archivable",
		"Locked",
		"CFrame",
		"Size",
		"MeshId",
		"MeshContent",
		"MeshSize",
		"TextureID",
		"TextureContent",
		"PivotOffset",
		"Color",
		"Material",
		"MaterialVariant",
		"Reflectance",
		"Transparency",
		"Anchored",
		"CanCollide",
		"CanTouch",
		"CanQuery",
		"CastShadow",
		"DoubleSided",
		"Massless",
		"CollisionGroup",
		"CustomPhysicalProperties",
		"RootPriority",
		"RenderFidelity",
		"CollisionFidelity",
	}
	local ALLOWED =
		{ CFrame = true, Size = true, Color = true, TextureID = true, Transparency = true }
	local function snapshot(item, excludeMutable)
		local props = {}
		for _, key in PART_PROPS do
			if not excludeMutable or not ALLOWED[key] then
				props[key] = item[key]
			end
		end
		local tags = item:GetTags()
		table.sort(tags)
		return {
			properties = props,
			attributes = item:GetAttributes(),
			tags = tags,
			children = item:GetChildren(),
		}
	end
	local function oldSame(row, after)
		local item, values = row.item, if after then row.after else row.before
		if
			item.Parent ~= row.parent
			or item.Name ~= row.name
			or not same(snapshot(item, true), row.immutable)
		then
			return false
		end
		for property, value in values do
			if item[property] ~= value then
				return false
			end
		end
		return true
	end
	local function codeRecord(item)
		local tags = item:GetTags()
		table.sort(tags)
		return {
			class = item.ClassName,
			prototype = item.ClassName,
			properties = {},
			attributes = item:GetAttributes(),
			tags = tags,
		}
	end
	local function bedsGuard(work)
		assert(
			work.bedRoot.Parent == work.map
				and work.bedRoot.Name == "GreenBedEditor"
				and same(work.bedRoot:GetAttributes(), work.bedRootAttrs),
			"Existing bed root preserved"
		)
		local tags = work.bedRoot:GetTags()
		table.sort(tags)
		assert(
			same(tags, work.bedRootTags) and #work.bedRoot:GetChildren() == 1406,
			"Existing bed set preserved"
		)
		for _, row in work.beds do
			assert(
				row.item.Parent == work.bedRoot
					and row.item.Name == row.name
					and same(snapshot(row.item, false), row.before),
				"Existing bed properties/geometry preserved"
			)
		end
	end
	local function newGuard(work, installed)
		local parent = if installed then game.ReplicatedStorage.GameShared.Game else work.private
		assert(
			work.data.Parent == parent
				and #work.data:GetChildren() == 3
				and same(codeRecord(work.data), work.proposal.new_nodes[DATA]),
			"Prepared data folder preserved"
		)
		for path, item in work.added do
			local expectedParent = if path:sub(1, #DATA + 1) == DATA .. "/"
				then work.data
				else parent
			assert(
				item.Parent == expectedParent
					and #item:GetChildren() == 0
					and item.Name == path:match("([^/]+)$")
					and item.Source == payload.newSources[path].source
					and same(codeRecord(item), work.proposal.new_nodes[path]),
				"Prepared new Source preserved"
			)
		end
	end
	local function exclusionGuard(work)
		local ex = work.layout.ReadExclusions(work.map, work.field)
		assert(
			#ex.Boxes == 188
				and #ex.Circles == 19
				and ex.GreenBeds == true
				and #ex.TrailEdges == 100
				and ex.Signature == work.signature,
			"Accepted clearances preserved"
		)
		return ex
	end
	local function destroyPrivate(work)
		local retained = 0
		if work.scratch then
			if work.scratch.Parent == nil then
				work.scratch:Destroy()
			else
				retained += 1
			end
		end
		for _, item in work.proofTemplates or {} do
			if item.Parent == nil then
				item:Destroy()
			else
				retained += 1
			end
		end
		if work.private and work.private.Parent == nil then
			work.private:Destroy()
		else
			retained += 1
		end
		return retained
	end
	local map, field = target()
	if mode == "prepare" then
		local retained = sourceGuard(false)
		assert(
			_G[KEY] == nil and not locate(DATA) and not locate(GEOMETRY),
			"Existing preparation/code preserved"
		)
		local transport =
			assert(_G.__CornBGreenVariantsV1_transport, "Verified owned transport required")
		assert(validHash(transport.sha256), "Frozen payload hash required")
		local work = {
			owner = OWNER,
			state = "preparing",
			map = map,
			field = field,
			retained = retained,
			old = {},
			beds = {},
			added = {},
			changes = {},
			proofTemplates = {},
			proposal = {
				version = 1,
				owner = OWNER,
				baseline_sha256 = "db9398781ec6d68da97bfadb1514e5a589cdf5a293424538e19bc29869f7a371",
				payload_sha256 = transport.sha256,
				old = {},
				new_nodes = {},
			},
		}
		_G[KEY] = work
		local ok, problem = pcall(function()
			work.private = Instance.new("Folder")
			work.private.Name = "Game"
			work.data = Instance.new("Folder")
			work.data.Name = "CornGreenGeometryData"
			work.data:SetAttribute("BGreenVariantsOwner", OWNER)
			work.data:SetAttribute("corn_project_id", "children_of_corn")
			work.data.Parent = work.private
			for path, row in payload.newSources do
				assert(not locate(path), "Existing new-code path preserved")
				local item = Instance.new("ModuleScript")
				item.Name = path:match("([^/]+)$")
				item.Source = row.source
				item:SetAttribute("BGreenVariantsOwner", OWNER)
				item:SetAttribute("corn_project_id", "children_of_corn")
				item.Parent = if path:sub(1, #DATA + 1) == DATA .. "/"
					then work.data
					else work.private
				work.added[path] = item
				work.proposal.new_nodes[path] = codeRecord(item)
			end
			work.proposal.new_nodes[DATA] = codeRecord(work.data)
			for path, row in payload.sourceChanges do
				local item = assert(locate(path), "Changed Source required")
				work.changes[path] =
					{ item = item, parent = item.Parent, before = item.Source, after = row.source }
			end
			local function helper(name, source)
				local item = Instance.new("ModuleScript")
				item.Name = name
				item.Source = source
				item.Parent = work.private
				return item
			end
			local originalBeds = assert(locate(BED_LAYOUT), "Unchanged bed layout required")
			helper("GreenBedLayout", originalBeds.Source)
			work.layout = require(helper("CornLayout", payload.sourceChanges[LAYOUT].source))
			work.appearance =
				require(helper("CornAppearance", payload.sourceChanges[APPEARANCE].source))
			local templates = work.appearance.DetailedTemplates()
			local proof = { uri = 0, opaque = 0, templates = 0, lods = 3, varieties = 4 }
			local seenTemplates = {}
			for _, lod in { "Near", "Mid", "Far" } do
				for variety = 1, 4 do
					local item = templates[lod][variety]
					assert(
						not seenTemplates[item]
							and item.Parent == nil
							and item.Size.Y == 8
							and work.appearance.IsDetailedPlant(item, variety, lod)
							and item.CastShadow
							and item.DoubleSided
							and item.TextureID == "rbxassetid://137803536172445",
						"Exact four-variety native template proof required"
					)
					seenTemplates[item] = true
					table.insert(work.proofTemplates, item)
					if item.MeshContent.SourceType == Enum.ContentSourceType.Uri then
						proof.uri += 1
					else
						assert(
							item.MeshContent.SourceType == Enum.ContentSourceType.Opaque,
							"Opaque static variant required"
						)
						proof.opaque += 1
					end
					proof.templates += 1
				end
			end
			assert(
				proof.uri == 3 and proof.opaque == 9,
				"One original plus three static shapes per LOD required"
			)
			work.proof = proof
			local ex = work.layout.ReadExclusions(map, field)
			assert(
				#ex.Boxes == 188 and #ex.Circles == 19 and ex.GreenBeds and #ex.TrailEdges == 100,
				"Frozen exclusions required"
			)
			work.signature = ex.Signature
			work.bedRoot = assert(map:FindFirstChild("GreenBedEditor"), "Saved bed root required")
			work.bedRootAttrs = work.bedRoot:GetAttributes()
			work.bedRootTags = work.bedRoot:GetTags()
			table.sort(work.bedRootTags)
			for _, item in work.bedRoot:GetChildren() do
				assert(item:IsA("MeshPart"), "Exact saved bed meshes required")
				table.insert(
					work.beds,
					{ item = item, name = item.Name, before = snapshot(item, false) }
				)
			end
			assert(#work.beds == 1406, "All 1,406 saved beds required")
			local currentVisible = 0
			for _, folderName in { "EditorPreview", "EditorFieldOverview" } do
				local folder = assert(map:FindFirstChild(folderName), "Editor corn folder required")
				assert(
					#folder:GetChildren() == (if folderName == "EditorPreview" then 904 else 2576),
					"Complete existing corn set required"
				)
				for _, item in folder:GetChildren() do
					assert(
						item:IsA("MeshPart")
							and #item:GetChildren() == 0
							and item.MeshId == "rbxassetid://104111861186519"
							and item.TextureID == "rbxassetid://137803536172445"
							and (item.Transparency == 0 or item.Transparency == 1),
						"Accepted original editor corn required"
					)
					if item.Transparency == 0 then
						currentVisible += 1
					end
					local before = {
						CFrame = item.CFrame,
						Size = item.Size,
						Color = item.Color,
						TextureID = item.TextureID,
						Transparency = item.Transparency,
					}
					table.insert(work.old, {
						item = item,
						parent = folder,
						name = item.Name,
						before = before,
						immutable = snapshot(item, true),
						id = item:GetDebugId(0),
					})
				end
			end
			assert(
				#work.old == 3480 and currentVisible == 2591,
				"Accepted complete editor population required"
			)
			table.sort(work.old, function(a, b)
				if a.parent.Name ~= b.parent.Name then
					return a.parent.Name < b.parent.Name
				end
				local af, bf = tostring(a.before.CFrame), tostring(b.before.CFrame)
				return if af ~= bf then af < bf else a.id < b.id
			end)
			work.scratch = assert(work.old[1].item:Clone(), "Private ordinary-URI scratch required")
			work.scratch.Parent = nil
			work.scratch:SetAttribute("CornGreenOriginal", true)
			work.scratch:SetAttribute("corn_project_id", "children_of_corn")
			local spacing = work.layout.SpacingFor(field)
			local selectedCells, candidates = {}, {}
			for index, row in work.old do
				local localPosition = field.CFrame:PointToObjectSpace(row.before.CFrame.Position)
				local column, line =
					math.round(localPosition.X / spacing), math.round(localPosition.Z / spacing)
				local point = work.layout.CellPosition(field, column, line)
				local valid = not work.layout.IsExcluded(point, ex)
				local projected = work.layout.TrailEdgePosition(point, ex)
				valid = valid and not work.layout.IsExcluded(projected, ex)
				local token = column .. ":" .. line
				local size = Vector3.new(row.before.Size.X, 8, row.before.Size.Z)
				work.scratch.Size = size
				work.scratch:SetAttribute("CornGreenTemplateSize", size)
				work.scratch:SetAttribute("HarvestRootOffset", Vector3.new(0, 4, 0))
				work.layout.ApplyVariation(work.scratch, column, line)
				row.after = {
					CFrame = work.appearance.DetailedPivot(
						work.scratch,
						projected,
						work.layout.CellYaw(column, line)
					),
					Size = work.scratch.Size,
					Color = Color3.new(1, 1, 1),
					TextureID = "rbxassetid://137803536172445",
					Transparency = 1,
				}
				row.column, row.line, row.point, row.token = column, line, projected, token
				row.rank = (column * 73856093 + line * 19349663 + 817) % 104729
				if valid and not selectedCells[token] then
					selectedCells[token] = row
					table.insert(candidates, row)
				end
				if index % 64 == 0 then
					task.wait()
				end
			end
			table.sort(candidates, function(a, b)
				if a.rank ~= b.rank then
					return a.rank < b.rank
				end
				return if a.column ~= b.column then a.column < b.column else a.line < b.line
			end)
			local wanted = math.round(currentVisible * 0.7)
			assert(
				wanted == 1814 and #candidates >= wanted,
				"Enough unique real-soil cells required for exact 30% preview reduction"
			)
			for index = 1, wanted do
				candidates[index].after.Transparency = 0
			end
			work.beforeVisible, work.afterVisible, work.validCells =
				currentVisible, wanted, #candidates
			for _, row in work.old do
				local a, z = row.before, row.after
				table.insert(work.proposal.old, {
					path = row.item:GetFullName():gsub("%.", "/"),
					oldFrame = { a.CFrame:GetComponents() },
					beforeSize = { a.Size.X, a.Size.Y, a.Size.Z },
					oldTexture = a.TextureID,
					nativeDebugId = row.id,
					cframe = { z.CFrame:GetComponents() },
					size = { z.Size.X, z.Size.Y, z.Size.Z },
					color = { 1, 1, 1 },
					texture = z.TextureID,
					transparency = z.Transparency,
				})
			end
			sourceGuard(false, work)
			bedsGuard(work)
			exclusionGuard(work)
			newGuard(work, false)
			for _, row in work.old do
				assert(oldSame(row, false), "Concurrent old corn change preserved")
			end
			work.proposalText = http:JSONEncode(work.proposal)
			work.state = "prepared"
		end)
		if not ok then
			local kept = destroyPrivate(work)
			_G[KEY] = nil
			error(
				"Preparation failed; persistent B untouched; private foreign parents retained="
					.. kept
					.. ": "
					.. tostring(problem),
				0
			)
		end
		return {
			prepared = true,
			sources = 163,
			newSources = 4,
			sourceChanges = 3,
			corn = 3480,
			bedsUntouched = 1406,
			beforeVisible = work.beforeVisible,
			afterVisible = work.afterVisible,
			uniqueCandidates = work.validCells,
			proof = work.proof,
			proposalBytes = #work.proposalText,
			proposalSha256 = hash(work.proposalText),
		}
	end
	local work = assert(_G[KEY], "Prepared work required")
	assert(
		work.owner == OWNER and work.map == map and work.field == field,
		"Exact owned preparation required"
	)
	local function verify()
		sourceGuard(true, work)
		newGuard(work, true)
		bedsGuard(work)
		exclusionGuard(work)
		for _, row in work.old do
			assert(oldSame(row, true), "Installed editor corn preserved")
		end
	end
	if mode == "verify" or mode == "cleanup" then
		assert(work.state == "installed", "Installed state required")
		verify()
		if mode == "cleanup" then
			local kept = destroyPrivate(work)
			_G[KEY] = nil
			return { cleaned = true, privateForeignParentsRetained = kept, persistentSources = 167 }
		end
		return {
			verified = true,
			sources = 167,
			corn = 3480,
			visibleCorn = work.afterVisible,
			bedsUntouched = 1406,
		}
	end
	assert(mode == "install" and work.state == "prepared", "Explicit fresh installation required")
	sourceGuard(false, work)
	newGuard(work, false)
	bedsGuard(work)
	exclusionGuard(work)
	for _, row in work.old do
		assert(oldSame(row, false), "Author editor corn preserved")
	end
	assert(not locate(DATA) and not locate(GEOMETRY), "Author new-code paths preserved")
	local written = {}
	local ok, problem = pcall(function()
		work.data.Parent = game.ReplicatedStorage.GameShared.Game
		work.added[GEOMETRY].Parent = game.ReplicatedStorage.GameShared.Game
		for path, row in work.changes do
			assert(
				locate(path) == row.item
					and row.item.Parent == row.parent
					and row.item.Source == row.before,
				"Author Source identity/bytes preserved"
			)
			row.item.Source = row.after
		end
		for _, row in work.old do
			assert(oldSame(row, false), "Concurrent author corn preserved")
			table.insert(written, row)
			for property, value in row.after do
				row.item[property] = value
			end
			if #written % 64 == 0 then
				task.wait()
			end
		end
		verify()
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
		if work.data.Parent == game.ReplicatedStorage.GameShared.Game then
			work.data.Parent = work.private
		elseif work.data.Parent ~= work.private then
			conflicts += 1
		end
		if work.added[GEOMETRY].Parent == game.ReplicatedStorage.GameShared.Game then
			work.added[GEOMETRY].Parent = work.private
		elseif work.added[GEOMETRY].Parent ~= work.private then
			conflicts += 1
		end
		work.state = "prepared"
		if conflicts == 0 then
			sourceGuard(false, work)
			newGuard(work, false)
			bedsGuard(work)
			for _, row in work.old do
				assert(oldSame(row, false), "Rollback old-corn verification failed")
			end
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
		sources = 167,
		sourceChanges = 3,
		newSources = 4,
		corn = #written,
		visibleCorn = work.afterVisible,
		bedsUntouched = 1406,
		newWorldNodes = 0,
	}
end
