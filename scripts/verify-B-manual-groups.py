"""Independent expected graph for the frozen B manual-authoring groups.

Uses the accepted before DOM and pinned native-build/ItemModels sources only.
It never reads allowed values from the candidate. Call validate(before, after)
with the main audit's already parsed DOMs. Unspecified constructor defaults are
reported as unresolved; this sub-audit alone does not claim complete:true.
"""
from __future__ import annotations

import hashlib
import importlib.util
import math
from pathlib import Path
import sys
import argparse
import base64
import gzip
import json
import subprocess
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("manual_group_dom_helpers", ROOT / "scripts/verify-B-green-variants-copy.py")
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)
require, scalar, identity = v.require, v.scalar, v.identity
f32, vector_dom = v.h.f32, v.h.vector_dom
MAP = "Workspace/CornMap"
BUILD = ROOT / ".artifacts/playtests/2026-10-23-B-manual-authoring/native-build.luau"
BUILD_SHA256 = "b17dfb535f8fb5adc82af7da2706521daf77fb259b755bfb7786e7375cd40ae0"
ITEMS = ROOT / "src/server/Game/ItemModels.luau"
ITEMS_SHA256 = "7a842078fe3551aea7f063deea0527d5aad9de7e31f3359eff0d68c068e0685d"
GENERATED = {"UniqueId", "HistoryId", "ScriptGuid"}
SITES = tuple(f"{MAP}/KeySlots/Site_solo_slot_{index:02d}" for index in range(1, 16))
STARTS = tuple(f"{MAP}/CornerSpawns/{name}" for name in ("SW", "SE", "NW", "NE"))
HOUSES = tuple(f"{MAP}/Props/{name}/B_Visuals" for name in ("HouseWest", "HouseEast", "HouseNorthWest"))
HOME = MAP + "/Props/ScarecrowMarker"
OUT = ROOT / ".artifacts/playtests/2026-10-23-B-manual-authoring"
DEFAULT_READER = ROOT / "scripts/read-B-manual-constructor-defaults.luau"
DEFAULT_READER_SHA256 = "b12ae8df486ef1ba741edb3634452ad12d99d7bbdb54a8a5a8dafccb2efa5292"
LUNE = ROOT / ".tools/lune/lune.exe"
CANDIDATE_SHA256 = "4c5c0c5454da2689996babca4a88b66256240ebb2fb0ac7aa2f787b2ecd8227a"
AUTHOR_FIXTURE = OUT / "native-author-edit-fixture.luau"
AUTHOR_FIXTURE_SHA256 = "5a22304e0ca9e3c0032c0bb64130a5c66a3d748c6a34e89f121f4449134ed342"
MATH_PINS = {
    "model-metadata-math-input.json": "e17216bacb5d6bfd134a3cea9ee91e23fe489530e8e49a43ab773f240985abd6",
    "model-metadata-readonly-math.luau": "bf4ee201fc84e99d769744a295b01b64bff607a089fd0d3bc10dd566ea47da26",
    "model-metadata-readonly-math.json": "7e89abb7e16cb058a2d4638edd40995dc5202dc272ab6055a8d3b340aa53b2e5",
    "model-pivot-math-input.json": "48fbfb6dafbcf7e1089acb1d30b4453c63160a0aada88b787ce27bf38c439c22",
    "model-pivot-readonly-math.luau": "d42914f16e26eedf65c6a3eee69bea8af23c7e5166462730d59166e9f98ddedc",
    "model-pivot-readonly-math.json": "5a64fad3c5c7f8f42086da4c3a819730f779d5deb471c90aa9d0a4210db39c81",
}


def pin_inputs():
    require(hashlib.sha256(BUILD.read_bytes()).hexdigest() == BUILD_SHA256, "Frozen native-build changed")
    require(hashlib.sha256(ITEMS.read_bytes()).hexdigest() == ITEMS_SHA256, "Stump reference Source changed")


def vector(value):
    require(value[0] == "Vector3" and [row[0] for row in value[2]] == ["X", "Y", "Z"], "Invalid baseline Vector3")
    return [f32(float(row[1][1])) for row in value[2]]


def position(node):
    frame = node["properties"]["CFrame"]
    require(frame[0] == "CoordinateFrame" and [row[0] for row in frame[2]][:3] == ["X", "Y", "Z"], "Invalid baseline CFrame")
    return [f32(float(row[1][1])) for row in frame[2][:3]]


