from pathlib import Path
import hashlib, json

root = Path(__file__).resolve().parents[3]
out = Path(__file__).resolve().parent
accepted = json.loads((root/'.artifacts/playtests/2026-10-20-flashlight/payload.json').read_bytes())
prior = json.loads((root/'.artifacts/playtests/2026-10-20-flashlight-cone/payload.json').read_bytes())
baseline = root/'place/Children_of_corn.before-flashlight-directional-20261020.rbxl'
saved = (root/'place/Children_of_corn.rbxl').read_bytes()
assert len(saved)==1487543 and hashlib.sha256(saved).hexdigest()=='001a0e52bf8b76b8f40c2a8ef31509e287b720d043a42dd2888890b56b3a50d6'
if baseline.exists(): assert baseline.read_bytes()==saved
else: baseline.write_bytes(saved)
for entry in prior['entries']:
    if entry.get('source'):
        target=out/'before-src'/f"{entry['path'].rsplit('/',1)[1]}.luau"
        target.parent.mkdir(exist_ok=True)
        if target.exists(): assert target.read_text(encoding='utf-8')==entry['source']
        else: target.write_text(entry['source'],encoding='utf-8',newline='\n')
controller = root/'src/client/Controllers/FlashlightController.luau'
s=controller.read_text(encoding='utf-8')
assert hashlib.sha256(s.encode()).hexdigest()=='b274b2c66bc0da41ffe890b4a60ba0d0ab3783c6a5542d710742e168061807be'
def replace(old,new,count=1):
    global s
    assert s.count(old)==count,(old,s.count(old))
    s=s.replace(old,new)
replace('\tself._beams = {}\n\tself._cone = nil\n\tself._coneDistance = Presentation.Settings.Cone.length\n','')
replace('for _, collection in { self._lights, self._beams } do\n\t\t\t\t\tfor _, record in collection do','for _, record in self._lights do')
replace('\t\t\t\t\tend\n\t\t\t\tend\n\t\t\tend\n\t\t\twarn','\t\t\t\tend\n\t\t\tend\n\t\t\twarn')
replace('\tself._records, self._parts, self._lights, self._beams = {}, {}, {}, {}\n\tself._cone = nil\n\tself._coneDistance = Presentation.Settings.Cone.length','\tself._records, self._parts, self._lights = {}, {}, {}')
replace('\tlocal records, parts, lights, beams = {}, {}, {}, {}\n\tlocal cone = nil','\tlocal records, parts, lights = {}, {}, {}')
replace('#definitions + 2 <= Presentation.MaxParts','#definitions + 1 <= Presentation.MaxParts')
needle='\t\tfor _, name in { "main", "fill" } do'
replace(needle,'\t\tlocal lensAim = track(Instance.new("Attachment"), "LensAim", emitter.item, {\n\t\t\tCFrame = CFrame.identity,\n\t\t\tVisible = false,\n\t\t})\n'+needle)
replace('name, emitter.item, {','name, lensAim.item, {')
a=s.index('\t\tlocal spec = Presentation.Settings.Cone\n')
b=s.index('\t\tfor _, record in records do\n',a)
s=s[:a]+s[b:]
replace('\tself._records, self._parts, self._lights, self._beams, self._cone =\n\t\trecords, parts, lights, beams, cone','\tself._records, self._parts, self._lights = records, parts, lights')
a=s.index('function Controller:_updateCone(')
b=s.index('function Controller:_step(',a)
s=s[:a]+s[b:]
replace('\tself:_updateCone(dt)\n','')
replace('end, false, 3000, Enum.KeyCode.F)','end, false, 3000, Enum.UserInputType.MouseButton1)')
controller.write_text(s,encoding='utf-8',newline='\n')

