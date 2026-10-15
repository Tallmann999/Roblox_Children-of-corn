-- Production CornField + actual CornLayout and MeshPart clones in the Lune geometry adapter.
-- A narrow proxy observes Parent assignment; this is not cloud decode/GPU/network acceptance.
local adapter = require("./scene-adapter")
local fs, r, I = adapter.fs, adapter.r, adapter.I
local function loadSource(path, env)
	local fn = assert(loadstring(fs.readFile(path), path))
	setfenv(fn, setmetatable(env, { __index = getfenv() }))
	return fn()
end
local Appearance = loadSource("src/shared/Game/CornAppearance.luau", {})
local Layout = loadSource("src/shared/Game/CornLayout.luau", {
	CFrame = r.CFrame,
	Vector3 = r.Vector3,
	Vector2 = r.Vector2,
})
local function child(parent, class, name)
	local item = I.new(class)
	item.Name = name
	item.Parent = parent
	return item
end
local function setup(options)
	options = options or {}
	local storage, server = I.new("ReplicatedStorage"), I.new("ServerStorage")
	local shared = child(storage, "Folder", "GameShared")
	local configs = child(shared, "Folder", "Config")
	child(configs, "ModuleScript", "GameConfig")
	local gameFolder = child(shared, "Folder", "Game")
	child(gameFolder, "ModuleScript", "CornLayout")
	child(gameFolder, "ModuleScript", "CornAppearance")
	local source = child(server, "Model", "SM_Prop_Plant_Corn_01_L")
	source:SetAttribute("AuthorValue", "preserve")
	source:AddTag("source_import")
	local mesh = child(source, "MeshPart", "CornOriginal")
	mesh.Size = r.Vector3.new(2.4, 12, 3.6)
	mesh.CFrame = r.CFrame.new(14, 22, -7) * r.CFrame.Angles(0.1, 0.2, 0.3)
	mesh.MeshId = options.mesh or Appearance.MeshId
	mesh.TextureID = options.texture or Appearance.GreenTextureId
	mesh.Color = r.Color3.fromRGB(231, 224, 213)
	mesh.CanCollide, mesh.CanTouch, mesh.CanQuery = true, true, true
	mesh:SetAttribute("Imported", true)
	child(source, "AnimationController", "ImportMetadata")
	if options.surface then
		child(mesh, "SurfaceAppearance", "ManualAppearance")
	end
	local baseline = r.serializeModel({ source })
	local publications, warnings, prepared = {}, {}, {}
	local function observed(part)
		local proxy = {}
		return setmetatable(proxy, {
			__index = function(_, key)
				local value = part[key]
				if type(value) == "function" then
					return function(_, ...)
						return value(part, ...)
					end
				end
				return value
			end,
			__newindex = function(_, key, value)
				if key == "Parent" and value ~= nil then
					assert(part.TextureID == Appearance.DryTextureId, "Green art was published")
					assert(part.MeshId == Appearance.MeshId)
					table.insert(publications, { texture = part.TextureID, parent = value })
				end
				part[key] = value
			end,
		})
	end
	local layoutProxy = {
		Height = Layout.Height,
		PrepareTemplate = function(...)
			local part, problem = Layout.PrepareTemplate(...)
			if not part then
				return nil, problem
			end
			table.insert(prepared, part)
			return observed(part), nil
		end,
	}
	local config = { Environment = "DEV", Game = { SessionMode = "solo_local" } }
	local services = {
		ReplicatedStorage = storage,
		ServerStorage = server,
		RunService = {
			IsStudio = function()
				return options.studio ~= false
			end,
		},
	}
	local module = loadSource("src/server/Game/CornField.luau", {
		game = {
			GetService = function(_, name)
				return services[name]
			end,
		},
		Instance = I,
		require = function(target)
			if target.Name == "CornLayout" then
				return layoutProxy
			end
			if target.Name == "CornAppearance" then
				return Appearance
			end
			assert(target.Name == "GameConfig")
			return config
		end,
		warn = function(message)
			table.insert(warnings, message)
		end,
		print = function() end,
	})
	return module, storage, source, baseline, publications, warnings, prepared, server, config