def frame(x, y, z, cylinder=False):
    if cylinder:
        angle = f32(math.pi / 2)
        c, s = f32(math.cos(angle)), f32(math.sin(angle))
        rotation = [c, -s, 0, s, c, 0, 0, 0, 1]
    else:
        rotation = [1, 0, 0, 0, 1, 0, 0, 0, 1]
    return vector_dom("CoordinateFrame", [x, y, z] + rotation)


def udim2(xs, xo, ys, yo):
    return ["UDim2", "", [[key, scalar(key, value)] for key, value in zip(("XS", "XO", "YS", "YO"), (xs, xo, ys, yo))]]


def color(rgb):
    return ["Color3", "", [[key, scalar(key, repr(f32(channel / 255)))] for key, channel in zip(("R", "G", "B"), rgb)]]


def rgb_integer(rgb):
    return scalar("Color3uint8", (rgb[0] << 16) | (rgb[1] << 8) | rgb[2])


def expected_nodes(before):
    pin_inputs()
    item_source = before["ServerScriptService/GameServer/Game/ItemModels"]["properties"]["Source"][1]
    require(hashlib.sha256(item_source.replace("\r\n", "\n").encode()).hexdigest() == ITEMS_SHA256, "Accepted ItemModels differs from the pinned reference")
    ground = before[MAP + "/Ground"]
    ground_y = position(ground)[1] + vector(ground["properties"]["size"])[1] / 2
    result = {}
    owned = {"corn_project_id": "children_of_corn", "BManualAuthoringVersion": 1}

    def add(path, cls, properties=None, attributes=None):
        require(path not in result and path not in before, "Duplicate/pre-existing new group node")
        props = {"Name": scalar("string", path.rsplit("/", 1)[1]),
                 "Tags": scalar("BinaryString", ""),
                 "AttributesSerialize": v.h.encode_attributes(attributes or {})}
        props.update(properties or {})
        result[path] = {"class": cls, "properties": props}

    def label(parent, text, text_color):
        path = parent + "/EditorLabel"
        add(path, "BillboardGui", {
            "Size": udim2(0, 190, 0, 38), "StudsOffset": vector_dom("Vector3", [0, 2.5, 0]),
            "MaxDistance": scalar("float", 100), "AlwaysOnTop": scalar("bool", "true"),
        }, owned | {"BAuthoringHelper": True})
        add(path + "/TextLabel", "TextLabel", {
            "Size": udim2(1, 0, 1, 0), "BackgroundColor3": color((20, 25, 18)),
            "BackgroundTransparency": scalar("float", repr(f32(0.2))), "Text": scalar("string", text),
            "TextColor3": color(text_color), "TextSize": scalar("float", 15),
        })

    def point(parent, name, xyz, rgb, kind):
        path = parent + "/" + name
        add(path, "Part", {
            "size": vector_dom("Vector3", [1.2, 0.12, 1.2]), "CFrame": frame(*xyz),
            "Color3uint8": rgb_integer(rgb), "Material": scalar("token", 288),
            "Anchored": scalar("bool", "true"), "CanCollide": scalar("bool", "false"),
            "CanTouch": scalar("bool", "false"), "CanQuery": scalar("bool", "false"),
            "CastShadow": scalar("bool", "false"),
        }, owned | {"BAuthoringHelper": True, "BAuthoringPoint": kind})
        label(path, "ЭНЕРГЕТИК / ПЕНЁК" if kind == "energy" else "КАПКАН", rgb)

    for index, site in enumerate(SITES, 1):
        slot_id = f"solo_slot_{index:02d}"
        slot = before[f"{MAP}/KeySlots/{slot_id}"]
        x, _, z = position(slot)
        add(site, "Model", {"PrimaryPart": scalar("Ref", site + "/" + slot_id)}, owned)
        stump = site + "/PreviewStump"
        add(stump, "Model", {"PrimaryPart": scalar("Ref", stump + "/Stump")}, owned | {"BAuthoringPreview": True})
        for body, cap, offset, height, diameter in (
            ("Stump", "CutWood", (0, 4, 0), 8, 6),
            ("Step1", "Step1Top", (-7, 1.25, 0), 2.5, 3.2),
            ("Step2", "Step2Top", (-4, 2.5, 0), 5, 3.2),
        ):
            cx, cy, cz = f32(f32(x + 3.6) + offset[0]), f32(f32(ground_y) + offset[1]), f32(z + offset[2])
            for name, xyz, size, rgb in (
                (body, (cx, cy, cz), (height, diameter, diameter), (94, 70, 43)),
                (cap, (cx, f32(cy + f32(height / 2 + 0.01)), cz), (0.12, diameter - 0.15, diameter - 0.15), (171, 143, 95)),
            ):
                add(stump + "/" + name, "Part", {
                    "size": vector_dom("Vector3", size), "CFrame": frame(*xyz, cylinder=True),
                    "Color3uint8": rgb_integer(rgb), "Material": scalar("token", 512), "shape": scalar("token", 2),
                    "Anchored": scalar("bool", "true"), "CanCollide": scalar("bool", "false"),
                    "CanTouch": scalar("bool", "false"), "CanQuery": scalar("bool", "false"),
                }, {"corn_project_id": "children_of_corn", "BAuthoringHelper": True})
        point(site, "EnergyPoint", (f32(x + 3.6), f32(ground_y + 8.68), z), (65, 220, 95), "energy")
        point(site, "TrapPoint", (x - 3.6, ground_y + 0.22, z), (240, 110, 65), "trap")
        label(site + "/" + slot_id, slot_id + " / КЛЮЧ", (255, 220, 100))
    for start in STARTS:
        require(start in before and before[start]["class"] == "SpawnLocation", "Accepted start missing")
        label(start, "СТАРТ ИГРОКА / " + start.rsplit("/", 1)[1], (120, 195, 255))
    hx, _, hz = position(before[HOME + "/Body"])
    point(HOME, "WardenSpawn", (hx, ground_y + 0.15, hz), (210, 80, 240), "warden")
    result[HOME + "/WardenSpawn/EditorLabel/TextLabel"]["properties"]["Text"] = scalar("string", "СПАУН ЧУЧЕЛА — двигать Model")
    for house in HOUSES:
        add(house, "Model", {"PrimaryPart": scalar("Ref", "null")}, owned)
    require(len(result) == 254, "Independent group graph must contain 254 additions")
    return result


