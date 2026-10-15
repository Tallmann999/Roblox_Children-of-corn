"""Guarded three-Source update of the author's exact imported CornfieldFog.

The immutable XML and original live snapshot must agree before generation.
No Rojo mappings, scene bytes, properties, attributes or READ_ME are written.
"""
import argparse
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
ORIGINAL = ROOT / "assets/CornfieldFog/original.rbxmx"
ORIGINAL_HASH = "84c534d23645e84d1f585dde206680396204dd8070186c2b4824dbe5b97834e7"
ORIGINAL_BYTES = 32411
BASELINE = ROOT / "place/Children_of_corn.before-haze-clusters-20261015.rbxl"
BASELINE_HASH = "a897bb52fa85505090f973e910139915e6ebb2995e44915c31ecbc2b5c511dca"
SNAPSHOT = ROOT / ".artifacts/playtests/2026-10-15-haze-clusters/original-import.json"
HISTORY = ROOT / "scripts/haze-source-history.json"
APPROVED_PRIOR_BUNDLE = "da04c177f8267a863683312e3f67ee2f6cddc558b3c572e3d39ab90655af1f86"
FOG = "Workspace/CornfieldFog"
SOURCES = {
    FOG + "/Config": "assets/CornfieldFog/Config.luau",
    FOG + "/RuntimeServer": "assets/CornfieldFog/RuntimeServer.server.luau",
    FOG + "/RuntimeServer/ClientTemplate": "assets/CornfieldFog/ClientTemplate.client.luau",
}
CLASSES = {FOG: "Model", FOG + "/Config": "ModuleScript", FOG + "/RuntimeServer": "Script",
           FOG + "/RuntimeServer/ClientTemplate": "LocalScript", FOG + "/READ_ME": "StringValue"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def normalized(source):
    return source.replace("\r\n", "\n")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def original_nodes():
    require(ORIGINAL.stat().st_size == ORIGINAL_BYTES and digest(ORIGINAL) == ORIGINAL_HASH, "Immutable original fog XML changed")
    records = {}
    def walk(item, prefix):
        props = item.find("Properties")
        require(props is not None, "Fog XML properties missing")
        name = props.find("string[@name='Name']")
        require(name is not None and name.text, "Fog XML name missing")
        path = prefix + "/" + name.text
        require(path not in records, "Duplicate original fog path")
        records[path] = {"class": item.attrib["class"], "properties": {prop.attrib["name"]: [prop.tag, prop.text or "", []] for prop in props}}
        require(all(not list(prop) for prop in props), "Unexpected nested fog XML property")
        for child in item.findall("Item"):
            walk(child, path)
    root = ET.parse(ORIGINAL).getroot()
    require(len(root.findall("Item")) == 1, "Expected one original fog model")
    walk(root.find("Item"), "Workspace")
    require({path: item["class"] for path, item in records.items()} == CLASSES, "Original five-node fog topology changed")
    require({path for path, item in records.items() if "Source" in item["properties"]} == set(SOURCES), "Original three fog Sources changed")
    require(records[FOG + "/RuntimeServer"]["properties"]["Disabled"] == ["bool", "false", []]
            and records[FOG + "/RuntimeServer/ClientTemplate"]["properties"]["Disabled"] == ["bool", "true", []], "Original fog flags changed")
    return records


def verify_snapshot(records):
    snapshot = json.loads(SNAPSHOT.read_text(encoding="utf-8-sig"))
    require(snapshot["name"] == "CornfieldFog" and snapshot["class"] == "Model"
            and not snapshot["attrs"] and not snapshot["tags"], "Original fog import root differs from XML")
    nodes = snapshot["nodes"]
    require(len(nodes) == 4 and {node["path"].replace(".", "/") for node in nodes} == set(CLASSES) - {FOG}, "Original fog snapshot topology differs from XML")
    for node in nodes:
        path = node["path"].replace(".", "/")
        expected = records[path]
        require(node["class"] == expected["class"] and not node["attrs"] and not node["tags"], "Original fog snapshot class/ownership differs from XML: " + path)
        if path in SOURCES:
            require(normalized(node["source"]) == normalized(expected["properties"]["Source"][1]), "Original live Source differs from immutable XML: " + path)
        if "Disabled" in expected["properties"]:
            require(node["enabled"] == (expected["properties"]["Disabled"][1] == "false"), "Original fog snapshot enabled flag changed")
        if path.endswith("/READ_ME"):
            require(node["value"] == expected["properties"]["Value"][1], "Original fog snapshot READ_ME changed")


def current_sources():
    result = {path: normalized((ROOT / file).read_text(encoding="utf-8")) for path, file in SOURCES.items()}
    require(all(source and len(source.encode("utf-8")) < 200000 for source in result.values()), "Missing/oversized fog Source")
    return result


def prior_sources():
    history = json.loads(HISTORY.read_text(encoding="utf-8"))
    require(history["version"] == 1 and history["original_xml_sha256"] == ORIGINAL_HASH
            and len(history["bundles"]) == 1, "Unrecognized fog Source history")
    bundle = history["bundles"][0]
    require(bundle["id"] == APPROVED_PRIOR_BUNDLE and set(bundle["hashes"]) == set(bundle["sources"]) == set(SOURCES), "Unrecognized prior fog Source bundle")
    fingerprint = hashlib.sha256(json.dumps(bundle["hashes"], sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    require(fingerprint == APPROVED_PRIOR_BUNDLE, "Prior fog bundle fingerprint changed")
    sources = {path: normalized(source) for path, source in bundle["sources"].items()}
    require(all(hashlib.sha256(source.encode("utf-8")).hexdigest() == bundle["hashes"][path] for path, source in sources.items()), "Prior fog Source fingerprint changed")
    return sources


def literal(value):
    return json.dumps(value, ensure_ascii=False)


def installer(records, current, prior):
    rows = "{\n" + ",\n".join("{path=" + literal(path) + ",class=" + literal(CLASSES[path]) +
        ",original=" + literal(normalized(records[path]["properties"]["Source"][1])) + ",source=" + literal(current[path]) +
        (",prior=" + literal(prior[path]) if prior[path] != current[path] else "") + "}" for path in SOURCES) + "\n}"
    readme = records[FOG + "/READ_ME"]["properties"]["Value"][1]
    return '''-- Generated exact imported CornfieldFog three-Source update. Stopped Edit only.
-- Original XML SHA256: ''' + ORIGINAL_HASH + '''
local run=game:GetService("RunService")
assert(run:IsStudio() and not run:IsRunning(),"Stop Children_of_corn Play before fog installation")
local world=game:GetService("Workspace")
assert(not world:FindFirstChild("Asmr_Base") and not world:FindFirstChild("ASMR_Models"),"Wrong scene; nothing changed")
local map=world:FindFirstChild("CornMap")
assert(map and map:IsA("Model") and map:GetAttribute("corn_project_id")=="children_of_corn","Wrong project; nothing changed")
local function unique(parent,name,class)
    local found=nil
    for _,child in parent:GetChildren() do
        if child.Name==name then assert(not found,"Duplicate fog node; nothing changed") found=child end
    end
    assert(found and found.ClassName==class,"Missing/reclassified fog node; nothing changed: "..name)
    assert(next(found:GetAttributes())==nil and #found:GetTags()==0,"Unknown fog attributes/tags; nothing changed")
    return found
end
local fog=unique(world,"CornfieldFog","Model")
local config=unique(fog,"Config","ModuleScript")
local server=unique(fog,"RuntimeServer","Script")
local client=unique(server,"ClientTemplate","LocalScript")
local readme=unique(fog,"READ_ME","StringValue")
assert(#fog:GetChildren()==3 and #server:GetChildren()==1 and #config:GetChildren()==0 and #client:GetChildren()==0 and #readme:GetChildren()==0,"Unknown fog topology; nothing changed")
assert(not server.Disabled and client.Disabled,"Imported fog enabled flags changed; nothing changed")
assert(server.RunContext==Enum.RunContext.Legacy and client.RunContext==Enum.RunContext.Legacy,"Imported fog RunContext changed; nothing changed")
assert(fog.PrimaryPart==nil and fog.ModelStreamingMode==Enum.ModelStreamingMode.Default and fog.LevelOfDetail==Enum.ModelLevelOfDetail.Automatic,"Imported fog model properties changed; nothing changed")
assert(readme.Value==''' + literal(readme) + ''',"Imported fog READ_ME changed; nothing changed")
local bindings={
    ["Workspace/CornfieldFog/Config"]=config,
    ["Workspace/CornfieldFog/RuntimeServer"]=server,
    ["Workspace/CornfieldFog/RuntimeServer/ClientTemplate"]=client,
}
local entries=''' + rows + '''
local function normalized(source) return (string.gsub(source,"\\r\\n","\\n")) end
local editor=game:GetService("ScriptEditorService")
local before,after,previous=true,true,true
for _,entry in entries do
    local item=bindings[entry.path]
    assert(item and item.ClassName==entry.class,"Fog Source disappeared; nothing changed")
    assert(editor:FindScriptDocument(item)==nil,"Close fog script tab; nothing changed: "..entry.path)
    local source=normalized(item.Source)
    before=before and source==entry.original
    after=after and source==entry.source
    previous=previous and source==(entry.prior or entry.source)
end
assert(before or after or previous,"Unknown/manual/partial fog Sources; nothing changed")
if after then return {changed=0,sources=3,instances=5,repeated=true} end
local history=game:GetService("ChangeHistoryService")
history:SetWaypoint("Before CornfieldFog haze update")
local changed={}
local ok,problem=pcall(function()
    for _,entry in entries do
        local item=bindings[entry.path]
        if normalized(item.Source)~=entry.source then
            table.insert(changed,{item=item,source=item.Source})
            item.Source=entry.source
            -- HAZE_AFTER_SOURCE_WRITE
        end
    end
end)
if not ok then
    for index=#changed,1,-1 do changed[index].item.Source=changed[index].source end
    error("Fog update rolled back: "..tostring(problem))
end
history:SetWaypoint("Installed CornfieldFog haze update")
return {changed=#changed,sources=3,instances=5,repeated=false}
'''


def build(check=False):
    require(BASELINE.stat().st_size == 1019419 and digest(BASELINE) == BASELINE_HASH, "Immutable before-haze-clusters baseline changed")
    records = original_nodes()
    verify_snapshot(records)
    current = current_sources()
    prior = prior_sources()
    output = ROOT / "scripts/install-haze.luau"
    content = installer(records, current, prior)
    if check:
        require(output.exists() and output.read_text(encoding="utf-8") == content, "Stale haze installer")
    else:
        output.write_text(content, encoding="utf-8")
    require(digest(ORIGINAL) == ORIGINAL_HASH and digest(BASELINE) == BASELINE_HASH, "Immutable input changed during build")
    require(current_sources() == current, "Fog asset Sources changed during build")
    require(prior_sources() == prior, "Approved prior fog bundle changed during build")
    print(json.dumps({"passed": True, "checked": check, "sources": 3, "instances": 5,
        "original_xml_sha256": ORIGINAL_HASH, "snapshot_matches_xml": True,
        "scene_written": False, "installer": str(output)}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    build(args.check)
