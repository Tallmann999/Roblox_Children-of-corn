from pathlib import Path

root=Path(__file__).resolve().parents[3]
s=(root/'scripts/build-flashlight-cone-installer.py').read_text(encoding='utf-8')
s=s.replace('flashlight-cone','flashlight-directional').replace('flashlight_cone','flashlight_directional').replace('projector-cone','directional surface-light').replace('Projector cone','Directional flashlight')
s=s.replace('Only FlashlightController and FlashlightPresentation may change.','Only FlashlightController, FlashlightPresentation and RoundText may change.')
s=s.replace('"StarterPlayer/StarterPlayerScripts/GameClient/Controllers/FlashlightController",','"StarterPlayer/StarterPlayerScripts/GameClient/Controllers/FlashlightController",\n    "ReplicatedStorage/GameShared/Game/RoundText",')
s=s.replace('Expected only two flashlight presentation Sources:','Expected only three flashlight/input Sources:')
s=s.replace('    accepted, sources, classes, changed = mapping()','    accepted, sources, classes, changed = mapping()\n    prior_path = ROOT / ".artifacts/playtests/2026-10-20-flashlight-cone/payload.json"\n    require(sha(prior_path.read_bytes()) == "ed0b774f5f5d85e86d2b3e0351fcb3fd8bd881a45930d61d199b196d83f1839f", "Frozen prior cone stage changed")\n    prior = {row["path"]: row for row in json.loads(prior_path.read_bytes())["entries"]}')
s=s.replace('"before": old["after"], "after": after}', '"before": old["after"], "staged": prior[path]["after"], "after": after}')
needle='    return core.replace("@PAYLOAD_SHA@", payload_sha).replace("@BASELINE_SHA@", BASELINE_SHA)'
assert s.count(needle)==1
s=s.replace(needle,'''    # Accept exactly one complete known pre-edit state, or the complete final
    # state. Mixed partial states and arbitrary edits are refused before writes.
    core = core.replace("local byPath, baseline, final = {}, true, true", "local byPath, baseline, staged, final = {}, true, true, true")
    core = core.replace("final = final and hash == entry.after", "staged = staged and hash == entry.staged\\n        final = final and hash == entry.after")
    core = core.replace("assert(baseline or final,", "assert(baseline or staged or final,")
    core = core.replace("digest(item.Source) == entry.before,", "digest(item.Source) == (if baseline then entry.before else entry.staged),")
    return core.replace("@PAYLOAD_SHA@", payload_sha).replace("@BASELINE_SHA@", BASELINE_SHA)''')
(root/'scripts/build-flashlight-directional-installer.py').write_text(s,encoding='utf-8',newline='\n')
s=(root/'scripts/verify-flashlight-cone-copy.py').read_text(encoding='utf-8')
s=s.replace('flashlight-cone','flashlight-directional').replace('flashlight_cone','flashlight_directional').replace('projector-cone','directional flashlight')
s=s.replace('two declared','three declared').replace('Both and only two','All and only three').replace('two projector-cone Sources','three directional/input Sources')
s=s.replace('FlashlightController and FlashlightPresentation contents only.','FlashlightController, FlashlightPresentation and RoundText contents only.')
(root/'scripts/verify-flashlight-directional-copy.py').write_text(s,encoding='utf-8',newline='\n')
s=(root/'tests/flashlight-cone-pipeline.py').read_text(encoding='utf-8')
s=s.replace('flashlight-cone','flashlight-directional').replace('flashlight_cone','flashlight_directional').replace('projector-cone','directional flashlight').replace('two-Source','three-Source')
s=s.replace('result.changed==2','result.changed==3').replace('changed=2','changed=3').replace('"source_changes": 2','"source_changes": 3').replace('for point=1,2 do','for point=1,3 do')
# Also execute the real generated installer on the complete installed unsaved
# cone state. This never serializes or writes a scene file.
needle='local rejected={}\n'
assert s.count(needle)==1
s=s.replace(needle,'''local prior=serde.decode("json",fs.readFile(".artifacts/playtests/2026-10-20-flashlight-cone/payload.json"))
local staged=setup()
for _,entry in prior.entries do if entry.source then resolve(staged,entry.path).Source=entry.source end end
local stagedBefore=snapshot(staged)
ok,result=run(staged)assert(ok and result.changed==3 and result.created==0)
unchanged(staged,stagedBefore,true)
local rejected={}
''')
s=s.replace('for path in changed do\n', '''for _,entry in prior.entries do if entry.source then
 reject("partial-prior-stage:"..entry.path,function(p)resolve(p,entry.path).Source=entry.source end)
end end
for path in changed do
''')
s=s.replace('crlfAccepted=true','crlfAccepted=true,priorStageAccepted=true')
(root/'tests/flashlight-directional-pipeline.py').write_text(s,encoding='utf-8',newline='\n')
print('Prepared guarded 3-Source pipeline with exact complete prior-stage acceptance.')
