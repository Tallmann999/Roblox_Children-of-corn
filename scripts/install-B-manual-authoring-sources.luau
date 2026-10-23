-- MCP-only Source transaction after the independent manual world grouping.
-- No world, lighting, Save, serialization, publication or A/C writes.
-- selene: allow(global_usage)
return function(payload)
	local S = assert(_G.__CornBManualAuthoringV1, "Fresh manual-authoring baseline required")
	local CHANGED = {
		["ReplicatedStorage/GameShared/Game/CornLayout"] = "variants/B/shared/Game/CornLayout.luau",
		["StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornController"] = "variants/B/client/Controllers/CornController.luau",
		["StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornBackdropController"] = "variants/B/client/Controllers/CornBackdropController.luau",
		["StarterPlayer/StarterPlayerScripts/GameClient/Controllers/GreenBedController"] = "variants/B/client/Controllers/GreenBedController.luau",
		["ServerScriptService/GameServer/Game/InventoryWorld"] = "variants/B/server/Game/InventoryWorld.luau",
		["ServerScriptService/GameServer/Game/HarvestWorld"] = "variants/B/server/Game/HarvestWorld.luau",
		["ServerScriptService/GameServer/Game/RoundAudio"] = "variants/B/server/Game/RoundAudio.luau",
		["StarterPlayer/StarterPlayerScripts/GameClient/Controllers/HarvestGeometryController"] = "variants/B/client/Controllers/HarvestGeometryController.luau",
	}
	local ADDED = {
		["ReplicatedStorage/GameShared/Game/ManualScene"] = "variants/B/shared/Game/ManualScene.luau",
		["ServerScriptService/GameServer/Services/ManualSceneService"] = "variants/B/server/Services/ManualSceneService.luau",
		["StarterPlayer/StarterPlayerScripts/GameClient/Controllers/AuthoringCornController"] = "variants/B/client/Controllers/AuthoringCornController.luau",
	}
	local encoding = game:GetService("EncodingService")
	local editor = game:GetService("ScriptEditorService")
	local function hash(value)
		return (
			encoding:ComputeStringHash(value, Enum.HashAlgorithm.Sha256):gsub(".", function(c)
				return string.format("%02x", c:byte())
			end)
		)
	end
	local function normalized(value)
		return (value:gsub("\r\n", "\n"):gsub("\r", "\n"))
	end
	local function keys(value)
		local result = {}
		for key in value do
			table.insert(result, key)
		end
		table.sort(result)
		return result
	end
	local function exactKeys(value, expected, label)
		assert(
			type(value) == "table" and getmetatable(value) == nil,
			"Plain table required: " .. label
		)
		local count = 0
		for key in value do
			assert(expected[key], "Unexpected key: " .. label .. "/" .. tostring(key))
			count += 1
		end
		local wanted = 0
		for key in expected do
			assert(value[key] ~= nil, "Missing key: " .. label .. "/" .. key)
			wanted += 1
		end
		assert(count == wanted, "Closed key set required: " .. label)
	end
	local function locate(path)
		local item = game
		for _, component in path:split("/") do
			local found
			for _, child in item:GetChildren() do
				if child.Name == component then
					assert(not found, "Ambiguous path: " .. path)
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
	local function identity(item)
		local ok, id = pcall(function()
			return item:GetDebugId(0)
		end)
		if ok then
			return tostring(id)
		end
		return tostring(item.UniqueId)
	end
	local function target()
		local run = game:GetService("RunService")
		assert(run:IsStudio() and not run:IsRunning(), "Stopped Studio Edit required")
		assert(
			game.Name == "Children_of_corn_B.rbxl" and game.PlaceId == 0 and game.GameId == 0,
			"Exact local B file required"
		)
		local map = assert(workspace:FindFirstChild("CornMap"), "CornMap required")
		assert(
			map:GetAttribute("corn_project_id") == "children_of_corn"
				and map:GetAttribute("HarvestArtVariant") == "B",
			"B project required"
		)
		assert(
			map:GetAttribute("BManualAuthoringVersion") == 1,
			"Manual authoring version required"
		)
		assert(
			map.Ground.Size == Vector3.new(630, 2, 630)
				and map.FieldZone.Size == Vector3.new(630, 10, 630),
			"Field changed"
		)
		local plants = assert(map:FindFirstChild("CornAuthoring"), "Assembled corn required")
		assert(
			plants == S.folder
				and plants:GetAttribute("Ready") == true
				and plants:GetAttribute("InitialPlantCount") == S.created,
			"Assembled corn identity/count changed"
		)
		assert(
			type(S.before) == "table"
				and S.before.sourceCount == 168
				and type(S.before.sources) == "table",
			"168-Source native baseline required"
		)
		assert(
			type(S.journal) == "table" and type(S.added) == "table",
			"Owned rollback journal required"
		)
	end
	local function sha(value)
		return type(value) == "string" and #value == 64 and value:match("^[0-9a-f]+$") ~= nil
	end
	local function compile(source, path)
		assert(
			type(source) == "string"
				and #source > 0
				and not source:find("\r", 1, true)
				and not source:find("\0", 1, true),
			"Exact LF Source required: " .. path
		)
		local compiled, problem = loadstring(source, "=" .. path)
		assert(compiled, "Source syntax refused: " .. path .. ": " .. tostring(problem))
	end
	target()
	exactKeys(
		payload,
		{
			version = true,
			owner = true,
			variant = true,
			baselineSha256 = true,
			beforeSourceCount = true,
			afterSourceCount = true,
			expectedBeforeSources = true,
			sourceChanges = true,
			newSources = true,
		},
		"payload"
	)
	assert(
		payload.version == 1
			and payload.owner == "CornBManualAuthoringV1"
			and payload.variant == "B",
		"Payload owner/version required"
	)
	assert(
		payload.baselineSha256 == "c91efe74d1750095eac19390800192ad03b264d7a99de46cf21d170fcb4ed31f"
			and payload.beforeSourceCount == 168
			and payload.afterSourceCount == 171,
		"Accepted baseline required"
	)
	exactKeys(payload.sourceChanges, CHANGED, "sourceChanges")
	exactKeys(payload.newSources, ADDED, "newSources")
	exactKeys(payload.expectedBeforeSources, S.before.sources, "expectedBeforeSources")
	local signatureRows = { payload.baselineSha256 }
	for _, path in keys(payload.expectedBeforeSources) do
		local row, before = payload.expectedBeforeSources[path], S.before.sources[path]
		exactKeys(row, { class = true, sha256 = true }, path)
		assert(
			sha(row.sha256) and row.sha256 == before.sha256 and row.class == before.class,
			"Independent native baseline differs: " .. path
		)
		table.insert(signatureRows, path .. "|" .. row.class .. "|" .. row.sha256)
	end
	assert(#signatureRows == 169, "All 168 old Sources required")
	for _, group in
		{
			{ rows = payload.sourceChanges, files = CHANGED, old = true },
			{ rows = payload.newSources, files = ADDED, old = false },
		}
	do
		for _, path in keys(group.rows) do
			local row = group.rows[path]
			local allowed = { class = true, file = true, sha256 = true, source = true }
			if group.old then
				allowed.beforeSha256 = true
			end
			exactKeys(row, allowed, path)
			assert(
				row.class == "ModuleScript"
					and row.file == group.files[path]
					and sha(row.sha256)
					and hash(row.source) == row.sha256,
				"Reviewed replacement pin differs: " .. path
			)
			if group.old then
				assert(
					row.beforeSha256 == payload.expectedBeforeSources[path].sha256
						and row.sha256 ~= row.beforeSha256,
					"Replacement before-pin differs: " .. path
				)
			else
				assert(not payload.expectedBeforeSources[path], "New Source already in baseline")
			end
			compile(row.source, path)
			table.insert(signatureRows, path .. "|" .. row.file .. "|" .. row.sha256)
		end
	end
	local signature = hash(table.concat(signatureRows, "\n"))
	if S.sourcesPayload then
		assert(
			S.phase == "sources-installed"
				and S.sourcesPayloadSignature == signature
				and type(S.verifySources) == "function",
			"Installed payload/state differs"
		)
		S.verifySources()
		return { installed = false, repeated = true, changedSources = 0, newSources = 0, totalSources = 171 }
	end
	assert(S.phase == "grouped", "Grouped world required before Source installation")
	local oldObjects, newObjects = {}, {}
	local function moduleDefaults(item)
		assert(
			item.ClassName == "ModuleScript"
				and item.Archivable == true
				and #item:GetChildren() == 0
				and #item:GetTags() == 0
				and next(item:GetAttributes()) == nil,
			"New Module must remain childless/default"
		)
	end
	local function verify(installed)
		target()
		local found, count = {}, 0
		for _, item in game:GetDescendants() do
			if item:IsA("LuaSourceContainer") then
				local path = item:GetFullName():gsub("%.", "/")
				assert(not found[path], "Duplicate Source path: " .. path)
				found[path] = true
				count += 1
				local row = (installed and payload.sourceChanges[path])
					or payload.expectedBeforeSources[path]
				row = row or (installed and payload.newSources[path])
				assert(
					row
						and row.class == item.ClassName
						and hash(normalized(item.Source)) == row.sha256,
					"Author Source preserved: " .. path
				)
				assert(
					normalized(editor:GetEditorSource(item)) == normalized(item.Source),
					"Unsaved editor buffer: " .. path
				)
				compile(normalized(item.Source), path)
				if payload.expectedBeforeSources[path] then
					assert(
						identity(item) == S.before.sources[path].id,
						"Old Source identity changed: " .. path
					)
					if oldObjects[path] then
						assert(
							item == oldObjects[path].item and item.Parent == oldObjects[path].parent,
							"Old Source identity/parent changed: " .. path
						)
					else
						oldObjects[path] = { item = item, parent = item.Parent }
					end
				else
					assert(
						installed and item == newObjects[path],
						"New Source identity changed: " .. path
					)
					moduleDefaults(item)
				end
			end
		end
		assert(count == (if installed then 171 else 168), "Complete Source graph required")
		for path in payload.expectedBeforeSources do
			assert(found[path], "Missing retained Source: " .. path)
		end
		for path in payload.newSources do
			assert(
				(not installed and not locate(path)) or (installed and found[path]),
				"New Source graph differs: " .. path
			)
		end
		for _, document in editor:GetScriptDocuments() do
			local item = document:GetScript()
			if item and item:IsDescendantOf(game) then
				assert(
					normalized(document:GetText()) == normalized(item.Source),
					"Unsaved open document: " .. item:GetFullName()
				)
			end
		end
		return {
			totalSources = count,
			retainedSources = 168,
			newSources = if installed then 3 else 0,
			editorBuffersExact = true,
		}
	end
	verify(false)
	local function freeze(value)
		for _, child in value do
			if type(child) == "table" then
				freeze(child)
			end
		end
		if not table.isfrozen(value) then
			table.freeze(value)
		end
	end
	freeze(payload)
	local journalStart, addedStart = #S.journal, #S.added
	local written, created = {}, {}
	local ok, problem = pcall(function()
		for _, path in keys(payload.newSources) do
			local row = payload.newSources[path]
			local item = Instance.new("ModuleScript")
			table.insert(created, { item = item, path = path })
			item.Name = path:match("([^/]+)$")
			item.Source = row.source
			moduleDefaults(item)
			newObjects[path] = item
		end
		verify(false)
		for _, path in keys(payload.sourceChanges) do
			local row, item = payload.sourceChanges[path], oldObjects[path].item
			local entry =
				{ item = item, property = "Source", before = item.Source, after = row.source }
			table.insert(written, entry)
			table.insert(S.journal, entry)
			item.Source = row.source
		end
		for _, path in keys(payload.newSources) do
			local parentPath = assert(path:match("^(.*)/[^/]+$"))
			local parent = assert(locate(parentPath), "New Module parent missing: " .. parentPath)
			assert(not locate(path), "New Module collision: " .. path)
			local item = newObjects[path]
			table.insert(S.added, item)
			item.Parent = parent
		end
		verify(true)
	end)
	if not ok then
		local failures = {}
		for index = #written, 1, -1 do
			local row = written[index]
			local restored, issue = pcall(function()
				assert(
					row.item.Source == row.after or row.item.Source == row.before,
					"Concurrent author Source preserved"
				)
				row.item.Source = row.before
			end)
			if not restored then
				table.insert(failures, tostring(issue))
			end
		end
		for _, record in created do
			local item, path = record.item, record.path
			local removed, issue = pcall(function()
				moduleDefaults(item)
				assert(
					item.Source == payload.newSources[path].source
						or (not item.Parent and item.Source == ""),
					"Concurrent new Module edit preserved"
				)
				item:Destroy()
			end)
			if not removed then
				table.insert(failures, tostring(issue))
			end
		end
		local restored, issue = pcall(function()
			verify(false)
		end)
		if not restored then
			table.insert(failures, tostring(issue))
		end
		if #failures == 0 then
			while #S.journal > journalStart do
				table.remove(S.journal)
			end
			while #S.added > addedStart do
				table.remove(S.added)
			end
		end
		error(
			"Source install rolled back: "
				.. tostring(problem)
				.. (
					if #failures > 0
						then "; rollback conflict: " .. table.concat(failures, "; ")
						else "; all 168 old Sources/editor buffers exact"
				)
		)
	end
	S.sourcesPayload = payload
	S.sourcesPayloadSignature = signature
	S.verifySources = function()
		return verify(true)
	end
	S.phase = "sources-installed"
	return {
		installed = true,
		changedSources = 8,
		newSources = 3,
		retainedSources = 168,
		totalSources = 171,
		journalSourceRows = #S.journal - journalStart,
		addedCodeNodes = #S.added - addedStart,
	}
end
