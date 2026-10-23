"""Freeze exact verified Blender data and generate B-only runtime modules.
Does not modify FBX, blend, original source files, A, existing Sources or Studio.
"""
import hashlib,json,math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
OUT=Path(__file__).resolve().parent
DEST=ROOT/"variants/B/shared/Game/CornGreenGeometryData"
report=json.loads((OUT/"build-report.json").read_text(encoding="utf-8"))
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
DEST.mkdir(parents=True,exist_ok=True)
manifest={"version":1,"source_sha256":report["source_sha256"],"texture_sha256":report["texture_sha256"],
    "blend":report["blend"],"runtime_coordinate_contract":{
        "positions":"bbox-centred Roblox studs at nominal height 8; [Blender x, z, -y]",
        "root_offset_studs":"actual bottom stem root minus bbox centre",
        "bbox_center_from_root_studs":"bbox centre minus actual bottom stem root",
        "placement":"root*yaw*CFrame.new(bbox_center_from_root.X,bbox_center_from_root.Y*actualHeight/8,bbox_center_from_root.Z)",
        "uvs":"original palette U, 1-original V; no unwrap",
        "normals":"source custom corner normals transformed by deformation inverse-transpose Jacobian and proper [x,z,-y] rotation",
        "corner_colors":"original non-albedo authoring masks preserved for provenance; do not multiply into green BaseColor"},
    "assets":[],"checks":0}
for record in report["runtime_data"]:
    path=Path(record["runtime_json"])
    data=json.loads(path.read_text(encoding="utf-8"))
    data["original_source_sha256"]=report["source_sha256"]
    if record["key"]!="Original":
        fbx=ROOT/(record["name"]+".fbx")
        assert sha(fbx)==record["fbx"]["sha256"],"Exported FBX changed"
        data["exported_fbx_sha256"]=sha(fbx)
        assert record["roundtrip"]["corner_comparison"]["pass"]
    assert len(data["positions"])==377 and len(data["triangles"])==510
    assert len(data["triangle_uvs"])==len(data["triangle_normals"])==510
    size=data["bounds"]["size"];center=data["bbox_center_from_root_studs"];root=data["root_offset_studs"]
    assert abs(size[1]-8)<1e-6 and all(abs(a+b)<1e-6 for a,b in zip(center,root))
    for position in data["positions"]:
        assert all(math.isfinite(v) for v in position);manifest["checks"]+=3
        assert all(abs(v)<=extent/2+2e-5 for v,extent in zip(position,size))
    for triangle,uvs,normals in zip(data["triangles"],data["triangle_uvs"],data["triangle_normals"]):
        assert all(1<=index<=377 for index in triangle)
        assert all(1<=index<=len(data["uvs"]) for index in uvs)
        assert all(1<=index<=len(data["normals"]) for index in normals)
        manifest["checks"]+=9
    assert all(abs(sum(v*v for v in normal)-1)<2e-5 for normal in data["normals"])
    assert all(-1e-6<=v<=1+1e-6 for uv in data["uvs"] for v in uv)
    # Metadata addition changes no geometry/UV/normal channels.
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding="utf-8")
    record["runtime_sha256"]=sha(path)
    info={key:record[key] for key in ["key","name","vertices","triangles","dimensions_m","height_studs",
        "runtime_json","runtime_sha256","root_offset_studs","bbox_center_from_root_studs","bounds_studs",
        "envelope_from_root_studs","qa_geometry_pass"]}
    if record["key"]!="Original":
        info["fbx"]=record["fbx"];info["roundtrip"]=record["roundtrip"]
        compact=json.dumps(data,ensure_ascii=True,separators=(",",":"))
        module=("-- Verified Blender original-green-corn shape "+data["key"]+"; preserve palette UVs.\n"
            "-- Original FBX "+data["original_source_sha256"]+"; exported FBX "+data["exported_fbx_sha256"]+".\n"
            "return game:GetService(\"HttpService\"):JSONDecode([==[\n"+compact+"\n]==])\n")
        module_path=DEST/(record["key"]+".luau")
        module_path.write_text(module,encoding="utf-8",newline="\n")
        info["module"]=str(module_path);info["module_bytes"]=module_path.stat().st_size;info["module_sha256"]=sha(module_path)
    manifest["assets"].append(info)
report["source_unchanged"]=sha(Path(report["source"]))==report["source_sha256"]
assert report["source_unchanged"] and sha(ROOT/"assets/corn/01_roblax_style.png")==report["texture_sha256"]
(OUT/"build-report.json").write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
manifest["source_unchanged"]=True
manifest["geometry_QA_pass"]=all(item["qa_geometry_pass"] for item in manifest["assets"])
(OUT/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
print(json.dumps({"pass":True,"checks":manifest["checks"],"assets":[{k:a[k] for k in ["key","runtime_sha256","bounds_studs","root_offset_studs"]} for a in manifest["assets"]],"modules":[{"file":a["module"],"bytes":a["module_bytes"],"sha256":a["module_sha256"]} for a in manifest["assets"] if "module" in a]}))
