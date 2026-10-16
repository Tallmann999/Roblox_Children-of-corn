-- Real controller scheduling/metadata ownership in a limited Lune event adapter.
local adapter = require("./scene-adapter")
local fs, r, I = adapter.fs, adapter.r, adapter.I
local signals, deferred, disconnected = {}, {}, 0
local function signal(item, name)
	if not signals[item] then
		signals[item] = {}
	end
	if signals[item][name] then
		return signals[item][name]
	end
	local entries = {}
	local result = {
		Connect = function(_, callback)
			local entry = { callback = callback, connected = true }
			table.insert(entries, entry)
			return {
				Disconnect = function()
					if entry.connected then
						disconnected += 1
					end
					entry.connected = false
				end,
			}
		end,
		Fire = function()
			for _, entry in entries do
				if entry.connected then
					entry.callback()
				end
			end
		end,
	}
	signals[item][name] = result
	return result
end
r.implementMethod("Instance", "GetAttributeChangedSignal", function(item, name)
	return signal(item, "attr:" .. name)
end)
r.implementMethod("Instance", "GetPropertyChangedSignal", function(item, name)
	return signal(item, "property:" .. name)
end)
local world, storage = I.new("Workspace"), I.new("ReplicatedStorage")
local shared, gameFolder, module = I.new("Folder"), I.new("Folder"), I.new("ModuleScript")
shared.Name, gameFolder.Name, module.Name = "GameShared", "Game", "HarvestArtGeometry"
shared.Parent, gameFolder.Parent, module.Parent = storage, shared, gameFolder
local map = I.new("Model")
map.Name = "CornMap"
map:SetAttribute("corn_project_id", "children_of_corn")
map.Parent = world
local function owner(item)
	item:SetAttribute("corn_project_id", "children_of_corn")
	item:SetAttribute("HarvestGeometryOwner", "harvest_warden_v1")
end
local root = I.new("Folder")
root.Name = "HarvestDecor"
owner(root)
root.Parent = map
local props, marker, home = I.new("Folder"), I.new("Model"), I.new("Folder")
props.Name, marker.Name, home.Name = "Props", "ScarecrowMarker", "HarvestWardenHome"
props.Parent, marker.Parent, home.Parent = map, props, marker
owner(home)
local function mesh(parent, name, stamp)
	local part = I.new("MeshPart")
	part.Name = name
	part.CFrame = r.CFrame.new(7, 8, 9)
	part.Size = r.Vector3.new(2, 3, 4)
	part.Transparency = 0.4
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Anchored = true
	if stamp then
		owner(part)
		part:SetAttribute("HarvestMeshKey", name)
	end
	part.Parent = parent
	return part
end
local fence = mesh(root, "Fence", true)
local warden = mesh(home, "Warden", true)
local unrelated = mesh(props, "UnrelatedArt", true)
local applied = {}
local applyCount = 0
local geometry = {
	Apply = function(part, key)
		assert(part ~= unrelated and key == part.Name, "Unowned/outside art applied")
		applied[part] = true
		applyCount += 1
		assert(
			part.CFrame == r.CFrame.new(7, 8, 9)
				and part.Size == r.Vector3.new(2, 3, 4)
				and math.abs(part.Transparency - 0.4) < 0.00001
				and not part.CanQuery,
			"Author properties changed"
		)
	end,
}
local warnings = 0
local fn = assert(loadstring(fs.readFile("src/client/Controllers/HarvestGeometryController.luau")))
setfenv(
	fn,
	setmetatable({
		game = {
			GetService = function(_, name)
				return if name == "Workspace"
					then world
					elseif name == "ReplicatedStorage" then storage
					else {
						IsStudio = function()
							return true
						end,
					}
			end,
		},
		require = function()
			return geometry
		end,
		task = {
			defer = function(callback)
				table.insert(deferred, callback)
			end,
		},
		warn = function()
			warnings += 1
		end,
	}, { __index = getfenv() })
)
local controller = fn()
controller:Init({ Config = { Environment = "DEV", Game = { SessionMode = "team_local" } } })
controller._map = map
controller:_ensure()
assert(
	applyCount == 2 and applied[fence] and applied[warden] and not applied[unrelated],
	"Both owned art roots were not restored: "
		.. tostring(controller._lastError)
		.. "/"
		.. tostring(applyCount)
)
local late = mesh(root, "Late", false)
controller:_ensure()
assert(
	not applied[late] and controller._lastError == nil,
	"Incomplete replicated metadata treated as foreign"
)
owner(late)
late:SetAttribute("HarvestMeshKey", "Late")
signal(late, "attr:HarvestMeshKey"):Fire()
signal(late, "attr:corn_project_id"):Fire()
assert(#deferred == 1, "Attribute bursts were not coalesced")
local callback = table.remove(deferred, 1)
callback()
assert(applied[late] and controller._lastError == nil, "Late metadata did not restore geometry")
root:SetAttribute("HarvestGeometryOwner", nil)
controller:_ensure()
assert(controller._lastError == nil, "Late root ownership metadata did not wait")
root:SetAttribute("HarvestGeometryOwner", "harvest_warden_v1")
signal(root, "attr:HarvestGeometryOwner"):Fire()
table.remove(deferred, 1)()
assert(controller._lastError == nil, "Root metadata event did not recover")
late:SetAttribute("corn_project_id", "foreign_game")
applied[late] = nil
controller:_ensure()
assert(not applied[late] and controller._lastError and warnings == 1, "Foreign metadata accepted")
controller:_ensure()
assert(warnings == 1, "Repeated errors spam warnings")
controller:Destroy()
assert(disconnected > 0, "Controller events were not disconnected")
signal(fence, "property:MeshContent"):Fire()
assert(#deferred == 0, "Destroyed controller still scheduled")
print(
	"PASS harvest-geometry-controller: both owned roots, property preservation, late part/root metadata, burst coalescing, foreign refusal and cleanup"
)
