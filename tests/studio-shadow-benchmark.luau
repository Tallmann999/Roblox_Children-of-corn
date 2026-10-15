-- Run on the verified Children_of_corn Studio CLIENT during Play, after the
-- coordinator fixes the player/camera. Does not move either. Async 5x30 seconds;
-- poll the returned local StringValue for stage progress and final JSON.
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
assert(
	RunService:IsStudio() and RunService:IsRunning() and RunService:IsClient(),
	"Studio Play Client required"
)
local PROJECT = "children_of_corn"
local map = assert(workspace:FindFirstChild("CornMap"), "CornMap required")
assert(map:IsA("Model") and map:GetAttribute("corn_project_id") == PROJECT, "Wrong project")
local player = assert(Players.LocalPlayer, "Client owner required")
local root = assert(
	player.Character and player.Character:FindFirstChild("HumanoidRootPart"),
	"Staged player root required"
)
local camera = assert(workspace.CurrentCamera, "Staged camera required")
local near = assert(map:FindFirstChild("CornClientPlants"), "Loaded near corn required")
local torches = assert(map:FindFirstChild("TorchMarkers"), "Owned torches required")
local function ownedNear()
	return near.Parent == map
		and near:IsA("Folder")
		and near:GetAttribute("CornClientRendererOwned") == true
		and near:GetAttribute("corn_project_id") == PROJECT
end
assert(ownedNear(), "Unrecognized near corn preserved")
assert(
	torches:GetAttribute("CornTorchMarkersOwned") == true
		and torches:GetAttribute("corn_project_id") == PROJECT,
	"Unrecognized torches preserved"
)
local userSettings = UserSettings():GetService("UserGameSettings")
local LIGHTING_FIELDS =
	{ "LightingStyle", "PrioritizeLightingQuality", "GlobalShadows", "ShadowSoftness" }
local originalLighting = {}
for _, key in LIGHTING_FIELDS do
	originalLighting[key] = Lighting[key]
end
assert(originalLighting.LightingStyle == Enum.LightingStyle.Soft, "Expected actual Soft baseline")
local originalQuality = userSettings.SavedQualityLevel
local effectiveQuality = originalQuality
local originalFrame, originalRoot, originalViewport, originalFov =
	camera.CFrame, root.Position, camera.ViewportSize, camera.FieldOfView
local began = os.clock()
local guid = HttpService:GenerateGUID(false)
local result = Instance.new("StringValue")
result.Name = "CornShadowBenchmarkReport_" .. guid
result:SetAttribute("corn_test_owned", true)
result:SetAttribute("FixtureId", guid)
result.Parent = ReplicatedStorage
local function readable(value)
	return if typeof(value) == "EnumItem" then tostring(value) else value
end
local function tryRead(reader)
	local ok, value = pcall(reader)
	return if ok then readable(value) else "unavailable: " .. tostring(value)
end
local function lightingRead()
	local values = {}
	for _, key in LIGHTING_FIELDS do
		values[key] = readable(Lighting[key])
	end
	return values
end
local function viewport()
	return { camera.ViewportSize.X, camera.ViewportSize.Y }
end
local function cameraRead()
	return {
		position = { camera.CFrame.Position.X, camera.CFrame.Position.Y, camera.CFrame.Position.Z },
		frame = { camera.CFrame:GetComponents() },
		fov = camera.FieldOfView,
		viewport = viewport(),
	}
end
local report = {
	fixture_version = 1,
	fixture_id = guid,
	done = false,
	passed = false,
	benchmark_valid = false,
	status = "running",
	phase = "preparing",
	warm_seconds = 5,
	measure_seconds = 25,
	quality_original = tostring(originalQuality),
	quality_target = tostring(Enum.SavedQualitySetting.QualityLevel10),
	fixed_quality = false,
	baseline_lighting = lightingRead(),
	initial_camera = cameraRead(),
	initial_focus = "unknown",
	focus_events = {},
	stages = {},
	method = "Static current-client RenderStepped A/B: Soft, Realistic only, Realistic plus at most 256 existing LOD1 BaseParts within 24 studs of the staged player, then at most two nearest enabled owned TorchLights, then Soft repeat. Each stage 5s warm +25s measurement. Attempts SavedQualityLevel10 with setter/readback; a capability refusal preserves actual quality and makes the comparison conditional because Automatic may adapt detail. Exact captured restore. Known background/transition frames excluded; initial unknown focus prevents foreground certification. No player/camera, geometry/Source/saved-world edits or whole-field per-frame scan. This short static test does not establish GPU headroom or ordinary-route performance.",
}
report.studio_rendering_quality = tryRead(function()
	return settings().Rendering.QualityLevel
end)
report.studio_graphics_mode = tryRead(function()
	return settings().Rendering.GraphicsMode
end)
report.graphics_quality_level = tryRead(function()
	return userSettings.GraphicsQualityLevel
end)
local candidates, selectedLights, partSnapshots, lightSnapshots = {}, {}, {}, {}
local connections = {}
local worker, watchdog
local finished = false
local focus, focusRevision = "unknown", 0
local measurement
local function publish()
	report.elapsed_sec = os.clock() - began
	result.Value = HttpService:JSONEncode(report)
