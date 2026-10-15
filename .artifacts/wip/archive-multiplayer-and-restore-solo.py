"""Archive project-owned multiplayer WIP and restore only src from pinned solo bytes."""
import hashlib
import importlib.util
import json
import subprocess
import zipfile
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SRC = (ROOT / "src").resolve()
OUT = (ROOT / ".artifacts/wip").resolve()
BASELINE = ROOT / "place/Children_of_corn.before-multiplayer-20261015.rbxl"
BASELINE_SHA = "493bc1f9b512d618d0a815b2197e3af854f775cd711b363db2906d8fbaf1fb68"
ZIP = OUT / "2026-10-15-multiplayer-src.zip"
MANIFEST = OUT / "2026-10-15-multiplayer-src.manifest.json"
DIFF = OUT / "2026-10-15-multiplayer-src.git-diff.patch"
MAP_COPY = OUT / "2026-10-15-multiplayer-src.sourcemap.json"
REMOVED = {
    "ServerScriptService/GameServer/Game/TeamRound": "src/server/Game/TeamRound.luau",
    "ServerScriptService/GameServer/Game/RoundParticipant": "src/server/Game/RoundParticipant.luau",
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def under_src(relative):
    item = ROOT / relative
    absolute = item.resolve()
    assert absolute.is_relative_to(SRC) and not item.is_symlink(), relative
    return absolute


def source_files():
    files = sorted(p for p in SRC.rglob("*") if p.is_file())
    for item in files:
        assert not item.is_symlink() and item.resolve().is_relative_to(SRC), item
        assert item.suffix == ".luau" or item.name == ".gitkeep", item
    return {p.relative_to(ROOT).as_posix(): p.read_bytes() for p in files}


assert ROOT == Path("D:/ROBLOX/My_Projects/Roblox_Children of Corn").resolve()
assert OUT.is_relative_to(ROOT) and SRC.is_relative_to(ROOT)
OUT.mkdir(parents=True, exist_ok=True)
assert not any(p.exists() for p in (ZIP, MANIFEST, DIFF, MAP_COPY)), "Archive already exists; refuse replacement"
baseline_bytes = BASELINE.read_bytes()
assert len(baseline_bytes) == 995988 and digest(baseline_bytes) == BASELINE_SHA
mapping_bytes = (ROOT / "build/sourcemap.json").read_bytes()
source_map = json.loads(mapping_bytes)
mapping = {}


def walk(node, prefix=None):
    path = "" if prefix is None else prefix + "/" + node["name"] if prefix else node["name"]
    files = [p for p in node.get("filePaths", []) if p.startswith("src/") and p.endswith(".luau")]
    assert len(files) <= 1, path
    if files:
        assert path not in mapping and files[0] not in {v[0] for v in mapping.values()}, path
        under_src(files[0])
        mapping[path] = (files[0], node["className"])
    for child in node.get("children", []):
        walk(child, path)


walk(source_map)
assert len(mapping) == 77
snapshot = source_files()
assert {p for p in snapshot if p.endswith(".luau")} == {v[0] for v in mapping.values()}
spec = importlib.util.spec_from_file_location("wip_backup_reader", ROOT / "scripts/verify-scene-preservation.py")
reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader)
dom, warnings = reader.known_dom(BASELINE)
assert len(dom) == 4160 and sum("Source" in n["properties"] for n in dom.values()) == 78
missing = set(mapping) - set(dom)
assert missing == set(REMOVED)
restore = {}
for path, (relative, class_name) in mapping.items():
    if path in missing:
        assert relative == REMOVED[path]
        continue
    node = dom[path]
    source = node["properties"]["Source"]
    assert node["class"] == class_name and source[0] == "string" and not source[2], path
    data = source[1].replace("\r\n", "\n").encode("utf-8")
    assert b"\r" not in data and data.decode("utf-8").encode("utf-8") == data, path
    restore[relative] = data
assert len(restore) == 75
assert source_files() == snapshot, "Source changed during read-only preparation"
git_diff = subprocess.run(
    ["git", "diff", "--binary", "--no-ext-diff", "--no-textconv", "HEAD", "--", "src"],
    cwd=ROOT, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
).stdout
git_status = subprocess.run(
    ["git", "status", "--porcelain=v1", "--", "src"],
    cwd=ROOT, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
).stdout.decode("utf-8")
head = subprocess.run(
    ["git", "rev-parse", "HEAD"], cwd=ROOT, check=True, stdout=subprocess.PIPE,
).stdout.decode("ascii").strip()

