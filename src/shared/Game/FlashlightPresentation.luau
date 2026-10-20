--!strict

-- Pure camera-local geometry and motion. No Instances, input hooks or gameplay.
local Flashlight = { MaxParts = 11, NearClearance = 0.65 }
local cf, v3 = CFrame.new, Vector3.new
local TAU = 2 * math.pi
local SETTINGS = table.freeze({
	WalkSpeed = 12,
	WalkCadence = 1.7,
	MaxCadence = 2.1,
	MaxSprintScale = 1.35,
	MotionRate = 8,
	AimRate = 14,
	AimLimit = math.rad(2),
	MaxDt = 0.25,
	TeleportSpeed = 64,
	Lights = table.freeze({
		main = table.freeze({ range = 24, angle = 26, brightness = 22.62, shadows = false }),
		fill = table.freeze({ range = 24, angle = 54, brightness = 15.08, shadows = false }),
	}),
	HandFill = table.freeze({ range = 1.5, angle = 75, brightness = 0.08, shadows = false }),
	Pitch = -6,
})
Flashlight.Settings = SETTINGS
Flashlight.LensFrame = cf(0, 0, -0.442)
Flashlight.HandFillFrame = cf(0, 0.11, -0.1)
	* CFrame.Angles(0, math.pi, 0)
	* CFrame.Angles(-math.rad(35), 0, 0)

type Definition = {
	name: string,
	size: Vector3,
	localFrame: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType,
	isHand: boolean,
}
local definitions: { Definition } = {}
local function add(
	name: string,
	size: Vector3,
	frame: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?,
	isHand: boolean?
)
	table.insert(
		definitions,
		table.freeze({
			name = name,
			size = size,
			localFrame = frame,
			color = color,
			material = material,
			shape = shape or Enum.PartType.Block,
			isHand = isHand == true,
		})
	)
end
local dark, black, rim =
	Color3.fromRGB(27, 29, 31), Color3.fromRGB(12, 14, 16), Color3.fromRGB(65, 69, 73)
local cylinder = CFrame.Angles(0, math.pi / 2, 0)
add(
	"Body",
	v3(0.62, 0.18, 0.18),
	cf(0, 0, 0.08) * cylinder,
	dark,
	Enum.Material.Metal,
	Enum.PartType.Cylinder
)
add(
	"Head",
	v3(0.2, 0.25, 0.25),
	cf(0, 0, -0.31) * cylinder,
	black,
	Enum.Material.Metal,
	Enum.PartType.Cylinder
)
add(
	"Rim",
	v3(0.045, 0.27, 0.27),
	cf(0, 0, -0.4) * cylinder,
	rim,
	Enum.Material.Metal,
	Enum.PartType.Cylinder
)
add(
	"Lens",
	v3(0.018, 0.218, 0.218),
	cf(0, 0, -0.433) * cylinder,
	Color3.fromRGB(225, 232, 238),
	Enum.Material.Glass,
	Enum.PartType.Cylinder
)
add(
	"BackCap",
	v3(0.055, 0.195, 0.195),
	cf(0, 0, 0.417) * cylinder,
	black,
	Enum.Material.Metal,
	Enum.PartType.Cylinder
)
for index = 1, 3 do
	add(
		"GripRing" .. index,
		v3(0.035, 0.194, 0.194),
		cf(0, 0, 0.04 + index * 0.09) * cylinder,
		black,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Cylinder
	)
end
add("Switch", v3(0.075, 0.025, 0.1), cf(0, 0.1, -0.03), black, Enum.Material.SmoothPlastic)
local skin = Color3.fromRGB(197, 151, 113)
add(
	"LeftPalm",
	v3(0.245, 0.235, 0.27),
	cf(-0.035, -0.12, 0.22),
	skin,
	Enum.Material.SmoothPlastic,
	nil,
	true
)
add(
	"LeftThumb",
	v3(0.095, 0.175, 0.16),
	cf(0.105, -0.038, 0.2) * CFrame.Angles(0, 0, math.rad(-18)),
	skin,
	Enum.Material.SmoothPlastic,
	nil,
	true
)
table.freeze(definitions)

function Flashlight.Definitions(): { Definition }
	return definitions
end

type MotionState = {
	phase: number,
	idlePhase: number,
	travelSpeed: number,
	weight: number,
	lagPitch: number,
	lagYaw: number,
}
type Output = { view: CFrame, aim: CFrame, camera: CFrame, bobWeight: number }

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function number(value: any, fallback: number): number
	return if finite(value) then value else fallback
end

function Flashlight.Tuning(values: any): any
	local supplied = if type(values) == "table" then values else {}
	local result = {}
	for name, spec in { wide = SETTINGS.Lights.fill, core = SETTINGS.Lights.main } do
		local row = if type(supplied[name]) == "table" then supplied[name] else {}
		result[name] = {
			range = math.clamp(number(row.range, spec.range), 4, 64),
			angle = math.clamp(number(row.angle, spec.angle), 6, 100),
			brightness = math.clamp(number(row.brightness, spec.brightness), 0, 40),
			shadows = if type(row.shadows) == "boolean" then row.shadows else spec.shadows,
		}
	end
	local pose = if type(supplied.pose) == "table" then supplied.pose else {}
	result.pose = { pitch = math.clamp(number(pose.pitch, SETTINGS.Pitch), -30, 15) }
	return result
