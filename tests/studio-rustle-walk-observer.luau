-- Read-only bounded observation of the real local avatar's production rustles.
-- Start before walking; runner records native/scripted motion separately.
-- This observer has no synthetic commits, motion, remote or Sound writes.
local Players = game:GetService("Players")
local Run = game:GetService("RunService")
local Http = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")
assert(Run:IsStudio() and Run:IsRunning() and Run:IsClient(), "Studio Play Client required")
local root =
	assert(Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart"), "Living root required")
assert(workspace.CornMap:GetAttribute("corn_project_id") == "children_of_corn", "Wrong project")
local value = Instance.new("StringValue")
value.Name = "CornRustleWalkObserver_" .. Http:GenerateGUID(false)
value:SetAttribute("corn_test_owned", true)
value.Parent = RS
local began = os.clock()
local report = {
	done = false,
	method = "Read-only actual local avatar production Sound observer during walking; motion method recorded separately",
	voices = {},
	cues = {},
	positions = {},
}
local connections, seen = {}, {}
local function bind(sound)
	if not sound:IsA("Sound") or seen[sound] then
		return
	end
	local role = sound:GetAttribute("audio_role")
	if role == "corn_rustle" then
		seen[sound] = true
		table.insert(
			connections,
			sound:GetAttributeChangedSignal("AudioRustleStart"):Connect(function()
				table.insert(
					report.cues,
					{ at = os.clock() - began, commit = sound:GetAttribute("AudioRustleStart") }
				)
			end)
		)
		return
	end
	if role ~= "corn_rustle_local" then
		return
	end
	local row = { name = sound.Name, clips = {}, ended = 0, stopped = 0, uri_cuts = 0 }
	local active
	seen[sound] = { sound = sound, row = row }
	table.insert(report.voices, row)
	table.insert(
		connections,
		sound.Played:Connect(function()
			active = {
				at = os.clock() - began,
				uri = sound.SoundId,
				key = sound:GetAttribute("AudioAssetKey"),
				id = sound:GetAttribute("AudioRustleId"),
				length = sound.TimeLength,
				max_position = 0,
				max_loudness = 0,
			}
			table.insert(row.clips, active)
		end)
	)
	table.insert(
		connections,
		sound.Ended:Connect(function()
			row.ended += 1
			if active then
				active.ended = os.clock() - began
			end
		end)
	)
	table.insert(
		connections,
		sound.Stopped:Connect(function()
			row.stopped += 1
		end)
	)
	table.insert(
		connections,
		sound:GetPropertyChangedSignal("SoundId"):Connect(function()
			if active and not active.ended and sound.IsPlaying and active.uri ~= sound.SoundId then
				row.uri_cuts += 1
			end
		end)
	)
	seen[sound].sample = function()
		if active and sound.Parent and not active.ended then
			active.length = math.max(active.length, sound.TimeLength)
			active.max_position = math.max(active.max_position, sound.TimePosition)
			active.max_loudness = math.max(active.max_loudness, sound.PlaybackLoudness)
		end
	end
end
table.insert(connections, root.ChildAdded:Connect(bind))
for _, child in root:GetChildren() do
	bind(child)
end
task.spawn(function()
	while os.clock() - began < 24 and root.Parent do
		for _, entry in seen do
			if type(entry) == "table" then
				entry.sample()
			end
		end
		table.insert(report.positions, {
			at = os.clock() - began,
			x = root.Position.X,
			y = root.Position.Y,
			z = root.Position.Z,
		})
		task.wait(0.1)
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	report.done = true
	value.Value = Http:JSONEncode(report)
end)
return { handle = value.Name, duration = 24 }
