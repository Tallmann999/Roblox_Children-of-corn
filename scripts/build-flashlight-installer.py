"""Build a guarded variant-A flashlight installer; no scene or HTTP writes.

The accepted black-night A is immutable. Two ModuleScripts are added only to
existing code parents; changed existing Sources are explicitly constrained.
"""
from __future__ import annotations
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / "place/Children_of_corn.before-flashlight-20261020.rbxl"
BASELINE_SHA = "34c266ba847bd112fc552c720e06e0b4dd01b0378e840f15dea7f97917545498"
BASELINE_BYTES = 1483077
ACCEPTED_PAYLOAD = ROOT / ".artifacts/playtests/2026-10-20-black-night/payload.json"
ACCEPTED_PAYLOAD_SHA = "cd0163a72a29624178561569a9e1d332aebf6a80086285b22510ed22160b2376"
OUT = ROOT / ".artifacts/playtests/2026-10-20-flashlight"
OWNER = "corn_flashlight_20261020"
ADDITIONS = frozenset({
    "ReplicatedStorage/GameShared/Game/FlashlightPresentation",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/FlashlightController",
})
REQUIRED_CHANGED = frozenset({"StarterPlayer/StarterPlayerScripts/GameClient/Controllers/RoundController",
    "ReplicatedStorage/GameShared/Game/RoundText"})
ALLOWED_CHANGED = REQUIRED_CHANGED
spec = importlib.util.spec_from_file_location("flashlight_harvest_builder", ROOT / "scripts/build-harvest-installer.py")
harvest = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harvest)
require, sha, compact = harvest.require, harvest.sha, harvest.compact


def accepted_payload():
    require(sha(ACCEPTED_PAYLOAD.read_bytes()) == ACCEPTED_PAYLOAD_SHA, "Accepted black-night payload changed")
    payload = json.loads(ACCEPTED_PAYLOAD.read_bytes())
    require(payload["owner"] == "corn_black_night_20261020" and len(payload["entries"]) == 153
            and not payload["addedNodes"] and payload["beforeClasses"] == payload["classes"], "Unexpected accepted black-night topology")
    return payload


def require_baseline():
    require(BASELINE.is_file() and BASELINE.stat().st_size == BASELINE_BYTES
            and sha(BASELINE.read_bytes()) == BASELINE_SHA, "Exact immutable before-flashlight A backup required")


def mapping():
    accepted = accepted_payload()
    sources, classes = harvest.current_mapping()
    previous = {row["path"]: row for row in accepted["entries"]}
    require(len(previous) == 153 and len(sources) == 152, "Expected 152 project Sources and 153 accepted persistent Sources")
    require(set(sources) == {path for path in previous if harvest.owned(path)} | ADDITIONS, "Unexpected flashlight Source additions/removals")
    require(set(classes) == set(accepted["classes"]) | ADDITIONS
            and all(classes[path] == cls for path, cls in accepted["classes"].items())
            and all(classes[path] == "ModuleScript" for path in ADDITIONS), "Unexpected code-container/class changes")
    changed = {path for path, source in sources.items() if path in previous and sha(source.encode()) != previous[path]["after"]}
    require(REQUIRED_CHANGED.issubset(changed) and changed.issubset(ALLOWED_CHANGED), "Unexpected existing Source edits: " + str(sorted(changed)))
    return accepted, sources, classes, changed


def payload_data():
    accepted, sources, classes, changed = mapping()
    previous = {row["path"]: row for row in accepted["entries"]}
    entries = []
    for path in sorted(set(previous) | ADDITIONS):
        old = previous.get(path)
        source = sources.get(path)
        after = sha(source.encode()) if source is not None else old["after"]
        row = {"path": path, "class": classes[path] if path in classes else old["class"], "after": after}
        if old:
            row["before"] = old["after"]
        if path in ADDITIONS or path in changed:
            row["source"] = source
        entries.append(row)
    return {"version": 1, "owner": OWNER, "baselineSha256": BASELINE_SHA, "roots": list(harvest.ROOTS),
        "beforeClasses": accepted["classes"], "classes": classes,
        "addedNodes": [{"path": path, "class": "ModuleScript"} for path in sorted(ADDITIONS)], "entries": entries}


def installer_core(payload_sha):
    core = harvest.CORE.replace("Harvest", "Flashlight").replace("Corn Flashlight art code", "Corn flashlight code")
    core = core.replace('payload.owner == "harvest_warden_v1"', 'payload.owner == "' + OWNER + '"')
    core = core.replace('if baseline then 80 else #payload.entries', 'if baseline then 153 else #payload.entries')
    needle = 'local ground, field = map:FindFirstChild("Ground"), map:FindFirstChild("FieldZone")'
    require(core.count(needle) == 1 and core.count('if baseline then 153 else #payload.entries') == 1, "Reused installer core changed unexpectedly")
    core = core.replace(needle, 'assert(map:GetAttribute("HarvestArtVariant") == "A", "Flashlight update is scoped to A; nothing changed")\n' + needle)
    return core.replace("@PAYLOAD_SHA@", payload_sha).replace("@BASELINE_SHA@", BASELINE_SHA)


def build():
    require_baseline()
    accepted = accepted_payload()
    result = subprocess.run([str(ROOT / ".tools/lune/lune.exe"), "run", str(ROOT / ".artifacts/harvest-install/read-baseline.luau"), str(BASELINE)],
        cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    native = json.loads(result.stdout)
    expected = {row["path"]: {"class": row["class"], "sha256": row["after"]} for row in accepted["entries"]}
    require({path: {"class": row["class"], "sha256": row["sha256"]} for path, row in native["sources"].items()} == expected
            and native["classes"] == accepted["classes"], "Immutable flashlight baseline Sources/classes differ from accepted checkpoint")
    payload = payload_data()
    raw = compact(payload)
    equals = "=="
    while ("]" + equals + "]").encode() in raw:
        equals += "="
    installer = "-- Generated guarded A-only flashlight code update; no HTTP/world writes.\nlocal raw = [" + equals + "[" + raw.decode() + "]" + equals + "]\n" + installer_core(sha(raw))
    require(len(installer.encode()) < 195000, "Inline flashlight installer too large for a safe native command")
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "payload.json").write_bytes(raw)
    target = ROOT / "scripts/install-flashlight.luau"
    target.write_text(installer, encoding="utf-8", newline="\n")
    changed = sorted(row["path"] for row in payload["entries"] if row.get("before") and row["before"] != row["after"])
    manifest = {"version": 1, "owner": OWNER, "baseline_sha256": BASELINE_SHA,
        "accepted_black_night_payload_sha256": ACCEPTED_PAYLOAD_SHA, "baseline_sources": 153, "final_sources": 155,
        "project_sources": 152, "new_nodes": 2, "added_sources": sorted(ADDITIONS), "changed_existing": changed,
        "payload_bytes": len(raw), "payload_sha256": sha(raw), "installer_bytes": len(installer.encode()),
        "installer_sha256": sha(target.read_bytes()), "source_only": True, "scene_written": False, "variant": "A"}
    (OUT / "pipeline-manifest.json").write_bytes(compact(manifest) + b"\n")
    require_baseline()
    accepted_payload()
    print(json.dumps(manifest))
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compact", action="store_true", help="Installer always embeds compact, SHA256-guarded JSON")
    parser.parse_args()
    build()
