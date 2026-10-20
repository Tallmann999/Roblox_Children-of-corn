-- Exercise startup ordering, foreign scenes, automatic reset and unload ownership.
local fs = require("@lune/fs")
local create = assert(loadstring(fs.readFile("studio-plugins/CornStudioQualityGuard.luau")))()
local function signal()
	local callbacks = {}
	return {
		Connect = function(_, fn)
			local entry = { fn = fn, alive = true }
			table.insert(callbacks, entry)
			return {
				Disconnect = function()
					entry.alive = false
				end,
			}
		end,
		Fire = function(_, ...)
			for _, entry in callbacks do
				if entry.alive then
					entry.fn(...)
				end
			end
		end,
	}
end
local checks = 0
local function check(value, reason)
	assert(value, reason)
	checks += 1
end
local function fixture(name, variant, delayed)
	local queue, attrs, children, mapSignals =
		{}, { corn_project_id = "children_of_corn", HarvestArtVariant = variant }, {}, {}
	local ground, field =
		{
			Size = "630x2x630",
			IsA = function()
				return true
			end,
		}, {
			Size = "630x10x630",
			IsA = function()
				return true
			end,
		}
	local map = { Name = "CornMap", ChildAdded = signal(), ChildRemoved = signal() }
	function map:GetAttribute(key)
		return attrs[key]
	end
	function map:GetAttributeChangedSignal(key)
		mapSignals[key] = mapSignals[key] or signal()
		return mapSignals[key]
	end
	function map:FindFirstChild(key)
		return ({ Ground = ground, FieldZone = field })[key]
	end
	local workspace = { ChildAdded = signal(), ChildRemoved = signal() }
	function workspace:FindFirstChild(key)
		return children[key]
	end
	if not delayed then
		children.CornMap = map
	end
	local nameChanged = signal()
	local game = { Name = name, Loaded = signal() }
	function game:GetService(key)
		assert(key == "Workspace")
		return workspace
	end
	function game:GetPropertyChangedSignal(key)
		assert(key == "Name")
		return nameChanged
	end
	local values, changed, writes =
		{ QualityLevel = 0, EditQualityLevel = 0, FrameRateManager = "Auto" }, {}, {}
	local render = setmetatable({
		GetPropertyChangedSignal = function(_, key)
			changed[key] = changed[key] or signal()
			return changed[key]
		end,
	}, {
		__index = values,
		__newindex = function(_, key, value)
			assert(key == "QualityLevel" or key == "EditQualityLevel", "Unrequested setting write")
			values[key] = value
			table.insert(writes, key)
			if changed[key] then
				changed[key]:Fire()
			end
		end,
	})
	local heartbeat = signal()
	local guard = create({
		game = game,
		render = render,
		level = 21,
		groundSize = ground.Size,
		fieldSize = field.Size,
		defer = function(fn)
			table.insert(queue, fn)
		end,
		heartbeat = heartbeat,
	})
	local function flush()
		while #queue > 0 do
			table.remove(queue, 1)()
		end
	end
	return {
		guard = guard,
		game = game,
		render = render,
		attrs = attrs,
		map = map,
		children = children,
		workspace = workspace,
		ground = ground,
		values = values,
		writes = writes,
		flush = flush,
		heartbeat = heartbeat,
		nameChanged = nameChanged,
	}
end
for _, item in { { "Children_of_corn.rbxl", "A" }, { "Children_of_corn_B.rbxl", "B" } } do
	local f = fixture(item[1], item[2], false)
	check(
		f.guard.IsActive() and f.render.QualityLevel == 21 and f.render.EditQualityLevel == 21,
		"A/B startup must be fixed"
	)
	f.render.QualityLevel = 0
	f.flush()
	check(f.render.QualityLevel == 21, "Repair core startup Automatic reset")
	f.values.QualityLevel = 0
	f.heartbeat:Fire(0.3)
	check(f.render.QualityLevel == 21, "Repair reset even when engine emits no property event")
	f.guard.Destroy()
	f.flush()
	check(
		f.render.QualityLevel == 0 and f.render.EditQualityLevel == 0,
		"Unload restores only owned settings"
	)
	f.render.QualityLevel = 5
	f.flush()
	check(f.render.QualityLevel == 5, "Unloaded guard must not write")
end
for _, item in { { "Cooking.rbxl", "A" }, { "Children_of_corn_B.rbxl", "A" } } do
	local f = fixture(item[1], item[2], false)
	f.flush()
	check(
		not f.guard.IsActive() and #f.writes == 0,
		"Foreign filename/variant must not change graphics"
	)
	f.guard.Destroy()
end
local f = fixture("Children_of_corn_B.rbxl", "B", true)
check(not f.guard.IsActive() and #f.writes == 0, "No map during initial load")
f.children.CornMap = f.map
f.workspace.ChildAdded:Fire(f.map)
f.flush()
check(f.guard.IsActive() and f.render.QualityLevel == 21, "Late loaded map must activate")
f.game.Name = "Showroom.rbxlx"
f.nameChanged:Fire()
f.flush()
check(not f.guard.IsActive() and f.render.QualityLevel == 0, "Leaving Corn releases graphics")
f.guard.Destroy()
f = fixture("Children_of_corn_B.rbxl", "B", false)
f.render.QualityLevel = 7
f.guard.Destroy()
f.flush()
check(
	f.render.QualityLevel == 7 and f.render.EditQualityLevel == 0,
	"Unload must preserve a later foreign write"
)
f = fixture("Children_of_corn_B.rbxl", "B", false)
f.children.CornMap = nil
f.workspace.ChildRemoved:Fire(f.map)
f.flush()
check(not f.guard.IsActive() and f.render.QualityLevel == 0, "Removed map must release graphics")
f.guard.Destroy()
print(
	"PASS: Studio quality guard",
	checks,
	"meaningful lifecycle/ownership checks; no renderer claim"
)
