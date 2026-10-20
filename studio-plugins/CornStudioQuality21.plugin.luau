-- Corn Studio Quality21. Local authoring plugin; owned A/B files only.
local createGuard = (function()
-- Studio plugin factory. It never changes game instances or UserGameSettings.
return function(context)
	local game, render = context.game, context.render
	local level, defer = context.level, context.defer
	local workspace = game:GetService("Workspace")
	local variants = { ["Children_of_corn.rbxl"] = "A", ["Children_of_corn_B.rbxl"] = "B" }
	local properties = { "QualityLevel", "EditQualityLevel" }
	local connections, mapConnections, previous = {}, {}, {}
	local alive, active, queued, writing = true, false, false, false
	local watchedMap
	local guard = { writes = 0, activations = 0 }
	local function disconnect(list)
		for _, connection in list do
			connection:Disconnect()
		end
		table.clear(list)
	end
	local function ownedCorn()
		local variant = variants[game.Name]
		local map = workspace:FindFirstChild("CornMap")
		if not variant or not map then
			return false
		end
		if
			map:GetAttribute("corn_project_id") ~= "children_of_corn"
			or map:GetAttribute("HarvestArtVariant") ~= variant
		then
			return false
		end
		local ground, field = map:FindFirstChild("Ground"), map:FindFirstChild("FieldZone")
		return ground ~= nil
			and field ~= nil
			and ground:IsA("BasePart")
			and field:IsA("BasePart")
			and ground.Size == context.groundSize
			and field.Size == context.fieldSize
	end
	local function release()
		active, writing = false, true
		for _, property in properties do
			if previous[property] ~= nil and render[property] == level then
				render[property] = previous[property]
			end
		end
		table.clear(previous)
		writing = false
	end
	local function apply()
		if not alive or writing then
			return
		end
		if not ownedCorn() then
			if active then
				release()
			end
			return
		end
		if not active then
			for _, property in properties do
				previous[property] = render[property]
			end
			active = true
			guard.activations += 1
			if context.notice then
				context.notice()
			end
		end
		writing = true
		for _, property in properties do
			if render[property] ~= level then
				render[property] = level
				guard.writes += 1
			end
		end
		writing = false
	end
	local function schedule()
		if not alive or queued or writing then
			return
		end
		queued = true
		defer(function()
			queued = false
			if alive then
				apply()
			end
		end)
	end
	local function watchMap()
		local map = workspace:FindFirstChild("CornMap")
		if map == watchedMap then
			schedule()
			return
		end
		disconnect(mapConnections)
		watchedMap = map
		if map then
			for _, name in { "corn_project_id", "HarvestArtVariant" } do
				table.insert(mapConnections, map:GetAttributeChangedSignal(name):Connect(schedule))
			end
			table.insert(mapConnections, map.ChildAdded:Connect(schedule))
			table.insert(mapConnections, map.ChildRemoved:Connect(schedule))
		end
		schedule()
	end
	for _, property in properties do
		table.insert(connections, render:GetPropertyChangedSignal(property):Connect(schedule))
	end
	-- RenderSettings setters do not emit property signals in the tested Studio.
	-- Poll at most four times per second so CoreGui startup resets are repaired.
	local elapsed = 0
	table.insert(
		connections,
		context.heartbeat:Connect(function(dt)
			elapsed += dt
			if elapsed >= 0.25 then
				elapsed = 0
				apply()
			end
		end)
	)
	table.insert(connections, game:GetPropertyChangedSignal("Name"):Connect(schedule))
	table.insert(connections, game.Loaded:Connect(watchMap))
	table.insert(
		connections,
		workspace.ChildAdded:Connect(function(child)
			if child.Name == "CornMap" then
				watchMap()
			end
		end)
	)
	table.insert(
		connections,
		workspace.ChildRemoved:Connect(function(child)
			if child == watchedMap then
				watchMap()
			end
		end)
	)
	function guard.Destroy()
		if not alive then
			return
		end
		alive = false
		disconnect(connections)
		disconnect(mapConnections)
		if active then
			release()
		end
	end
	function guard.IsActive()
		return active
	end
	watchMap()
	apply()
	return guard
end

end)()
local guard = createGuard({
    game = game, render = settings().Rendering,
    level = Enum.QualityLevel.Level21, defer = task.defer,
    heartbeat = game:GetService("RunService").Heartbeat,
    groundSize = Vector3.new(630, 2, 630), fieldSize = Vector3.new(630, 10, 630),
    notice = function() print("[CornStudioQuality21] Corn A/B: fixed Studio render quality21") end,
})
plugin.Unloading:Connect(function() guard.Destroy() end)
