-- Local plugin factory. Restores existing session meshes in stopped manual B;
-- it never builds a layout, creates plants, saves a place or contacts a service.
return function(context)
	local game, run, workspace = context.game, context.run, context.game:GetService("Workspace")
	local storage = game:GetService("ReplicatedStorage")
	local connections, mapConnections = {}, {}
	local attempted, stopRetried = {}, {}
	local alive, busy, queued, forced = true, false, false, false
	local watchedMap, lastWarning, pendingStop
	local lastRunning = run:IsRunning()
	local guard = { attempts = 0, restored = 0 }
	local toolbar = context.plugin:CreateToolbar("Corn: карта")
	local refresh = toolbar:CreateButton(
		"CornManualRestore",
		"Восстановить меши сохранённой сцены B",
		"",
		"Обновить сцену"
	)
	local points = toolbar:CreateButton(
		"CornManualPoints",
		"Выбрать точки предметов, игроков и чучело",
		"",
		"Точки карты"
	)

	local function disconnect(list)
		for _, connection in list do
			connection:Disconnect()
		end
		table.clear(list)
	end
	local function target()
		if
			not alive
			or not run:IsStudio()
			or run:IsRunning()
			or game.Name ~= "Children_of_corn_B.rbxl"
		then
			return nil
		end
		local map = workspace:FindFirstChild("CornMap")
		if not map or not map:IsA("Model") or map.Parent ~= workspace then
			return nil
		end
		if
			map:GetAttribute("corn_project_id") ~= "children_of_corn"
			or map:GetAttribute("HarvestArtVariant") ~= "B"
			or map:GetAttribute("BManualAuthoringVersion") ~= 1
		then
			return nil
		end
		return map
	end
	local function currentModule()
		local shared = storage:FindFirstChild("GameShared")
		local folder = shared and shared:FindFirstChild("Game")
		local module = folder and folder:FindFirstChild("ManualScene")
		return if module and module:IsA("ModuleScript") then module else nil
	end
	local function updateButtons()
		local enabled = target() ~= nil
		refresh.Enabled, points.Enabled = enabled, enabled
	end
	local function notice(problem)
		local message = tostring(problem)
		if message ~= lastWarning then
			lastWarning = message
			context.warn("[CornManualSceneEditor] " .. message)
		end
	end
	local function schedule(force)
		if not alive or busy then
			return
		end
		forced = forced or force == true
		if queued then
			return
		end
		queued = true
		context.defer(function()
			queued = false
			local manual = forced
			forced = false
			local map, module = target(), currentModule()
			updateButtons()
			if not map or not module or (attempted[map] and not manual) then
				return
			end
			attempted[map], busy = true, true
			guard.attempts += 1
			local ok, result = pcall(function()
				local restore = context.require(module)
				assert(
					target() == map and currentModule() == module,
					"B Edit binding changed during module load"
				)
				assert(
					type(restore) == "table" and type(restore.RestoreEdit) == "function",
					"ManualScene.RestoreEdit missing"
				)
				return restore.RestoreEdit()
			end)
			busy = false
			if ok then
				guard.restored += 1
				lastWarning = nil
				if manual and alive and context.notice then
					context.notice(result)
				end
			elseif alive then
				notice(result)
			end
			local retry = pendingStop
			pendingStop = nil
			if retry and target() == retry then
				context.defer(function()
					schedule(true)
				end)
			end
		end)
	end
	local function watchMap()
		local map = workspace:FindFirstChild("CornMap")
		if map ~= watchedMap then
			disconnect(mapConnections)
			watchedMap = map
			if map then
				for _, name in { "corn_project_id", "HarvestArtVariant", "BManualAuthoringVersion" } do
					table.insert(
						mapConnections,
						map:GetAttributeChangedSignal(name):Connect(function()
							updateButtons()
							schedule(false)
						end)
					)
				end
			end
		end
		updateButtons()
		schedule(false)
	end
	function guard.Restore()
		schedule(true)
	end
	function guard.SelectPoints()
		local map = target()
		if not map then
			return
		end
		local props = map:FindFirstChild("Props")
		local selected = {}
		for _, item in
			{
				map:FindFirstChild("KeySlots"),
				map:FindFirstChild("CornerSpawns"),
				if props then props:FindFirstChild("ScarecrowMarker") else nil,
			}
		do
			if item then
				table.insert(selected, item)
			end
		end
		if #selected > 0 then
			context.selection:Set(selected)
		end
	end
	function guard.Destroy()
		if not alive then
			return
		end
		alive = false
		pendingStop = nil
		disconnect(connections)
		disconnect(mapConnections)
		refresh.Enabled, points.Enabled = false, false
	end
	table.insert(connections, refresh.Click:Connect(guard.Restore))
	table.insert(connections, points.Click:Connect(guard.SelectPoints))
	table.insert(connections, context.plugin.Unloading:Connect(guard.Destroy))
	table.insert(connections, game.Loaded:Connect(watchMap))
	table.insert(connections, game:GetPropertyChangedSignal("Name"):Connect(watchMap))
	table.insert(
		connections,
		workspace.ChildAdded:Connect(function(item)
			if item.Name == "CornMap" then
				watchMap()
			end
		end)
	)
	table.insert(
		connections,
		workspace.ChildRemoved:Connect(function(item)
			if item == watchedMap then
				watchMap()
			end
		end)
	)
	table.insert(
		connections,
		storage.DescendantAdded:Connect(function(item)
			if item.Name == "ManualScene" or item.Name == "GameShared" then
				schedule(false)
			end
		end)
	)
	-- This observes the Play -> Edit transition only. It never polls mesh state
	-- or rebuilds on frames, selection changes, object moves or object deletion.
	table.insert(
		connections,
		context.heartbeat:Connect(function()
			local running = run:IsRunning()
			if running == lastRunning then
				return
			end
			lastRunning = running
			updateButtons()
			if not running then
				local map = target()
				if map and not stopRetried[map] then
					stopRetried[map] = true
					if busy then
						pendingStop = map
					else
						schedule(true)
					end
				end
			end
		end)
	)
	watchMap()
	return guard
end
