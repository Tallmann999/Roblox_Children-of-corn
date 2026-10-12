--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local Shared = ReplicatedStorage:WaitForChild("GameShared"):WaitForChild("Game")
local Inventory = require(Shared:WaitForChild("Inventory"))
local Presentation = require(Shared:WaitForChild("HandheldPresentation"))
local player = Players.LocalPlayer
local MODEL_NAME = "CornHandheld"
local PROJECT = "children_of_corn"
local BINDING = "CornHandheldPresentation"
local Controller = { Name = "HandheldController", Order = 97 }

function Controller:Init(_context: any)
	self._snapshot = nil
	self._roundId = -1
	self._useId = 0
	self._endedRound = nil
	self._gesture = nil
	self._visual = nil
	self._camera = nil
	self._character = nil
	self._kind = nil
	self._minimap = nil
	self._capture = nil
	self._connections = {}
	self._bound = false
	self._generation = 0
	self._refused = nil
end

function Controller:_clearVisual()
	local model = self._visual
	self._visual = nil
	self._kind = nil
	self._character = nil
	self._camera = nil
	if model then
		if
			model:GetAttribute("CornHandheldOwned") == true
			and model:GetAttribute("corn_project_id") == PROJECT
			and model:GetAttribute("HandheldVersion") == 1
		then
			model:Destroy()
		else
			warn("[HandheldController] Changed held model preserved")
		end
	end
end

function Controller:_cancelGesture()
	self._gesture = nil
	self._generation += 1
end

function Controller:Clear(_reason: string?)
	self._snapshot = nil
	self:_cancelGesture()
	self:_clearVisual()
end

function Controller:_livingCharacter(): (Model?, Humanoid?)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if character and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return character, humanoid
	end
	return nil, nil
end

function Controller:_canShow(camera: Camera?, humanoid: Humanoid?): boolean
	return self._snapshot ~= nil
		and self._snapshot.phase == "active"
		and camera ~= nil
		and humanoid ~= nil
		and camera.CameraType == Enum.CameraType.Custom
		and camera.CameraSubject == humanoid
		and camera:GetAttribute("CornCaptureCameraOwner") == nil
		and player.CameraMode == Enum.CameraMode.LockFirstPerson
		and not GuiService.MenuIsOpen
		and not (self._minimap and self._minimap._expanded)
		and not (self._capture and self._capture._state.active)
end

local function skin(character: Model, side: string): Color3
	for _, name in { side .. "Hand", side .. " Arm", side .. "LowerArm" } do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part.Color
		end
	end
	return Color3.fromRGB(191, 145, 110)
end

function Controller:_buildVisual(kind: string, camera: Camera, character: Model): boolean
	local existing = camera:FindFirstChild(MODEL_NAME)
	if existing then
		if self._refused ~= existing then
			self._refused = existing
			warn("[HandheldController] Existing held model refused; unknown ownership/state")
		end
		return false
	end
	local definitions = Presentation.Definitions(kind)
	if #definitions == 0 then
		return false
	end
	assert(#definitions + #Presentation.Hands + 1 <= 24, "Held geometry exceeds24parts")
	local model = Instance.new("Model")
	model.Name = MODEL_NAME
	model:SetAttribute("CornHandheldOwned", true)
	model:SetAttribute("corn_project_id", PROJECT)
	model:SetAttribute("HandheldVersion", 1)
	model:SetAttribute("ItemKind", kind)
	local function part(
		name: string,
		size: Vector3,
		frame: CFrame,
		color: Color3,
		material: Enum.Material,
		shape: Enum.PartType?
	): Part
		local item = Instance.new("Part")
		item.Name = name
		item.Size = size
		item.CFrame = frame
		item.Color = color
		item.Material = material
		if shape then
			item.Shape = shape
		end
		item.Anchored = true
		item.CanCollide = false
		item.CanTouch = false
		item.CanQuery = false
		item.CastShadow = false
		item.Parent = model
		return item
	end
	local anchor = part(
		"Anchor",
		Vector3.new(0.08, 0.08, 0.08),
		CFrame.identity,
		Color3.new(),
		Enum.Material.SmoothPlastic,
		nil
	)
	anchor.Transparency = 1
	model.PrimaryPart = anchor
	for _, definition in definitions do
		local item = part(
			definition.name,
			definition.size,
			definition.localFrame,
			definition.color,
			definition.material,
			definition.shape
		)
		if kind == "energy" and definition.name == "Can" then
			local label = Instance.new("SurfaceGui")
			label.Name = "EnergyLabel"
			label.Face = Enum.NormalId.Back
			label.AlwaysOnTop = false
			label.LightInfluence = 0
			label.Active = false
			label.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
			label.CanvasSize = Vector2.new(256, 256)
			label.Parent = item
			local paper = Instance.new("Frame")
			paper.Name = "Paper"
			paper.AnchorPoint = Vector2.new(0.5, 0.5)
			paper.Position = UDim2.fromScale(0.5, 0.5)
			paper.Size = UDim2.fromScale(0.8, 0.8)
			paper.Rotation = 90
			paper.BackgroundColor3 = Color3.fromRGB(33, 135, 69)
			paper.BorderSizePixel = 0
			paper.Parent = label
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 12)
			corner.Parent = paper
			local logo = Instance.new("TextLabel")
			logo.Name = "Logo"
			logo.Size = UDim2.fromScale(1, 0.6)
			logo.Position = UDim2.fromScale(0, 0.04)
			logo.BackgroundTransparency = 1
			logo.Font = Enum.Font.GothamBold
			logo.TextSize = 100
			logo.TextColor3 = Color3.new(1, 1, 1)
			logo.Text = "+"
			logo.Parent = paper
			local name = logo:Clone()
			name.Name = "Name"
			name.Size = UDim2.fromScale(1, 0.22)
			name.Position = UDim2.fromScale(0, 0.68)
			name.TextSize = 30
			name.Text = "ENERGY"
			name.Parent = paper
		end
	end
	for _, hand in Presentation.Hands do
		part(
			hand.name,
			hand.size,
			hand.localFrame,
			skin(character, if string.find(hand.name, "Left", 1, true) then "Left" else "Right"),
			Enum.Material.SmoothPlastic,
			nil
		)
	end
	self._visual, self._camera, self._character, self._kind = model, camera, character, kind
	self._refused = nil
	model.Parent = camera
	return true
