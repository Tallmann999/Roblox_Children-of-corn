-- Actual controller code with real Lune CFrames and deterministic event/camera adapter.
-- No Studio rendering or FPS result is claimed.
local fs = require("@lune/fs")
local r = require("@lune/roblox")
local CF, V3 = r.CFrame, r.Vector3
local reads, descReads, connected, disconnected = 0, 0, 0, 0
local function signal()
	local listeners = {}
	return {
		Connect = function(_, callback)
			local connection = { Connected = true }
			connected += 1
			function connection:Disconnect()
				if self.Connected then
					self.Connected = false
					disconnected += 1
				end
			end
			table.insert(listeners, { Connection = connection, Callback = callback })
			return connection
		end,
		Fire = function(_, ...)
			for _, listener in listeners do
				if listener.Connection.Connected then
					listener.Callback(...)
				end
			end
		end,
	}
end
local function node(class, name)
	local object = {
		ClassName = class,
		Name = name,
		Parent = nil,
		Children = {},
		Attributes = {},
		Signals = {},
		ChildAdded = signal(),
		ChildRemoved = signal(),
		AncestryChanged = signal(),
	}
	function object:IsA(kind)
		return kind == self.ClassName or (kind == "BasePart" and self.ClassName == "Part")
	end
	function object:GetAttribute(name)
		return self.Attributes[name]
	end
	function object:SetAttribute(name, value)
		if self.Attributes[name] ~= value then
			self.Attributes[name] = value
			if self.Signals[name] then
				self.Signals[name]:Fire()
			end
		end
	end
	function object:GetAttributeChangedSignal(name)
		if not self.Signals[name] then
			self.Signals[name] = signal()
		end
		return self.Signals[name]
	end
	function object:GetChildren()
		reads += 1
		return table.clone(self.Children)
	end
	function object:GetDescendants()
		descReads += 1
		local result = {}
		local function visit(parent)
			for _, child in parent.Children do
				table.insert(result, child)
				visit(child)
			end
		end
		visit(self)
		return result
	end
	function object:FindFirstChildOfClass(class)
		for _, child in self.Children do
			if child.ClassName == class then
				return child
			end
		end
		return nil
	end
	function object:FindFirstChild(name)
		for _, child in self.Children do
			if child.Name == name then
				return child
			end
		end
		return nil
	end
	return object
end
local function parent(object, nextParent)
	local previous = object.Parent
	if previous then
		for index, child in previous.Children do
			if child == object then
				table.remove(previous.Children, index)
				break
			end
		end
	end
	object.Parent = nextParent
	object.AncestryChanged:Fire(object, nextParent)
	if previous then
		previous.ChildRemoved:Fire(object)
	end
	if nextParent then
		table.insert(nextParent.Children, object)
		nextParent.ChildAdded:Fire(object)
	end
end
local world = node("Workspace", "Workspace")
local camera = { CFrame = CF.new(0, 5, 0), Visible = true }
function camera:WorldToViewportPoint(position)
	local point = self.CFrame:PointToObjectSpace(position)
	return V3.new(point.X, point.Y, -point.Z), self.Visible and point.Z < 0
end
world.CurrentCamera = camera
local character = node("Model", "Player")
local humanoid = node("Humanoid", "Humanoid")
humanoid.Health, humanoid.MoveDirection = 100, V3.zero
parent(humanoid, character)
local playerRoot = node("Part", "HumanoidRootPart")
playerRoot.Position = V3.new(0, 3, 0)
parent(playerRoot, character)
local player = { Character = character }
local heartbeat = signal()
local fn = assert(loadstring(fs.readFile("src/client/Controllers/CornWindController.luau")))
setfenv(
	fn,
	setmetatable({
		game = {
			GetService = function(_, name)
				if name == "Workspace" then
					return world
				end
				if name == "Players" then
					return { LocalPlayer = player }
				end
				if name == "RunService" then
					return {
						IsStudio = function()
							return true
						end,
						Heartbeat = heartbeat,
					}
				end
				error(name)
			end,
		},
		CFrame = CF,
		Vector3 = V3,
	}, { __index = getfenv() })
)
local Controller = fn()
local controller = setmetatable({}, { __index = Controller })
controller:Init({ Config = { Environment = "DEV", Game = { SessionMode = "solo_local" } } })
controller._clock = function()
	return 0
