"""Read-only HTTP integration check for local Rojo A/B servers; no Studio connection."""
from __future__ import annotations

import hashlib
import argparse
import importlib.util
import json
from pathlib import Path
import socket
import struct
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request


sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / ".artifacts/playtests/2026-10-22-rojo-variants/serve-smoke.json"
spec = importlib.util.spec_from_file_location("rojo_ab", ROOT / "scripts/rojo-ab.py")
rojo = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rojo)


def unpack_messagepack(raw):
    """Decode only the standard scalar/container types returned by Rojo's GET API."""
    offset = 0

    def take(length):
        nonlocal offset
        if offset + length > len(raw):
            raise ValueError("Truncated MessagePack response")
        result = raw[offset:offset + length]
        offset += length
        return result

    def number(format):
        return struct.unpack(">" + format, take(struct.calcsize(">" + format)))[0]

    def decode(depth=0):
        if depth > 100:
            raise ValueError("Excessive MessagePack nesting")
        code = take(1)[0]
        if code < 0x80:
            return code
        if code >= 0xE0:
            return code - 256
        if 0xA0 <= code <= 0xBF:
            return take(code & 31).decode("utf-8")
        if code in (0xC0, 0xC2, 0xC3):
            return {0xC0: None, 0xC2: False, 0xC3: True}[code]
        if code in (0xCA, 0xCB, 0xCC, 0xCD, 0xCE, 0xCF, 0xD0, 0xD1, 0xD2, 0xD3):
            return number({0xCA: "f", 0xCB: "d", 0xCC: "B", 0xCD: "H", 0xCE: "I",
                           0xCF: "Q", 0xD0: "b", 0xD1: "h", 0xD2: "i", 0xD3: "q"}[code])
        if code in (0xC4, 0xC5, 0xC6, 0xD9, 0xDA, 0xDB):
            value = take(number({0xC4: "B", 0xC5: "H", 0xC6: "I",
                                 0xD9: "B", 0xDA: "H", 0xDB: "I"}[code]))
            return value.decode("utf-8") if code >= 0xD9 else value
        if 0x90 <= code <= 0x9F or code in (0xDC, 0xDD):
            count = code & 15 if code < 0xA0 else number("H" if code == 0xDC else "I")
            return [decode(depth + 1) for _ in range(count)]
        if 0x80 <= code <= 0x8F or code in (0xDE, 0xDF):
            count = code & 15 if code < 0x90 else number("H" if code == 0xDE else "I")
            result = {}
            for _ in range(count):
                key = decode(depth + 1)
                if key in result:
                    raise ValueError("Duplicate MessagePack map key")
                result[key] = decode(depth + 1)
            return result
        raise ValueError("Unsupported MessagePack type: " + hex(code))

    result = decode()
    rojo.require(offset == len(raw), "Trailing bytes after MessagePack response")
    return result


