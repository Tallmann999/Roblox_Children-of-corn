-- Pure plugin lifecycle fixture. It executes the production factory without
-- reading a place, writing game properties, building meshes or running Studio.
local fs = require("@lune/fs")
local create = assert(loadstring(fs.readFile("studio-plugins/CornManualSceneEditor.luau")))()
assert(
	loadstring(fs.readFile("studio-plugins/CornManualSceneEditor.plugin.luau")),
	"Generated plugin entry does not compile"
)
local checks = 0
local function check(condition, message)
	checks += 1
	assert(condition, message)
end
local function fixture(options)
	options = options or {}
	local connected, disconnected = 0, 0
	local function signal()
		local listeners = {}
		return {
			Connect = function(_, callback)
				local entry = { Callback = callback, Active = true }
				table.insert(listeners, entry)
				connected += 1
				return {
					Disconnect = function()
						if entry.Active then
							disconnected += 1
						end
						entry.Active = false
					end,
				}
			end,
			Fire = function(_, ...)
				for _, entry in listeners do
					if entry.Active then
						entry.Callback(...)
					end
				end
			end,
		}
	end
	local function instance(class, name)
		local item =
			{ Name = name, ClassName = class, Children = {}, Attributes = {}, Signals = {} }
		function item:IsA(kind)
			return self.ClassName == kind
		end
		function item:FindFirstChild(key)
			return self.Children[key]
		end
		function item:GetAttribute(key)
			return self.Attributes[key]
		end
		function item:GetAttributeChangedSignal(key)
			self.Signals[key] = self.Signals[key] or signal()
			return self.Signals[key]
		end
		return item
	end
	local workspace = instance("Workspace", "Workspace")
	workspace.ChildAdded, workspace.ChildRemoved = signal(), signal()
	local storage = instance("ReplicatedStorage", "ReplicatedStorage")
	storage.DescendantAdded = signal()
	local shared, folder, module =
		instance("Folder", "GameShared"),
		instance("Folder", "Game"),
		instance("ModuleScript", "ManualScene")
	storage.Children.GameShared, shared.Children.Game = shared, folder
	if not options.missingModule then
		folder.Children.ManualScene = module
	end
	local map = instance("Model", "CornMap")
	map.Parent = workspace
	map.Attributes = {
		corn_project_id = "children_of_corn",
		HarvestArtVariant = "B",
		BManualAuthoringVersion = 1,
	}
	if options.variant then
		map.Attributes.HarvestArtVariant = options.variant
	end
	if options.project then
		map.Attributes.corn_project_id = options.project
	end
	if options.missingVersion then
		map.Attributes.BManualAuthoringVersion = nil
	end
	if not options.delayedMap then
		workspace.Children.CornMap = map
	end
	local slots, starts, props, marker =
		instance("Folder", "KeySlots"),
		instance("Folder", "CornerSpawns"),
		instance("Folder", "Props"),
		instance("Model", "ScarecrowMarker")
	map.Children.KeySlots, map.Children.CornerSpawns, map.Children.Props = slots, starts, props
	props.Children.ScarecrowMarker = marker
	local heartbeat, loaded, nameChanged, unloading = signal(), signal(), signal(), signal()
	local running = options.running or false
	local studio = options.studio ~= false
	local game = { Name = options.name or "Children_of_corn_B.rbxl", Loaded = loaded }
	function game:GetService(name)
		return if name == "Workspace"
			then workspace
			elseif name == "ReplicatedStorage" then storage
			else nil
	end
	function game:GetPropertyChangedSignal(name)
		check(name == "Name", "Plugin watched an unrelated game property")
		return nameChanged
	end
	local run = {
		IsRunning = function()
			return running
		end,
		IsStudio = function()
			return studio
		end,
	}
	local buttons = {}
	local plugin = {
		Unloading = unloading,
		CreateToolbar = function()
			return {
				CreateButton = function(_, id)
					buttons[id] = { Click = signal() }
					return buttons[id]
				end,
			}
		end,
	}
	local queue, warnings, selection = {}, {}, {}
	local restoreCalls, requireCalls = 0, 0
	local restoreModule = {
		RestoreEdit = function()
			restoreCalls += 1
			if options.restoreHook then
				options.restoreHook()
			end
			if options.fail then
				error("fixture restore failed", 0)
			end
			return { restoredCorn = 3 }
		end,
	}
	local guard = create({
		game = game,
		run = run,
		plugin = plugin,
		heartbeat = heartbeat,
		defer = function(callback)
			table.insert(queue, callback)
		end,
		require = function(required)
			check(required == module, "Plugin required an unexpected module")
			requireCalls += 1
			if options.requireHook then
				options.requireHook()
			end
			return restoreModule
		end,
		warn = function(message)
			table.insert(warnings, message)
		end,
		selection = {
			Set = function(_, items)
				selection = items
			end,
		},
	})
	local function flush()
		local count = 0
		while #queue > 0 do
			count += 1
			check(count < 12, "Plugin recursively rebuilt the scene")
			table.remove(queue, 1)()
		end
	end
	return {
		guard = guard,
		game = game,
		workspace = workspace,
		storage = storage,
		map = map,
		module = module,
		folder = folder,
		buttons = buttons,
		options = options,
		loaded = loaded,
		nameChanged = nameChanged,
		heartbeat = heartbeat,
		unloading = unloading,
		warnings = warnings,
		flush = flush,
		setRunning = function(value)
			running = value
		end,
		selection = function()
			return selection
		end,
		counts = function()
			return restoreCalls, requireCalls, connected, disconnected
		end,
		queue = queue,
		slots = slots,
		starts = starts,
		marker = marker,
	}