end
local function focusEvent(value)
	focus, focusRevision = value, focusRevision + 1
	table.insert(report.focus_events, { at = os.clock() - began, focused = value })
end
table.insert(
	connections,
	UserInputService.WindowFocused:Connect(function()
		focusEvent(true)
	end)
)
table.insert(
	connections,
	UserInputService.WindowFocusReleased:Connect(function()
		focusEvent(false)
	end)
)
local function restoreFlags(problems)
	for _, snapshot in partSnapshots do
		local part = snapshot.part
		if part.Parent then
			if not ownedNear() or not part:IsDescendantOf(near) then
				table.insert(problems, "Near part ownership/path changed: " .. snapshot.path)
			else
				local ok, failure = pcall(function()
					part.CastShadow = snapshot.value
				end)
				if not ok or part.CastShadow ~= snapshot.value then
					table.insert(
						problems,
						"CastShadow restore: " .. tostring(failure or snapshot.path)
					)
				end
			end
		end
	end
	for _, snapshot in lightSnapshots do
		local light, torch = snapshot.light, snapshot.torch
		if light.Parent then
			if
				torch.Parent ~= torches
				or torch:GetAttribute("CornTorchOwned") ~= true
				or torch:GetAttribute("corn_project_id") ~= PROJECT
				or not light:IsDescendantOf(torch)
			then
				table.insert(problems, "Torch ownership/path changed: " .. snapshot.path)
			else
				local ok, failure = pcall(function()
					light.Shadows = snapshot.value
				end)
				if not ok or light.Shadows ~= snapshot.value then
					table.insert(
						problems,
						"Light.Shadows restore: " .. tostring(failure or snapshot.path)
					)
				end
			end
		end
	end
end
local function finish(status, problem)
	if finished then
		return
	end
	finished = true
	measurement = nil
	for _, connection in connections do
		connection:Disconnect()
	end
	local problems = {}
	restoreFlags(problems)
	for _, key in LIGHTING_FIELDS do
		if Lighting[key] ~= originalLighting[key] then
			local ok, failure = pcall(function()
				Lighting[key] = originalLighting[key]
			end)
			if not ok or Lighting[key] ~= originalLighting[key] then
				table.insert(
					problems,
					key .. " restore: " .. tostring(failure or "readback mismatch")
				)
			end
		end
	end
	if userSettings.SavedQualityLevel ~= originalQuality then
		local qualityOk, qualityFailure = pcall(function()
			userSettings.SavedQualityLevel = originalQuality
		end)
		if not qualityOk or userSettings.SavedQualityLevel ~= originalQuality then
			table.insert(
				problems,
				"SavedQualityLevel restore: " .. tostring(qualityFailure or "readback mismatch")
			)
		end
	end
	report.cleanup, report.cleanup_problems = #problems == 0, problems
	report.restored_lighting, report.restored_quality =
		lightingRead(), tostring(userSettings.SavedQualityLevel)
	report.final_focus, report.final_camera = focus, cameraRead()
	report.done, report.status, report.problem, report.phase = true, status, problem, "done"
	report.passed = status == "completed" and report.cleanup
	local allValid = #report.stages == 5
	for _, stage in report.stages do
		allValid = allValid and stage.valid
	end
	report.benchmark_valid = report.passed and allValid
	if report.passed and not report.benchmark_valid then
		report.status = "completed_conditional"
	end
	publish()
	print("SHADOW_BENCHMARK " .. report.status .. " " .. result.Name)
	if watchdog and watchdog ~= coroutine.running() then
		pcall(task.cancel, watchdog)
	end