end

function Flashlight.NewState(): MotionState
	return table.freeze({
		phase = 0,
		idlePhase = 0,
		travelSpeed = 0,
		weight = 0,
		lagPitch = 0,
		lagYaw = 0,
	})
end

function Flashlight.Step(previous: any, delta: any, supplied: any): (MotionState, Output)
	local old = if type(previous) == "table" then previous else Flashlight.NewState()
	local input = if type(supplied) == "table" then supplied else {}
	local dt = if finite(delta) then math.clamp(delta, 0, SETTINGS.MaxDt) else 0
	local speed = math.max(number(input.speed, 0), 0)
	local reset = input.teleported == true
		or speed > SETTINGS.TeleportSpeed
		or not finite(delta)
		or (finite(delta) and delta > SETTINGS.MaxDt)
		or (input.speed ~= nil and not finite(input.speed))
	local phase = number(old.phase, 0) % TAU
	local idlePhase = (number(old.idlePhase, 0) + dt * TAU * 0.24) % TAU
	local travelSpeed =
		math.clamp(number(old.travelSpeed, 0), 0, 12 * SETTINGS.MaxCadence / SETTINGS.WalkCadence)
	local weight = math.clamp(number(old.weight, 0), 0, SETTINGS.MaxSprintScale)
	local lagPitch = math.clamp(number(old.lagPitch, 0), -SETTINGS.AimLimit, SETTINGS.AimLimit)
	local lagYaw = math.clamp(number(old.lagYaw, 0), -SETTINGS.AimLimit, SETTINGS.AimLimit)
	if reset then
		phase, travelSpeed, weight, lagPitch, lagYaw = 0, 0, 0, 0, 0
		speed = 0
	end
	local movingSpeed = if input.grounded == true then speed else 0
	local cadenceTarget =
		math.min(movingSpeed, SETTINGS.WalkSpeed * SETTINGS.MaxCadence / SETTINGS.WalkCadence)
	local sprint = math.clamp((movingSpeed - SETTINGS.WalkSpeed) / 6, 0, 1)
	local weightTarget = math.clamp(movingSpeed / SETTINGS.WalkSpeed, 0, 1)
		* (1 + (SETTINGS.MaxSprintScale - 1) * sprint)
	local decay = math.exp(-SETTINGS.MotionRate * dt)
	-- Exact integration of the filtered speed avoids FPS-dependent gait phase.
	local travelled = cadenceTarget * dt
		+ (travelSpeed - cadenceTarget) * (1 - decay) / SETTINGS.MotionRate
	phase = (phase + travelled * TAU * SETTINGS.WalkCadence / SETTINGS.WalkSpeed) % TAU
	travelSpeed = cadenceTarget + (travelSpeed - cadenceTarget) * decay
	weight = weightTarget + (weight - weightTarget) * decay
	local turn = input.turn
	local turnValid = typeof(turn) == "Vector2" and finite(turn.X) and finite(turn.Y)
	if dt > 0 and not reset then
		local turnPitch = if turnValid then math.clamp(turn.X, -math.pi, math.pi) else 0
		local turnYaw = if turnValid then math.clamp(turn.Y, -math.pi, math.pi) else 0
		local aimDecay = math.exp(-SETTINGS.AimRate * dt)
		-- turn is a camera angular displacement in radians for this frame. This
		-- is the exact first-order lag for constant angular velocity over dt.
		local follow = (1 - aimDecay) / (SETTINGS.AimRate * dt)
		lagPitch = math.clamp(
			lagPitch * aimDecay - turnPitch * follow,
			-SETTINGS.AimLimit,
			SETTINGS.AimLimit
		)
		lagYaw =
			math.clamp(lagYaw * aimDecay - turnYaw * follow, -SETTINGS.AimLimit, SETTINGS.AimLimit)
	end
	local state: MotionState = table.freeze({
		phase = phase,
		idlePhase = idlePhase,
		travelSpeed = travelSpeed,
		weight = weight,
		lagPitch = lagPitch,
		lagYaw = lagYaw,
	})
	local side, rise = math.sin(phase), math.cos(phase)
	local camera = cf(side * 0.014 * weight, rise * 0.022 * weight, side * 0.004 * weight)
		* CFrame.Angles(math.rad(0.14) * rise * weight, 0, math.rad(0.25) * side * weight)
	local aspect = math.clamp(number(input.aspect, 16 / 9), 0.3, 4)
	local left = -0.44 * math.clamp(aspect / 1.5, 0.48, 1)
	local breath = math.sin(idlePhase)
	local view = cf(
		left + side * 0.024 * weight + breath * 0.003,
		-0.48 + rise * 0.026 * weight + breath * 0.004,
		-1.24 + side * 0.006 * weight
	) * CFrame.Angles(
		math.rad(0.1) * rise * weight,
		0,
		math.rad(0.16) * side * weight + math.rad(0.06) * breath
	)
	return state,
		{
			view = view,
			aim = CFrame.Angles(0, lagYaw, 0) * CFrame.Angles(lagPitch, 0, 0),
			camera = camera,
			bobWeight = weight,
		}
end

return table.freeze(Flashlight)
