local fs = require("@lune/fs")
local Rules = assert(loadstring(fs.readFile("src/shared/Game/AudioRules.luau")))()
assert(
	Rules.RustleVoices == 2 and Rules.RustleInterval == 0.225,
	"Rustle requires a fixed two-voice half cadence"
)
for _, offset in { 0, 6, 12, 18, 24 } do
	assert(not Rules.CricketIsOn(99 + offset, 100, offset))
	for _, delta in { 0, 1, 14.999, 30, 44.999, 60, 74.999 } do
		assert(Rules.CricketIsOn(100 + offset + delta, 100, offset))
	end
	for _, delta in { 15, 15.001, 29.999, 45, 59.999, 75 } do
		assert(not Rules.CricketIsOn(100 + offset + delta, 100, offset))
	end
end
assert(Rules.CricketFadeIn == 1 and Rules.CricketFadeOut == 1 and Rules.CricketStartWindow == 1)
for _, sample in
	{
		{ 0, 15, 15.02, 0 },
		{ 0.25, 14.75, 14.77, 0.25 },
		{ 0.5, 14.5, 14.52, 0.5 },
		{ 1, 14, 14.02, 1 },
		{ 14, 1, 1.02, 1 },
		{ 14.5, 0.5, 0.52, 0.5 },
		{ 14.9, 0.1, 0.12, 0.1 },
		{ 15, 0, 0.02, 0 },
		{ 1, 14, 0.3, 0.3 },
		{ 2, 13, 0, 0 },
		{ -0.1, 15, 15.02, 0 },
	}
do
	assert(math.abs(Rules.CricketEnvelope(sample[1], sample[2], sample[3]) - sample[4]) < 0.000001)
end
assert(Rules.CricketEnvelope(0 / 0, 15, 15) == 0)
assert(Rules.CricketEnvelope(1, math.huge, 15) == 0)
assert(Rules.CricketEnvelope(1, 15, -1) == 0)
local alpha = 0
for _ = 1, 84 do
	alpha = Rules.Fade(alpha, 1, 1 / 60, Rules.HuntFadeIn)
end
assert(math.abs(alpha - 1) < 0.00001)
for _ = 1, 150 do
	alpha = Rules.Fade(alpha, 0, 1 / 60, Rules.HuntFadeOut)
end
assert(math.abs(alpha) < 0.00001)
assert(Rules.Fade(0.4, 0, 10, 2.5) == 0)
assert(Rules.Fade(0.4, 1, 0, 1.4) == 0.4)
assert(Rules.Fade(0 / 0, 1, 1, 1) == 0)
assert(Rules.ChaseIntensity(10) == 1 and Rules.ChaseIntensity(42) == 0.35)
assert(Rules.ChaseIntensity(60) == 0 and Rules.ChaseIntensity(math.huge) == 0)
assert(#Rules.CornKeys == 6 and #Rules.VoiceKeys == 3 and Rules.ActorLimit == 8)
print(
	"PASS: five staggered 15/15 cycles, 1-second cricket start/end envelopes including shorter decoded clips and invalid inputs; existing hunt fades/intensity and bounded pools"
)
