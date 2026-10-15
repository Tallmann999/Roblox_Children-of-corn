"""Read-only exact engine-save audit: 78 Sources, 28 CFrames, 2 author-approved Bloom values.

Five imported fog nodes are checked against the immutable original XML and a
fixed serialized-default schema. New engine identity IDs alone are generated;
all 6839 original identities/properties remain guarded by the original audit.
"""
import argparse
import collections
import importlib.util
import json
import math
from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / "place/Children_of_corn.before-haze-clusters-20261015.rbxl"
BASELINE_HASH = "a897bb52fa85505090f973e910139915e6ebb2995e44915c31ecbc2b5c511dca"
BASELINE_BYTES = 1019419
MANIFEST = ROOT / "scripts/cluster-layout.json"
MANIFEST_HASH = "e768de19254049b242865baa7e68d7eb87f4b21fa4b38ca63889dc1ea624fd86"
FRAME_KEYS = ("X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22")
BLOOM_PATH = "Lighting/Bloom"
BLOOM_VALUES = {"Intensity": (1, 0.85), "Size": (24, 32)}
spec = importlib.util.spec_from_file_location("readability", ROOT / "scripts/verify-readability-copy.py")
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)
spec = importlib.util.spec_from_file_location("fog_builder", ROOT / "scripts/build-haze-installer.py")
fog = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fog)
require = r.require


def layout():
    require(r.sha256(MANIFEST) == MANIFEST_HASH, "Fixed cluster manifest changed")
    data = r.load_json(MANIFEST)
    require(data["version"] == 1 and data["baseline"] == {
        "path": "place/Children_of_corn.before-haze-clusters-20261015.rbxl",
        "bytes": BASELINE_BYTES, "sha256": BASELINE_HASH,
    }, "Unrecognized cluster baseline")
    parts = data["parts"]
    require(len(parts) == len({part["path"] for part in parts}) == 28, "Expected fixed 28 CFrame targets")
    require(collections.Counter(part["role"] for part in parts) == {"slot": 15, "torch": 10, "barrel": 3}, "Unrecognized cluster target roles")
    return data


def frame(value):
    require(value[0] == "CoordinateFrame" and len(value[2]) == 12, "Unexpected cluster CFrame type/shape")
    fields = {}
    for key, child in value[2]:
        require(key not in fields and key in FRAME_KEYS and child[0] == key and not child[2], "Malformed cluster CFrame")
        value = float(child[1])
        require(math.isfinite(value) and abs(value) <= 3.4028234663852886e38, "Nonfinite/overflow cluster CFrame")
        # Lune XML uses the shortest round-tripping f32 decimal, e.g. 262.8
        # represents exactly 262.79998779296875 in the engine/manifest.
        fields[key] = struct.unpack("<f", struct.pack("<f", value))[0]
    require(set(fields) == set(FRAME_KEYS) and all(math.isfinite(v) for v in fields.values()), "Nonfinite cluster CFrame")
    return [fields[key] for key in FRAME_KEYS]


def scalar(kind, value):
    return [kind, str(value), []]


def vector(kind, values):
    keys = FRAME_KEYS if kind in {"CoordinateFrame", "CFrame"} else ("X", "Y", "Z")
    return [kind, "", [[key, scalar(key, value)] for key, value in zip(keys, values)]]


def fog_schema(asset_sources):
    original = fog.original_nodes()
    require(set(asset_sources) == set(fog.SOURCES), "Expected exactly three fog asset Sources")
    result = {}
    for path, node in original.items():
        cls = node["class"]
        props = {
            "Name": scalar("string", path.rsplit("/", 1)[-1]),
            "AttributesSerialize": scalar("BinaryString", ""), "Capabilities": scalar("SecurityCapabilities", 0),
            "HistoryId": scalar("UniqueId", "0" * 32), "DefinesCapabilities": scalar("bool", "false"),
            "SerializedOverrides": scalar("BinaryString", ""), "SourceAssetId": scalar("int64", -1), "Tags": scalar("BinaryString", ""),
        }
        if cls == "Model":
            props |= {
                "LevelOfDetail": scalar("token", 0), "ModelStreamingMode": scalar("token", 0),
                "ModelMeshCFrame": vector("CoordinateFrame", (0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)),
                "ModelMeshData": scalar("SharedString", ""), "ModelMeshSize": vector("Vector3", (0, 0, 0)),
                "NeedsPivotMigration": scalar("bool", "false"), "PrimaryPart": scalar("Ref", "null"),
                "ScaleFactor": scalar("float", 1), "SlimHash": scalar("SharedString", ""),
                "WorldPivotData": ["OptionalCoordinateFrame", "", [["CFrame", vector("CFrame", (0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1))]]],
            }
        elif cls in {"ModuleScript", "Script", "LocalScript"}:
            props |= {"LinkedSource": ["ContentId", "", [["null", scalar("null", "")]]], "Source": scalar("string", asset_sources[path])}
            if cls in {"Script", "LocalScript"}:
                props |= {"Disabled": node["properties"]["Disabled"], "RunContext": scalar("token", 0)}
        else:
            require(cls == "StringValue", "Unexpected fog class")
            props["Value"] = node["properties"]["Value"]
        result[path] = {"class": cls, "properties": props}
    return result