def in_scope(path):
    return (path.startswith(MAP + "/KeySlots/") or path.startswith(MAP + "/CornerSpawns/")
            or path.startswith(HOME + "/") or any(path == root or path.startswith(root + "/") for root in HOUSES))


def property_same(actual, expected):
    if v.expected_same(actual, expected):
        return True
    if actual[0] == expected[0] == "OptionalCoordinateFrame" and len(actual[2]) == len(expected[2]) == 1:
        left, right = actual[2][0], expected[2][0]
        return left[0] == right[0] == "CFrame" and v.expected_same(
            ["CoordinateFrame", "", left[1][2]], ["CoordinateFrame", "", right[1][2]])
    if actual[0] != expected[0] or actual[0] not in {"Color3", "UDim2"}:
        return False
    if [row[0] for row in actual[2]] != [row[0] for row in expected[2]]:
        return False
    return all(a[1][0] == e[1][0] and not a[1][2] and not e[1][2]
               and f32(float(a[1][1])) == f32(float(e[1][1])) for a, e in zip(actual[2], expected[2]))


def components(value):
    return [f32(float(row[1][1])) for row in value[2]]


def freeze_text(path, text):
    # JSON proposals were frozen by Windows text I/O (CRLF); code was LF.
    # MATH_PINS checks the exact original bytes before this semantic rebuild.
    require(path.is_file() and path.read_text(encoding="utf-8") == text,
            "Frozen independently derived math proposal differs: " + path.name)


