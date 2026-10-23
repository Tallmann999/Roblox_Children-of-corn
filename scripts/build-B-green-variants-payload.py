"""Freeze the three reviewed B edits and four new corn geometry Sources."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".artifacts/playtests/2026-10-23-B-green-variants"


def build():
    before = json.loads((OUT / "expected-before-sources.json").read_text())
    manifest = json.loads((ROOT / "rojo/source-map.json").read_text())
    changes, additions = {}, {}
    for path, row in manifest["variants"]["B"]["sources"].items():
        source = (ROOT / row["file"]).read_text(encoding="utf-8").replace("\r\n", "\n")
        digest = hashlib.sha256(source.encode()).hexdigest()
        assert digest == row["baseline_sha256"]
        if path in before and digest != before[path]["sha256"]:
            changes[path] = {"before_sha256": before[path]["sha256"], "after_sha256": digest, "source": source}
        elif path not in before:
            additions[path] = {"class": row["class"], "sha256": digest, "source": source}
    assert len(before) == 163 and len(changes) == 3 and len(additions) == 4
    assert set(changes) == {"ReplicatedStorage/GameShared/Game/CornAppearance", "ReplicatedStorage/GameShared/Game/CornLayout",
                            "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornWindController"}
    value = {"owner": "corn_B_green_variants_v1", "sources": before, "sourceChanges": changes, "newSources": additions}
    raw = (json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n").encode()
    digest = hashlib.sha256(raw).hexdigest()
    with (OUT / "payload.json").open("xb") as file:
        file.write(raw)
    info = {"payload_sha256": digest, "payload_bytes": len(raw), "old_sources": 163,
            "replacements": list(changes), "additions": list(additions), "total_sources": 167}
    (OUT / "payload-info.json").write_text(json.dumps(info, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps(info))


if __name__ == "__main__":
    build()
