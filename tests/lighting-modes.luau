-- Loads the production module in a limited Lune adapter. No Studio rendering or scene writes.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local I, C = roblox.Instance, roblox.Color3
local source = assert(loadstring(fs.readFile("src/shared/Game/LightingModes.luau")))
setfenv(source, setmetatable({ Color3 = C }, { __index = getfenv() }))
local Modes = source()

local lightingProperties = {
	"ClockTime",
	"Brightness",
	"Ambient",
	"OutdoorAmbient",
	"FogColor",
	"FogStart",
	"FogEnd",
}
local atmosphereProperties = { "Density", "Haze", "Offset", "Color", "Decay" }
local hardLighting = {
	ClockTime = 20.5,
	Brightness = 1,
	Ambient = C.fromRGB(18, 22, 30),
	OutdoorAmbient = C.fromRGB(38, 42, 53),
	FogColor = C.fromRGB(20, 27, 36),
	FogStart = 55,
	FogEnd = 320,
}
local hardAtmosphere = {
	Density = 0.27,
	Haze = 0.8,
	Offset = 0.25,
	Color = C.fromRGB(95, 110, 130),
	Decay = C.fromRGB(32, 41, 56),
}

local function count(values)
	local total = 0
	for _ in values do
		total += 1
	end
	return total
end

local function equal(actual, expected, label)
	if typeof(expected) == "Color3" then
		assert(typeof(actual) == "Color3", label .. " type")
		assert(
			math.abs(actual.R - expected.R) < 0.000001
				and math.abs(actual.G - expected.G) < 0.000001
				and math.abs(actual.B - expected.B) < 0.000001,
			label
		)
	elseif type(expected) == "number" then
		assert(math.abs(actual - expected) < 0.000001, label)
	else
		assert(actual == expected, label)
	end
end

local function values(item, properties)
	local result = {}
	for _, property in properties do
		result[property] = item[property]
	end
	return result
end

local function expectValues(item, expected, label)
	for property, value in expected do
		equal(item[property], value, label .. "." .. property)
	end
end

assert(Modes.Default == "hard", "Default must be hard")
assert(count(Modes.Order) == 1 and Modes.Order[1] == "hard", "Only hard may be ordered")
assert(count(Modes.Profiles) == 1 and Modes.Profiles.hard, "Only hard may have a profile")
assert(table.isfrozen(Modes) and table.isfrozen(Modes.Order), "Public mode contract must be frozen")
assert(
	table.isfrozen(Modes.Profiles) and table.isfrozen(Modes.Profiles.hard),
	"Profile contract must be frozen"
)
expectValues(Modes.Profiles.hard, hardLighting, "Hard Lighting profile")
expectValues(Modes.Profiles.hard, hardAtmosphere, "Hard Atmosphere profile")
assert(Modes.Profiles.hard.Torches == true, "Night torches must be enabled")
equal(Modes.Profiles.hard.SkyTop, C.fromRGB(10, 16, 32), "Hard SkyTop")
equal(Modes.Profiles.hard.SkyBottom, C.fromRGB(46, 59, 76), "Hard SkyBottom")
assert(Modes.IsValid("hard") == true, "Hard mode must be valid")

local invalidModes = {
	{ label = "nil" },
	{ label = "number", value = 3 },
	{ label = "false", value = false },
	{ label = "table", value = { mode = "hard" } },
	{ label = "easy", value = "easy" },
	{ label = "medium", value = "medium" },
	{ label = "unknown", value = "night" },
	{ label = "case", value = "Hard" },
	{ label = "whitespace", value = "hard " },
	{ label = "empty", value = "" },
}
for _, entry in invalidModes do
	assert(Modes.IsValid(entry.value) == false, "Invalid mode accepted: " .. entry.label)
	local accesses = 0
	local untouched = setmetatable({}, {
		__index = function()
			accesses += 1
			error("Lighting accessed before validating mode")
		end,
		__newindex = function()
			accesses += 1
			error("Lighting mutated before validating mode")
		end,
	})
	local ok, message = pcall(Modes.Apply, untouched, entry.value)
	assert(
		not ok and tostring(message):find("Unknown lighting mode", 1, true),
		"Invalid Apply must assert before access: " .. entry.label
	)
	assert(accesses == 0, "Invalid Apply accessed Lighting: " .. entry.label)
end
print(
	"PASS: frozen hard-only mode contract, retained hard profile, 10 invalid payloads refused before Lighting access"
)

local function newLighting()
	local lighting = I.new("Lighting")
	lighting.ClockTime = 12.75
	lighting.Brightness = 2.25
	lighting.Ambient = C.fromRGB(101, 103, 107)
	lighting.OutdoorAmbient = C.fromRGB(151, 153, 157)
	lighting.FogColor = C.fromRGB(201, 203, 207)
	lighting.FogStart = 400
	lighting.FogEnd = 1400
	lighting.ExposureCompensation = 0.5
	lighting.EnvironmentDiffuseScale = 0.65
	lighting.GlobalShadows = false
	lighting:SetAttribute("AuthorLighting", "preserve")
	return lighting
end