def write_metadata_math_proposal(before):
    """Only baseline inputs and the two frozen native Stage/Restore calls."""
    require(hashlib.sha256(AUTHOR_FIXTURE.read_bytes()).hexdigest() == AUTHOR_FIXTURE_SHA256, "Author fixture changed")
    rows = []
    for index, site in enumerate(SITES, 1):
        slot = before[f"{MAP}/KeySlots/solo_slot_{index:02d}"]["properties"]
        require(v.expected_same(slot["PivotOffset"], frame(0, 0, 0)), "Nondefault slot pivot requires explicit composition")
        rows.append({"path": site, "pivot": components(slot["CFrame"]), "offset": [.5, 0, .5],
                     "yaw": .05, "before": components(frame(0, 0, 0))})
    for name in ("HouseWest", "HouseEast", "HouseNorthWest", "ScarecrowMarker"):
        path = MAP + "/Props/" + name
        props = before[path]["properties"]
        require(props["PrimaryPart"] == scalar("Ref", "null") and len(props["WorldPivotData"][2]) == 1,
                "Expected exact accepted WorldPivot for old Model")
        rows.append({"path": path, "pivot": components(props["WorldPivotData"][2][0][1]),
                     "offset": [1, 0, 1] if name == "ScarecrowMarker" else [.25, 0, .5],
                     "yaw": 0 if name == "ScarecrowMarker" else .01,
                     "before": components(props["ModelMeshCFrame"])})
    payload = {"stage_count": 2, "author_fixture_sha256": AUTHOR_FIXTURE_SHA256,
               "native_build_sha256": BUILD_SHA256, "baseline_only": True, "rows": rows}
    freeze_text(OUT / "model-metadata-math-input.json", json.dumps(payload, indent=2) + "\n")
    code = '''-- Pure arithmetic proposal: no Instances, Source, Parent or property writes.
assert(game.Name=="Children_of_corn_B.rbxl" and not game:GetService("RunService"):IsRunning())
local map=workspace:FindFirstChild("CornMap")
assert(map and map:GetAttribute("corn_project_id")=="children_of_corn" and map:GetAttribute("HarvestArtVariant")=="B" and map:GetAttribute("BManualAuthoringVersion")==1)
local H=game:GetService("HttpService")
local input=H:JSONDecode([==[''' + json.dumps(payload, separators=(",", ":")) + ''']==])
local output={}
for _,row in input.rows do
 local pivot=CFrame.new(table.unpack(row.pivot))
 local target=CFrame.new(pivot.Position+Vector3.new(table.unpack(row.offset)))*CFrame.Angles(0,row.yaw,0)*pivot.Rotation
 local delta=target*pivot:Inverse()
 local result=CFrame.new(table.unpack(row.before))
 for _=1,input.stage_count do result=delta*result end
 output[row.path]={result:GetComponents()}
end
return H:JSONEncode({stage_count=input.stage_count,author_fixture_sha256=input.author_fixture_sha256,baseline_only=true,modelMeshCFrames=output})
'''
    freeze_text(OUT / "model-metadata-readonly-math.luau", code)
    return payload


