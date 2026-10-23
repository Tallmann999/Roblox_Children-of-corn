"""Add only the four B corn shape Sources to the explicit code-only mapping."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
NEW = {
    "ReplicatedStorage/GameShared/Game/CornGreenGeometry": "variants/B/shared/Game/CornGreenGeometry.luau",
    **{f"ReplicatedStorage/GameShared/Game/CornGreenGeometryData/Var{i:02}":
       f"variants/B/shared/Game/CornGreenGeometryData/Var{i:02}.luau" for i in range(1, 4)},
}


def prepare():
    path = ROOT / "rojo/source-map.json"
    manifest = json.loads(path.read_text(encoding="utf-8"))
    a_before = json.dumps(manifest["variants"]["A"], sort_keys=True)
    b = manifest["variants"]["B"]
    assert len(b["sources"]) in (160, 164)
    for code_path, file in NEW.items():
        b["sources"][code_path] = {"class": "ModuleScript", "file": file}
        b["classes"][code_path] = "ModuleScript"
    b["classes"]["ReplicatedStorage/GameShared/Game/CornGreenGeometryData"] = "Folder"
    for row in b["sources"].values():
        row["baseline_sha256"] = hashlib.sha256((ROOT / row["file"]).read_text(encoding="utf-8").replace("\r\n", "\n").encode()).hexdigest()
    baseline = json.loads((ROOT / ".artifacts/playtests/2026-10-23-B-green-variants/baseline.json").read_text())
    scene = ROOT / b["scene"]
    assert hashlib.sha256(scene.read_bytes()).hexdigest() == baseline["baseline_B_sha256"]
    b["scene_bytes"] = baseline["baseline_B_bytes"]
    b["scene_sha256"] = baseline["baseline_B_sha256"]
    assert json.dumps(manifest["variants"]["A"], sort_keys=True) == a_before
    path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"B_owned_sources": len(b["sources"]), "B_code_classes": len(b["classes"]), "A_mapping_unchanged": True}))


if __name__ == "__main__":
    prepare()
