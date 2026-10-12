-- Current RoundHud constructor/render/Activated/_fitCard methods, deterministic
-- GUI-object adapter. No engine pixels/network asset loading or physical mouse claims.
local fs = require("@lune/fs")
local process = require("@lune/process")
local r = require("@lune/roblox")
local viewport = r.Vector2.new(1400, 800)
local function signal()
	local items = {}
	return {
		Connect = function(_, fn)
			local c = {
				Connected = true,
				Disconnect = function(self)
					self.Connected = false
				end,
			}
			table.insert(items, { c, fn })
			return c
		end,
		Fire = function(_, ...)
			for _, entry in items do
				if entry[1].Connected then
					entry[2](...)
				end
			end
		end,
	}
end
local api, make = {}, nil
local function sizeOf(item)
	if item._class == "ScreenGui" or item._class == "PlayerGui" then
		return viewport
	end
	local parent = if item.Parent then sizeOf(item.Parent) else viewport
	return r.Vector2.new(
		item.Size.X.Scale * parent.X + item.Size.X.Offset,
		item.Size.Y.Scale * parent.Y + item.Size.Y.Offset
	)
end
local function scaleOf(item)
	local result = if item.Parent then scaleOf(item.Parent) else 1
	for _, child in item._children do
		if child._class == "UIScale" then
			result *= child.Scale
		end
	end
	return result
end
local meta = {
	__index = function(item, key)
		if api[key] then
			return api[key]
		end
		if key == "Parent" then
			return item._props.Parent
		end
		if key == "AbsoluteSize" then
			return sizeOf(item) * scaleOf(item)
		end
		if key == "AbsolutePosition" then
			if item._class == "ScreenGui" or item._class == "PlayerGui" then
				return r.Vector2.zero
			end
			local parentSize = if item.Parent then sizeOf(item.Parent) else viewport
			local parentScale = if item.Parent then scaleOf(item.Parent) else 1
			local parentPos = if item.Parent then item.Parent.AbsolutePosition else r.Vector2.zero
			local own = sizeOf(item) * scaleOf(item)
			return parentPos
				+ r.Vector2.new(
					item.Position.X.Scale * parentSize.X + item.Position.X.Offset,
					item.Position.Y.Scale * parentSize.Y + item.Position.Y.Offset
				) * parentScale
				- r.Vector2.new(item.AnchorPoint.X * own.X, item.AnchorPoint.Y * own.Y)
		end
		if item._props[key] ~= nil then
			return item._props[key]
		end
		for _, child in item._children do
			if child.Name == key then
				return child
			end
		end
		return nil
	end,
	__newindex = function(item, key, value)
		if key == "Parent" then
			local prior = item._props.Parent
			if prior then
				for index, child in prior._children do
					if child == item then
						table.remove(prior._children, index)
						break
					end
				end
			end
			item._props.Parent = value
			if value then
				table.insert(value._children, item)
			end
		else
			item._props[key] = value
		end
	end,
}
make = function(class)
	return setmetatable({
		_class = class,
		_children = {},
		_signals = {},
		_props = {
			Name = class,
			Size = r.UDim2.fromOffset(0, 0),
			Position = r.UDim2.fromOffset(0, 0),
			AnchorPoint = r.Vector2.zero,
			Visible = true,
			Active = false,
			Scale = 1,
			Text = "",
			Image = "",
			Activated = signal(),
		},
	}, meta)
end
function api:IsA(class)
	return self._class == class or class == "Instance"
end
function api:GetChildren()
	return table.clone(self._children)
end
function api:GetDescendants()
	local all = {}
	for _, child in self._children do
		table.insert(all, child)
		for _, nested in child:GetDescendants() do
			table.insert(all, nested)
		end
	end
	return all
end
function api:FindFirstChild(name)
	for _, child in self._children do
		if child.Name == name then
			return child
		end
	end
	return nil
end
function api:WaitForChild(name)
	return assert(self:FindFirstChild(name), "Missing fixture node " .. name)
end
function api:GetPropertyChangedSignal(name)
	if not self._signals[name] then
		self._signals[name] = signal()
	end
	return self._signals[name]
end
function api:Destroy()
	for _, child in self:GetChildren() do
		child:Destroy()
	end
	self.Parent = nil
	self._props.Destroyed = true
end
local function load(path, env)
	local fn = assert(loadstring(fs.readFile(path), path))
	setfenv(fn, setmetatable(env, { __index = getfenv() }))
	return fn()
end
local modules = {
	LightingModes = load("src/shared/Game/LightingModes.luau", { Color3 = r.Color3 }),
	RoundText = load("src/shared/Game/RoundText.luau", {}),
	ModePreviewImages = load("src/shared/Game/ModePreviewImages.luau", {}),
	MinimapGeometry = load(
		"src/shared/Game/MinimapGeometry.luau",
		{ Vector2 = r.Vector2, Vector3 = r.Vector3 }
	),
}
local storage = make("Folder")
storage.Name = "ReplicatedStorage"
local shared = make("Folder")
shared.Name = "GameShared"
shared.Parent = storage
local gameFolder = make("Folder")
gameFolder.Name = "Game"
gameFolder.Parent = shared
for name in modules do
	local item = make("ModuleScript")
	item.Name = name
	item.Parent = gameFolder
end
local Hud = load("src/client/Game/RoundHud.luau", {
	game = {
		GetService = function(_, name)
			assert(name == "ReplicatedStorage")
			return storage
		end,
	},
	require = function(item)
		return assert(modules[item.Name], item.Name)
	end,
	Instance = { new = make },
	UDim2 = r.UDim2,
	UDim = r.UDim,
	Vector2 = r.Vector2,
	Color3 = r.Color3,
	Enum = r.Enum,
})
local seen, readyImages = {}, true
for _, mode in modules.LightingModes.Order do
	local uri = modules.ModePreviewImages[mode]
	if not uri:match("^rbxassetid://[1-9]%d*$") or seen[uri] then
		readyImages = false
	else
		seen[uri] = true
	end
