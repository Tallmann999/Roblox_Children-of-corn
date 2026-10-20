--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Shared = ReplicatedStorage:WaitForChild("GameShared"):WaitForChild("Game")
local Presentation = require(Shared:WaitForChild("FlashlightPresentation"))
local player = Players.LocalPlayer
local PROJECT = "children_of_corn"
local MODEL_NAME = "CornPersonalFlashlight"
local PRE_BINDING = "CornFlashlightCameraBase"
local POST_BINDING = "CornFlashlightPresentation"
local ACTION = "CornFlashlightToggle"
local Controller = { Name = "FlashlightController", Order = 98 }
local PHASES = {
	ready = true,
	preparing = true,
	active = true,
	caught = true,
	escaped = true,
	aborted = true,
	caught_out = true,
}
local TERMINAL = { escaped = true, aborted = true, caught_out = true }
local ATTRIBUTES = { CornFlashlightOwned = true, corn_project_id = PROJECT, FlashlightVersion = 1 }

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function frameValid(value: any): boolean
	if typeof(value) ~= "CFrame" then
		return false
	end
	for _, component in { value:GetComponents() } do
		if not finite(component) then
			return false
		end
	end
	return true
end

local function ownedAttributes(item: Instance): boolean
	local attributes = item:GetAttributes()
	for name, value in ATTRIBUTES do
		if attributes[name] ~= value then
			return false
		end
	end
	for name in attributes do
		if ATTRIBUTES[name] == nil then
			return false
		end
	end
	return true
end

local function propertyEqual(actual: any, expected: any): boolean
	local kind = typeof(expected)
	if kind == "NumberSequence" or kind == "ColorSequence" then
		if typeof(actual) ~= kind then
			return false
		end
		local first, second = actual.Keypoints, expected.Keypoints
		if #first ~= #second then
			return false
		end
		for index, point in first do
			local other = second[index]
			if point.Time ~= other.Time or point.Value ~= other.Value then
				return false
			end
			if kind == "NumberSequence" and point.Envelope ~= other.Envelope then
				return false
			end
		end
		return true
	end
	return actual == expected
end

local function recordMatches(record: any, skipChildren: boolean?): boolean
	local item = record.item
	if
		item.ClassName ~= record.class
		or item.Name ~= record.name
		or item.Parent ~= record.parent
		or not ownedAttributes(item)
		or #item:GetTags() ~= 0
	then
		return false
	end
	for property, value in record.properties do
		if not propertyEqual(item[property], value) then
			return false
		end
	end
	if skipChildren then
		return true
	end
	local children = item:GetChildren()
	if #children ~= #record.children then
		return false
	end
	for _, child in children do
		if not table.find(record.children, child) then
			return false
		end
	end
	return true
end

local function ownedPath(item: Instance, model: Model): boolean
	local parent = item.Parent
	for _ = 1, 3 do
		if parent == model then
			return true
		end
		if not parent or not ownedAttributes(parent) then
			return false
		end
		parent = parent.Parent
	end
	return false
end

local function write(record: any, property: string, value: any)
	record.item[property] = value
	record.properties[property] = record.item[property]
end

local function skin(character: Model): Color3
	for _, name in { "LeftHand", "Left Arm", "LeftLowerArm" } do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part.Color
		end
	end
	return Color3.fromRGB(191, 145, 110)
end

function Controller:Init(_context: any)
	self._snapshot = nil
	self._roundId = -1
	self._endedRound = nil
	self._on = true
	self._focused = true
	self._visual = nil
	self._visualCamera = nil
	self._character = nil
	self._records = {}
	self._parts = {}
	self._lights = {}
	self._beams = {}
	self._cone = nil
	self._coneDistance = Presentation.Settings.Cone.length
	self._effect = nil
	self._lastBase = nil
	self._lastPosition = nil
	self._state = Presentation.NewState()
	self._connections = {}
	self._started = false
	self._bound = false
	self._actionBound = false
	self._movement = nil
	self._minimap = nil
	self._capture = nil
end

-- Only remove our own last additive result. A new mouse-look or capture frame
-- belongs to its writer and must never be inverted or replaced here.
function Controller:_unapplyCamera()
	local effect = self._effect
	self._effect = nil
	if
		effect
		and effect.camera.CFrame == effect.result
		and effect.camera.CameraType == Enum.CameraType.Custom
		and effect.camera.CameraSubject == effect.subject
		and effect.camera:GetAttribute("CornCaptureCameraOwner") == nil
	then
		effect.camera.CFrame = effect.base
	end
end

function Controller:_visualOwned(): boolean
	if not self._visual then
		return false
	end
	for _, record in self._records do
		if not recordMatches(record) then
			return false
		end
	end
	return true
