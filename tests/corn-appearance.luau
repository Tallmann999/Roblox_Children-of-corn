-- Actual appearance-controller methods and Lune MeshPart Instances.
-- Deterministic Heartbeat/clock adapter verifies logic and batch bounds, not GPU pixels/asset loading.
local adapter = require("./scene-adapter")
local fs, r, I = adapter.fs, adapter.r, adapter.I
local function loadSource(path, env)
	local fn = assert(loadstring(fs.readFile(path), path))
	setfenv(fn, setmetatable(env, { __index = getfenv() }))
	return fn()
end
local Appearance = loadSource("src/shared/Game/CornAppearance.luau", {})
assert(Appearance.MeshId == "rbxassetid://104111861186519")
assert(Appearance.GreenTextureId == "rbxassetid://137803536172445")
assert(Appearance.DryTextureId == "rbxassetid://103653296385119")
assert(
	Appearance.IsValidMode(nil)
		and Appearance.IsValidMode("easy")
		and Appearance.IsValidMode("medium")
		and Appearance.IsValidMode("hard")
)
for _, bad in { true, 17, {}, "unknown" } do
	assert(not Appearance.IsValidMode(bad))
end
assert(
	Appearance.IsDry("medium")
		and Appearance.IsDry("hard")
		and not Appearance.IsDry("easy")
		and Appearance.IsDry(nil)
)
local PROJECT = "children_of_corn"
local function signal()
	local entries = {}
	return {
		Connect = function(_, callback)
			local connection = {
				Connected = true,
				Disconnect = function(self)
					self.Connected = false
				end,
			}
			table.insert(entries, { connection, callback })
			return connection
		end,
		Fire = function(_, dt)
			for _, pair in entries do
				if pair[1].Connected then
					pair[2](dt)
				end
			end
		end,
		Entries = entries,
	}
end
local function node(name)
	return {
		Name = name,
		WaitForChild = function(_, child)
			return node(child)
		end,
	}
end
local function setup()
	local heartbeat = signal()
	local clockStep, clockValue = 0, 0
	local run = {
		IsStudio = function()
			return true
		end,
		Heartbeat = heartbeat,
	}
	local services =
		{ ReplicatedStorage = node("ReplicatedStorage"), RunService = run, Workspace = {} }
	local Module = loadSource("src/client/Controllers/CornAppearanceController.luau", {
		game = {
			GetService = function(_, name)
				return services[name]
			end,
		},
		require = function()
			return Appearance
		end,
		os = {
			clock = function()
				clockValue += clockStep
				return clockValue
			end,
		},
	})
	local controller = setmetatable({ _refresh = function() end }, { __index = Module })
	controller:Init({})
	controller:Start({ Config = { Environment = "DEV", Game = { SessionMode = "solo_local" } } })
	assert(
		controller._heartbeat and #heartbeat.Entries == 1,
		"DEV solo-local Start did not connect"
	)
	return controller, heartbeat, function(step)
		clockStep = step
		clockValue = 0
	end
end
local function root(controller, name, flag)
	local folder = I.new("Folder")
	folder.Name = name
	folder:SetAttribute(flag, true)
	folder:SetAttribute("corn_project_id", PROJECT)
	local record = { folder = folder, flag = flag, parts = {}, connections = {} }
	controller._roots[folder] = record
	return record
end
local function mesh(parent, name, attributes, texture)
	local item = I.new("MeshPart")
	item.Name = name or "Corn"
	item.MeshId = Appearance.MeshId
	item.TextureID = texture or Appearance.GreenTextureId
	item.Anchored = true
	item.CanCollide = false
	item.CanTouch = false
	item.CanQuery = false
	for key, value in attributes or {} do
		item:SetAttribute(key, value)
	end
	item.Parent = parent
	return item
end
local function drain(controller, heartbeat)
	local frames = 0
	while #controller._queue > 0 do
		heartbeat:Fire(1 / 60)
		frames += 1
		assert(frames < 100)
	end
	assert(controller._head == 1 and next(controller._queued) == nil)
