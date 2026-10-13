--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local Shared = ReplicatedStorage:WaitForChild("GameShared"):WaitForChild("Game")
local Capture = require(Shared:WaitForChild("CapturePresentation"))
local Pose = require(Shared:WaitForChild("MonsterPose"))
local player = Players.LocalPlayer
local VISUAL_NAME = "CornCaptureVisual"
local CAMERA_OWNER = "CornCaptureCameraOwner"
local BINDING = "CornCaptureCamera"
local PROJECT = "children_of_corn"
-- Lift only the decorative shot above nearby corn; server catch geometry stays exact.
local PRESENTATION_OFFSET = CFrame.new(0, 4, 0)
local Controller = { Name = "CaptureController", Order = 92 }

function Controller:Init(_context: any)
	self._state = Capture.NewState()
	self._snapshot = nil
	self._movement = nil
	self._minimap = nil
	self._round = nil
	self._visual = nil
	self._parts = {}
	self._hiddenServer = {}
	self._saved = nil
	self._token = nil
	self._generation = 0
	self._bound = false
	self._connections = {}
	self._deathConnection = nil
end

local function knownMonster(model: Instance?): boolean
	return model ~= nil
		and model:IsA("Model")
		and model:GetAttribute("CornMonsterOwned") == true
		and model:GetAttribute("corn_project_id") == PROJECT
		and model:GetAttribute("MonsterRigVersion") == 1
end

function Controller:_hideServerRig()
	local map = workspace:FindFirstChild("CornMap")
	local runtime = if map and map:GetAttribute("corn_project_id") == PROJECT
		then map:FindFirstChild("CornRoundRuntime")
		else nil
	local model = if runtime and runtime:GetAttribute("corn_project_id") == PROJECT
		then runtime:FindFirstChild("Monster")
		else nil
	if not knownMonster(model) then
		return
	end
	local children = model:GetChildren()
	if #children ~= #Pose.Parts + 1 then
		return
	end
	local allowed = { Root = true }
	for _, definition in Pose.Parts do
		allowed[definition.Name] = true
		local part = model:FindFirstChild(definition.Name)
		if not part or not part:IsA("BasePart") or part.Size ~= definition.Size then
			return
		end
	end
	for _, child in children do
		if not allowed[child.Name] or not child:IsA("BasePart") then
			return
		end
		allowed[child.Name] = nil
	end
	for _, definition in Pose.Parts do
		local part = model:FindFirstChild(definition.Name) :: BasePart
		table.insert(
			self._hiddenServer,
			{ part = part, previous = part.LocalTransparencyModifier, model = model }
		)
		part.LocalTransparencyModifier = 1
	end
end

function Controller:_restoreServerRig()
	for _, entry in self._hiddenServer do
		if
			knownMonster(entry.model)
			and entry.part.Parent == entry.model
			and entry.part.LocalTransparencyModifier == 1
		then
			entry.part.LocalTransparencyModifier = entry.previous
		end
	end
	table.clear(self._hiddenServer)
end

function Controller:_livingCharacter(): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if character and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return character, humanoid, root
	end
	return nil, nil, nil
end

function Controller:_presentation(active: boolean)
	if self._minimap and active then
		self._minimap:SetExpanded(false)
	end
	if self._movement then
		self._movement:SetCaptureActive(active)
	end
	local hud = if self._round then self._round._hud else nil
	if hud then
		hud:SetCaptureActive(active)
	end
end

