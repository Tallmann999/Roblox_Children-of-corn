"""Build guarded code-only Harvest installer and exact localhost JSON payload.

The accepted engine baseline is read-only. This does not connect Studio, launch
Rojo sync, serialize a place, change the map or publish an experience.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / "place/Children_of_corn.before-harvest-art-20261016.rbxl"
BASELINE_SHA = "b5084774be98e97a045c6b90a819bdd061b8d4f61b259c3a6e4eb77233ff2646"
NATIVE = ROOT / ".artifacts/harvest-art-native-before.json"
OUT = ROOT / ".artifacts/harvest-install"
ROOTS = ("ReplicatedStorage/GameShared", "ServerScriptService/GameServer", "StarterPlayer/StarterPlayerScripts/GameClient")
ALLOWED_CHANGED = {
    "ReplicatedStorage/GameShared/Game/CornAppearance",
    "ReplicatedStorage/GameShared/Game/MonsterPose",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornController",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornBackdropController",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornAppearanceController",
    "ServerScriptService/GameServer/Game/MonsterHunt",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/MonsterAnimationController",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CaptureController",
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def normalized(source):
    return source.replace("\r\n", "\n")


def owned(path):
    return any(path == root or path.startswith(root + "/") for root in ROOTS)


def compact(data):
    return json.dumps(data,ensure_ascii=False,allow_nan=False,separators=(",", ":")).encode("utf-8")


def baseline_data():
    require(BASELINE.stat().st_size == 1003371 and sha(BASELINE.read_bytes()) == BASELINE_SHA, "Immutable accepted Harvest baseline changed")
    result = subprocess.run([str(ROOT / ".tools/lune/lune.exe"), "run", str(OUT / "read-baseline.luau"), str(BASELINE)], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    data = json.loads(result.stdout)
    require(len(data["sources"]) == 80 and len(data["classes"]) == 89, "Unexpected engine baseline code topology")
    native = json.loads(NATIVE.read_bytes())
    require(native.get("ok") is True and len(native["sources"]) == 80, "Accepted native Source audit unavailable")
    native_sources = {row["path"]:{key:row[key] for key in ("class","sha256","bytes")} for row in native["sources"]}
    require(data["sources"] == native_sources, "Engine baseline differs from exact native Source audit")
    (OUT / "baseline-code.json").write_bytes(compact(data)+b"\n")
    return data


def current_mapping():
    sources, classes = {}, {}
    def visit(node, prefix=None):
        path = "" if prefix is None else (prefix+"/"+node["name"] if prefix else node["name"])
        if owned(path):
            require(path not in classes, "Duplicate configured code path: "+path)
            classes[path] = node["className"]
        files = [f for f in node.get("filePaths",[]) if f.startswith("src/") and f.endswith(".luau")]
        require(len(files) <= 1, "Ambiguous Source binding: "+path)
        if files:
            target = (ROOT / files[0]).resolve()
            require(owned(path) and target.is_relative_to((ROOT / "src").resolve()), "Source outside owned code roots")
            source = normalized(target.read_text(encoding="utf-8"))
            require(len(source.encode()) < 200000, "Studio Source byte limit: "+path)
            sources[path] = source
        for child in node.get("children",[]): visit(child,path)
    visit(json.loads((ROOT / "build/sourcemap.json").read_bytes()))
    built = {}
    def xml_visit(item,prefix=""):
        name = item.find("Properties/string[@name='Name']").text
        path = prefix+"/"+name if prefix else name
        source = item.find("Properties/*[@name='Source']")
        if source is not None:
            require(path not in built and path in sources and item.attrib["class"] == classes[path], "Unexpected built Source: "+path)
            built[path] = normalized(source.text or "")
        for child in item.findall("Item"): xml_visit(child,path)
    for item in ET.parse(ROOT / "build/code-foundation.rbxlx").getroot().findall("Item"): xml_visit(item)
    require(built == sources, "Stale Rojo build; run scripts/check.ps1 before building Harvest installer")
    require(set(sources).issubset(classes), "Source outside configured code topology")
    return sources,classes


CORE = r'''local run = game:GetService("RunService")
assert(run:IsStudio() and run:IsEdit() and not run:IsRunning(), "Stop Play before Harvest code installation")
local world = game:GetService("Workspace")
for _, name in { "Asmr_Base", "ASMR_Models", "Cooking_Cheff", "SpeedMonkey", "New_+1 speed monkey" } do
    assert(not world:FindFirstChild(name), "Foreign game root; nothing changed: " .. name)
end
local map = world:FindFirstChild("CornMap")
assert(map and map:IsA("Model") and map:GetAttribute("corn_project_id") == "children_of_corn", "Open owned Children_of_corn; nothing changed")
local ground, field = map:FindFirstChild("Ground"), map:FindFirstChild("FieldZone")
assert(ground and ground:IsA("BasePart") and ground.Size == Vector3.new(630, 2, 630), "Expected accepted 630 Ground; nothing changed")
assert(field and field:IsA("BasePart") and field.Size == Vector3.new(630, 10, 630), "Expected accepted 630 FieldZone; nothing changed")
for _, name in { "Runtime", "CornRoundRuntime", "CornClientPlants", "CornClientBackdrop" } do
    assert(not map:FindFirstChild(name), "Runtime exists; nothing changed: " .. name)
end
assert(not game:GetService("ReplicatedStorage"):FindFirstChild("CornRuntimeArt"), "Runtime art exists; nothing changed")
local encoding = game:GetService("EncodingService")
local function rawDigest(value)
    local raw = encoding:ComputeStringHash(value, Enum.HashAlgorithm.Sha256)
    return (string.gsub(raw, ".", function(byte) return string.format("%02x", string.byte(byte)) end))
end
local function digest(value)
    return rawDigest((string.gsub(value, "\r\n", "\n")))
end
assert(type(raw) == "string" and rawDigest(raw) == "@PAYLOAD_SHA@", "Harvest payload SHA256 mismatch; nothing changed")
local payload = game:GetService("HttpService"):JSONDecode(raw)
assert(payload.version == 1 and payload.owner == "harvest_warden_v1" and payload.baselineSha256 == "@BASELINE_SHA@", "Unknown Harvest payload; nothing changed")
local function uniqueChild(parent, name)
    local found = nil
    for _, child in parent:GetChildren() do
        if child.Name == name then assert(not found, "Duplicate instance name; nothing changed: " .. name) found = child end
    end
    return found
end
local function resolve(path)
    local item = game
    for _, name in string.split(path, "/") do item = item and uniqueChild(item, name) end
    return item
end
local function pathOf(item)
    local names = {}
    while item and item ~= game do table.insert(names, 1, item.Name) item = item.Parent end
    assert(item == game, "Detached code instance; nothing changed")
    return table.concat(names, "/")
end
local editor = game:GetService("ScriptEditorService")
local byPath, baseline, final = {}, true, true
for _, entry in payload.entries do
    assert(not byPath[entry.path], "Duplicate payload Source binding; nothing changed")
    byPath[entry.path] = entry
    assert(not entry.source or digest(entry.source) == entry.after, "Payload Source hash differs; nothing changed")
    local item = resolve(entry.path)
    if item then
        assert(item.ClassName == entry.class, "Source class collision; nothing changed: " .. entry.path)
        assert(not editor:FindScriptDocument(item), "Close script tab; nothing changed: " .. entry.path)
        local hash = digest(item.Source)
        baseline = baseline and entry.before ~= nil and hash == entry.before
        final = final and hash == entry.after
    else
        assert(entry.before == nil, "Missing original Source; nothing changed: " .. entry.path)
        final = false
    end
end
for path, class in payload.classes do
    local item = resolve(path)
    if item then
        assert(item.ClassName == class, "Code class collision; nothing changed: " .. path)
        baseline = baseline and payload.beforeClasses[path] == class
    else
        assert(not payload.beforeClasses[path], "Missing original code container; nothing changed: " .. path)
        final = false
    end
end
for _, prefix in payload.roots do
    local root = assert(resolve(prefix), "Missing owned code root; nothing changed")
    for _, item in root:GetDescendants() do
        local path = pathOf(item)
        assert(payload.classes[path] == item.ClassName and resolve(path) == item, "Unexpected code topology; nothing changed: " .. path)
    end
end
local sourceCount = 0
for _, item in game:GetDescendants() do
    if item:IsA("LuaSourceContainer") then
        local path = pathOf(item)
        assert(byPath[path] and resolve(path) == item, "Unexpected persistent Source; nothing changed: " .. path)
        sourceCount += 1
    end
end
assert(baseline or final, "Unknown Source edits or partial Harvest install; nothing changed")
assert(sourceCount == (if baseline then 80 else #payload.entries), "Persistent Source count differs; nothing changed")
if final then return { changed = 0, created = 0, totalSources = #payload.entries, repeated = true } end
local history = game:GetService("ChangeHistoryService")
history:SetWaypoint("Before Corn Harvest art code")
local changed, created = {}, {}
local ok, problem = pcall(function()
    for _, row in payload.addedNodes do
        assert(not resolve(row.path), "Added node appeared; rollback: " .. row.path)
        local parent = assert(resolve(string.match(row.path, "^(.*)/[^/]+$")))
        local item = Instance.new(row.class)
        table.insert(created, item)
        item.Name = string.match(row.path, "[^/]+$")
        local entry = byPath[row.path]
        if entry then item.Source = assert(entry.source) end
        item.Parent = parent
    end
    for _, entry in payload.entries do
        if entry.before and entry.source then
            local item = assert(resolve(entry.path))
            assert(digest(item.Source) == entry.before, "Original Source changed; rollback: " .. entry.path)
            table.insert(changed, { item = item, source = item.Source })
            item.Source = entry.source
        end
    end
    for _, entry in payload.entries do
        local item = assert(resolve(entry.path))
        assert(digest(item.Source) == entry.after, "Final Source verification failed; rollback: " .. entry.path)
    end
    for path, class in payload.classes do assert(resolve(path).ClassName == class, "Final code topology differs; rollback") end
end)
if not ok then
    for index = #changed, 1, -1 do changed[index].item.Source = changed[index].source end
    for index = #created, 1, -1 do created[index]:Destroy() end
    error("Harvest code update rolled back: " .. tostring(problem))
end
history:SetWaypoint("Installed Corn Harvest art code")
return { changed = #changed, created = #created, totalSources = #payload.entries, repeated = false }
'''


def transport_sources(raw,direct,payload_sha):
    # Each temporary StringValue and MCP stage stays below native 200k limits.
    chunks, offset = [], 0
    while offset < len(raw):
        end = min(len(raw),offset+125000)
        while end < len(raw) and raw[end] & 0xC0 == 0x80: end -= 1
        piece = raw[offset:end]
        piece.decode("utf-8")
        chunks.append(piece)
        offset = end
    folder_name = "CornHarvestInstallerTransport"
    rows = []
    for index,piece in enumerate(chunks,1):
        name = f"Chunk{index:03}"
        rows.append({"name":name,"bytes":len(piece),"sha256":sha(piece)})
        equals = "=="
        while ("]"+equals+"]").encode() in piece: equals += "="
        stage = f'''-- Temporary owned transport only; never a project Source or world art.
local run = game:GetService("RunService")
assert(run:IsStudio() and run:IsEdit() and not run:IsRunning(), "Stop Play before staging Harvest data")
local world = game:GetService("Workspace")
local map = world:FindFirstChild("CornMap")
assert(map and map:IsA("Model") and map:GetAttribute("corn_project_id") == "children_of_corn", "Wrong game; no transport staged")
assert(map.Ground.Size == Vector3.new(630,2,630) and map.FieldZone.Size == Vector3.new(630,10,630), "Wrong field; no transport staged")
local parent = game:GetService("ReplicatedStorage")
local folder = parent:FindFirstChild("{folder_name}")
if folder then
    assert(folder:IsA("Folder") and folder:GetAttribute("HarvestInstallTransportOwned") == true and folder:GetAttribute("PayloadSha256") == "{payload_sha}", "Foreign transport preserved")
else
    folder = Instance.new("Folder")
    folder.Name = "{folder_name}"
    folder:SetAttribute("HarvestInstallTransportOwned",true)
    folder:SetAttribute("PayloadSha256","{payload_sha}")
    folder.Parent = parent
end
local value = [{equals}[''' + piece.decode("utf-8") + f''']{equals}]
local part = folder:FindFirstChild("{name}")
if part then
    assert(part:IsA("StringValue") and part.Value == value and #part:GetChildren() == 0, "Foreign/changed transport chunk preserved")
else
    part = Instance.new("StringValue")
    part.Name = "{name}"
    part.Value = value
    part.Parent = folder
end
return {{staged="{name}",bytes=#value,payloadSha256="{payload_sha}"}}
'''
        (OUT / f"stage-{index:03}.luau").write_text(stage,encoding="utf-8",newline="\n")
        (OUT / f"payload-{index:03}.txt").write_bytes(piece)
    wrapper = "-- Generated loader for exact temporary StringValue transport.\nlocal install = (function()\n"+direct+"end)()\n"
    wrapper += f'''local parent = game:GetService("ReplicatedStorage")
local folder = parent:FindFirstChild("{folder_name}")
assert(folder and folder:IsA("Folder") and folder:GetAttribute("HarvestInstallTransportOwned") == true and folder:GetAttribute("PayloadSha256") == "{payload_sha}", "Unknown Harvest transport preserved")
local names = {{''' + ",".join(json.dumps(row["name"]) for row in rows) + f'''}}
assert(#folder:GetChildren() == {len(rows)}, "Missing/foreign Harvest transport content preserved")
local pieces = {{}}
for _, name in names do
    local item = folder:FindFirstChild(name)
    assert(item and item:IsA("StringValue") and #item:GetChildren() == 0, "Unknown Harvest transport child preserved")
    table.insert(pieces,item.Value)
end
local result = install(table.concat(pieces))
folder:Destroy()
return result
'''
    (ROOT / "scripts/install-harvest-staged.luau").write_text(wrapper,encoding="utf-8",newline="\n")
    (OUT / "transport-manifest.json").write_bytes(compact({"payload_sha256":payload_sha,"chunks":rows})+b"\n")
    return len(rows)


def build():
    OUT.mkdir(parents=True,exist_ok=True)
    before = baseline_data()
    sources,classes = current_mapping()
    old = before["sources"]
    old_project = {path:row for path,row in old.items() if owned(path)}
    expected_new = {
        "ReplicatedStorage/GameShared/Game/HarvestArtGeometry",
        "ReplicatedStorage/GameShared/Game/HarvestWardenVisual",
        "ServerScriptService/GameServer/Game/HarvestWorld",
        "ServerScriptService/GameServer/Services/HarvestArtService",
        "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/HarvestGeometryController",
    }
    data_manifest = json.loads((ROOT / "assets/harvest-warden/catalog-manifest.json").read_bytes())
    for file in data_manifest["sources"]:
        require(file.startswith("src/shared/Game/HarvestGeometryData/") and file.endswith(".luau"), "Unexpected Harvest data manifest path")
        suffix = file[len("src/shared/"):-len(".luau")]
        if suffix.endswith("/init"): suffix = suffix[:-len("/init")]
        expected_new.add("ReplicatedStorage/GameShared/"+suffix)
    require(set(sources) == set(old_project)|expected_new, "Unexpected or missing Harvest Source topology; run check.ps1")
    require(all(classes.get(path) == cls for path,cls in before["classes"].items()), "Accepted code container/class changed")
    added = set(classes)-set(before["classes"])
    require(all(classes[path] in ("ModuleScript","Folder") for path in added), "Only new ModuleScripts/Folders permitted")
    require(added == expected_new, "Unexpected added code container outside declared Harvest Sources")
    changed = {path for path,source in sources.items() if path in old and sha(source.encode()) != old[path]["sha256"]}
    require(changed.issubset(ALLOWED_CHANGED), "Undeclared existing Source changes: "+str(sorted(changed-ALLOWED_CHANGED)))
    entries = []
    for path in sorted(set(sources)|set(old)):
        previous = old.get(path)
        source = sources.get(path)
        after = sha(source.encode()) if source is not None else previous["sha256"]
        row = {"path":path,"class":classes.get(path,previous["class"] if previous else None),"after":after}
        if previous: row["before"] = previous["sha256"]
        if not previous or previous["sha256"] != after: row["source"] = source
        entries.append(row)
    payload = {"version":1,"owner":"harvest_warden_v1","baselineSha256":BASELINE_SHA,
               "roots":list(ROOTS),"beforeClasses":before["classes"],"classes":classes,
               "addedNodes":[{"path":path,"class":classes[path]} for path in sorted(added,key=lambda p:(p.count("/"),p))],"entries":entries}
    raw = compact(payload)
    payload_sha = sha(raw)
    core = CORE.replace("@PAYLOAD_SHA@",payload_sha).replace("@BASELINE_SHA@",BASELINE_SHA)
    (OUT / "payload.json").write_bytes(raw)
    direct = "-- Generated guarded Harvest code-only installer. Input is the exact JSON payload string.\nreturn function(raw)\n"+core+"end\n"
    (ROOT / "scripts/install-harvest-direct.luau").write_text(direct,encoding="utf-8",newline="\n")
    http = "-- Generated guarded Harvest code-only installer; correct stopped Corn Edit only.\nlocal install = (function()\n"+direct+"end)()\n" + r'''local http = game:GetService("HttpService")
local previous = http.HttpEnabled
local ok, result = pcall(function()
    if not previous then http.HttpEnabled = true end
    return http:GetAsync("http://127.0.0.1:8768/payload.json", true)
end)
local restored, restoreProblem = pcall(function()
    if http.HttpEnabled ~= previous then http.HttpEnabled = previous end
end)
assert(restored, "Could not restore HttpEnabled; no Sources changed: " .. tostring(restoreProblem))
assert(ok, "Local Harvest payload fetch failed; no Sources changed: " .. tostring(result))
return install(result)
'''
    (ROOT / "scripts/install-harvest.luau").write_text(http,encoding="utf-8",newline="\n")
    transport_chunks = transport_sources(raw,direct,payload_sha)
    manifest = {"transport_chunks":transport_chunks,"version":1,"baseline_sha256":BASELINE_SHA,"native_before_sha256":sha(NATIVE.read_bytes()),
                "payload_bytes":len(raw),"payload_sha256":payload_sha,"baseline_sources":80,"final_sources":len(entries),
                "project_sources":len(sources),"new_nodes":len(added),"new_sources":sum(path not in old for path in sources),
                "changed_existing":sorted(changed),"source_only":True,"scene_written":False,
                "installers":{name:sha((ROOT / "scripts" / name).read_bytes()) for name in ("install-harvest.luau","install-harvest-direct.luau","install-harvest-staged.luau")}}
    (OUT / "manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8",newline="\n")
    require(sha(BASELINE.read_bytes()) == BASELINE_SHA, "Immutable baseline changed during build")
    print(json.dumps(manifest,ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compact",action="store_true",help="Workflow compatibility; installer always uses compact SHA256 guards")
    parser.parse_args()
    build()
