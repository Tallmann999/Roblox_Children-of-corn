--!strict

-- Camera-only geometry and poses. Gameplay and accepted-use history stay on server.
local Handheld = { MaxParts = 24, NearClearance = 0.65 }
local cf, v3 = CFrame.new, Vector3.new
local metal = Enum.Material.Metal
local block, cylinder = Enum.PartType.Block, Enum.PartType.Cylinder
type Definition = {
	name: string,
	size: Vector3,
	localFrame: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType,
}
local definitions: { [string]: { Definition } } = { key = {}, energy = {}, trap = {} }

local function add(
	kind: string,
	name: string,
	size: Vector3,
	frame: CFrame,
	color: Color3,
	scale: number,
	shape: Enum.PartType?
)
	-- Uniformly shrink positions and sizes, retaining the server object's rotations.
	local scaled = cf(frame.Position * scale) * (frame - frame.Position)
	table.insert(
		definitions[kind],
		table.freeze({
			name = name,
			size = size * scale,
			localFrame = scaled,
			color = color,
			material = metal,
			shape = shape or block,
		})
	)
end

local gold, steel = Color3.fromRGB(235, 192, 60), Color3.fromRGB(91, 100, 99)
for index = 1, 12 do
	local angle = index * math.pi / 6
	add(
		"key",
		"Ring" .. index,
		v3(0.26, 0.15, 0.42),
		cf(math.cos(angle) * 0.65, 0, -1 + math.sin(angle) * 0.65) * CFrame.Angles(0, -angle, 0),
		gold,
		0.38
	)
end
add("key", "Shaft", v3(0.23, 0.17, 1.95), cf(0, 0, 0.58), gold, 0.38)
for index = 1, 2 do
	add("key", "Tooth" .. index, v3(0.58, 0.17, 0.22), cf(0.2, 0, 0.75 + index * 0.36), gold, 0.38)
end

add(
	"energy",
	"Can",
	v3(1.25, 0.72, 0.72),
	CFrame.Angles(0, 0, math.pi / 2),
	Color3.fromRGB(38, 116, 65),
	0.68,
	cylinder
)
for _, side in { -1, 1 } do
	add(
		"energy",
		if side < 0 then "LidBottom" else "LidTop",
		v3(0.07, 0.74, 0.74),
		cf(0, side * 0.62, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(180, 192, 185),
		0.68,
		cylinder
	)
end

add("trap", "Plate", v3(0.16, 2.2, 2.2), CFrame.Angles(0, 0, math.pi / 2), steel, 0.48, cylinder)
for _, side in { -1, 1 } do
	local jaw = cf(side * 0.95, 0.18, 0)
	add("trap", if side < 0 then "LeftJaw" else "RightJaw", v3(0.18, 0.2, 2.15), jaw, steel, 0.48)
	for tooth = -2, 2 do
		add(
			"trap",
			(if side < 0 then "LeftTooth" else "RightTooth") .. tostring(tooth + 3),
			v3(0.16, 0.32, 0.18),
			jaw * cf(0, 0.2, tooth * 0.4),
			Color3.fromRGB(163, 170, 164),
			0.48
		)
	end
end
add("trap", "Trigger", v3(0.65, 0.13, 0.65), cf(0, 0.15, 0), Color3.fromRGB(154, 118, 62), 0.48)
for _, values in definitions do
	table.freeze(values)
end
table.freeze(definitions)
local empty = table.freeze({})

-- The controller uses avatar skin color and gives these parts the same safe flags.
Handheld.Hands = table.freeze({
	table.freeze({
		name = "RightHand",
		size = v3(0.19, 0.32, 0.25),
		localFrame = cf(0.24, -0.24, 0.24),
	}),
	table.freeze({
		name = "LeftHand",
		size = v3(0.19, 0.32, 0.25),
		localFrame = cf(-0.24, -0.3, 0.28),
	}),
})

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function Handheld.Definitions(kind: string): { Definition }
	return definitions[kind] or empty
end

function Handheld.Duration(kind: string): number
	return if kind == "energy" then 0.9 elseif kind == "trap" then 0.55 else 0
end

function Handheld.IsFinished(kind: string, elapsed: number): boolean
	return not finite(elapsed) or Handheld.Duration(kind) == 0 or elapsed >= Handheld.Duration(kind)
end

local function ease(progress: number): number
	local value = math.clamp(progress, 0, 1)
	return value * value * (3 - 2 * value)
end

local function held(kind: string, aspect: number): CFrame
	-- Narrow screens move the hand toward the centre without bringing it nearer.
	local right = 0.59 * math.clamp(aspect / 1.5, 0.45, 1)
	if kind == "key" then
		return cf(right, -0.6, -1.7) * CFrame.Angles(math.rad(65), math.rad(-8), math.rad(-18))
	elseif kind == "trap" then
		return cf(right, -0.68, -1.8) * CFrame.Angles(math.rad(55), math.rad(-8), math.rad(-12))
	end
	return cf(right, -0.6, -1.55) * CFrame.Angles(math.rad(-5), math.rad(-8), math.rad(-12))
end

function Handheld.GetPose(kind: string, elapsed: number, using: boolean, aspect: number?): CFrame
	local ratio = if finite(aspect) then math.clamp(aspect :: number, 0.3, 4) else 16 / 9
	local start = held(kind, ratio)
	if not using or Handheld.Duration(kind) == 0 or not finite(elapsed) then
		return start
	end
	local time = math.max(elapsed, 0)
	if kind == "energy" then
		local mouth = cf(0.16, -0.23, -1.45)
			* CFrame.Angles(math.rad(70), math.rad(-8), math.rad(-12))
		if time <= 0.27 then
			return start:Lerp(mouth, ease(time / 0.27))
		end
		if time <= 0.63 then
			return mouth
		end
		local lowered = cf(start.Position.X, -1.3, -1.7)
			* CFrame.Angles(math.rad(30), math.rad(-8), math.rad(-12))
		return mouth:Lerp(lowered, ease((time - 0.63) / 0.27))
	end
	local placed = cf(start.Position.X * 0.7, -1.85, -2.25)
		* CFrame.Angles(math.rad(8), 0, math.rad(-6))
	return start:Lerp(placed, ease(time / 0.55))
end

return table.freeze(Handheld)
