-- Guarded B-only refinement: exact existing properties and five existing Sources.
-- No new instances, scene serialization, saving, or work outside Studio MCP.
return function(payload, options)
	options = options or {}
	local project, owner = "children_of_corn", "corn_edge_shadows_v1"
	assert(type(payload) == "table" and payload.owner == owner, "Unknown corn edge/shadow payload")
	local run = game:GetService("RunService")
	assert(run:IsStudio() and not run:IsRunning(), "Stopped Studio Edit required")
	assert(game.Name == "Children_of_corn_B.rbxl", "Verified B scene required")
	local pathIndex, selectorCache
	local function candidates(path)
		if not pathIndex then
			pathIndex = {}
			for _, item in game:GetDescendants() do
				-- Older snapshots flatten dots in real names, e.g. Coat.001.
				-- Keep every alias grouped so an ambiguous path is refused.
				local full = item:GetFullName():gsub("%.", "/")
				local siblings = pathIndex[full]
				if not siblings then
					siblings = {}
					pathIndex[full] = siblings
				end
				siblings[#siblings + 1] = item
			end
		end
		return pathIndex[path] or {}
	end
	local function validPath(path)
		return type(path) == "string"
			and path ~= ""
			and not path:find("//", 1, true)
			and not path:find(".", 1, true)
			and path:sub(1, 1) ~= "/"
			and path:sub(-1) ~= "/"
	end
	local decode
	local function selectorMatches(item, selector)
		assert(
			type(selector) == "table" and next(selector) ~= nil,
			"Nonempty exact selector required"
		)
		for property, value in selector do
			assert(
				type(property) == "string" and property ~= "Parent" and property ~= "Source",
				"Invalid selector property"
			)
			if item[property] ~= decode(value, item[property]) then
				return false
			end
		end
		return true
	end
	local function selectedChildren(path, selector, installedSelector)
		local property = next(selector)
		assert(type(property) == "string", "Nonempty exact selector required")
		local siblings = candidates(path)
		if #siblings == 0 then
			return siblings
		end
		selectorCache = selectorCache or {}
		local nameIndex = selectorCache[path]
		if not nameIndex then
			nameIndex = {}
			selectorCache[path] = nameIndex
		end
		local buckets = nameIndex[property]
		if not buckets then
			buckets = {}
			for _, child in siblings do
				local key = tostring(child[property])
				local bucket = buckets[key]
				if not bucket then
					bucket = {}
					buckets[key] = bucket
				end
				bucket[#bucket + 1] = child
			end
			nameIndex[property] = buckets
		end
		local selected, seen = {}, {}
		for _, values in { selector, installedSelector } do
			if values and values[property] ~= nil then
				local key = tostring(decode(values[property], siblings[1][property]))
				for _, child in buckets[key] or {} do
					if not seen[child] then
						selected[#selected + 1] = child
						seen[child] = true
					end
				end
			end
		end
		-- String buckets only accelerate selection. Every candidate is still
		-- compared by exact native values below, so collisions never select it.
		return selected
	end
	local function resolve(path, selector, installedSelector)
		assert(validPath(path), "Invalid absolute instance path")
		local result
		for _, item in
			(if selector
				then selectedChildren(path, selector, installedSelector)
				else candidates(path))
		do
			if
				not selector
				or selectorMatches(item, selector)
				or (installedSelector and selectorMatches(item, installedSelector))
			then
				assert(not result, "Ambiguous full instance path/selector: " .. path)
				result = item
			end
		end
		return result
	end
	local map = assert(resolve("Workspace/CornMap"), "CornMap missing")
	assert(
		map:IsA("Model")
			and map:GetAttribute("corn_project_id") == project
			and map:GetAttribute("HarvestArtVariant") == "B",
		"Wrong Corn B identity"
	)
	assert(
		resolve("Workspace/CornMap/Ground").Size == Vector3.new(630, 2, 630)
			and resolve("Workspace/CornMap/FieldZone").Size == Vector3.new(630, 10, 630),
		"World bounds changed"
	)
	local function finite(number)
		return type(number) == "number" and number == number and math.abs(number) < math.huge
	end
	decode = function(value, current)
		if type(value) ~= "table" then
			assert(
				type(value) == "string" or type(value) == "boolean" or finite(value),
				"Invalid scalar value"
			)
			if typeof(current) == "EnumItem" and type(value) == "string" then
				return assert(current.EnumType[value], "Unknown enum name")
			end
			return value
		end
		local kind, values = value.kind, value.value
		if kind == "Nil" then
			return nil
		end
		assert(type(values) == "table", "Typed value array required")
		if kind == "Enum" then
			assert(
				#values == 2 and type(values[1]) == "string" and type(values[2]) == "string",
				"Invalid enum"
			)
			return assert(Enum[values[1]][values[2]], "Unknown enum")
		end
		local count = ({ CFrame = 12, Vector3 = 3, Color3 = 3 })[kind]
		assert(count and #values == count, "Unknown typed value or component count")
		for _, number in values do
			assert(finite(number), "Nonfinite typed value")
		end
		if kind == "CFrame" then
			return CFrame.new(table.unpack(values))
		end
		if kind == "Vector3" then
			return Vector3.new(table.unpack(values))
		end
		return Color3.new(table.unpack(values))
	end
	local function same(a, b)
		if typeof(a) == "UniqueId" and type(b) == "string" then
			return tostring(a) == b
		end
		return a == b
	end
	local function exactTags(item, expected)
		local actual, wanted = item:GetTags(), {}
		assert(type(expected) == "table", "Tags array required")
		for _, tag in expected do
			assert(type(tag) == "string" and not wanted[tag], "Duplicate/invalid tag")
			wanted[tag] = true
		end
		if #actual ~= #expected then
			return false
		end
		for _, tag in actual do
			if not wanted[tag] then
				return false
			end
		end
		return true
	end
	local encoding = game:GetService("EncodingService")
	local function hash(source)
		local bytes =
			encoding:ComputeStringHash(source:gsub("\r\n", "\n"), Enum.HashAlgorithm.Sha256)
		return (
			bytes:gsub(".", function(byte)
				return string.format("%02x", string.byte(byte))
			end)
		)
	end
	local allowedSources = {
		["ReplicatedStorage/GameShared/Game/CornLayout"] = true,
		["StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornController"] = true,
		["StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornBackdropController"] = true,
		["ReplicatedStorage/GameShared/Game/CornAppearance"] = true,
		["ReplicatedStorage/GameShared/Game/HarvestWardenVisual"] = true,
	}
	local function validHash(value)
		return type(value) == "string" and #value == 64 and not value:find("[^0-9a-f]")
	end
	assert(
		type(payload.sources) == "table" and type(payload.sourceChanges) == "table",
		"Source manifests required"
	)
	assert(
		type(payload.changes) == "table" and type(payload.guards) == "table",
		"World manifests required"
	)
	assert(payload.nodes == nil or #payload.nodes == 0, "No new nodes allowed")
	local sourceChanges, sourceByItem, sourceCount = {}, {}, 0
	for path, row in payload.sources do
		assert(
			validPath(path) and type(row) == "table" and validHash(row.sha256),
			"Invalid Source guard"
		)
		assert(
			row.class == "ModuleScript" or row.class == "LocalScript" or row.class == "Script",
			"Invalid Source class"
		)
		sourceCount += 1
	end
	assert(sourceCount == 157, "All 157 accepted B Sources required")
	for path, row in payload.sourceChanges do
		local original = payload.sources[path]
		assert(
			allowedSources[path] and original and original.class == "ModuleScript",
			"Unapproved Source target"
		)
		assert(
			type(row) == "table" and validHash(row.before_sha256) and validHash(row.after_sha256),
			"Invalid Source hashes"
		)
		assert(
			row.before_sha256 == original.sha256 and row.before_sha256 ~= row.after_sha256,
			"Source before guard differs/no-op"
		)
		assert(
			type(row.source) == "string"
				and row.source ~= ""
				and not row.source:find("\r", 1, true)
				and not row.source:find("\0", 1, true)
				and hash(row.source) == row.after_sha256,
			"New Source bytes differ"
		)
		local item = assert(resolve(path), "Source target missing")
		assert(item.ClassName == "ModuleScript", "Changed Source class")
		local entry = { path = path, row = row, item = item, parent = item.Parent }
		sourceChanges[#sourceChanges + 1], sourceByItem[item] = entry, entry
	end
	assert(#sourceChanges == 5, "Exactly the five approved presentation Sources required")
	table.sort(sourceChanges, function(a, b)
		return a.path < b.path
	end)
	local function sourcePreflight()
		local before, after, seen, count = true, true, {}, 0
		for _, item in game:GetDescendants() do
			if item:IsA("LuaSourceContainer") then
				local path = item:GetFullName():gsub("%.", "/")
				assert(not seen[path], "Duplicate persistent Source path")
				local guard = assert(payload.sources[path], "Unknown Source preserved: " .. path)
				assert(item.ClassName == guard.class, "Changed persistent Source class")
				seen[path], count = true, count + 1
				local current = hash(item.Source)
				local change = payload.sourceChanges[path]
				if change then
					local entry = sourceByItem[item]
					assert(
						entry and entry.path == path and item.Parent == entry.parent,
						"Source identity/parent changed"
					)
					before = before and current == change.before_sha256
					after = after and current == change.after_sha256
				else
					assert(current == guard.sha256, "Author Source edit preserved: " .. path)
				end
			end
		end
		assert(count == 157, "Persistent Source count differs")
		for path in payload.sources do
			assert(seen[path], "Missing retained Source: " .. path)
		end
		for _, document in game:GetService("ScriptEditorService"):GetScriptDocuments() do
			assert(
				not sourceByItem[document:GetScript()],
				"Close changed Source editor tab before installation"
			)
		end
		return before, after
	end
	local function selectorKey(row)
		if not row.selector then
			return ""
		end
		local fields = {}
		for property, value in row.selector do
			fields[#fields + 1] = property .. "=" .. tostring(decode(value))
		end
		table.sort(fields)
		return "[" .. table.concat(fields, "|") .. "]"
	end
	local protected = {
		Name = true,
		Parent = true,
		ClassName = true,
		UniqueId = true,
		Source = true,
		ScriptGuid = true,
		HistoryId = true,
		Capabilities = true,
		DefinesCapabilities = true,
		SerializedOverrides = true,
		SourceAssetId = true,
		AttributesSerialize = true,
		Tags = true,
	}
	local changes, byItem, changeKeys = {}, {}, {}
	for _, row in payload.changes do
		assert(
			type(row) == "table" and validPath(row.path) and row.path:sub(1, 10) == "Workspace/",
			"World change outside Workspace"
		)
		assert(
			type(row.property) == "string"
				and row.property ~= ""
				and type(row.attribute) == "boolean",
			"Invalid world change"
		)
		assert(
			row.attribute or not protected[row.property],
			"Protected identity/Source write forbidden"
		)
		assert(
			(
				row.path
					== "Workspace/CornMap/Props/ScarecrowMarker/HarvestWardenHome/Detailed/LeftEye/001_Material1"
				or row.path
					== "Workspace/CornMap/Props/ScarecrowMarker/HarvestWardenHome/Detailed/RightEye/001_Material1"
			)
				and ((not row.attribute and row.property == "Transparency") or (row.attribute and row.property == "HarvestVisibleTransparency"))
				and row.before == 0
				and row.after == 1
				and not row.selector,
			"Only the four exact red-eye visibility changes are approved"
		)
		local item = assert(
			resolve(row.path, row.selector, row.installedSelector),
			"World change target missing"
		)
		assert(not item:IsA("LuaSourceContainer"), "World change cannot modify Source containers")
		local actual = if row.attribute then item:GetAttribute(row.property) else item[row.property]
		local before, after = decode(row.before, actual), decode(row.after, actual)
		assert(not same(before, after), "No-op world change must be omitted")
		local key = row.path
			.. selectorKey(row)
			.. (if row.attribute then "/@" else "/$")
			.. row.property
		assert(not changeKeys[key], "Duplicate world change")
		local entry =
			{ row = row, item = item, parent = item.Parent, before = before, after = after }
		local group = byItem[item]
		if not group then
			group = {}
			byItem[item] = group
		end
		local groupKey = (if row.attribute then "@" else "$") .. row.property
		assert(not group[groupKey], "Aliased duplicate world write")
		changes[#changes + 1], changeKeys[key], group[groupKey] = entry, entry, entry
	end
	assert(#changes == 4, "Exactly four eye visibility changes required")
	local guards, guardedItems = {}, {}
	for _, row in payload.guards do
		assert(
			type(row) == "table"
				and validPath(row.path)
				and type(row.properties) == "table"
				and type(row.attributes) == "table"
				and type(row.tags) == "table",
			"Invalid world guard"
		)
		local item = assert(
			resolve(row.path, row.selector, row.installedSelector),
			"Guarded author node missing"
		)
		assert(not guardedItems[item], "Duplicate/aliased world guard")
		local entry = { row = row, item = item, parent = item.Parent }
		guards[#guards + 1], guardedItems[item] = entry, entry
	end
	assert(#guards > 0 and #guards <= 6000, "Unbounded/empty guards")
	for _, entry in changes do
		local guard = assert(guardedItems[entry.item], "Changed world node lacks complete guard")
		assert(
			entry.row.attribute or guard.row.properties[entry.row.property] ~= nil,
			"Changed property not covered by guard"
		)
	end
	local function guardMatches(guard, phase)
		local item, row = guard.item, guard.row
		assert(
			item.ClassName == row.class
				and item.Parent == guard.parent
				and exactTags(item, row.tags),
			"Author class/parent/tags changed"
		)
		local group = byItem[item] or {}
		for property, value in row.properties do
			local entry = group["$" .. property]
			local expected = if entry then entry[phase] else decode(value, item[property])
			assert(
				same(item[property], expected),
				"Author property changed: " .. row.path .. "/" .. property
			)
		end
		local actual, expectedNames = item:GetAttributes(), {}
		for name, value in row.attributes do
			local entry = group["@" .. name]
			local expected = if entry then entry[phase] else decode(value, actual[name])
			if expected ~= nil then
				expectedNames[name] = true
			end
			assert(
				same(actual[name], expected),
				"Author attribute changed: " .. row.path .. "/" .. name
			)
		end
		for key, entry in group do
			if key:sub(1, 1) == "@" and row.attributes[entry.row.property] == nil then
				local expected = entry[phase]
				if expected ~= nil then
					expectedNames[entry.row.property] = true
				end
				assert(same(actual[entry.row.property], expected), "Added attribute differs")
			end
		end
		for name in actual do
			assert(expectedNames[name], "Unknown author attribute preserved")
		end
	end
	local function inspect()
		pathIndex, selectorCache = nil, nil
		assert(
			run:IsStudio() and not run:IsRunning() and game.Name == "Children_of_corn_B.rbxl",
			"Studio state changed"
		)
		assert(
			resolve("Workspace/CornMap") == map
				and map:GetAttribute("corn_project_id") == project
				and map:GetAttribute("HarvestArtVariant") == "B",
			"Corn B identity changed"
		)
		assert(
			resolve("Workspace/CornMap/Ground").Size == Vector3.new(630, 2, 630)
				and resolve("Workspace/CornMap/FieldZone").Size == Vector3.new(630, 10, 630),
			"World dimensions changed"
		)
		local before, after = sourcePreflight()
		for _, entry in changes do
			local row, item = entry.row, entry.item
			assert(
				resolve(row.path, row.selector, row.installedSelector) == item
					and item.Parent == entry.parent,
				"World identity changed"
			)
			local actual = if row.attribute
				then item:GetAttribute(row.property)
				else item[row.property]
			before = before and same(actual, entry.before)
			after = after and same(actual, entry.after)
		end
		assert(before or after, "Partial/unknown Source or world state preserved")
		local phase = if after then "after" else "before"
		for _, guard in guards do
			assert(
				resolve(guard.row.path, guard.row.selector, guard.row.installedSelector)
					== guard.item,
				"Guarded node identity changed"
			)
			guardMatches(guard, phase)
		end
		if payload.expectedWorkspaceDescendants ~= nil then
			local count = #assert(resolve("Workspace")):GetDescendants()
			assert(count == payload.expectedWorkspaceDescendants, "Workspace topology changed")
		end
		return if after then "installed" else "baseline"
	end
	local initial = inspect()
	if options.dryRun then
		return {
			dryRun = true,
			state = initial,
			plannedChanges = #changes,
			plannedSourceChanges = #sourceChanges,
			guardedInstances = #guards,
			retainedSources = 157,
			created = 0,
		}
	end
	if initial == "installed" then
		return { created = 0, changedProperties = 0, changedSources = 0, repeated = true }
	end
	-- Any preparation callback/yield precedes a complete fresh inspection. The
	-- actual Source and property commit below has no explicit yield points.
	if options.prepareYield then
		options.prepareYield()
	end
	assert(inspect() == "baseline", "World changed before commit")
	local journal, writes = {}, 0
	local function wrote()
		writes += 1
		if options.failAfterWrites == writes then
			error("Injected corn edge/shadow transaction failure")
		end
	end
	local ok, problem = pcall(function()
		game:GetService("ChangeHistoryService")
			:SetWaypoint("Before Corn B trail edges and static corn shadows")
		for _, entry in sourceChanges do
			journal[#journal + 1] = { source = true, item = entry.item, before = entry.item.Source }
			entry.item.Source = entry.row.source
			assert(
				hash(entry.item.Source) == entry.row.after_sha256,
				"Source write readback differs"
			)
			wrote()
		end
		for _, entry in changes do
			journal[#journal + 1] = entry
			if entry.row.attribute then
				entry.item:SetAttribute(entry.row.property, entry.after)
			else
				entry.item[entry.row.property] = entry.after
			end
			wrote()
		end
		assert(inspect() == "installed", "Corn edge/shadow readback differs")
	end)
	if not ok then
		local failures = {}
		for index = #journal, 1, -1 do
			local entry = journal[index]
			local restored, failure = pcall(function()
				if entry.source then
					entry.item.Source = entry.before
				elseif entry.row.attribute then
					entry.item:SetAttribute(entry.row.property, entry.before)
				else
					entry.item[entry.row.property] = entry.before
				end
			end)
			if not restored then
				failures[#failures + 1] = tostring(failure)
			end
		end
		local restored, failure = pcall(function()
			assert(inspect() == "baseline", "Rollback state differs")
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
	game:GetService("ChangeHistoryService")
		:SetWaypoint("Corn B trail edges and static corn shadows")
	return {
		created = 0,
		changedProperties = #changes,
		changedSources = #sourceChanges,
		retainedSources = 157,
		repeated = false,
	}
end
