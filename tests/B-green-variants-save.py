"""23Oct strict Save and intent-builder refusal tests; in-memory only."""
from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


v = module("green_variants_audit_test", "scripts/verify-B-green-variants-copy.py")
b = module("green_variants_builder_test", "scripts/build-B-green-variants-world-plan.py")
PIN = "a" * 64


def fixture(before):
    guards = {p: {"class": n["class"], "sha256": v.source_sha(n["properties"]["Source"][1])}
              for p, n in before.items() if "Source" in n["properties"]}
    payload = {"owner": v.OWNER, "sources": guards, "sourceChanges": {}, "newSources": {}}
    for path in v.ALLOWED_SOURCE_CHANGES:
        text = before[path]["properties"]["Source"][1].replace("\r\n", "\n") + "\n-- In-memory 23Oct migration fixture.\n"
        payload["sourceChanges"][path] = {"before_sha256": guards[path]["sha256"], "after_sha256": v.source_sha(text), "source": text}
    for path in v.ALLOWED_NEW_SOURCES:
        text = "return {} -- in-memory " + path + "\n"
        payload["newSources"][path] = {"class": "ModuleScript", "sha256": v.source_sha(text), "source": text}
    proposal = {"version": 1, "owner": v.OWNER, "baseline_sha256": v.BASELINE_SHA256, "payload_sha256": PIN, "old": [], "new_nodes": {}}
    numbers = lambda value: [b.m.f32(float(pair[1][1])) for pair in value[2]]
    for path, node in before.items():
        if node["class"] != "MeshPart" or not any(v.under(path, root) for root in v.EDITOR_ROOTS):
            continue
        props = node["properties"]
        frame, size = numbers(props["CFrame"]), numbers(props["size"])
        new_frame, new_size = frame.copy(), size.copy()
        new_frame[0] += .125; new_size[1] = 7.5 + len(proposal["old"]) % 9 * .125
        proposal["old"].append({"path": path.rpartition("/")[0] + "/" + props["Name"][1],
                                "oldFrame": frame, "beforeSize": size, "oldTexture": b.GREEN,
                                "cframe": new_frame, "size": new_size, "color": [1, 1, 1],
                                "texture": b.GREEN, "transparency": float(props["Transparency"][1])})
    for path in v.ALLOWED_NEW_NODES:
        cls = "Folder" if path == v.DATA_ROOT else "ModuleScript"
        proposal["new_nodes"][path] = {"class": cls, "prototype": cls, "properties": [],
                                       "attributes": {"BGreenVariantsOwner": v.OWNER, "corn_project_id": "children_of_corn"}, "tags": []}
    world = b.build(before, payload, proposal, PIN)
    after = before.copy()
    copied = set()
    def node(path):
        if path not in copied:
            after[path] = copy.deepcopy(after[path]); copied.add(path)
        return after[path]
    for path, row in payload["sourceChanges"].items():
        node(path)["properties"]["Source"] = v.scalar("string", row["source"])
    for row in world["retained_changes"]:
        node(row["path"])["properties"][row["property"]] = copy.deepcopy(row["after"])
    for index, (path, row) in enumerate(world["new_nodes"].items(), 1):
        after[path] = copy.deepcopy(row)
        props = after[path]["properties"]
        props["UniqueId"] = v.scalar("UniqueId", "f" * 28 + f"{index:04x}")
        props["HistoryId"] = v.scalar("UniqueId", "0" * 32)
        if row["class"] == "ModuleScript":
            props["ScriptGuid"] = v.scalar("string", "{F0000000-1234-5678-ABCD-" + f"{index:012X}" + "}")
    return payload, proposal, world, after


