-- Actual Sources, real CFrames, deterministic event/replication adapter. No FPS claim.
local fs = require("@lune/fs")
local r = require("@lune/roblox")
local CF, V3 = r.CFrame, r.Vector3
local reads, descReads, connected, disconnected = 0, 0, 0, 0
local poseFn = assert(loadstring(fs.readFile("src/shared/Game/MonsterPose.luau")))
setfenv(
	poseFn,
	setmetatable(
		{ CFrame = CF, Vector3 = V3, Color3 = r.Color3, Enum = r.Enum },
		{ __index = getfenv() }
	)
)
local Pose = poseFn()
assert(#Pose.Parts == 9 and table.isfrozen(Pose.Rest) and table.isfrozen(Pose.Parts))
assert(Pose.HeightScale == 1.3 and Pose.FeetY == -3)
local definitions = {}
for _, definition in Pose.Parts do
	definitions[definition.Name] = definition
end
assert(math.abs(Pose.Rest.LeftLeg.Position.Y - definitions.LeftLeg.Size.Y / 2 + 3) < 0.000001)
assert(
	math.abs((Pose.Rest.Hat.Position.Y + definitions.Hat.Size.Y / 2 + 3) - 10.8 * 1.3) < 0.000001
)
assert(
	definitions.Coat.Size.X == 4
		and definitions.Coat.Size.Z == 2
		and math.abs(definitions.Coat.Size.Y - 9.1) < 0.000001
)
local function close(a, b, message)
	local aValues, bValues = { a:GetComponents() }, { b:GetComponents() }
	for index, value in aValues do
		assert(math.abs(value - bValues[index]) < 0.00001, message)
	end
end
for _, state in { "dormant", "stopped", "invalid" } do
	assert(Pose.Get(state, 2, true) == Pose.Rest)
end
assert(
	Pose.Get("chase", math.huge, true) == Pose.Rest and Pose.Get("chase", 0 / 0, true) == Pose.Rest
)
for _, state in { "patrol", "chase", "trapped", "capturing" } do
	for _, moving in { true, false } do
		for index = 0, 120 do
			local time = index / 30
			local pose = Pose.Get(state, time, moving)
			local count = 0
			for name, frame in pose do
				count += 1
				assert(Pose.Rest[name], "Unknown pose part")
				for _, value in { frame:GetComponents() } do
					assert(value == value and math.abs(value) <= 13, "Nonfinite/unbounded pose")
				end
			end
			assert(count == 9)
			for _, name in { "Hat", "LeftEye", "RightEye" } do
				close(
					pose.Head:ToObjectSpace(pose[name]),
					Pose.Rest.Head:ToObjectSpace(Pose.Rest[name]),
					"Head group detached"
				)
			end
			for _, side in { -1, 1 } do
				for _, kind in { "Arm", "Leg" } do
					local name = (if side < 0 then "Left" else "Right") .. kind
					local pivot = if kind == "Arm"
						then V3.new(side * 1.5, 3, 0)
						else V3.new(side, 0, 0)
					pivot = Pose.ScalePosition(pivot)
					local localPivot = Pose.Rest[name]:PointToObjectSpace(pivot)
					assert(
						(pose[name]:PointToWorldSpace(localPivot) - pivot).Magnitude < 0.00001,
						"Shoulder/hip anchor shifted"
					)
				end
			end
			if (state == "patrol" or state == "chase") and not moving then
				close(pose.LeftLeg, Pose.Rest.LeftLeg, "Stationary NPC pretended to walk")
				close(pose.RightLeg, Pose.Rest.RightLeg, "Stationary NPC pretended to walk")
			end
		end
	end
end
local walking = Pose.Get("chase", 0.15, true)
assert(walking.LeftLeg.LookVector.Y * walking.RightLeg.LookVector.Y < 0, "Gait legs not opposed")
local capturing = Pose.Get("capturing", 0.6, false)
assert(
	capturing.LeftArm.Position.Z < -1 and capturing.RightArm.Position.Z < -1,
	"Capture arms do not reach forward"
)
assert(Pose.Get("trapped", 0.2, false).LeftLeg ~= Pose.Rest.LeftLeg, "Trapped struggle missing")
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
	setmetatable(object, {
		__index = function(self, key)
			if key == "CFrame" then
				return rawget(self, "Frame")
			end
			if key == "Position" then
				return rawget(self, "Frame").Position
			end
			return nil
		end,
		__newindex = function(self, key, value)
			if key == "CFrame" then
				self.Writes = (self.Writes or 0) + 1
				rawset(self, "Frame", value)
			else
				rawset(self, key, value)
			end
		end,
	})
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

local world, replicated =
	node("Workspace", "Workspace"), node("ReplicatedStorage", "ReplicatedStorage")
local shared, sharedGame, poseModule =
	node("Folder", "GameShared"), node("Folder", "Game"), node("ModuleScript", "MonsterPose")
parent(shared, replicated)
parent(sharedGame, shared)
parent(poseModule, sharedGame)
for _, object in { replicated, shared, sharedGame } do
	function object:WaitForChild(name)
		return assert(self:FindFirstChild(name))
	end
end
local heartbeat = signal()
local controllerFn =
	assert(loadstring(fs.readFile("src/client/Controllers/MonsterAnimationController.luau")))
setfenv(
	controllerFn,
	setmetatable({
		game = {
			GetService = function(_, name)
				if name == "Workspace" then
					return world
				end
				if name == "ReplicatedStorage" then
					return replicated
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
		require = function(module)
			assert(module == poseModule)
			return Pose
		end,
	}, { __index = getfenv() })
)
local Controller = controllerFn()
local controller = setmetatable({}, { __index = Controller })
controller:Init({ Config = { Environment = "DEV", Game = { SessionMode = "solo_local" } } })
local map, runtime = node("Model", "CornMap"), node("Folder", "CornRoundRuntime")
map:SetAttribute("corn_project_id", "children_of_corn")
runtime:SetAttribute("corn_project_id", "children_of_corn")
parent(map, world)
parent(runtime, map)
local decorative = node("Folder", "CornClientBackdrop")
parent(decorative, map)
for index = 1, 3000 do
	parent(node("Part", "Distant" .. tostring(index)), decorative)
end
local function part(name, frame)
	local object = node("Part", name)
	object.CFrame = frame
	object.Anchored, object.CanCollide, object.CanTouch, object.CanQuery = true, false, false, false
	return object
end
local function rig()
	local model = node("Model", "Monster")
	model:SetAttribute("CornMonsterOwned", true)
	model:SetAttribute("corn_project_id", "children_of_corn")
	model:SetAttribute("MonsterRigVersion", 1)
	model:SetAttribute("HuntState", "dormant")
	local root = part("Root", CF.new(40, 17, -50) * CF.Angles(0, 0.6, 0))
	parent(root, model)
	model.PrimaryPart = root
	local parts = {}
	for _, definition in Pose.Parts do
		local p = part(definition.Name, root.CFrame * Pose.Rest[definition.Name])
		p.Size = definition.Size
		parts[definition.Name] = p
		parent(p, model)
	end
	parent(model, runtime)
	return model, root, parts
end
local model, root, parts = rig()
controller:Start()
local afterStart = connected
controller:Start()
assert(afterStart == connected, "Start duplicated connections")
local function tick(dt)
	heartbeat:Fire(dt or 1 / 30)
end
local function rest(rigRoot, rigParts, message)
	for name, p in rigParts do
		close(p.CFrame, rigRoot.CFrame * Pose.Rest[name], message)
	end
end
local rootWrites = root.Writes
tick()
assert(controller._lastWrites == 9, "Initial rest should be one bounded9part write")
for _ = 1, 60 do
	tick()
end
assert(
	controller._lastWrites == 0 and root.Writes == rootWrites,
	"Dormant animation mutated root/rest repeatedly"
)
model:SetAttribute("HuntState", "patrol")
tick()
assert(controller._lastWrites == 9)
close(parts.LeftLeg.CFrame, root.CFrame * Pose.Rest.LeftLeg, "Stationary NPC had walking leg pose")
local previous = parts.Head.CFrame
tick(0.001)
assert(parts.Head.CFrame == previous, "30Hz throttle failed")
root.CFrame = CF.new(41, 17, -50) * CF.Angles(0, 0.7, 0)
rootWrites = root.Writes
tick()
assert(parts.LeftLeg.CFrame ~= root.CFrame * Pose.Rest.LeftLeg and root.Writes == rootWrites)
model:SetAttribute("HuntState", "chase")
local before = 0
for _, p in parts do
	before += p.Writes
end
local indexedReads, indexedDesc = reads, descReads
for _ = 1, 600 do
	tick(1 / 60)
	assert(controller._lastWrites <= 9)
end
local after = 0
for _, p in parts do
	after += p.Writes
end
assert(after - before <= 9 * 302, "Controller exceeded30Hz write budget")
assert(reads == indexedReads and descReads == indexedDesc, "Animation scanned scene/rig repeatedly")
assert(root.Writes == rootWrites, "Animation wrote authoritativeRoot")
model:SetAttribute("HuntState", "trapped")
tick()
tick()
assert(parts.LeftLeg.CFrame ~= root.CFrame * Pose.Rest.LeftLeg)
model:SetAttribute("HuntState", "capturing")
for _ = 1, 20 do
	tick()
end
assert(parts.LeftArm.CFrame ~= root.CFrame * Pose.Rest.LeftArm)
model:SetAttribute("HuntState", "stopped")
rest(root, parts, "Stopped state did not instantly restore")
for _ = 1, 60 do
	tick()
end
assert(controller._lastWrites == 0)
model:SetAttribute("HuntState", "chase")
tick()
root.CFrame = CF.new(200, 18, 25) * CF.Angles(0, -1.2, 0)
rootWrites = root.Writes
model:SetAttribute("CornMonsterOwned", false)
assert(controller._model == nil)
rest(root, parts, "Ownership loss did not restore relative to currentRoot")
assert(root.Writes == rootWrites)
model:SetAttribute("CornMonsterOwned", true)
tick(0.5)
assert(controller._model == model, "Ownership recovery did not rebind")
local removed = parts.LeftArm
parent(removed, nil)
assert(controller._model == nil, "Part removal retained stale rig binding")
rest(root, parts, "Part removal retained procedural pose")
tick(0.5)
assert(controller._model == nil, "Partial streamed rig animated")
parent(removed, model)
tick(0.5)
assert(controller._model == model, "Complete streamin rig failed rebind")
local extra = part("ManualUnknownPart", CF.new())
parent(extra, model)
tick(0.5)
assert(controller._model == nil, "Unknown manual geometry animated")
parent(extra, nil)
tick(0.5)
assert(controller._model == model)
parent(model, nil)
assert(controller._model == nil)
rest(root, parts, "Removed model retained motion")
local newer, newRoot, newParts = rig()
newer:SetAttribute("HuntState", "chase")
tick()
assert(controller._model == newer)
parent(runtime, nil)
assert(controller._runtime == nil and controller._model == nil)
rest(newRoot, newParts, "Runtime removal retained motion")
parent(runtime, map)
tick(0.5)
assert(controller._model == newer)
map:SetAttribute("corn_project_id", "other")
assert(controller._map == nil and controller._model == nil)
rest(newRoot, newParts, "Mapownership loss retained motion")
map:SetAttribute("corn_project_id", "children_of_corn")
tick(0.5)
parent(map, nil)
assert(controller._map == nil)
rest(newRoot, newParts, "Map removal retained motion")
parent(map, world)
tick(0.5)
controller:Destroy()
rest(newRoot, newParts, "Destroy retained motion")
assert(
	controller._model == nil and controller._connection == nil and disconnected == connected,
	"Lifecycle leaked connections"
)
print(
	"PASS: actual MonsterPose grouped head/hat/eyes, fixed shoulder/hip anchors, opposed moving gait/no stationary steps, bounded finite9part poses; actualController30Hz/9writes/0Rootwrites, dormant/stopped write silence, no field/recurring scans, current-root restrestore and complete streaming/replacement/ownership/manualrig/Destroy cleanup"
)