def write_pivot_math_proposal(before):
    """Oriented cuboid bounds from the immutable assembly recipe only."""
    expected = expected_nodes(before)
    rows = []
    def part(node):
        return {"frame": components(node["properties"]["CFrame"]),
                "size": vector(node["properties"]["size"])}
    def beneath(prefix):
        return [part(node) for path, node in before.items()
                if path.startswith(prefix + "/") and "CFrame" in node["properties"] and "size" in node["properties"]]
    for index, site in enumerate(SITES, 1):
        slot_id = f"solo_slot_{index:02d}"
        slot = before[f"{MAP}/KeySlots/{slot_id}"]
        stump_root = site + "/PreviewStump"
        stump_parts = [part(node) for path, node in expected.items() if path.startswith(stump_root + "/") and node["class"] == "Part"]
        points = [part(expected[site + "/" + name]) for name in ("EnergyPoint", "TrapPoint")]
        rows.append({"path": site, "basis": components(slot["properties"]["CFrame"]),
                     "parts": [part(slot)] + beneath(f"{MAP}/TorchMarkers/torch_{slot_id}") + stump_parts + points})
        rows.append({"path": stump_root, "basis": components(expected[stump_root + "/Stump"]["properties"]["CFrame"]),
                     "parts": stump_parts})
    for house in ("HouseWest", "HouseEast", "HouseNorthWest"):
        overlays = [(path, node) for path, node in before.items()
                    if path.startswith(MAP + "/HarvestDecor/VariantB/") and "CFrame" in node["properties"]
                    and v.h.decode_attributes(node["properties"]["AttributesSerialize"]).get("HarvestSourceHouse", {}).get("value") == house]
        require(len(overlays) > 0, "Independent B barn primitives missing")
        parts = [part(node) for _, node in overlays]
        parts.extend(part(node) for path, node in before.items()
                     if path.startswith(f"{MAP}/HarvestDecor/Common/{house}_") and "CFrame" in node["properties"])
        rows.append({"path": f"{MAP}/Props/{house}/B_Visuals", "basis": components(overlays[0][1]["properties"]["CFrame"]), "parts": parts})
        for side in ("-1", "1"):
            prefix = f"{MAP}/TorchMarkers/torch_{house}{side}"
            primary = before[prefix]["properties"]["PrimaryPart"][1]
            require(primary in before, "Accepted torch PrimaryPart missing")
            rows.append({"path": prefix, "basis": components(before[primary]["properties"]["CFrame"]), "parts": beneath(prefix)})
    require(len(rows) == 39, "Expected 33 new and 6 old derived model pivots")
    payload = {"baseline_only": True, "native_build_sha256": BUILD_SHA256,
               "author_fixture_sha256": AUTHOR_FIXTURE_SHA256, "stage_count": 2, "rows": rows}
    freeze_text(OUT / "model-pivot-math-input.json", json.dumps(payload, indent=2) + "\n")
    code = '''-- Baseline cuboid arithmetic only; no Instances or property writes.
assert(game.Name=="Children_of_corn_B.rbxl" and not game:GetService("RunService"):IsRunning())
local map=workspace:FindFirstChild("CornMap")
assert(map and map:GetAttribute("corn_project_id")=="children_of_corn" and map:GetAttribute("HarvestArtVariant")=="B" and map:GetAttribute("BManualAuthoringVersion")==1)
local H=game:GetService("HttpService")
local input=H:JSONDecode([==[''' + json.dumps(payload, separators=(",", ":")) + ''']==])
local output={}
for _,row in input.rows do
 local basis=CFrame.new(table.unpack(row.basis))
 local low,high=Vector3.new(math.huge,math.huge,math.huge),Vector3.new(-math.huge,-math.huge,-math.huge)
 for _,part in row.parts do
  local cf=basis:ToObjectSpace(CFrame.new(table.unpack(part.frame)))
  local half=Vector3.new(table.unpack(part.size))/2
  local right,up,back=cf.XVector,cf.YVector,cf.ZVector
  local extent=Vector3.new(math.abs(right.X)*half.X+math.abs(up.X)*half.Y+math.abs(back.X)*half.Z,
   math.abs(right.Y)*half.X+math.abs(up.Y)*half.Y+math.abs(back.Y)*half.Z,
   math.abs(right.Z)*half.X+math.abs(up.Z)*half.Y+math.abs(back.Z)*half.Z)
  local lo,hi=cf.Position-extent,cf.Position+extent
  low=Vector3.new(math.min(low.X,lo.X),math.min(low.Y,lo.Y),math.min(low.Z,lo.Z))
  high=Vector3.new(math.max(high.X,hi.X),math.max(high.Y,hi.Y),math.max(high.Z,hi.Z))
 end
 local pivot=basis*CFrame.new((low+high)/2)
 output[row.path]={pivot:GetComponents()}
end
return H:JSONEncode({baseline_only=true,author_fixture_sha256=input.author_fixture_sha256,worldPivots=output})
'''
    freeze_text(OUT / "model-pivot-readonly-math.luau", code)
    return payload


def independent_model_metadata(before):
    for filename, pin in MATH_PINS.items():
        require(hashlib.sha256((OUT / filename).read_bytes()).hexdigest() == pin,
                "Frozen pure-math evidence changed: " + filename)
    mesh_input = write_metadata_math_proposal(before)
    pivot_input = write_pivot_math_proposal(before)
    mesh_result = json.loads((OUT / "model-metadata-readonly-math.json").read_bytes())
    pivot_result = json.loads((OUT / "model-pivot-readonly-math.json").read_bytes())
    require(mesh_result["baseline_only"] is True and mesh_result["stage_count"] == 2
            and mesh_result["author_fixture_sha256"] == AUTHOR_FIXTURE_SHA256
            and set(mesh_result["modelMeshCFrames"]) == {row["path"] for row in mesh_input["rows"]},
            "Model mesh math result provenance differs")
    require(pivot_result["baseline_only"] is True and pivot_result["author_fixture_sha256"] == AUTHOR_FIXTURE_SHA256
            and set(pivot_result["worldPivots"]) == {row["path"] for row in pivot_input["rows"]},
            "Model pivot math result provenance differs")
    result = {}
    for path, numbers in mesh_result["modelMeshCFrames"].items():
        result.setdefault(path, {})["ModelMeshCFrame"] = vector_dom("CoordinateFrame", numbers)
    for path, numbers in pivot_result["worldPivots"].items():
        result.setdefault(path, {})["WorldPivotData"] = ["OptionalCoordinateFrame", "", [["CFrame", vector_dom("CFrame", numbers)]]]
    return result


