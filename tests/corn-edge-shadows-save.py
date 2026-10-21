"""Strict corn-edge/shadow save fixtures: full accepted DOM, no RBXL writes."""
from __future__ import annotations

import argparse
import copy
import importlib.util
import json
from pathlib import Path
import struct
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("corn_edge_shadows_save_audit", ROOT / "scripts/verify-corn-edge-shadows-copy.py")
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)


def source_manifest(before):
    return {path: {"class": node["class"], "sha256": v.source_sha(node["properties"]["Source"][1])}
            for path, node in before.items() if "Source" in node["properties"]}


def fixture_payload(before):
    changes = {}
    for path in sorted(v.ALLOWED_SOURCE_PATHS):
        old = before[path]["properties"]["Source"][1].replace("\r\n", "\n")
        new = old + "\n-- Exact synthetic corn-edge save-fixture Source replacement.\n"
        changes[path] = {"before_sha256": v.source_sha(old), "after_sha256": v.source_sha(new), "source": new}
    return {"owner": v.OWNER, "sources": source_manifest(before), "nodes": [],
            "sourceChanges": changes, "changes": copy.deepcopy(v.WORLD_CHANGES)}


def fixture_after(before, payload):
    changes, attributes, sources = v.prepare_plan(before, payload)
    after = before.copy()

    def node(path):
        if after[path] is before.get(path):
            after[path] = copy.deepcopy(after[path])
        return after[path]

    for (path, prop), value in changes.items():
        node(path)["properties"][prop] = copy.deepcopy(value)
    for path in {path for path, _ in attributes}:
        raw = {name: bytes.fromhex(entry["raw"]) for name, entry in v.decode_attributes(before[path]["properties"]["AttributesSerialize"]).items()}
        for (target, name), row in attributes.items():
            if target != path:
                continue
            wanted = row["after"]
            if wanted == {"kind": "Nil"}:
                raw.pop(name, None)
            else:
                raw[name] = bytes.fromhex(v.encode_attributes({name: wanted})[1])[4:]
        data = struct.pack("<I", len(raw)) + b"".join(raw[name] for name in sorted(raw))
        node(path)["properties"]["AttributesSerialize"] = v.scalar("BinaryString", data.hex())
    for path, value in sources.items():
        node(path)["properties"]["Source"] = copy.deepcopy(value)
    return after


def manifest_reader_fixture(reviewed):
    original_path, original_pin = v.MANIFEST, v.MANIFEST_SHA256
    target = v.OUT / "eyes-fixture-manifest.tmp.json"
    assert target.resolve().parent == v.OUT.resolve() and not target.exists()
    refused = []
    try:
        v.MANIFEST = target
        def check(name, edit=None, raw=None, pin=None):
            doc = copy.deepcopy(reviewed)
            if edit:
                edit(doc)
            data = raw if raw is not None else (json.dumps(doc, sort_keys=True) + "\n").encode()
            target.write_bytes(data)
            v.MANIFEST_SHA256 = v.sha(target) if pin is None else pin
            try:
                v.read_manifest()
            except (ValueError, TypeError, KeyError):
                refused.append(name)
                return
            raise AssertionError("Unsafe manifest reader accepted: " + name)
        target.write_text(json.dumps(reviewed) + "\n")
        v.MANIFEST_SHA256 = v.sha(target)
        assert v.read_manifest() == reviewed
        check("unreviewed missing pin", pin=False)
        check("changed manifest hash", pin="f" * 64)
        check("wrong owner", lambda d: d.__setitem__("owner", "foreign"))
        check("wrong version", lambda d: d.__setitem__("version", 2))
        check("bool version", lambda d: d.__setitem__("version", True))
        check("extra schema field", lambda d: d.__setitem__("ignore", True))
        check("malformed payload hash", lambda d: d.__setitem__("payload_sha256", "x" * 64))
        source = next(iter(reviewed["sourceChanges"]))
        check("missing source review", lambda d: d["sourceChanges"].pop(source))
        check("extra source review", lambda d: d["sourceChanges"].__setitem__("Foreign/Source", copy.deepcopy(d["sourceChanges"][source])))
        check("extra source field", lambda d: d["sourceChanges"][source].__setitem__("skip", True))
        check("malformed source before hash", lambda d: d["sourceChanges"][source].__setitem__("before_sha256", "bad"))
        check("malformed source after hash", lambda d: d["sourceChanges"][source].__setitem__("after_sha256", "bad"))
        check("no-op source pair", lambda d: d["sourceChanges"][source].__setitem__("after_sha256", d["sourceChanges"][source]["before_sha256"]))
        check("duplicate owner key", raw=b'{"owner":"corn_edge_shadows_v1","owner":"foreign"}')
    finally:
        if target.exists():
            target.unlink()
        v.MANIFEST, v.MANIFEST_SHA256 = original_path, original_pin
    return refused


