"""Persist only the requested Studio rendering quality; preserve all other bytes."""
from pathlib import Path
import hashlib
import json
import os
import tempfile
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[3]
path = Path(os.environ["LOCALAPPDATA"]) / "Roblox/GlobalSettings_13.xml"
before = path.read_bytes()
before_sha = hashlib.sha256(before).hexdigest()
assert before_sha == "833625510fee1924e37893f66bb9115a78edfd3b620db7a0ad7ee96efcf3e2d3", "Studio settings changed; preserved"
old, new = b'<token name="QualityLevel">0</token>', b'<token name="QualityLevel">21</token>'
assert before.count(old) == 1 and new not in before
tree = ET.fromstring(before)
render = tree.findall(".//Item[@class='RenderSettings']/Properties/token[@name='QualityLevel']")
assert len(render) == 1 and render[0].text == "0"
after = before.replace(old, new)
updated = ET.fromstring(after)
assert updated.find(".//Item[@class='RenderSettings']/Properties/token[@name='QualityLevel']").text == "21"
with tempfile.NamedTemporaryFile(dir=path.parent, prefix="corn-quality-", suffix=".tmp", delete=False) as temp:
    temp.write(after)
    replacement = Path(temp.name)
assert path.read_bytes() == before, "Concurrent Studio settings change; preserved"
os.replace(replacement, path)
assert path.read_bytes() == after
report = {"path": str(path), "before_sha256": before_sha,
          "after_sha256": hashlib.sha256(after).hexdigest(),
          "only_changed_property": "RenderSettings.QualityLevel", "before": 0, "after": 21,
          "other_settings_bytes_exact": True}
(root / ".artifacts/playtests/2026-10-20-A-flashlight-preset/studio-quality-file.json").write_text(
    json.dumps(report, indent=2) + "\n", encoding="utf-8")
print(json.dumps(report))
