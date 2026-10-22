-- Invoke only through Studio MCP in the author's new, independently verified C.
-- Pass the exact prepared payload as an argument. No HTTP, Rojo or cloud writes.
return function(payload, preflight)
	local run = game:GetService("RunService")
	assert(run:IsStudio() and not run:IsRunning(), "Stopped C Edit required")
	assert(game.PlaceId == 0, "Separate local C scene required")
	assert(not workspace:FindFirstChild("CornMap"), "A/B must not receive C geometry")
	assert(
		payload.owner == "children_of_corn_C_test" and payload.version == 1,
		"C payload identity required"
	)
	assert(
		type(preflight) == "function" and type(payload.native_target) == "table",
		"Fresh reviewed native C preflight required"
	)
	local measured = preflight()
	assert(
		measured.name == payload.native_target.name
			and measured.fingerprint == payload.native_target.fingerprint
			and measured.sourceCount == payload.native_target.sourceCount,
		"C changed after read-only preflight; preserved"
	)
	local encoding = game:GetService("EncodingService")
	local function hash(text)
		return (
			encoding
				:ComputeStringHash(text:gsub("\r\n", "\n"), Enum.HashAlgorithm.Sha256)
				:gsub(".", function(c)
					return string.format("%02x", string.byte(c))
				end)
		)
	end
	local function locate(path)
		local current = game
		for component in path:gmatch("[^/]+") do
			local found = nil
			for _, child in current:GetChildren() do
				if child.Name == component then
					assert(not found, "Duplicate native C path")
					found = child
				end
			end
			if not found then
				return nil
			end
			current = found
		end
		return current
	end
	local count = 0
	for _, item in game:GetDescendants() do
		if item:IsA("LuaSourceContainer") then
			count += 1
			local path = item:GetFullName():gsub("%.", "/")
			local expected = payload.sources[path]
			assert(
				expected
					and item.ClassName == expected.class
					and hash(item.Source) == expected.sha256,
				"Existing author Source preserved: " .. path
			)
			assert(
				game:GetService("ScriptEditorService"):GetEditorSource(item) == item.Source,
				"Unsaved editor buffer preserved"
			)
		end
	end
	assert(count == 0 or count == 9, "Blank or complete C source state required")
	local total = 0
	for path, row in payload.sources do
		total += 1
		assert(
			hash(row.source) == row.sha256 and #row.source < 200000,
			"C transport Source differs"
		)
		local existing = locate(path)
		if existing then
			assert(
				existing.ClassName == row.class and hash(existing.Source) == row.sha256,
				"Manual Source preserved"
			)
		end
	end
	assert(total == 9, "Complete nine-Source C payload required")
	if count == 0 then
		assert(
			not game.ReplicatedStorage:FindFirstChild("CornCTestSystem"),
			"Foreign C system preserved"
		)
		local root = Instance.new("Folder")
		root.Name = "CornCTestSystem"
		root:SetAttribute("corn_project_id", payload.owner)
		local data = Instance.new("Folder")
		data.Name = "Data"
		data.Parent = root
		local created = {}
		local ok, problem = pcall(function()
			for path, row in payload.sources do
				local item = Instance.new(row.class)
				item.Name = path:match("([^/]+)$")
				item.Source = row.source
				item:SetAttribute("corn_project_id", payload.owner)
				if item:IsA("BaseScript") then
					item.Disabled = true
				end
				created[path] = item
				if path:find("/Data/", 1, true) then
					item.Parent = data
				elseif row.class == "ModuleScript" then
					item.Parent = root
				end
			end
			root.Parent = game.ReplicatedStorage
			created["ServerScriptService/CornCTestBootstrap"].Parent = game.ServerScriptService
			created["StarterPlayer/StarterPlayerScripts/CornCTestBootstrap"].Parent =
				game.StarterPlayer.StarterPlayerScripts
		end)
		if not ok then
			for _, item in created do
				item:Destroy()
			end
			root:Destroy()
			error(problem, 0)
		end
	end
	game.Name = "Children_of_corn_C.rbxl"
	local result = require(game.ReplicatedStorage.CornCTestSystem.Scene).Ensure("Edit")
	local lighting = game:GetService("Lighting")
	lighting.LightingStyle = Enum.LightingStyle.Realistic
	lighting.ClockTime = 14
	lighting.Brightness = 2
	lighting.GlobalShadows = true
	lighting.Ambient = Color3.fromRGB(70, 74, 65)
	lighting.OutdoorAmbient = Color3.fromRGB(115, 122, 101)
	lighting.EnvironmentDiffuseScale = 1
	lighting.EnvironmentSpecularScale = 0.5
	lighting.ExposureCompensation = 0
	local originalSpawn = workspace:FindFirstChild("SpawnLocation")
	if originalSpawn and originalSpawn:IsA("SpawnLocation") then
		originalSpawn.Enabled = false
		-- Preserve the new Baseplate template's marker outside the walkable world.
		-- Its visible pad would otherwise obstruct the middle of the C corridor.
		assert(not game.ServerStorage:FindFirstChild("SpawnLocation"), "Author backup preserved")
		originalSpawn.Parent = game.ServerStorage
	end
	game.StarterPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
	game.StarterPlayer.CameraMinZoomDistance = 0.5
	game.StarterPlayer.CameraMaxZoomDistance = 0.5
	game.StarterPlayer.CharacterWalkSpeed = 12
	game.ServerScriptService.CornCTestBootstrap.Disabled = false
	game.StarterPlayer.StarterPlayerScripts.CornCTestBootstrap.Disabled = false
	return result
end