end
local map = node("Model", "CornMap")
map:SetAttribute("corn_project_id", "children_of_corn")
parent(map, world)
local near = node("Folder", "CornClientPlants")
near:SetAttribute("corn_project_id", "children_of_corn")
near:SetAttribute("CornClientRendererOwned", true)
parent(near, map)
local group = node("Folder", "Chunk_0:-1")
parent(group, near)
local far = node("Folder", "CornClientBackdrop")
far:SetAttribute("corn_project_id", "children_of_corn")
far:SetAttribute("CornClientBackdropOwned", true)
far:SetAttribute("CornEditorOverview", true)
far:SetAttribute("Ready", true)
parent(far, map)
local runtime = node("Folder", "CornRoundRuntime")
runtime:SetAttribute("corn_project_id", "children_of_corn")
parent(runtime, map)
local monster = node("Model", "Monster")
monster:SetAttribute("CornMonsterOwned", true)
monster:SetAttribute("corn_project_id", "children_of_corn")
monster:SetAttribute("MonsterRigVersion", 1)
monster:SetAttribute("MonsterIndex", 1)
monster:SetAttribute("HuntState", "dormant")
parent(monster, runtime)
local monsterRoot = node("Part", "Root")
monsterRoot.Position = V3.new(0, 3, -30)
parent(monsterRoot, monster)
local originals = {}
local function plant(layer, position, name)
	local part = node("Part", name or "Corn")
	part.CFrame, part.Size = CF.new(position) * CF.Angles(0, 0.6, 0), V3.new(1.2, 8, 1.8)
	part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
	part.Transparency, part.LocalTransparencyModifier = 0, 0
	if layer == far then
		part:SetAttribute("CornClientBackdropOwned", true)
		part:SetAttribute("corn_project_id", "children_of_corn")
	else
		part:SetAttribute("CornPlantTemplateOwned", true)
	end
	originals[part] = part.CFrame
	parent(part, layer)
	return part
end
local a = plant(group, V3.new(-1, 4, -2))
local b = plant(group, V3.new(1, 4, -3))
local c = plant(group, V3.new(2, 4, -4))
local behind = plant(group, V3.new(0, 4, 3))
local remoteA = plant(far, V3.new(-1, 4, -31), "Far_0_-10")
local remoteB = plant(far, V3.new(1, 4, -32), "Far_1_-10")
local distant = plant(far, V3.new(220, 4, -220), "Far_74_-74")
local author = node("Part", "Author")
author.CFrame = CF.new(2, 4, -2)
parent(author, map)
local authorFrame = author.CFrame
controller:Start()
local afterStart = connected
controller:Start()
assert(connected == afterStart, "Duplicate Start connection")
local function ticks(count, dt)
	for _ = 1, count do
		heartbeat:Fire(dt or 0.2)
	end
end
local function restored(message)
	for part, frame in originals do
		assert(part.CFrame == frame, message)
	end
end
controller:SetMode("hard")
ticks(5)
restored("Stationary player created general wind")
assert(controller._lastWrites == 0 and controller._lastScanned == 0)
humanoid.MoveDirection = V3.new(0, 0, -1)
ticks(1)
assert(
	a.CFrame ~= originals[a] and b.CFrame ~= originals[b],
	"Two closest front plants did not react"
)
assert(c.CFrame == originals[c] and behind.CFrame == originals[behind], "Moved extra/behind plants")
assert(remoteA.CFrame == originals[remoteA] and distant.CFrame == originals[distant])
assert(author.CFrame == authorFrame and controller._lastWrites == 2)
for _, part in { a, b } do
	local base = originals[part].Position - V3.new(0, part.Size.Y / 2, 0)
	local localBase = originals[part]:PointToObjectSpace(base)
	assert(
		(part.CFrame:PointToWorldSpace(localBase) - base).Magnitude < 0.0001,
		"Ground anchor shifted"
	)
	local tilt = math.acos(math.clamp(part.CFrame.UpVector:Dot(originals[part].UpVector), -1, 1))
	assert(tilt <= math.rad(3) + 0.00001, "Reaction tilt exceeded3deg")
end
local held = a.CFrame
heartbeat:Fire(0.01)
assert(a.CFrame == held, "12Hz throttle failed")
humanoid.MoveDirection = V3.zero
ticks(4)
restored("Stopped player left persistent wind")
for _, mode in { "easy", "medium", "hard" } do
	controller:SetMode(mode)
	humanoid.MoveDirection = V3.new(0, 0, -1)
	ticks(1)
	assert(controller._lastNear == 2, "Contact reaction missing in " .. mode)
	controller:SetMode(nil)
	restored("Mode off did not exactly restore")
