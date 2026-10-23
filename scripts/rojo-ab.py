"""Validate explicit A/B Rojo ownership and compare builds to saved scenes read-only.

Project generation changes only A.project.json/B.project.json. It never copies
Sources from future src into frozen snapshots, connects Studio or writes RBXL.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ROOTS = (
    "ReplicatedStorage/GameShared",
    "ServerScriptService/GameServer",
    "StarterPlayer/StarterPlayerScripts/GameClient",
)
SERVICES = {
    "ReplicatedStorage": "ReplicatedStorage",
    "ServerScriptService": "ServerScriptService",
    "StarterPlayer": "StarterPlayer",
    "StarterPlayer/StarterPlayerScripts": "StarterPlayerScripts",
}
SPLIT_FILES = {
    "ReplicatedStorage/GameShared/Game/CornAppearance": "shared/Game/CornAppearance.luau",
    "ReplicatedStorage/GameShared/Game/CornLayout": "shared/Game/CornLayout.luau",
    "ReplicatedStorage/GameShared/Game/HarvestWardenVisual": "shared/Game/HarvestWardenVisual.luau",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornBackdropController": "client/Controllers/CornBackdropController.luau",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornController": "client/Controllers/CornController.luau",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornWindController": "client/Controllers/CornWindController.luau",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/FlashlightController": "client/Controllers/FlashlightController.luau",
    "ServerScriptService/GameServer/Game/InventoryWorld": "server/Game/InventoryWorld.luau",
    "ServerScriptService/GameServer/Game/HarvestWorld": "server/Game/HarvestWorld.luau",
    "ServerScriptService/GameServer/Game/RoundAudio": "server/Game/RoundAudio.luau",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/HarvestGeometryController": "client/Controllers/HarvestGeometryController.luau",
}
MANUAL_B_ONLY = {
    "ReplicatedStorage/GameShared/Game/ManualScene": "variants/B/shared/Game/ManualScene.luau",
    "ServerScriptService/GameServer/Services/ManualSceneService": "variants/B/server/Services/ManualSceneService.luau",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/AuthoringCornController": "variants/B/client/Controllers/AuthoringCornController.luau",
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def source(file):
    return file.read_text(encoding="utf-8").replace("\r\n", "\n")


def owned(path):
    return any(path == prefix or path.startswith(prefix + "/") for prefix in ROOTS)


def load_manifest(root=ROOT):
    return json.loads((root / "rojo/source-map.json").read_text(encoding="utf-8"))


def require_project_ports_idle(manifest):
    for row in manifest["variants"].values():
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as connection:
            connection.settimeout(0.3)
            require(connection.connect_ex(("127.0.0.1", row["port"])) != 0,
                    "Refusing project regeneration while a loopback listener is active: " + str(row["port"]))


def safe_file(root, relative):
    require(isinstance(relative, str) and "\\" not in relative, "Expected portable relative file path")
    file = (root / relative).resolve()
    require(not Path(relative).is_absolute() and file.is_relative_to(root.resolve()), "File escapes project")
    require(file.is_file() and file.suffix == ".luau", "Source file missing or not Luau: " + relative)
    return file


def make_project(manifest, variant):
    row = manifest["variants"][variant]
    tree = {"$className": "DataModel", "$ignoreUnknownInstances": True}
    classes = SERVICES | row["classes"]
    directories = {path for path, entry in row["sources"].items() if entry["file"].endswith("/init.luau")}
    for path in sorted(classes, key=lambda key: (key.count("/"), key)):
        require(owned(path) or path in SERVICES, "World/foreign mapping refused: " + path)
        if any(path.startswith(parent + "/") for parent in directories):
            continue  # Directory middleware owns these children; guarded .meta files preserve unknown children.
        node = tree
        for component in path.split("/"):
            node = node.setdefault(component, {})
        node["$ignoreUnknownInstances"] = True
        if path in row["sources"]:
            file = row["sources"][path]["file"]
            node["$path"] = Path(file).parent.as_posix() if path in directories else file
        else:
            node["$className"] = classes[path]
    return {
        "name": Path(row["scene"]).name,
        "serveAddress": "127.0.0.1",
        "servePort": row["port"],
        "emitLegacyScripts": True,
        "tree": tree,
    }


def validate_projects(root=ROOT, projects=None):
    manifest = load_manifest(root)
    require(manifest["version"] == 1 and manifest["roots"] == list(ROOTS), "Unexpected ownership manifest")
    require(set(manifest["variants"]) == {"A", "B"}, "Explicit A and B required")
    shared = manifest["shared_sources"]
    split = set(manifest["split_paths"])
    require(len(shared) == 142 and split == set(SPLIT_FILES), "Reviewed common/split Source set differs")
    require(not set(shared) & split, "A split Source cannot be shared")
    mapped_files = set()
    for variant, count, port, scene in (
        ("A", 153, 34873, "place/Children_of_corn.rbxl"),
        ("B", 168, 34874, "place/Children_of_corn_B.rbxl"),
    ):
        row = manifest["variants"][variant]
        require(row["port"] == port and row["scene"] == scene, "Wrong variant scene/port")
        require(len(row["sources"]) == count, "Wrong variant Source count")
        require(set(shared).issubset(row["sources"]), "Missing shared Source")
        require({p: row["sources"][p] for p in shared} == shared, "Shared Source redirected")
        require(all(owned(path) for path in row["classes"]), "World class outside code roots")
        require(all(cls in {"Folder", "ModuleScript", "Script", "LocalScript"} for cls in row["classes"].values()),
                "Only code instances may be mapped")
        require(all(path in row["classes"] for path in row["sources"]), "Source class missing")
        files = set()
        for path, entry in row["sources"].items():
            require(entry["class"] in {"ModuleScript", "Script", "LocalScript"}
                    and row["classes"][path] == entry["class"], "Wrong Source class: " + path)
            file = safe_file(root, entry["file"])
            require(entry["file"] not in files, "One file maps multiple Sources")
            files.add(entry["file"])
            if path in shared:
                require(entry["file"].startswith("src/"), "Shared Source must use src")
            else:
                require(entry["file"].startswith("variants/" + variant + "/"), "Cross-variant Source mapping")
            text = source(file)
            require(text.strip() and "\x00" not in text, "Invalid Source text")
        mapped_files.update(files)
        actual = projects[variant] if projects is not None else json.loads(
            (root / (variant + ".project.json")).read_text(encoding="utf-8"))
        require(actual == make_project(manifest, variant), "Unsafe/stale " + variant + ".project.json")
    a, b = (manifest["variants"][v]["sources"] for v in ("A", "B"))
    for path, relative in SPLIT_FILES.items():
        for variant in ("A", "B"):
            entry = manifest["variants"][variant]["sources"].get(path, {})
            require(entry.get("file") == "variants/" + variant + "/" + relative,
                    "Split Source must use its exact canonical variant file: " + path)
    for path, relative in MANUAL_B_ONLY.items():
        entry = b.get(path, {})
        require(entry.get("file") == relative and entry.get("class") == "ModuleScript",
                "Manual authoring Source must use its canonical B ModuleScript: " + path)
    shadow = "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornShadowController"
    night = "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/NightModeController"
    beds = {
        "ReplicatedStorage/GameShared/Game/GreenBedLayout",
        "ReplicatedStorage/GameShared/Game/GreenBedGeometry",
        "ReplicatedStorage/GameShared/Game/GreenBedGeometryData/Center",
        "ReplicatedStorage/GameShared/Game/GreenBedGeometryData/End",
        "ReplicatedStorage/GameShared/Game/GreenBedGeometryData/Skirt",
        "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/GreenBedController",
    }
    corn_shapes = {"ReplicatedStorage/GameShared/Game/CornGreenGeometry"} | {
        f"ReplicatedStorage/GameShared/Game/CornGreenGeometryData/Var{i:02}" for i in range(1, 4)}
    require(set(a) == set(shared) | split and set(b) == set(a) | {shadow, night} | beds | corn_shapes | set(MANUAL_B_ONLY),
            "Variant-only topology differs")
    require(b[night]["file"] == "variants/B/client/Controllers/NightModeController.luau",
            "B night controller must use its canonical variant file")
    require(len(manifest["variants"]["A"]["classes"]) == 165
            and len(manifest["variants"]["B"]["classes"]) == 182,
            "Reviewed code class count differs")
    require(all(a[path]["file"] != b[path]["file"] for path in split), "Split Sources must be independent")
    legacy = set(manifest["legacy_unmapped_files"])
    require(legacy == {"src/" + relative for relative in SPLIT_FILES.values()}
            | {"src/client/Controllers/CornShadowController.luau"}
            and not mapped_files & legacy, "Legacy mixed src must not be served")
    all_src = {p.relative_to(root).as_posix() for p in (root / "src").rglob("*.luau")}
    require(all_src == {entry["file"] for entry in shared.values()} | legacy,
            "Unmapped/new src file: update the explicit ownership manifest deliberately")
    all_variants = {p.relative_to(root).as_posix() for p in (root / "variants").rglob("*.luau")}
    require(all_variants == {p for p in mapped_files if p.startswith("variants/")}, "Unmapped override file")
    # Rojo requires init.luau to be loaded through its directory. Guard that
    # directory's complete inventory, including metadata at EVERY implicit node.
    implicit = {path for path, entry in shared.items() if any(
        path == parent or path.startswith(parent + "/")
        for parent, item in shared.items() if item["file"].endswith("/init.luau"))}
    metadata = {str(Path(shared[path]["file"]).with_suffix(".meta.json")).replace("\\", "/") for path in implicit}
    for relative in metadata:
        file = root / relative
        require(file.is_file() and json.loads(file.read_text(encoding="utf-8")) == {"ignoreUnknownInstances": True},
                "Implicit code node must preserve unknown Studio children: " + relative)
    actual_metadata = {p.relative_to(root).as_posix() for base in (root / "src", root / "variants")
                       for pattern in ("*.meta.json", "*.meta.jsonc") for p in base.rglob(pattern)}
    require(actual_metadata == metadata, "Unexpected/unreviewed Rojo metadata")
    for path, entry in shared.items():
        if not entry["file"].endswith("/init.luau"):
            continue
        folder = (root / entry["file"]).parent
        expected = {p for p in mapped_files | metadata if (root / p).is_relative_to(folder)}
        actual = {p.relative_to(root).as_posix() for p in folder.rglob("*") if p.is_file()}
        require(actual == expected, "Unreviewed file in an implicitly mapped code directory")
    default = json.loads((root / "default.project.json").read_text(encoding="utf-8"))
    require(default.get("servePlaceIds") == [] and default.get("name") == "ChildrenOfCorn_CodeCheckOnly",
            "Default mixed-source project must reject every live connection")
    require("placeId" not in default and "gameId" not in default, "Do not rewrite place/universe IDs")
    return manifest


def read_scene(root, file):
    result = subprocess.run(
        [str(root / ".tools/lune/lune.exe"), "run", str(root / "scripts/read-rojo-sources.luau"), str(file)],
        cwd=root, capture_output=True, check=True,
    )
    return json.loads(result.stdout)


def built_sources(file):
    classes, sources, script_properties = {}, {}, {}
    def visit(item, prefix=""):
        props = item.find("Properties")
        name = next(node.text for node in props if node.attrib.get("name") == "Name")
        path = prefix + "/" + name if prefix else name
        require(path not in classes, "Duplicate built instance")
        classes[path] = item.attrib["class"]
        text = next((node.text or "" for node in props if node.attrib.get("name") == "Source"), None)
        if text is not None:
            sources[path] = {"class": item.attrib["class"], "source": text.replace("\r\n", "\n")}
            script_properties[path] = {node.attrib["name"]: node.text for node in props
                                       if node.attrib.get("name") not in {"Name", "Source"}}
        for child in item.findall("Item"):
            visit(child, path)
    for item in ET.parse(file).getroot().findall("Item"):
        visit(item)
    return classes, sources, script_properties


def check_builds(root=ROOT, saved=False):
    manifest = validate_projects(root)
    rojo = shutil.which("rojo")
    require(rojo is not None, "Load scripts/use-project-tools.ps1 first")
    report = {"passed": True, "shared_sources": len(manifest["shared_sources"]), "variants": {}}
    with tempfile.TemporaryDirectory(prefix="corn-rojo-code-check-") as directory:
        for variant, row in manifest["variants"].items():
            build = Path(directory) / (variant + ".rbxlx")
            sourcemap = Path(directory) / (variant + ".json")
            project = root / (variant + ".project.json")
            for args in (["build", str(project), "--output", str(build)],
                         ["sourcemap", str(project), "--output", str(sourcemap)]):
                command = subprocess.run([rojo, *args], cwd=root, capture_output=True)
                require(command.returncode == 0, command.stderr.decode("utf-8", "replace"))
            classes, built, properties = built_sources(build)
            expected = {path: {"class": item["class"], "source": source(safe_file(root, item["file"]))}
                        for path, item in row["sources"].items()}
            require(classes == SERVICES | row["classes"] and built == expected,
                    "Rojo build adds/drops/changes code outside the explicit graph: " + variant)
            for path, values in properties.items():
                require(not values or values == {"RunContext": "0"}, "Unexpected served script properties: " + path)
            result = {"sources": len(built), "code_instances": len(row["classes"]), "build_and_sourcemap": True}
            if saved:
                file = root / row["scene"]
                original = file.read_bytes()
                require(len(original) == row["scene_bytes"] and sha(original) == row["scene_sha256"],
                        "Saved scene differs from the reviewed setup checkpoint; preserve and review author changes")
                native = read_scene(root, file)
                native_owned = {path: {key: value[key] for key in ("class", "source")}
                                for path, value in native["sources"].items() if owned(path)}
                require(native_owned == built and native["classes"] == row["classes"],
                        "Build differs from saved variant Sources/classes: " + variant)
                require(all(value.get("runContext", "Legacy") == "Legacy"
                            and not value.get("disabled", False) for path, value in native["sources"].items() if owned(path)),
                        "Nondefault saved Script properties require explicit review")
                unmanaged = {path: {"class": value["class"], "sha256": sha(value["source"].encode())}
                             for path, value in native["sources"].items() if not owned(path)}
                require(unmanaged == manifest["unmanaged_sources"], "Unmanaged Sources changed")
                require(file.read_bytes() == original, "Scene bytes changed during read-only check")
                result.update({"saved_sources_exact": True, "scene_sha256": sha(original),
                               "total_scene_sources": len(native["sources"]), "scene_bytes_unchanged": True})
            report["variants"][variant] = result
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--check", action="store_true")
    action.add_argument("--write-projects", action="store_true")
    parser.add_argument("--saved", action="store_true", help="Also require exact reviewed engine-saved A/B Sources")
    args = parser.parse_args()
    if args.write_projects:
        require(not args.saved, "--saved requires --check")
        manifest = load_manifest()
        projects = {variant: make_project(manifest, variant) for variant in ("A", "B")}
        validate_projects(projects=projects)
        require_project_ports_idle(manifest)
        for variant in ("A", "B"):
            target = ROOT / (variant + ".project.json")
            temporary = target.with_suffix(".json.tmp")
            temporary.write_text(
                json.dumps(projects[variant], ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8", newline="\n",
            )
            temporary.replace(target)
        validate_projects()
        print("Generated explicit A/B project files; no Sources or scenes written.")
    else:
        print(json.dumps(check_builds(saved=args.saved), indent=2))


if __name__ == "__main__":
    main()