def expected_complete_nodes(before):
    result = expected_nodes(before)
    metadata = independent_model_metadata(before)
    for path, node in result.items():
        node["properties"].update(metadata.get(path, {}))
    return result


def constructor_defaults(before):
    """Read independent bundled reflection defaults, never a candidate property."""
    require(hashlib.sha256(DEFAULT_READER.read_bytes()).hexdigest() == DEFAULT_READER_SHA256, "Independent default reader changed")
    xml = subprocess.run([str(LUNE), "run", str(DEFAULT_READER)], check=True,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout
    root = ET.fromstring(xml)
    shared = {node.attrib["md5"]: base64.b64decode(node.text or "").hex()
              for node in root.findall("./SharedStrings/SharedString")}
    def value(node):
        text = node.text or ""
        if node.tag == "SharedString":
            require(text in shared, "Independent default shared string unresolved")
            text = shared[text]
        elif node.tag == "BinaryString":
            text = base64.b64decode(text).hex()
        return [node.tag, text, [[child.tag, value(child)] for child in node]]
    result = {item.attrib["class"]: {p.attrib["name"]: value(p) for p in item.find("Properties")}
              for item in root.findall("Item")}
    require(set(result) == {"Model", "Part", "BillboardGui", "TextLabel"}, "Independent constructor class set differs")
    common = {"Capabilities": scalar("SecurityCapabilities", "0"),
              "SerializedOverrides": scalar("BinaryString", ""),
              "AttributesSerialize": scalar("BinaryString", ""), "Tags": scalar("BinaryString", "")}
    # These fields are unrepresentable through Lune's Lua values. Their exact
    # empty constructor encoding is separately present in accepted Parts/Models.
    for cls, prototype in (("Part", MAP + "/KeySlots/solo_slot_01"), ("Model", HOME)):
        for prop in ("Capabilities", "SerializedOverrides"):
            wanted = common[prop]
            require(v.same(before[prototype]["properties"][prop], wanted), "Accepted constructor metadata differs: " + cls + "/" + prop)
    for defaults in result.values():
        defaults.update(common)
        for prop in GENERATED:
            defaults.pop(prop, None)
        # Archivable is an inherited runtime flag omitted by the accepted
        # Studio engine serializer, although explicit Lune setters emit it.
        require(all("archivable" not in before[p]["properties"] for p in
                    (MAP + "/KeySlots/solo_slot_01", HOME)), "Accepted engine archivable schema differs")
        defaults.pop("archivable", None)
    # The bundled API names this GuiObject property InputSink. The current
    # engine serialization alias is Sink; its value remains the independently
    # computed reflection constructor default, never a candidate-derived value.
    require(result["TextLabel"].pop("InputSink") == scalar("token", 0), "Independent InputSink default differs")
    result["TextLabel"]["Sink"] = scalar("token", 0)
    return result


def validate(before, after, constructor_defaults=None):
    expected = expected_complete_nodes(before)
    old_ids = {identity(node) for node in before.values()}
    new_scope = {path for path, node in after.items() if in_scope(path) and identity(node) not in old_ids}
    require(new_scope == set(expected), "Manual group/helper addition graph differs: missing="
            + repr(sorted(set(expected) - new_scope)) + "; extra=" + repr(sorted(new_scope - set(expected))))
    unresolved, counts = {}, {}
    for path, wanted in expected.items():
        actual = after[path]
        require(actual["class"] == wanted["class"], "Manual group class differs: " + path)
        require(path.rpartition("/")[0] in after, "Manual group parent missing: " + path)
        counts[wanted["class"]] = counts.get(wanted["class"], 0) + 1
        properties = actual["properties"]
        declared = wanted["properties"]
        if constructor_defaults is not None:
            require(wanted["class"] in constructor_defaults, "Independent constructor class missing")
            declared = constructor_defaults[wanted["class"]] | declared
            require(set(properties) == set(declared) | (set(properties) & GENERATED), "Complete manual property schema differs: " + path)
        for prop, value in declared.items():
            require(prop in properties, "Explicit manual property absent: " + path + "/" + prop)
            compare = v.attributes_same if prop == "AttributesSerialize" else v.tags_same if prop == "Tags" else property_same
            require(compare(properties[prop], value), "Explicit manual property differs: " + path + "/" + prop)
        leftovers = sorted(set(properties) - set(declared) - GENERATED)
        if leftovers:
            previous = unresolved.setdefault(wanted["class"], set())
            previous.update(leftovers)
    pin_inputs()
    return {"passed": True, "complete": constructor_defaults is not None and not unresolved, "new_group_helper_instances": len(expected),
            "class_counts": counts, "explicit_properties_exact": True,
            "expected_paths": sorted(expected),
            "unresolved_constructor_defaults": {key: sorted(value) for key, value in sorted(unresolved.items())},
            "constructor_defaults_independently_supplied": constructor_defaults is not None,
            "exact_derived_new_model_mesh_frames": 15, "exact_derived_new_model_world_pivots": 33,
            "model_metadata_math_pins": MATH_PINS,
            "native_build_sha256": BUILD_SHA256, "item_models_sha256": ITEMS_SHA256,
            "scope": "254 exact new manual groups/points/stump parts/labels. Explicit values derive solely from immutable before DOM and frozen builder/reference, never the candidate. Generated metadata and unresolved constructor defaults require the main independent audit."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-dom", type=Path, default=OUT / "baseline-known-dom.json.gz")
    parser.add_argument("--candidate-dom", type=Path, default=OUT / "candidate-noncorn-dom.json.gz")
    parser.add_argument("--candidate", type=Path, default=ROOT / "place/Children_of_corn_B.rbxl")
    parser.add_argument("--report", type=Path, default=OUT / "save-groups-validation.json")
    args = parser.parse_args()
    require(args.report.resolve().is_relative_to(OUT.resolve()), "Report must stay in manual evidence")
    candidate_hash = hashlib.sha256(args.candidate.read_bytes()).hexdigest()
    require(candidate_hash == CANDIDATE_SHA256, "Author-saved candidate changed")
    before = json.loads(gzip.decompress(args.baseline_dom.read_bytes()))
    after = json.loads(gzip.decompress(args.candidate_dom.read_bytes()))
    defaults = constructor_defaults(before)
    try:
        report = validate(before, after, defaults)
    except ValueError as error:
        # Preserve a useful non-green report when the explicit proposal passes
        # but engine Model metadata still needs an independent derivation.
        report = validate(before, after)
        expected = expected_nodes(before)
        mismatches = []
        for path, wanted in expected.items():
            declared = defaults[wanted["class"]] | wanted["properties"]
            properties = after[path]["properties"]
            for prop in sorted(set(declared) | (set(properties) - GENERATED)):
                actual, value = properties.get(prop), declared.get(prop)
                compare = v.attributes_same if prop == "AttributesSerialize" else v.tags_same if prop == "Tags" else property_same
                if actual is None or value is None or not compare(actual, value):
                    mismatches.append({"path": path, "property": prop,
                                       "candidate_value": actual, "independent_expected_value": value})
        report.update({"passed": False, "complete": False,
                       "constructor_defaults_independently_supplied": True,
                       "unresolved_constructor_defaults": {},
                       "unresolved_model_metadata": mismatches,
                       "failure": str(error)})
    require(hashlib.sha256(args.candidate.read_bytes()).hexdigest() == candidate_hash, "Candidate changed during group audit")
    report.update({"candidate_sha256": candidate_hash,
                   "default_reader_sha256": hashlib.sha256(DEFAULT_READER.read_bytes()).hexdigest(),
                   "lune_sha256": hashlib.sha256(LUNE.read_bytes()).hexdigest()})
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: value for key, value in report.items() if key != "expected_paths"}, ensure_ascii=False))
    if not report["passed"]:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
