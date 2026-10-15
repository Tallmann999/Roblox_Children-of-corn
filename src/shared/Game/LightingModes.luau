--!strict

local LightingModes = {}
LightingModes.Order = table.freeze({ "hard" })
LightingModes.Default = "hard"
LightingModes.Profiles = table.freeze({
	hard = table.freeze({
		ClockTime = 20.5,
		Brightness = 1,
		Ambient = Color3.fromRGB(18, 22, 30),
		OutdoorAmbient = Color3.fromRGB(38, 42, 53),
		FogColor = Color3.fromRGB(20, 27, 36),
		FogStart = 55,
		FogEnd = 320,
		Density = 0.27,
		Haze = 0.8,
		Offset = 0.25,
		Color = Color3.fromRGB(95, 110, 130),
		Decay = Color3.fromRGB(32, 41, 56),
		Torches = true,
		SkyTop = Color3.fromRGB(10, 16, 32),
		SkyBottom = Color3.fromRGB(46, 59, 76),
	}),
})

local LIGHTING_PROPERTIES =
	{ "ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "FogColor", "FogStart", "FogEnd" }
local ATMOSPHERE_PROPERTIES = { "Density", "Haze", "Offset", "Color", "Decay" }

function LightingModes.IsValid(value: any): boolean
	return value == "hard"
end

function LightingModes.Capture(lighting: Lighting): any
	local state = { lighting = {}, atmospheres = {} }
	for _, property in LIGHTING_PROPERTIES do
		state.lighting[property] = (lighting :: any)[property]
	end
	for _, effect in lighting:GetChildren() do
		if effect:IsA("Atmosphere") then
			local values = {}
			for _, property in ATMOSPHERE_PROPERTIES do
				values[property] = (effect :: any)[property]
			end
			table.insert(state.atmospheres, { instance = effect, values = values })
		end
	end
	return state
end

function LightingModes.Apply(lighting: Lighting, mode: string)
	assert(LightingModes.IsValid(mode), "Unknown lighting mode")
	local profile = (LightingModes.Profiles :: any)[mode]
	for _, property in LIGHTING_PROPERTIES do
		(lighting :: any)[property] = profile[property]
	end
	for _, effect in lighting:GetChildren() do
		if effect:IsA("Atmosphere") then
			for _, property in ATMOSPHERE_PROPERTIES do
				(effect :: any)[property] = profile[property]
			end
		end
	end
end

function LightingModes.Restore(lighting: Lighting, state: any)
	for property, value in state.lighting do
		(lighting :: any)[property] = value
	end
	for _, entry in state.atmospheres do
		if entry.instance.Parent == lighting then
			for property, value in entry.values do
				entry.instance[property] = value
			end
		end
	end
end

return table.freeze(LightingModes)