end
local function percentile(sorted, fraction)
	return sorted[math.clamp(math.ceil(#sorted * fraction), 1, #sorted)] * 1000
end
local function metrics(samples)
	if #samples == 0 then
		return { frames = 0 }
	end
	local sorted, sum, over33, over50, over100 = table.clone(samples), 0, 0, 0, 0
	for _, dt in samples do
		sum += dt
		if dt > 0.033 then
			over33 += 1
		end
		if dt > 0.05 then
			over50 += 1
		end
		if dt > 0.1 then
			over100 += 1
		end
	end
	table.sort(sorted)
	return {
		frames = #samples,
		sampled_seconds = sum,
		fps = #samples / sum,
		mean_ms = sum / #samples * 1000,
		p50_ms = percentile(sorted, 0.5),
		p95_ms = percentile(sorted, 0.95),
		p99_ms = percentile(sorted, 0.99),
		max_ms = sorted[#sorted] * 1000,
		over_33ms = over33,
		over_50ms = over50,
		over_100ms = over100,
	}
end
table.insert(
	connections,
	RunService.RenderStepped:Connect(function(dt)
		local current = measurement
		if not current or dt <= 0 or dt ~= dt then
			return
		end
		current.total_frames += 1
		if current.previous_revision ~= focusRevision then
			current.transition_frames += 1
		elseif focus == false then
			current.background_frames += 1
		else
			table.insert(current.samples, dt)
			if focus == true then
				table.insert(current.foreground_samples, dt)
			else
				current.unknown_frames += 1
			end
		end
		current.previous_revision = focusRevision
	end)
)
local function addIssue(stage, issue)
	if not table.find(stage.issues, issue) then
		table.insert(stage.issues, issue)
	end
end
local function snapshotCounts(stage)
	local alive, partCount, lightCount = 0, 0, 0
	for _, entry in partSnapshots do
		if entry.part.Parent then
			alive += 1
			if entry.part.CastShadow then
				partCount += 1
			end
		end
	end
	for _, entry in lightSnapshots do
		if entry.light.Parent and entry.light.Shadows and entry.light.Enabled then
			lightCount += 1
		end
	end
	return {
		selected_parts_alive = alive,
		selected_parts_casting = partCount,
		selected_enabled_shadow_lights = lightCount,
		loaded_near_plants = near:GetAttribute("LoadedPlants"),
		loaded_backdrop_plants = (
			map:FindFirstChild("CornClientBackdrop")
			and map.CornClientBackdrop:GetAttribute("LoadedPlants")
		) or 0,
		expected_parts_casting = if stage.corn then #partSnapshots else 0,
		expected_shadow_lights = if stage.lights then #lightSnapshots else 0,
	}
end
local function observe(stage)
	if
		workspace.CurrentCamera ~= camera
		or not root.Parent
		or (root.Position - originalRoot).Magnitude > 0.25
	then
		addIssue(stage, "Player/camera identity or staged player position changed")
	end
	local relative = originalFrame:ToObjectSpace(camera.CFrame)
	local _, angle = relative:ToAxisAngle()
	if
		relative.Position.Magnitude > 0.1
		or math.abs(angle) > 0.005
		or camera.FieldOfView ~= originalFov
	then
		addIssue(stage, "Staged camera pose/FOV changed")
	end
	if camera.ViewportSize ~= originalViewport then
		addIssue(stage, "Viewport changed")
	end
	if userSettings.SavedQualityLevel ~= effectiveQuality then
		addIssue(stage, "SavedQualityLevel drifted")
	end
	if Lighting.LightingStyle ~= stage.style then
		addIssue(stage, "LightingStyle drifted")
	end
	for _, key in { "PrioritizeLightingQuality", "GlobalShadows", "ShadowSoftness" } do
		if Lighting[key] ~= originalLighting[key] then
			addIssue(stage, key .. " drifted")
		end
	end
	if not ownedNear() then
		addIssue(stage, "Near folder ownership/path changed")
	end
	for _, entry in partSnapshots do
		if
			not entry.part.Parent
			or not entry.part:IsDescendantOf(near)
			or entry.part.CastShadow ~= stage.corn
		then
			addIssue(stage, "Selected near caster disappeared or changed")
			break
		end
	end
	for _, entry in lightSnapshots do
		if
			not entry.light.Parent
			or not entry.light.Enabled
			or entry.light.Shadows ~= stage.lights
		then
			addIssue(stage, "Selected enabled torch disappeared or changed")
			break
		end
	end
end
local function abort(reason)
	finish("aborted", reason)
	if worker and worker ~= coroutine.running() and coroutine.status(worker) ~= "dead" then
		pcall(task.cancel, worker)
	end
end
for _, item in { game, map, root, camera } do
	table.insert(
		connections,
		item.Destroying:Connect(function()
			abort("Staged client lifecycle ended: " .. item.ClassName)
		end)
	)
end
publish()
watchdog = task.delay(175, function()
	finish("blocked", "175-second watchdog; incomplete stages are not benchmark acceptance")
	if worker and coroutine.status(worker) ~= "dead" then
		pcall(task.cancel, worker)
	end
end)
worker = task.spawn(function()
	local ok, failure = xpcall(function()
		-- One finite near-only inventory. Neither backdrop nor Workspace is scanned.
		for _, item in near:GetDescendants() do
			if item:IsA("BasePart") then
				local chunk = item.Parent
				while chunk and chunk.Parent ~= near do
					chunk = chunk.Parent
				end
				local distance = (item.Position - originalRoot).Magnitude
				if
					chunk
					and chunk:GetAttribute("DetailStride") == 3
					and distance <= 24
					and not item.CastShadow
				then
					table.insert(
						candidates,
						{ part = item, distance = distance, path = item:GetFullName() }
					)
				end
			end
		end
		table.sort(candidates, function(a, b)
			return if a.distance == b.distance then a.path < b.path else a.distance < b.distance
		end)
		for index = 1, math.min(256, #candidates) do
			local entry = candidates[index]
			table.insert(partSnapshots, {
				part = entry.part,
				value = entry.part.CastShadow,
				path = entry.path,
				distance = entry.distance,
			})
		end
		for _, torch in torches:GetChildren() do
			if
				torch:IsA("Model")
				and torch:GetAttribute("CornTorchOwned") == true
				and torch:GetAttribute("corn_project_id") == PROJECT
				and torch:HasTag("corn_torch")
			then
				local flame = torch:FindFirstChild("Flame")
				local light = flame and flame:FindFirstChild("TorchLight")
				if
					flame
					and flame:IsA("BasePart")
					and light
					and light:IsA("PointLight")
					and light.Enabled
					and light.Brightness > 0
					and not light.Shadows
				then
					table.insert(selectedLights, {
						light = light,
						torch = torch,
						distance = (flame.Position - originalRoot).Magnitude,
					})
				end
			end
		end
		table.sort(selectedLights, function(a, b)
			return a.distance < b.distance
		end)
		for index = 1, math.min(2, #selectedLights) do
			local entry = selectedLights[index]
			table.insert(lightSnapshots, {
				light = entry.light,
				torch = entry.torch,
				value = entry.light.Shadows,
				path = entry.light:GetFullName(),
				distance = entry.distance,
			})
		end
		report.candidates_within_24_studs, report.selected_corn_parts, report.selected_lights =
			#candidates, #partSnapshots, {}
		for _, entry in lightSnapshots do
			table.insert(
				report.selected_lights,
				{ path = entry.path, distance = entry.distance, range = entry.light.Range }
			)
		end
		assert(
			#partSnapshots > 0,
			"No actual LOD1 parts within 24 studs; stage the player near corn"
		)
		assert(
			#lightSnapshots == 2,
			"Two enabled owned TorchLights required; stage near torches in dusk/night"
		)
		local qualityOk, qualityFailure = pcall(function()
			userSettings.SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel10
		end)
		effectiveQuality = userSettings.SavedQualityLevel
		report.quality_setter_ok = qualityOk
		report.quality_setter_problem = if qualityOk then nil else tostring(qualityFailure)
		report.quality_effective = tostring(effectiveQuality)
		report.fixed_quality = effectiveQuality == Enum.SavedQualitySetting.QualityLevel10
		if not report.fixed_quality then
			report.quality_limit =
				"Quality10 setter/readback unavailable; actual quality preserved. Automatic may adapt rendering detail between stages."
		end
		local stages = {
			{ name = "A0_Soft", style = Enum.LightingStyle.Soft, corn = false, lights = false },
			{
				name = "A1_Realistic",
				style = Enum.LightingStyle.Realistic,
				corn = false,
				lights = false,
			},
			{
				name = "B1_Realistic_near_corn",
				style = Enum.LightingStyle.Realistic,
				corn = true,
				lights = false,
			},
			{
				name = "C1_Realistic_near_corn_two_torches",
				style = Enum.LightingStyle.Realistic,
				corn = true,
				lights = true,
			},
			{
				name = "A0_Soft_repeat",
				style = Enum.LightingStyle.Soft,
				corn = false,
				lights = false,
			},
		}
		for _, settingsStage in stages do
			local stage = {
				name = settingsStage.name,
				issues = {},
				focus_first = focus,
				warm_started_at = os.clock() - began,
				corn = settingsStage.corn,
				lights = settingsStage.lights,
				style = settingsStage.style,
			}
			if not report.fixed_quality then
				addIssue(
					stage,
					"Fixed Quality10 unavailable; comparison uses actual quality and may adapt detail"
				)
			end
			Lighting.LightingStyle = stage.style
			assert(Lighting.LightingStyle == stage.style, "LightingStyle setter/readback refused")
			for _, entry in partSnapshots do
				assert(
					ownedNear() and entry.part:IsDescendantOf(near),
					"Near path changed before stage"
				)
				entry.part.CastShadow = stage.corn
			end
			for _, entry in lightSnapshots do
				assert(
					entry.light:IsDescendantOf(entry.torch) and entry.light.Enabled,
					"Enabled torch changed before stage"
				)
				entry.light.Shadows = stage.lights
			end
			stage.lighting, stage.quality, stage.camera_first =
				lightingRead(), tostring(userSettings.SavedQualityLevel), cameraRead()
			stage.warm_counts = snapshotCounts(stage)
			report.stage, report.phase = stage.name, "warm"
			-- Keep runtime-only EnumItem out of JSON; stage is appended after measurement.
			publish()
			local warmUntil = os.clock() + 5
			while os.clock() < warmUntil do
				observe(stage)
				task.wait(0.25)
			end
			local current = {
				samples = {},
				foreground_samples = {},
				total_frames = 0,
				background_frames = 0,
				transition_frames = 0,
				unknown_frames = 0,
				previous_revision = focusRevision,
			}
			stage.measure_started_at, stage.focus_measure_first = os.clock() - began, focus
			stage.counts_first = snapshotCounts(stage)
			measurement = current
			report.phase = "measure"
			publish()
			local measureUntil = os.clock() + 25
			while os.clock() < measureUntil do
				observe(stage)
				task.wait(1)
				publish()
			end
			measurement = nil
			stage.measure_ended_at, stage.focus_last, stage.camera_last =
				os.clock() - began, focus, cameraRead()
			stage.counts_last, stage.metrics, stage.foreground_metrics =
				snapshotCounts(stage), metrics(current.samples), metrics(current.foreground_samples)
			if
				stage.counts_first.loaded_near_plants ~= stage.counts_last.loaded_near_plants
				or stage.counts_first.loaded_backdrop_plants
					~= stage.counts_last.loaded_backdrop_plants
			then
				addIssue(stage, "Loaded corn counts changed during measurement")
			end
			stage.total_frames, stage.excluded_background_frames, stage.excluded_focus_transition_frames, stage.unknown_focus_frames =
				current.total_frames,
				current.background_frames,
				current.transition_frames,
				current.unknown_frames
			if current.unknown_frames > 0 then
				addIssue(stage, "Initial window focus unobserved; measurements conditional")
			end
			if current.background_frames > 0 or current.transition_frames > 0 then
				addIssue(stage, "Window focus changed/background frames excluded")
			end
			if #current.foreground_samples < 100 then
				addIssue(stage, "Insufficient certified foreground frames")
			end
			stage.valid = #stage.issues == 0
			stage.style = tostring(stage.style)
			table.insert(report.stages, stage)
			publish()
		end
	end, function(problem)
		return debug.traceback(tostring(problem), 2)
	end)
	measurement = nil
	finish(if ok then "completed" else "failed", if ok then nil else failure)
end)
return {
	status = "started",
	report_name = result.Name,
	fixture_id = guid,
	stages = 5,
	seconds_per_stage = 30,
	deadline_seconds = 175,
	read = "Poll this LOCAL ReplicatedStorage StringValue; save final JSON evidence, then remove only the report value.",
}
