"""Build the guarded 69-to-71 Source handheld update. No scene writes or sync."""
import argparse
import hashlib
import importlib.util
import json
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / "place/Children_of_corn.before-handheld-20261012.rbxl"
BASELINE_HASH = "66997087e67a05e0095448c8c1fb91b51d61f6acf1de865a78df3b376fb87d93"
PREFIXES = ("ReplicatedStorage/GameShared", "ServerScriptService/GameServer", "StarterPlayer/StarterPlayerScripts/GameClient")
ADDITIONS = {
    "ReplicatedStorage/GameShared/Game/HandheldPresentation",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/HandheldController",
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def owned(path):
    return any(path == prefix or path.startswith(prefix + "/") for prefix in PREFIXES)


def literal(value):
    return json.dumps(value, ensure_ascii=False).replace(".", r"\046")


def build():
    require(BASELINE.stat().st_size == 995413 and hashlib.sha256(BASELINE.read_bytes()).hexdigest() == BASELINE_HASH, "Immutable 69-Source before-handheld baseline changed")
    history_input = ROOT / "scripts/scarecrow-source-history.json"
    history_output = ROOT / "scripts/handheld-source-history.json"
    history = json.loads(history_input.read_text(encoding="utf-8"))
    require(len(history) == 69 and all(isinstance(v, list) and v and all(isinstance(s, str) for s in v) for v in history.values()), "Expected approved 69-Source scarecrow history")
    if history_output.exists():
        extra_history = json.loads(history_output.read_text(encoding="utf-8"))
        require(set(extra_history) == set(history) | ADDITIONS, "Unexpected handheld history topology")
        for path, versions in extra_history.items():
            require(isinstance(versions, list) and versions and all(isinstance(s, str) for s in versions), "Invalid handheld Source history")
            for version in versions:
                if version not in history.setdefault(path, []):
                    history[path].append(version)
    spec = importlib.util.spec_from_file_location("preservation", ROOT / "scripts/verify-scene-preservation.py")
    preservation = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(preservation)
    baseline_dom, _ = preservation.known_dom(BASELINE)
    old_sources = {path: node["properties"]["Source"][1].replace("\r\n", "\n") for path, node in baseline_dom.items() if "Source" in node["properties"]}
    require(len(old_sources) == 69 and set(old_sources) == set(json.loads(history_input.read_text(encoding="utf-8"))), "Scarecrow history/baseline Source paths differ")
    for path, source in old_sources.items():
        require(source in history[path], "Immutable Source not fingerprinted by scarecrow history: " + path)
    mapping, classes = {}, {}
    def visit_map(node, prefix=None):
        path = "" if prefix is None else (prefix + "/" + node["name"] if prefix else node["name"])
        if owned(path):
            require(path not in classes, "Duplicate build path: " + path)
            classes[path] = node["className"]
        files = [f for f in node.get("filePaths", []) if f.startswith("src/") and f.endswith(".luau")]
        require(len(files) <= 1, "Ambiguous source mapping: " + path)
        if files:
            require(owned(path) and (ROOT / files[0]).resolve().is_relative_to((ROOT / "src").resolve()), "Source mapping outside owned src")
            mapping[path] = files[0]
        for child in node.get("children", []):
            visit_map(child, path)
    visit_map(json.loads((ROOT / "build/sourcemap.json").read_text(encoding="utf-8")))
    require(len(mapping) == 71 and set(mapping) == set(old_sources) | ADDITIONS, "Run check.ps1: expected the 69 baseline Sources plus exactly 2 handheld additions")
    baseline_classes = {path: node["class"] for path, node in baseline_dom.items() if owned(path)}
    require(set(classes) == set(baseline_classes) | ADDITIONS, "Unexpected new/missing code container")
    require(all(classes[path] == cls for path, cls in baseline_classes.items()), "Original code class changed")
    require(all(classes[path] == "ModuleScript" for path in ADDITIONS), "New handheld Sources must be ModuleScript")
    rows = []
    def visit(item, prefix=""):
        name = item.find("Properties/string[@name='Name']").text
        path = prefix + "/" + name if prefix else name
        source = item.find("Properties/*[@name='Source']")
        if source is not None:
            require(path in mapping and owned(path), "Build Source outside configured code roots")
            current = (source.text or "").replace("\r\n", "\n")
            require(current == (ROOT / mapping[path]).read_text(encoding="utf-8").replace("\r\n", "\n"), "Stale build; run check.ps1: " + path)
            require(len(current.encode("utf-8")) < 200000, "Studio Source limit exceeded: " + path)
            require(item.attrib["class"] == classes[path], "Build class/sourcemap mismatch")
            baseline = old_sources.get(path)
            previous = [s for s in history.get(path, []) if s != current and s != baseline]
            # The current Source already recognizes an unchanged baseline;
            # avoid embedding the 19 geometry chunks twice unnecessarily.
            explicit_baseline = baseline if baseline != current else None
            rows.append((path, classes[path], explicit_baseline, previous, current))
        for child in item.findall("Item"):
            visit(child, path)
    for item in ET.parse(ROOT / "build/code-foundation.rbxlx").getroot().findall("Item"):
        visit(item)
    require(len(rows) == 71 and {row[0] for row in rows} == set(mapping), "Missing/duplicate built Source")
    entries = "{\n" + ",\n".join("{path=" + literal(path) + ",allowMissing=" + ("true" if path in ADDITIONS else "false") + ",class=" + literal(cls) + ",baseline=" + ("nil" if old is None else literal(old)) + ",history={" + ",".join(literal(s) for s in previous) + "},source=" + literal(current) + "}" for path, cls, old, previous, current in rows) + "\n}"
    expected_classes = "{" + ",".join("[" + literal(path) + "]=" + literal(cls) for path, cls in sorted(classes.items())) + "}"
    head = '''-- Generated by build-handheld-installer.py. Children_of_corn stopped Edit only.
-- Immutable before-handheld SHA256: ''' + BASELINE_HASH + '''
local run=game:GetService("RunService")
assert(run:IsStudio() and not run:IsRunning(),"Stop Play before handheld code installation")
local world=game:GetService("Workspace")
assert(not world:FindFirstChild("Asmr_Base") and not world:FindFirstChild("ASMR_Models"),"Wrong game; nothing changed")
local map=world:FindFirstChild("CornMap")
assert(map and map:IsA("Model") and map:GetAttribute("corn_project_id")=="children_of_corn","Open Children_of_corn; nothing changed")
local function resolve(path)
    local found=game
    for _,segment in string.split(path,"/") do found=found and found:FindFirstChild(segment) end
    return found
end
local function normalized(source) return (string.gsub(source,"\\r\\n","\\n")) end
local editor=game:GetService("ScriptEditorService")
local entries='''
    tail = '''
local expectedClasses=''' + expected_classes + '''
local additions={'''+ ",".join("[" + literal(path) + "]=true" for path in sorted(ADDITIONS)) + '''}
for path,cls in expectedClasses do
    local item=resolve(path)
    assert(item or additions[path],"Missing original code; nothing changed: "..path)
    assert(not item or item.ClassName==cls,"Code class collision; nothing changed: "..path)
end
for _,entry in entries do
    local item=resolve(entry.path)
    local parentPath=string.match(entry.path,"^(.*)/[^/]+$")
    assert(resolve(parentPath),"Missing code parent; nothing changed: "..entry.path)
    if item then
        assert(item.ClassName==entry.class,"Object collision; nothing changed: "..entry.path)
        assert(editor:FindScriptDocument(item)==nil,"Close script tab; nothing changed: "..entry.path)
        local recognized=normalized(item.Source)==normalized(entry.source) or (entry.baseline and normalized(item.Source)==normalized(entry.baseline))
        for _,oldSource in entry.history do recognized=recognized or normalized(item.Source)==normalized(oldSource) end
        assert(recognized,"Manual Source edit; nothing changed: "..entry.path)
    else
        assert(entry.allowMissing==true and entry.class=="ModuleScript","Missing baseline code; nothing changed: "..entry.path)
    end
end
for _,prefix in {"ReplicatedStorage/GameShared","ServerScriptService/GameServer","StarterPlayer/StarterPlayerScripts/GameClient"} do
    for _,item in resolve(prefix):GetDescendants() do
        local suffix=string.sub(item:GetFullName(),#string.gsub(prefix,"/",".")+2)
        local path=prefix.."/"..string.gsub(suffix,"%.","/")
        assert(expectedClasses[path]==item.ClassName,"Unrecognized code instance; nothing changed: "..path)
    end
end
local history=game:GetService("ChangeHistoryService")
history:SetWaypoint("Before Corn handheld presentation")
local changed,created={},{}
local ok,problem=pcall(function()
    for _,entry in entries do
        local item=resolve(entry.path)
        if not item then
            local parentPath,name=string.match(entry.path,"^(.*)/([^/]+)$")
            item=Instance.new(entry.class);item.Name=name
            table.insert(created,item)
            item.Source=entry.source;item.Parent=resolve(parentPath)
        elseif normalized(item.Source)~=normalized(entry.source) then
            table.insert(changed,{item=item,source=item.Source})
            item.Source=entry.source
        end
    end
end)
if not ok then
    for _,entry in changed do entry.item.Source=entry.source end
    for index=#created,1,-1 do created[index]:Destroy() end
    error("Handheld update rolled back: "..tostring(problem))
end
history:SetWaypoint("Installed Corn handheld presentation")
print("ChildrenOfCorn: held-item code installed; author world and art preserved")
return {changed=#changed,created=#created,sources=71}
'''
    output = ROOT / "scripts/install-handheld.luau"
    output.write_text(head + entries + "\n" + tail, encoding="utf-8")
    for path, _, _, _, current in rows:
        if current not in history.setdefault(path, []):
            history[path].append(current)
    history_output.write_text(json.dumps(history, ensure_ascii=False, indent=2), encoding="utf-8")
    require(hashlib.sha256(BASELINE.read_bytes()).hexdigest() == BASELINE_HASH, "Immutable baseline changed during build")
    print(json.dumps({"built": str(output), "sources": len(rows), "new_sources": len(ADDITIONS), "baseline_sources": 69, "bytes": output.stat().st_size, "scene_written": False}))


if __name__ == "__main__":
    argparse.ArgumentParser(description=__doc__).parse_args()
    build()
