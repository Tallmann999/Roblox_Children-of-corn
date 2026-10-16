"""Strict Harvest save checker against immutable DOM plus synthetic exact-contract A/B.
No scene write; production engine-save acceptance and independent manifest review remain separate.
"""
import copy
import importlib.util
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("harvest_audit", ROOT / "scripts/verify-harvest-copy.py")
f = importlib.util.module_from_spec(spec)
spec.loader.exec_module(f)
assert f.sha256(f.BASELINE) == f.BASELINE_HASH and f.BASELINE.stat().st_size == f.BASELINE_BYTES
BEFORE, _ = f.r.p.known_dom(f.BASELINE)
TYPED, _ = f.typed.typed_scene(f.BASELINE)
PAYLOAD, SOURCES, CLASSES, CODE_ADDED, DECLARED = f.mapping()
ASSETS = f.fog.current_sources()
CATALOG = f.load_json(f.CATALOG)
assert f.basepart_color((0.095, 0.061, 0.029)) == [24 / 255, 15 / 255, 7 / 255]
assert f.basepart_color((0.042, 0.031, 0.026)) == [10 / 255, 7 / 255, 6 / 255]
MODULE = BEFORE["ServerScriptService/GameServer/Game/RoundAudio"]
TEMPLATES = {cls: next(row for row in BEFORE.values() if row["class"] == cls) for cls in ("Folder", "Model", "MeshPart", "Part", "Texture")}


def scalar(kind, value): return [kind, str(value), []]


def build(variant):
    specs = f.world_contract(TYPED, CATALOG, variant)
    after = copy.deepcopy(BEFORE)
    signatures = copy.deepcopy(TYPED)
    counter = 0
    def uid():
        nonlocal counter
        counter += 1
        return f"{(1 << 125) + counter:032x}"
    for path in sorted(CODE_ADDED):
        row = copy.deepcopy(MODULE)
        row["properties"]["Name"] = scalar("string", path.rsplit("/", 1)[1])
        row["properties"]["UniqueId"] = scalar("UniqueId", uid())
        row["properties"]["ScriptGuid"] = scalar("string", "{A0000000-0000-0000-0000-" + f"{counter:012x}" + "}")
        after[path] = row
    for path, source in (SOURCES | ASSETS).items(): after[path]["properties"]["Source"] = scalar("string", source)
    for path, expected in specs.items():
        row = copy.deepcopy(TEMPLATES[expected["class"]])
        props = row["properties"]
        props["Name"] = scalar("string", path.rsplit("/", 1)[1])
        props["UniqueId"] = scalar("UniqueId", uid())
        props["AttributesSerialize"] = scalar("BinaryString", "01")
        if path in (f.DECOR,f.HOME):
            name=b"HarvestAppliedVariant"
            props["AttributesSerialize"][1]=(struct.pack("<I",len(name))+name+bytes([2])+struct.pack("<I",1)+variant.encode()).hex()
        props["Tags"] = scalar("BinaryString", "")
        props["Capabilities"] = scalar("SecurityCapabilities", 0)
        props["DefinesCapabilities"] = scalar("bool", "false")
        props["SerializedOverrides"] = scalar("BinaryString", "")
        for value in props.values():
            if value[0] == "Ref": value[1] = "null"
        if expected["class"] in ("Part", "MeshPart"):
            for key in ("CanCollide", "CanTouch", "CanQuery"): props[key] = scalar("bool", "false")
            props["Transparency"] = scalar("float", expected["properties"]["Transparency"]["value"])
        if expected["class"] == "MeshPart":
            props["MeshContent"] = ["Content", "", [["null", ["null", "", []]]]]
            texture = expected["attributes"]["HarvestTexture"]["value"]
            props["TextureContent"] = ["Content", "", [["uri", ["uri", texture, []]]]] if texture else ["Content", "", [["null", ["null", "", []]]]]
        if expected["class"] == "Texture":
            branch=expected["attributes"]["HarvestBranch"]["value"]
            props["Transparency"]=scalar("float",0 if branch==variant else 1)
            props["TextureContent"] = ["Content", "", [["uri", ["uri", expected["attributes"]["HarvestTexture"]["value"], []]]]]
            props["Face"] = scalar("token", 1)
            props["StudsPerTileU"] = props["StudsPerTileV"] = scalar("float", 8)
        after[path] = row
        signatures[path] = copy.deepcopy(expected)
        for key, value in signatures[path]["properties"].items():
            if value["type"] == "EnumItem" and "name" in value:
                signatures[path]["properties"][key] = {"type": "EnumItem", "value": {"name": value["name"], "enum": "Enum.Material", "value": 0}}
    signatures[f.MAP]["attributes"] |= {"HarvestArtVariant": f.tv("string", variant)}
    after[f.MAP]["properties"]["AttributesSerialize"] = scalar("BinaryString", "01")
    for path in f.HOME_PARTS: after[path]["properties"]["Transparency"] = scalar("float", 1)
    if variant == "B":
        for path in f.BARN_PARTS: after[path]["properties"]["Transparency"] = scalar("float", 1)
    manifest = {"version": 1, "owner": f.OWNER, "baseline_sha256": f.BASELINE_HASH, "catalog_sha256": f.sha256(f.CATALOG), "payload_sha256": f.sha256(f.PAYLOAD), "variant": variant, "nodes": {path: copy.deepcopy(after[path]) for path in specs}}
    return after, signatures, specs, manifest