def main(expected_payload_sha256=None):
    before, _, unknown = v.read_baseline()
    payload = fixture_payload(before)
    original_read_manifest = v.read_manifest
    reviewed = {"version": 1, "owner": v.OWNER, "payload_sha256": "0" * 64,
                "sourceChanges": {p: {k: row[k] for k in ("before_sha256", "after_sha256")} for p, row in payload["sourceChanges"].items()}}
    manifest_reader_refused = manifest_reader_fixture(reviewed)
    v.read_manifest = lambda: copy.deepcopy(reviewed)
    after = fixture_after(before, payload)
    positive = v.validate_dom(before, after, payload)
    assert positive["passed"] and positive["complete"] and positive["total_sources"] == 157
    assert positive["new_instances"] == 0 and positive["unchanged_sources"] == 152
    assert positive["declared_property_changes"] == 2 and positive["declared_attribute_changes"] == 2
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
        raise AssertionError("Unsafe corn-edge/shadow save accepted: " + name)

    ground = "Workspace/CornMap/Ground"
    trail = v.EYE_PREFIX + "LeftEye.001_Material1"
    source = next(iter(payload["sourceChanges"]))
    other_source = next(path for path in payload["sources"] if path not in payload["sourceChanges"])
    reject("retained Source edit", lambda t, n: n(other_source)["properties"].__setitem__("Source", v.scalar("string", "return 0")))
    reject("declared Source partial", lambda t, n: n(source)["properties"].__setitem__("Source", before[source]["properties"]["Source"]))
    reject("declared Source foreign", lambda t, n: n(source)["properties"].__setitem__("Source", v.scalar("string", "return 0")))
    reject("Source ScriptGuid", lambda t, n: n(source)["properties"].__setitem__("ScriptGuid", v.scalar("string", "{F1234567-89AB-CDEF-0123-456789ABCDEF}")))
    reject("Source deletion", lambda t, n: t.pop(source))
    reject("Source identity", lambda t, n: n(source)["properties"].__setitem__("UniqueId", v.scalar("UniqueId", "b" * 32)))
    reject("extra object", lambda t, n: t.__setitem__(ground + "/Extra", copy.deepcopy(after[ground])))
    reject("world deletion", lambda t, n: t.pop(ground))
    reject("retained replacement UID", lambda t, n: n(ground)["properties"].__setitem__("UniqueId", v.scalar("UniqueId", "d" * 32)))
    reject("zero UID", lambda t, n: n(ground)["properties"].__setitem__("UniqueId", v.scalar("UniqueId", "0" * 32)))
    reject("duplicate UID", lambda t, n: n(ground)["properties"].__setitem__("UniqueId", copy.deepcopy(after[trail]["properties"]["UniqueId"])))
    reject("real Name", lambda t, n: n(ground)["properties"].__setitem__("Name", v.scalar("string", "Foreign")))
    reject("class", lambda t, n: n(ground).__setitem__("class", "MeshPart"))
    reject("parent", lambda t, n: t.__setitem__("Workspace/Ground", t.pop(ground)))
    reject("world position", lambda t, n: n(ground)["properties"]["CFrame"][2][0][1].__setitem__(1, "1"))
    reject("world geometry", lambda t, n: n(ground)["properties"]["size"][2][0][1].__setitem__(1, "631"))
    reject("world collision", lambda t, n: n(ground)["properties"].__setitem__("CanCollide", v.scalar("bool", "false")))
    reject("declared eye surface partial", lambda t, n: n(trail)["properties"].__setitem__("Transparency", before[trail]["properties"]["Transparency"]))
    reject("undeclared shadow change", lambda t, n: n(trail)["properties"].__setitem__("CastShadow", v.scalar("bool", "false")))
    reject("unknown property", lambda t, n: n(trail)["properties"].__setitem__("Foreign", v.scalar("string", "foreign")))
    reject("missing property", lambda t, n: n(trail)["properties"].pop("Massless"))
    reject("tags", lambda t, n: n(trail)["properties"].__setitem__("Tags", v.scalar("BinaryString", "666f726569676e")))
    map_path = "Workspace/CornMap"
    reject("declared eye attribute partial", lambda t, n: n(trail)["properties"].__setitem__("AttributesSerialize", before[trail]["properties"]["AttributesSerialize"]))
    reject("extra attribute", lambda t, n: n(map_path)["properties"].__setitem__("AttributesSerialize", v.encode_attributes({"RefineFixture": "fixture", "Foreign": True})))
    reject("Lighting", lambda t, n: n("Lighting")["properties"].__setitem__("Brightness", v.scalar("float", 2)))
    reject("light flags undeclared", lambda t, n: n("ReplicatedStorage/CornFlashlightSettings/Wide")["properties"].__setitem__("Shadows", v.scalar("bool", "false")))
    reject("malformed Camera", lambda t, n: n("Workspace/Camera")["properties"].__setitem__("CFrame", v.scalar("CoordinateFrame", "foreign")))
    reject("Camera infinity", lambda t, n: n("Workspace/Camera")["properties"]["CFrame"][2][0][1].__setitem__(1, "inf"))
    reject("Camera type", lambda t, n: n("Workspace/Camera")["properties"].__setitem__("CameraType", v.scalar("token", 999)))

    manifest_refusals = []

    def reject_payload(name, edit):
        manifest = copy.deepcopy(payload)
        edit(manifest)
        try:
            v.prepare_plan(before, manifest)
        except (ValueError, KeyError, TypeError, IndexError):
            manifest_refusals.append(name)
            return
        raise AssertionError("Unsafe corn-edge/shadow manifest accepted: " + name)

    reject_payload("owner", lambda p: p.__setitem__("owner", "foreign"))
    reject_payload("additions", lambda p: p["nodes"].append({"path": ground + "/Extra"}))
    reject_payload("missing Source pin", lambda p: p["sources"].pop(other_source))
    reject_payload("wrong Source pin", lambda p: p["sources"][other_source].__setitem__("sha256", "0" * 64))
    reject_payload("before Source hash", lambda p: p["sourceChanges"][source].__setitem__("before_sha256", "0" * 64))
    reject_payload("after Source hash", lambda p: p["sourceChanges"][source].__setitem__("after_sha256", "0" * 64))
    reject_payload("CR Source", lambda p: p["sourceChanges"][source].__setitem__("source", "return 0\r\n"))
    reject_payload("duplicate property", lambda p: p["changes"].append(copy.deepcopy(p["changes"][0])))
    reject_payload("no-op property", lambda p: p["changes"][0].__setitem__("after", p["changes"][0]["before"]))
    reject_payload("before value mismatch", lambda p: p["changes"][0].__setitem__("before", 10))
    reject_payload("protected identity", lambda p: p["changes"][0].__setitem__("property", "UniqueId"))
    reject_payload("direct Source property", lambda p: p["changes"][0].update({"path": source, "property": "Source", "before": "return 0", "after": "return 1"}))
    reject_payload("foreign Lighting edit", lambda p: p["changes"][0].update({"path": "Lighting", "property": "Brightness", "before": 1, "after": 2}))
    reject_payload("unknown row field", lambda p: p["changes"][0].__setitem__("ignore", True))
    reject_payload("malformed selector", lambda p: p["changes"][0].__setitem__("selector", {"Name": "trail_001"}))

    reject_payload("unexpected sixth source", lambda p: p["sourceChanges"].__setitem__(other_source, copy.deepcopy(p["sourceChanges"][source])))
    reject_payload("missing intended source", lambda p: p["sourceChanges"].pop(source))
    reject_payload("foreign static eye", lambda p: p["changes"][0].__setitem__("path", p["changes"][0]["path"].replace("Detailed", "Classic")))
    reject_payload("extra world delta", lambda p: p["changes"].append({"path": ground, "property": "CastShadow", "attribute": False, "before": True, "after": False}))
    # Only documented editor state may differ; identities prove sibling reindex.
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

    full, frozen_refused = None, []
    v.read_manifest = original_read_manifest
    if v.MANIFEST_SHA256 is not None:
        frozen = v.read_payload(expected_payload_sha256)
        complete = fixture_after(before, frozen)
        full = {key: value for key, value in v.validate_dom(before, complete, frozen).items() if key != "changes"}
        full_changes, full_attrs, full_sources = v.prepare_plan(before, frozen)

        def reject_frozen(name, path, prop):
            partial = complete.copy()
            partial[path] = copy.deepcopy(complete[path])
            partial[path]["properties"][prop] = copy.deepcopy(before[path]["properties"][prop])
            try:
                v.validate_dom(before, partial, frozen)
            except ValueError:
                frozen_refused.append(name)
                return
            raise AssertionError("Partial frozen refinement save accepted: " + name)

        for path in full_sources:
            reject_frozen("partial Source " + path, path, "Source")
        for prop in ("Transparency",):
            target = next(path for path, name in full_changes if name == prop)
            reject_frozen("partial frozen " + prop, target, prop)
        for path in sorted({path for path, _ in full_attrs}):
            reject_frozen("partial frozen attributes " + path, path, "AttributesSerialize")
    v.baseline_info()
    print(json.dumps({"passed": True, "refused_dom": len(refused), "refused_manifest": len(manifest_refusals),
                      "refused_terrain": len(terrain_refused), "refused_manifest_reader": len(manifest_reader_refused), "frozen_refused_dom": len(frozen_refused), "manifest_sha_pinned": v.MANIFEST_SHA256 is not None, "frozen_payload": full,
                      "positives": ["full retained DOM plus exact property/attribute/Source manifest", "finite Camera", "FilteredSelection", "UID-proven barrel sibling reindex"],
                      "scene_written": False}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--payload-sha256")
    args = parser.parse_args()
    main(args.payload_sha256)