end
local module, storage, source, baseline, publications = setup()
assert(module.Prepare())
local art = assert(storage:FindFirstChild("CornRuntimeArt"))
local first = assert(art:FindFirstChild("CornPlantTemplate"))
assert(#publications == 1 and first.TextureID == Appearance.DryTextureId)
assert(first.Size.Y == 8 and first:GetAttribute("CornPlantTemplateOwned") == true)
assert(first.Anchored and not first.CanCollide and not first.CanTouch and not first.CanQuery)
assert(r.serializeModel({ source }) == baseline, "Author import changed")
-- Both renderer creation paths clone before Parent; the first clone state is already yellow.
for _, name in { "Corn", "Far_0_0" } do
	local clone = first:Clone()
	assert(clone.Parent == nil and clone.TextureID == Appearance.DryTextureId)
	clone.Name = name
	clone.Parent = I.new("Folder")
	assert(clone.TextureID == Appearance.DryTextureId)
end
assert(module.Prepare() and #publications == 2)
local current = assert(art:FindFirstChild("CornPlantTemplate"))
assert(current ~= first and current.TextureID == Appearance.DryTextureId)
assert(r.serializeModel({ source }) == baseline)
print(
	"PASS: production prepare publishes dry before Parent, clones inherit dry, repeat and exact original import preserved"
)
for _, options in
	{
		{ mesh = "rbxassetid://999" },
		{ texture = "rbxassetid://999" },
		{ surface = true },
	}
do
	local bad, badStorage, badSource, badBaseline, published, warnings = setup(options)
	assert(not bad.Prepare() and #published == 0 and #warnings == 1)
	assert(not badStorage:FindFirstChild("CornRuntimeArt"))
	assert(r.serializeModel({ badSource }) == badBaseline)
end
for _, badContainer in { "class", "owner", "project", "template", "duplicate" } do
	local bad, badStorage, badSource, badBaseline, published = setup()
	local folder =
		child(badStorage, if badContainer == "class" then "Model" else "Folder", "CornRuntimeArt")
	folder:SetAttribute("CornRuntimeArtOwned", badContainer ~= "owner")
	folder:SetAttribute(
		"corn_project_id",
		if badContainer == "project" then "other" else "children_of_corn"
	)
	local retained = child(folder, "MeshPart", "CornPlantTemplate")
	retained.TextureID = "rbxassetid://retained"
	retained:SetAttribute("CornPlantTemplateOwned", badContainer ~= "template")
	if badContainer == "duplicate" then
		child(badStorage, "Folder", "CornRuntimeArt")
	end
	local before = r.serializeModel({ folder })
	assert(not bad.Prepare() and #published == 0)
	assert(
		r.serializeModel({ folder }) == before and r.serializeModel({ badSource }) == badBaseline
	)
end
local dry, _, drySource, dryBaseline, dryPublished = setup({ texture = Appearance.DryTextureId })
assert(dry.Prepare() and #dryPublished == 1 and r.serializeModel({ drySource }) == dryBaseline)
for _, kind in { "studio", "environment", "mode", "duplicate-source" } do
	local inactive, inactiveStorage, _, _, published, _, _, server, config =
		setup({ studio = kind ~= "studio" })
	if kind == "environment" then
		config.Environment = "PROD"
	end
	if kind == "mode" then
		config.Game.SessionMode = "multiplayer"
	end
	if kind == "duplicate-source" then
		child(server, "Model", "CornPlantTemplate")
	end
	assert(
		not inactive.Prepare()
			and #published == 0
			and not inactiveStorage:FindFirstChild("CornRuntimeArt")
	)
end
print(
	"PASS: unknown mesh/texture/SurfaceAppearance and 9 ownership/session/duplicate guards publish nothing and preserve existing art"
)