def main():
    before, warning, unknown = v.read_baseline()
    payload, proposal, world, after = fixture(before)
    positive = v.validate_dom(before, after, payload, world, PIN)
    assert positive["complete"] and positive["total_sources"] == 167 and positive["new_instances"] == 5
    assert positive["unchanged_sources"] == 160 and len(world["new_nodes"]) == 5
    corn = next(row["path"] for row in world["retained_changes"])
    bed = next(p for p, n in before.items() if n["class"] == "MeshPart" and v.under(p, "Workspace/CornMap/GreenBedEditor"))
    source = next(iter(v.ALLOWED_SOURCE_CHANGES))
    retained_source = next(p for p in payload["sources"] if p not in v.ALLOWED_SOURCE_CHANGES)
    added = next(iter(v.ALLOWED_NEW_SOURCES))
    another_added = next(p for p in v.ALLOWED_NEW_SOURCES if p != added)
    refused = []
    def reject(name, mutation):
        tree, plan, body = after.copy(), copy.deepcopy(world), copy.deepcopy(payload)
        copied = set()
        def node(path):
            if path not in copied:
                tree[path] = copy.deepcopy(tree[path]); copied.add(path)
            return tree[path]
        mutation(tree, node, plan, body)
        try:
            v.validate_dom(before, tree, body, plan, PIN)
        except (ValueError, TypeError, KeyError, IndexError):
            refused.append(name)
        else:
            raise AssertionError("Unsafe Save accepted: " + name)
    reject("retained Source", lambda t,n,w,p: n(retained_source)["properties"].__setitem__("Source", v.scalar("string", "return 0")))
    reject("partial Source", lambda t,n,w,p: n(source)["properties"].__setitem__("Source", before[source]["properties"]["Source"]))
    reject("retained Source GUID", lambda t,n,w,p: n(source)["properties"].__setitem__("ScriptGuid", v.scalar("string", "{F0000000-1234-5678-ABCD-000000000099}")))
    reject("missing Source guard", lambda t,n,w,p: p["sources"].pop(source))
    reject("wrong changed Source graph", lambda t,n,w,p: p["sourceChanges"].pop(source))
    reject("wrong new Source graph", lambda t,n,w,p: p["newSources"].__setitem__(added + "Extra", p["newSources"][added]))
    reject("new Source body", lambda t,n,w,p: n(added)["properties"].__setitem__("Source", v.scalar("string", "return 0")))
    reject("new Source hidden properties", lambda t,n,w,p: n(added)["properties"].__setitem__("SourceAssetId", v.scalar("int64", "123")))
    reject("new Source old GUID", lambda t,n,w,p: n(added)["properties"].__setitem__("ScriptGuid", before[source]["properties"]["ScriptGuid"]))
    reject("new Source duplicate GUID", lambda t,n,w,p: n(added)["properties"].__setitem__("ScriptGuid", copy.deepcopy(t[another_added]["properties"]["ScriptGuid"])))
    reject("new Source zero GUID", lambda t,n,w,p: n(added)["properties"].__setitem__("ScriptGuid", v.scalar("string", "{00000000-0000-0000-0000-000000000000}")))
    reject("new Source HistoryId", lambda t,n,w,p: n(added)["properties"].__setitem__("HistoryId", v.scalar("UniqueId", "bad")))
    reject("old corn mesh content", lambda t,n,w,p: n(corn)["properties"].__setitem__("MeshContent", ["Content","",[["null",["null","",[]]]]]))
    reject("old corn InitialSize", lambda t,n,w,p: n(corn)["properties"]["InitialSize"][2][0][1].__setitem__(1,"999"))
    reject("old corn physics", lambda t,n,w,p: n(corn)["properties"].__setitem__("CanCollide",v.scalar("bool","true")))
    reject("old corn attrs", lambda t,n,w,p: n(corn)["properties"].__setitem__("AttributesSerialize",v.scalar("BinaryString","00000000")))
    reject("old corn partial pose", lambda t,n,w,p: n(corn)["properties"].__setitem__("CFrame",before[corn]["properties"]["CFrame"]))
    reject("old corn identity", lambda t,n,w,p: n(corn)["properties"].__setitem__("UniqueId",v.scalar("UniqueId","b"*32)))
    reject("old corn parent", lambda t,n,w,p: t.__setitem__("Workspace/CornMap/RelocatedCorn",t.pop(corn)))
    reject("bed position", lambda t,n,w,p: n(bed)["properties"]["CFrame"][2][0][1].__setitem__(1,"999"))
    reject("bed physics", lambda t,n,w,p: n(bed)["properties"].__setitem__("CanCollide",v.scalar("bool","true")))
    reject("bed texture", lambda t,n,w,p: n(bed)["properties"].__setitem__("TextureContent",["Content","",[["uri",["uri",b.GREEN,[]]]]]))
    reject("bed mesh metadata", lambda t,n,w,p: n(bed)["properties"].__setitem__("PhysicalConfigData",v.scalar("SharedString","01")))
    reject("bed removed", lambda t,n,w,p: t.pop(bed))
    reject("Lighting", lambda t,n,w,p: n("Lighting")["properties"].__setitem__("Brightness",v.scalar("float","99")))
    reject("new world addition", lambda t,n,w,p: w["new_nodes"].__setitem__("Workspace/CornMap/Extra",copy.deepcopy(w["new_nodes"][v.DATA_ROOT])))
    reject("world permission widened to bed", lambda t,n,w,p: w["retained_changes"][0].__setitem__("path",bed))
    reject("world permission widened to mesh", lambda t,n,w,p: w["retained_changes"][0].__setitem__("property","InitialSize"))
    reject("world owner", lambda t,n,w,p: w.__setitem__("owner","foreign"))
    reject("world baseline", lambda t,n,w,p: w.__setitem__("baseline_sha256","b"*64))
    reject("new code owner attr", lambda t,n,w,p: n(added)["properties"].__setitem__("AttributesSerialize",v.h.encode_attributes({"BGreenVariantsOwner":"foreign","corn_project_id":"children_of_corn"})))
    reject("new code tags", lambda t,n,w,p: n(added)["properties"].__setitem__("Tags",v.scalar("BinaryString","61")))
    reject("new code missing default", lambda t,n,w,p: n(added)["properties"].pop("LinkedSource"))
    reject("nonfinite Camera", lambda t,n,w,p: n("Workspace/Camera")["properties"]["CFrame"][2][0][1].__setitem__(1,"nan"))
    camera = after.copy(); camera["Workspace/Camera"] = copy.deepcopy(after["Workspace/Camera"])
    camera["Workspace/Camera"]["properties"]["CFrame"][2][0][1][1] = "1"
    assert v.validate_dom(before,camera,payload,world,PIN)["complete"]
    reindexed = after.copy()
    siblings = [p for p in after if p.startswith("Workspace/CornMap/EditorPreview/") and "#" in p][:2]
    reindexed[siblings[0]],reindexed[siblings[1]] = reindexed[siblings[1]],reindexed[siblings[0]]
    assert v.validate_dom(before,reindexed,payload,world,PIN)["complete"]
    builder_refused = []
    for name, mutation in (
            ("missing old corn",lambda p:p["old"].pop()),
            ("duplicate old corn",lambda p:p["old"].__setitem__(1,copy.deepcopy(p["old"][0]))),
            ("wrong old pose",lambda p:p["old"][0]["oldFrame"].__setitem__(0,9999)),
            ("private old override",lambda p:p["old"][0].__setitem__("InitialSize",[1,1,1])),
            ("yellow corn",lambda p:p["old"][0].__setitem__("texture","rbxassetid://103653296385119")),
            ("nonpositive corn",lambda p:p["old"][0]["size"].__setitem__(1,0)),
            ("new code property override",lambda p:p["new_nodes"][added].__setitem__("properties",{"SourceAssetId":123})),
            ("new node class",lambda p:p["new_nodes"][added].__setitem__("class","Script")),
            ("new node owner",lambda p:p["new_nodes"][added]["attributes"].__setitem__("BGreenVariantsOwner","foreign")),
    ):
        bad = copy.deepcopy(proposal);mutation(bad)
        try:b.build(before,payload,bad,PIN)
        except (ValueError,TypeError,KeyError):builder_refused.append(name)
        else:raise AssertionError("Unsafe native proposal accepted: "+name)
    terrain_refused = []
    v.r.validate_unknown(unknown,copy.deepcopy(unknown))
    for field in ("payload_sha256","instance_count","payload_bytes"):
        bad=copy.deepcopy(unknown);row=next(iter(bad["properties"].values()))
        row[field]="f"*64 if field=="payload_sha256" else row[field]+1
        try:v.r.validate_unknown(unknown,bad)
        except ValueError:terrain_refused.append(field)
        else:raise AssertionError("Changed raw Terrain accepted")
    print(json.dumps({"passed":True,"baseline_instances":len(before),"baseline_sources":163,"candidate_sources":167,
                      "world_additions":0,"new_code_nodes":5,"retained_beds":1406,"editor_corn":3480,
                      "DOM_refusals":len(refused),"builder_refusals":builder_refused,"terrain_refusals":terrain_refused,
                      "positive_camera":True,"positive_sibling_reindex":True,"scope":"In-memory only; no scene/candidate/payload writes","baseline_warning":warning}))


if __name__ == "__main__":main()
