"""Guarded A-only directional surface-light Source update; no HTTP or world writes.

Only FlashlightController, FlashlightPresentation and RoundText may change. The accepted
155-Source flashlight payload, immutable A backup and older pipelines are read-only.
"""
from __future__ import annotations
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / "place/Children_of_corn.before-flashlight-directional-20261020.rbxl"
BASELINE_SHA = "001a0e52bf8b76b8f40c2a8ef31509e287b720d043a42dd2888890b56b3a50d6"
BASELINE_BYTES = 1487543
ACCEPTED_PAYLOAD = ROOT / ".artifacts/playtests/2026-10-20-flashlight/payload.json"
ACCEPTED_PAYLOAD_SHA = "de2f8be0cd7c78d6076011714e54063c647c1311335a8ad00d53bcdc141e9c96"
OUT = ROOT / ".artifacts/playtests/2026-10-20-flashlight-directional"
OWNER = "corn_flashlight_directional_20261020"
ALLOWED_CHANGED = frozenset({
    "ReplicatedStorage/GameShared/Game/FlashlightPresentation",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/FlashlightController",
    "ReplicatedStorage/GameShared/Game/RoundText",
})
spec = importlib.util.spec_from_file_location("flashlight_directional_harvest_builder", ROOT / "scripts/build-harvest-installer.py")
harvest = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harvest)
require, sha, compact = harvest.require, harvest.sha, harvest.compact


def require_baseline():
    require(BASELINE.is_file() and BASELINE.stat().st_size == BASELINE_BYTES
            and sha(BASELINE.read_bytes()) == BASELINE_SHA, "Exact immutable before-flashlight-directional A backup required")


def accepted_payload():
    require(sha(ACCEPTED_PAYLOAD.read_bytes()) == ACCEPTED_PAYLOAD_SHA, "Accepted flashlight payload changed")
    payload = json.loads(ACCEPTED_PAYLOAD.read_bytes())
    require(payload["owner"] == "corn_flashlight_20261020" and len(payload["entries"]) == 155
            and len(payload["addedNodes"]) == 2, "Unexpected accepted 155-Source flashlight payload")
    return payload


def mapping():
    accepted = accepted_payload()
    sources, classes = harvest.current_mapping()
    previous = {row["path"]: row for row in accepted["entries"]}
    require(len(previous) == 155 and len(sources) == 152 and classes == accepted["classes"], "155-Source code topology must remain exact")
    require(set(sources) == {path for path in previous if harvest.owned(path)}, "Unexpected configured Source set")
    changed = {path for path, source in sources.items() if sha(source.encode()) != previous[path]["after"]}
    require(changed == ALLOWED_CHANGED, "Expected only three flashlight/input Sources: " + str(sorted(changed)))
    return accepted, sources, classes, changed


def payload_data():
    accepted, sources, classes, changed = mapping()
    prior_path = ROOT / ".artifacts/playtests/2026-10-20-flashlight-cone/payload.json"
    require(sha(prior_path.read_bytes()) == "ed0b774f5f5d85e86d2b3e0351fcb3fd8bd881a45930d61d199b196d83f1839f", "Frozen prior cone stage changed")
    prior = {row["path"]: row for row in json.loads(prior_path.read_bytes())["entries"]}
    entries = []
    for old in accepted["entries"]:
        path = old["path"]
        source = sources.get(path)
        after = sha(source.encode()) if source is not None else old["after"]
        row = {"path": path, "class": old["class"], "before": old["after"], "staged": prior[path]["after"], "after": after}
        if path in changed:
            row["source"] = source
        entries.append(row)
    return {"version": 1, "owner": OWNER, "baselineSha256": BASELINE_SHA,
        "roots": list(harvest.ROOTS), "beforeClasses": classes, "classes": classes,
        "addedNodes": [], "entries": entries}


def installer_core(payload_sha):
    core = harvest.CORE.replace("Harvest", "Flashlight cone").replace("Corn Flashlight cone art code", "Corn flashlight cone code")
    core = core.replace('payload.owner == "harvest_warden_v1"', 'payload.owner == "' + OWNER + '"')
    core = core.replace('if baseline then 80 else #payload.entries', 'if baseline then 155 else #payload.entries')
    needle = 'local ground, field = map:FindFirstChild("Ground"), map:FindFirstChild("FieldZone")'
    require(core.count(needle) == 1 and core.count('if baseline then 155 else #payload.entries') == 1, "Reused guard core changed unexpectedly")
    core = core.replace(needle, 'assert(map:GetAttribute("HarvestArtVariant") == "A", "Directional flashlight is scoped to A; nothing changed")\n' + needle)
    # Accept exactly one complete known pre-edit state, or the complete final
    # state. Mixed partial states and arbitrary edits are refused before writes.
    core = core.replace("local byPath, baseline, final = {}, true, true", "local byPath, baseline, staged, final = {}, true, true, true")
    core = core.replace("final = final and hash == entry.after", "staged = staged and hash == entry.staged\n        final = final and hash == entry.after")
    core = core.replace("assert(baseline or final,", "assert(baseline or staged or final,")
    core = core.replace("digest(item.Source) == entry.before,", "digest(item.Source) == (if baseline then entry.before else entry.staged),")
    return core.replace("@PAYLOAD_SHA@", payload_sha).replace("@BASELINE_SHA@", BASELINE_SHA)


def build():
    require_baseline()
    accepted = accepted_payload()
    result = subprocess.run([str(ROOT / ".tools/lune/lune.exe"), "run", str(ROOT / ".artifacts/harvest-install/read-baseline.luau"), str(BASELINE)],
        cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    actual = json.loads(result.stdout)
    expected = {row["path"]: {"class": row["class"], "sha256": row["after"]} for row in accepted["entries"]}
    require({path: {"class": row["class"], "sha256": row["sha256"]} for path, row in actual["sources"].items()} == expected
            and actual["classes"] == accepted["classes"], "Immutable pre-cone Sources/classes differ from accepted flashlight save")
    payload = payload_data()
    raw = compact(payload)
    equals = "=="
    while ("]" + equals + "]").encode() in raw:
        equals += "="
    installer = "-- Generated guarded A-only directional surface-light Source update.\nlocal raw = [" + equals + "[" + raw.decode() + "]" + equals + "]\n" + installer_core(sha(raw))
    require(len(installer.encode()) < 195000, "Inline directional surface-light installer exceeds safe native command size")
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "payload.json").write_bytes(raw)
    target = ROOT / "scripts/install-flashlight-directional.luau"
    target.write_text(installer, encoding="utf-8", newline="\n")
    manifest = {"version": 1, "owner": OWNER, "baseline_sha256": BASELINE_SHA,
        "accepted_flashlight_payload_sha256": ACCEPTED_PAYLOAD_SHA, "baseline_sources": 155,
        "final_sources": 155, "project_sources": 152, "new_nodes": 0,
        "changed_existing": sorted(ALLOWED_CHANGED), "payload_bytes": len(raw), "payload_sha256": sha(raw),
        "installer_bytes": len(installer.encode()), "installer_sha256": sha(target.read_bytes()),
        "source_only": True, "scene_written": False, "variant": "A"}
    (OUT / "pipeline-manifest.json").write_bytes(compact(manifest) + b"\n")
    require_baseline()
    accepted_payload()
    print(json.dumps(manifest))
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compact", action="store_true", help="Installer always embeds compact SHA256-guarded JSON")
    parser.parse_args()
    build()
