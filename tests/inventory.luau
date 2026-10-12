local Inventory = require("../src/shared/Game/Inventory")
local state = Inventory.new(0)
assert(Inventory.IsValidSnapshot(Inventory.Snapshot(state, 0)))
assert(Inventory.Snapshot(state, 0).use.id==0 and Inventory.Snapshot(state,0).use.kind=="none")
state.useId=1;state.useKind="energy";assert(Inventory.IsValidSnapshot(Inventory.Snapshot(state,0)))
local useSnapshot=Inventory.Snapshot(state,0);useSnapshot.use.id=99;assert(state.useId==1)
for _, bad in { {id=0,kind="energy"},{id=1,kind="none"},{id=1.5,kind="trap"},{id=-1,kind="energy"},{id=0/0,kind="energy"},{id=math.huge,kind="trap"},{id=1,kind="key"} } do
 local shot=Inventory.Snapshot(state,0);shot.use=bad;assert(not Inventory.IsValidSnapshot(shot))
end
for _, kind in { "energy", "trap", "key", "energy", "trap" } do assert(Inventory.Add(state, kind)) end
assert(not Inventory.Add(state, "energy"))
assert(not Inventory.Request(state, "use", 2, 0), "Unselected use")
assert(Inventory.Request(state, "select", 2, 0))
assert(Inventory.Request(state, "use", 2, 0))
assert(Inventory.Request(state, "select", 3, 0))
assert(not Inventory.Request(state, "use", 3, 0), "Key must not activate")
assert(Inventory.Remove(state, "key")); assert(Inventory.Add(state, "key"))
state.energyUntil = 30
assert(Inventory.Multiplier(state, 29.999) == 2 and Inventory.Multiplier(state, 30) == 1)
assert(Inventory.Snapshot(state, 25).energy_remaining == 5)
state.energyUntil = 40
assert(Inventory.Multiplier(state, 26) == 2 and Inventory.Snapshot(state, 26).energy_remaining == 14)
for _, slot in { 0, 6, -1, 1.5, 0/0, math.huge, "1", {} } do assert(not Inventory.Request(state, "select", slot, 1)) end
for _, malformed in { {}, {slots={},selected=1,energy_remaining=0}, {slots=state.slots,selected=1,energy_remaining=0/0}, {slots=state.slots,selected=1,energy_remaining=31} } do assert(not Inventory.IsValidSnapshot(malformed)) end
state = Inventory.new(0)
for _=1,10 do assert(Inventory.Request(state,"select",1,0)) end
assert(not Inventory.Request(state,"select",1,0)); assert(Inventory.Request(state,"select",1,1))
local snapshot=Inventory.Snapshot(state,1); snapshot.slots[1]="key"; assert(state.slots[1]=="empty")
print("PASS inventory capacity/type/selection/key/expiry/refresh/rate/snapshot isolation")