# Retain all established camera/lifecycle assertions; replace superseded air-Beam
# tests with real surface-light/lens-axis checks and mouse input coverage.
p=root/'tests/flashlight-controller.luau';t=p.read_text(encoding='utf-8')
a=t.index('local rayCount, rayHit, rayFailure, lastRay')
b=t.index('local input = ',a)
t=t[:a]+'local rayCount = 0\nfunction world:Raycast() rayCount += 1; error("Surface-light lamp must not cast decorative rays") end\n'+t[b:]
t=t.replace('key == r.Enum.KeyCode.F','key == r.Enum.UserInputType.MouseButton1')
t=t.replace('assert(#controller._beams == 4)\n\tfor _, record in controller._beams do assert(record.item.Enabled == expected) end','for _, item in controller._visual:GetDescendants() do assert(not item:IsA("Beam"), "Rejected air tunnel returned") end')
t=t.replace('#Flashlight.Definitions()+2','#Flashlight.Definitions()+1').replace('<= 14','<= 12')
t=t.replace('~= .35','~= .45')
t=t.replace('assert(controller._lights[1].item.Angle == 36 and controller._lights[2].item.Angle == 50)','assert(controller._lights[1].item.Angle == 28 and controller._lights[2].item.Angle == 56)')
a=t.index('-- Actual nested billboard renderer:')
b=t.index('-- Repeated render updates',a)
t=t[:a]+'''-- The same exact lens attachment emits the bright circular core and weak spill.
local main, fill = controller._lights[1].item, controller._lights[2].item
assert(main.Parent == fill.Parent and main.Parent.Name == "LensAim")
assert(main.Parent.CFrame == r.CFrame.identity)
assert(main.Face == r.Enum.NormalId.Front and fill.Face == main.Face)
assert(main.Range == 64 and main.Brightness == 4 and main.Shadows)
assert(fill.Range == 32 and math.abs(fill.Brightness-.45)<1e-7 and fill.Shadows)
render(1/60)
assert(rayCount == 0 and controller:_visualOwned())
local emitter = main.Parent.Parent
local axis = emitter.CFrame * main.Parent.CFrame
assert(axis.LookVector:Dot(camera.CFrame.LookVector) > .9999)
assert((axis.Position-(emitter.CFrame.Position)).Magnitude < 1e-6)
assert(main.Angle < fill.Angle and main.Brightness > fill.Brightness)
assert(f(r.Enum.UserInputState.Change) == r.Enum.ContextActionResult.Pass and controller._on)

'''+t[b:]
t=t.replace('local ownedBeams = table.clone(controller._beams)\n','').replace('for _, record in ownedBeams do assert(not record.item.Enabled) end\n','')
a=t.index('show(2)\nlocal changedBeamModel')
b=t.index('-- Partial allocation',a)
t=t[:a]+'''show(2)
local nestedModel = controller._visual
local nestedLight = controller._lights[1].item
local authorChild = make("Folder")
authorChild.Name, authorChild.Parent = "AuthorLightChild", nestedLight
controller:Clear("light foreign child")
assert(not nestedModel.Destroyed and authorChild.Parent == nestedLight and not nestedLight.Enabled)
nestedModel:Destroy()

'''+t[b:]
t=t.replace('{#Flashlight.Definitions()+3, #Flashlight.Definitions()+6, #Flashlight.Definitions()+10, #Flashlight.Definitions()+19}','{#Flashlight.Definitions()+2, #Flashlight.Definitions()+3, #Flashlight.Definitions()+4, #Flashlight.Definitions()+6}')
t=t.replace('F toggles','Mouse toggles').replace('pass F','pass LMB').replace('lamp/F/round','lamp/LMB/round')
start=t.index('print("PASS: real FlashlightController')
end=t.index('\n]==]',start)
t=t[:start]+'print("PASS: real FlashlightController A-only LMB toggle/default-on/lifecycle, 12 parts/three lens-directed spots/no sphere or air Beams, shared core/spill lens and forward axis, no decorative raycasts, camera rollback/no accumulation, cursor/map/menu/capture/death/respawn cleanup, foreign subtree edits preserved, light allocation rollback, no Root writes")'+t[end:]
p.write_text(t,encoding='utf-8',newline='\n')
p=root/'tests/flashlight-presentation.luau';t=p.read_text(encoding='utf-8')
t=t.replace('#definitions + 2','#definitions + 1')
t=t.replace('main.angle == 36','main.angle == 28').replace('main.brightness == 3','main.brightness == 4')
t=t.replace('fill.range == 18 and Flash.Settings.Lights.fill.angle == 50','fill.range == 32 and Flash.Settings.Lights.fill.angle == 56')
t=t.replace('fill.brightness == 0.35 and not Flash.Settings.Lights.fill.shadows','fill.brightness == 0.45 and Flash.Settings.Lights.fill.shadows')
a=t.index('local cone = Flash.Settings.Cone')
b=t.index('local hands = 0',a)
t=t[:a]+'''assert(Flash.Settings.Cone == nil and Flash.ConeFrames == nil, "Rejected billboard cone remains")
-- Both cones widen physically from the lens: the spill always surrounds the core.
for _, distance in {1, 5, 10, 20, 32} do
 local coreRadius=distance*math.tan(math.rad(Flash.Settings.Lights.main.angle/2))
 local spillRadius=distance*math.tan(math.rad(Flash.Settings.Lights.fill.angle/2))
 assert(coreRadius>0 and spillRadius>coreRadius*2)
end
'''+t[b:]
t=t.replace('narrow two-spot specs/directed hand fill, four nested forward cone layers with bounded width factors/length/taper/near-far fade/composite opacity and invalid-ray guards','bright circular core/soft wider spill at lens, directed hand fill, no billboard cone')
p.write_text(t,encoding='utf-8',newline='\n')
print('Prepared 3 production Sources, surface-light fixtures and immutable baseline; no Studio writes.')
