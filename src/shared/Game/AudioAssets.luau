--!strict
-- Author files prepared in assets/audio/roblox-import; real Roblox IDs are required.
local clips = {
	["COC_Corn_Continuous_02"] = table.freeze({
		-- Author-supplied full MP3, imported and decoder-checked in Studio.
		Id = "rbxassetid://138698164682825",
		Gain = 1,
		Duration = 11.064,
	}),
	["COC_Energy_Open"] = table.freeze({
		Id = "rbxassetid://117691782180305",
		Gain = 1.633052,
		Duration = 1.33,
	}),
	["COC_Trap_Place"] = table.freeze({
		Id = "rbxassetid://113868187938008",
		Gain = 0.997700,
		Duration = 0.57,
	}),
	["COC_Crickets_15s"] = table.freeze({
		Id = "rbxassetid://135204357018646",
		Gain = 0.994260,
		Duration = 15.02,
	}),
	["COC_Hunt"] = table.freeze({
		Id = "rbxassetid://112733609126247",
		Gain = 0.998849,
		Duration = 90.04,
	}),
	["COC_Background_02"] = table.freeze({
		Id = "rbxassetid://134619170853693",
		Gain = 0.998849,
		Duration = 61.91,
	}),
	["COC_Fire"] = table.freeze({
		Id = "rbxassetid://105538100476464",
		Gain = 1.001152,
		Duration = 29.31,
	}),
	["COC_Monster_01"] = table.freeze({
		Id = "rbxassetid://100872584572146",
		Gain = 1.000000,
		Duration = 2.38,
	}),
	["COC_Monster_02"] = table.freeze({
		Id = "rbxassetid://92691373477671",
		Gain = 0.998849,
		Duration = 3.06,
	}),
	["COC_Monster_03"] = table.freeze({
		Id = "rbxassetid://128947814251611",
		Gain = 1.003460,
		Duration = 3.6,
	}),
	["COC_Corn_02"] = table.freeze({
		Id = "rbxassetid://70577970161798",
		Gain = 1.515305,
		Duration = 0.89,
	}),
	["COC_Corn_10"] = table.freeze({
		Id = "rbxassetid://136100994535896",
		Gain = 0.988553,
		Duration = 0.44,
	}),
	["COC_Corn_11"] = table.freeze({
		Id = "rbxassetid://82316318861323",
		Gain = 2.251645,
		Duration = 1.15,
	}),
	["COC_Corn_13"] = table.freeze({
		Id = "rbxassetid://128248535752141",
		Gain = 1.158777,
		Duration = 2.06,
	}),
	["COC_Corn_18"] = table.freeze({
		Id = "rbxassetid://101463611520693",
		Gain = 1.316740,
		Duration = 0.97,
	}),
	["COC_Corn_20"] = table.freeze({
		Id = "rbxassetid://80980555958242",
		Gain = 0.993116,
		Duration = 0.99,
	}),
}
local missing = table.freeze({ Id = "", Gain = 1, Duration = 0 })
local Assets = {}
function Assets.Get(key: string): { Id: string, Gain: number, Duration: number }
	return clips[key] or missing
end
function Assets.List(): { [string]: { Id: string, Gain: number, Duration: number } }
	return clips
end
table.freeze(clips)
return table.freeze(Assets)
