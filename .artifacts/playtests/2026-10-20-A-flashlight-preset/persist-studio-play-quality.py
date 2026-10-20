"""Persist the author's manual maximum Studio Play graphics preference only."""
from pathlib import Path
import hashlib
import json
import os
import tempfile
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[3]
path = Path(os.environ["LOCALAPPDATA"]) / "Roblox/GlobalBasicSettings_13_Studio.xml"
before = path.read_bytes()
before_sha = hashlib.sha256(before).hexdigest()
assert before_sha == "440f7707b8aa1941d76983635634029efbc0299fab6ae2c530ce053b3173b63d", "Studio Play settings changed; preserved"
old = b'<token name="SavedQualityLevel">0</token>'
new = b'<token name="SavedQualityLevel">10</token>'
assert before.count(old) == 1 and new not in before
tree = ET.fromstring(before)
quality = tree.findall(".//Item[@class='UserGameSettings']/Properties/token[@name='SavedQualityLevel']")
assert len(quality) == 1 and quality[0].text == "0"
after = before.replace(old, new)
assert ET.fromstring(after).find(".//Item[@class='UserGameSettings']/Properties/token[@name='SavedQualityLevel']").text == "10"
with tempfile.NamedTemporaryFile(dir=path.parent, prefix="corn-play-quality-", suffix=".tmp", delete=False) as temp:
    temp.write(after)
    replacement = Path(temp.name)
assert path.read_bytes() == before, "Concurrent Studio settings change; preserved"
os.replace(replacement, path)
assert path.read_bytes() == after
report = {"path": str(path), "before_sha256": before_sha,
          "after_sha256": hashlib.sha256(after).hexdigest(),
          "only_changed_property": "UserGameSettings.SavedQualityLevel", "before": 0, "after": 10,
          "other_settings_bytes_exact": True, "Studio_restart_required": True,
          "scope": "Studio-specific settings file only; standalone Roblox player settings untouched."}
(root / ".artifacts/playtests/2026-10-20-A-flashlight-preset/studio-play-quality-file.json").write_text(
    json.dumps(report, indent=2) + "\n", encoding="utf-8")
print(json.dumps(report))
