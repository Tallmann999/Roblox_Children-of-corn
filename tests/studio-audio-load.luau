-- Actual client audio decoder; no world gameplay or audible mix claim.
local SoundService = game:GetService("SoundService")
local Assets = require(game.ReplicatedStorage.GameShared.Game.AudioAssets)
local folder = Instance.new("Folder")
folder.Name = "AudioLoadAcceptance"
folder:SetAttribute("corn_test_owned", true)
folder.Parent = SoundService
local sounds, result, missing = {}, {}, {}
local ok, problem = pcall(function()
	for key, clip in Assets.List() do
		assert(string.match(clip.Id, "^rbxassetid://%d+$"), "Missing real ID: " .. key)
		local sound = Instance.new("Sound")
		sound.Name = key
		sound.SoundId = clip.Id
		sound.Volume = 0
		sound.Parent = folder
		sounds[key] = sound
	end
	local deadline = os.clock() + 15
	while os.clock() < deadline do
		local all = true
		for _, sound in sounds do
			if not sound.IsLoaded then all = false end
		end
		if all then break end
		task.wait(0.2)
	end
	for key, sound in sounds do
		result[key] = { loaded = sound.IsLoaded, length = sound.TimeLength, id = sound.SoundId }
		if not sound.IsLoaded or sound.TimeLength <= 0 then
			table.insert(missing, key)
		end
	end
end)
folder:Destroy()
assert(ok, tostring(problem))
return game:GetService("HttpService"):JSONEncode({ assets = result, loaded_count = 15 - #missing, missing = missing, passed = #missing == 0, cleanup = true, method = "Actual IsLoaded/TimeLength for all fifteen author assets, muted temporary decoding; no claim of listener mix" })
