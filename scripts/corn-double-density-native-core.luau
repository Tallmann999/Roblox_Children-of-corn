-- Stopped verified B only: five exact existing Source replacements, no world writes.
return function(payload, options)
	options = options or {}
	local run = game:GetService("RunService")
	local function target()
		assert(run:IsStudio() and not run:IsRunning(), "Stopped Studio Edit required")
		assert(game.Name == "Children_of_corn_B.rbxl", "Corn B filename required")
		local map = workspace:FindFirstChild("CornMap")
		assert(
			map
				and map:IsA("Model")
				and map:GetAttribute("corn_project_id") == "children_of_corn"
				and map:GetAttribute("HarvestArtVariant") == "B",
			"Verified Corn B identity required"
		)
		assert(
			map.Ground.Size == Vector3.new(630, 2, 630)
				and map.FieldZone.Size == Vector3.new(630, 10, 630),
			"Corn field bounds changed"
		)
		return map
	end
	local map = target()
	assert(
		type(payload) == "table" and payload.owner == "corn_double_density_v1",
		"Unknown payload"
	)
	assert(
		type(payload.sources) == "table" and type(payload.sourceChanges) == "table",
		"Source manifests required"
	)
	assert(type(payload.changes) == "table" and #payload.changes == 0, "No world writes allowed")
	assert(type(payload.nodes) == "table" and #payload.nodes == 0, "No new nodes allowed")
	local allowed = {
		["ReplicatedStorage/GameShared/Game/CornLayout"] = true,
		["ReplicatedStorage/GameShared/Game/CornAppearance"] = true,
		["StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornController"] = true,
		["StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornBackdropController"] = true,
		["StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornWindController"] = true,
	}
	local function validHash(value)
		return type(value) == "string" and #value == 64 and not value:find("[^0-9a-f]")
	end
	local function hash(source)
		return (
			game:GetService("EncodingService")
				:ComputeStringHash(source:gsub("\r\n", "\n"), Enum.HashAlgorithm.Sha256)
				:gsub(".", function(b)
					return string.format("%02x", b:byte())
				end)
		)
	end
	local function sourceIndex()
		local result, count = {}, 0
		for _, item in game:GetDescendants() do
			if item:IsA("LuaSourceContainer") then
				local path = item:GetFullName():gsub("%.", "/")
				assert(not result[path], "Ambiguous Source path")
				result[path], count = item, count + 1
			end
		end
		assert(count == 157, "All 157 retained B Sources required")
		return result
	end
	local index = sourceIndex()
	local entries, byItem, guardCount = {}, {}, 0
	for path, row in payload.sources do
		assert(type(row) == "table" and validHash(row.sha256), "Invalid Source guard")
		local item = assert(index[path], "Missing Source: " .. tostring(path))
		assert(item.ClassName == row.class, "Source class changed")
		guardCount += 1
	end
	assert(guardCount == 157, "Exactly 157 Source guards required")
	for path, row in payload.sourceChanges do
		assert(
			allowed[path] and payload.sources[path] and index[path],
			"Unapproved Source replacement"
		)
		assert(
			type(row) == "table" and validHash(row.before_sha256) and validHash(row.after_sha256),
			"Invalid replacement hashes"
		)
		assert(
			row.before_sha256 == payload.sources[path].sha256
				and row.before_sha256 ~= row.after_sha256,
			"Wrong Source baseline/no-op"
		)
		assert(
			type(row.source) == "string"
				and row.source ~= ""
				and not row.source:find("\r", 1, true)
				and not row.source:find("\0", 1, true)
				and hash(row.source) == row.after_sha256,
			"Replacement bytes differ"
		)
		local item = index[path]
		assert(item.ClassName == "ModuleScript", "Only existing ModuleScripts allowed")
		local entry = { item = item, path = path, parent = item.Parent, row = row }
		entries[#entries + 1], byItem[item] = entry, entry
	end
	assert(#entries == 5, "Exactly five density/rendering Sources required")
	table.sort(entries, function(a, b)
		return a.path < b.path
	end)
	local function inspect()
		assert(target() == map, "Corn map identity changed")
		local current = sourceIndex()
		local before, after = true, true
		for path, row in payload.sources do
			local item = assert(current[path], "Missing retained Source")
			assert(
				item == index[path] and item.ClassName == row.class,
				"Source identity/class changed"
			)
			local actual = hash(item.Source)
			local change = payload.sourceChanges[path]
			if change then
				assert(item.Parent == byItem[item].parent, "Source parent changed")
				before = before and actual == change.before_sha256
				after = after and actual == change.after_sha256
			else
				assert(actual == row.sha256, "Author Source edit preserved: " .. path)
			end
		end
		for _, document in game:GetService("ScriptEditorService"):GetScriptDocuments() do
			assert(not byItem[document:GetScript()], "Close changed Source editor tab first")
		end
		assert(before or after, "Partial or author-edited Source state preserved")
		return if after then "installed" else "baseline"
	end
	local initial = inspect()
	if options.dryRun then
		return {
			dryRun = true,
			state = initial,
			retainedSources = 157,
			plannedSourceChanges = 5,
			worldChanges = 0,
			created = 0,
		}
	end
	if initial == "installed" then
		return { repeated = true, changedSources = 0, worldChanges = 0, created = 0 }
	end
	if options.prepareYield then
		options.prepareYield()
	end
	assert(inspect() == "baseline", "Source state changed before commit")
	local journal = {}
	local ok, problem = pcall(function()
		game:GetService("ChangeHistoryService")
			:SetWaypoint("Before Corn B doubled planting density")
		for i, entry in entries do
			journal[#journal + 1] = { item = entry.item, source = entry.item.Source }
			entry.item.Source = entry.row.source
			assert(
				hash(entry.item.Source) == entry.row.after_sha256,
				"Source write readback differs"
			)
			if options.failAfterWrites == i then
				error("Injected density Source failure")
			end
		end
		assert(inspect() == "installed", "Density Source verification failed")
	end)
	if not ok then
		local failures = {}
		for i = #journal, 1, -1 do
			local restored, failure = pcall(function()
				journal[i].item.Source = journal[i].source
			end)
			if not restored then
				failures[#failures + 1] = tostring(failure)
			end
		end
		local restored, failure = pcall(function()
			assert(inspect() == "baseline", "Source rollback verification failed")
		end)
		if not restored then
			failures[#failures + 1] = tostring(failure)
		end
		error(
			tostring(problem)
				.. (
					if #failures > 0
						then "; rollback errors: " .. table.concat(failures, "; ")
						else ""
				)
		)
	end
	game:GetService("ChangeHistoryService"):SetWaypoint("Corn B doubled planting density")
	return {
		repeated = false,
		changedSources = 5,
		retainedSources = 157,
		worldChanges = 0,
		created = 0,
	}
end
