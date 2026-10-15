"""Build the guarded 75-to-75 Source readability update. No scene writes or sync."""
import argparse
import hashlib
import importlib.util
import json
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / "place/Children_of_corn.before-readability-20261013.rbxl"
BASELINE_HASH = "4ee103b95110e2a2a1a691d58a7bb5cdc34d0dc466d3c5265b47eb5823986546"
PREFIXES = ("ReplicatedStorage/GameShared", "ServerScriptService/GameServer", "StarterPlayer/StarterPlayerScripts/GameClient")
ADDITIONS = set()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def owned(path):
    return any(path == prefix or path.startswith(prefix + "/") for prefix in PREFIXES)


def literal(value):
    return json.dumps(value, ensure_ascii=False).replace(".", r"\046")


def load_json(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, "Duplicate JSON key: " + key)
            result[key] = value
        return result
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique)


def build(compact=False):
    require(BASELINE.stat().st_size == 1007172 and hashlib.sha256(BASELINE.read_bytes()).hexdigest() == BASELINE_HASH, "Immutable 75-Source before-readability baseline changed")
    history_input = ROOT / "scripts/audio-source-history.json"
    history_output = ROOT / "scripts/readability-source-history.json"
    history = load_json(history_input)
    require(len(history) == 75 and all(isinstance(v, list) and v and all(isinstance(s, str) for s in v) for v in history.values()), "Expected approved 75-Source audio history")
    if history_output.exists():
        extra_history = load_json(history_output)
        require(set(extra_history) == set(history) | ADDITIONS, "Unexpected readability history topology")
        for path, versions in extra_history.items():
            require(isinstance(versions, list) and versions and all(isinstance(s, str) for s in versions), "Invalid readability Source history")
            for version in versions:
                if version not in history.setdefault(path, []):
                    history[path].append(version)
    spec = importlib.util.spec_from_file_location("preservation", ROOT / "scripts/verify-scene-preservation.py")
    preservation = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(preservation)
    baseline_dom, _ = preservation.known_dom(BASELINE)
    old_sources = {path: node["properties"]["Source"][1].replace("\r\n", "\n") for path, node in baseline_dom.items() if "Source" in node["properties"]}
    require(len(old_sources) == 75 and set(old_sources) == set(load_json(history_input)), "Audio history/baseline Source paths differ")
    for path, source in old_sources.items():
        require(source in history[path], "Immutable Source not fingerprinted by audio history: " + path)
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
    visit_map(load_json(ROOT / "build/sourcemap.json"))
    require(len(mapping) == 75 and set(mapping) == set(old_sources) | ADDITIONS, "Run check.ps1: expected the 75 baseline Sources without new instances")
    baseline_classes = {path: node["class"] for path, node in baseline_dom.items() if owned(path)}
    require(set(classes) == set(baseline_classes) | ADDITIONS, "Unexpected new/missing code container")
    require(all(classes[path] == cls for path, cls in baseline_classes.items()), "Original code class changed")
    require(all(classes[path] == "ModuleScript" for path in ADDITIONS), "No new Sources are authorized")
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
    require(len(rows) == 75 and {row[0] for row in rows} == set(mapping), "Missing/duplicate built Source")
    if compact:
        # Keep the same exact-source guards without embedding megabytes of
        # unchanged geometry data and historical Sources into the MCP request.
        def digest(source):
            return hashlib.sha256(source.replace("\r\n", "\n").encode("utf-8")).hexdigest()
        entries = "{\n" + ",\n".join(
            "{path=" + literal(path) + ",class=" + literal(cls) +
            ",hash=" + literal(digest(current)) + ",history={" +
            ",".join(literal(digest(s)) for s in ([old] if old is not None else []) + previous) +
            "},source=" + (literal(current) if old is not None or previous else "nil") + "}"
            for path, cls, old, previous, current in rows
        ) + "\n}"
    else:
        entries = "{\n" + ",\n".join("{path=" + literal(path) + ",allowMissing=" + ("true" if path in ADDITIONS else "false") + ",class=" + literal(cls) + ",baseline=" + ("nil" if old is None else literal(old)) + ",history={" + ",".join(literal(s) for s in previous) + "},source=" + literal(current) + "}" for path, cls, old, previous, current in rows) + "\n}"
    expected_classes = "{" + ",".join("[" + literal(path) + "]=" + literal(cls) for path, cls in sorted(classes.items())) + "}"
    head = '''-- Generated by build-readability-installer.py. Children_of_corn stopped Edit only.
-- Immutable before-readability SHA256: ''' + BASELINE_HASH + '''
local run=game:GetService("RunService")
assert(run:IsStudio() and not run:IsRunning(),"Stop Play before readability code installation")
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
history:SetWaypoint("Before Corn hunt readability")
local changed,created={},{}
local ok,problem=pcall(function()
    for _,entry in entries do
        local item=resolve(entry.path)
        assert(item,"Original code disappeared; update rolled back: "..entry.path)
        if normalized(item.Source)~=normalized(entry.source) then
            table.insert(changed,{item=item,source=item.Source})
            item.Source=entry.source
        end
    end
end)
if not ok then
    for _,entry in changed do entry.item.Source=entry.source end
    for index=#created,1,-1 do created[index]:Destroy() end
    error("Readability update rolled back: "..tostring(problem))
end
history:SetWaypoint("Installed Corn hunt readability")
print("ChildrenOfCorn: readability code installed; author world and art preserved")
return {changed=#changed,created=#created,sources=75}
'''
    if compact:
        require(not ADDITIONS, "Compact installer only supports the existing code topology")
        hash_function = '''local encoding=game:GetService("EncodingService")
local function digest(source)
    local raw=encoding:ComputeStringHash(normalized(source),Enum.HashAlgorithm.Sha256)
    return (string.gsub(raw,".",function(byte) return string.format("%02x",string.byte(byte)) end))
end
'''
        head = head.replace("local entries=", hash_function + "local entries=")
        old_guard = '''        local recognized=normalized(item.Source)==normalized(entry.source) or (entry.baseline and normalized(item.Source)==normalized(entry.baseline))
        for _,oldSource in entry.history do recognized=recognized or normalized(item.Source)==normalized(oldSource) end'''
        new_guard = '''        local currentHash=digest(item.Source)
        local recognized=currentHash==entry.hash
        for _,oldHash in entry.history do recognized=recognized or currentHash==oldHash end
        assert(not entry.source or digest(entry.source)==entry.hash,"Installer Source/hash mismatch; nothing changed: "..entry.path)'''
        require(old_guard in tail, "Compact guard insertion point missing")
        tail = tail.replace(old_guard, new_guard)
        tail = tail.replace('if normalized(item.Source)~=normalized(entry.source) then',
                            'if digest(item.Source)~=entry.hash then\n            assert(entry.source,"Missing changed Source; update rolled back: "..entry.path)')
    output = ROOT / "scripts/install-readability.luau"
    output.write_text(head + entries + "\n" + tail, encoding="utf-8")
    for path, _, _, _, current in rows:
        if current not in history.setdefault(path, []):
            history[path].append(current)
    history_output.write_text(json.dumps(history, ensure_ascii=False, indent=2), encoding="utf-8")
    require(hashlib.sha256(BASELINE.read_bytes()).hexdigest() == BASELINE_HASH, "Immutable baseline changed during build")
    print(json.dumps({"built": str(output), "sources": len(rows), "new_sources": len(ADDITIONS), "baseline_sources": 75, "bytes": output.stat().st_size, "compact_sha256_guards": compact, "scene_written": False}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compact", action="store_true", help="Native SHA256 Source guards; omit unchanged geometry Sources from the MCP request")
    args = parser.parse_args()
    build(compact=args.compact)
