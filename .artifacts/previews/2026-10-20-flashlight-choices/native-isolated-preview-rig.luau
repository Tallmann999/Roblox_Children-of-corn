local p=game.Players.LocalPlayer
local run=game:GetService('RunService')
local uis=game:GetService('UserInputService')
local L=game:GetService('Lighting')
local data=require(game.ReplicatedStorage.GameShared.Game.FlashlightPresentation)
local mode=Instance.new('IntValue');mode.Name='Mode';mode.Value=1;mode.Parent=script
local phase=Instance.new('NumberValue');phase.Name='Phase';phase.Value=0;phase.Parent=script
local active=Instance.new('BoolValue');active.Name='Active';active.Value=true;active.Parent=script
local result=Instance.new('StringValue');result.Name='Result';result.Parent=script
local c=workspace.CurrentCamera
local savedCamera={type=c.CameraType,frame=c.CFrame,focus=c.Focus,fov=c.FieldOfView}
local savedMouse=uis.MouseIconEnabled
local savedLighting={}
for _,key in {'Ambient','OutdoorAmbient','Brightness','EnvironmentDiffuseScale','EnvironmentSpecularScale'}do savedLighting[key]=L[key]end
local sky=Instance.new('Sky');sky.Name='CornGifPreviewBlackSky';sky:SetAttribute('CornGifPreviewOwned',true)
for _,key in {'SkyboxBk','SkyboxDn','SkyboxFt','SkyboxLf','SkyboxRt','SkyboxUp'}do sky[key]='rbxassetid://127362238475901'end
sky.CelestialBodiesShown=false;sky.StarCount=0;sky.Parent=L
local preview=Instance.new('Folder');preview.Name='CornFlashlightPreviewSet';preview:SetAttribute('CornGifPreviewOwned',true);preview.Parent=workspace
local function prop(name,size,pos,color,material)
 local a=Instance.new('Part');a.Name=name;a.Size=size;a.CFrame=CFrame.new(pos);a.Color=color;a.Material=material;a.Anchored=true;a.CanCollide=true;a.CanQuery=true;a.CanTouch=false;a.Parent=preview;return a
end
prop('Wall',Vector3.new(26,14,1),Vector3.new(2000,1006.5,2020),Color3.fromRGB(75,68,59),Enum.Material.WoodPlanks)
prop('Floor',Vector3.new(30,1,38),Vector3.new(2000,999.5,2014),Color3.fromRGB(42,39,34),Enum.Material.Ground)
prop('Crate',Vector3.new(3,3,3),Vector3.new(1995,1001.5,2013),Color3.fromRGB(61,45,28),Enum.Material.WoodPlanks)
local can=prop('Barrel',Vector3.new(3,2,2),Vector3.new(2005,1001.5,2015),Color3.fromRGB(52,55,57),Enum.Material.Metal);can.Shape=Enum.PartType.Cylinder;can.CFrame=CFrame.new(can.Position)*CFrame.Angles(0,0,math.pi/2)
local template=game.ReplicatedStorage.CornRuntimeArt.CornPlantTemplate
for i,offset in {Vector3.new(-9,0,9),Vector3.new(-8.5,0,15),Vector3.new(-9,0,19),Vector3.new(8,0,9),Vector3.new(9,0,15),Vector3.new(9,0,19)}do
 local a=template:Clone();a.Name='PreviewCorn'..i;a.CFrame=CFrame.new(Vector3.new(2000,1000+a.Size.Y/2,2000)+offset)*CFrame.Angles(0,i*.7,0);a.Anchored=true;a.CanCollide=false;a.CanQuery=false;a.CanTouch=false;a.Parent=preview
end


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

local rig=Instance.new('Model');rig.Name='CornGifFlashlightRig';rig:SetAttribute('CornGifPreviewOwned',true);rig.Parent=c
local parts={}
for _,def in data.Definitions()do
 local a=Instance.new('Part');a.Name=def.name;a.Size=def.size;a.Color=def.color;a.Material=def.material;a.Shape=def.shape;a.Anchored=true;a.CanCollide=false;a.CanTouch=false;a.CanQuery=false;a.CastShadow=false;a.Parent=rig
 table.insert(parts,{item=a,frame=def.localFrame})
