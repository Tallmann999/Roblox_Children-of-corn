-- MCP-only replacement of already installed B authoring Sources.
-- Keeps all 171 code identities and every world node; no Save or serialization.
-- selene: allow(global_usage)
return function(payload)
	local S = assert(_G.__CornBManualAuthoringV1, "Installed manual B required")
	assert(
		S.phase == "sources-installed" and type(S.verifySources) == "function" and S.sourcesPayload,
		"Verified installed Sources required"
	)
	local previous = {
		payload = S.sourcesPayload,
		signature = S.sourcesPayloadSignature,
		verify = S.verifySources,
		phase = S.phase,
	}
	-- The existing accepted 171-Source guard and its editor-buffer checks run first.
	local prior = previous.verify()
	assert(prior.totalSources == 171, "Prior 171-Source acceptance required")
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
	local editor, encoding =
		game:GetService("ScriptEditorService"), game:GetService("EncodingService")
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
	local function exact(value, expected, label)
		assert(
			type(value) == "table" and getmetatable(value) == nil,
			"Plain table required: " .. label
		)
		local count, wanted = 0, 0
		for key in value do
			assert(expected[key], "Unexpected key: " .. label .. "/" .. tostring(key))
			count += 1
		end
		for key in expected do
			assert(value[key] ~= nil, "Missing key: " .. label .. "/" .. key)
			wanted += 1
		end
		assert(count == wanted, "Closed key set required: " .. label)
	end
	local function sha(value)
		return type(value) == "string" and #value == 64 and value:match("^[0-9a-f]+$") ~= nil
	end
	local function identity(item)
		local ok, id = pcall(function()
			return item:GetDebugId(0)
		end)
		return if ok then tostring(id) else tostring(item.UniqueId)
	end
	local function target()
		local run = game:GetService("RunService")
		assert(run:IsStudio() and not run:IsRunning(), "Stopped Studio Edit required")
		assert(
			game.Name == "Children_of_corn_B.rbxl" and game.PlaceId == 0 and game.GameId == 0,
			"Exact local B required"
		)
		local map = assert(workspace:FindFirstChild("CornMap"), "CornMap required")
		assert(
			map:GetAttribute("corn_project_id") == "children_of_corn"
				and map:GetAttribute("HarvestArtVariant") == "B"
				and map:GetAttribute("BManualAuthoringVersion") == 1,
			"B project/version required"
		)
		assert(
			map.Ground.Size == Vector3.new(630, 2, 630)
				and map.FieldZone.Size == Vector3.new(630, 10, 630),
			"Field changed"
		)
		-- Source acceptance is independent of the separately approved world-pool move.
		assert(
			S.folder
				and S.folder.Parent
				and S.folder:GetAttribute("Ready") == true
				and S.folder:GetAttribute("InitialPlantCount") == S.created,
			"Owned authored corn changed"
		)
		assert(
			S.before.sourceCount == 168
				and type(S.before.sources) == "table"
				and type(S.journal) == "table"
				and type(S.added) == "table",
			"Owned original baseline/journal required"
		)
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
	exact(
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
			and payload.variant == "B"
			and payload.baselineSha256 == "c91efe74d1750095eac19390800192ad03b264d7a99de46cf21d170fcb4ed31f"
			and payload.beforeSourceCount == 168
			and payload.afterSourceCount == 171,
		"Accepted payload baseline required"
	)
	exact(payload.expectedBeforeSources, S.before.sources, "expectedBeforeSources")
	exact(payload.sourceChanges, CHANGED, "sourceChanges")
	exact(payload.newSources, ADDED, "newSources")
	local rows = { payload.baselineSha256 }
	local expected = {}
	for _, path in keys(payload.expectedBeforeSources) do
		local row, before, old =
			payload.expectedBeforeSources[path],
			S.before.sources[path],
			previous.payload.expectedBeforeSources[path]
		exact(row, { class = true, sha256 = true }, path)
		assert(
			old
				and row.class == before.class
				and row.class == old.class
				and sha(row.sha256)
				and row.sha256 == before.sha256
				and row.sha256 == old.sha256,
			"Original Source baseline differs: " .. path
		)
		expected[path] = row
		table.insert(rows, path .. "|" .. row.class .. "|" .. row.sha256)
	end
	assert(#rows == 169, "All 168 original Sources required")
	for _, group in
		{
			{
				rows = payload.sourceChanges,
				oldRows = previous.payload.sourceChanges,
				files = CHANGED,
				old = true,
			},
			{ rows = payload.newSources, oldRows = previous.payload.newSources, files = ADDED, old = false },
		}
	do
		exact(group.rows, group.oldRows, "Installed change topology")
		for _, path in keys(group.rows) do
			local row, old = group.rows[path], group.oldRows[path]
			local allowed = { class = true, file = true, sha256 = true, source = true }
			if group.old then
				allowed.beforeSha256 = true
			end
			exact(row, allowed, path)
			assert(
				row.class == "ModuleScript"
					and row.class == old.class
					and row.file == group.files[path]
					and row.file == old.file
					and sha(row.sha256)
					and hash(row.source) == row.sha256,
				"New Source pin/file differs: " .. path
			)
			if group.old then
				assert(
					row.beforeSha256 == payload.expectedBeforeSources[path].sha256
						and row.beforeSha256 == old.beforeSha256
						and row.sha256 ~= row.beforeSha256,
					"Original before-pin changed: " .. path
				)
			else
				assert(
					not payload.expectedBeforeSources[path],
					"New Source moved into original baseline"
				)
			end
			compile(row.source, path)
			expected[path] = row
			table.insert(rows, path .. "|" .. row.file .. "|" .. row.sha256)
		end
	end
	local signature = hash(table.concat(rows, "\n"))
	if signature == previous.signature then
		return { upgraded = false, repeated = true, changedSources = 0, newNodes = 0, totalSources = 171 }
	end
	local objects = {}
	local function priorRow(path)
		return previous.payload.sourceChanges[path]
			or previous.payload.expectedBeforeSources[path]
			or previous.payload.newSources[path]
	end
	for _, item in game:GetDescendants() do
		if item:IsA("LuaSourceContainer") then
			local path = item:GetFullName():gsub("%.", "/")
			local row = assert(priorRow(path), "Unreviewed prior Source: " .. path)
			assert(
				not objects[path]
					and item.ClassName == row.class
					and hash(normalized(item.Source)) == row.sha256,
				"Prior Source changed: " .. path
			)
			objects[path] = {
				item = item,
				parent = item.Parent,
				id = identity(item),
				name = item.Name,
				before = item.Source,
			}
		end
	end
	exact(objects, expected, "Current installed Source identities")
	local function verify()
		target()
		local found, count = {}, 0
		for _, item in game:GetDescendants() do
			if item:IsA("LuaSourceContainer") then
				local path = item:GetFullName():gsub("%.", "/")
				local row, old = expected[path], objects[path]
				assert(not found[path] and row and old, "Unexpected/missing Source: " .. path)
				assert(
					item == old.item
						and identity(item) == old.id
						and item.Parent == old.parent
						and item.Name == old.name
						and item.ClassName == row.class,
					"Code identity/parent changed: " .. path
				)
				assert(
					hash(normalized(item.Source)) == row.sha256
						and normalized(editor:GetEditorSource(item)) == normalized(item.Source),
					"Source/editor buffer changed: " .. path
				)
				if ADDED[path] then
					assert(
						item.Archivable
							and #item:GetChildren() == 0
							and #item:GetTags() == 0
							and next(item:GetAttributes()) == nil,
						"New Module metadata changed: " .. path
					)
				end
				compile(normalized(item.Source), path)
				found[path] = true
				count += 1
			end
		end
		exact(found, expected, "Complete installed Source graph")
		assert(count == 171, "All 171 Sources required")
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
			totalSources = 171,
			retainedSources = 168,
			newSources = 3,
			editorBuffersExact = true,
			allCodeIdentitiesRetained = true,
		}
	end
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
	local planned = {}
	for _, path in keys(objects) do
		local old, row = objects[path], expected[path]
		if normalized(old.before) ~= (row.source or normalized(old.before)) then
			assert(CHANGED[path] or ADDED[path], "Unreviewed Source upgrade: " .. path)
			table.insert(
				planned,
				{ item = old.item, property = "Source", before = old.before, after = row.source, path = path }
			)
		end
	end
	assert(#planned > 0 and #planned <= 11, "Upgrade differences required")
	previous.verify()
	local journalStart, addedStart = #S.journal, #S.added
	local written = {}
	local ok, problem = pcall(function()
		for _, row in planned do
			assert(
				row.item.Source == row.before,
				"Concurrent author Source preserved: " .. row.path
			)
			table.insert(written, row)
			table.insert(S.journal, row)
			row.item.Source = row.after
		end
		verify()
		assert(#S.added == addedStart, "Upgrade must not add nodes")
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
		local restored, issue = pcall(previous.verify)
		if not restored then
			table.insert(failures, tostring(issue))
		end
		if #failures == 0 then
			while #S.journal > journalStart do
				table.remove(S.journal)
			end
		end
		assert(
			S.phase == previous.phase
				and S.sourcesPayload == previous.payload
				and S.verifySources == previous.verify,
			"Prior acceptance state changed during failed upgrade"
		)
		error(
			"Source upgrade rolled back: "
				.. tostring(problem)
				.. (
					if #failures > 0
						then "; rollback conflict: " .. table.concat(failures, "; ")
						else "; previous 171 Sources exact"
				)
		)
	end
	S.sourcesPayload = payload
	S.sourcesPayloadSignature = signature
	S.verifySources = verify
	return {
		upgraded = true,
		changedSources = #written,
		newNodes = 0,
		totalSources = 171,
		journalSourceRows = #S.journal - journalStart,
		allCodeIdentitiesRetained = true,
		previousSignature = previous.signature,
		payloadSignature = signature,
	}
end
