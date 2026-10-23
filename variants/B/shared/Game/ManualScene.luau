--!strict
-- Editor restoration only. The authored Instances, including deletions, remain authoritative.
local RunService = game:GetService("RunService")
local ManualScene = {}

function ManualScene.IsTarget(map: Instance?): boolean
	return map ~= nil
		and map:IsA("Model")
		and map.Name == "CornMap"
		and map:GetAttribute("corn_project_id") == "children_of_corn"
		and map:GetAttribute("HarvestArtVariant") == "B"
		and map:GetAttribute("BManualAuthoringVersion") == 1
end

local function apply(part: MeshPart, template: MeshPart)
	local frame, size = part.CFrame, part.Size
	local texture, color, material = part.TextureID, part.Color, part.Material
	local transparency, shadow = part.Transparency, part.CastShadow
	part:ApplyMesh(template)
	part.CFrame, part.Size = frame, size
	part.TextureID, part.Color, part.Material = texture, color, material
	part.Transparency, part.CastShadow = transparency, shadow
end

function ManualScene.RestoreEdit(): any
	assert(RunService:IsStudio() and not RunService:IsRunning(), "Stopped Studio Edit required")
	assert(game.Name == "Children_of_corn_B.rbxl", "Exact B file required")
	local map = workspace:FindFirstChild("CornMap")
	assert(ManualScene.IsTarget(map), "B manual scene required")
	assert(map and map:IsA("Model"), "Manual scene Model missing")
	local function current()
		assert(
			not RunService:IsRunning()
				and map.Parent == workspace
				and workspace:FindFirstChild("CornMap") == map
				and ManualScene.IsTarget(map),
			"Editor restoration interrupted by Play or map change"
		)
	end
	local folder = assert(map:FindFirstChild("CornAuthoring"), "Authored plants missing")
	assert(
		folder:GetAttribute("corn_project_id") == "children_of_corn"
			and folder:GetAttribute("BManualAuthoringVersion") == 1,
		"Foreign corn preserved"
	)
	local appearance = require(script.Parent.CornAppearance)
	local templates = appearance.DetailedTemplates()
	current()
	local count, restored = 0, 0
	for _, part in folder:GetDescendants() do
		if part:IsA("MeshPart") then
			assert(
				part:GetAttribute("corn_project_id") == "children_of_corn",
				"Foreign plant preserved"
			)
			local variety = part:GetAttribute("CornGreenVariety")
			assert(
				type(variety) == "number" and variety % 1 == 0 and variety >= 1 and variety <= 4,
				"Unknown plant variety preserved"
			)
			current()
			if part.MeshContent.SourceType == Enum.ContentSourceType.None then
				apply(part, templates.Near[variety])
				restored += 1
			end
			count += 1
			if count % 256 == 0 then
				task.wait()
			end
		end
	end
	local beds = map:FindFirstChild("GreenBedEditor")
	local soilRestored = 0
	if beds then
		local geometry = require(script.Parent.GreenBedGeometry)
		local soil = geometry.BuildTemplates()
		current()
		for index, part in beds:GetDescendants() do
			if part:IsA("MeshPart") then
				assert(
					part:GetAttribute("BGreenBedsOwner") == "corn_B_green_beds_v1",
					"Foreign soil preserved"
				)
				local key = part:GetAttribute("BGreenBedGeometryKey")
				assert(type(key) == "string" and soil[key], "Unknown soil preserved")
				current()
				if part.MeshContent.SourceType == Enum.ContentSourceType.None then
					apply(part, soil[key])
					soilRestored += 1
				end
			end
			if index % 128 == 0 then
				task.wait()
			end
		end
	end
	local server = game:GetService("ServerScriptService"):FindFirstChild("GameServer")
	assert(server and server:FindFirstChild("Game"), "Project server modules required")
	current()
	local farm = require(server.Game.FarmGeometry).Ensure()
	current()
	-- A previous MCP Edit inspection may have required the old Source. A private
	-- clone avoids that cache without adding any temporary script to the scene.
	local module = server.Game.HarvestWorld:Clone()
	local ok, harvest = pcall(function()
		return require(module).Ensure()
	end)
	module:Destroy()
	assert(ok, harvest)
	current()
	return {
		plants = count,
		restoredCorn = restored,
		restoredSoil = soilRestored,
		farm = farm,
		harvest = harvest,
	}
end

return table.freeze(ManualScene)
