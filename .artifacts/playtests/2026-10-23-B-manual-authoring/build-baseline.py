"""Freeze the accepted engine B bytes and the committed source expectations.

Reads engine files and Git objects; writes this task's support files only.
It never serializes a scene, touches Studio, changes a manifest or replaces an
existing snapshot. Re-running verifies identical bytes rather than refreshing.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
HEAD = "2d3ccd7044f832221e616d7a09ec8c8ce36e4e68"
ACCEPTED = {
    "A": ("place/Children_of_corn.rbxl", 1491827, "c1f054029ca729f314889ce7874c17c6e5f772cb20541a9c0ceedd796f3446b7"),
    "B": ("place/Children_of_corn_B.rbxl", 1759554, "c91efe74d1750095eac19390800192ad03b264d7a99de46cf21d170fcb4ed31f"),
    "C": ("place/Children_of_corn_TestScene.rbxl", 187672, "24a2d0ff9711d0805d3bcc738a156939574384d859ee3ec8493cc24621712010"),
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def frozen(path, data):
    if path.exists():
        assert path.read_bytes() == data, f"Immutable support file differs: {path}"
    else:
        with path.open("xb") as stream:
            stream.write(data)


def write_json(path, data):
    frozen(path, (json.dumps(data, indent=2, ensure_ascii=False, sort_keys=True) + "\n").encode())


def main():
    assert git("rev-parse", "HEAD").decode().strip() == HEAD, "Unexpected baseline Git HEAD"
    scenes = {}
    for variant, (relative, size, expected) in ACCEPTED.items():
        data = (ROOT / relative).read_bytes()
        assert len(data) == size and digest(data) == expected, f"Accepted {variant} scene changed"
        scenes[variant] = {"file": relative, "bytes": size, "sha256": expected}

    map_bytes = git("show", HEAD + ":rojo/source-map.json")
    assert (ROOT / "rojo/source-map.json").read_bytes() == map_bytes, "Source map differs from committed accepted baseline"
    mapping = json.loads(map_bytes)
    expected_sources = {}
    for path, entry in mapping["variants"]["B"]["sources"].items():
        source = git("show", HEAD + ":" + entry["file"])
        assert digest(source) == entry["baseline_sha256"], f"Committed Source/map mismatch: {path}"
        expected_sources[path] = {
            "class": entry["class"], "file": entry["file"],
            "sha256": digest(source), "bytes": len(source), "ownership": "canonical_B",
        }
    prior_relative = ".artifacts/playtests/2026-10-23-B-night-toggle/expected-before-sources.json"
    prior_bytes = git("show", HEAD + ":" + prior_relative)
    prior = json.loads(prior_bytes)
    for path, entry in mapping["unmanaged_sources"].items():
        assert prior[path] == entry, f"Unmanaged Fog source differs from previous accepted guard: {path}"
        expected_sources[path] = {**entry, "ownership": "unmanaged_fog", "evidence": prior_relative}
    assert len(expected_sources) == 168, "Expected exactly 168 baseline Sources"

    archive = OUT / "before-manual-authoring.zip"
    archive_entry = "B-before-manual-authoring.rbxl"
    bdata = (ROOT / ACCEPTED["B"][0]).read_bytes()
    if archive.exists():
        with zipfile.ZipFile(archive) as source_archive:
            assert source_archive.namelist() == [archive_entry], "Immutable archive entries differ"
            assert source_archive.read(archive_entry) == bdata, "Immutable archive baseline differs"
    else:
        # Fixed metadata keeps the reviewed archive reproducible across reruns.
        info = zipfile.ZipInfo(archive_entry, (2026, 10, 23, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o100444 << 16
        with zipfile.ZipFile(archive, mode="x", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as target:
            target.writestr(info, bdata, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    archive_sha = digest(archive.read_bytes())

    baseline = {
        "schema": "corn_B_manual_authoring_readonly_baseline_v1", "git_head": HEAD,
        "baseline_source_map_file": "rojo/source-map.json", "baseline_source_map_sha256": digest(map_bytes),
        "scene_files": scenes,
        "archive": {"file": archive.name, "entry": archive_entry, "sha256": archive_sha,
                    "scene_bytes": len(bdata), "scene_sha256": digest(bdata)},
        "accepted_saved_instance_count": 6054, "expected_source_count": 168,
        "canonical_source_count": 165, "unmanaged_fog_source_count": 3,
        "expected_sources": expected_sources,
        "unmanaged_fog_evidence": {"file": prior_relative, "sha256": digest(prior_bytes)},
        "scope": "Immutable accepted B engine bytes and committed expected Source inventory only. Native snapshot is separate. No Studio, Save, scene serialization, manifest changes, commit, push or publication.",
    }
    write_json(OUT / "baseline.json", baseline)
    write_json(OUT / "expected-before-sources.json", {
        path: {"class": entry["class"], "sha256": entry["sha256"]}
        for path, entry in expected_sources.items()
    })
    original = ROOT / ".artifacts/playtests/2026-10-23-B-green-variants/native-snapshot.luau"
    original_bytes = original.read_bytes()
    text = original_bytes.decode()
    assert text.count("options.sourceCount or 157") == 1
    assert text.count('"Expected 157 current persistent B Sources"') == 1
    assert text.count('options.storeKey:sub(1, 23) == "__CornBGreenVariantsV1_"') == 1
    text = text.replace("options.sourceCount or 157", "options.sourceCount or 168")
    text = text.replace('"Expected 157 current persistent B Sources"', '"Expected current persistent B Source count: " .. tostring(options.sourceCount or 168)')
    text = text.replace('options.storeKey:sub(1, 23) == "__CornBGreenVariantsV1_"', 'options.storeKey:sub(1, 25) == "__CornBManualAuthoringV1_"')
    text = text.replace('owner="corn_rojo_B_readonly_snapshot_v1"', 'owner="CornBManualAuthoringV1"')
    # The owned prefix is 25 characters including both initial underscores.
    assert len("__CornBManualAuthoringV1_") == 25
    frozen(OUT / "native-snapshot.luau", text.encode())
    print(json.dumps({"passed": True, "baseline_sources": len(expected_sources), "archive_sha256": archive_sha,
                      "baseline_sha256": digest((OUT / "baseline.json").read_bytes()),
                      "native_snapshot_sha256": digest((OUT / "native-snapshot.luau").read_bytes()),
                      "native_snapshot_origin_sha256": digest(original_bytes)}, indent=2))


if __name__ == "__main__":
    main()
