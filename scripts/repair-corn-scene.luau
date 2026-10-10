-- Paste ALL of repair-corn-scene.luau into the correct scene's Studio Command Bar.
local run = game:GetService("RunService")
assert(run:IsStudio() and not run:IsRunning(), "Stop Play before Corn scene repair")
local world = game:GetService("Workspace")
assert(not world:FindFirstChild("Asmr_Base") and not world:FindFirstChild("ASMR_Models"),
    "Speed Monkey detected; nothing changed")
local map = world:FindFirstChild("CornMap")
assert(map and map:IsA("Model") and map:GetAttribute("corn_project_id") == "children_of_corn",
    "Open the installed Children_of_corn scene; nothing changed")
local function resolve(path)
    local found = game
    for _, segment in string.split(path, "/") do found = found and found:FindFirstChild(segment) end
    return found
end
local function normalized(source) return (string.gsub(source, "\r\n", "\n")) end
local editor = game:GetService("ScriptEditorService")
local freshPaths = {
    ["ReplicatedStorage/GameShared/Game/CornLayout"] = true,
    ["ServerScriptService/GameServer/Game/MapAuthoring"] = true,
}

local baseline = {
{ path = [========[StarterPlayer/StarterPlayerScripts/GameClient/Bootstrap]========], class = [========[LocalScript]========], source = [========[--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameShared = ReplicatedStorage:WaitForChild("GameShared")
local Config = require(GameShared:WaitForChild("Config"):WaitForChild("GameConfig"))
local Workspace = game:GetService("Workspace")
local map = Workspace:WaitForChild("CornMap", 10)
if
	not map
	or map:GetAttribute("corn_project_id") ~= "children_of_corn"
	or Workspace:FindFirstChild("Asmr_Base")
	or Workspace:FindFirstChild("ASMR_Models")
then
	warn("[ChildrenOfCorn] Inactive: editable CornMap missing or another game detected")
	return
end
local Logger = require(GameShared:WaitForChild("Core"):WaitForChild("Logger"))
local log = Logger.new("ClientBootstrap", Config.Debug)

local controllersFolder = script.Parent:WaitForChild("Controllers")

type RuntimeModule = {
	Name: string?,
	Order: number?,
	Init: ((self: RuntimeModule, context: any) -> ())?,
	Start: ((self: RuntimeModule, context: any) -> ())?,
}

local loaded: { RuntimeModule } = {}
local byName: { [string]: RuntimeModule } = {}

for _, child in controllersFolder:GetChildren() do
	if child:IsA("ModuleScript") then
		local ok, result = pcall(require, child)
		if not ok then
			error(
				string.format(
					"Failed to require controller %s: %s",
					child:GetFullName(),
					tostring(result)
				)
			)
		end
		if type(result) ~= "table" then
			error(string.format("Controller %s must return a table", child:GetFullName()))
		end
		local module = result :: RuntimeModule
		local name = module.Name or child.Name
		if byName[name] then
			error(string.format("Duplicate controller name: %s", name))
		end
		module.Name = name
		byName[name] = module
		table.insert(loaded, module)
	end
end

table.sort(loaded, function(a, b)
	return (a.Order or 100) < (b.Order or 100)
end)

local context = {
	Config = Config,
	Controllers = byName,
	Log = Logger.new("Client", Config.Debug),
}

for _, module in loaded do
	if module.Init then
		module:Init(context)
	end
end

for _, module in loaded do
	if module.Start then
		module:Start(context)
	end
end

log:Info(string.format("Started %d controllers", #loaded))
]========] },
{ path = [========[StarterPlayer/StarterPlayerScripts/GameClient/Controllers/RoundController]========], class = [========[ModuleScript]========], source = [========[--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameShared = ReplicatedStorage:WaitForChild("GameShared")
local EndpointNames = require(GameShared:WaitForChild("Network"):WaitForChild("EndpointNames"))
local RoundHud = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("RoundHud"))

type Snapshot = RoundHud.Snapshot

local RoundController = {
	Name = "RoundController",
	Order = 100,
	_snapshot = nil :: Snapshot?,
	_requestRemote = nil :: RemoteEvent?,
	_snapshotConnection = nil :: RBXScriptConnection?,
	_lastRequest = -math.huge,
	_hud = nil :: any,
}

local PHASES: { [string]: boolean } = {
	ready = true,
	preparing = true,
	active = true,
	escaped = true,
	aborted = true,
}
local ACTIONS: { [string]: boolean } = {
	start = true,
	retry = true,
	abort = true,
	menu = true,
}
local DEBOUNCE_SEC = 0.55
local REMOTE_WAIT_SEC = 10

local function nonnegativeNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value >= 0 and value < math.huge
end

local function validSnapshot(value: any): boolean
	return typeof(value) == "table"
		and typeof(value.phase) == "string"
		and PHASES[value.phase] == true
		and typeof(value.has_key) == "boolean"
		and typeof(value.gate_open) == "boolean"
		and nonnegativeNumber(value.session_diamonds)
		and nonnegativeNumber(value.reward_diamonds)
		and nonnegativeNumber(value.elapsed_sec)
		and typeof(value.notice) == "string"
end

local function getRemote(folder: Instance, name: string): RemoteEvent?
	local instance = folder:WaitForChild(name, REMOTE_WAIT_SEC)
	if not instance or not instance:IsA("RemoteEvent") then
		warn(
			string.format(
				"[RoundController] RemoteEvent %s is unavailable after %ds",
				name,
				REMOTE_WAIT_SEC
			)
		)
		return nil
	end
	return instance
end

function RoundController:Init(_context: any)
	self._snapshot = nil :: Snapshot?
	self._requestRemote = nil :: RemoteEvent?
	self._snapshotConnection = nil :: RBXScriptConnection?
	self._lastRequest = -math.huge
	self._hud = nil

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui", REMOTE_WAIT_SEC)
	if not playerGui or not playerGui:IsA("PlayerGui") then
		warn("[RoundController] PlayerGui is unavailable; the round interface was not created")
		return
	end
	self._hud = RoundHud.new(playerGui)
	self._hud:SetOnAction(function(action: string)
		self:_request(action)
	end)
end

function RoundController:_request(action: string)
	local remote = self._requestRemote
	local hud = self._hud
	if not remote or not hud or not self._snapshot or ACTIONS[action] ~= true then
		return
	end
	local now = os.clock()
	if now - self._lastRequest < DEBOUNCE_SEC then
		return
	end
	self._lastRequest = now
	hud:SetBusy(true)
	remote:FireServer(action)
	-- Only the server changes the view. A rejected request must not leave buttons stuck.
	task.delay(DEBOUNCE_SEC, function()
		if self._hud == hud then
			hud:SetBusy(false)
		end
	end)
end

function RoundController:Start(_context: any)
	local hud = self._hud
	if not hud then
		return
	end
	local folder = ReplicatedStorage:WaitForChild("GameRemotes", REMOTE_WAIT_SEC)
	if not folder or not folder:IsA("Folder") then
		warn("[RoundController] GameRemotes is unavailable; check RoundService startup in Output")
		hud:ShowUnavailable()
		return
	end
	local requestRemote = getRemote(folder, EndpointNames.RequestRoundAction)
	local snapshotRemote = getRemote(folder, EndpointNames.RoundSnapshot)
	if not requestRemote or not snapshotRemote then
		hud:ShowUnavailable()
		return
	end
	self._requestRemote = requestRemote
	self._snapshotConnection = snapshotRemote.OnClientEvent:Connect(function(payload: any)
		if not validSnapshot(payload) then
			warn("[RoundController] Ignored a malformed round_snapshot")
			return
		end
		self._snapshot = payload :: Snapshot
		hud:Render(payload :: Snapshot)
	end)

	-- Subscribe first: initial server messages may precede the client controller.
	requestRemote:FireServer("sync")
	task.delay(2, function()
		if self._hud == hud and self._snapshot == nil then
			requestRemote:FireServer("sync")
		end
	end)
	task.delay(REMOTE_WAIT_SEC, function()
		if self._hud == hud and self._snapshot == nil then
			warn("[RoundController] No valid initial round_snapshot; check RoundService Output")
			hud:ShowUnavailable()
		end
	end)
end

function RoundController:Destroy()
	if self._snapshotConnection then
		self._snapshotConnection:Disconnect()
		self._snapshotConnection = nil
	end
	if self._hud then
		self._hud:Destroy()
		self._hud = nil
	end
	self._requestRemote = nil
end

return RoundController
]========] },
{ path = [========[StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornController]========], class = [========[ModuleScript]========], source = [========[--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameShared = ReplicatedStorage:WaitForChild("GameShared")
local CornLayout = require(GameShared:WaitForChild("Game"):WaitForChild("CornLayout"))

type Chunk = {
	Key: string,
	Folder: Folder,
	MinColumn: number,
	MaxColumn: number,
	MinRow: number,
	MaxRow: number,
	Column: number,
	Row: number,
	Distance: number,
	Count: number,
	Alive: boolean,
	Done: boolean,
}

local CornController = {
	Name = "CornController",
	Order = 50,
	_enabled = false,
	_connection = nil :: RBXScriptConnection?,
	_map = nil :: Model?,
	_field = nil :: BasePart?,
	_template = nil :: CornLayout.Plant?,
	_folder = nil :: Folder?,
	_chunks = {} :: { [string]: Chunk },
	_queue = {} :: { Chunk },
	_exclusions = nil :: CornLayout.Exclusions?,
	_pivotOffset = CFrame.identity,
	_height = CornLayout.Height,
	_pollElapsed = math.huge,
	_plantCount = 0,
	_lastWarning = "",
}

local PROJECT_ID = "children_of_corn"
local POLL_SEC = 0.3
local CREATE_BUDGET = 18
local CELL_BUDGET = 100
local TIME_BUDGET_SEC = 0.003
local MAX_CHUNKS = 28

function CornController:_warn(message: string)
	if self._lastWarning ~= message then
		self._lastWarning = message
		warn("[CornController] " .. message)
	end
end

function CornController:_clearChunks()
	for _, chunk in self._chunks do
		chunk.Alive = false
		chunk.Folder:Destroy()
	end
	self._chunks = {}
	self._queue = {}
	self._plantCount = 0
	if self._folder then
		self._folder:SetAttribute("LoadedPlants", 0)
	end
end

function CornController:_clearInputs()
	self:_clearChunks()
	if self._folder then
		self._folder:Destroy()
	end
	self._folder = nil
	self._map = nil
	self._field = nil
	self._template = nil
	self._exclusions = nil
end

function CornController:_resolveInputs(): boolean
	local map = Workspace:FindFirstChild("CornMap")
	local field = if map then map:FindFirstChild("FieldZone") else nil
	local art = ReplicatedStorage:FindFirstChild("CornRuntimeArt")
	local template = if art then art:FindFirstChild("CornPlantTemplate") else nil
	if not map or not map:IsA("Model") or map:GetAttribute("corn_project_id") ~= PROJECT_ID then
		self:_clearInputs()
		self:_warn("The owned CornMap is not available; editor preview is preserved")
		return false
	end
	if
		not field
		or not field:IsA("BasePart")
		or field.CFrame.UpVector:Dot(Vector3.yAxis) < 0.9999
	then
		self:_clearInputs()
		self:_warn("CornMap needs a horizontal FieldZone; editor preview is preserved")
		return false
	end
	if
		not art
		or not art:IsA("Folder")
		or art:GetAttribute("CornRuntimeArtOwned") ~= true
		or art:GetAttribute("corn_project_id") ~= PROJECT_ID
		or not template
		or (not template:IsA("Model") and not template:IsA("BasePart"))
		or template:GetAttribute("CornPlantTemplateOwned") ~= true
	then
		self:_clearInputs()
		self:_warn("Prepared corn art is not available; check CornField Output")
		return false
	end
	if
		self._map == map
		and self._field == field
		and self._template == template
		and self._folder
	then
		return true
	end
	self:_clearInputs()
	local existing = map:FindFirstChild("CornClientPlants")
	if existing then
		if
			not existing:IsA("Folder")
			or existing:GetAttribute("CornClientRendererOwned") ~= true
			or existing:GetAttribute("corn_project_id") ~= PROJECT_ID
		then
			self:_warn("Refused to replace unowned CornMap/CornClientPlants")
			return false
		end
		existing:Destroy()
	end
	local bounds, size = CornLayout.Bounds(template)
	self._pivotOffset = template:GetPivot():ToObjectSpace(bounds):Inverse()
	self._height = size.Y
	self._map = map
	self._field = field
	self._template = template
	local folder = Instance.new("Folder")
	folder.Name = "CornClientPlants"
	folder:SetAttribute("CornClientRendererOwned", true)
	folder:SetAttribute("corn_project_id", PROJECT_ID)
	folder:SetAttribute("LoadedPlants", 0)
	folder.Parent = map
	self._folder = folder
	-- This client-only deletion never changes the author's saved scene or Props.
	local preview = map:FindFirstChild("EditorPreview")
	if
		preview
		and preview:IsA("Folder")
		and preview:GetAttribute("CornEditorPreview") == true
		and preview:GetAttribute("corn_project_id") == PROJECT_ID
	then
		preview:Destroy()
	end
	self._lastWarning = ""
	return true
end

function CornController:_reconcile(root: BasePart)
	if not self:_resolveInputs() then
		return
	end
	local map = self._map :: Model
	local field = self._field :: BasePart
	local folder = self._folder :: Folder
	local exclusions = CornLayout.ReadExclusions(map, field)
	if self._exclusions and self._exclusions.Signature ~= exclusions.Signature then
		self:_clearChunks()
	end
	self._exclusions = exclusions
	local minColumn, maxColumn, minRow, maxRow = CornLayout.GetCellBounds(field)
	local localRoot = field.CFrame:PointToObjectSpace(root.Position)
	local width = CornLayout.Spacing * CornLayout.ChunkCells
	local radius = CornLayout.RenderRadius
	local desired: { any } = {}
	for chunkColumn = math.floor((localRoot.X - radius) / width), math.floor((localRoot.X + radius) / width) do
		for chunkRow = math.floor((localRoot.Z - radius) / width), math.floor((localRoot.Z + radius) / width) do
			local firstColumn = math.max(minColumn, chunkColumn * CornLayout.ChunkCells)
			local lastColumn = math.min(maxColumn, (chunkColumn + 1) * CornLayout.ChunkCells - 1)
			local firstRow = math.max(minRow, chunkRow * CornLayout.ChunkCells)
			local lastRow = math.min(maxRow, (chunkRow + 1) * CornLayout.ChunkCells - 1)
			if firstColumn > lastColumn or firstRow > lastRow then
				continue
			end
			local centerX = (firstColumn + lastColumn) * CornLayout.Spacing / 2
			local centerZ = (firstRow + lastRow) * CornLayout.Spacing / 2
			local distance = (centerX - localRoot.X) ^ 2 + (centerZ - localRoot.Z) ^ 2
			if distance <= radius * radius then
				table.insert(desired, {
					Key = chunkColumn .. ":" .. chunkRow,
					MinColumn = firstColumn,
					MaxColumn = lastColumn,
					MinRow = firstRow,
					MaxRow = lastRow,
					Distance = distance,
				})
			end
		end
	end
	table.sort(desired, function(a, b)
		return if a.Distance == b.Distance then a.Key < b.Key else a.Distance < b.Distance
	end)
	local wanted: { [string]: boolean } = {}
	for index, candidate in desired do
		if index > MAX_CHUNKS then
			break
		end
		wanted[candidate.Key] = true
		local chunk = self._chunks[candidate.Key]
		if chunk then
			chunk.Distance = candidate.Distance
		else
			local chunkFolder = Instance.new("Folder")
			chunkFolder.Name = "Chunk_" .. candidate.Key
			chunkFolder.Parent = folder
			chunk = {
				Key = candidate.Key,
				Folder = chunkFolder,
				MinColumn = candidate.MinColumn,
				MaxColumn = candidate.MaxColumn,
				MinRow = candidate.MinRow,
				MaxRow = candidate.MaxRow,
				Column = candidate.MinColumn,
				Row = candidate.MinRow,
				Distance = candidate.Distance,
				Count = 0,
				Alive = true,
				Done = false,
			}
			self._chunks[candidate.Key] = chunk
		end
	end
	for key, chunk in self._chunks do
		if not wanted[key] then
			chunk.Alive = false
			self._plantCount -= chunk.Count
			chunk.Folder:Destroy()
			self._chunks[key] = nil
		end
	end
	self._queue = {}
	for _, chunk in self._chunks do
		if not chunk.Done then
			table.insert(self._queue, chunk)
		end
	end
	table.sort(self._queue, function(a, b)
		return if a.Distance == b.Distance then a.Key < b.Key else a.Distance < b.Distance
	end)
end

function CornController:_createBatch()
	local template = self._template
	local field = self._field
	local exclusions = self._exclusions
	if not template or not field or not exclusions then
		return
	end
	local began = os.clock()
	local examined = 0
	local created = 0
	while
		#self._queue > 0
		and examined < CELL_BUDGET
		and created < CREATE_BUDGET
		and os.clock() - began < TIME_BUDGET_SEC
	do
		local chunk = self._queue[1]
		if not chunk.Alive or chunk.Done then
			table.remove(self._queue, 1)
			continue
		end
		local column = chunk.Column
		local row = chunk.Row
		chunk.Column += 1
		if chunk.Column > chunk.MaxColumn then
			chunk.Column = chunk.MinColumn
			chunk.Row += 1
		end
		if chunk.Row > chunk.MaxRow then
			chunk.Done = true
			table.remove(self._queue, 1)
		end
		examined += 1
		local position = CornLayout.CellPosition(field, column, row)
		if CornLayout.IsExcluded(position, exclusions) then
			continue
		end
		local clone = template:Clone()
		if not clone then
			self:_warn("Prepared corn template is not Archivable")
			self:Destroy()
			return
		end
		local plant = clone :: CornLayout.Plant
		plant.Name = "Corn"
		plant:PivotTo(
			field.CFrame
				* CFrame.new(
					column * CornLayout.Spacing,
					-field.Size.Y / 2 + self._height / 2,
					row * CornLayout.Spacing
				)
				* CFrame.Angles(0, CornLayout.CellYaw(column, row), 0)
				* self._pivotOffset
		)
		plant.Parent = chunk.Folder
		chunk.Count += 1
		self._plantCount += 1
		created += 1
	end
	if self._folder then
		self._folder:SetAttribute("LoadedPlants", self._plantCount)
	end
end

function CornController:_step(delta: number)
	self._pollElapsed += delta
	if self._pollElapsed >= POLL_SEC then
		self._pollElapsed = 0
		local character = Players.LocalPlayer.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if root and root:IsA("BasePart") then
			self:_reconcile(root)
		else
			self:_clearChunks()
		end
	end
	self:_createBatch()
end

function CornController:Init(context: any)
	self._enabled = RunService:IsStudio()
		and context.Config.Environment == "DEV"
		and context.Config.Game.SessionMode == "solo_local"
end

function CornController:Start()
	if not self._enabled or self._connection then
		return
	end
	self._connection = RunService.Heartbeat:Connect(function(delta: number)
		self:_step(delta)
	end)
end

function CornController:Destroy()
	self._enabled = false
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	self:_clearInputs()
end

return CornController
]========] },
{ path = [========[StarterPlayer/StarterPlayerScripts/GameClient/Game/RoundHud]========], class = [========[ModuleScript]========], source = [========[--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RoundText: { [string]: string } = require(
	ReplicatedStorage:WaitForChild("GameShared"):WaitForChild("Game"):WaitForChild("RoundText")
)

export type Snapshot = {
	phase: string,
	has_key: boolean,
	gate_open: boolean,
	session_diamonds: number,
	reward_diamonds: number,
	elapsed_sec: number,
	notice: string,
}

local RoundHud = {}
RoundHud.__index = RoundHud

local PANEL_COLOR = Color3.fromRGB(27, 32, 28)
local TEXT_COLOR = Color3.fromRGB(239, 242, 233)
local MUTED_COLOR = Color3.fromRGB(190, 199, 186)
local BUTTON_COLOR = Color3.fromRGB(84, 109, 67)
local DISABLED_COLOR = Color3.fromRGB(63, 69, 61)

local function text(key: string, values: { [string]: string | number }?): string
	local template = RoundText[key] or ""
	return (
		string.gsub(template, "{([%w_]+)}", function(name)
			local value = if values then values[name] else nil
			return if value ~= nil then tostring(value) else "{" .. name .. "}"
		end)
	)
end

local function elapsedText(seconds: number): string
	local whole = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", math.floor(whole / 60), whole % 60)
end

local function label(
	parent: Instance,
	name: string,
	size: UDim2,
	position: UDim2,
	fontSize: number
): TextLabel
	local result = Instance.new("TextLabel")
	result.Name = name
	result.Size = size
	result.Position = position
	result.BackgroundTransparency = 1
	result.Font = Enum.Font.Gotham
	result.TextSize = fontSize
	result.TextColor3 = TEXT_COLOR
	result.TextWrapped = true
	result.TextXAlignment = Enum.TextXAlignment.Left
	result.TextYAlignment = Enum.TextYAlignment.Center
	result.Text = ""
	result.Parent = parent
	return result
end

local function button(
	parent: Instance,
	name: string,
	key: string,
	size: UDim2,
	position: UDim2
): TextButton
	local result = Instance.new("TextButton")
	result.Name = name
	result.Size = size
	result.Position = position
	result.BackgroundColor3 = BUTTON_COLOR
	result.BorderSizePixel = 0
	result.Font = Enum.Font.GothamMedium
	result.TextSize = 17
	result.TextColor3 = TEXT_COLOR
	result.Text = text(key)
	result.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = result
	return result
end

local function panel(parent: Instance, name: string, size: UDim2, position: UDim2): Frame
	local result = Instance.new("Frame")
	result.Name = name
	result.Size = size
	result.Position = position
	result.BackgroundColor3 = PANEL_COLOR
	result.BackgroundTransparency = 0.08
	result.BorderSizePixel = 0
	result.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = result
	return result
end

function RoundHud.new(playerGui: PlayerGui)
	local root = Instance.new("ScreenGui")
	root.Name = "CornRoundHud"
	root.ResetOnSpawn = false
	root.DisplayOrder = 10
	root.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	root.Parent = playerGui

	local card = panel(root, "RoundCard", UDim2.fromOffset(460, 320), UDim2.fromScale(0.5, 0.5))
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	local title = label(card, "Title", UDim2.new(1, -48, 0, 38), UDim2.fromOffset(24, 20), 27)
	title.Font = Enum.Font.GothamBold
	local message = label(card, "Message", UDim2.new(1, -48, 0, 52), UDim2.fromOffset(24, 68), 19)
	local resultTime =
		label(card, "Elapsed", UDim2.new(1, -48, 0, 26), UDim2.fromOffset(24, 124), 16)
	resultTime.TextColor3 = MUTED_COLOR
	local balance = label(card, "Balance", UDim2.new(1, -48, 0, 26), UDim2.fromOffset(24, 154), 16)
	balance.TextColor3 = MUTED_COLOR
	local notice = label(card, "Notice", UDim2.new(1, -48, 0, 46), UDim2.fromOffset(24, 186), 16)
	notice.TextColor3 = Color3.fromRGB(233, 209, 142)
	local start = button(
		card,
		"Start",
		"corn_loop_start",
		UDim2.new(1, -48, 0, 44),
		UDim2.fromOffset(24, 250)
	)
	local retry = button(
		card,
		"Retry",
		"corn_loop_retry",
		UDim2.new(0.5, -30, 0, 44),
		UDim2.fromOffset(24, 250)
	)
	local menu = button(
		card,
		"Menu",
		"corn_loop_menu",
		UDim2.new(0.5, -30, 0, 44),
		UDim2.new(0.5, 6, 0, 250)
	)
	local preparingLeave = button(
		card,
		"Leave",
		"corn_loop_leave",
		UDim2.new(1, -48, 0, 44),
		UDim2.fromOffset(24, 250)
	)

	local active = panel(root, "ActiveStatus", UDim2.new(0.64, 0, 0, 128), UDim2.fromOffset(20, 16))
	local activeConstraint = Instance.new("UISizeConstraint")
	activeConstraint.MaxSize = Vector2.new(690, 128)
	activeConstraint.Parent = active
	local objective =
		label(active, "Objective", UDim2.new(1, -32, 0, 32), UDim2.fromOffset(16, 8), 19)
	objective.Font = Enum.Font.GothamMedium
	local activeTime =
		label(active, "Elapsed", UDim2.new(1, -32, 0, 24), UDim2.fromOffset(16, 42), 15)
	activeTime.TextColor3 = MUTED_COLOR
	local activeBalance =
		label(active, "Balance", UDim2.new(1, -32, 0, 24), UDim2.fromOffset(16, 66), 15)
	activeBalance.TextColor3 = MUTED_COLOR
	local activeNotice =
		label(active, "Notice", UDim2.new(1, -32, 0, 24), UDim2.fromOffset(16, 94), 16)
	activeNotice.TextColor3 = notice.TextColor3
	local activeLeave = button(
		root,
		"LeaveRound",
		"corn_loop_leave",
		UDim2.fromOffset(185, 40),
		UDim2.new(1, -205, 0, 16)
	)

	local self = setmetatable({
		_root = root,
		_card = card,
		_title = title,
		_message = message,
		_time = resultTime,
		_balance = balance,
		_notice = notice,
		_active = active,
		_objective = objective,
		_activeTime = activeTime,
		_activeBalance = activeBalance,
		_activeNotice = activeNotice,
		_start = start,
		_retry = retry,
		_menu = menu,
		_preparingLeave = preparingLeave,
		_activeLeave = activeLeave,
		_buttons = { start, retry, menu, preparingLeave, activeLeave },
		_connections = {} :: { RBXScriptConnection },
		_snapshot = nil :: Snapshot?,
		_busy = false,
		_unavailable = false,
	}, RoundHud)
	self:_render()
	return self
end

function RoundHud:SetOnAction(callback: (string) -> ())
	local bindings = {
		{ button = self._start, action = "start" },
		{ button = self._retry, action = "retry" },
		{ button = self._menu, action = "menu" },
		{ button = self._preparingLeave, action = "abort" },
		{ button = self._activeLeave, action = "abort" },
	}
	for _, binding in bindings do
		table.insert(
			self._connections,
			binding.button.Activated:Connect(function()
				if not self._busy and not self._unavailable and self._snapshot ~= nil then
					callback(binding.action)
				end
			end)
		)
	end
end

function RoundHud:_render()
	local snapshot = self._snapshot
	local phase = if snapshot then snapshot.phase else "loading"
	local isActive = phase == "active"
	local isResult = phase == "escaped" or phase == "aborted"
	self._card.Visible = not isActive
	self._active.Visible = isActive
	self._activeLeave.Visible = isActive
	self._start.Visible = phase == "ready" or phase == "loading"
	self._retry.Visible = isResult
	self._menu.Visible = isResult
	self._preparingLeave.Visible = phase == "preparing"
	for _, control in self._buttons do
		local enabled = snapshot ~= nil and not self._busy and not self._unavailable
		control.Active = enabled
		control.AutoButtonColor = enabled
		control.BackgroundColor3 = if enabled then BUTTON_COLOR else DISABLED_COLOR
		control.TextTransparency = if enabled then 0 else 0.35
	end

	self._title.Text = text("corn_loop_title")
	self._time.Text = ""
	self._notice.Text = if snapshot then text(snapshot.notice) else ""
	self._balance.Visible = snapshot ~= nil
	self._balance.Text = text(
		"corn_loop_test_balance",
		{ count = if snapshot then snapshot.session_diamonds else 0 }
	)
	if self._unavailable then
		self._message.Text = text("corn_loop_connection_error")
	elseif phase == "loading" or phase == "preparing" then
		self._message.Text = text("corn_loop_loading")
	elseif phase == "ready" then
		self._message.Text = text("corn_loop_objective_search")
	elseif snapshot and isResult then
		self._title.Text = text(
			if phase == "escaped" then "corn_loop_result_escape" else "corn_loop_result_aborted"
		)
		self._message.Text = if phase == "escaped"
			then text("corn_loop_reward", { count = snapshot.reward_diamonds })
			else ""
		self._time.Text = text("corn_loop_round_time", { time = elapsedText(snapshot.elapsed_sec) })
	end

	if snapshot and isActive then
		local objectiveKey = if snapshot.gate_open
			then "corn_loop_objective_exit"
			elseif snapshot.has_key then "corn_loop_objective_return"
			else "corn_loop_objective_search"
		self._objective.Text = text(objectiveKey)
		self._activeTime.Text =
			text("corn_loop_round_time", { time = elapsedText(snapshot.elapsed_sec) })
		self._activeBalance.Text = self._balance.Text
		self._activeNotice.Text = text(snapshot.notice)
	end
end

function RoundHud:Render(snapshot: Snapshot)
	self._unavailable = false
	self._snapshot = snapshot
	self:_render()
end

function RoundHud:SetBusy(busy: boolean)
	self._busy = busy
	self:_render()
end

function RoundHud:ShowUnavailable()
	self._unavailable = true
	self:_render()
end

function RoundHud:Destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	self._root:Destroy()
end

return RoundHud
]========] },
{ path = [========[ReplicatedStorage/GameShared/Config/GameConfig]========], class = [========[ModuleScript]========], source = [========[--!strict

local Balance = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("Balance"))

return {
	Environment = "DEV",
	Debug = true,
	Game = {
		Id = "children_of_corn",
		Name = "Дети кукурузы",
		Version = "0.1.0",
		SessionMode = "solo_local",
		SupportedDevice = "pc",
	},
	CoreLoop = Balance,
	Persistence = {
		Enabled = false,
		StoreName = "PlayerData_v1",
		SchemaVersion = 1,
	},
}
]========] },
{ path = [========[ReplicatedStorage/GameShared/Core/Logger]========], class = [========[ModuleScript]========], source = [========[--!strict

local Logger = {}
Logger.__index = Logger

function Logger.new(scope: string, debugEnabled: boolean?)
	return setmetatable({
		_scope = scope,
		_debug = debugEnabled == true,
	}, Logger)
end

function Logger:Info(...: any)
	print(string.format("[%s]", self._scope), ...)
end

function Logger:Warn(...: any)
	warn(string.format("[%s]", self._scope), ...)
end

function Logger:Debug(...: any)
	if self._debug then
		print(string.format("[%s][DEBUG]", self._scope), ...)
	end
end

return Logger
]========] },
{ path = [========[ReplicatedStorage/GameShared/Game/Balance]========], class = [========[ModuleScript]========], source = [========[--!strict

-- Baseline from docs/2026-10-09_core-loop_gd-spec.md, sections 11-12.
-- Field size is confirmed at 1200 x 1200; corn visibility still needs a Studio playtest.
return {
	target_round_min_sec = 420,
	target_round_max_sec = 600,
	hunt_start_delay_sec = 15,
	key_slot_count = 15,
	barrel_count = 3,
	max_catches = 2,
	stamina_capacity = 100,
	sprint_duration_sec = 4,
	stamina_refill_sec = 6,
	walk_speed = 12,
	sprint_speed = 18,
	monster_patrol_speed = 10,
	monster_chase_speed = 14,
	monster_detect_radius = 32,
	monster_lose_radius = 44,
	monster_lose_delay_sec = 1.5,
	monster_growl_radius = 72,
	monster_capture_radius = 3,
	capture_transition_sec = 1,
	respawn_protection_sec = 5,
	key_drop_adjust_radius = 6,
	interaction_radius = 4,
	escape_reward_diamonds = 10,
}
]========] },
{ path = [========[ReplicatedStorage/GameShared/Game/RoundText]========], class = [========[ModuleScript]========], source = [========[--!strict

-- Keep player-facing strings in the GD namespace; this slice has no hunt/stamina UI.
return table.freeze({
	corn_loop_title = "Дети кукурузы",
	corn_loop_start = "Начать",
	corn_loop_loading = "Подготовка раунда…",
	corn_loop_objective_search = "Найди ключ от ворот и сбеги",
	corn_loop_objective_return = "Ключ найден. Вернись к воротам",
	corn_loop_objective_exit = "Ворота открыты — беги наружу",
	corn_loop_need_key = "Нужен ключ",
	corn_loop_result_escape = "Ты сбежал",
	corn_loop_result_aborted = "Раунд завершён",
	corn_loop_reward = "+{count} алмазов",
	corn_loop_test_balance = "Алмазы в этом тесте: {count}",
	corn_loop_round_time = "Время раунда: {time}",
	corn_loop_retry = "Ещё раз",
	corn_loop_menu = "В меню",
	corn_loop_leave = "Завершить раунд",
	corn_loop_setup_error = "Не удалось подготовить раунд. Попробуй снова",
	corn_loop_connection_error = "Не удалось подключить интерфейс. Перезапусти тест Studio",
})
]========] },
{ path = [========[ReplicatedStorage/GameShared/Game/CornLayout]========], class = [========[ModuleScript]========], source = [========[--!strict

local CornLayout = {
	Height = 8,
	Spacing = 4.5,
	Seed = 817,
	ChunkCells = 8,
	RenderRadius = 85,
}

export type Plant = Model | BasePart
export type Box = { Frame: CFrame, HalfSize: Vector2 }
export type Circle = { Center: Vector3, Radius: number }
export type Exclusions = { Boxes: { Box }, Circles: { Circle }, Signature: string }

local SLOT_RADIUS = 6
local BOX_PADDING = 1.5

local function finite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

function CornLayout.Bounds(plant: Plant): (CFrame, Vector3)
	if plant:IsA("Model") then
		return plant:GetBoundingBox()
	end
	return plant.CFrame, plant.Size
end

function CornLayout.PrepareTemplate(source: Instance, height: number?): (Plant?, string?)
	if not source:IsA("Model") and not source:IsA("BasePart") then
		return nil, "Corn source must be a Model or BasePart"
	end
	local targetHeight = height or CornLayout.Height
	if not finite(targetHeight) or targetHeight <= 0 then
		return nil, "Corn height must be positive and finite"
	end
	local items = source:GetDescendants()
	table.insert(items, source)
	local partCount = 0
	for _, item in items do
		if item:IsA("LuaSourceContainer") then
			return nil, "Corn source contains code"
		end
		if
			item:IsA("Sound")
			or item:IsA("ParticleEmitter")
			or item:IsA("Beam")
			or item:IsA("Trail")
			or item:IsA("ProximityPrompt")
			or item:IsA("ClickDetector")
			or item:IsA("RemoteEvent")
			or item:IsA("RemoteFunction")
		then
			return nil, "Corn source must contain only static art"
		end
		if not item.Archivable then
			return nil, "Corn source has non-Archivable contents"
		end
		if item:IsA("BasePart") then
			partCount += 1
		end
	end
	if partCount == 0 then
		return nil, "Corn source has no BaseParts"
	end

	local prepared = source:Clone() :: Plant?
	if not prepared then
		return nil, "Corn source could not be cloned"
	end
	local ok, problem = pcall(function()
		local _, size = CornLayout.Bounds(prepared :: Plant)
		if not finite(size.Y) or size.Y <= 0 then
			error("Corn source has no usable height")
		end
		local ratio = targetHeight / size.Y
		if prepared:IsA("Model") then
			prepared:ScaleTo(prepared:GetScale() * ratio)
		else
			prepared.Size *= ratio
			for _, item in prepared:GetChildren() do
				if item:IsA("SpecialMesh") then
					item.Scale *= ratio
				end
			end
		end
		local clones = prepared:GetDescendants()
		table.insert(clones, prepared)
		for _, item in clones do
			-- Art tags must not become gameplay bindings on every decorative clone.
			for _, tag in item:GetTags() do
				item:RemoveTag(tag)
			end
			if item:IsA("BasePart") then
				item.Anchored = true
				item.CanCollide = false
				item.CanTouch = false
				item.CanQuery = false
				item.CastShadow = false
				if item:IsA("MeshPart") then
					item.DoubleSided = true
				end
			end
		end
		prepared:PivotTo(CornLayout.PivotForPlant(prepared, Vector3.zero, 0))
	end)
	if not ok then
		prepared:Destroy()
		return nil, tostring(problem)
	end
	return prepared, nil
end

function CornLayout.PivotForPlant(plant: Plant, groundPosition: Vector3, yaw: number): CFrame
	local bounds, size = CornLayout.Bounds(plant)
	local boundsFromPivot = plant:GetPivot():ToObjectSpace(bounds)
	return CFrame.new(groundPosition + Vector3.new(0, size.Y / 2, 0))
		* CFrame.Angles(0, yaw, 0)
		* boundsFromPivot:Inverse()
end

function CornLayout.GetCellBounds(field: BasePart): (number, number, number, number)
	local half = field.Size / 2
	return math.ceil(-half.X / CornLayout.Spacing),
		math.floor(half.X / CornLayout.Spacing),
		math.ceil(-half.Z / CornLayout.Spacing),
		math.floor(half.Z / CornLayout.Spacing)
end

function CornLayout.CellPosition(field: BasePart, column: number, row: number): Vector3
	return field.CFrame:PointToWorldSpace(
		Vector3.new(column * CornLayout.Spacing, -field.Size.Y / 2, row * CornLayout.Spacing)
	)
end

function CornLayout.CellYaw(column: number, row: number): number
	local hash = (column * 73856093 + row * 19349663 + CornLayout.Seed * 83492791) % 104729
	return hash / 104729 * math.pi * 2
end

local function footprint(frame: CFrame, size: Vector3, padding: number): Box
	local look = frame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local flat = CFrame.new(frame.Position) * CFrame.Angles(0, yaw, 0)
	local half = size / 2
	local right = flat.RightVector
	local forward = flat.LookVector
	local width = math.abs(right:Dot(frame.RightVector)) * half.X
		+ math.abs(right:Dot(frame.UpVector)) * half.Y
		+ math.abs(right:Dot(frame.LookVector)) * half.Z
	local depth = math.abs(forward:Dot(frame.RightVector)) * half.X
		+ math.abs(forward:Dot(frame.UpVector)) * half.Y
		+ math.abs(forward:Dot(frame.LookVector)) * half.Z
	return { Frame = flat, HalfSize = Vector2.new(width + padding, depth + padding) }
end

local function authorDescendants(map: Model): { Instance }
	local result: { Instance } = {}
	local stack = map:GetChildren()
	while #stack > 0 do
		local item = table.remove(stack)
		local owned = item:GetAttribute("corn_project_id") == "children_of_corn"
		local decoration = owned
			and (
				(item.Name == "EditorPreview" and item:GetAttribute("CornEditorPreview") == true)
				or (item.Name == "CornClientPlants" and item:GetAttribute("CornClientRendererOwned") == true)
				or item.Name == "CornRoundRuntime"
			)
		if decoration then
			continue
		end
		table.insert(result, item)
		for _, child in item:GetChildren() do
			table.insert(stack, child)
		end
	end
	return result
end
function CornLayout.ReadExclusions(map: Model, field: BasePart): Exclusions
	local boxes: { Box } = {}
	local circles: { Circle } = {}
	local signatures: { string } = { tostring(field.CFrame) .. "/" .. tostring(field.Size) }
	local included: { [Instance]: boolean } = {}
	local function addBox(part: BasePart, padding: number)
		if included[part] then
			return
		end
		included[part] = true
		table.insert(boxes, footprint(part.CFrame, part.Size, padding))
		table.insert(
			signatures,
			part:GetFullName()
				.. "/box/"
				.. tostring(part.CFrame)
				.. "/"
				.. tostring(part.Size)
				.. "/"
				.. padding
		)
	end
	for _, folderName in { "NoCornZones", "Props" } do
		local folder = map:FindFirstChild(folderName)
		if folder then
			for _, item in folder:GetDescendants() do
				if item:IsA("BasePart") then
					addBox(item, BOX_PADDING)
				end
			end
		end
	end
	for _, item in authorDescendants(map) do
		if item:IsA("BasePart") then
			if item:HasTag("corn_no_corn_zone") then
				addBox(item, BOX_PADDING)
			end
			if item:HasTag("corn_key_slot") then
				table.insert(circles, { Center = item.Position, Radius = SLOT_RADIUS })
				table.insert(signatures, item:GetFullName() .. "/slot/" .. tostring(item.Position))
			elseif item:HasTag("corn_spawn") then
				addBox(item, 4)
				table.insert(circles, { Center = item.Position, Radius = 10 })
				table.insert(signatures, item:GetFullName() .. "/spawn/" .. tostring(item.Position))
			end
		end
	end
	local gate = map:FindFirstChild("EscapeGate")
	if gate then
		local door = gate:FindFirstChild("Door", true)
		if door and door:IsA("BasePart") then
			addBox(door, 6)
		end
	end
	table.sort(signatures)
	return { Boxes = boxes, Circles = circles, Signature = table.concat(signatures, "|") }
end

function CornLayout.IsExcluded(position: Vector3, exclusions: Exclusions): boolean
	for _, circle in exclusions.Circles do
		local delta = position - circle.Center
		if delta.X * delta.X + delta.Z * delta.Z <= circle.Radius * circle.Radius then
			return true
		end
	end
	for _, box in exclusions.Boxes do
		local localPosition = box.Frame:PointToObjectSpace(position)
		if
			math.abs(localPosition.X) <= box.HalfSize.X
			and math.abs(localPosition.Z) <= box.HalfSize.Y
		then
			return true
		end
	end
	return false
end

return CornLayout
]========] },
{ path = [========[ReplicatedStorage/GameShared/Network/EndpointNames]========], class = [========[ModuleScript]========], source = [========[--!strict

return {
	RequestRoundAction = "request_round_action",
	RoundSnapshot = "round_snapshot",
}
]========] },
{ path = [========[ServerScriptService/GameServer/Bootstrap]========], class = [========[Script]========], source = [========[--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameShared = ReplicatedStorage:WaitForChild("GameShared")
local Config = require(GameShared:WaitForChild("Config"):WaitForChild("GameConfig"))
local Workspace = game:GetService("Workspace")
local map = Workspace:WaitForChild("CornMap", 10)
if
	not map
	or map:GetAttribute("corn_project_id") ~= "children_of_corn"
	or Workspace:FindFirstChild("Asmr_Base")
	or Workspace:FindFirstChild("ASMR_Models")
then
	warn("[ChildrenOfCorn] Inactive: editable CornMap missing or another game detected")
	return
end
local Logger = require(GameShared:WaitForChild("Core"):WaitForChild("Logger"))
local log = Logger.new("ServerBootstrap", Config.Debug)

local servicesFolder = script.Parent:WaitForChild("Services")

type RuntimeModule = {
	Name: string?,
	Order: number?,
	Init: ((self: RuntimeModule, context: any) -> ())?,
	Start: ((self: RuntimeModule, context: any) -> ())?,
}

local loaded: { RuntimeModule } = {}
local byName: { [string]: RuntimeModule } = {}

for _, child in servicesFolder:GetChildren() do
	if child:IsA("ModuleScript") then
		local ok, result = pcall(require, child)
		if not ok then
			error(
				string.format(
					"Failed to require service %s: %s",
					child:GetFullName(),
					tostring(result)
				)
			)
		end
		if type(result) ~= "table" then
			error(string.format("Service %s must return a table", child:GetFullName()))
		end
		local module = result :: RuntimeModule
		local name = module.Name or child.Name
		if byName[name] then
			error(string.format("Duplicate service name: %s", name))
		end
		module.Name = name
		byName[name] = module
		table.insert(loaded, module)
	end
end

table.sort(loaded, function(a, b)
	return (a.Order or 100) < (b.Order or 100)
end)

local context = {
	Config = Config,
	Services = byName,
	Log = Logger.new("Server", Config.Debug),
}

for _, module in loaded do
	if module.Init then
		module:Init(context)
	end
end

for _, module in loaded do
	if module.Start then
		module:Start(context)
	end
end

log:Info(string.format("Started %d services", #loaded))
]========] },
{ path = [========[ServerScriptService/GameServer/Game/SoloRound]========], class = [========[ModuleScript]========], source = [========[--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameShared = ReplicatedStorage:WaitForChild("GameShared")
local Endpoints = require(GameShared:WaitForChild("Network"):WaitForChild("EndpointNames"))
local AuthoredWorld = require(script.Parent:WaitForChild("AuthoredWorld"))

local SoloRound = {}
SoloRound.__index = SoloRound

function SoloRound.new(context: any)
	return setmetatable({
		context = context,
		balance = context.Config.CoreLoop,
		action = context.Services.NetworkService:GetEvent(Endpoints.RequestRoundAction),
		snapshot = context.Services.NetworkService:GetEvent(Endpoints.RoundSnapshot),
		world = nil :: any,
		player = nil :: Player?,
		phase = "ready",
		epoch = 0,
		hasKey = false,
		gateOpen = false,
		diamonds = 0,
		reward = 0,
		startedAt = nil :: number?,
		elapsed = 0,
		notice = "",
		random = Random.new(),
		connections = {} :: { RBXScriptConnection },
		characterConnection = nil :: RBXScriptConnection?,
		characterRemovingConnection = nil :: RBXScriptConnection?,
		deathConnection = nil :: RBXScriptConnection?,
		keyConnection = nil :: RBXScriptConnection?,
		roundCharacter = nil :: Model?,
		boundCharacter = nil :: Model?,
		controlledCharacter = nil :: Model?,
		jumpPower = 50,
		jumpHeight = 7.2,
		autoRotate = true,
		requestTokens = 2,
		requestAt = os.clock(),
		interactionAt = -math.huge,
		pollAt = 0,
		snapshotAt = 0,
	}, SoloRound)
end

function SoloRound:_send()
	local player = self.player
	if not player or player.Parent ~= Players then
		return
	end
	self.snapshot:FireClient(player, {
		phase = self.phase,
		has_key = self.hasKey,
		gate_open = self.gateOpen,
		session_diamonds = self.diamonds,
		reward_diamonds = self.reward,
		elapsed_sec = if self.phase == "active" and self.startedAt
			then os.clock() - self.startedAt
			else self.elapsed,
		notice = self.notice,
	})
end

function SoloRound:_livingCharacter(): (Model?, Humanoid?, BasePart?)
	local player = self.player
	local character = if player then player.Character else nil
	if not character or not character.Parent then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

function SoloRound:_controls(enabled: boolean)
	local character, humanoid = self:_livingCharacter()
	if not character or not humanoid then
		return
	end
	if self.controlledCharacter ~= character then
		self.controlledCharacter = character
		self.jumpPower = humanoid.JumpPower
		self.jumpHeight = humanoid.JumpHeight
		self.autoRotate = humanoid.AutoRotate
	end
	humanoid.WalkSpeed = if enabled then self.balance.walk_speed else 0
	humanoid.JumpPower = if enabled then self.jumpPower else 0
	humanoid.JumpHeight = if enabled then self.jumpHeight else 0
	humanoid.AutoRotate = enabled and self.autoRotate
end

function SoloRound:_moveToStart(character: Model)
	if not self.world then
		return
	end
	character:PivotTo(self.world:GetSpawnCFrame())
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
end

function SoloRound:_clearKey()
	if self.keyConnection then
		self.keyConnection:Disconnect()
		self.keyConnection = nil
	end
	if self.world then
		self.world:ClearKey()
	end
end

function SoloRound:_finish(phase: string, notice: string)
	if self.phase ~= "active" and self.phase ~= "preparing" then
		return
	end
	-- Fix the terminal state before rewarding or notifying any client.
	self.elapsed = if self.startedAt then os.clock() - self.startedAt else 0
	self.phase = phase
	self.epoch += 1
	self.notice = notice
	self.reward = if phase == "escaped" then self.balance.escape_reward_diamonds else 0
	self.diamonds += self.reward
	self.hasKey = false
	self:_clearKey()
	if self.world then
		self.world:SetInteractionEnabled(false, self.gateOpen)
	end
	self:_controls(false)
	self:_send()
	self.context.Log:Info("Round finished:", phase, "reward:", self.reward)
end

function SoloRound:_canInteract(
	player: Player,
	item: BasePart,
	itemPrompt: ProximityPrompt
): boolean
	if player ~= self.player or self.phase ~= "active" or not itemPrompt.Enabled then
		return false
	end
	local now = os.clock()
	if now - self.interactionAt < 0.25 then
		return false
	end
	self.interactionAt = now
	local character, _, root = self:_livingCharacter()
	if not character or character ~= self.roundCharacter or not root then
		return false
	end
	if not self.world or not item:IsDescendantOf(self.world.Root) then
		return false
	end
	local direction = item.Position - root.Position
	if direction.Magnitude > self.balance.interaction_radius then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	local hit = Workspace:Raycast(root.Position, direction, params)
	return not hit or hit.Instance == item
end

function SoloRound:_openGate(player: Player)
	local world = self.world
	if
		not world
		or self.gateOpen
		or not self:_canInteract(player, world.GateAnchor, world.GatePrompt)
	then
		return
	end
	local _, _, root = self:_livingCharacter()
	if not root or not world:IsGateFront(root.Position) then
		return
	end
	if not self.hasKey then
		self.notice = "corn_loop_need_key"
		self:_send()
		return
	end
	self.hasKey = false
	self.gateOpen = true
	self.notice = ""
	world:SetGateOpen(true)
	self:_send()
end

function SoloRound:_ensureWorld(): boolean
	if self.world then
		return self.world:IsValid()
	end
	local ok, result =
		pcall(AuthoredWorld.new, self.balance.interaction_radius, self.balance.key_slot_count)
	if not ok then
		self.context.Log:Warn("Cannot bind editable CornMap:", result)
		return false
	end
	self.world = result
	table.insert(
		self.connections,
		self.world.GatePrompt.Triggered:Connect(function(player: Player)
			self:_openGate(player)
		end)
	)
	return true
end

function SoloRound:_startRound()
	if self.phase ~= "ready" and self.phase ~= "escaped" and self.phase ~= "aborted" then
		return
	end
	self.epoch += 1
	local epoch = self.epoch
	self.phase = "preparing"
	self.startedAt = nil
	self.elapsed = 0
	self.reward = 0
	self.notice = ""
	self.hasKey = false
	self.gateOpen = false
	self.roundCharacter = nil
	self:_clearKey()
	self:_controls(false)
	self:_send()
	if not self:_ensureWorld() then
		self:_finish("aborted", "corn_loop_setup_error")
		return
	end
	self.world:SetGateOpen(false)
	self.world:SetInteractionEnabled(false, false)

	task.spawn(function()
		local deadline = os.clock() + 10
		local character: Model? = nil
		while
			self.epoch == epoch
			and self.phase == "preparing"
			and self.player
			and self.player.Parent == Players
		do
			character = self:_livingCharacter()
			if character or os.clock() >= deadline then
				break
			end
			task.wait(0.1)
		end
		if self.epoch ~= epoch or self.phase ~= "preparing" then
			return
		end
		if not character then
			self:_finish("aborted", "corn_loop_setup_error")
			return
		end
		if not self.world or not self.world:IsValid() then
			self:_finish("aborted", "corn_loop_setup_error")
			return
		end
		self:_moveToStart(character)
		self.roundCharacter = character
		local slot = self.world.Slots[self.random:NextInteger(1, #self.world.Slots)]
		local keyPrompt = self.world:SpawnKey(slot)
		self.keyConnection = keyPrompt.Triggered:Connect(function(player: Player)
			local key = self.world.Key
			if
				self.epoch ~= epoch
				or self.hasKey
				or self.gateOpen
				or not key
				or keyPrompt ~= self.world.KeyPrompt
			then
				return
			end
			if not self:_canInteract(player, key, keyPrompt) then
				return
			end
			self.hasKey = true
			self.notice = ""
			self:_clearKey()
			self:_send()
		end)
		self.startedAt = os.clock()
		self.phase = "active"
		self.world:SetInteractionEnabled(true, false)
		self:_controls(true)
		self:_send()
		self.context.Log:Info("Solo round started")
	end)
end

function SoloRound:_menu()
	if self.phase ~= "escaped" and self.phase ~= "aborted" then
		return
	end
	self.epoch += 1
	self.phase = "ready"
	self.reward = 0
	self.elapsed = 0
	self.startedAt = nil
	self.notice = ""
	self.hasKey = false
	self.gateOpen = false
	self:_clearKey()
	if self.world then
		self.world:SetGateOpen(false)
		self.world:SetInteractionEnabled(false, false)
	end
	local character = self:_livingCharacter()
	if character then
		self:_moveToStart(character)
	end
	self:_controls(false)
	self:_send()
end

function SoloRound:_request(player: Player, action: any)
	if player ~= self.player then
		return
	end
	local now = os.clock()
	self.requestTokens = math.min(2, self.requestTokens + (now - self.requestAt) * 2)
	self.requestAt = now
	if self.requestTokens < 1 then
		return
	end
	self.requestTokens -= 1
	if type(action) ~= "string" then
		return
	end
	if action == "sync" then
		self:_send()
	elseif
		(action == "start" and self.phase == "ready")
		or (action == "retry" and (self.phase == "escaped" or self.phase == "aborted"))
	then
		self:_startRound()
	elseif action == "abort" then
		self:_finish("aborted", "corn_loop_result_aborted")
	elseif action == "menu" then
		self:_menu()
	end
end

function SoloRound:_bindCharacter(character: Model)
	if character == self.boundCharacter then
		return
	end
	self.boundCharacter = character
	if self.deathConnection then
		self.deathConnection:Disconnect()
		self.deathConnection = nil
	end
	if self.phase == "active" or (self.phase == "preparing" and self.roundCharacter ~= nil) then
		self:_finish("aborted", "corn_loop_result_aborted")
	end
	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 10)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		local player = self.player
		if not player or player.Character ~= character or self.boundCharacter ~= character then
			return
		end
		if not humanoid or not humanoid:IsA("Humanoid") or not root or not root:IsA("BasePart") then
			self:_finish("aborted", "corn_loop_setup_error")
			return
		end
		self.deathConnection = humanoid.Died:Connect(function()
			if self.player and self.player.Character == character then
				self:_finish("aborted", "corn_loop_result_aborted")
			end
		end)
		if self.phase ~= "active" and self.phase ~= "preparing" then
			self:_moveToStart(character)
		end
		self:_controls(self.phase == "active" and self.roundCharacter == character)
		self:_send()
	end)
end

function SoloRound:_addPlayer(player: Player)
	if self.player then
		return -- One owner, no multiplayer matchmaking in this prototype.
	end
	self.player = player
	self.requestTokens = 2
	self.requestAt = os.clock()
	self.characterConnection = player.CharacterAdded:Connect(function(character: Model)
		self:_bindCharacter(character)
	end)
	self.characterRemovingConnection = player.CharacterRemoving:Connect(function(character: Model)
		if
			player == self.player
			and (character == self.boundCharacter or character == player.Character)
		then
			self:_finish("aborted", "corn_loop_result_aborted")
		end
	end)
	if player.Character then
		self:_bindCharacter(player.Character)
	end
	self:_send()
end

function SoloRound:_removePlayer(player: Player)
	if player ~= self.player then
		return
	end
	self.epoch += 1
	self:_clearKey()
	if self.characterConnection then
		self.characterConnection:Disconnect()
		self.characterConnection = nil
	end
	if self.deathConnection then
		self.deathConnection:Disconnect()
		self.deathConnection = nil
	end
	if self.characterRemovingConnection then
		self.characterRemovingConnection:Disconnect()
		self.characterRemovingConnection = nil
	end
	self.player = nil
	self.phase = "ready"
	self.hasKey = false
	self.gateOpen = false
	self.diamonds = 0
	self.reward = 0
	self.startedAt = nil
	self.elapsed = 0
	self.notice = ""
	self.roundCharacter = nil
	self.boundCharacter = nil
	self.controlledCharacter = nil
	if self.world then
		self.world:SetGateOpen(false)
		self.world:SetInteractionEnabled(false, false)
	end
end

function SoloRound:_poll(now: number)
	if self.phase ~= "active" then
		return
	end
	local character, _, root = self:_livingCharacter()
	if not character or character ~= self.roundCharacter or not root then
		self:_finish("aborted", "corn_loop_result_aborted")
		return
	end
	if
		not self.world
		or not self.world:IsValid()
		or not self.world:IsOnPlayground(root.Position)
	then
		self:_finish("aborted", "corn_loop_setup_error")
		return
	end
	if self.gateOpen and self.world:IsInExit(root.Position) then
		self:_finish("escaped", "")
		return
	end
	if now - self.snapshotAt >= 1 then
		self.snapshotAt = now
		self:_send()
	end
end

function SoloRound:Start()
	self:_ensureWorld()
	table.insert(
		self.connections,
		self.action.OnServerEvent:Connect(function(player: Player, action: any)
			self:_request(player, action)
		end)
	)
	table.insert(
		self.connections,
		Players.PlayerAdded:Connect(function(player: Player)
			self:_addPlayer(player)
		end)
	)
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player: Player)
			self:_removePlayer(player)
		end)
	)
	table.insert(
		self.connections,
		RunService.Heartbeat:Connect(function()
			local now = os.clock()
			if now - self.pollAt >= 0.1 then
				self.pollAt = now
				self:_poll(now)
			end
		end)
	)
	for _, player in Players:GetPlayers() do
		self:_addPlayer(player)
	end
end

return SoloRound
]========] },
{ path = [========[ServerScriptService/GameServer/Game/CornField]========], class = [========[ModuleScript]========], source = [========[--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local GameShared = ReplicatedStorage:WaitForChild("GameShared")
local Config = require(GameShared:WaitForChild("Config"):WaitForChild("GameConfig"))
local CornLayout = require(GameShared:WaitForChild("Game"):WaitForChild("CornLayout"))

local CornField = {}
local PROJECT_ID = "children_of_corn"
local OWNER_ATTRIBUTE = "CornRuntimeArtOwned"

function CornField.Prepare(): boolean
	if
		not RunService:IsStudio()
		or Config.Environment ~= "DEV"
		or Config.Game.SessionMode ~= "solo_local"
	then
		return false
	end
	local sources: { Instance } = {}
	for _, item in ServerStorage:GetChildren() do
		if item.Name == "CornPlantTemplate" or item.Name == "SM_Prop_Plant_Corn_01_L" then
			table.insert(sources, item)
		end
	end
	if #sources ~= 1 then
		warn(
			"[CornField] Expected exactly one ServerStorage CornPlantTemplate or SM_Prop_Plant_Corn_01_L art source"
		)
		return false
	end
	local prepared, problem = CornLayout.PrepareTemplate(sources[1])
	if not prepared then
		warn("[CornField] " .. (problem or "Could not prepare corn art"))
		return false
	end
	local folder: Instance? = nil
	for _, item in ReplicatedStorage:GetChildren() do
		if item.Name == "CornRuntimeArt" then
			if folder then
				prepared:Destroy()
				warn(
					"[CornField] Duplicate CornRuntimeArt containers; existing contents were preserved"
				)
				return false
			end
			folder = item
		end
	end
	if
		folder
		and (
			not folder:IsA("Folder")
			or folder:GetAttribute(OWNER_ATTRIBUTE) ~= true
			or folder:GetAttribute("corn_project_id") ~= PROJECT_ID
		)
	then
		prepared:Destroy()
		warn("[CornField] Refused to overwrite an unowned CornRuntimeArt container")
		return false
	end
	if folder then
		for _, item in folder:GetChildren() do
			if
				item.Name == "CornPlantTemplate"
				and item:GetAttribute("CornPlantTemplateOwned") ~= true
			then
				prepared:Destroy()
				warn("[CornField] Refused to overwrite unowned CornPlantTemplate art")
				return false
			end
		end
	else
		folder = Instance.new("Folder")
		folder.Name = "CornRuntimeArt"
		folder:SetAttribute(OWNER_ATTRIBUTE, true)
		folder:SetAttribute("corn_project_id", PROJECT_ID)
	end
	prepared.Name = "CornPlantTemplate"
	prepared:SetAttribute("CornPlantTemplateOwned", true)
	prepared:SetAttribute("CornPlantHeight", CornLayout.Height)
	for _, item in folder:GetChildren() do
		if
			item.Name == "CornPlantTemplate"
			and item:GetAttribute("CornPlantTemplateOwned") == true
		then
			item:Destroy()
		end
	end
	prepared.Parent = folder
	folder.Parent = ReplicatedStorage
	print("[CornField] Prepared a corn art clone; ServerStorage source is unchanged")
	return true
end

return CornField
]========] },
{ path = [========[ServerScriptService/GameServer/Game/AuthoredWorld]========], class = [========[ModuleScript]========], source = [========[--!strict
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local CornField = require(script.Parent:WaitForChild("CornField"))
local AuthoredWorld = {}
AuthoredWorld.__index = AuthoredWorld

local function namedPart(parent: Instance, name: string): BasePart
	local item = parent:FindFirstChild(name)
	assert(item and item:IsA("BasePart"), "Missing map part: " .. name)
	return item
end

local function hasTag(item: Instance, tag: string): boolean
	return CollectionService:HasTag(item, tag)
end

local function prompt(
	parent: Instance,
	name: string,
	action: string,
	object: string,
	radius: number
): ProximityPrompt
	assert(not parent:FindFirstChild(name), "Duplicate owned prompt: " .. name)
	local item = Instance.new("ProximityPrompt")
	item.Name = name
	item.ActionText = action
	item.ObjectText = object
	item.KeyboardKeyCode = Enum.KeyCode.E
	item.MaxActivationDistance = radius
	item.RequiresLineOfSight = true
	item.HoldDuration = 0
	item.Enabled = false
	item.Parent = parent
	return item
end

local function inBox(part: BasePart, position: Vector3): boolean
	local point = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(point.X) <= half.X
		and math.abs(point.Y) <= half.Y
		and math.abs(point.Z) <= half.Z
end

function AuthoredWorld.new(radius: number, expectedSlots: number)
	local root = Workspace:FindFirstChild("CornMap")
	assert(
		root and root:IsA("Model") and root:GetAttribute("corn_project_id") == "children_of_corn",
		"Install the editable CornMap in Children_of_corn before Test"
	)
	local spawn = namedPart(root, "RoundSpawn")
	local field = namedPart(root, "FieldZone")
	local bounds = namedPart(root, "PlayBounds")
	local gateModel = root:FindFirstChild("EscapeGate")
	assert(
		gateModel and gateModel:IsA("Model") and hasTag(gateModel, "corn_gate"),
		"Missing tagged EscapeGate"
	)
	local gate = namedPart(gateModel, "Door")
	local anchor = namedPart(gateModel, "InteractionAnchor")
	local exit = namedPart(gateModel, "ExitZone")
	assert(hasTag(spawn, "corn_spawn") and hasTag(exit, "corn_exit"), "Missing spawn/exit tags")
	assert(
		exit:GetAttribute("gate_id") == gateModel:GetAttribute("gate_id"),
		"Gate/exit identity mismatch"
	)
	local slots: { BasePart } = {}
	local seen: { [string]: boolean } = {}
	for _, item in root:GetDescendants() do
		if item:IsA("BasePart") and hasTag(item, "corn_key_slot") then
			local id = item:GetAttribute("slot_id")
			assert(
				type(id) == "string" and id ~= "" and not seen[id],
				"Key slot ids must be unique strings"
			)
			seen[id] = true
			table.insert(slots, item)
		end
	end
	assert(#slots == expectedSlots, "CornMap must have " .. tostring(expectedSlots) .. " key slots")
	table.sort(slots, function(a, b)
		return tostring(a:GetAttribute("slot_id")) < tostring(b:GetAttribute("slot_id"))
	end)
	assert(not root:FindFirstChild("CornRoundRuntime"), "CornRoundRuntime already exists")
	assert(not anchor:FindFirstChild("CornGatePrompt"), "CornGatePrompt already exists")
	assert(gate.CanCollide, "Closed Door must have CanCollide enabled")
	local artOk, artReady = pcall(CornField.Prepare)
	if not artOk or not artReady then
		warn("[AuthoredWorld] Corn art unavailable:", artReady)
	end
	local runtime = Instance.new("Folder")
	runtime.Name = "CornRoundRuntime"
	runtime:SetAttribute("corn_project_id", "children_of_corn")
	runtime.Parent = root
	local gatePrompt = prompt(anchor, "CornGatePrompt", "Открыть", "Ворота", radius)
	local self = setmetatable({
		Root = root,
		Radius = radius,
		Slots = slots,
		Spawn = spawn,
		Field = field,
		Bounds = bounds,
		GateModel = gateModel,
		Gate = gate,
		GateAnchor = anchor,
		Exit = exit,
		Runtime = runtime,
		GatePrompt = gatePrompt,
		ClosedTransparency = gate.Transparency,
		ClosedCollision = gate.CanCollide,
		ClosedQuery = gate.CanQuery,
		Key = nil :: Part?,
		KeyPrompt = nil :: ProximityPrompt?,
	}, AuthoredWorld)
	return self
end

function AuthoredWorld:GetSpawnCFrame(): CFrame
	return self.Spawn.CFrame * CFrame.new(0, self.Spawn.Size.Y / 2 + 3.5, 0)
end

function AuthoredWorld:ClearKey()
	if self.Key then
		self.Key:Destroy()
	end
	self.Key = nil
	self.KeyPrompt = nil
end

function AuthoredWorld:SpawnKey(slot: BasePart): ProximityPrompt
	assert(slot:IsDescendantOf(self.Root), "Key slot must belong to CornMap")
	self:ClearKey()
	local key = Instance.new("Part")
	key.Name = "GateKey"
	key.Size = Vector3.new(1.5, 0.4, 3)
	key.CFrame = slot.CFrame * CFrame.new(0, slot.Size.Y / 2 + 0.3, 0)
	key.Anchored = true
	key.Color = Color3.fromRGB(240, 198, 69)
	key.Material = Enum.Material.Metal
	key.CanCollide = false
	key.CanTouch = false
	key.Parent = self.Runtime
	self.Key = key
	self.KeyPrompt =
		prompt(key, "CornKeyPrompt", "Подобрать", "Ключ от ворот", self.Radius)
	return self.KeyPrompt
end

function AuthoredWorld:SetGateOpen(open: boolean)
	self.Gate.CanCollide = if open then false else self.ClosedCollision
	self.Gate.CanQuery = if open then false else self.ClosedQuery
	self.Gate.Transparency = if open then 1 else self.ClosedTransparency
	self.GatePrompt.Enabled = false
	self.Runtime:SetAttribute("GateOpen", open)
end

function AuthoredWorld:SetInteractionEnabled(enabled: boolean, gateOpen: boolean)
	self.GatePrompt.Enabled = enabled and not gateOpen
	if self.KeyPrompt then
		self.KeyPrompt.Enabled = enabled
	end
end

function AuthoredWorld:IsGateFront(position: Vector3): boolean
	local anchor = self.Gate.CFrame:PointToObjectSpace(self.GateAnchor.Position)
	local point = self.Gate.CFrame:PointToObjectSpace(position)
	local frontSign = if anchor.Z < 0 then -1 else 1
	return point.Z * frontSign > self.Gate.Size.Z / 2
end

function AuthoredWorld:IsInExit(position: Vector3): boolean
	return inBox(self.Exit, position)
end

function AuthoredWorld:IsOnPlayground(position: Vector3): boolean
	return inBox(self.Bounds, position)
end

function AuthoredWorld:IsValid(): boolean
	if
		self.Root.Parent ~= Workspace
		or not self.Runtime:IsDescendantOf(self.Root)
		or not self.Spawn:IsDescendantOf(self.Root)
		or not self.Field:IsDescendantOf(self.Root)
		or not self.Bounds:IsDescendantOf(self.Root)
		or not self.Gate:IsDescendantOf(self.Root)
		or not self.GateAnchor:IsDescendantOf(self.Root)
		or not self.Exit:IsDescendantOf(self.Root)
		or not self.GatePrompt:IsDescendantOf(self.GateAnchor)
		or #self.Slots ~= 15
	then
		return false
	end
	for _, slot in self.Slots do
		if not slot:IsDescendantOf(self.Root) then
			return false
		end
	end
	return true
end

return AuthoredWorld
]========] },
{ path = [========[ServerScriptService/GameServer/Game/MapAuthoring]========], class = [========[ModuleScript]========], source = [========[--!strict
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local Layout = require(
	ReplicatedStorage:WaitForChild("GameShared"):WaitForChild("Game"):WaitForChild("CornLayout")
)
local MapAuthoring = {}

local function guard()
	assert(
		RunService:IsStudio() and not RunService:IsRunning(),
		"Use the Command Bar in Studio Edit mode"
	)
	assert(
		not Workspace:FindFirstChild("Asmr_Base") and not Workspace:FindFirstChild("ASMR_Models"),
		"Speed Monkey scene detected; Corn installation refused"
	)
	local config = ReplicatedStorage:FindFirstChild("GameShared")
	config = config and config:FindFirstChild("Config")
	local module = config and config:FindFirstChild("GameConfig")
	assert(
		module
			and module:IsA("ModuleScript")
			and string.find(module.Source, 'Id = "children_of_corn"', 1, true),
		"Open the Children_of_corn project"
	)
end

local function artSource(): Instance
	local first = ServerStorage:FindFirstChild("CornPlantTemplate")
	local imported = ServerStorage:FindFirstChild("SM_Prop_Plant_Corn_01_L")
	assert(not (first and imported), "Keep one unambiguous corn source in ServerStorage")
	local source = first or imported
	assert(source, "Imported corn asset missing from ServerStorage")
	return source
end

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3
): Part
	local item = Instance.new("Part")
	item.Name = name
	item.Anchored = true
	item.Size = size
	item.Position = position
	item.Color = color
	item.TopSurface = Enum.SurfaceType.Smooth
	item.BottomSurface = Enum.SurfaceType.Smooth
	item.Parent = parent
	return item
end

local function zone(parent: Instance, name: string, size: Vector3, position: Vector3): Part
	local item = part(parent, name, size, position, Color3.fromRGB(123, 175, 113))
	item.Transparency = 1
	item.CanCollide = false
	item.CanTouch = false
	item.CanQuery = false
	return item
end

local function noCorn(parent: Instance, name: string, size: Vector3, position: Vector3): Part
	local item = zone(parent, name, size, position)
	CollectionService:AddTag(item, "corn_no_corn_zone")
	return item
end

local function house(parent: Instance, name: string, origin: Vector3)
	local root = Instance.new("Model")
	root.Name = name
	root.Parent = parent
	local walls = part(
		root,
		"Body",
		Vector3.new(20, 12, 24),
		origin + Vector3.new(0, 6, 0),
		Color3.fromRGB(95, 84, 62)
	)
	walls.Material = Enum.Material.WoodPlanks
	local door = part(
		root,
		"DecorativeDoor",
		Vector3.new(4, 7, 0.25),
		origin + Vector3.new(0, 3.5, -12.1),
		Color3.fromRGB(58, 45, 33)
	)
	door.Material = Enum.Material.Wood
	for _, side in { -1, 1 } do
		local roof = part(
			root,
			"Roof",
			Vector3.new(12, 1, 26),
			origin + Vector3.new(side * 5, 14, 0),
			Color3.fromRGB(54, 57, 49)
		)
		roof.CFrame *= CFrame.Angles(0, 0, -side * math.pi / 8)
		roof.Material = Enum.Material.Slate
	end
end

function MapAuthoring.Preview(map: Model, center: Vector3, radius: number?): number
	guard()
	local field = map:FindFirstChild("FieldZone")
	assert(field and field:IsA("BasePart"), "CornMap FieldZone missing")
	local old = map:FindFirstChild("EditorPreview")
	assert(
		not old
			or (
				old:IsA("Folder")
				and old:GetAttribute("CornEditorPreview") == true
				and old:GetAttribute("corn_project_id") == "children_of_corn"
			),
		"Unrecognized EditorPreview; not replaced"
	)
	local prepared, problem = Layout.PrepareTemplate(artSource())
	assert(prepared, problem or "Cannot prepare corn preview")
	local folder = Instance.new("Folder")
	folder.Name = "EditorPreview"
	folder:SetAttribute("CornEditorPreview", true)
	folder:SetAttribute("corn_project_id", "children_of_corn")
	local distance = math.clamp(radius or 55, 10, 85)
	local localCenter = field.CFrame:PointToObjectSpace(center)
	local minColumn, maxColumn, minRow, maxRow = Layout.GetCellBounds(field)
	minColumn = math.max(minColumn, math.ceil((localCenter.X - distance) / Layout.Spacing))
	maxColumn = math.min(maxColumn, math.floor((localCenter.X + distance) / Layout.Spacing))
	minRow = math.max(minRow, math.ceil((localCenter.Z - distance) / Layout.Spacing))
	maxRow = math.min(maxRow, math.floor((localCenter.Z + distance) / Layout.Spacing))
	local exclusions = Layout.ReadExclusions(map, field)
	local _, fieldYaw = field.CFrame:ToOrientation()
	local count = 0
	local ok, err = pcall(function()
		for row = minRow, maxRow do
			for column = minColumn, maxColumn do
				local position = Layout.CellPosition(field, column, row)
				local delta = position - center
				if
					Vector2.new(delta.X, delta.Z).Magnitude <= distance
					and not Layout.IsExcluded(position, exclusions)
				then
					local clone = prepared:Clone()
					assert(clone, "Corn clone is not Archivable")
					clone.Name = "Corn"
					clone:PivotTo(
						Layout.PivotForPlant(
							prepared,
							position,
							Layout.CellYaw(column, row) + fieldYaw
						)
					)
					clone.Parent = folder
					count += 1
				end
			end
		end
	end)
	prepared:Destroy()
	if not ok then
		folder:Destroy()
		error(tostring(err))
	end
	if old then
		old:Destroy()
	end
	folder.Parent = map
	folder:SetAttribute("PlantCount", count)
	return count
end

function MapAuthoring.PreviewAtSelection(): number
	guard()
	local map = Workspace:FindFirstChild("CornMap")
	assert(
		map and map:IsA("Model") and map:GetAttribute("corn_project_id") == "children_of_corn",
		"CornMap missing"
	)
	local spawn = map:FindFirstChild("RoundSpawn")
	assert(spawn and spawn:IsA("BasePart"), "RoundSpawn missing")
	local center = spawn.Position
	local selected = Selection:Get()[1]
	if selected and (selected:IsA("Model") or selected:IsA("BasePart")) then
		center = selected:GetPivot().Position
	end
	local count = MapAuthoring.Preview(map, center)
	print("CornMap editor preview:", count, "plants near selection")
	return count
end

function MapAuthoring.Install(): Model
	guard()
	assert(not Workspace:FindFirstChild("CornMap"), "CornMap already exists; manual edits retained")
	local testClone, problem = Layout.PrepareTemplate(artSource())
	assert(testClone, problem or "Corn art preparation failed")
	testClone:Destroy()
	local root = Instance.new("Model")
	root.Name = "CornMap"
	root:SetAttribute("corn_project_id", "children_of_corn")
	root:SetAttribute("map_version", 1)
	local ok, err = pcall(function()
		local ground = part(
			root,
			"Ground",
			Vector3.new(1200, 2, 1200),
			Vector3.new(0, 79, 0),
			Color3.fromRGB(91, 97, 70)
		)
		ground.Material = Enum.Material.Ground
		local field = zone(root, "FieldZone", Vector3.new(1200, 10, 1200), Vector3.new(0, 85, 0))
		CollectionService:AddTag(field, "corn_field_zone")
		local bounds = zone(root, "PlayBounds", Vector3.new(1200, 50, 1240), Vector3.new(0, 100, 0))
		CollectionService:AddTag(bounds, "corn_play_bounds")
		local zones = Instance.new("Folder")
		zones.Name = "NoCornZones"
		zones.Parent = root
		local props = Instance.new("Folder")
		props.Name = "Props"
		props.Parent = root
		local slots = Instance.new("Folder")
		slots.Name = "KeySlots"
		slots.Parent = root
		local boundaries = Instance.new("Folder")
		boundaries.Name = "Boundaries"
		boundaries.Parent = root
		local wall = Color3.fromRGB(51, 61, 52)
		part(boundaries, "West", Vector3.new(2, 20, 1204), Vector3.new(-601, 90, 0), wall)
		part(boundaries, "East", Vector3.new(2, 20, 1204), Vector3.new(601, 90, 0), wall)
		part(boundaries, "South", Vector3.new(1200, 20, 2), Vector3.new(0, 90, -601), wall)
		part(boundaries, "NorthLeft", Vector3.new(594, 20, 2), Vector3.new(-303, 90, 601), wall)
		part(boundaries, "NorthRight", Vector3.new(594, 20, 2), Vector3.new(303, 90, 601), wall)
		local spawn = part(
			root,
			"RoundSpawn",
			Vector3.new(6, 0.15, 6),
			Vector3.new(0, 80.075, -500),
			Color3.fromRGB(158, 176, 150)
		)
		spawn.CFrame *= CFrame.Angles(0, math.pi, 0)
		spawn.CanCollide = false
		spawn.CanTouch = false
		spawn.CanQuery = false
		spawn:SetAttribute("spawn_id", "solo_start")
		CollectionService:AddTag(spawn, "corn_spawn")
		noCorn(zones, "StartClearing", Vector3.new(20, 10, 20), Vector3.new(0, 85, -500))
		local allSlots: { Part } = {}
		for row = 1, 5 do
			for column = 1, 3 do
				local id = string.format("solo_slot_%02d", #allSlots + 1)
				local slot = part(
					slots,
					id,
					Vector3.new(6, 0.12, 6),
					Vector3.new((column - 2) * 360, 80.06, (row - 3) * 180),
					Color3.fromRGB(119, 123, 87)
				)
				slot.CanCollide = false
				slot.CanTouch = false
				slot.CanQuery = false
				slot:SetAttribute("slot_id", id)
				CollectionService:AddTag(slot, "corn_key_slot")
				table.insert(allSlots, slot)
			end
		end
		for _, index in { 3, 8, 13 } do
			local barrel = part(
				props,
				"LookoutBarrel",
				Vector3.new(4, 3.2, 3.2),
				allSlots[index].Position + Vector3.new(4, 1.94, 0),
				Color3.fromRGB(111, 78, 48)
			)
			barrel.CFrame *= CFrame.Angles(0, 0, math.pi / 2)
			barrel.Shape = Enum.PartType.Cylinder
			barrel.Material = Enum.Material.Wood
			CollectionService:AddTag(barrel, "corn_barrel")
		end
		house(props, "HouseWest", Vector3.new(-180, 80, -190))
		house(props, "HouseEast", Vector3.new(210, 80, 120))
		house(props, "HouseNorthWest", Vector3.new(-420, 80, 240))
		local scarecrow = Instance.new("Model")
		scarecrow.Name = "ScarecrowMarker"
		scarecrow:SetAttribute("role", "visual_scarecrow_placeholder")
		scarecrow.Parent = props
		part(
			scarecrow,
			"Pole",
			Vector3.new(0.8, 20, 0.8),
			Vector3.new(12, 90, 12),
			Color3.fromRGB(77, 60, 42)
		)
		part(
			scarecrow,
			"Body",
			Vector3.new(4, 8, 2),
			Vector3.new(12, 94, 12),
			Color3.fromRGB(35, 39, 30)
		)
		part(
			scarecrow,
			"Arms",
			Vector3.new(14, 1, 1),
			Vector3.new(12, 97, 12),
			Color3.fromRGB(35, 39, 30)
		)
		part(
			scarecrow,
			"Head",
			Vector3.new(2.5, 2.5, 2.5),
			Vector3.new(12, 99.5, 12),
			Color3.fromRGB(89, 83, 54)
		)
		local gate = Instance.new("Model")
		gate.Name = "EscapeGate"
		gate:SetAttribute("gate_id", "solo_gate")
		gate.Parent = root
		CollectionService:AddTag(gate, "corn_gate")
		part(
			gate,
			"Door",
			Vector3.new(12, 18, 2),
			Vector3.new(0, 89, 601),
			Color3.fromRGB(114, 75, 49)
		).CanTouch =
			false
		zone(gate, "InteractionAnchor", Vector3.new(0.1, 0.1, 0.1), Vector3.new(0, 83, 599.7))
		local exit = zone(gate, "ExitZone", Vector3.new(12, 22, 8), Vector3.new(0, 91, 610))
		exit:SetAttribute("gate_id", "solo_gate")
		CollectionService:AddTag(exit, "corn_exit")
		noCorn(gate, "ApproachClearance", Vector3.new(20, 10, 28), Vector3.new(0, 85, 600))
		part(gate, "Header", Vector3.new(12, 2, 2), Vector3.new(0, 99, 601), wall)
		local apron = part(
			gate,
			"ExitGround",
			Vector3.new(20, 2, 20),
			Vector3.new(0, 79, 610),
			Color3.fromRGB(91, 97, 70)
		)
		apron.Material = Enum.Material.Ground
		gate.PrimaryPart = gate.Door :: BasePart
		root.Parent = Workspace
		local count = MapAuthoring.Preview(root, spawn.Position)
		root:SetAttribute("EditorCornCount", count)
		Selection:Set({ spawn })
	end)
	if not ok then
		root:Destroy()
		error(tostring(err))
	end
	print(
		"CornMap installed: 1200 x 1200 studs, 15 key slots, gate, 3 barrels, 3 decorative houses"
	)
	return root
end
return MapAuthoring
]========] },
{ path = [========[ServerScriptService/GameServer/Services/NetworkService]========], class = [========[ModuleScript]========], source = [========[--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkService = {
	Name = "NetworkService",
	Order = 10,
}

local root: Folder

function NetworkService:Init(_context: any)
	local existing = ReplicatedStorage:FindFirstChild("GameRemotes")
	if existing and not existing:IsA("Folder") then
		error("ReplicatedStorage.GameRemotes exists but is not a Folder")
	end
	if existing then
		root = existing
	else
		root = Instance.new("Folder")
		root.Name = "GameRemotes"
		root.Parent = ReplicatedStorage
	end
end

function NetworkService:GetEvent(name: string): RemoteEvent
	local existing = root:FindFirstChild(name)
	if existing then
		assert(existing:IsA("RemoteEvent"), string.format("%s is not a RemoteEvent", name))
		return existing
	end
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = root
	return event
end

function NetworkService:GetFunction(name: string): RemoteFunction
	local existing = root:FindFirstChild(name)
	if existing then
		assert(existing:IsA("RemoteFunction"), string.format("%s is not a RemoteFunction", name))
		return existing
	end
	local fn = Instance.new("RemoteFunction")
	fn.Name = name
	fn.Parent = root
	return fn
end

return NetworkService
]========] },
{ path = [========[ServerScriptService/GameServer/Services/TagService]========], class = [========[ModuleScript]========], source = [========[--!strict

local CollectionService = game:GetService("CollectionService")

local TagService = {
	Name = "TagService",
	Order = 20,
}

local connections: { RBXScriptConnection } = {}

function TagService:Bind(tag: string, onAdded: (Instance) -> (), onRemoved: ((Instance) -> ())?)
	for _, instance in CollectionService:GetTagged(tag) do
		task.spawn(onAdded, instance)
	end

	table.insert(connections, CollectionService:GetInstanceAddedSignal(tag):Connect(onAdded))
	if onRemoved then
		table.insert(
			connections,
			CollectionService:GetInstanceRemovedSignal(tag):Connect(onRemoved)
		)
	end
end

function TagService:Destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

return TagService
]========] },
{ path = [========[ServerScriptService/GameServer/Services/RoundService]========], class = [========[ModuleScript]========], source = [========[--!strict

local RunService = game:GetService("RunService")
local SoloRound = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("SoloRound"))

local RoundService = { Name = "RoundService", Order = 30 }
local runtime: any = nil

function RoundService:Init(context: any)
	if
		not RunService:IsStudio()
		or context.Config.Environment ~= "DEV"
		or context.Config.Game.SessionMode ~= "solo_local"
	then
		context.Log:Warn("Temporary solo prototype is available only in Studio DEV mode")
		return
	end
	runtime = SoloRound.new(context)
end

function RoundService:Start()
	if runtime then
		runtime:Start()
	end
end

return RoundService
]========] }
}
local previousRepair = {
{ path = [========[StarterPlayer/StarterPlayerScripts/GameClient/Bootstrap]========], class = [========[LocalScript]========], source = [========[--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameShared = ReplicatedStorage:WaitForChild("GameShared")
local Config = require(GameShared:WaitForChild("Config"):WaitForChild("GameConfig"))
local Workspace = game:GetService("Workspace")
local map = Workspace:WaitForChild("CornMap", 10)
if
	not map
	or map:GetAttribute("corn_project_id") ~= "children_of_corn"
	or Workspace:FindFirstChild("Asmr_Base")
	or Workspace:FindFirstChild("ASMR_Models")
then
	warn("[ChildrenOfCorn] Inactive: editable CornMap missing or another game detected")
	return
end
local Logger = require(GameShared:WaitForChild("Core"):WaitForChild("Logger"))
local log = Logger.new("ClientBootstrap", Config.Debug)

local controllersFolder = script.Parent:WaitForChild("Controllers")

type RuntimeModule = {
	Name: string?,
	Order: number?,
	Init: ((self: RuntimeModule, context: any) -> ())?,
	Start: ((self: RuntimeModule, context: any) -> ())?,
}

local loaded: { RuntimeModule } = {}
local byName: { [string]: RuntimeModule } = {}

for _, child in controllersFolder:GetChildren() do
	if child:IsA("ModuleScript") then
		local ok, result = pcall(require, child)
		if not ok then
			error(
				string.format(
					"Failed to require controller %s: %s",
					child:GetFullName(),
					tostring(result)
				)
			)
		end
		if type(result) ~= "table" then
			error(string.format("Controller %s must return a table", child:GetFullName()))
		end
		local module = result :: RuntimeModule
		local name = module.Name or child.Name
		if byName[name] then
			error(string.format("Duplicate controller name: %s", name))
		end
		module.Name = name
		byName[name] = module
		table.insert(loaded, module)
	end
end

table.sort(loaded, function(a, b)
	return (a.Order or 100) < (b.Order or 100)
end)

local context = {
	Config = Config,
	Controllers = byName,
	Log = Logger.new("Client", Config.Debug),
}

for _, module in loaded do
	if module.Init then
		module:Init(context)
	end
end

for _, module in loaded do
	if module.Start then
		module:Start(context)
	end
end

log:Info(string.format("Started %d controllers", #loaded))
]========] },
{ path = [========[StarterPlayer/StarterPlayerScripts/GameClient/Controllers/RoundController]========], class = [========[ModuleScript]========], source = [========[--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameShared = ReplicatedStorage:WaitForChild("GameShared")
local EndpointNames = require(GameShared:WaitForChild("Network"):WaitForChild("EndpointNames"))
local RoundHud = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("RoundHud"))

type Snapshot = RoundHud.Snapshot

local RoundController = {
	Name = "RoundController",
	Order = 100,
	_snapshot = nil :: Snapshot?,
	_requestRemote = nil :: RemoteEvent?,
	_snapshotConnection = nil :: RBXScriptConnection?,
	_lastRequest = -math.huge,
	_hud = nil :: any,
}

local PHASES: { [string]: boolean } = {
	ready = true,
	preparing = true,
	active = true,
	escaped = true,
	aborted = true,
}
local ACTIONS: { [string]: boolean } = {
	start = true,
	retry = true,
	abort = true,
	menu = true,
}
local DEBOUNCE_SEC = 0.55
local REMOTE_WAIT_SEC = 10

local function nonnegativeNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value >= 0 and value < math.huge
end

local function validSnapshot(value: any): boolean
	return typeof(value) == "table"
		and typeof(value.phase) == "string"
		and PHASES[value.phase] == true
		and typeof(value.has_key) == "boolean"
		and typeof(value.gate_open) == "boolean"
		and nonnegativeNumber(value.session_diamonds)
		and nonnegativeNumber(value.reward_diamonds)
		and nonnegativeNumber(value.elapsed_sec)
		and typeof(value.notice) == "string"
end

local function getRemote(folder: Instance, name: string): RemoteEvent?
	local instance = folder:WaitForChild(name, REMOTE_WAIT_SEC)
	if not instance or not instance:IsA("RemoteEvent") then
		warn(
			string.format(
				"[RoundController] RemoteEvent %s is unavailable after %ds",
				name,
				REMOTE_WAIT_SEC
			)
		)
		return nil
	end
	return instance
end

function RoundController:Init(_context: any)
	self._snapshot = nil :: Snapshot?
	self._requestRemote = nil :: RemoteEvent?
	self._snapshotConnection = nil :: RBXScriptConnection?
	self._lastRequest = -math.huge
	self._hud = nil

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui", REMOTE_WAIT_SEC)
	if not playerGui or not playerGui:IsA("PlayerGui") then
		warn("[RoundController] PlayerGui is unavailable; the round interface was not created")
		return
	end
	self._hud = RoundHud.new(playerGui)
	self._hud:SetOnAction(function(action: string)
		self:_request(action)
	end)
end

function RoundController:_request(action: string)
	local remote = self._requestRemote
	local hud = self._hud
	if not remote or not hud or not self._snapshot or ACTIONS[action] ~= true then
		return
	end
	local now = os.clock()
	if now - self._lastRequest < DEBOUNCE_SEC then
		return
	end
	self._lastRequest = now
	hud:SetBusy(true)
	remote:FireServer(action)
	-- Only the server changes the view. A rejected request must not leave buttons stuck.
	task.delay(DEBOUNCE_SEC, function()
		if self._hud == hud then
			hud:SetBusy(false)
		end
	end)
end

function RoundController:Start(_context: any)
	local hud = self._hud
	if not hud then
		return
	end
	local folder = ReplicatedStorage:WaitForChild("GameRemotes", REMOTE_WAIT_SEC)
	if not folder or not folder:IsA("Folder") then
		warn("[RoundController] GameRemotes is unavailable; check RoundService startup in Output")
		hud:ShowUnavailable()
		return
	end
	local requestRemote = getRemote(folder, EndpointNames.RequestRoundAction)
	local snapshotRemote = getRemote(folder, EndpointNames.RoundSnapshot)
	if not requestRemote or not snapshotRemote then
		hud:ShowUnavailable()
		return
	end
	self._requestRemote = requestRemote
	self._snapshotConnection = snapshotRemote.OnClientEvent:Connect(function(payload: any)
		if not validSnapshot(payload) then
			warn("[RoundController] Ignored a malformed round_snapshot")
			return
		end
		self._snapshot = payload :: Snapshot
		hud:Render(payload :: Snapshot)
	end)

	-- Subscribe first: initial server messages may precede the client controller.
	requestRemote:FireServer("sync")
	task.delay(2, function()
		if self._hud == hud and self._snapshot == nil then
			requestRemote:FireServer("sync")
		end
	end)
	task.delay(REMOTE_WAIT_SEC, function()
		if self._hud == hud and self._snapshot == nil then
			warn("[RoundController] No valid initial round_snapshot; check RoundService Output")
			hud:ShowUnavailable()
		end
	end)
end

function RoundController:Destroy()
	if self._snapshotConnection then
		self._snapshotConnection:Disconnect()
		self._snapshotConnection = nil
	end
	if self._hud then
		self._hud:Destroy()
		self._hud = nil
	end
	self._requestRemote = nil
end

return RoundController
]========] },
{ path = [========[StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornController]========], class = [========[ModuleScript]========], source = [========[--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameShared = ReplicatedStorage:WaitForChild("GameShared")
local CornLayout = require(GameShared:WaitForChild("Game"):WaitForChild("CornLayout"))

type Chunk = {
	Key: string,
	Folder: Folder,
	MinColumn: number,
	MaxColumn: number,
	MinRow: number,
	MaxRow: number,
	Column: number,
	Row: number,
	Distance: number,
	Count: number,
	Alive: boolean,
	Done: boolean,
}

type OverviewItem = {
	Part: BasePart,
	PreviousModifier: number,
	Frame: CFrame,
	Size: Vector3,
	Keys: { string },
	Hidden: boolean,
}

local CornController = {
	Name = "CornController",
	Order = 50,
	_enabled = false,
	_connection = nil :: RBXScriptConnection?,
	_map = nil :: Model?,
	_field = nil :: BasePart?,
	_template = nil :: CornLayout.Plant?,
	_folder = nil :: Folder?,
	_chunks = {} :: { [string]: Chunk },
	_queue = {} :: { Chunk },
	_exclusions = nil :: CornLayout.Exclusions?,
	_pivotOffset = CFrame.identity,
	_height = CornLayout.Height,
	_pollElapsed = math.huge,
	_plantCount = 0,
	_lastWarning = "",
	_overviewFolder = nil :: Folder?,
	_overviewParts = {} :: { [BasePart]: OverviewItem },
	_overviewByChunk = {} :: { [string]: { OverviewItem } },
	_overviewDirty = {} :: { [OverviewItem]: boolean },
	_overviewFieldFrame = CFrame.identity,
	_overviewFieldSize = Vector3.zero,
}

local PROJECT_ID = "children_of_corn"
local POLL_SEC = 0.3
local CREATE_BUDGET = 18
local CELL_BUDGET = 100
local TIME_BUDGET_SEC = 0.003
local MAX_CHUNKS = 28

function CornController:_warn(message: string)
	if self._lastWarning ~= message then
		self._lastWarning = message
		warn("[CornController] " .. message)
	end
end

local function overviewKeys(field: BasePart, part: BasePart): { string }
	local relative = field.CFrame:ToObjectSpace(part.CFrame)
	local half = part.Size / 2
	-- Require completed fine groups across the entire rotated coarse footprint.
	-- The margin also covers the small deterministic cell stagger.
	local padding = CornLayout.Spacing * 0.75
	local halfX = math.abs(relative.RightVector.X) * half.X
		+ math.abs(relative.UpVector.X) * half.Y
		+ math.abs(relative.LookVector.X) * half.Z
		+ padding
	local halfZ = math.abs(relative.RightVector.Z) * half.X
		+ math.abs(relative.UpVector.Z) * half.Y
		+ math.abs(relative.LookVector.Z) * half.Z
		+ padding
	local fieldHalf = field.Size / 2
	local minX = math.max(relative.Position.X - halfX, -fieldHalf.X)
	local maxX = math.min(relative.Position.X + halfX, fieldHalf.X)
	local minZ = math.max(relative.Position.Z - halfZ, -fieldHalf.Z)
	local maxZ = math.min(relative.Position.Z + halfZ, fieldHalf.Z)
	local keys: { string } = {}
	if minX > maxX or minZ > maxZ then
		return keys
	end
	local width = CornLayout.Spacing * CornLayout.ChunkCells
	local offset = CornLayout.Spacing / 2
	for column = math.floor((minX + offset) / width), math.floor((maxX + offset) / width) do
		for row = math.floor((minZ + offset) / width), math.floor((maxZ + offset) / width) do
			table.insert(keys, column .. ":" .. row)
		end
	end
	return keys
end

function CornController:_showOverview()
	for _, entry in self._overviewParts do
		if entry.Hidden then
			if entry.Part.Parent then
				entry.Part.LocalTransparencyModifier = entry.PreviousModifier
			end
			entry.Hidden = false
		end
	end
	self._overviewDirty = {}
end

function CornController:_restoreOverview()
	self:_showOverview()
	self._overviewFolder = nil
	self._overviewParts = {}
	self._overviewByChunk = {}
end

function CornController:_markOverviewChunk(key: string)
	for _, entry in self._overviewByChunk[key] or {} do
		self._overviewDirty[entry] = true
	end
end

function CornController:_bindOverview()
	local map = self._map
	local field = self._field
	local folder = if map then map:FindFirstChild("EditorFieldOverview") else nil
	if not folder then
		self:_restoreOverview()
		return
	end
	if
		not field
		or not folder:IsA("Folder")
		or folder:GetAttribute("CornEditorOverview") ~= true
		or folder:GetAttribute("corn_project_id") ~= PROJECT_ID
	then
		self:_restoreOverview()
		self:_warn("Unrecognized EditorFieldOverview is preserved")
		return
	end
	local children = folder:GetChildren()
	local cachedCount = 0
	for _ in self._overviewParts do
		cachedCount += 1
	end
	local reusable = self._overviewFolder == folder
		and self._overviewFieldFrame == field.CFrame
		and self._overviewFieldSize == field.Size
		and cachedCount == #children
	-- Validate the whole container before any local visibility changes.
	for _, item in children do
		if
			not item:IsA("BasePart")
			or item:GetAttribute("CornEditorOverview") ~= true
			or item:GetAttribute("corn_project_id") ~= PROJECT_ID
		then
			self:_restoreOverview()
			self:_warn("EditorFieldOverview contains unowned objects; all were preserved")
			return
		end
		local previous = self._overviewParts[item]
		if not previous or previous.Frame ~= item.CFrame or previous.Size ~= item.Size then
			reusable = false
		end
	end
	if reusable then
		return
	end
	self:_restoreOverview()
	self._overviewFolder = folder
	self._overviewFieldFrame = field.CFrame
	self._overviewFieldSize = field.Size
	for _, item in children do
		local part = item :: BasePart
		local entry: OverviewItem = {
			Part = part,
			PreviousModifier = part.LocalTransparencyModifier,
			Frame = part.CFrame,
			Size = part.Size,
			Keys = overviewKeys(field, part),
			Hidden = false,
		}
		self._overviewParts[part] = entry
		for _, key in entry.Keys do
			local items = self._overviewByChunk[key]
			if not items then
				items = {}
				self._overviewByChunk[key] = items
			end
			table.insert(items, entry)
		end
	end
	for key, chunk in self._chunks do
		if chunk.Done then
			self:_markOverviewChunk(key)
		end
	end
end

function CornController:_updateOverview()
	local folder = self._overviewFolder
	if not folder then
		return
	end
	if
		folder:GetAttribute("CornEditorOverview") ~= true
		or folder:GetAttribute("corn_project_id") ~= PROJECT_ID
	then
		self:_restoreOverview()
		return
	end
	for entry in self._overviewDirty do
		local part = entry.Part
		if
			part.Parent ~= folder
			or part:GetAttribute("CornEditorOverview") ~= true
			or part:GetAttribute("corn_project_id") ~= PROJECT_ID
		then
			self:_restoreOverview()
			self:_warn("Overview ownership changed; its visibility was restored")
			return
		end
		local covered = #entry.Keys > 0
		for _, key in entry.Keys do
			local chunk = self._chunks[key]
			if not chunk or not chunk.Done then
				covered = false
				break
			end
		end
		if covered ~= entry.Hidden then
			part.LocalTransparencyModifier = if covered then 1 else entry.PreviousModifier
			entry.Hidden = covered
		end
	end
	self._overviewDirty = {}
end

function CornController:_clearChunks()
	self:_showOverview()
	for _, chunk in self._chunks do
		chunk.Alive = false
		chunk.Folder:Destroy()
	end
	self._chunks = {}
	self._queue = {}
	self._plantCount = 0
	if self._folder then
		self._folder:SetAttribute("LoadedPlants", 0)
	end
end

function CornController:_clearInputs()
	self:_clearChunks()
	self:_restoreOverview()
	if self._folder then
		self._folder:Destroy()
	end
	self._folder = nil
	self._map = nil
	self._field = nil
	self._template = nil
	self._exclusions = nil
end

function CornController:_resolveInputs(): boolean
	local map = Workspace:FindFirstChild("CornMap")
	local field = if map then map:FindFirstChild("FieldZone") else nil
	local art = ReplicatedStorage:FindFirstChild("CornRuntimeArt")
	local template = if art then art:FindFirstChild("CornPlantTemplate") else nil
	if not map or not map:IsA("Model") or map:GetAttribute("corn_project_id") ~= PROJECT_ID then
		self:_clearInputs()
		self:_warn("The owned CornMap is not available; editor preview is preserved")
		return false
	end
	if
		not field
		or not field:IsA("BasePart")
		or field.CFrame.UpVector:Dot(Vector3.yAxis) < 0.9999
	then
		self:_clearInputs()
		self:_warn("CornMap needs a horizontal FieldZone; editor preview is preserved")
		return false
	end
	if
		not art
		or not art:IsA("Folder")
		or art:GetAttribute("CornRuntimeArtOwned") ~= true
		or art:GetAttribute("corn_project_id") ~= PROJECT_ID
		or not template
		or (not template:IsA("Model") and not template:IsA("BasePart"))
		or template:GetAttribute("CornPlantTemplateOwned") ~= true
	then
		self:_clearInputs()
		self:_warn("Prepared corn art is not available; check CornField Output")
		return false
	end
	if
		self._map == map
		and self._field == field
		and self._template == template
		and self._folder
	then
		return true
	end
	self:_clearInputs()
	local existing = map:FindFirstChild("CornClientPlants")
	if existing then
		if
			not existing:IsA("Folder")
			or existing:GetAttribute("CornClientRendererOwned") ~= true
			or existing:GetAttribute("corn_project_id") ~= PROJECT_ID
		then
			self:_warn("Refused to replace unowned CornMap/CornClientPlants")
			return false
		end
		existing:Destroy()
	end
	local bounds, size = CornLayout.Bounds(template)
	self._pivotOffset = template:GetPivot():ToObjectSpace(bounds):Inverse()
	self._height = size.Y
	self._map = map
	self._field = field
	self._template = template
	local folder = Instance.new("Folder")
	folder.Name = "CornClientPlants"
	folder:SetAttribute("CornClientRendererOwned", true)
	folder:SetAttribute("corn_project_id", PROJECT_ID)
	folder:SetAttribute("LoadedPlants", 0)
	folder.Parent = map
	self._folder = folder
	-- This client-only deletion never changes the author's saved scene or Props.
	local preview = map:FindFirstChild("EditorPreview")
	if
		preview
		and preview:IsA("Folder")
		and preview:GetAttribute("CornEditorPreview") == true
		and preview:GetAttribute("corn_project_id") == PROJECT_ID
	then
		preview:Destroy()
	end
	self._lastWarning = ""
	return true
end

function CornController:_reconcile(root: BasePart)
	if not self:_resolveInputs() then
		return
	end
	local map = self._map :: Model
	local field = self._field :: BasePart
	local folder = self._folder :: Folder
	self:_bindOverview()
	local exclusions = CornLayout.ReadExclusions(map, field)
	if self._exclusions and self._exclusions.Signature ~= exclusions.Signature then
		self:_clearChunks()
	end
	self._exclusions = exclusions
	local minColumn, maxColumn, minRow, maxRow = CornLayout.GetCellBounds(field)
	local localRoot = field.CFrame:PointToObjectSpace(root.Position)
	local width = CornLayout.Spacing * CornLayout.ChunkCells
	local radius = CornLayout.RenderRadius
	local desired: { any } = {}
	for chunkColumn = math.floor((localRoot.X - radius) / width), math.floor((localRoot.X + radius) / width) do
		for chunkRow = math.floor((localRoot.Z - radius) / width), math.floor((localRoot.Z + radius) / width) do
			local firstColumn = math.max(minColumn, chunkColumn * CornLayout.ChunkCells)
			local lastColumn = math.min(maxColumn, (chunkColumn + 1) * CornLayout.ChunkCells - 1)
			local firstRow = math.max(minRow, chunkRow * CornLayout.ChunkCells)
			local lastRow = math.min(maxRow, (chunkRow + 1) * CornLayout.ChunkCells - 1)
			if firstColumn > lastColumn or firstRow > lastRow then
				continue
			end
			local centerX = (firstColumn + lastColumn) * CornLayout.Spacing / 2
			local centerZ = (firstRow + lastRow) * CornLayout.Spacing / 2
			local distance = (centerX - localRoot.X) ^ 2 + (centerZ - localRoot.Z) ^ 2
			if distance <= radius * radius then
				table.insert(desired, {
					Key = chunkColumn .. ":" .. chunkRow,
					MinColumn = firstColumn,
					MaxColumn = lastColumn,
					MinRow = firstRow,
					MaxRow = lastRow,
					Distance = distance,
				})
			end
		end
	end
	table.sort(desired, function(a, b)
		return if a.Distance == b.Distance then a.Key < b.Key else a.Distance < b.Distance
	end)
	local wanted: { [string]: boolean } = {}
	for index, candidate in desired do
		if index > MAX_CHUNKS then
			break
		end
		wanted[candidate.Key] = true
		local chunk = self._chunks[candidate.Key]
		if chunk then
			chunk.Distance = candidate.Distance
		else
			local chunkFolder = Instance.new("Folder")
			chunkFolder.Name = "Chunk_" .. candidate.Key
			chunkFolder.Parent = folder
			chunk = {
				Key = candidate.Key,
				Folder = chunkFolder,
				MinColumn = candidate.MinColumn,
				MaxColumn = candidate.MaxColumn,
				MinRow = candidate.MinRow,
				MaxRow = candidate.MaxRow,
				Column = candidate.MinColumn,
				Row = candidate.MinRow,
				Distance = candidate.Distance,
				Count = 0,
				Alive = true,
				Done = false,
			}
			self._chunks[candidate.Key] = chunk
		end
	end
	for key, chunk in self._chunks do
		if not wanted[key] then
			self:_markOverviewChunk(key)
			chunk.Alive = false
			self._plantCount -= chunk.Count
			chunk.Folder:Destroy()
			self._chunks[key] = nil
		end
	end
	self._queue = {}
	for _, chunk in self._chunks do
		if not chunk.Done then
			table.insert(self._queue, chunk)
		end
	end
	table.sort(self._queue, function(a, b)
		return if a.Distance == b.Distance then a.Key < b.Key else a.Distance < b.Distance
	end)
	self:_updateOverview()
end

function CornController:_createBatch()
	local template = self._template
	local field = self._field
	local exclusions = self._exclusions
	if not template or not field or not exclusions then
		return
	end
	local began = os.clock()
	local _, fieldYaw = field.CFrame:ToOrientation()
	local examined = 0
	local created = 0
	while
		#self._queue > 0
		and examined < CELL_BUDGET
		and created < CREATE_BUDGET
		and os.clock() - began < TIME_BUDGET_SEC
	do
		local chunk = self._queue[1]
		if not chunk.Alive or chunk.Done then
			table.remove(self._queue, 1)
			continue
		end
		local column = chunk.Column
		local row = chunk.Row
		chunk.Column += 1
		if chunk.Column > chunk.MaxColumn then
			chunk.Column = chunk.MinColumn
			chunk.Row += 1
		end
		if chunk.Row > chunk.MaxRow then
			chunk.Done = true
			self:_markOverviewChunk(chunk.Key)
			table.remove(self._queue, 1)
		end
		examined += 1
		local position = CornLayout.CellPosition(field, column, row)
		if CornLayout.IsExcluded(position, exclusions) then
			continue
		end
		local clone = template:Clone()
		if not clone then
			self:_warn("Prepared corn template is not Archivable")
			self:Destroy()
			return
		end
		local plant = clone :: CornLayout.Plant
		plant.Name = "Corn"
		plant:PivotTo(
			CFrame.new(position + Vector3.new(0, self._height / 2, 0))
				* CFrame.Angles(0, CornLayout.CellYaw(column, row) + fieldYaw, 0)
				* self._pivotOffset
		)
		plant.Parent = chunk.Folder
		chunk.Count += 1
		self._plantCount += 1
		created += 1
	end
	if self._folder then
		self._folder:SetAttribute("LoadedPlants", self._plantCount)
	end
	self:_updateOverview()
end

function CornController:_step(delta: number)
	self._pollElapsed += delta
	if self._pollElapsed >= POLL_SEC then
		self._pollElapsed = 0
		local character = Players.LocalPlayer.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if root and root:IsA("BasePart") then
			self:_reconcile(root)
		else
			self:_clearChunks()
		end
	end
	self:_createBatch()
end

function CornController:Init(context: any)
	self._enabled = RunService:IsStudio()
		and context.Config.Environment == "DEV"
		and context.Config.Game.SessionMode == "solo_local"
end

function CornController:Start()
	if not self._enabled or self._connection then
		return
	end
	self._connection = RunService.Heartbeat:Connect(function(delta: number)
		self:_step(delta)
	end)
end

function CornController:Destroy()
	self._enabled = false
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	self:_clearInputs()
end

return CornController
]========] },
{ path = [========[StarterPlayer/StarterPlayerScripts/GameClient/Game/RoundHud]========], class = [========[ModuleScript]========], source = [========[--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RoundText: { [string]: string } = require(
	ReplicatedStorage:WaitForChild("GameShared"):WaitForChild("Game"):WaitForChild("RoundText")
)

export type Snapshot = {
	phase: string,
	has_key: boolean,
	gate_open: boolean,
	session_diamonds: number,
	reward_diamonds: number,
	elapsed_sec: number,
	notice: string,
}

local RoundHud = {}
RoundHud.__index = RoundHud

local PANEL_COLOR = Color3.fromRGB(27, 32, 28)
local TEXT_COLOR = Color3.fromRGB(239, 242, 233)
local MUTED_COLOR = Color3.fromRGB(190, 199, 186)
local BUTTON_COLOR = Color3.fromRGB(84, 109, 67)
local DISABLED_COLOR = Color3.fromRGB(63, 69, 61)

local function text(key: string, values: { [string]: string | number }?): string
	local template = RoundText[key] or ""
	return (
		string.gsub(template, "{([%w_]+)}", function(name)
			local value = if values then values[name] else nil
			return if value ~= nil then tostring(value) else "{" .. name .. "}"
		end)
	)
end

local function elapsedText(seconds: number): string
	local whole = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", math.floor(whole / 60), whole % 60)
end

local function label(
	parent: Instance,
	name: string,
	size: UDim2,
	position: UDim2,
	fontSize: number
): TextLabel
	local result = Instance.new("TextLabel")
	result.Name = name
	result.Size = size
	result.Position = position
	result.BackgroundTransparency = 1
	result.Font = Enum.Font.Gotham
	result.TextSize = fontSize
	result.TextColor3 = TEXT_COLOR
	result.TextWrapped = true
	result.TextXAlignment = Enum.TextXAlignment.Left
	result.TextYAlignment = Enum.TextYAlignment.Center
	result.Text = ""
	result.Parent = parent
	return result
end

local function button(
	parent: Instance,
	name: string,
	key: string,
	size: UDim2,
	position: UDim2
): TextButton
	local result = Instance.new("TextButton")
	result.Name = name
	result.Size = size
	result.Position = position
	result.BackgroundColor3 = BUTTON_COLOR
	result.BorderSizePixel = 0
	result.Font = Enum.Font.GothamMedium
	result.TextSize = 17
	result.TextColor3 = TEXT_COLOR
	result.Text = text(key)
	result.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = result
	return result
end

local function panel(parent: Instance, name: string, size: UDim2, position: UDim2): Frame
	local result = Instance.new("Frame")
	result.Name = name
	result.Size = size
	result.Position = position
	result.BackgroundColor3 = PANEL_COLOR
	result.BackgroundTransparency = 0.08
	result.BorderSizePixel = 0
	result.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = result
	return result
end

function RoundHud.new(playerGui: PlayerGui)
	local root = Instance.new("ScreenGui")
	root.Name = "CornRoundHud"
	root.ResetOnSpawn = false
	root.DisplayOrder = 10
	root.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	root.Parent = playerGui

	local card = panel(root, "RoundCard", UDim2.fromOffset(460, 320), UDim2.fromScale(0.5, 0.5))
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	local title = label(card, "Title", UDim2.new(1, -48, 0, 38), UDim2.fromOffset(24, 20), 27)
	title.Font = Enum.Font.GothamBold
	local message = label(card, "Message", UDim2.new(1, -48, 0, 52), UDim2.fromOffset(24, 68), 19)
	local resultTime =
		label(card, "Elapsed", UDim2.new(1, -48, 0, 26), UDim2.fromOffset(24, 124), 16)
	resultTime.TextColor3 = MUTED_COLOR
	local balance = label(card, "Balance", UDim2.new(1, -48, 0, 26), UDim2.fromOffset(24, 154), 16)
	balance.TextColor3 = MUTED_COLOR
	local notice = label(card, "Notice", UDim2.new(1, -48, 0, 46), UDim2.fromOffset(24, 186), 16)
	notice.TextColor3 = Color3.fromRGB(233, 209, 142)
	local start = button(
		card,
		"Start",
		"corn_loop_start",
		UDim2.new(1, -48, 0, 44),
		UDim2.fromOffset(24, 250)
	)
	local retry = button(
		card,
		"Retry",
		"corn_loop_retry",
		UDim2.new(0.5, -30, 0, 44),
		UDim2.fromOffset(24, 250)
	)
	local menu = button(
		card,
		"Menu",
		"corn_loop_menu",
		UDim2.new(0.5, -30, 0, 44),
		UDim2.new(0.5, 6, 0, 250)
	)
	local preparingLeave = button(
		card,
		"Leave",
		"corn_loop_leave",
		UDim2.new(1, -48, 0, 44),
		UDim2.fromOffset(24, 250)
	)

	local active = panel(root, "ActiveStatus", UDim2.new(0.64, 0, 0, 128), UDim2.fromOffset(20, 16))
	local activeConstraint = Instance.new("UISizeConstraint")
	activeConstraint.MaxSize = Vector2.new(690, 128)
	activeConstraint.Parent = active
	local objective =
		label(active, "Objective", UDim2.new(1, -32, 0, 32), UDim2.fromOffset(16, 8), 19)
	objective.Font = Enum.Font.GothamMedium
	local activeTime =
		label(active, "Elapsed", UDim2.new(1, -32, 0, 24), UDim2.fromOffset(16, 42), 15)
	activeTime.TextColor3 = MUTED_COLOR
	local activeBalance =
		label(active, "Balance", UDim2.new(1, -32, 0, 24), UDim2.fromOffset(16, 66), 15)
	activeBalance.TextColor3 = MUTED_COLOR
	local activeNotice =
		label(active, "Notice", UDim2.new(1, -32, 0, 24), UDim2.fromOffset(16, 94), 16)
	activeNotice.TextColor3 = notice.TextColor3
	local activeLeave = button(
		root,
		"LeaveRound",
		"corn_loop_leave",
		UDim2.fromOffset(185, 40),
		UDim2.new(1, -205, 0, 16)
	)

	local self = setmetatable({
		_root = root,
		_card = card,
		_title = title,
		_message = message,
		_time = resultTime,
		_balance = balance,
		_notice = notice,
		_active = active,
		_objective = objective,
		_activeTime = activeTime,
		_activeBalance = activeBalance,
		_activeNotice = activeNotice,
		_start = start,
		_retry = retry,
		_menu = menu,
		_preparingLeave = preparingLeave,
		_activeLeave = activeLeave,
		_buttons = { start, retry, menu, preparingLeave, activeLeave },
		_connections = {} :: { RBXScriptConnection },
		_snapshot = nil :: Snapshot?,
		_busy = false,
		_unavailable = false,
	}, RoundHud)
	self:_render()
	return self
end

function RoundHud:SetOnAction(callback: (string) -> ())
	local bindings = {
		{ button = self._start, action = "start" },
		{ button = self._retry, action = "retry" },
		{ button = self._menu, action = "menu" },
		{ button = self._preparingLeave, action = "abort" },
		{ button = self._activeLeave, action = "abort" },
	}
	for _, binding in bindings do
		table.insert(
			self._connections,
			binding.button.Activated:Connect(function()
				if not self._busy and not self._unavailable and self._snapshot ~= nil then
					callback(binding.action)
				end
			end)
		)
	end
end

function RoundHud:_render()
	local snapshot = self._snapshot
	local phase = if snapshot then snapshot.phase else "loading"
	local isActive = phase == "active"
	local isResult = phase == "escaped" or phase == "aborted"
	self._card.Visible = not isActive
	self._active.Visible = isActive
	self._activeLeave.Visible = isActive
	self._start.Visible = phase == "ready" or phase == "loading"
	self._retry.Visible = isResult
	self._menu.Visible = isResult
	self._preparingLeave.Visible = phase == "preparing"
	for _, control in self._buttons do
		local enabled = snapshot ~= nil and not self._busy and not self._unavailable
		control.Active = enabled
		control.AutoButtonColor = enabled
		control.BackgroundColor3 = if enabled then BUTTON_COLOR else DISABLED_COLOR
		control.TextTransparency = if enabled then 0 else 0.35
	end

	self._title.Text = text("corn_loop_title")
	self._time.Text = ""
	self._notice.Text = if snapshot then text(snapshot.notice) else ""
	self._balance.Visible = snapshot ~= nil
	self._balance.Text = text(
		"corn_loop_test_balance",
		{ count = if snapshot then snapshot.session_diamonds else 0 }
	)
	if self._unavailable then
		self._message.Text = text("corn_loop_connection_error")
	elseif phase == "loading" or phase == "preparing" then
		self._message.Text = text("corn_loop_loading")
	elseif phase == "ready" then
		self._message.Text = text("corn_loop_objective_search")
	elseif snapshot and isResult then
		self._title.Text = text(
			if phase == "escaped" then "corn_loop_result_escape" else "corn_loop_result_aborted"
		)
		self._message.Text = if phase == "escaped"
			then text("corn_loop_reward", { count = snapshot.reward_diamonds })
			else ""
		self._time.Text = text("corn_loop_round_time", { time = elapsedText(snapshot.elapsed_sec) })
	end

	if snapshot and isActive then
		local objectiveKey = if snapshot.gate_open
			then "corn_loop_objective_exit"
			elseif snapshot.has_key then "corn_loop_objective_return"
			else "corn_loop_objective_search"
		self._objective.Text = text(objectiveKey)
		self._activeTime.Text =
			text("corn_loop_round_time", { time = elapsedText(snapshot.elapsed_sec) })
		self._activeBalance.Text = self._balance.Text
		self._activeNotice.Text = text(snapshot.notice)
	end
end

function RoundHud:Render(snapshot: Snapshot)
	self._unavailable = false
	self._snapshot = snapshot
	self:_render()
end

function RoundHud:SetBusy(busy: boolean)
	self._busy = busy
	self:_render()
end

function RoundHud:ShowUnavailable()
	self._unavailable = true
	self:_render()
end

function RoundHud:Destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	self._root:Destroy()
end

return RoundHud
]========] },
{ path = [========[ReplicatedStorage/GameShared/Config/GameConfig]========], class = [========[ModuleScript]========], source = [========[--!strict

local Balance = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("Balance"))

return {
	Environment = "DEV",
	Debug = true,
	Game = {
		Id = "children_of_corn",
		Name = "Дети кукурузы",
		Version = "0.1.0",
		SessionMode = "solo_local",
		SupportedDevice = "pc",
	},
	CoreLoop = Balance,
	Persistence = {
		Enabled = false,
		StoreName = "PlayerData_v1",
		SchemaVersion = 1,
	},
}
]========] },
{ path = [========[ReplicatedStorage/GameShared/Core/Logger]========], class = [========[ModuleScript]========], source = [========[--!strict

local Logger = {}
Logger.__index = Logger

function Logger.new(scope: string, debugEnabled: boolean?)
	return setmetatable({
		_scope = scope,
		_debug = debugEnabled == true,
	}, Logger)
end

function Logger:Info(...: any)
	print(string.format("[%s]", self._scope), ...)
end

function Logger:Warn(...: any)
	warn(string.format("[%s]", self._scope), ...)
end

function Logger:Debug(...: any)
	if self._debug then
		print(string.format("[%s][DEBUG]", self._scope), ...)
	end
end

return Logger
]========] },
{ path = [========[ReplicatedStorage/GameShared/Game/Balance]========], class = [========[ModuleScript]========], source = [========[--!strict

-- Baseline from docs/2026-10-09_core-loop_gd-spec.md, sections 11-12.
-- Field size is confirmed at 1200 x 1200; corn visibility still needs a Studio playtest.
return {
	target_round_min_sec = 420,
	target_round_max_sec = 600,
	hunt_start_delay_sec = 15,
	key_slot_count = 15,
	barrel_count = 3,
	max_catches = 2,
	stamina_capacity = 100,
	sprint_duration_sec = 4,
	stamina_refill_sec = 6,
	walk_speed = 12,
	sprint_speed = 18,
	monster_patrol_speed = 10,
	monster_chase_speed = 14,
	monster_detect_radius = 32,
	monster_lose_radius = 44,
	monster_lose_delay_sec = 1.5,
	monster_growl_radius = 72,
	monster_capture_radius = 3,
	capture_transition_sec = 1,
	respawn_protection_sec = 5,
	key_drop_adjust_radius = 6,
	interaction_radius = 4,
	escape_reward_diamonds = 10,
}
]========] },
{ path = [========[ReplicatedStorage/GameShared/Game/RoundText]========], class = [========[ModuleScript]========], source = [========[--!strict

-- Keep player-facing strings in the GD namespace; this slice has no hunt/stamina UI.
return table.freeze({
	corn_loop_title = "Дети кукурузы",
	corn_loop_start = "Начать",
	corn_loop_loading = "Подготовка раунда…",
	corn_loop_objective_search = "Найди ключ от ворот и сбеги",
	corn_loop_objective_return = "Ключ найден. Вернись к воротам",
	corn_loop_objective_exit = "Ворота открыты — беги наружу",
	corn_loop_need_key = "Нужен ключ",
	corn_loop_result_escape = "Ты сбежал",
	corn_loop_result_aborted = "Раунд завершён",
	corn_loop_reward = "+{count} алмазов",
	corn_loop_test_balance = "Алмазы в этом тесте: {count}",
	corn_loop_round_time = "Время раунда: {time}",
	corn_loop_retry = "Ещё раз",
	corn_loop_menu = "В меню",
	corn_loop_leave = "Завершить раунд",
	corn_loop_setup_error = "Не удалось подготовить раунд. Попробуй снова",
	corn_loop_connection_error = "Не удалось подключить интерфейс. Перезапусти тест Studio",
})
]========] },
{ path = [========[ReplicatedStorage/GameShared/Game/CornLayout]========], class = [========[ModuleScript]========], source = [========[--!strict

local CornLayout = {
	Height = 8,
	Spacing = 3,
	Seed = 817,
	ChunkCells = 12,
	RenderRadius = 85,
}

export type Plant = Model | BasePart
export type Box = { Frame: CFrame, HalfSize: Vector2 }
export type Circle = { Center: Vector3, Radius: number }
export type Exclusions = { Boxes: { Box }, Circles: { Circle }, Signature: string }

local SLOT_RADIUS = 6
local BOX_PADDING = 1.5

local function finite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

function CornLayout.Bounds(plant: Plant): (CFrame, Vector3)
	if plant:IsA("Model") then
		return plant:GetBoundingBox()
	end
	return plant.CFrame, plant.Size
end

function CornLayout.PrepareTemplate(source: Instance, height: number?): (Plant?, string?)
	if not source:IsA("Model") and not source:IsA("BasePart") then
		return nil, "Corn source must be a Model or BasePart"
	end
	local targetHeight = height or CornLayout.Height
	if not finite(targetHeight) or targetHeight <= 0 then
		return nil, "Corn height must be positive and finite"
	end
	local items = source:GetDescendants()
	table.insert(items, source)
	local partCount = 0
	for _, item in items do
		if item:IsA("LuaSourceContainer") then
			return nil, "Corn source contains code"
		end
		if
			item:IsA("Sound")
			or item:IsA("ParticleEmitter")
			or item:IsA("Beam")
			or item:IsA("Trail")
			or item:IsA("ProximityPrompt")
			or item:IsA("ClickDetector")
			or item:IsA("RemoteEvent")
			or item:IsA("RemoteFunction")
		then
			return nil, "Corn source must contain only static art"
		end
		if not item.Archivable then
			return nil, "Corn source has non-Archivable contents"
		end
		if item:IsA("BasePart") then
			partCount += 1
		end
	end
	if partCount == 0 then
		return nil, "Corn source has no BaseParts"
	end

	local prepared = source:Clone() :: Plant?
	if not prepared then
		return nil, "Corn source could not be cloned"
	end
	local ok, problem = pcall(function()
		local _, size = CornLayout.Bounds(prepared :: Plant)
		if not finite(size.Y) or size.Y <= 0 then
			error("Corn source has no usable height")
		end
		local ratio = targetHeight / size.Y
		if prepared:IsA("Model") then
			prepared:ScaleTo(prepared:GetScale() * ratio)
		else
			prepared.Size *= ratio
			for _, item in prepared:GetChildren() do
				if item:IsA("SpecialMesh") then
					item.Scale *= ratio
				end
			end
		end
		-- The imported plant has one mesh plus import poses/animation metadata.
		-- Keep only that normalized mesh on decorative copies; the source is untouched.
		if prepared:IsA("Model") and partCount == 1 then
			local mesh = prepared:FindFirstChildWhichIsA("MeshPart", true)
			if mesh and mesh:IsA("MeshPart") then
				mesh.Parent = nil
				prepared:Destroy()
				prepared = mesh
			end
		end
		for _, item in prepared:GetDescendants() do
			if
				item:IsA("AnimationController")
				or (item:IsA("Folder") and item.Name == "InitialPoses")
			then
				item:Destroy()
			end
		end
		local clones = prepared:GetDescendants()
		table.insert(clones, prepared)
		for _, item in clones do
			-- Art tags must not become gameplay bindings on every decorative clone.
			for _, tag in item:GetTags() do
				item:RemoveTag(tag)
			end
			if item:IsA("BasePart") then
				item.Anchored = true
				item.CanCollide = false
				item.CanTouch = false
				item.CanQuery = false
				item.CastShadow = false
				if item:IsA("MeshPart") then
					item.DoubleSided = true
				end
			end
		end
		prepared:PivotTo(CornLayout.PivotForPlant(prepared, Vector3.zero, 0))
	end)
	if not ok then
		prepared:Destroy()
		return nil, tostring(problem)
	end
	return prepared, nil
end

function CornLayout.PivotForPlant(plant: Plant, groundPosition: Vector3, yaw: number): CFrame
	local bounds, size = CornLayout.Bounds(plant)
	local boundsFromPivot = plant:GetPivot():ToObjectSpace(bounds)
	return CFrame.new(groundPosition + Vector3.new(0, size.Y / 2, 0))
		* CFrame.Angles(0, yaw, 0)
		* boundsFromPivot:Inverse()
end

function CornLayout.GetCellBounds(field: BasePart): (number, number, number, number)
	local half = field.Size / 2
	return math.ceil(-half.X / CornLayout.Spacing),
		math.floor(half.X / CornLayout.Spacing),
		math.ceil(-half.Z / CornLayout.Spacing),
		math.floor(half.Z / CornLayout.Spacing)
end

function CornLayout.CellPosition(field: BasePart, column: number, row: number): Vector3
	local half = field.Size / 2
	local hashX = (column * 92837111 + row * 689287499 + CornLayout.Seed) % 104729
	local hashZ = (column * 19349663 + row * 83492791 + CornLayout.Seed) % 104729
	local stagger = if row % 2 == 0 then -CornLayout.Spacing * 0.15 else CornLayout.Spacing * 0.15
	local x = column * CornLayout.Spacing
		+ stagger
		+ (hashX / 104729 - 0.5) * CornLayout.Spacing * 0.12
	local z = row * CornLayout.Spacing + (hashZ / 104729 - 0.5) * CornLayout.Spacing * 0.12
	return field.CFrame:PointToWorldSpace(
		Vector3.new(math.clamp(x, -half.X, half.X), -half.Y, math.clamp(z, -half.Z, half.Z))
	)
end

function CornLayout.CellYaw(column: number, row: number): number
	local hash = (column * 73856093 + row * 19349663 + CornLayout.Seed * 83492791) % 104729
	return hash / 104729 * math.pi * 2
end

local function footprint(frame: CFrame, size: Vector3, padding: number): Box
	local look = frame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local flat = CFrame.new(frame.Position) * CFrame.Angles(0, yaw, 0)
	local half = size / 2
	local right = flat.RightVector
	local forward = flat.LookVector
	local width = math.abs(right:Dot(frame.RightVector)) * half.X
		+ math.abs(right:Dot(frame.UpVector)) * half.Y
		+ math.abs(right:Dot(frame.LookVector)) * half.Z
	local depth = math.abs(forward:Dot(frame.RightVector)) * half.X
		+ math.abs(forward:Dot(frame.UpVector)) * half.Y
		+ math.abs(forward:Dot(frame.LookVector)) * half.Z
	return { Frame = flat, HalfSize = Vector2.new(width + padding, depth + padding) }
end

local function authorDescendants(map: Model): { Instance }
	local result: { Instance } = {}
	local stack = map:GetChildren()
	while #stack > 0 do
		local item = table.remove(stack)
		local owned = item:GetAttribute("corn_project_id") == "children_of_corn"
		local decoration = owned
			and (
				(item.Name == "EditorPreview" and item:GetAttribute("CornEditorPreview") == true)
				or (item.Name == "EditorFieldOverview" and item:GetAttribute("CornEditorOverview") == true)
				or (item.Name == "CornClientPlants" and item:GetAttribute("CornClientRendererOwned") == true)
				or item.Name == "CornRoundRuntime"
			)
		if decoration then
			continue
		end
		table.insert(result, item)
		for _, child in item:GetChildren() do
			table.insert(stack, child)
		end
	end
	return result
end
function CornLayout.ReadExclusions(map: Model, field: BasePart): Exclusions
	local boxes: { Box } = {}
	local circles: { Circle } = {}
	local signatures: { string } = { tostring(field.CFrame) .. "/" .. tostring(field.Size) }
	local included: { [Instance]: boolean } = {}
	local function addBox(part: BasePart, padding: number)
		if included[part] then
			return
		end
		included[part] = true
		table.insert(boxes, footprint(part.CFrame, part.Size, padding))
		table.insert(
			signatures,
			part:GetFullName()
				.. "/box/"
				.. tostring(part.CFrame)
				.. "/"
				.. tostring(part.Size)
				.. "/"
				.. padding
		)
	end
	for _, folderName in { "NoCornZones", "Props" } do
		local folder = map:FindFirstChild(folderName)
		if folder then
			for _, item in folder:GetDescendants() do
				if item:IsA("BasePart") then
					addBox(item, BOX_PADDING)
				end
			end
		end
	end
	for _, item in authorDescendants(map) do
		if item:IsA("BasePart") then
			if item:HasTag("corn_no_corn_zone") then
				addBox(item, BOX_PADDING)
			end
			if item:HasTag("corn_key_slot") then
				table.insert(circles, { Center = item.Position, Radius = SLOT_RADIUS })
				table.insert(signatures, item:GetFullName() .. "/slot/" .. tostring(item.Position))
			elseif item:HasTag("corn_spawn") then
				addBox(item, 4)
				table.insert(circles, { Center = item.Position, Radius = 10 })
				table.insert(signatures, item:GetFullName() .. "/spawn/" .. tostring(item.Position))
			end
		end
	end
	local gate = map:FindFirstChild("EscapeGate")
	if gate then
		local door = gate:FindFirstChild("Door", true)
		if door and door:IsA("BasePart") then
			addBox(door, 6)
		end
	end
	table.sort(signatures)
	return { Boxes = boxes, Circles = circles, Signature = table.concat(signatures, "|") }
end

function CornLayout.IsExcluded(position: Vector3, exclusions: Exclusions): boolean
	for _, circle in exclusions.Circles do
		local delta = position - circle.Center
		if delta.X * delta.X + delta.Z * delta.Z <= circle.Radius * circle.Radius then
			return true
		end
	end
	for _, box in exclusions.Boxes do
		local localPosition = box.Frame:PointToObjectSpace(position)
		if
			math.abs(localPosition.X) <= box.HalfSize.X
			and math.abs(localPosition.Z) <= box.HalfSize.Y
		then
			return true
		end
	end
	return false
end

return CornLayout
]========] },
{ path = [========[ReplicatedStorage/GameShared/Network/EndpointNames]========], class = [========[ModuleScript]========], source = [========[--!strict

return {
	RequestRoundAction = "request_round_action",
	RoundSnapshot = "round_snapshot",
}
]========] },
{ path = [========[ServerScriptService/GameServer/Bootstrap]========], class = [========[Script]========], source = [========[--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameShared = ReplicatedStorage:WaitForChild("GameShared")
local Config = require(GameShared:WaitForChild("Config"):WaitForChild("GameConfig"))
local Workspace = game:GetService("Workspace")
local map = Workspace:WaitForChild("CornMap", 10)
if
	not map
	or map:GetAttribute("corn_project_id") ~= "children_of_corn"
	or Workspace:FindFirstChild("Asmr_Base")
	or Workspace:FindFirstChild("ASMR_Models")
then
	warn("[ChildrenOfCorn] Inactive: editable CornMap missing or another game detected")
	return
end
local Logger = require(GameShared:WaitForChild("Core"):WaitForChild("Logger"))
local log = Logger.new("ServerBootstrap", Config.Debug)

local servicesFolder = script.Parent:WaitForChild("Services")

type RuntimeModule = {
	Name: string?,
	Order: number?,
	Init: ((self: RuntimeModule, context: any) -> ())?,
	Start: ((self: RuntimeModule, context: any) -> ())?,
}

local loaded: { RuntimeModule } = {}
local byName: { [string]: RuntimeModule } = {}

for _, child in servicesFolder:GetChildren() do
	if child:IsA("ModuleScript") then
		local ok, result = pcall(require, child)
		if not ok then
			error(
				string.format(
					"Failed to require service %s: %s",
					child:GetFullName(),
					tostring(result)
				)
			)
		end
		if type(result) ~= "table" then
			error(string.format("Service %s must return a table", child:GetFullName()))
		end
		local module = result :: RuntimeModule
		local name = module.Name or child.Name
		if byName[name] then
			error(string.format("Duplicate service name: %s", name))
		end
		module.Name = name
		byName[name] = module
		table.insert(loaded, module)
	end
end

table.sort(loaded, function(a, b)
	return (a.Order or 100) < (b.Order or 100)
end)

local context = {
	Config = Config,
	Services = byName,
	Log = Logger.new("Server", Config.Debug),
}

for _, module in loaded do
	if module.Init then
		module:Init(context)
	end
end

for _, module in loaded do
	if module.Start then
		module:Start(context)
	end
end

log:Info(string.format("Started %d services", #loaded))
]========] },
{ path = [========[ServerScriptService/GameServer/Game/SoloRound]========], class = [========[ModuleScript]========], source = [========[--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameShared = ReplicatedStorage:WaitForChild("GameShared")
local Endpoints = require(GameShared:WaitForChild("Network"):WaitForChild("EndpointNames"))
local AuthoredWorld = require(script.Parent:WaitForChild("AuthoredWorld"))

local SoloRound = {}
SoloRound.__index = SoloRound

function SoloRound.new(context: any)
	return setmetatable({
		context = context,
		balance = context.Config.CoreLoop,
		action = context.Services.NetworkService:GetEvent(Endpoints.RequestRoundAction),
		snapshot = context.Services.NetworkService:GetEvent(Endpoints.RoundSnapshot),
		world = nil :: any,
		selectedSpawn = nil :: BasePart?,
		player = nil :: Player?,
		phase = "ready",
		epoch = 0,
		hasKey = false,
		gateOpen = false,
		diamonds = 0,
		reward = 0,
		startedAt = nil :: number?,
		elapsed = 0,
		notice = "",
		random = Random.new(),
		connections = {} :: { RBXScriptConnection },
		characterConnection = nil :: RBXScriptConnection?,
		characterRemovingConnection = nil :: RBXScriptConnection?,
		deathConnection = nil :: RBXScriptConnection?,
		keyConnection = nil :: RBXScriptConnection?,
		roundCharacter = nil :: Model?,
		boundCharacter = nil :: Model?,
		controlledCharacter = nil :: Model?,
		jumpPower = 50,
		jumpHeight = 7.2,
		autoRotate = true,
		requestTokens = 2,
		requestAt = os.clock(),
		interactionAt = -math.huge,
		pollAt = 0,
		snapshotAt = 0,
	}, SoloRound)
end

function SoloRound:_send()
	local player = self.player
	if not player or player.Parent ~= Players then
		return
	end
	self.snapshot:FireClient(player, {
		phase = self.phase,
		has_key = self.hasKey,
		gate_open = self.gateOpen,
		session_diamonds = self.diamonds,
		reward_diamonds = self.reward,
		elapsed_sec = if self.phase == "active" and self.startedAt
			then os.clock() - self.startedAt
			else self.elapsed,
		notice = self.notice,
	})
end

function SoloRound:_livingCharacter(): (Model?, Humanoid?, BasePart?)
	local player = self.player
	local character = if player then player.Character else nil
	if not character or not character.Parent then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

function SoloRound:_controls(enabled: boolean)
	local character, humanoid = self:_livingCharacter()
	if not character or not humanoid then
		return
	end
	if self.controlledCharacter ~= character then
		self.controlledCharacter = character
		self.jumpPower = humanoid.JumpPower
		self.jumpHeight = humanoid.JumpHeight
		self.autoRotate = humanoid.AutoRotate
	end
	humanoid.WalkSpeed = if enabled then self.balance.walk_speed else 0
	humanoid.JumpPower = if enabled then self.jumpPower else 0
	humanoid.JumpHeight = if enabled then self.jumpHeight else 0
	humanoid.AutoRotate = enabled and self.autoRotate
end

function SoloRound:_fallbackSpawn(): BasePart?
	local map = Workspace:FindFirstChild("CornMap")
	if
		not map
		or not map:IsA("Model")
		or map:GetAttribute("corn_project_id") ~= "children_of_corn"
	then
		return nil
	end
	local ok, result = pcall(AuthoredWorld.FindSafeSpawn, map)
	if not ok then
		self.context.Log:Warn("Cannot find a safe CornMap spawn:", result)
		return nil
	end
	return result
end

function SoloRound:_setRespawnLocation()
	local player = self.player
	if not player then
		return
	end
	local spawn = self.selectedSpawn
	player.RespawnLocation = if spawn
			and spawn:IsA("SpawnLocation")
			and spawn:IsDescendantOf(Workspace)
		then spawn
		else nil
end

function SoloRound:_chooseSpawn()
	if self.world and self.world:IsValid() then
		self.selectedSpawn = self.world:SelectSpawn(self.random:NextInteger(1, #self.world.Spawns))
	else
		self.selectedSpawn = self:_fallbackSpawn()
	end
	self:_setRespawnLocation()
end

function SoloRound:_moveToStart(character: Model)
	local spawn = self.selectedSpawn
	local map = Workspace:FindFirstChild("CornMap")
	if
		not spawn
		or not map
		or not map:IsA("Model")
		or not AuthoredWorld.IsSafeSpawn(map, spawn)
	then
		spawn = self:_fallbackSpawn()
		self.selectedSpawn = spawn
	end
	if not spawn then
		self.context.Log:Warn("No valid CornMap start; install or repair CornerSpawns")
		return
	end
	self:_setRespawnLocation()
	character:PivotTo(AuthoredWorld.SpawnCFrame(spawn))
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
end

function SoloRound:_clearKey()
	if self.keyConnection then
		self.keyConnection:Disconnect()
		self.keyConnection = nil
	end
	if self.world then
		self.world:ClearKey()
	end
end

function SoloRound:_finish(phase: string, notice: string)
	if self.phase ~= "active" and self.phase ~= "preparing" then
		return
	end
	-- Fix the terminal state before rewarding or notifying any client.
	self.elapsed = if self.startedAt then os.clock() - self.startedAt else 0
	self.phase = phase
	self.epoch += 1
	self.notice = notice
	self.reward = if phase == "escaped" then self.balance.escape_reward_diamonds else 0
	self.diamonds += self.reward
	self.hasKey = false
	self:_clearKey()
	if self.world then
		self.world:SetInteractionEnabled(false, self.gateOpen)
	end
	self:_controls(false)
	self:_send()
	self.context.Log:Info("Round finished:", phase, "reward:", self.reward)
end

function SoloRound:_canInteract(
	player: Player,
	item: BasePart,
	itemPrompt: ProximityPrompt
): boolean
	if player ~= self.player or self.phase ~= "active" or not itemPrompt.Enabled then
		return false
	end
	local now = os.clock()
	if now - self.interactionAt < 0.25 then
		return false
	end
	self.interactionAt = now
	local character, _, root = self:_livingCharacter()
	if not character or character ~= self.roundCharacter or not root then
		return false
	end
	if not self.world or not item:IsDescendantOf(self.world.Root) then
		return false
	end
	local direction = item.Position - root.Position
	if direction.Magnitude > self.balance.interaction_radius then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	local hit = Workspace:Raycast(root.Position, direction, params)
	return not hit or hit.Instance == item
end

function SoloRound:_openGate(player: Player)
	local world = self.world
	if
		not world
		or self.gateOpen
		or not self:_canInteract(player, world.GateAnchor, world.GatePrompt)
	then
		return
	end
	local _, _, root = self:_livingCharacter()
	if not root or not world:IsGateFront(root.Position) then
		return
	end
	if not self.hasKey then
		self.notice = "corn_loop_need_key"
		self:_send()
		return
	end
	self.hasKey = false
	self.gateOpen = true
	self.notice = ""
	world:SetGateOpen(true)
	self:_send()
end

function SoloRound:_ensureWorld(): boolean
	if self.world then
		return self.world:IsValid()
	end
	local ok, result =
		pcall(AuthoredWorld.new, self.balance.interaction_radius, self.balance.key_slot_count)
	if not ok then
		self.context.Log:Warn("Cannot bind editable CornMap:", result)
		return false
	end
	self.world = result
	if self.selectedSpawn and table.find(self.world.Spawns, self.selectedSpawn) then
		self.world.Spawn = self.selectedSpawn
	end
	table.insert(
		self.connections,
		self.world.GatePrompt.Triggered:Connect(function(player: Player)
			self:_openGate(player)
		end)
	)
	return true
end

function SoloRound:_startRound()
	if self.phase ~= "ready" and self.phase ~= "escaped" and self.phase ~= "aborted" then
		return
	end
	self.epoch += 1
	local epoch = self.epoch
	self.phase = "preparing"
	self.startedAt = nil
	self.elapsed = 0
	self.reward = 0
	self.notice = ""
	self.hasKey = false
	self.gateOpen = false
	self.roundCharacter = nil
	self:_clearKey()
	self:_controls(false)
	self:_send()
	if not self:_ensureWorld() then
		self:_chooseSpawn()
		local character = self:_livingCharacter()
		if character then
			self:_moveToStart(character)
		end
		self:_finish("aborted", "corn_loop_setup_error")
		return
	end
	self:_chooseSpawn()
	self.world:SetGateOpen(false)
	self.world:SetInteractionEnabled(false, false)

	task.spawn(function()
		local deadline = os.clock() + 10
		local character: Model? = nil
		while
			self.epoch == epoch
			and self.phase == "preparing"
			and self.player
			and self.player.Parent == Players
		do
			character = self:_livingCharacter()
			if character or os.clock() >= deadline then
				break
			end
			task.wait(0.1)
		end
		if self.epoch ~= epoch or self.phase ~= "preparing" then
			return
		end
		if not character then
			self:_finish("aborted", "corn_loop_setup_error")
			return
		end
		if not self.world or not self.world:IsValid() then
			self:_finish("aborted", "corn_loop_setup_error")
			return
		end
		self:_moveToStart(character)
		self.roundCharacter = character
		local slot = self.world.Slots[self.random:NextInteger(1, #self.world.Slots)]
		local keyPrompt = self.world:SpawnKey(slot)
		self.keyConnection = keyPrompt.Triggered:Connect(function(player: Player)
			local key = self.world.Key
			if
				self.epoch ~= epoch
				or self.hasKey
				or self.gateOpen
				or not key
				or keyPrompt ~= self.world.KeyPrompt
			then
				return
			end
			if not self:_canInteract(player, key, keyPrompt) then
				return
			end
			self.hasKey = true
			self.notice = ""
			self:_clearKey()
			self:_send()
		end)
		self.startedAt = os.clock()
		self.phase = "active"
		self.world:SetInteractionEnabled(true, false)
		self:_controls(true)
		self:_send()
		self.context.Log:Info("Solo round started")
	end)
end

function SoloRound:_menu()
	if self.phase ~= "escaped" and self.phase ~= "aborted" then
		return
	end
	self.epoch += 1
	self.phase = "ready"
	self.reward = 0
	self.elapsed = 0
	self.startedAt = nil
	self.notice = ""
	self.hasKey = false
	self.gateOpen = false
	self:_clearKey()
	if self.world then
		self.world:SetGateOpen(false)
		self.world:SetInteractionEnabled(false, false)
	end
	local character = self:_livingCharacter()
	if character then
		self:_moveToStart(character)
	end
	self:_controls(false)
	self:_send()
end

function SoloRound:_request(player: Player, action: any)
	if player ~= self.player then
		return
	end
	local now = os.clock()
	self.requestTokens = math.min(2, self.requestTokens + (now - self.requestAt) * 2)
	self.requestAt = now
	if self.requestTokens < 1 then
		return
	end
	self.requestTokens -= 1
	if type(action) ~= "string" then
		return
	end
	if action == "sync" then
		self:_send()
	elseif
		(action == "start" and self.phase == "ready")
		or (action == "retry" and (self.phase == "escaped" or self.phase == "aborted"))
	then
		self:_startRound()
	elseif action == "abort" then
		self:_finish("aborted", "corn_loop_result_aborted")
	elseif action == "menu" then
		self:_menu()
	end
end

function SoloRound:_bindCharacter(character: Model)
	if character == self.boundCharacter then
		return
	end
	self.boundCharacter = character
	if self.deathConnection then
		self.deathConnection:Disconnect()
		self.deathConnection = nil
	end
	if self.phase == "active" or (self.phase == "preparing" and self.roundCharacter ~= nil) then
		self:_finish("aborted", "corn_loop_result_aborted")
	end
	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 10)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		local player = self.player
		if not player or player.Character ~= character or self.boundCharacter ~= character then
			return
		end
		if not humanoid or not humanoid:IsA("Humanoid") or not root or not root:IsA("BasePart") then
			self:_finish("aborted", "corn_loop_setup_error")
			return
		end
		self.deathConnection = humanoid.Died:Connect(function()
			if self.player and self.player.Character == character then
				self:_finish("aborted", "corn_loop_result_aborted")
			end
		end)
		if self.phase ~= "active" and self.phase ~= "preparing" then
			self:_moveToStart(character)
		end
		self:_controls(self.phase == "active" and self.roundCharacter == character)
		self:_send()
	end)
end

function SoloRound:_addPlayer(player: Player)
	if self.player then
		return -- One owner, no multiplayer matchmaking in this prototype.
	end
	self.player = player
	self:_setRespawnLocation()
	self.requestTokens = 2
	self.requestAt = os.clock()
	self.characterConnection = player.CharacterAdded:Connect(function(character: Model)
		self:_bindCharacter(character)
	end)
	self.characterRemovingConnection = player.CharacterRemoving:Connect(function(character: Model)
		if
			player == self.player
			and (character == self.boundCharacter or character == player.Character)
		then
			self:_finish("aborted", "corn_loop_result_aborted")
		end
	end)
	if player.Character then
		self:_bindCharacter(player.Character)
	end
	self:_send()
end

function SoloRound:_removePlayer(player: Player)
	if player ~= self.player then
		return
	end
	self.epoch += 1
	self:_clearKey()
	if self.characterConnection then
		self.characterConnection:Disconnect()
		self.characterConnection = nil
	end
	if self.deathConnection then
		self.deathConnection:Disconnect()
		self.deathConnection = nil
	end
	if self.characterRemovingConnection then
		self.characterRemovingConnection:Disconnect()
		self.characterRemovingConnection = nil
	end
	self.player = nil
	self.phase = "ready"
	self.hasKey = false
	self.gateOpen = false
	self.diamonds = 0
	self.reward = 0
	self.startedAt = nil
	self.elapsed = 0
	self.notice = ""
	self.roundCharacter = nil
	self.boundCharacter = nil
	self.controlledCharacter = nil
	if self.world then
		self.world:SetGateOpen(false)
		self.world:SetInteractionEnabled(false, false)
	end
end

function SoloRound:_poll(now: number)
	if self.phase ~= "active" then
		return
	end
	local character, _, root = self:_livingCharacter()
	if not character or character ~= self.roundCharacter or not root then
		self:_finish("aborted", "corn_loop_result_aborted")
		return
	end
	if
		not self.world
		or not self.world:IsValid()
		or not self.world:IsOnPlayground(root.Position)
	then
		self:_finish("aborted", "corn_loop_setup_error")
		return
	end
	if self.gateOpen and self.world:IsInExit(root.Position) then
		self:_finish("escaped", "")
		return
	end
	if now - self.snapshotAt >= 1 then
		self.snapshotAt = now
		self:_send()
	end
end

function SoloRound:Start()
	self:_ensureWorld()
	self:_chooseSpawn()
	table.insert(
		self.connections,
		self.action.OnServerEvent:Connect(function(player: Player, action: any)
			self:_request(player, action)
		end)
	)
	table.insert(
		self.connections,
		Players.PlayerAdded:Connect(function(player: Player)
			self:_addPlayer(player)
		end)
	)
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player: Player)
			self:_removePlayer(player)
		end)
	)
	table.insert(
		self.connections,
		RunService.Heartbeat:Connect(function()
			local now = os.clock()
			if now - self.pollAt >= 0.1 then
				self.pollAt = now
				self:_poll(now)
			end
		end)
	)
	for _, player in Players:GetPlayers() do
		self:_addPlayer(player)
	end
end

return SoloRound
]========] },
{ path = [========[ServerScriptService/GameServer/Game/CornField]========], class = [========[ModuleScript]========], source = [========[--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local GameShared = ReplicatedStorage:WaitForChild("GameShared")
local Config = require(GameShared:WaitForChild("Config"):WaitForChild("GameConfig"))
local CornLayout = require(GameShared:WaitForChild("Game"):WaitForChild("CornLayout"))

local CornField = {}
local PROJECT_ID = "children_of_corn"
local OWNER_ATTRIBUTE = "CornRuntimeArtOwned"

function CornField.Prepare(): boolean
	if
		not RunService:IsStudio()
		or Config.Environment ~= "DEV"
		or Config.Game.SessionMode ~= "solo_local"
	then
		return false
	end
	local sources: { Instance } = {}
	for _, item in ServerStorage:GetChildren() do
		if item.Name == "CornPlantTemplate" or item.Name == "SM_Prop_Plant_Corn_01_L" then
			table.insert(sources, item)
		end
	end
	if #sources ~= 1 then
		warn(
			"[CornField] Expected exactly one ServerStorage CornPlantTemplate or SM_Prop_Plant_Corn_01_L art source"
		)
		return false
	end
	local prepared, problem = CornLayout.PrepareTemplate(sources[1])
	if not prepared then
		warn("[CornField] " .. (problem or "Could not prepare corn art"))
		return false
	end
	local folder: Instance? = nil
	for _, item in ReplicatedStorage:GetChildren() do
		if item.Name == "CornRuntimeArt" then
			if folder then
				prepared:Destroy()
				warn(
					"[CornField] Duplicate CornRuntimeArt containers; existing contents were preserved"
				)
				return false
			end
			folder = item
		end
	end
	if
		folder
		and (
			not folder:IsA("Folder")
			or folder:GetAttribute(OWNER_ATTRIBUTE) ~= true
			or folder:GetAttribute("corn_project_id") ~= PROJECT_ID
		)
	then
		prepared:Destroy()
		warn("[CornField] Refused to overwrite an unowned CornRuntimeArt container")
		return false
	end
	if folder then
		for _, item in folder:GetChildren() do
			if
				item.Name == "CornPlantTemplate"
				and item:GetAttribute("CornPlantTemplateOwned") ~= true
			then
				prepared:Destroy()
				warn("[CornField] Refused to overwrite unowned CornPlantTemplate art")
				return false
			end
		end
	else
		folder = Instance.new("Folder")
		folder.Name = "CornRuntimeArt"
		folder:SetAttribute(OWNER_ATTRIBUTE, true)
		folder:SetAttribute("corn_project_id", PROJECT_ID)
	end
	prepared.Name = "CornPlantTemplate"
	prepared:SetAttribute("CornPlantTemplateOwned", true)
	prepared:SetAttribute("CornPlantHeight", CornLayout.Height)
	for _, item in folder:GetChildren() do
		if
			item.Name == "CornPlantTemplate"
			and item:GetAttribute("CornPlantTemplateOwned") == true
		then
			item:Destroy()
		end
	end
	prepared.Parent = folder
	folder.Parent = ReplicatedStorage
	print("[CornField] Prepared a corn art clone; ServerStorage source is unchanged")
	return true
end

return CornField
]========] },
{ path = [========[ServerScriptService/GameServer/Game/AuthoredWorld]========], class = [========[ModuleScript]========], source = [========[--!strict
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local CornField = require(script.Parent:WaitForChild("CornField"))
local AuthoredWorld = {}
AuthoredWorld.__index = AuthoredWorld

local function namedPart(parent: Instance, name: string): BasePart
	local item = parent:FindFirstChild(name)
	assert(item and item:IsA("BasePart"), "Missing map part: " .. name)
	return item
end

local function hasTag(item: Instance, tag: string): boolean
	return CollectionService:HasTag(item, tag)
end

local function prompt(
	parent: Instance,
	name: string,
	action: string,
	object: string,
	radius: number
): ProximityPrompt
	assert(not parent:FindFirstChild(name), "Duplicate owned prompt: " .. name)
	local item = Instance.new("ProximityPrompt")
	item.Name = name
	item.ActionText = action
	item.ObjectText = object
	item.KeyboardKeyCode = Enum.KeyCode.E
	item.MaxActivationDistance = radius
	item.RequiresLineOfSight = true
	item.HoldDuration = 0
	item.Enabled = false
	item.Parent = parent
	return item
end

local function inBox(part: BasePart, position: Vector3): boolean
	local point = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(point.X) <= half.X
		and math.abs(point.Y) <= half.Y
		and math.abs(point.Z) <= half.Z
end

local function validateSpawn(root: Model, spawn: BasePart, bounds: BasePart)
	assert(spawn:IsDescendantOf(root), "Spawn must belong to CornMap")
	assert(hasTag(spawn, "corn_spawn"), "Missing corn_spawn tag: " .. spawn.Name)
	local id = spawn:GetAttribute("spawn_id")
	assert(type(id) == "string" and id ~= "", "Spawn id must be a nonempty string: " .. spawn.Name)
	assert(spawn.Anchored, "Spawn must be Anchored: " .. spawn.Name)
	assert(
		spawn.CFrame.UpVector:Dot(Vector3.yAxis) > 0.999,
		"Spawn must remain horizontal: " .. spawn.Name
	)
	if spawn:IsA("SpawnLocation") then
		assert(
			spawn.Enabled and spawn.Neutral,
			"Corner spawn must be enabled and neutral: " .. spawn.Name
		)
	end
	local position = (spawn.CFrame * CFrame.new(0, spawn.Size.Y / 2 + 3.5, 0)).Position
	assert(inBox(bounds, position), "Spawn is outside PlayBounds: " .. spawn.Name)
end

function AuthoredWorld.IsSafeSpawn(root: Model, spawn: BasePart): boolean
	local bounds = root:FindFirstChild("PlayBounds")
	return bounds ~= nil and bounds:IsA("BasePart") and pcall(validateSpawn, root, spawn, bounds)
end

function AuthoredWorld.ReadSpawns(root: Model): { BasePart }
	local bounds = namedPart(root, "PlayBounds")
	local corners = root:FindFirstChild("CornerSpawns")
	local spawns: { BasePart } = {}
	if corners then
		assert(
			corners:IsA("Folder")
				and corners:GetAttribute("CornCornerSpawnsOwned") == true
				and corners:GetAttribute("corn_project_id") == "children_of_corn",
			"Unrecognized CornerSpawns"
		)
		local seen: { [string]: boolean } = {}
		for _, item in corners:GetChildren() do
			assert(item:IsA("SpawnLocation"), "CornerSpawns must contain only SpawnLocations")
			validateSpawn(root, item, bounds)
			local id = item:GetAttribute("spawn_id") :: string
			assert(not seen[id], "Corner spawn ids must be unique")
			seen[id] = true
			table.insert(spawns, item)
		end
		assert(#spawns == 4, "CornMap must have four corner spawns")
		table.sort(spawns, function(a, b)
			return tostring(a:GetAttribute("spawn_id")) < tostring(b:GetAttribute("spawn_id"))
		end)
	else
		local legacy = namedPart(root, "RoundSpawn")
		validateSpawn(root, legacy, bounds)
		table.insert(spawns, legacy)
	end
	return spawns
end

-- A broken gate or slot must not leave the menu character underneath the map.
function AuthoredWorld.FindSafeSpawn(root: Model): BasePart?
	local bounds = root:FindFirstChild("PlayBounds")
	if not bounds or not bounds:IsA("BasePart") then
		return nil
	end
	local candidates: { BasePart } = {}
	local corners = root:FindFirstChild("CornerSpawns")
	if
		corners
		and corners:IsA("Folder")
		and corners:GetAttribute("CornCornerSpawnsOwned") == true
		and corners:GetAttribute("corn_project_id") == "children_of_corn"
	then
		for _, item in corners:GetChildren() do
			if item:IsA("SpawnLocation") and pcall(validateSpawn, root, item, bounds) then
				table.insert(candidates, item)
			end
		end
	end
	table.sort(candidates, function(a, b)
		return tostring(a:GetAttribute("spawn_id")) < tostring(b:GetAttribute("spawn_id"))
	end)
	if candidates[1] then
		return candidates[1]
	end
	local legacy = root:FindFirstChild("RoundSpawn")
	if legacy and legacy:IsA("BasePart") and pcall(validateSpawn, root, legacy, bounds) then
		return legacy
	end
	return nil
end

function AuthoredWorld.SpawnCFrame(spawn: BasePart): CFrame
	return spawn.CFrame * CFrame.new(0, spawn.Size.Y / 2 + 3.5, 0)
end

function AuthoredWorld.new(radius: number, expectedSlots: number)
	local root = Workspace:FindFirstChild("CornMap")
	assert(
		root and root:IsA("Model") and root:GetAttribute("corn_project_id") == "children_of_corn",
		"Install the editable CornMap in Children_of_corn before Test"
	)
	local spawns = AuthoredWorld.ReadSpawns(root)
	local field = namedPart(root, "FieldZone")
	local bounds = namedPart(root, "PlayBounds")
	local gateModel = root:FindFirstChild("EscapeGate")
	assert(
		gateModel and gateModel:IsA("Model") and hasTag(gateModel, "corn_gate"),
		"Missing tagged EscapeGate"
	)
	local gate = namedPart(gateModel, "Door")
	local anchor = namedPart(gateModel, "InteractionAnchor")
	local exit = namedPart(gateModel, "ExitZone")
	assert(hasTag(exit, "corn_exit"), "Missing corn_exit tag")
	local gateId = gateModel:GetAttribute("gate_id")
	assert(type(gateId) == "string" and gateId ~= "", "Gate id must be a nonempty string")
	assert(exit:GetAttribute("gate_id") == gateId, "Gate/exit identity mismatch")
	local slots: { BasePart } = {}
	local seen: { [string]: boolean } = {}
	for _, item in root:GetDescendants() do
		if item:IsA("BasePart") and hasTag(item, "corn_key_slot") then
			local id = item:GetAttribute("slot_id")
			assert(
				type(id) == "string" and id ~= "" and not seen[id],
				"Key slot ids must be unique strings"
			)
			seen[id] = true
			table.insert(slots, item)
		end
	end
	assert(#slots == expectedSlots, "CornMap must have " .. tostring(expectedSlots) .. " key slots")
	table.sort(slots, function(a, b)
		return tostring(a:GetAttribute("slot_id")) < tostring(b:GetAttribute("slot_id"))
	end)
	assert(not root:FindFirstChild("CornRoundRuntime"), "CornRoundRuntime already exists")
	assert(not anchor:FindFirstChild("CornGatePrompt"), "CornGatePrompt already exists")
	assert(gate.CanCollide, "Closed Door must have CanCollide enabled")
	local artOk, artReady = pcall(CornField.Prepare)
	if not artOk or not artReady then
		warn("[AuthoredWorld] Corn art unavailable:", artReady)
	end
	local runtime = Instance.new("Folder")
	runtime.Name = "CornRoundRuntime"
	runtime:SetAttribute("corn_project_id", "children_of_corn")
	runtime.Parent = root
	local gatePrompt = prompt(anchor, "CornGatePrompt", "Открыть", "Ворота", radius)
	local self = setmetatable({
		Root = root,
		Radius = radius,
		Slots = slots,
		Spawns = spawns,
		Spawn = spawns[1],
		Field = field,
		Bounds = bounds,
		GateModel = gateModel,
		Gate = gate,
		GateAnchor = anchor,
		Exit = exit,
		Runtime = runtime,
		GatePrompt = gatePrompt,
		ClosedTransparency = gate.Transparency,
		ClosedCollision = gate.CanCollide,
		ClosedQuery = gate.CanQuery,
		Key = nil :: Part?,
		KeyPrompt = nil :: ProximityPrompt?,
	}, AuthoredWorld)
	return self
end

function AuthoredWorld:SelectSpawn(index: number): BasePart
	assert(index % 1 == 0 and index >= 1 and index <= #self.Spawns, "Invalid spawn index")
	local spawn = self.Spawns[index]
	validateSpawn(self.Root, spawn, self.Bounds)
	self.Spawn = spawn
	return spawn
end

function AuthoredWorld:GetSpawnCFrame(): CFrame
	validateSpawn(self.Root, self.Spawn, self.Bounds)
	return AuthoredWorld.SpawnCFrame(self.Spawn)
end

function AuthoredWorld:ClearKey()
	if self.Key then
		self.Key:Destroy()
	end
	self.Key = nil
	self.KeyPrompt = nil
end

function AuthoredWorld:SpawnKey(slot: BasePart): ProximityPrompt
	assert(slot:IsDescendantOf(self.Root), "Key slot must belong to CornMap")
	self:ClearKey()
	local key = Instance.new("Part")
	key.Name = "GateKey"
	key.Size = Vector3.new(1.5, 0.4, 3)
	key.CFrame = slot.CFrame * CFrame.new(0, slot.Size.Y / 2 + 0.3, 0)
	key.Anchored = true
	key.Color = Color3.fromRGB(240, 198, 69)
	key.Material = Enum.Material.Metal
	key.CanCollide = false
	key.CanTouch = false
	key.Parent = self.Runtime
	self.Key = key
	self.KeyPrompt =
		prompt(key, "CornKeyPrompt", "Подобрать", "Ключ от ворот", self.Radius)
	return self.KeyPrompt
end

function AuthoredWorld:SetGateOpen(open: boolean)
	self.Gate.CanCollide = if open then false else self.ClosedCollision
	self.Gate.CanQuery = if open then false else self.ClosedQuery
	self.Gate.Transparency = if open then 1 else self.ClosedTransparency
	self.GatePrompt.Enabled = false
	self.Runtime:SetAttribute("GateOpen", open)
end

function AuthoredWorld:SetInteractionEnabled(enabled: boolean, gateOpen: boolean)
	self.GatePrompt.Enabled = enabled and not gateOpen
	if self.KeyPrompt then
		self.KeyPrompt.Enabled = enabled
	end
end

function AuthoredWorld:IsGateFront(position: Vector3): boolean
	local anchor = self.Gate.CFrame:PointToObjectSpace(self.GateAnchor.Position)
	local point = self.Gate.CFrame:PointToObjectSpace(position)
	local frontSign = if anchor.Z < 0 then -1 else 1
	return point.Z * frontSign > self.Gate.Size.Z / 2
end

function AuthoredWorld:IsInExit(position: Vector3): boolean
	return inBox(self.Exit, position)
end

function AuthoredWorld:IsOnPlayground(position: Vector3): boolean
	return inBox(self.Bounds, position)
end

function AuthoredWorld:IsValid(): boolean
	if
		self.Root.Parent ~= Workspace
		or not self.Runtime:IsDescendantOf(self.Root)
		or not self.Spawn:IsDescendantOf(self.Root)
		or not self.Field:IsDescendantOf(self.Root)
		or not self.Bounds:IsDescendantOf(self.Root)
		or not self.Gate:IsDescendantOf(self.Root)
		or not self.GateAnchor:IsDescendantOf(self.Root)
		or not self.Exit:IsDescendantOf(self.Root)
		or not self.GatePrompt:IsDescendantOf(self.GateAnchor)
		or #self.Slots ~= 15
	then
		return false
	end
	local spawnIds: { [string]: boolean } = {}
	for _, spawn in self.Spawns do
		if not pcall(validateSpawn, self.Root, spawn, self.Bounds) then
			return false
		end
		local id = spawn:GetAttribute("spawn_id") :: string
		if spawnIds[id] then
			return false
		end
		spawnIds[id] = true
	end
	local gateId = self.GateModel:GetAttribute("gate_id")
	if type(gateId) ~= "string" or gateId == "" or gateId ~= self.Exit:GetAttribute("gate_id") then
		return false
	end
	for _, slot in self.Slots do
		if not slot:IsDescendantOf(self.Root) then
			return false
		end
	end
	return true
end

return AuthoredWorld
]========] },
{ path = [========[ServerScriptService/GameServer/Game/MapAuthoring]========], class = [========[ModuleScript]========], source = [========[--!strict
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local Layout = require(
	ReplicatedStorage:WaitForChild("GameShared"):WaitForChild("Game"):WaitForChild("CornLayout")
)
local MapAuthoring = {}

local function guard()
	assert(
		RunService:IsStudio() and not RunService:IsRunning(),
		"Use the Command Bar in Studio Edit mode"
	)
	assert(
		not Workspace:FindFirstChild("Asmr_Base") and not Workspace:FindFirstChild("ASMR_Models"),
		"Speed Monkey scene detected; Corn installation refused"
	)
	local config = ReplicatedStorage:FindFirstChild("GameShared")
	config = config and config:FindFirstChild("Config")
	local module = config and config:FindFirstChild("GameConfig")
	assert(
		module
			and module:IsA("ModuleScript")
			and string.find(module.Source, 'Id = "children_of_corn"', 1, true),
		"Open the Children_of_corn project"
	)
end

local function artSource(): Instance
	local first = ServerStorage:FindFirstChild("CornPlantTemplate")
	local imported = ServerStorage:FindFirstChild("SM_Prop_Plant_Corn_01_L")
	assert(not (first and imported), "Keep one unambiguous corn source in ServerStorage")
	local source = first or imported
	assert(source, "Imported corn asset missing from ServerStorage")
	return source
end

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3
): Part
	local item = Instance.new("Part")
	item.Name = name
	item.Anchored = true
	item.Size = size
	item.Position = position
	item.Color = color
	item.TopSurface = Enum.SurfaceType.Smooth
	item.BottomSurface = Enum.SurfaceType.Smooth
	item.Parent = parent
	return item
end

local function zone(parent: Instance, name: string, size: Vector3, position: Vector3): Part
	local item = part(parent, name, size, position, Color3.fromRGB(123, 175, 113))
	item.Transparency = 1
	item.CanCollide = false
	item.CanTouch = false
	item.CanQuery = false
	return item
end

local function noCorn(parent: Instance, name: string, size: Vector3, position: Vector3): Part
	local item = zone(parent, name, size, position)
	CollectionService:AddTag(item, "corn_no_corn_zone")
	return item
end

local function house(parent: Instance, name: string, origin: Vector3)
	local root = Instance.new("Model")
	root.Name = name
	root.Parent = parent
	local walls = part(
		root,
		"Body",
		Vector3.new(20, 12, 24),
		origin + Vector3.new(0, 6, 0),
		Color3.fromRGB(95, 84, 62)
	)
	walls.Material = Enum.Material.WoodPlanks
	local door = part(
		root,
		"DecorativeDoor",
		Vector3.new(4, 7, 0.25),
		origin + Vector3.new(0, 3.5, -12.1),
		Color3.fromRGB(58, 45, 33)
	)
	door.Material = Enum.Material.Wood
	for _, side in { -1, 1 } do
		local roof = part(
			root,
			"Roof",
			Vector3.new(12, 1, 26),
			origin + Vector3.new(side * 5, 14, 0),
			Color3.fromRGB(54, 57, 49)
		)
		roof.CFrame *= CFrame.Angles(0, 0, -side * math.pi / 8)
		roof.Material = Enum.Material.Slate
	end
end

function MapAuthoring.EnsureCornerSpawns(map: Model): Folder
	guard()
	assert(
		map.Parent == Workspace and map:GetAttribute("corn_project_id") == "children_of_corn",
		"Corner spawns require the correct editable CornMap"
	)
	local field = map:FindFirstChild("FieldZone")
	local bounds = map:FindFirstChild("PlayBounds")
	assert(
		field and field:IsA("BasePart") and bounds and bounds:IsA("BasePart"),
		"FieldZone/PlayBounds missing"
	)
	assert(field.CFrame.UpVector:Dot(Vector3.yAxis) > 0.999, "FieldZone must remain horizontal")
	assert(field.Size.X > 100 and field.Size.Z > 100, "FieldZone is too small for corner starts")
	local entries = {
		{ Name = "SW", Id = "solo_corner_sw", X = -1, Z = -1 },
		{ Name = "SE", Id = "solo_corner_se", X = 1, Z = -1 },
		{ Name = "NW", Id = "solo_corner_nw", X = -1, Z = 1 },
		{ Name = "NE", Id = "solo_corner_ne", X = 1, Z = 1 },
	}
	local old = map:FindFirstChild("CornerSpawns")
	if old then
		assert(
			old:IsA("Folder")
				and old:GetAttribute("CornCornerSpawnsOwned") == true
				and old:GetAttribute("corn_project_id") == "children_of_corn",
			"Unrecognized CornerSpawns; not replaced"
		)
		assert(#old:GetChildren() == 4, "CornerSpawns must contain exactly four owned starts")
		for _, entry in entries do
			local item = old:FindFirstChild(entry.Name)
			assert(
				item
					and item:IsA("SpawnLocation")
					and item:GetAttribute("spawn_id") == entry.Id
					and item:GetAttribute("CornCornerSpawnOwned") == true
					and item:GetAttribute("corn_project_id") == "children_of_corn"
					and CollectionService:HasTag(item, "corn_spawn")
					and item.Enabled
					and item.Neutral,
				"Unknown or invalid corner start: " .. entry.Name
			)
			local position = bounds.CFrame:PointToObjectSpace(
				(item.CFrame * CFrame.new(0, item.Size.Y / 2 + 3.5, 0)).Position
			)
			local half = bounds.Size / 2
			assert(
				math.abs(position.X) <= half.X
					and math.abs(position.Y) <= half.Y
					and math.abs(position.Z) <= half.Z
					and item.Anchored
					and item.CFrame.UpVector:Dot(Vector3.yAxis) > 0.999,
				"Corner start is unsafe: " .. entry.Name
			)
		end
		return old
	end
	local folder = Instance.new("Folder")
	folder.Name = "CornerSpawns"
	folder:SetAttribute("CornCornerSpawnsOwned", true)
	folder:SetAttribute("corn_project_id", "children_of_corn")
	local ok, problem = pcall(function()
		for _, entry in entries do
			local localPosition = Vector3.new(
				entry.X * (field.Size.X / 2 - 50),
				-field.Size.Y / 2 + 0.075,
				entry.Z * (field.Size.Z / 2 - 50)
			)
			local position = field.CFrame:PointToWorldSpace(localPosition)
			local center = Vector3.new(field.Position.X, position.Y, field.Position.Z)
			local item = Instance.new("SpawnLocation")
			item.Parent = folder
			item.Name = entry.Name
			item.Size = Vector3.new(6, 0.15, 6)
			item.CFrame = CFrame.lookAt(position, center)
			item.Anchored = true
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = false
			item.Neutral = true
			item.Enabled = true
			item.AllowTeamChangeOnTouch = false
			item.Duration = 0
			item.Color = Color3.fromRGB(158, 176, 150)
			item:SetAttribute("spawn_id", entry.Id)
			item:SetAttribute("CornCornerSpawnOwned", true)
			item:SetAttribute("corn_project_id", "children_of_corn")
			CollectionService:AddTag(item, "corn_spawn")
			local candidate = bounds.CFrame:PointToObjectSpace(
				(item.CFrame * CFrame.new(0, item.Size.Y / 2 + 3.5, 0)).Position
			)
			local half = bounds.Size / 2
			assert(
				math.abs(candidate.X) <= half.X
					and math.abs(candidate.Y) <= half.Y
					and math.abs(candidate.Z) <= half.Z,
				"Corner start is outside PlayBounds"
			)
			item.Parent = folder
		end
	end)
	if not ok then
		folder:Destroy()
		error(tostring(problem))
	end
	folder.Parent = map
	return folder
end

function MapAuthoring.Preview(map: Model, center: Vector3, radius: number?): number
	guard()
	local field = map:FindFirstChild("FieldZone")
	assert(field and field:IsA("BasePart"), "CornMap FieldZone missing")
	local old = map:FindFirstChild("EditorPreview")
	assert(
		not old
			or (
				old:IsA("Folder")
				and old:GetAttribute("CornEditorPreview") == true
				and old:GetAttribute("corn_project_id") == "children_of_corn"
			),
		"Unrecognized EditorPreview; not replaced"
	)
	local prepared, problem = Layout.PrepareTemplate(artSource())
	assert(prepared, problem or "Cannot prepare corn preview")
	local folder = Instance.new("Folder")
	folder.Name = "EditorPreview"
	folder:SetAttribute("CornEditorPreview", true)
	folder:SetAttribute("corn_project_id", "children_of_corn")
	local distance = math.clamp(radius or 55, 10, 85)
	local localCenter = field.CFrame:PointToObjectSpace(center)
	local minColumn, maxColumn, minRow, maxRow = Layout.GetCellBounds(field)
	minColumn = math.max(minColumn, math.ceil((localCenter.X - distance) / Layout.Spacing))
	maxColumn = math.min(maxColumn, math.floor((localCenter.X + distance) / Layout.Spacing))
	minRow = math.max(minRow, math.ceil((localCenter.Z - distance) / Layout.Spacing))
	maxRow = math.min(maxRow, math.floor((localCenter.Z + distance) / Layout.Spacing))
	local exclusions = Layout.ReadExclusions(map, field)
	local _, fieldYaw = field.CFrame:ToOrientation()
	local count = 0
	local ok, err = pcall(function()
		for row = minRow, maxRow do
			for column = minColumn, maxColumn do
				local position = Layout.CellPosition(field, column, row)
				local delta = position - center
				if
					Vector2.new(delta.X, delta.Z).Magnitude <= distance
					and not Layout.IsExcluded(position, exclusions)
				then
					local clone = prepared:Clone()
					assert(clone, "Corn clone is not Archivable")
					clone.Name = "Corn"
					clone:PivotTo(
						Layout.PivotForPlant(
							prepared,
							position,
							Layout.CellYaw(column, row) + fieldYaw
						)
					)
					clone.Parent = folder
					count += 1
				end
			end
		end
	end)
	prepared:Destroy()
	if not ok then
		folder:Destroy()
		error(tostring(err))
	end
	if old then
		old:Destroy()
	end
	folder.Parent = map
	folder:SetAttribute("PlantCount", count)
	return count
end

-- Whole-map coarse corn for authoring and distant view; fine plants stay local.
function MapAuthoring.RebuildOverview(map: Model): number
	guard()
	assert(
		map.Parent == Workspace and map:GetAttribute("corn_project_id") == "children_of_corn",
		"CornMap missing"
	)
	local field = map:FindFirstChild("FieldZone")
	assert(field and field:IsA("BasePart"), "FieldZone missing")
	assert(field.CFrame.UpVector:Dot(Vector3.yAxis) > 0.9999, "FieldZone must stay horizontal")
	local old = map:FindFirstChild("EditorFieldOverview")
	if old then
		assert(
			old:IsA("Folder")
				and old:GetAttribute("CornEditorOverview") == true
				and old:GetAttribute("corn_project_id") == "children_of_corn",
			"Unrecognized overview; retained"
		)
		for _, item in old:GetChildren() do
			assert(
				item:IsA("BasePart")
					and item:GetAttribute("CornEditorOverview") == true
					and item:GetAttribute("corn_project_id") == "children_of_corn",
				"Overview contains manual objects; retained"
			)
		end
	end
	local prepared, problem = Layout.PrepareTemplate(artSource())
	assert(prepared, problem or "Cannot prepare overview art")
	assert(prepared:IsA("MeshPart"), "Whole-field overview requires the imported single-mesh corn")
	local stride = 16
	prepared.Size = Vector3.new(prepared.Size.X * 6, prepared.Size.Y, prepared.Size.Z * 6)
	local _, preparedSize = Layout.Bounds(prepared)
	local half = preparedSize / 2
	local folder = Instance.new("Folder")
	folder.Name = "EditorFieldOverview"
	folder:SetAttribute("CornEditorOverview", true)
	folder:SetAttribute("corn_project_id", "children_of_corn")
	folder:SetAttribute("OverviewSpacing", stride)
	local exclusions = Layout.ReadExclusions(map, field)
	local _, yaw = field.CFrame:ToOrientation()
	local count = 0
	local ok, err = pcall(function()
		for row = math.ceil(-field.Size.Z / 2 / stride), math.floor(field.Size.Z / 2 / stride) do
			for column = math.ceil(-field.Size.X / 2 / stride), math.floor(field.Size.X / 2 / stride) do
				local ground = field.CFrame:PointToWorldSpace(
					Vector3.new(column * stride, -field.Size.Y / 2, row * stride)
				)
				local excluded = false
				for _, x in { -1, 0, 1 } do
					for _, z in { -1, 0, 1 } do
						local sample = ground
							+ field.CFrame:VectorToWorldSpace(
								Vector3.new(x * half.X, 0, z * half.Z)
							)
						if Layout.IsExcluded(sample, exclusions) then
							excluded = true
							break
						end
					end
					if excluded then
						break
					end
				end
				if excluded then
					continue
				end
				local clone = prepared:Clone()
				assert(clone, "Overview clone failed")
				clone.Name = "DistantCorn"
				clone:SetAttribute("CornEditorOverview", true)
				clone:SetAttribute("corn_project_id", "children_of_corn")
				clone:PivotTo(Layout.PivotForPlant(prepared, ground, yaw))
				clone.Parent = folder
				count += 1
				if count % 128 == 0 then
					task.wait()
				end
			end
		end
	end)
	prepared:Destroy()
	if not ok then
		folder:Destroy()
		error(tostring(err))
	end
	if old then
		old:Destroy()
	end
	folder:SetAttribute("PlantCount", count)
	folder.Parent = map
	print("CornMap whole-field overview:", count, "coarse meshes; fine corn uses 3-stud spacing")
	return count
end

function MapAuthoring.PreviewAtSelection(): number
	guard()
	local map = Workspace:FindFirstChild("CornMap")
	assert(
		map and map:IsA("Model") and map:GetAttribute("corn_project_id") == "children_of_corn",
		"CornMap missing"
	)
	local spawn: Instance? = map:FindFirstChild("RoundSpawn")
	if not spawn then
		local corners = map:FindFirstChild("CornerSpawns")
		spawn = corners and corners:FindFirstChild("SW")
	end
	assert(spawn and spawn:IsA("BasePart"), "CornMap has no preview start")
	local center = spawn.Position
	local selected = Selection:Get()[1]
	if selected and (selected:IsA("Model") or selected:IsA("BasePart")) then
		center = selected:GetPivot().Position
	end
	local count = MapAuthoring.Preview(map, center)
	print("CornMap editor preview:", count, "plants near selection")
	return count
end

function MapAuthoring.Install(): Model
	guard()
	assert(not Workspace:FindFirstChild("CornMap"), "CornMap already exists; manual edits retained")
	local testClone, problem = Layout.PrepareTemplate(artSource())
	assert(testClone, problem or "Corn art preparation failed")
	testClone:Destroy()
	local root = Instance.new("Model")
	root.Name = "CornMap"
	root:SetAttribute("corn_project_id", "children_of_corn")
	root:SetAttribute("map_version", 1)
	local ok, err = pcall(function()
		local ground = part(
			root,
			"Ground",
			Vector3.new(1200, 2, 1200),
			Vector3.new(0, 79, 0),
			Color3.fromRGB(91, 97, 70)
		)
		ground.Material = Enum.Material.Ground
		local field = zone(root, "FieldZone", Vector3.new(1200, 10, 1200), Vector3.new(0, 85, 0))
		CollectionService:AddTag(field, "corn_field_zone")
		local bounds = zone(root, "PlayBounds", Vector3.new(1200, 50, 1240), Vector3.new(0, 100, 0))
		CollectionService:AddTag(bounds, "corn_play_bounds")
		local zones = Instance.new("Folder")
		zones.Name = "NoCornZones"
		zones.Parent = root
		local props = Instance.new("Folder")
		props.Name = "Props"
		props.Parent = root
		local slots = Instance.new("Folder")
		slots.Name = "KeySlots"
		slots.Parent = root
		local boundaries = Instance.new("Folder")
		boundaries.Name = "Boundaries"
		boundaries.Parent = root
		local wall = Color3.fromRGB(51, 61, 52)
		part(boundaries, "West", Vector3.new(2, 20, 1204), Vector3.new(-601, 90, 0), wall)
		part(boundaries, "East", Vector3.new(2, 20, 1204), Vector3.new(601, 90, 0), wall)
		part(boundaries, "South", Vector3.new(1200, 20, 2), Vector3.new(0, 90, -601), wall)
		part(boundaries, "NorthLeft", Vector3.new(594, 20, 2), Vector3.new(-303, 90, 601), wall)
		part(boundaries, "NorthRight", Vector3.new(594, 20, 2), Vector3.new(303, 90, 601), wall)
		local spawn = part(
			root,
			"RoundSpawn",
			Vector3.new(6, 0.15, 6),
			Vector3.new(0, 80.075, -500),
			Color3.fromRGB(158, 176, 150)
		)
		spawn.CFrame *= CFrame.Angles(0, math.pi, 0)
		spawn.CanCollide = false
		spawn.CanTouch = false
		spawn.CanQuery = false
		spawn:SetAttribute("spawn_id", "solo_start")
		CollectionService:AddTag(spawn, "corn_spawn")
		noCorn(zones, "StartClearing", Vector3.new(20, 10, 20), Vector3.new(0, 85, -500))
		local allSlots: { Part } = {}
		for row = 1, 5 do
			for column = 1, 3 do
				local id = string.format("solo_slot_%02d", #allSlots + 1)
				local slot = part(
					slots,
					id,
					Vector3.new(6, 0.12, 6),
					Vector3.new((column - 2) * 360, 80.06, (row - 3) * 180),
					Color3.fromRGB(119, 123, 87)
				)
				slot.CanCollide = false
				slot.CanTouch = false
				slot.CanQuery = false
				slot:SetAttribute("slot_id", id)
				CollectionService:AddTag(slot, "corn_key_slot")
				table.insert(allSlots, slot)
			end
		end
		for _, index in { 3, 8, 13 } do
			local barrel = part(
				props,
				"LookoutBarrel",
				Vector3.new(4, 3.2, 3.2),
				allSlots[index].Position + Vector3.new(4, 1.94, 0),
				Color3.fromRGB(111, 78, 48)
			)
			barrel.CFrame *= CFrame.Angles(0, 0, math.pi / 2)
			barrel.Shape = Enum.PartType.Cylinder
			barrel.Material = Enum.Material.Wood
			CollectionService:AddTag(barrel, "corn_barrel")
		end
		house(props, "HouseWest", Vector3.new(-180, 80, -190))
		house(props, "HouseEast", Vector3.new(210, 80, 120))
		house(props, "HouseNorthWest", Vector3.new(-420, 80, 240))
		local scarecrow = Instance.new("Model")
		scarecrow.Name = "ScarecrowMarker"
		scarecrow:SetAttribute("role", "visual_scarecrow_placeholder")
		scarecrow.Parent = props
		part(
			scarecrow,
			"Pole",
			Vector3.new(0.8, 20, 0.8),
			Vector3.new(12, 90, 12),
			Color3.fromRGB(77, 60, 42)
		)
		part(
			scarecrow,
			"Body",
			Vector3.new(4, 8, 2),
			Vector3.new(12, 94, 12),
			Color3.fromRGB(35, 39, 30)
		)
		part(
			scarecrow,
			"Arms",
			Vector3.new(14, 1, 1),
			Vector3.new(12, 97, 12),
			Color3.fromRGB(35, 39, 30)
		)
		part(
			scarecrow,
			"Head",
			Vector3.new(2.5, 2.5, 2.5),
			Vector3.new(12, 99.5, 12),
			Color3.fromRGB(89, 83, 54)
		)
		local gate = Instance.new("Model")
		gate.Name = "EscapeGate"
		gate:SetAttribute("gate_id", "solo_gate")
		gate.Parent = root
		CollectionService:AddTag(gate, "corn_gate")
		part(
			gate,
			"Door",
			Vector3.new(12, 18, 2),
			Vector3.new(0, 89, 601),
			Color3.fromRGB(114, 75, 49)
		).CanTouch =
			false
		zone(gate, "InteractionAnchor", Vector3.new(0.1, 0.1, 0.1), Vector3.new(0, 83, 599.7))
		local exit = zone(gate, "ExitZone", Vector3.new(12, 22, 8), Vector3.new(0, 91, 610))
		exit:SetAttribute("gate_id", "solo_gate")
		CollectionService:AddTag(exit, "corn_exit")
		noCorn(gate, "ApproachClearance", Vector3.new(20, 10, 28), Vector3.new(0, 85, 600))
		part(gate, "Header", Vector3.new(12, 2, 2), Vector3.new(0, 99, 601), wall)
		local apron = part(
			gate,
			"ExitGround",
			Vector3.new(20, 2, 20),
			Vector3.new(0, 79, 610),
			Color3.fromRGB(91, 97, 70)
		)
		apron.Material = Enum.Material.Ground
		gate.PrimaryPart = gate.Door :: BasePart
		root.Parent = Workspace
		MapAuthoring.EnsureCornerSpawns(root)
		MapAuthoring.RebuildOverview(root)
		local count = MapAuthoring.Preview(root, spawn.Position)
		root:SetAttribute("EditorCornCount", count)
		Selection:Set({ spawn })
	end)
	if not ok then
		root:Destroy()
		error(tostring(err))
	end
	print(
		"CornMap installed: 1200 x 1200 studs, 15 key slots, gate, 3 barrels, 3 decorative houses"
	)
	return root
end
return MapAuthoring
]========] },
{ path = [========[ServerScriptService/GameServer/Services/NetworkService]========], class = [========[ModuleScript]========], source = [========[--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkService = {
	Name = "NetworkService",
	Order = 10,
}

local root: Folder

function NetworkService:Init(_context: any)
	local existing = ReplicatedStorage:FindFirstChild("GameRemotes")
	if existing and not existing:IsA("Folder") then
		error("ReplicatedStorage.GameRemotes exists but is not a Folder")
	end
	if existing then
		root = existing
	else
		root = Instance.new("Folder")
		root.Name = "GameRemotes"
		root.Parent = ReplicatedStorage
	end
end

function NetworkService:GetEvent(name: string): RemoteEvent
	local existing = root:FindFirstChild(name)
	if existing then
		assert(existing:IsA("RemoteEvent"), string.format("%s is not a RemoteEvent", name))
		return existing
	end
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = root
	return event
end

function NetworkService:GetFunction(name: string): RemoteFunction
	local existing = root:FindFirstChild(name)
	if existing then
		assert(existing:IsA("RemoteFunction"), string.format("%s is not a RemoteFunction", name))
		return existing
	end
	local fn = Instance.new("RemoteFunction")
	fn.Name = name
	fn.Parent = root
	return fn
end

return NetworkService
]========] },
{ path = [========[ServerScriptService/GameServer/Services/TagService]========], class = [========[ModuleScript]========], source = [========[--!strict

local CollectionService = game:GetService("CollectionService")

local TagService = {
	Name = "TagService",
	Order = 20,
}

local connections: { RBXScriptConnection } = {}

function TagService:Bind(tag: string, onAdded: (Instance) -> (), onRemoved: ((Instance) -> ())?)
	for _, instance in CollectionService:GetTagged(tag) do
		task.spawn(onAdded, instance)
	end

	table.insert(connections, CollectionService:GetInstanceAddedSignal(tag):Connect(onAdded))
	if onRemoved then
		table.insert(
			connections,
			CollectionService:GetInstanceRemovedSignal(tag):Connect(onRemoved)
		)
	end
end

function TagService:Destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

return TagService
]========] },
{ path = [========[ServerScriptService/GameServer/Services/RoundService]========], class = [========[ModuleScript]========], source = [========[--!strict

local RunService = game:GetService("RunService")
local SoloRound = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("SoloRound"))

local RoundService = { Name = "RoundService", Order = 30 }
local runtime: any = nil

function RoundService:Init(context: any)
	if
		not RunService:IsStudio()
		or context.Config.Environment ~= "DEV"
		or context.Config.Game.SessionMode ~= "solo_local"
	then
		context.Log:Warn("Temporary solo prototype is available only in Studio DEV mode")
		return
	end
	runtime = SoloRound.new(context)
end

function RoundService:Start()
	if runtime then
		runtime:Start()
	end
end

return RoundService
]========] }
}
local updates = {
{ path = [========[ReplicatedStorage/GameShared/Config/GameConfig]========], class = [========[ModuleScript]========], source = [========[--!strict

local Balance = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("Balance"))

return {
	Environment = "DEV",
	Debug = true,
	Game = {
		Id = "children_of_corn",
		Name = "Дети кукурузы",
		Version = "0.1.0",
		SessionMode = "solo_local",
		SupportedDevice = "pc",
	},
	CoreLoop = Balance,
	Persistence = {
		Enabled = false,
		StoreName = "PlayerData_v1",
		SchemaVersion = 1,
	},
}
]========] },
{ path = [========[ReplicatedStorage/GameShared/Core/Logger]========], class = [========[ModuleScript]========], source = [========[--!strict

local Logger = {}
Logger.__index = Logger

function Logger.new(scope: string, debugEnabled: boolean?)
	return setmetatable({
		_scope = scope,
		_debug = debugEnabled == true,
	}, Logger)
end

function Logger:Info(...: any)
	print(string.format("[%s]", self._scope), ...)
end

function Logger:Warn(...: any)
	warn(string.format("[%s]", self._scope), ...)
end

function Logger:Debug(...: any)
	if self._debug then
		print(string.format("[%s][DEBUG]", self._scope), ...)
	end
end

return Logger
]========] },
{ path = [========[ReplicatedStorage/GameShared/Game/Balance]========], class = [========[ModuleScript]========], source = [========[--!strict

-- Baseline from docs/2026-10-09_core-loop_gd-spec.md, sections 11-12.
-- Field size is confirmed at 1200 x 1200; corn visibility still needs a Studio playtest.
return {
	target_round_min_sec = 420,
	target_round_max_sec = 600,
	hunt_start_delay_sec = 15,
	key_slot_count = 15,
	barrel_count = 3,
	max_catches = 2,
	stamina_capacity = 100,
	sprint_duration_sec = 4,
	stamina_refill_sec = 6,
	walk_speed = 12,
	sprint_speed = 18,
	monster_patrol_speed = 10,
	monster_chase_speed = 14,
	monster_detect_radius = 32,
	monster_lose_radius = 44,
	monster_lose_delay_sec = 1.5,
	monster_growl_radius = 72,
	monster_capture_radius = 3,
	capture_transition_sec = 1,
	respawn_protection_sec = 5,
	key_drop_adjust_radius = 6,
	interaction_radius = 4,
	escape_reward_diamonds = 10,
}
]========] },
{ path = [========[ReplicatedStorage/GameShared/Game/CornLayout]========], class = [========[ModuleScript]========], source = [========[--!strict

local CornLayout = {
	Height = 8,
	Spacing = 3,
	Seed = 817,
	ChunkCells = 12,
	RenderRadius = 85,
}

export type Plant = Model | BasePart
export type Box = { Frame: CFrame, HalfSize: Vector2 }
export type Circle = { Center: Vector3, Radius: number }
export type Exclusions = { Boxes: { Box }, Circles: { Circle }, Signature: string }

local SLOT_RADIUS = 6
local BOX_PADDING = 1.5

local function finite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

function CornLayout.Bounds(plant: Plant): (CFrame, Vector3)
	if plant:IsA("Model") then
		return plant:GetBoundingBox()
	end
	return plant.CFrame, plant.Size
end

function CornLayout.PrepareTemplate(source: Instance, height: number?): (Plant?, string?)
	if not source:IsA("Model") and not source:IsA("BasePart") then
		return nil, "Corn source must be a Model or BasePart"
	end
	local targetHeight = height or CornLayout.Height
	if not finite(targetHeight) or targetHeight <= 0 then
		return nil, "Corn height must be positive and finite"
	end
	local items = source:GetDescendants()
	table.insert(items, source)
	local partCount = 0
	for _, item in items do
		if item:IsA("LuaSourceContainer") then
			return nil, "Corn source contains code"
		end
		if
			item:IsA("Sound")
			or item:IsA("ParticleEmitter")
			or item:IsA("Beam")
			or item:IsA("Trail")
			or item:IsA("ProximityPrompt")
			or item:IsA("ClickDetector")
			or item:IsA("RemoteEvent")
			or item:IsA("RemoteFunction")
		then
			return nil, "Corn source must contain only static art"
		end
		if not item.Archivable then
			return nil, "Corn source has non-Archivable contents"
		end
		if item:IsA("BasePart") then
			partCount += 1
		end
	end
	if partCount == 0 then
		return nil, "Corn source has no BaseParts"
	end

	local prepared = source:Clone() :: Plant?
	if not prepared then
		return nil, "Corn source could not be cloned"
	end
	local ok, problem = pcall(function()
		local _, size = CornLayout.Bounds(prepared :: Plant)
		if not finite(size.Y) or size.Y <= 0 then
			error("Corn source has no usable height")
		end
		local ratio = targetHeight / size.Y
		if prepared:IsA("Model") then
			prepared:ScaleTo(prepared:GetScale() * ratio)
		else
			prepared.Size *= ratio
			for _, item in prepared:GetChildren() do
				if item:IsA("SpecialMesh") then
					item.Scale *= ratio
				end
			end
		end
		-- The imported plant has one mesh plus import poses/animation metadata.
		-- Keep only that normalized mesh on decorative copies; the source is untouched.
		if prepared:IsA("Model") and partCount == 1 then
			local mesh = prepared:FindFirstChildWhichIsA("MeshPart", true)
			if mesh and mesh:IsA("MeshPart") then
				mesh.Parent = nil
				prepared:Destroy()
				prepared = mesh
			end
		end
		for _, item in prepared:GetDescendants() do
			if
				item:IsA("AnimationController")
				or (item:IsA("Folder") and item.Name == "InitialPoses")
			then
				item:Destroy()
			end
		end
		local clones = prepared:GetDescendants()
		table.insert(clones, prepared)
		for _, item in clones do
			-- Art tags must not become gameplay bindings on every decorative clone.
			for _, tag in item:GetTags() do
				item:RemoveTag(tag)
			end
			if item:IsA("BasePart") then
				item.Anchored = true
				item.CanCollide = false
				item.CanTouch = false
				item.CanQuery = false
				item.CastShadow = false
				if item:IsA("MeshPart") then
					item.DoubleSided = true
				end
			end
		end
		prepared:PivotTo(CornLayout.PivotForPlant(prepared, Vector3.zero, 0))
	end)
	if not ok then
		prepared:Destroy()
		return nil, tostring(problem)
	end
	return prepared, nil
end

function CornLayout.PivotForPlant(plant: Plant, groundPosition: Vector3, yaw: number): CFrame
	local bounds, size = CornLayout.Bounds(plant)
	local boundsFromPivot = plant:GetPivot():ToObjectSpace(bounds)
	return CFrame.new(groundPosition + Vector3.new(0, size.Y / 2, 0))
		* CFrame.Angles(0, yaw, 0)
		* boundsFromPivot:Inverse()
end

function CornLayout.GetCellBounds(field: BasePart): (number, number, number, number)
	local half = field.Size / 2
	return math.ceil(-half.X / CornLayout.Spacing),
		math.floor(half.X / CornLayout.Spacing),
		math.ceil(-half.Z / CornLayout.Spacing),
		math.floor(half.Z / CornLayout.Spacing)
end

function CornLayout.CellPosition(field: BasePart, column: number, row: number): Vector3
	local half = field.Size / 2
	local hashX = (column * 92837111 + row * 689287499 + CornLayout.Seed) % 104729
	local hashZ = (column * 19349663 + row * 83492791 + CornLayout.Seed) % 104729
	local stagger = if row % 2 == 0 then -CornLayout.Spacing * 0.15 else CornLayout.Spacing * 0.15
	local x = column * CornLayout.Spacing
		+ stagger
		+ (hashX / 104729 - 0.5) * CornLayout.Spacing * 0.12
	local z = row * CornLayout.Spacing + (hashZ / 104729 - 0.5) * CornLayout.Spacing * 0.12
	return field.CFrame:PointToWorldSpace(
		Vector3.new(math.clamp(x, -half.X, half.X), -half.Y, math.clamp(z, -half.Z, half.Z))
	)
end

function CornLayout.CellYaw(column: number, row: number): number
	local hash = (column * 73856093 + row * 19349663 + CornLayout.Seed * 83492791) % 104729
	return hash / 104729 * math.pi * 2
end

local function footprint(frame: CFrame, size: Vector3, padding: number): Box
	local look = frame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local flat = CFrame.new(frame.Position) * CFrame.Angles(0, yaw, 0)
	local half = size / 2
	local right = flat.RightVector
	local forward = flat.LookVector
	local width = math.abs(right:Dot(frame.RightVector)) * half.X
		+ math.abs(right:Dot(frame.UpVector)) * half.Y
		+ math.abs(right:Dot(frame.LookVector)) * half.Z
	local depth = math.abs(forward:Dot(frame.RightVector)) * half.X
		+ math.abs(forward:Dot(frame.UpVector)) * half.Y
		+ math.abs(forward:Dot(frame.LookVector)) * half.Z
	return { Frame = flat, HalfSize = Vector2.new(width + padding, depth + padding) }
end

local function authorDescendants(map: Model): { Instance }
	local result: { Instance } = {}
	local stack = map:GetChildren()
	while #stack > 0 do
		local item = table.remove(stack)
		local owned = item:GetAttribute("corn_project_id") == "children_of_corn"
		local decoration = owned
			and (
				(item.Name == "EditorPreview" and item:GetAttribute("CornEditorPreview") == true)
				or (item.Name == "EditorFieldOverview" and item:GetAttribute("CornEditorOverview") == true)
				or (item.Name == "CornClientPlants" and item:GetAttribute("CornClientRendererOwned") == true)
				or item.Name == "CornRoundRuntime"
			)
		if decoration then
			continue
		end
		table.insert(result, item)
		for _, child in item:GetChildren() do
			table.insert(stack, child)
		end
	end
	return result
end
function CornLayout.ReadExclusions(map: Model, field: BasePart): Exclusions
	local boxes: { Box } = {}
	local circles: { Circle } = {}
	local signatures: { string } = { tostring(field.CFrame) .. "/" .. tostring(field.Size) }
	local included: { [Instance]: boolean } = {}
	local function addBox(part: BasePart, padding: number)
		if included[part] then
			return
		end
		included[part] = true
		table.insert(boxes, footprint(part.CFrame, part.Size, padding))
		table.insert(
			signatures,
			part:GetFullName()
				.. "/box/"
				.. tostring(part.CFrame)
				.. "/"
				.. tostring(part.Size)
				.. "/"
				.. padding
		)
	end
	for _, folderName in { "NoCornZones", "Props" } do
		local folder = map:FindFirstChild(folderName)
		if folder then
			for _, item in folder:GetDescendants() do
				if item:IsA("BasePart") then
					addBox(item, BOX_PADDING)
				end
			end
		end
	end
	for _, item in authorDescendants(map) do
		if item:IsA("BasePart") then
			if item:HasTag("corn_no_corn_zone") then
				addBox(item, BOX_PADDING)
			end
			if item:HasTag("corn_key_slot") then
				table.insert(circles, { Center = item.Position, Radius = SLOT_RADIUS })
				table.insert(signatures, item:GetFullName() .. "/slot/" .. tostring(item.Position))
			elseif item:HasTag("corn_spawn") then
				addBox(item, 4)
				table.insert(circles, { Center = item.Position, Radius = 10 })
				table.insert(signatures, item:GetFullName() .. "/spawn/" .. tostring(item.Position))
			end
		end
	end
	local gate = map:FindFirstChild("EscapeGate")
	if gate then
		local door = gate:FindFirstChild("Door", true)
		if door and door:IsA("BasePart") then
			addBox(door, 6)
		end
	end
	table.sort(signatures)
	return { Boxes = boxes, Circles = circles, Signature = table.concat(signatures, "|") }
end

function CornLayout.IsExcluded(position: Vector3, exclusions: Exclusions): boolean
	for _, circle in exclusions.Circles do
		local delta = position - circle.Center
		if delta.X * delta.X + delta.Z * delta.Z <= circle.Radius * circle.Radius then
			return true
		end
	end
	for _, box in exclusions.Boxes do
		local localPosition = box.Frame:PointToObjectSpace(position)
		if
			math.abs(localPosition.X) <= box.HalfSize.X
			and math.abs(localPosition.Z) <= box.HalfSize.Y
		then
			return true
		end
	end
	return false
end

return CornLayout
]========] },
{ path = [========[ReplicatedStorage/GameShared/Game/RoundText]========], class = [========[ModuleScript]========], source = [========[--!strict

-- Player-facing strings shared by the round and movement HUDs.
return table.freeze({
	corn_loop_title = "Дети кукурузы",
	corn_loop_start = "Начать",
	corn_loop_loading = "Подготовка раунда…",
	corn_loop_objective_search = "Найди ключ от ворот и сбеги",
	corn_loop_objective_return = "Ключ найден. Вернись к воротам",
	corn_loop_objective_exit = "Ворота открыты — беги наружу",
	corn_loop_need_key = "Нужен ключ",
	corn_loop_result_escape = "Ты сбежал",
	corn_loop_result_aborted = "Раунд завершён",
	corn_loop_reward = "+{count} алмазов",
	corn_loop_test_balance = "Алмазы в этом тесте: {count}",
	corn_loop_round_time = "Время раунда: {time}",
	corn_loop_retry = "Ещё раз",
	corn_loop_menu = "В меню",
	corn_loop_leave = "Завершить раунд",
	corn_loop_setup_error = "Не удалось подготовить раунд. Попробуй снова",
	corn_loop_connection_error = "Не удалось подключить интерфейс. Перезапусти тест Studio",
	corn_movement_stamina = "Выносливость {percent}%",
	corn_movement_controls = "Shift — спринт · Space — прыжок · Alt — курсор",
	corn_movement_exhausted = "Отпусти Shift, чтобы снова бежать",
	corn_movement_cursor = "Alt — вернуться к игре",
})
]========] },
{ path = [========[ReplicatedStorage/GameShared/Game/Stamina]========], class = [========[ModuleScript]========], source = [========[--!strict

-- Pure server-side resource rules. No client supplies stamina or elapsed time.
export type State = {
	value: number,
	intent: boolean,
	exhausted: boolean,
	sprinting: boolean,
	tokens: number,
	requestAt: number,
}

local Stamina = {}

function Stamina.new(capacity: number, now: number): State
	return {
		value = capacity,
		intent = false,
		exhausted = false,
		sprinting = false,
		tokens = 12,
		requestAt = now,
	}
end

function Stamina.Request(state: State, value: any, now: number, active: boolean): boolean
	if type(value) ~= "boolean" then
		return false
	end
	if not value then
		-- Release cannot be lost behind a rate limit or inactive phase.
		state.intent = false
		state.exhausted = false
		state.sprinting = false
		return true
	end
	if not active then
		return false
	end
	if state.intent then
		return true
	end
	state.tokens = math.min(12, state.tokens + math.max(0, now - state.requestAt) * 6)
	state.requestAt = now
	if state.tokens < 1 then
		return false
	end
	state.tokens -= 1
	state.intent = true
	return true
end

function Stamina.Step(state: State, dt: number, moving: boolean, active: boolean, balance: any)
	if not active then
		state.intent = false
		state.sprinting = false
		return
	end
	state.sprinting = state.intent and moving and not state.exhausted and state.value > 0
	if state.sprinting then
		state.value =
			math.max(0, state.value - balance.stamina_capacity / balance.sprint_duration_sec * dt)
		if state.value <= 0.000001 then
			state.value = 0
			state.exhausted = true
			state.sprinting = false
		end
	else
		state.value = math.min(
			balance.stamina_capacity,
			state.value + balance.stamina_capacity / balance.stamina_refill_sec * dt
		)
	end
end

return Stamina
]========] },
{ path = [========[ReplicatedStorage/GameShared/Network/EndpointNames]========], class = [========[ModuleScript]========], source = [========[--!strict

return {
	RequestRoundAction = "request_round_action",
	RoundSnapshot = "round_snapshot",
	RequestSprintIntent = "request_sprint_intent",
}
]========] },
{ path = [========[ServerScriptService/GameServer/Bootstrap]========], class = [========[Script]========], source = [========[--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameShared = ReplicatedStorage:WaitForChild("GameShared")
local Config = require(GameShared:WaitForChild("Config"):WaitForChild("GameConfig"))
local Workspace = game:GetService("Workspace")
local map = Workspace:WaitForChild("CornMap", 10)
if
	not map
	or map:GetAttribute("corn_project_id") ~= "children_of_corn"
	or Workspace:FindFirstChild("Asmr_Base")
	or Workspace:FindFirstChild("ASMR_Models")
then
	warn("[ChildrenOfCorn] Inactive: editable CornMap missing or another game detected")
	return
end
local Logger = require(GameShared:WaitForChild("Core"):WaitForChild("Logger"))
local log = Logger.new("ServerBootstrap", Config.Debug)

local servicesFolder = script.Parent:WaitForChild("Services")

type RuntimeModule = {
	Name: string?,
	Order: number?,
	Init: ((self: RuntimeModule, context: any) -> ())?,
	Start: ((self: RuntimeModule, context: any) -> ())?,
}

local loaded: { RuntimeModule } = {}
local byName: { [string]: RuntimeModule } = {}

for _, child in servicesFolder:GetChildren() do
	if child:IsA("ModuleScript") then
		local ok, result = pcall(require, child)
		if not ok then
			error(
				string.format(
					"Failed to require service %s: %s",
					child:GetFullName(),
					tostring(result)
				)
			)
		end
		if type(result) ~= "table" then
			error(string.format("Service %s must return a table", child:GetFullName()))
		end
		local module = result :: RuntimeModule
		local name = module.Name or child.Name
		if byName[name] then
			error(string.format("Duplicate service name: %s", name))
		end
		module.Name = name
		byName[name] = module
		table.insert(loaded, module)
	end
end

table.sort(loaded, function(a, b)
	return (a.Order or 100) < (b.Order or 100)
end)

local context = {
	Config = Config,
	Services = byName,
	Log = Logger.new("Server", Config.Debug),
}

for _, module in loaded do
	if module.Init then
		module:Init(context)
	end
end

for _, module in loaded do
	if module.Start then
		module:Start(context)
	end
end

log:Info(string.format("Started %d services", #loaded))
]========] },
{ path = [========[ServerScriptService/GameServer/Game/AuthoredWorld]========], class = [========[ModuleScript]========], source = [========[--!strict
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local CornField = require(script.Parent:WaitForChild("CornField"))
local AuthoredWorld = {}
AuthoredWorld.__index = AuthoredWorld

local function namedPart(parent: Instance, name: string): BasePart
	local item = parent:FindFirstChild(name)
	assert(item and item:IsA("BasePart"), "Missing map part: " .. name)
	return item
end

local function hasTag(item: Instance, tag: string): boolean
	return CollectionService:HasTag(item, tag)
end

local function prompt(
	parent: Instance,
	name: string,
	action: string,
	object: string,
	radius: number
): ProximityPrompt
	assert(not parent:FindFirstChild(name), "Duplicate owned prompt: " .. name)
	local item = Instance.new("ProximityPrompt")
	item.Name = name
	item.ActionText = action
	item.ObjectText = object
	item.KeyboardKeyCode = Enum.KeyCode.E
	item.MaxActivationDistance = radius
	item.RequiresLineOfSight = true
	item.HoldDuration = 0
	item.Enabled = false
	item.Parent = parent
	return item
end

local function inBox(part: BasePart, position: Vector3): boolean
	local point = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(point.X) <= half.X
		and math.abs(point.Y) <= half.Y
		and math.abs(point.Z) <= half.Z
end

local function validateSpawn(root: Model, spawn: BasePart, bounds: BasePart)
	assert(spawn:IsDescendantOf(root), "Spawn must belong to CornMap")
	assert(hasTag(spawn, "corn_spawn"), "Missing corn_spawn tag: " .. spawn.Name)
	local id = spawn:GetAttribute("spawn_id")
	assert(type(id) == "string" and id ~= "", "Spawn id must be a nonempty string: " .. spawn.Name)
	assert(spawn.Anchored, "Spawn must be Anchored: " .. spawn.Name)
	assert(
		spawn.CFrame.UpVector:Dot(Vector3.yAxis) > 0.999,
		"Spawn must remain horizontal: " .. spawn.Name
	)
	if spawn:IsA("SpawnLocation") then
		assert(
			spawn.Enabled and spawn.Neutral,
			"Corner spawn must be enabled and neutral: " .. spawn.Name
		)
	end
	local position = (spawn.CFrame * CFrame.new(0, spawn.Size.Y / 2 + 3.5, 0)).Position
	assert(inBox(bounds, position), "Spawn is outside PlayBounds: " .. spawn.Name)
end

function AuthoredWorld.IsSafeSpawn(root: Model, spawn: BasePart): boolean
	local bounds = root:FindFirstChild("PlayBounds")
	return bounds ~= nil and bounds:IsA("BasePart") and pcall(validateSpawn, root, spawn, bounds)
end

function AuthoredWorld.ReadSpawns(root: Model): { BasePart }
	local bounds = namedPart(root, "PlayBounds")
	local corners = root:FindFirstChild("CornerSpawns")
	local spawns: { BasePart } = {}
	if corners then
		assert(
			corners:IsA("Folder")
				and corners:GetAttribute("CornCornerSpawnsOwned") == true
				and corners:GetAttribute("corn_project_id") == "children_of_corn",
			"Unrecognized CornerSpawns"
		)
		local seen: { [string]: boolean } = {}
		for _, item in corners:GetChildren() do
			assert(item:IsA("SpawnLocation"), "CornerSpawns must contain only SpawnLocations")
			validateSpawn(root, item, bounds)
			local id = item:GetAttribute("spawn_id") :: string
			assert(not seen[id], "Corner spawn ids must be unique")
			seen[id] = true
			table.insert(spawns, item)
		end
		assert(#spawns == 4, "CornMap must have four corner spawns")
		table.sort(spawns, function(a, b)
			return tostring(a:GetAttribute("spawn_id")) < tostring(b:GetAttribute("spawn_id"))
		end)
	else
		local legacy = namedPart(root, "RoundSpawn")
		validateSpawn(root, legacy, bounds)
		table.insert(spawns, legacy)
	end
	return spawns
end

-- A broken gate or slot must not leave the menu character underneath the map.
function AuthoredWorld.FindSafeSpawn(root: Model): BasePart?
	local bounds = root:FindFirstChild("PlayBounds")
	if not bounds or not bounds:IsA("BasePart") then
		return nil
	end
	local candidates: { BasePart } = {}
	local corners = root:FindFirstChild("CornerSpawns")
	if
		corners
		and corners:IsA("Folder")
		and corners:GetAttribute("CornCornerSpawnsOwned") == true
		and corners:GetAttribute("corn_project_id") == "children_of_corn"
	then
		for _, item in corners:GetChildren() do
			if item:IsA("SpawnLocation") and pcall(validateSpawn, root, item, bounds) then
				table.insert(candidates, item)
			end
		end
	end
	table.sort(candidates, function(a, b)
		return tostring(a:GetAttribute("spawn_id")) < tostring(b:GetAttribute("spawn_id"))
	end)
	if candidates[1] then
		return candidates[1]
	end
	local legacy = root:FindFirstChild("RoundSpawn")
	if legacy and legacy:IsA("BasePart") and pcall(validateSpawn, root, legacy, bounds) then
		return legacy
	end
	return nil
end

function AuthoredWorld.SpawnCFrame(spawn: BasePart): CFrame
	return spawn.CFrame * CFrame.new(0, spawn.Size.Y / 2 + 3.5, 0)
end

function AuthoredWorld.new(radius: number, expectedSlots: number)
	local root = Workspace:FindFirstChild("CornMap")
	assert(
		root and root:IsA("Model") and root:GetAttribute("corn_project_id") == "children_of_corn",
		"Install the editable CornMap in Children_of_corn before Test"
	)
	local spawns = AuthoredWorld.ReadSpawns(root)
	local field = namedPart(root, "FieldZone")
	local bounds = namedPart(root, "PlayBounds")
	local gateModel = root:FindFirstChild("EscapeGate")
	assert(
		gateModel and gateModel:IsA("Model") and hasTag(gateModel, "corn_gate"),
		"Missing tagged EscapeGate"
	)
	local gate = namedPart(gateModel, "Door")
	local anchor = namedPart(gateModel, "InteractionAnchor")
	local exit = namedPart(gateModel, "ExitZone")
	assert(hasTag(exit, "corn_exit"), "Missing corn_exit tag")
	local gateId = gateModel:GetAttribute("gate_id")
	assert(type(gateId) == "string" and gateId ~= "", "Gate id must be a nonempty string")
	assert(exit:GetAttribute("gate_id") == gateId, "Gate/exit identity mismatch")
	local slots: { BasePart } = {}
	local seen: { [string]: boolean } = {}
	for _, item in root:GetDescendants() do
		if item:IsA("BasePart") and hasTag(item, "corn_key_slot") then
			local id = item:GetAttribute("slot_id")
			assert(
				type(id) == "string" and id ~= "" and not seen[id],
				"Key slot ids must be unique strings"
			)
			seen[id] = true
			table.insert(slots, item)
		end
	end
	assert(#slots == expectedSlots, "CornMap must have " .. tostring(expectedSlots) .. " key slots")
	table.sort(slots, function(a, b)
		return tostring(a:GetAttribute("slot_id")) < tostring(b:GetAttribute("slot_id"))
	end)
	assert(not root:FindFirstChild("CornRoundRuntime"), "CornRoundRuntime already exists")
	assert(not anchor:FindFirstChild("CornGatePrompt"), "CornGatePrompt already exists")
	assert(gate.CanCollide, "Closed Door must have CanCollide enabled")
	local artOk, artReady = pcall(CornField.Prepare)
	if not artOk or not artReady then
		warn("[AuthoredWorld] Corn art unavailable:", artReady)
	end
	local runtime = Instance.new("Folder")
	runtime.Name = "CornRoundRuntime"
	runtime:SetAttribute("corn_project_id", "children_of_corn")
	runtime.Parent = root
	local gatePrompt = prompt(anchor, "CornGatePrompt", "Открыть", "Ворота", radius)
	local self = setmetatable({
		Root = root,
		Radius = radius,
		Slots = slots,
		Spawns = spawns,
		Spawn = spawns[1],
		Field = field,
		Bounds = bounds,
		GateModel = gateModel,
		Gate = gate,
		GateAnchor = anchor,
		Exit = exit,
		Runtime = runtime,
		GatePrompt = gatePrompt,
		ClosedTransparency = gate.Transparency,
		ClosedCollision = gate.CanCollide,
		ClosedQuery = gate.CanQuery,
		Key = nil :: Part?,
		KeyPrompt = nil :: ProximityPrompt?,
	}, AuthoredWorld)
	return self
end

function AuthoredWorld:SelectSpawn(index: number): BasePart
	assert(index % 1 == 0 and index >= 1 and index <= #self.Spawns, "Invalid spawn index")
	local spawn = self.Spawns[index]
	validateSpawn(self.Root, spawn, self.Bounds)
	self.Spawn = spawn
	return spawn
end

function AuthoredWorld:GetSpawnCFrame(): CFrame
	validateSpawn(self.Root, self.Spawn, self.Bounds)
	return AuthoredWorld.SpawnCFrame(self.Spawn)
end

function AuthoredWorld:ClearKey()
	if self.Key then
		self.Key:Destroy()
	end
	self.Key = nil
	self.KeyPrompt = nil
end

function AuthoredWorld:SpawnKey(slot: BasePart): ProximityPrompt
	assert(slot:IsDescendantOf(self.Root), "Key slot must belong to CornMap")
	self:ClearKey()
	local key = Instance.new("Part")
	key.Name = "GateKey"
	key.Size = Vector3.new(1.5, 0.4, 3)
	key.CFrame = slot.CFrame * CFrame.new(0, slot.Size.Y / 2 + 0.3, 0)
	key.Anchored = true
	key.Color = Color3.fromRGB(240, 198, 69)
	key.Material = Enum.Material.Metal
	key.CanCollide = false
	key.CanTouch = false
	key.Parent = self.Runtime
	self.Key = key
	self.KeyPrompt =
		prompt(key, "CornKeyPrompt", "Подобрать", "Ключ от ворот", self.Radius)
	return self.KeyPrompt
end

function AuthoredWorld:SetGateOpen(open: boolean)
	self.Gate.CanCollide = if open then false else self.ClosedCollision
	self.Gate.CanQuery = if open then false else self.ClosedQuery
	self.Gate.Transparency = if open then 1 else self.ClosedTransparency
	self.GatePrompt.Enabled = false
	self.Runtime:SetAttribute("GateOpen", open)
end

function AuthoredWorld:SetInteractionEnabled(enabled: boolean, gateOpen: boolean)
	self.GatePrompt.Enabled = enabled and not gateOpen
	if self.KeyPrompt then
		self.KeyPrompt.Enabled = enabled
	end
end

function AuthoredWorld:IsGateFront(position: Vector3): boolean
	local anchor = self.Gate.CFrame:PointToObjectSpace(self.GateAnchor.Position)
	local point = self.Gate.CFrame:PointToObjectSpace(position)
	local frontSign = if anchor.Z < 0 then -1 else 1
	return point.Z * frontSign > self.Gate.Size.Z / 2
end

function AuthoredWorld:IsInExit(position: Vector3): boolean
	return inBox(self.Exit, position)
end

function AuthoredWorld:IsOnPlayground(position: Vector3): boolean
	return inBox(self.Bounds, position)
end

function AuthoredWorld:IsValid(): boolean
	if
		self.Root.Parent ~= Workspace
		or not self.Runtime:IsDescendantOf(self.Root)
		or not self.Spawn:IsDescendantOf(self.Root)
		or not self.Field:IsDescendantOf(self.Root)
		or not self.Bounds:IsDescendantOf(self.Root)
		or not self.Gate:IsDescendantOf(self.Root)
		or not self.GateAnchor:IsDescendantOf(self.Root)
		or not self.Exit:IsDescendantOf(self.Root)
		or not self.GatePrompt:IsDescendantOf(self.GateAnchor)
		or #self.Slots ~= 15
	then
		return false
	end
	local spawnIds: { [string]: boolean } = {}
	for _, spawn in self.Spawns do
		if not pcall(validateSpawn, self.Root, spawn, self.Bounds) then
			return false
		end
		local id = spawn:GetAttribute("spawn_id") :: string
		if spawnIds[id] then
			return false
		end
		spawnIds[id] = true
	end
	local gateId = self.GateModel:GetAttribute("gate_id")
	if type(gateId) ~= "string" or gateId == "" or gateId ~= self.Exit:GetAttribute("gate_id") then
		return false
	end
	for _, slot in self.Slots do
		if not slot:IsDescendantOf(self.Root) then
			return false
		end
	end
	return true
end

return AuthoredWorld
]========] },
{ path = [========[ServerScriptService/GameServer/Game/CornField]========], class = [========[ModuleScript]========], source = [========[--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local GameShared = ReplicatedStorage:WaitForChild("GameShared")
local Config = require(GameShared:WaitForChild("Config"):WaitForChild("GameConfig"))
local CornLayout = require(GameShared:WaitForChild("Game"):WaitForChild("CornLayout"))

local CornField = {}
local PROJECT_ID = "children_of_corn"
local OWNER_ATTRIBUTE = "CornRuntimeArtOwned"

function CornField.Prepare(): boolean
	if
		not RunService:IsStudio()
		or Config.Environment ~= "DEV"
		or Config.Game.SessionMode ~= "solo_local"
	then
		return false
	end
	local sources: { Instance } = {}
	for _, item in ServerStorage:GetChildren() do
		if item.Name == "CornPlantTemplate" or item.Name == "SM_Prop_Plant_Corn_01_L" then
			table.insert(sources, item)
		end
	end
	if #sources ~= 1 then
		warn(
			"[CornField] Expected exactly one ServerStorage CornPlantTemplate or SM_Prop_Plant_Corn_01_L art source"
		)
		return false
	end
	local prepared, problem = CornLayout.PrepareTemplate(sources[1])
	if not prepared then
		warn("[CornField] " .. (problem or "Could not prepare corn art"))
		return false
	end
	local folder: Instance? = nil
	for _, item in ReplicatedStorage:GetChildren() do
		if item.Name == "CornRuntimeArt" then
			if folder then
				prepared:Destroy()
				warn(
					"[CornField] Duplicate CornRuntimeArt containers; existing contents were preserved"
				)
				return false
			end
			folder = item
		end
	end
	if
		folder
		and (
			not folder:IsA("Folder")
			or folder:GetAttribute(OWNER_ATTRIBUTE) ~= true
			or folder:GetAttribute("corn_project_id") ~= PROJECT_ID
		)
	then
		prepared:Destroy()
		warn("[CornField] Refused to overwrite an unowned CornRuntimeArt container")
		return false
	end
	if folder then
		for _, item in folder:GetChildren() do
			if
				item.Name == "CornPlantTemplate"
				and item:GetAttribute("CornPlantTemplateOwned") ~= true
			then
				prepared:Destroy()
				warn("[CornField] Refused to overwrite unowned CornPlantTemplate art")
				return false
			end
		end
	else
		folder = Instance.new("Folder")
		folder.Name = "CornRuntimeArt"
		folder:SetAttribute(OWNER_ATTRIBUTE, true)
		folder:SetAttribute("corn_project_id", PROJECT_ID)
	end
	prepared.Name = "CornPlantTemplate"
	prepared:SetAttribute("CornPlantTemplateOwned", true)
	prepared:SetAttribute("CornPlantHeight", CornLayout.Height)
	for _, item in folder:GetChildren() do
		if
			item.Name == "CornPlantTemplate"
			and item:GetAttribute("CornPlantTemplateOwned") == true
		then
			item:Destroy()
		end
	end
	prepared.Parent = folder
	folder.Parent = ReplicatedStorage
	print("[CornField] Prepared a corn art clone; ServerStorage source is unchanged")
	return true
end

return CornField
]========] },
{ path = [========[ServerScriptService/GameServer/Game/MapAuthoring]========], class = [========[ModuleScript]========], source = [========[--!strict
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local Layout = require(
	ReplicatedStorage:WaitForChild("GameShared"):WaitForChild("Game"):WaitForChild("CornLayout")
)
local MapAuthoring = {}

local function guard()
	assert(
		RunService:IsStudio() and not RunService:IsRunning(),
		"Use the Command Bar in Studio Edit mode"
	)
	assert(
		not Workspace:FindFirstChild("Asmr_Base") and not Workspace:FindFirstChild("ASMR_Models"),
		"Speed Monkey scene detected; Corn installation refused"
	)
	local config = ReplicatedStorage:FindFirstChild("GameShared")
	config = config and config:FindFirstChild("Config")
	local module = config and config:FindFirstChild("GameConfig")
	assert(
		module
			and module:IsA("ModuleScript")
			and string.find(module.Source, 'Id = "children_of_corn"', 1, true),
		"Open the Children_of_corn project"
	)
end

local function artSource(): Instance
	local first = ServerStorage:FindFirstChild("CornPlantTemplate")
	local imported = ServerStorage:FindFirstChild("SM_Prop_Plant_Corn_01_L")
	assert(not (first and imported), "Keep one unambiguous corn source in ServerStorage")
	local source = first or imported
	assert(source, "Imported corn asset missing from ServerStorage")
	return source
end

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3
): Part
	local item = Instance.new("Part")
	item.Name = name
	item.Anchored = true
	item.Size = size
	item.Position = position
	item.Color = color
	item.TopSurface = Enum.SurfaceType.Smooth
	item.BottomSurface = Enum.SurfaceType.Smooth
	item.Parent = parent
	return item
end

local function zone(parent: Instance, name: string, size: Vector3, position: Vector3): Part
	local item = part(parent, name, size, position, Color3.fromRGB(123, 175, 113))
	item.Transparency = 1
	item.CanCollide = false
	item.CanTouch = false
	item.CanQuery = false
	return item
end

local function noCorn(parent: Instance, name: string, size: Vector3, position: Vector3): Part
	local item = zone(parent, name, size, position)
	CollectionService:AddTag(item, "corn_no_corn_zone")
	return item
end

local function house(parent: Instance, name: string, origin: Vector3)
	local root = Instance.new("Model")
	root.Name = name
	root.Parent = parent
	local walls = part(
		root,
		"Body",
		Vector3.new(20, 12, 24),
		origin + Vector3.new(0, 6, 0),
		Color3.fromRGB(95, 84, 62)
	)
	walls.Material = Enum.Material.WoodPlanks
	local door = part(
		root,
		"DecorativeDoor",
		Vector3.new(4, 7, 0.25),
		origin + Vector3.new(0, 3.5, -12.1),
		Color3.fromRGB(58, 45, 33)
	)
	door.Material = Enum.Material.Wood
	for _, side in { -1, 1 } do
		local roof = part(
			root,
			"Roof",
			Vector3.new(12, 1, 26),
			origin + Vector3.new(side * 5, 14, 0),
			Color3.fromRGB(54, 57, 49)
		)
		roof.CFrame *= CFrame.Angles(0, 0, -side * math.pi / 8)
		roof.Material = Enum.Material.Slate
	end
end

function MapAuthoring.EnsureCornerSpawns(map: Model): Folder
	guard()
	assert(
		map.Parent == Workspace and map:GetAttribute("corn_project_id") == "children_of_corn",
		"Corner spawns require the correct editable CornMap"
	)
	local field = map:FindFirstChild("FieldZone")
	local bounds = map:FindFirstChild("PlayBounds")
	assert(
		field and field:IsA("BasePart") and bounds and bounds:IsA("BasePart"),
		"FieldZone/PlayBounds missing"
	)
	assert(field.CFrame.UpVector:Dot(Vector3.yAxis) > 0.999, "FieldZone must remain horizontal")
	assert(field.Size.X > 100 and field.Size.Z > 100, "FieldZone is too small for corner starts")
	local entries = {
		{ Name = "SW", Id = "solo_corner_sw", X = -1, Z = -1 },
		{ Name = "SE", Id = "solo_corner_se", X = 1, Z = -1 },
		{ Name = "NW", Id = "solo_corner_nw", X = -1, Z = 1 },
		{ Name = "NE", Id = "solo_corner_ne", X = 1, Z = 1 },
	}
	local old = map:FindFirstChild("CornerSpawns")
	if old then
		assert(
			old:IsA("Folder")
				and old:GetAttribute("CornCornerSpawnsOwned") == true
				and old:GetAttribute("corn_project_id") == "children_of_corn",
			"Unrecognized CornerSpawns; not replaced"
		)
		assert(#old:GetChildren() == 4, "CornerSpawns must contain exactly four owned starts")
		for _, entry in entries do
			local item = old:FindFirstChild(entry.Name)
			assert(
				item
					and item:IsA("SpawnLocation")
					and item:GetAttribute("spawn_id") == entry.Id
					and item:GetAttribute("CornCornerSpawnOwned") == true
					and item:GetAttribute("corn_project_id") == "children_of_corn"
					and CollectionService:HasTag(item, "corn_spawn")
					and item.Enabled
					and item.Neutral,
				"Unknown or invalid corner start: " .. entry.Name
			)
			local position = bounds.CFrame:PointToObjectSpace(
				(item.CFrame * CFrame.new(0, item.Size.Y / 2 + 3.5, 0)).Position
			)
			local half = bounds.Size / 2
			assert(
				math.abs(position.X) <= half.X
					and math.abs(position.Y) <= half.Y
					and math.abs(position.Z) <= half.Z
					and item.Anchored
					and item.CFrame.UpVector:Dot(Vector3.yAxis) > 0.999,
				"Corner start is unsafe: " .. entry.Name
			)
		end
		return old
	end
	local folder = Instance.new("Folder")
	folder.Name = "CornerSpawns"
	folder:SetAttribute("CornCornerSpawnsOwned", true)
	folder:SetAttribute("corn_project_id", "children_of_corn")
	local ok, problem = pcall(function()
		for _, entry in entries do
			local localPosition = Vector3.new(
				entry.X * (field.Size.X / 2 - 50),
				-field.Size.Y / 2 + 0.075,
				entry.Z * (field.Size.Z / 2 - 50)
			)
			local position = field.CFrame:PointToWorldSpace(localPosition)
			local center = Vector3.new(field.Position.X, position.Y, field.Position.Z)
			local item = Instance.new("SpawnLocation")
			item.Parent = folder
			item.Name = entry.Name
			item.Size = Vector3.new(6, 0.15, 6)
			item.CFrame = CFrame.lookAt(position, center)
			item.Anchored = true
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = false
			item.Neutral = true
			item.Enabled = true
			item.AllowTeamChangeOnTouch = false
			item.Duration = 0
			item.Color = Color3.fromRGB(158, 176, 150)
			item:SetAttribute("spawn_id", entry.Id)
			item:SetAttribute("CornCornerSpawnOwned", true)
			item:SetAttribute("corn_project_id", "children_of_corn")
			CollectionService:AddTag(item, "corn_spawn")
			local candidate = bounds.CFrame:PointToObjectSpace(
				(item.CFrame * CFrame.new(0, item.Size.Y / 2 + 3.5, 0)).Position
			)
			local half = bounds.Size / 2
			assert(
				math.abs(candidate.X) <= half.X
					and math.abs(candidate.Y) <= half.Y
					and math.abs(candidate.Z) <= half.Z,
				"Corner start is outside PlayBounds"
			)
			item.Parent = folder
		end
	end)
	if not ok then
		folder:Destroy()
		error(tostring(problem))
	end
	folder.Parent = map
	return folder
end

function MapAuthoring.Preview(map: Model, center: Vector3, radius: number?): number
	guard()
	local field = map:FindFirstChild("FieldZone")
	assert(field and field:IsA("BasePart"), "CornMap FieldZone missing")
	local old = map:FindFirstChild("EditorPreview")
	assert(
		not old
			or (
				old:IsA("Folder")
				and old:GetAttribute("CornEditorPreview") == true
				and old:GetAttribute("corn_project_id") == "children_of_corn"
			),
		"Unrecognized EditorPreview; not replaced"
	)
	local prepared, problem = Layout.PrepareTemplate(artSource())
	assert(prepared, problem or "Cannot prepare corn preview")
	local folder = Instance.new("Folder")
	folder.Name = "EditorPreview"
	folder:SetAttribute("CornEditorPreview", true)
	folder:SetAttribute("corn_project_id", "children_of_corn")
	local distance = math.clamp(radius or 55, 10, 85)
	local localCenter = field.CFrame:PointToObjectSpace(center)
	local minColumn, maxColumn, minRow, maxRow = Layout.GetCellBounds(field)
	minColumn = math.max(minColumn, math.ceil((localCenter.X - distance) / Layout.Spacing))
	maxColumn = math.min(maxColumn, math.floor((localCenter.X + distance) / Layout.Spacing))
	minRow = math.max(minRow, math.ceil((localCenter.Z - distance) / Layout.Spacing))
	maxRow = math.min(maxRow, math.floor((localCenter.Z + distance) / Layout.Spacing))
	local exclusions = Layout.ReadExclusions(map, field)
	local _, fieldYaw = field.CFrame:ToOrientation()
	local count = 0
	local ok, err = pcall(function()
		for row = minRow, maxRow do
			for column = minColumn, maxColumn do
				local position = Layout.CellPosition(field, column, row)
				local delta = position - center
				if
					Vector2.new(delta.X, delta.Z).Magnitude <= distance
					and not Layout.IsExcluded(position, exclusions)
				then
					local clone = prepared:Clone()
					assert(clone, "Corn clone is not Archivable")
					clone.Name = "Corn"
					clone:PivotTo(
						Layout.PivotForPlant(
							prepared,
							position,
							Layout.CellYaw(column, row) + fieldYaw
						)
					)
					clone.Parent = folder
					count += 1
				end
			end
		end
	end)
	prepared:Destroy()
	if not ok then
		folder:Destroy()
		error(tostring(err))
	end
	if old then
		old:Destroy()
	end
	folder.Parent = map
	folder:SetAttribute("PlantCount", count)
	return count
end

-- Whole-map coarse corn for authoring and distant view; fine plants stay local.
function MapAuthoring.RebuildOverview(map: Model): number
	guard()
	assert(
		map.Parent == Workspace and map:GetAttribute("corn_project_id") == "children_of_corn",
		"CornMap missing"
	)
	local field = map:FindFirstChild("FieldZone")
	assert(field and field:IsA("BasePart"), "FieldZone missing")
	assert(field.CFrame.UpVector:Dot(Vector3.yAxis) > 0.9999, "FieldZone must stay horizontal")
	local old = map:FindFirstChild("EditorFieldOverview")
	if old then
		assert(
			old:IsA("Folder")
				and old:GetAttribute("CornEditorOverview") == true
				and old:GetAttribute("corn_project_id") == "children_of_corn",
			"Unrecognized overview; retained"
		)
		for _, item in old:GetChildren() do
			assert(
				item:IsA("BasePart")
					and item:GetAttribute("CornEditorOverview") == true
					and item:GetAttribute("corn_project_id") == "children_of_corn",
				"Overview contains manual objects; retained"
			)
		end
	end
	local prepared, problem = Layout.PrepareTemplate(artSource())
	assert(prepared, problem or "Cannot prepare overview art")
	assert(prepared:IsA("MeshPart"), "Whole-field overview requires the imported single-mesh corn")
	local stride = 16
	-- Preserve plant proportions. This sparse layer is an approximate field overview,
	-- while EditorPreview and the client renderer provide dense, life-size plants.
	local _, preparedSize = Layout.Bounds(prepared)
	local half = preparedSize / 2
	local folder = Instance.new("Folder")
	folder.Name = "EditorFieldOverview"
	folder:SetAttribute("CornEditorOverview", true)
	folder:SetAttribute("corn_project_id", "children_of_corn")
	folder:SetAttribute("OverviewSpacing", stride)
	folder:SetAttribute("OverviewApproximation", true)
	folder:SetAttribute("OverviewPlantScale", 1)
	local exclusions = Layout.ReadExclusions(map, field)
	local _, yaw = field.CFrame:ToOrientation()
	local count = 0
	local ok, err = pcall(function()
		for row = math.ceil(-field.Size.Z / 2 / stride), math.floor(field.Size.Z / 2 / stride) do
			for column = math.ceil(-field.Size.X / 2 / stride), math.floor(field.Size.X / 2 / stride) do
				local ground = field.CFrame:PointToWorldSpace(
					Vector3.new(column * stride, -field.Size.Y / 2, row * stride)
				)
				local excluded = false
				for _, x in { -1, 0, 1 } do
					for _, z in { -1, 0, 1 } do
						local sample = ground
							+ field.CFrame:VectorToWorldSpace(
								Vector3.new(x * half.X, 0, z * half.Z)
							)
						if Layout.IsExcluded(sample, exclusions) then
							excluded = true
							break
						end
					end
					if excluded then
						break
					end
				end
				if excluded then
					continue
				end
				local clone = prepared:Clone()
				assert(clone, "Overview clone failed")
				clone.Name = "DistantCorn"
				clone:SetAttribute("CornEditorOverview", true)
				clone:SetAttribute("corn_project_id", "children_of_corn")
				clone:PivotTo(Layout.PivotForPlant(prepared, ground, yaw))
				clone.Parent = folder
				count += 1
				if count % 128 == 0 then
					task.wait()
				end
			end
		end
	end)
	prepared:Destroy()
	if not ok then
		folder:Destroy()
		error(tostring(err))
	end
	if old then
		old:Destroy()
	end
	folder:SetAttribute("PlantCount", count)
	folder.Parent = map
	print(
		"CornMap whole-field overview:",
		count,
		"upright sparse overview meshes; fine corn uses 3-stud spacing"
	)
	return count
end

function MapAuthoring.PreviewAtSelection(): number
	guard()
	local map = Workspace:FindFirstChild("CornMap")
	assert(
		map and map:IsA("Model") and map:GetAttribute("corn_project_id") == "children_of_corn",
		"CornMap missing"
	)
	local spawn: Instance? = map:FindFirstChild("RoundSpawn")
	if not spawn then
		local corners = map:FindFirstChild("CornerSpawns")
		spawn = corners and corners:FindFirstChild("SW")
	end
	assert(spawn and spawn:IsA("BasePart"), "CornMap has no preview start")
	local center = spawn.Position
	local selected = Selection:Get()[1]
	if selected and (selected:IsA("Model") or selected:IsA("BasePart")) then
		center = selected:GetPivot().Position
	end
	local count = MapAuthoring.Preview(map, center)
	print("CornMap editor preview:", count, "plants near selection")
	return count
end

function MapAuthoring.Install(): Model
	guard()
	assert(not Workspace:FindFirstChild("CornMap"), "CornMap already exists; manual edits retained")
	local testClone, problem = Layout.PrepareTemplate(artSource())
	assert(testClone, problem or "Corn art preparation failed")
	testClone:Destroy()
	local root = Instance.new("Model")
	root.Name = "CornMap"
	root:SetAttribute("corn_project_id", "children_of_corn")
	root:SetAttribute("map_version", 1)
	local ok, err = pcall(function()
		local ground = part(
			root,
			"Ground",
			Vector3.new(1200, 2, 1200),
			Vector3.new(0, 79, 0),
			Color3.fromRGB(91, 97, 70)
		)
		ground.Material = Enum.Material.Ground
		local field = zone(root, "FieldZone", Vector3.new(1200, 10, 1200), Vector3.new(0, 85, 0))
		CollectionService:AddTag(field, "corn_field_zone")
		local bounds = zone(root, "PlayBounds", Vector3.new(1200, 50, 1240), Vector3.new(0, 100, 0))
		CollectionService:AddTag(bounds, "corn_play_bounds")
		local zones = Instance.new("Folder")
		zones.Name = "NoCornZones"
		zones.Parent = root
		local props = Instance.new("Folder")
		props.Name = "Props"
		props.Parent = root
		local slots = Instance.new("Folder")
		slots.Name = "KeySlots"
		slots.Parent = root
		local boundaries = Instance.new("Folder")
		boundaries.Name = "Boundaries"
		boundaries.Parent = root
		local wall = Color3.fromRGB(51, 61, 52)
		part(boundaries, "West", Vector3.new(2, 20, 1204), Vector3.new(-601, 90, 0), wall)
		part(boundaries, "East", Vector3.new(2, 20, 1204), Vector3.new(601, 90, 0), wall)
		part(boundaries, "South", Vector3.new(1200, 20, 2), Vector3.new(0, 90, -601), wall)
		part(boundaries, "NorthLeft", Vector3.new(594, 20, 2), Vector3.new(-303, 90, 601), wall)
		part(boundaries, "NorthRight", Vector3.new(594, 20, 2), Vector3.new(303, 90, 601), wall)
		local spawn = part(
			root,
			"RoundSpawn",
			Vector3.new(6, 0.15, 6),
			Vector3.new(0, 80.075, -500),
			Color3.fromRGB(158, 176, 150)
		)
		spawn.CFrame *= CFrame.Angles(0, math.pi, 0)
		spawn.CanCollide = false
		spawn.CanTouch = false
		spawn.CanQuery = false
		spawn:SetAttribute("spawn_id", "solo_start")
		CollectionService:AddTag(spawn, "corn_spawn")
		noCorn(zones, "StartClearing", Vector3.new(20, 10, 20), Vector3.new(0, 85, -500))
		local allSlots: { Part } = {}
		for row = 1, 5 do
			for column = 1, 3 do
				local id = string.format("solo_slot_%02d", #allSlots + 1)
				local slot = part(
					slots,
					id,
					Vector3.new(6, 0.12, 6),
					Vector3.new((column - 2) * 360, 80.06, (row - 3) * 180),
					Color3.fromRGB(119, 123, 87)
				)
				slot.CanCollide = false
				slot.CanTouch = false
				slot.CanQuery = false
				slot:SetAttribute("slot_id", id)
				CollectionService:AddTag(slot, "corn_key_slot")
				table.insert(allSlots, slot)
			end
		end
		for _, index in { 3, 8, 13 } do
			local barrel = part(
				props,
				"LookoutBarrel",
				Vector3.new(4, 3.2, 3.2),
				allSlots[index].Position + Vector3.new(4, 1.94, 0),
				Color3.fromRGB(111, 78, 48)
			)
			barrel.CFrame *= CFrame.Angles(0, 0, math.pi / 2)
			barrel.Shape = Enum.PartType.Cylinder
			barrel.Material = Enum.Material.Wood
			CollectionService:AddTag(barrel, "corn_barrel")
		end
		house(props, "HouseWest", Vector3.new(-180, 80, -190))
		house(props, "HouseEast", Vector3.new(210, 80, 120))
		house(props, "HouseNorthWest", Vector3.new(-420, 80, 240))
		local scarecrow = Instance.new("Model")
		scarecrow.Name = "ScarecrowMarker"
		scarecrow:SetAttribute("role", "visual_scarecrow_placeholder")
		scarecrow.Parent = props
		part(
			scarecrow,
			"Pole",
			Vector3.new(0.8, 20, 0.8),
			Vector3.new(12, 90, 12),
			Color3.fromRGB(77, 60, 42)
		)
		part(
			scarecrow,
			"Body",
			Vector3.new(4, 8, 2),
			Vector3.new(12, 94, 12),
			Color3.fromRGB(35, 39, 30)
		)
		part(
			scarecrow,
			"Arms",
			Vector3.new(14, 1, 1),
			Vector3.new(12, 97, 12),
			Color3.fromRGB(35, 39, 30)
		)
		part(
			scarecrow,
			"Head",
			Vector3.new(2.5, 2.5, 2.5),
			Vector3.new(12, 99.5, 12),
			Color3.fromRGB(89, 83, 54)
		)
		local gate = Instance.new("Model")
		gate.Name = "EscapeGate"
		gate:SetAttribute("gate_id", "solo_gate")
		gate.Parent = root
		CollectionService:AddTag(gate, "corn_gate")
		part(
			gate,
			"Door",
			Vector3.new(12, 18, 2),
			Vector3.new(0, 89, 601),
			Color3.fromRGB(114, 75, 49)
		).CanTouch =
			false
		zone(gate, "InteractionAnchor", Vector3.new(0.1, 0.1, 0.1), Vector3.new(0, 83, 599.7))
		local exit = zone(gate, "ExitZone", Vector3.new(12, 22, 8), Vector3.new(0, 91, 610))
		exit:SetAttribute("gate_id", "solo_gate")
		CollectionService:AddTag(exit, "corn_exit")
		noCorn(gate, "ApproachClearance", Vector3.new(20, 10, 28), Vector3.new(0, 85, 600))
		part(gate, "Header", Vector3.new(12, 2, 2), Vector3.new(0, 99, 601), wall)
		local apron = part(
			gate,
			"ExitGround",
			Vector3.new(20, 2, 20),
			Vector3.new(0, 79, 610),
			Color3.fromRGB(91, 97, 70)
		)
		apron.Material = Enum.Material.Ground
		gate.PrimaryPart = gate.Door :: BasePart
		root.Parent = Workspace
		MapAuthoring.EnsureCornerSpawns(root)
		MapAuthoring.RebuildOverview(root)
		local count = MapAuthoring.Preview(root, spawn.Position)
		root:SetAttribute("EditorCornCount", count)
		Selection:Set({ spawn })
	end)
	if not ok then
		root:Destroy()
		error(tostring(err))
	end
	print(
		"CornMap installed: 1200 x 1200 studs, 15 key slots, gate, 3 barrels, 3 decorative houses"
	)
	return root
end
return MapAuthoring
]========] },
{ path = [========[ServerScriptService/GameServer/Game/SoloRound]========], class = [========[ModuleScript]========], source = [========[--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameShared = ReplicatedStorage:WaitForChild("GameShared")
local Endpoints = require(GameShared:WaitForChild("Network"):WaitForChild("EndpointNames"))
local AuthoredWorld = require(script.Parent:WaitForChild("AuthoredWorld"))
local Stamina = require(GameShared:WaitForChild("Game"):WaitForChild("Stamina"))

local SoloRound = {}
SoloRound.__index = SoloRound

function SoloRound.new(context: any)
	return setmetatable({
		context = context,
		balance = context.Config.CoreLoop,
		action = context.Services.NetworkService:GetEvent(Endpoints.RequestRoundAction),
		snapshot = context.Services.NetworkService:GetEvent(Endpoints.RoundSnapshot),
		sprintIntent = context.Services.NetworkService:GetEvent(Endpoints.RequestSprintIntent),
		stamina = Stamina.new(context.Config.CoreLoop.stamina_capacity, os.clock()),
		world = nil :: any,
		selectedSpawn = nil :: BasePart?,
		player = nil :: Player?,
		phase = "ready",
		epoch = 0,
		hasKey = false,
		gateOpen = false,
		diamonds = 0,
		reward = 0,
		startedAt = nil :: number?,
		elapsed = 0,
		notice = "",
		random = Random.new(),
		connections = {} :: { RBXScriptConnection },
		characterConnection = nil :: RBXScriptConnection?,
		characterRemovingConnection = nil :: RBXScriptConnection?,
		deathConnection = nil :: RBXScriptConnection?,
		keyConnection = nil :: RBXScriptConnection?,
		roundCharacter = nil :: Model?,
		boundCharacter = nil :: Model?,
		controlledCharacter = nil :: Model?,
		jumpPower = 50,
		jumpHeight = 7.2,
		autoRotate = true,
		requestTokens = 2,
		requestAt = os.clock(),
		interactionAt = -math.huge,
		pollAt = 0,
		snapshotAt = 0,
	}, SoloRound)
end

function SoloRound:_send()
	local player = self.player
	if not player or player.Parent ~= Players then
		return
	end
	local facing = if self.selectedSpawn
		then self.selectedSpawn.CFrame.LookVector
		else Vector3.new(0, 0, -1)
	local horizontal = Vector3.new(facing.X, 0, facing.Z)
	local startLook = if horizontal.Magnitude > 0 then horizontal.Unit else Vector3.new(0, 0, -1)
	self.snapshot:FireClient(player, {
		phase = self.phase,
		has_key = self.hasKey,
		gate_open = self.gateOpen,
		session_diamonds = self.diamonds,
		reward_diamonds = self.reward,
		elapsed_sec = if self.phase == "active" and self.startedAt
			then os.clock() - self.startedAt
			else self.elapsed,
		notice = self.notice,
		stamina = self.stamina.value,
		stamina_capacity = self.balance.stamina_capacity,
		is_sprinting = self.stamina.sprinting,
		sprint_exhausted = self.stamina.exhausted,
		start_look = startLook,
	})
end

function SoloRound:_livingCharacter(): (Model?, Humanoid?, BasePart?)
	local player = self.player
	local character = if player then player.Character else nil
	if not character or not character.Parent then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

function SoloRound:_controls(enabled: boolean)
	if not enabled then
		Stamina.Request(self.stamina, false, os.clock(), false)
	end
	local character, humanoid = self:_livingCharacter()
	if not character or not humanoid then
		return
	end
	if self.controlledCharacter ~= character then
		self.controlledCharacter = character
		self.jumpPower = humanoid.JumpPower
		self.jumpHeight = humanoid.JumpHeight
		self.autoRotate = humanoid.AutoRotate
	end
	humanoid.WalkSpeed = if enabled then self.balance.walk_speed else 0
	humanoid.JumpPower = if enabled then self.jumpPower else 0
	humanoid.JumpHeight = if enabled then self.jumpHeight else 0
	humanoid.AutoRotate = enabled and self.autoRotate
end

function SoloRound:_fallbackSpawn(): BasePart?
	local map = Workspace:FindFirstChild("CornMap")
	if
		not map
		or not map:IsA("Model")
		or map:GetAttribute("corn_project_id") ~= "children_of_corn"
	then
		return nil
	end
	local ok, result = pcall(AuthoredWorld.FindSafeSpawn, map)
	if not ok then
		self.context.Log:Warn("Cannot find a safe CornMap spawn:", result)
		return nil
	end
	return result
end

function SoloRound:_setRespawnLocation()
	local player = self.player
	if not player then
		return
	end
	local spawn = self.selectedSpawn
	player.RespawnLocation = if spawn
			and spawn:IsA("SpawnLocation")
			and spawn:IsDescendantOf(Workspace)
		then spawn
		else nil
end

function SoloRound:_chooseSpawn()
	if self.world and self.world:IsValid() then
		self.selectedSpawn = self.world:SelectSpawn(self.random:NextInteger(1, #self.world.Spawns))
	else
		self.selectedSpawn = self:_fallbackSpawn()
	end
	self:_setRespawnLocation()
end

function SoloRound:_moveToStart(character: Model)
	local spawn = self.selectedSpawn
	local map = Workspace:FindFirstChild("CornMap")
	if
		not spawn
		or not map
		or not map:IsA("Model")
		or not AuthoredWorld.IsSafeSpawn(map, spawn)
	then
		spawn = self:_fallbackSpawn()
		self.selectedSpawn = spawn
	end
	if not spawn then
		self.context.Log:Warn("No valid CornMap start; install or repair CornerSpawns")
		return
	end
	self:_setRespawnLocation()
	character:PivotTo(AuthoredWorld.SpawnCFrame(spawn))
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
end

function SoloRound:_clearKey()
	if self.keyConnection then
		self.keyConnection:Disconnect()
		self.keyConnection = nil
	end
	if self.world then
		self.world:ClearKey()
	end
end

function SoloRound:_finish(phase: string, notice: string)
	if self.phase ~= "active" and self.phase ~= "preparing" then
		return
	end
	-- Fix the terminal state before rewarding or notifying any client.
	self.elapsed = if self.startedAt then os.clock() - self.startedAt else 0
	self.phase = phase
	self.epoch += 1
	self.notice = notice
	self.reward = if phase == "escaped" then self.balance.escape_reward_diamonds else 0
	self.diamonds += self.reward
	self.hasKey = false
	self:_clearKey()
	if self.world then
		self.world:SetInteractionEnabled(false, self.gateOpen)
	end
	self:_controls(false)
	self:_send()
	self.context.Log:Info("Round finished:", phase, "reward:", self.reward)
end

function SoloRound:_canInteract(
	player: Player,
	item: BasePart,
	itemPrompt: ProximityPrompt
): boolean
	if player ~= self.player or self.phase ~= "active" or not itemPrompt.Enabled then
		return false
	end
	local now = os.clock()
	if now - self.interactionAt < 0.25 then
		return false
	end
	self.interactionAt = now
	local character, _, root = self:_livingCharacter()
	if not character or character ~= self.roundCharacter or not root then
		return false
	end
	if not self.world or not item:IsDescendantOf(self.world.Root) then
		return false
	end
	local direction = item.Position - root.Position
	if direction.Magnitude > self.balance.interaction_radius then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	local hit = Workspace:Raycast(root.Position, direction, params)
	return not hit or hit.Instance == item
end

function SoloRound:_openGate(player: Player)
	local world = self.world
	if
		not world
		or self.gateOpen
		or not self:_canInteract(player, world.GateAnchor, world.GatePrompt)
	then
		return
	end
	local _, _, root = self:_livingCharacter()
	if not root or not world:IsGateFront(root.Position) then
		return
	end
	if not self.hasKey then
		self.notice = "corn_loop_need_key"
		self:_send()
		return
	end
	self.hasKey = false
	self.gateOpen = true
	self.notice = ""
	world:SetGateOpen(true)
	self:_send()
end

function SoloRound:_ensureWorld(): boolean
	if self.world then
		return self.world:IsValid()
	end
	local ok, result =
		pcall(AuthoredWorld.new, self.balance.interaction_radius, self.balance.key_slot_count)
	if not ok then
		self.context.Log:Warn("Cannot bind editable CornMap:", result)
		return false
	end
	self.world = result
	if self.selectedSpawn and table.find(self.world.Spawns, self.selectedSpawn) then
		self.world.Spawn = self.selectedSpawn
	end
	table.insert(
		self.connections,
		self.world.GatePrompt.Triggered:Connect(function(player: Player)
			self:_openGate(player)
		end)
	)
	return true
end

function SoloRound:_startRound()
	if self.phase ~= "ready" and self.phase ~= "escaped" and self.phase ~= "aborted" then
		return
	end
	self.epoch += 1
	self.stamina = Stamina.new(self.balance.stamina_capacity, os.clock())
	local epoch = self.epoch
	self.phase = "preparing"
	self.startedAt = nil
	self.elapsed = 0
	self.reward = 0
	self.notice = ""
	self.hasKey = false
	self.gateOpen = false
	self.roundCharacter = nil
	self:_clearKey()
	self:_controls(false)
	self:_send()
	if not self:_ensureWorld() then
		self:_chooseSpawn()
		local character = self:_livingCharacter()
		if character then
			self:_moveToStart(character)
		end
		self:_finish("aborted", "corn_loop_setup_error")
		return
	end
	self:_chooseSpawn()
	self.world:SetGateOpen(false)
	self.world:SetInteractionEnabled(false, false)

	task.spawn(function()
		local deadline = os.clock() + 10
		local character: Model? = nil
		while
			self.epoch == epoch
			and self.phase == "preparing"
			and self.player
			and self.player.Parent == Players
		do
			character = self:_livingCharacter()
			if character or os.clock() >= deadline then
				break
			end
			task.wait(0.1)
		end
		if self.epoch ~= epoch or self.phase ~= "preparing" then
			return
		end
		if not character then
			self:_finish("aborted", "corn_loop_setup_error")
			return
		end
		if not self.world or not self.world:IsValid() then
			self:_finish("aborted", "corn_loop_setup_error")
			return
		end
		self:_moveToStart(character)
		self.roundCharacter = character
		local slot = self.world.Slots[self.random:NextInteger(1, #self.world.Slots)]
		local keyPrompt = self.world:SpawnKey(slot)
		self.keyConnection = keyPrompt.Triggered:Connect(function(player: Player)
			local key = self.world.Key
			if
				self.epoch ~= epoch
				or self.hasKey
				or self.gateOpen
				or not key
				or keyPrompt ~= self.world.KeyPrompt
			then
				return
			end
			if not self:_canInteract(player, key, keyPrompt) then
				return
			end
			self.hasKey = true
			self.notice = ""
			self:_clearKey()
			self:_send()
		end)
		self.startedAt = os.clock()
		self.phase = "active"
		self.world:SetInteractionEnabled(true, false)
		self:_controls(true)
		self:_send()
		self.context.Log:Info("Solo round started")
	end)
end

function SoloRound:_menu()
	if self.phase ~= "escaped" and self.phase ~= "aborted" then
		return
	end
	self.epoch += 1
	self.phase = "ready"
	self.reward = 0
	self.elapsed = 0
	self.startedAt = nil
	self.notice = ""
	self.hasKey = false
	self.gateOpen = false
	self:_clearKey()
	if self.world then
		self.world:SetGateOpen(false)
		self.world:SetInteractionEnabled(false, false)
	end
	local character = self:_livingCharacter()
	if character then
		self:_moveToStart(character)
	end
	self:_controls(false)
	self:_send()
end

function SoloRound:_request(player: Player, action: any)
	if player ~= self.player then
		return
	end
	local now = os.clock()
	self.requestTokens = math.min(2, self.requestTokens + (now - self.requestAt) * 2)
	self.requestAt = now
	if self.requestTokens < 1 then
		return
	end
	self.requestTokens -= 1
	if type(action) ~= "string" then
		return
	end
	if action == "sync" then
		self:_send()
	elseif
		(action == "start" and self.phase == "ready")
		or (action == "retry" and (self.phase == "escaped" or self.phase == "aborted"))
	then
		self:_startRound()
	elseif action == "abort" then
		self:_finish("aborted", "corn_loop_result_aborted")
	elseif action == "menu" then
		self:_menu()
	end
end

function SoloRound:_bindCharacter(character: Model)
	if character == self.boundCharacter then
		return
	end
	self.boundCharacter = character
	if self.deathConnection then
		self.deathConnection:Disconnect()
		self.deathConnection = nil
	end
	if self.phase == "active" or (self.phase == "preparing" and self.roundCharacter ~= nil) then
		self:_finish("aborted", "corn_loop_result_aborted")
	end
	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 10)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		local player = self.player
		if not player or player.Character ~= character or self.boundCharacter ~= character then
			return
		end
		if not humanoid or not humanoid:IsA("Humanoid") or not root or not root:IsA("BasePart") then
			self:_finish("aborted", "corn_loop_setup_error")
			return
		end
		self.deathConnection = humanoid.Died:Connect(function()
			if self.player and self.player.Character == character then
				self:_finish("aborted", "corn_loop_result_aborted")
			end
		end)
		if self.phase ~= "active" and self.phase ~= "preparing" then
			self:_moveToStart(character)
		end
		self:_controls(self.phase == "active" and self.roundCharacter == character)
		self:_send()
	end)
end

function SoloRound:_addPlayer(player: Player)
	if self.player then
		return -- One owner, no multiplayer matchmaking in this prototype.
	end
	self.player = player
	self:_setRespawnLocation()
	self.requestTokens = 2
	self.requestAt = os.clock()
	self.characterConnection = player.CharacterAdded:Connect(function(character: Model)
		self:_bindCharacter(character)
	end)
	self.characterRemovingConnection = player.CharacterRemoving:Connect(function(character: Model)
		if
			player == self.player
			and (character == self.boundCharacter or character == player.Character)
		then
			self:_finish("aborted", "corn_loop_result_aborted")
		end
	end)
	if player.Character then
		self:_bindCharacter(player.Character)
	end
	self:_send()
end

function SoloRound:_removePlayer(player: Player)
	if player ~= self.player then
		return
	end
	self.epoch += 1
	self:_clearKey()
	if self.characterConnection then
		self.characterConnection:Disconnect()
		self.characterConnection = nil
	end
	if self.deathConnection then
		self.deathConnection:Disconnect()
		self.deathConnection = nil
	end
	if self.characterRemovingConnection then
		self.characterRemovingConnection:Disconnect()
		self.characterRemovingConnection = nil
	end
	self.player = nil
	self.stamina = Stamina.new(self.balance.stamina_capacity, os.clock())
	self.phase = "ready"
	self.hasKey = false
	self.gateOpen = false
	self.diamonds = 0
	self.reward = 0
	self.startedAt = nil
	self.elapsed = 0
	self.notice = ""
	self.roundCharacter = nil
	self.boundCharacter = nil
	self.controlledCharacter = nil
	if self.world then
		self.world:SetGateOpen(false)
		self.world:SetInteractionEnabled(false, false)
	end
end

function SoloRound:_poll(now: number)
	if self.phase ~= "active" then
		return
	end
	local character, _, root = self:_livingCharacter()
	if not character or character ~= self.roundCharacter or not root then
		self:_finish("aborted", "corn_loop_result_aborted")
		return
	end
	if
		not self.world
		or not self.world:IsValid()
		or not self.world:IsOnPlayground(root.Position)
	then
		self:_finish("aborted", "corn_loop_setup_error")
		return
	end
	if self.gateOpen and self.world:IsInExit(root.Position) then
		self:_finish("escaped", "")
		return
	end
	if now - self.snapshotAt >= 0.25 then
		self.snapshotAt = now
		self:_send()
	end
end

function SoloRound:_sprintRequest(player: Player, value: any)
	if player ~= self.player then
		return
	end
	local character = self:_livingCharacter()
	Stamina.Request(
		self.stamina,
		value,
		os.clock(),
		self.phase == "active" and character ~= nil and character == self.roundCharacter
	)
end

function SoloRound:_movement(dt: number)
	local character, humanoid, root = self:_livingCharacter()
	local active = self.phase == "active" and character ~= nil and character == self.roundCharacter
	local velocity = if root then root.AssemblyLinearVelocity else Vector3.zero
	local moving = Vector3.new(velocity.X, 0, velocity.Z).Magnitude > 0.5
	Stamina.Step(self.stamina, dt, moving, active, self.balance)
	if humanoid then
		humanoid.WalkSpeed = if not active
			then 0
			elseif self.stamina.sprinting then self.balance.sprint_speed
			else self.balance.walk_speed
		humanoid:SetAttribute("corn_stamina", self.stamina.value)
		humanoid:SetAttribute("corn_sprinting", self.stamina.sprinting)
		humanoid:SetAttribute("corn_sprint_exhausted", self.stamina.exhausted)
	end
end

function SoloRound:Start()
	self:_ensureWorld()
	self:_chooseSpawn()
	table.insert(
		self.connections,
		self.sprintIntent.OnServerEvent:Connect(function(player: Player, value: any)
			self:_sprintRequest(player, value)
		end)
	)
	table.insert(
		self.connections,
		self.action.OnServerEvent:Connect(function(player: Player, action: any)
			self:_request(player, action)
		end)
	)
	table.insert(
		self.connections,
		Players.PlayerAdded:Connect(function(player: Player)
			self:_addPlayer(player)
		end)
	)
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player: Player)
			self:_removePlayer(player)
		end)
	)
	table.insert(
		self.connections,
		RunService.Heartbeat:Connect(function(dt: number)
			self:_movement(dt)
			local now = os.clock()
			if now - self.pollAt >= 0.1 then
				self.pollAt = now
				self:_poll(now)
			end
		end)
	)
	for _, player in Players:GetPlayers() do
		self:_addPlayer(player)
	end
end

return SoloRound
]========] },
{ path = [========[ServerScriptService/GameServer/Services/NetworkService]========], class = [========[ModuleScript]========], source = [========[--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkService = {
	Name = "NetworkService",
	Order = 10,
}

local root: Folder

function NetworkService:Init(_context: any)
	local existing = ReplicatedStorage:FindFirstChild("GameRemotes")
	if existing and not existing:IsA("Folder") then
		error("ReplicatedStorage.GameRemotes exists but is not a Folder")
	end
	if existing then
		root = existing
	else
		root = Instance.new("Folder")
		root.Name = "GameRemotes"
		root.Parent = ReplicatedStorage
	end
end

function NetworkService:GetEvent(name: string): RemoteEvent
	local existing = root:FindFirstChild(name)
	if existing then
		assert(existing:IsA("RemoteEvent"), string.format("%s is not a RemoteEvent", name))
		return existing
	end
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = root
	return event
end

function NetworkService:GetFunction(name: string): RemoteFunction
	local existing = root:FindFirstChild(name)
	if existing then
		assert(existing:IsA("RemoteFunction"), string.format("%s is not a RemoteFunction", name))
		return existing
	end
	local fn = Instance.new("RemoteFunction")
	fn.Name = name
	fn.Parent = root
	return fn
end

return NetworkService
]========] },
{ path = [========[ServerScriptService/GameServer/Services/RoundService]========], class = [========[ModuleScript]========], source = [========[--!strict

local RunService = game:GetService("RunService")
local SoloRound = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("SoloRound"))

local RoundService = { Name = "RoundService", Order = 30 }
local runtime: any = nil

function RoundService:Init(context: any)
	if
		not RunService:IsStudio()
		or context.Config.Environment ~= "DEV"
		or context.Config.Game.SessionMode ~= "solo_local"
	then
		context.Log:Warn("Temporary solo prototype is available only in Studio DEV mode")
		return
	end
	runtime = SoloRound.new(context)
end

function RoundService:Start()
	if runtime then
		runtime:Start()
	end
end

return RoundService
]========] },
{ path = [========[ServerScriptService/GameServer/Services/TagService]========], class = [========[ModuleScript]========], source = [========[--!strict

local CollectionService = game:GetService("CollectionService")

local TagService = {
	Name = "TagService",
	Order = 20,
}

local connections: { RBXScriptConnection } = {}

function TagService:Bind(tag: string, onAdded: (Instance) -> (), onRemoved: ((Instance) -> ())?)
	for _, instance in CollectionService:GetTagged(tag) do
		task.spawn(onAdded, instance)
	end

	table.insert(connections, CollectionService:GetInstanceAddedSignal(tag):Connect(onAdded))
	if onRemoved then
		table.insert(
			connections,
			CollectionService:GetInstanceRemovedSignal(tag):Connect(onRemoved)
		)
	end
end

function TagService:Destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

return TagService
]========] },
{ path = [========[StarterPlayer/StarterPlayerScripts/GameClient/Bootstrap]========], class = [========[LocalScript]========], source = [========[--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameShared = ReplicatedStorage:WaitForChild("GameShared")
local Config = require(GameShared:WaitForChild("Config"):WaitForChild("GameConfig"))
local Workspace = game:GetService("Workspace")
local map = Workspace:WaitForChild("CornMap", 10)
if
	not map
	or map:GetAttribute("corn_project_id") ~= "children_of_corn"
	or Workspace:FindFirstChild("Asmr_Base")
	or Workspace:FindFirstChild("ASMR_Models")
then
	warn("[ChildrenOfCorn] Inactive: editable CornMap missing or another game detected")
	return
end
local Logger = require(GameShared:WaitForChild("Core"):WaitForChild("Logger"))
local log = Logger.new("ClientBootstrap", Config.Debug)

local controllersFolder = script.Parent:WaitForChild("Controllers")

type RuntimeModule = {
	Name: string?,
	Order: number?,
	Init: ((self: RuntimeModule, context: any) -> ())?,
	Start: ((self: RuntimeModule, context: any) -> ())?,
}

local loaded: { RuntimeModule } = {}
local byName: { [string]: RuntimeModule } = {}

for _, child in controllersFolder:GetChildren() do
	if child:IsA("ModuleScript") then
		local ok, result = pcall(require, child)
		if not ok then
			error(
				string.format(
					"Failed to require controller %s: %s",
					child:GetFullName(),
					tostring(result)
				)
			)
		end
		if type(result) ~= "table" then
			error(string.format("Controller %s must return a table", child:GetFullName()))
		end
		local module = result :: RuntimeModule
		local name = module.Name or child.Name
		if byName[name] then
			error(string.format("Duplicate controller name: %s", name))
		end
		module.Name = name
		byName[name] = module
		table.insert(loaded, module)
	end
end

table.sort(loaded, function(a, b)
	return (a.Order or 100) < (b.Order or 100)
end)

local context = {
	Config = Config,
	Controllers = byName,
	Log = Logger.new("Client", Config.Debug),
}

for _, module in loaded do
	if module.Init then
		module:Init(context)
	end
end

for _, module in loaded do
	if module.Start then
		module:Start(context)
	end
end

log:Info(string.format("Started %d controllers", #loaded))
]========] },
{ path = [========[StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornController]========], class = [========[ModuleScript]========], source = [========[--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameShared = ReplicatedStorage:WaitForChild("GameShared")
local CornLayout = require(GameShared:WaitForChild("Game"):WaitForChild("CornLayout"))

type Chunk = {
	Key: string,
	Folder: Folder,
	MinColumn: number,
	MaxColumn: number,
	MinRow: number,
	MaxRow: number,
	Column: number,
	Row: number,
	Distance: number,
	Count: number,
	Alive: boolean,
	Done: boolean,
}

type OverviewItem = {
	Part: BasePart,
	PreviousModifier: number,
	Frame: CFrame,
	Size: Vector3,
	Keys: { string },
	Hidden: boolean,
}

local CornController = {
	Name = "CornController",
	Order = 50,
	_enabled = false,
	_connection = nil :: RBXScriptConnection?,
	_map = nil :: Model?,
	_field = nil :: BasePart?,
	_template = nil :: CornLayout.Plant?,
	_folder = nil :: Folder?,
	_chunks = {} :: { [string]: Chunk },
	_queue = {} :: { Chunk },
	_exclusions = nil :: CornLayout.Exclusions?,
	_pivotOffset = CFrame.identity,
	_height = CornLayout.Height,
	_pollElapsed = math.huge,
	_plantCount = 0,
	_lastWarning = "",
	_overviewFolder = nil :: Folder?,
	_overviewParts = {} :: { [BasePart]: OverviewItem },
	_overviewByChunk = {} :: { [string]: { OverviewItem } },
	_overviewDirty = {} :: { [OverviewItem]: boolean },
	_overviewFieldFrame = CFrame.identity,
	_overviewFieldSize = Vector3.zero,
}

local PROJECT_ID = "children_of_corn"
local POLL_SEC = 0.3
local CREATE_BUDGET = 18
local CELL_BUDGET = 100
local TIME_BUDGET_SEC = 0.003
local MAX_CHUNKS = 28

function CornController:_warn(message: string)
	if self._lastWarning ~= message then
		self._lastWarning = message
		warn("[CornController] " .. message)
	end
end

local function overviewKeys(field: BasePart, part: BasePart): { string }
	local relative = field.CFrame:ToObjectSpace(part.CFrame)
	local half = part.Size / 2
	-- Require completed fine groups across the entire rotated coarse footprint.
	-- The margin also covers the small deterministic cell stagger.
	local padding = CornLayout.Spacing * 0.75
	local halfX = math.abs(relative.RightVector.X) * half.X
		+ math.abs(relative.UpVector.X) * half.Y
		+ math.abs(relative.LookVector.X) * half.Z
		+ padding
	local halfZ = math.abs(relative.RightVector.Z) * half.X
		+ math.abs(relative.UpVector.Z) * half.Y
		+ math.abs(relative.LookVector.Z) * half.Z
		+ padding
	local fieldHalf = field.Size / 2
	local minX = math.max(relative.Position.X - halfX, -fieldHalf.X)
	local maxX = math.min(relative.Position.X + halfX, fieldHalf.X)
	local minZ = math.max(relative.Position.Z - halfZ, -fieldHalf.Z)
	local maxZ = math.min(relative.Position.Z + halfZ, fieldHalf.Z)
	local keys: { string } = {}
	if minX > maxX or minZ > maxZ then
		return keys
	end
	local width = CornLayout.Spacing * CornLayout.ChunkCells
	local offset = CornLayout.Spacing / 2
	for column = math.floor((minX + offset) / width), math.floor((maxX + offset) / width) do
		for row = math.floor((minZ + offset) / width), math.floor((maxZ + offset) / width) do
			table.insert(keys, column .. ":" .. row)
		end
	end
	return keys
end

function CornController:_showOverview()
	for _, entry in self._overviewParts do
		if entry.Hidden then
			if entry.Part.Parent then
				entry.Part.LocalTransparencyModifier = entry.PreviousModifier
			end
			entry.Hidden = false
		end
	end
	self._overviewDirty = {}
end

function CornController:_restoreOverview()
	self:_showOverview()
	self._overviewFolder = nil
	self._overviewParts = {}
	self._overviewByChunk = {}
end

function CornController:_markOverviewChunk(key: string)
	for _, entry in self._overviewByChunk[key] or {} do
		self._overviewDirty[entry] = true
	end
end

function CornController:_bindOverview()
	local map = self._map
	local field = self._field
	local folder = if map then map:FindFirstChild("EditorFieldOverview") else nil
	if not folder then
		self:_restoreOverview()
		return
	end
	if
		not field
		or not folder:IsA("Folder")
		or folder:GetAttribute("CornEditorOverview") ~= true
		or folder:GetAttribute("corn_project_id") ~= PROJECT_ID
	then
		self:_restoreOverview()
		self:_warn("Unrecognized EditorFieldOverview is preserved")
		return
	end
	local children = folder:GetChildren()
	local cachedCount = 0
	for _ in self._overviewParts do
		cachedCount += 1
	end
	local reusable = self._overviewFolder == folder
		and self._overviewFieldFrame == field.CFrame
		and self._overviewFieldSize == field.Size
		and cachedCount == #children
	-- Validate the whole container before any local visibility changes.
	for _, item in children do
		if
			not item:IsA("BasePart")
			or item:GetAttribute("CornEditorOverview") ~= true
			or item:GetAttribute("corn_project_id") ~= PROJECT_ID
		then
			self:_restoreOverview()
			self:_warn("EditorFieldOverview contains unowned objects; all were preserved")
			return
		end
		local previous = self._overviewParts[item]
		if not previous or previous.Frame ~= item.CFrame or previous.Size ~= item.Size then
			reusable = false
		end
	end
	if reusable then
		return
	end
	self:_restoreOverview()
	self._overviewFolder = folder
	self._overviewFieldFrame = field.CFrame
	self._overviewFieldSize = field.Size
	for _, item in children do
		local part = item :: BasePart
		local entry: OverviewItem = {
			Part = part,
			PreviousModifier = part.LocalTransparencyModifier,
			Frame = part.CFrame,
			Size = part.Size,
			Keys = overviewKeys(field, part),
			Hidden = false,
		}
		self._overviewParts[part] = entry
		for _, key in entry.Keys do
			local items = self._overviewByChunk[key]
			if not items then
				items = {}
				self._overviewByChunk[key] = items
			end
			table.insert(items, entry)
		end
	end
	for key, chunk in self._chunks do
		if chunk.Done then
			self:_markOverviewChunk(key)
		end
	end
end

function CornController:_updateOverview()
	local folder = self._overviewFolder
	if not folder then
		return
	end
	if
		folder:GetAttribute("CornEditorOverview") ~= true
		or folder:GetAttribute("corn_project_id") ~= PROJECT_ID
	then
		self:_restoreOverview()
		return
	end
	for entry in self._overviewDirty do
		local part = entry.Part
		if
			part.Parent ~= folder
			or part:GetAttribute("CornEditorOverview") ~= true
			or part:GetAttribute("corn_project_id") ~= PROJECT_ID
		then
			self:_restoreOverview()
			self:_warn("Overview ownership changed; its visibility was restored")
			return
		end
		local covered = #entry.Keys > 0
		for _, key in entry.Keys do
			local chunk = self._chunks[key]
			if not chunk or not chunk.Done then
				covered = false
				break
			end
		end
		if covered ~= entry.Hidden then
			part.LocalTransparencyModifier = if covered then 1 else entry.PreviousModifier
			entry.Hidden = covered
		end
	end
	self._overviewDirty = {}
end

function CornController:_clearChunks()
	self:_showOverview()
	for _, chunk in self._chunks do
		chunk.Alive = false
		chunk.Folder:Destroy()
	end
	self._chunks = {}
	self._queue = {}
	self._plantCount = 0
	if self._folder then
		self._folder:SetAttribute("LoadedPlants", 0)
	end
end

function CornController:_clearInputs()
	self:_clearChunks()
	self:_restoreOverview()
	if self._folder then
		self._folder:Destroy()
	end
	self._folder = nil
	self._map = nil
	self._field = nil
	self._template = nil
	self._exclusions = nil
end

function CornController:_resolveInputs(): boolean
	local map = Workspace:FindFirstChild("CornMap")
	local field = if map then map:FindFirstChild("FieldZone") else nil
	local art = ReplicatedStorage:FindFirstChild("CornRuntimeArt")
	local template = if art then art:FindFirstChild("CornPlantTemplate") else nil
	if not map or not map:IsA("Model") or map:GetAttribute("corn_project_id") ~= PROJECT_ID then
		self:_clearInputs()
		self:_warn("The owned CornMap is not available; editor preview is preserved")
		return false
	end
	if
		not field
		or not field:IsA("BasePart")
		or field.CFrame.UpVector:Dot(Vector3.yAxis) < 0.9999
	then
		self:_clearInputs()
		self:_warn("CornMap needs a horizontal FieldZone; editor preview is preserved")
		return false
	end
	if
		not art
		or not art:IsA("Folder")
		or art:GetAttribute("CornRuntimeArtOwned") ~= true
		or art:GetAttribute("corn_project_id") ~= PROJECT_ID
		or not template
		or (not template:IsA("Model") and not template:IsA("BasePart"))
		or template:GetAttribute("CornPlantTemplateOwned") ~= true
	then
		self:_clearInputs()
		self:_warn("Prepared corn art is not available; check CornField Output")
		return false
	end
	if
		self._map == map
		and self._field == field
		and self._template == template
		and self._folder
	then
		return true
	end
	self:_clearInputs()
	local existing = map:FindFirstChild("CornClientPlants")
	if existing then
		if
			not existing:IsA("Folder")
			or existing:GetAttribute("CornClientRendererOwned") ~= true
			or existing:GetAttribute("corn_project_id") ~= PROJECT_ID
		then
			self:_warn("Refused to replace unowned CornMap/CornClientPlants")
			return false
		end
		existing:Destroy()
	end
	local bounds, size = CornLayout.Bounds(template)
	self._pivotOffset = template:GetPivot():ToObjectSpace(bounds):Inverse()
	self._height = size.Y
	self._map = map
	self._field = field
	self._template = template
	local folder = Instance.new("Folder")
	folder.Name = "CornClientPlants"
	folder:SetAttribute("CornClientRendererOwned", true)
	folder:SetAttribute("corn_project_id", PROJECT_ID)
	folder:SetAttribute("LoadedPlants", 0)
	folder.Parent = map
	self._folder = folder
	-- This client-only deletion never changes the author's saved scene or Props.
	local preview = map:FindFirstChild("EditorPreview")
	if
		preview
		and preview:IsA("Folder")
		and preview:GetAttribute("CornEditorPreview") == true
		and preview:GetAttribute("corn_project_id") == PROJECT_ID
	then
		preview:Destroy()
	end
	self._lastWarning = ""
	return true
end

function CornController:_reconcile(root: BasePart)
	if not self:_resolveInputs() then
		return
	end
	local map = self._map :: Model
	local field = self._field :: BasePart
	local folder = self._folder :: Folder
	self:_bindOverview()
	local exclusions = CornLayout.ReadExclusions(map, field)
	if self._exclusions and self._exclusions.Signature ~= exclusions.Signature then
		self:_clearChunks()
	end
	self._exclusions = exclusions
	local minColumn, maxColumn, minRow, maxRow = CornLayout.GetCellBounds(field)
	local localRoot = field.CFrame:PointToObjectSpace(root.Position)
	local width = CornLayout.Spacing * CornLayout.ChunkCells
	local radius = CornLayout.RenderRadius
	local desired: { any } = {}
	for chunkColumn = math.floor((localRoot.X - radius) / width), math.floor((localRoot.X + radius) / width) do
		for chunkRow = math.floor((localRoot.Z - radius) / width), math.floor((localRoot.Z + radius) / width) do
			local firstColumn = math.max(minColumn, chunkColumn * CornLayout.ChunkCells)
			local lastColumn = math.min(maxColumn, (chunkColumn + 1) * CornLayout.ChunkCells - 1)
			local firstRow = math.max(minRow, chunkRow * CornLayout.ChunkCells)
			local lastRow = math.min(maxRow, (chunkRow + 1) * CornLayout.ChunkCells - 1)
			if firstColumn > lastColumn or firstRow > lastRow then
				continue
			end
			local centerX = (firstColumn + lastColumn) * CornLayout.Spacing / 2
			local centerZ = (firstRow + lastRow) * CornLayout.Spacing / 2
			local distance = (centerX - localRoot.X) ^ 2 + (centerZ - localRoot.Z) ^ 2
			if distance <= radius * radius then
				table.insert(desired, {
					Key = chunkColumn .. ":" .. chunkRow,
					MinColumn = firstColumn,
					MaxColumn = lastColumn,
					MinRow = firstRow,
					MaxRow = lastRow,
					Distance = distance,
				})
			end
		end
	end
	table.sort(desired, function(a, b)
		return if a.Distance == b.Distance then a.Key < b.Key else a.Distance < b.Distance
	end)
	local wanted: { [string]: boolean } = {}
	for index, candidate in desired do
		if index > MAX_CHUNKS then
			break
		end
		wanted[candidate.Key] = true
		local chunk = self._chunks[candidate.Key]
		if chunk then
			chunk.Distance = candidate.Distance
		else
			local chunkFolder = Instance.new("Folder")
			chunkFolder.Name = "Chunk_" .. candidate.Key
			chunkFolder.Parent = folder
			chunk = {
				Key = candidate.Key,
				Folder = chunkFolder,
				MinColumn = candidate.MinColumn,
				MaxColumn = candidate.MaxColumn,
				MinRow = candidate.MinRow,
				MaxRow = candidate.MaxRow,
				Column = candidate.MinColumn,
				Row = candidate.MinRow,
				Distance = candidate.Distance,
				Count = 0,
				Alive = true,
				Done = false,
			}
			self._chunks[candidate.Key] = chunk
		end
	end
	for key, chunk in self._chunks do
		if not wanted[key] then
			self:_markOverviewChunk(key)
			chunk.Alive = false
			self._plantCount -= chunk.Count
			chunk.Folder:Destroy()
			self._chunks[key] = nil
		end
	end
	self._queue = {}
	for _, chunk in self._chunks do
		if not chunk.Done then
			table.insert(self._queue, chunk)
		end
	end
	table.sort(self._queue, function(a, b)
		return if a.Distance == b.Distance then a.Key < b.Key else a.Distance < b.Distance
	end)
	self:_updateOverview()
end

function CornController:_createBatch()
	local template = self._template
	local field = self._field
	local exclusions = self._exclusions
	if not template or not field or not exclusions then
		return
	end
	local began = os.clock()
	local _, fieldYaw = field.CFrame:ToOrientation()
	local examined = 0
	local created = 0
	while
		#self._queue > 0
		and examined < CELL_BUDGET
		and created < CREATE_BUDGET
		and os.clock() - began < TIME_BUDGET_SEC
	do
		local chunk = self._queue[1]
		if not chunk.Alive or chunk.Done then
			table.remove(self._queue, 1)
			continue
		end
		local column = chunk.Column
		local row = chunk.Row
		chunk.Column += 1
		if chunk.Column > chunk.MaxColumn then
			chunk.Column = chunk.MinColumn
			chunk.Row += 1
		end
		if chunk.Row > chunk.MaxRow then
			chunk.Done = true
			self:_markOverviewChunk(chunk.Key)
			table.remove(self._queue, 1)
		end
		examined += 1
		local position = CornLayout.CellPosition(field, column, row)
		if CornLayout.IsExcluded(position, exclusions) then
			continue
		end
		local clone = template:Clone()
		if not clone then
			self:_warn("Prepared corn template is not Archivable")
			self:Destroy()
			return
		end
		local plant = clone :: CornLayout.Plant
		plant.Name = "Corn"
		plant:PivotTo(
			CFrame.new(position + Vector3.new(0, self._height / 2, 0))
				* CFrame.Angles(0, CornLayout.CellYaw(column, row) + fieldYaw, 0)
				* self._pivotOffset
		)
		plant.Parent = chunk.Folder
		chunk.Count += 1
		self._plantCount += 1
		created += 1
	end
	if self._folder then
		self._folder:SetAttribute("LoadedPlants", self._plantCount)
	end
	self:_updateOverview()
end

function CornController:_step(delta: number)
	self._pollElapsed += delta
	if self._pollElapsed >= POLL_SEC then
		self._pollElapsed = 0
		local character = Players.LocalPlayer.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if root and root:IsA("BasePart") then
			self:_reconcile(root)
		else
			self:_clearChunks()
		end
	end
	self:_createBatch()
end

function CornController:Init(context: any)
	self._enabled = RunService:IsStudio()
		and context.Config.Environment == "DEV"
		and context.Config.Game.SessionMode == "solo_local"
end

function CornController:Start()
	if not self._enabled or self._connection then
		return
	end
	self._connection = RunService.Heartbeat:Connect(function(delta: number)
		self:_step(delta)
	end)
end

function CornController:Destroy()
	self._enabled = false
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	self:_clearInputs()
end

return CornController
]========] },
{ path = [========[StarterPlayer/StarterPlayerScripts/GameClient/Controllers/MovementController]========], class = [========[ModuleScript]========], source = [========[--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local shared = ReplicatedStorage:WaitForChild("GameShared")
local Endpoints = require(shared:WaitForChild("Network"):WaitForChild("EndpointNames"))
local Text = require(shared:WaitForChild("Game"):WaitForChild("RoundText"))

local MovementController = { Name = "MovementController", Order = 90 }
local SPRINT_ACTION = "CornSprint"
local CURSOR_ACTION = "CornCursor"
local player = Players.LocalPlayer

function MovementController:_intent(value: boolean)
	if self._intentValue ~= value then
		self._intentValue = value
		if self._remote then
			self._remote:FireServer(value)
		end
	end
end

function MovementController:_release()
	table.clear(self._shifts)
	self:_intent(false)
end

function MovementController:_camera()
	if self._active then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		player.CameraMinZoomDistance = 0.5
		player.CameraMaxZoomDistance = 0.5
		local camera = workspace.CurrentCamera
		if camera and self._snapshot then
			local position = camera.CFrame.Position
			camera.CFrame = CFrame.lookAt(position, position + self._snapshot.start_look)
		end
	else
		player.CameraMaxZoomDistance = self._savedMax
		player.CameraMinZoomDistance = self._savedMin
		player.CameraMode = self._savedMode
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end

function MovementController:_render()
	self._gui.Enabled = self._active
	self._cursorGuard.Visible = self._active and self._cursorOpen
	if self._roundLeave then
		self._roundLeave.Modal = self._active and self._cursorOpen
	end
	local s = self._snapshot
	if not s then
		return
	end
	local ratio = math.clamp(s.stamina / s.stamina_capacity, 0, 1)
	self._fill.Size = UDim2.fromScale(ratio, 1)
	self._fill.BackgroundColor3 = if s.sprint_exhausted
		then Color3.fromRGB(191, 146, 71)
		else Color3.fromRGB(119, 161, 86)
	self._label.Text = string.gsub(
		Text.corn_movement_stamina,
		"{percent}",
		tostring(math.floor(ratio * 100 + 0.5))
	)
	self._hint.Text = if self._cursorOpen
		then Text.corn_movement_cursor
		elseif s.sprint_exhausted then Text.corn_movement_exhausted
		else Text.corn_movement_controls
end

function MovementController:Init(_context: any)
	self._active = false
	self._cursorOpen = false
	self._intentValue = false
	self._shifts = {}
	self._connections = {}
	self._savedMode = player.CameraMode
	self._savedMin = player.CameraMinZoomDistance
	self._savedMax = player.CameraMaxZoomDistance
	local gui = Instance.new("ScreenGui")
	gui.Name = "CornMovementHud"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	self._gui = gui
	local guard = Instance.new("TextButton")
	guard.Name = "CursorGuard"
	guard.Size = UDim2.fromOffset(1, 1)
	guard.BackgroundTransparency = 1
	guard.Text = ""
	guard.Modal = true
	guard.Visible = false
	guard.Parent = gui
	self._cursorGuard = guard
	local panel = Instance.new("Frame")
	panel.Name = "Stamina"
	panel.Size = UDim2.fromOffset(350, 88)
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, 20, 1, -20)
	panel.BackgroundColor3 = Color3.fromRGB(27, 32, 28)
	panel.BackgroundTransparency = 0.12
	panel.BorderSizePixel = 0
	panel.Parent = gui
	local function label(name: string, y: number, size: number): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.Position = UDim2.fromOffset(12, y)
		l.Size = UDim2.new(1, -24, 0, 24)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.Gotham
		l.TextSize = size
		l.TextColor3 = Color3.fromRGB(239, 242, 233)
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Parent = panel
		return l
	end
	self._label = label("Amount", 6, 16)
	self._hint = label("Controls", 57, 12)
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Position = UDim2.fromOffset(12, 37)
	track.Size = UDim2.new(1, -24, 0, 10)
	track.BackgroundColor3 = Color3.fromRGB(63, 69, 61)
	track.BorderSizePixel = 0
	track.Parent = panel
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BorderSizePixel = 0
	fill.Parent = track
	self._fill = fill
end

function MovementController:SetSnapshot(snapshot: any)
	local active = snapshot.phase == "active"
	self._snapshot = snapshot
	if active ~= self._active then
		self:_release()
		self._cursorOpen = false
		self._active = active
		self:_camera()
	end
	self:_render()
end

function MovementController:Start(_context: any)
	local folder = ReplicatedStorage:WaitForChild("GameRemotes", 10)
	assert(folder, "Movement remotes are unavailable")
	local remote = folder:WaitForChild(Endpoints.RequestSprintIntent, 10)
	assert(remote and remote:IsA("RemoteEvent"), "Sprint intent remote is unavailable")
	self._remote = remote
	self._roundLeave = player.PlayerGui:WaitForChild("CornRoundHud"):WaitForChild("LeaveRound")
	ContextActionService:BindActionAtPriority(
		SPRINT_ACTION,
		function(_, state: Enum.UserInputState, input: InputObject)
			if state == Enum.UserInputState.Begin then
				if
					self._active
					and not self._cursorOpen
					and not UserInputService:GetFocusedTextBox()
				then
					self._shifts[input.KeyCode] = true
				end
			elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				self._shifts[input.KeyCode] = nil
			end
			self:_intent(self._active and not self._cursorOpen and next(self._shifts) ~= nil)
			return Enum.ContextActionResult.Sink
		end,
		false,
		3000,
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.RightShift
	)
	ContextActionService:BindActionAtPriority(CURSOR_ACTION, function(_, state: Enum.UserInputState)
		if not self._active then
			return Enum.ContextActionResult.Pass
		end
		if state == Enum.UserInputState.Begin then
			self._cursorOpen = not self._cursorOpen
			self:_release()
			self:_render()
		end
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.KeyCode.LeftAlt)
	for _, signal in { UserInputService.WindowFocusReleased, GuiService.MenuOpened } do
		table.insert(
			self._connections,
			signal:Connect(function()
				self:_release()
			end)
		)
	end
	table.insert(
		self._connections,
		player.CharacterAdded:Connect(function()
			self:_release()
			self:_camera()
		end)
	)
end

function MovementController:Destroy()
	self:_release()
	self._active = false
	self:_camera()
	ContextActionService:UnbindAction(SPRINT_ACTION)
	ContextActionService:UnbindAction(CURSOR_ACTION)
	for _, connection in self._connections do
		connection:Disconnect()
	end
	self._gui:Destroy()
end

return MovementController
]========] },
{ path = [========[StarterPlayer/StarterPlayerScripts/GameClient/Controllers/RoundController]========], class = [========[ModuleScript]========], source = [========[--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameShared = ReplicatedStorage:WaitForChild("GameShared")
local EndpointNames = require(GameShared:WaitForChild("Network"):WaitForChild("EndpointNames"))
local RoundHud = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("RoundHud"))

type Snapshot = RoundHud.Snapshot

local RoundController = {
	Name = "RoundController",
	Order = 100,
	_snapshot = nil :: Snapshot?,
	_requestRemote = nil :: RemoteEvent?,
	_snapshotConnection = nil :: RBXScriptConnection?,
	_lastRequest = -math.huge,
	_hud = nil :: any,
}

local PHASES: { [string]: boolean } = {
	ready = true,
	preparing = true,
	active = true,
	escaped = true,
	aborted = true,
}
local ACTIONS: { [string]: boolean } = {
	start = true,
	retry = true,
	abort = true,
	menu = true,
}
local DEBOUNCE_SEC = 0.55
local REMOTE_WAIT_SEC = 10

local function nonnegativeNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value >= 0 and value < math.huge
end

local function validSnapshot(value: any): boolean
	return typeof(value) == "table"
		and typeof(value.phase) == "string"
		and PHASES[value.phase] == true
		and typeof(value.has_key) == "boolean"
		and typeof(value.gate_open) == "boolean"
		and nonnegativeNumber(value.session_diamonds)
		and nonnegativeNumber(value.reward_diamonds)
		and nonnegativeNumber(value.elapsed_sec)
		and typeof(value.notice) == "string"
		and nonnegativeNumber(value.stamina)
		and nonnegativeNumber(value.stamina_capacity)
		and value.stamina_capacity > 0
		and value.stamina <= value.stamina_capacity
		and typeof(value.is_sprinting) == "boolean"
		and typeof(value.sprint_exhausted) == "boolean"
		and typeof(value.start_look) == "Vector3"
		and value.start_look.Magnitude > 0.99
		and value.start_look.Magnitude < 1.01
		and math.abs(value.start_look.Y) < 0.001
end

local function getRemote(folder: Instance, name: string): RemoteEvent?
	local instance = folder:WaitForChild(name, REMOTE_WAIT_SEC)
	if not instance or not instance:IsA("RemoteEvent") then
		warn(
			string.format(
				"[RoundController] RemoteEvent %s is unavailable after %ds",
				name,
				REMOTE_WAIT_SEC
			)
		)
		return nil
	end
	return instance
end

function RoundController:Init(_context: any)
	self._snapshot = nil :: Snapshot?
	self._requestRemote = nil :: RemoteEvent?
	self._snapshotConnection = nil :: RBXScriptConnection?
	self._lastRequest = -math.huge
	self._hud = nil

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui", REMOTE_WAIT_SEC)
	if not playerGui or not playerGui:IsA("PlayerGui") then
		warn("[RoundController] PlayerGui is unavailable; the round interface was not created")
		return
	end
	self._hud = RoundHud.new(playerGui)
	self._hud:SetOnAction(function(action: string)
		self:_request(action)
	end)
end

function RoundController:_request(action: string)
	local remote = self._requestRemote
	local hud = self._hud
	if not remote or not hud or not self._snapshot or ACTIONS[action] ~= true then
		return
	end
	local now = os.clock()
	if now - self._lastRequest < DEBOUNCE_SEC then
		return
	end
	self._lastRequest = now
	hud:SetBusy(true)
	remote:FireServer(action)
	-- Only the server changes the view. A rejected request must not leave buttons stuck.
	task.delay(DEBOUNCE_SEC, function()
		if self._hud == hud then
			hud:SetBusy(false)
		end
	end)
end

function RoundController:Start(context: any)
	local hud = self._hud
	if not hud then
		return
	end
	local folder = ReplicatedStorage:WaitForChild("GameRemotes", REMOTE_WAIT_SEC)
	if not folder or not folder:IsA("Folder") then
		warn("[RoundController] GameRemotes is unavailable; check RoundService startup in Output")
		hud:ShowUnavailable()
		return
	end
	local requestRemote = getRemote(folder, EndpointNames.RequestRoundAction)
	local snapshotRemote = getRemote(folder, EndpointNames.RoundSnapshot)
	if not requestRemote or not snapshotRemote then
		hud:ShowUnavailable()
		return
	end
	self._requestRemote = requestRemote
	self._snapshotConnection = snapshotRemote.OnClientEvent:Connect(function(payload: any)
		if not validSnapshot(payload) then
			warn("[RoundController] Ignored a malformed round_snapshot")
			return
		end
		self._snapshot = payload :: Snapshot
		hud:Render(payload :: Snapshot)
		context.Controllers.MovementController:SetSnapshot(payload)
	end)

	-- Subscribe first: initial server messages may precede the client controller.
	requestRemote:FireServer("sync")
	task.delay(2, function()
		if self._hud == hud and self._snapshot == nil then
			requestRemote:FireServer("sync")
		end
	end)
	task.delay(REMOTE_WAIT_SEC, function()
		if self._hud == hud and self._snapshot == nil then
			warn("[RoundController] No valid initial round_snapshot; check RoundService Output")
			hud:ShowUnavailable()
		end
	end)
end

function RoundController:Destroy()
	if self._snapshotConnection then
		self._snapshotConnection:Disconnect()
		self._snapshotConnection = nil
	end
	if self._hud then
		self._hud:Destroy()
		self._hud = nil
	end
	self._requestRemote = nil
end

return RoundController
]========] },
{ path = [========[StarterPlayer/StarterPlayerScripts/GameClient/Game/RoundHud]========], class = [========[ModuleScript]========], source = [========[--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RoundText: { [string]: string } = require(
	ReplicatedStorage:WaitForChild("GameShared"):WaitForChild("Game"):WaitForChild("RoundText")
)

export type Snapshot = {
	phase: string,
	has_key: boolean,
	gate_open: boolean,
	session_diamonds: number,
	reward_diamonds: number,
	elapsed_sec: number,
	notice: string,
	stamina: number,
	stamina_capacity: number,
	is_sprinting: boolean,
	sprint_exhausted: boolean,
	start_look: Vector3,
}

local RoundHud = {}
RoundHud.__index = RoundHud

local PANEL_COLOR = Color3.fromRGB(27, 32, 28)
local TEXT_COLOR = Color3.fromRGB(239, 242, 233)
local MUTED_COLOR = Color3.fromRGB(190, 199, 186)
local BUTTON_COLOR = Color3.fromRGB(84, 109, 67)
local DISABLED_COLOR = Color3.fromRGB(63, 69, 61)

local function text(key: string, values: { [string]: string | number }?): string
	local template = RoundText[key] or ""
	return (
		string.gsub(template, "{([%w_]+)}", function(name)
			local value = if values then values[name] else nil
			return if value ~= nil then tostring(value) else "{" .. name .. "}"
		end)
	)
end

local function elapsedText(seconds: number): string
	local whole = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", math.floor(whole / 60), whole % 60)
end

local function label(
	parent: Instance,
	name: string,
	size: UDim2,
	position: UDim2,
	fontSize: number
): TextLabel
	local result = Instance.new("TextLabel")
	result.Name = name
	result.Size = size
	result.Position = position
	result.BackgroundTransparency = 1
	result.Font = Enum.Font.Gotham
	result.TextSize = fontSize
	result.TextColor3 = TEXT_COLOR
	result.TextWrapped = true
	result.TextXAlignment = Enum.TextXAlignment.Left
	result.TextYAlignment = Enum.TextYAlignment.Center
	result.Text = ""
	result.Parent = parent
	return result
end

local function button(
	parent: Instance,
	name: string,
	key: string,
	size: UDim2,
	position: UDim2
): TextButton
	local result = Instance.new("TextButton")
	result.Name = name
	result.Size = size
	result.Position = position
	result.BackgroundColor3 = BUTTON_COLOR
	result.BorderSizePixel = 0
	result.Font = Enum.Font.GothamMedium
	result.TextSize = 17
	result.TextColor3 = TEXT_COLOR
	result.Text = text(key)
	result.Modal = parent.Name == "RoundCard"
	result.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = result
	return result
end

local function panel(parent: Instance, name: string, size: UDim2, position: UDim2): Frame
	local result = Instance.new("Frame")
	result.Name = name
	result.Size = size
	result.Position = position
	result.BackgroundColor3 = PANEL_COLOR
	result.BackgroundTransparency = 0.08
	result.BorderSizePixel = 0
	result.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = result
	return result
end

function RoundHud.new(playerGui: PlayerGui)
	local root = Instance.new("ScreenGui")
	root.Name = "CornRoundHud"
	root.ResetOnSpawn = false
	root.DisplayOrder = 10
	root.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	root.Parent = playerGui

	local card = panel(root, "RoundCard", UDim2.fromOffset(460, 320), UDim2.fromScale(0.5, 0.5))
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	local title = label(card, "Title", UDim2.new(1, -48, 0, 38), UDim2.fromOffset(24, 20), 27)
	title.Font = Enum.Font.GothamBold
	local message = label(card, "Message", UDim2.new(1, -48, 0, 52), UDim2.fromOffset(24, 68), 19)
	local resultTime =
		label(card, "Elapsed", UDim2.new(1, -48, 0, 26), UDim2.fromOffset(24, 124), 16)
	resultTime.TextColor3 = MUTED_COLOR
	local balance = label(card, "Balance", UDim2.new(1, -48, 0, 26), UDim2.fromOffset(24, 154), 16)
	balance.TextColor3 = MUTED_COLOR
	local notice = label(card, "Notice", UDim2.new(1, -48, 0, 46), UDim2.fromOffset(24, 186), 16)
	notice.TextColor3 = Color3.fromRGB(233, 209, 142)
	local start = button(
		card,
		"Start",
		"corn_loop_start",
		UDim2.new(1, -48, 0, 44),
		UDim2.fromOffset(24, 250)
	)
	local retry = button(
		card,
		"Retry",
		"corn_loop_retry",
		UDim2.new(0.5, -30, 0, 44),
		UDim2.fromOffset(24, 250)
	)
	local menu = button(
		card,
		"Menu",
		"corn_loop_menu",
		UDim2.new(0.5, -30, 0, 44),
		UDim2.new(0.5, 6, 0, 250)
	)
	local preparingLeave = button(
		card,
		"Leave",
		"corn_loop_leave",
		UDim2.new(1, -48, 0, 44),
		UDim2.fromOffset(24, 250)
	)

	local active = panel(root, "ActiveStatus", UDim2.new(0.64, 0, 0, 128), UDim2.fromOffset(20, 16))
	local activeConstraint = Instance.new("UISizeConstraint")
	activeConstraint.MaxSize = Vector2.new(690, 128)
	activeConstraint.Parent = active
	local objective =
		label(active, "Objective", UDim2.new(1, -32, 0, 32), UDim2.fromOffset(16, 8), 19)
	objective.Font = Enum.Font.GothamMedium
	local activeTime =
		label(active, "Elapsed", UDim2.new(1, -32, 0, 24), UDim2.fromOffset(16, 42), 15)
	activeTime.TextColor3 = MUTED_COLOR
	local activeBalance =
		label(active, "Balance", UDim2.new(1, -32, 0, 24), UDim2.fromOffset(16, 66), 15)
	activeBalance.TextColor3 = MUTED_COLOR
	local activeNotice =
		label(active, "Notice", UDim2.new(1, -32, 0, 24), UDim2.fromOffset(16, 94), 16)
	activeNotice.TextColor3 = notice.TextColor3
	local activeLeave = button(
		root,
		"LeaveRound",
		"corn_loop_leave",
		UDim2.fromOffset(185, 40),
		UDim2.new(1, -205, 0, 16)
	)

	local self = setmetatable({
		_root = root,
		_card = card,
		_title = title,
		_message = message,
		_time = resultTime,
		_balance = balance,
		_notice = notice,
		_active = active,
		_objective = objective,
		_activeTime = activeTime,
		_activeBalance = activeBalance,
		_activeNotice = activeNotice,
		_start = start,
		_retry = retry,
		_menu = menu,
		_preparingLeave = preparingLeave,
		_activeLeave = activeLeave,
		_buttons = { start, retry, menu, preparingLeave, activeLeave },
		_connections = {} :: { RBXScriptConnection },
		_snapshot = nil :: Snapshot?,
		_busy = false,
		_unavailable = false,
	}, RoundHud)
	self:_render()
	return self
end

function RoundHud:SetOnAction(callback: (string) -> ())
	local bindings = {
		{ button = self._start, action = "start" },
		{ button = self._retry, action = "retry" },
		{ button = self._menu, action = "menu" },
		{ button = self._preparingLeave, action = "abort" },
		{ button = self._activeLeave, action = "abort" },
	}
	for _, binding in bindings do
		table.insert(
			self._connections,
			binding.button.Activated:Connect(function()
				if not self._busy and not self._unavailable and self._snapshot ~= nil then
					callback(binding.action)
				end
			end)
		)
	end
end

function RoundHud:_render()
	local snapshot = self._snapshot
	local phase = if snapshot then snapshot.phase else "loading"
	local isActive = phase == "active"
	local isResult = phase == "escaped" or phase == "aborted"
	self._card.Visible = not isActive
	self._active.Visible = isActive
	self._activeLeave.Visible = isActive
	self._start.Visible = phase == "ready" or phase == "loading"
	self._retry.Visible = isResult
	self._menu.Visible = isResult
	self._preparingLeave.Visible = phase == "preparing"
	for _, control in self._buttons do
		local enabled = snapshot ~= nil and not self._busy and not self._unavailable
		control.Active = enabled
		control.AutoButtonColor = enabled
		control.BackgroundColor3 = if enabled then BUTTON_COLOR else DISABLED_COLOR
		control.TextTransparency = if enabled then 0 else 0.35
	end

	self._title.Text = text("corn_loop_title")
	self._time.Text = ""
	self._notice.Text = if snapshot then text(snapshot.notice) else ""
	self._balance.Visible = snapshot ~= nil
	self._balance.Text = text(
		"corn_loop_test_balance",
		{ count = if snapshot then snapshot.session_diamonds else 0 }
	)
	if self._unavailable then
		self._message.Text = text("corn_loop_connection_error")
	elseif phase == "loading" or phase == "preparing" then
		self._message.Text = text("corn_loop_loading")
	elseif phase == "ready" then
		self._message.Text = text("corn_loop_objective_search")
	elseif snapshot and isResult then
		self._title.Text = text(
			if phase == "escaped" then "corn_loop_result_escape" else "corn_loop_result_aborted"
		)
		self._message.Text = if phase == "escaped"
			then text("corn_loop_reward", { count = snapshot.reward_diamonds })
			else ""
		self._time.Text = text("corn_loop_round_time", { time = elapsedText(snapshot.elapsed_sec) })
	end

	if snapshot and isActive then
		local objectiveKey = if snapshot.gate_open
			then "corn_loop_objective_exit"
			elseif snapshot.has_key then "corn_loop_objective_return"
			else "corn_loop_objective_search"
		self._objective.Text = text(objectiveKey)
		self._activeTime.Text =
			text("corn_loop_round_time", { time = elapsedText(snapshot.elapsed_sec) })
		self._activeBalance.Text = self._balance.Text
		self._activeNotice.Text = text(snapshot.notice)
	end
end

function RoundHud:Render(snapshot: Snapshot)
	self._unavailable = false
	self._snapshot = snapshot
	self:_render()
end

function RoundHud:SetBusy(busy: boolean)
	self._busy = busy
	self:_render()
end

function RoundHud:ShowUnavailable()
	self._unavailable = true
	self:_render()
end

function RoundHud:Destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	self._root:Destroy()
end

return RoundHud
]========] }
}
local prior = {}
for _, entry in baseline do prior[entry.path] = entry end
local previous = {}
for _, entry in previousRepair do previous[entry.path] = entry end
local objects = {}
for _, entry in updates do
    local item = resolve(entry.path)
    local old = prior[entry.path]
    if not item then
        assert(not old and entry.class == "ModuleScript", "Missing code object: " .. entry.path .. "; nothing changed")
        local parentPath = string.match(entry.path, "^(.*)/[^/]+$")
        assert(resolve(parentPath), "Missing code parent: " .. entry.path .. "; nothing changed")
        continue
    end
    assert(item.ClassName == entry.class, "Code class collision: " .. entry.path .. "; nothing changed")
    assert(editor:FindScriptDocument(item) == nil, "Close script tab: " .. entry.path .. "; nothing changed")
    assert((old and normalized(item.Source) == normalized(old.source))
        or (previous[entry.path] and normalized(item.Source) == normalized(previous[entry.path].source))
        or normalized(item.Source) == normalized(entry.source),
        "Unrecognized manual Source edit: " .. entry.path .. "; nothing changed")
    if freshPaths[entry.path] then
        assert(#item:GetChildren() == 0, "Authoring module contains extra objects: " .. entry.path .. "; nothing changed")
    end
    objects[entry.path] = item
end
local oldPreview = map:FindFirstChild("EditorPreview")
local oldOverview = map:FindFirstChild("EditorFieldOverview")
for _, record in {{oldPreview, "CornEditorPreview"}, {oldOverview, "CornEditorOverview"}} do
    local folder = record[1]
    if folder then
        assert(folder:IsA("Folder") and folder:GetAttribute(record[2]) == true
            and folder:GetAttribute("corn_project_id") == "children_of_corn", "Unrecognized authoring layer; nothing changed")
    end
end
local art = game:GetService("ServerStorage")
local artSource = art:FindFirstChild("CornPlantTemplate") or art:FindFirstChild("SM_Prop_Plant_Corn_01_L")
assert(artSource, "Corn source missing; nothing changed")
local function shape(item, rootName)
    local children = {}
    for _, child in item:GetChildren() do table.insert(children, shape(child)) end
    table.sort(children)
    return item.ClassName .. ":" .. (rootName or item.Name) .. "[" .. table.concat(children, "|") .. "]"
end
local sourceMesh = if artSource:IsA("MeshPart") then artSource else artSource:FindFirstChildWhichIsA("MeshPart", true)
assert(sourceMesh and sourceMesh:IsA("MeshPart"), "Expected imported corn mesh; nothing changed")
local modelShape = shape(artSource, "Corn")
local meshShape = shape(sourceMesh, "Corn")
if oldPreview then
    for _, item in oldPreview:GetChildren() do
        local itemShape = shape(item)
        assert(item.Name == "Corn" and (itemShape == modelShape or itemShape == meshShape),
            "EditorPreview contains manual objects; nothing changed")
    end
end
if oldOverview then
    local overviewShape = shape(sourceMesh, "DistantCorn")
    for _, item in oldOverview:GetChildren() do
        assert(item:IsA("MeshPart") and item:GetAttribute("CornEditorOverview") == true
            and item:GetAttribute("corn_project_id") == "children_of_corn" and shape(item) == overviewShape,
            "EditorFieldOverview contains manual objects; nothing changed")
    end
end
local oldCorners = map:FindFirstChild("CornerSpawns")
local lowerSpawn = world:FindFirstChild("SpawnLocation")
local lowerWasEnabled = if lowerSpawn and lowerSpawn:IsA("SpawnLocation") then lowerSpawn.Enabled else nil
local previousVersion = map:GetAttribute("map_version")
local changed, swapped, created = {}, {}, {}
local layersDetached = false
local history = game:GetService("ChangeHistoryService")
history:SetWaypoint("Before Corn spawn and field repair")
local ok, problem = pcall(function()
    for _, entry in updates do
        local item = objects[entry.path]
        if not item then
            local parentPath, name = string.match(entry.path, "^(.*)/([^/]+)$")
            item = Instance.new(entry.class)
            item.Name = name
            table.insert(created, item)
            item.Source = entry.source
            item.Parent = resolve(parentPath)
            objects[entry.path] = item
        end
        if freshPaths[entry.path] then
            -- New instances avoid edit-mode require() caches from the original install.
            local replacement = item:Clone()
            assert(replacement, "Module clone failed")
            replacement.Source = entry.source
            local parent = item.Parent
            item.Parent = nil
            replacement.Parent = parent
            table.insert(swapped, {old=item, new=replacement, parent=parent})
        else
            table.insert(changed, {item=item, source=item.Source})
            item.Source = entry.source
        end
    end
    if oldPreview then oldPreview.Parent = nil end
    if oldOverview then oldOverview.Parent = nil end
    layersDetached = true
    local author = require(resolve("ServerScriptService/GameServer/Game/MapAuthoring"))
    local corners = author.EnsureCornerSpawns(map)
    local selected = corners:FindFirstChild("SW")
    assert(selected and selected:IsA("SpawnLocation"), "SW corner is missing")
    author.RebuildOverview(map)
    author.Preview(map, selected.Position)
    local field = map:FindFirstChild("FieldZone")
    if lowerWasEnabled ~= nil and field and field:IsA("BasePart")
        and lowerSpawn.Position.Y < field.Position.Y - field.Size.Y / 2 - 10 then
        lowerSpawn.Enabled = false
    end
    map:SetAttribute("map_version", 2)
    game:GetService("Selection"):Set({selected})
end)
if not ok then
    if layersDetached then
        for _, name in {"EditorPreview", "EditorFieldOverview"} do
            local newLayer = map:FindFirstChild(name)
            if newLayer then newLayer:Destroy() end
        end
    end
    if not oldCorners then
        local corners = map:FindFirstChild("CornerSpawns")
        if corners then corners:Destroy() end
    end
    if oldPreview then oldPreview.Parent = map end
    if oldOverview then oldOverview.Parent = map end
    if lowerWasEnabled ~= nil then lowerSpawn.Enabled = lowerWasEnabled end
    map:SetAttribute("map_version", previousVersion)
    for _, entry in changed do entry.item.Source = entry.source end
    for index = #created, 1, -1 do created[index]:Destroy() end
    for index = #swapped, 1, -1 do
        local entry = swapped[index]
        entry.new:Destroy()
        entry.old.Parent = entry.parent
    end
    error("Corn scene repair rolled back: " .. tostring(problem))
end
if oldPreview then oldPreview:Destroy() end
if oldOverview then oldOverview:Destroy() end
for _, entry in swapped do entry.old:Destroy() end
history:SetWaypoint("Repaired Corn corner starts and dense field")
print("ChildrenOfCorn scene repaired: 4 corner spawns, dense corn, full field overview; press F, SAVE, then Play")
