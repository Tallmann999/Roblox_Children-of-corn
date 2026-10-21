-- Narrow B-only world transaction. The caller supplies an independently reviewed payload.
-- This factory never saves a scene, replaces a Source, or operates outside Studio MCP.
return function(payload, options)
	options = options or {}
	local project, owner = "children_of_corn", "corn_maze02_v1"
	assert(type(payload) == "table" and payload.owner == owner, "Unknown maze payload")
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
	local shadowPath =
		"StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornShadowController"
	local shadowHash = "1a2a933017b2b0b4680bbafef5323ee3a67e44c8caa1ce1014f159b0861334be"
	local function sourcePreflight()
		local seen, expectedCount, originalCount = {}, 0, 0
		for path, entry in payload.sources do
			assert(
				validPath(path) and type(entry) == "table" and type(entry.sha256) == "string",
				"Invalid Source manifest"
			)
			expectedCount += 1
			if path ~= shadowPath then
				originalCount += 1
			else
				assert(
					entry.class == "ModuleScript" and entry.sha256 == shadowHash,
					"Unknown shadow Source"
				)
			end
		end
		assert(
			originalCount == 156 and (expectedCount == 156 or expectedCount == 157),
			"Expected 156 retained B Sources"
		)
		for _, item in game:GetDescendants() do
			if item:IsA("LuaSourceContainer") then
				local path = item:GetFullName():gsub("%.", "/")
				assert(not seen[path], "Duplicate persistent Source path")
				seen[path] = true
				local expected = payload.sources[path]
				if not expected and path == shadowPath then
					expected = { class = "ModuleScript", sha256 = shadowHash }
				end
				assert(
					expected
						and item.ClassName == expected.class
						and hash(item.Source) == expected.sha256,
					"Unknown/edited Source preserved: " .. path
				)
				if path == shadowPath then
					assert(
						#item:GetChildren() == 0
							and #item:GetTags() == 0
							and next(item:GetAttributes()) == nil
							and item.Archivable,
						"Edited shadow metadata preserved"
					)
				end
			end
		end
		for path in payload.sources do
			assert(seen[path], "Missing retained Source: " .. path)
		end
	end
	local selectorKeys = {}
	local function selectorKey(row)
		if selectorKeys[row] then
			return selectorKeys[row]
		end
		if not row.selector then
			return ""
		end
		local parts = {}
		for property, value in row.selector do
			parts[#parts + 1] = property .. "=" .. tostring(decode(value))
		end
		table.sort(parts)
		local result = "[" .. table.concat(parts, "|") .. "]"
		selectorKeys[row] = result
		return result
	end
	local changes, changeKeys, attributeChanges = {}, {}, {}
	assert(
		type(payload.changes) == "table" and type(payload.nodes) == "table",
		"World manifest required"
	)
	local protected = {
		Name = true,
		Parent = true,
		ClassName = true,
		UniqueId = true,
		Source = true,
		ScriptGuid = true,
	}
	for _, row in payload.changes do
		assert(
			type(row) == "table"
				and validPath(row.path)
				and type(row.property) == "string"
				and row.property ~= ""
				and type(row.attribute) == "boolean",
			"Invalid retained change"
		)
		assert(
			row.path == "Workspace/CornMap" or row.path:sub(1, 18) == "Workspace/CornMap/",
			"Change outside CornMap"
		)
		assert(row.attribute or not protected[row.property], "Identity/Source writes forbidden")
		local key = row.path
			.. selectorKey(row)
			.. "/"
			.. (if row.attribute then "@" else "$")
			.. row.property
		assert(not changeKeys[key], "Duplicate retained change")
		local item = assert(
			resolve(row.path, row.selector, row.installedSelector),
			"Retained change target missing"
		)
		assert(not item:IsA("LuaSourceContainer"), "Source containers are retained")
		local current = if row.attribute
			then item:GetAttribute(row.property)
			else item[row.property]
		local before, after = decode(row.before, current), decode(row.after, current)
		assert(not same(before, after), "No-op change must be omitted")
		local entry = { item = item, row = row, before = before, after = after, key = key }
		changes[#changes + 1], changeKeys[key] = entry, entry
		if row.attribute then
			local identityKey = row.path .. selectorKey(row)
			local group = attributeChanges[identityKey]
			if not group then
				group = {}
				attributeChanges[identityKey] = group
			end
			group[#group + 1] = entry
		end
	end
	local roots = {
		"Workspace/CornMap/Maze02",
		"Workspace/CornMap/NoCornZones/Maze02Masks",
		"Workspace/CornMap/Props/VillageRoad/Maze02Trails",
	}
	local function allowedNewPath(path)
		for _, root in roots do
			if path == root or path:sub(1, #root + 1) == root .. "/" then
				return true
			end
		end
		return false
	end
	local classes =
		{ Folder = true, Model = true, Part = true, WedgePart = true, CornerWedgePart = true }
	local nodes, byPath, rootPaths = {}, {}, {}
	for _, row in payload.nodes do
		assert(
			type(row) == "table"
				and validPath(row.path)
				and allowedNewPath(row.path)
				and classes[row.class]
				and not byPath[row.path],
			"Unknown/duplicate new world node"
		)
		assert(
			type(row.properties) == "table"
				and type(row.attributes) == "table"
				and row.attributes.corn_project_id == project
				and row.attributes.CornMazeOwner == owner,
			"New node ownership metadata required"
		)
		for property in row.properties do
			assert(not protected[property], "New node identity/Source property forbidden")
		end
		local parentPath, name = row.path:match("^(.*)/([^/]+)$")
		local entry = { row = row, parentPath = parentPath, name = name }
		nodes[#nodes + 1], byPath[row.path] = entry, entry
	end
	assert(#nodes > 0 and #nodes <= 4096 and #changes <= 8192, "Unbounded maze transaction")
	table.sort(nodes, function(a, b)
		return a.row.path < b.row.path
	end)
	for _, entry in nodes do
		for _, rootPath in roots do
			if entry.row.path:sub(1, #rootPath + 1) == rootPath .. "/" then
				assert(byPath[rootPath], "Entire new owned root must be declared")
			end
		end
	end
	for _, entry in nodes do
		assert(
			byPath[entry.parentPath] or resolve(entry.parentPath),
			"New node parent undeclared/missing"
		)
		if not byPath[entry.parentPath] then
			entry.retainedParent = resolve(entry.parentPath)
			rootPaths[#rootPaths + 1] = entry.row.path
		end
	end
	local function propertiesMatch(item, row, phase)
		if item.ClassName ~= row.class or not exactTags(item, row.tags) then
			return false, "class/tags"
		end
		local actualAttrs = item:GetAttributes()
		local count, actualCount = 0, 0
		local identityKey = row.path .. selectorKey(row)
		for property, value in row.properties do
			local key = identityKey .. "/$" .. property
			local changed = changeKeys[key]
			local expected = if changed then changed[phase] else decode(value, item[property])
			if not same(item[property], expected) then
				return false,
					"property "
						.. property
						.. ": "
						.. tostring(item[property])
						.. " ~= "
						.. tostring(expected)
			end
		end
		for name, value in row.attributes do
			local changed = changeKeys[identityKey .. "/@" .. name]
			local expected = if changed then changed[phase] else decode(value, actualAttrs[name])
			if expected ~= nil then
				count += 1
			end
			if not same(actualAttrs[name], expected) then
				return false,
					"attribute "
						.. name
						.. ": "
						.. tostring(actualAttrs[name])
						.. " ~= "
						.. tostring(expected)
			end
		end
		for _, changed in attributeChanges[identityKey] or {} do
			if row.attributes[changed.row.property] == nil then
				local expected = changed[phase]
				if expected ~= nil then
					count += 1
					if not same(actualAttrs[changed.row.property], expected) then
						return false, "added attribute " .. changed.row.property
					end
				end
			end
		end
		for _ in actualAttrs do
			actualCount += 1
		end
		return count == actualCount, "attribute count"
	end
	local guards = {}
	for _, row in payload.guards or {} do
		guards[#guards + 1] = {
			row = row,
			item = assert(
				resolve(row.path, row.selector, row.installedSelector),
				"Guarded author node missing: " .. row.path .. selectorKey(row)
			),
		}
	end
	local function guardsMatch(phase)
		for _, guard in guards do
			local row, item = guard.row, guard.item
			assert(
				resolve(row.path, row.selector, row.installedSelector) == item,
				"Guarded author identity changed"
			)
			local matches, reason = propertiesMatch(item, row, phase)
			assert(
				matches,
				"Guarded author properties/metadata changed: "
					.. row.path
					.. " ("
					.. tostring(reason)
					.. ")"
			)
		end
	end
	local function inspect()
		-- Each full inspection gets fresh sibling lists, then shares only that
		-- non-yielding read pass. Dense overview duplicates otherwise cost O(n²).
		pathIndex, selectorCache = nil, {}
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
			"World bounds changed"
		)
		for _, entry in nodes do
			if entry.retainedParent then
				assert(
					resolve(entry.parentPath) == entry.retainedParent,
					"Author parent identity changed"
				)
			end
		end
		sourcePreflight()
		local before, after, afterMismatch = true, true, nil
		for _, entry in changes do
			assert(
				resolve(entry.row.path, entry.row.selector, entry.row.installedSelector)
					== entry.item,
				"Retained identity changed during preparation"
			)
			local actual = if entry.row.attribute
				then entry.item:GetAttribute(entry.row.property)
				else entry.item[entry.row.property]
			before = before and same(actual, entry.before)
			after = after and same(actual, entry.after)
			if not afterMismatch and not same(actual, entry.after) then
				afterMismatch = entry.row.path
					.. "/"
					.. entry.row.property
					.. ": "
					.. tostring(actual)
					.. " ~= "
					.. tostring(entry.after)
			end
		end
		local present = 0
		for _, entry in nodes do
			local item = resolve(entry.row.path)
			if item then
				present += 1
				assert(
					propertiesMatch(item, entry.row, "after"),
					"Modified maze node preserved: " .. entry.row.path
				)
			end
		end
		if present > 0 then
			assert(
				present == #nodes and after,
				"Partial maze installation preserved: "
					.. tostring(present)
					.. "/"
					.. #nodes
					.. "; "
					.. tostring(afterMismatch)
			)
			for _, rootPath in rootPaths do
				local root = assert(resolve(rootPath))
				for _, item in root:GetDescendants() do
					assert(
						byPath[item:GetFullName():gsub("%.", "/")],
						"Unknown child inside maze preserved"
					)
				end
			end
			guardsMatch("after")
			return "installed"
		end
		assert(before, "Unknown/partial author world changes preserved")
		guardsMatch("before")
		return "baseline"
	end
	local initialState = inspect()
	if options.dryRun then
		return {
			dryRun = true,
			state = initialState,
			plannedNodes = #nodes,
			plannedChanges = #changes,
			guardedInstances = #guards,
			retainedSources = 156,
		}
	end
	if initialState == "installed" then
		return { created = 0, changedProperties = 0, repeated = true }
	end
	local prepared, created, journal, writes = {}, {}, {}, 0
	local function wrote()
		writes += 1
		if options.failAfterWrites == writes then
			error("Injected maze transaction write failure")
		end
	end
	local ok, problem = pcall(function()
		-- Prepare bounded pieces outside the DataModel. Only new nodes may change here.
		for index, entry in nodes do
			local item = Instance.new(entry.row.class)
			created[#created + 1] = item
			item.Name = entry.name
			for property, value in entry.row.properties do
				item[property] = decode(value, item[property])
			end
			for name, value in entry.row.attributes do
				item:SetAttribute(name, decode(value))
			end
			for _, tag in entry.row.tags do
				item:AddTag(tag)
			end
			local matches, reason = propertiesMatch(item, entry.row, "after")
			assert(
				matches,
				"Prepared maze node readback differs: "
					.. entry.row.path
					.. " ("
					.. tostring(reason)
					.. ")"
			)
			prepared[entry.row.path] = item
			if index % 64 == 0 then
				if options.prepareYield then
					options.prepareYield(index)
				else
					task.wait()
				end
			end
		end
		-- Recheck all originals after preparation yields. No yield is permitted from here.
		assert(inspect() == "baseline", "World changed while preparing maze")
		game:GetService("ChangeHistoryService"):SetWaypoint("Before Corn B maze variant 2")
		for _, entry in nodes do
			local item = prepared[entry.row.path]
			item.Parent = prepared[entry.parentPath] or assert(resolve(entry.parentPath))
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
		assert(inspect() == "installed", "Maze transaction readback differs")
	end)
	if not ok then
		local rollbackProblems = {}
		for index = #journal, 1, -1 do
			local entry = journal[index]
			local restored, failure = pcall(function()
				if entry.row.attribute then
					entry.item:SetAttribute(entry.row.property, entry.before)
				else
					entry.item[entry.row.property] = entry.before
				end
			end)
			if not restored then
				rollbackProblems[#rollbackProblems + 1] = tostring(failure)
			end
		end
		for index = #created, 1, -1 do
			local removed, failure = pcall(function()
				created[index]:Destroy()
			end)
			if not removed then
				rollbackProblems[#rollbackProblems + 1] = tostring(failure)
			end
		end
		error(
			tostring(problem)
				.. (
					if #rollbackProblems > 0
						then "; rollback errors: " .. table.concat(rollbackProblems, "; ")
						else ""
				)
		)
	end
	game:GetService("ChangeHistoryService"):SetWaypoint("Corn B maze variant 2")
	return {
		created = #nodes,
		changedProperties = #changes,
		repeated = false,
		retainedSources = 156,
	}
end
