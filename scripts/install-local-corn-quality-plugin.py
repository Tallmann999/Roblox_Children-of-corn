"""Install only the reviewed Corn local Studio plugin; leave all others untouched."""
from pathlib import Path
import hashlib
import json
import os

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = "5b25f94bd58ee116c65f345e7a7f931407fe016560d952ece41effb288babf43"
source = ROOT / "studio-plugins/CornStudioQuality21.rbxmx"
payload = source.read_bytes()
assert hashlib.sha256(payload).hexdigest() == EXPECTED, "Unreviewed plugin bytes"
plugin_dir = Path(os.environ["LOCALAPPDATA"]) / "Roblox/Plugins"
assert plugin_dir.is_dir(), "Expected existing local Studio plugins directory"
target = plugin_dir / source.name
assert target.resolve().parent == plugin_dir.resolve(), "Unexpected destination"
existed = target.exists()
if existed:
    assert target.read_bytes() == payload, "Unknown existing plugin; refusing overwrite"
else:
    with target.open("xb") as stream:
        stream.write(payload)
assert target.read_bytes() == payload, "Installed bytes differ"
report = {"target": str(target), "sha256": EXPECTED, "bytes": len(payload),
          "created": not existed, "other_plugins_changed": False,
          "scenes_changed": False, "game_sources_changed": False}
evidence = ROOT / ".artifacts/playtests/2026-10-20-studio-quality-lock"
evidence.mkdir(parents=True, exist_ok=True)
(evidence / "install.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
print(json.dumps(report))