def validate(after, signatures, specs, variant, manifest, sources=None):
    return f.validate_dom(BEFORE, after, sources or SOURCES, CLASSES, CODE_ADDED, DECLARED, ASSETS, TYPED, signatures, specs, variant, manifest)[0]


rejected = []
for variant in ("A", "B"):
    AFTER, SIGNATURES, SPECS, MANIFEST = build(variant)
    report = validate(AFTER, SIGNATURES, SPECS, variant, MANIFEST)
    assert report["passed"] and report["complete"] and report["total_sources"] == 153
    assert report["new_code_instances"] == 73 and report["new_art_instances"] == 291 and report["new_instances"] == 364
    incomplete = validate(AFTER, SIGNATURES, SPECS, variant, None)
    assert incomplete["passed"] is False and incomplete["complete"] is False and incomplete["requires_independent_world_review"]
    empty_table_signatures = SIGNATURES.copy()
    for path in SPECS:
        empty_table_signatures[path] = SIGNATURES[path] | {"tags": {}}
    validate(AFTER, empty_table_signatures, SPECS, variant, MANIFEST)

    def rejects(name, mutate, typed_mutate=None, manifest_mutate=None, sources=None):
        after = AFTER.copy()
        signatures = SIGNATURES.copy()
        if typed_mutate:
            for path in set(SPECS) | {f.MAP}: signatures[path] = copy.deepcopy(SIGNATURES[path])
        manifest = copy.deepcopy(MANIFEST) if manifest_mutate else MANIFEST
        # Copy-on-write original/new record mutation helper.
        def node(path):
            after[path] = copy.deepcopy(after[path])
            return after[path]
        mutate(after, node)
        if typed_mutate: typed_mutate(signatures)
        if manifest_mutate: manifest_mutate(manifest)
        try:
            validate(after, signatures, SPECS, variant, manifest, sources)
        except (ValueError, KeyError, IndexError, TypeError):
            rejected.append(variant + ":" + name)
            return
        raise AssertionError("Unsafe Harvest save accepted: " + variant + ":" + name)

    for path in sorted(DECLARED | set(CODE_ADDED)):
        rejects(path + " Source", lambda a, n, p=path: n(p)["properties"].__setitem__("Source", scalar("string", "return 'foreign'")))
        rejects(path + " capabilities", lambda a, n, p=path: n(p)["properties"].__setitem__("Capabilities", scalar("SecurityCapabilities", 1)))
    for path in (f.MAP + "/Ground", f.MAP + "/Props/HouseWest", "Lighting", "Lighting/Bloom", "Workspace/Baseplate", "ServerStorage/CornFarmAssets"):
        rejects(path + " identity", lambda a, n, p=path: n(p)["properties"].__setitem__("UniqueId", scalar("UniqueId", "f" * 32)))
        rejects(path + " extra property", lambda a, n, p=path: n(p)["properties"].__setitem__("Unexpected", scalar("bool", "true")))
        rejects(path + " class", lambda a, n, p=path: n(p).__setitem__("class", "Part" if BEFORE[p]["class"] == "Folder" else "Folder"))
    rejects("Original terrain removed", lambda a, n: a.pop("Workspace/Terrain"))
    rejects("Pole hidden", lambda a, n: n(f.MAP + "/Props/ScarecrowMarker/Pole")["properties"].__setitem__("Transparency", scalar("float", 1)))
    rejects("Home not hidden", lambda a, n: n(f.HOME_PARTS[0])["properties"].__setitem__("Transparency", scalar("float", 0)))
    rejects("Home partial opacity", lambda a, n: n(f.HOME_PARTS[1])["properties"].__setitem__("Transparency", scalar("float", 0.9)))
    barn = next(iter(f.BARN_PARTS))
    rejects("Barn wrong variant", lambda a, n: n(barn)["properties"].__setitem__("Transparency", scalar("float", 0 if variant == "B" else 1)))
    rejects("Map foreign attribute", lambda a, n: None, lambda t: t[f.MAP]["attributes"].__setitem__("ForeignGame", f.tv("boolean", True)))
    rejects("Map variant mismatch", lambda a, n: None, lambda t: t[f.MAP]["attributes"].__setitem__("HarvestArtVariant", f.tv("string", "B" if variant == "A" else "A")))
    rejects("New external instance", lambda a, n: a.__setitem__("Workspace/ForeignRemote", copy.deepcopy(MODULE)))
    for path in (f.DECOR, f.HOME, f.DECOR + "/VariantB/GroundSurface", f.DECOR + "/VariantB/RoadSurface/HarvestSurface", next(p for p, s in SPECS.items() if s["class"] == "MeshPart")):
        rejects(path + " missing", lambda a, n, p=path: a.pop(p))
        rejects(path + " new Source", lambda a, n, p=path: n(p)["properties"].__setitem__("Source", scalar("string", "foreign")))
        rejects(path + " child", lambda a, n, p=path: a.__setitem__(p + "/Foreign", copy.deepcopy(MODULE)))
        rejects(path + " ownership", lambda a, n: None, lambda t, p=path: t[p]["attributes"]["corn_project_id"].__setitem__("value", "foreign"))
        rejects(path + " attribute added", lambda a, n: None, lambda t, p=path: t[p]["attributes"].__setitem__("Arbitrary", f.tv("number", 1)))
        rejects(path + " Tags", lambda a, n: None, lambda t, p=path: t[p]["tags"].append("corn_key_slot"))
    part = next(path for path, row in SPECS.items() if row["class"] == "MeshPart")
    rejects("New art collision", lambda a, n: n(part)["properties"].__setitem__("CanQuery", scalar("bool", "true")))
    rejects("New art foreign mesh URI", lambda a, n: n(part)["properties"].__setitem__("MeshContent", ["Content", "", [["uri", ["uri", "rbxassetid://123", []]]]]))
    rejects("New art foreign reference", lambda a, n: n(f.HOME + "/Classic")["properties"].__setitem__("PrimaryPart", ["Ref", f.MAP + "/Ground", []]))
    rejects("New art texture changed", lambda a, n: n(part)["properties"].__setitem__("TextureContent", ["Content", "", [["uri", ["uri", "rbxassetid://123", []]]]]))
    for prop in ("CFrame", "Size", "Transparency", "CanQuery", "Material", "Color"):
        def typed_change(t, prop=prop):
            value = t[part]["properties"][prop]
            if prop in ("CFrame", "Size", "Color"): value["value"][0] += 3
            elif prop == "Material": value["value"]["name"] = "Ice"
            elif prop == "Transparency": value["value"] = 0.4
            else: value["value"] = True
        rejects("New art typed " + prop, lambda a, n: None, typed_change)
    rejects("Frozen world arbitrary physical data", lambda a, n: n(part)["properties"].__setitem__("PhysicsData", scalar("BinaryString", "f0")))
    rejects("Frozen manifest wrong variant", lambda a, n: None, manifest_mutate=lambda m: m.__setitem__("variant", "unknown"))
    rejects("Frozen manifest extra node", lambda a, n: None, manifest_mutate=lambda m: m["nodes"].__setitem__("Workspace/Foreign", MODULE))
    rejects("Frozen manifest schema", lambda a, n: None, manifest_mutate=lambda m: m.__setitem__("candidate_allowlist", True))
    rejects("Duplicate UID", lambda a, n: n(part)["properties"].__setitem__("UniqueId", copy.deepcopy(BEFORE[f.MAP + "/Ground"]["properties"]["UniqueId"])))
    for prop in ("CFrame", "Focus"):
        for invalid in ("nan", "inf", "-inf", "3.4028236e38"):
            def camera(a, n, prop=prop, invalid=invalid): n("Workspace/Camera")["properties"][prop][2][0][1][1] = invalid
            rejects("Camera " + prop + " " + invalid, camera)
        rejects("Camera " + prop + " missing", lambda a, n, prop=prop: n("Workspace/Camera")["properties"][prop][2].pop())
    positive = AFTER.copy()
    for path, text in (SOURCES | ASSETS).items():
        positive[path] = copy.deepcopy(positive[path])
        positive[path]["properties"]["Source"][1] = text.replace("\n", "\r\n")
    validate(positive, SIGNATURES, SPECS, variant, MANIFEST)