with zipfile.ZipFile(ZIP, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for relative, payload in sorted(snapshot.items()):
        archive.writestr(relative, payload)
with zipfile.ZipFile(ZIP, "r") as archive:
    assert len(archive.namelist()) == len(snapshot) and set(archive.namelist()) == set(snapshot)
    assert archive.testzip() is None
    for relative, payload in snapshot.items():
        assert archive.read(relative) == payload, "Archive readback differs: " + relative
DIFF.write_bytes(git_diff)
MAP_COPY.write_bytes(mapping_bytes)
assert DIFF.read_bytes() == git_diff and MAP_COPY.read_bytes() == mapping_bytes
manifest = {
    "scope": "Preserve unfinished multiplayer WIP; restore only src to exact accepted solo Sources. No scene, Studio, docs, tests or scripts changes.",
    "created_utc": datetime.now(timezone.utc).isoformat(),
    "archive": ZIP.relative_to(ROOT).as_posix(),
    "archive_sha256": digest(ZIP.read_bytes()),
    "archive_bytes": ZIP.stat().st_size,
    "archive_readback_exact": True,
    "git_head": head,
    "git_status_src": git_status,
    "git_diff": {"path": DIFF.relative_to(ROOT).as_posix(), "sha256": digest(git_diff), "bytes": len(git_diff)},
    "source_map": {"path": MAP_COPY.relative_to(ROOT).as_posix(), "sha256": digest(mapping_bytes)},
    "archived_files": [{"path": p, "bytes": len(data), "sha256": digest(data)} for p, data in sorted(snapshot.items())],
    "archived_luau_sources": 77,
    "archived_non_source_files": len(snapshot) - 77,
    "baseline": {"path": BASELINE.relative_to(ROOT).as_posix(), "sha256": BASELINE_SHA, "bytes": len(baseline_bytes), "sources": 78, "instances": 4160},
    "restore_sources": [{"path": p, "bytes": len(data), "sha256": digest(data)} for p, data in sorted(restore.items())],
    "remove_after_archive": sorted(REMOVED.values()),
    "restored": False,
    "reader_warnings": warnings,
}
MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
assert json.loads(MANIFEST.read_text(encoding="utf-8"))["archive_readback_exact"]

# Every source is now preserved and has passed byte-for-byte ZIP readback.
# Refuse even a concurrent one-byte change before the first mutation.
assert source_files() == snapshot
assert digest(BASELINE.read_bytes()) == BASELINE_SHA
assert (ROOT / "build/sourcemap.json").read_bytes() == mapping_bytes
for relative, data in restore.items():
    under_src(relative).write_bytes(data)
for relative in ("src/server/Game/TeamRound.luau", "src/server/Game/RoundParticipant.luau"):
    target = under_src(relative)
    assert target.read_bytes() == snapshot[relative], "Own module changed after archive"
    target.unlink()  # Exactly these two verified, archived files; no recursive deletion.
after = source_files()
expected_after = {p: data for p, data in snapshot.items() if p not in REMOVED.values()}
expected_after.update(restore)
assert after == expected_after
assert len([p for p in after if p.endswith(".luau")]) == 75
assert all(after[path] == data for path, data in restore.items())
assert digest(BASELINE.read_bytes()) == BASELINE_SHA
assert digest(ZIP.read_bytes()) == manifest["archive_sha256"]
with zipfile.ZipFile(ZIP, "r") as archive:
    assert all(archive.read(path) == data for path, data in snapshot.items())
canonical = "".join(p + "\0" + digest(data) + "\n" for p, data in sorted(restore.items())).encode("utf-8")
manifest.update({
    "restored": True,
    "restored_sources": 75,
    "removed_own_sources": 2,
    "untouched_non_source_files": len(after) - 75,
    "clean_source_set_sha256": digest(canonical),
    "clean_digest_definition": "SHA256(UTF8 concat of sorted relative src path + NUL + file SHA256 hex + LF)",
    "archive_verified_again_after_restore": True,
})
MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({key: manifest[key] for key in (
    "archive", "archive_sha256", "archive_bytes", "archive_readback_exact", "archived_luau_sources", "archived_non_source_files", "restored", "restored_sources", "removed_own_sources", "clean_source_set_sha256", "archive_verified_again_after_restore",
)}, ensure_ascii=False))
