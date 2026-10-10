-- Pure resource regression tests; live physics/input are tested separately in Studio.
local Stamina = require("../src/shared/Game/Stamina")
local Balance = require("../src/shared/Game/Balance")
local function near(a, b) assert(math.abs(a-b) < 0.00001, tostring(a).." != "..tostring(b)) end
local function run(state, seconds, moving, active, step)
    for _=1, math.floor(seconds/step+0.5) do Stamina.Step(state,step,moving,active,Balance) end
end
for _, dt in {1/30,1/60,1/144,0.1} do
    local s=Stamina.new(100,0)
    assert(Stamina.Request(s,true,0,true))
    run(s,4,true,true,dt)
    near(s.value,0)
    assert(s.exhausted and not s.sprinting)
    run(s,6,true,true,dt)
    near(s.value,100)
    assert(s.exhausted and not s.sprinting,"Held Shift must not restart sprint")
    assert(Stamina.Request(s,false,10,true))
    assert(Stamina.Request(s,true,10,true))
    Stamina.Step(s,1,true,true,Balance)
    near(s.value,75)
    assert(s.sprinting and not s.exhausted)
end
local s=Stamina.new(100,0)
Stamina.Request(s,true,0,true)
run(s,10,false,true,0.1)
near(s.value,100)
assert(not s.sprinting)
s.value=0
Stamina.Request(s,false,10,true)
run(s,6,true,true,0.1) -- walk/jump without a sprint request: no extra cost
near(s.value,100)
Stamina.Request(s,true,20,true)
Stamina.Step(s,1,true,false,Balance)
near(s.value,100)
assert(not s.intent and not s.sprinting)
for _, value in {"true",1,{},0/0} do assert(not Stamina.Request(s,value,20,true)) end
assert(not Stamina.Request(s,true,20,false))
s=Stamina.new(100,20)
for _=1,12 do assert(Stamina.Request(s,true,20,true)); Stamina.Request(s,false,20,true) end
assert(not Stamina.Request(s,true,20,true),"Rate limit failed")
assert(Stamina.Request(s,false,20,false),"Release must always be accepted")
assert(Stamina.Request(s,true,21,true),"Rate limiter did not refill")
near(Stamina.new(100,22).value,100)
print("PASS: 4-second drain/6-second refill at 30/60/144/10Hz; exhausted release latch; moving only; walk/jump regeneration; inactive/type/rate guards; fresh round")