end

function Controller:_clearVisual()
	local model = self._visual
	if model then
		if self:_visualOwned() then
			model:Destroy()
		else
			-- An inserted foreign child must survive. Quench only the still-exact
			-- light instances we created under the unchanged original container.
			if
				model.ClassName == "Model"
				and model.Name == MODEL_NAME
				and model.Parent == self._visualCamera
				and ownedAttributes(model)
			then
				for _, collection in { self._lights, self._beams } do
					for _, record in collection do
						if recordMatches(record, true) and ownedPath(record.item, model) then
							record.item.Enabled = false
						end
					end
				end
			end
			warn("[FlashlightController] Changed personal flashlight preserved")
		end
	end
	self._visual, self._visualCamera, self._character = nil, nil, nil
	self._records, self._parts, self._lights, self._beams = {}, {}, {}, {}
	self._cone = nil
	self._coneDistance = Presentation.Settings.Cone.length
end

function Controller:_suspend()
	self:_unapplyCamera()
	self:_clearVisual()
	self._lastBase, self._lastPosition = nil, nil
	self._state = Presentation.NewState()
end

function Controller:_unbind()
	if self._bound then
		RunService:UnbindFromRenderStep(PRE_BINDING)
		RunService:UnbindFromRenderStep(POST_BINDING)
		self._bound = false
	end
end

function Controller:Clear(_reason: string?)
	self._snapshot = nil
	self:_suspend()
	self:_unbind()
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

function Controller:_eligible(camera: Camera?, humanoid: Humanoid?): boolean
	local map = workspace:FindFirstChild("CornMap")
	return self._snapshot ~= nil
		and self._snapshot.phase == "active"
		and self._endedRound ~= self._roundId
		and map ~= nil
		and map:IsA("Model")
		and map:GetAttribute("corn_project_id") == PROJECT
		and map:GetAttribute("HarvestArtVariant") == "A"
		and camera ~= nil
		and humanoid ~= nil
		and camera.CameraType == Enum.CameraType.Custom
		and camera.CameraSubject == humanoid
		and camera:GetAttribute("CornCaptureCameraOwner") == nil
		and player.CameraMode == Enum.CameraMode.LockFirstPerson
		and self._focused
		and not GuiService.MenuIsOpen
		and UserInputService:GetFocusedTextBox() == nil
		and not (self._movement and (self._movement._cursorOpen or self._movement._mapOpen))
		and not (self._minimap and self._minimap._expanded)
		and not (self._capture and self._capture._state.active)
end

