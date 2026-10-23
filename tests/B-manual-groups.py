"""Independent graph/default fixture; no candidate values become allowances."""
from pathlib import Path
import copy
import gzip
import importlib.util
import json

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("manual_group_audit", ROOT / "scripts/verify-B-manual-groups.py")
g = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)
before = json.loads(gzip.decompress((g.OUT / "baseline-known-dom.json.gz").read_bytes()))
expected = g.expected_complete_nodes(before)
defaults = g.constructor_defaults(before)
after = dict(before)
for index, site in enumerate(g.SITES, 1):
    old = f"{g.MAP}/KeySlots/solo_slot_{index:02d}"
    after[site + f"/solo_slot_{index:02d}"] = after.pop(old)
for index, (path, row) in enumerate(expected.items(), 1):
    props = copy.deepcopy(defaults[row["class"]] | row["properties"])
    props["UniqueId"] = g.scalar("UniqueId", f"f0f0f0f0f0f0f0f0{index:016x}")
    props["HistoryId"] = g.scalar("UniqueId", "0" * 32)
    after[path] = {"class": row["class"], "properties": props}

result = g.validate(before, after, defaults)
assert result["passed"] and result["complete"] and result["new_group_helper_instances"] == 254
assert result["class_counts"] == {"Model": 33, "Part": 121, "BillboardGui": 50, "TextLabel": 50}
assert not g.validate(before, after)["complete"], "An explicit-only audit claimed all constructor defaults"
checks = 3
site = g.SITES[0]
point = site + "/EnergyPoint"
label = point + "/EditorLabel"
text = label + "/TextLabel"


def refuses(mutator):
    global checks
    fixture = dict(after)
    # Clone just the new graph, not the immutable 90MB baseline DOM.
    for path in expected:
        fixture[path] = copy.deepcopy(after[path])
    mutator(fixture)
    try:
        g.validate(before, fixture, defaults)
    except (ValueError, KeyError):
        checks += 1
    else:
        raise AssertionError("Malformed group fixture accepted")


refuses(lambda dom: dom.pop(point))
refuses(lambda dom: dom.__setitem__(site + "/UnexpectedPart", copy.deepcopy(dom[point])))
refuses(lambda dom: dom[site].__setitem__("class", "Folder"))
refuses(lambda dom: dom[point]["properties"].__setitem__("CFrame", g.frame(12, 20, 30)))
refuses(lambda dom: dom[point]["properties"].__setitem__("size", g.vector_dom("Vector3", [1.2, .12, 2.4])))
refuses(lambda dom: dom[text]["properties"].__setitem__("Text", g.scalar("string", "wrong")))
refuses(lambda dom: dom[label]["properties"].__setitem__("MaxDistance", g.scalar("float", "150")))
refuses(lambda dom: dom[site + "/PreviewStump/Stump"]["properties"].__setitem__("CanCollide", g.scalar("bool", "true")))
refuses(lambda dom: dom[site]["properties"].__setitem__("PrimaryPart", g.scalar("Ref", g.MAP + "/KeySlots/solo_slot_01")))
refuses(lambda dom: dom[point]["properties"].__setitem__("AttributesSerialize", g.v.h.encode_attributes({"foreign": True})))
refuses(lambda dom: dom[text]["properties"].__setitem__("Tags", g.scalar("BinaryString", b"corn_spawn".hex())))
refuses(lambda dom: dom[text]["properties"].__setitem__("HiddenForeignProperty", g.scalar("bool", "true")))
refuses(lambda dom: dom[point]["properties"].__setitem__("TopSurface", g.scalar("token", "0")))
refuses(lambda dom: dom[text]["properties"]["FontFace"][2][0][1].__setitem__(2, [["url", g.scalar("url", "rbxassetid://foreign")]]))
refuses(lambda dom: dom[site]["properties"].__setitem__("WorldPivotData", ["OptionalCoordinateFrame", "", [["CFrame", g.frame(1, 2, 3)]]]))
refuses(lambda dom: dom[site]["properties"].__setitem__("ModelMeshCFrame", g.frame(0, 0, 0)))
refuses(lambda dom: dom[text]["properties"].pop("Visible"))
refuses(lambda dom: dom[point]["properties"].__setitem__("UniqueId", before[g.MAP]["properties"]["UniqueId"]))
refuses(lambda dom: dom[site + "/PreviewStump/Stump"]["properties"].__setitem__("Color3uint8", g.scalar("Color3uint8", "0")))
print(f"PASS B manual groups: {checks} exact graph/placement/schema/default/refusal checks; no candidate-derived allowances")
