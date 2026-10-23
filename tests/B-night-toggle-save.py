"""Meaningful refusal fixtures for the one-additive-Module B Save audit.

Uses the immutable real B DOM, never rewrites or serializes a scene. The new
Module is an in-memory fixture; a final engine Save still requires native QA
and the explicitly pinned fixed canonical Source audit.
"""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("night_save", ROOT / "scripts/verify-B-night-toggle-copy.py")
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)


def main():
    before, warning, unknown = v.read_baseline()
    source = "return { Name = 'NightModeController' }\n"
    new = copy.deepcopy(v.expected_module(before, source))
    new["properties"].update({"UniqueId": v.scalar("UniqueId", "123456789abcdef0123456789abcdef0"),
                              "HistoryId": v.scalar("UniqueId", "0" * 32),
                              "ScriptGuid": v.scalar("string", "{12345678-9abc-def0-1234-56789abcdef0}")})
    after = before | {v.ADDED: new}
    positive = v.validate_dom(before, after, source)
    assert positive["complete"] and positive["unchanged_sources"] == 167
    refused = []

    def reject(name, mutate):
        candidate = after.copy()
        touched = set()

        def node(path):
            if path not in touched:
                candidate[path] = copy.deepcopy(candidate[path])
                touched.add(path)
            return candidate[path]

        mutate(candidate, node)
        try:
            v.validate_dom(before, candidate, source)
        except (ValueError, KeyError, TypeError):
            refused.append(name)
        else:
            raise AssertionError("Unsafe Save accepted: " + name)

    old_source = v.MODULE_TEMPLATE
    corn = next(p for p, n in before.items() if p.startswith("Workspace/CornMap/EditorPreview/") and n["class"] == "MeshPart")
    bed = next(p for p, n in before.items() if p.startswith("Workspace/CornMap/GreenBedEditor/") and n["class"] == "MeshPart")
    fog = next(p for p, n in before.items() if "Source" in n["properties"] and "Fog" in p)
    reject("missing addition", lambda t,n: t.pop(v.ADDED))
    reject("retained Source", lambda t,n: n(old_source)["properties"].__setitem__("Source", v.scalar("string", "return {}")))
    reject("Fog Source", lambda t,n: n(fog)["properties"].__setitem__("Source", v.scalar("string", "return {}")))
    reject("persistent Lighting", lambda t,n: n("Lighting")["properties"].__setitem__("Brightness", v.scalar("float", "99")))
    reject("old corn pose", lambda t,n: n(corn)["properties"]["CFrame"][2][0][1].__setitem__(1, "999"))
    reject("bed physics", lambda t,n: n(bed)["properties"].__setitem__("CanCollide", v.scalar("bool", "true")))
    reject("bed mesh metadata", lambda t,n: n(bed)["properties"].__setitem__("InitialSize", v.scalar("Vector3", "bad")))
    reject("retained identity", lambda t,n: n(corn)["properties"].__setitem__("UniqueId", v.scalar("UniqueId", "d" * 32)))
    reject("retained parent", lambda t,n: t.__setitem__("Workspace/CornMap/Relocated", t.pop(corn)))
    reject("wrong controller Source", lambda t,n: n(v.ADDED)["properties"].__setitem__("Source", v.scalar("string", "return {}")))
    reject("new attrs", lambda t,n: n(v.ADDED)["properties"].__setitem__("AttributesSerialize", v.h.encode_attributes({"unexpected": True})))
    reject("new tags", lambda t,n: n(v.ADDED)["properties"].__setitem__("Tags", v.scalar("BinaryString", "61")))
    reject("new SourceAssetId", lambda t,n: n(v.ADDED)["properties"].__setitem__("SourceAssetId", v.scalar("int64", "123")))
    reject("new zero UID", lambda t,n: n(v.ADDED)["properties"].__setitem__("UniqueId", v.scalar("UniqueId", "0" * 32)))
    reject("new old ScriptGuid", lambda t,n: n(v.ADDED)["properties"].__setitem__("ScriptGuid", before[old_source]["properties"]["ScriptGuid"]))
    reject("new malformed HistoryId", lambda t,n: n(v.ADDED)["properties"].__setitem__("HistoryId", v.scalar("UniqueId", "bad")))
    reject("extra node", lambda t,n: t.__setitem__(v.ADDED + "/Child", copy.deepcopy(new)))
    reject("nonfinite Camera", lambda t,n: n("Workspace/Camera")["properties"]["CFrame"][2][0][1].__setitem__(1, "nan"))
    camera = after.copy()
    camera["Workspace/Camera"] = copy.deepcopy(after["Workspace/Camera"])
    camera["Workspace/Camera"]["properties"]["CFrame"][2][0][1][1] = "1"
    assert v.validate_dom(before, camera, source)["complete"]
    siblings = [p for p in after if p.startswith("Workspace/CornMap/EditorPreview/") and "#" in p][:2]
    assert len(siblings) == 2
    reindexed = after.copy()
    reindexed[siblings[0]], reindexed[siblings[1]] = reindexed[siblings[1]], reindexed[siblings[0]]
    assert v.validate_dom(before, reindexed, source)["complete"]
    terrain_refused = []
    v.r.validate_unknown(unknown, copy.deepcopy(unknown))
    for field in ("payload_sha256", "instance_count", "payload_bytes"):
        bad = copy.deepcopy(unknown)
        row = next(iter(bad["properties"].values()))
        row[field] = "f" * 64 if field == "payload_sha256" else row[field] + 1
        try:
            v.r.validate_unknown(unknown, bad)
        except ValueError:
            terrain_refused.append(field)
        else:
            raise AssertionError("Changed raw Terrain accepted")
    fixed_source_pin = None
    if v.SOURCE.is_file():
        fixed_source_pin = hashlib.sha256(v.SOURCE.read_bytes()).hexdigest()
        assert v.controller_source(fixed_source_pin)
        try:
            v.controller_source("0" * 64)
        except ValueError:
            refused.append("unreviewed fixed-file Source pin")
        else:
            raise AssertionError("Unpinned fixed-file Source accepted")
    print(json.dumps({"passed": True, "baseline_instances": len(before), "candidate_instances": len(after),
                      "unchanged_sources": 167, "total_sources": 168, "new_code_nodes": 1,
                      "persistent_world_lighting_fog_changes": 0, "DOM_refusals": refused,
                      "terrain_refusals": terrain_refused, "positive_camera": True, "positive_sibling_reindex": True,
                      "fixed_source_pin_tested": fixed_source_pin,
                      "scope": "In-memory only; no scene or controller writes", "baseline_warning": warning}))


if __name__ == "__main__":
    main()
