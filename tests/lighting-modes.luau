-- Loads the production module in a limited Lune adapter. No Studio rendering or scene writes.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local I, C = roblox.Instance, roblox.Color3
local function newInstance(class)
	local instance = I.new(class)
	if class == "Sky" then
		-- Lune's Sky database omits these native defaults. Explicit fixture values
		-- exercise cleanup ownership; they make no Studio default/rendering claim.
		instance.SunTextureId = "rbxassetid://fixture-default-sun"
		instance.MoonTextureId = "rbxassetid://fixture-default-moon"
		instance.SkyboxOrientation = roblox.Vector3.zero
	end
	return instance
end
local source = assert(loadstring(fs.readFile("src/shared/Game/LightingModes.luau")))
setfenv(
	source,
	setmetatable({ Color3 = C, Instance = { new = newInstance } }, { __index = getfenv() })
)
local Modes = source()

local lightingProperties = {
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
local atmosphereProperties = { "Density", "Haze", "Offset", "Color", "Decay" }
local hardLighting = {
	ClockTime = 20.5,
	Brightness = 0,
	Ambient = C.new(0, 0, 0),
	OutdoorAmbient = C.new(0, 0, 0),
	EnvironmentDiffuseScale = 0,
	EnvironmentSpecularScale = 0,
	GlobalShadows = true,
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
equal(Modes.Profiles.hard.SkyTop, C.new(0, 0, 0), "Hard SkyTop")
equal(Modes.Profiles.hard.SkyBottom, C.new(0, 0, 0), "Hard SkyBottom")
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
	"PASS: frozen hard-only black-night contract, torches enabled, unchanged fog profile, 10 invalid payloads refused before Lighting access"
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
	lighting.EnvironmentSpecularScale = 0.35
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
local extras = values(lighting, { "ExposureCompensation" })
local state = Modes.Capture(lighting)
assert(
	count(state.lighting) == 10 and #state.atmospheres == 2 and #state.skies == 0,
	"Capture must cover ten properties, both Atmospheres and no invented Sky"
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
assert(#lighting:GetChildren() == 4, "Missing sky requires exactly one owned runtime Sky")

Modes.Restore(lighting, state)
expectValues(lighting, originalLighting, "Restored Lighting")
expectValues(first, originalFirst, "Restored first Atmosphere")
expectValues(second, originalSecond, "Restored second Atmosphere")
assert(
	first.Parent == lighting and second.Parent == lighting and correction.Parent == lighting,
	"Restore changed existing effect parents"
)
assert(#lighting:GetChildren() == 3, "Restore leaked runtime Sky")
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
assert(#bareLighting:GetChildren() == 1, "Missing sky requires a single runtime Sky")
assert(bareLighting:GetChildren()[1]:IsA("Sky"), "Missing Atmosphere may not be synthesized")
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
	"PASS: restore skips removed/reparented effects and preserves later foreign Atmospheres; only missing Sky gets bounded runtime fallback"
)

-- Black night clears the six authored sky faces and celestial visibility only for
-- the round. It must restore exact per-Sky values, including false/zero values,
-- and must not move, delete or replace author effects.
local skyProperties = {
	"CelestialBodiesShown",
	"StarCount",
	"SkyboxBk",
	"SkyboxDn",
	"SkyboxFt",
	"SkyboxLf",
	"SkyboxRt",
	"SkyboxUp",
}
local blackSky = {
	CelestialBodiesShown = false,
	StarCount = 0,
	SkyboxBk = "rbxassetid://127362238475901",
	SkyboxDn = "rbxassetid://127362238475901",
	SkyboxFt = "rbxassetid://127362238475901",
	SkyboxLf = "rbxassetid://127362238475901",
	SkyboxRt = "rbxassetid://127362238475901",
	SkyboxUp = "rbxassetid://127362238475901",
}
local function newSky(name, parent, suffix)
	local sky = I.new("Sky")
	sky.Name = name
	sky.CelestialBodiesShown = suffix == "first"
	sky.StarCount = if suffix == "first" then 1250 else 0
	for _, face in { "Bk", "Dn", "Ft", "Lf", "Rt", "Up" } do
		sky["Skybox" .. face] = "rbxassetid://author-" .. suffix .. "-" .. face
	end
	sky.SunAngularSize = 18
	sky.MoonAngularSize = 9
	sky.SunTextureId = "rbxassetid://author-sun-" .. suffix
	sky.MoonTextureId = "rbxassetid://author-moon-" .. suffix
	sky:SetAttribute("AuthorSky", suffix)
	sky.Parent = parent
	return sky
end
local skyLighting = newLighting()
local skyFirst = newSky("AuthorSky", skyLighting, "first")
local skySecond = newSky("OtherSky", skyLighting, "second")
local sunProperties = { "SunAngularSize", "MoonAngularSize", "SunTextureId", "MoonTextureId" }
local skyFirstBefore = values(skyFirst, skyProperties)
local skySecondBefore = values(skySecond, skyProperties)
local skyFirstExtras = values(skyFirst, sunProperties)
local skySecondExtras = values(skySecond, sunProperties)
local skyState = Modes.Capture(skyLighting)
assert(#skyState.skies == 2 and #skyState.atmospheres == 0, "Capture lost existing Skies")
for _, entry in skyState.skies do
	assert(count(entry.values) == 8, "Sky Capture must cover eight changed properties")
end
expectValues(skyFirst, skyFirstBefore, "Capture leaves first Sky unchanged")
expectValues(skySecond, skySecondBefore, "Capture leaves second Sky unchanged")
for _ = 1, 2 do
	Modes.Apply(skyLighting, "hard")
	expectValues(skyFirst, blackSky, "First Sky black")
	expectValues(skySecond, blackSky, "Second Sky black")
	expectValues(skyFirst, skyFirstExtras, "First Sky unrelated properties")
	expectValues(skySecond, skySecondExtras, "Second Sky unrelated properties")
	assert(#skyLighting:GetChildren() == 2, "Black night synthesized/deleted a Sky")
	assert(skyFirst:GetAttribute("AuthorSky") == "first", "Sky metadata changed")
end
Modes.Restore(skyLighting, skyState)
expectValues(skyFirst, skyFirstBefore, "Exact first Sky restore")
expectValues(skySecond, skySecondBefore, "Exact second Sky restore")
Modes.Apply(skyLighting, "hard")
skySecond.Parent = elsewhere
skySecond.StarCount = 7
skyFirst.Parent = nil
skyFirst.SkyboxUp = "rbxassetid://removed-author-edit"
local laterSky = newSky("LaterSky", skyLighting, "later")
local laterSkyBefore = values(laterSky, skyProperties)
Modes.Restore(skyLighting, skyState)
equal(skySecond.StarCount, 7, "Moved Sky preserved")
equal(skyFirst.SkyboxUp, "rbxassetid://removed-author-edit", "Removed Sky preserved")
expectValues(laterSky, laterSkyBefore, "Later Sky preserved")
assert(
	skyFirst.Parent == nil and skySecond.Parent == elsewhere and #skyLighting:GetChildren() == 1,
	"Sky restore changed author topology"
)
print(
	"PASS: eight black-sky properties captured/restored exactly across repeated apply; unrelated textures/angles/metadata and moved/removed/later Skies preserved; no effects created"
)

do
	local empty = newLighting()
	local baseline = Modes.Capture(empty)
	Modes.Apply(empty, "hard")
	local sky = empty:GetChildren()[1]
	expectValues(sky, blackSky, "Owned fallback black Sky")
	assert(
		sky:GetAttribute("CornBlackNightSkyOwned") == true
			and sky:GetAttribute("corn_project_id") == "children_of_corn",
		"Runtime Sky ownership missing"
	)
	Modes.Apply(empty, "hard")
	assert(#empty:GetChildren() == 1 and empty:GetChildren()[1] == sky, "Repeated Apply leaked Sky")
	local observer = Modes.Capture(empty)
	Modes.Restore(empty, observer)
	assert(sky.Parent == empty, "Later observer Restore deleted a Sky from its own baseline")
	Modes.Restore(empty, baseline)
	assert(#empty:GetChildren() == 0, "Original Restore leaked owned fallback")
	Modes.Restore(empty, baseline)
	assert(#empty:GetChildren() == 0, "Repeated Restore synthesized a Sky")
	Modes.Apply(empty, "hard")
	assert(#empty:GetChildren() == 1, "New round did not reconstruct fallback")
	Modes.Restore(empty, baseline)
	assert(#empty:GetChildren() == 0, "New round leaked fallback")
end

for _, mutation in
	{
		function(sky)
			sky.StarCount = 5
		end,
		function(sky)
			sky.SunTextureId = "rbxassetid://manual-sun"
		end,
		function(sky)
			sky.SkyboxOrientation = roblox.Vector3.new(0, 35, 0)
		end,
		function(sky)
			sky.Archivable = false
		end,
		function(sky)
			sky.Name = "ManualSky"
		end,
		function(sky)
			sky:SetAttribute("AuthorEdit", true)
		end,
		function(sky)
			sky:AddTag("AuthorTag")
		end,
		function(sky)
			I.new("Folder").Parent = sky
		end,
		function(sky)
			sky.Parent = elsewhere
		end,
	}
do
	local empty = newLighting()
	local baseline = Modes.Capture(empty)
	Modes.Apply(empty, "hard")
	local sky = empty:GetChildren()[1]
	mutation(sky)
	local parent = sky.Parent
	Modes.Restore(empty, baseline)
	assert(sky.Parent == parent, "Foreign edited/moved runtime Sky deleted")
	sky:Destroy()
end
print(
	"PASS: absent-Sky fallback reused across Apply, exact original/observer/repeated Restore, new round; nine foreign edits refuse deletion"
)
