"""Build a reviewable local plugin; --install alone opts in to a guarded copy."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
NAME = "CornManualSceneEditor"
SOURCE = ROOT / "studio-plugins" / f"{NAME}.luau"
REVIEWED_SOURCE_SHA256 = "4ea93c8a058645128d4b3ba86d08353bd706f28538f62c5ef48a555582625819"


def digest(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def build_payload(source: bytes) -> tuple[bytes, str]:
    if digest(source) != REVIEWED_SOURCE_SHA256:
        raise RuntimeError("Manual editor source differs from the reviewed SHA256")
    core = source.decode("utf-8")
    entry = """-- Local Corn manual scene editor. Exact stopped B only.
local createEditor = (function()
""" + core + """
end)()
local run = game:GetService("RunService")
createEditor({
    game = game, run = run, plugin = plugin,
    heartbeat = run.Heartbeat, defer = task.defer, require = require,
    selection = game:GetService("Selection"), warn = warn,
    notice = function() print("[CornManualSceneEditor] Сцена обновлена из существующих объектов") end,
})
"""
    xml = ET.Element("roblox", version="4")
    item = ET.SubElement(xml, "Item", {"class": "Script", "referent": "RBXCornManualSceneEditor"})
    properties = ET.SubElement(item, "Properties")
    ET.SubElement(properties, "string", name="Name").text = NAME
    ET.SubElement(properties, "ProtectedString", name="Source").text = entry
    ET.SubElement(properties, "bool", name="Disabled").text = "false"
    return ET.tostring(xml, encoding="utf-8", xml_declaration=True), entry


def install_payload(payload: bytes, plugin_dir: Path) -> dict:
    if not plugin_dir.is_dir():
        raise RuntimeError("Expected an existing local Studio Plugins directory")
    plugin_dir = plugin_dir.resolve()
    target = plugin_dir / f"{NAME}.rbxmx"
    if target.resolve().parent != plugin_dir:
        raise RuntimeError("Plugin destination escaped the expected directory")
    existed = target.exists()
    if existed:
        if target.is_symlink() or not target.is_file() or digest(target.read_bytes()) != digest(payload):
            raise RuntimeError("Unknown existing manual editor plugin; refusing overwrite")
    else:
        with target.open("xb") as stream:
            stream.write(payload)
    if target.read_bytes() != payload:
        raise RuntimeError("Installed plugin bytes differ")
    return {"target": str(target), "created": not existed, "sha256": digest(payload)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--install", action="store_true", help="Install the reviewed artifact into the existing local Roblox Plugins directory")
    args = parser.parse_args()
    source = SOURCE.read_bytes()
    payload, entry = build_payload(source)
    output = ROOT / "studio-plugins" / f"{NAME}.rbxmx"
    output.write_bytes(payload)
    output.with_suffix(".plugin.luau").write_text(entry, encoding="utf-8", newline="\n")
    report = {
        "artifact": str(output), "sha256": digest(payload), "bytes": len(payload),
        "source_sha256": digest(source), "installed": False,
        "scope": "Exact Children_of_corn_B.rbxl, stopped Studio, manual B version 1",
        "network": False, "scene_save": False, "layout_rebuild": False,
        "other_plugins_changed": False,
    }
    if args.install:
        local_data = os.environ.get("LOCALAPPDATA")
        if not local_data:
            raise RuntimeError("LOCALAPPDATA is required only for --install")
        report["installation"] = install_payload(payload, Path(local_data) / "Roblox" / "Plugins")
        report["installed"] = True
    output.with_suffix(".manifest.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