def free_port(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as check:
        check.bind(("127.0.0.1", port))


def no_listener(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as check:
        check.settimeout(0.5)
        return check.connect_ex(("127.0.0.1", port)) != 0


def read_api(port, endpoint):
    # Explicitly avoid ambient HTTP proxies; every request remains on loopback.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open("http://127.0.0.1:" + str(port) + endpoint, timeout=2) as response:
        rojo.require(response.status == 200, "Unexpected HTTP status")
        rojo.require(response.headers.get_content_type() == "application/msgpack", "Expected MessagePack API")
        return unpack_messagepack(response.read())


def graph_check(info, response, manifest, variant):
    row = manifest["variants"][variant]
    rojo.require(info["projectName"] == Path(row["scene"]).name, "Wrong served variant")
    instances = response["instances"]
    root_id = info["rootInstanceId"]
    root = instances[root_id]
    rojo.require(root["Name"] == info["projectName"] and root["ClassName"] == "DataModel", "Wrong API root")
    classes, sources, seen = {}, {}, set()

    def visit(instance_id, path):
        rojo.require(instance_id not in seen, "Duplicate/cyclic instance ID")
        seen.add(instance_id)
        node = instances[instance_id]
        rojo.require(node["Metadata"]["ignoreUnknownInstances"] is True,
                     "Unknown Studio children may be removed: " + path)
        properties = node["Properties"]
        if path:
            rojo.require(path not in classes, "Duplicate API instance path")
            classes[path] = node["ClassName"]
        if "Source" in properties:
            rojo.require(set(properties).issubset({"Source", "RunContext"}), "Unexpected served code property: " + path)
            if "RunContext" in properties:
                rojo.require(properties["RunContext"] == {"Enum": 0}, "Non-Legacy script RunContext")
            rojo.require(set(properties["Source"]) == {"String"}, "Unexpected Source encoding")
            sources[path] = {"class": node["ClassName"], "source": properties["Source"]["String"]}
        else:
            rojo.require(not properties, "Unexpected container/world properties: " + path)
        for child_id in node["Children"]:
            child = instances[child_id]
            visit(child_id, (path + "/" if path else "") + child["Name"])

    visit(root_id, "")
    rojo.require(seen == set(instances), "API response includes unreachable instances")
    expected_sources = {path: {"class": entry["class"],
                               "source": rojo.source(rojo.safe_file(ROOT, entry["file"]))}
                        for path, entry in row["sources"].items()}
    rojo.require(classes == rojo.SERVICES | row["classes"], "Served classes differ from explicit code graph")
    rojo.require(sources == expected_sources, "Served Sources differ from variant files")
    digest = hashlib.sha256(json.dumps(sources, sort_keys=True).encode()).hexdigest()
    return {"sources": len(sources), "instances_including_DataModel": len(instances),
            "all_nested_ignore_unknown_instances": True, "code_sources_and_classes_exact": True,
            "only_Source_and_Legacy_RunContext_properties": True, "source_graph_sha256": digest}


def inspect_server(binary, project, port, check):
    free_port(port)  # Refuse an occupied port; never stop another server.
    with tempfile.TemporaryFile(mode="w+b") as output:
        process = subprocess.Popen(
            [str(binary), "serve", str(ROOT / project), "--address", "127.0.0.1", "--port", str(port)],
            cwd=ROOT, stdin=subprocess.DEVNULL, stdout=output, stderr=output,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        result = None
        try:
            deadline = time.monotonic() + 15
            while True:
                rojo.require(process.poll() is None, "Own Rojo server exited before readiness")
                try:
                    info = read_api(port, "/api/rojo")
                    break
                except (urllib.error.URLError, TimeoutError, ConnectionError):
                    if time.monotonic() >= deadline:
                        raise TimeoutError("Own Rojo server did not become ready")
                    time.sleep(0.1)
            rojo.require(info["serverVersion"] == "7.7.0", "Unexpected Rojo version")
            result = check(info, port)
            result.update({"passed": True, "port": port, "server_version": info["serverVersion"],
                           "project_name": info["projectName"], "GET_only": True})
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=3)
            rojo.require(no_listener(port), "A listener remains after own server shutdown")
            if result is not None:
                result["own_server_stopped"] = process.poll() is not None
        return result


def main(report_file=REPORT, port_offset=0):
    manifest = rojo.validate_projects(ROOT)
    binary = ROOT / ".tools/rokit-data/tool-storage/rojo-rbx/rojo/7.7.0/rojo.exe"
    rojo.require(binary.is_file(), "Pinned local Rojo binary missing")
    scene_hashes = {variant: rojo.sha((ROOT / row["scene"]).read_bytes())
                    for variant, row in manifest["variants"].items()}
    ports = [row["port"] + port_offset for row in manifest["variants"].values()] + [34872 + port_offset]
    for port in ports:
        free_port(port)
    report = {"passed": True, "scope": "GET-only local Rojo API; no Studio client, POST, sync or RBXL writes.",
              "port_offset": port_offset,
              "variants": {}}
    for variant, row in manifest["variants"].items():
        def check(info, port, selected=variant):
            return graph_check(info, read_api(port, "/api/read/" + info["rootInstanceId"]), manifest, selected)
        report["variants"][variant] = inspect_server(binary, variant + ".project.json", row["port"] + port_offset, check)
    a, b = (report["variants"][variant] for variant in ("A", "B"))
    rojo.require(a["sources"] == 153 and b["sources"] == 165
                 and a["source_graph_sha256"] != b["source_graph_sha256"], "A/B isolation check failed")

    def default_check(info, port):
        rojo.require(info.get("expectedPlaceIds") == [], "Default project must reject every live PlaceId")
        return {"expected_place_ids": [], "default_live_connection_allowlist_empty": True}

    report["default"] = inspect_server(binary, "default.project.json", 34872 + port_offset, default_check)
    for variant, row in manifest["variants"].items():
        rojo.require(rojo.sha((ROOT / row["scene"]).read_bytes()) == scene_hashes[variant],
                     "Scene changed during read-only API smoke test")
    report["scene_bytes_unchanged"] = scene_hashes
    report_file.parent.mkdir(parents=True, exist_ok=True)
    report_file.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=REPORT)
    parser.add_argument("--port-offset", type=int, default=0)
    args = parser.parse_args()
    main(args.report, args.port_offset)