end
local flags = { CornEditorOverview = true, corn_project_id = PROJECT }
local controller, heartbeat, clock = setup()
local overview = root(controller, "EditorFieldOverview", "CornEditorOverview")
local plants = {}
for i = 1, 700 do
	local item = mesh(overview.folder, "Owned_" .. i, flags)
	controller:_register(overview, item)
	plants[i] = item
end
controller:_register(overview, plants[1])
controller:_enqueue(plants[1])
assert(#controller._queue == 700, "Registration/queue did not deduplicate")
controller:SetMode("medium")
assert(#controller._queue == 700)
heartbeat:Fire(1 / 60)
local changed = 0
for _, item in plants do
	if item.TextureID == Appearance.DryTextureId then
		changed += 1
	end
end
assert(
	changed == 384,
	"Heartbeat batch must apply exactly the 384 cap with unbounded fixture clock"
)
drain(controller, heartbeat)
for _, item in plants do
	assert(item.TextureID == Appearance.DryTextureId)
end
controller:SetMode("hard")
drain(controller, heartbeat)
for _, item in plants do
	assert(item.TextureID == Appearance.DryTextureId)
end
for _, invalid in { "not_a_mode", 17, true, {} } do
	controller:SetMode(invalid)
	assert(controller._mode == "hard" and #controller._queue == 0)
end
controller:SetMode(nil)
drain(controller, heartbeat)
for _, item in plants do
	assert(item.TextureID == Appearance.DryTextureId, "Ready returned the field to green")
end
controller:SetMode("easy")
drain(controller, heartbeat)
for _, item in plants do
	assert(item.TextureID == Appearance.GreenTextureId)
end
controller:SetMode(nil)
clock(0.0005)
heartbeat:Fire(1 / 60)
changed = 0
for _, item in plants do
	if item.TextureID == Appearance.DryTextureId then
		changed += 1
	end
end
assert(changed > 0 and changed < 384, "2 ms clock did not stop the batch")
clock(0)
drain(controller, heartbeat)
print(
	"PASS: asset whitelist, ready/hard yellow, DEV Start, duplicate registration and 384/2ms batch guards"
)
local art = root(controller, "CornRuntimeArt", "CornRuntimeArtOwned")
local prepared =
	mesh(art.folder, "CornPlantTemplate", { CornPlantTemplateOwned = true, CornPlantHeight = 8 })
controller:_register(art, prepared)
drain(controller, heartbeat)
assert(prepared.TextureID == Appearance.DryTextureId)
local near = root(controller, "CornClientPlants", "CornClientRendererOwned")
local chunk = I.new("Folder")
chunk.Name = "Chunk_0_0"
chunk.Parent = near.folder
local inherited = prepared:Clone()
inherited.Name = "Corn"
inherited.Parent = chunk
assert(
	inherited:GetAttribute("corn_project_id") == nil,
	"Fixture accidentally added a near per-part project flag"
)
controller:_register(near, inherited)
assert(controller._entries[inherited].texture == Appearance.DryTextureId)
controller:SetMode("easy")
drain(controller, heartbeat)
assert(
	inherited.TextureID == Appearance.DryTextureId
		and prepared.TextureID == Appearance.GreenTextureId
)
local savedYellow = mesh(overview.folder, "SavedYellow", flags, Appearance.DryTextureId)
controller:_register(overview, savedYellow)
drain(controller, heartbeat)
assert(savedYellow.TextureID == Appearance.DryTextureId)
controller:SetMode(nil)
drain(controller, heartbeat)
assert(
	savedYellow.TextureID == Appearance.DryTextureId
		and inherited.TextureID == Appearance.DryTextureId
)
local far = root(controller, "CornClientBackdrop", "CornClientBackdropOwned")
local farPart = mesh(
	far.folder,
	"Far_0_0",
	{ CornEditorOverview = true, CornClientBackdropOwned = true, corn_project_id = PROJECT }
)
controller:_register(far, farPart)
assert(controller._entries[farPart], "Owned far copy was rejected")
local rejects = {
	mesh(overview.folder, "Unowned", {}),
	mesh(
		overview.folder,
		"WrongProject",
		{ CornEditorOverview = true, corn_project_id = "foreign" }
	),
	mesh(far.folder, "FarMissingOwnFlag", flags),
	mesh(chunk, "Corn", {}),
	mesh(near.folder, "Corn", { CornPlantTemplateOwned = true }),
	mesh(art.folder, "UnrelatedTemplate", { CornPlantTemplateOwned = true }),
	mesh(overview.folder, "ForeignMesh", flags),
	mesh(overview.folder, "ForeignURI", flags, "rbxassetid://12345"),
	mesh(overview.folder, "InteractiveCopy", flags),
	mesh(overview.folder, "SurfaceCopy", flags),
}
rejects[7].MeshId = "rbxassetid://9999"
rejects[9].CanQuery = true
local surface = I.new("SurfaceAppearance")
surface.Parent = rejects[10]
for i, item in rejects do
	local record = if i == 3
		then far
		elseif i == 4 or i == 5 then near
		elseif i == 6 then art
		else overview
	local original = item.TextureID
	controller:_register(record, item)
	assert(
		not controller._entries[item],
		"Unowned/foreign/unsupported appearance was accepted at reject " .. i
	)
	assert(item.TextureID == original)
end
drain(controller, heartbeat)
controller:SetMode("hard")
drain(controller, heartbeat)
local manual = plants[1]
manual.TextureID = "rbxassetid://9876"
controller:_apply(manual)
assert(not controller._entries[manual] and manual.TextureID == "rbxassetid://9876")
local foreignMesh = plants[2]
foreignMesh.MeshId = "rbxassetid://4567"
controller:_apply(foreignMesh)
assert(not controller._entries[foreignMesh] and foreignMesh.MeshId == "rbxassetid://4567")
local lostPart = plants[3]
lostPart:SetAttribute("CornEditorOverview", false)
controller:_apply(lostPart)
assert(not controller._entries[lostPart] and lostPart.TextureID == Appearance.GreenTextureId)
local lostRoot = farPart
far.folder:SetAttribute("CornClientBackdropOwned", false)
controller:_apply(lostRoot)
assert(not controller._entries[lostRoot] and lostRoot.TextureID == Appearance.GreenTextureId)
local removed = plants[4]
removed.Parent = nil
controller:_apply(removed)
assert(not controller._entries[removed] and removed.TextureID == Appearance.GreenTextureId)
local forgotten = plants[5]
controller:_forget(forgotten)
assert(
	not controller._entries[forgotten]
		and overview.parts[forgotten] == nil
		and forgotten.TextureID == Appearance.GreenTextureId
)
local overlay = plants[6]
local laterSurface = I.new("SurfaceAppearance")
laterSurface.Parent = overlay
controller:_apply(overlay)
assert(not controller._entries[overlay] and overlay.TextureID == Appearance.GreenTextureId)
print(
	"PASS: dry-template clone inheritance, actual near flags, far/overview guards, foreign mesh/URI/physics/SurfaceAppearance preservation, ownership loss and removal"
)
controller:Destroy()
assert(not heartbeat.Entries[1][1].Connected and controller._heartbeat == nil)
assert(
	next(controller._entries) == nil
		and next(controller._roots) == nil
		and #controller._queue == 0
		and next(controller._queued) == nil
)
assert(
	inherited.TextureID == Appearance.DryTextureId
		and prepared.TextureID == Appearance.GreenTextureId
		and savedYellow.TextureID == Appearance.DryTextureId
)
assert(manual.TextureID == "rbxassetid://9876")
assert(foreignMesh.MeshId == "rbxassetid://4567")
print(
	"PASS: Destroy disconnects actual registered Heartbeat and restores managed copies without overwriting manual unknown edits"
)
