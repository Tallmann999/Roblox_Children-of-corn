-- Read-only real active-round audit after the guarded 630-stud resize.
local Run = game:GetService("RunService")
assert(Run:IsStudio() and Run:IsRunning() and Run:IsServer(), "Studio Play Server required")
local map = assert(workspace:FindFirstChild("CornMap"), "CornMap missing")
assert(map:GetAttribute("corn_project_id") == "children_of_corn", "Wrong project")
local World = require(game.ServerScriptService.GameServer.Game.AuthoredWorld)
local field = map.FieldZone
local function close(a, b)
	return math.abs(a - b) < 0.0001
end
assert(close(field.Size.X, 630) and close(field.Size.Z, 630), "Field must be630 square")
assert(close(map.Ground.Size.X, 630) and close(map.Ground.Size.Z, 630), "Ground size mismatch")
assert(
	close(map.PlayBounds.Size.X, 630) and close(map.PlayBounds.Size.Z, 670),
	"Exit bounds allowance lost"
)
local spawns = World.ReadSpawns(map)
assert(#spawns == 4, "Four authored spawns required")
for _, spawn in spawns do
	assert(World.IsSafeSpawn(map, spawn), "Unsafe resized spawn: " .. spawn.Name)
	local point = field.CFrame:PointToObjectSpace(spawn.Position)
	assert(
		close(math.abs(point.X), 288.75) and close(math.abs(point.Z), 288.75),
		"Wrong corner translation"
	)
end
local slots = map.KeySlots:GetChildren()
assert(#slots == 15, "Fifteen search slots required")
for _, slot in slots do
	assert(slot:HasTag("corn_key_slot"), "Unknown search slot")
	local id = slot:GetAttribute("slot_id")
	local torch = assert(map.TorchMarkers:FindFirstChild("torch_" .. id), "Slot torch missing")
	assert(close(torch.Pole.Position.X - slot.Position.X, 0), "Torch X detached from slot")
	assert(close(torch.Pole.Position.Z - slot.Position.Z, 4), "Torch Z detached from slot")
	local point = field.CFrame:PointToObjectSpace(slot.Position)
	assert(math.abs(point.X) < 315 and math.abs(point.Z) < 315, "Slot outside smaller field")
	if math.abs(point.X) < 30 then
		assert(math.abs(point.X) >= 21, "Central stump cluster overlaps road")
	end
end
local gate = map.EscapeGate
local door = field.CFrame:PointToObjectSpace(gate.Door.Position)
local exit = field.CFrame:PointToObjectSpace(gate.ExitZone.Position)
assert(close(door.X, 0) and close(door.Z, 316), "Gate not moved to new north edge")
assert(close(gate.Door.Size.X, 12), "Human gate width changed")
assert(close(exit.Z, 325), "Escape trigger not moved with gate")
local runtime = assert(map:FindFirstChild("CornRoundRuntime"), "No actual round runtime")
local items = assert(runtime:FindFirstChild("InventoryItems"), "Start a fresh round before audit")
local counts, rows, used = { energy = 0, trap = 0 }, {}, {}
local function slotAt(point, offset)
	for _, slot in slots do
		if close(point.X, slot.Position.X + offset) and close(point.Z, slot.Position.Z) then
			return slot:GetAttribute("slot_id")
		end
	end
	return nil
end
for _, item in items:GetChildren() do
	local kind = item:GetAttribute("item_kind")
	if kind == "energy" or kind == "trap" then
		counts[kind] += 1
		local anchor = assert(item:FindFirstChild("Anchor"), "Item anchor missing")
		local prompt =
			assert(anchor:FindFirstChildOfClass("ProximityPrompt"), "Item prompt missing")
		assert(
			prompt.Enabled and prompt.MaxActivationDistance == 4,
			"Active item pickup unavailable"
		)
		local offset = if kind == "trap" then -3.6 else 3.6
		local slot = assert(slotAt(anchor.Position, offset), "Item detached from resized slot")
		assert(not used[slot], "Duplicate item slot")
		used[slot] = true
		table.insert(
			rows,
			{ name = item.Name, kind = kind, slot = slot, position = tostring(anchor.Position) }
		)
	end
end
assert(counts.energy == 2 and counts.trap == 2, "Expected2 energy and2 traps in fresh round")
local key =
	assert(runtime:FindFirstChild("GateKeyModel"), "Fresh key missing"):FindFirstChild("GateKey")
assert(key and key:IsA("BasePart"), "Key anchor missing")
local keySlot = assert(slotAt(key.Position, 0), "Key detached from resized slot")
assert(not used[keySlot], "Key and pickup share slot")
assert(key.CornKeyPrompt.Enabled, "Fresh key pickup disabled")
local lookouts = assert(items:FindFirstChild("LookoutStumps"), "Energy lookout folder missing")
assert(#lookouts:GetChildren() == 2, "Two persistent energy stumps required")
return {
	status = "PASS",
	method = "Read-only actual authored world and fresh runtime bindings; no pickup/input/GPU acceptance",
	side = 630,
	spawns = #spawns,
	linked_field_torches = #slots,
	energy = counts.energy,
	traps = counts.trap,
	key = { slot = keySlot, position = tostring(key.Position) },
	items = rows,
	lookouts = #lookouts:GetChildren(),
}
