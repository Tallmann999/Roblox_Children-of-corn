"""Build the closed 8-replacement/3-addition B Source payload; no scene I/O."""
from __future__ import annotations

import hashlib
import argparse
import importlib.util
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".artifacts/playtests/2026-10-23-B-manual-authoring"
BASELINE = "c91efe74d1750095eac19390800192ad03b264d7a99de46cf21d170fcb4ed31f"
BASELINE_JSON_SHA = "a7cb6a167ca90a8d4cf993eaa49063f447d5f97143e88fbad8e90fd441345210"
CHANGED = {
    "ReplicatedStorage/GameShared/Game/CornLayout": "variants/B/shared/Game/CornLayout.luau",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornController": "variants/B/client/Controllers/CornController.luau",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornBackdropController": "variants/B/client/Controllers/CornBackdropController.luau",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/GreenBedController": "variants/B/client/Controllers/GreenBedController.luau",
    "ServerScriptService/GameServer/Game/InventoryWorld": "variants/B/server/Game/InventoryWorld.luau",
    "ServerScriptService/GameServer/Game/HarvestWorld": "variants/B/server/Game/HarvestWorld.luau",
    "ServerScriptService/GameServer/Game/RoundAudio": "variants/B/server/Game/RoundAudio.luau",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/HarvestGeometryController": "variants/B/client/Controllers/HarvestGeometryController.luau",
}
ADDED = {
    "ReplicatedStorage/GameShared/Game/ManualScene": "variants/B/shared/Game/ManualScene.luau",
    "ServerScriptService/GameServer/Services/ManualSceneService": "variants/B/server/Services/ManualSceneService.luau",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/AuthoringCornController": "variants/B/client/Controllers/AuthoringCornController.luau",
}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def normalized_source(file):
    text = file.read_bytes().decode("utf-8").replace("\r\n", "\n").replace("\r", "\n")
    assert text.strip() and "\x00" not in text and not text.startswith("\ufeff"), f"Invalid Source: {file}"
    return text


def make_payload(manifest, before, read_source=normalized_source):
    """Pure closed-graph validation except caller-provided Source reads."""
    assert len(before) == 168 and not set(ADDED) & set(before), "Exact 168-before Source set required"
    owned = manifest["variants"]["B"]["sources"]
    unmanaged = manifest["unmanaged_sources"]
    assert len(owned) == 168 and len(unmanaged) == 3, "Current explicit B graph must be 168 owned + 3 Fog"
    assert set(owned) | set(unmanaged) == set(before) | set(ADDED), "Unexpected/missing Source graph"
    assert not set(owned) & set(unmanaged), "Fog cannot be mapped by Rojo"
    for path, entry in unmanaged.items():
        assert before[path] == entry, f"Unmanaged Fog changed: {path}"
    changed, added, read = {}, {}, {}
    for path, entry in owned.items():
        file = ROOT / entry["file"]
        assert file.resolve().is_relative_to(ROOT.resolve()) and file.suffix == ".luau", "Unsafe Source path"
        source = read_source(file)
        read[file] = source
        digest = sha(source.encode())
        if path in ADDED:
            assert entry["file"] == ADDED[path] and entry["class"] == "ModuleScript", "Noncanonical new Source"
            added[path] = {"class": "ModuleScript", "file": entry["file"], "sha256": digest, "source": source}
        else:
            old = before[path]
            assert entry["class"] == old["class"], f"Retained Source class changed: {path}"
            if path in CHANGED:
                assert entry["file"] == CHANGED[path] and entry["class"] == "ModuleScript", "Noncanonical replacement"
                assert digest != old["sha256"], f"Reviewed replacement is unchanged: {path}"
                changed[path] = {"class": entry["class"], "file": entry["file"], "beforeSha256": old["sha256"],
                                 "sha256": digest, "source": source}
            else:
                assert digest == old["sha256"], f"Unreviewed retained Source edit: {path}"
    assert set(changed) == set(CHANGED) and set(added) == set(ADDED), "Closed change set differs"
    payload = {"version": 1, "owner": "CornBManualAuthoringV1", "variant": "B", "baselineSha256": BASELINE,
               "beforeSourceCount": 168, "afterSourceCount": 171, "expectedBeforeSources": before,
               "sourceChanges": changed, "newSources": added}
    return payload, read


def main(output=None):
    baseline_raw = (OUT / "baseline.json").read_bytes()
    assert sha(baseline_raw) == BASELINE_JSON_SHA, "Frozen baseline JSON changed"
    baseline = json.loads(baseline_raw)
    assert baseline["scene_files"]["B"]["sha256"] == BASELINE
    before = json.loads((OUT / "expected-before-sources.json").read_text())
    assert before == {p: {"class": e["class"], "sha256": e["sha256"]}
                      for p, e in baseline["expected_sources"].items()}, "Frozen Source guard changed"
    manifest_path = ROOT / "rojo/source-map.json"
    manifest = json.loads(manifest_path.read_text())
    assert manifest["variants"]["B"]["scene_sha256"] == BASELINE, "Premature saved B hash promotion"
    assert manifest["variants"]["B"]["scene_bytes"] == 1759554
    spec = importlib.util.spec_from_file_location("manual_rojo", ROOT / "scripts/rojo-ab.py")
    rojo = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(rojo)
    rojo.validate_projects()
    payload, reads = make_payload(manifest, before)
    raw = (json.dumps(payload, indent=2, ensure_ascii=False, sort_keys=True) + "\n").encode()
    target = (output or (OUT / "payload.json")).resolve()
    assert target.parent == OUT.resolve() and target.name.startswith("payload") and target.suffix == ".json", "Payload must remain a separate payload*.json in this task's evidence"
    assert not target.exists() or target.read_bytes() == raw, "Frozen payload exists with different Source bytes"
    # Only new-module metadata acquires its first reviewed Source baseline.
    # Every existing entry and the author-saved scene pins remain untouched.
    for path, entry in payload["newSources"].items():
        manifest["variants"]["B"]["sources"][path]["baseline_sha256"] = entry["sha256"]
    for file, text in reads.items():
        assert normalized_source(file) == text, f"Source changed during payload freeze: {file}"
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    if not target.exists():
        with target.open("xb") as stream:
            stream.write(raw)
    report = {"passed": True, "owner": payload["owner"], "baseline_sha256": BASELINE,
              "payload_file": str(target.relative_to(ROOT)).replace("\\", "/"),
              "payload_bytes": len(raw), "payload_sha256": sha(raw), "before_sources": 168,
              "unchanged_sources": 160, "changed_sources": 8, "new_sources": 3, "after_sources": 171,
              "new_source_pins": {p: e["sha256"] for p, e in payload["newSources"].items()},
              "scope": "Source files and JSON metadata only; no Studio or scene I/O."}
    target.with_name(target.stem + "-info.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="New immutable payload revision in this task's evidence folder")
    main(parser.parse_args().output)
