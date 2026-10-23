-- Actual B torch polling + cached branch traversal through the Lune adapter.
local adapter = require("./scene-adapter")
local fs, r, I = adapter.fs, adapter.r, adapter.I
local CF, V3 = r.CFrame, r.Vector3
local signals = {}
local function signal(item, name)
	signals[item] = signals[item] or {}
	if not signals[item][name] then
		local callbacks = {}
		signals[item][name] = {
			Connect = function(_, callback)
				table.insert(callbacks, callback)
				return {
					Disconnect = function()
						table.clear(callbacks)
					end,
				}
			end,
			Fire = function(_, ...)
				for _, callback in callbacks do
					callback(...)
				end
			end,
		}
	end
	return signals[item][name]
end
for _, name in { "DescendantAdded", "DescendantRemoving" } do
	r.implementProperty("Instance", name, function(item)
		return signal(item, name)
	end)
end
r.implementMethod("Instance", "GetAttributeChangedSignal", function(item, name)
	return signal(item, name)
end)
local checks = 0
local function check(value, reason)
	assert(value, reason)
	checks += 1
end
local function child(parent, class, name)
	local item = I.new(class)
	item.Name, item.Parent = name, parent
	return item
end
local world, storage = I.new("Workspace"), I.new("ReplicatedStorage")
local modules = child(child(storage, "Folder", "GameShared"), "Folder", "Game")
child(modules, "ModuleScript", "CornLayout")
local map = child(world, "Model", "CornMap")
map:SetAttribute("corn_project_id", "children_of_corn")
map:SetAttribute("HarvestArtVariant", "B")
map:SetAttribute("BManualAuthoringVersion", 1)
local corn = child(map, "Folder", "CornAuthoring")
corn:SetAttribute("corn_project_id", "children_of_corn")
corn:SetAttribute("BManualAuthoringVersion", 1)
local props, slots, markers =
	child(map, "Folder", "Props"),
	child(map, "Folder", "KeySlots"),
	child(map, "Folder", "TorchMarkers")
local house, site = child(props, "Model", "HouseWest"), child(slots, "Model", "Site_A")
local root = child(child(world, "Model", "Character"), "Part", "HumanoidRootPart")
root.CFrame = CF.identity
local function torch(parent, x, project)
	local model = child(parent, "Model", "torch_test")
	model:SetAttribute("CornTorchOwned", true)
	model:SetAttribute("corn_project_id", project or "children_of_corn")
	local flame = child(model, "Part", "Flame")
	flame.CFrame, flame.PivotOffset, flame.LocalTransparencyModifier =
		CF.new(x, 0, 0), CF.identity, 0
	local fire = child(flame, "Fire", "Fire")
	fire.Enabled = true
	local light = child(flame, "PointLight", "Light")
	light.Enabled = true
	return { Model = model, Flame = flame, Fire = fire, Light = light }
end
local houseTorch, siteTorch, oldTorch = torch(house, 20), torch(site, 30), torch(markers, 50)
local farTorch, fadeTorch, foreign = torch(house, 95), torch(site, 260), torch(house, 40, "foreign")
local scans = 0
local source = fs.readFile("variants/B/client/Controllers/CornController.luau")
	:gsub("branch:GetDescendants%(%)", "fixtureDescendants(branch)")
	:gsub("root%.Position", "root.CFrame.Position")
local fn = assert(loadstring(source))
setfenv(
	fn,
	setmetatable({
		game = {
			GetService = function(_, name)
				return ({
					Workspace = world,
					ReplicatedStorage = storage,
					Players = { LocalPlayer = { Character = root.Parent } },
					RunService = {
						IsStudio = function()
							return true
						end,
					},
				})[name]
			end,
		},
		CFrame = CF,
		Vector3 = V3,
		require = function()
			return {
				Height = 8,
				AuthoringSource = function(value)
					return value and value:FindFirstChild("CornAuthoring")
				end,
			}
		end,
		fixtureDescendants = function(branch)
			assert(branch ~= corn and branch ~= map, "Torch handler scanned the full corn map")
			scans += 1
			return branch:GetDescendants()
		end,
	}, { __index = getfenv() })
)
local prototype = fn()
local controller = setmetatable({}, { __index = prototype })
controller:Init({ Config = { Environment = "DEV", Game = { SessionMode = "solo_local" } } })
controller._reconcile = function(self)
	self._map = nil
end
controller._createBatch = function() end
controller._pollElapsed = math.huge
controller:_step(1)
check(
	#controller._manualTorches == 5,
	"Nested house/site/legacy branches did not resolve all owned torches"
)
for _, item in { houseTorch, siteTorch, oldTorch } do
	check(item.Fire.Enabled and item.Light.Enabled, "Close torch did not enable fire/light")
end
check(farTorch.Fire.Enabled and not farTorch.Light.Enabled, "90-stud light threshold changed")
check(
	not fadeTorch.Fire.Enabled
		and not fadeTorch.Light.Enabled
		and math.abs(fadeTorch.Flame.LocalTransparencyModifier - 0.25) < 1e-6,
	"220-stud fire threshold or240..320fade changed"
)
local afterBuild = scans
controller:_step(1)
check(scans == afterBuild, "Unchanged torch polls rescanned authoring branches")
controller:SetLightingMode("easy")
controller:_step(1)
for _, item in { houseTorch, siteTorch, oldTorch, farTorch, fadeTorch } do
	check(
		not item.Fire.Enabled
			and not item.Light.Enabled
			and item.Flame.LocalTransparencyModifier == 1,
		"Easy mode left moved torches enabled"
	)
end
check(foreign.Fire.Enabled and foreign.Light.Enabled, "Foreign torch was changed")
controller:SetLightingMode("hard")
controller:_step(1)
houseTorch.Flame.CFrame = CF.new(250, 0, 0)
controller:_step(1)
check(
	not houseTorch.Fire.Enabled
		and not houseTorch.Light.Enabled
		and math.abs(houseTorch.Flame.LocalTransparencyModifier - 0.125) < 1e-6,
	"Moved torch did not use its current pivot"
)
local added = torch(site, 10)
signal(slots, "DescendantAdded"):Fire(added.Model)
controller:_step(1)
check(
	#controller._manualTorches == 6 and added.Fire.Enabled,
	"Added nested torch did not invalidate cache"
)
added.Model:SetAttribute("CornTorchOwned", false)
signal(added.Model, "CornTorchOwned"):Fire()
controller:_step(1)
check(#controller._manualTorches == 5, "Late ownership metadata did not invalidate cache")
local owned = oldTorch.Model
owned.Parent = nil
signal(markers, "DescendantRemoving"):Fire(owned)
controller:_step(1)
check(#controller._manualTorches == 4, "Removed torch stayed cached")
controller:_clearManualTorches()
check(
	controller._manualTorchMap == nil and #controller._manualTorchConnections == 0,
	"Torch watchers leaked"
)
print(
	"PASS: "
		.. checks
		.. " manual nested torch branches/easy-hard/distances/fade/current pivot/cache/invalidation/foreign guard checks"
)