function Controller:_buildVisual(camera: Camera, character: Model): boolean
	if camera:FindFirstChild(MODEL_NAME) then
		return false
	end
	local model = Instance.new("Model")
	local records, parts, lights, beams = {}, {}, {}, {}
	local cone = nil
	local created = { model }
	local ok, problem = pcall(function()
		local function track(item: Instance, name: string, parent: Instance?, properties: any): any
			if item ~= model then
				table.insert(created, item)
			end
			item.Name = name
			for key, value in ATTRIBUTES do
				item:SetAttribute(key, value)
			end
			local observed = {}
			for key, value in properties do
				item[key] = value
				observed[key] = item[key]
			end
			item.Parent = parent
			local record = {
				item = item,
				name = name,
				class = item.ClassName,
				parent = parent,
				properties = observed,
				children = {},
			}
			table.insert(records, record)
			return record
		end
		track(model, MODEL_NAME, nil, {})
		local definitions = Presentation.Definitions()
		assert(#definitions + 2 <= Presentation.MaxParts, "Flashlight exceeds bounded geometry")
		local function part(
			name: string,
			size: Vector3,
			frame: CFrame,
			color: Color3,
			material: Enum.Material,
			shape: Enum.PartType?,
			transparency: number
		): any
			local record = track(Instance.new("Part"), name, model, {
				Size = size,
				CFrame = frame,
				Color = color,
				Material = material,
				Shape = shape or Enum.PartType.Block,
				Transparency = transparency,
				LocalTransparencyModifier = 0,
				Anchored = true,
				CanCollide = false,
				CanTouch = false,
				CanQuery = false,
				CastShadow = false,
			})
			record.localFrame = frame
			table.insert(parts, record)
			return record
		end
		for _, definition in definitions do
			part(
				definition.name,
				definition.size,
				definition.localFrame,
				if definition.isHand then skin(character) else definition.color,
				definition.material,
				definition.shape,
				0
			)
		end
		local emitter = part(
			"Emitter",
			Vector3.new(0.08, 0.08, 0.08),
			Presentation.LensFrame,
			Color3.new(1, 1, 1),
			Enum.Material.SmoothPlastic,
			nil,
			1
		)
		for _, name in { "main", "fill" } do
			local spec = Presentation.Settings.Lights[name]
			local record = track(Instance.new("SpotLight"), name, emitter.item, {
				Face = Enum.NormalId.Front,
				Color = Color3.new(1, 1, 1),
				Range = spec.range,
				Angle = spec.angle,
				Brightness = spec.brightness,
				Shadows = spec.shadows,
				Enabled = self._on,
			})
			table.insert(lights, record)
		end
		local handAim = track(Instance.new("Attachment"), "HandFillAim", emitter.item, {
			CFrame = Presentation.LensFrame:Inverse() * Presentation.HandFillFrame,
			Visible = false,
		})
		local handSpec = Presentation.Settings.HandFill
		local handFill = track(Instance.new("SpotLight"), "HandFill", handAim.item, {
			Face = Enum.NormalId.Front,
			Color = Color3.new(1, 1, 1),
			Range = handSpec.range,
			Angle = handSpec.angle,
			Brightness = handSpec.brightness,
			Shadows = handSpec.shadows,
			Enabled = self._on,
		})
		table.insert(lights, handFill)
		local spec = Presentation.Settings.Cone
		local frames = Presentation.ConeFrames(spec.length)
		local last = part(
			"ConeEnd",
			Vector3.new(0.08, 0.08, 0.08),
			Presentation.LensFrame * CFrame.new(0, 0, -frames.length),
			Color3.new(1, 1, 1),
			Enum.Material.SmoothPlastic,
			nil,
			1
		)
		for index, layer in frames.layers do
			local firstAttachment =
				track(Instance.new("Attachment"), "ConeStart" .. index, emitter.item, {
					CFrame = layer.first,
					Visible = false,
				})
			local lastAttachment =
				track(Instance.new("Attachment"), "ConeEnd" .. index, last.item, {
					CFrame = CFrame.new(0, 0, frames.length) * layer.last,
					Visible = false,
				})
			local beam = track(Instance.new("Beam"), "ConePlane" .. index, emitter.item, {
				Attachment0 = firstAttachment.item,
				Attachment1 = lastAttachment.item,
				Width0 = layer.width0,
				Width1 = layer.width1,
				Color = spec.color,
				Transparency = spec.transparency,
				FaceCamera = true,
				Segments = 16,
				CurveSize0 = 0,
				CurveSize1 = 0,
				Texture = "",
				LightEmission = 1,
				LightInfluence = 0,
				Enabled = self._on,
			})
			table.insert(beams, beam)
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character, model }
		params.RespectCanCollide = true
		params.IgnoreWater = false
		cone = { emitter = emitter, last = last, params = params }
		for _, record in records do
			record.children = record.item:GetChildren()
		end
	end)
	if not ok then
		for index = #created, 1, -1 do
			created[index]:Destroy()
		end
		warn("[FlashlightController] Personal flashlight creation failed: " .. tostring(problem))
		return false
	end
	records[1].parent = camera
	self._visual, self._visualCamera, self._character = model, camera, character
	self._records, self._parts, self._lights, self._beams, self._cone =
		records, parts, lights, beams, cone
	model.Parent = camera
	return true
end

function Controller:_updateCone(dt: number)
	local cone = self._cone
	if not cone then
		return
	end
	local emitter = cone.emitter.item.CFrame
	-- Only a render step casts. Snapshot/F refreshes use dt=0 and reuse the last
	-- bounded result, so UI/network updates cannot multiply rays within a frame.
	if self._on and dt > 0 then
		local ok, hit = pcall(
			workspace.Raycast,
			workspace,
			emitter.Position,
			emitter.LookVector * Presentation.Settings.Cone.length,
			cone.params
		)
		self._coneDistance = if not ok
			then 0
			elseif hit == nil then Presentation.Settings.Cone.length
			elseif finite(hit.Distance) then hit.Distance
			else 0
	end
	local frames = Presentation.ConeFrames(self._coneDistance)
	write(cone.last, "CFrame", emitter * CFrame.new(0, 0, -frames.length))
	for index, beam in self._beams do
		local layer = frames.layers[index]
		write(beam, "Width0", layer.width0)
		write(beam, "Width1", layer.width1)
		write(beam, "Enabled", self._on and frames.enabled)
	end
end

