local fs = require("@lune/fs")
local Rules = assert(loadstring(fs.readFile("src/shared/Game/AudioRules.luau")))()
for _, offset in { 0, 6, 12, 18, 24 } do
	assert(not Rules.CricketIsOn(99 + offset, 100, offset))
	for _, delta in { 0, 1, 14.999, 30, 44.999, 60, 74.999 } do
		assert(Rules.CricketIsOn(100 + offset + delta, 100, offset))
	end
	for _, delta in { 15, 15.001, 29.999, 45, 59.999, 75 } do
		assert(not Rules.CricketIsOn(100 + offset + delta, 100, offset))
	end
end
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
	"PASS: five staggered 15/15 cycles, exact fade-in/fade-out, pause/stall/invalid inputs, near/far hunt intensity and bounded pools"
)
