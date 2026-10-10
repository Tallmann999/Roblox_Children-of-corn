--!strict

-- Pure server-side resource rules. No client supplies stamina or elapsed time.
export type State = {
	value: number,
	intent: boolean,
	exhausted: boolean,
	sprinting: boolean,
	tokens: number,
	requestAt: number,
}

local Stamina = {}

function Stamina.new(capacity: number, now: number): State
	return {
		value = capacity,
		intent = false,
		exhausted = false,
		sprinting = false,
		tokens = 12,
		requestAt = now,
	}
end

function Stamina.Request(state: State, value: any, now: number, active: boolean): boolean
	if type(value) ~= "boolean" then
		return false
	end
	if not value then
		-- Release cannot be lost behind a rate limit or inactive phase.
		state.intent = false
		state.exhausted = false
		state.sprinting = false
		return true
	end
	if not active then
		return false
	end
	if state.intent then
		return true
	end
	state.tokens = math.min(12, state.tokens + math.max(0, now - state.requestAt) * 6)
	state.requestAt = now
	if state.tokens < 1 then
		return false
	end
	state.tokens -= 1
	state.intent = true
	return true
end

function Stamina.Step(state: State, dt: number, moving: boolean, active: boolean, balance: any)
	if not active then
		state.intent = false
		state.sprinting = false
		return
	end
	state.sprinting = state.intent and moving and not state.exhausted and state.value > 0
	if state.sprinting then
		state.value =
			math.max(0, state.value - balance.stamina_capacity / balance.sprint_duration_sec * dt)
		if state.value <= 0.000001 then
			state.value = 0
			state.exhausted = true
			state.sprinting = false
		end
	else
		state.value = math.min(
			balance.stamina_capacity,
			state.value + balance.stamina_capacity / balance.stamina_refill_sec * dt
		)
	end
end

return Stamina