def validate_fog(before, after, asset_sources):
    expected = fog_schema(asset_sources)
    require(set(after) - set(before) == set(expected), "Unexpected/missing imported fog node")
    old_ids = {node["properties"]["UniqueId"][1].lower() for node in before.values() if "UniqueId" in node["properties"]}
    old_guids = {node["properties"]["ScriptGuid"][1].lower() for node in before.values() if "ScriptGuid" in node["properties"]}
    new_ids, new_guids = set(), set()
    for path, node in expected.items():
        actual = after[path]
        require(actual["class"] == node["class"], "Imported fog class changed: " + path)
        generated = {"UniqueId"} | ({"ScriptGuid"} if path in asset_sources else set())
        require(set(actual["properties"]) == set(node["properties"]) | generated, "Imported fog property set changed: " + path)
        for prop, value in node["properties"].items():
            other = actual["properties"][prop]
            if prop == "Source":
                require(other[0] == "string" and not other[2] and fog.normalized(other[1]) == value[1], "Fog asset Source mismatch: " + path)
            else:
                require(r.normalized(other) == r.normalized(value), "Imported fog property changed: " + path + "/" + prop)
        value = actual["properties"]["UniqueId"]
        require(value[0] == "UniqueId" and not value[2] and re.fullmatch(r"[0-9a-fA-F]{32}", value[1]) and int(value[1], 16) != 0, "Invalid new fog identity")
        identity = value[1].lower()
        require(identity not in old_ids and identity not in new_ids, "Duplicate original/new fog identity")
        new_ids.add(identity)
        if "ScriptGuid" in generated:
            value = actual["properties"]["ScriptGuid"]
            require(value[0] == "string" and not value[2] and re.fullmatch(r"\{[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\}", value[1]), "Invalid new fog ScriptGuid")
            guid = value[1].lower()
            require(guid not in old_guids and guid not in new_guids and guid != "{00000000-0000-0000-0000-000000000000}", "Duplicate original/new fog ScriptGuid")
            new_guids.add(guid)
    return expected