end

function Controller:_step(now: number)
	local camera = workspace.CurrentCamera
	local character, humanoid = self:_livingCharacter()
	if not self:_canShow(camera, humanoid) then
		self:_cancelGesture()
		self:_clearVisual()
		return
	end
	if self._camera and camera ~= self._camera then
		self:_cancelGesture()
		self:_clearVisual()
		return
	end
	local gesture = self._gesture
	if gesture and now >= gesture.deadline then
		self:_cancelGesture()
		gesture = nil
	end
	local inventory = self._snapshot.inventory
	local kind = if gesture then gesture.kind else inventory.slots[inventory.selected]
	if kind == "empty" then
		self:_clearVisual()
		return
	end
	if
		self._visual
		and (self._kind ~= kind or self._character ~= character or self._visual.Parent ~= camera)
	then
		self:_clearVisual()
	end
	if
		self._visual
		and (
			self._visual:GetAttribute("CornHandheldOwned") ~= true
			or self._visual:GetAttribute("corn_project_id") ~= PROJECT
			or self._visual:GetAttribute("HandheldVersion") ~= 1
			or self._visual:GetAttribute("ItemKind") ~= kind
		)
	then
		self:_cancelGesture()
		self:_clearVisual()
		return
	end
	if not self._visual and not self:_buildVisual(kind, camera :: Camera, character :: Model) then
		return
	end
	local elapsed = if gesture then math.max(0, now - gesture.started) else 0
	local viewport = (camera :: Camera).ViewportSize
	local aspect = if viewport.Y > 0 then viewport.X / viewport.Y else 16 / 9
	self._visual:PivotTo(
		(camera :: Camera).CFrame * Presentation.GetPose(kind, elapsed, gesture ~= nil, aspect)
	)
end

function Controller:_beginGesture(kind: string, selected: number, now: number)
	local duration = Presentation.Duration(kind)
	if duration <= 0 then
		return
	end
	self:_cancelGesture()
	self._gesture = { kind = kind, selected = selected, started = now, deadline = now + duration }
	local generation = self._generation
	task.delay(duration, function()
		if
			self._generation == generation
			and self._gesture
			and os.clock() >= self._gesture.deadline
		then
			self:_cancelGesture()
			self:_step(os.clock())
		end
	end)
end

function Controller:SetSnapshot(snapshot: any)
	if
		type(snapshot) ~= "table"
		or type(snapshot.minimap) ~= "table"
		or not Inventory.IsValidSnapshot(snapshot.inventory)
	then
		self:Clear("malformed")
		return
	end
	local roundId = snapshot.minimap.round_id
	local use = snapshot.inventory.use
	if
		type(roundId) ~= "number"
		or roundId % 1 ~= 0
		or roundId < self._roundId
		or type(use) ~= "table"
		or type(use.id) ~= "number"
		or use.id % 1 ~= 0
		or use.id < 0
		or use.id == math.huge
	then
		return
	end
	if
		roundId == self._roundId
		and snapshot.phase == "active"
		and (use.id < self._useId or self._endedRound == roundId)
	then
		return
	end
	local first = roundId ~= self._roundId
	local previous = self._snapshot
	if first then
		self:_cancelGesture()
		self:_clearVisual()
		self._roundId, self._useId = roundId, use.id
		self._endedRound = nil
	end
	self._snapshot = snapshot
	if
		snapshot.phase == "escaped"
		or snapshot.phase == "aborted"
		or snapshot.phase == "caught_out"
	then
		self._endedRound = roundId
	end
	local selected = snapshot.inventory.selected
	if
		self._gesture
		and previous
		and (
			previous.inventory.selected ~= selected
			or (
				previous.inventory.slots[selected] ~= snapshot.inventory.slots[selected]
				and snapshot.inventory.slots[selected] ~= "empty"
			)
		)
	then
		self:_cancelGesture()
	end
	if not first and use.id > self._useId then
		self._useId = use.id
		local camera = workspace.CurrentCamera
		local _, humanoid = self:_livingCharacter()
		if (use.kind == "energy" or use.kind == "trap") and self:_canShow(camera, humanoid) then
			self:_beginGesture(use.kind, selected, os.clock())
		end
	end
	self:_step(os.clock())
end

function Controller:Start(context: any)
	self._minimap = context.Controllers.MinimapController
	self._capture = context.Controllers.CaptureController
	RunService:BindToRenderStep(BINDING, Enum.RenderPriority.Camera.Value + 2, function()
		self:_step(os.clock())
	end)
	self._bound = true
	table.insert(
		self._connections,
		GuiService.MenuOpened:Connect(function()
			self:_cancelGesture()
			self:_clearVisual()
		end)
	)
	for _, signal in { player.CharacterAdded, player.CharacterRemoving } do
		table.insert(
			self._connections,
			signal:Connect(function()
				self:Clear("character changed")
			end)
		)
	end
end

function Controller:Destroy()
	self:Clear("destroy")
	if self._bound then
		RunService:UnbindFromRenderStep(BINDING)
		self._bound = false
	end
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	self._minimap, self._capture = nil, nil
end

return Controller
