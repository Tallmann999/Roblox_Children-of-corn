--!strict

local LightingModes = {}
LightingModes.Order = table.freeze({ "hard" })
LightingModes.Default = "hard"
LightingModes.Profiles = table.freeze({
	hard = table.freeze({
		ClockTime = 20.5,
		Brightness = 0,
		Ambient = Color3.new(0, 0, 0),
		OutdoorAmbient = Color3.new(0, 0, 0),
		EnvironmentDiffuseScale = 0,
		EnvironmentSpecularScale = 0,
		GlobalShadows = true,
		FogColor = Color3.fromRGB(20, 27, 36),
		FogStart = 55,
		FogEnd = 320,
		Density = 0.27,
		Haze = 0.8,
		Offset = 0.25,
		Color = Color3.fromRGB(95, 110, 130),
		Decay = Color3.fromRGB(32, 41, 56),
		Torches = true,
		SkyTop = Color3.new(0, 0, 0),
		SkyBottom = Color3.new(0, 0, 0),
	}),
})

local LIGHTING_PROPERTIES = {
	"ClockTime",
	"Brightness",
	"Ambient",
	"OutdoorAmbient",
	"EnvironmentDiffuseScale",
	"EnvironmentSpecularScale",
	"GlobalShadows",
	"FogColor",
	"FogStart",
	"FogEnd",
}
local ATMOSPHERE_PROPERTIES = { "Density", "Haze", "Offset", "Color", "Decay" }
-- A decoded solid-black image is required: empty faces fall back to a blue sky.
local BLACK_SKY_TEXTURE = "rbxassetid://127362238475901"
local SKY_PROPERTIES = {
	CelestialBodiesShown = false,
	StarCount = 0,
	SkyboxBk = BLACK_SKY_TEXTURE,
	SkyboxDn = BLACK_SKY_TEXTURE,
	SkyboxFt = BLACK_SKY_TEXTURE,
	SkyboxLf = BLACK_SKY_TEXTURE,
	SkyboxRt = BLACK_SKY_TEXTURE,
	SkyboxUp = BLACK_SKY_TEXTURE,
}
local SKY_PRESERVED_PROPERTIES = {
	"SunAngularSize",
	"MoonAngularSize",
	"SunTextureId",
	"MoonTextureId",
	"SkyboxOrientation",
	"Archivable",
}
local createdSkies: { [Lighting]: any } = setmetatable({}, { __mode = "k" }) :: any

local function createBlackSky(lighting: Lighting)
	local sky = Instance.new("Sky")
	sky.Name = "CornBlackNightSky"
	sky:SetAttribute("CornBlackNightSkyOwned", true)
	sky:SetAttribute("corn_project_id", "children_of_corn")
	local values = {}
	for property, value in SKY_PROPERTIES do
		(sky :: any)[property] = value
		values[property] = (sky :: any)[property]
	end
	for _, property in SKY_PRESERVED_PROPERTIES do
		values[property] = (sky :: any)[property]
	end
	createdSkies[lighting] = { instance = sky, values = values }
	sky.Parent = lighting
end

local function releaseCreatedSky(lighting: Lighting, state: any)
	local record = createdSkies[lighting]
	if not record then
		return
	end
	local sky = record.instance
	for _, entry in state.skies do
		if entry.instance == sky then
			-- A later observer's baseline already included this runtime Sky.
			return
		end
	end
	createdSkies[lighting] = nil
	if sky.Parent ~= lighting or sky.Name ~= "CornBlackNightSky" or #sky:GetChildren() ~= 0 then
		return
	end
	local attributes = sky:GetAttributes()
	if
		attributes.CornBlackNightSkyOwned ~= true
		or attributes.corn_project_id ~= "children_of_corn"
		or #sky:GetTags() ~= 0
	then
		return
	end
	local attributeCount = 0
	for _ in attributes do
		attributeCount += 1
	end
	if attributeCount ~= 2 then
		return
	end
	for property, value in record.values do
		if (sky :: any)[property] ~= value then
			return
		end
	end
	sky:Destroy()
end

function LightingModes.IsValid(value: any): boolean
	return value == "hard"
end

function LightingModes.Capture(lighting: Lighting): any
	local state = { lighting = {}, atmospheres = {}, skies = {} }
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
		elseif effect:IsA("Sky") then
			local values = {}
			for property in SKY_PROPERTIES do
				values[property] = (effect :: any)[property]
			end
			table.insert(state.skies, { instance = effect, values = values })
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
	local hasSky = false
	for _, effect in lighting:GetChildren() do
		if effect:IsA("Atmosphere") then
			for _, property in ATMOSPHERE_PROPERTIES do
				(effect :: any)[property] = profile[property]
			end
		elseif effect:IsA("Sky") then
			hasSky = true
			-- Suppress the authored colored sky without replacing its instance.
			for property, value in SKY_PROPERTIES do
				(effect :: any)[property] = value
			end
		end
	end
	if not hasSky then
		createBlackSky(lighting)
	end
end

function LightingModes.Restore(lighting: Lighting, state: any)
	releaseCreatedSky(lighting, state)
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
	for _, entry in state.skies do
		if entry.instance.Parent == lighting then
			for property, value in entry.values do
				entry.instance[property] = value
			end
		end
	end
end

return table.freeze(LightingModes)
