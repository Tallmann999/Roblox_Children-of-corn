-- Actual MonsterHunt on the established geometry adapter. Gameplay remains
-- authoritative; this checks the visual opt-in against legacy + both variants.
local adapter = require("./scene-adapter")
local fs, r, I = adapter.fs, adapter.r, adapter.I
local CF, V3 = r.CFrame, r.Vector3
local Balance = require("../src/shared/Game/Balance")
local poseFn = assert(loadstring(fs.readFile("src/shared/Game/MonsterPose.luau")))
setfenv(
	poseFn,
	setmetatable(
		{ CFrame = CF, Vector3 = V3, Color3 = r.Color3, Enum = r.Enum },
		{ __index = getfenv() }
	)
)
local Pose = poseFn()
local rs = {
	WaitForChild = function(self)
		return self
	end,
}
local huntSource = fs.readFile("src/server/Game/MonsterHunt.luau")
for _, name in { "world.Ground", "home", "self.root", "playerRoot", "slot", "self.patrolSlot" } do
	huntSource = huntSource:gsub(name:gsub("%.", "%%.") .. "%.Position", name .. ".CFrame.Position")
end
local huntFn = assert(loadstring(huntSource))
setfenv(
	huntFn,
	setmetatable({
		game = {
			GetService = function(_, name)
				if name == "ReplicatedStorage" then
					return rs
				end
				assert(name == "PathfindingService")
				return {
					CreatePath = function()
						error("Unexpected path in stationary visual check")
					end,
				}
			end,
		},
		require = function()
			return Pose
		end,
		Instance = I,
		Vector3 = V3,
		CFrame = CF,
		Color3 = r.Color3,
		Enum = r.Enum,
		workspace = {
			Raycast = function()
				return nil
			end,
			Blockcast = function()
				return nil
			end,
		},
		RaycastParams = {
			new = function()
				return {}
			end,
		},
		task = { spawn = function() end },
	}, { __index = getfenv() })
)
local Hunt = huntFn()
for _, variant in { "legacy", "A", "B", "foreign" } do
	local map = I.new("Model")
	map:SetAttribute("HarvestArtVariant", if variant == "legacy" then nil else variant)
	local home = I.new("Model")
	home.Parent = map
	local body = I.new("Part")
	body.Name, body.CFrame, body.Transparency, body.Parent = "Body", CF.new(0, 8, 0), 0, home
	local ground = I.new("Part")
	ground.Size, ground.CFrame, ground.Parent = V3.new(630, 2, 630), CF.new(0, -1, 0), map
	local runtime = I.new("Folder")
	runtime.Parent = map
	local slot = I.new("Part")
	slot.CFrame, slot.Parent = CF.new(10, 0, 10), map
	local world = { Root = map, Home = home, Ground = ground, Runtime = runtime, Slots = { slot } }
	local character = I.new("Model")
	local target = I.new("Part")
	target.Name, target.CFrame, target.Parent = "HumanoidRootPart", CF.new(100, 3, 0), character
	local enabled = variant == "A" or variant == "B"
	local hunt = Hunt.new(world, Balance, 0, 1)
	assert(hunt.model:GetAttribute("MonsterRigVersion") == 1)
	assert(hunt.model:GetAttribute("HarvestWardenVersion") == (if enabled then 1 else nil))
	assert(hunt.model:GetAttribute("HarvestArtVariant") == (if enabled then variant else nil))
	assert(#hunt.model:GetChildren() == 10 and #hunt.visuals == 9)
	assert(hunt.root.Size == V3.new(3, 6, 2) and hunt.root.CFrame.Position == V3.new(0, 3, 0))
	assert(not hunt:Step(0, Balance.hunt_start_delay_sec - 0.001, target, true))
	for _, part in hunt.visuals do
		assert(part.Transparency == 1)
	end
	local _, awakened = hunt:Step(0, Balance.hunt_start_delay_sec, target, true)
	assert(awakened and hunt.state == "patrol" and body.Transparency == 1)
	for _, part in hunt.visuals do
		assert(part.Transparency == (if enabled then 1 else 0))
	end
	assert(hunt.detectRadius == 48)
	target.CFrame = CF.new(hunt.root.CFrame.Position + V3.new(48.001, 0, 0))
	hunt.firstChaseUsed = true
	hunt:Step(0, 21, target, false)
	assert(hunt.state == "patrol")
	target.CFrame = CF.new(hunt.root.CFrame.Position + V3.new(48, 0, 0))
	hunt:Step(0, 21.1, target, false)
	assert(hunt.state == "chase")
	hunt:SetDetectionMultiplier(2)
	assert(hunt.detectRadius == 96 and hunt.model:GetAttribute("DetectionRadius") == 96)
	hunt:Destroy()
	assert(body.Transparency == 0 and not runtime:FindFirstChild("Monster"))
	local reinforcement = Hunt.new(world, Balance, 22, 1, { index = 2, immediate = true })
	assert(reinforcement.state == "patrol" and reinforcement.model.Name == "Monster2")
	for _, part in reinforcement.visuals do
		assert(part.Transparency == (if enabled then 1 else 0))
	end
	reinforcement:Destroy()
	map:Destroy()
	character:Destroy()
end
print(
	"PASS: actual MonsterHunt legacy/A/B opt-in and unknown-variant fallback, unchanged Root/rig topology/9 carriers, hidden Warden carriers on timed and immediate awakening, original marker restoration, authoritative 48/96 detection and cleanup"
)
