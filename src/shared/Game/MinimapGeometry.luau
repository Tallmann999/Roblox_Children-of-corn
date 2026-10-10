--!strict

local MinimapGeometry = {
	CompactSize = 180,
	UpdateHz = 10,
	VisitPadding = 3,
	VisitHeight = 12,
	ClearingRadius = 6,
}

export type Visit = { id: string, kind: string, position: Vector3 }
export type Death = { id: number, kind: string, position: Vector3 }
export type History = { round_id: number, visited: { Visit }, deaths: { Death } }

local function finite(value: any): boolean
	return typeof(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function position(value: any): boolean
	return typeof(value) == "Vector3" and finite(value.X) and finite(value.Y) and finite(value.Z)
end

function MinimapGeometry.IsValid(value: any): boolean
	if
		typeof(value) ~= "table"
		or not finite(value.round_id)
		or value.round_id < 0
		or value.round_id % 1 ~= 0
	then
		return false
	end
	if
		typeof(value.visited) ~= "table"
		or typeof(value.deaths) ~= "table"
		or #value.visited > 18
		or #value.deaths > 3
	then
		return false
	end
	local seen: { [string]: boolean } = {}
	local count = 0
	for index, visit in value.visited do
		count += 1
		if
			typeof(index) ~= "number"
			or index % 1 ~= 0
			or index < 1
			or index > #value.visited
			or typeof(visit) ~= "table"
			or typeof(visit.id) ~= "string"
			or visit.id == ""
			or #visit.id > 100
			or seen[visit.id]
			or (visit.kind ~= "clearing" and visit.kind ~= "house")
			or not position(visit.position)
		then
			return false
		end
		seen[visit.id] = true
	end
	if count ~= #value.visited then
		return false
	end
	local deaths: { [number]: boolean } = {}
	count = 0
	for index, death in value.deaths do
		count += 1
		if
			typeof(index) ~= "number"
			or index % 1 ~= 0
			or index < 1
			or index > #value.deaths
			or typeof(death) ~= "table"
			or not finite(death.id)
			or death.id < 1
			or death.id % 1 ~= 0
			or deaths[death.id]
			or (death.kind ~= "caught" and death.kind ~= "death")
			or not position(death.position)
		then
			return false
		end
		deaths[death.id] = true
	end
	return count == #value.deaths
end

function MinimapGeometry.Project(frame: CFrame, size: Vector3, worldPosition: Vector3): Vector2
	local point = frame:PointToObjectSpace(worldPosition)
	return Vector2.new(
		math.clamp(point.X / size.X + 0.5, 0, 1),
		math.clamp(point.Z / size.Z + 0.5, 0, 1)
	)
end

function MinimapGeometry.Heading(frame: CFrame, direction: Vector3): number
	local localDirection = frame:VectorToObjectSpace(direction)
	return math.deg(math.atan2(localDirection.X, -localDirection.Z))
end

return MinimapGeometry
