-- Established streaming/event adapter + actual production controller new branch.
-- EditableMesh construction is represented by a separately verified visual stub.
local fs = require("@lune/fs")
local base = fs.readFile("tests/monster-animation.luau")
local marker = "local model, root, parts = rig()"
local at = assert(base:find(marker, 1, true), "Animation fixture boundary changed")
local setup = base:sub(1, at - 1)
local oldRequire = [[		require = function(module)
			assert(module == poseModule)
			return Pose
		end,]]
local replacement = [==[
		task = {spawn = function(callback) table.insert(buildTasks, callback) end},
		warn = function(message) table.insert(buildWarnings, message) end,
		require = function(module)
			if module == poseModule then return Pose end
			if module.Name == "HarvestArtGeometry" then
				return {Template=function(key)
					table.insert(templateKeys,key)
					if interruptBuild then interruptBuild() end
					return {Key=key}
				end}
			end
			assert(module.Name == "HarvestWardenVisual")
			return {new=function(template, host)
				local model = node("Model", "HarvestWardenVisual")
				parent(model,host)
				local visual = {model=model,host=host,key=template.Key,steps=0}
				function visual:Valid() return self.model.Parent == self.host end
				function visual:Step(frame,pose,visible,carriers)
					self.frame,self.pose,self.visible,self.carriers=frame,pose,visible,carriers
					self.steps += 1
					return 22
				end
				function visual:Destroy() parent(self.model,nil); self.destroyed=true end
				table.insert(builtVisuals,visual)
				return visual
			end}
		end,
]==]
local first = assert(setup:find(oldRequire, 1, true), "Animation module adapter changed")
setup = setup:sub(1, first - 1) .. replacement .. setup:sub(first + #oldRequire)
local prelude = [==[
local buildTasks,buildWarnings,templateKeys,builtVisuals={}, {}, {}, {}
local interruptBuild=nil
for _, name in {"HarvestArtGeometry", "HarvestWardenVisual"} do
	local object=node("ModuleScript",name)
	parent(object,sharedGame)
end
]==]
local boundary = "local heartbeat = signal()"
local before = assert(setup:find(boundary, 1, true))
setup = setup:sub(1, before - 1) .. prelude .. setup:sub(before)
local checks = [==[
local model,root,parts=rig()
model:SetAttribute("HarvestWardenVersion",1)
model:SetAttribute("HarvestArtVariant","A")
local rootWrites=root.Writes
controller:Start()
assert(controller._model==model and not controller._warden and #buildTasks==1)
buildTasks[1]()
local classic=controller._warden
assert(classic and classic.key=="WardenClassic" and classic.model.Parent==root)
assert(#model:GetChildren()==10,"Local art changed ten-child compatible rig")
heartbeat:Fire(1/30)
assert(not classic.visible and classic.pose==Pose.WardenRest)
model:SetAttribute("HuntState","chase")
root.CFrame += V3.new(.2,0,0)
heartbeat:Fire(1/30)
assert(classic.visible and classic.pose.LeftArm~=CF.identity and classic.carriers==controller._parts)
assert(root.Writes==rootWrites+1,"Decoration wrote Root")
local steps=classic.steps
heartbeat:Fire(.001)
assert(classic.steps==steps,"Warden exceeded30Hz throttle")
model:SetAttribute("HarvestArtVariant","B")
assert(not controller._model and classic.destroyed,"Variant takeover kept stale classic art")
heartbeat:Fire(.5)
assert(#buildTasks==2)
buildTasks[2]()
local detailed=controller._warden
assert(detailed and detailed.key=="WardenDetailed")
model:SetAttribute("HuntState","stopped")
assert(not detailed.visible and detailed.pose==Pose.WardenRest,"Stopped Warden retained lights/pose")
parent(model,nil)
assert(detailed.destroyed and not controller._warden)
-- Unloading the round during Template's yielded build cannot attach stale art.
local newer,newRoot,newParts=rig()
newer:SetAttribute("HarvestWardenVersion",1)
newer:SetAttribute("HarvestArtVariant","A")
heartbeat:Fire(.5)
assert(#buildTasks==3)
interruptBuild=function() parent(newer,nil) end
buildTasks[3]()
assert(#builtVisuals==2 and not controller._warden and not newRoot:FindFirstChild("HarvestWardenVisual"))
-- Memory allocation failure must not produce an invisible active attacker or
-- retry expensive builds on every Heartbeat. A successful retry hides fallback.
local retryModel,retryRoot,retryParts=rig()
retryModel:SetAttribute("HarvestWardenVersion",1)
retryModel:SetAttribute("HarvestArtVariant","B")
heartbeat:Fire(.5)
assert(#buildTasks==4)
interruptBuild=function() error("simulated EditableMesh budget") end
buildTasks[4]()
assert(controller._wardenFallback and not controller._wardenBuildPending and #buildWarnings==1)
retryModel:SetAttribute("HuntState","chase")
heartbeat:Fire(1/30)
for _, part in retryParts do assert(part.Transparency==0,"Allocation failure made invisible attacker") end
for _=1,18 do heartbeat:Fire(.25) end
assert(#buildTasks==4,"Failed art construction retried too frequently")
for _=1,4 do heartbeat:Fire(.25) end
assert(#buildTasks==5)
interruptBuild=nil
buildTasks[5]()
assert(controller._warden and not controller._wardenFallback)
for _, part in retryParts do assert(part.Transparency==1,"Recovered art retained primitive fallback") end
controller:Destroy()
assert(#buildWarnings==1)
assert(connected==disconnected,"New art lifecycle leaked connections")
print("PASS: actual MonsterAnimationController cached A/B build, Root-nested compatibility, raw asset pose, dormant/stopped visibility, carrier masking,30Hz throttle, variant replacement, Root preservation, streamed-out generation guard and allocation-failure visible fallback/bounded5second retry/recovery")
]==]
local fn = assert(loadstring(setup .. checks, "harvest-warden-animation"))
fn()
