"""Full accepted B DOM refusal fixtures; modifies only in-memory decoded data."""
from __future__ import annotations

import argparse
import copy
import importlib.util
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("B_double_density_save_audit", ROOT / "scripts/verify-B-double-density-copy.py")
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)


def fixture_payload(before):
    sources = {path: {"class": node["class"], "sha256": v.source_sha(node["properties"]["Source"][1])}
               for path, node in before.items() if "Source" in node["properties"]}
    changes = {}
    for path in sorted(v.ALLOWED_SOURCE_PATHS):
        old = before[path]["properties"]["Source"][1].replace("\r\n", "\n")
        text = old + "\n-- Synthetic in-memory double-density audit fixture.\n"
        changes[path] = {"before_sha256": v.source_sha(old), "after_sha256": v.source_sha(text), "source": text}
    return {"owner": v.OWNER, "sources": sources, "sourceChanges": changes, "nodes": [], "changes": []}


def fixture_after(before, payload):
    _, _, sources = v.prepare_plan(before, payload)
    after = before.copy()
    for path, source in sources.items():
        after[path] = copy.deepcopy(after[path])
        after[path]["properties"]["Source"] = copy.deepcopy(source)
    return after


def reader_fixtures(reviewed):
    original = v.MANIFEST, v.MANIFEST_SHA256, v.PAYLOAD_SHA256
    target = v.OUT / "save-fixture-manifest.tmp.json"
    assert not target.exists() and target.resolve().parent == v.OUT.resolve()
    refused = []
    try:
        v.MANIFEST = target
        v.PAYLOAD_SHA256 = reviewed["payload_sha256"]
        def check(name, edit=None, raw=None, pin=None):
            doc = copy.deepcopy(reviewed)
            if edit:
                edit(doc)
            target.write_bytes(raw if raw is not None else (json.dumps(doc) + "\n").encode())
            v.MANIFEST_SHA256 = pin if pin is not None else v.sha(target)
            try:
                v.read_manifest()
            except (ValueError, TypeError, KeyError):
                refused.append(name)
                return
            raise AssertionError("Unsafe manifest reader accepted: " + name)
        target.write_text(json.dumps(reviewed) + "\n")
        v.MANIFEST_SHA256 = v.sha(target)
        assert v.read_manifest() == reviewed
        check("missing pin", pin=False)
        check("wrong pin", pin="f" * 64)
        check("wrong owner", lambda d: d.__setitem__("owner", "foreign"))
        check("bool version", lambda d: d.__setitem__("version", True))
        check("wrong version", lambda d: d.__setitem__("version", 2))
        check("extra field", lambda d: d.__setitem__("skip", True))
        check("wrong payload hash", lambda d: d.__setitem__("payload_sha256", "1" * 64))
        source = next(iter(reviewed["sourceChanges"]))
        check("missing reviewed Source", lambda d: d["sourceChanges"].pop(source))
        check("extra reviewed Source", lambda d: d["sourceChanges"].__setitem__("Foreign", copy.deepcopy(d["sourceChanges"][source])))
        check("extra Source field", lambda d: d["sourceChanges"][source].__setitem__("skip", True))
        check("bad before hash", lambda d: d["sourceChanges"][source].__setitem__("before_sha256", "bad"))
        check("bad after hash", lambda d: d["sourceChanges"][source].__setitem__("after_sha256", "bad"))
        check("no-op hash", lambda d: d["sourceChanges"][source].__setitem__("after_sha256", d["sourceChanges"][source]["before_sha256"]))
        check("duplicate key", raw=b'{"owner":"corn_double_density_v1","owner":"foreign"}')
    finally:
        if target.exists():
            target.unlink()
        v.MANIFEST, v.MANIFEST_SHA256, v.PAYLOAD_SHA256 = original
    return refused