local function newAtmosphere(name, parent, density)
	local effect = I.new("Atmosphere")
	effect.Name = name
	effect.Density = density
	effect.Haze = 1.25
	effect.Offset = -0.15
	effect.Color = C.fromRGB(180, 170, 160)
	effect.Decay = C.fromRGB(70, 80, 90)
	effect.Glare = 0.45
	effect:SetAttribute("AuthorEffect", name)
	effect.Parent = parent
	return effect
end

local lighting = newLighting()
local first = newAtmosphere("AuthorAtmosphere", lighting, 0.12)
local second = newAtmosphere("OtherAtmosphere", lighting, 0.22)
local correction = I.new("ColorCorrectionEffect")
correction.Name = "AuthorCorrection"
correction.Brightness = 0.1
correction.TintColor = C.fromRGB(210, 220, 230)
correction.Enabled = false
correction.Parent = lighting
local originalLighting = values(lighting, lightingProperties)
local originalFirst = values(first, atmosphereProperties)
local originalSecond = values(second, atmosphereProperties)
local extras =
	values(lighting, { "ExposureCompensation", "EnvironmentDiffuseScale", "GlobalShadows" })
local state = Modes.Capture(lighting)
assert(
	count(state.lighting) == 7 and #state.atmospheres == 2,
	"Capture must cover seven properties and both Atmospheres"
)
for _, entry in state.atmospheres do
	assert(count(entry.values) == 5, "Capture must cover five Atmosphere properties")
end
expectValues(lighting, originalLighting, "Capture leaves Lighting unchanged")
expectValues(first, originalFirst, "Capture leaves first effect unchanged")
expectValues(second, originalSecond, "Capture leaves second effect unchanged")

Modes.Apply(lighting, "hard")
expectValues(lighting, hardLighting, "Applied hard Lighting")
expectValues(first, hardAtmosphere, "Applied first Atmosphere")
expectValues(second, hardAtmosphere, "Applied second Atmosphere")
expectValues(lighting, extras, "Unrelated Lighting properties")
equal(first.Glare, 0.45, "Unrelated Atmosphere.Glare")
assert(first:GetAttribute("AuthorEffect") == "AuthorAtmosphere", "Effect metadata changed")
assert(lighting:GetAttribute("AuthorLighting") == "preserve", "Lighting metadata changed")
equal(correction.Brightness, 0.1, "ColorCorrection brightness")
equal(correction.TintColor, C.fromRGB(210, 220, 230), "ColorCorrection tint")
assert(correction.Enabled == false and correction.Parent == lighting, "Foreign correction changed")
assert(#lighting:GetChildren() == 3, "Apply may not create or destroy effects")

Modes.Restore(lighting, state)
expectValues(lighting, originalLighting, "Restored Lighting")
expectValues(first, originalFirst, "Restored first Atmosphere")
expectValues(second, originalSecond, "Restored second Atmosphere")
assert(
	first.Parent == lighting and second.Parent == lighting and correction.Parent == lighting,
	"Restore changed existing effect parents"
)
print("PASS: Capture/Apply/Restore preserves original effects, unrelated properties and metadata")

Modes.Apply(lighting, "hard")
local elsewhere = I.new("Folder")
second.Parent = elsewhere
second.Density = 0.47
local foreign = newAtmosphere("ForeignAfterCapture", lighting, 0.39)
local foreignBefore = values(foreign, atmosphereProperties)
Modes.Restore(lighting, state)
expectValues(lighting, originalLighting, "Restore after effect changes")
expectValues(first, originalFirst, "Restore retained original")
expectValues(foreign, foreignBefore, "New foreign effect preserved")
equal(second.Density, 0.47, "Moved captured effect preserved")
assert(second.Parent == elsewhere and foreign.Parent == lighting, "Restore moved foreign effects")
assert(
	#lighting:GetChildren() == 3 and #elsewhere:GetChildren() == 1,
	"Restore changed effect counts"
)
first.Parent = nil
first.Density = 0.49
Modes.Restore(lighting, state)
equal(first.Density, 0.49, "Removed captured effect preserved")
assert(first.Parent == nil and #lighting:GetChildren() == 2, "Restore recreated a removed effect")

local bareLighting = newLighting()
local bareBefore = values(bareLighting, lightingProperties)
local bareState = Modes.Capture(bareLighting)
assert(#bareState.atmospheres == 0, "Empty Lighting capture contains an Atmosphere")
Modes.Apply(bareLighting, "hard")
expectValues(bareLighting, hardLighting, "Hard without Atmosphere")
assert(#bareLighting:GetChildren() == 0, "Missing Atmosphere may not be synthesized")
local later = newAtmosphere("LaterAuthorEffect", bareLighting, 0.31)
local laterBefore = values(later, atmosphereProperties)
Modes.Restore(bareLighting, bareState)
expectValues(bareLighting, bareBefore, "Restore missing-effect baseline")
expectValues(later, laterBefore, "Restore preserves later effect")
assert(
	later.Parent == bareLighting and #bareLighting:GetChildren() == 1,
	"Empty-baseline Restore changed foreign effect ownership"
)
print(
	"PASS: restore skips removed/reparented effects and preserves later foreign Atmospheres; missing-effect apply creates nothing"
)