function Controller:_step(dt: number): boolean
	self:_unapplyCamera()
	local camera = workspace.CurrentCamera
	local character, humanoid, root = self:_livingCharacter()
	if not self:_eligible(camera, humanoid) then
		self:_suspend()
		return false
	end
	if self._visual and (self._visualCamera ~= camera or self._character ~= character) then
		self:_suspend()
	end
	if self._visual and not self:_visualOwned() then
		self:_suspend()
		return false
	end
	if not self._visual and not self:_buildVisual(camera :: Camera, character :: Model) then
		return false
	end
	local base = (camera :: Camera).CFrame
	if not frameValid(base) then
		self:_suspend()
		return false
	end
	local turn = Vector2.zero
	if self._lastBase then
		local pitch, yaw = self._lastBase:ToObjectSpace(base):ToOrientation()
		turn = Vector2.new(pitch, yaw)
	end
	local velocity = (root :: BasePart).AssemblyLinearVelocity
	local speed = if finite(velocity.X) and finite(velocity.Z)
		then math.sqrt(velocity.X ^ 2 + velocity.Z ^ 2)
		else 0
	local position = (root :: BasePart).Position
	local viewport = (camera :: Camera).ViewportSize
	local state, output = Presentation.Step(self._state, dt, {
		speed = speed,
		grounded = (humanoid :: Humanoid).FloorMaterial ~= Enum.Material.Air,
		turn = turn,
		aspect = if viewport.Y > 0 then viewport.X / viewport.Y else 16 / 9,
		teleported = self._lastPosition ~= nil and (position - self._lastPosition).Magnitude > 32,
	})
	if
		type(output) ~= "table"
		or not frameValid(output.camera)
		or not frameValid(output.aim)
		or not frameValid(output.view)
	then
		self:_suspend()
		return false
	end
	self._state, self._lastBase, self._lastPosition = state, base, position
	local rendered = base * output.camera
	if output.camera ~= CFrame.identity then
		(camera :: Camera).CFrame = rendered
		self._effect =
			{ camera = camera, base = base, result = (camera :: Camera).CFrame, subject = humanoid }
	end
	local frame = rendered * output.aim * output.view
	for _, record in self._parts do
		write(record, "CFrame", frame * record.localFrame)
	end
	for _, record in self._lights do
		write(record, "Enabled", self._on)
	end
	self:_updateCone(dt)
	return true
end

function Controller:_bind()
	if self._started and not self._bound then
		RunService:BindToRenderStep(PRE_BINDING, Enum.RenderPriority.Camera.Value - 1, function()
			self:_unapplyCamera()
		end)
		RunService:BindToRenderStep(
			POST_BINDING,
			Enum.RenderPriority.Camera.Value + 1,
			function(dt: number)
				self:_step(dt)
			end
		)
		self._bound = true
	end
end

function Controller:SetSnapshot(snapshot: any)
	if
		type(snapshot) ~= "table"
		or type(snapshot.minimap) ~= "table"
		or not PHASES[snapshot.phase]
	then
		self:Clear("malformed")
		return
	end
	local id = snapshot.minimap.round_id
	if not finite(id) or id < 0 or id % 1 ~= 0 or id < self._roundId then
		return
	end
	if id == self._roundId and self._endedRound == id and snapshot.phase == "active" then
		return
	end
	if id ~= self._roundId then
		self:Clear("new round")
		self._roundId, self._endedRound, self._on = id, nil, true
	end
	if TERMINAL[snapshot.phase] then
		self._endedRound = id
	end
	if snapshot.phase ~= "active" then
		self:Clear(snapshot.phase)
		return
	end
	local map = workspace:FindFirstChild("CornMap")
	if not map or map:GetAttribute("HarvestArtVariant") ~= "A" then
		self:Clear("variant")
		return
	end
	self._snapshot = { phase = snapshot.phase }
	self:_bind()
	self:_step(0)
end

function Controller:Start(context: any)
	self._movement = context.Controllers.MovementController
	self._minimap = context.Controllers.MinimapController
	self._capture = context.Controllers.CaptureController
	self._started = true
	ContextActionService:BindActionAtPriority(ACTION, function(_, state: Enum.UserInputState)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if not self:_step(0) then
			return Enum.ContextActionResult.Pass
		end
		self._on = not self._on
		self:_step(0)
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.KeyCode.F)
	self._actionBound = true
	table.insert(
		self._connections,
		GuiService.MenuOpened:Connect(function()
			self:_suspend()
		end)
	)
	table.insert(
		self._connections,
		UserInputService.WindowFocusReleased:Connect(function()
			self._focused = false
			self:_suspend()
		end)
	)
	table.insert(
		self._connections,
		UserInputService.WindowFocused:Connect(function()
			self._focused = true
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
	if self._snapshot then
		self:_bind()
	end
end

function Controller:Destroy()
	self:Clear("destroy")
	if self._actionBound then
		ContextActionService:UnbindAction(ACTION)
		self._actionBound = false
	end
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	self._started = false
	self._movement, self._minimap, self._capture = nil, nil, nil
end

return Controller
