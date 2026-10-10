--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Geometry = require(
	ReplicatedStorage:WaitForChild("GameShared")
		:WaitForChild("Game")
		:WaitForChild("MinimapGeometry")
)

local BOUNDARY_EPSILON = 0.0001
local MAX_VISITS = 18
local MAX_DEATHS = 3
local HOUSE_NAMES = { "HouseWest", "HouseEast", "HouseNorthWest" }

local MinimapState = { PollInterval = 1 / Geometry.UpdateHz }
MinimapState.__index = MinimapState

local function finitePosition(position: Vector3): boolean
	return position.X == position.X
		and position.Y == position.Y
		and position.Z == position.Z
		and math.abs(position.X) < math.huge
		and math.abs(position.Y) < math.huge
		and math.abs(position.Z) < math.huge
end

function MinimapState.new()
	return setmetatable({
		roundId = 0,
		visited = {} :: { any },
		visitedIds = {} :: { [string]: boolean },
		deaths = {} :: { any },
		deadCharacters = {} :: { [Model]: boolean },
	}, MinimapState)
end

function MinimapState:ClearHistory()
	table.clear(self.visited)
	table.clear(self.visitedIds)
	table.clear(self.deaths)
	table.clear(self.deadCharacters)
end

function MinimapState:ResetHistory()
	self.roundId += 1
	self:ClearHistory()
end

function MinimapState:_visit(id: string, kind: string, position: Vector3): boolean
	if self.visitedIds[id] or #self.visited >= MAX_VISITS or not finitePosition(position) then
		return false
	end
	self.visitedIds[id] = true
	table.insert(self.visited, { id = id, kind = kind, position = position })
	return true
end

function MinimapState:Poll(world: any, position: Vector3): boolean
	if not finitePosition(position) then
		return false
	end
	local changed = false
	local field = world.Field
	if math.abs(position.Y - field.Position.Y) <= Geometry.VisitHeight then
		local radius = Geometry.ClearingRadius + Geometry.VisitPadding + BOUNDARY_EPSILON
		for _, slot in world.Slots do
			if slot:IsDescendantOf(world.Root) and slot:HasTag("corn_key_slot") then
				local slotId = slot:GetAttribute("slot_id")
				local offset = position - slot.Position
				if
					type(slotId) == "string"
					and slotId ~= ""
					and offset.X * offset.X + offset.Z * offset.Z <= radius * radius
				then
					changed = self:_visit("clearing:" .. slotId, "clearing", slot.Position)
						or changed
				end
			end
		end
	end
	local props = world.Root:FindFirstChild("Props")
	if props then
		for _, name in HOUSE_NAMES do
			local house = props:FindFirstChild(name)
			if house and house:IsA("Model") and house:FindFirstChildWhichIsA("BasePart", true) then
				local frame, size = house:GetBoundingBox()
				-- Horizontal bounds follow the authored house yaw; height is a separate tolerance.
				local projected = Vector3.new(position.X, frame.Position.Y, position.Z)
				local localPosition = frame:PointToObjectSpace(projected)
				if
					math.abs(position.Y - frame.Position.Y) <= Geometry.VisitHeight
					and math.abs(localPosition.X) <= size.X / 2 + Geometry.VisitPadding + BOUNDARY_EPSILON
					and math.abs(localPosition.Z)
						<= size.Z / 2 + Geometry.VisitPadding + BOUNDARY_EPSILON
				then
					changed = self:_visit("house:" .. name, "house", frame.Position) or changed
				end
			end
		end
	end
	return changed
end

function MinimapState:RecordCaught(position: Vector3): boolean
	if #self.deaths >= MAX_DEATHS or not finitePosition(position) then
		return false
	end
	table.insert(self.deaths, { id = #self.deaths + 1, kind = "caught", position = position })
	return true
end

function MinimapState:RecordDeath(character: Model, position: Vector3): boolean
	if
		self.deadCharacters[character]
		or #self.deaths >= MAX_DEATHS
		or not finitePosition(position)
	then
		return false
	end
	self.deadCharacters[character] = true
	table.insert(self.deaths, { id = #self.deaths + 1, kind = "death", position = position })
	return true
end

function MinimapState:Snapshot(): any
	local visited = {}
	local deaths = {}
	for _, item in self.visited do
		table.insert(visited, { id = item.id, kind = item.kind, position = item.position })
	end
	for _, item in self.deaths do
		table.insert(deaths, { id = item.id, kind = item.kind, position = item.position })
	end
	return { round_id = self.roundId, visited = visited, deaths = deaths }
end

return MinimapState
