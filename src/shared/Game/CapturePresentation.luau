--!strict
local Capture = { Duration = 1, ApproachDuration = 0.7 }

-- Fixed screen-space paint. Numeric definitions keep this module usable by
-- the server's snapshot validator without constructing any GUI or art.
Capture.PaintDrops = table.freeze({
	table.freeze({ x = 0.19, y = 0.29, w = 0.105, h = 0.074, rotation = -18, color = 1 }),
	table.freeze({ x = 0.14, y = 0.25, w = 0.052, h = 0.035, rotation = 8, color = 1 }),
	table.freeze({ x = 0.24, y = 0.25, w = 0.041, h = 0.028, rotation = 22, color = 1 }),
	table.freeze({ x = 0.16, y = 0.34, w = 0.028, h = 0.024, rotation = 0, color = 1 }),
	table.freeze({ x = 0.27, y = 0.32, w = 0.025, h = 0.021, rotation = 0, color = 1 }),
	table.freeze({ x = 0.71, y = 0.38, w = 0.119, h = 0.086, rotation = 16, color = 2 }),
	table.freeze({ x = 0.66, y = 0.34, w = 0.057, h = 0.037, rotation = -12, color = 2 }),
	table.freeze({ x = 0.77, y = 0.34, w = 0.031, h = 0.023, rotation = 0, color = 2 }),
	table.freeze({ x = 0.77, y = 0.44, w = 0.039, h = 0.024, rotation = 24, color = 2 }),
	table.freeze({ x = 0.68, y = 0.44, w = 0.029, h = 0.027, rotation = 0, color = 2 }),
	table.freeze({ x = 0.39, y = 0.72, w = 0.103, h = 0.067, rotation = -9, color = 3 }),
	table.freeze({ x = 0.34, y = 0.67, w = 0.051, h = 0.033, rotation = 18, color = 3 }),
	table.freeze({ x = 0.44, y = 0.68, w = 0.035, h = 0.026, rotation = 0, color = 3 }),
	table.freeze({ x = 0.43, y = 0.77, w = 0.026, h = 0.023, rotation = 0, color = 3 }),
	table.freeze({ x = 0.31, y = 0.75, w = 0.025, h = 0.020, rotation = 0, color = 3 }),
	table.freeze({ x = 0.10, y = 0.43, w = 0.013, h = 0.018, rotation = -24, color = 1 }),
	table.freeze({ x = 0.29, y = 0.17, w = 0.016, h = 0.013, rotation = 0, color = 1 }),
	table.freeze({ x = 0.84, y = 0.29, w = 0.012, h = 0.018, rotation = 20, color = 2 }),
	table.freeze({ x = 0.59, y = 0.48, w = 0.016, h = 0.013, rotation = 0, color = 2 }),
	table.freeze({ x = 0.27, y = 0.83, w = 0.014, h = 0.017, rotation = -12, color = 3 }),
	table.freeze({ x = 0.49, y = 0.60, w = 0.017, h = 0.012, rotation = 0, color = 3 }),
})

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function Capture.IsValidSnapshot(value: any): boolean
	if
		type(value) ~= "table"
		or not finite(value.id)
		or value.id % 1 ~= 0
		or value.id < 0
		or value.id > 2
	then
		return false
	end
	if
		not finite(value.remaining)
		or value.remaining < 0
		or value.remaining > Capture.Duration
		or typeof(value.frame) ~= "CFrame"
	then
		return false
	end
	if value.id == 0 and value.remaining ~= 0 then
		return false
	end
	for _, component in { value.frame:GetComponents() } do
		if not finite(component) or math.abs(component) > 1000000 then
			return false
		end
	end
	local x, y, z = value.frame.XVector, value.frame.YVector, value.frame.ZVector
	return math.abs(x.Magnitude - 1) < 0.001
		and math.abs(y.Magnitude - 1) < 0.001
		and math.abs(z.Magnitude - 1) < 0.001
		and math.abs(x:Dot(y)) < 0.001
		and math.abs(x:Dot(z)) < 0.001
		and math.abs(y:Dot(z)) < 0.001
		and x:Cross(y):Dot(z) > 0.999
