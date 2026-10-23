-- MCP-only reversible author edits. No Source, Save, publication or serialization.
local S = assert(_G.__CornBManualAuthoringV1, "Manual authoring session required")
local API = {}
local PROJECT = "children_of_corn"
local function identity()
	local run = game:GetService("RunService")
	assert(run:IsStudio() and not run:IsRunning(), "Stopped Studio Edit required")
	assert(game.Name == "Children_of_corn_B.rbxl" and game.PlaceId == 0, "Exact local B required")
	assert(
		S.phase == "sources-installed" and type(S.verifySources) == "function",
		"Installed final Sources required"
	)
	local map = assert(workspace:FindFirstChild("CornMap"), "CornMap required")
	assert(
		map:IsA("Model")
			and map:GetAttribute("corn_project_id") == PROJECT
			and map:GetAttribute("HarvestArtVariant") == "B"
			and map:GetAttribute("BManualAuthoringVersion") == 1
			and map.FieldZone.Size == Vector3.new(630, 10, 630),
		"Manual B identity changed"
	)
	S.verifySources()
	return map
end
local function frame(value)
	return { value:GetComponents() }
end
local function vector(value)
	return { value.X, value.Y, value.Z }
end
local function cornRecord(part)
	return {
		name = part.Name,
		parent = if part.Parent then part.Parent:GetFullName() else "nil",
		frame = frame(part.CFrame),
		size = vector(part.Size),
		variety = part:GetAttribute("CornGreenVariety"),
		column = part:GetAttribute("CornAuthorColumn"),
		row = part:GetAttribute("CornAuthorRow"),
	}
end
local function partCount(folder)
	local count = 0
	for _, item in folder:GetDescendants() do
		if item:IsA("MeshPart") then
			count += 1
		end
	end
	return count
end
local function restore(fixture)
	if fixture.copy then
		fixture.copy:Destroy()
		fixture.copy = nil
	end
	if fixture.deleted.Parent == nil then
		fixture.deleted.Parent = fixture.deletedParent
	else
		assert(
			fixture.deleted.Parent == fixture.deletedParent,
			"Detached plant acquired a foreign parent"
		)
	end
	-- Restore saved values, never an inverse transform or a second PivotTo.
	for _, row in fixture.parts do
		row.item.CFrame = row.before
	end
	-- Auto pivots normally return exactly after the part restoration. Avoid
	-- materializing an optional editor pivot when its value already matches.
	for index = #fixture.models, 1, -1 do
		local row = fixture.models[index]
		if row.item.WorldPivot ~= row.before then
			row.item.WorldPivot = row.before
		end
	end
	for _, row in fixture.parts do
		assert(
			row.item.CFrame == row.before,
			"Exact part restore failed: " .. row.item:GetFullName()
		)
	end
	for _, row in fixture.models do
		assert(
			row.item.WorldPivot == row.before,
			"Exact model pivot restore failed: " .. row.item:GetFullName()
		)
	end
	assert(fixture.deleted.Parent == fixture.deletedParent, "Deleted plant parent restore failed")
	assert(
		partCount(fixture.source) == fixture.sourceCount,
		"Authored source count did not restore"
	)
end

