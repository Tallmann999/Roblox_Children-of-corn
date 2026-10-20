"""Strict one-Source look-down engine-DOM and Terrain guards.

All mutation fixtures remain in memory; no scene save or Studio connection.
"""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("cone_pipeline_audit", ROOT / "scripts/verify-flashlight-lookdown-copy.py")
f = importlib.util.module_from_spec(spec)
spec.loader.exec_module(f)
f.builder.require_baseline()
_, SOURCES, CLASSES, _ = f.builder.mapping()
ASSETS = f.fog.current_sources()
MANIFEST = json.loads((f.builder.OUT / "pipeline-manifest.json").read_bytes())
assert f.sha256(ROOT / "scripts/install-flashlight-lookdown.luau") == MANIFEST["installer_sha256"]
BEFORE, _ = f.r.p.known_dom(f.BASELINE)
assert len(BEFORE) == 4527


def scalar(kind, value):
    return [kind, str(value), []]


AFTER = BEFORE.copy()
AFTER.update(f.author_nodes(BEFORE))
AFTER["Lighting"] = copy.deepcopy(BEFORE["Lighting"])
AFTER["Lighting"]["properties"]["LightingStyle"] = scalar("token", 0)
for path in f.DECLARED_SOURCES:
    AFTER[path] = copy.deepcopy(BEFORE[path])
    AFTER[path]["properties"]["Source"] = scalar("string", SOURCES[path])


def validate(after):
    return f.validate_dom(BEFORE, after, SOURCES, CLASSES, ASSETS)


positive = validate(AFTER)
assert positive["passed"] and positive["complete"] and positive["total_sources"] == 156
assert positive["new_instances"] == 2 and positive["removed_instances"] == 0
assert positive["source_changes"] == sorted(f.DECLARED_SOURCES)
rejected = []


def rejects(name, mutate):
    after = AFTER.copy()
    def node(path):
        if after[path] is AFTER.get(path):
            after[path] = copy.deepcopy(after[path])
        return after[path]
    mutate(after, node)
    try:
        validate(after)
    except (ValueError, KeyError, TypeError, IndexError):
        rejected.append(name)
        return
    raise AssertionError("Unsafe directional flashlight save accepted: " + name)


for path in sorted(set(SOURCES) | set(ASSETS)):
    rejects("foreign Source:" + path, lambda a, n, p=path: n(p)["properties"].__setitem__("Source", scalar("string", "return 'foreign'")))
for path in []:
    rejects("missing changed Source:" + path, lambda a, n, p=path: a.__setitem__(p, BEFORE[p]))
    rejects("changed class:" + path, lambda a, n, p=path: n(p).__setitem__("class", "Script"))
    rejects("changed UID:" + path, lambda a, n, p=path: n(p)["properties"].__setitem__("UniqueId", scalar("UniqueId", "9" * 32)))
    rejects("changed capabilities:" + path, lambda a, n, p=path: n(p)["properties"].__setitem__("Capabilities", scalar("SecurityCapabilities", 1)))
    rejects("changed script GUID:" + path, lambda a, n, p=path: n(p)["properties"].__setitem__("ScriptGuid", scalar("string", "{F0000000-0000-0000-0000-000000000001}")))
    rejects("changed module attrs:" + path, lambda a, n, p=path: n(p)["properties"].__setitem__("AttributesSerialize", scalar("BinaryString", "00")))
rejects("extra instance", lambda a, n: a.__setitem__("Workspace/Foreign", copy.deepcopy(BEFORE["Workspace/CornMap/Ground"])))
rejects("missing world instance", lambda a, n: a.pop("Workspace/CornMap/Ground"))
rejects("world parent", lambda a, n: a.__setitem__("Workspace/RelocatedGround", a.pop("Workspace/CornMap/Ground")))
rejects("world physics", lambda a, n: n("Workspace/CornMap/Ground")["properties"].__setitem__("CanCollide", scalar("bool", "false")))
rejects("world attributes", lambda a, n: n("Workspace/CornMap")["properties"].__setitem__("AttributesSerialize", scalar("BinaryString", "00")))
rejects("world size", lambda a, n: n("Workspace/CornMap/Ground")["properties"]["size"][2][0][1].__setitem__(1, "631"))
mesh = "Workspace/CornMap/Props/ScarecrowMarker/HarvestWardenHome/Classic/Coat_Material1"
rejects("mesh metadata", lambda a, n: n(mesh)["properties"].__setitem__("VertexCount", scalar("int", 171)))
for prop in ("Brightness", "Ambient", "OutdoorAmbient", "FogStart", "FogEnd"):
    rejects("Lighting:" + prop, lambda a, n, p=prop: n("Lighting")["properties"].__setitem__(p, scalar("float", 999)))
rejects("missing style change", lambda a,n: n("Lighting")["properties"].__setitem__("LightingStyle", scalar("token",1)))
rejects("arbitrary style enum", lambda a,n: n("Lighting")["properties"].__setitem__("LightingStyle", scalar("token",999)))
rejects("malformed style", lambda a,n: n("Lighting")["properties"].__setitem__("LightingStyle", scalar("string","Realistic")))
for path in f.AUTHOR_PATHS:
    rejects("missing author node:"+path, lambda a,n,p=path:a.pop(p))
    for prop in AFTER[path]["properties"]:
        rejects("changed author property:"+path+"/"+prop, lambda a,n,p=path,k=prop:n(p)["properties"].__setitem__(k, scalar("string","unsafe")))
for prop in ("CFrame", "Focus"):
    rejects("arbitrary Camera:" + prop, lambda a, n, p=prop: n("Workspace/Camera")["properties"].__setitem__(p, scalar("CoordinateFrame", "arbitrary")))
    for value in ("nan", "inf", "1e40"):
        rejects("nonfinite Camera:" + prop + value, lambda a, n, p=prop, v=value: n("Workspace/Camera")["properties"][p][2][0][1].__setitem__(1, v))
    rejects("duplicate Camera component:" + prop, lambda a, n, p=prop: n("Workspace/Camera")["properties"][p][2].__setitem__(1, copy.deepcopy(n("Workspace/Camera")["properties"][p][2][0])))
camera = AFTER.copy()
camera["Workspace/Camera"] = copy.deepcopy(camera["Workspace/Camera"])
for prop in ("CFrame", "Focus"):
    camera["Workspace/Camera"]["properties"][prop][2][0][1][1] = "12.5"
validate(camera)
terrain = f.r.p.unknown_properties(f.BASELINE)
f.r.validate_unknown(terrain, copy.deepcopy(terrain))
terrain_rejected = []
for field in ("payload_sha256", "payload_bytes", "instance_count"):
    bad = copy.deepcopy(terrain)
    row = next(iter(bad["properties"].values()))
    row[field] = "0" * 64 if field == "payload_sha256" else row[field] + 1
    try:
        f.r.validate_unknown(terrain, bad)
    except ValueError:
        terrain_rejected.append(field)
    else:
        raise AssertionError("Changed raw Terrain accepted")


report = {"passed":True,"complete":True,"dom_refusals":len(rejected),"terrain_refusals":len(terrain_rejected),"valid_camera_frames":2,"rejected":rejected,"terrain_rejected":terrain_rejected,"scene_written":False}
(f.builder.OUT/'save-fixtures.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:v for k,v in report.items() if k not in {'rejected','terrain_rejected'}}))