end

function Capture.NewState(): any
	return {
		roundId = -1,
		lastId = 0,
		active = false,
		deadline = 0,
		started = 0,
		frame = CFrame.identity,
	}
end

function Capture.Cancel(state: any)
	state.active = false
end

-- Incoming snapshots may shorten a running deadline, but cannot extend or replay it.
function Capture.Observe(state: any, roundId: any, value: any, phase: any, now: number): string
	local wasActive = state.active
	if
		not finite(roundId)
		or roundId < 0
		or roundId % 1 ~= 0
		or not finite(now)
		or not Capture.IsValidSnapshot(value)
	then
		Capture.Cancel(state)
		return if wasActive then "cancel" else "none"
	end
	if roundId < state.roundId then
		Capture.Cancel(state)
		return if wasActive then "cancel" else "none"
	end
	if roundId ~= state.roundId then
		state.roundId, state.lastId, state.active = roundId, 0, false
	end
	if phase ~= "caught" or value.id == 0 or value.remaining <= 0 then
		state.lastId = math.max(state.lastId, value.id)
		Capture.Cancel(state)
		return if wasActive then "cancel" else "none"
	end
	if state.active and value.id == state.lastId then
		state.deadline = math.min(state.deadline, now + value.remaining)
		if now >= state.deadline then
			Capture.Cancel(state)
			return "cancel"
		end
		return "keep"
	end
	if value.id <= state.lastId then
		return if wasActive and not state.active then "cancel" else "none"
	end
	state.lastId = value.id
	state.active = true
	state.started = now - (Capture.Duration - value.remaining)
	state.deadline = now + value.remaining
	state.frame = value.frame
	return "begin"
end

function Capture.Progress(state: any, now: number): number
	return math.clamp((now - state.started) / Capture.ApproachDuration, 0, 1)
end

local function elapsedTime(elapsed: number): number
	return if finite(elapsed) then math.clamp(elapsed, 0, Capture.Duration) else 0
end

function Capture.HeadShake(elapsed: number): CFrame
	local time = elapsedTime(elapsed)
	local strength = math.clamp(time / 0.13, 0, 1)
	return CFrame.Angles(
		math.sin(time * 2 * math.pi * 13) * math.rad(6) * strength,
		math.sin(time * 2 * math.pi * 11) * math.rad(14) * strength,
		math.sin(time * 2 * math.pi * 9) * math.rad(7) * strength
	)
end

function Capture.CameraShake(elapsed: number): CFrame
	local time = elapsedTime(elapsed)
	local strength = math.clamp(time / 0.3, 0, 1)
	return CFrame.new(
		math.sin(time * 2 * math.pi * 7) * 0.028 * strength,
		math.sin(time * 2 * math.pi * 9) * 0.020 * strength,
		0
	) * CFrame.Angles(
		math.sin(time * 2 * math.pi * 6) * math.rad(0.35) * strength,
		math.sin(time * 2 * math.pi * 8) * math.rad(0.45) * strength,
		math.sin(time * 2 * math.pi * 5) * math.rad(0.65) * strength
	)
end

function Capture.MouthOpen(elapsed: number): number
	local progress = math.clamp(elapsedTime(elapsed) / 0.22, 0, 1)
	return 0.3 + 0.7 * progress * progress * (3 - 2 * progress)
end

function Capture.PaintOpacity(elapsed: number): number
	local time = elapsedTime(elapsed)
	return math.clamp((time - 0.42) / 0.09, 0, 1)
		* (1 - math.clamp((time - 0.9) / 0.1, 0, 1))
		* 0.88
end

return table.freeze(Capture)
