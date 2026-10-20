local p=game.Players.LocalPlayer
local run=game:GetService('RunService')
local http=game:GetService('HttpService')
local f=require(p.PlayerScripts.GameClient.Controllers.FlashlightController)
local movement=require(p.PlayerScripts.GameClient.Controllers.MovementController)
movement._cursorOpen=false;movement:_render()
local saved=f._focused;local started=os.clock()
local all={initialOn=f._on,roundId=f._roundId,events={}}
local result=Instance.new('StringValue');result.Name='Result';result.Value='ready';result.Parent=script
run:BindToRenderStep('CornConeAcceptanceFocus',198,function()f._focused=true end)
local function states()
 local v={on=f._on,lights={},beams={}}
 for _,r in f._lights do v.lights[r.item.Name]=r.item.Enabled end
 for _,r in f._beams do v.beams[r.item.Name]=r.item.Enabled end
 return v
end
local input=game.UserInputService.InputBegan:Connect(function(i)
 if i.KeyCode==Enum.KeyCode.F then task.defer(function()task.wait(.05);table.insert(all.events,states())end)end
end)
task.wait(.2)
local ok,report=xpcall(function()
-- Run in a temporary LocalScript beside the normal Bootstrap, not MCP require cache.
-- Read-only render sample; diagnostic focus/camera/input staging is external.
local run = game:GetService("RunService")
local http = game:GetService("HttpService")
assert(run:IsStudio() and run:IsClient() and run:IsRunning())
local player = assert(game:GetService("Players").LocalPlayer)
local controller = require(player.PlayerScripts.GameClient.Controllers.FlashlightController)
local model = assert(controller._visual, "Start a real active A round")
assert(workspace.CornMap:GetAttribute("HarvestArtVariant") == "A")
assert(controller:_visualOwned(), "Native ownership readback failed")
local beams, lights = {}, {}
local parts = 0
for _, item in model:GetDescendants() do
	assert(not item:IsA("LuaSourceContainer"))
	if item:IsA("Beam") then
		table.insert(beams, item)
		assert(item.FaceCamera and item.Texture == "" and item.Attachment0 and item.Attachment1)
	elseif item:IsA("Light") then
		assert(item:IsA("SpotLight"), "Spherical PointLight remains")
		lights[item.Name] = { angle = item.Angle, range = item.Range, brightness = item.Brightness }
	elseif item:IsA("BasePart") then
		parts += 1
		assert(item.Anchored and not item.CanCollide and not item.CanTouch and not item.CanQuery)
	end
end
assert(#beams == 4 and parts <= 14, "Unexpected cone budget")
local samples = {}
local started = os.clock()
for _ = 1, 80 do
	run.RenderStepped:Wait()
	assert(
		controller._visual == model and controller:_visualOwned(),
		"Viewmodel churn or native ownership drift"
	)
	local current = {}
	for _, beam in beams do
		assert(beam.Enabled == (controller._on and controller._coneDistance >= 0.5))
		local delta = beam.Attachment1.WorldPosition - beam.Attachment0.WorldPosition
		assert(delta.Magnitude > 0 and delta.Magnitude <= 30.01)
		assert(beam.Width0 < beam.Width1 and beam.Width0 <= 0.2)
		local forward = workspace.CurrentCamera.CFrame.LookVector
		table.insert(
			current,
			{
				name = beam.Name,
				length = delta.Magnitude,
				startWidth = beam.Width0,
				endWidth = beam.Width1,
				forwardDot = delta.Unit:Dot(forward),
				enabled = beam.Enabled,
			}
		)
	end
	table.insert(samples, { t = os.clock() - started, beams = current })
end
return http:JSONEncode({
	passed = true,
	duration = os.clock() - started,
	parts = parts,
	lights = lights,
	beams = #beams,
	samples = samples,
	limits = "One normal-bootstrap client. Read-only render sampling, not full-round fear/FPS/four-client acceptance.",
})


end,debug.traceback)
all.observerOk=ok;all.observer=if ok then http:JSONDecode(report) else report
local walls={}
local wallOk,wallReport=xpcall(function()
 local function probe(distance,thickness)
  local emitter=assert(f._cone).emitter.item.CFrame
  local part=Instance.new('Part');part.Name='CornConeDiagnosticWall';part.Size=Vector3.new(12,12,thickness)
  part.CFrame=emitter*CFrame.new(0,0,-distance);part.Anchored=true;part.CanCollide=true;part.CanQuery=true;part.CanTouch=false;part.Transparency=1;part.CastShadow=false
  part:SetAttribute('CornFlashlightConeDiagnosticOwned',true);part.Parent=workspace;table.insert(walls,part)
  run.RenderStepped:Wait();run.RenderStepped:Wait()
  local data={distance=f._coneDistance,expected=distance-thickness/2,widths={},enabled={}}
  for _,r in f._beams do table.insert(data.widths,r.item.Width1);table.insert(data.enabled,r.item.Enabled)end
  assert(math.abs(data.distance-data.expected)<.06,'Real wall clipping differs')
  part:Destroy();run.RenderStepped:Wait();run.RenderStepped:Wait()
  return data
 end
 local far=probe(8,1)
 local near=probe(.25,.1)
 for _,enabled in near.enabled do assert(not enabled,'Near wall must suppress volume')end
 return {far=far,near=near,restoredLength=f._coneDistance}
end,debug.traceback)
for _,wall in walls do if wall.Parent then wall:Destroy()end end
all.wallOk=wallOk;all.wall=wallReport
while os.clock()-started<18 do
 all.current=states();all.elapsed=os.clock()-started;result.Value=http:JSONEncode(all);task.wait(.1)
end
input:Disconnect();run:UnbindFromRenderStep('CornConeAcceptanceFocus');f._focused=saved;f:_suspend();all.done=true;result.Value=http:JSONEncode(all)

