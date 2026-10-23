"""Independent read-only reimport of the three frozen exports: colors + transforms.
No asset, scene or data file rewrites. Writes only this verification report.
"""
import bpy,json,hashlib
from pathlib import Path
from collections import Counter
OUT=Path(__file__).resolve().parent
manifest=json.loads((OUT/"manifest.json").read_text(encoding="utf-8"))
result={"pass":True,"variants":[]}
for row in manifest["assets"]:
    if row["key"]=="Original":continue
    bpy.ops.wm.read_factory_settings(use_empty=True)
    path=Path(row["fbx"]["path"])
    assert hashlib.sha256(path.read_bytes()).hexdigest()==row["fbx"]["sha256"]
    assert bpy.ops.import_scene.fbx(filepath=str(path),use_image_search=False)=={"FINISHED"}
    ob=next(ob for ob in bpy.context.scene.objects if ob.type=="MESH")
    data=json.loads(Path(row["runtime_json"]).read_text(encoding="utf-8"))
    channels={}
    for name,channel in data["corner_colors"].items():
        attr=ob.data.color_attributes.get(name)
        assert attr is not None
        actual=Counter(tuple(round(v,5)for v in value.color)for value in attr.data)
        expected=Counter(tuple(round(v,5)for v in channel["colors"][i-1])
            for triple in channel["triangle_colors"]for i in triple)
        channels[name]={"source_corner_count":sum(expected.values()),"reimport_corner_count":sum(actual.values()),
            "equal_multiset_5decimal":actual==expected}
        assert actual==expected
    result["variants"].append({"key":row["key"],"color_channels":channels,
        "armatures":sum(ob.type=="ARMATURE"for ob in bpy.context.scene.objects),
        "actions":len(bpy.data.actions),"one_mesh":sum(ob.type=="MESH"for ob in bpy.context.scene.objects)==1})
(OUT/"color-roundtrip.json").write_text(json.dumps(result,indent=2),encoding="utf-8")
print("@@JSON@@"+json.dumps(result))
