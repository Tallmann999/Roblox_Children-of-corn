-- Studio MCP only. The caller first captures the read-only 167-Source B baseline.
-- Adds one code ModuleScript; never writes Lighting, UI, geometry or old Sources.
-- selene: allow(global_usage)
return function(source, expectedHash)
	local state = assert(_G.__CornBNightToggleV1, "Fresh B baseline required")
	local run = game:GetService("RunService")
	assert(run:IsStudio() and not run:IsRunning(), "Stopped Studio Edit required")
	assert(game.Name == "Children_of_corn_B.rbxl" and game.PlaceId == 0, "Exact B file required")
	local map = assert(workspace:FindFirstChild("CornMap"))
	assert(map:GetAttribute("corn_project_id") == "children_of_corn", "Project mismatch")
	assert(map:GetAttribute("HarvestArtVariant") == "B", "Variant mismatch")
	assert(map.FieldZone.Size == Vector3.new(630, 10, 630), "Field mismatch")
	local encoding = game:GetService("EncodingService")
	local function hash(value)
		return (
			encoding:ComputeStringHash(value, Enum.HashAlgorithm.Sha256):gsub(".", function(c)
				return string.format("%02x", c:byte())
			end)
		)
	end
	assert(
		type(source) == "string" and source ~= "" and hash(source) == expectedHash,
		"Source pin differs"
	)
	assert(loadstring(source), "Source must compile")
	local parent = game.StarterPlayer.StarterPlayerScripts.GameClient.Controllers
	local existing = parent:FindFirstChild("NightModeController")
	local function verify(count)
		local current = state.snapshot({ sourceCount = count })
		for id, before in state.before.nodes do
			local after = assert(current.nodes[id], "Retained instance removed: " .. before.path)
			assert(after.sha256 == before.sha256, "Retained instance changed: " .. before.path)
		end
		assert(
			current.worldLightingSha256 == state.before.worldLightingSha256,
			"World/Lighting changed"
		)
		assert(
			current.instances == state.before.instances + count - 167,
			"Unexpected added instances"
		)
		for _, row in current.editorDocuments do
			assert(row.textSha256 == row.sourceSha256, "Unsaved editor buffer: " .. row.path)
		end
		for id, row in current.nodes do
			if not state.before.nodes[id] then
				assert(
					row.path
						== "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/NightModeController",
					"Foreign addition"
				)
				assert(
					row.class == "ModuleScript" and row.sourceSha256 == expectedHash,
					"New Source differs"
				)
			end
		end
		return current
	end
	if existing then
		assert(
			existing:IsA("ModuleScript") and existing.Source == source,
			"Controller name collision"
		)
		assert(#existing:GetChildren() == 0 and #existing:GetTags() == 0, "Controller modified")
		assert(next(existing:GetAttributes()) == nil, "Controller attributes changed")
		verify(168)
		return {
			installed = false,
			repeated = true,
			oldSourcesRetained = 167,
			worldUnchanged = true,
		}
	end
	verify(167)
	local module = Instance.new("ModuleScript")
	module.Name, module.Source = "NightModeController", source
	local ok, problem = pcall(function()
		module.Parent = parent
		verify(168)
	end)
	if not ok then
		module:Destroy()
		error(problem)
	end
	return { installed = true, addedSources = 1, oldSourcesRetained = 167, worldUnchanged = true }
end