end
local emitter=Instance.new('Part');emitter.Name='LensEmitter';emitter.Size=Vector3.new(.05,.05,.05);emitter.Transparency=1;emitter.Anchored=true;emitter.CanCollide=false;emitter.CanQuery=false;emitter.CanTouch=false;emitter.CastShadow=false;emitter.Parent=rig
local main=Instance.new('SpotLight');main.Face=Enum.NormalId.Front;main.Color=Color3.new(1,1,1);main.Range=64;main.Brightness=3;main.Shadows=true;main.Parent=emitter
local fill=Instance.new('SpotLight');fill.Face=Enum.NormalId.Front;fill.Color=Color3.new(1,1,1);fill.Range=18;fill.Angle=50;fill.Brightness=.2;fill.Shadows=true;fill.Parent=emitter
local hand=Instance.new('Attachment');hand.CFrame=data.LensFrame:Inverse()*data.HandFillFrame;hand.Parent=emitter
local hl=Instance.new('SpotLight');hl.Face=Enum.NormalId.Front;hl.Range=1.5;hl.Angle=75;hl.Brightness=.08;hl.Color=Color3.new(1,1,1);hl.Parent=hand
local endpart=emitter:Clone();endpart:ClearAllChildren();endpart.Name='PreviewConeEnd';endpart.Parent=rig
local beams={}
local cone=data.ConeFrames(18)
for i,layer in cone.layers do
 local first=Instance.new('Attachment');first.CFrame=layer.first;first.Parent=emitter
 local last=Instance.new('Attachment');last.CFrame=CFrame.new(0,0,cone.length)*layer.last;last.Parent=endpart
 local b=Instance.new('Beam');b.Attachment0=first;b.Attachment1=last;b.Width0=layer.width0;b.Width1=layer.width1;b.FaceCamera=true;b.Segments=16;b.Texture='';b.Transparency=data.Settings.Cone.transparency;b.Color=data.Settings.Cone.color;b.LightEmission=1;b.LightInfluence=0;b.Parent=emitter;table.insert(beams,b)
end
c.CameraType=Enum.CameraType.Scriptable
run:BindToRenderStep('CornIsolatedGifCamera',205,function()
 local a=phase.Value
 local pos=Vector3.new(2000,1005+.025*math.sin(a*2),2000)
 local base=CFrame.lookAt(pos,pos+Vector3.new(0,0,20))
 c.CFrame=base*CFrame.Angles(.015*math.sin(a),.13*math.sin(a),.002*math.sin(a*2));c.Focus=c.CFrame*CFrame.new(0,0,-20)
 c.FieldOfView=math.min(120,math.deg(2*math.atan(math.tan(math.rad(31))*c.ViewportSize.Y/360)))
 local view=c.CFrame*CFrame.new(-.44,-.48,-1.24)
 for _,part in parts do part.item.CFrame=view*part.frame end
 emitter.CFrame=view*data.LensFrame;endpart.CFrame=emitter.CFrame*CFrame.new(0,0,-18)
 main.Angle=if mode.Value==1 then 24 else 40;fill.Enabled=mode.Value~=1
 for _,b in beams do b.Enabled=mode.Value==3 end
 uis.MouseIconEnabled=false
 L.Ambient=Color3.new(0,0,0);L.OutdoorAmbient=Color3.new(0,0,0);L.Brightness=0;L.EnvironmentDiffuseScale=0;L.EnvironmentSpecularScale=0
 for _,g in p.PlayerGui:GetChildren()do if g:IsA('ScreenGui')and g~=gui then g.Enabled=false end end
 result.Value=game.HttpService:JSONEncode({mode=mode.Value,phase=a,roi={640,360},viewport={c.ViewportSize.X,c.ViewportSize.Y},previewOnly=true})
end)
local started=os.clock()
while active.Value and os.clock()-started<600 do task.wait(.1)end
run:UnbindFromRenderStep('CornIsolatedGifCamera')
rig:Destroy();preview:Destroy();gui:Destroy();sky:Destroy()
for k,v in savedLighting do L[k]=v end
for _,g in guis do if g.item.Parent==p.PlayerGui then g.item.Enabled=g.enabled end end
c.CameraType=savedCamera.type;c.CFrame=savedCamera.frame;c.Focus=savedCamera.focus;c.FieldOfView=savedCamera.fov;uis.MouseIconEnabled=savedMouse
result.Value='done'

