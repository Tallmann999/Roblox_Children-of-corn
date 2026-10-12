--!strict
local Inventory = { Capacity = 5, EnergyDuration = 30, TrapDuration = 10 }
local kinds = { empty = true, key = true, energy = true, trap = true }
function Inventory.IsSlot(slot: any): boolean
	return type(slot) == "number" and slot % 1 == 0 and slot >= 1 and slot <= Inventory.Capacity
end
function Inventory.IsValidSnapshot(value: any): boolean
	if
		type(value) ~= "table"
		or type(value.slots) ~= "table"
		or not Inventory.IsSlot(value.selected)
	then
		return false
	end
	local count = 0
	for index, kind in value.slots do
		if not Inventory.IsSlot(index) or type(kind) ~= "string" or not kinds[kind] then
			return false
		end
		count += 1
	end
	local remaining = value.energy_remaining
	return count == Inventory.Capacity
		and type(remaining) == "number"
		and remaining == remaining
		and remaining >= 0
		and remaining <= Inventory.EnergyDuration
end
function Inventory.new(now: number): any
	return {
		slots = table.create(Inventory.Capacity, "empty"),
		selected = 1,
		energyUntil = 0,
		tokens = 10,
		requestAt = now,
	}
end
function Inventory.Add(state: any, kind: string): boolean
	if kind == "empty" or not kinds[kind] then
		return false
	end
	local slot = table.find(state.slots, "empty")
	if not slot then
		return false
	end
	state.slots[slot] = kind
	if state.slots[state.selected] == "empty" then
		state.selected = slot
	end
	return true
end
function Inventory.Remove(state: any, kind: string): boolean
	local slot = table.find(state.slots, kind)
	if not slot then
		return false
	end
	state.slots[slot] = "empty"
	return true
end
function Inventory.Request(state: any, action: any, slot: any, now: number): boolean
	if not Inventory.IsSlot(slot) or (action ~= "select" and action ~= "use") then
		return false
	end
	state.tokens = math.min(10, state.tokens + math.max(0, now - state.requestAt) * 6)
	state.requestAt = now
	if state.tokens < 1 then
		return false
	end
	state.tokens -= 1
	if action == "select" then
		state.selected = slot
		return true
	end
	return state.selected == slot and (state.slots[slot] == "energy" or state.slots[slot] == "trap")
end
function Inventory.Snapshot(state: any, now: number): any
	return {
		slots = table.clone(state.slots),
		selected = state.selected,
		energy_remaining = math.clamp(state.energyUntil - now, 0, Inventory.EnergyDuration),
	}
end
function Inventory.Multiplier(state: any, now: number): number
	return if state.energyUntil > now then 2 else 1
end
return table.freeze(Inventory)