def validate_dom(before, after, sources, classes, asset_sources):
    require(len(before) == 6839 and len(after) == 6844, "Expected original6839 plus imported5 fog instances")
    new_fog = validate_fog(before, after, asset_sources)
    adjusted = before.copy()
    changes = []
    require(BLOOM_PATH in before and BLOOM_PATH in after and before[BLOOM_PATH]["class"] == after[BLOOM_PATH]["class"] == "BloomEffect", "Fixed author Bloom missing/reclassified")
    bloom_properties = before[BLOOM_PATH]["properties"].copy()
    for prop, (old, target) in BLOOM_VALUES.items():
        require(prop in bloom_properties and r.normalized(bloom_properties[prop]) == scalar("float", old), "Immutable author Bloom baseline differs: " + prop)
        actual = after[BLOOM_PATH]["properties"].get(prop)
        require(actual is not None and actual[0] == "float" and not actual[2], "Author Bloom property type differs: " + prop)
        value = float(actual[1])
        require(math.isfinite(value) and abs(value) <= 3.4028234663852886e38 and struct.pack("<f", value) == struct.pack("<f", target), "Unapproved author Bloom value: " + prop)
        bloom_properties[prop] = actual
        changes.append({"path": BLOOM_PATH, "property": prop, "reason": "fixed_author_approved_bloom", "before": old, "after": struct.unpack("<f", struct.pack("<f", target))[0]})
    adjusted[BLOOM_PATH] = before[BLOOM_PATH] | {"properties": bloom_properties}
    for entry in layout()["parts"]:
        path = entry["path"]
        require(path in before and path in after and before[path]["class"] == after[path]["class"] == "Part", "Fixed cluster Part missing/reclassified: " + path)
        old = frame(before[path]["properties"]["CFrame"])
        actual = after[path]["properties"]["CFrame"]
        new = frame(actual)
        require(all(abs(a - b) <= 0.00001 for a, b in zip(old, entry["before"])), "Immutable cluster baseline frame differs: " + path)
        require(all(abs(a - b) <= 0.00001 for a, b in zip(new, entry["after"])), "Unapproved/incomplete cluster placement: " + path)
        adjusted[path] = before[path] | {"properties": before[path]["properties"] | {"CFrame": actual}}
        changes.append({"path": path, "property": "CFrame", "reason": "fixed_author_approved_cluster_translation", "before": old, "after": new})
    existing = {path: node for path, node in after.items() if path not in new_fog}
    result = r.validate_dom(adjusted, existing, sources, classes)
    require(sum("Source" in node["properties"] for node in after.values()) == 78, "Expected persistent78 Source total")
    result["allowed_changes"].extend(changes)
    return result | {"new_instances": 5, "matching_asset_sources": 3, "total_sources": 78,
        "cluster_cframes": 28, "bloom_property_changes": 2, "fog_original_xml_sha256": fog.ORIGINAL_HASH,
        "new_fog_identity_scope": "Five valid unique engine identity IDs and three ScriptGuids; original6839 identities remain exact",
        "world_and_lighting_exact": False, "world_exact_except_28_cluster_cframes_five_fog_nodes_and_two_bloom_values": True}


def check(original, candidate):
    original, candidate = original.resolve(), candidate.resolve()
    old_hash, new_hash = r.sha256(original), r.sha256(candidate)
    require(original == BASELINE.resolve() and old_hash == BASELINE_HASH and original.stat().st_size == BASELINE_BYTES, "Immutable before-haze-clusters baseline changed")
    require(candidate.is_file() and candidate.suffix.lower() == ".rbxl", "Candidate must be exact engine-saved RBXL")
    sources, classes = r.mapping_from_sourcemap(ROOT / "build/sourcemap.json")
    asset_sources = fog.current_sources()
    records = fog.original_nodes()
    fog.verify_snapshot(records)
    before, warning_before = r.p.known_dom(original)
    after, warning_after = r.p.known_dom(candidate)
    unknown_before, unknown_after = r.p.unknown_properties(original), r.p.unknown_properties(candidate)
    r.validate_unknown(unknown_before, unknown_after)
    result = validate_dom(before, after, sources, classes, asset_sources)
    meta = r.p.corn_metadata(candidate)
    require(meta["corners_valid"] and meta["overview_owned"] and meta["preview_owned"], "CornMap guards invalid")
    require(r.sha256(original) == old_hash and r.sha256(candidate) == new_hash, "Input scene changed during audit")
    require(r.mapping_from_sourcemap(ROOT / "build/sourcemap.json") == (sources, classes) and fog.current_sources() == asset_sources, "Source/build/assets changed during audit")
    require(r.sha256(MANIFEST) == MANIFEST_HASH and r.sha256(fog.ORIGINAL) == fog.ORIGINAL_HASH, "Fixed layout/original XML changed during audit")
    return result | {"passed": True, "original_sha256": old_hash, "candidate_sha256": new_hash,
        "original_instances": len(before), "candidate_instances": len(after), "bytes": candidate.stat().st_size,
        "layout_sha256": MANIFEST_HASH, "raw_unknown_properties": unknown_after,
        "warnings": {"original": warning_before, "candidate": warning_after},
        "scope": "Read-only exact engine bytes; existing75 Sources match src, three imported fog Sources match declared assets. Only fixed28 Part CFrames, two exact author-approved Bloom values, five exact-schema imported nodes, Sources and approved editor metadata differ; all other original properties/identities/world/Lighting/art/raw Terrain stay exact. No new service metadata exceptions."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("original", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    report_path = args.report.resolve()
    require(report_path.suffix.lower() == ".json" and any(report_path.is_relative_to((ROOT / folder).resolve()) for folder in ("build", ".artifacts")), "Report must remain in owned artifact/build directory")
    report = check(args.original, args.candidate)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({key: value for key, value in report.items() if key not in {"allowed_changes", "warnings", "raw_unknown_properties"}}))