function Controller:_buildVisual(frame: CFrame): boolean
	frame *= PRESENTATION_OFFSET
	if workspace:FindFirstChild(VISUAL_NAME) then
		warn("[CaptureController] Existing capture visual refused; unknown ownership/state")
		return false
	end
	assert(#Pose.Parts == 9, "Capture pose requires exactly nine decorative parts")
	local model = Instance.new("Model")
	model.Name = VISUAL_NAME
	model:SetAttribute("CornCaptureOwned", true)
	model:SetAttribute("corn_project_id", PROJECT)
	model:SetAttribute("CaptureRigVersion", 1)
	model:SetAttribute("MonsterHeightScale", Pose.HeightScale)
	local parts = {}
	for _, definition in Pose.Parts do
		assert(
			not parts[definition.Name] and typeof(Pose.Rest[definition.Name]) == "CFrame",
			"Invalid capture rig definition"
		)
		local part = Instance.new("Part")
		part.Name = definition.Name
		part.Size = definition.Size
		part.Color = definition.Color
		part.Material = definition.Material
		part.CFrame = frame * Pose.Rest[definition.Name]
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Parent = model
		parts[definition.Name] = part
	end
	local light = Instance.new("PointLight")
	light.Name = "CaptureFaceLight"
	light.Brightness = 1
	light.Range = 12
	light.Shadows = false
	light.Color = Color3.fromRGB(255, 206, 154)
	light.Parent = assert(parts.Head, "Capture face missing")
	self._visual, self._parts = model, parts
	model.Parent = workspace
	return true
end

function Controller:_restoreCamera()
	local saved = self._saved
	self._saved = nil
	if not saved or saved.camera:GetAttribute(CAMERA_OWNER) ~= self._token then
		return
	end
	local camera = saved.camera
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		-- Another camera controller changed the type without our token handshake.
		camera:SetAttribute(CAMERA_OWNER, nil)
		return
	end
	local character, humanoid, root = self:_livingCharacter()
	camera.FieldOfView = saved.fieldOfView
	camera.CameraSubject = if character ~= saved.character and humanoid
		then humanoid
		else saved.subject
	if
		root
		and self._snapshot
		and (self._snapshot.phase == "active" or self._snapshot.phase == "caught")
	then
		local direction = self._snapshot.start_look
		if typeof(direction) ~= "Vector3" or direction.Magnitude < 0.9 then
			direction = saved.frame.LookVector
		end
		local eye = root.Position + Vector3.new(0, 1.5, 0)
		camera.CFrame = CFrame.lookAt(eye, eye + direction)
	else
		camera.CFrame = saved.frame
	end
	camera.Focus = saved.focus
	camera.CameraType = saved.cameraType
	camera:SetAttribute(CAMERA_OWNER, nil)
end

function Controller:Cancel(_reason: string?)
	Capture.Cancel(self._state)
	self._generation += 1
	if self._bound then
		RunService:UnbindFromRenderStep(BINDING)
		self._bound = false
	end
	local visual = self._visual
	self._visual = nil
	self._parts = {}
	self:_restoreServerRig()
	if visual then
		if
			visual:GetAttribute("CornCaptureOwned") == true
			and visual:GetAttribute("corn_project_id") == PROJECT
			and visual:GetAttribute("CaptureRigVersion") == 1
		then
			visual:Destroy()
		else
			warn("[CaptureController] Changed capture visual preserved during cleanup")
		end
	end
	self:_restoreCamera()
	self._token = nil
	self:_presentation(false)
end

function Controller:_step(now: number)
	if self._minimap and self._minimap._expanded then
		self._minimap:SetExpanded(false)
	end
	local saved = self._saved
	if
		not self._state.active
		or now >= self._state.deadline
		or GuiService.MenuIsOpen
		or not saved
	then
		self:Cancel("deadline/menu")
		return
	end
	local _, humanoid = self:_livingCharacter()
	local camera = workspace.CurrentCamera
	if
		not humanoid
		or camera ~= saved.camera
		or camera:GetAttribute(CAMERA_OWNER) ~= self._token
		or camera.CameraType ~= Enum.CameraType.Scriptable
	then
		self:Cancel("camera/death")
		return
	end
	local elapsed = math.max(0, now - self._state.started)
	local pose = Pose.Get("capturing", elapsed, false)
	local frame = self._state.frame * PRESENTATION_OFFSET
	for name, part in self._parts do
		part.CFrame = frame * pose[name]
	end
	local progress = Capture.Progress(self._state, now)
	local eased = progress * progress * (3 - 2 * progress)
	local head = (frame * pose.Head).Position
	local distance = 8 - 4.2 * eased
	local position = head + frame.LookVector * distance + frame.UpVector * 0.15
	local target = head + frame.LookVector * 1.05
	camera.CFrame = CFrame.lookAt(position, target, frame.UpVector)
	camera.Focus = CFrame.new(target)
	camera.FieldOfView = 70 - 8 * eased
end

function Controller:_scheduleDeadline()
	local generation = self._generation
	task.delay(math.max(0, self._state.deadline - os.clock()), function()
		if
			self._generation == generation
			and self._state.active
			and os.clock() >= self._state.deadline
		then
			self:Cancel("wall-clock deadline")
		end
	end)
end

function Controller:_begin(): boolean
	local camera = workspace.CurrentCamera
	local character, humanoid = self:_livingCharacter()
	if
		GuiService.MenuIsOpen
		or not camera
		or not humanoid
		or camera:GetAttribute(CAMERA_OWNER) ~= nil
	then
		return false
	end
	if not self:_buildVisual(self._state.frame) then
		return false
	end
	self:_hideServerRig()
	self._generation += 1
	self._token = HttpService:GenerateGUID(false)
	self._saved = {
		camera = camera,
		cameraType = camera.CameraType,
		subject = camera.CameraSubject,
		fieldOfView = camera.FieldOfView,
		frame = camera.CFrame,
		focus = camera.Focus,
		character = character,
	}
	camera:SetAttribute(CAMERA_OWNER, self._token)
	self:_presentation(true)
	camera.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep(BINDING, Enum.RenderPriority.Camera.Value + 1, function()
		self:_step(os.clock())
	end)
	self._bound = true
	self:_step(os.clock())
	self:_scheduleDeadline()
	return true
end

function Controller:SetSnapshot(snapshot: any)
	local previousDeadline = self._state.deadline
	local roundId = if type(snapshot) == "table" and type(snapshot.minimap) == "table"
		then snapshot.minimap.round_id
		else nil
	local capture = if type(snapshot) == "table" then snapshot.capture else nil
	local phase = if type(snapshot) == "table" then snapshot.phase else nil
	local action = Capture.Observe(self._state, roundId, capture, phase, os.clock())
	self._snapshot = if type(snapshot) == "table" then snapshot else nil
	if action == "cancel" then
		self:Cancel("snapshot")
	elseif action == "begin" then
		-- Release the previous owned effect before replacing its confirmed identity.
		if self._saved then
			local confirmedState = self._state
			self._state = Capture.NewState()
			self:Cancel("new capture")
			self._state = confirmedState
		end
		if not self:_begin() then
			self:Cancel("unavailable")
		end
	elseif action == "keep" and self._state.deadline < previousDeadline - 0.001 then
		self:_scheduleDeadline()
	end
end

function Controller:_watchDeath(character: Model?)
	if self._deathConnection then
		self._deathConnection:Disconnect()
		self._deathConnection = nil
	end
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		self._deathConnection = humanoid.Died:Connect(function()
			self:Cancel("death")
		end)
	end
end

function Controller:Start(context: any)
	self._movement = context.Controllers.MovementController
	self._minimap = context.Controllers.MinimapController
	self._round = context.Controllers.RoundController
	self:_watchDeath(player.Character)
	table.insert(
		self._connections,
		GuiService.MenuOpened:Connect(function()
			self:Cancel("menu")
		end)
	)
	table.insert(
		self._connections,
		player.CharacterRemoving:Connect(function()
			self:Cancel("reset")
		end)
	)
	table.insert(
		self._connections,
		player.CharacterAdded:Connect(function(character)
			self:Cancel("respawn")
			self:_watchDeath(character)
		end)
	)
end

function Controller:Destroy()
	self:Cancel("destroy")
	if self._deathConnection then
		self._deathConnection:Disconnect()
		self._deathConnection = nil
	end
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	self._snapshot = nil
	self._movement, self._minimap, self._round = nil, nil, nil
end

return Controller