a_dom,a_typed,a_specs,a_manifest=build("A")
b_dom,b_typed,b_specs,b_manifest=build("B")
derived,delta=f.derive_variant_b_manifest(a_manifest,TYPED,CATALOG)
assert derived==b_manifest and len(delta)==57
validate(b_dom,b_typed,b_specs,"B",derived)
for bad in ("missing_variant_pattern","duplicate_variant_pattern","wrong_A_visibility"):
    changed=copy.deepcopy(a_manifest)
    prop=changed["nodes"][f.DECOR]["properties"]["AttributesSerialize"]
    if bad=="missing_variant_pattern":prop[1]="00"
    elif bad=="duplicate_variant_pattern":prop[1]+=prop[1]
    else:
        path=next(p for p,s in a_specs.items() if s["class"]=="MeshPart" and s["attributes"]["HarvestBranch"]["value"]=="A")
        changed["nodes"][path]["properties"]["Transparency"][1]="0.7"
    try:f.derive_variant_b_manifest(changed,TYPED,CATALOG)
    except ValueError:rejected.append("A-to-B:"+bad)
    else:raise AssertionError("Unsafe A-to-B manifest derivation accepted: "+bad)

raw = f.r.p.unknown_properties(f.BASELINE)
assert raw["supported"]
terrain_rejected = 0
for mutate in (lambda x: x["properties"].clear(), lambda x: x.__setitem__("supported", False), lambda x: x["properties"][next(iter(x["properties"]))].__setitem__("payload_sha256", "0" * 64)):
    changed = copy.deepcopy(raw)
    mutate(changed)
    try: f.r.validate_unknown(raw, changed)
    except ValueError: terrain_rejected += 1
assert terrain_rejected == 3
print(f"PASS harvest-copy-verifier: both exact A/B contracts, 153 Sources/73 code+291 art additions; {len(rejected)} unsafe DOM/typed/manifest cases, 3 raw Terrain refusals; first-save review remains explicitly incomplete")
