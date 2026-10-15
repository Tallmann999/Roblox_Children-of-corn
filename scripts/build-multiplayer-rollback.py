"""Build exact initial-attempt rollback. No Studio, Source or scene writes."""
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EVIDENCE = ROOT / ".artifacts/playtests/2026-10-15-multiplayer/initial-attempt"
MANIFEST_HASH = "fb25ba722d6385ca6cc5e911113b2f9cb807c76fa44dabaa3b51f3f0d90a489a"
INITIAL_INSTALLER_HASH = "0818132a28e127910d4edbe81d369889ba9e0d02ad9ead5a802a129a8ed79f0f"
spec = importlib.util.spec_from_file_location("multiplayer_rollback_helpers", ROOT / "scripts/verify-multiplayer-copy.py")
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)


def digest(source):
    return hashlib.sha256(source.replace("\r\n", "\n").encode()).hexdigest()


def literal(value):
    return json.dumps(value, ensure_ascii=False).replace(".", r"\046")


def build():
    v.require(v.sha256(v.BASELINE) == v.BASELINE_HASH and v.BASELINE.stat().st_size == v.BASELINE_BYTES, "Immutable baseline changed")
    manifest_path = EVIDENCE / "pipeline-manifest.json"
    v.require(v.sha256(manifest_path) == MANIFEST_HASH, "Initial installed-source manifest changed")
    v.require(v.sha256(EVIDENCE / "install-initial-multiplayer.luau") == INITIAL_INSTALLER_HASH, "Initial installer evidence changed")
    manifest = v.r.load_json(manifest_path)
    before, _ = v.r.p.known_dom(v.BASELINE)
    original = {p: n["properties"]["Source"][1].replace("\r\n", "\n") for p, n in before.items() if "Source" in n["properties"]}
    project = manifest["project_source_sha256"]
    v.require(len(original) == 78 and len(project) == 77, "Unexpected original/initial Source count")
    v.require(set(project) == {p for p in original if v.r.p.owned(p)} | v.ADDITIONS, "Initial Source topology changed")
    classes = {p: n["class"] for p, n in before.items() if v.r.p.owned(p)} | {p: "ModuleScript" for p in v.ADDITIONS}
    hashes = project | {p: digest(s) for p, s in original.items() if not v.r.p.owned(p)}
    changed = {p for p in original if digest(original[p]) != hashes[p]}
    initial_changes = {
        "ReplicatedStorage/GameShared/Config/GameConfig", "ReplicatedStorage/GameShared/Game/RoundText",
        "ServerScriptService/GameServer/Game/MonsterHunt", "ServerScriptService/GameServer/Game/RoundAudio",
        "ServerScriptService/GameServer/Services/RoundService",
        "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/RoundController",
        "StarterPlayer/StarterPlayerScripts/GameClient/Game/RoundHud",
    }
    v.require(changed == initial_changes, "Expected exact seven initial existing Source deltas")
    entries = []
    for path, hash_value in sorted(hashes.items()):
        cls = classes.get(path, before[path]["class"] if path in before else "ModuleScript")
        entries.append("{path=" + literal(path) + ",class=" + literal(cls) + ",initial=" + literal(hash_value) +
            ",baseline=" + (literal(digest(original[path])) if path in original else "nil") +
            ",source=" + (literal(original[path]) if path in changed else "nil") + "}")
    expected = "{" + ",".join("[" + literal(p) + "]=" + literal(c) for p, c in sorted(classes.items())) + "}"
    source = '''-- Exact rollback of failed initial seven-Source multiplayer attempt only.
-- No outside diagnostics, art, map, Lighting or other scene content is changed.
-- Frozen manifest SHA256: ''' + MANIFEST_HASH + '''
local run=game:GetService("RunService")
assert(run:IsStudio() and run:IsEdit() and not run:IsRunning(),"Stop Play before initial multiplayer rollback")
local function child(parent,name)
    local found=nil
    for _,item in parent:GetChildren() do
        if item.Name==name then assert(not found,"Duplicate name; nothing changed: "..name) found=item end
    end
    return found
end
local function resolve(path)
    local item=game
    for _,name in string.split(path,"/") do item=item and child(item,name) end
    return item
end
local function pathOf(item)
    local names={}
    while item and item~=game do table.insert(names,1,item.Name) item=item.Parent end
    assert(item==game,"Detached original; nothing changed")
    return table.concat(names,"/")
end
local world=game:GetService("Workspace")
local map=resolve("Workspace/CornMap")
assert(map and map:IsA("Model") and map:GetAttribute("corn_project_id")=="children_of_corn","Wrong Children_of_corn target; nothing changed")
local ground,field=resolve("Workspace/CornMap/Ground"),resolve("Workspace/CornMap/FieldZone")
assert(ground and field and ground:IsA("BasePart") and field:IsA("BasePart") and ground.Size==Vector3.new(630,2,630) and field.Size==Vector3.new(630,10,630),"Expected accepted630 map; nothing changed")
assert(not map:FindFirstChild("Runtime") and not world:FindFirstChild("Asmr_Base") and not world:FindFirstChild("ASMR_Models"),"Wrong/runtime scene; nothing changed")
local encoding=game:GetService("EncodingService")
local function normalized(value) return (string.gsub(value,"\\r\\n","\\n")) end
local function digest(value)
    local raw=encoding:ComputeStringHash(normalized(value),Enum.HashAlgorithm.Sha256)
    return (string.gsub(raw,".",function(byte) return string.format("%02x",string.byte(byte)) end))
end
local editor=game:GetService("ScriptEditorService")
local entries={
''' + ",\n".join(entries) + '''
}
local expectedClasses=''' + expected + '''
local additions={''' + ",".join("[" + literal(p) + "]=true" for p in sorted(v.ADDITIONS)) + '''}
for path,cls in expectedClasses do
    local item=resolve(path)
    assert(item and item.ClassName==cls,"Missing/colliding initial code; nothing changed: "..path)
end
for _,entry in entries do
    local item=resolve(entry.path)
    assert(item and item.ClassName==entry.class,"Missing/colliding initial Source; nothing changed: "..entry.path)
    assert(editor:FindScriptDocument(item)==nil,"Close script tab; nothing changed: "..entry.path)
    assert(digest(item.Source)==entry.initial,"Source differs from exact initial install; nothing changed: "..entry.path)
    assert(not entry.source or digest(entry.source)==entry.baseline,"Rollback Source/hash mismatch; nothing changed: "..entry.path)
    if additions[entry.path] then
        assert(#item:GetChildren()==0 and #item:GetTags()==0 and next(item:GetAttributes())==nil,"New module manually extended; nothing changed: "..entry.path)
    end
end
for _,prefix in {"ReplicatedStorage/GameShared","ServerScriptService/GameServer","StarterPlayer/StarterPlayerScripts/GameClient"} do
    for _,item in resolve(prefix):GetDescendants() do
        local path=pathOf(item)
        assert(expectedClasses[path]==item.ClassName and resolve(path)==item,"Unknown owned-code topology; nothing changed: "..path)
    end
end
local history=game:GetService("ChangeHistoryService")
history:SetWaypoint("Before exact initial Corn multiplayer rollback")
local changed,detached={},{}
local ok,problem=pcall(function()
    for _,entry in entries do
        local item=assert(resolve(entry.path))
        if entry.source then
            table.insert(changed,{item=item,source=item.Source})
            item.Source=entry.source
        elseif additions[entry.path] then
            table.insert(detached,{item=item,parent=item.Parent,path=entry.path})
            item.Parent=nil
        end
    end
    for _,entry in entries do
        local item=resolve(entry.path)
        if additions[entry.path] then assert(not item,"New module still attached; rollback failed")
        else assert(item and digest(item.Source)==entry.baseline,"Baseline Source verification failed: "..entry.path) end
    end
end)
if not ok then
    for index=#detached,1,-1 do detached[index].item.Parent=detached[index].parent end
    for index=#changed,1,-1 do changed[index].item.Source=changed[index].source end
    error("Initial multiplayer rollback reverted: "..tostring(problem))
end
-- Destroy only after every baseline Source and detached-module check passed.
for _,entry in detached do entry.item:Destroy() end
history:SetWaypoint("Restored exact pre-multiplayer Corn code")
return {changed=#changed,removed=#detached,sources=75,totalSources=78,outsideDiagnosticsUntouched=true}
'''
    path = ROOT / "scripts/rollback-initial-multiplayer.luau"
    path.write_text(source, encoding="utf-8")
    v.require(v.sha256(v.BASELINE) == v.BASELINE_HASH and v.sha256(manifest_path) == MANIFEST_HASH, "Immutable input changed during build")
    print(json.dumps({"built": str(path), "bytes": path.stat().st_size, "restored_sources": 7, "removed_modules": 2, "guarded_sources": 80, "initial_manifest_sha256": MANIFEST_HASH, "scene_written": False}))


if __name__ == "__main__":
    build()