end
controller:SetMode("hard")
humanoid.MoveDirection = V3.new(0, 0, -1)
monster:SetAttribute("HuntState", "patrol")
ticks(1)
assert(remoteA.CFrame == originals[remoteA], "Monster moved plants before actual movement")
monsterRoot.Position = V3.new(0.3, 3, -30)
ticks(1)
assert(controller._lastNear == 2 and controller._lastFar == 2 and #controller._selected == 4)
assert(remoteA.CFrame ~= originals[remoteA] and remoteB.CFrame ~= originals[remoteB])
monster:SetAttribute("HuntState", "trapped")
ticks(2)
assert(
	remoteA.CFrame == originals[remoteA] and remoteB.CFrame == originals[remoteB],
	"Trapped monster created wind"
)
-- Three moving NPCs still contribute only one nearest actor/two plants.
local function extraRig(index, z)
	local model = node("Model", "Monster" .. index)
	model:SetAttribute("CornMonsterOwned", true)
	model:SetAttribute("corn_project_id", "children_of_corn")
	model:SetAttribute("MonsterRigVersion", 1)
	model:SetAttribute("MonsterIndex", index)
	model:SetAttribute("HuntState", "chase")
	parent(model, runtime)
	local root = node("Part", "Root")
	root.Position = V3.new(0, 3, z)
	parent(root, model)
	return model, root
end
local secondMonster, secondRoot = extraRig(2, -20)
local thirdMonster, thirdRoot = extraRig(3, -40)
local fourthMonster, fourthRoot = extraRig(4, -10)
local secondA = plant(far, V3.new(-1, 4, -20), "Far_0_-6")
local secondB = plant(far, V3.new(1, 4, -21), "Far_1_-6")
local thirdA = plant(far, V3.new(-1, 4, -40), "Far_0_-13")
local thirdB = plant(far, V3.new(1, 4, -41), "Far_1_-13")
ticks(1)
secondRoot.Position += V3.new(0.3, 0, 0)
thirdRoot.Position += V3.new(0.3, 0, 0)
fourthRoot.Position += V3.new(0.3, 0, 0)
local actorFrames = { secondRoot.Position, thirdRoot.Position, fourthRoot.Position }
ticks(1)
assert(
	controller._monsterRoot == secondRoot
		and secondA.CFrame ~= originals[secondA]
		and secondB.CFrame ~= originals[secondB],
	"Nearest moving reinforcement did not animate"
)
assert(
	thirdA.CFrame == originals[thirdA]
		and thirdB.CFrame == originals[thirdB]
		and #controller._selected <= 4
		and controller._lastWrites <= 32,
	"Three NPCs expanded corn budget"
)
assert(
	secondRoot.Position == actorFrames[1]
		and thirdRoot.Position == actorFrames[2]
		and fourthRoot.Position == actorFrames[3],
	"Wind wrote authoritative roots"
)
secondMonster:SetAttribute("HuntState", "trapped")
thirdRoot.Position += V3.new(0.3, 0, 0)
ticks(1)
assert(
	controller._monsterRoot == thirdRoot and thirdA.CFrame ~= originals[thirdA],
	"Trapped nearest masked moving farther NPC"
)
assert(secondA.CFrame == originals[secondA] and secondB.CFrame == originals[secondB])
thirdMonster:SetAttribute("corn_project_id", "foreign")
secondMonster:SetAttribute("HuntState", "chase")
secondMonster:SetAttribute("MonsterIndex", 3)
secondRoot.Position += V3.new(0.3, 0, 0)
thirdRoot.Position += V3.new(0.3, 0, 0)
ticks(1)
assert(
	controller._monsterRoot == nil and thirdA.CFrame == originals[thirdA],
	"Foreign/index/fourth NPC created wind"
)
for _, model in { secondMonster, thirdMonster, fourthMonster } do
	parent(model, nil)
end
for _, part in { secondA, secondB, thirdA, thirdB } do
	parent(part, nil)
end
-- A live stationary player on a stump sees only the monster's local disturbance.
humanoid.MoveDirection = V3.zero
playerRoot.Position = V3.new(0, 35, 0)
camera.CFrame = CF.new(0, 40, 0)
monster:SetAttribute("HuntState", "chase")
ticks(2)
monsterRoot.Position = V3.new(0.6, 3, -30)
ticks(1)
assert(
	a.CFrame == originals[a] and b.CFrame == originals[b],
	"Stump elevated player animated ground corn"
)
assert(controller._lastFar == 2, "Elevated view lost visible moving monster corn")
humanoid.Health = 0
ticks(1)
restored("Dead player retained reaction")
humanoid.Health = 100
playerRoot.Position = V3.new(0, 3, 0)
camera.CFrame = CF.new(0, 5, 0)
humanoid.MoveDirection = V3.new(0, 0, -1)
monster:SetAttribute("HuntState", "stopped")
ticks(1)
a.LocalTransparencyModifier = 1
ticks(1)
assert(a.CFrame == originals[a], "Invisible stalk retained motion")
a.LocalTransparencyModifier = 0
camera.Visible = false
ticks(1)
restored("Offscreen plants retained motion")
camera.Visible = true
playerRoot.Position = V3.new(500, 3, 500)
camera.CFrame = CF.new(500, 5, 500)
ticks(1)
restored("Leaving contact radius retained motion")
playerRoot.Position = V3.new(0, 3, 0)
camera.CFrame = CF.new(0, 5, 0)
ticks(1)
parent(a, nil)
assert(a.CFrame == originals[a] and controller._layers.near.Count == 3)
local fresh = plant(group, V3.new(-0.5, 4, -1.5))
ticks(1)
assert(fresh.CFrame ~= originals[fresh], "Event-added stalk not indexed")
parent(group, nil)
assert(fresh.CFrame == originals[fresh] and next(controller._layers.near.Groups) == nil)
monster:SetAttribute("HuntState", "chase")
ticks(1)
monsterRoot.Position = V3.new(0.8, 3, -30)
ticks(1)
far:SetAttribute("Ready", false)
assert(remoteA.CFrame == originals[remoteA] and remoteB.CFrame == originals[remoteB])
far:SetAttribute("Ready", true)
monsterRoot.Position = V3.new(1, 3, -30)
ticks(1)
parent(far, nil)
assert(remoteA.CFrame == originals[remoteA] and controller._layers.far == nil)
parent(far, map)
parent(group, near)
for index = 1, 3000 do
	plant(far, V3.new(1000 + index * 6, 4, -1000), "Far_" .. tostring(1000 + index) .. "_-99")
end
local beforeCount = controller._layers.near.Count + controller._layers.far.Count
heartbeat:Fire(0.01)
assert(
	controller._layers.near.Count + controller._layers.far.Count - beforeCount <= 64,
	"Index batch exceeded64"
)
while controller._pendingTail > 0 do
	heartbeat:Fire(0.01)
end
local indexedReads, indexedDesc = reads, descReads
for _ = 1, 30 do
	monsterRoot.Position += V3.new(0.05, 0, 0)
	ticks(1)
	assert(controller._lastNear + controller._lastFar <= 4 and controller._lastWrites <= 32)
	assert(controller._lastScanned <= 256, "Spatial lookup scanned distant field")
end
assert(
	reads == indexedReads and descReads == indexedDesc,
	"Reaction repeatedly rescanned whole layer"
)
-- Imported multi-part plants must still obey the same four-plant/32-part ceiling.
for part in originals do
	part.Transparency = 1
end
local function modelPlant(position)
	local model = node("Model", "Corn")
	model:SetAttribute("CornPlantTemplateOwned", true)
	function model:GetBoundingBox()
		return CF.new(position), V3.new(1.2, 8, 1.8)
	end
	for index = 1, 8 do
		plant(model, position + V3.new(index * 0.02, 0, 0), "Part" .. tostring(index))
	end
	parent(model, group)
end
modelPlant(V3.new(-1, 4, -2))
modelPlant(V3.new(1, 4, -3))
modelPlant(V3.new(-1, 4, -31))
modelPlant(V3.new(1, 4, -32))
ticks(1)
monsterRoot.Position += V3.new(0.2, 0, 0)
ticks(1)
assert(
	#controller._selected == 4 and controller._lastWrites == 32,
	"Multi-part player+monster fixture did not exercise the32-part bound"
)
for _ = 1, 8 do
	controller:SetMode("easy")
	ticks(1)
	controller:SetMode(nil)
	restored("Repeated mode changes accumulated drift")
end
controller:SetMode("hard")
ticks(1)
near:SetAttribute("CornClientRendererOwned", false)
assert(controller._layers.near == nil)
for part, frame in originals do
	if part.Parent == group then
		assert(part.CFrame == frame, "Ownership loss retained motion")
	end
end
near:SetAttribute("CornClientRendererOwned", true)
ticks(3)
parent(map, nil)
assert(controller._map == nil and next(controller._layers) == nil)
restored("Map removal retained motion")
parent(map, world)
ticks(3)
controller:Destroy()
assert(controller._map == nil and next(controller._layers) == nil and controller._pendingTail == 0)
restored("Destroy retained motion")
assert(disconnected == connected, "Signal connections leaked")
print(
	"PASS: actual corn controller no ambient wind; 2 front/contact +2 nearest moving NPC stalks across3rigs/foreign+index+fourth guards, all modes, rooted<=3deg, no stationary/dead/trapped/elevated-player wind, stump view,12Hz/5Hz/4plant/32part/256candidate budgets, exact restore, no recurring scans, stream/ownership/Ready/map cleanup and no signal leaks"
)