def main(expected_payload_sha256=None):
    before, _, unknown = v.read_baseline()
    payload = fixture_payload(before)
    reviewed = {"version": 1, "owner": v.OWNER, "payload_sha256": "0" * 64,
                "sourceChanges": {path: {key: row[key] for key in ("before_sha256", "after_sha256")}
                                  for path, row in payload["sourceChanges"].items()}}
    reader_refused = reader_fixtures(reviewed)
    real_reader = v.read_manifest
    v.read_manifest = lambda: copy.deepcopy(reviewed)
    after = fixture_after(before, payload)
    positive = v.validate_dom(before, after, payload)
    assert positive["passed"] and positive["complete"] and positive["total_sources"] == 157
    assert positive["new_instances"] == 0 and positive["unchanged_sources"] == 152
    assert positive["declared_property_changes"] == positive["declared_attribute_changes"] == 0
    refused = []
    def reject(name, edit):
        tree = after.copy()
        def node(path):
            if tree[path] is after.get(path):
                tree[path] = copy.deepcopy(tree[path])
            return tree[path]
        edit(tree, node)
        try:
            v.validate_dom(before, tree, payload)
        except (ValueError, KeyError, TypeError, IndexError):
            refused.append(name)
            return
        raise AssertionError("Unsafe double-density save accepted: " + name)
    ground = "Workspace/CornMap/Ground"
    source = next(iter(payload["sourceChanges"]))
    other = next(path for path in payload["sources"] if path not in payload["sourceChanges"])
    eye = "Workspace/CornMap/Props/ScarecrowMarker/HarvestWardenHome/Detailed/LeftEye.001_Material1"
    reject("retained Source", lambda t, n: n(other)["properties"].__setitem__("Source", v.scalar("string", "return 0")))
    reject("partial Source", lambda t, n: n(source)["properties"].__setitem__("Source", before[source]["properties"]["Source"]))
    reject("foreign Source", lambda t, n: n(source)["properties"].__setitem__("Source", v.scalar("string", "return 0")))
    reject("ScriptGuid", lambda t, n: n(source)["properties"].__setitem__("ScriptGuid", v.scalar("string", "{F1234567-89AB-CDEF-0123-456789ABCDEF}")))
    reject("Source deleted", lambda t, n: t.pop(source))
    reject("Source UID", lambda t, n: n(source)["properties"].__setitem__("UniqueId", v.scalar("UniqueId", "b" * 32)))
    reject("extra object", lambda t, n: t.__setitem__(ground + "/Extra", copy.deepcopy(after[ground])))
    reject("deleted world", lambda t, n: t.pop(ground))
    reject("world replacement", lambda t, n: n(ground)["properties"].__setitem__("UniqueId", v.scalar("UniqueId", "d" * 32)))
    reject("zero UID", lambda t, n: n(ground)["properties"].__setitem__("UniqueId", v.scalar("UniqueId", "0" * 32)))
    reject("duplicate UID", lambda t, n: n(ground)["properties"].__setitem__("UniqueId", copy.deepcopy(after[eye]["properties"]["UniqueId"])))
    reject("Name", lambda t, n: n(ground)["properties"].__setitem__("Name", v.scalar("string", "Foreign")))
    reject("class", lambda t, n: n(ground).__setitem__("class", "MeshPart"))
    reject("parent", lambda t, n: t.__setitem__("Workspace/Ground", t.pop(ground)))
    reject("position", lambda t, n: n(ground)["properties"]["CFrame"][2][0][1].__setitem__(1, "1"))
    reject("geometry", lambda t, n: n(ground)["properties"]["size"][2][0][1].__setitem__(1, "631"))
    reject("collision", lambda t, n: n(ground)["properties"].__setitem__("CanCollide", v.scalar("bool", "false")))
    reject("eye visibility", lambda t, n: n(eye)["properties"].__setitem__("Transparency", v.scalar("float", 0)))
    reject("shadow", lambda t, n: n(eye)["properties"].__setitem__("CastShadow", v.scalar("bool", "false")))
    reject("unknown property", lambda t, n: n(eye)["properties"].__setitem__("Foreign", v.scalar("string", "foreign")))
    reject("missing property", lambda t, n: n(eye)["properties"].pop("Massless"))
    reject("tags", lambda t, n: n(eye)["properties"].__setitem__("Tags", v.scalar("BinaryString", "666f726569676e")))
    reject("attribute", lambda t, n: n(eye)["properties"].__setitem__("AttributesSerialize", v.encode_attributes({"Foreign": True})))
    reject("Lighting", lambda t, n: n("Lighting")["properties"].__setitem__("Brightness", v.scalar("float", 2)))
    reject("light flags", lambda t, n: n("ReplicatedStorage/CornFlashlightSettings/Wide")["properties"].__setitem__("Shadows", v.scalar("bool", "false")))
    reject("malformed Camera", lambda t, n: n("Workspace/Camera")["properties"].__setitem__("CFrame", v.scalar("CoordinateFrame", "foreign")))
    reject("infinite Camera", lambda t, n: n("Workspace/Camera")["properties"]["CFrame"][2][0][1].__setitem__(1, "inf"))
    reject("Camera type", lambda t, n: n("Workspace/Camera")["properties"].__setitem__("CameraType", v.scalar("token", 999)))

    payload_refused = []
    def reject_payload(name, edit):
        bad = copy.deepcopy(payload)
        edit(bad)
        try:
            v.prepare_plan(before, bad)
        except (ValueError, KeyError, TypeError, IndexError):
            payload_refused.append(name)
            return
        raise AssertionError("Unsafe double-density payload accepted: " + name)
    reject_payload("owner", lambda p: p.__setitem__("owner", "foreign"))
    reject_payload("addition", lambda p: p["nodes"].append({"path": ground + "/Extra"}))
    reject_payload("world delta", lambda p: p["changes"].append({"path": ground, "property": "CastShadow", "before": True, "after": False}))
    reject_payload("missing Source pin", lambda p: p["sources"].pop(other))
    reject_payload("wrong Source pin", lambda p: p["sources"][other].__setitem__("sha256", "0" * 64))
    reject_payload("extra Source pin", lambda p: p["sources"].__setitem__("Foreign", copy.deepcopy(p["sources"][other])))
    reject_payload("before Source hash", lambda p: p["sourceChanges"][source].__setitem__("before_sha256", "0" * 64))
    reject_payload("after Source hash", lambda p: p["sourceChanges"][source].__setitem__("after_sha256", "0" * 64))
    reject_payload("CR Source", lambda p: p["sourceChanges"][source].__setitem__("source", "return 0\r\n"))
    reject_payload("NUL Source", lambda p: p["sourceChanges"][source].__setitem__("source", "return 0\x00"))
    reject_payload("missing intended Source", lambda p: p["sourceChanges"].pop(source))
    reject_payload("sixth Source", lambda p: p["sourceChanges"].__setitem__(other, copy.deepcopy(p["sourceChanges"][source])))
    reject_payload("extra Source row field", lambda p: p["sourceChanges"][source].__setitem__("skip", True))

    camera = after.copy()
    camera["Workspace/Camera"] = copy.deepcopy(camera["Workspace/Camera"])
    for prop in ("CFrame", "Focus"):
        camera["Workspace/Camera"]["properties"][prop][2][0][1][1] = "12.5"
    v.validate_dom(before, camera, payload)
    selection = after.copy()
    for index, path in enumerate(sorted(v.r.SELECTION_PATHS), 1):
        selection[path] = copy.deepcopy(selection[path])
        selection[path]["properties"]["UniqueId"] = v.scalar("UniqueId", f"{(2 << 124) + index:032x}")
    v.validate_dom(before, selection, payload)
    barrels = sorted(path for path, node in before.items() if node["properties"]["Name"] == v.scalar("string", "LookoutBarrel"))
    swap = {barrels[0]: barrels[1], barrels[1]: barrels[0]}
    reindexed = {swap.get(path, path): node | {"properties": {key: v.remap_refs(value, swap) for key, value in node["properties"].items()}}
                 for path, node in after.items()}
    assert v.validate_dom(before, reindexed, payload)["reindexed_exporter_paths"] == 2
    terrain_refused = []
    v.r.validate_unknown(unknown, copy.deepcopy(unknown))
    for field in ("payload_sha256", "payload_bytes", "instance_count"):
        bad = copy.deepcopy(unknown)
        row = next(iter(bad["properties"].values()))
        row[field] = "0" * 64 if field == "payload_sha256" else row[field] + 1
        try:
            v.r.validate_unknown(unknown, bad)
        except ValueError:
            terrain_refused.append(field)
        else:
            raise AssertionError("Changed raw Terrain accepted")

    frozen, frozen_refused = None, []
    v.read_manifest = real_reader
    if v.MANIFEST_SHA256 is not None:
        full_payload = v.read_payload(expected_payload_sha256)
        complete = fixture_after(before, full_payload)
        frozen = {key: value for key, value in v.validate_dom(before, complete, full_payload).items() if key != "changes"}
        for path in full_payload["sourceChanges"]:
            partial = complete.copy()
            partial[path] = copy.deepcopy(complete[path])
            partial[path]["properties"]["Source"] = copy.deepcopy(before[path]["properties"]["Source"])
            try:
                v.validate_dom(before, partial, full_payload)
            except ValueError:
                frozen_refused.append(path)
            else:
                raise AssertionError("Partial frozen Source accepted: " + path)
    v.baseline_info()
    print(json.dumps({"passed": True, "refused_dom": len(refused), "refused_payload": len(payload_refused),
                      "refused_manifest_reader": len(reader_refused), "refused_terrain": len(terrain_refused),
                      "frozen_refused_dom": len(frozen_refused), "frozen_payload": frozen,
                      "positives": ["full retained DOM plus exact five Sources", "finite Camera", "FilteredSelection", "UID-proven sibling reindex"],
                      "scene_written": False}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--payload-sha256")
    args = parser.parse_args()
    main(args.payload_sha256)
