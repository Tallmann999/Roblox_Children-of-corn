"""Default read-only audit; --apply restores exact clean engine-saved Corn bytes.

This handles only the audited 50d8d341 foreign-sync file and the immutable
493bc1f9 clean engine backup. The mixed file is retained immutably first.
No Roblox scene is reconstructed or reserialized. Stop the external writer
before applying; unknown author edits or any world difference are refused.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
MIXED_HASH = "50d8d341bcffc34148151ff7ea2e3e7dad7dbe513be1f8cedc82573333f30aca"
MIXED_BYTES = 359914
CLEAN_HASH = "493bc1f9b512d618d0a815b2197e3af854f775cd711b363db2906d8fbaf1fb68"
CLEAN_BYTES = 995988
FOREIGN_SOURCES = frozenset({
    "ReplicatedStorage/GameShared/Game/DanceClip",
    "ReplicatedStorage/GameShared/Game/IntroVisuals",
    "ReplicatedStorage/GameShared/Game/NoteVisuals",
    "ReplicatedStorage/GameShared/Game/RhythmChart",
    "ReplicatedStorage/GameShared/Game/RhythmConfig",
    "ReplicatedStorage/GameShared/Game/SuperComboChart",
    "ServerScriptService/GameServer/Game/ArenaBuilder",
    "ServerScriptService/GameServer/Services/RhythmService",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/RhythmController",
    "StarterPlayer/StarterPlayerScripts/GameClient/Game/BattleCamera",
    "StarterPlayer/StarterPlayerScripts/GameClient/Game/CharacterChoreography",
    "StarterPlayer/StarterPlayerScripts/GameClient/Game/RhythmAudio",
    "StarterPlayer/StarterPlayerScripts/GameClient/Game/RhythmUI",
    "StarterPlayer/StarterPlayerScripts/GameClient/Game/SuperComboClient",
})
CHANGED_SHARED_SOURCES = frozenset({
    "ReplicatedStorage/GameShared/Config/GameConfig",
    "ServerScriptService/GameServer/Bootstrap",
    "StarterPlayer/StarterPlayerScripts/GameClient/Bootstrap",
})
SELECTION_PATHS = {"FilteredSelection", "FilteredSelection#2", "FilteredSelection#3", "FilteredSelection#4"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def guarded_paths():
    root = ROOT.resolve()
    require(root == ROOT, "Redirected workspace root")
    place = root / "place"
    require(place.is_dir() and place.resolve() == place, "Redirected/missing scene directory")
    paths = {
        "working": place / "Children_of_corn.rbxl",
        "clean": place / "Children_of_corn.before-multiplayer-20261015.rbxl",
        "mixed_backup": place / "Children_of_corn.before-foreign-cleanup-20261015.rbxl",
        "temporary": place / "Children_of_corn.foreign-recovery-493bc1f9b512d618.tmp",
    }
    for label, path in paths.items():
        require(path.is_absolute() and path.is_relative_to(root) and path.resolve() == path, "Redirected/outside-workspace " + label + " path")
    require(len(set(paths.values())) == 4, "Recovery path collision")
    return paths


def validate_scene_evidence(clean, mixed):
    """Read-only known DOM and exact unknown binary Terrain payloads."""
    spec = importlib.util.spec_from_file_location("corn_foreign_recovery_readonly", ROOT / "scripts/verify-scene-preservation.py")
    scene = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(scene)
    before, warning_before = scene.known_dom(clean)
    after, warning_after = scene.known_dom(mixed)
    require(len(before) == 4160 and len(after) == 4119, "Scene instance count differs from audited recovery pair")
    old_sources = {p: n["properties"]["Source"][1].replace("\r\n", "\n") for p, n in before.items() if "Source" in n["properties"]}
    new_sources = {p: n["properties"]["Source"][1].replace("\r\n", "\n") for p, n in after.items() if "Source" in n["properties"]}
    require(len(old_sources) == 78 and len(new_sources) == 22, "Unexpected clean/mixed Source counts")
    require(set(new_sources) - set(old_sources) == FOREIGN_SOURCES, "Foreign Source paths differ from exact fourteen audited Cooking/Rhythm modules")
    require(len(set(old_sources) - set(new_sources)) == 70, "Unexpected removed Corn Source set")
    changed = {p for p in set(old_sources) & set(new_sources) if old_sources[p] != new_sources[p]}
    require(changed == CHANGED_SHARED_SOURCES, "Unexpected reused Source edits")
    service = new_sources["ServerScriptService/GameServer/Services/RhythmService"]
    controller = new_sources["StarterPlayer/StarterPlayerScripts/GameClient/Controllers/RhythmController"]
    require(all(marker in service for marker in ("CookingRemotes", "CookingPhase", "CookingScore")) and "CookingRhythmMVP" in controller, "Expected foreign Cooking/Rhythm markers missing")
    old_world = {p: n for p, n in before.items() if not scene.owned(p) and p not in SELECTION_PATHS}
    new_world = {p: n for p, n in after.items() if not scene.owned(p) and p not in SELECTION_PATHS}
    require(len(old_world) == 4069 and set(old_world) == set(new_world), "Original world/art/Lighting instance set changed")
    for path, node in old_world.items():
        require(node == new_world[path], "Original world/art/Lighting/identity/parent property changed: " + path)
    require(all(before[p] == after.get(p) for p in SELECTION_PATHS), "Audited selection metadata changed")
    unknown_before = scene.unknown_properties(clean)
    unknown_after = scene.unknown_properties(mixed)
    require(unknown_before.get("supported") and unknown_after.get("supported") and unknown_before == unknown_after, "Raw Terrain/unknown binary properties changed")
    return {"passed": True, "clean_instances": len(before), "mixed_instances": len(after),
        "world_instances_exact": len(old_world), "world_art_lighting_identities_names_classes_parents_exact": True,
        "raw_terrain_exact": True, "raw_unknown_properties": unknown_before, "selection_exact": True,
        "clean_sources": 78, "mixed_sources": 22, "foreign_source_paths": sorted(FOREIGN_SOURCES),
        "removed_corn_source_paths": sorted(set(old_sources) - set(new_sources)), "changed_reused_source_paths": sorted(changed),
        "warnings": {"clean": warning_before, "mixed": warning_after}}


def write_exclusive(path, data):
    with path.open("xb") as handle:
        handle.write(data)
        handle.flush()
        os.fsync(handle.fileno())


def recover(apply=False):
    paths = guarded_paths()
    working, clean, backup, temporary = (paths[key] for key in ("working", "clean", "mixed_backup", "temporary"))
    mixed_data, clean_data = working.read_bytes(), clean.read_bytes()
    require(len(mixed_data) == MIXED_BYTES and digest(mixed_data) == MIXED_HASH, "Working file is no longer the exact audited foreign-sync scene; inspect author edits")
    require(len(clean_data) == CLEAN_BYTES and digest(clean_data) == CLEAN_HASH, "Immutable clean Corn backup changed")
    if backup.exists():
        require(backup.read_bytes() == mixed_data, "Immutable foreign-cleanup backup collision; preserve both files")
    require(not temporary.exists(), "Recovery temporary path collision")
    evidence = validate_scene_evidence(clean, working)
    require(evidence.get("passed") is True, "Scene evidence verification failed")
    require(guarded_paths() == paths and working.read_bytes() == mixed_data and clean.read_bytes() == clean_data, "Scene/path changed during read-only preflight")
    report = {"passed": True, "applied": False, "working": str(working), "working_before_sha256": MIXED_HASH,
        "working_before_bytes": len(mixed_data), "clean_backup": str(clean), "clean_sha256": CLEAN_HASH,
        "clean_bytes": len(clean_data), "foreign_cleanup_backup": str(backup), "backup_already_exists": backup.exists(),
        "scene_evidence": evidence, "method": "Exact immutable engine-saved clean bytes; no scene reconstruction or serialization"}
    if not apply:
        return report | {"scope": "Read-only preflight. No project, scene, backup or artifact written. Use --apply explicitly for the guarded byte recovery."}
    require(guarded_paths() == paths and working.read_bytes() == mixed_data and clean.read_bytes() == clean_data, "Inputs changed before recovery")
    if backup.exists():
        require(backup.read_bytes() == mixed_data, "Foreign-cleanup backup changed before recovery")
    else:
        write_exclusive(backup, mixed_data)
    require(backup.read_bytes() == mixed_data, "Foreign-cleanup backup differs from exact mixed bytes")
    created_temporary = False
    try:
        require(not temporary.exists(), "Recovery temporary appeared during preflight")
        # Mark ownership only after exclusive creation succeeds. A collision is
        # never removed by cleanup; our own partial write is safe to remove.
        with temporary.open("xb") as handle:
            created_temporary = True
            handle.write(clean_data)
            handle.flush()
            os.fsync(handle.fileno())
        require(guarded_paths() == paths, "Recovery paths redirected during copy")
        require(working.read_bytes() == mixed_data, "Working scene changed during recovery; author edit preserved")
        require(clean.read_bytes() == clean_data and digest(clean.read_bytes()) == CLEAN_HASH, "Clean backup changed during recovery")
        require(backup.read_bytes() == mixed_data, "Immutable mixed backup changed during recovery")
        require(temporary.read_bytes() == clean_data, "Temporary clean copy differs")
        os.replace(temporary, working)
    finally:
        if created_temporary and temporary.exists():
            temporary.unlink()
    require(working.read_bytes() == clean_data and clean.read_bytes() == clean_data and backup.read_bytes() == mixed_data, "Post-recovery byte verification failed")
    return report | {"applied": True, "restored_sha256": CLEAN_HASH, "restored_bytes": len(clean_data),
        "mixed_backup_sha256": MIXED_HASH, "scope": "Exact clean engine bytes atomically restored. Exact mixed bytes retained immutably; no source/world editing or scene serialization."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Explicitly back up the audited mixed file and atomically restore exact clean engine bytes")
    args = parser.parse_args()
    print(json.dumps(recover(apply=args.apply), ensure_ascii=False))
