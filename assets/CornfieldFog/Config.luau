-- Audited adaptation of the author's imported CornfieldFog. Play-session only.
-- Existing remote field names remain compatible: Steps is haze intensity,
-- StartRatio is optional palette tint strength; neither is a visibility distance.
return {
	Enabled = true,
	Steps = 20,
	StartRatio = 0.2,
	Preset = "Auto", -- Follow the current day/dusk/night palette until explicitly tinted.
	Presets = {
		Field = Color3.fromRGB(177, 184, 158),
		Dawn = Color3.fromRGB(205, 197, 171),
		Night = Color3.fromRGB(20, 27, 36),
	},
	-- Added to the CURRENT baseline Haze, not a replacement for LightingModes.
	-- Current .0/.4/.8 mode baselines become .5/1.25/1.8 at intensity20.
	HazeBoost = { Day = 0.5, Dusk = 0.85, Night = 1 },
	MaxDensity = 0.36,
	MaxHaze = 2.8,
	MinSteps = 10,
	MaxSteps = 120,
	AdminUserIds = {},
	AllowExperienceOwner = true,
	PanelInStudio = true,
	FieldOnly = false,
	FieldCenter = Vector3.new(0, 0, 0),
	FieldSize = Vector3.new(840, 300, 840),
	EdgeFadeStuds = 30,
}
