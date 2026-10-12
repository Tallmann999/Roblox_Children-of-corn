"""Generate guarded, byte-exact farm JSON ModuleScript chunks below Studio Source limits."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA_ROOT = ROOT / "src/shared/Game/FarmGeometryData"
NEUTRAL_ROOT = ROOT / "assets/farm/neutral"
MAX_SOURCE_BYTES = 140_000
HEADER = "-- Generated verified neutral FBX geometry; no Cloud asset upload.\n"
COUNTS = {
    "SM_Bld_Barn_03": 7,
    "SM_Prop_Truck_Rusted_01": 1,
    "SM_Prop_Tyre_01": 1,
    "SM_Prop_Rubbish_Pile_05": 1,
}


def sha(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sources_for(key: str, raw: bytes) -> tuple[dict[Path, bytes], dict]:
    text = raw.decode("utf-8")
    if "\r" in text:
        raise ValueError(f"{key}: CR bytes cannot survive a Luau long string exactly")
    data = json.loads(text)
    if data.get("index_base") != 1 or len(data.get("meshes", [])) != COUNTS[key]:
        raise ValueError(f"{key}: unrecognized catalog")
    equals = "=="
    while f"]{equals}]" in text:
        equals += "="
        if len(equals) > 64:
            raise ValueError(f"{key}: unsafe long-string delimiter")
    prefix = (HEADER + f"return [{equals}[").encode("utf-8")
    suffix = f"]{equals}]\n".encode("utf-8")
    budget = MAX_SOURCE_BYTES - len(prefix) - len(suffix)
    outputs, pieces, chunk_rows = {}, [], []
    offset = 0
    while offset < len(raw):
        end = min(len(raw), offset + budget)
        while end < len(raw) and raw[end] & 0xC0 == 0x80:
            end -= 1
        if end <= offset:
            raise ValueError("UTF8 chunk boundary did not advance")
        piece = raw[offset:end]
        piece.decode("utf-8")
        pieces.append(piece)
        name = f"Chunk{len(pieces):02d}"
        source = prefix + piece + suffix
        if len(source) > MAX_SOURCE_BYTES:
            raise ValueError("Source budget exceeded")
        path = DATA_ROOT / key / (name + ".luau")
        outputs[path] = source
        chunk_rows.append({"name": name, "source_bytes": len(source), "sha256": sha(source)})
        offset = end
    if b"".join(pieces) != raw:
        raise ValueError("Neutral reconstruction differs")
    names = ", ".join(json.dumps(row["name"]) for row in chunk_rows)
    loop = f"for _, name in {{ {names} }} do\n"
    if len(loop.rstrip()) > 100:
        entries = "".join(f'\t\t"{row["name"]}",\n' for row in chunk_rows)
        loop = "for _, name in\n\t{\n" + entries + "\t}\ndo\n"
    init = (HEADER + "local chunks = {}\n" + loop
            + "\ttable.insert(chunks, require(script:WaitForChild(name)))\nend\n"
            + 'return game:GetService("HttpService"):JSONDecode(table.concat(chunks))\n').encode("utf-8")
    if len(init) > MAX_SOURCE_BYTES:
        raise ValueError("Init Source budget exceeded")
    outputs[DATA_ROOT / key / "init.luau"] = init
    row = {"asset_key": key, "raw_bytes": len(raw), "raw_sha256": sha(raw),
           "meshes": len(data["meshes"]), "triangles": sum(len(mesh["triangles"]) for mesh in data["meshes"]),
           "init_source_bytes": len(init), "init_sha256": sha(init), "chunks": chunk_rows}
    return outputs, row


def main() -> None:
    outputs, rows, legacy, legacy_formatted = {}, [], {}, {}
    for key in COUNTS:
        raw = (NEUTRAL_ROOT / (key + ".json")).read_bytes()
        generated, row = sources_for(key, raw)
        outputs.update(generated)
        rows.append(row)
        legacy[DATA_ROOT / (key + ".luau")] = (HEADER + 'return game:GetService("HttpService"):JSONDecode([==[').encode("utf-8") + raw + b']==])\n'
        legacy_formatted[DATA_ROOT / (key + ".luau")] = (HEADER + 'return game:GetService("HttpService"):JSONDecode(\n\t[==[').encode("utf-8") + raw + b']==]\n)\n'
    if sum(row["triangles"] for row in rows) != 16_226:
        raise ValueError("Verified farm triangle count changed")
    data_resolved = DATA_ROOT.resolve()
    for path in outputs | legacy:
        if not path.resolve().is_relative_to(data_resolved):
            raise ValueError("Generated path escaped owned data root")
    existing = list(DATA_ROOT.rglob("*")) if DATA_ROOT.exists() else []
    allowed_dirs = {DATA_ROOT / key for key in COUNTS}
    for path in existing:
        if path.is_dir():
            if path not in allowed_dirs:
                raise ValueError(f"Unknown data folder preserved: {path}")
            continue
        if path not in outputs and path not in legacy:
            raise ValueError(f"Unknown data file preserved: {path}")
        expected = outputs.get(path, legacy.get(path))
        # Accept platform line endings only outside exact compact JSON payloads.
        current = path.read_bytes().replace(b"\r\n", b"\n")
        if current != expected and current != legacy_formatted.get(path):
            raise ValueError(f"Manual/unknown data Source preserved: {path}")
    before = {path: path.read_bytes() for path in existing if path.is_file()}
    created_dirs = []
    try:
        for path, source in outputs.items():
            if not path.parent.exists():
                path.parent.mkdir(parents=True)
                created_dirs.append(path.parent)
            path.write_bytes(source)
        for path in legacy:
            if path.exists():
                path.unlink()
    except BaseException:
        for path in outputs:
            if path not in before and path.exists():
                path.unlink()
        for path, content in before.items():
            path.write_bytes(content)
        for path in reversed(created_dirs):
            path.rmdir()
        raise
    for path, source in outputs.items():
        if path.read_bytes() != source or len(source) > MAX_SOURCE_BYTES:
            raise ValueError(f"Written Source differs or exceeds budget: {path}")
    manifest = {"max_source_utf8_bytes": MAX_SOURCE_BYTES, "data_sources": len(outputs),
                "chunks": sum(len(row["chunks"]) for row in rows), "assets": rows}
    manifest_path = ROOT / "build/farm-data-manifest.json"
    manifest_path.parent.mkdir(exist_ok=True)
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"PASS: {len(outputs)} data Sources ({manifest['chunks']} chunks), max {max(map(len, outputs.values()))} UTF8 bytes; exact 4 neutral reconstructions; 10 meshes/16226 triangles")


if __name__ == "__main__":
    main()