end

local f = fixture()
check(f.counts() == 0, "Startup restoration was not deferred")
f.flush()
check(f.counts() == 1 and f.guard.restored == 1, "Exact stopped B did not restore at startup")
check(
	f.buttons.CornManualRestore.Enabled and f.buttons.CornManualPoints.Enabled,
	"Valid map buttons disabled"
)
for _ = 1, 20 do
	f.heartbeat:Fire()
end
f.loaded:Fire()
f.nameChanged:Fire()
f.flush()
check(f.counts() == 1, "Unchanged frames/load events rebuilt the map")
f.buttons.CornManualPoints.Click:Fire()
local selected = f.selection()
check(
	#selected == 3
		and selected[1] == f.slots
		and selected[2] == f.starts
		and selected[3] == f.marker,
	"Wrong authoring points selected"
)
f.buttons.CornManualRestore.Click:Fire()
f.buttons.CornManualRestore.Click:Fire()
f.flush()
check(f.counts() == 2, "Manual refresh burst was not coalesced")
f.setRunning(true)
f.heartbeat:Fire()
f.guard.Restore()
f.guard.SelectPoints()
f.flush()
check(f.counts() == 2 and not f.buttons.CornManualRestore.Enabled, "Plugin restored during Play")
f.setRunning(false)
f.heartbeat:Fire()
check(f.counts() == 2, "Stop retry was not deferred")
f.flush()
check(f.counts() == 3, "First Stop did not retry restoration once")
f.setRunning(true)
f.heartbeat:Fire()
f.setRunning(false)
f.heartbeat:Fire()
f.flush()
check(f.counts() == 3, "Repeated Stop rebuilt the same loaded map")
f.guard.Destroy()
f.guard.Restore()
f.flush()
local calls, _, connected, disconnected = f.counts()
check(calls == 3 and connected == disconnected, "Unload leaked listeners or restored again")

for _, options in
	{
		{ name = "Children_of_corn.rbxl" },
		{ name = "Foreign.rbxl" },
		{ variant = "A" },
		{ project = "other" },
		{ studio = false },
		{ running = true },
	}
do
	f = fixture(options)
	f.guard.Restore()
	f.flush()
	check(
		f.counts() == 0 and not f.buttons.CornManualRestore.Enabled,
		"Foreign/non-Edit context restored"
	)
	f.guard.Destroy()
end
f = fixture({ delayedMap = true })
f.flush()
check(f.counts() == 0, "Absent map restored")
f.workspace.Children.CornMap = f.map
f.workspace.ChildAdded:Fire(f.map)
f.flush()
check(f.counts() == 1, "Late map did not restore")
f.workspace.Children.CornMap = nil
f.workspace.ChildRemoved:Fire(f.map)
f.guard.Restore()
f.flush()
check(f.counts() == 1 and not f.buttons.CornManualRestore.Enabled, "Removed map remained active")
f.guard.Destroy()

f = fixture({ missingModule = true, missingVersion = true })
f.flush()
check(f.counts() == 0, "Incomplete authoring setup restored")
f.map.Attributes.BManualAuthoringVersion = 1
f.map.Signals.BManualAuthoringVersion:Fire()
f.flush()
check(f.counts() == 0, "Missing module restored")
f.folder.Children.ManualScene = f.module
f.storage.DescendantAdded:Fire(f.module)
f.flush()
check(f.counts() == 1, "Late exact module did not restore")
f.guard.Destroy()

f = fixture()
f.options.requireHook = function()
	f.setRunning(true)
end
f.flush()
check(f.counts() == 0 and #f.warnings == 1, "Play race after require reached RestoreEdit")
f.guard.Destroy()
f = fixture()
f.options.requireHook = function()
	f.workspace.Children.CornMap = nil
end
f.flush()
check(f.counts() == 0, "Map replacement race reached RestoreEdit")
f.guard.Destroy()
f = fixture({ fail = true })
f.flush()
f.guard.Restore()
f.flush()
check(
	#f.warnings == 1 and f.guard.restored == 0,
	"Repeated failure spammed logs or counted as success"
)
f.options.fail = false
f.guard.Restore()
f.flush()
check(f.guard.restored == 1, "Explicit refresh did not recover after a failure")
f.guard.Destroy()
f = fixture()
f.options.restoreHook = function()
	f.loaded:Fire()
end
f.flush()
check(f.counts() == 1 and #f.queue == 0, "Restore callbacks recursively scheduled work")
f.guard.Destroy()
f = fixture()
local stoppedDuringRestore = false
f.options.restoreHook = function()
	if stoppedDuringRestore then
		return
	end
	stoppedDuringRestore = true
	f.setRunning(true)
	f.heartbeat:Fire()
	f.setRunning(false)
	f.heartbeat:Fire()
end
f.flush()
check(
	f.counts() == 2 and #f.queue == 0,
	"A Stop during a yielding restore lost its single deferred retry"
)
f.guard.Destroy()
f = fixture()
f.unloading:Fire()
f.flush()
check(f.counts() == 0, "Queued startup ran after plugin unload")
print(
	"PASS Studio manual editor: "
		.. checks
		.. " identity/lifecycle/race/coalescing/refusal checks; no native rendering claim"
)
