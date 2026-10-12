-- Actual pure presentation and server model Sources; no Studio/FPS claim.
local fs = require("@lune/fs")
local r = require("@lune/roblox")
local CF, V3 = r.CFrame, r.Vector3
local function load(path, env)
	local fn = assert(loadstring(fs.readFile(path), path))
	setfenv(fn, setmetatable(env, { __index = getfenv() }))
	return fn()
end
local types = {
	CFrame = CF,
	Vector3 = V3,
	Vector2 = r.Vector2,
	Color3 = r.Color3,
	Enum = r.Enum,
	UDim2 = r.UDim2,
}
local Held = load("src/shared/Game/HandheldPresentation.luau", types)
local function close(a, b, message)
	local av, bv = { a:GetComponents() }, { b:GetComponents() }
	for index, value in av do
		assert(math.abs(value - bv[index]) < 0.00001, message)
	end
end
-- Record the actual server factories so held definitions cannot silently diverge.
local instance = {}
function instance.new(class)
	local object =
		{ ClassName = class, Children = {}, Attributes = {}, Shape = r.Enum.PartType.Block }
	function object:SetAttribute(name, value)
		self.Attributes[name] = value
	end
	setmetatable(object, {
		__newindex = function(self, key, value)
			if key == "Parent" then
				table.insert(value.Children, self)
			end
			rawset(self, key, value)
		end,
	})
	return object
end
local serverEnvironment = table.clone(types)
serverEnvironment.Instance = instance
local Models = load("src/server/Game/ItemModels.luau", serverEnvironment)
local factories = { key = Models.Key, energy = Models.Energy, trap = Models.Trap }
local scales = { key = 0.38, energy = 0.68, trap = 0.48 }
local expectedCounts = { key = 15, energy = 3, trap = 14 }
assert(table.isfrozen(Held) and #Held.Hands == 2 and Held.MaxParts == 24)
assert(
	#Held.Definitions("none") == 0
		and #Held.Definitions("empty") == 0
		and #Held.Definitions("invalid") == 0
)
for kind, factory in factories do
	local model = factory(CF.identity)
	local defs, sourceParts, names = Held.Definitions(kind), {}, {}
	assert(#defs == expectedCounts[kind] and #defs + #Held.Hands + 1 <= Held.MaxParts)
	assert(table.isfrozen(defs))
	for _, part in model.Children do
		if part.Name ~= "Anchor" then
			table.insert(sourceParts, part)
		end
	end
	assert(#sourceParts == #defs)
	for index, definition in defs do
		assert(
			table.isfrozen(definition) and not names[definition.name],
			"Mutable/duplicate model definition"
		)
		names[definition.name] = true
		local source, scale = sourceParts[index], scales[kind]
		assert(
			(definition.size - source.Size * scale).Magnitude < 0.00001,
			"Server dimension mismatch"
		)
		local frame = CF.new(source.CFrame.Position * scale)
			* (source.CFrame - source.CFrame.Position)
		close(definition.localFrame, frame, "Server geometry rotation/position mismatch")
		assert(
			definition.color == source.Color
				and definition.material == source.Material
				and definition.shape == source.Shape,
			"Server appearance mismatch"
		)
		assert(definition.size.X > 0 and definition.size.Y > 0 and definition.size.Z > 0)
	end
end

assert(
	Held.Duration("key") == 0 and Held.Duration("energy") == 0.9 and Held.Duration("trap") == 0.55
)
for _, kind in { "energy", "trap" } do
	local duration = Held.Duration(kind)
	assert(not Held.IsFinished(kind, -1) and not Held.IsFinished(kind, duration - 0.000001))
	assert(Held.IsFinished(kind, duration) and Held.IsFinished(kind, duration + 100))
	assert(Held.IsFinished(kind, 0 / 0) and Held.IsFinished(kind, math.huge))
	close(
		Held.GetPose(kind, 100, true),
		Held.GetPose(kind, duration, true),
		"Long frame/pause did not settle at exact end"
	)
	close(
		Held.GetPose(kind, -1, true),
		Held.GetPose(kind, 0, true),
		"Negative time extrapolated pose"
	)
end
close(
	Held.GetPose("key", 0.5, true),
	Held.GetPose("key", 0, false),
	"Passive key has a use animation"
)

local function corners(definition)
	local points = {}
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				table.insert(
					points,
					definition.localFrame:PointToWorldSpace(definition.size * V3.new(x, y, z) / 2)
				)
			end
		end
	end
	return points
end
local tested, closest = 0, -math.huge
for _, aspect in { 0.3, 0.56, 1, 16 / 9, 4 } do
	for _, kind in { "key", "energy", "trap" } do
		local defs = table.clone(Held.Definitions(kind))
		for _, hand in Held.Hands do
			table.insert(defs, hand)
		end
		for _, using in { false, true } do
			for index = 0, 120 do
				local elapsed = index / 100
				local pose = Held.GetPose(kind, elapsed, using, aspect)
				for _, component in { pose:GetComponents() } do
					assert(
						component == component and math.abs(component) < 4,
						"Unbounded/nonfinite pose"
					)
				end
				local x, y, z = pose.XVector, pose.YVector, pose.ZVector
				assert(
					math.abs(x.Magnitude - 1) < 0.00001
						and math.abs(x:Dot(y)) < 0.00001
						and x:Cross(y):Dot(z) > 0.99999,
					"Pose lost rigid orientation"
				)
				for _, definition in defs do
					for _, point in corners(definition) do
						local at = pose:PointToWorldSpace(point)
						closest = math.max(closest, at.Z)
						assert(at.Z <= -Held.NearClearance, "Item/hand crossed camera near plane")
					end
				end
				tested += 1
			end
		end
	end
end
local energyHeld, energySip = Held.GetPose("energy", 0, false), Held.GetPose("energy", 0.4, true)
assert(
	energySip.Position.Y > energyHeld.Position.Y and energySip.Position.X < energyHeld.Position.X,
	"Can did not raise toward mouth"
)
assert(
	math.acos(math.clamp(energySip.UpVector:Dot(energyHeld.UpVector), -1, 1)) > math.rad(45),
	"Can did not tilt for drinking"
)
local trapHeld, trapEnd = Held.GetPose("trap", 0, false), Held.GetPose("trap", 0.55, true)
assert(
	trapEnd.Position.Y < trapHeld.Position.Y and trapEnd.Position.Z < trapHeld.Position.Z,
	"Trap did not lower forward"
)
assert(
	Held.GetPose("energy", 0, false, 0.56).Position.X < energyHeld.Position.X,
	"Narrow viewport did not move model toward centre"
)
close(
	Held.GetPose("energy", 0, false, 0 / 0),
	energyHeld,
	"Malformed aspect did not use finite default"
)
close(Held.GetPose("energy", 0 / 0, true), energyHeld, "Malformed elapsed produced unstable pose")
-- Stateless absolute-time curves cannot accumulate drift or replay from delta input.
local jump = Held.GetPose("energy", 0.82, true)
for _ = 1, 1000 do
	close(Held.GetPose("energy", 0.82, true), jump, "Repeated timestamp accumulated drift")
end
print(
	"PASS: server-matching immutable15/3/14part geometry, <=18total with2hands+anchor, exact0.9/0.55duration/largeframe completion/passivekey, "
		.. tostring(tested)
		.. " finite rigid poses with camera near-clearance "
		.. tostring(-closest)
		.. ", raise/tilt/lowerforward/narrowviewport and deterministic no-drift time curves"
)
