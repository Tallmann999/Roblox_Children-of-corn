"""Build a local Studio plugin model, never a game/place or cloud asset."""
from pathlib import Path
import hashlib
import json
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
core = (root / "studio-plugins/CornStudioQualityGuard.luau").read_text(encoding="utf-8")
entry = """-- Corn Studio Quality21. Local authoring plugin; owned A/B files only.
local createGuard = (function()
""" + core + """
end)()
local guard = createGuard({
    game = game, render = settings().Rendering,
    level = Enum.QualityLevel.Level21, defer = task.defer,
    heartbeat = game:GetService("RunService").Heartbeat,
    groundSize = Vector3.new(630, 2, 630), fieldSize = Vector3.new(630, 10, 630),
    notice = function() print("[CornStudioQuality21] Corn A/B: fixed Studio render quality21") end,
})
plugin.Unloading:Connect(function() guard.Destroy() end)
"""
xml = ET.Element("roblox", version="4")
item = ET.SubElement(xml, "Item", {"class": "Script", "referent": "RBXCornStudioQuality21"})
properties = ET.SubElement(item, "Properties")
ET.SubElement(properties, "string", name="Name").text = "CornStudioQuality21"
ET.SubElement(properties, "ProtectedString", name="Source").text = entry
ET.SubElement(properties, "bool", name="Disabled").text = "false"
result = ET.tostring(xml, encoding="utf-8", xml_declaration=True)
output = root / "studio-plugins/CornStudioQuality21.rbxmx"
output.write_bytes(result)
(root / "studio-plugins/CornStudioQuality21.plugin.luau").write_text(entry, encoding="utf-8", newline="\n")
manifest = {"plugin": output.name, "plugin_sha256": hashlib.sha256(result).hexdigest(),
            "source_sha256": hashlib.sha256(entry.encode()).hexdigest(), "bytes": len(result),
            "scope": "Local Studio rendering preferences for owned Corn A/B only",
            "game_sources_changed": False, "scenes_changed": False, "network": False}
(root / "studio-plugins/manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print(json.dumps(manifest))
