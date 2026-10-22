"""Prepare isolated C code and guarded native authoring. Never write a scene file."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".artifacts/scene-C/2026-10-22-build"
FILES = {
    "ReplicatedStorage/CornCTestSystem/Data/Grass": ("ModuleScript", "scene-c/data/Grass.luau"),
    "ReplicatedStorage/CornCTestSystem/Data/Center": ("ModuleScript", "scene-c/data/Center.luau"),
    "ReplicatedStorage/CornCTestSystem/Data/End": ("ModuleScript", "scene-c/data/End.luau"),
    "ReplicatedStorage/CornCTestSystem/Data/Skirt": ("ModuleScript", "scene-c/data/Skirt.luau"),
    "ReplicatedStorage/CornCTestSystem/Geometry": ("ModuleScript", "scene-c/geometry/Geometry.luau"),
    "ReplicatedStorage/CornCTestSystem/Layout": ("ModuleScript", "scene-c/runtime/Layout.luau"),
    "ReplicatedStorage/CornCTestSystem/Scene": ("ModuleScript", "scene-c/runtime/Scene.luau"),
    "ServerScriptService/CornCTestBootstrap": ("Script", "scene-c/runtime/Bootstrap.server.luau"),
    "StarterPlayer/StarterPlayerScripts/CornCTestBootstrap": ("LocalScript", "scene-c/runtime/Bootstrap.client.luau"),
}


def build():
    sources = {}
    for path, (cls, file) in FILES.items():
        text = (ROOT / file).read_text(encoding="utf-8").replace("\r\n", "\n")
        assert 0 < len(text.encode()) < 200000 and "\x00" not in text
        sources[path] = {"class": cls, "file": file, "source": text,
                         "sha256": hashlib.sha256(text.encode()).hexdigest()}
    payload = {"owner": "children_of_corn_C_test", "version": 1, "sources": sources}
    OUT.mkdir(parents=True, exist_ok=True)
    raw = json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n"
    (OUT / "payload.json").write_text(raw, encoding="utf-8", newline="\n")
    manifest = {"owner": payload["owner"], "payload_sha256": hashlib.sha256(raw.encode()).hexdigest(),
                "sources": {p: {k: row[k] for k in ("class", "file", "sha256")} for p, row in sources.items()},
                "layout_counts": {"Corn": 288, "Center": 2, "End": 4, "Skirt": 6, "Grass": 68},
                "native_installation": "pending verified empty Children_of_corn_C.rbxl Edit",
                "scene_file_written": False, "AB_mappings_or_sources_written": False}
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    tree = {"$className": "DataModel", "$ignoreUnknownInstances": True}
    classes = {"ReplicatedStorage": "ReplicatedStorage", "ServerScriptService": "ServerScriptService",
               "StarterPlayer": "StarterPlayer", "StarterPlayer/StarterPlayerScripts": "StarterPlayerScripts",
               "ReplicatedStorage/CornCTestSystem": "Folder", "ReplicatedStorage/CornCTestSystem/Data": "Folder"}
    for path in sorted(set(classes) | set(sources), key=lambda p: (p.count("/"), p)):
        node = tree
        for component in path.split("/"):
            node = node.setdefault(component, {})
        node["$ignoreUnknownInstances"] = True
        if path in sources:
            node["$path"] = sources[path]["file"]
        else:
            node["$className"] = classes[path]
    project = {"name": "ChildrenOfCorn_C_CodeOnly", "servePlaceIds": [], "serveAddress": "127.0.0.1",
               "servePort": 34875, "emitLegacyScripts": True, "tree": tree}
    (ROOT / "C-code.project.json").write_text(json.dumps(project, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"sources": len(sources), "payload_bytes": len(raw.encode()),
                      "payload_sha256": manifest["payload_sha256"], "source_max_bytes": max(len(r["source"].encode()) for r in sources.values()),
                      "native_status": manifest["native_installation"]}))


if __name__ == "__main__":
    build()
