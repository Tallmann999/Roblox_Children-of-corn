"""Build the guarded, code-only variant-A black-night installer.

Only two existing Sources may change. The accepted Harvest payload and both
saved A/B scenes are read-only; the exact A backup is created exclusively once.
No Studio connection, HTTP setting, live Rojo or scene serialization is used.
"""
from __future__ import annotations
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCE_A = ROOT / "place/Children_of_corn.rbxl"
BASELINE = ROOT / "place/Children_of_corn.before-black-night-20261020.rbxl"
BASELINE_SHA = "2672483f1313180152856e82b971a98f6f2b784639778a7ee6cff9d546050a11"
BASELINE_BYTES = 1485712
ACCEPTED_PAYLOAD = ROOT / ".artifacts/harvest-install/payload.json"
ACCEPTED_PAYLOAD_SHA = "0ab19ed60dd76e3440e1b08489092bc19b3bdb5e239de17723cdd0a743d491ec"
OUT = ROOT / ".artifacts/playtests/2026-10-20-black-night"
ALLOWED_CHANGED = frozenset({
    "ReplicatedStorage/GameShared/Game/LightingModes",
    "ReplicatedStorage/GameShared/Game/HarvestWardenVisual",
})
OWNER = "corn_black_night_20261020"
spec = importlib.util.spec_from_file_location("black_night_harvest_builder", ROOT / "scripts/build-harvest-installer.py")
harvest = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harvest)
require, sha, compact = harvest.require, harvest.sha, harvest.compact


def accepted_payload():
    require(sha(ACCEPTED_PAYLOAD.read_bytes()) == ACCEPTED_PAYLOAD_SHA, "Accepted Harvest payload changed")
    payload = json.loads(ACCEPTED_PAYLOAD.read_bytes())
    require(payload["owner"] == "harvest_warden_v1" and len(payload["entries"]) == 153, "Unexpected accepted 153-Source payload")
    return payload


def ensure_baseline():
    if not BASELINE.exists():
        raw = SOURCE_A.read_bytes()
        require(len(raw) == BASELINE_BYTES and sha(raw) == BASELINE_SHA, "Working A no longer equals accepted pre-night bytes; cannot create baseline")
        with BASELINE.open("xb") as output:
            output.write(raw)
    require(BASELINE.stat().st_size == BASELINE_BYTES and sha(BASELINE.read_bytes()) == BASELINE_SHA, "Immutable pre-night A baseline changed")


def mapping():
    accepted = accepted_payload()
    sources, classes = harvest.current_mapping()
    old = {row["path"]: row for row in accepted["entries"]}
    require(len(old) == 153 and len(sources) == 150 and classes == accepted["classes"], "Unexpected persistent code topology; no additions permitted")
    require(set(sources) == {path for path in old if harvest.owned(path)}, "Unexpected configured Source set")
    changed = {path for path, source in sources.items() if sha(source.encode()) != old[path]["after"]}
    require(changed == ALLOWED_CHANGED, "Expected exactly LightingModes and HarvestWardenVisual changes: " + str(sorted(changed)))
    return accepted, sources, classes, changed


def payload_data():
    accepted, sources, classes, changed = mapping()
    entries = []
    for previous in accepted["entries"]:
        path = previous["path"]
        source = sources.get(path)
        after = sha(source.encode()) if source is not None else previous["after"]
        row = {"path": path, "class": previous["class"], "before": previous["after"], "after": after}
        if path in changed:
            row["source"] = source
        entries.append(row)
    return {"version": 1, "owner": OWNER, "baselineSha256": BASELINE_SHA,
            "roots": list(harvest.ROOTS), "beforeClasses": classes, "classes": classes,
            "addedNodes": [], "entries": entries}


def installer_core(payload_sha):
    core = harvest.CORE.replace("Harvest", "Black-night").replace("Corn Black-night art code", "Corn black-night code")
    core = core.replace('payload.owner == "harvest_warden_v1"', 'payload.owner == "' + OWNER + '"')
    core = core.replace('if baseline then 80 else #payload.entries', 'if baseline then 153 else #payload.entries')
    assertion = 'assert(map:GetAttribute("HarvestArtVariant") == "A", "Black night is scoped to variant A; nothing changed")\n'
    needle = 'local ground, field = map:FindFirstChild("Ground"), map:FindFirstChild("FieldZone")'
    require(core.count(needle) == 1 and core.count('if baseline then 153 else #payload.entries') == 1, "Harvest core guard shape changed")
    core = core.replace(needle, assertion + needle)
    return core.replace("@PAYLOAD_SHA@", payload_sha).replace("@BASELINE_SHA@", BASELINE_SHA)


def build():
    ensure_baseline()
    accepted = accepted_payload()
    result = subprocess.run([str(ROOT / ".tools/lune/lune.exe"), "run",
        str(ROOT / ".artifacts/harvest-install/read-baseline.luau"), str(BASELINE)],
        cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    actual = json.loads(result.stdout)
    expected = {row["path"]: {"class": row["class"], "sha256": row["after"]} for row in accepted["entries"]}
    require({path: {"class": row["class"], "sha256": row["sha256"]} for path, row in actual["sources"].items()} == expected,
            "Immutable pre-night Sources differ from accepted Harvest payload")
    require(actual["classes"] == accepted["classes"], "Immutable pre-night classes differ")
    payload = payload_data()
    raw = compact(payload)
    digest = sha(raw)
    core = installer_core(digest)
    equals = "=="
    while ("]" + equals + "]").encode() in raw:
        equals += "="
    installer = "-- Generated guarded two-Source black-night update; stopped variant A only.\nlocal raw = [" + equals + "[" + raw.decode() + "]" + equals + "]\n" + core
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "payload.json").write_bytes(raw)
    target = ROOT / "scripts/install-black-night.luau"
    target.write_text(installer, encoding="utf-8", newline="\n")
    manifest = {"version": 1, "owner": OWNER, "baseline_sha256": BASELINE_SHA,
        "accepted_harvest_payload_sha256": ACCEPTED_PAYLOAD_SHA, "baseline_sources": 153,
        "final_sources": 153, "project_sources": 150, "new_nodes": 0,
        "changed_existing": sorted(ALLOWED_CHANGED), "payload_bytes": len(raw), "payload_sha256": digest,
        "installer_bytes": len(installer.encode()), "installer_sha256": sha(target.read_bytes()),
        "source_only": True, "scene_written": False, "variant": "A"}
    (OUT / "pipeline-manifest.json").write_bytes(compact(manifest) + b"\n")
    require(sha(BASELINE.read_bytes()) == BASELINE_SHA and sha(ACCEPTED_PAYLOAD.read_bytes()) == ACCEPTED_PAYLOAD_SHA,
            "Immutable input changed during build")
    print(json.dumps(manifest, ensure_ascii=False))
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compact", action="store_true", help="Installer always embeds compact, hash-guarded JSON")
    parser.parse_args()
    build()
