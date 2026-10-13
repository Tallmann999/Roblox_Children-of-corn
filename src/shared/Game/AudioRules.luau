--!strict
local Rules = {
	Mix = table.freeze({ Master = 0.8, Music = 1, Ambience = 1, Effects = 1 }),
	Volume = table.freeze({
		Background = 0.12,
		Hunt = 0.34,
		Energy = 0.55,
		Trap = 0.48,
		Crickets = 0.23,
		Fire = 0.055,
		Rustle = 0.38,
		Monster = 0.68,
		Awakening = 0.95,
	}),
	Ranges = table.freeze({
		Rustle = table.freeze({ Min = 5, Max = 65 }),
		Monster = table.freeze({ Min = 8, Max = 115 }),
		Fire = table.freeze({ Min = 4, Max = 35 }),
		Crickets = table.freeze({ Min = 8, Max = 130 }),
		Awakening = table.freeze({ Min = 20, Max = 1400 }),
	}),
	CricketOn = 15,
	Cycle = 30,
	VoiceMin = 4,
	VoiceMax = 7.5,
	FirstVoiceDelay = 0.4,
	ActorLimit = 8,
	RustleInterval = 0.45,
	HuntFadeIn = 1.4,
	HuntFadeOut = 2.5,
	HuntMaxDistance = 60,
	BackgroundFade = 0.8,
	CornKeys = table.freeze({
		"COC_Corn_02",
		"COC_Corn_10",
		"COC_Corn_11",
		"COC_Corn_13",
		"COC_Corn_18",
		"COC_Corn_20",
	}),
	VoiceKeys = table.freeze({ "COC_Monster_01", "COC_Monster_02", "COC_Monster_03" }),
}

local function finite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

function Rules.Fade(current: number, goal: number, dt: number, seconds: number): number
	if not finite(current) or not finite(goal) or not finite(dt) or dt < 0 then
		return 0
	end
	current, goal = math.clamp(current, 0, 1), math.clamp(goal, 0, 1)
	if seconds <= 0 then
		return goal
	end
	if not finite(seconds) then
		return current
	end
	local step = dt / seconds
	return if current < goal then math.min(goal, current + step) else math.max(goal, current - step)
end

function Rules.ChaseIntensity(distance: number): number
	if not finite(distance) or distance < 0 or distance >= Rules.HuntMaxDistance then
		return 0
	end
	return 0.35 + 0.65 * (1 - math.clamp((distance - 10) / 32, 0, 1))
end

function Rules.CricketIsOn(now: number, started: number, offset: number): boolean
	local elapsed = now - started - offset
	return finite(elapsed) and elapsed >= 0 and elapsed % Rules.Cycle < Rules.CricketOn
end

return table.freeze(Rules)
