local p=game.Players.LocalPlayer
local run=game:GetService('RunService')
local uis=game:GetService('UserInputService')
local f=require(p.PlayerScripts.GameClient.Controllers.FlashlightController)
local movement=require(p.PlayerScripts.GameClient.Controllers.MovementController)
movement._cursorOpen=false;movement:_render()
local mode=Instance.new('IntValue');mode.Name='Mode';mode.Value=1;mode.Parent=script
local phase=Instance.new('NumberValue');phase.Name='Phase';phase.Value=0;phase.Parent=script
local active=Instance.new('BoolValue');active.Name='Active';active.Value=true;active.Parent=script
local result=Instance.new('StringValue');result.Name='Result';result.Parent=script
local savedFocus=f._focused
local savedMouse=uis.MouseIconEnabled
local c=workspace.CurrentCamera
local savedFov=c.FieldOfView
local guis={}
for _,g in p.PlayerGui:GetChildren()do if g:IsA('ScreenGui')then table.insert(guis,{item=g,enabled=g.Enabled})end end
local gui=Instance.new('ScreenGui');gui.Name='CornFlashlightGifPreviewMask';gui.IgnoreGuiInset=true;gui.ResetOnSpawn=false;gui.DisplayOrder=100000;gui:SetAttribute('CornGifPreviewOwned',true)
local function mask(name,pos,size)
 local a=Instance.new('Frame');a.Name=name;a.Position=pos;a.Size=size;a.BackgroundColor3=Color3.new(0,0,0);a.BorderSizePixel=0;a.Parent=gui
end
mask('Top',UDim2.fromScale(0,0),UDim2.new(1,0,.5,-180))
mask('Bottom',UDim2.new(0,0,.5,180),UDim2.new(1,0,.5,-180))
mask('Left',UDim2.new(0,0,.5,-180),UDim2.new(.5,-320,0,360))
mask('Right',UDim2.new(.5,320,.5,-180),UDim2.new(.5,-320,0,360))
gui.Parent=p.PlayerGui
local function set(r,key,v)r.item[key]=v;r.properties[key]=r.item[key]end
run:BindToRenderStep('CornGifPreviewFocus',198,function()f._focused=true;f._on=true end)
run:BindToRenderStep('CornGifPreviewCamera',200.5,function()
 local a=phase.Value
 local pos=Vector3.new(-94.5,18.9+.025*math.sin(a*2),-121)
 local base=CFrame.lookAt(pos,pos+Vector3.new(0,0,20))
 c.CFrame=base*CFrame.Angles(.015*math.sin(a),.13*math.sin(a),.002*math.sin(a*2))
 c.FieldOfView=math.min(120,math.deg(2*math.atan(math.tan(math.rad(31))*c.ViewportSize.Y/360)))
end)
run:BindToRenderStep('CornGifPreviewLight',203,function()
 uis.MouseIconEnabled=false
 for _,g in p.PlayerGui:GetChildren()do if g:IsA('ScreenGui')and g~=gui then g.Enabled=false end end
 for _,r in f._lights do
  if r.item.Name=='main'then set(r,'Angle',if mode.Value==1 then 24 else 40);set(r,'Range',64);set(r,'Brightness',3);set(r,'Shadows',true);set(r,'Enabled',true)
  elseif r.item.Name=='fill'then set(r,'Angle',50);set(r,'Range',18);set(r,'Brightness',.2);set(r,'Shadows',true);set(r,'Enabled',mode.Value~=1)
  else set(r,'Enabled',true)end
 end
 for _,r in f._beams do set(r,'Enabled',mode.Value==3 and f._coneDistance>=.5)end
 result.Value=game.HttpService:JSONEncode({mode=mode.Value,phase=phase.Value,owned=f._visual and f:_visualOwned(),roi={640,360},viewport={c.ViewportSize.X,c.ViewportSize.Y}})
end)
result.Value='ready'
local started=os.clock()
while active.Value and os.clock()-started<600 do task.wait(.1)end
run:UnbindFromRenderStep('CornGifPreviewFocus');run:UnbindFromRenderStep('CornGifPreviewCamera');run:UnbindFromRenderStep('CornGifPreviewLight')
f._focused=savedFocus;f:_suspend();c.FieldOfView=savedFov;uis.MouseIconEnabled=savedMouse
for _,g in guis do if g.item.Parent==p.PlayerGui then g.item.Enabled=g.enabled end end
gui:Destroy();result.Value='done'