end
if table.find(process.args, "--require-images") then
	assert(readyImages, "ModePreviewImages has empty/invalid/reused URI; photos pending")
end
local playerGui = make("PlayerGui")
local hud = Hud.new(playerGui)
local base = {
	lighting_mode = "medium",
	phase = "ready",
	has_key = false,
	gate_open = false,
	session_diamonds = 0,
	reward_diamonds = 0,
	elapsed_sec = 15,
	notice = "",
	stamina = 100,
	stamina_capacity = 100,
	is_sprinting = false,
	sprint_exhausted = false,
	start_look = r.Vector3.new(0, 0, -1),
	catches_remaining = 2,
	monster_state = "patrol",
	protection_sec = 0,
	minimap = { round_id = 1, visited = {}, deaths = {} },
}
local function render(phase)
	local state = table.clone(base)
	state.phase = phase
	hud:Render(state)
end
local function rect(item)
	return {
		x = item.AbsolutePosition.X,
		y = item.AbsolutePosition.Y,
		w = item.AbsoluteSize.X,
		h = item.AbsoluteSize.Y,
	}
end
local function inside(item, parent)
	local a, b = rect(item), rect(parent)
	assert(
		a.x >= b.x - 0.01
			and a.y >= b.y - 0.01
			and a.x + a.w <= b.x + b.w + 0.01
			and a.y + a.h <= b.y + b.h + 0.01,
		item.Name .. " overflow"
	)
	return a
end
local function separate(a, b, message)
	assert(
		a.x + a.w <= b.x + 0.01
			or b.x + b.w <= a.x + 0.01
			or a.y + a.h <= b.y + 0.01
			or b.y + b.h <= a.y + 0.01,
		message
	)
end
local photos = 0
for _, item in hud._root:GetDescendants() do
	assert(
		not item:IsA("ViewportFrame") and not item:IsA("WorldModel"),
		"Synthetic viewport scene remains"
	)
	if item:IsA("ImageLabel") then
		photos += 1
	end
end
assert(photos == 3, "Photo card count")
for _, size in { r.Vector2.new(1400, 800), r.Vector2.new(800, 600), r.Vector2.new(640, 480) } do
	viewport = size
	for _, phase in { "ready", "preparing", "active", "caught", "escaped", "aborted", "caught_out" } do
		render(phase)
		local expanded = phase == "ready"
			or phase == "escaped"
			or phase == "aborted"
			or phase == "caught_out"
		assert(
			hud._modeCards.Visible == expanded and hud._card.Visible == (phase ~= "active"),
			"Photo phase visibility"
		)
		inside(hud._card, hud._root)
		if expanded then
			local row = inside(hud._modeCards, hud._card)
			local previous = nil
			for _, mode in modules.LightingModes.Order do
				local option = hud._modeCards:FindFirstChild(mode)
				local bounds = inside(option, hud._modeCards)
				if previous then
					separate(previous, bounds, "Mode cards overlap")
				end
				previous = bounds
				local photo = inside(option.LightingPreview, option)
				assert(
					option.LightingPreview.Image == modules.ModePreviewImages[mode]
						and option.LightingPreview.ScaleType == r.Enum.ScaleType.Crop,
					"Photo URI/Crop"
				)
				assert(
					photo.w / photo.h > 1.5 and photo.w / photo.h < 1.8,
					"Photo aspect distorted"
				)
				local name = inside(option:FindFirstChild("Name"), option)
				local desc = inside(option.Description, option)
				local button = inside(option.Select, option)
				separate(photo, name, "photo/name overlap")
				separate(name, desc, "name/desc overlap")
				separate(desc, button, "desc/button overlap")
				hud._modeButtons[mode].Activated:Fire()
				assert(
					hud._selectedMode == mode
						and hud._modeButtons[mode].Text
							== modules.RoundText.corn_modes_selected_button,
					"Current choice handler failed"
				)
			end
			local hint = inside(hud._modeHint, hud._card)
			local balance = inside(hud._balance, hud._card)
			local action = inside(if phase == "ready" then hud._start else hud._retry, hud._card)
			separate(row, hint, "row/hint overlap")
			separate(hint, balance, "hint/balance overlap")
			separate(balance, action, "balance/action overlap")
			if phase ~= "ready" then
				separate(action, inside(hud._menu, hud._card), "retry/menu overlap")
			end
		else
			for _, button in hud._modeButtons do
				assert(not button.Active, "Invisible mode button active")
			end
		end
	end
end
render("ready")
hud:SetBusy(true)
local prior = hud._selectedMode
hud._modeButtons.easy.Activated:Fire()
assert(hud._selectedMode == prior, "Busy choice changed")
hud:SetBusy(false)
hud:ShowUnavailable()
hud._modeButtons.easy.Activated:Fire()
assert(hud._selectedMode == prior, "Unavailable choice changed")
local oldConnections = table.clone(hud._connections)
hud:Destroy()
assert(#playerGui:GetChildren() == 0 and #hud._connections == 0, "Photo GUI cleanup failed")
for _, connection in oldConnections do
	assert(not connection.Connected, "Photo signal leaked")
end
print(
	"PASS: actual RoundHud photo constructor/render/choice handlers,3 Crop images/no cloned world, all phases,1400x800/800x600/640x480 adapter layouts and cleanup"
)
print(
	if readyImages
		then "PASS: configured photo URIs are nonempty/unique; asset/pixel acceptance remains engine-only"
		else "PENDING: three actual photo URIs still empty; no asset/image acceptance claimed"
)
