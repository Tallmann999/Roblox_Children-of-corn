--!strict
local Capture = { Duration = 1, ApproachDuration = 0.7 }

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

return table.freeze(Capture)
