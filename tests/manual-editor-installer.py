"""Exercise the real builder/installer inside a project-local temporary folder."""
from pathlib import Path
import importlib.util
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("manual_editor_installer", ROOT / "scripts/install-local-corn-manual-editor.py")
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
checks = 0


def check(condition, message):
    global checks
    checks += 1
    assert condition, message


source = module.SOURCE.read_bytes()
payload, entry = module.build_payload(source)
xml = ET.fromstring(payload)
check(xml.tag == "roblox" and xml.attrib == {"version": "4"}, "Unexpected model format")
items = xml.findall("Item")
check(len(items) == 1 and items[0].attrib["class"] == "Script", "Plugin contains non-script instances")
check(items[0].find("Properties/ProtectedString").text == entry, "Embedded reviewed source differs")
check(items[0].find("Properties/bool").text == "false", "Plugin script disabled")
check(module.build_payload(source)[0] == payload, "Build is not deterministic")
try:
    module.build_payload(source + b"-- changed\n")
except RuntimeError:
    check(True, "Unreviewed source refused")
else:
    raise AssertionError("Unreviewed source accepted")

scratch = ROOT / ".artifacts" / "tests"
scratch.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="manual-editor-installer-", dir=scratch) as temporary:
    folder = Path(temporary)
    other = folder / "UnrelatedPlugin.rbxmx"
    other.write_bytes(b"other plugin exact bytes")
    result = module.install_payload(payload, folder)
    target = folder / f"{module.NAME}.rbxmx"
    check(result["created"] and target.read_bytes() == payload, "Fresh guarded install differs")
    check(other.read_bytes() == b"other plugin exact bytes", "Unrelated plugin changed")
    result = module.install_payload(payload, folder)
    check(not result["created"], "Identical plugin install did not remain unchanged")
    target.write_bytes(b"foreign version")
    try:
        module.install_payload(payload, folder)
    except RuntimeError:
        check(target.read_bytes() == b"foreign version", "Foreign version overwritten")
    else:
        raise AssertionError("Unknown plugin version accepted")
    check(other.read_bytes() == b"other plugin exact bytes", "Foreign refusal changed another plugin")
    try:
        module.install_payload(payload, folder / "missing")
    except RuntimeError:
        check(not (folder / "missing").exists(), "Missing plugins directory was created")
    else:
        raise AssertionError("Missing plugins directory accepted")

print(f"PASS manual editor installer: {checks} deterministic/hash/unknown-version/isolation checks; no local Studio install")
