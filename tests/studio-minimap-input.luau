-- Actual engine UI and current input-handler methods; physical Escape is protected by MCP.
local source=game.Players.LocalPlayer.PlayerScripts.GameClient.Controllers
local Controller=require(source.MinimapController)
local Movement=require(source.MovementController)
local movement=setmetatable({}, {__index=Movement})
movement:Init({});movement._gui.Name="MinimapMovementAcceptance"
movement._active=true
movement._snapshot={stamina=100,stamina_capacity=100,sprint_exhausted=false}
local controller=setmetatable({}, {__index=Controller})
controller:Init({});controller._hud._gui.Name="MinimapInputAcceptance"
local checks={}
local ok,problem=pcall(function()
 controller:Start({Controllers={MovementController=movement}})
 local s={phase="active",minimap={round_id=1,visited={},deaths={}}}
 controller:SetSnapshot(s)
 controller:_input({KeyCode=Enum.KeyCode.M},false)
 assert(controller._expanded and movement._mapOpen and movement._cursorGuard.Visible)
 assert(movement._hint.Text=="M — закрыть карту · охота продолжается")
 controller:SetSnapshot(s);assert(controller._expanded)
 controller:_input({KeyCode=Enum.KeyCode.Escape},true)
 assert(not controller._expanded and not movement._mapOpen and not movement._cursorGuard.Visible)
 checks.escape_processed_handler=true;checks.m_open=true;checks.snapshot_preserves=true
 movement._cursorOpen=true
 controller:SetExpanded(true);controller:_input({KeyCode=Enum.KeyCode.Escape},false)
 assert(movement._cursorOpen and movement._cursorGuard.Visible)
 checks.alt_state_restored=true
 controller:SetExpanded(true)
 controller:SetSnapshot({phase="caught",minimap=s.minimap})
 assert(not controller._expanded)
 checks.phase_closes=true
end)
controller:Destroy();movement:Destroy()
assert(ok,tostring(problem))
checks.method="Current handler methods + actual engine UI; synthetic key argument, physical Esc manual pending"
return game.HttpService:JSONEncode(checks)
