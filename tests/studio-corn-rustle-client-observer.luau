-- Bounded read-only client observation of the isolated server playback fixture.
local RS = game:GetService("ReplicatedStorage")
local HTTP = game:GetService("HttpService")
local Run = game:GetService("RunService")
assert(Run:IsStudio() and Run:IsRunning() and Run:IsClient())
assert(workspace.CornMap:GetAttribute("corn_project_id") == "children_of_corn")
local reportValue = Instance.new("StringValue")
reportValue.Name = "CornRustleClientObserver_" .. HTTP:GenerateGUID(false)
reportValue:SetAttribute("corn_test_owned", true)
reportValue.Parent = RS
local report = {
	done = false,
	sounds = {},
	events = {},
	method = "Real client Sound properties and natural Ended events; fixture motion, no ordinary walking or human audibility claim",
}
local connections, seen = {}, {}
local began = os.clock()
local function bind(sound)
	if
		not sound:IsA("Sound")
		or seen[sound]
		or sound:GetAttribute("audio_role") ~= "corn_rustle"
	then
		return
	end
	local model = sound:FindFirstAncestorOfClass("Model")
	if
		not model
		or model:GetAttribute("corn_test_owned") ~= true
		or not string.match(model.Name, "^CornRustlePlaybackScratch_")
	then
		return
	end
	seen[sound] = true
	local row = {
		path = sound:GetFullName(),
		fixture_id = model:GetAttribute("FixtureId"),
		loaded = false,
		ends = 0,
		stops = 0,
		max_position = 0,
		max_loudness = 0,
		clips = {},
	}
	local active
	table.insert(report.sounds, row)
	local function sample()
		if not sound.Parent then
			return
		end
		row.loaded = row.loaded or sound.IsLoaded
		row.max_position = math.max(row.max_position, sound.TimePosition)
		row.max_loudness = math.max(row.max_loudness, sound.PlaybackLoudness)
		if sound.IsPlaying and (not active or active.id ~= sound.SoundId or active.ended) then
			active = {
				id = sound.SoundId,
				start = os.clock() - began,
				length = sound.TimeLength,
				max_position = 0,
				max_loudness = 0,
			}
			table.insert(row.clips, active)
		end
		if active and not active.ended then
			active.length = math.max(active.length, sound.TimeLength)
			active.max_position = math.max(active.max_position, sound.TimePosition)
			active.max_loudness = math.max(active.max_loudness, sound.PlaybackLoudness)
		end
	end
	table.insert(
		connections,
		sound.Ended:Connect(function()
			row.ends += 1
			if active then
				active.ended = os.clock() - began
			end
		end)
	)
	table.insert(
		connections,
		sound.Stopped:Connect(function()
			row.stops += 1
		end)
	)
	table.insert(connections, Run.Heartbeat:Connect(sample))
	sample()
end
table.insert(connections, workspace.DescendantAdded:Connect(bind))
for _, item in workspace:GetDescendants() do
	bind(item)
end
task.spawn(function()
	while os.clock() - began < 43 do
		task.wait(0.25)
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	report.done = true
	report.elapsed_sec = os.clock() - began
	report.connections_removed = true
	reportValue.Value = HTTP:JSONEncode(report)
end)
reportValue.Value = HTTP:JSONEncode(report)
return { report_name = reportValue.Name, max_seconds = 43 }