function API.Stage()
	local map = identity()
	assert(S.authorEditFixture == nil, "A staged author fixture already exists; restore it first")
	local source = assert(map:FindFirstChild("CornAuthoring"), "Author source folder missing")
	assert(
		source:IsA("Folder")
			and source:GetAttribute("corn_project_id") == PROJECT
			and source:GetAttribute("BManualAuthoringVersion") == 1,
		"Foreign authored source preserved"
	)
	local fixture =
		{ map = map, source = source, parts = {}, models = {}, sourceCount = partCount(source) }
	assert(fixture.sourceCount == 70664, "Expected the accepted 70664 authored plants")
	local partSeen, modelSeen = {}, {}
	local function rememberModel(model)
		if model:IsA("Model") and not modelSeen[model] then
			modelSeen[model] = true
			table.insert(fixture.models, { item = model, before = model.WorldPivot })
		end
	end
	local function rememberPart(part)
		if not partSeen[part] then
			partSeen[part] = true
			table.insert(fixture.parts, { item = part, before = part.CFrame })
		end
		local ancestor = part.Parent
		while ancestor and ancestor ~= workspace do
			rememberModel(ancestor)
			ancestor = ancestor.Parent
		end
	end
	local function rememberTree(root)
		rememberModel(root)
		for _, item in root:GetDescendants() do
			if item:IsA("BasePart") then
				rememberPart(item)
			elseif item:IsA("Model") then
				rememberModel(item)
			end
		end
	end
	local sites, houses, spawns = {}, {}, {}
	local slots = assert(map:FindFirstChild("KeySlots"), "Sites missing")
	for _, site in slots:GetChildren() do
		assert(
			site:IsA("Model") and site.PrimaryPart and site.PrimaryPart:HasTag("corn_key_slot"),
			"Malformed author site"
		)
		table.insert(sites, site)
		rememberTree(site)
	end
	assert(#sites == 15, "Exactly fifteen author sites required")
	table.sort(sites, function(a, b)
		return a.Name < b.Name
	end)
	for _, name in { "HouseWest", "HouseEast", "HouseNorthWest" } do
		local house = assert(map.Props:FindFirstChild(name), "House missing: " .. name)
		assert(house:IsA("Model"), "House Model required")
		table.insert(houses, house)
		rememberTree(house)
	end
	local warden = assert(map.Props:FindFirstChild("ScarecrowMarker"), "Warden home missing")
	assert(
		warden:IsA("Model") and warden:HasTag("corn_monster_home"),
		"Tagged warden Model required"
	)
	rememberTree(warden)
	for _, spawn in map.CornerSpawns:GetChildren() do
		assert(
			spawn:IsA("SpawnLocation") and spawn:HasTag("corn_spawn"),
			"Four real player SpawnLocations required"
		)
		table.insert(spawns, spawn)
		rememberPart(spawn)
	end
	assert(#spawns == 4, "Exactly four player starts required")
	local sw = assert(map.CornerSpawns:FindFirstChild("SW"), "SW start required")
	local nearest = {}
	for index, part in source:GetDescendants() do
		if part:IsA("MeshPart") then
			local column, row =
				part:GetAttribute("CornAuthorColumn"), part:GetAttribute("CornAuthorRow")
			if
				type(column) == "number"
				and type(row) == "number"
				and column % 2 == 0
				and row % 2 == 0
			then
				local delta = part.CFrame.Position - sw.CFrame.Position
				local candidate = {
					item = part,
					distance = delta.X * delta.X + delta.Z * delta.Z,
					key = part:GetFullName(),
				}
				if #nearest < 3 or candidate.distance <= nearest[3].distance then
					table.insert(nearest, candidate)
					table.sort(nearest, function(a, b)
						return if a.distance == b.distance
							then a.key < b.key
							else a.distance < b.distance
					end)
					if #nearest > 3 then
						table.remove(nearest)
					end
				end
			end
		end
		if index % 1024 == 0 then
			task.wait()
		end
	end
	assert(#nearest == 3, "Three near-SW even/even source plants required")
	local moved, duplicateSource, deleted = nearest[1].item, nearest[2].item, nearest[3].item
	for _, part in { moved, duplicateSource, deleted } do
		assert(
			part:GetAttribute("corn_project_id") == PROJECT and #part:GetChildren() == 0,
			"Foreign source plant preserved"
		)
		rememberPart(part)
	end
	fixture.moved, fixture.duplicateSource, fixture.deleted, fixture.deletedParent =
		moved, duplicateSource, deleted, deleted.Parent
	fixture.before = {
		moved = cornRecord(moved),
		duplicateSource = cornRecord(duplicateSource),
		deleted = cornRecord(deleted),
	}
	identity()
	S.authorEditFixture = fixture -- Full native refs survive Play until exact Edit restore.
	local function moveModel(model, offset, yaw)
		local pivot = model:GetPivot()
		model:PivotTo(
			CFrame.new(pivot.Position + offset) * CFrame.Angles(0, yaw, 0) * pivot.Rotation
		)
	end
	local ok, problem = pcall(function()
		for _, site in sites do
			moveModel(site, Vector3.new(0.5, 0, 0.5), 0.05)
		end
		for _, house in houses do
			moveModel(house, Vector3.new(0.25, 0, 0.5), 0.01)
		end
		moveModel(warden, Vector3.new(1, 0, 1), 0)
		for _, spawn in spawns do
			spawn.CFrame += Vector3.new(0.25, 0, 0.25)
		end
		moved.CFrame += Vector3.new(27, 0, 0)
		local copy = assert(duplicateSource:Clone(), "Manual copy unavailable")
		fixture.copy = copy
		copy.Name = "ManualAcceptanceCopy"
		copy.CFrame += Vector3.new(2.1, 0, 0)
		copy.Parent = duplicateSource.Parent
		deleted.Parent = nil
		assert(partCount(source) == fixture.sourceCount, "Stage source count differs")
		identity()
	end)
	if not ok then
		local recovered, failure = pcall(restore, fixture)
		if recovered then
			S.authorEditFixture = nil
		end
		error(
			tostring(problem)
				.. (
					if recovered
						then "; exact author fixture rolled back"
						else "; restore required: " .. tostring(failure)
				)
		)
	end
	fixture.expected = {
		moved = cornRecord(moved),
		copy = cornRecord(fixture.copy),
		deleted = cornRecord(deleted),
	}
	return {
		staged = true,
		sites = #sites,
		houses = #houses,
		playerStarts = #spawns,
		savedPartFrames = #fixture.parts,
		savedModelPivots = #fixture.models,
		actualSourceCount = partCount(source),
		before = fixture.before,
		expected = fixture.expected,
		sourceCount = 171,
		saved = false,
	}
end

function API.Restore()
	local map = identity()
	local fixture = assert(S.authorEditFixture, "No staged author edits")
	assert(fixture.map == map and fixture.source.Parent == map, "Author fixture map changed")
	restore(fixture)
	S.verifySources()
	S.authorEditFixture = nil
	return {
		restored = true,
		exactPartFrames = #fixture.parts,
		exactModelPivots = #fixture.models,
		actualSourceCount = partCount(fixture.source),
		sourceCount = 171,
		saved = false,
	}
end

return API
