-- Verified Studio Client only. Actual current GUI/assets; controlled phase/choice
-- states and simulated usable viewport inputs. No game/world/camera mutations.
local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local player = Players.LocalPlayer
local shared = game.ReplicatedStorage.GameShared.Game
local Images = require(shared.ModePreviewImages)
local Modes = require(shared.LightingModes)
local Text = require(shared.RoundText)
local RoundHud = require(player.PlayerScripts.GameClient.Game.RoundHud)
local function expect(condition: any, message: string?)
	assert(condition, message or "Photo-card state/style/layout assertion failed; see caller line")
end
local seen = {}
for _, mode in Modes.Order do
	local uri = Images[mode]
	expect(
		type(uri) == "string" and uri:match("^rbxassetid://[1-9]%d*$"),
		"Photo URI empty/invalid for " .. mode
	)
	expect(not seen[uri], "Photo URI reused across modes: " .. mode)
	seen[uri] = true
end
local hud = RoundHud.new(player.PlayerGui)
local actualRoot = hud._root
actualRoot.Name = "ModePhotoAcceptance"
local base = {
	lighting_mode = "medium",
	phase = "ready",
	has_key = false,
	gate_open = false,
	session_diamonds = 0,
	reward_diamonds = 0,
	elapsed_sec = 16,
	notice = "",
	stamina = 100,
	stamina_capacity = 100,
	is_sprinting = false,
	sprint_exhausted = false,
	start_look = Vector3.new(0, 0, -1),
	catches_remaining = 2,
	monster_state = "patrol",
	protection_sec = 0,
	minimap = { round_id = 1, visited = {}, deaths = {} },
}
local checks = {}
local function render(phase)
	local snapshot = table.clone(base)
	snapshot.phase = phase
	if phase == "escaped" then
		snapshot.reward_diamonds = 10
	end
	hud:Render(snapshot)
end
local function localRect(item, parentWidth, parentHeight)
	local width = item.Size.X.Scale * parentWidth + item.Size.X.Offset
	local height = item.Size.Y.Scale * parentHeight + item.Size.Y.Offset
	return {
		x = item.Position.X.Scale * parentWidth
			+ item.Position.X.Offset
			- item.AnchorPoint.X * width,
		y = item.Position.Y.Scale * parentHeight
			+ item.Position.Y.Offset
			- item.AnchorPoint.Y * height,
		w = width,
		h = height,
	}
end
local function inside(item, width, height)
	local a = localRect(item, width, height)
	expect(
		a.x >= -0.01 and a.y >= -0.01 and a.x + a.w <= width + 0.01 and a.y + a.h <= height + 0.01,
		item.Name .. " exceeds parent layout bounds"
	)
	return a
end
local function noOverlap(a, b, name)
	expect(
		a.x + a.w <= b.x + 0.01
			or b.x + b.w <= a.x + 0.01
			or a.y + a.h <= b.y + 0.01
			or b.y + b.h <= a.y + 0.01,
		"Overlap: " .. name
	)
