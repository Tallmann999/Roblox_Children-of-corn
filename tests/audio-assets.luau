local fs = require("@lune/fs")
local Assets = assert(loadstring(fs.readFile("src/shared/Game/AudioAssets.luau")))()
local Rules = assert(loadstring(fs.readFile("src/shared/Game/AudioRules.luau")))()
local count, configured = 0, 0
for key, clip in Assets.List() do
	count += 1
	assert(type(key) == "string" and string.sub(key, 1, 4) == "COC_", "Unscoped audio key")
	assert(clip.Duration > 0 and clip.Duration < 420, "Invalid duration: " .. key)
	assert(clip.Gain > 0 and clip.Gain < 3 and clip.Gain == clip.Gain, "Invalid gain: " .. key)
	assert(
		clip.Id == "" or string.match(clip.Id, "^rbxassetid://%d+$"),
		"Invalid asset URI: " .. key
	)
	if clip.Id ~= "" then
		configured += 1
	end
	local base = if string.find(key, "Corn", 1, true)
		then Rules.Volume.Rustle
		elseif string.find(key, "Monster", 1, true) then Rules.Volume.Monster
		elseif key == "COC_Energy_Open" then Rules.Volume.Energy
		elseif key == "COC_Trap_Place" then Rules.Volume.Trap
		elseif key == "COC_Fire" then Rules.Volume.Fire
		elseif key == "COC_Crickets_15s" then Rules.Volume.Crickets
		elseif key == "COC_Hunt" then Rules.Volume.Hunt
		else Rules.Volume.Background
	assert(base * clip.Gain <= 1, "Clipping-prone gain: " .. key)
end
assert(count == 16, "Expected original 15 clips plus one comparison clip")
local comparison = Assets.Get("COC_Corn_Continuous_02")
assert(
	comparison.Duration == 11.064,
	"Comparison manifest must retain the prepared author duration"
)
assert(
	Rules.CornLoopSpeed == 1 and Rules.CornLoopSprintSpeed == 1.5,
	"Unexpected loop playback speeds"
)
assert(
	Assets.Get("unknown").Id == "" and Assets.Get("unknown").Duration == 0,
	"Unknown asset must be inert"
)
for _, key in Rules.CornKeys do
	assert(Assets.Get(key).Duration > 0, "Missing corn duration: " .. key)
end
for _, key in Rules.VoiceKeys do
	assert(Assets.Get(key).Duration > 0, "Missing monster voice duration: " .. key)
end
print(
	"PASS:15 preserved author clips plus 1 continuous comparison clip; finite durations/gains, role headroom, walk1/sprint1.5; configured Roblox IDs="
		.. configured
)
assert(configured == 0 or configured == 16, "Audio ID mapping incomplete")
