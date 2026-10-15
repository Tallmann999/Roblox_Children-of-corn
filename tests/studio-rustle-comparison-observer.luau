-- Bounded read-only production observer. Operator input/motion is recorded separately.
local Run = game:GetService("RunService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("SoundService")
local Http = game:GetService("HttpService")
assert(Run:IsStudio() and Run:IsRunning() and Run:IsClient(), "Play Client required")
assert(workspace.CornMap:GetAttribute("corn_project_id") == "children_of_corn")
local player = assert(Players.LocalPlayer)
local loop = assert(SS:FindFirstChild("CornPersonalAudio")):FindFirstChild("CornLoop")
assert(loop and loop:IsA("Sound") and loop.SoundId == "rbxassetid://138698164682825")
assert(
	loop:GetAttribute("CornAudioOwned") == true and loop:GetAttribute("audio_role") == "cornloop"
)
local hud = assert(player.PlayerGui:FindFirstChild("CornMovementHud"))
local value = Instance.new("StringValue")
value.Name = "CornRustleComparisonObserver_" .. Http:GenerateGUID(false)
value:SetAttribute("corn_test_owned", true)
value:SetAttribute("Stage", "initial")
value.Parent = RS
local began = os.clock()
local report = {
	method = "Read-only actual production Sound; native input and diagnostic staging recorded separately",
	done = false,
	events = {},
	samples = {},
	voices = {},
}
local connections, seen = {}, {}
local latestSnapshot
table.insert(connections, RS.GameRemotes.round_snapshot.OnClientEvent:Connect(function(snapshot)
	latestSnapshot = snapshot
end))
local function event(kind)
	table.insert(
		report.events,
		{
			at = os.clock() - began,
			stage = value:GetAttribute("Stage"),
			kind = kind,
			cursor = loop.TimePosition,
			speed = loop.PlaybackSpeed,
		}
	)
end
for _, name in { "Played", "Paused", "Resumed", "Stopped", "DidLoop", "Ended" } do
	table.insert(
		connections,
		loop[name]:Connect(function()
			event(name)
		end)
	)
end
local function bind(sound)
	if
		not sound:IsA("Sound")
		or seen[sound]
		or sound:GetAttribute("audio_role") ~= "corn_rustle_local"
	then
		return
	end
	seen[sound] = true
	local row = { path = sound:GetFullName(), plays = 0, natural_ends = 0, stops = 0 }
	table.insert(report.voices, row)
	table.insert(
		connections,
		sound.Played:Connect(function()
			row.plays += 1
		end)
	)
	table.insert(
		connections,
		sound.Ended:Connect(function()
			row.natural_ends += 1
		end)
	)
	table.insert(
		connections,
		sound.Stopped:Connect(function()
			row.stops += 1
		end)
	)
end
local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
if root then
	for _, child in root:GetChildren() do
		bind(child)
	end
	table.insert(connections, root.ChildAdded:Connect(bind))
end
task.spawn(function()
	while value.Parent and value:GetAttribute("Stop") ~= true and os.clock() - began < 180 do
		root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local source = root and root:FindFirstChild("CornAudio_corn_rustle")
		local snapshot = latestSnapshot
		table.insert(
			report.samples,
			{
				at = os.clock() - began,
				stage = value:GetAttribute("Stage"),
				cursor = loop.TimePosition,
				playing = loop.IsPlaying,
				speed = loop.PlaybackSpeed,
				loudness = loop.PlaybackLoudness,
				loaded = loop.IsLoaded,
				length = loop.TimeLength,
				mode = hud:GetAttribute("RustleMode"),
				corn_active = source and source:GetAttribute("AudioCornActive") == true,
				phase = snapshot and snapshot.phase,
				sprint = snapshot and snapshot.is_sprinting == true,
				x = root and root.Position.X,
				z = root and root.Position.Z,
			}
		)
		task.wait(0.1)
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	report.done = true
	if value.Parent then
		report.sample_count = #report.samples
		report.sample_chunks = {}
		-- StringValue has a 200000-byte limit. Publish bounded JSON arrays;
		-- the metadata stays small even for the full 180-second observation.
		for first = 1, #report.samples, 200 do
			local samples = {}
			for index = first, math.min(first + 199, #report.samples) do
				table.insert(samples, report.samples[index])
			end
			local chunk = Instance.new("StringValue")
			chunk.Name = "Samples" .. tostring(first)
			chunk:SetAttribute("corn_test_owned", true)
			chunk.Value = Http:JSONEncode(samples)
			assert(#chunk.Value < 200000, "Observer chunk exceeds StringValue limit")
			chunk.Parent = value
			table.insert(report.sample_chunks, chunk.Name)
		end
		report.samples = nil
		value.Value = Http:JSONEncode(report)
	end
end)
return { handle = value.Name, max_duration = 180 }