end
local ok, problem = pcall(function()
	local failed = {}
	local photoLabels = {}
	for _, mode in Modes.Order do
		table.insert(photoLabels, hud._modeCards[mode].LightingPreview)
	end
	-- Instance content supplies ImageLabel's asset type to the engine loader.
	-- Bare URI preloading failed while these actual image objects succeeded.
	ContentProvider:PreloadAsync(photoLabels, function(uri, status)
		if status ~= Enum.AssetFetchStatus.Success then
			table.insert(failed, uri .. "/" .. status.Name)
		end
	end)
	expect(#failed == 0, "Photo fetch failed: " .. table.concat(failed, ", "))
	render("ready")
	local deadline = os.clock() + 10
	repeat
		local loaded = true
		for _, label in photoLabels do
			loaded = loaded and label.IsLoaded
		end
		if loaded then
			break
		end
		task.wait(0.1)
	until os.clock() >= deadline
	local imageCount = 0
	for _, item in actualRoot:GetDescendants() do
		expect(
			not item:IsA("ViewportFrame") and not item:IsA("WorldModel"),
			"Synthetic scene retained in photo UI"
		)
		if item:IsA("ImageLabel") then
			imageCount += 1
		end
	end
	expect(imageCount == 3)
	for _, mode in Modes.Order do
		local card = hud._modeCards:FindFirstChild(mode)
		expect(card and card.Name == mode and card:FindFirstChild("Select"))
		local image = card.LightingPreview
		expect(
			image:IsA("ImageLabel")
				and image.Image == Images[mode]
				and image.ScaleType == Enum.ScaleType.Crop
		)
		expect(image.IsLoaded, "Real photo not loaded for " .. mode)
		expect(image.Size.Y.Offset == 128 and image.Size.X.Scale == 1)
		expect(
			image.AbsoluteSize.X / image.AbsoluteSize.Y > 1.5
				and image.AbsoluteSize.X / image.AbsoluteSize.Y < 1.8
		)
		expect(card:FindFirstChild("Name").Text == Text["corn_modes_" .. mode])
		expect(card.Description.Text == Text["corn_modes_" .. mode .. "_desc"])
	end
	checks.unique_loaded_real_images_and_crop = true
	checks.three_photos_without_world_cloning = true
	for _, phase in { "ready", "preparing", "active", "caught", "escaped", "aborted", "caught_out" } do
		render(phase)
		local expanded = phase == "ready"
			or phase == "escaped"
			or phase == "aborted"
			or phase == "caught_out"
		expect(hud._modeCards.Visible == expanded)
		expect(
			hud._card.Visible == (phase ~= "active") and hud._active.Visible == (phase == "active")
		)
		for _, mode in Modes.Order do
			expect(hud._modeButtons[mode].Active == expanded)
		end
		if expanded then
			for _, choice in Modes.Order do
				hud._selectedMode = choice
				hud:_render()
				expect(hud._chooseMode.Text:find(Text["corn_modes_" .. choice], 1, true))
				for _, mode in Modes.Order do
					local button = hud._modeButtons[mode]
					expect(
						button.Text
							== (
								if mode == choice
									then Text.corn_modes_selected_button
									else Text.corn_modes_select
							)
					)
					expect(button.Active)
				end
			end
		end
	end
	checks.all_phases_and_controlled_choices = true
	render("ready")
	hud:SetBusy(true)
	for _, button in hud._modeButtons do
		expect(not button.Active)
	end
	hud:SetBusy(false)
	hud:ShowUnavailable()
	for _, button in hud._modeButtons do
		expect(not button.Active)
	end
	render("ready")
	checks.busy_unavailable_disable_choices = true
	for _, viewport in { Vector2.new(1400, 800), Vector2.new(800, 600), Vector2.new(640, 480) } do
		for _, phase in { "ready", "escaped", "preparing", "caught" } do
			render(phase)
			-- _fitCard reads only AbsoluteSize. The actual GUI/card remains the renderer target.
			hud._root = { AbsoluteSize = viewport }
			hud:_fitCard()
			hud._root = actualRoot
			local cardWidth, cardHeight = hud._card.Size.X.Offset, hud._card.Size.Y.Offset
			local scale = hud._cardScale.Scale
			expect(
				cardWidth * scale <= viewport.X - 36 + 0.01
					and cardHeight * scale <= viewport.Y - 36 + 0.01
			)
			local expanded = phase == "ready" or phase == "escaped"
			if expanded then
				local mapRect = inside(hud._modeCards, cardWidth, cardHeight)
				local titleRect = inside(hud._title, cardWidth, cardHeight)
				local messageRect = inside(hud._message, cardWidth, cardHeight)
				local chooseRect = inside(hud._chooseMode, cardWidth, cardHeight)
				noOverlap(titleRect, messageRect, "title/message")
				if hud._time.Visible then
					local timeRect = inside(hud._time, cardWidth, cardHeight)
					noOverlap(messageRect, timeRect, "message/time")
					noOverlap(timeRect, chooseRect, "time/choice")
				else
					noOverlap(messageRect, chooseRect, "message/choice")
				end
				noOverlap(chooseRect, mapRect, "choice/mode row")
				local previous = nil
				for _, mode in Modes.Order do
					local card = hud._modeCards[mode]
					local cardRect = inside(card, mapRect.w, mapRect.h)
					if previous then
						noOverlap(previous, cardRect, "mode siblings")
					end
					previous = cardRect
					local image = inside(card.LightingPreview, cardRect.w, cardRect.h)
					local name = inside(card:FindFirstChild("Name"), cardRect.w, cardRect.h)
					local desc = inside(card.Description, cardRect.w, cardRect.h)
					local select = inside(card.Select, cardRect.w, cardRect.h)
					noOverlap(image, name, "photo/name")
					noOverlap(name, desc, "name/description")
					noOverlap(desc, select, "description/select")
				end
				local hint = inside(hud._modeHint, cardWidth, cardHeight)
				local balance = inside(hud._balance, cardWidth, cardHeight)
				local action = inside(
					if phase == "ready" then hud._start else hud._retry,
					cardWidth,
					cardHeight
				)
				noOverlap(mapRect, hint, "mode row/hint")
				noOverlap(hint, balance, "hint/balance")
				noOverlap(balance, action, "balance/action")
				if phase == "escaped" then
					local menu = inside(hud._menu, cardWidth, cardHeight)
					noOverlap(action, menu, "retry/menu")
				end
			else
				inside(hud._preparingLeave, cardWidth, cardHeight)
			end
		end
	end
	checks.layout_bounds_and_no_overlap_at_simulated_viewports = true
	checks.simulated_usable_viewports = "1400x800 /800x600 /640x480; no physical window resize"
end)
hud._root = actualRoot
hud:Destroy()
expect(ok, tostring(problem))
expect(not player.PlayerGui:FindFirstChild("ModePhotoAcceptance"))
checks.cleanup = true
checks.method =
	"Current actual GUI/assets; controlled phases/choices and simulated _fitCard viewport inputs; mouse selection accepted separately"
return game:GetService("HttpService"):JSONEncode(checks)
