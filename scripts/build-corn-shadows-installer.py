"""Prepare a B-only, additive shadow controller installer. Never serialize/save scenes."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '.artifacts/playtests/2026-10-21-corn-shadows'
BASELINE = ROOT / 'place/Children_of_corn_B.rbxl'
BASELINE_SHA = 'f33571e819fb605130b05489789c93f11c0ef92a3e9762c77691130a60c3d9c0'
A_SHA = 'c1f054029ca729f314889ce7874c17c6e5f772cb20541a9c0ceedd796f3446b7'
MODULE = 'StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornShadowController'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def archive_baseline():
    OUT.mkdir(parents=True, exist_ok=True)
    original = BASELINE.read_bytes()
    assert len(original) == 1494878 and sha(original) == BASELINE_SHA, 'Current accepted B bytes required'
    assert sha((ROOT / 'place/Children_of_corn.rbxl').read_bytes()) == A_SHA, 'A changed'
    archive_path = OUT / 'before-shadows.zip'
    if not archive_path.exists():
        with zipfile.ZipFile(archive_path, 'x', compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr('checkpoint/B-before-shadows.rbxl', original)
    with zipfile.ZipFile(archive_path) as archive:
        assert archive.namelist() == ['checkpoint/B-before-shadows.rbxl']
        assert archive.read('checkpoint/B-before-shadows.rbxl') == original, 'Immutable shadow archive differs'
    info = {'archive_sha256': sha(archive_path.read_bytes()), 'baseline_sha256': BASELINE_SHA,
            'baseline_bytes': len(original), 'untouched_A_sha256': A_SHA}
    baseline_path = OUT / 'baseline.json'
    if baseline_path.exists():
        assert json.loads(baseline_path.read_text()) == info, 'Immutable baseline metadata changed'
    else:
        baseline_path.write_text(json.dumps(info, indent=2) + '\n', encoding='utf-8', newline='\n')
    return info


def build():
    info = archive_baseline()
    read = subprocess.run([str(ROOT / '.tools/lune/lune.exe'), 'run',
                           str(ROOT / '.artifacts/harvest-install/read-baseline.luau'), str(BASELINE)],
                          capture_output=True, check=True, cwd=ROOT)
    original = json.loads(read.stdout)
    expected = {p: {'class': v['class'], 'sha256': v['sha256']} for p, v in original['sources'].items()}
    native = json.loads((OUT / 'native-before.json').read_text(encoding='utf-8'))
    assert len(expected) == 156 and native['sources'] == expected, 'Native Sources differ from accepted saved B'
    assert native['bank']['Wide']['shadows'] is False and native['bank']['Core']['shadows'] is False
    source = (ROOT / 'src/client/Controllers/CornShadowController.luau').read_text(encoding='utf-8')
    source_hash = sha(source.encode())
    payload = {'sources': expected, 'source': source, 'sourceHash': source_hash, 'path': MODULE}
    raw = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
    code = '''-- B only: retain all 156 Sources; add bounded foreground shadow controller and enable two lights.
local run = game:GetService("RunService")
assert(run:IsStudio() and not run:IsRunning(), "Stopped Edit required")
assert(game.Name == "Children_of_corn_B.rbxl", "Wrong scene; preserved")
local map = assert(workspace:FindFirstChild("CornMap"))
assert(map:IsA("Model") and map:GetAttribute("corn_project_id") == "children_of_corn"
    and map:GetAttribute("HarvestArtVariant") == "B", "Wrong Corn B identity")
assert(map.Ground.Size == Vector3.new(630,2,630) and map.FieldZone.Size == Vector3.new(630,10,630), "Wrong world bounds")
assert(game.Lighting.LightingStyle == Enum.LightingStyle.Realistic and game.Lighting.GlobalShadows, "Lighting baseline changed")
local payload = game:GetService("HttpService"):JSONDecode([====[@PAYLOAD@]====])
local encoding = game:GetService("EncodingService")
local function hash(source)
    local raw = encoding:ComputeStringHash((source:gsub("\\r\\n", "\\n")), Enum.HashAlgorithm.Sha256)
    return (raw:gsub(".", function(b) return string.format("%02x", string.byte(b)) end))
end
assert(hash(payload.source) == payload.sourceHash, "Transport hash differs")
local function child(parent, name)
    local result
    for _, item in parent:GetChildren() do
        if item.Name == name then assert(not result, "Duplicate child " .. name); result = item end
    end
    return result
end
local parent = assert(child(assert(child(assert(child(game.StarterPlayer,"StarterPlayerScripts")),"GameClient")),"Controllers"))
assert(parent:IsA("Folder"), "Controller parent differs")
local current = child(parent, "CornShadowController")
local count, seen = 0, {}
for _, item in game:GetDescendants() do
    if item:IsA("LuaSourceContainer") then
        local path = item:GetFullName():gsub("%.", "/")
        assert(not seen[path], "Duplicate Source path"); seen[path] = true
        if item == current then
            assert(path == payload.path and item.ClassName == "ModuleScript" and hash(item.Source) == payload.sourceHash, "Changed shadow Source preserved")
            assert(#item:GetChildren() == 0 and #item:GetTags() == 0 and next(item:GetAttributes()) == nil and item.Archivable, "Changed shadow metadata preserved")
        else
            local expected = payload.sources[path]
            assert(expected and expected.class == item.ClassName and hash(item.Source) == expected.sha256, "Unknown/edited Source preserved: " .. path)
            count += 1
        end
    end
end
assert(count == 156, "Expected all156 original Sources")
for path in payload.sources do assert(seen[path], "Missing Source " .. path) end
local editor = game:GetService("ScriptEditorService")
for _, document in editor:GetScriptDocuments() do
    local item = document:GetScript()
    assert(not current or item ~= current, "Close shadow controller script editor before installation")
end
local bank = assert(child(game.ReplicatedStorage,"CornFlashlightSettings"))
assert(bank.ClassName == "Folder" and #bank:GetChildren() == 2 and #bank:GetTags() == 0, "Changed settings bank")
local attrs = bank:GetAttributes(); local attrCount = 0; for _ in attrs do attrCount += 1 end
assert(attrCount == 3 and attrs.Pitch == -6 and attrs.CornFlashlightSettingsVersion == 1 and attrs.corn_project_id == "children_of_corn", "Bank metadata changed")
local wide, core = assert(child(bank,"Wide")), assert(child(bank,"Core"))
for _, light in {wide, core} do
    assert(light.ClassName == "SpotLight" and #light:GetChildren() == 0 and #light:GetTags() == 0 and next(light:GetAttributes()) == nil, "Unknown light metadata")
    assert(light.Enabled and light.Color == Color3.new(1,1,1) and light.Face == Enum.NormalId.Front, "Changed light settings preserved")
end
assert(math.abs(wide.Brightness - 2.08) < 0.000001 and wide.Angle == 78 and wide.Range == 18
    and math.abs(core.Brightness - 22.62) < 0.00001 and core.Angle == 12 and core.Range == 24, "Manual preset edits preserved")
if current then
    assert(wide.Shadows and core.Shadows, "Partial installed state preserved")
    return {created=0, changedProperties=0, totalSources=157, repeated=true, sourceHash=payload.sourceHash}
end
assert(not wide.Shadows and not core.Shadows, "Partial/unknown shadow state preserved")
local originalWide, originalCore = wide.Shadows, core.Shadows
local created
game:GetService("ChangeHistoryService"):SetWaypoint("Before Corn flashlight and nearby corn shadows")
local ok, problem = pcall(function()
    created = Instance.new("ModuleScript")
    created.Name = "CornShadowController"
    created.Source = payload.source
    assert(hash(created.Source) == payload.sourceHash, "Source readback differs")
    wide.Shadows = true
    core.Shadows = true
    created.Parent = parent
    assert(wide.Shadows and core.Shadows and child(parent,"CornShadowController") == created, "Shadow readback differs")
end)
if not ok then
    wide.Shadows = originalWide; core.Shadows = originalCore
    if created then created:Destroy() end
    error(problem)
end
game:GetService("ChangeHistoryService"):SetWaypoint("Corn flashlight and nearby corn shadows")
return {created=1, changedProperties=2, totalSources=157, sourceHash=payload.sourceHash,
    wideShadows=wide.Shadows, coreShadows=core.Shadows}
'''.replace('@PAYLOAD@', raw)
    target = ROOT / 'scripts/install-corn-shadows.luau'
    target.write_text(code, encoding='utf-8', newline='\n')
    manifest = info | {'new_module': MODULE, 'source_sha256': source_hash,
                       'installer_sha256': sha(code.encode()), 'installer_bytes': len(code.encode()),
                       'retained_sources': 156, 'total_sources': 157, 'source_changes': 0,
                       'new_modules': 1, 'changed_settings': ['Wide.Shadows', 'Core.Shadows'],
                       'variant': 'B', 'scene_written': False}
    (OUT / 'pipeline-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(json.dumps(manifest))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--archive-only', action='store_true')
    args = parser.parse_args()
    if args.archive_only:
        print(json.dumps(archive_baseline()))
    else:
        build()
